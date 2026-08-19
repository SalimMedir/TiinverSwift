import SwiftUI

/// Port de la VUE de `android/views/LayerEditorPanel.java` (504 lignes) au-dessus de l'état pur
/// déjà porté (`LayerEditorPanelState.swift`, écrit en avance, jamais monté — voir
/// ANIMEMS_PARITY_AUDIT_V1.md F-28) — panneau opacité/teinte/arrondi/flou avec aperçu en direct
/// et validation créant des keyframes visuels à la frame courante du playhead. **Ajouté le
/// 2026-08-19 (Phase B, Lot 3)** : voir `AnimemesEditorState.snapshotLayerEditor()`/
/// `applyLayerEditorPreview(_:)`/`validateLayerEditor(_:)`/`cancelLayerEditor(_:)` pour le
/// raisonnement complet sur le déclencheur (bouton dédié plutôt qu'appui long sur la timeline,
/// substitution de geste assumée et documentée là-bas) et le modèle aperçu/validation/annulation.
struct LayerEditorPanelView: View {
    let objectType: AnimationObjectData.ObjectType?
    let original: LayerEditorPanelState
    let onPreview: (LayerEditorPanelState) -> Void
    let onValidate: (LayerEditorPanelState) -> Void
    let onCancel: (LayerEditorPanelState) -> Void
    var onDismiss: () -> Void

    @State private var panel: LayerEditorPanelState

    init(
        objectType: AnimationObjectData.ObjectType?, original: LayerEditorPanelState,
        onPreview: @escaping (LayerEditorPanelState) -> Void,
        onValidate: @escaping (LayerEditorPanelState) -> Void,
        onCancel: @escaping (LayerEditorPanelState) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.objectType = objectType
        self.original = original
        self.onPreview = onPreview
        self.onValidate = onValidate
        self.onCancel = onCancel
        self.onDismiss = onDismiss
        _panel = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Opacité") {
                    Slider(value: Binding(
                        get: { Double(panel.opacity) },
                        set: { panel.opacity = Float($0); onPreview(panel) }
                    ), in: 0...1)
                }
                if LayerEditorPanelState.showsCornerRadius(for: objectType) {
                    Section("Arrondi") {
                        Slider(value: Binding(
                            get: { Double(panel.cornerRadius) },
                            set: { panel.cornerRadius = Float($0); onPreview(panel) }
                        ), in: 0...60)
                    }
                }
                Section("Flou de bord") {
                    Slider(value: Binding(
                        get: { Double(panel.feather) },
                        set: { panel.feather = Float($0); onPreview(panel) }
                    ), in: 0...1)
                }
                Section("Teinte") {
                    // Port de `PALETTE` (`LayerEditorPanelState.palette`) — `0` = "pas de teinte",
                    // première entrée, fidèle à l'ordre Android.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(LayerEditorPanelState.palette, id: \.self) { swatch in
                                Button {
                                    panel.tintColor = swatch
                                    onPreview(panel)
                                } label: {
                                    Circle()
                                        .fill(swatch == 0 ? Color.clear : Self.color(argb: swatch))
                                        .overlay(
                                            Circle().stroke(panel.tintColor == swatch ? Color.accentColor : Color.gray, lineWidth: panel.tintColor == swatch ? 3 : 1)
                                        )
                                        .overlay(swatch == 0 ? Image(systemName: "slash.circle") : nil)
                                        .frame(width: 28, height: 28)
                                }
                            }
                        }
                    }
                    if panel.tintColor != 0 {
                        Slider(value: Binding(
                            get: { Double(panel.tintStrength) },
                            set: { panel.tintStrength = Float($0); onPreview(panel) }
                        ), in: 0...1)
                    }
                }
            }
            .navigationTitle("Propriétés du calque")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        onCancel(original)
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        onValidate(panel)
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Même conversion ARGB→`Color` que `TimelineView.color(fromPacked:)` — dupliquée
    /// volontairement (2 seuls sites d'appel dans des fichiers différents, ne justifie pas de
    /// sortir cette conversion de son contexte).
    private static func color(argb: UInt32) -> Color {
        Color(
            red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}
