import Foundation

/// Port de `contacts/repository/ConnectedUsersRepository.java` (lu en entier, 2026-08-15) —
/// liste des "contacts" Tiinver d'un utilisateur (dérivée serveur, abonnés/abonnements — PAS le
/// carnet d'adresses du téléphone ; `ContactsFragment.java` a bien du code `CursorLoader`/
/// `infoContract.USER_URI` pour les contacts du téléphone, mais il est CONFIRMÉ MORT — jamais
/// câblé à `LoaderManager.initLoader`, seule `ConnectedUserViewModel.getConnectedUsers()` alimente
/// réellement l'écran). Aucune recherche/filtre côté client dans `ContactsFragment.java` d'origine
/// — reproduit à l'identique (liste brute).
@MainActor
final class ContactsRepository {
    static let shared = ContactsRepository()
    private init() {}

    /// `GET connectedusers/{userId}` — réponse `{error, data: "<tableau JSON encodé en chaîne>"}`,
    /// même convention "data re-sérialisé en chaîne" que d'autres endpoints de ce backend (voir
    /// `JSONValue.stringEncodedJSON`).
    func connectedUsers(userId: String) async throws -> [GroupMemberCandidate] {
        let value = try await APIClient.shared.get("connectedusers/\(userId)")
        guard value.isBackendSuccess, let data = try? value.stringEncodedJSON("data").rawData else { return [] }
        return (try? JSONDecoder().decode([GroupMemberCandidate].self, from: data)) ?? []
    }
}
