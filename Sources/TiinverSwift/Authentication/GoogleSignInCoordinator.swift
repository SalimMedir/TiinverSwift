import UIKit
import GoogleSignIn
import FirebaseAuth

/// Port du flux Google partagé par `LoginFragment.launchCredentialManager/firebaseAuthWithGoogle`
/// et `withprovider/SignUpWithGoogle.java` (code quasi identique dans les deux fichiers,
/// factorisé ici en un seul coordinateur plutôt que dupliqué comme côté Android).
///
/// Étapes reproduites fidèlement : (1) obtenir un ID token Google (Credential Manager côté
/// Android → `GIDSignIn` côté iOS), (2) échanger ce jeton contre une session **Firebase Auth**
/// (`GoogleAuthProvider.credential` + `Auth.auth().signIn`), (3) lire `email`/`displayName`/`uid`
/// depuis le `FirebaseUser` résultant — PAS depuis la réponse Google brute — pour construire le
/// `User` envoyé au backend Tiinver (`providerId` = `uid` Firebase, pas le `sub` Google brut,
/// exactement comme `profile.getUid()` sur `GoogleAuthProvider.PROVIDER_ID` côté Android).
///
/// Identifiants OAuth — **mise à jour du 2026-08-10, valeurs CONFIRMÉES** par
/// `Resources/GoogleService-Info.plist` (fichier réel téléchargé par l'utilisateur depuis la
/// console Firebase, pas déduit indirectement) :
/// - `clientID` = `CLIENT_ID` du plist iOS (`837038293145-1nf0ru4uk7k9ve96m1p6s4bqi35dnj6q...`,
///   associé à `BUNDLE_ID = com.tiinver.ios`, confirmé être le VRAI bundle id de l'app iOS —
///   voir `project.yml`). Remplace l'ancienne valeur `...0g1db5214de6hrop4ui0elj7obq46tik...`,
///   qui était associée au mauvais bundle id (`com.tiinver.tiinverProject`, une app invite
///   secondaire côté Android, pas l'app iOS principale).
/// - `serverClientID` = client OAuth `client_type: 3` (web) de `app/google-services.json`
///   (Android) — **absent du `GoogleService-Info.plist` iOS** (Firebase n'y inclut pas les
///   clients web). Réutilisé depuis le fichier Android après VÉRIFICATION (pas supposition) que
///   ce client web est partagé au niveau du PROJET Firebase entier, pas lié à un bundle id
///   particulier : il apparaît à l'identique (`...44hahuobt7akggvj6rfi9ltc5msj7dg0...`) sous les
///   DEUX apps Android du même fichier, et son `GCM_SENDER_ID`/project number (837038293145)
///   correspond à celui du plist iOS — même projet Firebase confirmé par recoupement.
enum GoogleSignInCoordinator {
    private static let iOSClientID = "837038293145-1nf0ru4uk7k9ve96m1p6s4bqi35dnj6q.apps.googleusercontent.com"
    private static let webClientID = "837038293145-44hahuobt7akggvj6rfi9ltc5msj7dg0.apps.googleusercontent.com"

    struct GoogleUser {
        let providerId: String
        let email: String?
        let fullname: String?
        let username: String
    }

    /// Port de `launchCredentialManager()` + `handleSignIn(credential)` +
    /// `firebaseAuthWithGoogle(idToken)` + `updateUI(fUser)`. `serverClientID` reproduit
    /// `setServerClientId(getString(R.string.default_web_client_id))` de l'original.
    @MainActor
    static func signIn(presenting viewController: UIViewController) async throws -> GoogleUser {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: iOSClientID, serverClientID: webClientID)

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: nil,
            additionalScopes: nil
        )
        guard let idToken = result.user.idToken?.tokenString else {
            throw APIError.decoding(NSError(domain: "GoogleSignIn", code: -1))
        }

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        let authResult = try await Auth.auth().signIn(with: credential)
        let fUser = authResult.user

        let fullname = fUser.displayName
        let username = StringManager.username(fromFullname: fullname ?? "")
        return GoogleUser(providerId: fUser.uid, email: fUser.email, fullname: fullname, username: username)
    }
}
