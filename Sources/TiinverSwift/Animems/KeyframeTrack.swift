import Foundation

/// Port de `engine/keyframe/KeyframeTrack.java` — piste de keyframes pour UNE propriété nommée
/// (ex. "opacity"), triée par horodatage, avec interpolation/easing. Utilisée par
/// `AnimationObjectData` (module 8, pas encore porté) — un objet de calque possède une
/// `KeyframeTrack` par propriété animée (`Map<String, KeyframeTrack>` côté Android, deviendra un
/// `[String: KeyframeTrack]` côté Swift au moment de porter `AnimationObjectData`).
struct KeyframeTrack {
    /// Port des constantes `PROP_*` — noms de propriété EXACTS (utilisés tels quels comme clés de
    /// dictionnaire par le futur port d'`AnimationObjectData`, pas de renommage Swift-isé qui
    /// casserait la correspondance).
    enum PropertyName {
        static let matrix = "matrix"
        static let maskRotation = "maskRotation"
        static let maskOffsetX = "maskOffsetX"
        static let maskOffsetY = "maskOffsetY"
        static let maskScale = "maskScale"
        static let maskMirrorGap = "maskMirrorGap"
        static let color = "color"
        static let opacity = "opacity"
        static let cornerRadius = "cornerRadius"
        static let feather = "feather"
        static let maskType = "mask"
        static let positionX = "posX"
        static let positionY = "posY"
        static let scale = "scale"
        static let rotation = "rotation"
        static let skewX = "skewX"
        static let skewY = "skewY"
    }

    /// Port des constantes `MARKER_COLOR_*` — ARGB packé 32 bits (même format que
    /// `Keyframe.colorValue`/`android.graphics.Color`), pas un type `Color` SwiftUI : la
    /// conversion revient à l'écran de timeline (module 8, UI pas encore construite).
    private enum MarkerColor {
        static let color: UInt32 = 0xFF21_96F3
        static let opacity: UInt32 = 0xFFFF_C107
        static let corner: UInt32 = 0xFF4C_AF50
        static let feather: UInt32 = 0xFFE9_1E63
        static let unknown: UInt32 = 0xFFAA_AAAA
        static let positionLightBlue: UInt32 = 0xFF03_A9F4
        static let scaleOrange: UInt32 = 0xFFFF_9800
        static let rotationPurple: UInt32 = 0xFF9C_27B0
        static let skewTeal: UInt32 = 0xFF00_9688
    }

    let propertyName: String
    private(set) var keyframes: [Keyframe] = []

    init(propertyName: String) {
        self.propertyName = propertyName
    }

    var isEmpty: Bool { keyframes.isEmpty }
    var count: Int { keyframes.count }

    /// Port de `addKeyframe(long, float[], EasingType)` — si un keyframe existe déjà exactement à
    /// `timestampNs`, sa valeur/easing sont remplacées EN PLACE (pas de doublon), sinon insertion
    /// suivie d'un tri par horodatage croissant (comme `Collections.sort` côté Android).
    mutating func addKeyframe(timestampNs: Int64, value: [Float], easing: Keyframe.EasingType = .linear) {
        if let index = keyframes.firstIndex(where: { $0.timestampNs == timestampNs }) {
            keyframes[index].value = value
            keyframes[index].easing = easing
            return
        }
        keyframes.append(Keyframe(timestampNs: timestampNs, value: value, easing: easing))
        keyframes.sort { $0.timestampNs < $1.timestampNs }
    }

    /// Port de `removeKeyframe(String id)`.
    @discardableResult
    mutating func removeKeyframe(id: String) -> Bool {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return false }
        keyframes.remove(at: index)
        return true
    }

    mutating func clear() {
        keyframes.removeAll()
    }

    /// Port de `getValue(long timestampNs)` — `nil` si la piste est vide (port de `null`
    /// Android) ; valeur figée avant le premier/après le dernier keyframe ; interpolation avec
    /// easing entre les deux keyframes encadrants sinon.
    func getValue(at timestampNs: Int64) -> [Float]? {
        guard !keyframes.isEmpty else { return nil }
        if keyframes.count == 1 { return keyframes[0].value }

        if timestampNs <= keyframes[0].timestampNs { return keyframes[0].value }

        let last = keyframes[keyframes.count - 1]
        if timestampNs >= last.timestampNs { return last.value }

        var before: Keyframe?
        var after: Keyframe?
        for i in 0..<(keyframes.count - 1) {
            let a = keyframes[i]
            let b = keyframes[i + 1]
            if timestampNs >= a.timestampNs && timestampNs < b.timestampNs {
                before = a
                after = b
                break
            }
        }

        guard let kfBefore = before, let kfAfter = after else { return keyframes[0].value }

        let t = Float(timestampNs - kfBefore.timestampNs) / Float(kfAfter.timestampNs - kfBefore.timestampNs)
        let tEased = Self.applyEasing(t, kfBefore.easing)
        return Self.lerp(kfBefore.value, kfAfter.value, tEased)
    }

    /// Port de `findNearest(long, long)`.
    func findNearest(to timestampNs: Int64, toleranceNs: Int64) -> Keyframe? {
        var best: Keyframe?
        var bestDistance = Int64.max
        for kf in keyframes {
            let distance = abs(kf.timestampNs - timestampNs)
            if distance < bestDistance && distance <= toleranceNs {
                bestDistance = distance
                best = kf
            }
        }
        return best
    }

    /// Port de `getMarkerColor()` (couleur d'affichage sur la timeline, pas encore construite).
    var markerColor: UInt32 {
        switch propertyName {
        case PropertyName.color: return MarkerColor.color
        case PropertyName.opacity: return MarkerColor.opacity
        case PropertyName.cornerRadius: return MarkerColor.corner
        case PropertyName.feather: return MarkerColor.feather
        case PropertyName.positionX, PropertyName.positionY: return MarkerColor.positionLightBlue
        case PropertyName.scale: return MarkerColor.scaleOrange
        case PropertyName.rotation: return MarkerColor.rotationPurple
        case PropertyName.skewX, PropertyName.skewY: return MarkerColor.skewTeal
        case PropertyName.matrix: return MarkerColor.positionLightBlue
        default: return MarkerColor.unknown
        }
    }

    private static func applyEasing(_ t: Float, _ easing: Keyframe.EasingType) -> Float {
        switch easing {
        case .easeIn: return t * t
        case .easeOut: return t * (2 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        case .linear: return t
        }
    }

    /// Port de `lerp(float[], float[], float)` — s'arrête à `min(a.count, b.count)` comme
    /// l'original (`Math.min(a.length, b.length)`), pas une erreur si les tailles diffèrent.
    private static func lerp(_ a: [Float], _ b: [Float], _ t: Float) -> [Float] {
        let length = min(a.count, b.count)
        var result = [Float](repeating: 0, count: length)
        for i in 0..<length {
            result[i] = a[i] + t * (b[i] - a[i])
        }
        return result
    }
}
