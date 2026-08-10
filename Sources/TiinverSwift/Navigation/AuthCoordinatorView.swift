import SwiftUI

/// Port du routeur `Authentification/MainActivity.java implements FragmentConnectionListener`
/// (`onArticleSelected(int position, Bundle)`, switch à 9 cas, chaque `Fragment` remplacé dans
/// `R.id.login_container` avec `addToBackStack(null)`).
///
/// `NavigationStack` + une pile `[AuthScreen]` reproduit fidèlement le comportement
/// `replace(...).addToBackStack(null)` d'Android (empilement, retour arrière possible), plutôt
/// qu'un simple `@State var currentScreen` qui perdrait l'historique.
///
/// **Correspondance des positions vérifiée dans le code source** (pas devinée) :
/// 0=PoliticaDemand (écran de démarrage, `onArticleSelected(0,null)` appelé dans `onCreate`),
/// 1=Onboarding, 2=SignUpWithGoogle, 3=SignupFragment (inscription), 4=LoginFragment,
/// 5=MyCodeConfirmFragment (voir décision : DEAD CODE, non porté), 6=mdpOublier
/// (`NewPasswordView`, saisie du nouveau mot de passe), 7=EmailVerificatiionCode
/// (`EmailVerificationView`, vérification de code — utilisé par DEUX flux : après inscription
/// ET avant réinitialisation de mot de passe), 8=RecoverPassword (`ForgotPasswordRequestView`,
/// saisie email/téléphone pour lancer la récupération).
///
/// **Flux mot de passe oublié reconstitué en lisant les 3 fichiers ensemble** (ce qui avait été
/// noté comme un "point non-évident"/possible incohérence dans une version antérieure de ce
/// fichier s'avère être le flux normal, pas un bug) : Login "mot de passe oublié" → position 8
/// (saisie email/téléphone) → position 7 (vérification du code, `action=forgotpassword`) →
/// position 6 (saisie du nouveau mot de passe) → retour position 4. `mdpOublier`/position 6 EST
/// bien atteint, juste pas directement depuis `LoginView` — la dénomination française
///("mdpOublier" = la DERNIÈRE étape, "RecoverPassword" = la PREMIÈRE) explique la confusion
/// initiale, pas un bug Android.
enum AuthScreen: Hashable {
    case politicaDemand      // 0
    case onboarding          // 1
    case signUpWithGoogle    // 2
    case register            // 3
    case login                // 4
    case forgotPasswordNewPassword(usingEmail: Bool, email: String, phone: String, verificationCode: String) // 6
    case emailVerification(usingEmail: Bool, mail: String, phone: String, password: String, action: String) // 7
    case recoverPasswordRequest // 8
}

struct AuthCoordinatorView: View {
    @State private var path: [AuthScreen] = []
    var onAuthenticated: (User) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            screen(for: .politicaDemand)
                .navigationDestination(for: AuthScreen.self) { screen(for: $0) }
        }
    }

    @ViewBuilder
    private func screen(for screen: AuthScreen) -> some View {
        switch screen {
        case .politicaDemand:
            PoliticaDemandView {
                path.append(.onboarding) // butAcceptarPolitica → position 1
            }
        case .onboarding:
            OnboardingView {
                path.append(.signUpWithGoogle) // nextbtn (dernière page) / skipbtn → position 2
            }
        case .signUpWithGoogle:
            SignUpWithGoogleView(
                onRegistered: { user in onAuthenticated(user) },
                onContinueWithEmail: { path.append(.register) }, // signup2 → position 3
                onLogin: { popToLogin() }                        // login → position 4
            )
        case .register:
            RegisterView(
                onRegistered: { usingEmail, mail, phone, password in
                    // → position 7, action=signin (SignupFragment.registerResponse)
                    path.append(.emailVerification(usingEmail: usingEmail, mail: mail, phone: phone, password: password, action: "signin"))
                },
                onLogin: { popToLogin() } // login → position 4
            )
        case .login:
            LoginView(
                onLoginSuccess: { user in onAuthenticated(user) },
                onForgotPassword: { path.append(.recoverPasswordRequest) }, // position 8
                onRegister: { path.append(.signUpWithGoogle) },             // position 2
                onEmailNotVerified: { usingEmail, mail, phone, password in
                    path.append(.emailVerification(usingEmail: usingEmail, mail: mail, phone: phone, password: password, action: "signin"))
                }
            )
        case let .recoverPasswordRequest:
            ForgotPasswordRequestView(
                onSubmit: { usingEmail, mail, phone in
                    // → position 7, action=forgotpassword (RecoverPassword.clicOub)
                    path.append(.emailVerification(usingEmail: usingEmail, mail: mail, phone: phone, password: "", action: "forgotpassword"))
                },
                onBack: { popToLogin() } // suivantOub → position 4
            )
        case let .emailVerification(usingEmail, mail, phone, password, action):
            EmailVerificationView(
                usingEmail: usingEmail, mail: mail, phone: phone, password: password, action: action,
                onLoginSuccess: { user in onAuthenticated(user) },
                onForgotPasswordVerified: { usingEmail, verificationCode in
                    // → position 6 (EmailVerificatiionCode.verifyUserByMail, branche forgotpassword)
                    path.append(.forgotPasswordNewPassword(usingEmail: usingEmail, email: mail, phone: phone, verificationCode: verificationCode))
                }
            )
        case let .forgotPasswordNewPassword(usingEmail, email, phone, verificationCode):
            NewPasswordView(
                usingEmail: usingEmail, email: email, phone: phone, verificationCode: verificationCode,
                onBackToLogin: { popToLogin() } // suivantOub → position 4
            )
        }
    }

    /// Équivalent des multiples `mCallback.onArticleSelected(4, ...)` de l'original — retourne à
    /// l'écran de connexion en vidant la pile plutôt qu'en empilant un nouveau Login par-dessus
    /// (le `FragmentManager` Android, via `findFragmentByTag`, réutilise l'instance existante si
    /// déjà présente ; `NavigationStack` n'a pas cette déduplication automatique par tag — vider
    /// la pile jusqu'à Login reproduit le même résultat observable).
    private func popToLogin() {
        path = [.login]
    }
}
