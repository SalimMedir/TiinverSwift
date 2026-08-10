import Foundation

/// Port consolidé de `Authentification/AuthViewModel.java`,
/// `Authentification/login/SigninViewModel.java`, `Authentification/register/SignupViewModel.java`
/// et `Authentification/passwordrecovery/PWRViewModel.java`.
///
/// Les quatre classes Android sont du code **strictement identique** (mêmes 5 méthodes, même
/// délégation à `AuthRepository`, aucune variation) — un seul `AuthViewModel` regroupe donc ce que
/// l'app Android répartissait en 4 `AndroidViewModel` quasi-dupliqués (un par écran/`Fragment`,
/// convention Android pour scoper le cycle de vie, sans justification fonctionnelle ici en
/// SwiftUI). `@Published var user` remplace le `LiveData<User>` observé par chaque `Fragment`.
///
/// `AuthRepository.java`/`AutentificationWenack.java` (couche réseau) sont déjà portés en
/// `Networking/Endpoints/AuthEndpoints.swift` (module 1) ; ce type ajoute seulement l'état
/// observable + la gestion d'erreur réseau (absente côté Android : `AutentificationWenack` ne
/// remonte jamais d'échec réseau au `Fragment`, seulement un `User` avec `etat` renseigné —
/// reproduit ici en distinguant `errorMessage` réseau/décodage de `user.etat` métier).
@MainActor
final class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Équivalent de `AuthRepository.setLogin`.
    func login(username: String, password: String, provider: String) async {
        await run { try await AuthEndpoints.login(username: username, password: password, provider: provider) }
    }

    /// Équivalent de `AuthRepository.setLoginWithGoogle`.
    func loginWithGoogle(providerId: String, email: String, provider: String) async {
        await run { try await AuthEndpoints.loginWithGoogle(providerId: providerId, email: email, provider: provider) }
    }

    /// Équivalent de `AuthRepository.setRegister`.
    func register(user: User, provider: String) async {
        await run { try await AuthEndpoints.register(user: user, provider: provider) }
    }

    /// Équivalent de `AuthRepository.setRegisterWithGoogle`.
    func registerWithProvider(user: User, provider: String) async {
        await run { try await AuthEndpoints.registerWithProvider(user: user, provider: provider) }
    }

    /// Équivalent de `AuthRepository.setPasswordForgotted`. Les deux branches `usingEmail`/
    /// `!usingEmail` du code Android d'origine construisent exactement le même payload
    /// (`phoneOrEmail` prend `email` ou `phone` selon le booléen, tout le reste est identique) —
    /// reproduit ici sans branchement inutile, la distinction est déjà faite dans
    /// `AuthEndpoints.passwordForgotten`.
    func passwordForgotten(user: User, usingEmail: Bool) async {
        await run { try await AuthEndpoints.passwordForgotten(user: user, usingEmail: usingEmail) }
    }

    private func run(_ request: @escaping () async throws -> User) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            user = try await request()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
