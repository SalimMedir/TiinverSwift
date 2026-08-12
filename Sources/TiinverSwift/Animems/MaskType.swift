/// Port de `engine/mask/MaskType.java` — types de masque disponibles, rendus en bitmap ARGB
/// (côté Swift : `CGImage`, voir `MaskFactory.swift`).
enum MaskType {
    case circle
    case square
    case rectangle
    case horizontal
    case mirror
    case heart
    case star

    /// Port de `MaskPreviewEditorPanel.getMaskLabel`'s switch labels.
    var displayName: String {
        switch self {
        case .circle: return "Circle"
        case .square: return "Square"
        case .rectangle: return "Rectangle"
        case .horizontal: return "Horizontal"
        case .mirror: return "Mirror"
        case .heart: return "Heart"
        case .star: return "Star"
        }
    }
}
