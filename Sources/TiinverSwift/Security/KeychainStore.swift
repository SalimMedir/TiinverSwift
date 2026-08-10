import Foundation
import Security

/// Stocke l'apiKey utilisateur dans le Trousseau iOS.
///
/// Équivalent de `SharedPreferences("tiinver_1995").getString("apiKey", ...)` côté Android
/// (back_sync/infoContract.java: MY_API_KEY, lu par 55 fichiers), mais migré vers Keychain car
/// c'est une donnée d'authentification sensible — recommandation explicite de
/// TIINVER_IOS_PORT_ANALYSIS.md §6.2 ("Keychain pour apiKey, UserDefaults pour le reste").
enum KeychainStore {
    private static let service = "com.tiinver.app"
    private static let apiKeyAccount = "apiKey"

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
        SecItemAdd(attributes as CFDictionary, nil)
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
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
