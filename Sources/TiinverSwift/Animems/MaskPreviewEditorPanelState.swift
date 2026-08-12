import Foundation

/// Port de la logique d'état de `android/mask/MaskPreviewEditorPanel.java` — panneau compact
/// d'édition d'un masque déjà appliqué (opacité, flou, inversion, écart miroir), le
/// zoom/déplacement se faisant par geste direct sur le canvas via
/// `MaskEditController.OnMaskGestureListener` (voir `AnimemesGestureController.swift`, méthodes de
/// masque explicitement différées). Vue SwiftUI elle-même différée pour la même raison que
/// `LayerEditorPanelState` (dépend de la sélection de calque courante, pas encore portée).
///
/// **Non porté délibérément** : `buildFinalBitmapStatic`/`applyOpacity` (réécriture manuelle du
/// canal alpha du bitmap de masque pour appliquer l'opacité AVANT compositing) — superflu dans
/// l'architecture Swift : `LayerRenderer.composite` applique déjà l'opacité une seule fois via
/// `context.setAlpha` au moment du dessin du calque masqué (voir tête de fichier
/// `LayerRenderer.swift`), donc appliquer l'opacité une seconde fois en pré-traitant les pixels du
/// masque la re-appliquerait en double. Confirmé en lisant `LayerRenderer.composite` : le masque
/// est dessiné via `context.draw(maskImage, in:)` DANS le bloc où l'alpha du contexte est déjà
/// celui du calque — l'architecture Core Graphics rend cette étape Android obsolète, pas
/// simplement différée.
struct MaskPreviewEditorPanelState: Equatable {
    static let maxFeatherPx: Float = 80
    static let maxFeatherPreview: Float = 30

    /// Les seules valeurs que `onCancelClicked` restaure (`original*` côté Android) — un struct
    /// dédié plutôt qu'un `MaskPreviewEditorPanelState?` imbriqué : un `struct` Swift ne peut pas
    /// contenir une propriété stockée de son PROPRE type (taille non déterminable à la
    /// compilation, contrairement à une classe où seul un pointeur serait stocké) — trouvé par le
    /// premier build réel couvrant ce fichier (`error: value type 'MaskPreviewEditorPanelState'
    /// cannot have a stored property that recursively contains it`, voir "Erreurs rencontrées et
    /// résolues"). Ce sous-ensemble de champs (sans `original` lui-même) suffit : Android ne
    /// restaure jamais qu'un instantané PLAT des mêmes 8 valeurs, jamais un snapshot-de-snapshot.
    struct Snapshot: Equatable {
        var maskType: MaskType?
        var inverted = false
        var opacity: Float = 1.0
        var feather: Float = 0
        var offsetX: Float = 0
        var offsetY: Float = 0
        var scale: Float = 1
        var mirrorGap: Float = 0.06
    }

    var maskType: MaskType?
    var inverted = false
    var opacity: Float = 1.0
    var feather: Float = 0
    var offsetX: Float = 0
    var offsetY: Float = 0
    var scale: Float = 1
    var mirrorGap: Float = 0.06

    /// Snapshot pris à `init(...)`, restauré par `onCancelClicked` — port de
    /// `original*`/`onCancelClicked`.
    private(set) var original: Snapshot?

    private var currentSnapshot: Snapshot {
        Snapshot(
            maskType: maskType, inverted: inverted, opacity: opacity, feather: feather,
            offsetX: offsetX, offsetY: offsetY, scale: scale, mirrorGap: mirrorGap)
    }

    /// Port de `init(type:offsetX:offsetY:scale:mirrorGap:inv:opa:feath:)`.
    static func initial(
        type: MaskType, offsetX: Float = 0, offsetY: Float = 0, scale: Float = 1,
        mirrorGap: Float = 0.06, inverted: Bool = false, opacity: Float = 1, feather: Float = 0
    ) -> MaskPreviewEditorPanelState {
        var state = MaskPreviewEditorPanelState(
            maskType: type, inverted: inverted, opacity: opacity, feather: feather,
            offsetX: offsetX, offsetY: offsetY, scale: scale, mirrorGap: mirrorGap)
        state.original = state.currentSnapshot
        return state
    }

    /// Port de `onGestureUpdate` — poussé par le geste direct sur le canvas (drag = offset, pinch =
    /// scale).
    mutating func applyGestureUpdate(offsetX: Float, offsetY: Float, scale: Float) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }

    /// Port de `onCancelClicked` — restaure le snapshot `original` (le masque lui-même,
    /// `maskType`, n'est jamais modifiable dans ce panneau donc pas besoin d'un cas particulier).
    /// `original` lui-même n'a plus besoin d'être ré-assigné après restauration (contrairement au
    /// premier jet) : `Snapshot` étant un type PLAT distinct, il n'est jamais écrasé par cette
    /// méthode — annuler plusieurs fois de suite reste possible sans effet de bord.
    mutating func cancel() {
        guard let original else { return }
        maskType = original.maskType
        inverted = original.inverted
        opacity = original.opacity
        feather = original.feather
        offsetX = original.offsetX
        offsetY = original.offsetY
        scale = original.scale
        mirrorGap = original.mirrorGap
    }

    /// Port de `getMaskLabel`.
    var label: String {
        guard let maskType else { return "Mask" }
        return "Mask — \(maskType.displayName)"
    }
}
