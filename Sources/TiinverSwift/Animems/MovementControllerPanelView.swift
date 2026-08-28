import SwiftUI

/// Port de `movement_controller_handler.xml`/`MovementControllerHandlerView` — panneau de
/// bascules (zoom/rotation/inclinaison/haut/bas/gauche/droite/point d'ancrage) + un slider
/// d'angle, remplaçant la zone timeline pendant qu'il est ouvert (`AnimemesCompound.java:1857-
/// 1874` : `movement_controller_view.setVisibility(VISIBLE)`, `frameList`/`timelineView`
/// masqués) — même agencement que `BezierEditorView` (autre remplacement de zone timeline,
/// `AnimemesEditorView.body`). **Ajouté (2026-08-28, V6-F-002)**.
struct MovementControllerPanelView: View {
    @ObservedObject var state: AnimemesEditorState
    /// Port de `oldProgress`/du décalage `finalProgress = progress + 90` — le slider Android part
    /// de 0 (repère "neutre" = 90 après décalage) ; conservé identique ici pour que les formules
    /// de `MovementControllerTransformer` (delta entre progrès successifs) restent un port fidèle
    /// sans reformulation.
    /// **Corrigé (2026-08-28, V7-F-003)** — plage `90...190`, fidèle à `MovementControllerHandlerView.
    /// java:85-92` (`SeekBar android:max="100"` + décalage `finalProgress = progress + 90`) : la
    /// plage réelle du SeekBar Android ne descend jamais sous 90. La précédente plage `0...180`
    /// (symétrique par simplicité) permettait un delta négatif de -90 impossible côté Android, et
    /// plafonnait 10 unités plus tôt (180 au lieu de 190) à la hausse.
    @State private var sliderValue: Double = 90

    private let toggles: [(field: WritableKeyPath<MovementControllerState, Bool>, icon: String, label: String)] = [
        (\.zoom, "arrow.up.left.and.arrow.down.right", "Zoom"),
        (\.rotation, "rotate.right", "Rotation"),
        (\.skew, "parallelogram", "Inclinaison"),
        (\.top, "arrow.up", "Haut"),
        (\.bottom, "arrow.down", "Bas"),
        (\.left, "arrow.left", "Gauche"),
        (\.right, "arrow.right", "Droite"),
        (\.anchorPoint, "scope", "Point d'ancrage"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(toggles, id: \.label) { toggle in
                        let isOn = state.movementController[keyPath: toggle.field]
                        Button {
                            state.movementController[keyPath: toggle.field].toggle()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: toggle.icon)
                                Text(toggle.label).font(.caption2)
                            }
                            .padding(8)
                            .foregroundStyle(isOn ? .black : .white)
                            .background(isOn ? Color.white : Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal)
            }
            // Port du slider d'angle — voir `MovementControllerHandlerView.java:83-107`
            // (`onProgressChanged`/`onStartTrackingTouch`/`onStopTrackingTouch`).
            Slider(
                value: $sliderValue, in: 90...190,
                onEditingChanged: { editing in
                    if editing {
                        state.movementControllerBeginTracking(atProgress: Int(sliderValue))
                    } else {
                        // V7-F-001 : miroir de `onStopTrackingTouch`/`touchUp(0)` — capture une
                        // keyframe si la capture automatique est active, comme un glisser direct.
                        state.movementControllerEndTracking()
                    }
                }
            )
            .padding(.horizontal)
            .onChange(of: sliderValue) { newValue in
                state.movementControllerProgressChanged(Int(newValue))
            }
        }
        .padding(.vertical, 10)
        .frame(height: 110)
        .background(Color.black)
        .onDisappear { state.closeMovementController() }
    }
}
