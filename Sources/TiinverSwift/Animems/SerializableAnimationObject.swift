import CoreGraphics
import Foundation
import UIKit

/// Port de `model/SerializableAnimationObject.java` — forme "à plat" (JSON-friendly) d'un
/// `AnimationObjectData`, utilisée pour la sauvegarde/le partage d'un calque (bitmaps encodées en
/// base64 PNG, comme l'original — `BitmapUtils.bitmapToBase64`/`base64ToBitmap` lus pour confirmer
/// le format exact : `Bitmap.CompressFormat.PNG`, qualité 100, PAS JPEG).
///
/// **Champs non repris, confirmés hors-scope de cette classe précise** : masque, keyframes,
/// forme (shape) — `SerializableAnimationObject.java` lui-même ne les sérialise pas (grep confirmé
/// sur son propre contenu, lu en entier ci-dessus) ; seuls id/label/type/dimensions/position
/// temporelle/couleurs/bitmaps sont couverts. Pas une lacune de ce portage, une fidélité au
/// périmètre réel de la classe Android.
struct SerializableAnimationObject: Codable {
    var id: String
    var label: String?
    var objectType: String
    var width: Int
    var height: Int
    var track: Int
    var startFrame: Int
    var endFrame: Int
    var backgroundColor: UInt32
    var objectColor: UInt32
    var bitmapChangeIntervalMs: Int
    var bitmapBase64: [String] = []

    static func from(_ src: AnimationObjectData) -> SerializableAnimationObject {
        var s = SerializableAnimationObject(
            id: src.id,
            label: src.label,
            objectType: (src.objectType ?? .bitmap).rawValue,
            width: Int(src.width),
            height: Int(src.height),
            track: src.track,
            startFrame: src.startFrame,
            endFrame: src.endFrame,
            backgroundColor: src.backgroundColor,
            objectColor: src.objectColor,
            bitmapChangeIntervalMs: src.bitmapChangeIntervalMs
        )
        s.bitmapBase64 = src.bitmaps.compactMap { Self.base64(from: $0) }
        return s
    }

    static func toAnimationObject(_ s: SerializableAnimationObject) -> AnimationObjectData {
        let obj = AnimationObjectData()
        obj.id = s.id
        obj.label = s.label
        obj.objectType = AnimationObjectData.ObjectType(rawValue: s.objectType)
        obj.width = CGFloat(s.width)
        obj.height = CGFloat(s.height)
        obj.track = s.track
        obj.startFrame = s.startFrame
        obj.endFrame = s.endFrame
        obj.backgroundColor = s.backgroundColor
        obj.objectColor = s.objectColor
        obj.bitmapChangeIntervalMs = s.bitmapChangeIntervalMs

        let images = s.bitmapBase64.compactMap { Self.image(fromBase64: $0) }
        obj.setBitmaps(images)
        return obj
    }

    // MARK: - Base64 PNG — port de `Utils/BitmapUtils.bitmapToBase64`/`base64ToBitmap`

    private static func base64(from image: CGImage) -> String? {
        UIImage(cgImage: image).pngData()?.base64EncodedString()
    }

    private static func image(fromBase64 base64Str: String) -> CGImage? {
        guard let data = Data(base64Encoded: base64Str), let uiImage = UIImage(data: data) else { return nil }
        return uiImage.cgImage
    }
}
