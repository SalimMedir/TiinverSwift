import SwiftUI

/// Port de `Authentification/withprovider/SignUpWithGoogle.java`.
///
/// `withprovider/SignupWithProviderViewModel.java` (identique à `AuthViewModel`/3 autres
/// doublons déjà consolidés au module 3, voir `AuthViewModel.swift`) et
/// `Authentification/ContinueWithGoogleRepository.java` (confirmé mort par grep — zéro
/// `new ContinueWithGoogleRepository(` dans tout le dépôt, `firebaseAuthWithGoogle` y est
/// d'ailleurs commenté) NON portés séparément.
///
/// PAS porté ici, volontairement : bannière AdMob (module 16) ; log Facebook Ads (SDK Facebook
/// pas encore câblé) ; demande de permission galerie (`Permission.requestPermission`,
/// `READ_MEDIA_IMAGES` — sans équivalent nécessaire à cet écran précis côté iOS, `PHPicker`
/// gère ses propres permissions au moment de l'usage, pas en amont).
struct SignUpWithGoogleView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var errorText: String?

    var onRegistered: (User) -> Void
    var onContinueWithEmail: () -> Void
    var onLogin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView()
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }

            Button("Continuer avec Google") { // signup1
                Task { await signInWithGoogle() }
            }
            .disabled(viewModel.isLoading)

            Button("Continuer avec email") { onContinueWithEmail() } // signup2 → position 3
                .disabled(viewModel.isLoading)

            Button("Déjà un compte ? Se connecter", action: onLogin) // login → position 4
                .disabled(viewModel.isLoading)
        }
        .padding()
        .onChange(of: viewModel.user) { newUser in
            guard let newUser else { return }
            handle(newUser)
        }
    }

    private func signInWithGoogle() async {
        errorText = nil
        guard let presenter = UIApplication.shared.rootViewController else { return }
        guard let googleUser = try? await GoogleSignInCoordinator.signIn(presenting: presenter) else { return }

        var user = User()
        user.email = googleUser.email
        user.fullname = googleUser.fullname
        user.username = googleUser.username
        user.providerId = googleUser.providerId
        // Port de Settings.getStringPreferenceForReferredBy(activity, infoContract.REFERRED_BY).
        user.referredBy = UserDefaults.standard.string(forKey: "REFERRED_BY")

        await viewModel.registerWithProvider(user: user, provider: "google")
    }

    /// Port de `SignUpWithGoogle.CreateSyncAccount`.
    private func handle(_ user: User) {
        switch user.etat {
        case "User created successfully":
            Task { await AuthSessionPersistence.persist(user) }
            onRegistered(user)
        case "NoInser":
            errorText = "Échec de l'inscription" // R.string.NoInser
        case "User Already Exists":
            errorText = "Cet email existe déjà" // R.string.mailExist
        case "NoConnect":
            errorText = "Connexion impossible" // R.string.NoConnect
        default:
            break
        }
    }
}
