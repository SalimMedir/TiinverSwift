import CoreGraphics

/// Port des petits utilitaires statiques de `android/croper/CropImage.java` réellement utilisés
/// par ce projet (`CroperView.onCropImageComplete`) — le reste de `CropImage.java` (998 lignes,
/// orchestration de `CropImageActivity`/intents Android, sans équivalent iOS) est couvert par le
/// remplacement `TOCropViewController` (voir décision d'architecture, journal module 9).
enum PhotoCropUtils {
    /// Port de `CropImage.toOvalBitmap` — rend transparent tout pixel hors de l'ellipse inscrite
    /// dans le rectangle de l'image (masque de forme "OVAL" du recadreur, bouton `btn_shape` de
    /// `CroperView`).
    static func toOvalImage(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Pas de flip Y nécessaire ici : l'ellipse inscrite dans le rectangle complet de l'image
        // est symétrique verticalement, le repère du contexte (bas-gauche vs haut-gauche) ne
        // change pas le résultat — contrairement à `FreeformCropView`/`MaskFactory`, qui dessinent
        // une forme dépendante de coordonnées EXTERNES (tracé au doigt).
        context.addEllipse(in: CGRect(x: 0, y: 0, width: w, height: h))
        context.clip()
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
