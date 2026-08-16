import SwiftUI

/// Port de `Authentification/register/SignupFragment.java` + `view/RegisterCompound.java`.
///
/// `Authentification/register/Inscrire.java` et `register/phoneNumber.java` NON portés — confirmés
/// morts par grep (zéro `new Inscrire(`/`new phoneNumber(` dans tout le dépôt).
///
/// PAS porté ici, volontairement : bannière AdMob (`loadBanner`/`initializeMobileAdsSdk`, module
/// 16) ; log Facebook Ads `AppEventsConstants.EVENT_NAME_COMPLETED_REGISTRATION` (SDK Facebook
/// pas encore choisi/câblé, hors périmètre de ce module) ; navigation réelle (closures, comme
/// `LoginView.swift`).
struct RegisterView: View {
    @StateObject private var viewModel = AuthViewModel()

    @State private var usingEmail = true
    @State private var fullname = ""
    @State private var mail = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var errorText: String?

    var onRegistered: (_ usingEmail: Bool, _ mail: String, _ phone: String, _ password: String) -> Void
    var onLogin: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TextField("Nom complet", text: $fullname) // R.id.fullname

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
                SecureField("Confirmer le mot de passe", text: $passwordConfirm)

                // Même correctif que `SignUpWithGoogleView.swift` (2026-08-16, captures Appetize) :
                // `viewModel.errorMessage` (réseau/transport, alimenté par `AuthViewModel.run`'s
                // `catch`) n'était jamais rendu ici, seul `errorText` local (alimenté uniquement
                // par `handle(_:)`, jamais appelé si `register()` lève une exception au lieu de
                // retourner un `User`) — un échec de `register()` restait invisible.
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                } else if let networkError = viewModel.errorMessage {
                    Text(networkError).foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Inscription") // R.string.inscription
                    }
                }
                .disabled(viewModel.isLoading)

                Button("Déjà un compte ? Se connecter", action: onLogin) // login.setOnClickListener → position 4
            }
            .padding()
        }
        .onChange(of: viewModel.user) { newUser in
            guard let newUser else { return }
            handle(newUser)
        }
    }

    /// Port de `SignupFragment.thereIsFieldEmpty` + `isMailValid`/`isValidPhoneNumber` (mêmes
    /// expressions régulières que l'original).
    private func validate() -> Bool {
        guard !fullname.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorText = "Le nom complet est requis" // R.string.fullname + R.string.empty
            return false
        }
        if usingEmail {
            guard !mail.isEmpty else { errorText = "L'email est requis"; return false }
        } else {
            guard !phone.isEmpty else { errorText = "Le téléphone est requis"; return false }
        }
        guard !password.isEmpty else { errorText = "Le mot de passe est requis"; return false }
        guard !passwordConfirm.isEmpty else { errorText = "La confirmation est requise"; return false }
        guard password == passwordConfirm else {
            errorText = "Les mots de passe ne correspondent pas" // R.string.mdpDiff
            return false
        }
        if usingEmail {
            guard isMailValid(mail) else {
                errorText = "Email invalide" // R.string.NoValidMail
                return false
            }
        } else {
            guard isValidPhoneNumber(phone) else {
                errorText = "Numéro invalide" // R.string.NoValidPhoneNumber
                return false
            }
        }
        return true
    }

    private func isMailValid(_ email: String) -> Bool {
        let pattern = #"^[_A-Za-z0-9-\+]+(\.[_A-Za-z0-9-]+)*@[A-Za-z0-9-]+(\.[A-Za-z0-9]+)*(\.[A-Za-z]{2,})$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidPhoneNumber(_ number: String) -> Bool {
        let pattern = #"^\s*(?:\+?(\d{1,3}))?[-. (]*(\d{3})[-. )]*(\d{3})[-. ]*(\d{1,5})(?: *x(\d+))?\s*$"#
        return number.range(of: pattern, options: .regularExpression) != nil
    }

    private func submit() async {
        errorText = nil
        guard validate() else { return }

        // Équivalent de Settings.setBooleanPreference(context, infoContract.USING_EMAIL, usingEmail)
        // — voir décision déjà documentée pour LoginView.swift (module 3).
        UserDefaults.standard.set(usingEmail, forKey: "USING_EMAIL")

        var user = User()
        user.email = mail.trimmingCharacters(in: .whitespaces)
        user.phone = phone.trimmingCharacters(in: .whitespaces)
        user.password = password
        user.fullname = fullname.trimmingCharacters(in: .whitespaces)
        user.username = StringManager.username(fromFullname: user.fullname ?? "")
        // Port de Settings.getStringPreferenceForReferredBy(activity, infoContract.REFERRED_BY)
        // (écrit par SplashActivity depuis l'Install Referrer API — module non porté ici).
        user.referredBy = UserDefaults.standard.string(forKey: "REFERRED_BY")

        let provider = usingEmail ? "email" : "phone"
        await viewModel.register(user: user, provider: provider)
    }

    /// Port de `SignupFragment.registerResponse`.
    private func handle(_ user: User) {
        switch user.etat {
        case "User created successfully":
            onRegistered(usingEmail, mail, phone, password) // → position 7 (EmailVerification), arg action=signin
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
