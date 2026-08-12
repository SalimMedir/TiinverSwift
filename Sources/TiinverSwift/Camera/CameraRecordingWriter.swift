import AVFoundation
import CoreVideo

protocol CameraRecordingWriterDelegate: AnyObject {
    func cameraRecordingWriter(_ writer: CameraRecordingWriter, didFinishWithURL url: URL)
    func cameraRecordingWriter(_ writer: CameraRecordingWriter, didFailWithError error: Error)
}

/// Port de `MediaVideoEncoder` + `MediaAudioEncoder` + `MediaMuxerCaptureWrapper` — les 3 fichiers
/// lus intégralement (pas seulement leurs constantes, comme lors du premier passage du module 7 —
/// voir journal "point 5") avant d'écrire cette version. Android : `MediaCodec` H.264/AAC séparé,
/// encodés indépendamment puis multiplexés par `MediaMuxer` (`addTrack`/`start`/`stop` avec
/// compteurs `encoderCount`/`startedCount` pour synchroniser le démarrage — nécessaire car
/// `MediaFormat` de chaque piste n'est connu qu'après un callback asynchrone
/// `INFO_OUTPUT_FORMAT_CHANGED` du `MediaCodec`). Vers `AVAssetWriter`, qui fait le mux+encode en
/// un seul objet ET reçoit `outputSettings` de façon SYNCHRONE dès la construction de chaque
/// `AVAssetWriterInput` — la synchronisation à deux compteurs de `MediaMuxerCaptureWrapper`
/// n'a donc pas d'équivalent nécessaire ici (elle résout un problème d'API bas niveau Android qui
/// ne se pose pas avec `AVAssetWriter`), pas un détail oublié. Décision d'architecture déjà actée
/// dans `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.1 (ligne `AVAssetWriter`/`MediaMuxer` — "plus
/// simple côté iOS").
///
/// Constantes d'encodage reprises à l'identique : vidéo H.264 30fps,
/// bitRate = BPP(0.25) × frameRate × largeur × hauteur, **keyframe toutes les 3 secondes**
/// (`AVVideoMaxKeyFrameIntervalDurationKey`, port de `KEY_I_FRAME_INTERVAL=3` — MANQUAIT dans le
/// premier jet de ce fichier, ajouté après relecture complète) ; audio AAC-LC 44100Hz mono
/// 64kbps. Garde de monotonicité des horodatages audio ajoutée (`lastAudioPresentationTime`,
/// port de `preventAudioPresentationTimeUs`) — voir sa documentation plus bas pour le détail de
/// la comparaison de plateforme.
final class CameraRecordingWriter {
    weak var delegate: CameraRecordingWriterDelegate?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var sessionStarted = false
    private let queue = DispatchQueue(label: "com.tiinver.camera.recording")

    /// Port de `MediaMuxerCaptureWrapper.preventAudioPresentationTimeUs` (`writeSampleData` :
    /// n'écrit un échantillon audio QUE si son horodatage est strictement supérieur au précédent).
    /// Trouvé en relisant `MediaMuxerCaptureWrapper.java` en entier (point 5, module 7) — protège
    /// côté Android contre des horodatages non strictement croissants renvoyés par le calcul
    /// manuel de PTS d'`AudioRecord` (`MediaAudioEncoder.getPTSUs()`, thread de capture séparé).
    /// Ajouté ici par prudence bien que le mécanisme source du problème n'existe pas tel quel côté
    /// iOS (`AVCaptureAudioDataOutput` livre des `CMSampleBuffer` horodatés par l'horloge matérielle,
    /// normalement déjà strictement croissants) — coûte rien si jamais déclenché, protège si un
    /// device/scénario produit malgré tout un doublon.
    private var lastAudioPresentationTime: CMTime?

    private(set) var isRecording = false

    private static let frameRate: Int32 = 30
    private static let bitsPerPixel: Double = 0.25

    /// Pool de `CVPixelBuffer` assorti aux attributs attendus par l'`AVAssetWriterInput` vidéo —
    /// utilisé par `CameraRecorder` pour rendre l'image déjà filtrée (MetalPetal) avant de
    /// l'ajouter ici, un seul chemin de rendu aperçu+export (voir `CameraRecorder.swift`).
    var pixelBufferPool: CVPixelBufferPool? {
        pixelBufferAdaptor?.pixelBufferPool
    }

    func start(to url: URL, videoWidth: Int, videoHeight: Int) {
        queue.async { [weak self] in
            self?.startWriting(to: url, videoWidth: videoWidth, videoHeight: videoHeight)
        }
    }

    private func startWriting(to url: URL, videoWidth: Int, videoHeight: Int) {
        do {
            try? FileManager.default.removeItem(at: url)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

            let bitRate = Int(Self.bitsPerPixel * Double(Self.frameRate) * Double(videoWidth) * Double(videoHeight))
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitRate,
                    AVVideoExpectedSourceFrameRateKey: Self.frameRate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    // Port de `MediaFormat.KEY_I_FRAME_INTERVAL = 3` (`MediaVideoEncoder.prepare`)
                    // — trouvé en relisant le fichier Android en entier (point 5, module 7),
                    // absent du premier jet de ce fichier qui n'avait extrait que bitrate/fps/
                    // profil. Un keyframe toutes les 3 secondes, pas une estimation.
                    AVVideoMaxKeyFrameIntervalDurationKey: 3.0,
                ],
            ]
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: vInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: videoWidth,
                    kCVPixelBufferHeightKey as String: videoHeight,
                ]
            )
            if writer.canAdd(vInput) { writer.add(vInput) }

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000,
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) { writer.add(aInput) }

            assetWriter = writer
            videoInput = vInput
            audioInput = aInput
            pixelBufferAdaptor = adaptor
            outputURL = url
            sessionStarted = false
            lastAudioPresentationTime = nil
            isRecording = true
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.cameraRecordingWriter(self, didFailWithError: error)
            }
        }
    }

    /// `pixelBuffer` = image DÉJÀ filtrée (MetalPetal) — équivalent de `EncodeRenderHandler.draw`
    /// côté Android, qui appliquait le filtre GL directement sur la surface d'entrée de
    /// `MediaVideoEncoder`.
    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        queue.async { [weak self] in
            guard let self, let writer = self.assetWriter, let vInput = self.videoInput, let adaptor = self.pixelBufferAdaptor else { return }
            if !self.sessionStarted {
                writer.startWriting()
                writer.startSession(atSourceTime: presentationTime)
                self.sessionStarted = true
            }
            guard vInput.isReadyForMoreMediaData else { return }
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }
    }

    func appendAudio(sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self, self.sessionStarted, let aInput = self.audioInput, aInput.isReadyForMoreMediaData else { return }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if let last = self.lastAudioPresentationTime, CMTimeCompare(presentationTime, last) <= 0 {
                return
            }
            self.lastAudioPresentationTime = presentationTime
            aInput.append(sampleBuffer)
        }
    }

    /// Port de `GPUCameraRecorder.stop()` → `MediaMuxerCaptureWrapper.stopRecording()` →
    /// `CameraRecordListener.onVideoFileReady()`.
    func stop() {
        queue.async { [weak self] in
            guard let self, let writer = self.assetWriter, let url = self.outputURL else { return }
            self.isRecording = false
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    if writer.status == .completed {
                        self.delegate?.cameraRecordingWriter(self, didFinishWithURL: url)
                    } else if let error = writer.error {
                        self.delegate?.cameraRecordingWriter(self, didFailWithError: error)
                    }
                }
            }
        }
    }
}
