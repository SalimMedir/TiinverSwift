import Foundation

/// Port de `ProfileViewModel.java` + logique réseau de `UserProfile.java`/`AddPerfilFoto.java`
/// (module 17, tous lus en entier) — UN SEUL ViewModel couvre les deux écrans Android
/// (`UserProfile` = profil d'AUTRUI, `AddPerfilFoto` = SON PROPRE profil), consolidés en un
/// `ProfileView` unique paramétré par `isCurrentUser` plutôt que dupliqués comme côté Android —
/// simplification délibérée, documentée : les deux Activity partagent ~80% de la même mise en page
/// (grille de posts paginée, en-tête avatar/bio/stats), seules les actions de l'en-tête diffèrent
/// (suivre/bloquer/signaler vs modifier/wallet/monétisation).
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: User?
    @Published var posts: [FeedActivity] = []
    @Published var isLoadingProfile = false
    @Published var isLoadingPosts = false
    @Published var isBlocked = false
    @Published var isFollowing = false

    let userId: String
    let isCurrentUser: Bool
    private let repository = ProfileRepository.shared
    private let limit = 15
    private var offset = 0
    private var reachedEnd = false

    init(userId: String, isCurrentUser: Bool) {
        self.userId = userId
        self.isCurrentUser = isCurrentUser
    }

    func loadProfile() async {
        guard let viewerId = UserSession.shared.myId else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        profile = try? await repository.fetchProfile(userId: userId, viewerId: viewerId)
        isFollowing = profile?.isFollowed ?? false
        if let username = profile?.username {
            isBlocked = UserDefaults.standard.bool(forKey: username + "_blocked") // port de `infoContract.BLOCKED` ("_blocked", vérifié)
        }
    }

    func loadInitialPosts() async {
        offset = 0
        reachedEnd = false
        posts = []
        await loadMorePosts()
    }

    func loadMorePosts() async {
        guard !isLoadingPosts, !reachedEnd, let viewerId = UserSession.shared.myId else { return }
        isLoadingPosts = true
        defer { isLoadingPosts = false }
        do {
            let page = try await repository.fetchUserPosts(actor: userId, viewerId: viewerId, limit: limit, offset: offset)
            if page.isEmpty {
                reachedEnd = true
            } else {
                posts.append(contentsOf: page)
                offset += limit
            }
        } catch {}
    }

    /// Port de `butSeguir.setOnClickListener` (`UserProfile.java`) — écho optimiste immédiat
    /// (`labelSeguir.setText(R.string.pending)`), fidèle à l'original.
    func follow() async {
        guard let myId = UserSession.shared.myId else { return }
        isFollowing = true
        try? await repository.follow(userId: userId, followerId: myId)
    }

    /// Port de `UserProfile.block`/`actionOnMenuItem` — bascule bloquer/débloquer.
    func toggleBlock() async {
        guard let myUsername = UserSession.shared.username, let myId = UserSession.shared.myId, let targetUsername = profile?.username
        else { return }
        let blocked = (try? await repository.toggleBlock(myUsername: myUsername, myId: myId, targetUsername: targetUsername, targetUserId: userId)) ?? isBlocked
        isBlocked = blocked
        UserDefaults.standard.set(blocked, forKey: targetUsername + "_blocked")
        if blocked { posts = [] }
    }
}
