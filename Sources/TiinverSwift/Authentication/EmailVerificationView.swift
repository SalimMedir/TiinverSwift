import SwiftUI

/// Port de `Authentification/EmailVerificatiionCode.java`.
///
/// Point de flux confirmé en lisant le code source (pas deviné) : cet écran (position 7) est
/// utilisé par DEUX flux distincts selon `action` — après inscription (`action == "signin"` :
/// vérifie puis appelle `AuthViewModel.login`) et avant réinitialisation de mot de passe
/// (`action == "forgotpassword"` : vérifie puis route vers `NewPasswordView`, position 6, avec
/// le code de vérification en paramètre). Le champ `verifyUserByPhone()` de l'original est un
/// no-op (code mort commenté, vérification téléphonique jamais implémentée côté serveur à ce
/// jour) — reproduit tel quel : rien n'est envoyé si `usingEmail == false`.
///
/// `code`/`static_code` (générateur pseudo-aléatoire local, jamais utilisé nulle part dans le
/// fichier) sont du code mort côté Android — la vérification réelle passe entièrement par le
/// serveur (`verifyemail`). Non reproduits.
struct EmailVerificationView: View {
    let usingEmail: Bool
    let mail: String
    let phone: String
    let password: String
    let action: String // "signin" | "forgotpassword"

    @StateObject private var authViewModel = AuthViewModel()
    @State private var code = ""
    @State private var errorText: String?
    @State private var isVerifying = false
    @State private var secondsRemaining = 60

    var onLoginSuccess: (User) -> Void
    var onForgotPasswordVerified: (_ usingEmail: Bool, _ verificationCode: String) -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Text(usingEmail ? "Un code vous a été envoyé par email" : "Un code vous a été envoyé par SMS")
                // R.string.code_msg_body_by_mail / R.string.codemsgbody
            Text("Saisissez le code reçu") // R.string.code_msg_foot

            TextField("Code", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .onChange(of: code) { newValue in
                    errorText = nil
                    if newValue.count == 4 { Task { await verify(newValue) } }
                }

            if isVerifying { ProgressView() }
            if let errorText { Text(errorText).foregroundStyle(.red) }

            if secondsRemaining > 0 {
                Text(timeString(secondsRemaining))
            } else {
                Button("Renvoyer le code") { // click_here
                    Task { await sendCode() }
                }
            }
        }
        .padding()
        .task { await sendCode() }
        .onReceive(timer) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
        }
        .onChange(of: authViewModel.user) { newUser in
            guard action == "signin", let newUser, newUser.etat == "Login Successful" else { return }
            AuthSessionPersistence.saveSession(newUser) // voir LoginView.swift, même correction race condition
            Task { await AuthSessionPersistence.persist(newUser) } // port de CreateSyncAccount (EmailVerificatiionCode.java)
            onLoginSuccess(newUser)
        }
    }

    /// Port de `sendCode()`.
    private func sendCode() async {
        secondsRemaining = 60
        guard usingEmail else { return } // verifyUserByPhone() = no-op côté Android
        try? await VerificationEndpoints.sendOtp(email: mail, subject: "Code de vérification") // R.string.code_verification
    }

    /// Port de `verifyUserByMail(verificationCode)`.
    private func verify(_ code: String) async {
        isVerifying = true
        defer { isVerifying = false }
        guard let verified = try? await VerificationEndpoints.verifyEmail(verificationCode: code, email: mail), verified else {
            return
        }
        if action == "signin" {
            await login()
        } else if action == "forgotpassword" {
            onForgotPasswordVerified(usingEmail, code)
        }
    }

    /// Port de `login()`.
    private func login() async {
        UserDefaults.standard.set(usingEmail, forKey: "USING_EMAIL")
        let username = usingEmail ? mail : phone
        let provider = usingEmail ? "email" : "phone"
        await authViewModel.login(username: username, password: password, provider: provider)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
