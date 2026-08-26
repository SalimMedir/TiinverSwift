import Foundation

/// Port partiel de `Activity/ui/MainFragment.java` (1966 lignes — hors de portée d'un portage
/// intégral à ce stade). La boucle "charger la page suivante / afficher" ET les interactions
/// (like/commentaire/partage/suppression/masquage/ne-plus-suivre/blocage/signalement, câblées le
/// 2026-08-16 après un audit dédié ayant trouvé ces actions ENTIÈREMENT absentes malgré des
/// endpoints déjà identifiés) sont portées ici. Double-tap, pagination infinie fine (seuil fixe "2
/// avant la fin" ici vs seuil dynamique par item visible côté Android — équivalent fonctionnel,
/// pas une divergence de comportement), et le mode édition/upload restent hors périmètre.
@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [FeedActivity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Diagnostic AFFICHÉ À L'ÉCRAN (pas seulement dans la console, potentiellement inaccessible
    /// depuis Appetize) — demande explicite de l'utilisateur suite à plusieurs tours de rapports
    /// "Home vide" non résolus par la seule lecture de code. Retiré une fois la cause confirmée.
    @Published var diagnostics: String = ""
    /// Port du `Toast` d'échec de `ActivityAdapter.deleteMyPost`'s `onError` (V4-F-032) — transitoire,
    /// affiché par les vues qui déclenchent `deleteOwnPost` (`FeedView`/`FeedDetailPagerView`).
    @Published var deleteError: String?

    private let repository = FeedRepository()
    private let profileRepository = ProfileRepository.shared
    private let pageSize = 10
    private var offset = 0
    /// **Ajouté (V5-F-009, 2026-08-24)** — jeton de génération : incrémenté à chaque `reset()`.
    /// Une réponse de pagination (`loadNextPage()`) dont le jeton capturé au départ ne correspond
    /// plus à ce compteur au retour du réseau est PÉRIMÉE (un `reset()` a eu lieu entre-temps) et
    /// n'est plus appliquée à `posts`/`offset`. Port de `loadResetData` (`MainFragment.java:
    /// 481-489`), qui ne vérifie AUCUN flag `loading` avant de relancer un chargement page 1 —
    /// contrairement à l'ancien `reset()` iOS qui partageait le même verrou `isLoading` que
    /// `loadNextPage()` et se faisait donc silencieusement bloquer par une pagination en vol.
    private var loadGeneration = 0

    /// Port de `notifyUser` (`POST push {"userId": ...}`) — **ajouté le 2026-08-24
    /// (MIGRATION_PARITY_AUDIT_V4.md V4-F-030, Phase B P1)**. Vérifié Android : câblé dans
    /// `MainFragment` (Feed), `ProfileFeedFragment` (Profile), `HashtagProfile` (résultats hashtag)
    /// — les 3 sources Android du pager plein écran qui appellent réellement `notifyUser` — mais
    /// PAS dans `FullScreenMedia` (source Android de `SearchView`/`NotificationsListView`, `grep
    /// notifyUser` = 0 résultat dans ce fichier). Un lien profond `/post/{token}` (`HomeShellView`)
    /// route côté Android par `ShareActivity.getActivities` → `SplashActivity` → contexte
    /// `MainFragment` normal, donc notifie aussi. Positionné à l'INIT (pas une constante globale)
    /// car chaque écran instancie son propre `FeedViewModel` jetable (voir `FeedDetailPagerView`).
    private let notifiesAuthorOnInteraction: Bool

    init(notifiesAuthorOnInteraction: Bool = false) {
        self.notifiesAuthorOnInteraction = notifiesAuthorOnInteraction
    }

    /// Port de `notifyUser(id)` lui-même — fire-and-forget, aucune erreur remontée à l'appelant
    /// (fidèle à `data.Post(map, "push", null)`, callback Android nul).
    private func notifyPostAuthorIfNeeded(_ post: FeedActivity) {
        guard notifiesAuthorOnInteraction, let actorId = post.actor else { return }
        Task { try? await repository.notifyPostAuthor(userId: actorId) }
    }

    /// Port de `Settings.setBooleanPreference(id+infoContract.DELETE_POST, true)` — masquage LOCAL
    /// d'une publication d'autrui (`ActivityAdapter.deletePostById`, PAS un vrai appel serveur, voir
    /// `hideOthersPost`). Persisté via `UserDefaults` plutôt que le système `ContentProvider`
    /// Android (rôle identique : survivre au redémarrage de l'app).
    private static let hiddenPostsKey = "feed_hidden_post_ids"
    private var hiddenPostIDs: Set<Int> {
        get { Set((UserDefaults.standard.array(forKey: Self.hiddenPostsKey) as? [Int]) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.hiddenPostsKey) }
    }

    func loadInitial() async {
        guard posts.isEmpty else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading else { return }
        await fetchPage(generation: loadGeneration)
    }

    /// Port de `navigation_home` re-tap sur `MainFragment.loadResetData()` (module 5,
    /// `HomeShellView`/`HomeActivity.mOnNavigationItemSelectedListener`).
    ///
    /// **Corrigé (V5-F-009, 2026-08-24)** — `loadResetData` (Android) ne vérifie AUCUN flag
    /// `loading` avant de relancer un chargement page 1 : le rafraîchissement n'est JAMAIS
    /// silencieusement annulé par une pagination en vol. L'ancienne version appelait
    /// `loadNextPage()`, partageant son `guard !isLoading` — si un `loadNextPage()` de pagination
    /// était déjà en vol au moment du tirage pour rafraîchir, ce `guard` bloquait le VRAI
    /// rechargement de la page 1, `posts`/`offset` restaient remis à zéro sans nouvelle donnée, et
    /// la réponse PÉRIMÉE de l'ancienne pagination (page N) s'appliquait ensuite au tableau
    /// fraîchement vidé — flux figé sur d'anciennes données puis doublons à la pagination
    /// suivante. `reset()` appelle maintenant directement `fetchPage` (contourne le `guard
    /// !isLoading` de `loadNextPage()`, fidèle à l'absence de garde d'Android) après avoir
    /// incrémenté `loadGeneration` — toute réponse de pagination encore en vol au moment du
    /// `reset()` portera un jeton périmé et sera ignorée par `fetchPage` à son retour.
    func reset() async {
        loadGeneration += 1
        let generation = loadGeneration
        posts = []
        offset = 0
        await fetchPage(generation: generation)
    }

    private func fetchPage(generation: Int) async {
        // 2026-08-13 — CAUSE RÉELLE CONFIRMÉE du feed vide sans aucune erreur visible (audit
        // post-Appetize.io) : cette garde retournait SILENCIEUSEMENT si `myId` était absent/invalide
        // (pas de session valide) — `errorMessage` n'était jamais touché dans ce cas précis (seul le
        // bloc `catch` plus bas le renseignait), et de toute façon `FeedView.swift` ne rendait NULLE
        // PART `errorMessage`/`isLoading` (2ᵉ défaut confirmé indépendamment, voir `FeedView.swift`)
        // — l'écran restait donc blanc pour TOUJOURS, sans distinction possible entre "en cours de
        // chargement", "échec réseau" et "pas de session". Rendu visible explicitement ici.
        // Logs de diagnostic temporaires (2026-08-16, demande explicite de l'utilisateur suite au
        // test Appetize "le Home n'affiche toujours aucun feed") — à retirer une fois la cause
        // confirmée par un run réel. Format demandé : SESSION / FEED REQUEST / FEED RESPONSE / FEED UI.
        let sessionLine = "SESSION: myId=\(UserSession.shared.myId ?? "nil") token=\(UserSession.shared.apiKey != nil ? "present" : "nil") authenticated=\(UserSession.shared.isLoggedIn)"
        print(sessionLine)
        diagnostics = sessionLine
        guard let myIdString = UserSession.shared.myId, let userId = Int(myIdString) else {
            errorMessage = "Aucune session active — reconnexion nécessaire."
            let line = "FEED REQUEST: aborted — myId nil or non-numeric (raw=\(UserSession.shared.myId ?? "nil"))"
            print(line)
            diagnostics += "\n" + line
            // Voir `UserSession.debugLastLoginRawUserJSON` — si présent, prouve que le login a
            // RÉUSSI (décodage sans erreur) mais que le JSON "user" reçu n'avait pas la clé "id"
            // attendue, montrant la clé RÉELLE utilisée par ce endpoint pour trancher enfin.
            if let raw = UserSession.shared.debugLastLoginRawUserJSON {
                let rawLine = "LOGIN RAW USER JSON (id manquant malgré succès) : \(raw)"
                print(rawLine)
                diagnostics += "\n" + rawLine
            }
            return
        }
        isLoading = true
        errorMessage = nil
        // V5-F-009 : ne rabaisse `isLoading` que si CETTE génération est toujours la génération
        // courante — sinon un fetch périmé, résolu APRÈS qu'un `reset()` en a lancé un nouveau,
        // couperait à tort le spinner du VRAI chargement encore en vol.
        defer { if generation == loadGeneration { isLoading = false } }

        let requestLine = "FEED REQUEST: feedtimeline/\(userId)/\(pageSize)/\(offset) authHeader=\(UserSession.shared.apiKey != nil ? "present" : "nil")"
        print(requestLine)
        diagnostics += "\n" + requestLine
        do {
            let result = try await repository.fetchTimeline(userId: userId, limit: pageSize, offset: offset)
            // V5-F-009 : un `reset()` a eu lieu pendant cet appel réseau — cette réponse correspond
            // à une requête émise pour une génération déjà périmée (offset/posts d'une liste qui
            // n'existe plus), l'appliquer corromprait l'état fraîchement réinitialisé.
            guard generation == loadGeneration else {
                let staleLine = "FEED RESPONSE: discarded — stale generation \(generation), current \(loadGeneration)"
                print(staleLine)
                return
            }
            let page = result.activities
            let responseLine = "FEED RESPONSE: server sent \(result.receivedCount) activities, \(page.count) decoded successfully" + (result.receivedCount != page.count ? " — \(result.receivedCount - page.count) DROPPED BY DECODE FAILURE" : "")
            print(responseLine)
            diagnostics += "\n" + responseLine
            try? await repository.cache(page)
            let hidden = hiddenPostIDs
            let visible = page.filter { !hidden.contains($0.id) }
            posts.append(contentsOf: visible)
            offset += page.count
            let uiLine = "FEED UI: hiddenFiltered=\(page.count - visible.count) displayedTotal=\(posts.count)"
            print(uiLine)
            diagnostics += "\n" + uiLine
        } catch {
            errorMessage = error.localizedDescription
            let errorLine = "FEED RESPONSE: error=\(error)"
            print(errorLine)
            diagnostics += "\n" + errorLine
        }
    }

    // MARK: - Interactions (port de `OnLikeClicked`/`OnclickCommentaire`/`OnclickPrtg`/`OnclickMoreExpand`)

    /// Port de `OnLikeClicked` — bascule optimiste locale (`isLiked`/`likes`), PUIS envoie TOUJOURS
    /// les MÊMES paramètres réseau (`verb: "like"`, `status: "LIKE"`) quel que soit le sens du
    /// bascule, fidèle à l'original (le serveur bascule lui-même l'état ; Android n'envoie jamais de
    /// "unlike" distinct).
    func toggleLike(_ post: FeedActivity) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }), let myId = UserSession.shared.myId else { return }
        let wasLiked = posts[index].isLiked == "true"
        posts[index].isLiked = wasLiked ? "false" : "true"
        posts[index].likes = max(0, (posts[index].likes ?? 0) + (wasLiked ? -1 : 1))
        let object = post.object ?? ""
        Task { try? await repository.reaction(activityId: post.id, userId: myId, verb: "like", object: object, status: "LIKE") }
        // Port de `notifyUser(mediaObject.getActor())` (`MainFragment.java:1174`) — appelé
        // INCONDITIONNELLEMENT après le like ET l'unlike (en dehors du `if/else` de bascule côté
        // Android), sans attendre la réponse de `reaction` (V4-F-030).
        notifyPostAuthorIfNeeded(post)
    }

    /// Port de `OnclickPrtg` — envoie TOUJOURS `verb: "share"`/`status: "SHARE"` (même remarque que
    /// `toggleLike`), puis ajuste le compteur local selon la réponse RÉELLE du serveur
    /// (`message == infoContract.SHARE` → +1, `== infoContract.UNSHARE` → -1), PAS un bascule
    /// optimiste pré-calculé côté client comme le like (fidèle à l'ordre des opérations Android :
    /// `OnclickPrtg` attend la réponse avant de toucher le compteur). Le partage natif
    /// (`shareMediaLink`) est déclenché par l'appelant (vue), pas ici — même séparation que
    /// l'original (`data.Post` réseau ET `shareMediaLink` appelés indépendamment par le handler).
    func toggleShare(_ post: FeedActivity) async {
        guard let myId = UserSession.shared.myId else { return }
        let object = post.object ?? ""
        guard let message = try? await repository.reaction(activityId: post.id, userId: myId, verb: "share", object: object, status: "SHARE"),
              let index = posts.firstIndex(where: { $0.id == post.id })
        else { return }
        if message == "Share successfully" {
            posts[index].share = (posts[index].share ?? 0) + 1
        } else if message == "Unshare successfully" {
            posts[index].share = max(0, (posts[index].share ?? 0) - 1)
        }
        // Port de `notifyUser(mediaObject.getActor())` (`MainFragment.java:1238`) — placé au MÊME
        // niveau que le `if/else if` de message ci-dessus (pas imbriqué dedans) : se déclenche sur
        // TOUT succès réseau du `reaction`, que le message retourné soit SHARE, UNSHARE, ou autre
        // chose (V4-F-030).
        notifyPostAuthorIfNeeded(post)
    }

    /// Port de `notifyUser(mediaObject.getActor())` dans `OnclickCommentaire`
    /// (`MainFragment.java:1190`) — déclenché à l'OUVERTURE du panneau de commentaires, PAS à
    /// l'envoi d'un commentaire (vérifié : `notifyUser` est appelé immédiatement après
    /// `mySheetDialog.show(...)`, avant même que l'utilisateur ait pu écrire quoi que ce soit) —
    /// **ajouté le 2026-08-24 (V4-F-030, Phase B P1)**. Appelé par la vue au moment où elle arme
    /// `commentsPost`, pas depuis `CommentsView` elle-même.
    func notifyCommentOpened(_ post: FeedActivity) {
        notifyPostAuthorIfNeeded(post)
    }

    /// Port de `ActivityAdapter.deleteMyPost` — UNIQUEMENT pour ses propres publications (garde déjà
    /// faite par l'appelant via `FeedActivity`'s `actor == myId`, voir `FeedView.moreActions`).
    ///
    /// **Corrigé le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-032, Phase B P1)** — `try?`
    /// avalait l'échec de `deleteActivity` (réseau OU rejet backend, `deleteActivity` lève déjà
    /// correctement via `isBackendSuccess`) et retirait le post de `posts` INCONDITIONNELLEMENT.
    /// Vérifié dans `ActivityAdapter.deleteMyPost` (`Activity/adapter/ActivityAdapter.java:847-867`,
    /// lu en entier) : `deletePostById` (retrait local) n'est appelé QUE dans `onResonse` (succès,
    /// `error=="false"` — même contrat `TransportData.Post` que V4-F-020) ; `onError` affiche
    /// seulement un Toast, sans toucher la liste. Le post disparaissait donc de l'UI même sur échec,
    /// pour réapparaître au rechargement suivant — désynchronisation silencieuse. Retrait local
    /// désormais conditionné au succès réel ; `deleteError` publié sinon (équivalent du Toast
    /// Android, affiché par les 2 vues qui déclenchent cette action).
    func deleteOwnPost(_ post: FeedActivity) async {
        guard let myId = UserSession.shared.myId else { return }
        do {
            try await repository.deleteActivity(id: post.id, actorId: myId)
            posts.removeAll { $0.id == post.id }
        } catch {
            deleteError = "Échec de la suppression du post."
        }
    }

    /// Port de la branche non-propriétaire de `OnclickMoreExpand`'s `delete_content`
    /// (`ActivityAdapter.deletePostById` + `Settings.setBooleanPreference(...DELETE_POST, true)`) —
    /// retrait LOCAL uniquement, persisté pour ne pas réapparaître après un `reset()`/relance de
    /// l'app, PAS un appel serveur (Android ne supprime pas la publication d'autrui, il la masque
    /// juste dans SON propre flux).
    func hideOthersPost(_ post: FeedActivity) {
        var hidden = hiddenPostIDs
        hidden.insert(post.id)
        hiddenPostIDs = hidden
        posts.removeAll { $0.id == post.id }
    }

    /// Port de `OnclickMoreExpand`'s branche `unfollow` — MÊME endpoint `follow` que
    /// `ProfileRepository.follow` (le serveur bascule lui-même suivre/ne-plus-suivre, PAS un
    /// endpoint distinct côté Android — `td.Following(map)` avec `userId=actor cible`,
    /// `followId=myId`, exactement les paramètres de `ProfileRepository.follow`).
    func unfollow(_ post: FeedActivity) async {
        guard let myId = UserSession.shared.myId, let actorId = post.actor else { return }
        try? await profileRepository.follow(userId: actorId, followerId: myId)
    }

    /// Port du bouton `followBtn` de `CustomCardView.setData` (fullscreen, `ViewPagerAdapter`) —
    /// même motif unidirectionnel que `ProfileViewModel.follow()`/`SuggestionsCarouselView.follow`
    /// (n'agit QUE si pas déjà suivi, écho optimiste immédiat) : Android masque `followBtn`
    /// entièrement une fois `mediaObject.isFollowed()==true` plutôt que d'en faire un bascule.
    ///
    /// **Corrigé le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-107, Phase B P1 — bug frère,
    /// même pattern `try?` + optimiste sans rollback que `SearchView.toggleFollow`/
    /// `ProfileViewModel.follow`, trouvé en vérifiant tous les appelants de
    /// `ProfileRepository.follow`)** — rollback ajouté, fidèle au vrai comportement Android
    /// (`UserProfile.java:507-508`).
    func followFromDetail(_ post: FeedActivity) async {
        guard post.isFollowed != true, let index = posts.firstIndex(where: { $0.id == post.id }),
            let myId = UserSession.shared.myId, let actorId = post.actor
        else { return }
        posts[index].isFollowed = true
        do {
            try await profileRepository.follow(userId: actorId, followerId: myId)
        } catch {
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index].isFollowed = false
            }
        }
    }

    /// Port de la branche `block_content` de `OnclickMoreExpand` → `block(mediaObject)` — mêmes
    /// paramètres exacts (`username`=mon pseudo, `username_blocked`=pseudo cible, `userId`=mon id,
    /// `user_blocked_id`=`mediaObject.getActor()`).
    ///
    /// **Corrigé le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-033, Phase B P1)** — `_ = try?`
    /// avalait le résultat de `toggleBlock` (déjà un `Bool` fidèle à
    /// `message.equals(USER_BLOCKED)`, voir `ProfileRepository.toggleBlock`) et retirait le post
    /// INCONDITIONNELLEMENT. Vérifié dans `MainFragment.block()` (`Activity/ui/MainFragment.java:
    /// 1704-1758`, lu en entier) : `mAdapter.deletePost` (retrait local) n'est appelé QUE dans la
    /// branche `response.equals(USER_BLOCKED)` — PAS sur `USER_UNBLOCKED` (bascule inverse : le
    /// serveur débloque au lieu de bloquer si l'utilisateur était déjà bloqué) ni sur `onError`
    /// (Toast seul). Retrait local désormais conditionné à `blocked == true` ; aucun affichage
    /// d'erreur ajouté ici (contrairement à V4-F-032) — `toggleBlock` retourne le même `Bool` `false`
    /// pour un déblocage légitime ET pour un rejet backend, les distinguer nécessiterait de modifier
    /// `toggleBlock` lui-même, hors périmètre de ce lot ; le comportement correct (ne pas retirer le
    /// post) est identique dans les deux cas.
    func block(_ post: FeedActivity) async {
        guard let myId = UserSession.shared.myId, let myUsername = UserSession.shared.username,
              let targetUsername = post.username, let actorId = post.actor
        else { return }
        guard let blocked = try? await profileRepository.toggleBlock(myUsername: myUsername, myId: myId, targetUsername: targetUsername, targetUserId: actorId),
              blocked
        else { return }
        posts.removeAll { $0.id == post.id }
    }

    /// Port de `Report.report()` — voir `FeedRepository.reportUser` pour la note de fidélité sur
    /// `target_id`/`report_type` selon le contexte (grille vide, plein écran rempli).
    ///
    /// **Corrigé (V5-F-007, 2026-08-24)** — `includesTarget` distingue les 2 comportements Android
    /// (`MainFragment` grille vs `FeedFragment`/`ProfileFeedFragment`/`HashtagProfile` plein écran).
    func report(_ post: FeedActivity, reason: String, includesTarget: Bool = false) async {
        guard let actorId = post.actor, let username = post.username else { return }
        try? await repository.reportUser(
            userId: actorId, username: username, message: reason,
            targetId: includesTarget ? String(post.id) : "", reportType: includesTarget ? "content" : ""
        )
    }
}
