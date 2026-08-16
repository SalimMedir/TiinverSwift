import Foundation

/// Port des appels réseau de `Authentification/EmailVerificatiionCode.java` +
/// `Authentification/passwordrecovery/mdpOublier.java` (SuccessRequest, envoi d'email de
/// confirmation). Utilise le client générique (`APIClient.post`, en-têtes standard avec
/// `Authorization` si une session existe) — PAS `postAuth` : ces écrans utilisent
/// `new TransportData(...)` côté Android, pas `AutentificationWenack`, contrairement aux 5
/// endpoints de `AuthEndpoints.swift`.
enum VerificationEndpoints {
    /// Port de `EmailVerificatiionCode.sendOtp()` (endpoint "sendotp").
    static func sendOtp(email: String, subject: String) async throws {
        let params = [
            "to": email,
            "subject": subject,
            "message": "Tiinver code :",
            "header": "support@tiinver.com" // infoContract.MAIL
        ]
        _ = try await APIClient.shared.post(params, endpoint: "sendotp")
    }

    /// Port de `EmailVerificatiionCode.verifyUserByMail(verificationCode)` (endpoint "verifyemail").
    /// Retourne `true` si `error == "false" && message == "verification passed"`, à l'identique.
    static func verifyEmail(verificationCode: String, email: String) async throws -> Bool {
        let params = ["verificationCode": verificationCode, "email": email, "checkBy": "email"]
        let json = try await APIClient.shared.post(params, endpoint: "verifyemail")
        // 2026-08-17 : `errorFieldNormalized` — même précaution que `AuthEndpoints` (voir
        // `JSONValue.swift`), ce module partage le même backend d'authentification que `login`
        // (confirmé booléen JSON natif sur "error").
        return json.errorFieldNormalized == "false" && json.backendErrorMessage == "verification passed"
    }

    /// Port de `mdpOublier.SuccessRequest` (envoi de l'email de confirmation de changement de
    /// mot de passe, endpoint générique "mail").
    static func sendMail(to: String, subject: String, message: String) async throws {
        let params = ["to": to, "subject": subject, "message": message]
        _ = try await APIClient.shared.post(params, endpoint: "mail")
    }
}
