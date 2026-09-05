import SwiftUI
import WebKit

/// Port de `Authentification/PoliticaDemand.java` (position 0, premier écran affiché par
/// `MainActivity.onCreate` → `onArticleSelected(0,null)`).
///
/// `WebAppInterface`/`JavascriptInterface` de l'original est un pont JS→Android déclaré mais
/// jamais attaché à une `WebView` dans ce fichier (`webView.addJavascriptInterface` absent) —
/// code mort, non porté.
struct PoliticaDemandView: View {
    @State private var webViewURL: URL?
    @State private var showWebView = false

    var onAccept: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("auth_privacy_intro", comment: "Texte d'introduction politique/conditions"))
                .multilineTextAlignment(.center)

            HStack {
                Button(NSLocalizedString("auth_privacy_policy", comment: "Lien politique de confidentialité")) { // R.string.privacypolicies
                    open("https://tiinver.com/privacy_policy.html")
                }
                Button(NSLocalizedString("auth_terms_of_use", comment: "Lien conditions d'utilisation")) { // R.string.termsofuse
                    open("https://tiinver.com/terms_conditions.html")
                }
            }
            .font(.footnote)

            Button(NSLocalizedString("auth_accept", comment: "Bouton accepter"), action: onAccept) // butAcceptarPolitica → position 1 (Onboarding)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .sheet(isPresented: $showWebView) {
            if let webViewURL {
                InAppWebView(url: webViewURL)
            }
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webViewURL = url
        showWebView = true
    }
}

/// Port de `MyWebView.java` (Activity plein écran hébergeant une `WebView`) — reproduit ici
/// comme une feuille modale plutôt qu'un écran séparé, `MyWebView.java` lui-même pas lu en
/// détail (usage trivial : charger une URL statique). Rendu `internal` le 2026-08-20
/// (MIGRATION_PARITY_AUDIT_V3.md V3-F-129, Phase B P1) pour être réutilisé par
/// `Settings/SettingSubViews.swift` (`SettingAboutView`) plutôt que de dupliquer ce wrapper trivial.
struct InAppWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(URLRequest(url: url))
    }
}
