import Foundation

/// Développement NOUVEAU (module 12) — AUCUN équivalent Android : contrairement au jeton FCM
/// (`Notifications/PushTokenRegistrar.swift`, port réel de `MyFirebaseInstanceIdService`, poussé
/// vers l'endpoint générique `user` avec `column="fcmId"`), le jeton VoIP PushKit n'existe QUE côté
/// iOS — Android n'a pas de notion de jeton PushKit à enregistrer, donc pas de méthode Android à
/// porter ici. Endpoint DÉDIÉ choisi plutôt que de réutiliser le motif générique `user`/`column`
/// (qui existe et pourrait aussi convenir, voir note ci-dessous) — décision explicite du
/// développeur, pas une convention Android à respecter.
///
/// **PAS l'implémentation serveur** — ce fichier ne fait qu'appeler l'endpoint, il ne le définit
/// pas. Le backend PHP/Slim est un projet séparé, voir MIGRATION_PROGRESS.md section "Backend à
/// implémenter — PushKit/VoIP" pour la spécification complète à donner à l'équipe serveur.
enum VoIPTokenRegistrar {
    /// Port du point d'enregistrement (voir `VoIPPushManagerDelegate.voIPPushManager(_:didUpdateToken:)`,
    /// câblé dans `CallCoordinator`) — envoie le jeton PushKit hex-encodé au backend dès qu'il est
    /// (re)délivré par `PKPushRegistry` (à l'inscription initiale ET à chaque rotation, `PushKit`
    /// peut redonner un jeton différent, contrairement à APNs classique où c'est moins fréquent).
    ///
    /// **Endpoint** : `POST user/voip-token`
    /// **Corps** (mêmes conventions `[String:String]`+`JSONEncoding` que tout `APIClient.post`,
    /// voir `Networking/APIClient.swift`) :
    /// ```json
    /// { "userId": "<UserSession.shared.myId>", "voipToken": "<jeton hex 64 caractères>" }
    /// ```
    /// **PAS implémenté côté serveur** — voir MIGRATION_PROGRESS.md.
    static func register(_ token: Data) async {
        guard let userId = UserSession.shared.myId else { return }
        let params = ["userId": userId, "voipToken": Self.hexString(token)]
        _ = try? await APIClient.shared.post(params, endpoint: "user/voip-token")
    }

    /// Port de la convention APNs standard (jeton device transmis en hexadécimal minuscule, pas en
    /// Base64) — c'est le format attendu par la quasi-totalité des intégrations serveur APNs/VoIP,
    /// y compris celles basées sur des bibliothèques PHP courantes (`pushok`/`edamov/pushok` par
    /// exemple) ; documenté ici plutôt que deviné silencieusement puisqu'aucune implémentation
    /// serveur Android équivalente n'existe pour trancher le format par lecture de source.
    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
