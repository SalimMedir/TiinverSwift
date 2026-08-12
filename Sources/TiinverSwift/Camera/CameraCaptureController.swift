import AVFoundation
import CoreVideo

protocol CameraCaptureControllerDelegate: AnyObject {
    func cameraCaptureController(_ controller: CameraCaptureController, didOutputVideo sampleBuffer: CMSampleBuffer)
    func cameraCaptureController(_ controller: CameraCaptureController, didOutputAudio sampleBuffer: CMSampleBuffer)
    func cameraCaptureController(_ controller: CameraCaptureController, didFailWithError error: Error)
    /// Port de `CameraRecordListener.onGetFlashSupport` — appelé UNE fois par (re)configuration
    /// de session, pas par frame.
    func cameraCaptureController(_ controller: CameraCaptureController, didUpdateFlashSupport supported: Bool)
}

enum CameraCaptureError: Error {
    case deviceUnavailable
    /// Port de `BaseCameraFragment.onRequestPermissionsResult` (`REQUEST_CAMERA_PERMISSION`) —
    /// contrairement à Android, iOS ne bloque pas explicitement AVANT `startRunning()` sur un
    /// refus (la session démarrerait simplement sans flux), donc l'autorisation est vérifiée
    /// explicitement ici plutôt que laissée à un échec silencieux.
    case permissionDenied
}

/// Port de `GPUCameraRecorder` + `CameraHandler` + `CameraThread` (orchestration `Camera2` sur un
/// thread `HandlerThread` dédié) vers `AVCaptureSession` — modèle de session natif iOS, mature,
/// pas besoin de gérer un thread de capture à la main (`AVCaptureSession` le fait déjà en
/// interne), voir `TIINVER_IOS_PORT_ANALYSIS.md` §3.3 ("Faible-Moyen : modèle de session
/// différent mais mature"). `CameraThread.OnStartPreviewListener`/`CameraRecordListener` sont
/// fusionnés dans le seul protocole `CameraCaptureControllerDelegate` ci-dessus — Android sépare
/// les deux car `CameraThread` tourne sur un thread séparé du reste du cycle de vie, distinction
/// sans objet ici (`AVCaptureSession` notifie déjà sur sa propre queue).
///
/// ⚠️ NON COMPILÉ (voir contrainte d'environnement en tête de `MIGRATION_PROGRESS.md`) — API
/// `AVCaptureSession`/`AVCaptureVideoDataOutput` standard et bien établie, risque de build plus
/// faible que la partie MetalPetal (voir `Filters/`), mais jamais exécutée sur un simulateur/
/// device réel à ce stade.
final class CameraCaptureController: NSObject {
    weak var delegate: CameraCaptureControllerDelegate?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tiinver.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private(set) var lensFacing: LensFacing = .back
    /// Port de `GPUCameraRecorder.flashSupport` (`CameraRecordListener.onGetFlashSupport`).
    private(set) var isFlashSupported = false
    private var isFlashOn = false

    /// Port de `GPUCameraRecorderBuilder.cameraWidth/cameraHeight` (1280x720 par défaut).
    private let preset: AVCaptureSession.Preset = .hd1280x720

    func start(lensFacing: LensFacing) {
        self.lensFacing = lensFacing
        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.delegate?.cameraCaptureController(self, didFailWithError: CameraCaptureError.permissionDenied)
                return
            }
            self.sessionQueue.async {
                self.configureSession()
                self.session.startRunning()
            }
        }
    }

    /// Port de `BaseCameraFragment.onResume` (`ContextCompat.checkSelfPermission(CAMERA)`) +
    /// `requestPermissions`. La permission micro est demandée en même temps (Android la demande
    /// implicitement au premier accès à `AudioRecord`/`MediaRecorder` dans `MediaAudioEncoder`,
    /// pas de permission micro dédiée séparée observée dans le code lu).
    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        func requestAudio(videoGranted: Bool) {
            guard videoGranted else {
                completion(false)
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                completion(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            default:
                completion(false)
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            requestAudio(videoGranted: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { requestAudio(videoGranted: granted) }
            }
        default:
            completion(false)
        }
    }

    /// Port de `GPUCameraRecorder.release()` (`destroyPreview` + arrêt du thread caméra).
    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    /// Port de `BaseCameraFragment.switchCamera()` (`releaseCamera()` puis
    /// `CameraRecordListener.onCameraThreadFinish` relance `setUpCamera()` avec le nouveau
    /// `lensFacing` — ici, reconfiguration directe de la session sans la recréer entièrement,
    /// équivalent observable).
    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.lensFacing = self.lensFacing.toggled
            self.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = preset

        if let videoInput { session.removeInput(videoInput) }
        if let audioInput { session.removeInput(audioInput) }
        for output in session.outputs { session.removeOutput(output) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: lensFacing.avPosition),
              let input = try? AVCaptureDeviceInput(device: device) else {
            delegate?.cameraCaptureController(self, didFailWithError: CameraCaptureError.deviceUnavailable)
            return
        }
        isFlashSupported = device.hasFlash
        delegate?.cameraCaptureController(self, didUpdateFlashSupport: isFlashSupported)

        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        }

        if let micDevice = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: micDevice),
           session.canAddInput(micInput) {
            session.addInput(micInput)
            audioInput = micInput
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        // `fragment_camera_portrate` (nom du layout Android) : plein écran portrait uniquement,
        // pas de rotation à gérer dynamiquement comme le fait `GPUCameraRecorderBuilder.degrees`
        // pour le cas paysage (jamais atteint dans cet écran).
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (lensFacing == .front)
            }
        }
    }

    /// Port de `CameraThread.changeManualFocusPoint` (`CameraRecorder.changeManualFocusPoint`,
    /// appelé depuis `SampleCameraGLView` au tap — coordonnées déjà normalisées côté appelant
    /// dans `CameraPreviewView.swift`, pas de conversion largeur/hauteur ici contrairement à
    /// l'original Android qui la faisait dans ce même point d'entrée).
    func changeManualFocusPoint(_ point: CGPoint) {
        guard let device = videoInput?.device, device.isFocusPointOfInterestSupported else { return }
        try? device.lockForConfiguration()
        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
        }
        device.unlockForConfiguration()
    }

    /// Port de `CameraThread.changeAutoFocus` (appelé par `BaseCameraFragment.flash()`).
    func changeAutoFocus() {
        guard let device = videoInput?.device, device.isFocusModeSupported(.continuousAutoFocus) else { return }
        try? device.lockForConfiguration()
        device.focusMode = .continuousAutoFocus
        device.unlockForConfiguration()
    }

    /// Port de `CameraThread.switchFlashMode`. ⚠️ Point signalé pour information : côté Android,
    /// `BaseCameraFragment.flash()` (qui appelle `switchFlashMode()`+`changeAutoFocus()`) n'est
    /// câblé à AUCUN élément visible du layout dans le fichier lu (`R.id.btn_flash` commenté) —
    /// fonctionnalité présente dans le code mais probablement inatteignable depuis l'UI Android
    /// réelle. Câblé ici à un vrai bouton dans `CameraView.swift` (meilleure UX iOS), PAS une
    /// simple reproduction du bug Android faute d'écran de référence exact.
    func switchFlashMode() {
        guard isFlashSupported, let device = videoInput?.device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        isFlashOn.toggle()
        device.torchMode = isFlashOn ? .on : .off
        device.unlockForConfiguration()
    }
}

extension CameraCaptureController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            delegate?.cameraCaptureController(self, didOutputVideo: sampleBuffer)
        } else {
            delegate?.cameraCaptureController(self, didOutputAudio: sampleBuffer)
        }
    }
}
