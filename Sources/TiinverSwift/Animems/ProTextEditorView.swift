import SwiftUI
import UIKit

/// Port de la VUE de `android/views/ProTextEditorView.java` au-dessus de l'état pur déjà porté
/// (`ProTextEditorState.swift` — voir sa doc pour le contexte complet). **Ajouté le 2026-08-26
/// (MIGRATION_PARITY_AUDIT_V5.md V5-F-089, Phase B P1)** : avant ce correctif, le bouton texte de
/// `AnimemesEditorView` (`ic_text`/`btn_text`) ouvrait une simple alerte système `TextField`, sans
/// aucune des 6 options réelles côté Android (couleur texte, couleur fond, police, taille,
/// alignement, fond+arrondi — `TAB_TEXT_COLOR`...`TAB_BG_SHAPE`).
///
/// **Portée assumée** : Android ouvre cet éditeur en PLEIN ÉCRAN par-dessus le canevas avec un
/// scrim (`ProTextEditorView extends FrameLayout`, montré via `AnimemesCompound`) — reproduit ici
/// via `fullScreenCover`. Palette de couleurs/police/tabs fidèles à `PALETTE`/`FONT_NAME`/
/// `typefaces` (`ProTextEditorState`/`ProTextFont`, déjà portés). Layout des tabs/panneaux
/// reconstruit en SwiftUI idiomatique plutôt que pixel-exact (mêmes 6 réglages atteignables, pas
/// le même moteur de vue `RecyclerView`/`LinearLayout` — cohérent avec le reste du portage
/// Animems : comportement/options reproduits, pas la hiérarchie de vues Android bit-exacte).
struct ProTextEditorView: View {
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @State private var style = ProTextEditorState()
    @State private var activeTab: Tab = .textColor
    @FocusState private var isFocused: Bool

    /// Port de `etLp = new FrameLayout.LayoutParams((int) dp(300), WRAP)` — l'`EditText` Android a
    /// une largeur FIXE de 300dp (PAS `WRAP_CONTENT`), quelle que soit la longueur du texte tapé ;
    /// seule la hauteur s'ajuste au contenu. Reproduit à l'identique ici.
    private static let bubbleWidth: CGFloat = 300

    enum Tab: CaseIterable {
        case textColor, bgColor, font, size, align, bgShape

        var icon: String {
            switch self {
            case .textColor: return "paintpalette"
            case .bgColor: return "paintbrush.pointed"
            case .font: return "textformat"
            case .size: return "textformat.size"
            case .align: return "text.alignleft"
            case .bgShape: return "square.dashed"
            }
        }

        var label: String {
            switch self {
            case .textColor: return "Texte"
            case .bgColor: return "Fond"
            case .font: return "Police"
            case .size: return "Taille"
            case .align: return "Align"
            case .bgShape: return "Forme"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                textBubble
                Spacer()
                bottomToolbar
            }
        }
        .onAppear { isFocused = true }
    }

