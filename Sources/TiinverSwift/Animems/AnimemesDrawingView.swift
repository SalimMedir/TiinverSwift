import SwiftUI
import UIKit

/// Port du crayon (`ic_paint` → `mView.setAction("drawPath")`, `AnimemesCompound.java:2078-2095`,
/// confirmé réel par audit dédié du 2026-08-16) — dessin libre à même le canevas Animems, un
/// nouveau calque bitmap (fond transparent) créé à la validation. Réutilise le même motif
/// tracé-multi-traits que la Galerie (`PhotoToolsView.strokes`), adapté ici pour produire UNE
/// image aplatie plutôt qu'une superposition vivante — Animems traite le résultat comme UN calque
/// animable, pas comme une liste de traits éditables séparément.
struct AnimemesDrawingView: View {
    let canvasSize: CGSize
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    private struct Stroke {
        var points: [CGPoint] = []
        var color: Color = .white
    }

    @State private var strokes: [Stroke] = []
    @State private var currentColor: Color = .white
    @State private var measuredSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Canvas { context, size in
                        for stroke in strokes {
                            var path = Path()
                            guard let first = stroke.points.first else { continue }
                            path.move(to: first)
                            for point in stroke.points.dropFirst() { path.addLine(to: point) }
                            context.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .background(Color(white: 0.08))
                    .onAppear { measuredSize = geo.size }
                    .onChange(of: geo.size) { measuredSize = $0 }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if value.translation == .zero {
                                    strokes.append(Stroke(points: [value.location], color: currentColor))
                                } else {
                                    strokes[strokes.count - 1].points.append(value.location)
                                }
                            }
                    )
                }
                .aspectRatio(canvasSize.width / max(1, canvasSize.height), contentMode: .fit)

                HStack(spacing: 14) {
                    ForEach([Color.red, .yellow, .blue, .green, .white, .black], id: \.self) { color in
                        Circle().fill(color).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(.white, lineWidth: currentColor == color ? 2 : 0))
                            .onTapGesture { currentColor = color }
                    }
                    if !strokes.isEmpty {
                        Button { strokes.removeLast() } label: { Image(systemName: "arrow.uturn.backward") }
                    }
                }
                .font(.title3)
                .foregroundStyle(.white)
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Dessiner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") { onDone(flatten()) }.disabled(strokes.isEmpty)
                }
            }
        }
    }

    /// Rasterise tous les traits (coordonnées VUE, `measuredSize`) à l'échelle du canevas Animems
    /// réel (`canvasSize`) — même principe de ré-échelle que `FreeformCropView.croppedImage`.
    private func flatten() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { ctx in
            let scaleX = canvasSize.width / max(1, measuredSize.width)
            let scaleY = canvasSize.height / max(1, measuredSize.height)
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                let path = UIBezierPath()
                path.move(to: CGPoint(x: first.x * scaleX, y: first.y * scaleY))
                for point in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
                }
                path.lineWidth = 8
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor(stroke.color).setStroke()
                path.stroke()
            }
        }
    }
}
