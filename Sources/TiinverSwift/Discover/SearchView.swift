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

    /// Port de `GridLayoutManager(this, 3)` (V3-F-100) — 3 colonnes pour les résultats
    /// "Publications" uniquement (comptes/hashtags restent des lignes pleine-largeur, fidèle au
    /// `SpanSizeLookup` Android : `TYPE_POST` = 1 colonne, tout le reste = 3).
    private let postGridColumns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

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
                                NavigationLink {
                                    HashtagFeedView(tag: tag.tag, postCount: tag.post_count ?? 0, totalViews: tag.total_views ?? 0)
                                } label: {
                                    hashtagRow(tag)
                                }
                            }
                        }
                    }
                    // Corrigé (V3-F-100, SEARCH complémentaire) : Android affiche les résultats
                    // "Publications" en grille 3 colonnes (`GridLayoutManager(this, 3)`,
                    // `SpanSizeLookup` → `TYPE_POST` = 1 colonne, `RechercheTiinver.java:143-153`),
                    // pas en liste verticale de lignes — reconstruit fidèlement via `LazyVGrid`
                    // plutôt que la `postRow` en `HStack` précédente.
                    if !results.posts.isEmpty {
                        Section("Publications") { // R.string equivalent non identifié
                            LazyVGrid(columns: postGridColumns, spacing: 2) {
                                ForEach(results.posts) { post in
                                    postGridCell(post).onTapGesture { Task { await openDetail(for: post) } }
                                }
                            }
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                    // Port de `showEmpty("Erreur de chargement")`/`showEmpty("Aucun résultat pour …")`
                    // (`RechercheTiinver.java:452-455,567`) — les deux états manquaient côté iOS
                    // (échec réseau et absence de résultat rendus indistinguables d'une recherche
                    // jamais lancée, `try?` avalant l'erreur dans `SearchRepository`).
                    // Corrigé (V3-F-105, SEARCH — complémentaire) : seuil `>= 2` hérité tel quel du
                    // seuil RÉSEAU (`runSearch` n'est déclenché qu'à partir de 2 caractères), alors
                    // que `suggest()` (la SEULE source d'`errorText` pour une query courte) n'est
                    // déclenchée qu'à `count == 1` (`.onChange(of: query)` ci-dessous) — les deux
                    // seuils ne se recoupaient jamais, donc un échec réseau sur une query d'exactement
                    // 1 caractère ne montrait ni erreur ni "aucun résultat", écran figé sans feedback.
                    // Fidèle à `RechercheTiinver.java:412-431,567` (`showEmpty` inconditionnel, pas de
                    // seuil de longueur pour l'affichage).
                    if !isLoading, query.count >= 1 {
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

    /// Port de `HashtagViewHolder.bind` (V3-F-101, SEARCH complémentaire) — `post_count`/
    /// `total_views` étaient décodés (`SearchHashtagResult`) mais jamais affichés côté iOS.
    /// Formats EXACTS reproduits : `"{n} publication(s)"` (pluriel français conditionnel),
    /// `"{formatCount(total_views)} vues"` (`UniversalSearchAdapter.java:334-339`).
    private func hashtagRow(_ tag: SearchHashtagResult) -> some View {
        HStack {
            Label("#\(tag.tag)", systemImage: "number")
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                let count = tag.post_count ?? 0
                Text("\(count) publication\(count > 1 ? "s" : "")").font(.caption2)
                Text("\(StringManager.formatCount(tag.total_views ?? 0)) vues").font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Port de `PostViewHolder.bind` (V3-F-100, SEARCH complémentaire) — tuile carrée réutilisée
    /// pour la grille 3 colonnes : vignette pleine cellule, icône vidéo (coin haut-droit) si
    /// `verb=="video"`/`object=="videos"` (comparaison EXACTE, pas insensible à la casse — fidèle à
    /// `"video".equals(item.getVerb())`/`"videos".equals(item.getObject())`), compteur de vues
    /// formaté (coin bas-gauche).
    private func postGridCell(_ post: SearchPostResult) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let thumb = post.thumbnailURL {
                    CDNAsyncImage(url: thumb) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            if post.verb == "video" || post.object == "videos" {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            Text(StringManager.formatCount(post.views ?? 0))
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
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
                // Corrigé (V3-F-104, SEARCH — complémentaire) : `save()` était appelé APRÈS le
                // do/catch, donc inconditionnellement même en cas d'échec réseau — Android ne
                // sauvegarde QUE dans `onResonse` (`RechercheTiinver.java:440-458`), jamais dans
                // `onError`. Déplacé DANS la branche succès pour ne plus polluer l'historique
                // local avec des recherches jamais réellement abouties.
                RecentSearchStore.save(query)
                recent = RecentSearchStore.all()
            } catch {
                results = SearchResults()
                errorText = "Erreur de chargement."
            }
        }
    }
}
