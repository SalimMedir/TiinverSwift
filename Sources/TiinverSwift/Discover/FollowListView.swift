import SwiftUI

/// Port de `Following/FollowList.java` (166, entier) + `FollowRepository.java` (56, entier) —
/// liste d'abonnés/abonnements paginée. Endpoint UNIQUE `{type}/{userId}/{followerId}/{limit}/
/// {offset}` où `type` ∈ `{"followers","following"}` sert directement de segment d'URL (vérifié :
/// `type+"/"+userId+"/"+followerId+"/"+limit+"/"+offset"`, PAS un paramètre nommé).
struct FollowListView: View {
    let userId: String
    let type: FollowListType
    @State private var users: [SearchUserResult] = []
    @State private var isLoading = false
    @State private var offset = 0
    private let limit = 25

    enum FollowListType: String {
        case followers, following

        var title: String {
            switch self {
            case .followers: return "Abonnés"
            case .following: return "Abonnements"
            }
        }
    }

    var body: some View {
        List(users) { user in
            NavigationLink { ProfileView(userId: String(user.id), isCurrentUser: false) } label: {
                HStack {
                    AsyncImage(url: URL(string: user.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                        Color(.secondarySystemBackground)
                    }
                    .frame(width: 44, height: 44).clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text("\(user.firstname ?? "") \(user.lastname ?? "")")
                        Text("@\(user.username ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear { if user.id == users.last?.id { Task { await loadMore() } } }
        }
        .navigationTitle(type.title) // R.id.title, port de `title.setText(type)`
        .task { await loadMore() }
    }

    private func loadMore() async {
        guard !isLoading, let followerId = UserSession.shared.myId else { return }
        isLoading = true
        defer { isLoading = false }
        let page = (try? await FollowRepository.shared.list(type: type.rawValue, userId: userId, followerId: followerId, limit: limit, offset: offset)) ?? []
        guard !page.isEmpty else { return }
        users.append(contentsOf: page)
        offset += limit
    }
}

@MainActor
final class FollowRepository {
    static let shared = FollowRepository()
    private init() {}

    func list(type: String, userId: String, followerId: String, limit: Int, offset: Int) async throws -> [SearchUserResult] {
        let value = try await APIClient.shared.get("\(type)/\(userId)/\(followerId)/\(limit)/\(offset)")
        guard value.isBackendSuccess, let data = value["users"]?.rawData else { return [] }
        return (try? JSONDecoder().decode([SearchUserResult].self, from: data)) ?? []
    }
}
