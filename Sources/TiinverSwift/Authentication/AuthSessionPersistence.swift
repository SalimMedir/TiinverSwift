import Foundation

/// Port de la partie "réussite" de `LoginFragment.CreateSyncAccount` /
/// `EmailVerificatiionCode.CreateSyncAccount` (les deux fichiers Android ont une copie quasi
/// identique de cette méthode — factorisée ici en un seul endroit plutôt que dupliquée dans
/// `LoginView.swift` ET `EmailVerificationView.swift`).
enum AuthSessionPersistence {
    /// Persiste apiKey (Keychain), identifiants (UserDefaults via `UserSession`), le compte local
    /// (`AccountEntity`), puis pousse le jeton push au serveur — équivalent de
    /// `MyFirebaseInstanceIdService.requestNewFCMToken(requireActivity())`, maintenant que le
    /// module 4 utilise Firebase Cloud Messaging (voir `PushTokenRegistrar.swift`).
    static func persist(_ user: User) async {
        UserSession.shared.save(user) // Port de SessionManager.saveUser(context, user)

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
