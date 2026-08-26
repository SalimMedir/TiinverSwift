import Foundation

/// Équivalent des clés stockées dans `SharedPreferences("tiinver_1995")` côté Android
/// (back_sync/infoContract.java : MYID, MY_API_KEY, PROFILE, USERNAME, NIKNAME, FIRSTNAME,
/// LASTNAME, REFERRAL_CODE — le jeu complet réellement utilisé par `manager/SessionManager.java`
/// pour reconstruire un `User` minimal au démarrage, découvert en lisant le module 5
/// `SplashActivity`/`SessionManager`, voir MIGRATION_PROGRESS.md décision du 2026-08-10 : les 4
/// derniers champs manquaient dans la version initiale de ce fichier, écrite au module 1 avant
/// que `SessionManager.getUser`/`saveUser` n'aient été lus en détail). `apiKey` seul est sensible
/// et vit dans le Trousseau via `KeychainStore`; le reste reste en UserDefaults, conformément à
/// TIINVER_IOS_PORT_ANALYSIS.md §6.2.
final class UserSession {
    static let shared = UserSession()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let myId = "myId"
        static let profile = "profile"
        static let username = "username"
        static let nikname = "nikname"
        static let firstname = "firstname"
        static let lastname = "lastname"
        static let referralCode = "referralCode"
        static let coinsAmount = "coinsAmount"
        static let gemsAmount = "gemsAmount"
        static let pendingCoinsAmount = "pendingCoinsAmount"
        static let pendingGemsAmount = "pendingGemsAmount"
        static let debugLastLoginRawUserJSON = "debugLastLoginRawUserJSON"
    }

    private init() {}

    /// Diagnostic temporaire (2026-08-16) — voir `AuthEndpoints.parseLoginResponse` : capture le
    /// dictionnaire JSON brut du "user" reçu à la connexion quand `error=="false"` (décodage
    /// RÉUSSI, pas d'exception) mais que `user.id` est quand même resté `nil` — le seul scénario
    /// qui explique une navigation propre vers Home suivie d'une session vide. Lu par
    /// `FeedViewModel`/`ProfileViewModel` et affiché dans leur panneau de diagnostic déjà visible
    /// à l'écran, pour trancher au prochain test réel sans deviner davantage. À retirer une fois
    /// la cause confirmée.
    var debugLastLoginRawUserJSON: String? {
        get { defaults.string(forKey: Keys.debugLastLoginRawUserJSON) }
        set { defaults.set(newValue, forKey: Keys.debugLastLoginRawUserJSON) }
    }

    var apiKey: String? {
        get { KeychainStore.loadAPIKey() }
        set {
            if let newValue {
                KeychainStore.saveAPIKey(newValue)
            } else {
                KeychainStore.deleteAPIKey()
            }
        }
    }

    var myId: String? {
        get { defaults.string(forKey: Keys.myId) }
        set { defaults.set(newValue, forKey: Keys.myId) }
    }

    var profile: String? {
        get { defaults.string(forKey: Keys.profile) }
        set { defaults.set(newValue, forKey: Keys.profile) }
    }

    var username: String? {
        get { defaults.string(forKey: Keys.username) }
        set { defaults.set(newValue, forKey: Keys.username) }
    }

    var nikname: String? {
        get { defaults.string(forKey: Keys.nikname) }
        set { defaults.set(newValue, forKey: Keys.nikname) }
    }

    var firstname: String? {
        get { defaults.string(forKey: Keys.firstname) }
        set { defaults.set(newValue, forKey: Keys.firstname) }
    }

    var lastname: String? {
        get { defaults.string(forKey: Keys.lastname) }
        set { defaults.set(newValue, forKey: Keys.lastname) }
    }

    var referralCode: String? {
        get { defaults.string(forKey: Keys.referralCode) }
        set { defaults.set(newValue, forKey: Keys.referralCode) }
    }

    var isLoggedIn: Bool {
        apiKey != nil && myId != nil
    }

    /// Port de `Settings.getFloatPreference(COINS_AMOUNT)`/`setFloatPreference` (module 15, Wallet)
    /// — cache local rapide du solde, lu par TOUS les écrans wallet avant tout appel réseau,
    /// mis à jour de façon optimiste après achat/retrait/transfert/conversion/récompense.
    var coinsAmount: Double {
        get { defaults.double(forKey: Keys.coinsAmount) }
        set { defaults.set(newValue, forKey: Keys.coinsAmount) }
    }

    var gemsAmount: Double {
        get { defaults.double(forKey: Keys.gemsAmount) }
        set { defaults.set(newValue, forKey: Keys.gemsAmount) }
    }

    /// Port de `PENDING_COINS_AMOUNT`/`PENDING_GEMS_AMOUNT` — solde de récompense (pub rewarded)
    /// pas encore confirmé par le serveur (`WalletRepository.updateToServer`, réessayé au prochain
    /// gain si la requête précédente a échoué).
    var pendingCoinsAmount: Int {
        get { defaults.integer(forKey: Keys.pendingCoinsAmount) }
        set { defaults.set(newValue, forKey: Keys.pendingCoinsAmount) }
    }

    var pendingGemsAmount: Int {
        get { defaults.integer(forKey: Keys.pendingGemsAmount) }
        set { defaults.set(newValue, forKey: Keys.pendingGemsAmount) }
    }

    /// Port de `SessionManager.getUser(context)` — reconstruit un `User` minimal depuis les
    /// champs persistés localement (PAS un appel réseau), à l'identique de l'original.
    func cachedUser() -> User? {
        guard let myId, let id = Int(myId) else { return nil }
        var user = User()
        user.id = id
        user.username = username
        user.nikname = nikname
        user.firstname = firstname
        user.lastname = lastname
        user.profile = profile
        user.apikey = apiKey
        user.referralCode = referralCode
        return user
    }

    /// Port de `SessionManager.saveUser(context, user)`.
    func save(_ user: User) {
        myId = user.id.map(String.init)
        username = user.username
        firstname = user.firstname
        lastname = user.lastname
        profile = user.profile
        apiKey = user.apiKey ?? user.apikey
        nikname = user.nikname
        referralCode = user.referralCode
    }

    /// Équivalent de la déconnexion : purge apiKey (Keychain) + identifiants (UserDefaults).
    ///
    /// **Étendu le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-004, Phase B P2)** — cette
    /// méthode ne purgeait que les champs d'IDENTITÉ (myId/profile/username/...), pas l'équivalent
    /// fidèle de `SessionManager.clear()` côté Android (`SharedPreferences.edit().clear().apply()`,
    /// vide la TOTALITÉ du fichier "tiinver_1995" partagé par `back_sync/infoContract.java` —
    /// solde wallet EN CACHE inclus, `Settings.setStringPreference(context,"fcmId",...)` inclus).
    /// Sur un appareil partagé, `coinsAmount`/`gemsAmount`/`pendingCoinsAmount`/`pendingGemsAmount`
    /// résiduels de l'utilisateur A pouvaient s'afficher dans `WalletView`/`WalletViewModel` pour
    /// l'utilisateur B jusqu'à ce qu'un fetch profil les écrase — fenêtre d'information financière
    /// erronée. `fcmId` résiduel pouvait aussi rester associé au compte A côté serveur tant qu'aucun
    /// nouveau jeton n'était repoussé.
    func clear() {
        apiKey = nil
        defaults.removeObject(forKey: Keys.myId)
        defaults.removeObject(forKey: Keys.profile)
        defaults.removeObject(forKey: Keys.username)
        defaults.removeObject(forKey: Keys.nikname)
        defaults.removeObject(forKey: Keys.firstname)
        defaults.removeObject(forKey: Keys.lastname)
        defaults.removeObject(forKey: Keys.referralCode)
        defaults.removeObject(forKey: Keys.coinsAmount)
        defaults.removeObject(forKey: Keys.gemsAmount)
        defaults.removeObject(forKey: Keys.pendingCoinsAmount)
        defaults.removeObject(forKey: Keys.pendingGemsAmount)
        PushTokenRegistrar.clearToken()
    }
}

/// Port du reset de pile de tâches d'Android au logout (`Intent(SplashActivity)` avec
/// `FLAG_ACTIVITY_CLEAR_TASK`, voir `RootRouterView.swift`) — **ajouté le 2026-08-19**
/// (MIGRATION_PARITY_AUDIT_V3.md V3-F-051, Phase B P0-4). `UserSession` n'est PAS un
/// `ObservableObject` (singleton `final class` simple, décision d'architecture antérieure non
/// remise en cause ici) — `NotificationCenter` est le mécanisme le plus direct et le moins
/// invasif pour que `RootRouterView` (qui possède l'état de navigation racine local,
/// `@State private var authenticatedUser`) soit informé d'un logout survenu ailleurs dans l'app,
/// sans convertir `UserSession` en `ObservableObject` (changement d'architecture plus large que
/// nécessaire pour ce correctif précis).
extension Notification.Name {
    static let userDidLogout = Notification.Name("com.tiinver.userDidLogout")
}
