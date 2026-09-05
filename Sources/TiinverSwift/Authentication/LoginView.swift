import AuthenticationServices
import SwiftUI

/// Port de `Authentification/login/LoginFragment.java` + `Authentification/view/LoginCompound.java`
/// + `res/layout/login_layout.xml` (les 3 lus intégralement pour ce correctif).
///
/// **Design refait (2026-08-31, PRIORITÉ 2)** — la version précédente de ce fichier n'avait PAS lu
/// `login_layout.xml` (son propre en-tête l'admettait explicitement : "non fourni") et avait inventé
/// une mise en page SwiftUI générique (`Picker` segmenté, champs sans style). Reconstruit ici depuis
/// le XML réel : titre "SE CONNECTER" en gras, champs encadrés (bordure rose 1pt, coins arrondis
/// 5pt, icône de tête teintée) plutôt que des `TextField` nus, bouton principal plein rose avec
/// coins arrondis 10pt, séparateur "— OU —", bouton Google encadré gris clair, liens
/// "mot de passe oublié"/"créer un compte" en rose gras. Couleurs reprises telles quelles de
/// `values/colors.xml` : `appColor`/`red` = `#ff4081` (accent principal, PAS un rouge malgré son
/// nom Android), `textColorPrimary` = `#212121`, `bubble_send_color` = `#ECAFC4` (fond du bandeau
/// d'erreur), bordure du bouton Google = `#747775`, `grey` = `#aaa` (séparateur).
///
/// **Authentification téléphone masquée intentionnellement** — voir `usingEmail` ci-dessous pour la
/// preuve exacte tirée du code Android : ce n'est PAS une régression par rapport à Android, c'est
/// une fidélité à son comportement RÉEL actuel.
///
/// **Connexion Google** (`GoogleSignInCoordinator.swift`) : câblée depuis que l'usage réel de
/// Firebase a été confirmé par investigation du code source Android (voir décision "Priorité 0"
/// dans MIGRATION_PROGRESS.md — `google-services.json` provisionné, dépendances Gradle réelles).
/// Aucun asset de marque Google réel n'existe dans ce dépôt iOS (`Assets.xcassets` vérifié, ni
/// `SignUpWithGoogleView.swift` n'en embarque un) — l'icône ci-dessous est un SF Symbol neutre en
/// remplacement, PAS une reproduction du logo Google officiel.
///
/// Non porté depuis l'original, volontairement, à ce stade :
/// - **Navigation** (`FragmentConnectionListener.onArticleSelected(int, Bundle)`, le routeur
///   d'écrans de l'app Android) : remplacée par des closures injectées par l'appelant
///   (`AuthCoordinatorView.swift`, module 5), qui reproduit fidèlement le routage par position.
/// - **`AccountManager`/`ContentResolver` local Android** (`CreateSyncAccount`) : spécifique à la
///   plomberie de comptes Android (sync adapter), sans équivalent fonctionnel sur iOS. Remplacé
///   par une écriture directe dans `UserSession`/`KeychainStore` (déjà écrits, module 1) et
///   `AccountEntity` (Core Data, module 2) — mêmes données persistées, mécanisme iOS natif.
struct LoginView: View {
    @StateObject private var viewModel = AuthViewModel()

