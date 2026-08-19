import SwiftUI

/// Port de l'UI de `android/Paint/PaintPreviewEditorPanel.java` (mode `automateCapture == true`
/// d'`ic_paint`, confirmé réel côté Android — voir doc de `AnimemesEditorState.
/// addCapturedPaintFrames(_:delayMs:canvasSize:)`) au-dessus de `PaintCaptureController`/
/// `PaintDrawingCanvas` (déjà entièrement portés, jamais montés — voir ANIMEMS_PARITY_AUDIT_V1.md
/// F-26). **Ajouté le 2026-08-19 (Phase B, Lot 7)**. Structure calquée sur `AnimemesDrawingView`
/// (même style palette/toolbar) pour rester cohérent visuellement avec le mode dessin simple déjà
/// câblé.
struct PaintCaptureSheetView: View {
    let canvasSize: CGSize
    var onDone: ([CGImage], Int) -> Void
    var onCancel: () -> Void

    @StateObject private var controller = PaintCaptureController()
    @State private var speedProgress: Double = Double(PaintCaptureController.seekProgress(fromDelayMs: PaintCaptureController.defaultDelayMs))

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PaintDrawingCanvas(controller: controller)
                    .background(Color(white: 0.08))
                    .aspectRatio(canvasSize.width / max(1, canvasSize.height), contentMode: .fit)

                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        ForEach(PaintCaptureController.palette, id: \.self) { swatch in
                            Circle()
                                .fill(Self.color(argb: swatch))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.white, lineWidth: controller.strokeColor == swatch ? 2 : 0))
                                .onTapGesture { controller.strokeColor = swatch }
                        }
                        if !controller.frames.isEmpty {
                            Button { controller.clearAll() } label: { Image(systemName: "trash") }
                        }
                    }
                    HStack {
                        Text("Épaisseur").font(.caption).foregroundStyle(.white.opacity(0.7))
                        Slider(value: $controller.strokeWidth, in: 2...40)
                    }
                    HStack {
                        Text("Vitesse").font(.caption).foregroundStyle(.white.opacity(0.7))
                        Slider(value: Binding(
                            get: { speedProgress },
                            set: { speedProgress = $0; controller.delayMs = PaintCaptureController.delayMs(fromSeekProgress: Int($0)) }
                        ), in: 0...100)
                    }
                    Text("\(controller.frames.count) frame(s) capturée(s)")
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                .font(.title3)
                .foregroundStyle(.white)
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Dessin animé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") { onDone(controller.frames, controller.delayMs) }
                        .disabled(controller.frames.isEmpty)
                }
            }
        }
    }

    private static func color(argb: UInt32) -> Color {
        Color(
            red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}
