import AVFoundation

/// Port de `com.animems.engine.android.gpuv.camerarecorder.LensFacing` (enum à 2 valeurs,
/// `CameraCharacteristics.LENS_FACING_FRONT`/`LENS_FACING_BACK`).
enum LensFacing {
    case front
    case back

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back: return .back
        }
    }

    var toggled: LensFacing {
        self == .back ? .front : .back
    }
}
