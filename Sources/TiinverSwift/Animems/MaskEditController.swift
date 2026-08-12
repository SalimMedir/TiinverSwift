import CoreGraphics

/// Port de `engine/mask/MaskEditController.java` — protocoles de callback pour l'édition de masque
/// par geste direct sur le canvas (voir `AnimemesGestureController.swift`, méthodes
/// `handleMaskEditTouch`/`maskApplyDrag`/`cummulateMaskTransform`/`startMaskEditMode`/
/// `stopMaskEditMode`, lues en entier mais explicitement NON portées — dépendance manquante ici
/// même que celle documentée dans `MaskPreviewEditorPanelState.swift`).
protocol MaskGestureListener: AnyObject {
    func maskOffsetChanged(offsetX: CGFloat, offsetY: CGFloat)
    func maskScaleChanged(_ scale: CGFloat)
    func maskRotationChanged(_ rotation: CGFloat)
}

protocol MaskEditModeListener: AnyObject {
    func maskEditDidStart(layerId: String, maskType: MaskType)
    func maskEditDidEnd()
    func maskParamsChanged(
        maskType: MaskType, inverted: Bool, opacity: Float, feather: Float,
        offsetX: Float, offsetY: Float, scale: Float, mirrorGap: Float)
}
