import AuthenticationServices
import CryptoKit
import FirebaseAuth
import UIKit

/// "Sign in with Apple", câblé sur le même modèle que `GoogleSignInCoordinator.swift` : (1) obtenir
/// un jeton d'identité via `AuthenticationServices` (`ASAuthorizationController`), (2) échanger ce
/// jeton contre une session **Firebase Auth** (`OAuthProvider.appleCredential` + `Auth.auth().signIn`),
/// (3) lire `email`/`displayName`/`uid` depuis le `FirebaseUser` résultant pour construire l'objet
/// envoyé ensuite au backend Tiinver via le MÊME endpoint générique que Google (voir
/// `AuthEndpoints.loginWithGoogle`/`registerWithProvider`, qui prennent déjà un `provider: String`
/// arbitraire — appelés ici avec `provider: "apple"`, sans aucune modification de la couche réseau).
///
/// **Non disponible sur Android** — aucun équivalent à porter depuis l'app Android de référence,
/// fonctionnalité nouvelle demandée directement côté iOS (2026-09-01).
///
/// **⚠️ Support backend NON VÉRIFIÉ** — contrairement au reste de ce portage, il n'existe aucune
/// preuve (code source backend indisponible dans ce dépôt) que l'API Tiinver accepte réellement
/// `provider: "apple"` sur l'endpoint `login`/`register`. À confirmer par un test réel avant de
/// considérer ce flux fonctionnel de bout en bout — voir résumé de session.
enum AppleSignInCoordinator {
    struct AppleUser {
        /// `uid` Firebase — même rôle que `GoogleUser.providerId`, envoyé au backend Tiinver.
        let providerId: String
        /// Identifiant STABLE Apple (`credential.user`) — PAS envoyé au backend, à persister via
        /// `UserSession.shared.appleUserIdentifier` pour `checkCredentialStateAtLaunch()`.
        let appleUserIdentifier: String
        let email: String?
        let fullname: String?
        let username: String
    }

    /// Port du flux complet, service autonome (indépendant de toute UI) : requête Apple avec nonce
    /// hashé → `ASAuthorizationAppleIDCredential` → jeton d'identité + nonce brut → échange Firebase.
    /// Construit et présente son propre `ASAuthorizationController` — utilisé par les appelants qui
    /// n'ont pas déjà un `SignInWithAppleButton` SwiftUI (celui-ci gère sa propre présentation, voir
    /// `configureRequest(_:)`/`resolveUser(from:rawNonce:)` ci-dessous, réutilisés par `LoginView.
    /// appleButton` pour NE PAS dupliquer la logique nonce/Firebase entre les deux chemins).
    @MainActor
    static func signIn(presenting window: UIWindow) async throws -> AppleUser {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let rawNonce = configureRequest(request)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleAuthorizationDelegate(anchor: window)
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        let authorization = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
            delegate.continuation = continuation
            controller.performRequests()
        }

