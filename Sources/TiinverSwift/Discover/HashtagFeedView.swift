import SwiftUI

/// Port de `uploadPerfilPhoto/HashtagProfile.java` (navigation depuis `UniversalSearchAdapter.
/// java:341-348`) — grille des publications d'un hashtag, réutilise EXACTEMENT le même motif
/// grille-2-colonnes → tap → pager plein écran que le Feed principal (`FeedGridCell`/
/// `FeedDetailPagerView`, rendus `internal` le 2026-08-16 pour permettre cette réutilisation plutôt
/// que de dupliquer le rendu de cellule).
struct HashtagFeedView: View {
    let tag: String

    @State private var posts: [FeedActivity] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var showDetail = false
    @State private var detailStartIndex = 0

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

    var body: some View {
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
                        }
                    }
                    .padding(1)
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
        do {
            posts = try await ProfileRepository().fetchHashtagPosts(tag: tag, limit: 30, offset: 0)
            errorText = nil
        } catch {
            errorText = "Erreur de chargement."
        }
    }
}
