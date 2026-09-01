import SwiftUI
import UserNotifications

/// Port de `SplashActivity.navigateAfterConfig` — décision `goToLogin()` vs `goToHome(user)` sur
/// la seule base de `SessionManager.getUser(context) != null` (présence d'une session locale,
/// PAS une revalidation réseau à froid). Reproduit ici via `UserSession.shared.cachedUser()`
/// (déjà écrit, module 5).
///
/// Gate de mise à jour forcée porté (Firebase Remote Config confirmé réellement utilisé — voir
/// `PushTokenRegistrar.swift`, décision Priorité 0). Android compare `currentTime > lastTime ||
/// remoteVersion > VERSION_CODE` (`SplashActivity.navigateAfterConfig`). **Divergence
/// DÉLIBÉRÉE iOS/Android, décision produit (2026-08-13, pas un bug ni une simplification de
/// portage)** : la condition de VERSION est entièrement RETIRÉE côté iOS — seule la date
/// d'expiration (`Date() > expiryDate`) déclenche `UpdateAppView` ici, sur demande explicite du
/// propriétaire du projet. Raison produit : `version_code` (Remote Config) est un paramètre
/// PARTAGÉ avec l'app Android en production (son propre `versionCode` Gradle), jamais pensé pour
/// être comparé à un `CFBundleVersion` iOS indépendant — cause du blocage réel rencontré lors des
/// tests Appetize.io, résolue en supprimant la comparaison plutôt qu'en tentant de forcer un
/// alignement inter-plateforme hors périmètre de ce portage. Objectif produit du choix "date
/// seule" : repousser l'expiration depuis la console Firebase (`app_expire_day/month/year`) débloque
/// l'app SANS nouveau déploiement, ce qu'une condition de version ne permettrait pas. **Piège de
/// portage évité, documenté** : `MyTimeManager.getTimeInMillis(expireDay, expireMonth - 1,
/// expireYear)` soustrait 1 au mois car `java.util.Calendar` est 0-indexé — `Calendar`/
/// `DateComponents` de Foundation sont 1-indexés (mois 1-12), donc PAS de `-1` ici malgré la
/// ressemblance avec l'original.
struct RootRouterView: View {
    @State private var authenticatedUser: User?
    @State private var forceUpdateRequired = false
    @State private var configChecked = false
    @Environment(\.scenePhase) private var scenePhase
    /// **Ajouté (V5-F-001, 2026-08-24)** — voir `.fullScreenCover` dans `body` ci-dessous.
    @ObservedObject private var callCoordinator: CallCoordinator = .shared
    /// **Ajouté (V5-F-050, 2026-08-25)** — voir `.alert` dans `body` ci-dessous.
    @ObservedObject private var deepLinks: DeepLinkCenter = .shared

