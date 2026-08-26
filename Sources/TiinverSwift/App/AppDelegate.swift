import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn

/// Point d'accroche pour l'initialisation des SDK tiers.
///
/// Module 4 (Notifications push) : port de l'enregistrement de jeton
/// (`back_sync/MyFirebaseInstanceIdService.java`) via **Firebase Cloud Messaging** — décision
/// tranchée par investigation du code source (voir `PushTokenRegistrar.swift` pour les preuves :
/// dépendances Gradle réelles, `google-services.json` provisionné, usage explicite de
/// `FirebaseMessaging.getInstance().getToken()` côté Android).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // `Resources/GoogleService-Info.plist` intégré le 2026-08-10 (fichier réel fourni par
        // l'utilisateur, BUNDLE_ID confirmé = "com.tiinver.ios", voir `project.yml` et
        // MIGRATION_PROGRESS.md) — `FirebaseApp.configure()` le lit automatiquement.
        FirebaseApp.configure()

        // Port de `TiinverConfig.init(Context)` (module 15, Wallet) — zone tarifaire dérivée du
        // pays, conditionne l'affichage FCFA/mobile money vs USDC/crypto dans tout le Wallet.
        TiinverConfig.configure()

        // Port de `MobileAds.initialize` (module 16, AdMob) — **écart délibéré avec Android** :
        // le SDK Android correspondant appelle cette initialisation dans un bloc ENTIÈREMENT
        // COMMENTÉ côté source (`EarnCoinsActivity.java`, code mort côté Android lui-même,
        // vraisemblablement une auto-initialisation via les métadonnées du manifeste suffit sur
        // cette plateforme) — côté iOS, `MobileAds.shared.start(completionHandler:)` est une étape
        // de configuration EXPLICITEMENT REQUISE par Google (pas d'auto-initialisation
        // équivalente), documentée de façon stable et non ambiguë dans tous les guides
        // d'intégration officiels — appelée ici plutôt que reproduire le no-op Android.
        configureAdMob()

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        // **Déplacé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-061, Phase B P2)** vers
        // `RootRouterView.onAppear` — voir sa doc pour le détail complet. Avant ce correctif, la
        // demande d'autorisation notifications était déclenchée ICI, de façon inconditionnelle et
        // synchrone, AVANT que la fenêtre/le premier écran (splash, onboarding OU home) n'ait été
        // rendu — Android ne montre JAMAIS ce dialogue avant qu'au moins un écran de l'app soit
        // visible (`OnboardingFragment.onViewCreated`/`HomeActivity`, tous deux APRÈS rendu).

        // Module 12 (Appels WebRTC/CallKit) — port du point d'enregistrement de `CallService`
        // (Android le démarre à la demande, `startForegroundService` — iOS a besoin d'un
        // enregistrement PushKit précoce, dès le lancement, pour pouvoir réveiller l'app tuée).
        Task { @MainActor in CallCoordinator.shared.start() }

        return true
    }

    /// Port de la conformité App Tracking Transparency (GAP-018, audit du 2026-08-16) — voir
    /// `AdMobManager.requestTrackingAuthorizationIfNeeded()` pour le détail complet. Déclenché ici
    /// (PAS `didFinishLaunching`) car la fenêtre principale n'est garantie "key" qu'à ce stade,
    /// condition requise pour que le prompt système ATT s'affiche de façon fiable.
    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in requestTrackingAuthorizationIfNeeded() }
    }

    /// Port de `MainActivity`/`SplashActivity` gérant le retour du flux Google (Credential
    /// Manager côté Android n'a pas de callback URL équivalent, mais `GoogleSignIn-iOS` en a un
    /// standard) — requis par `GIDSignIn` pour compléter le flux OAuth.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// L'APNs device token doit être transmis à Firebase pour qu'il puisse dériver/rafraîchir le
    /// jeton FCM — `Messaging` s'en sert en interne, la valeur exploitable pour le backend arrive
    /// via `messaging(_:didReceiveRegistrationToken:)` ci-dessous, pas ici directement.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Équivalent Android : onNewToken n'est simplement jamais appelé en cas d'échec — aucune
        // branche d'erreur explicite à reproduire côté MyFirebaseInstanceIdService non plus.
    }

    /// Port de `MyFirebaseMessagingService.onNewToken` — reçoit le jeton FCM (pas le jeton APNs
    /// brut) dès qu'il est disponible/rafraîchi.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        PushTokenRegistrar.handleFCMToken(fcmToken)
        Task { await PushTokenRegistrar.pushTokenToServer() }
    }

    /// Port de `MyFirebaseMessagingService.onMessageReceived` (branche `remoteMessage.getData()`
    /// non vide) → `TiinverSyncWorker.visiteServeur` → `MyBackgroundTask.notifyUser(id)` →
    /// `NotificationRepository.fetchNotifications(id)`. Cette dernière étape est la SEULE
    /// vraiment pertinente pour le module 4 (Notifications) — le reste de `TiinverSyncWorker`
    /// (sync des messages de chat privés/groupe, `ChatRepository`) appartient au module 11
    /// (Messagerie, pas encore atteint) et n'est PAS porté ici. `MyBackgroundTask`/
    /// `Http/transportDataBackground.java`/`Activity/service/ActivityService.java` (repérés au
    /// grep initial du module 4) lus et confirmés HORS SUJET : logout/suppression de compte
    /// (module 17) et upload de média en premier plan (module 6/7), pas des notifications push.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let userId = UserSession.shared.myId else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let viewModel = NotificationCenterViewModel()
            await viewModel.fetchNotifications(userId: userId)
            completionHandler(.newData)
        }
    }

    /// Port de l'affichage systématique des notifications même app au premier plan — Android
    /// n'a pas de distinction premier plan/arrière-plan équivalente à `willPresent` (une
    /// notification FCM "notification" s'affiche toujours dans la barre système).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Port du routage par destination de `NotificationUtils.show()`/`activityMap`
    /// (`Intent` vers `ActivityMsg`/`HomeActivity`/...) — ici, publication sur `DeepLinkCenter`
    /// (module 5) plutôt qu'un `Intent` direct, `HomeShellView` observant la destination pour
    /// ouvrir le bon écran. Seules les catégories déjà portées (`missed_call` exclu, VoIP/CallKit
    /// = module 12) sont routées.
    ///
    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-021, Phase B P1-11)** — le
    /// commentaire précédent affirmait à tort que router SYSTÉMATIQUEMENT vers `.notifications`
    /// reproduisait `activityMap.get("MainActivity")` par défaut côté Android — mais
    /// `activityMap.get("MainActivity")` mappe vers `SplashActivity` (écran d'accueil), PAS vers un
    /// centre de notifications (confirmé : `back_sync/NotificationUtils.java:290-338`/`:103-153`
    /// construisent TOUJOURS `destination = "MainActivity"`, pour une notification d'activité
    /// COMME pour un message de chat). `categoryIdentifier` (`LocalNotificationBuilder.
    /// activityNotificationContent`/`chatMessageNotificationContent`) distingue maintenant les deux
    /// familles : seule une notification d'activité (like/comment/follow/etc.) ouvre le centre de
    /// notifications ; un message de chat, un appel manqué, ou toute catégorie inconnue ouvre
    /// l'accueil, fidèle à Android.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            switch response.notification.request.content.categoryIdentifier {
            case "activity":
                DeepLinkCenter.shared.route(.notifications)
            default:
                DeepLinkCenter.shared.route(.home)
            }
            completionHandler()
        }
    }
}
