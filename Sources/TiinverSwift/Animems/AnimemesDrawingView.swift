import SwiftUI
import UIKit

/// Port du crayon (`ic_paint` → `mView.setAction("drawPath")`, `AnimemesCompound.java:2078-2095`,
/// confirmé réel par audit dédié du 2026-08-16) — dessin libre à même le canevas Animems, un
/// nouveau calque bitmap (fond transparent) créé à la validation. Réutilise le même motif
/// tracé-multi-traits que la Galerie (`PhotoToolsView.strokes`), adapté ici pour produire UNE
/// image aplatie plutôt qu'une superposition vivante — Animems traite le résultat comme UN calque
/// animable, pas comme une liste de traits éditables séparément.
///
/// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-090, Phase B P2)** — 3 écarts
/// comblés par rapport au moteur de dessin Animems d'origine (`MemesView2.java`, la classe
/// réellement active) : (1) épaisseur de trait fixée en dur à 8pt sans contrôle → `Slider`
/// 1...100 fidèle au `SeekBar` (`PaintSizeListAdapter.java:35-45`, `paintSize` par défaut=10,
/// `ImageViewCanvas.java:122`) ; (2) palette réduite à 6 couleurs arbitraires → 21 couleurs
/// réelles de `PaintList.getPaintList()` (`PaintList.java:18-75`, hex lus directement dans
/// `colors.xml`) ; (3) tracé en segments droits bruts → lissage de Chaikin 1 itération
/// (`AnimationEngine.chaikin`, `:371-388`) + filtre `MIN_DIST=4` sur les points bruts avant
/// lissage (`MemesView2.java:119-120,1973`), reproduits ci-dessous.
struct AnimemesDrawingView: View {
    let canvasSize: CGSize
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    private struct Stroke {
        var points: [CGPoint] = []
        var color: Color = .white
        var lineWidth: CGFloat = 10
    }

    @State private var strokes: [Stroke] = []
    @State private var currentColor: Color = .white
    /// Port de `paintSize` (`ImageViewCanvas.java:122`/`MemesView2.java:176`, défaut réel = 10, PAS
    /// le `progress=5` du `SeekBar` fraîchement créé dans `PaintSizeListAdapter` — 2 valeurs par
    /// défaut différentes côté Android lui-même, `paintSize` est celle qui compte réellement tant
    /// qu'aucun geste n'a modifié le slider).
    @State private var currentLineWidth: CGFloat = 10
    @State private var measuredSize: CGSize = .zero

    /// Port de `PaintList.getPaintList()` (`PaintList.java:18-75`) — 21 couleurs réelles (indices
    /// 0-20 du `for i<21` d'origine : transparent, appColor2, color1...color19 ; `color20` déclaré
    /// dans le `switch` mais jamais atteint par cette boucle précise, non repris). Hex lus
    /// directement dans `engine/src/main/res/values/colors.xml`.
    private static let palette: [Color] = [
        .clear, // R.color.transparent (#00FFFFFF)
        Color(red: 0x19 / 255, green: 0x76 / 255, blue: 0xD2 / 255), // appColor2
        Color(red: 0xa4 / 255, green: 0x01 / 255, blue: 0x00 / 255), // color1
        Color(red: 0x00 / 255, green: 0x62 / 255, blue: 0xa4 / 255), // color2
        Color(red: 0xa4 / 255, green: 0x57 / 255, blue: 0x00 / 255), // color3
        Color(red: 0xad / 255, green: 0x09 / 255, blue: 0xb9 / 255), // color4
        Color(red: 0xe4 / 255, green: 0x03 / 255, blue: 0x5d / 255), // color5
        Color(red: 0x33 / 255, green: 0x80 / 255, blue: 0x03 / 255), // color6
        Color(red: 0x64 / 255, green: 0x0f / 255, blue: 0x0e / 255), // color7
        Color(red: 0x0d / 255, green: 0x66 / 255, blue: 0x5a / 255), // color8
        .black, // color9
        Color(red: 0xa7 / 255, green: 0x21 / 255, blue: 0x98 / 255), // color10
        Color(red: 0x35 / 255, green: 0x6c / 255, blue: 0x19 / 255), // color11
        Color(red: 0x8e / 255, green: 0x45 / 255, blue: 0x10 / 255), // color12
        Color(red: 0x54 / 255, green: 0x05 / 255, blue: 0x05 / 255), // color13
        Color(red: 0xd6 / 255, green: 0xbd / 255, blue: 0x01 / 255), // color14
        Color(red: 0x84 / 255, green: 0x7e / 255, blue: 0x01 / 255), // color15
        Color(red: 0x06 / 255, green: 0x6E / 255, blue: 0x64 / 255), // color16
        Color(red: 0xAC / 255, green: 0x76 / 255, blue: 0x0B / 255), // color17
        Color(red: 0x4E / 255, green: 0x64 / 255, blue: 0x67 / 255), // color18
        Color(red: 0x84 / 255, green: 0x03 / 255, blue: 0x9A / 255), // color19
    ]

