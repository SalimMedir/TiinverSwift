import CoreGraphics
import SwiftUI

/// Port de `android/Paint/PaintPreviewEditorPanel.java` — dessin au doigt capturé comme une
/// séquence de frames bitmap (calque `PATH`-like animé : chaque trait est "filmé" pendant qu'il se
/// dessine, produisant une petite animation façon GIF). Fichier auto-contenu (aucune dépendance
/// timeline/moteur au-delà de produire des `CGImage` bruts) — porté ICI en entier (modèle + rendu +
/// gestes), comme `BezierEditorView`.
@MainActor
final class PaintCaptureController: ObservableObject {
    static let defaultStrokeWidth: CGFloat = 12
    static let defaultDelayMs = 80
    static let minDelayMs = 33
    static let maxDelayMs = 500

    /// Capture 1 bitmap toutes les `captureInterval` itérations de `move` — reproduit
    /// `CAN_DRAW = 6` de l'original.
    static let captureInterval = 6

    static let palette: [UInt32] = [
        0xFFFF_FFFF, 0xFFFF_5252, 0xFFFF_9800, 0xFFFF_EB3B, 0xFF4C_AF50,
        0xFF21_96F3, 0xFF9C_27B0, 0xFFE9_1E63, 0xFF00_BCD4, 0xFF79_5548,
    ]

    @Published private(set) var frames: [CGImage] = []
    @Published private(set) var previewImage: CGImage?
    @Published var strokeColor: UInt32 = 0xFFFF_FFFF
    @Published var strokeWidth: CGFloat = PaintCaptureController.defaultStrokeWidth
    @Published var delayMs: Int = PaintCaptureController.defaultDelayMs

    private var context: CGContext?
    private var size: CGSize = .zero
    private var currentPath: CGMutablePath?
    private var lastPoint: CGPoint = .zero
    private var moveCount = 0
    private var lastCaptureCount = 0

    /// Port de `DrawView.onSizeChanged` — bitmap recréé aux dimensions EXACTES de la vue (pas de
    /// distorsion), ancien contenu perdu (même comportement que l'original : pas de copie/redimensionnement
    /// de l'ancien tracé).
    func resize(to newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0, newSize != size else { return }
        size = newSize
        context = CGContext(
            data: nil, width: Int(newSize.width), height: Int(newSize.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // Contexte bitmap créé manuellement (origine bas-gauche, style PDF) — flip Y nécessaire
        // pour que les coordonnées tactiles SwiftUI (haut-gauche) dessinent au bon endroit, même
        // motif documenté dans `MaskFactory`/`AnimemesRecompose`. Appliqué UNE fois ici, avant tout
        // `saveGState`/`restoreGState` de trait : chaque `restoreGState()` revient à cet état déjà
        // flippé, pas à l'identité — le flip persiste pour tous les traits suivants.
        context?.translateBy(x: 0, y: newSize.height)
        context?.scaleBy(x: 1, y: -1)
        updatePreview()
    }

    func beginStroke(at point: CGPoint) {
        guard context != nil else { return }
        let path = CGMutablePath()
        path.move(to: point)
        currentPath = path
        lastPoint = point
        moveCount = 0
        lastCaptureCount = 0
    }

    /// Port de `onDrawMove` — lissage quadratique : le point de contrôle est le DERNIER point brut,
    /// le point de fin est le MILIEU entre le dernier point brut et le point courant (évite les
    /// angles vifs du tracé au doigt sans dépendance externe).
    func moveStroke(to point: CGPoint) {
        guard let context, let path = currentPath else { return }
        let mid = CGPoint(x: (lastPoint.x + point.x) / 2, y: (lastPoint.y + point.y) / 2)
        path.addQuadCurve(to: mid, control: lastPoint)

        strokeCurrentPath(path, in: context)
        lastPoint = point
        moveCount += 1

        if moveCount - lastCaptureCount == Self.captureInterval {
            captureFrame()
            lastCaptureCount = moveCount
        }
        updatePreview()
    }

    func endStroke(at point: CGPoint) {
        guard let context, let path = currentPath else { return }
        path.addLine(to: point)
        strokeCurrentPath(path, in: context)
        captureFrame()

        currentPath = nil
        moveCount = 0
        lastCaptureCount = 0
        updatePreview()
    }

    /// Port de `clearAll`.
    func clearAll() {
        frames = []
        if let context {
            context.clear(CGRect(origin: .zero, size: size))
        }
        currentPath = nil
        moveCount = 0
        lastCaptureCount = 0
        updatePreview()
    }

    /// Port de `seekProgressFromDelay`/`delayFromSeekProgress` — mapping inversé (0 = lent/délai
    /// max, 100 = rapide/délai min) pour un slider "Vitesse".
    static func seekProgress(fromDelayMs delayMs: Int) -> Int {
        let t = Double(delayMs - minDelayMs) / Double(maxDelayMs - minDelayMs)
        return Int(((1 - t) * 100).rounded())
    }

    static func delayMs(fromSeekProgress progress: Int) -> Int {
        let t = 1 - Double(progress) / 100
        return minDelayMs + Int((t * Double(maxDelayMs - minDelayMs)).rounded())
    }

    private func strokeCurrentPath(_ path: CGMutablePath, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(cgColor(argb: strokeColor))
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private func captureFrame() {
        guard let image = context?.makeImage() else { return }
        frames.append(image)
    }

    private func updatePreview() {
        previewImage = context?.makeImage()
    }

    private func cgColor(argb: UInt32) -> CGColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255
        let r = CGFloat((argb >> 16) & 0xFF) / 255
        let g = CGFloat((argb >> 8) & 0xFF) / 255
        let b = CGFloat(argb & 0xFF) / 255
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }
}

/// Port de `DrawView` + gestion tactile de `PaintPreviewEditorPanel` — surface de dessin seule.
/// Palette/sliders/boutons (pure disposition Android `LinearLayout`, sans logique) laissés à
/// l'appelant SwiftUI, comme documenté dans le journal module 8.
struct PaintDrawingCanvas: View {
    @ObservedObject var controller: PaintCaptureController

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                if let image = controller.previewImage {
                    context.draw(Image(decorative: image, scale: 1), at: .zero, anchor: .topLeading)
                }
            }
            .onAppear { controller.resize(to: geo.size) }
            .onChange(of: geo.size) { controller.resize(to: $0) }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.translation == .zero {
                            controller.beginStroke(at: value.location)
                        } else {
                            controller.moveStroke(to: value.location)
                        }
                    }
                    .onEnded { value in
                        controller.endStroke(at: value.location)
                    }
            )
        }
    }
}