    var body: some View {
        Group {
            if forceUpdateRequired {
                UpdateAppView()
            } else if !configChecked {
                ProgressView()
            } else if let authenticatedUser {
                HomeShellView(user: authenticatedUser)
            } else if let cachedUser = UserSession.shared.cachedUser() {
                // Port de SessionManager.getUser(context) : reconstruit depuis les champs
                // persistés localement, pas un appel réseau.
                HomeShellView(user: cachedUser)
            } else {
                AuthCoordinatorView { user in
                    authenticatedUser = user
                    // Port de `HomeActivity.onNetworkChange` → `App.resetSocket()`+`connectSocket()`
                    // (`HomeActivity.java:485-487`), le point réel où Android (re)connecte le
                    // socket avec le jeton fraîchement obtenu après un login. **Ajouté le
                    // 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-016/023, Phase B P0-1)** —
                    // sans cet appel, `ChatRepository.shared` (déjà touché au lancement de l'app
                    // via `CallCoordinator.start()`, potentiellement AVANT authentification)
                    // resterait figé sur un socket anonyme/sans jeton pour tout le reste du
                    // process, même après un login réussi dans la même session.
                    ChatRepository.shared.attachToCurrentSocket()
                }
            }
        }
        .task {
            await checkForceUpdate()
        }
        // Port de la vérification recommandée par Apple pour "Sign in with Apple"
        // (`ASAuthorizationAppleIDProvider.getCredentialState`, voir `AppleSignInCoordinator.
        // checkCredentialStateAtLaunch()`) — au lancement, une fois, comme `checkForceUpdate()`
        // ci-dessus. Sans effet (retour immédiat) si la session en cours n'a jamais été établie via
        // Apple.
        .task {
            await AppleSignInCoordinator.checkCredentialStateAtLaunch()
        }
        // Port de `ShareActivity`/`SplashActivity` (réception d'un lien profond) — monté ICI (pas
        // dans `HomeShellView`) pour capter un lien reçu AVANT authentification (parrainage
        // notamment, lu dès l'inscription — voir `RegisterView.swift`/`SignUpWithGoogleView.swift`),
        // pas seulement une fois connecté. `DeepLinkCenter` bufferise déjà les destinations qui
        // nécessitent une session (même mécanisme que les notifications push).
        .onOpenURL { url in
            DeepLinkRouter.handle(url)
        }
        // Port du reset de pile de tâches d'Android au logout
        // (`transportDataBackground.deleteaccount()` → `Intent(SplashActivity)` avec
        // `FLAG_ACTIVITY_NEW_TASK|FLAG_ACTIVITY_CLEAR_TASK`, `transportDataBackground.java:176-180`)
        // — **ajouté le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-051, Phase B P0-4)**. Avant
        // ce correctif, `authenticatedUser` (un `@State` local, jamais réinitialisé) primait sur
        // TOUTE nouvelle lecture de `UserSession.shared.cachedUser()` après un logout survenu SANS
        // relancer l'app — l'utilisateur restait visuellement sur `HomeShellView` avec une session
        // sous-jacente totalement vide. `SettingSubViews.logout()`/`deleteAccount()` postent
        // `.userDidLogout` juste après `UserSession.shared.clear()` — voir `UserSession.swift`.
        .onReceive(NotificationCenter.default.publisher(for: .userDidLogout)) { _ in
            authenticatedUser = nil
        }
        // Port de `registerReceiver(networkStateReceiver, ...)`/`unregisterReceiver(...)`
        // (`HomeActivity.java:onStart`/`onStop`, lignes 209-222,247-254) — **ajouté le 2026-08-20
        // (MIGRATION_PARITY_AUDIT_V3.md V3-F-113, Phase B P1)**. Actif UNIQUEMENT premier plan
        // (`.active`), fidèle au cycle `onStart`/`onStop` d'Android (pas `onResume`/`onPause`, qui
        // n'englobe pas les changements multi-fenêtres — `.active` de SwiftUI est l'équivalent
        // direct). N'appelle `attachToCurrentSocket()` que si une session existe déjà
        // (`authenticatedUser`/session locale) : avant login, il n'y a pas de socket authentifié à
        // reconnecter — `AuthCoordinatorView`/`RootRouterView.swift:53` gère déjà ce cas au moment
        // du login.
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                startNetworkMonitor()
                // Port de `ViewTracker.startPeriodicSync` (V6-F-019) — Android obtient une
                // couverture "vider les vues laissées par une session tuée" via son job
                // `WorkManager` périodique (15 min, hors périmètre ici — voir
                // `ViewEventSyncService.swift`) ; ce déclencheur ponctuel au retour au premier
                // plan est la meilleure approximation atteignable sans construire tout le
                // chantier `BGTaskScheduler`. Best-effort, silencieux (comme `ViewSyncWorker`
                // avale déjà ses propres échecs réseau côté Android).
                Task { await ViewEventSyncService.sync() }
            } else if phase == .background {
                NetworkMonitor.shared.stop()
            }
        }
        // `.onChange(of: scenePhase)` ne se déclenche PAS pour la valeur initiale (au lancement,
        // la scène est déjà `.active` avant le premier rendu) — port explicite du PREMIER
        // `onStart()` d'Android, qui enregistre le receiver dès le lancement de l'Activity.
        .onAppear {
            startNetworkMonitor()
            // **Corrigé (2026-08-28, V7-F-018)** — pour la même raison que ci-dessus, le
            // déclencheur `ViewEventSyncService.sync()` posé dans la branche `.active` de
            // `.onChange(of: scenePhase)` ne couvrait JAMAIS le lancement à froid : une session
            // courte (sous `syncThreshold`) suivie d'un kill complet de l'app restait en attente
            // jusqu'à un futur cycle arrière-plan→premier-plan D'UNE SESSION ULTÉRIEURE. Même
            // déclenchement ici, au premier rendu.
            Task { await ViewEventSyncService.sync() }
        }
        // **Déplacé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-061, Phase B P2)** depuis
        // `AppDelegate.didFinishLaunchingWithOptions` — vérifié directement : `OnboardingFragment.
        // onViewCreated` (utilisateurs non connectés) ET `HomeActivity` (utilisateurs déjà
        // connectés, `SplashActivity` les route directement vers Home, jamais vers l'onboarding)
        // déclenchent TOUS DEUX la demande de permission notifications APRÈS que leur écran
        // respectif ait été rendu — jamais avant que l'app n'ait affiché quoi que ce soit.
        // `RootRouterView` est le point commun aux deux chemins (`HomeShellView` ET
        // `AuthCoordinatorView`, voir `body` ci-dessus) : son `.onAppear` se déclenche une fois la
        // branche réellement choisie insérée dans la hiérarchie de vues, jamais avant — fidèle aux
        // 2 points Android, unifiés en un seul ici plutôt que dupliqués par écran.
        .onAppear {
            guard ProcessInfo.processInfo.environment["SMOKE_TEST_MODE"] != "1" else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
        // **Corrigé (V5-F-001, 2026-08-24)** — déplacé depuis `ChatView.swift`, où `CallView`
        // n'était présenté que si l'instance SwiftUI de LA conversation en cours d'appel était
        // montée. Port de `CallActivity`/`IncomingCallActivity` (`AndroidManifest.xml:347-353`),
        // des Activities système lancées par `CallService` via `FLAG_ACTIVITY_NEW_TASK`
        // (`CallService.java:571-617`) — atteignables depuis N'IMPORTE QUEL écran de l'app,
        // jamais dépendantes d'un Fragment particulier. `RootRouterView` est le seul point
        // TOUJOURS monté (force-update, chargement, session mise en cache, pré-authentification
        // via `AuthCoordinatorView`, ou `HomeShellView` une fois connecté) — voir le commentaire
        // sur `ChatRepository.shared.attachToCurrentSocket()` ci-dessus confirmant que
        // `CallCoordinator.start()` peut déjà être actif AVANT authentification.
        .fullScreenCover(isPresented: Binding(get: { callCoordinator.state != .idle }, set: { _ in })) {
            CallView(coordinator: callCoordinator)
        }
        // **Corrigé (V5-F-050, 2026-08-25)** — port de `ShareActivity.onError` → `showDialog()`,
        // MÊME alerte que `HomeShellView` (V3-F-138). `.onOpenURL` est monté ICI précisément pour
        // capter un lien reçu AVANT authentification (voir commentaire ci-dessus), mais jusqu'ici
        // seul `HomeShellView` consommait `errorMessage` — un lien invalide/en échec réseau tapé
        // avant connexion (`AuthCoordinatorView` affiché) ne montrait RIEN à l'écran, fidèle à
        // aucun des deux comportements Android (qui affiche toujours `errorLoad`, connecté ou non).
        .alert(
            "Erreur",
            isPresented: Binding(get: { deepLinks.errorMessage != nil }, set: { if !$0 { deepLinks.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deepLinks.errorMessage ?? "")
        }
    }

    private func startNetworkMonitor() {
        NetworkMonitor.shared.start {
            if authenticatedUser != nil || UserSession.shared.cachedUser() != nil {
                ChatRepository.shared.attachToCurrentSocket()
            }
        }
    }

    /// **Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-001, Phase B P1)** — cette
    /// fonction faisait `_ = await TiinverFirebaseConfigManager.shared.fetchAndActivate()` (un
    /// VRAI appel réseau, attendu) AVANT de lire `expireDay`/`expireMonth`/`expireYear` et de lever
    /// `configChecked`, bloquant l'écran racine ENTIER (Home ET Login, `body` reste sur
    /// `ProgressView()` tant que `!configChecked`) jusqu'à ~60s sur réseau lent/absent. Vérifié dans
    /// `SplashActivity.navigateAfterConfig` (`SplashActivity.java:80-122`, lu en entier) : Android
    /// décide Home/Login/UpdateApp de façon SYNCHRONE à partir de `FirebaseConfigManager.
    /// getInstance()` — un wrapper dont `getExpireDay()`/etc. lisent le CACHE LOCAL du SDK Remote
    /// Config (valeurs du dernier fetch réussi, ou les défauts XML au tout premier lancement via
    /// `setDefaultsAsync`, appliqués SYNCHRONEMENT à l'init malgré le nom) — ZÉRO I/O réseau à cet
    /// instant. `config.fetchAndActivate()` (SANS listener) n'est appelé qu'APRÈS la navigation,
    /// pour la PROCHAINE ouverture, jamais attendu. `RemoteConfig.setDefaults(fromPlist:)`
    /// (`FirebaseConfigManager.swift:24`) est le même mécanisme synchrone côté iOS — lire
    /// `expireDay`/etc. ne nécessite donc PAS d'attendre `fetchAndActivate()` d'abord, exactement
    /// comme Android.
    private func checkForceUpdate() async {
        let config = TiinverFirebaseConfigManager.shared

        var expiryComponents = DateComponents()
        expiryComponents.year = config.expireYear
        expiryComponents.month = config.expireMonth
        expiryComponents.day = config.expireDay
        let expiryDate = Calendar(identifier: .gregorian).date(from: expiryComponents) ?? .distantFuture

        // 2026-08-13 — CHANGEMENT DE COMPORTEMENT PRODUIT (décision du propriétaire du projet, pas
        // un fix de bug) : le blocage "mise à jour requise" repose désormais UNIQUEMENT sur
        // `expiryDate` (Remote Config `app_expire_day/month/year`, modifiable à distance depuis la
        // console Firebase sans nouveau déploiement). La comparaison de version
        // (`config.versionCode > localVersion`) est RETIRÉE de cette condition — elle comparait un
        // `versionCode` Remote Config partagé avec l'app Android en production (jamais aligné avec
        // le `CFBundleVersion` iOS indépendant) à une métrique de version totalement différente,
        // cause du vrai blocage rencontré sur Appetize.io. `TiinverFirebaseConfigManager.
        // versionCode` (Settings/FirebaseConfigManager.swift) N'EST PAS supprimé : vérifié par grep
        // sur tout `Sources/` qu'il n'a aucun autre appelant que ce fichier — laissé en place par
        // simplicité (propriété Remote Config toujours valide si un usage futur en a besoin), mais
        // n'intervient plus dans cette décision.
        print("🔍 [checkForceUpdate] expiryDate = \(expiryDate), Date() = \(Date()), forceUpdateRequired (avant SMOKE_TEST_MODE) = \(Date() > expiryDate)")

        // `SMOKE_TEST_MODE=1` : UNIQUEMENT injecté par le workflow Codemagic `visual-smoke-test`
        // (`codemagic.yaml`, `SIMCTL_CHILD_SMOKE_TEST_MODE=1` exporté avant `xcrun simctl launch`
        // — même mécanisme, même variable que le contournement de la permission notifications
        // dans `App/AppDelegate.swift`). Inchangé par ce changement de logique — reste le seul
        // moyen de forcer `forceUpdateRequired = false` pour le pipeline CI automatisé, qui ne
        // contrôle pas la valeur `app_expire_*` publiée côté console Firebase. JAMAIS présent en
        // production/TestFlight — comportement strictement inchangé en son absence.
        if ProcessInfo.processInfo.environment["SMOKE_TEST_MODE"] == "1" {
            forceUpdateRequired = false
        } else {
            forceUpdateRequired = Date() > expiryDate
        }
        configChecked = true

        // Port de `config.fetchAndActivate()` (`SplashActivity.java:85`, sans listener, appelé
        // APRÈS la navigation) — rafraîchit le cache local pour la PROCHAINE ouverture, jamais
        // attendu par CETTE ouverture (voir doc de tête de fonction).
        Task { _ = await config.fetchAndActivate() }
    }
}
