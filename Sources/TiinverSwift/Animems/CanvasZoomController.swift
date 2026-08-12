import CoreGraphics
import SwiftUI

/// Port de `android/views/CanvasZoomController.java` — zoom du canvas d'édition (boutons +/−/fit),
/// distinct du zoom de la timeline (`TimelineViewModel.applyPinchZoom`). Fichier auto-contenu (un
/// seul état `currentScale` + un calcul de zoom minimum dépendant des tailles vue/parent), porté en
/// entier (modèle + rendu SwiftUI) comme `BezierEditorView`/`PaintPreviewEditorPanel`.
@MainActor
final class CanvasZoomState: ObservableObject {
    static let step: CGFloat = 0.25
    static let maxZoom: CGFloat = 4.0

    @Published private(set) var currentScale: CGFloat = 1.0
    /// Port de `ZOOM_MIN` — dynamique, recalculé après mesure (`computeMinZoom`).
    private(set) var minZoom: CGFloat = 1.0

    /// Port de `computeMinZoom` — zoom minimum qui garantit que la vue cible tient entièrement
    /// dans son parent (jamais sous `1.0`, la taille naturelle étant déjà acceptable).
    func updateMinZoom(targetSize: CGSize, parentSize: CGSize) {
        guard targetSize.width > 0, targetSize.height > 0,
            parentSize.width > 0, parentSize.height > 0
        else {
            minZoom = 1.0
            return
        }
        let minByW = parentSize.width / targetSize.width
        let minByH = parentSize.height / targetSize.height
        minZoom = max(1.0, min(minByW, minByH))
        if currentScale < minZoom { currentScale = minZoom }
    }

    /// Port de `zoom(delta)`.
    func zoom(by delta: CGFloat) {
        currentScale = max(minZoom, min(Self.maxZoom, currentScale + delta))
    }

    /// Port de `reset` (bouton "fit").
    func reset() {
        currentScale = 1.0
    }
}

/// Port de la construction UI de `CanvasZoomController` (`init`/`makeBtn`/`makeLabel`/`makeFitBtn`).
struct CanvasZoomControls: View {
    @ObservedObject var state: CanvasZoomState

    var body: some View {
        VStack(spacing: 2) {
            zoomButton("+") { state.zoom(by: CanvasZoomState.step) }
            Text(String(format: "%.1f×", state.currentScale))
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 38)
            zoomButton("−") { state.zoom(by: -CanvasZoomState.step) }
            Text("fit")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.67))
                .frame(width: 34, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.13)))
                .padding(.top, 4)
                .onTapGesture { state.reset() }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.27), lineWidth: 1))
    }

    private func zoomButton(_ label: String, action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 20))
            .foregroundColor(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.white.opacity(0.2)))
            .onTapGesture(perform: action)
    }
}