    /// Port de `MIN_DIST` (`MemesView2.java:119`) — un nouveau point brut n'est retenu que s'il est
    /// à au moins cette distance du précédent, comme `addFilteredPoint`/`rawPathPoints.add`.
    private static let minPointDistance: CGFloat = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Canvas { context, _ in
                        for stroke in strokes { Self.drawSmoothed(stroke, in: context) }
                    }
                    .background(Color(white: 0.08))
                    .onAppear { measuredSize = geo.size }
                    .onChange(of: geo.size) { measuredSize = $0 }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if value.translation == .zero {
                                    strokes.append(Stroke(points: [value.location], color: currentColor, lineWidth: currentLineWidth))
                                } else if let last = strokes[strokes.count - 1].points.last,
                                          Self.distance(last, value.location) >= Self.minPointDistance {
                                    strokes[strokes.count - 1].points.append(value.location)
                                }
                            }
                    )
                }
                .aspectRatio(canvasSize.width / max(1, canvasSize.height), contentMode: .fit)

                // Port du `SeekBar` `ic_paint_size` (`PaintSizeListAdapter.java:35-45`, 0...100).
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.white.opacity(0.6))
                    Slider(value: $currentLineWidth, in: 1...100)
                    Image(systemName: "circle.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)
                .tint(.white)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, color in
                            Circle().fill(color).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.white, lineWidth: currentColor == color ? 2 : 1))
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

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Port de `AnimationEngine.chaikin` (`:371-388`) — lissage par coupe de coin, 1 itération
    /// (`CHAIKIN_ITER=1`), extrémités du trait conservées telles quelles.
    private static func chaikin(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var out: [CGPoint] = [points[0]]
        for i in 0..<(points.count - 1) {
            let p0 = points[i], p1 = points[i + 1]
            out.append(CGPoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y))
            out.append(CGPoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y))
        }
        out.append(points[points.count - 1])
        return out
    }

    private static func drawSmoothed(_ stroke: Stroke, in context: GraphicsContext) {
        let smoothed = chaikin(stroke.points)
        guard let first = smoothed.first else { return }
        var path = Path()
        path.move(to: first)
        for point in smoothed.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
    }

    /// Rasterise tous les traits (coordonnées VUE, `measuredSize`) à l'échelle du canevas Animems
    /// réel (`canvasSize`) — même principe de ré-échelle que `FreeformCropView.croppedImage`.
    private func flatten() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { ctx in
            let scaleX = canvasSize.width / max(1, measuredSize.width)
            let scaleY = canvasSize.height / max(1, measuredSize.height)
            for stroke in strokes {
                let smoothed = Self.chaikin(stroke.points).map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
                guard let first = smoothed.first else { continue }
                let path = UIBezierPath()
                path.move(to: first)
                for point in smoothed.dropFirst() { path.addLine(to: point) }
                path.lineWidth = stroke.lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor(stroke.color).setStroke()
                path.stroke()
            }
        }
    }
}
