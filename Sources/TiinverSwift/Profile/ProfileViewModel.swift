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
    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-010, Phase B P2)** — port de
    /// `ProfileAdapter2.FooterViewHolder.bindView(type)` (`ProfileAdapter2.java:186-208`) : le
    /// pied de grille paginée bascule entre shimmer (chargement, type 0), rien (succès, type 1) et
    /// icône+texte+bouton "Réessayer" (échec, type 2) — `loadMorePosts()` avalait l'échec en
    /// silence (`catch { print(...) }`, jamais visible à l'écran), et `isLoadingPosts` (déjà
    /// publié) n'était lu par AUCUNE vue (confirmé par grep avant ce correctif).
    @Published var postsLoadError = false
    @Published var isBlocked = false
    @Published var isFollowing = false
    @Published var isUploadingPhoto = false
    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-009, Phase B P2)** — port de
    /// `AddPerfilFoto`'s `Result.ERROR` → `mAdapter.setProfilePictureStateLoading(3)`
    /// (`ProfileAdapter2.java:281-285` : `error.setVisibility(VISIBLE)`, une icône d'erreur dédiée
    /// superposée à l'avatar). `uploadProfilePicture` avalait l'échec réseau via `catch {}` vide —
    /// aucun état d'erreur, aucun indicateur visuel, contrairement à Android.
    @Published var photoUploadFailed = false
    /// Port du même correctif que `FeedViewModel.errorMessage` (2026-08-13, cause racine du feed
    /// vide sans erreur visible) — `loadProfile()` avalait silencieusement toute erreur réseau/
    /// session via `try?`, laissant `ProfileView.header` ne RIEN afficher (ni spinner, ni erreur,
    /// ni contenu) : indiscernable d'un profil réellement vide. Trouvé en réappliquant le même
    /// audit "silent try? = symptôme identique au bug Feed déjà corrigé" à Profile, qui ne l'avait
    /// jamais reçu.
    @Published var errorMessage: String?
    /// Diagnostic AFFICHÉ À L'ÉCRAN (pas seulement console, potentiellement inaccessible depuis
    /// Appetize) — même motif que `FeedViewModel.diagnostics`, demande explicite de l'utilisateur.
    @Published var diagnostics: String = ""

    private(set) var userId: String
    let isCurrentUser: Bool
    private let repository = ProfileRepository.shared
    private let limit = 15
    private var offset = 0
    private var reachedEnd = false

    init(userId: String, isCurrentUser: Bool) {
        self.userId = userId
        self.isCurrentUser = isCurrentUser
    }

    /// Filet de sécurité défensif : si CETTE instance a été construite avec un `userId` vide (le
    /// piège de capture figée documenté sur `loadProfile()` — `ProfileView()` construit avant que
    /// la session ne soit peuplée), et que la session contient bien un `myId` maintenant, on se
    /// corrige au lieu de rester bloqué indéfiniment sur `userId=""`. Sans coût si le piège ne se
    /// produit pas (no-op dans ce cas).
    private func healStaleUserIdIfNeeded() {
        guard isCurrentUser, userId.isEmpty, let myId = UserSession.shared.myId, !myId.isEmpty else { return }
        userId = myId
    }

    func loadProfile() async {
        healStaleUserIdIfNeeded()
        // `userId` est figé à la CONSTRUCTION de cette instance (`@StateObject`, jamais réévalué
        // ensuite) — port sensible si `ProfileView()` (init sans argument, capture
        // `UserSession.shared.myId ?? ""` UNE SEULE FOIS) est construit avant que la session ne
        // soit peuplée. Log explicite pour trancher : si `userId(param)` est vide ici alors que
        // `myId` (relu maintenant) ne l'est PAS, c'est la preuve de ce piège précis.
        let sessionLine = "SESSION: userId(param, figé à la construction)=\"\(userId)\" myId(relu maintenant)=\(UserSession.shared.myId ?? "nil") authenticated=\(UserSession.shared.isLoggedIn)"
        print(sessionLine)
        diagnostics = sessionLine
        guard let viewerId = UserSession.shared.myId else {
            errorMessage = "Aucune session active — reconnexion nécessaire."
            let line = "PROFILE REQUEST: aborted — UserSession.shared.myId is nil"
            print(line)
            diagnostics += "\n" + line
            // Voir `UserSession.debugLastLoginRawUserJSON` (même diagnostic que FeedViewModel).
            if let raw = UserSession.shared.debugLastLoginRawUserJSON {
                let rawLine = "LOGIN RAW USER JSON (id manquant malgré succès) : \(raw)"
                print(rawLine)
                diagnostics += "\n" + rawLine
            }
            return
        }
        if userId.isEmpty {
            let line = "PROFILE REQUEST: WARNING — userId(param) is EMPTY despite myId being set (\(viewerId)) — this IS the stale-capture bug, ProfileView() was constructed before session existed"
            print(line)
            diagnostics += "\n" + line
        }
        isLoadingProfile = true
        errorMessage = nil
        defer { isLoadingProfile = false }
        let requestLine = "PROFILE REQUEST: getuserbyid/\(userId)/\(viewerId)"
        print(requestLine)
        diagnostics += "\n" + requestLine
        do {
            profile = try await repository.fetchProfile(userId: userId, viewerId: viewerId)
            let responseLine = "PROFILE RESPONSE: success username=\(profile?.username ?? "nil") id=\(profile?.id.map(String.init) ?? "nil")"
            print(responseLine)
            diagnostics += "\n" + responseLine
            // **CAUSE RACINE RÉELLE trouvée le 2026-08-17** (retour utilisateur : "la valeur des
            // coins ne s'affiche pas dans Wallet") — port fidèle de `AddPerfilFoto.java:636`
            // (`Settings.setFloatPreference(..., COINS_AMOUNT, user.getCoinsAmount())`, exécuté
            // À CHAQUE chargement RÉUSSI de SON PROPRE profil) : Android n'a AUCUN endpoint dédié
            // "solde du portefeuille" et ne persiste PAS `coinsAmount` à la connexion — le cache
            // local (`Settings`/`UserSession.coinsAmount` ici) n'est mis à jour QUE quand le profil
            // personnel est rechargé, exactement ce point. `WalletViewModel.coinsAmount` lisait déjà
            // ce cache correctement ; c'est cette écriture qui manquait, jamais portée.
            if isCurrentUser, let coins = profile?.coinsAmount {
                UserSession.shared.coinsAmount = coins
            }
            if isCurrentUser, let gems = profile?.gemsAmount ?? profile?.gems {
                UserSession.shared.gemsAmount = gems
            }
        } catch {
            profile = nil
            errorMessage = "Impossible de charger le profil : \(error.localizedDescription)"
            let errorLine = "PROFILE RESPONSE: error=\(error)"
            print(errorLine)
            diagnostics += "\n" + errorLine
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

    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-014, Phase B P2)** — port de
    /// `UserProfile.executeTask` (`UserProfile.java:723-727`, `if (!isBlocked) { ...fetch... }`) :
    /// Android n'émet AUCUNE requête de posts pour un profil bloqué. `isBlocked` est déjà peuplé
    /// AVANT ce point (`loadProfile()` le lit depuis le cache local, appelé avant
    /// `loadInitialPosts()` dans `.task` de `ProfileView`) — garde ajoutée ici plutôt qu'une
    /// vérification par appelant, un seul point d'entrée réseau pour les posts.
    func loadMorePosts() async {
        guard !isLoadingPosts, !reachedEnd, !isBlocked, let viewerId = UserSession.shared.myId else { return }
        isLoadingPosts = true
        postsLoadError = false
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
            postsLoadError = true
        }
    }

    /// Port de `butSeguir.setOnClickListener` (`UserProfile.java`) — écho optimiste immédiat
    /// (`labelSeguir.setText(R.string.pending)`), fidèle à l'original.
    ///
    /// **Corrigé le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-107, Phase B P1 — bug frère
    /// découvert en vérifiant les sites d'appel du même pattern `try?` + mise à jour optimiste
    /// dans `SearchView.toggleFollow`)** — `try?` avalait l'erreur réseau sans jamais réinitialiser
    /// `isFollowing`, contrairement à l'Android RÉEL de CE bouton précis
    /// (`UserProfile.java:507-508` : `onFollowingError() { labelSeguir.setText(R.string.seguir) }`),
    /// qui remet explicitement le libellé à "Suivre" (et réactive le bouton, `.disabled(isFollowing)`
    /// dans `ProfileView.swift`) en cas d'échec. Avant ce correctif, un échec réseau laissait le
    /// bouton bloqué sur "Abonné"/désactivé en permanence, sans moyen de réessayer.
    /// **Étendu le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-014, Phase B P2)** — port de
    /// `UserProfile.java:501-504` (`OnFollowingSuccess` → `TransportData.notifyUser(context,
    /// metas.getId())`, en plus de la mise à jour du libellé déjà portée) : Android déclenche
    /// TOUJOURS un `POST push {userId}` (notification "quelqu'un vous suit") après un follow
    /// réussi, fire-and-forget (`data.Post(map,"push",null)`, callback null côté Android — reproduit
    /// ici par `try?`, échec silencieux sans affecter `isFollowing`).
    func follow() async {
        guard let myId = UserSession.shared.myId else { return }
        isFollowing = true
        do {
            try await repository.follow(userId: userId, followerId: myId)
            try? await FeedRepository().notifyPostAuthor(userId: userId)
        } catch {
            isFollowing = false
        }
    }

    /// Port de `AddPerfilFoto` (flux d'envoi de la photo de profil, section reprise dans
    /// `ProfileRepository.uploadProfilePicture` — voir GAP-004) — met à jour l'avatar affiché
    /// immédiatement après succès, comme `Onresponse` côté Android (`listenerAdapter.Onresponse`
    /// renvoie `object_url` et l'UI Android l'affiche aussitôt via Glide, sans recharger tout le
    /// profil).
    func uploadProfilePicture(imageData: Data) async {
        guard isCurrentUser, let myId = UserSession.shared.myId else { return }
        isUploadingPhoto = true
        photoUploadFailed = false
        defer { isUploadingPhoto = false }
        do {
            let url = try await repository.uploadProfilePicture(userId: myId, imageData: imageData)
            profile?.profile = url
        } catch {
            photoUploadFailed = true
        }
    }

    /// Port de `UserProfile.block`/`actionOnMenuItem` — bascule bloquer/débloquer.
    ///
    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-013, Phase B P1-7)** — Android
    /// (`UserProfile.java:1118-1124`, branche `USER_UNBLOCKED`) appelle explicitement
    /// `loadInitialData()` après un déblocage réussi, republiant immédiatement la grille. Seul le
    /// cas symétrique "bloquer" (vider `posts`) avait été porté ; ajouté ici le rechargement sur
    /// déblocage pour ne pas laisser la grille vide jusqu'à la sortie/retour de l'écran.
    func toggleBlock() async {
        guard let myUsername = UserSession.shared.username, let myId = UserSession.shared.myId, let targetUsername = profile?.username
        else { return }
        let blocked = (try? await repository.toggleBlock(myUsername: myUsername, myId: myId, targetUsername: targetUsername, targetUserId: userId)) ?? isBlocked
        isBlocked = blocked
        UserDefaults.standard.set(blocked, forKey: targetUsername + "_blocked")
        if blocked {
            posts = []
        } else {
            await loadInitialPosts()
        }
    }
}
