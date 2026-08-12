import CoreGraphics

/// Port de l'état de `android/views/ShapePreviewEditorPanel.java` — panneau de configuration
/// affiché AVANT l'ajout d'une forme au canvas (couleur/opacité/arrondi/épaisseur/contour), la
/// forme réelle étant produite par `ShapeFactory.rerender` déjà porté. Construction de vue Android
/// (`LinearLayout`/`SeekBar`/`HorizontalScrollView` programmatiques) non reprise — voir précédent
/// `LayerEditorPanelState`/`MaskPreviewEditorPanelState` (même raison : dépend d'un contexte de
/// sélection pas encore construit en SwiftUI).
struct ShapePreviewEditorPanelState {
    static let palette: [UInt32] = [
        0xFFFF_FFFF, 0xFF00_0000, 0xFFE5_3935, 0xFFE9_1E63, 0xFF9C_27B0,
        0xFF3F_51B5, 0xFF21_96F3, 0xFF00_BCD4, 0xFF4C_AF50, 0xFF8B_C34A,
        0xFFCD_DC39, 0xFFFF_EB3B, 0xFFFF_C107, 0xFFFF_9800, 0xFFFF_5722,
        0xFF79_5548, 0xFF60_7D8B, 0xFF9E_9E9E,
    ]

    /// Port de `init(shapeType:canvasW:canvasH:)` — construit les valeurs par défaut d'une nouvelle
    /// forme, dimensionnées relativement au canvas.
    static func makeDefault(
        shapeType: AnimationObjectData.ObjectType, canvasW: Int, canvasH: Int
    ) -> AnimationObjectData {
        let canvasW = canvasW > 0 ? canvasW : 400
        let canvasH = canvasH > 0 ? canvasH : 600

        let data = AnimationObjectData()
        data.objectType = shapeType
        data.shapeColor = 0xFFFF_FFFF
        data.shapeOpacity = 1.0
        data.shapeCornerRadius = 0
        data.shapeLineThickness = 8
        data.shapeStrokeWidth = 0
        data.visible = true
        data.isBackgroundTransparent = true

        switch shapeType {
        case .shapeRect:
            data.shapeW = max(canvasW / 2, 4)
            data.shapeH = max(canvasH / 6, 4)
        case .shapeCircle:
            let d = max(canvasW / 3, 4)
            data.shapeW = d
            data.shapeH = d
        case .shapeLine:
            fallthrough
        default:
            data.shapeW = max(canvasW / 2, 4)
            data.shapeH = Int(data.shapeLineThickness) + 4
        }
        return data
    }

    /// Port de `refreshRows` — visibilité conditionnelle des contrôles selon le type de forme.
    static func rowVisibility(for type: AnimationObjectData.ObjectType?) -> (
        cornerRadius: Bool, lineThickness: Bool, stroke: Bool
    ) {
        let isRect = type == .shapeRect
        let isLine = type == .shapeLine
        let hasStroke = isRect || type == .shapeCircle
        return (cornerRadius: isRect, lineThickness: isLine, stroke: hasStroke)
    }

    /// Port de `getShapeLabel`.
    static func label(for type: AnimationObjectData.ObjectType?) -> String {
        switch type {
        case .shapeRect: return "Rectangle"
        case .shapeCircle: return "Cercle"
        case .shapeLine: return "Ligne"
        default: return "Forme"
        }
    }
}
