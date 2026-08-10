import SwiftUI

/// Port de `Authentification/passwordrecovery/mdpOublier.java` (position 6 — dernière étape du
/// flux mot de passe oublié : saisie du nouveau mot de passe, après vérification du code par
/// `EmailVerificationView`, position 7).
struct NewPasswordView: View {
    let usingEmail: Bool
    let email: String
    let phone: String
    let verificationCode: String

    @StateObject private var viewModel = AuthViewModel()
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorText: String?
    @State private var infoMessage: String?

    var onBackToLogin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            SecureField("Nouveau mot de passe", text: $newPassword) // mdpOub
            SecureField("Confirmer le mot de passe", text: $confirmPassword) // mdpConfOub

            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
            if let infoMessage {
                Text(infoMessage) // infomdpOub
            }

            Button("Valider") { // relativebutton
                Task { await submit() }
            }
            .disabled(viewModel.isLoading)

            Button("Retour à la connexion", action: onBackToLogin) // suivantOub → position 4
        }
        .padding()
        .onChange(of: viewModel.user) { newUser in
            guard let newUser else { return }
            handle(newUser)
        }
    }

    /// Port de `clicOub` (mdpOublier.java).
    private func submit() async {
        errorText = nil
        guard newPassword == confirmPassword else {
            errorText = "Les mots de passe ne correspondent pas" // R.string.mdpDiff
            return
        }

        var user = User()
        if usingEmail {
            user.email = email
            user.password = newPassword
            user.verificationCode = verificationCode
        } else {
            user.phone = phone
            user.password = newPassword
        }
        await viewModel.passwordForgotten(user: user, usingEmail: usingEmail)
    }

    /// Port de `mdpOublier.SuccessRequest`.
    private func handle(_ user: User) {
        switch user.etat {
        case "Password Changed":
            let message = "Votre nouveau mot de passe : \(newPassword)" // R.string.infoMdpNv + password
            infoMessage = message
            newPassword = ""
            confirmPassword = ""
            if usingEmail {
                Task {
                    try? await VerificationEndpoints.sendMail(
                        to: email,
                        subject: "Changement de mot de passe", // R.string.password_change
                        message: message
                    )
                }
            }
        case "user not found":
            errorText = "Aucun compte associé" // R.string.Nocompte
            newPassword = ""
            confirmPassword = ""
        case "NoConnect":
            errorText = "Connexion impossible" // R.string.NoConnect
            newPassword = ""
            confirmPassword = ""
        default:
            break
        }
    }
}
