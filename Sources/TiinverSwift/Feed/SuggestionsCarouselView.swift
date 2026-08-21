import SwiftUI

/// Port de `AdapterSuggestContact`/`UserSuggestCompound` (`Activity/ui/AdapterSuggestContact.java`,
/// lu en entier) — carrousel horizontal de comptes suggérés, affiché en en-tête du fil (voir
/// `FeedView.homeHeader`). Se rétracte entièrement si la liste est vide (aucun placeholder vide
/// côté Android non plus : `getItemCount()` conditionne seulement le nombre de cellules du
/// `RecyclerView` interne, le conteneur `feed_header_layout.xml` reste lui toujours visible pour
/// la bannière AdMob/pièces qui le suit — comportement reproduit dans `FeedView.homeHeader`, pas
/// dans cette vue).
struct SuggestionsCarouselView: View {
    @State private var users: [User] = []
    @State private var followedIds: Set<Int> = []
    @State private var isLoading = false
    /// Port de `avatar.setOnClickListener` (`AdapterSuggestContact.ViewHolder.bindView`) — cette
    /// vue est intégrée dans `FeedView.homeHeader`, elle-même hébergée par l'onglet Accueil de
    /// `HomeShellView`, qui N'EST PAS enveloppé dans un `NavigationStack` (contrairement aux
    /// onglets Chat/Créateurs) — un `NavigationLink` y serait silencieusement inopérant. MÊME motif
    /// que `FeedDetailPagerView.openProfileUserId` : présentation par `fullScreenCover` piloté par
    /// état local plutôt que `NavigationLink`.
    @State private var openProfileUserId: String?

    var body: some View {
        Group {
            if !users.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(users, id: \.id) { user in
                            card(for: user)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: Binding(get: { openProfileUserId != nil }, set: { if !$0 { openProfileUserId = nil } })) {
            if let userId = openProfileUserId {
                NavigationStack {
                    ProfileView(userId: userId, isCurrentUser: false)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Fermer") { openProfileUserId = nil }
                            }
                        }
                }
            }
        }
    }

    private func card(for user: User) -> some View {
        VStack(spacing: 6) {
            Button(action: { if let id = user.id { openProfileUserId = String(id) } }) {
                CDNAsyncImage(url: user.profile.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(Color(.secondarySystemBackground))
                            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Port de `AdapterSuggestContact.ViewHolder.safeTrim` — même longueurs max (20/13).
            Text(safeTrim(user.nikname ?? user.username ?? "", 20))
                .font(.caption.bold())
                .lineLimit(1)
            Text("@\(safeTrim(user.username ?? "", 13))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button(action: { Task { await follow(user) } }) {
                Text(isFollowed(user) ? "Suivi" : "Suivre")
                    .font(.caption2.bold())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(isFollowed(user) ? Color(.systemGray5) : Color.accentColor, in: Capsule())
                    .foregroundStyle(isFollowed(user) ? Color.primary : Color.white)
            }
            .disabled(isFollowed(user))
        }
        .frame(width: 84)
    }

    private func safeTrim(_ text: String, _ maxLength: Int) -> String {
        guard !text.isEmpty else { return "" }
        return text.count <= maxLength ? text : String(text.prefix(maxLength - 1)) + "..."
    }

    private func isFollowed(_ user: User) -> Bool {
        guard let id = user.id else { return false }
        return followedIds.contains(id)
    }

    private func load() async {
        guard let myId = UserSession.shared.myId, users.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        users = (try? await SuggestionsRepository.shared.fetchSuggestions(userId: myId)) ?? []
    }

    /// Port de `AdapterSuggestContact.ViewHolder.mSeguirClick` — écho optimiste immédiat
    /// (`labelSeguir.setText(R.string.pending)` avant la réponse réseau), même motif que
    /// `ProfileViewModel.follow()`.
    ///
    /// **Corrigé le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-107, Phase B P1 — bug frère,
    /// même pattern `try?` + optimiste sans rollback, trouvé en vérifiant tous les appelants de
    /// `ProfileRepository.follow`)** — rollback ajouté (retire `targetId` de `followedIds` en cas
    /// d'échec) plutôt que de reproduire le blocage "pending" permanent de
    /// `AdapterSuggestContact.java:150-153` (`onFollowingError` masque juste le spinner, ne
    /// réinitialise jamais le libellé), pour ne jamais laisser un faux "Abonné" permanent.
    private func follow(_ user: User) async {
        guard let myId = UserSession.shared.myId, let targetId = user.id else { return }
        followedIds.insert(targetId)
        do {
            try await ProfileRepository.shared.follow(userId: String(targetId), followerId: myId)
        } catch {
            followedIds.remove(targetId)
        }
    }
}
