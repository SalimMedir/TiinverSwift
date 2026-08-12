import AVFoundation
import Combine
import MetalPetal
import UIKit

protocol CameraRecorderDelegate: AnyObject {
    /// Port de `CameraRecordListener.onGetFlashSupport`.
    func cameraRecorder(_ recorder: CameraRecorder, didUpdateFlashSupport supported: Bool)
    /// Port de `CameraRecordListener.onRecordStart`.
    func cameraRecorderDidStartRecording(_ recorder: CameraRecorder)
    /// Port de `CameraRecordListener.onVideoFileReady` (`filePath` = fichier `.mp4` complet).
    func cameraRecorder(_ recorder: CameraRecorder, didFinishRecordingAt url: URL)
    /// Port de `CameraRecordListener.onError`.
    func cameraRecorder(_ recorder: CameraRecorder, didFailWithError error: Error)
}

/// Port de `GPUCameraRecorder` — orchestre la capture (`CameraCaptureController`, ex-`Camera2`),
/// le filtre GPU en direct (MetalPetal, ex-`GlPreviewRenderer`/`GlFilter`) et l'enregistrement
/// (`CameraRecordingWriter`, ex-`MediaVideoEncoder`/`MediaAudioEncoder`/`MediaMuxerCaptureWrapper`).
///
/// **Différence d'architecture assumée, pas un oubli** : côté Android, l'aperçu (`GlPreviewRenderer`
/// sur la `GLSurfaceView`) et l'enregistrement (`EncodeRenderHandler` sur la surface d'entrée du
/// `MediaCodec`) sont DEUX pipelines GL séparés qui doivent rester synchronisés visuellement à la
/// main. Ici, chaque frame caméra est filtrée UNE SEULE FOIS par MetalPetal ; le résultat sert à
/// la fois à mettre à jour l'aperçu (`previewImage`, consommé par `CameraPreviewView`/
/// `MTIImageView`) ET, si un enregistrement est en cours, à alimenter `CameraRecordingWriter` —
/// un seul chemin de rendu, éliminant par construction le risque de divergence aperçu/export que
/// l'architecture Android doit gérer manuellement (même principe que la recommandation
/// `AVVideoCompositing` unifiée du futur moteur Animems, `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`
/// §2.1 — appliqué ici à la caméra, pas seulement à l'éditeur).
///
/// ⚠️ NON COMPILÉ — voir contrainte d'environnement en tête de `MIGRATION_PROGRESS.md`. Partie la
/// plus incertaine de ce fichier : le rendu MetalPetal → `CVPixelBuffer` du pool de l'asset
/// writer (`context.render(_:to:sRGB:)`, `pixelBufferAdaptor.pixelBufferPool`) — API réelle
/// vérifiée dans les en-têtes du SDK MetalPetal 1.10.0 (voir `Filters/` pour le détail de la
/// vérification), mais jamais exécutée.
final class CameraRecorder: NSObject, ObservableObject {
    weak var delegate: CameraRecorderDelegate?

    /// Image filtrée la plus récente — bindée par `CameraPreviewView` (`MTIImageView.image`).
    @Published private(set) var previewImage: MTIImage?
    @Published private(set) var isRecording = false
    @Published private(set) var lensFacing: LensFacing = .back
    /// Dernière vidéo écrite avec succès — piloté par `.onChange` côté SwiftUI (`CameraView`)
    /// plutôt que par `delegate` (`weak`, mal adapté à une `View` de type `struct`, voir
    /// commentaire de `CameraView.swift`). `delegate` reste disponible pour un usage non-SwiftUI.
    @Published private(set) var lastRecordedURL: URL?
    @Published private(set) var lastError: Error?

    /// Port de `GPUCameraRecorderBuilder.videoSize` (720×1280 par défaut, `BaseCameraFragment.
    /// videoWidth/videoHeight`).
    private let videoWidth = 720
    private let videoHeight = 1280

    private let captureController = CameraCaptureController()
    private let recordingWriter = CameraRecordingWriter()
    private let context: MTIContext?

    /// Exposé pour que `CameraPreviewView` (`MTIImageView`) réutilise le MÊME `MTIContext` (même
    /// file de commandes Metal) plutôt que d'en recréer un second — évite de dupliquer les
    /// ressources GPU pour un simple aperçu.
    var metalContext: MTIContext? { context }

    /// Port de `GlPreviewRenderer.setGlFilter`/`getFilter` — filtre courant appliqué à chaque
    /// frame, changé par le carrousel de `CameraView.swift`.
    private var currentFilter: (MTIImage) -> MTIImage = { $0 }

