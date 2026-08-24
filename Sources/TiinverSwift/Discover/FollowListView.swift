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
                    CDNAsyncImage(url: URL(string: user.profile ?? ""), targetSize: CGSize(width: 44, height: 44)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
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

    // Corrigé (V3-F-093, SILENT-04) : décodage du tableau ENTIER en un seul `try?` — plusieurs
    // champs de `SearchUserResult` (`username`/`firstname`/.../`category`) ne sont PAS lenient, donc
    // UN SEUL utilisateur avec un champ de type inattendu faisait échouer TOUTE la liste
    // abonnés/abonnements d'un coup, vidée silencieusement en `[]`. Même motif déjà corrigé pour
    // `TrophyRepository.weeklyRank`/`WalletRepository.transactions`/`CommentRepository.
    // decodeComments` — `compactMap` per-item avec diagnostic.
    func list(type: String, userId: String, followerId: String, limit: Int, offset: Int) async throws -> [SearchUserResult] {
        let value = try await APIClient.shared.get("\(type)/\(userId)/\(followerId)/\(limit)/\(offset)")
        guard value.isBackendSuccess, let array = value["users"]?.toArray() else { return [] }
        let decoded = array.compactMap { item -> SearchUserResult? in
            guard let data = item.rawData else {
                print("FOLLOW LIST: item.rawData nil for one user — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(SearchUserResult.self, from: data)
            } catch {
                print("FOLLOW LIST: decode failure for one user — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("FOLLOW LIST: received=\(array.count), only \(decoded.count) usable — \(array.count - decoded.count) skipped, see above")
        }
        return decoded
    }
}
