import CoreGraphics
import SwiftUI

/// Port de l'état de `android/views/ProTextEditorView.java` (éditeur de texte "pro" façon
/// Instagram/TikTok : couleur texte/fond, police, taille, alignement, fond arrondi).
///
/// **Portée réduite délibérément** : la quasi-totalité du fichier original (~850 des 923 lignes)
/// est de la construction de vue Android pure (`LinearLayout`/`RecyclerView`/`FrameLayout`
/// programmatiques, `ColorAdapter`/`FontAdapter`/`ColorDot`) — sans logique réutilisable au-delà de
/// ce qui est repris ci-dessous.
///
/// **Câblé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-089, Phase B P1)** — jusque-là ce
/// modèle existait mais n'était référencé nulle part (`ProTextEditorView.swift` n'existait pas
/// encore) : `AnimemesEditorState.addText` utilisait une simple alerte `TextField` sans aucune de
/// ces options. `ProTextEditorView.swift` (nouvelle vue SwiftUI, sheet plein écran) consomme
/// maintenant cet état pour reproduire les 6 onglets Android (couleur texte/fond, police, taille,
/// alignement, fond+arrondi) et rastérise le résultat en bitmap au moment de la confirmation,
/// fidèle à `renderBitmap()`/`onTextConfirmed` (voir doc d'`AnimemesEditorState.addStyledText`).
///
/// `darkenFor` n'est PAS reporté ici : identique à `ShapeFactory.darken` (même formule HSV,
/// `V *= 0.45`/`S *= 1.1` au lieu de `V -= 0.25`, mais même mécanisme) — dupliquer serait une
/// simple divergence de constantes, pas une nouvelle logique.
struct ProTextEditorState: Equatable {
    var textColor: UInt32 = 0xFFFF_FFFF
    var bgColor: UInt32 = 0x0000_0000
    var textSizeSp: CGFloat = 36
    var font: ProTextFont = .normal
    var alignment: TextAlignment = .center
    var bgEnabled = false
    var cornerDp: CGFloat = 14

    /// Port de `PALETTE`.
    static let palette: [UInt32] = [
        0xFFFF_FFFF, 0xFF00_0000, 0xFFFF_3B30, 0xFFFF_9500,
        0xFFFF_CC00, 0xFF34_C759, 0xFF00_C7BE, 0xFF00_7AFF,
        0xFF58_56D6, 0xFFAF_52DE, 0xFFFF_2D55, 0xFFFF_6B35,
        0xFF1D_B954, 0xFF1D_A1F2, 0xFFE1_306C, 0xFFFF_C300,
    ]

    /// Port de `darkenFor` — utilisé pour la couleur de fond par défaut quand `bgColor ==
    /// TRANSPARENT` (fond "auto" dérivé de la couleur du texte).
    static func autoBackgroundColor(for textColor: UInt32) -> UInt32 {
        let r = CGFloat((textColor >> 16) & 0xFF) / 255
        let g = CGFloat((textColor >> 8) & 0xFF) / 255
        let b = CGFloat(textColor & 0xFF) / 255
        let color = UIColor(red: r, green: g, blue: b, alpha: 1)

        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        v = max(0, v * 0.45)
        s = min(1, s * 1.1)
        let darkened = UIColor(hue: h, saturation: s, brightness: v, alpha: 200.0 / 255.0)

        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        darkened.getRed(&dr, green: &dg, blue: &db, alpha: &da)
        return (UInt32(da * 255) << 24) | (UInt32(dr * 255) << 16) | (UInt32(dg * 255) << 8) | UInt32(db * 255)
    }
}

/// Port de `FONT_NAME`/`typefaces` — 7 combinaisons police/style. Mapping SF Pro / SF Pro Serif /
/// SF Mono à confirmer visuellement (pas d'équivalent garanti 1:1 avec Sans-Serif/Serif/Mono
/// Android — approximation assumée, cohérente avec le reste du portage : comportement reproduit
/// [7 styles distincts sélectionnables], pas les valeurs de police bit-exactes).
enum ProTextFont: Int, CaseIterable {
    case normal, bold, italic, serif, mono, boldItalic, serifItalic

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .boldItalic: return "Bold·It"
        case .serifItalic: return "Serif·It"
        }
    }

    /// Utilisé pour l'aperçu SwiftUI en direct (`ProTextEditorView`).
    func font(size: CGFloat) -> Font {
        switch self {
        case .normal: return .system(size: size)
        case .bold: return .system(size: size, weight: .bold)
        case .italic: return .system(size: size).italic()
        case .serif: return .system(size: size, design: .serif)
        case .mono: return .system(size: size, design: .monospaced)
        case .boldItalic: return .system(size: size, weight: .bold).italic()
        case .serifItalic: return .system(size: size, design: .serif).italic()
        }
    }

    /// Même mapping que `font(size:)` ci-dessus mais en `UIFont` — nécessaire pour la rastérisation
    /// finale via `CGContext`/`NSAttributedString` (`ProTextEditorView.renderBitmap`, `Font`
    /// SwiftUI n'expose aucune API de dessin Core Graphics directe).
    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .normal: return .systemFont(ofSize: size)
        case .bold: return .boldSystemFont(ofSize: size)
        case .italic: return .italicSystemFont(ofSize: size)
        case .serif: return Self.designed(size: size, design: .serif, bold: false, italic: false)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .boldItalic: return Self.designed(size: size, design: .default, bold: true, italic: true)
        case .serifItalic: return Self.designed(size: size, design: .serif, bold: true, italic: true)
        }
    }

    private static func designed(size: CGFloat, design: UIFontDescriptor.SystemDesign, bold: Bool, italic: Bool) -> UIFont {
        var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .withDesign(design)?.withSize(size) ?? UIFontDescriptor().withSize(size)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let withTraits = descriptor.withSymbolicTraits(traits) { descriptor = withTraits }
        return UIFont(descriptor: descriptor, size: size)
    }
}