    override init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = try? MTIContext(device: device)
        } else {
            context = nil
        }
        super.init()
        captureController.delegate = self
        recordingWriter.delegate = self
    }

    func start(lensFacing: LensFacing) {
        self.lensFacing = lensFacing
        captureController.start(lensFacing: lensFacing)
    }

    /// Port de `GPUCameraRecorder.release()`.
    func release() {
        captureController.stop()
    }

    /// Port de `BaseCameraFragment.switchCamera()`.
    func switchCamera() {
        lensFacing = lensFacing.toggled
        captureController.switchCamera()
    }

    /// Port de `GPUCameraRecorder.setFilter`.
    func setFilter(_ filterType: CameraFilterType) {
        currentFilter = filterType.makeFilter()
    }

    /// Port de `GPUCameraRecorder.start(filePath)`.
    func startRecording(to url: URL) {
        guard !isRecording else { return }
        recordingWriter.start(to: url, videoWidth: videoWidth, videoHeight: videoHeight)
        isRecording = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraRecorderDidStartRecording(self)
        }
    }

    /// Port de `GPUCameraRecorder.stop()`.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingWriter.stop()
    }

    /// Port de `changeManualFocusPoint`/`changeAutoFocus`/`switchFlashMode` (délégués tels quels
    /// à `CameraCaptureController`).
    func changeManualFocusPoint(_ point: CGPoint) {
        captureController.changeManualFocusPoint(point)
    }

    func changeAutoFocus() {
        captureController.changeAutoFocus()
    }

    func switchFlashMode() {
        captureController.switchFlashMode()
    }

    var isFlashSupported: Bool { captureController.isFlashSupported }

    /// Port de `BaseCameraFragment.captureBitmap`/`createBitmapFromGLSurface` — snapshot de la
    /// dernière frame filtrée affichée à l'écran, pas une nouvelle capture Camera2 dédiée (Android
    /// fait de même : lecture directe du framebuffer GL affiché, `glReadPixels`).
    func capturePhoto() -> UIImage? {
        guard let context, let image = previewImage else { return nil }
        guard let cgImage = try? context.makeCGImage(from: image) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension CameraRecorder: CameraCaptureControllerDelegate {
    func cameraCaptureController(_ controller: CameraCaptureController, didOutputVideo sampleBuffer: CMSampleBuffer) {
        guard let context, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let inputImage = MTIImage(cvPixelBuffer: pixelBuffer, alphaType: .alphaIsOne)
        let filtered = currentFilter(inputImage)

        DispatchQueue.main.async { [weak self] in
            self?.previewImage = filtered
        }

        if isRecording {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if let pool = recordingWriter.pixelBufferPool,
               let outputBuffer = Self.makePixelBuffer(from: pool) {
                if (try? context.render(filtered, to: outputBuffer, sRGB: false)) != nil {
                    recordingWriter.appendVideo(pixelBuffer: outputBuffer, presentationTime: presentationTime)
                }
            }
        }
    }

    /// Port de `CameraRecordListener.onGetFlashSupport` — notifié UNE fois par
    /// `CameraCaptureController` à la (re)configuration de la session, pas à chaque frame
    /// (contrairement à un premier jet de ce fichier qui vérifiait `isFlashSupported` dans
    /// `didOutputVideo`, appelé ~30 fois/seconde pour une valeur qui ne change qu'au changement
    /// de caméra — corrigé avant tout build, relecture propre).
    func cameraCaptureController(_ controller: CameraCaptureController, didUpdateFlashSupport supported: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraRecorder(self, didUpdateFlashSupport: supported)
        }
    }

    func cameraCaptureController(_ controller: CameraCaptureController, didOutputAudio sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }
        recordingWriter.appendAudio(sampleBuffer: sampleBuffer)
    }

    func cameraCaptureController(_ controller: CameraCaptureController, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraRecorder(self, didFailWithError: error)
        }
    }

    private static func makePixelBuffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        return pixelBuffer
    }
}

extension CameraRecorder: CameraRecordingWriterDelegate {
    func cameraRecordingWriter(_ writer: CameraRecordingWriter, didFinishWithURL url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastRecordedURL = url
            self.delegate?.cameraRecorder(self, didFinishRecordingAt: url)
        }
    }

    func cameraRecordingWriter(_ writer: CameraRecordingWriter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastError = error
            self.delegate?.cameraRecorder(self, didFailWithError: error)
        }
    }
}
