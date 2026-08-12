import Foundation

/// Port de `engine/keyframe/Keyframe.java` — un keyframe représente la valeur d'une propriété à
/// un instant précis. Système "TOTALEMENT INDÉPENDANT du système de transformation matricielle
/// existant (transforms / glMatrix)" (commentaire du fichier source repris tel quel) — c'est-à-dire
/// indépendant de `Transform`/`AnimationObjectData.transforms`, PAS indépendant du reste du module
/// Animems dans son ensemble.
///
/// Propriétés supportées, valeur `[Float]` selon la propriété (reproduit à l'identique, pas de
/// type `enum` Swift plus "propre" substitué — le contrat exact avec `KeyframeTrack`/
/// `AnimationObjectData` dépend de cette représentation `[Float]` brute) :
///   "color"        → `[Float]` de 4 éléments `{A, R, G, B}`, chaque canal dans `[0, 255]`
///   "opacity"      → `[Float]` de 1 élément `{0.0 … 1.0}`
///   "cornerRadius" → `[Float]` de 1 élément `{px ≥ 0}`
///   "posX"/"posY"/"scale"/"rotation"/"skewX"/"skewY"/"feather"/masques → `[Float]` de 1 élément
///   "matrix"       → `[Float]` de 9 éléments (valeurs `android.graphics.Matrix`, voir
///                    `AnimationObjectData.addMatrixKeyframe`/`Transform.getMatrixValues` — un
///                    équivalent Swift de la représentation 3×3 `Matrix.getValues()` d'Android
///                    sera nécessaire au portage de `Transform`, pas encore fait à ce stade).
struct Keyframe: Identifiable, Equatable {
    enum EasingType {
        case linear
        case easeIn
        case easeOut
        case easeInOut
    }

    let id: String
    var timestampNs: Int64
    var value: [Float]
    var easing: EasingType

    init(timestampNs: Int64, value: [Float], easing: EasingType = .linear) {
        self.id = UUID().uuidString
        self.timestampNs = timestampNs
        self.value = value
        self.easing = easing
    }

    /// Port de `Keyframe.scalarValue` — construit une valeur à 1 élément (opacity, cornerRadius,
    /// posX/Y, scale, rotation, skewX/Y, feather, propriétés de masque).
    static func scalarValue(_ v: Float) -> [Float] {
        [v]
    }

    /// Port de `Keyframe.colorValue` — construit `{A, R, G, B}` depuis un ARGB packé sur 32 bits
    /// comme `android.graphics.Color`/`Paint.setColor(int)` (bit 24-31 = alpha, 16-23 = rouge,
    /// 8-15 = vert, 0-7 = bleu). PAS le format `UIColor`/`CGColor` d'iOS — reproduit tel quel car
    /// c'est ce que `AnimationObjectData.addColorKeyframe(long, int argb)` (module 8, pas encore
    /// porté) recevra en entrée, fidèle au contrat Android.
    static func colorValue(argb: UInt32) -> [Float] {
        [
            Float((argb >> 24) & 0xFF),
            Float((argb >> 16) & 0xFF),
            Float((argb >> 8) & 0xFF),
            Float(argb & 0xFF),
        ]
    }

    /// Port de `Keyframe.floatArrayToArgb` — reconstitue un ARGB packé depuis `{A, R, G, B}`,
    /// chaque canal saturé dans `[0, 255]` avant arrondi (`Math.round(Math.max(0, Math.min(255,
    /// c[i])))`, reproduit avec `.rounded()` + `clamped`).
    static func floatArrayToArgb(_ c: [Float]) -> UInt32 {
        func clampedChannel(_ v: Float) -> UInt32 {
            UInt32(max(0, min(255, v.rounded())))
        }
        let a = clampedChannel(c[0])
        let r = clampedChannel(c[1])
        let g = clampedChannel(c[2])
        let b = clampedChannel(c[3])
        return (a << 24) | (r << 16) | (g << 8) | b
    }
}
