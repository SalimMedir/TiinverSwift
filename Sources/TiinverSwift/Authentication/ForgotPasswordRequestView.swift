import SwiftUI

/// Port de `Authentification/passwordrecovery/RecoverPassword.java` (position 8 — première étape
/// du flux mot de passe oublié : saisie email/téléphone, envoi vers la vérification par code).
struct ForgotPasswordRequestView: View {
    @State private var usingEmail = true
    @State private var mail = ""
    @State private var phone = ""

    var onSubmit: (_ usingEmail: Bool, _ mail: String, _ phone: String) -> Void
    var onBack: () -> Void

    var body: some View {
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

            Button("Envoyer") {
                // Port fidèle d'un comportement probablement non intentionnel de l'original :
                // `clicOub` vérifie TOUJOURS `!mail.isEmpty()` (le champ email), même en mode
                // téléphone (`usingEmail == false`), où ce champ est vide/masqué — la
                // récupération par téléphone est donc silencieusement bloquée côté Android aussi.
                // Reproduit tel quel, PAS corrigé (règle du portage : ne pas "réparer" un
                // comportement observé sans confirmation explicite de l'utilisateur).
                guard !mail.isEmpty else { return }
                // Port de Settings.deleteSinglePreference(activity, infoContract.OTP) — aucun code
                // OTP local mis en cache par ce portage (le module Réglages/OTP local n'existe
                // pas encore), donc rien à supprimer ici : no-op fidèle à l'absence d'état.
                onSubmit(usingEmail, mail, phone) // → position 7, action=forgotpassword
            }

            Button("Retour", action: onBack) // suivantOub → position 4
        }
        .padding()
    }
}
