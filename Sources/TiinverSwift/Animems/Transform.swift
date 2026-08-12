import CoreGraphics
import Foundation

/// Port de `core/Transform.java` — état d'un calque à UNE frame précise (matrice, opacité,
/// teinte ARGB, arrondi, flou de bord).
///
/// **Décision d'architecture (module 8, voir journal `MIGRATION_PROGRESS.md`)** : Android stocke
/// DEUX représentations de la matrice — `Matrix` (Canvas, aperçu CPU) et `glMatrix` (`float[16]`,
/// pipeline GLSL de `MP4Encoder`, export GPU). Confirmé en lisant `MemesView2.java`
/// (`android/memes/MemesView2.java`) que la compositing des calques (masques, teinte, flou de
/// bord) n'utilise QUE des primitives Core Graphics-portables : `PorterDuff.Mode.DST_IN`
/// (masquage), `SRC_ATOP` via `PorterDuffColorFilter` (teinte), `CLEAR` (reset) — les 3 seuls
/// modes de fusion réellement utilisés dans tout le fichier (grep confirmé), qui correspondent
/// EXACTEMENT à `CGBlendMode.destinationIn`/`.sourceAtop`/`.clear`. **Donc Core Graphics seul
/// (`CGContext`) suffit pour la compositing des calques, aperçu ET export** (en dessinant chaque
/// frame d'export dans un `CGContext` adossé à un `CVPixelBuffer` avant `AVAssetWriter`, un seul
/// chemin de rendu partagé aperçu+export — encore plus direct que la recommandation
/// `AVVideoCompositing`+MetalPetal du rapport `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.1, qui
/// supposait Metal nécessaire pour ce niveau ; MetalPetal reste pertinent pour d'autres usages
/// (filtres caméra du module 7, éventuels effets GPU futurs), pas prouvé indispensable ici). Une
/// seule représentation `CGAffineTransform` suffit donc côté Swift — pas de `glMatrix`/`float[16]`
/// équivalent tant que l'export n'a pas besoin d'un pipeline GPU.
struct Transform {
    /// 9 éléments, ordre `android.graphics.Matrix.getValues()` :
    /// `[MSCALE_X, MSKEW_X, MTRANS_X, MSKEW_Y, MSCALE_Y, MTRANS_Y, MPERSP_0, MPERSP_1, MPERSP_2]`
    /// — même représentation brute que les keyframes `PROP_MATRIX` (`Keyframe.swift`), pas de
    /// conversion `CGAffineTransform` prématurée qui casserait la correspondance avec
    /// `KeyframeTrack`.
    var matrixValues: [Float]

    var frameIndex: Int = 0
    var cumulativeRotation: Float = 0
    var duration: Float = 0

    private var _feather: Float = 0
    var feather: Float {
        get { _feather }
        set { _feather = newValue }
    }

    private var _opacity: Float = 1.0
    /// Port de `setOpacity` — clampé `[0, 1]`.
    var opacity: Float {
        get { _opacity }
        set { _opacity = max(0, min(1, newValue)) }
    }

    /// ARGB packé (même format que `Keyframe.colorValue` — bits 24/16/8/0), `0` = pas de teinte.
    var color: UInt32 = 0

    private var _cornerRadius: Float = 0
    /// Port de `setCornerRadius` — clampé `>= 0`.
    var cornerRadius: Float {
        get { _cornerRadius }
        set { _cornerRadius = max(0, newValue) }
    }

    init(matrixValues: [Float] = Transform.identityValues) {
        self.matrixValues = matrixValues
    }

    static let identityValues: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

    /// Conversion vers `CGAffineTransform` pour le rendu Core Graphics — voir mapping d'ordre
    /// documenté dans `Keyframe.swift`/tête de fichier : Android `Matrix.getValues()` est
    /// `[a, c, tx, b, d, ty, …]` (indices 0,1,2,3,4,5) alors que `CGAffineTransform` est
    /// `(a, b, c, d, tx, ty)` — PAS le même ordre de champs malgré la ressemblance de nom.
    var cgAffineTransform: CGAffineTransform {
        guard matrixValues.count >= 6 else { return .identity }
        return CGAffineTransform(
            a: CGFloat(matrixValues[0]), b: CGFloat(matrixValues[3]),
            c: CGFloat(matrixValues[1]), d: CGFloat(matrixValues[4]),
            tx: CGFloat(matrixValues[2]), ty: CGFloat(matrixValues[5])
        )
    }

    /// Port de `setMatrixValues(float[])`/`setMatrix(Matrix)` — construit les 9 valeurs Android
    /// depuis un `CGAffineTransform` (sens inverse de `cgAffineTransform`).
    static func matrixValues(from transform: CGAffineTransform) -> [Float] {
        [
            Float(transform.a), Float(transform.c), Float(transform.tx),
            Float(transform.b), Float(transform.d), Float(transform.ty),
            0, 0, 1,
        ]
    }
}
