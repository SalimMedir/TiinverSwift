import MetalPetal
import SwiftUI

/// Port de `SampleCameraGLView` (`GLSurfaceView` custom, affichée par `GlPreviewRenderer`) —
/// wrapper SwiftUI autour de `MTIImageView`, la vue prête à l'emploi du SDK MetalPetal (vérifiée
/// directement dans `Frameworks/MetalPetal/UI/MTIImageView.h` du SDK réel 1.10.0 avant d'écrire
/// ce fichier — `context`/`image`/`resizingMode` sont ses propriétés publiques réelles). Pas de
/// pipeline `MTKView` + cache de textures Metal écrit à la main, contrairement à l'architecture
/// GL bas niveau d'origine.
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var recorder: CameraRecorder
    /// Port de `SampleCameraGLView.setTouchListener` → `GPUCameraRecorder.
    /// changeManualFocusPoint(eventX, eventY, width, height)` — coordonnées déjà normalisées
    /// [0,1] ici (la conversion largeur/hauteur qu'Android faisait dans `CameraThread` n'a plus
    /// lieu d'être : `AVCaptureDevice.focusPointOfInterest` attend directement des coordonnées
    /// normalisées).
    var onTapToFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> MTIImageView {
        let view = MTIImageView()
        if let metalContext = recorder.metalContext {
            view.context = metalContext
        }
        view.resizingMode = .aspectFill
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.onTap = onTapToFocus
        return view
    }

    func updateUIView(_ uiView: MTIImageView, context: Context) {
        uiView.image = recorder.previewImage
        context.coordinator.onTap = onTapToFocus
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var onTap: ((CGPoint) -> Void)?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let location = gesture.location(in: view)
            let normalized = CGPoint(x: location.x / view.bounds.width, y: location.y / view.bounds.height)
            onTap?(normalized)
        }
    }
}