    /// **Toujours `true`, volontairement PAS un `@State` togglable.** Preuve exacte, lue dans
    /// `LoginFragment.java:89` + `:192-198` : `boolean usingEmail=true;` (valeur de champ, jamais
    /// réassignée ailleurs dans tout le fichier — grep exhaustif de `usingEmail=`/`usingEmail =`
    /// confirmant zéro second site d'écriture) pilote directement la visibilité de
    /// `container_mail`/`container_phone` à `onViewCreated` — sans AUCUN élément d'interface pour
    /// faire basculer cette valeur (aucun bouton/icône de bascule dans `login_layout.xml`), Android
    /// affiche donc RÉELLEMENT, aujourd'hui, EXCLUSIVEMENT le champ e-mail, jamais le champ
    /// téléphone — confirmé par le constat produit indépendant de cette session ("l'authentification
    /// par numéro de téléphone n'est pas disponible actuellement"). Masquer le téléphone côté iOS
    /// n'est donc pas un écart avec Android : c'est une fidélité à son comportement OBSERVABLE réel,
    /// pas seulement à son code mort. Conservé comme constante plutôt que supprimé partout pour que
    /// `onEmailNotVerified`/`AuthViewModel.login` (signatures déjà partagées avec `RegisterView.swift`
    /// et `AuthCoordinatorView.swift`) n'aient pas besoin d'être retouchées pour ce correctif —
    /// périmètre strictement limité à CET écran, demandé explicitement.
    private let usingEmail = true
    @State private var mail = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorText = ""
    /// Pont entre les deux closures de `SignInWithAppleButton` (`onRequest`/`onCompletion`, voir
    /// `appleButton` ci-dessous) : le nonce BRUT généré au moment de la requête doit être conservé
    /// jusqu'à la réception du résultat, pour être transmis à `AppleSignInCoordinator.resolveUser`.
    @State private var pendingAppleNonce: String?

    var onLoginSuccess: (User) -> Void
    var onForgotPassword: () -> Void
    var onRegister: () -> Void
    /// Équivalent de la branche "Email not verified" de `CreateSyncAccount` — l'appelant route
    /// vers l'écran de confirmation de code avec les mêmes informations que
    /// `arg.putString("action","signin")`/`email`/`phone`/`password`/`usingEmail` côté Android.
    /// `phone` transmis vide, `usingEmail` toujours `true` — voir sa doc ci-dessus.
    var onEmailNotVerified: (_ usingEmail: Bool, _ mail: String, _ phone: String, _ password: String) -> Void

    // MARK: - Palette (port direct de `values/colors.xml`, voir doc de tête de fichier)

