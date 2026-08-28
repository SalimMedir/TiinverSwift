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
/// **Corrigé avec un repli UserDefaults, restreint à un échec Keychain réellement constaté**
/// (2026-08-17, puis durci le 2026-08-28 — V7-F-022) : la toute première version de ce repli
/// écrivait `UserDefaults` de façon INCONDITIONNELLE, avant même de tenter le Keychain — donc
/// en PRODUCTION, pas seulement dans le scénario CI/Appetize non signé qui l'a motivé, l'apiKey
/// (identifiant d'authentification permanent envoyé brut à chaque requête) restait en clair sur
/// disque pendant toute session active, annulant le bénéfice de sécurité que ce fichier vise
/// explicitement ("faire mieux qu'Android", TIINVER_IOS_PORT_ANALYSIS.md §6.2 — Android lui-même
/// stocke cette valeur dans `SharedPreferences` ordinaire, PAS l'Android Keystore). Le repli est
/// désormais posé APRÈS la tentative Keychain et UNIQUEMENT si `SecItemAdd` a réellement échoué
/// (`status != errSecSuccess`) — Keychain reste le choix PRIMAIRE et, dans l'écrasante majorité
/// des cas (tout appareil/build signé normalement), la seule copie qui existe jamais.
/// `loadAPIKey()` migre en plus silencieusement toute valeur de repli déjà écrite par une
/// installation antérieure à ce correctif vers le Keychain dès la prochaine lecture, pour ne pas
/// laisser une copie en clair orpheline sur les appareils déjà en session.
enum KeychainStore {
    private static let service = "com.tiinver.app"
    private static let apiKeyAccount = "apiKey"
    private static let fallbackDefaultsKey = "apiKey_keychainFallback"

    /// Diagnostic (2026-08-17) — dernier statut `OSStatus` observé lors de l'écriture Keychain,
    /// affiché dans les panneaux de diagnostic déjà en place pour confirmer/infirmer la cause
    /// ci-dessus sans deviner davantage au prochain test réel.
    private(set) static var lastSaveStatusDescription: String?

    static func saveAPIKey(_ apiKey: String) {
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
        if status == errSecSuccess {
            lastSaveStatusDescription = "OK"
            // Keychain fait désormais autorité — ne pas laisser traîner une copie en clair d'un
            // éventuel repli antérieur (échec passé, ou installation pré-V7-F-022).
            UserDefaults.standard.removeObject(forKey: fallbackDefaultsKey)
        } else {
            lastSaveStatusDescription =
                "ÉCHEC (OSStatus=\(status), \((SecCopyErrorMessageString(status, nil) as String?) ?? "?")) — repli UserDefaults utilisé"
            // Repli UNIQUEMENT sur échec Keychain réellement constaté (voir commentaire de tête).
            UserDefaults.standard.set(apiKey, forKey: fallbackDefaultsKey)
        }
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
        // Repli (voir commentaire de tête) — Keychain vide/en échec. Si une valeur a été laissée
        // par une session antérieure au durcissement V7-F-022 (ou par un échec Keychain réel),
        // on la migre maintenant vers le Keychain (retente `saveAPIKey`, qui nettoie la copie en
        // clair en cas de succès) au lieu de la laisser indéfiniment en UserDefaults.
        guard let fallback = UserDefaults.standard.string(forKey: fallbackDefaultsKey) else { return nil }
        saveAPIKey(fallback)
        return fallback
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
