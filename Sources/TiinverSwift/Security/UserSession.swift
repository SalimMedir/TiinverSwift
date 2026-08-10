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
    }

    private init() {}

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
    func clear() {
        apiKey = nil
        defaults.removeObject(forKey: Keys.myId)
        defaults.removeObject(forKey: Keys.profile)
        defaults.removeObject(forKey: Keys.username)
        defaults.removeObject(forKey: Keys.nikname)
        defaults.removeObject(forKey: Keys.firstname)
        defaults.removeObject(forKey: Keys.lastname)
        defaults.removeObject(forKey: Keys.referralCode)
    }
}
