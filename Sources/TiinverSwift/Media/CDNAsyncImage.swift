import SwiftUI
import UIKit

/// Remplaçant DROP-IN de `AsyncImage` de SwiftUI (mêmes deux signatures d'appel, même
/// comportement observable) — **cause racine réelle confirmée le 2026-08-17 par test réel** :
/// le CDN Tiinver exige un en-tête HTTP `Referer: https://tiinver.com` (port fidèle de
/// `ChargerImages.java`, `.addHeader("Referer", "https://tiinver.com")` — valeur EXACTE reprise
/// du fichier source Android, pas devinée) et rejette silencieusement toute requête sans cet
/// en-tête. `AsyncImage` de SwiftUI utilise `URLSession.shared` en interne SANS AUCUN point
/// d'extension public pour ajouter un en-tête personnalisé — sans ce correctif, CHAQUE image du
/// CDN (avatars, vignettes Feed/Profile/Chat/Notifications/Recherche) restait un placeholder
/// gris en permanence, sur TOUS les écrans de l'app.
struct CDNAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    /// Équivalent de `AsyncImage(url:content:)` (variante "phase").
    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    /// Équivalent de `AsyncImage(url:content:placeholder:)` (variante image/placeholder).
    /// `Content == AnyView` ici : évite d'avoir à reproduire exactement `_ConditionalContent<I,P>`
    /// (type interne de SwiftUI) — coût d'un seul `AnyView` par vue, sans impact perceptible pour
    /// ce cas d'usage (avatars/vignettes).
    init<I: View, P: View>(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == AnyView {
        self.url = url
        self.content = { phase in
            AnyView(Self.build(phase: phase, content: content, placeholder: placeholder))
        }
    }

    @ViewBuilder
    private static func build<I: View, P: View>(phase: AsyncImagePhase, content: (Image) -> I, placeholder: () -> P) -> some View {
        if let image = phase.image {
            content(image)
        } else {
            placeholder()
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { phase = .empty; return }
        var request = URLRequest(url: url)
        // Valeur EXACTE de `ChargerImages.java` — voir commentaire de tête.
        request.setValue("https://tiinver.com", forHTTPHeaderField: "Referer")
        // Défensif (2026-08-17, retest utilisateur signalant le problème encore présent après le
        // correctif ci-dessus) : `URLCache.shared` peut avoir mis en cache une réponse d'ERREUR
        // (403 sans `Referer`) obtenue sur un appareil/simulateur testé AVANT ce correctif — la clé
        // de cache HTTP standard porte sur l'URL, pas sur les en-têtes de la requête, donc rejouer
        // la MÊME URL après coup peut servir l'échec caché au lieu de refaire la requête (désormais
        // correcte). Élimine cette classe d'échec fantôme plutôt que de la diagnostiquer au cas par
        // cas.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let uiImage = UIImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            phase = .success(Image(uiImage: uiImage))
        } catch {
            phase = .failure(error)
        }
    }
}
