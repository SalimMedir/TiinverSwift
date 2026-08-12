import CoreGraphics
import CoreImage
import UIKit

/// Port de `engine/android/mask/MaskFactory.java` (230 lignes, lu en entier) — génère un masque
/// (`CGImage`, forme portée par le canal alpha) pour un `MaskType`, avec échelle/décalage/
/// rotation/inversion/flou de bord.
///
/// **Repère de coordonnées — piège de portage identifié et évité** : `android.graphics.Canvas`
/// a son origine en haut-à-gauche, Y croissant VERS LE BAS — tout le code de tracé de ce fichier
/// (translate/rotate/coordonnées de `Path`) est écrit dans ce repère. `CGContext` créé par
/// `CGContext(data:...)` a par défaut son origine en BAS-à-gauche, Y croissant vers le HAUT
/// (convention PDF historique de Core Graphics — pas UIKit, qui inverse déjà pour `UIView.draw`,
/// mais PAS un contexte bitmap créé manuellement comme ici). Sans correction, tout tracé serait
/// vertical-miroir par rapport à Android. Corrigé par un flip explicite
/// (`translateBy(y: height)` + `scaleBy(y: -1)`) juste après la création du contexte, une seule
/// fois — tout le reste du code de tracé peut ensuite être porté tel quel depuis les coordonnées
/// Android sans reconversion ligne à ligne.
///
/// **Flou de bord — comportement observable reproduit, pas l'algorithme interne** : Android
/// utilise `BlurMaskFilter(radius, Blur.NORMAL)` (flou Skia propriétaire du canal alpha). Reproduit
/// ici via `CIGaussianBlur` (Core Image) appliqué à l'image tracée — bord progressif similaire,
/// mais PAS un flou bit-identique (algorithmes différents, comme déjà documenté pour d'autres
/// équivalences plateforme de ce portage, ex. `VideoCacheManager` module 6).
enum MaskFactory {
    static func createMaskScaled(
        type: MaskType,
        width: Int,
        height: Int,
        inverted: Bool,
        featherRadius: CGFloat,
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        mirrorGap: CGFloat,
        rotation: CGFloat = 0
    ) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        let pad = featherRadius > 0 ? Int(featherRadius * 2) : 0
        let bw = width + pad * 2
        let bh = height + pad * 2

        let clampedScale = max(0.1, min(5, scale))
        let formW = CGFloat(width) * clampedScale
        let formH = CGFloat(height) * clampedScale
        let cx = CGFloat(width) / 2 + offsetX * CGFloat(width) - formW / 2
        let cy = CGFloat(height) / 2 + offsetY * CGFloat(height) - formH / 2

