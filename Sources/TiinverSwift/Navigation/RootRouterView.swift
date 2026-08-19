import SwiftUI

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
    }

    private func checkForceUpdate() async {
        _ = await TiinverFirebaseConfigManager.shared.fetchAndActivate()
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
    }
}
