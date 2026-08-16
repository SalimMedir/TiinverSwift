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
    @Published var isUploadingPhoto = false
    /// Port du même correctif que `FeedViewModel.errorMessage` (2026-08-13, cause racine du feed
    /// vide sans erreur visible) — `loadProfile()` avalait silencieusement toute erreur réseau/
    /// session via `try?`, laissant `ProfileView.header` ne RIEN afficher (ni spinner, ni erreur,
    /// ni contenu) : indiscernable d'un profil réellement vide. Trouvé en réappliquant le même
    /// audit "silent try? = symptôme identique au bug Feed déjà corrigé" à Profile, qui ne l'avait
    /// jamais reçu.
    @Published var errorMessage: String?

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
        print("SESSION: userId(param)=\(userId) myId=\(UserSession.shared.myId ?? "nil") apiKey.isEmpty=\(UserSession.shared.apiKey?.isEmpty ?? true) authenticated=\(UserSession.shared.isLoggedIn)")
        guard let viewerId = UserSession.shared.myId else {
            errorMessage = "Aucune session active — reconnexion nécessaire."
            print("PROFILE REQUEST: aborted — UserSession.shared.myId is nil")
            return
        }
        isLoadingProfile = true
        errorMessage = nil
        defer { isLoadingProfile = false }
        print("PROFILE REQUEST: endpoint=getuserbyid/\(userId)/\(viewerId) userId=\(userId) viewerId=\(viewerId)")
        do {
            profile = try await repository.fetchProfile(userId: userId, viewerId: viewerId)
            print("PROFILE RESPONSE: success username=\(profile?.username ?? "nil") id=\(profile?.id.map(String.init) ?? "nil")")
        } catch {
            profile = nil
            errorMessage = "Impossible de charger le profil : \(error.localizedDescription)"
            print("PROFILE RESPONSE: error=\(error)")
        }
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
        print("PROFILE POSTS REQUEST: endpoint=feedtimeline/\(userId)/\(viewerId)/\(limit)/\(offset)")
        do {
            let page = try await repository.fetchUserPosts(actor: userId, viewerId: viewerId, limit: limit, offset: offset)
            print("PROFILE POSTS RESPONSE: count=\(page.count)")
            if page.isEmpty {
                reachedEnd = true
            } else {
                posts.append(contentsOf: page)
                offset += limit
            }
        } catch {
            print("PROFILE POSTS RESPONSE: error=\(error)")
        }
    }

    /// Port de `butSeguir.setOnClickListener` (`UserProfile.java`) — écho optimiste immédiat
    /// (`labelSeguir.setText(R.string.pending)`), fidèle à l'original.
    func follow() async {
        guard let myId = UserSession.shared.myId else { return }
        isFollowing = true
        try? await repository.follow(userId: userId, followerId: myId)
    }

    /// Port de `AddPerfilFoto` (flux d'envoi de la photo de profil, section reprise dans
    /// `ProfileRepository.uploadProfilePicture` — voir GAP-004) — met à jour l'avatar affiché
    /// immédiatement après succès, comme `Onresponse` côté Android (`listenerAdapter.Onresponse`
    /// renvoie `object_url` et l'UI Android l'affiche aussitôt via Glide, sans recharger tout le
    /// profil).
    func uploadProfilePicture(imageData: Data) async {
        guard isCurrentUser, let myId = UserSession.shared.myId else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let url = try await repository.uploadProfilePicture(userId: myId, imageData: imageData)
            profile?.profile = url
        } catch {}
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
