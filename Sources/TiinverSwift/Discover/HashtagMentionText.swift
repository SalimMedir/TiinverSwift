import SwiftUI

/// Port de `view/textview/MentionTextView.java` — rend les `#hashtags`/`@mentions` d'un texte
/// cliquables, chacun ouvrant la recherche universelle pré-remplie (query + onglet dérivés du
/// token), fidèle à `TokenClickableSpan.onClick` (`MentionTextView.java:184-196`) →
/// `RechercheTiinver` (`autoQuery`/`autoTab`, `RechercheTiinver.java:156-181`).
///
/// **Ajouté le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-099, Phase B P1)** — fonctionnalité
/// jamais portée jusqu'ici (grep exhaustif `MentionTextView`/`onHashtagTap`/`clickableSpan` : zéro
/// résultat avant ce correctif), alors qu'Android la câble aux 2 seuls endroits où une légende de
/// post s'affiche (`VideoViewHolder.java:636`, `CustomCardView.java:142` — les 2 confirmés par
/// grep exhaustif, tous les 2 dans la même fiche plein écran, jamais dans la grille).
///
/// SwiftUI n'expose pas d'équivalent direct à `ClickableSpan` (tap par SOUS-plage de texte au sein
/// d'un même `Text`). Implémenté via `AttributedString` + attribut `.link` (schéma personnalisé
/// `tiinver-token://<tab>?q=<query>`) capturé par `.environment(\.openURL)` — la seule mécanique
/// SwiftUI native permettant un tap par plage à l'intérieur d'un bloc de texte unique (un
/// `NavigationLink`/geste par span n'existe pas pour `Text`).
///
/// **Nécessite une vérification sur device/simulateur réel** (API `AttributedString.link` +
/// `.environment(\.openURL)` jamais exercée dans cette session, conforme à la consigne de ne pas
/// déclencher de test Appetize) — le mécanisme est standard/documenté (WWDC21 "What's new in
/// Foundation"), mais aucune capture d'écran ni exécution ne l'a confirmé ici.
struct HashtagMentionText: View {
    let text: String
    var font: Font = .subheadline
    var baseColor: Color = .white
    /// Port de `TokenClickableSpan.onClick` — `query` = texte SANS préfixe (`searchQuery`),
    /// `tab` = `.hashtags`/`.users` (`tabTarget`), exactement les 2 seules valeurs qu'Android
    /// produit ici (jamais `.all`/`.posts`).
    var onToken: (_ query: String, _ tab: SearchTab) -> Void

    private static let scheme = "tiinver-token"

    /// Port de `HASHTAG_PATTERN`/`MENTION_PATTERN` (`MentionTextView.java:52-60`) — MÊMES classes
    /// de caractères (support accents/latin étendu pour les hashtags, `.`/`-`/`_` pour les
    /// mentions), traduites telles quelles en `NSRegularExpression`.
    private static let hashtagRegex = try? NSRegularExpression(pattern: "#([\\w\\u00C0-\\u024F]+)")
    private static let mentionRegex = try? NSRegularExpression(pattern: "@([\\w.\\-]+)")

    var body: some View {
        Text(Self.attributed(text, baseColor: baseColor))
            .font(font)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == Self.scheme,
                    let tab = SearchTab(rawValue: url.host ?? ""),
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "q" })?.value
                else { return .discarded }
                onToken(query, tab)
                return .handled
            })
    }

    private static func attributed(_ text: String, baseColor: Color) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = baseColor

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        // Port de `TokenClickableSpan` couleur hashtag — 0xFF1DA1F2 (bleu Twitter-like), jamais
        // personnalisée par un appelant (`setHashtagColor` : zéro appelant côté Android, grep
        // exhaustif), donc la seule valeur réelle à reproduire.
        if let hashtagRegex {
            for match in hashtagRegex.matches(in: text, range: nsRange) {
                apply(match, in: text, to: &attributed, tab: .hashtags, color: Color(red: 0x1D / 255, green: 0xA1 / 255, blue: 0xF2 / 255))
            }
        }
        // Couleur mention — 0xFFE91E63 (rose vif), jamais personnalisée (`setMentionColor` : zéro
        // appelant).
        if let mentionRegex {
            for match in mentionRegex.matches(in: text, range: nsRange) {
                apply(match, in: text, to: &attributed, tab: .users, color: Color(red: 0xE9 / 255, green: 0x1E / 255, blue: 0x63 / 255))
            }
        }
        return attributed
    }

    private static func apply(_ match: NSTextCheckingResult, in text: String, to attributed: inout AttributedString, tab: SearchTab, color: Color) {
        guard match.numberOfRanges > 1,
            let tokenRange = Range(match.range, in: text),
            let groupRange = Range(match.range(at: 1), in: text),
            let attrRange = Range(tokenRange, in: attributed)
        else { return }
        let query = String(text[groupRange])
        var components = URLComponents()
        components.scheme = scheme
        components.host = tab.rawValue
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        attributed[attrRange].link = components.url
        attributed[attrRange].foregroundColor = color
        // Port de `underlineEnabled = false` (jamais activé par `setUnderlineEnabled`, zéro
        // appelant côté Android) — aucun soulignement, contrairement au style `.link` par défaut
        // de SwiftUI qui souligne automatiquement ; neutralisé explicitement.
        attributed[attrRange].underlineStyle = nil
    }
}
