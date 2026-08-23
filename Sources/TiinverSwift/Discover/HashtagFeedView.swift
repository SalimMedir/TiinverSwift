import SwiftUI

/// Port de `uploadPerfilPhoto/HashtagProfile.java` (navigation depuis `UniversalSearchAdapter.
/// java:341-348`) — grille des publications d'un hashtag, réutilise EXACTEMENT le même motif
/// grille-2-colonnes → tap → pager plein écran que le Feed principal (`FeedGridCell`/
/// `FeedDetailPagerView`, rendus `internal` le 2026-08-16 pour permettre cette réutilisation plutôt
/// que de dupliquer le rendu de cellule).
struct HashtagFeedView: View {
    let tag: String
    /// Port de `intent.getIntExtra("post_count"/"total_views", 0)` (V3-F-101, SEARCH complémentaire)
    /// — "déjà connus depuis la recherche, pas besoin d'un appel réseau" (commentaire Android
    /// lui-même, `HashtagProfile.java:343-344`) : ces stats ne sont disponibles QUE quand on arrive
    /// depuis un résultat de recherche hashtag (`SearchView`), défaut `0` pour tout autre point
    /// d'entrée (tap `#hashtag` en légende, lien profond) — fidèle au défaut `getIntExtra(...,0)`.
    var postCount: Int = 0
    var totalViews: Int = 0

    @State private var posts: [FeedActivity] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var showDetail = false
    @State private var detailStartIndex = 0
    /// Port de `HashtagProfile.OFFSET`/`loadMoreData` (`HashtagProfile.java:102,461-465`) —
    /// **ajouté le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-102, Phase B P1)**. Avant ce
    /// correctif, `load()` n'était appelé qu'une seule fois (`.task`), sans état `offset`/déclencheur
    /// de scroll — aucun second appel réseau n'était jamais émis, cassant tout hashtag de plus de
    /// 30 publications (la LIMITE du premier appel, elle-même incorrecte : voir `pageLimit`).
    @State private var offset = 0
    @State private var reachedEnd = false
    @State private var isLoadingMore = false

    /// Port de `HashtagProfile.LIMIT` (`HashtagProfile.java:101`) — **corrigé le 2026-08-20
    /// (V3-F-102, Phase B P1)** : la valeur réelle Android est `10`, PAS `30` (vérifiée
    /// directement dans le source Android avant ce correctif — l'affirmation du finding original
    /// comme quoi "les paramètres du premier appel étaient déjà identiques" était inexacte).
    private let pageLimit = 10

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

    var body: some View {
        VStack(spacing: 0) {
            statsHeader
            Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                // `ContentUnavailableView` est iOS 17+ — cible de déploiement 16.0 (`project.yml`),
                // état vide reconstruit manuellement.
                emptyState(systemImage: "wifi.slash", text: errorText)
            } else if posts.isEmpty {
                emptyState(systemImage: "number", text: "Aucune publication pour #\(tag)")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(Array(posts.enumerated()), id: \.offset) { index, post in
                            FeedGridCell(post: post)
                                .onTapGesture { detailStartIndex = index; showDetail = true }
                                .onAppear {
                                    // Port du seuil de scroll infini (`visibleThreshold`/
                                    // `onScrolled`, `HashtagProfile.java:435-449`) — même motif
                                    // "dernière cellule visible" que `ProfileView.swift`
                                    // (`loadMorePosts`), pour rester cohérent avec le reste du
                                    // projet plutôt que de reproduire le seuil "5 avant la fin"
                                    // spécifique à Android.
                                    if post.id == posts.last?.id { Task { await loadMore() } }
                                }
                        }
                    }
                    .padding(1)
                }
            }
            }
        }
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(isPresented: $showDetail) {
            FeedDetailPagerView(posts: posts, startIndex: detailStartIndex, onClose: { showDetail = false })
        }
    }

    /// Port de `postValueView`/`viewsValueView` (`HashtagProfile.java:325-326,346-347`, V3-F-101) —
    /// toujours affiché, y compris à `0` (Android n'a pas de logique de masquage conditionnel sur
    /// ces `TextView`, valeurs par défaut `getIntExtra(...,0)` affichées telles quelles).
    private var statsHeader: some View {
        HStack(spacing: 24) {
            VStack {
                Text(StringManager.formatCount(postCount)).font(.headline)
                Text("Publications").font(.caption2).foregroundStyle(.secondary)
            }
            VStack {
                Text(StringManager.formatCount(totalViews)).font(.headline)
                Text("Vues").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func emptyState(systemImage: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        offset = 0
        reachedEnd = false
        do {
            let page = try await ProfileRepository.shared.fetchHashtagPosts(tag: tag, limit: pageLimit, offset: 0)
            posts = page
            offset = pageLimit
            if page.isEmpty { reachedEnd = true }
            errorText = nil
        } catch {
            errorText = "Erreur de chargement."
        }
    }

    /// Port de `loadMoreData()` (`HashtagProfile.java:461-465` : `OFFSET += LIMIT` puis
    /// `executeTask()`) — **ajouté le 2026-08-20 (V3-F-102, Phase B P1)**.
    private func loadMore() async {
        guard !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await ProfileRepository.shared.fetchHashtagPosts(tag: tag, limit: pageLimit, offset: offset)
            if page.isEmpty {
                reachedEnd = true
            } else {
                posts.append(contentsOf: page)
                offset += pageLimit
            }
        } catch {
            // Silencieux, cohérent avec `ProfileViewModel.loadMorePosts` (même motif : un échec de
            // page suivante n'efface pas ce qui est déjà affiché, pas d'état d'erreur bloquant).
        }
    }
}
