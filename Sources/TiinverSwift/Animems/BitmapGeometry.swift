import CoreGraphics
import UIKit

/// Port de fonctions géométriques bitmap ponctuelles d'`AnimemesCompound.java`, sans dépendance
/// sur le reste de la classe (pas de `View`/`Context` Android impliqué dans leur corps).
enum BitmapGeometry {
    /// Port de `AnimemesCompound.fitBitmapIntoSize` — redimensionne `src` en conservant son
    /// ratio ("aspect fit") et le centre dans un canevas transparent de taille
    /// `targetW`×`targetH` (ex. normaliser une bitmap de remplacement à la taille de celle
    /// qu'elle remplace dans un calque existant).
    static func fitBitmap(_ src: CGImage, targetW: CGFloat, targetH: CGFloat) -> CGImage? {
        guard targetW > 0, targetH > 0 else { return src }

        let scaleX = targetW / CGFloat(src.width)
        let scaleY = targetH / CGFloat(src.height)
        let scale = min(scaleX, scaleY)

        let scaledW = CGFloat(src.width) * scale
        let scaledH = CGFloat(src.height) * scale
        let offsetX = (targetW - scaledW) / 2
        let offsetY = (targetH - scaledH) / 2

        let canvasW = Int(targetW.rounded())
        let canvasH = Int(targetH.rounded())

        guard let context = CGContext(
            data: nil, width: canvasW, height: canvasH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return src }

        context.clear(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        context.interpolationQuality = .high
        // Origine Core Graphics par défaut (bas-gauche) — ici sans conséquence : le rectangle
        // cible est centré symétriquement, donc la même image dessinée "à l'envers" verticalement
        // occupe exactement le même rectangle (contrairement à `MaskFactory`, aucun tracé
        // dépendant de l'orientation Y n'entre en jeu ici).
        context.draw(src, in: CGRect(x: offsetX, y: offsetY, width: scaledW, height: scaledH))

        return context.makeImage()
    }
}
