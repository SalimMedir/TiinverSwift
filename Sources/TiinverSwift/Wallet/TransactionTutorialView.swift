import SwiftUI
import WebKit

/// Port de `wallet/TransactionTutorialActivity.java` (51 lignes, entier, 2026-08-18 P2) — 2 vidéos
/// YouTube intégrées (retrait/achat), atteint depuis `SelectAmountActivity`/`PurchaseActivity`
/// (superseded, voir `CoinStoreManager.swift`) ET `WithdrawActivity` (toujours actif, voir
/// `WithdrawView.swift`) — même ID vidéo YouTube en dur des deux côtés, reproduits tels quels.
struct TransactionTutorialView: View {
    private static let withdrawVideoID = "C_F2V6qTaGc"
    private static let purchaseVideoID = "fYxdI6DVlac"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comment retirer").font(.headline)
                    YouTubeEmbedView(videoID: Self.withdrawVideoID)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comment acheter des pièces").font(.headline)
                    YouTubeEmbedView(videoID: Self.purchaseVideoID)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .navigationTitle("Tutoriel")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Port de `YouTubePlayerView` (bibliothèque `androidyoutubeplayer`, aucun équivalent SDK natif
/// iOS) — même approche que `InAppWebView`/`PoliticaDemandView.swift` : lecteur intégré YouTube via
/// `WKWebView` chargeant l'URL `embed` officielle, plutôt qu'une dépendance tierce pour un besoin
/// aussi ponctuel (2 vidéos statiques).
private struct YouTubeEmbedView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = URL(string: "https://www.youtube.com/embed/\(videoID)") else { return }
        webView.load(URLRequest(url: url))
    }
}
