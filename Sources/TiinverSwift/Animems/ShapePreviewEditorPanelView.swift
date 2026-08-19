import SwiftUI

/// Port de la VUE de `android/views/ShapePreviewEditorPanel.java` au-dessus de l'état pur déjà
/// porté (`ShapePreviewEditorPanelState.swift`, écrit en avance, jamais monté — voir
/// ANIMEMS_PARITY_AUDIT_V1.md F-21). **Ajouté le 2026-08-19 (Phase B, Lot 5)** — avant ce
/// correctif, `AnimemesEditorState.addShape` insérait directement une forme à couleur/taille
/// codées en dur, sans passer par ce panneau de configuration pourtant réel côté Android
/// (couleur/opacité/arrondi/épaisseur/contour, choisis AVANT insertion).
struct ShapePreviewEditorPanelView: View {
    let data: AnimationObjectData
    let canvasSize: CGSize
    let onConfirm: (AnimationObjectData) -> Void
    let onCancel: () -> Void

    @State private var previewImage: CGImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Group {
                            if let previewImage {
                                Image(decorative: previewImage, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 120)
                            } else {
                                Color.clear.frame(height: 120)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color(white: 0.15))
                }
                Section("Couleur") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ShapePreviewEditorPanelState.palette, id: \.self) { swatch in
                                Button {
                                    data.shapeColor = swatch
                                    refresh()
                                } label: {
                                    Circle()
                                        .fill(Self.color(argb: swatch))
                                        .overlay(Circle().stroke(data.shapeColor == swatch ? Color.accentColor : Color.gray, lineWidth: data.shapeColor == swatch ? 3 : 1))
                                        .frame(width: 28, height: 28)
                                }
                            }
                        }
                    }
                }
                Section("Opacité") {
                    Slider(value: Binding(
                        get: { Double(data.shapeOpacity) },
                        set: { data.shapeOpacity = Float($0); refresh() }
                    ), in: 0...1)
                }
                let rows = ShapePreviewEditorPanelState.rowVisibility(for: data.objectType)
                if rows.cornerRadius {
                    Section("Arrondi") {
                        Slider(value: Binding(
                            get: { Double(data.shapeCornerRadius) },
                            set: { data.shapeCornerRadius = Float($0); refresh() }
                        ), in: 0...60)
                    }
                }
                if rows.lineThickness {
                    Section("Épaisseur") {
                        Slider(value: Binding(
                            get: { Double(data.shapeLineThickness) },
                            set: { data.shapeLineThickness = Float($0); refresh() }
                        ), in: 2...40)
                    }
                }
                if rows.stroke {
                    Section("Contour") {
                        Slider(value: Binding(
                            get: { Double(data.shapeStrokeWidth) },
                            set: { data.shapeStrokeWidth = Float($0); refresh() }
                        ), in: 0...20)
                    }
                }
            }
            .navigationTitle(ShapePreviewEditorPanelState.label(for: data.objectType))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { onConfirm(data) } }
            }
            .onAppear { refresh() }
        }
        .presentationDetents([.medium, .large])
    }

    private func refresh() {
        previewImage = ShapeFactory.rerender(data, canvasW: Int(canvasSize.width), canvasH: Int(canvasSize.height))
    }

    private static func color(argb: UInt32) -> Color {
        Color(
            red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}