        return try await resolveUser(from: authorization, rawNonce: rawNonce)
    }

    /// Configure une requête Apple ID (portée + nonce hashé) et renvoie le nonce BRUT correspondant,
    /// à conserver par l'appelant pour `resolveUser(from:rawNonce:)`. Extrait de `signIn(presenting:)`
    /// pour être réutilisé tel quel par le `onRequest` du `SignInWithAppleButton` natif
    /// (`LoginView.swift`), qui construit/présente son PROPRE `ASAuthorizationController` en interne
    /// — seule la CONFIGURATION de la requête et la RÉSOLUTION du résultat doivent rester identiques
    /// entre les deux chemins, pas le contrôleur lui-même.
    ///
    /// **Nonce (protection anti-rejeu)** — port fidèle du schéma documenté par Firebase pour Apple :
    /// une chaîne aléatoire cryptographiquement sûre est générée LOCALEMENT (`randomNonceString()`,
    /// `SecRandomCopyBytes`), son EMPREINTE SHA256 est envoyée à Apple (`request.nonce`, ce qu'Apple
    /// grave dans le jeton d'identité renvoyé), et c'est la chaîne BRUTE (non hashée) d'origine qui
    /// est ensuite fournie à Firebase (`rawNonce:`) — Firebase recalcule lui-même le SHA256 pour le
    /// comparer à celui gravé dans le jeton, garantissant que le jeton présenté correspond bien à
    /// CETTE requête précise et ne peut pas être rejoué depuis une interception antérieure.
    @discardableResult
    static func configureRequest(_ request: ASAuthorizationAppleIDRequest) -> String {
        let rawNonce = randomNonceString()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)
        return rawNonce
    }

    /// Échange `authorization` (déjà obtenue, par n'importe lequel des deux chemins ci-dessus) contre
    /// une session Firebase, puis construit l'`AppleUser` envoyé au backend Tiinver.
    static func resolveUser(from authorization: ASAuthorization, rawNonce: String) async throws -> AppleUser {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw APIError.decoding(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Identifiant Apple inattendu"]))
        }
        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.decoding(NSError(domain: "AppleSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "Jeton d'identité Apple absent"]))
        }

        // Port de `firebaseAuthWithGoogle(idToken)` côté `GoogleSignInCoordinator` — équivalent
        // Apple officiel de `GoogleAuthProvider.credential(withIDToken:accessToken:)`.
        let firebaseCredential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: credential.fullName)
        let authResult = try await Auth.auth().signIn(with: firebaseCredential)
        let fUser = authResult.user

        // Apple ne renvoie `fullName`/`email` QUE lors de la TOUTE PREMIÈRE autorisation pour cette
        // app (`credential.fullName`/`credential.email` sont `nil` ensuite, par design Apple — la
        // personne a déjà consenti, rien à redemander) — Firebase ne les reporte PAS automatiquement
        // dans `fUser.displayName`/`fUser.email` pour ce provider, contrairement à Google. Capturés
        // ici depuis le `credential` en PRIORITÉ ; repli sur le `FirebaseUser` (peuplé si l'email
        // n'est pas cachée via "Masquer mon e-mail", ou lors d'une connexion ultérieure où Firebase
        // a déjà mémorisé l'e-mail de la toute première fois).
        let fullname: String? = {
            guard let components = credential.fullName else { return fUser.displayName }
            let formatted = PersonNameComponentsFormatter().string(from: components)
            return formatted.isEmpty ? fUser.displayName : formatted
        }()
        let email = credential.email ?? fUser.email
        let username = StringManager.username(fromFullname: fullname ?? "")

        return AppleUser(
            providerId: fUser.uid,
            appleUserIdentifier: credential.user,
            email: email,
            fullname: fullname,
            username: username
        )
    }

    // MARK: - Vérification d'état au démarrage (`getCredentialState`)

    /// Port de la vérification recommandée par Apple (`ASAuthorizationAppleIDProvider.
    /// getCredentialState(forUserID:)`) — à appeler au lancement de l'app, PAS à chaque écran :
    /// détecte le cas où l'utilisateur a révoqué l'accès de l'app depuis Réglages > [son nom] >
    /// Connexion et sécurité > Applications utilisant Apple ID DEPUIS le dernier lancement, sans
    /// qu'aucune autre action de l'app ne le lui signale autrement. Ne fait RIEN (silencieux,
    /// best-effort — même politique que `ViewEventSyncService.sync()` dans `RootRouterView.swift`)
    /// si la session en cours n'a jamais été établie via Apple (`appleUserIdentifier == nil`) ou si
    /// la vérification échoue elle-même (pas de connexion, etc.) — ne doit jamais bloquer le
    /// démarrage de l'app ni interrompre une session par ailleurs valide sur une erreur transitoire.
    @MainActor
    static func checkCredentialStateAtLaunch() async {
        guard let userId = UserSession.shared.appleUserIdentifier else { return }
        let state = await withCheckedContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Never>) in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, _ in
                continuation.resume(returning: state)
            }
        }
        switch state {
        case .revoked, .notFound:
            // Port du même mécanisme de déconnexion que `SettingSubViews.logout()` — voir
            // `UserSession.clear()`/`.userDidLogout`, déjà observé par `RootRouterView`.
            UserSession.shared.clear()
            NotificationCenter.default.post(name: .userDidLogout, object: nil)
        case .authorized, .transferred:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Nonce

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            precondition(status == errSecSuccess, "SecRandomCopyBytes a échoué — pas de repli, un nonce prévisible viderait la protection anti-rejeu de sa raison d'être.")
            for byte in randomBytes where remaining > 0 {
                // Rejet des octets >= 248 pour un tirage uniforme sur les 64 caractères de `charset`
                // (256 = 4*64, les valeurs 248-255 introduiraient un léger biais) — port du motif
                // standard documenté par Apple/Firebase pour cette génération.
                if byte < 248 {
                    result.append(charset[Int(byte) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

/// `ASAuthorizationControllerDelegate`/`ASAuthorizationControllerPresentationContextProviding` sont
/// des protocoles Objective-C classiques (callbacks, pas `async`) — ce pont `NSObject` privé les
/// relie à `withCheckedThrowingContinuation` dans `signIn(presenting:)` ci-dessus, même motif que
/// `DisplayLinkProxy`/`AnimemesCaptureTickerProxy` (module Animems) pour `CADisplayLink`. Retenu
/// fortement par la variable locale `delegate` de `signIn(presenting:)` pendant toute la durée de
/// l'attente (les propriétés `delegate`/`presentationContextProvider` d'`ASAuthorizationController`
/// sont `weak`) — jamais stocké ailleurs, jamais partagé entre deux requêtes.
private final class AppleAuthorizationDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var continuation: CheckedContinuation<ASAuthorization, Error>?
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
