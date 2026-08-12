import CoreGraphics
import CoreImage

/// Port de `core/BitmapCacheManager.java` (lu en entier) — cache des bitmaps dérivées coûteuses à
/// recalculer à chaque frame (bord adouci "feather", masque courant) : évite de reconstruire
/// l'image à chaque frame de lecture tant que les paramètres n'ont pas changé de plus que
/// `CACHE_DELTA_THRESHOLD`. "Zéro GC en régime de croisière" (commentaire Android) ne s'applique
/// pas de la même façon en Swift/ARC, mais le principe (éviter un recalcul coûteux par frame)
/// reste identique et vaut d'être reproduit tel quel.
final class BitmapCacheManager {
    private static let cacheDeltaThreshold: CGFloat = 0.5

    // MARK: - Cache feather

    private var cachedFeatheredImage: CGImage?
    private var cachedFeatherPx: CGFloat = -1
    private var cachedSourceImageId: ObjectIdentifier?

    // MARK: - Cache mask

    private var cachedMaskImage: CGImage?
    private var cachedMaskOffX: CGFloat = .nan
    private var cachedMaskOffY: CGFloat = .nan
    private var cachedMaskScl: CGFloat = .nan
    private var cachedMaskGap: CGFloat = .nan
    private var cachedMaskRot: CGFloat = .nan
    private var cachedMaskFeatherPx: CGFloat = .nan
    private var cachedMaskW: Int = -1
    private var cachedMaskH: Int = -1

    private var viewWidth: CGFloat = 1
    private var viewHeight: CGFloat = 1

    func setViewSize(width: CGFloat, height: CGFloat) {
        if width > 0 { viewWidth = width }
        if height > 0 { viewHeight = height }
    }

    func invalidate() {
        cachedFeatheredImage = nil
        cachedFeatherPx = -1
        cachedSourceImageId = nil
        cachedMaskImage = nil
        cachedMaskOffX = .nan
        cachedMaskOffY = .nan
        cachedMaskScl = .nan
        cachedMaskGap = .nan
        cachedMaskRot = .nan
        cachedMaskFeatherPx = .nan
        cachedMaskW = -1
        cachedMaskH = -1
    }

    // MARK: - Cache feather

    /// Port de `getCachedFeatheredBitmap` — `src` identifié par sa référence (`CGImage` est une
    /// classe `CF`, `ObjectIdentifier` joue le rôle de `System.identityHashCode(src)` d'Android).
    func cachedFeatheredImage(source: CGImage, featherPx: CGFloat) -> CGImage {
        if featherPx <= 0 {
            cachedFeatheredImage = nil
            cachedFeatherPx = -1
            cachedSourceImageId = nil
            return source
        }

        let sourceId = ObjectIdentifier(source)
        let featherChanged = abs(featherPx - cachedFeatherPx) > Self.cacheDeltaThreshold
        let sourceChanged = sourceId != cachedSourceImageId

        if cachedFeatheredImage == nil || featherChanged || sourceChanged {
            cachedFeatheredImage = Self.applyFeather(source, featherPx: featherPx)
            cachedFeatherPx = featherPx
            cachedSourceImageId = sourceId
        }

        return cachedFeatheredImage ?? source
    }

    // MARK: - Cache mask

    /// Port de `getCachedMaskBitmap`.
    func cachedMaskImage(
        for obj: AnimationObjectData,
        bmpW: Int, bmpH: Int,
        maskOffX: CGFloat, maskOffY: CGFloat,
        maskScl: CGFloat, maskGap: CGFloat,
        maskRot: CGFloat, maskFeatherPx: CGFloat
    ) -> CGImage? {
        let paramsChanged =
            bmpW != cachedMaskW || bmpH != cachedMaskH
                || abs(maskOffX - cachedMaskOffX) > Self.cacheDeltaThreshold / max(viewWidth, 1)
                || abs(maskOffY - cachedMaskOffY) > Self.cacheDeltaThreshold / max(viewHeight, 1)
                || abs(maskScl - cachedMaskScl) > 0.01
                || abs(maskGap - cachedMaskGap) > 0.01
                || abs(maskRot - cachedMaskRot) > Self.cacheDeltaThreshold
                || abs(maskFeatherPx - cachedMaskFeatherPx) > Self.cacheDeltaThreshold

        if cachedMaskImage == nil || paramsChanged {
            guard let maskType = obj.appliedMaskType else { return nil }
            cachedMaskImage = MaskFactory.createMaskScaled(
                type: maskType, width: bmpW, height: bmpH,
                inverted: obj.maskInverted, featherRadius: maskFeatherPx,
                scale: maskScl, offsetX: maskOffX, offsetY: maskOffY,
                mirrorGap: maskGap, rotation: maskRot
            )
            cachedMaskW = bmpW
            cachedMaskH = bmpH
            cachedMaskOffX = maskOffX
            cachedMaskOffY = maskOffY
            cachedMaskScl = maskScl
            cachedMaskGap = maskGap
            cachedMaskRot = maskRot
            cachedMaskFeatherPx = maskFeatherPx
        }

        return cachedMaskImage
    }

    // MARK: - Utilitaires

    static let maxFeatherPx: CGFloat = 250

    /// Port de `applyFeather` — dessine `src` dans un canevas agrandi d'une marge, avec un flou
    /// appliqué. **Approximation documentée** (même limite que `MaskFactory.blurredAlpha`) :
    /// Android floute uniquement le MASQUE ALPHA du paint (`BlurMaskFilter`), en principe sans
    /// altérer les couleurs RGB internes de l'image ; `CIGaussianBlur` ici floute RGB+alpha
    /// ensemble (pas de séparation de canal), ce qui peut légèrement adoucir aussi l'intérieur de
    /// l'image, pas seulement son bord — effet observable proche (bord adouci), pas un
    /// portage pixel-exact.
    static func applyFeather(_ source: CGImage, featherPx: CGFloat) -> CGImage? {
        guard featherPx > 0 else { return source }
        let margin = featherMargin(featherPx)
        let w = source.width + margin * 2
        let h = source.height + margin * 2

        guard let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return source }
        context.draw(source, in: CGRect(x: margin, y: h - margin - source.height, width: source.width, height: source.height))
        guard let padded = context.makeImage() else { return source }

        let ciContext = CIContext()
        let ciImage = CIImage(cgImage: padded)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return padded }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(featherPx, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return padded }
        let cropped = output.cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        return ciContext.createCGImage(cropped, from: cropped.extent) ?? padded
    }

    static func featherMargin(_ featherPx: CGFloat) -> Int {
        Int(featherPx.rounded(.up))
    }
}
