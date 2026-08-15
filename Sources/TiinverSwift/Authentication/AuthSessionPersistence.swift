import Foundation

/// Port de la partie "réussite" de `LoginFragment.CreateSyncAccount` /
/// `EmailVerificatiionCode.CreateSyncAccount` (les deux fichiers Android ont une copie quasi
/// identique de cette méthode — factorisée ici en un seul endroit plutôt que dupliquée dans
/// `LoginView.swift` ET `EmailVerificationView.swift`).
enum AuthSessionPersistence {
    /// Partie SYNCHRONE de `persist(_:)` — extraite le 2026-08-15 (test Appetize réel) suite à une
    /// race condition confirmée : les 3 appelants (`LoginView`/`SignUpWithGoogleView`/
    /// `EmailVerificationView`) faisaient `Task { await persist(user) }` puis naviguaient
    /// IMMÉDIATEMENT après (`onLoginSuccess(user)`), sans attendre que `UserSession.shared.myId`
    /// soit réellement écrit. `HomeShellView`/`ProfileView` lisaient alors `myId` encore `nil` à
    /// leur tout premier chargement (`ProfileView.init()` : `UserSession.shared.myId ?? ""`, valeur
    /// figée dans un `let` au moment de la construction, jamais réévaluée ensuite) — écran Profil
    /// vide sans aucune erreur visible. `UserSession.save` est déjà synchrone (pas de `await`
    /// interne) : appeler CETTE fonction directement, AVANT de naviguer, suffit à éliminer la race
    /// — le reste de `persist` (Core Data, jeton push) peut rester asynchrone sans bloquer la
    /// navigation, aucun de ces effets n'est lu au premier rendu de Profile/Feed.
    static func saveSession(_ user: User) {
        UserSession.shared.save(user) // Port de SessionManager.saveUser(context, user)
    }

    /// Persiste apiKey (Keychain), identifiants (UserDefaults via `UserSession`), le compte local
    /// (`AccountEntity`), puis pousse le jeton push au serveur — équivalent de
    /// `MyFirebaseInstanceIdService.requestNewFCMToken(requireActivity())`, maintenant que le
    /// module 4 utilise Firebase Cloud Messaging (voir `PushTokenRegistrar.swift`).
    static func persist(_ user: User) async {
        saveSession(user)

        let accounts = CoreDataRepository<AccountEntity>()
        try? await accounts.insert { account in
            account.id = Int64(user.id ?? 0)
            account.apiKey = user.apiKey
            account.email = user.email
            account.phone = user.phone
            account.username = user.username
            account.firstname = user.firstname
            account.lastname = user.lastname
            account.nikname = "\(user.firstname ?? "") \(user.displayLastname)"
            account.profile = user.profile
            account.certified = user.certified
            account.emailVerified = user.emailVerified
            account.location = user.location
            account.school = user.school
            account.qualification = user.qualification
            account.birthday = user.birthday
            account.work = user.work
            account.coinsAmount = user.coinsAmount ?? 0
            account.referralCode = user.referralCode
            account.stamp = user.stamp
        }

        await PushTokenRegistrar.pushTokenToServer()
    }
}
