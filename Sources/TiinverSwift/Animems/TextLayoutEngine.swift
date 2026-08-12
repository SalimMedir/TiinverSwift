import Foundation

/// Port de `Utils/TextLayoutEngine.java` (lu en entier) — moteur de découpage de texte en lignes,
/// pur (mesure de largeur déléguée à l'appelant via `measurer`, comme l'original délègue à
/// `Paint.measureText` via `TextRect`).
///
/// **Indexation UTF-16, pas `String.Index`** — port fidèle du modèle d'indexation Java
/// (`String.charAt`/`substring(start,end)`/`indexOf`/`lastIndexOf` opèrent sur des UNITÉS UTF-16,
/// pas des points de code Unicode ni des `Character` Swift délimités par grapheme cluster).
/// Reproduit en travaillant sur `[UInt16]` (vue UTF-16 du texte), pas sur `String` directement —
/// un texte contenant des caractères hors du plan de base (emoji notamment) serait démembré à la
/// même limite qu'en Java (paire de substituts UTF-16 coupée en deux unités), comportement
/// IDENTIQUE à l'original, pas une régression de ce portage.
///
/// **Sentinelle `-1` conservée telle quelle** (pas de traduction en `Int?`) pour
/// `indexOf`/`lastIndex` : le code Java compare directement `blank > start`/`hyphen < start` avec
/// `-1` comme valeur "non trouvé" dans l'arithmétique — un `Int?` Swift aurait exigé une
/// reformulation des comparaisons avec un risque réel de dévier subtilement du comportement
/// exact ; la sentinelle `Int` reproduit l'original terme à terme.
final class TextLayoutEngine {
    private static let maxLinesCapacity = 256

    private(set) var starts = [Int](repeating: 0, count: TextLayoutEngine.maxLinesCapacity)
    private(set) var stops = [Int](repeating: 0, count: TextLayoutEngine.maxLinesCapacity)
    private(set) var lines = 0
    private(set) var textHeight = 0
    private(set) var wasCut = false
    private(set) var text: [UInt16] = []
    /// Chaîne d'origine — nécessaire pour reconstruire des sous-chaînes lisibles côté rendu
    /// (`TextRect.draw`), `text` (UTF-16 brut) ne suffisant pas à lui seul en Swift.
    private(set) var sourceString: String = ""

    private let charWidth: Int
    private let lineHeight: Int
    private let leading: Int
    let ascent: Int
    let descent: Int

    init(charWidth: Int, lineHeight: Int, ascent: Int, descent: Int, leading: Int) {
        self.charWidth = charWidth
        self.lineHeight = lineHeight
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
    }

    typealias TextWidthMeasurer = (_ text: [UInt16], _ start: Int, _ end: Int) -> Int

    /// Port de `prepare(String, int, int, TextWidthMeasurer)`.
    @discardableResult
    func prepare(text: String, maxWidth: Int, maxHeight: Int, measurer: TextWidthMeasurer) -> Int {
        lines = 0
        textHeight = 0
        sourceString = text
        self.text = Array(text.utf16)
        wasCut = false

        let length = self.text.count
        let maximumInLine = charWidth > 0 ? maxWidth / charWidth : length
        guard length >= 1 else { return 0 }

        var start = 0
        var stop = min(maximumInLine, length)

        while true {
            while start < length {
                let ch = self.text[start]
                if ch != 0x0A, ch != 0x0D, ch != 0x09, ch != 0x20 { break }
                start += 1
            }

            var o = stop + 1
            while stop < o, stop > start {
                o = stop
                let lowestNL = indexOfNewline(in: self.text, from: start)
                let measuredWidth = measurer(self.text, start, stop)

                if (lowestNL >= start && lowestNL < stop) || measuredWidth > maxWidth {
                    stop -= 1
                    var lowest = lowestNL
                    if lowest < start || lowest > stop {
                        let blank = lastIndex(of: 0x20, in: self.text, upTo: stop)
                        let hyphen = lastIndex(of: 0x2D, in: self.text, upTo: stop)
                        if blank > start, hyphen < start || blank > hyphen {
                            lowest = blank
                        } else if hyphen > start {
                            lowest = hyphen
                        }
                    }
                    if lowest >= start, lowest <= stop {
                        let ch = self.text[stop]
                        if ch != 0x0A, ch != 0x20 { lowest += 1 }
                        stop = lowest
                    }
                    continue
                }
                break
            }

            if start >= stop { break }

            var minus = 0
            if stop < length {
                let ch = self.text[stop - 1]
                if ch == 0x0A || ch == 0x20 { minus = 1 }
            }

            if textHeight + lineHeight > maxHeight {
                wasCut = true
                break
            }

            if lines < Self.maxLinesCapacity {
                starts[lines] = start
                stops[lines] = stop - minus
            }
            lines += 1
            if lines > Self.maxLinesCapacity { wasCut = true; break }

            if textHeight > 0 { textHeight += leading }
            textHeight += lineHeight

            if stop >= length { break }
            start = stop
            stop = length
        }

        return textHeight
    }

    /// Port de `text.indexOf("\n", start)` — retourne `-1` si absent.
    private func indexOfNewline(in text: [UInt16], from start: Int) -> Int {
        guard start >= 0, start < text.count else { return -1 }
        for i in start..<text.count where text[i] == 0x0A { return i }
        return -1
    }

    /// Port de `text.lastIndexOf(charStr, fromIndex)` — retourne `-1` si absent, recherche en
    /// arrière depuis `min(stop, text.count - 1)` inclus.
    private func lastIndex(of char: UInt16, in text: [UInt16], upTo stop: Int) -> Int {
        guard !text.isEmpty else { return -1 }
        let upper = min(stop, text.count - 1)
        guard upper >= 0 else { return -1 }
        for i in stride(from: upper, through: 0, by: -1) where text[i] == char { return i }
        return -1
    }

    /// Extrait la sous-chaîne Swift `[start, end)` en unités UTF-16 — utilisé par `TextRect`
    /// pour le rendu (équivalent de `text.substring(start, end)` Java).
    func substring(start: Int, end: Int) -> String {
        guard start >= 0, end <= text.count, start <= end else { return "" }
        let slice = Array(text[start..<end])
        return String(utf16CodeUnits: slice, count: slice.count)
    }

    func getAscent() -> Int { ascent }
    func getDescent() -> Int { descent }
    func getLeading() -> Int { leading }
}
