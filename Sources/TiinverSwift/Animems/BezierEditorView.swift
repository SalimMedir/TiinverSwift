import SwiftUI

/// Port de `android/views/BezierEditorView.java` — éditeur de courbe de Bézier cubique normalisée
/// `[0,1]×[0,1]` (P0 fixe en (0,0), P3 fixe en (1,1), P1/P2 déplaçables), utilisé pour définir des
/// courbes d'accélération personnalisées (easing).
///
/// Fichier auto-contenu (aucune dépendance vers `AnimationObjectData`/timeline/moteur) — contrairement
/// aux autres vues custom du module 8, porté ICI en entier (modèle + rendu SwiftUI), gestes inclus,
/// car directement testable visuellement sans dépendre du reste de l'éditeur.
struct BezierControlPoints: Equatable {
    var x1: CGFloat
    var y1: CGFloat
    var x2: CGFloat
    var y2: CGFloat

    /// Port du `easeInOut` par défaut de l'original.
    static let easeInOutDefault = BezierControlPoints(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    /// Port de `getInterpolation` — résolution de Newton-Raphson pour `x(u) = t`, puis évalue
    /// `y(u)` — mêmes 8 itérations et tolérances (`1e-6`) que l'original.
    func interpolation(at t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }

        var u = t
        for _ in 0..<8 {
            let xAtU = Self.sampleCurve(u: u, c1: Double(x1), c2: Double(x2))
            let dxdu = Self.sampleCurveDerivative(u: u, c1: Double(x1), c2: Double(x2))
            let error = xAtU - t
            if abs(error) < 1e-6 { break }
            if abs(dxdu) < 1e-6 { break }
            u -= error / dxdu
            u = max(0, min(1, u))
        }
        let yAtU = Self.sampleCurve(u: u, c1: Double(y1), c2: Double(y2))
        return max(0, min(1, yAtU))
    }

    private static func sampleCurve(u: Double, c1: Double, c2: Double) -> Double {
        let oneMinus = 1 - u
        return 3 * oneMinus * oneMinus * u * c1 + 3 * oneMinus * u * u * c2 + u * u * u
    }

    private static func sampleCurveDerivative(u: Double, c1: Double, c2: Double) -> Double {
        let oneMinus = 1 - u
        return 3 * (oneMinus * oneMinus * c1 + 2 * oneMinus * u * (c2 - c1) + u * u * (1 - c2))
    }
}

/// Port du rendu (`onDraw`) + des gestes de drag (`onTouchEvent`) de `BezierEditorView`.
struct BezierEditorView: View {
    @Binding var points: BezierControlPoints
    var onCommit: (() -> Void)?

    private let touchRadius: CGFloat = 12
    private let padding: CGFloat = 40

    @State private var dragging: DragTarget = .none
    private enum DragTarget { case none, p1, p2 }

    var body: some View {
        GeometryReader { geo in
            let left = padding, top = padding
            let right = geo.size.width - padding
            let bottom = geo.size.height - padding

            Canvas { context, _ in
                let frame = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                context.stroke(Path(frame), with: .color(Color(white: 0.7)), lineWidth: 2)
                drawGrid(context: &context, left: left, top: top, right: right, bottom: bottom)

                let p0 = normToView(0, 0, left, top, right, bottom)
                let p1 = normToView(points.x1, points.y1, left, top, right, bottom)
                let p2 = normToView(points.x2, points.y2, left, top, right, bottom)
                let p3 = normToView(1, 1, left, top, right, bottom)

                var handles = Path()
                handles.move(to: p0); handles.addLine(to: p1)
                handles.move(to: p2); handles.addLine(to: p3)
                context.stroke(handles, with: .color(Color(red: 0.129, green: 0.588, blue: 0.953)), lineWidth: 3)

                var curve = Path()
                curve.move(to: p0)
                curve.addCurve(to: p3, control1: p1, control2: p2)
                context.stroke(
                    curve, with: .color(Color(red: 1, green: 0.251, blue: 0.506)),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round))

                let pointColor = Color(red: 0.129, green: 0.588, blue: 0.953)
                context.fill(Path(ellipseIn: CGRect(x: p1.x - touchRadius, y: p1.y - touchRadius, width: touchRadius * 2, height: touchRadius * 2)), with: .color(pointColor))
                context.fill(Path(ellipseIn: CGRect(x: p2.x - touchRadius, y: p2.y - touchRadius, width: touchRadius * 2, height: touchRadius * 2)), with: .color(pointColor))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p1v = normToView(points.x1, points.y1, left, top, right, bottom)
                        let p2v = normToView(points.x2, points.y2, left, top, right, bottom)
                        if dragging == .none {
                            if distance(value.startLocation, p1v) <= touchRadius * 1.6 {
                                dragging = .p1
                            } else if distance(value.startLocation, p2v) <= touchRadius * 1.6 {
                                dragging = .p2
                            } else {
                                return
                            }
                        }
                        let norm = viewToNorm(value.location, left: left, top: top, right: right, bottom: bottom)
                        switch dragging {
                        case .p1: points.x1 = norm.x; points.y1 = norm.y
                        case .p2: points.x2 = norm.x; points.y2 = norm.y
                        case .none: break
                        }
                    }
                    .onEnded { _ in
                        dragging = .none
                        onCommit?()
                    }
            )
        }
    }

    private func drawGrid(context: inout GraphicsContext, left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        let steps = 4
        var path = Path()
        for i in 1..<steps {
            let x = left + CGFloat(i) * (right - left) / CGFloat(steps)
            let y = top + CGFloat(i) * (bottom - top) / CGFloat(steps)
            path.move(to: CGPoint(x: x, y: top)); path.addLine(to: CGPoint(x: x, y: bottom))
            path.move(to: CGPoint(x: left, y: y)); path.addLine(to: CGPoint(x: right, y: y))
        }
        context.stroke(path, with: .color(Color.black.opacity(0.067)), lineWidth: 1)
    }

    /// Port de `normToView` — origine normalisée en bas-gauche (`y=0` → bas), alors que
    /// `GeometryReader`/`Canvas` sont Y-vers-le-bas comme le `Canvas` Android d'origine — même
    /// inversion `bottom - ny * (bottom - top)` reproduite à l'identique.
    private func normToView(_ nx: CGFloat, _ ny: CGFloat, _ left: CGFloat, _ top: CGFloat, _ right: CGFloat, _ bottom: CGFloat) -> CGPoint {
        CGPoint(x: left + nx * (right - left), y: bottom - ny * (bottom - top))
    }

    private func viewToNorm(_ p: CGPoint, left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) -> CGPoint {
        let nx = max(0, min(1, (p.x - left) / (right - left)))
        let ny = max(0, min(1, (bottom - p.y) / (bottom - top)))
        return CGPoint(x: nx, y: ny)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
