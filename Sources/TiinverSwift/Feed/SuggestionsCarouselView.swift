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
    }

    private func card(for user: User) -> some View {
        VStack(spacing: 6) {
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
    private func follow(_ user: User) async {
        guard let myId = UserSession.shared.myId, let targetId = user.id else { return }
        followedIds.insert(targetId)
        try? await ProfileRepository.shared.follow(userId: String(targetId), followerId: myId)
    }
}
