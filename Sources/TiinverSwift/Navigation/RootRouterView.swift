import SwiftUI

/// Port de `SplashActivity.navigateAfterConfig` — décision `goToLogin()` vs `goToHome(user)` sur
/// la seule base de `SessionManager.getUser(context) != null` (présence d'une session locale,
/// PAS une revalidation réseau à froid). Reproduit ici via `UserSession.shared.cachedUser()`
/// (déjà écrit, module 5).
///
/// Gate de mise à jour forcée porté (Firebase Remote Config confirmé réellement utilisé — voir
/// `PushTokenRegistrar.swift`, décision Priorité 0) : `currentTime > lastTime ||
/// remoteVersion > VERSION_CODE` → `UpdateAppView`. **Simplification documentée** : l'original lit
/// `remoteVersion` depuis une valeur mise en cache localement (`infoContract.REMOTE_VERSION_KEY`,
/// clé `"version"`) dont l'écriture n'a pas été localisée dans le code lu jusqu'ici — ce portage
/// compare directement `TiinverFirebaseConfigManager.shared.versionCode` (valeur Remote Config
/// fraîchement récupérée) à `CFBundleVersion` de `Info.plist`, sans la couche de cache
/// intermédiaire dont l'origine reste incertaine. **Piège de portage évité, documenté** :
/// `MyTimeManager.getTimeInMillis(expireDay, expireMonth - 1, expireYear)` soustrait 1 au mois
/// car `java.util.Calendar` est 0-indexé — `Calendar`/`DateComponents` de Foundation sont
/// 1-indexés (mois 1-12), donc PAS de `-1` ici malgré la ressemblance avec l'original.
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
                }
            }
        }
        .task {
            await checkForceUpdate()
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

        let localVersion = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0

        // `SMOKE_TEST_MODE=1` : UNIQUEMENT injecté par le workflow Codemagic `visual-smoke-test`
        // (`codemagic.yaml`, `SIMCTL_CHILD_SMOKE_TEST_MODE=1` exporté avant `xcrun simctl launch`
        // — même mécanisme, même variable que le contournement de la permission notifications
        // dans `App/AppDelegate.swift`). Confirmé en conditions réelles (2026-08-13) : cette gate
        // fonctionne correctement (Remote Config `versionCode` du projet Firebase configuré
        // au-dessus de `CFBundleVersion` local) et bloque le smoke-test passif (aucune interaction
        // simulée) sur `UpdateAppView` indéfiniment — sauté UNIQUEMENT ici, `fetchAndActivate()`
        // reste appelé normalement au-dessus (les autres valeurs Remote Config, ex. tarification
        // certification/récompenses pub, restent chargées pour les écrans suivants). JAMAIS
        // présent en production/TestFlight — comportement strictement inchangé en son absence.
        if ProcessInfo.processInfo.environment["SMOKE_TEST_MODE"] == "1" {
            forceUpdateRequired = false
        } else {
            forceUpdateRequired = Date() > expiryDate || config.versionCode > localVersion
        }
        configChecked = true
    }
}
