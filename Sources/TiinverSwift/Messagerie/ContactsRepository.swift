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

    /// `GET connectedusers/{userId}` — `ConnectedUsersRepository.java` lit `"data"` via
    /// `object.getString("data")` + `Gson.fromJson(...)`, ce qui avait fait supposer ici un tableau
    /// JSON RE-ENCODÉ EN CHAÎNE (`stringEncodedJSON`). **PRUDENCE (2026-08-17)** : cette même
    /// lecture Android (`getString`+Gson) s'est révélée FAUSSE sur `weekly_rank`
    /// (`TrophyRepository.swift`, JSON réel fourni par l'utilisateur = tableau DIRECT malgré un
    /// code Android identique en apparence) — sans JSON réel de CET endpoint précis, tolère les
    /// deux formes plutôt que de reproduire une hypothèse déjà prouvée non fiable en général. Fort
    /// soupçon que ce soit la cause de "impossible de créer un groupe" (P0-F) : liste de contacts
    /// vide si ce décodage échouait silencieusement (`try?`), aucune sélection possible.
    func connectedUsers(userId: String) async throws -> [GroupMemberCandidate] {
        let value = try await APIClient.shared.get("connectedusers/\(userId)")
        guard value.isBackendSuccess else { return [] }
        if let nested = try? value.stringEncodedJSON("data"), let data = nested.rawData,
            let candidates = try? JSONDecoder().decode([GroupMemberCandidate].self, from: data)
        {
            return candidates
        }
        if let data = value["data"]?.rawData, let candidates = try? JSONDecoder().decode([GroupMemberCandidate].self, from: data) {
            return candidates
        }
        return []
    }
}