    // MARK: - Barre du haut (✕ / ✓, port de `buildTopBar`)

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.headline.bold())
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                    .frame(width: 44, height: 40)
                    .background(Circle().fill(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.13)))
            }
            Spacer()
            Button(action: confirm) {
                Image(systemName: "checkmark")
                    .font(.headline.bold())
                    .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                    .frame(width: 44, height: 40)
                    .background(Circle().fill(Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.13)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Zone de texte (port de `makeEditText`/`applyBackground`, aperçu en direct)

    private var textBubble: some View {
        TextField("Tapez votre texte…", text: $text, axis: .vertical)
            .focused($isFocused)
            .font(style.font.font(size: style.textSizeSp))
            .foregroundColor(Self.color(argb: style.textColor))
            .tint(Self.color(argb: style.textColor))
            .multilineTextAlignment(style.alignment)
            .padding(.horizontal, style.bgEnabled ? 20 : 16)
            .padding(.vertical, 14)
            .frame(width: Self.bubbleWidth)
            .background(bubbleBackground)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if style.bgEnabled {
            RoundedRectangle(cornerRadius: style.cornerDp)
                .fill(Self.color(argb: style.bgColor != 0 ? style.bgColor : ProTextEditorState.autoBackgroundColor(for: style.textColor)))
        }
    }

    // MARK: - Barre du bas (panneau actif + tabs, port de `toolbar`/`tabBarLayout`)

    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            panel.frame(height: 68)
            Divider().overlay(Color.white.opacity(0.15))
            tabBar
        }
        .background(Color(white: 0.07).opacity(0.96))
    }

    @ViewBuilder
    private var panel: some View {
        switch activeTab {
        case .textColor: colorPicker(bgMode: false)
        case .bgColor: colorPicker(bgMode: true)
        case .font: fontPicker
        case .size: sizePanel
        case .align: alignPanel
        case .bgShape: backgroundShapePanel
        }
    }

    /// Port de `ColorAdapter`/`colorRecycler` — 16 couleurs (`PALETTE`), pas de pastille
    /// "arc-en-ciel" additionnelle (celle-ci sélectionnait juste la couleur COURANTE côté Android,
    /// redondant avec la sélection déjà visible sur la pastille active).
    private func colorPicker(bgMode: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ProTextEditorState.palette, id: \.self) { argb in
                    let selected = bgMode ? (style.bgEnabled && style.bgColor == argb) : style.textColor == argb
                    Button {
                        if bgMode {
                            style.bgColor = argb
                            style.bgEnabled = true
                        } else {
                            style.textColor = argb
                        }
                    } label: {
                        Circle()
                            .fill(Self.color(argb: argb))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(selected ? Color.white : Color.white.opacity(0.25), lineWidth: selected ? 3 : 1))
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    /// Port de `FontAdapter`/`fontRecycler` — 7 `ProTextFont`.
    private var fontPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProTextFont.allCases, id: \.self) { font in
                    let selected = style.font == font
                    Button { style.font = font } label: {
                        VStack(spacing: 2) {
                            Text("Aa").font(font.font(size: 18))
                            Text(font.label).font(.system(size: 8))
                        }
                        .foregroundColor(selected ? .accentColor : .white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.08)))
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    /// Port de `buildSizePanel` (`SeekBar` 10...90sp).
    private var sizePanel: some View {
        HStack(spacing: 10) {
            Text("A").font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
            Slider(value: $style.textSizeSp, in: 10...90)
            Text("A").font(.system(size: 22)).foregroundColor(.white)
            Text("\(Int(style.textSizeSp))")
                .font(.system(size: 12)).foregroundColor(.accentColor).frame(minWidth: 30)
        }
        .padding(.horizontal, 16)
    }

    /// Port de `buildAlignPanel` — 3 boutons gauche/centre/droite.
    private var alignPanel: some View {
        HStack(spacing: 8) {
            alignButton(.leading, icon: "text.alignleft", label: "Gauche")
            alignButton(.center, icon: "text.aligncenter", label: "Centre")
            alignButton(.trailing, icon: "text.alignright", label: "Droite")
        }
        .padding(.horizontal, 14)
    }

    private func alignButton(_ alignment: TextAlignment, icon: String, label: String) -> some View {
        let selected = style.alignment == alignment
        return Button { style.alignment = alignment } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(label).font(.system(size: 9))
            }
            .foregroundColor(selected ? .accentColor : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.08)))
        }
    }

    /// Port de `buildBgShapePanel` — toggle fond ON/OFF + `SeekBar` d'arrondi 0...60dp.
    private var backgroundShapePanel: some View {
        HStack(spacing: 10) {
            Button {
                style.bgEnabled.toggle()
            } label: {
                Text(style.bgEnabled ? "BG ON" : "BG OFF")
                    .font(.system(size: 11))
                    .foregroundColor(style.bgEnabled ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(style.bgEnabled ? Color.accentColor : Color.white.opacity(0.15)))
            }
            .frame(width: 62)
            Image(systemName: "square").foregroundColor(.white.opacity(0.5)).font(.system(size: 14))
            Slider(value: $style.cornerDp, in: 0...60)
            Image(systemName: "circle").foregroundColor(.white.opacity(0.5)).font(.system(size: 14))
        }
        .padding(.horizontal, 14)
    }

    /// Port de `buildTabBar`.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button { activeTab = tab } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                        Text(tab.label).font(.system(size: 8))
                    }
                    .foregroundColor(activeTab == tab ? .accentColor : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Confirmation / rendu bitmap (port de `confirmText`/`renderBitmap`)

    private func confirm() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Port de `confirmText()` : texte vide → équivalent d'un `dismiss()`, pas d'ajout.
        guard !trimmed.isEmpty, let image = Self.renderBitmap(text: trimmed, style: style) else {
            onCancel()
            return
        }
        onConfirm(image)
    }

    /// Port de `ProTextEditorView.renderBitmap()` (`editText.draw(new Canvas(b))`, capture de la
    /// vue déjà stylée à l'écran). Un `TextField` SwiftUI n'expose pas d'équivalent direct — le
    /// même rendu est reconstruit ici depuis zéro via `NSAttributedString` dans un
    /// `UIGraphicsImageRenderer` cadré à `scale = 1` (pixel = point, même convention que
    /// `LayerRenderer`/`ShapeFactory` : `bmp.width`/`height` réutilisés tels quels comme taille en
    /// points au rendu — un rendu à l'échelle de l'écran [2x/3x] romprait cette convention).
    private static func renderBitmap(text: String, style: ProTextEditorState) -> UIImage? {
        let font = style.font.uiFont(size: style.textSizeSp)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = nsAlignment(style.alignment)
        paragraphStyle.lineBreakMode = .byWordWrapping
        let textColor = UIColor(cgColor: LayerRenderer.cgColor(argb: style.textColor))
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: textColor, .paragraphStyle: paragraphStyle,
        ])

        let hPad: CGFloat = style.bgEnabled ? 20 : 16
        let vPad: CGFloat = 14
        let contentWidth = bubbleWidth - hPad * 2
        let measured = attributed.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        let contentHeight = max(1, measured.height.rounded(.up))
        let totalSize = CGSize(width: bubbleWidth, height: contentHeight + vPad * 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: totalSize, format: format)
        return renderer.image { _ in
            if style.bgEnabled {
                let bgArgb = style.bgColor != 0 ? style.bgColor : ProTextEditorState.autoBackgroundColor(for: style.textColor)
                let bgColor = UIColor(cgColor: LayerRenderer.cgColor(argb: bgArgb))
                let path = UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: totalSize), cornerRadius: style.cornerDp
                )
                bgColor.setFill()
                path.fill()
            }
            attributed.draw(
                with: CGRect(x: hPad, y: vPad, width: contentWidth, height: contentHeight),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            )
        }
    }

    private static func nsAlignment(_ alignment: TextAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    private static func color(argb: UInt32) -> Color {
        Color(cgColor: LayerRenderer.cgColor(argb: argb))
    }
}
