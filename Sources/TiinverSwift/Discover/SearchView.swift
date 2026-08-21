import SwiftUI

/// Port de `RechercheTiinver.java` — recherche universelle (comptes/publications/hashtags),
/// onglets + suggestions + historique local. UI reconstruite (mise en page XML non fournie), la
/// logique réseau/debounce/onglets est fidèle.
struct SearchView: View {
    @State private var query: String
    @State private var tab: SearchTab
    @State private var results = SearchResults()
    @State private var recent = RecentSearchStore.all()
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var detailPost: FeedActivity?
    /// Port de `autoQuery`/`autoTab` (`RechercheTiinver.java:156-181`) — `true` uniquement au
    /// premier lancement avec une query pré-remplie (tap #hashtag/@mention, `V3-F-099`) ; lance la
    /// recherche IMMÉDIATEMENT sans passer par le debounce (`showRecentPanel(false)` +
    /// `searchFull(autoQuery, currentTab)` direct côté Android — pas d'attente de frappe puisqu'il
    /// n'y a pas eu de frappe).
    @State private var shouldAutoSearch: Bool

    /// Port d'`Intent(ctx, RechercheTiinver.class)` avec `autoQuery`/`autoTab`
    /// (`TokenClickableSpan.onClick`, `MentionTextView.java:184-196`) — **ajouté le 2026-08-20
    /// (MIGRATION_PARITY_AUDIT_V3.md V3-F-099, Phase B P1)**. `initialQuery` est TOUJOURS la query
    /// DÉPOUILLÉE du préfixe (`searchQuery`, jamais `displayToken`), fidèle à
    /// `RechercheTiinver.java:168` (`displayQuery = autoQuery` — le préfixage du champ affiché a
    /// été explicitement désactivé côté Android, code mort commenté aux lignes 163-167).
    init(initialQuery: String? = nil, initialTab: SearchTab = .all) {
        _query = State(initialValue: initialQuery ?? "")
        _tab = State(initialValue: initialTab)
        _shouldAutoSearch = State(initialValue: initialQuery.map { !$0.isEmpty } ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Onglet", selection: $tab) {
                ForEach(SearchTab.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: tab) { _ in runSearch(full: true) }

            List {
                if query.isEmpty {
                    Section("Recherches récentes") { // pas de libellé Android identifié (layout non fourni)
                        ForEach(recent, id: \.self) { entry in
                            Button(entry) { selectRecent(entry) }
                        }
                        .onDelete { indices in
                            for index in indices { RecentSearchStore.remove(recent[index]) }
                            recent = RecentSearchStore.all()
                        }
                        if !recent.isEmpty {
                            Button("Tout effacer", role: .destructive) { RecentSearchStore.clearAll(); recent = [] }
                        }
                    }
                } else {
                    if !results.users.isEmpty {
                        Section("Comptes") { // R.string.user
                            ForEach(results.users) { user in
                                HStack {
                                    NavigationLink { ProfileView(userId: String(user.id), isCurrentUser: false) } label: {
                                        userRow(user)
                                    }
                                    Spacer()
                                    // Port de `UniversalSearchAdapter.java:225-247` (bouton "Suivre"
                                    // inline sur la ligne résultat) — manquant côté iOS avant ce
                                    // correctif. `.buttonStyle(.borderless)` évite que le tap sur ce
                                    // bouton déclenche aussi la navigation du `NavigationLink` voisin
                                    // (comportement standard `List`/`NavigationLink` imbriqués).
                                    followButton(user)
                                }
                            }
                        }
                    }
                    if !results.hashtags.isEmpty {
                        Section("Hashtags") {
                            ForEach(results.hashtags) { tag in
                                NavigationLink { HashtagFeedView(tag: tag.tag) } label: {
                                    Label("#\(tag.tag)", systemImage: "number")
                                }
                            }
                        }
                    }
                    if !results.posts.isEmpty {
                        Section("Publications") { // R.string equivalent non identifié
                            ForEach(results.posts) { post in
                                postRow(post).contentShape(Rectangle()).onTapGesture { Task { await openDetail(for: post) } }
                            }
                        }
                    }
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                    // Port de `showEmpty("Erreur de chargement")`/`showEmpty("Aucun résultat pour …")`
                    // (`RechercheTiinver.java:452-455,567`) — les deux états manquaient côté iOS
                    // (échec réseau et absence de résultat rendus indistinguables d'une recherche
                    // jamais lancée, `try?` avalant l'erreur dans `SearchRepository`).
                    if !isLoading, query.count >= 2 {
                        if let errorText {
                            Text(errorText).foregroundStyle(.red).frame(maxWidth: .infinity)
                        } else if results.users.isEmpty, results.hashtags.isEmpty, results.posts.isEmpty {
                            Text("Aucun résultat pour \u{201C}\(query)\u{201D}")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $query, prompt: "Rechercher")
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // port du debounce — `DEBOUNCE_DELAY_MS = 300` vérifié le 2026-08-18 (P2), `RechercheTiinver.java:85`
                guard !Task.isCancelled else { return }
                if newValue.count < 2 {
                    if newValue.count >= 1 { await suggest(newValue) }
                } else {
                    runSearch(full: true)
                }
            }
        }
        .fullScreenCover(item: $detailPost) { post in
            FeedDetailPagerView(posts: [post], startIndex: 0, onClose: { detailPost = nil })
        }
        .task {
            guard shouldAutoSearch else { return }
            shouldAutoSearch = false
            runSearch(full: true)
        }
    }

    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-004 SEARCH-04, Phase B P1)** —
    /// port de `UniversalSearchAdapter.java:298-306` : le tap Android sur un résultat "publication"
    /// ne transporte QUE `activityId`/`userId`/`type` vers `FullScreenMedia`, qui recharge lui-même
    /// la publication fraîche par ID — `item` (les données de recherche, potentiellement obsolètes
    /// : compteurs de likes/commentaires figés au moment de la recherche) n'est JAMAIS réutilisé
    /// directement pour l'affichage plein écran. `post.asFeedActivity` (utilisé auparavant tel
    /// quel) reproduisait exactement ce défaut. Recharge maintenant via `getactivity/{token}`
    /// (`FeedRepository.fetchPost(byToken:)`, déjà utilisé pour les liens profonds — `SearchPostResult.
    /// token` existe déjà, jamais exploité ici) ; repli sur les données de recherche potentiellement
    /// obsolètes UNIQUEMENT si le rechargement échoue (réseau), pour ne jamais bloquer l'ouverture.
    private func openDetail(for post: SearchPostResult) async {
        if let token = post.token, !token.isEmpty,
            let fresh = try? await FeedRepository().fetchPost(byToken: token)
        {
            detailPost = fresh
        } else {
            detailPost = post.asFeedActivity
        }
    }

    private func userRow(_ user: SearchUserResult) -> some View {
        HStack {
            CDNAsyncImage(url: URL(string: user.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Color(.secondarySystemBackground)
            }
            .frame(width: 40, height: 40).clipShape(Circle())
            VStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Text("\(user.firstname ?? "") \(user.lastname ?? "")")
                    if user.certified == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.caption) }
                }
                Text("@\(user.username ?? "")").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func followButton(_ user: SearchUserResult) -> some View {
        Button {
            Task { await toggleFollow(user) }
        } label: {
            Text(user.isFollowed == true ? "Abonné" : "Suivre")
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(user.isFollowed == true ? Color(.secondarySystemBackground) : Color.accentColor)
                .foregroundStyle(user.isFollowed == true ? Color.primary : Color.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(user.isFollowed == true)
    }

    /// Port de `UniversalSearchAdapter`'s follow click handler — `ProfileRepository.follow` ne
    /// gère QUE le sens "suivre" (pas de bascule "ne plus suivre" depuis cette liste, fidèle à
    /// `ProfileViewModel.follow()` déjà porté — même absence côté profil, voir audit Profile).
    ///
    /// **Corrigé le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-107, Phase B P1)** — avant ce
    /// correctif, `isFollowed=true` était posé de façon optimiste puis JAMAIS annulé en cas
    /// d'échec réseau (`try?` avalait l'erreur) : l'utilisateur voyait "Abonné" affiché en
    /// permanence, bouton désactivé, sans moyen de réessayer — un faux positif persistant, pire
    /// que le comportement Android réel de ce bouton précis
    /// (`UniversalSearchAdapter.java:236-239` : `onFollowingError` masque juste le spinner, ne
    /// confirme jamais faussement un succès, mais reste aussi bloqué sur "pending" — un bug
    /// latent différent côté Android). Le VRAI rollback attendu existe ailleurs dans le même
    /// écran Android, sur le bouton "Suivre" principal du profil
    /// (`UserProfile.java:507-508` : `onFollowingError() { labelSeguir.setText(R.string.seguir) }`)
    /// — reproduit ici : `isFollowed` repasse à `false` en cas d'échec, réactivant le bouton pour
    /// un nouvel essai, plutôt que de reproduire le blocage "pending" ou le faux "Abonné" permanent.
    private func toggleFollow(_ user: SearchUserResult) async {
        guard user.isFollowed != true, let myId = UserSession.shared.myId else { return }
        if let index = results.users.firstIndex(where: { $0.id == user.id }) {
            results.users[index].isFollowed = true
        }
        do {
            try await ProfileRepository.shared.follow(userId: String(user.id), followerId: myId)
        } catch {
            if let index = results.users.firstIndex(where: { $0.id == user.id }) {
                results.users[index].isFollowed = false
            }
        }
    }

    private func postRow(_ post: SearchPostResult) -> some View {
        HStack {
            if let thumb = post.thumbnailURL {
                CDNAsyncImage(url: thumb) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading) {
                Text(post.message ?? "").lineLimit(2)
                Text("@\(post.username ?? "") · \(post.likes ?? 0) ❤️").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func suggest(_ text: String) async {
        do {
            results = try await SearchRepository.shared.suggest(query: text)
            errorText = nil
        } catch {
            results = SearchResults()
            errorText = "Erreur de chargement."
        }
    }

    /// Port de `RecentSearchAdapter.setOnItemClickListener`
    /// (`RechercheTiinver.java:252-279,324-328`) — **corrigé le 2026-08-20
    /// (MIGRATION_PARITY_AUDIT_V3.md V3-F-103, Phase B P1)**. Avant ce correctif, un tap sur une
    /// entrée récente préfixée ("#android"/"@tiinver") gardait le préfixe brut dans `query` et ne
    /// changeait jamais l'onglet — le backend recevait littéralement la query préfixée
    /// (`content/search?q=%23android&types=users,posts,hashtags...`) au lieu de la version
    /// dépouillée avec l'onglet dérivé, donnant 0 résultat de façon reproductible à 100 %.
    /// Reproduit maintenant le parsing Android : préfixe `#` → onglet Hashtags, `@` → onglet
    /// Utilisateurs, sinon onglet Tous ; la query envoyée au réseau est TOUJOURS dépouillée du
    /// préfixe, fidèle à `entry.startsWith("#")`/`"@"` → `query = entry.substring(1)`.
    private func selectRecent(_ entry: String) {
        if entry.hasPrefix("#") {
            tab = .hashtags
            query = String(entry.dropFirst())
        } else if entry.hasPrefix("@") {
            tab = .users
            query = String(entry.dropFirst())
        } else {
            tab = .all
            query = entry
        }
        runSearch(full: true)
    }

    private func runSearch(full: Bool) {
        guard query.count >= 2 else { return }
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                results = try await SearchRepository.shared.search(query: query, tab: tab)
                errorText = nil
            } catch {
                results = SearchResults()
                errorText = "Erreur de chargement."
            }
            RecentSearchStore.save(query)
            recent = RecentSearchStore.all()
        }
    }
}