        guard let context = CGContext(
            data: nil, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Piège de portage évité — voir commentaire de tête de fichier.
        context.translateBy(x: 0, y: CGFloat(bh))
        context.scaleBy(x: 1, y: -1)

        let path = pathForSize(type: type, width: formW, height: formH, mirrorGap: mirrorGap)

        if !inverted || featherRadius > 0 {
            context.clear(CGRect(x: 0, y: 0, width: bw, height: bh))
        } else {
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: bw, height: bh))
        }

        context.setFillColor(UIColor.white.cgColor)
        if inverted, featherRadius <= 0 {
            context.setBlendMode(.clear)
        }
        context.saveGState()
        context.translateBy(x: CGFloat(pad) + cx, y: CGFloat(pad) + cy)
        context.translateBy(x: formW / 2, y: formH / 2)
        context.rotate(by: rotation * .pi / 180)
        context.translateBy(x: -formW / 2, y: -formH / 2)
        if let path {
            context.addPath(path)
            context.fillPath()
        }
        context.restoreGState()

        guard var image = context.makeImage() else { return nil }

        if featherRadius > 0 {
            image = blurredAlpha(image, radius: featherRadius, canvasSize: CGSize(width: bw, height: bh)) ?? image
            if inverted {
                image = invertedAlpha(image) ?? image
            }
        }

        if pad > 0 {
            let cropRect = CGRect(x: pad, y: pad, width: width, height: height)
            image = image.cropping(to: cropRect) ?? image
        }

        return image
    }

    /// Port de `createMaskScaled` sans rotation (rétrocompatibilité côté Android).
    static func createMaskScaled(
        type: MaskType, width: Int, height: Int, inverted: Bool, featherRadius: CGFloat,
        scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat, mirrorGap: CGFloat
    ) -> CGImage? {
        createMaskScaled(
            type: type, width: width, height: height, inverted: inverted,
            featherRadius: featherRadius, scale: scale, offsetX: offsetX, offsetY: offsetY,
            mirrorGap: mirrorGap, rotation: 0
        )
    }

    // MARK: - Tracés (port de `buildPath`/`buildPathForSize` et des `build*` individuels)

    private static func pathForSize(type: MaskType, width: CGFloat, height: CGFloat, mirrorGap: CGFloat) -> CGPath? {
        guard width > 0, height > 0 else { return nil }
        if type == .mirror { return mirrorPath(width: width, height: height, gap: mirrorGap) }
        return path(for: type, width: width, height: height)
    }

    private static func path(for type: MaskType, width w: CGFloat, height h: CGFloat) -> CGPath? {
        switch type {
        case .circle: return circlePath(width: w, height: h)
        case .square: return squarePath(width: w, height: h)
        case .rectangle: return rectPath(width: w, height: h, landscape: false)
        case .horizontal: return rectPath(width: w, height: h, landscape: true)
        case .mirror: return mirrorPath(width: w, height: h, gap: 0.06)
        case .heart: return heartPath(width: w, height: h)
        case .star: return starPath(width: w, height: h, branches: 5)
        }
    }

    private static func circlePath(width w: CGFloat, height h: CGFloat) -> CGPath {
        let cx = w / 2, cy = h / 2
        let r = min(w, h) / 2 * 0.85
        return CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), transform: nil)
    }

    private static func squarePath(width w: CGFloat, height h: CGFloat) -> CGPath {
        let side = min(w, h) * 0.85
        let left = (w - side) / 2, top = (h - side) / 2
        return CGPath(rect: CGRect(x: left, y: top, width: side, height: side), transform: nil)
    }

    private static func rectPath(width w: CGFloat, height h: CGFloat, landscape: Bool) -> CGPath {
        let rw = landscape ? w * 0.90 : w * 0.60
        let rh = landscape ? h * 0.50 : h * 0.85
        let left = (w - rw) / 2, top = (h - rh) / 2
        return CGPath(rect: CGRect(x: left, y: top, width: rw, height: rh), transform: nil)
    }

    private static func mirrorPath(width w: CGFloat, height h: CGFloat, gap: CGFloat) -> CGPath {
        let gapPx = w * max(0, min(0.5, gap))
        let rh = h * 0.72
        let rw = (w - gapPx) / 2 * 0.90
        let top = (h - rh) / 2
        let leftL = w / 2 - gapPx / 2 - rw, leftR = w / 2 - gapPx / 2
        let rightL = w / 2 + gapPx / 2, rightR = w / 2 + gapPx / 2 + rw
        let path = CGMutablePath()
        path.addRect(CGRect(x: leftL, y: top, width: leftR - leftL, height: rh))
        path.addRect(CGRect(x: rightL, y: top, width: rightR - rightL, height: rh))
        return path
    }

    private static func heartPath(width w: CGFloat, height h: CGFloat) -> CGPath {
        let size = min(w, h) * 0.80
        let ox = (w - size) / 2, oy = (h - size) / 2 + size * 0.04
        let crewX = ox + size * 0.50, crewY = oy + size * 0.25
        let leftX = ox + size * 0.00, leftY = oy + size * 0.45
        let rightX = ox + size * 1.00, rightY = oy + size * 0.45
        let tipX = ox + size * 0.50, tipY = oy + size * 0.98
        let path = CGMutablePath()
        path.move(to: CGPoint(x: crewX, y: crewY))
        path.addCurve(
            to: CGPoint(x: leftX, y: leftY),
            control1: CGPoint(x: ox + size * 0.50, y: oy + size * 0.05),
            control2: CGPoint(x: ox + size * 0.00, y: oy + size * 0.10)
        )
        path.addCurve(
            to: CGPoint(x: tipX, y: tipY),
            control1: CGPoint(x: ox + size * 0.00, y: oy + size * 0.75),
            control2: CGPoint(x: ox + size * 0.35, y: oy + size * 0.95)
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: rightY),
            control1: CGPoint(x: ox + size * 0.65, y: oy + size * 0.95),
            control2: CGPoint(x: ox + size * 1.00, y: oy + size * 0.75)
        )
        path.addCurve(
            to: CGPoint(x: crewX, y: crewY),
            control1: CGPoint(x: ox + size * 1.00, y: oy + size * 0.10),
            control2: CGPoint(x: ox + size * 0.50, y: oy + size * 0.05)
        )
        path.closeSubpath()
        return path
    }

    private static func starPath(width w: CGFloat, height h: CGFloat, branches: Int) -> CGPath {
        let cx = w / 2, cy = h / 2
        let outerR = min(w, h) * 0.45
        let innerR = outerR * 0.40
        let path = CGMutablePath()
        let step = Double.pi / Double(branches)
        for i in 0..<(branches * 2) {
            let angle = Double(i) * step - .pi / 2
            let r = i % 2 == 0 ? outerR : innerR
            let x = cx + r * CGFloat(cos(angle))
            let y = cy + r * CGFloat(sin(angle))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Flou de bord et inversion alpha

    private static func blurredAlpha(_ image: CGImage, radius: CGFloat, canvasSize: CGSize) -> CGImage? {
        let ciContext = CIContext()
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        // `CIGaussianBlur` agrandit l'étendue de l'image (rayon de flou) — recadré à la taille
        // d'origine du canevas (avec padding), comme le fait le crop final d'Android sur `tmp`.
        let cropped = output.cropped(to: CGRect(origin: .zero, size: canvasSize))
        return ciContext.createCGImage(cropped, from: cropped.extent)
    }

    /// Port de `invertAlpha` — `newAlpha = 255 - alpha`, RGB forcé à blanc opaque (comme
    /// l'original : `(a << 24) | 0x00FFFFFF`, la couleur RGB d'origine n'a jamais d'importance ici
    /// puisque tous les masques sont tracés en blanc plein).
    private static func invertedAlpha(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for i in stride(from: 0, to: data.count, by: 4) {
            let alpha = data[i + 3]
            let invertedAlpha = 255 - alpha
            data[i] = invertedAlpha
            data[i + 1] = invertedAlpha
            data[i + 2] = invertedAlpha
            data[i + 3] = invertedAlpha
        }

        return context.makeImage()
    }
}
