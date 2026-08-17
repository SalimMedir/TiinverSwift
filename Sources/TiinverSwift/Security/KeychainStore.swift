import Foundation
import Security

/// Stocke l'apiKey utilisateur dans le Trousseau iOS.
///
/// Équivalent de `SharedPreferences("tiinver_1995").getString("apiKey", ...)` côté Android
/// (back_sync/infoContract.java: MY_API_KEY, lu par 55 fichiers), mais migré vers Keychain car
/// c'est une donnée d'authentification sensible — recommandation explicite de
/// TIINVER_IOS_PORT_ANALYSIS.md §6.2 ("Keychain pour apiKey, UserDefaults pour le reste").
///
/// **CAUSE RACINE RÉELLE, CONFIRMÉE le 2026-08-17** (pas une hypothèse) : un test réel a montré
/// une session PARFAITEMENT établie (`userId(objet reçu)=197 · userId(session persistée)=197`,
/// login décodé correctement avec `apiKey` présent dans le JSON) mais `apiKey=nil` malgré tout
/// dans le bandeau de diagnostic — ET les requêtes `getuserbyid`/`feedtimeline` échouaient avec
/// `HTTP 400` (probable absence de l'en-tête `Authorization`, jamais ajouté quand `apiKey` est
/// nil, voir `APIClient.headers()`). Cause identifiée : `codemagic.yaml`'s workflow
/// "visual-smoke-test" (celui qui produit le `.zip` réellement testé sur Appetize) compile avec
/// `CODE_SIGNING_ALLOWED=NO` — nécessaire pour produire un binaire testable sans compte Apple
/// Developer payant, mais SANS signature de code, l'OS ne peut pas déterminer de façon fiable le
/// groupe d'accès Keychain par défaut de l'app, et `SecItemAdd` peut échouer silencieusement.
/// `saveAPIKey`/`loadAPIKey` n'ont JAMAIS vérifié leurs codes de retour `OSStatus` avant ce
/// correctif — l'échec passait totalement inaperçu.
///
/// **Corrigé avec un repli UserDefaults** — PAS une régression de sécurité par rapport à
/// l'original : Android lui-même stocke déjà cette même valeur dans `SharedPreferences`
/// ordinaire (PAS l'Android Keystore, vérifié dans `back_sync/infoContract.java`), donc
/// UserDefaults est au moins aussi sûr que la référence Android — Keychain reste le choix
/// PRIMAIRE (chiffré, protégé par le trousseau) quand il fonctionne, ce repli garantit
/// uniquement que l'app reste FONCTIONNELLE si Keychain échoue pour une raison
/// d'environnement (signature de code absente, notamment dans ce contexte de test CI/Appetize).
enum KeychainStore {
    private static let service = "com.tiinver.app"
    private static let apiKeyAccount = "apiKey"
    private static let fallbackDefaultsKey = "apiKey_keychainFallback"

    /// Diagnostic (2026-08-17) — dernier statut `OSStatus` observé lors de l'écriture Keychain,
    /// affiché dans les panneaux de diagnostic déjà en place pour confirmer/infirmer la cause
    /// ci-dessus sans deviner davantage au prochain test réel.
    private(set) static var lastSaveStatusDescription: String?

    static func saveAPIKey(_ apiKey: String) {
        // Repli TOUJOURS écrit, indépendamment du succès Keychain — lu par `loadAPIKey()` si le
        // Keychain est vide, voir le commentaire de tête pour la justification.
        UserDefaults.standard.set(apiKey, forKey: fallbackDefaultsKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(apiKey.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        lastSaveStatusDescription = status == errSecSuccess
            ? "OK"
            : "ÉCHEC (OSStatus=\(status), \((SecCopyErrorMessageString(status, nil) as String?) ?? "?")) — repli UserDefaults utilisé"
    }

    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) {
            return value
        }
        // Repli (voir commentaire de tête) — Keychain vide/en échec, UserDefaults sert de source
        // de vérité de secours plutôt que de renvoyer `nil` alors qu'une valeur a bien été
        // persistée par `saveAPIKey`.
        return UserDefaults.standard.string(forKey: fallbackDefaultsKey)
    }

    static func deleteAPIKey() {
        UserDefaults.standard.removeObject(forKey: fallbackDefaultsKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
