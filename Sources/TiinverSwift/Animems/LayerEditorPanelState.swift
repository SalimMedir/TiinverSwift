import Foundation

/// Port de la logique d'état de `android/views/LayerEditorPanel.java` (panneau d'édition d'un
/// calque, ouvert par appui long sur une piste de la timeline) — SANS la construction de vue
/// Android (`LinearLayout`/`SeekBar` programmatiques, non portables 1:1 vers SwiftUI). La vue
/// SwiftUI elle-même reste différée : `bindToLayer` dépend de la sélection courante dans
/// `TimelineView` (item 4 du plan module 8, pas encore porté) — construire le panneau maintenant
/// serait invérifiable tant que la sélection de calque n'existe pas. Ce qui suit EST directement
/// réutilisable dès que ce contexte existera.
struct LayerEditorPanelState: Equatable {
    var opacity: Float = 1.0
    var tintColor: UInt32 = 0
    var tintStrength: Float = 0.5
    var cornerRadius: Float = 0
    var feather: Float = 0

    /// Port de `PALETTE` — `0` = "pas de teinte" (première entrée), reste = ARGB opaques.
    static let palette: [UInt32] = [
        0,
        0xFFFF_FFFF, 0xFF00_0000,
        0xFFE5_3935, 0xFFE9_1E63, 0xFF9C_27B0,
        0xFF3F_51B5, 0xFF21_96F3, 0xFF00_BCD4,
        0xFF4C_AF50, 0xFF8B_C34A,
        0xFFFF_EB3B, 0xFFFF_C107, 0xFFFF_9800,
        0xFFFF_5722, 0xFF79_5548, 0xFF60_7D8B,
    ]

    /// Port de `bindToLayer` — dérive les valeurs initiales du panneau à partir du calque
    /// sélectionné. Priorité : dernière `Transform` (`opacity`/`cornerRadius`/`feather`) si elle
    /// existe, sinon repli sur les propriétés de forme (`shapeOpacity`/`shapeCornerRadius`) ; le
    /// feather d'un masque sans valeur de Transform retombe sur `maskFeather` — reproduit à
    /// l'identique, y compris l'ordre des priorités qui diffère entre `opacity` (jamais de repli
    /// mask) et `feather` (repli mask uniquement si `Transform.feather == 0`).
    static func bound(to data: AnimationObjectData) -> LayerEditorPanelState {
        var state = LayerEditorPanelState()

        let lastTransform = data.transforms.last
        if let lastTransform {
            state.opacity = lastTransform.opacity
            state.cornerRadius = lastTransform.cornerRadius
        } else {
            state.opacity = data.shapeOpacity
            state.cornerRadius = data.isShape ? data.shapeCornerRadius : 0
        }

        state.feather = lastTransform?.feather ?? 0
        if state.feather == 0, data.isMask {
            state.feather = data.maskFeather
        }

        state.tintColor = 0
        state.tintStrength = 0.5
        return state
    }

    /// Port de `refreshCornerRowVisibility` — l'arrondi n'a de sens que pour ces 4 types.
    static func showsCornerRadius(for objectType: AnimationObjectData.ObjectType?) -> Bool {
        switch objectType {
        case .bitmap, .shapeRect, .text, .sticker: return true
        default: return false
        }
    }
}
