import CoreGraphics
import SwiftUI

/// Port de `android/croper/FreeformCropView.java` (module 9) — découpe une image selon un tracé
/// au doigt fermé (masque de forme libre), alternative au recadrage rectangle/ovale de
/// `TOCropViewController` (voir décision d'architecture dans le journal `MIGRATION_PROGRESS.md` :
/// bibliothèque tierce choisie pour remplacer `android/croper/CropImageView.java`+
/// `CropOverlayView.java`+`CropWindowHandler.java`+`CropWindowMoveHandler.java`, qui ne couvrent
/// PAS ce mode "freeform" — ce fichier reste donc un port direct, self-contained, comme
/// `BezierEditorView`/`CanvasZoomController` du module 8).
struct FreeformCropView: View {
    let sourceImage: CGImage
    @Binding var path: Path

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                context.draw(Image(decorative: sourceImage, scale: 1), in: CGRect(origin: .zero, size: size))
                context.stroke(
                    path, with: .color(Color(red: 0, green: 0, blue: 1, opacity: 120.0 / 255)),
                    style: StrokeStyle(lineWidth: 15))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.translation == .zero {
                            path = Path()
                            path.move(to: value.location)
                        } else {
                            path.addLine(to: value.location)
                        }
                    }
                    .onEnded { _ in
                        path.closeSubpath()
                    }
            )
        }
    }

    /// Port de `resetPath`.
    static func reset(_ path: inout Path) {
        path = Path()
    }

    /// Port de `getCroppedBitmap` — remet le tracé (exprimé en coordonnées VUE) à l'échelle de
    /// l'image source, puis l'utilise comme masque de découpe (rempli = conservé, le reste
    /// transparent). `viewSize` = taille de la `Canvas` au moment du tracé (celle utilisée par
    /// `body` ci-dessus).
    static func croppedImage(source: CGImage, path: Path, viewSize: CGSize) -> CGImage? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let w = source.width, h = source.height
        guard let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Contexte bitmap créé manuellement (origine bas-gauche, style PDF) — flip Y nécessaire
        // pour que le tracé SwiftUI (haut-gauche, comme le `Canvas` de `body` ci-dessus) se
        // découpe au bon endroit, même motif documenté dans `MaskFactory`/`PaintCapture`/
        // `AnimemesRecompose`.
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1, y: -1)

        let scaleX = CGFloat(w) / viewSize.width
        let scaleY = CGFloat(h) / viewSize.height
        let scaledPath = path.applying(CGAffineTransform(scaleX: scaleX, y: scaleY))

        context.addPath(scaledPath.cgPath)
        context.clip()
        context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

        return context.makeImage()
    }
}
