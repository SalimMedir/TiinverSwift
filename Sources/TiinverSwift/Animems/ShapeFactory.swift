import CoreGraphics
import UIKit

/// Port de `android/utils/ShapeFactory.java` — rasterise les paramètres de forme (rectangle,
/// cercle, ligne) en `CGImage`, pour rester compatible avec le pipeline bitmap existant
/// (`AnimationObjectData.bitmaps`) sans toucher à `LayerRenderer`/`AnimemesExporter`/la timeline —
/// même stratégie que l'original ("shapes are rasterized into Bitmap so they plug directly into
/// the existing AnimationObjectData bitmap pipeline").
enum ShapeFactory {
    private static let minSize = 4

    /// Port de `createRect`. `color` est l'ARGB packé de `AnimationObjectData.shapeColor` — seuls
    /// ses octets RVB sont utilisés : l'alpha final vient TOUJOURS du paramètre `alpha` séparé, car
    /// `Paint.setAlpha` (Android) REMPLACE l'octet alpha du `Paint.setColor` plutôt que de le
    /// multiplier — reproduit à l'identique via `clampAlpha`.
    static func createRect(
        w: Int, h: Int, color: UInt32, alpha: Float, cornerRadius: CGFloat, strokeWidth: CGFloat
    ) -> CGImage? {
        let w = max(w, minSize), h = max(h, minSize)
        guard let context = makeContext(width: w, height: h) else { return nil }

        let inset: CGFloat = strokeWidth > 0 ? strokeWidth / 2 : 0
        let rect = CGRect(x: inset, y: inset, width: CGFloat(w) - inset * 2, height: CGFloat(h) - inset * 2)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        if strokeWidth > 0 {
            context.addPath(path)
            context.setFillColor(argbColor(color, alpha: alpha))
            context.fillPath()

            context.addPath(path)
            context.setStrokeColor(argbColor(darken(color), alpha: alpha))
            context.setLineWidth(strokeWidth)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.strokePath()
        } else {
            context.addPath(path)
            context.setFillColor(argbColor(color, alpha: alpha))
            context.fillPath()
        }

        return context.makeImage()
    }

    /// Port de `createCircle`.
    static func createCircle(diameter: Int, color: UInt32, alpha: Float, strokeWidth: CGFloat) -> CGImage? {
        let diameter = max(diameter, minSize)
        guard let context = makeContext(width: diameter, height: diameter) else { return nil }

        let cx = CGFloat(diameter) / 2, cy = CGFloat(diameter) / 2
        let inset: CGFloat = strokeWidth > 0 ? strokeWidth / 2 : 0
        let radius = cx - inset
        let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)

        context.setFillColor(argbColor(color, alpha: alpha))
        context.fillEllipse(in: rect)

        if strokeWidth > 0 {
            context.setStrokeColor(argbColor(darken(color), alpha: alpha))
            context.setLineWidth(strokeWidth)
            context.strokeEllipse(in: rect)
        }

        return context.makeImage()
    }

    /// Port de `createLine`. Hauteur du bitmap = épaisseur + 4px de marge anti-alias (identique à
    /// l'original), extrémités arrondies (`Cap.ROUND`).
    static func createLine(length: Int, thickness: CGFloat, color: UInt32, alpha: Float) -> CGImage? {
        let length = max(length, minSize)
        let thickness = max(thickness, 1)
        let bitmapH = Int(thickness + 4)
        guard let context = makeContext(width: length, height: bitmapH) else { return nil }

        let cy = CGFloat(bitmapH) / 2
        context.setStrokeColor(argbColor(color, alpha: alpha))
        context.setLineWidth(thickness)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 0, y: cy))
        context.addLine(to: CGPoint(x: CGFloat(length), y: cy))
        context.strokePath()

        return context.makeImage()
    }

    /// Port de `rerenderShape` — reconstruit le bitmap d'un calque `SHAPE_*` à partir de ses
    /// propriétés stockées (appelé après édition dans le panneau de forme, pas encore porté —
    /// voir note module 8 sur `ShapePreviewEditorPanel`/`ShapeAddPanel`).
    static func rerender(_ data: AnimationObjectData, canvasW: Int, canvasH: Int) -> CGImage? {
        guard let type = data.objectType else { return nil }
        let color = data.shapeColor
        let alpha = data.shapeOpacity

        switch type {
        case .shapeRect:
            let w = data.shapeW > 0 ? data.shapeW : canvasW / 3
            let h = data.shapeH > 0 ? data.shapeH : canvasH / 6
            return createRect(
                w: w, h: h, color: color, alpha: alpha,
                cornerRadius: CGFloat(data.shapeCornerRadius), strokeWidth: CGFloat(data.shapeStrokeWidth))
        case .shapeCircle:
            let d = data.shapeW > 0 ? data.shapeW : canvasW / 4
            return createCircle(diameter: d, color: color, alpha: alpha, strokeWidth: CGFloat(data.shapeStrokeWidth))
        case .shapeLine:
            let len = data.shapeW > 0 ? data.shapeW : canvasW / 2
            return createLine(length: len, thickness: CGFloat(data.shapeLineThickness), color: color, alpha: alpha)
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// RVB de `argbColor` (l'octet alpha packé est ignoré — voir note `createRect`), combiné à
    /// l'alpha séparé `alpha` (`[0, 1]`, clampé comme `clampAlpha`).
    private static func argbColor(_ argbColor: UInt32, alpha: Float) -> CGColor {
        let r = CGFloat((argbColor >> 16) & 0xFF) / 255
        let g = CGFloat((argbColor >> 8) & 0xFF) / 255
        let b = CGFloat(argbColor & 0xFF) / 255
        let a = CGFloat(max(0, min(1, alpha)))
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }

    /// Port de `darkenColor` — HSV, `V -= 0.25` clampé, reconversion. `UIColor`'s
    /// `getHue(...)`/`init(hue:...)` implémentent la même transformée HSV standard que
    /// `android.graphics.Color.RGBToHSV`/`HSVToColor`.
    private static func darken(_ argbColor: UInt32) -> UInt32 {
        let r = CGFloat((argbColor >> 16) & 0xFF) / 255
        let g = CGFloat((argbColor >> 8) & 0xFF) / 255
        let b = CGFloat(argbColor & 0xFF) / 255
        let color = UIColor(red: r, green: g, blue: b, alpha: 1)

        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        v = max(0, v - 0.25)
        let darkened = UIColor(hue: h, saturation: s, brightness: v, alpha: 1)

        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        darkened.getRed(&dr, green: &dg, blue: &db, alpha: &da)
        return (0xFF << 24) | (UInt32(dr * 255) << 16) | (UInt32(dg * 255) << 8) | UInt32(db * 255)
    }
}
