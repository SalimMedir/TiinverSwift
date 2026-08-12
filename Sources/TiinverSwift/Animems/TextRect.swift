import CoreGraphics
import UIKit

/// Port de `android/renderer/TextRect.java` (lu en entier) — rendu du texte découpé par
/// `TextLayoutEngine` dans un `CGContext`.
///
/// **Approximation documentée, pas un portage pixel-exact** : Android mesure les métriques de
/// police via `Paint.FontMetricsInt` (valeurs ENTIÈRES, arrondies par le moteur de rendu Android,
/// sur la police système Android par défaut) ; ici, `UIFont.ascender`/`.descender`/`.leading`
/// (valeurs flottantes, arrondies au point supérieur, sur la police système iOS — PAS la même
/// police que sur Android, aucune tentative de faire correspondre visuellement les deux systèmes
/// n'a de sens). Le comportement observable (retour à la ligne automatique, troncature "...")
/// est reproduit fidèlement ; les dimensions exactes en pixels différeront forcément d'un système
/// de polices à l'autre — même principe déjà appliqué ailleurs dans ce portage (flou "feather",
/// module 8) : comportement reproduit, pas les valeurs internes bit-exactes.
///
/// **Convention de coordonnées `y` = BASELINE** (comme `Canvas.drawText` Android), PAS le coin
/// supérieur-gauche par défaut de `NSString.draw(at:)` — compensé explicitement en remontant de
/// `font.ascender` avant chaque `draw(at:)`. Suppose un `CGContext` Y-vers-le-bas (voir note de
/// `LayerRenderer.swift`).
final class TextRect {
    private let font: UIFont
    private let textColor: UIColor
    private var engine: TextLayoutEngine

    var isDrawIconLastOfText = false
    var icon: UIImage?
    var dp: CGFloat = 1

    init(font: UIFont, textColor: UIColor) {
        self.font = font
        self.textColor = textColor
        self.engine = TextLayoutEngine(charWidth: 0, lineHeight: 0, ascent: 0, descent: 0, leading: 0)
        rebuildEngine()
    }

    /// Port de `rebuildEngine` — reconstruit `TextLayoutEngine` depuis les métriques de `font`.
    /// **Signe du descent inversé entre les deux plateformes** : Android `metrics.descent` est
    /// POSITIF (distance sous la baseline) ; iOS `UIFont.descender` est NÉGATIF (même distance
    /// physique, convention de signe opposée) — `-font.descender` restaure la convention positive
    /// attendue par `TextLayoutEngine` (port fidèle de la sémantique Android, pas de la valeur
    /// brute iOS).
    private func rebuildEngine() {
        let ascentValue = Int((font.ascender).rounded(.up))
        let descentValue = Int((-font.descender).rounded(.up))
        let leadingValue = Int((font.leading).rounded(.up))
        let lineHeightValue = ascentValue + descentValue
        let charWidthValue = Int((("i" as NSString).size(withAttributes: [.font: font]).width).rounded(.up))
        engine = TextLayoutEngine(
            charWidth: charWidthValue, lineHeight: lineHeightValue,
            ascent: ascentValue, descent: descentValue, leading: leadingValue
        )
    }

    /// Port de `prepare(String, int, int)`.
    @discardableResult
    func prepare(text: String, maxWidth: Int, maxHeight: Int) -> Int {
        rebuildEngine()
        return engine.prepare(text: text, maxWidth: maxWidth, maxHeight: maxHeight) { [font] units, start, end in
            guard start < end, end <= units.count else { return 0 }
            let s = String(utf16CodeUnits: Array(units[start..<end]), count: end - start)
            return Int((s as NSString).size(withAttributes: [.font: font]).width.rounded(.up))
        }
    }

    /// Port de `draw(Canvas, float, float)`.
    func draw(in context: CGContext, left: CGFloat, top: CGFloat) {
        guard engine.textHeight > 0 else { return }
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let before = CGFloat(engine.getAscent())
        let after = CGFloat(engine.getDescent() + engine.getLeading())
        var y = top
        let lastLine = engine.lines - 1

        for i in 0..<max(engine.lines, 0) {
            let line: String
            if engine.wasCut, i == lastLine, engine.stops[i] - engine.starts[i] > 100 {
                line = engine.substring(start: engine.starts[i], end: engine.stops[i] - 3) + "..."
            } else {
                line = engine.substring(start: engine.starts[i], end: engine.stops[i])
            }
            y += before
            (line as NSString).draw(
                at: CGPoint(x: left, y: y - font.ascender),
                withAttributes: [.font: font, .foregroundColor: textColor]
            )
            y += after
        }

        if isDrawIconLastOfText, let icon, lastLine >= 0 {
            let lastLineText = engine.substring(start: engine.starts[lastLine], end: engine.stops[lastLine])
            let textWidth = (lastLineText as NSString).size(withAttributes: [.font: font]).width
            let rLeft = (left + textWidth + 5 * dp).rounded()
            let iconRect = CGRect(x: rLeft, y: y - 12 * dp, width: 12 * dp, height: 12 * dp)
            icon.draw(in: iconRect)
        }
    }

    var lines: Int { engine.lines }
    var textHeight: Int { engine.textHeight }
    var wasCut: Bool { engine.wasCut }
    var text: String { engine.sourceString }

    /// Port de `Paint.measureText(String)` (utilisé par `writeText` pour calculer
    /// `mTextWidth`/`bubbleElmentWidth` AVANT tout retour à la ligne — largeur du texte COMPLET
    /// sur une seule ligne, pas la largeur wrappée calculée par `prepare`).
    func measureWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
