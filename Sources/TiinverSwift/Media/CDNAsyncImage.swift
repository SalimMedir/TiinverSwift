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
        // Corrigé (V3-F-012, FEED-04) : le contournement précédent (`.reloadIgnoringLocalCacheData`
        // inconditionnel) désactivait le cache HTTP pour TOUTE image, y compris les téléchargements
        // réussis — écart réel vs Android (`ChargerImages.java`, `DiskCacheStrategy.ALL` sur TOUS
        // les chargeurs Glide), pas une fidélité voulue. Cache par défaut restauré ici
        // (`request.cachePolicy` non modifié = `.useProtocolCachePolicy`) ; le vrai problème
        // d'origine (une réponse 403 mise en cache AVANT l'ajout du header `Referer` ci-dessus,
        // la clé de cache HTTP standard ne portant pas sur les en-têtes) est traité plus bas de
        // façon ciblée : toute réponse invalide (statut non-2xx OU image indécodable) est
        // explicitement PURGÉE de `URLCache.shared` pour ne jamais rejouer indéfiniment un échec
        // figé, au lieu de désactiver le cache pour tout le monde en permanence.
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                let uiImage = UIImage(data: data)
            else {
                URLCache.shared.removeCachedResponse(for: request)
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            phase = .success(Image(uiImage: uiImage))
        } catch {
            phase = .failure(error)
        }
    }
}
