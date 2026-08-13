import Foundation

/// Port partiel de `Activity/ui/MainFragment.java` (1966 lignes — hors de portée d'un portage
/// intégral à ce stade). Seule la boucle "charger la page suivante / afficher" est portée ici ;
/// interactions (like/commentaire/partage/double-tap), pagination infinie fine, et le mode
/// "édition"/upload restent à porter avec les modules qui les concernent (18/11/7).
@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [FeedActivity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository = FeedRepository()
    private let pageSize = 10
    private var offset = 0

    func loadInitial() async {
        guard posts.isEmpty else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading else { return }
        // 2026-08-13 — CAUSE RÉELLE CONFIRMÉE du feed vide sans aucune erreur visible (audit
        // post-Appetize.io) : cette garde retournait SILENCIEUSEMENT si `myId` était absent/invalide
        // (pas de session valide) — `errorMessage` n'était jamais touché dans ce cas précis (seul le
        // bloc `catch` plus bas le renseignait), et de toute façon `FeedView.swift` ne rendait NULLE
        // PART `errorMessage`/`isLoading` (2ᵉ défaut confirmé indépendamment, voir `FeedView.swift`)
        // — l'écran restait donc blanc pour TOUJOURS, sans distinction possible entre "en cours de
        // chargement", "échec réseau" et "pas de session". Rendu visible explicitement ici.
        guard let userId = UserSession.shared.myId.flatMap(Int.init) else {
            errorMessage = "Aucune session active — reconnexion nécessaire."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await repository.fetchTimeline(userId: userId, limit: pageSize, offset: offset)
            try? await repository.cache(page)
            posts.append(contentsOf: page)
            offset += page.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Port de `navigation_home` re-tap sur `MainFragment.loadResetData()` (module 5,
    /// `HomeShellView`/`HomeActivity.mOnNavigationItemSelectedListener`).
    func reset() async {
        posts = []
        offset = 0
        await loadNextPage()
    }
}
