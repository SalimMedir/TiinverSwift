import Foundation
import FirebaseMessaging

/// Port de `back_sync/MyFirebaseInstanceIdService.java` (enregistrement du jeton push côté
/// serveur) — via **Firebase Cloud Messaging**, pas APNs brut.
///
/// **Décision Priorité 0 tranchée par investigation du code source Android (pas une supposition)** :
/// - `app/build.gradle` déclare `implementation 'com.google.firebase:firebase-messaging:25.0.1'`
///   ET `implementation("com.google.firebase:firebase-auth")`, plus `apply plugin:
///   'com.google.gms.google-services'` — dépendances réelles, pas du code mort.
/// - `MyFirebaseInstanceIdService.requestNewFCMToken` appelle explicitement
///   `FirebaseMessaging.getInstance().getToken()` (PAS un jeton APNs traduit manuellement) et
///   pousse ce jeton FCM vers la colonne backend `fcmId` via l'endpoint générique `user`.
/// - `app/google-services.json` existe avec un VRAI projet Firebase provisionné
///   (`project_id: "com-tiinver"`, `project_number: "837038293145"`) — et surtout, ce fichier
///   déclare DÉJÀ une app iOS dans Firebase (`services.appinvite_service.
///   other_platform_oauth_client[].ios_info.bundle_id = "com.tiinver.tiinverProject"`), preuve
///   qu'une app iOS Firebase a été anticipée/provisionnée avant ce portage.
/// - `TIINVER_IOS_PORT_ANALYSIS.md` liste explicitement "Notifications push (Firebase iOS
///   SDK/APNs, deep links)" comme ligne de le plan de portage, et recommande le "SDK iOS officiel"
///   pour Firebase Remote Config (même service Firebase, donc même logique pour Messaging/Auth).
///
/// Conclusion : Firebase Cloud Messaging CONFIRMÉ comme mécanisme réel (pas hypothétique) —
/// `PushTokenRegistrar` bascule sur `FirebaseMessaging`, `project.yml` inclut déjà les packages
/// `Firebase`/`GoogleSignIn` (ajoutés dès le module 1, jamais câblés jusqu'ici).
///
/// **Mise à jour du 2026-08-10** : le bundle id iOS réel est CONFIRMÉ `com.tiinver.ios` (clé
/// `BUNDLE_ID` de `Resources/GoogleService-Info.plist`, fichier fourni par l'utilisateur) —
/// corrige la valeur `com.tiinver.tiinverProject` notée ci-dessus, qui n'était qu'une déduction
/// indirecte depuis un identifiant d'app invite secondaire côté Android, pas le vrai bundle id.
/// `project.yml` mis à jour en conséquence. Voir MIGRATION_PROGRESS.md pour le détail.
enum PushTokenRegistrar {
    // Même clé que Settings.setStringPreference(context,"fcmId",token) côté Android.
    // `setting/Settings.java` (module 17) pas encore porté — UserDefaults direct comme dans
    // LoginView.swift (USING_EMAIL), à migrer vers un futur `Settings.swift` centralisé.
    private static let userDefaultsKey = "fcmId"

    /// Port de `MyFirebaseInstanceIdService.sendRegistrationToServer(token, context)` —
    /// appelé depuis `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)`
    /// (`AppDelegate.swift`).
    static func handleFCMToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: userDefaultsKey)
    }

    /// Port de `MyFirebaseInstanceIdService.requestNewFCMToken(context)` — pousse le jeton
    /// stocké vers le serveur (`user` endpoint, colonne `fcmId`) UNIQUEMENT si une session est
    /// active, à l'identique de la vérification `userId != null && !userId.equals("rien")`.
    static func pushTokenToServer() async {
        let token: String?
        if let cached = UserDefaults.standard.string(forKey: userDefaultsKey) {
            token = cached
        } else {
            token = await currentFCMToken()
        }
        guard let token else { return }
        guard let userId = UserSession.shared.myId else { return }
        let params = ["id": userId, "column": "fcmId", "value": token]
        _ = try? await APIClient.shared.post(params, endpoint: "user")
    }

    /// `FirebaseMessaging` (SDK 10.x) n'expose `token` qu'en API à callback — pas de variante
    /// `async` native confirmée sans accès à la documentation/Xcode (même type d'incertitude déjà
    /// documenté pour `Socket.IO-Client-Swift` dans `Realtime/TiinverSocket.swift`, module 1) —
    /// enveloppé ici en continuation. **HYPOTHÈSE À VÉRIFIER** au premier build réel : si le SDK
    /// résolu par SPM propose bien `Messaging.messaging().token(completion:)` avec cette
    /// signature exacte.
    private static func currentFCMToken() async -> String? {
        await withCheckedContinuation { continuation in
            Messaging.messaging().token { token, _ in
                continuation.resume(returning: token)
            }
        }
    }

    /// Port de `SessionManager.clear()` (`context.getSharedPreferences(PREFFERENCE_NAME,
    /// MODE_PRIVATE).edit().clear().apply()`) pour ce champ précis — **ajouté le 2026-08-26
    /// (MIGRATION_PARITY_AUDIT_V5.md V5-F-004, Phase B P2)**. Android vide TOUT le fichier de
    /// préférences partagé au logout/à la suppression de compte, y compris `fcmId` (même fichier
    /// que `COINS_AMOUNT`/etc., voir `back_sync/infoContract.java`) — appelé depuis
    /// `UserSession.clear()`.
    static func clearToken() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
