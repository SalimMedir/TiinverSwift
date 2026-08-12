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
    private(set) var original: MaskPreviewEditorPanelState?

    /// Port de `init(type:offsetX:offsetY:scale:mirrorGap:inv:opa:feath:)`.
    static func initial(
        type: MaskType, offsetX: Float = 0, offsetY: Float = 0, scale: Float = 1,
        mirrorGap: Float = 0.06, inverted: Bool = false, opacity: Float = 1, feather: Float = 0
    ) -> MaskPreviewEditorPanelState {
        var state = MaskPreviewEditorPanelState(
            maskType: type, inverted: inverted, opacity: opacity, feather: feather,
            offsetX: offsetX, offsetY: offsetY, scale: scale, mirrorGap: mirrorGap)
        state.original = state
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
    mutating func cancel() {
        guard let original else { return }
        let savedOriginal = original
        self = original
        self.original = savedOriginal
    }

    /// Port de `getMaskLabel`.
    var label: String {
        guard let maskType else { return "Mask" }
        return "Mask — \(maskType.displayName)"
    }
}