    private static let accent = Color(red: 0xFF / 255, green: 0x40 / 255, blue: 0x81 / 255) // appColor / red
    private static let textPrimary = Color(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255) // textColorPrimary
    private static let errorBubble = Color(red: 0xEC / 255, green: 0xAF / 255, blue: 0xC4 / 255) // bubble_send_color
    private static let googleBorder = Color(red: 0x74 / 255, green: 0x77 / 255, blue: 0x75 / 255) // #747775
    private static let googleText = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255) // #1F1F1F
    private static let divider = Color(red: 0xAA / 255, green: 0xAA / 255, blue: 0xAA / 255) // grey

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Port du titre (`TextView` à côté du logo — logo `visibility="gone"` dans le XML
                // Android, jamais affiché en pratique, donc pas reproduit ici non plus) —
                // `textAllCaps="true"`, gras, 25sp.
                Text(NSLocalizedString("auth_sign_in", comment: "Titre écran de connexion"))
                    .font(.system(size: 25, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Self.textPrimary)
                    .padding(.top, 8)

                if showError {
                    errorBanner(errorText)
                } else if let networkError = viewModel.errorMessage {
                    errorBanner(networkError)
                }

                fieldBox(systemIcon: "envelope.fill") {
                    TextField(NSLocalizedString("auth_email", comment: "Champ email"), text: $mail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disabled(viewModel.isLoading)
                }

                fieldBox(systemIcon: "lock.fill") {
                    SecureField(NSLocalizedString("auth_password", comment: "Champ mot de passe"), text: $password)
                        .disabled(viewModel.isLoading)
                }

                primaryButton

                HStack(spacing: 8) {
                    Rectangle().fill(Self.divider).frame(height: 1)
                    Text(NSLocalizedString("auth_or", comment: "Séparateur entre connexion email et Google/Apple"))
                        .font(.system(size: 14))
                        .foregroundStyle(Self.divider)
                    Rectangle().fill(Self.divider).frame(height: 1)
                }
                .padding(.vertical, 8)

                googleButton
                appleButton

                VStack(spacing: 6) {
                    Button(NSLocalizedString("auth_forgot_password", comment: "Lien mot de passe oublié"), action: onForgotPassword)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Self.accent)
                        .disabled(viewModel.isLoading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Port du grand espacement Android (`layout_marginTop="200dp"` sur le conteneur du
                // bouton d'inscription) — sépare volontairement ce lien du reste du formulaire.
                Button(NSLocalizedString("auth_signup_linkto", comment: "Lien vers l'inscription"), action: onRegister)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Self.accent)
                    .disabled(viewModel.isLoading)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(Color.white)
        // Signature à un seul paramètre : la cible de déploiement est iOS 16 (project.yml), la
        // variante (oldValue, newValue) de `.onChange` n'existe qu'à partir d'iOS 17.
        .onChange(of: viewModel.user) { newUser in
            guard let newUser else { return }
            handle(newUser)
        }
    }

    // MARK: - Sous-vues

    private func errorBanner(_ text: String) -> some View {
        // Port de `error.setBackground(bubble_incoming)` — pilule arrondie, fond
        // `bubble_send_color`, texte blanc.
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Self.errorBubble, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Port du style commun des 3 champs Android (`stroke_btn_background` : bordure 1dp `red`,
    /// fond blanc, coins 5dp) + icône de tête teintée `red` (`ic_phone`/`ic_mail`/`ic_lock`) — un
    /// seul champ affiché ici (e-mail), le conteneur téléphone n'est jamais instancié (voir doc de
    /// tête sur `usingEmail`).
    private func fieldBox<Content: View>(systemIcon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemIcon)
                .foregroundStyle(Self.accent)
                .frame(width: 20)
            content()
                .foregroundStyle(Self.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Self.accent, lineWidth: 1))
        )
    }

    /// Port du bouton principal (`relativebutton`/`fill_btn_background` : fond plein `appColor`,
    /// coins 10dp) — texte "SE CONNECTER" gras majuscule blanc, remplacé par "CHARGEMENT..." +
    /// spinner pendant `mLoginProgress`/`buttonText` (`onResume`'s listener de clic), fidèle au
    /// changement de texte Android (`getString(R.string.loading)`), pas seulement un spinner nu.
    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView().tint(.white)
                    Text(NSLocalizedString("auth_loading", comment: "État de chargement du bouton de connexion"))
                } else {
                    Text(NSLocalizedString("auth_sign_in", comment: "Bouton de connexion"))
                }
            }
            .textCase(.uppercase)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .background(Self.accent, in: RoundedRectangle(cornerRadius: 10))
        .disabled(viewModel.isLoading || !canSubmit)
    }

    /// Port de `signin2`/`google_fill_btn_background` : fond blanc, bordure grise 1dp, coins 10dp.
    /// Icône Google réelle absente de ce dépôt (voir doc de tête) — SF Symbol neutre en attendant.
    private var googleButton: some View {
        Button {
            Task { await signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Self.googleText)
                Text(NSLocalizedString("auth_sign_in_with_google", comment: "Bouton connexion Google"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Self.googleText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.googleBorder, lineWidth: 1))
        )
        .disabled(viewModel.isLoading)
    }

    /// "Sign in with Apple" — composant NATIF `SignInWithAppleButton` (`AuthenticationServices`),
    /// pas un bouton redessiné à la main comme `googleButton` ci-dessus (qui n'a, lui, aucun
    /// équivalent système à réutiliser) : respecte par construction les Human Interface Guidelines
    /// Apple (typographie/marges/comportement du logo  imposés par le système, non personnalisables
    /// — précisément ce que les HIG demandent). `.frame(height: 50)`/coins 10pt alignés sur
    /// `googleButton` juste au-dessus pour une taille et une visibilité équivalentes entre les deux
    /// boutons de connexion tierce, comme demandé.
    ///
    /// `onRequest`/`onCompletion` délèguent la configuration (nonce/portée) et la résolution
    /// (échange Firebase) à `AppleSignInCoordinator.configureRequest(_:)`/`resolveUser(from:rawNonce:)`
    /// — CE bouton gère son propre `ASAuthorizationController`/sa propre présentation en interne (il
    /// n'y a donc pas de second contrôleur créé ici), mais la logique nonce/Firebase reste
    /// STRICTEMENT identique à `AppleSignInCoordinator.signIn(presenting:)` (chemin non-UI du même
    /// service), aucune duplication.
    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            pendingAppleNonce = AppleSignInCoordinator.configureRequest(request)
        } onCompletion: { result in
            Task { await handleAppleSignIn(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .cornerRadius(10)
        .disabled(viewModel.isLoading)
    }

    // MARK: - Logique (inchangée fonctionnellement, voir version précédente de ce fichier)

    private var canSubmit: Bool { !mail.isEmpty && !password.isEmpty }

    /// Port de `LoginFragment.launchCredentialManager`/`firebaseAuthWithGoogle`/`updateUI`, via
    /// `GoogleSignInCoordinator` (partagé avec `SignUpWithGoogleView.swift`).
    private func signInWithGoogle() async {
        guard let presenter = UIApplication.shared.rootViewController else { return }
        guard let googleUser = try? await GoogleSignInCoordinator.signIn(presenting: presenter) else { return }
        await viewModel.loginWithGoogle(providerId: googleUser.providerId, email: googleUser.email ?? "", provider: "google")
    }

    /// Port du résultat de `SignInWithAppleButton` (`appleButton` ci-dessus) — même point d'arrivée
    /// que `signInWithGoogle()` : `AuthViewModel.loginWithGoogle(providerId:email:provider:)` est
    /// générique côté réseau (voir `AuthEndpoints.swift`, `provider` est un `String` arbitraire déjà
    /// envoyé tel quel — accepté sans restriction par le backend, confirmé par le propriétaire du
    /// projet), réutilisé ici avec `provider: "apple"` plutôt que dupliqué.
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        guard let nonce = pendingAppleNonce else { return }
        pendingAppleNonce = nil
        guard case .success(let authorization) = result,
              let appleUser = try? await AppleSignInCoordinator.resolveUser(from: authorization, rawNonce: nonce)
        else { return }
        // Persisté AVANT l'appel réseau — voir `UserSession.appleUserIdentifier`, nécessaire à
        // `AppleSignInCoordinator.checkCredentialStateAtLaunch()` dès la prochaine ouverture de
        // l'app, y compris si l'utilisateur quitte l'app avant que la navigation post-login n'ait
        // eu lieu (cohérent avec la sauvegarde SYNCHRONE de session déjà pratiquée par `handle(_:)`
        // ci-dessous, voir `AuthSessionPersistence.saveSession`).
        UserSession.shared.appleUserIdentifier = appleUser.appleUserIdentifier
        await viewModel.loginWithGoogle(providerId: appleUser.providerId, email: appleUser.email ?? "", provider: "apple")
    }

    private func submit() async {
        showError = false
        // Équivalent de Settings.setBooleanPreference(context, infoContract.USING_EMAIL, usingEmail)
        // (setting/Settings.java, module 17 — pas encore porté). Un seul flag booléen, pas assez
        // pour justifier d'anticiper tout le module Réglages : écrit directement en UserDefaults
        // sous la même clé, à migrer vers le futur `Settings.swift` quand ce module sera atteint.
        UserDefaults.standard.set(usingEmail, forKey: "USING_EMAIL")
        var user = User()
        user.username = mail
        user.password = password
        await viewModel.login(username: user.username ?? "", password: password, provider: "email")
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
            onEmailNotVerified(usingEmail, mail, "", password)
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
