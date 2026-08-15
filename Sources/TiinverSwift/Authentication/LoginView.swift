import SwiftUI

/// Port de `Authentification/login/LoginFragment.java` + `Authentification/view/LoginCompound.java`.
///
/// **Connexion Google** (`GoogleSignInCoordinator.swift`) : câblée depuis que l'usage réel de
/// Firebase a été confirmé par investigation du code source Android (voir décision "Priorité 0"
/// dans MIGRATION_PROGRESS.md — `google-services.json` provisionné, dépendances Gradle réelles).
///
/// Non porté depuis l'original, volontairement, à ce stade :
/// - **Navigation** (`FragmentConnectionListener.onArticleSelected(int, Bundle)`, le routeur
///   d'écrans de l'app Android) : remplacée par des closures injectées par l'appelant
///   (`AuthCoordinatorView.swift`, module 5), qui reproduit fidèlement le routage par position.
/// - **`AccountManager`/`ContentResolver` local Android** (`CreateSyncAccount`) : spécifique à la
///   plomberie de comptes Android (sync adapter), sans équivalent fonctionnel sur iOS. Remplacé
///   par une écriture directe dans `UserSession`/`KeychainStore` (déjà écrits, module 1) et
///   `AccountEntity` (Core Data, module 2) — mêmes données persistées, mécanisme iOS natif.
/// - Le bascule mail/téléphone (`container_mail`/`container_phone`, visibilité XML non disponible
///   sans le layout `login_layout.xml`, non fourni) est reconstituée comme un `Picker` segmenté —
///   comportement observable (`usingEmail` détermine quel champ est actif) reproduit fidèlement,
///   mais l'agencement visuel exact du XML original n'a pas pu être vérifié.
struct LoginView: View {
    @StateObject private var viewModel = AuthViewModel()

    @State private var usingEmail = true
    @State private var mail = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorText = ""

    var onLoginSuccess: (User) -> Void
    var onForgotPassword: () -> Void
    var onRegister: () -> Void
    /// Équivalent de la branche "Email not verified" de `CreateSyncAccount` — l'appelant route
    /// vers l'écran de confirmation de code avec les mêmes informations que
    /// `arg.putString("action","signin")`/`email`/`phone`/`password`/`usingEmail` côté Android.
    var onEmailNotVerified: (_ usingEmail: Bool, _ mail: String, _ phone: String, _ password: String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("", selection: $usingEmail) {
                    Text("Email").tag(true)
                    Text("Téléphone").tag(false)
                }
                .pickerStyle(.segmented)

                if usingEmail {
                    TextField("Email", text: $mail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                } else {
                    TextField("Téléphone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                SecureField("Mot de passe", text: $password)

                if showError {
                    Text(errorText)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Connexion")
                    }
                }
                .disabled(viewModel.isLoading || !canSubmit)

                Button("Mot de passe oublié ?", action: onForgotPassword)
                    .disabled(viewModel.isLoading)

                Button("Créer un compte", action: onRegister)
                    .disabled(viewModel.isLoading)

                Button("Continuer avec Google") {
                    Task { await signInWithGoogle() }
                }
                .disabled(viewModel.isLoading)
            }
            .padding()
        }
        // Signature à un seul paramètre : la cible de déploiement est iOS 16 (project.yml), la
        // variante (oldValue, newValue) de `.onChange` n'existe qu'à partir d'iOS 17.
        .onChange(of: viewModel.user) { newUser in
            guard let newUser else { return }
            handle(newUser)
        }
    }

    private var canSubmit: Bool {
        let identifier = usingEmail ? mail : phone
        return !identifier.isEmpty && !password.isEmpty
    }

    /// Port de `LoginFragment.launchCredentialManager`/`firebaseAuthWithGoogle`/`updateUI`, via
    /// `GoogleSignInCoordinator` (partagé avec `SignUpWithGoogleView.swift`).
    private func signInWithGoogle() async {
        guard let presenter = UIApplication.shared.rootViewController else { return }
        guard let googleUser = try? await GoogleSignInCoordinator.signIn(presenting: presenter) else { return }
        await viewModel.loginWithGoogle(providerId: googleUser.providerId, email: googleUser.email ?? "", provider: "google")
    }

    private func submit() async {
        showError = false
        // Équivalent de Settings.setBooleanPreference(context, infoContract.USING_EMAIL, usingEmail)
        // (setting/Settings.java, module 17 — pas encore porté). Un seul flag booléen, pas assez
        // pour justifier d'anticiper tout le module Réglages : écrit directement en UserDefaults
        // sous la même clé, à migrer vers le futur `Settings.swift` quand ce module sera atteint.
        UserDefaults.standard.set(usingEmail, forKey: "USING_EMAIL")
        var user = User()
        user.username = usingEmail ? mail : phone
        user.password = password
        let provider = usingEmail ? "email" : "phone"
        await viewModel.login(username: user.username ?? "", password: password, provider: provider)
    }

    /// Port du bloc `if(u.getEtat().equals(...))` de `LoginFragment.CreateSyncAccount`.
    private func handle(_ user: User) {
        switch user.etat {
        case "Login Successful":
            // Sauvegarde SYNCHRONE de la session AVANT de naviguer (voir `AuthSessionPersistence.
            // saveSession` — corrige la race condition qui laissait `UserSession.shared.myId` nil
            // au premier chargement de ProfileView/FeedView, écran Profil vide sur Appetize).
            AuthSessionPersistence.saveSession(user)
            Task { await AuthSessionPersistence.persist(user) }
            onLoginSuccess(user)
        case "Email not verified":
            onEmailNotVerified(usingEmail, mail, phone, password)
        case "Invalid credential":
            password = ""
            errorText = "Mot de passe incorrect" // R.string.Nomdp
            showError = true
        case "User not exist":
            password = ""
            errorText = "Aucun compte associé" // R.string.Nocompte
            showError = true
        case "NoConnect":
            password = ""
            errorText = "Connexion impossible" // R.string.NoConnect
            showError = true
        default:
            break
        }
    }
}
