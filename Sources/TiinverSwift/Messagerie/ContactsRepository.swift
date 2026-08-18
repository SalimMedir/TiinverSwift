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
    /// **DURCI le 2026-08-17 (P0-4, même défense-en-profondeur qu'appliquée à `FeedRepository.
    /// fetchTimeline`/`ProfileRepository.fetchUserPosts` cette même session)** : la cause racine
    /// concrète (`userId` numérique cassant le décodage `Decodable` strict) est déjà corrigée par
    /// `GroupMemberCandidate.init(from:)` ci-dessus, MAIS ce point d'appel décodait encore le
    /// tableau ENTIER via `try? JSONDecoder().decode([GroupMemberCandidate].self, ...)` — un
    /// `Array` Codable lève à la PREMIÈRE erreur d'élément, donc UN SEUL contact avec un champ
    /// encore non conforme (futur, non prévu ici) ferait de nouveau disparaître TOUTE la liste sans
    /// aucun diagnostic, exactement le symptôme "impossible de créer un groupe" déjà rapporté une
    /// fois pour cette cause précise. Remplacé par un décodage per-item + diagnostic console, même
    /// motif que le Feed/Profile.
    func connectedUsers(userId: String) async throws -> [GroupMemberCandidate] {
        let value = try await APIClient.shared.get("connectedusers/\(userId)")
        guard value.isBackendSuccess else { return [] }
        // `looselyEncodedJSON` (voir `JSONValue.swift`) tolère les deux formes possibles
        // (chaîne JSON ré-encodée OU tableau imbriqué direct) plutôt que de deviner laquelle cet
        // endpoint précis utilise.
        guard let array = value.looselyEncodedJSON("data")?.toArray() else { return [] }
        let decoded = array.compactMap { item -> GroupMemberCandidate? in
            guard let data = item.rawData else {
                print("CONTACTS: item.rawData nil for one candidate — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(GroupMemberCandidate.self, from: data)
            } catch {
                print("CONTACTS: decode failure for one candidate — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("CONTACTS: received=\(array.count) candidates, only \(decoded.count) decoded successfully — \(array.count - decoded.count) silently dropped, see decode failures above")
        }
        return decoded
    }

    /// Port de `NewMessage.getUserByPhoneNumber` (`roster/NewMessage.java:157-195`, entier,
    /// 2026-08-18 P2) — `POST isPhoneOrEmailExiste {phoneOrEmail: str}`, réponse `{user: {...}}`
    /// (UN SEUL objet, PAS un tableau malgré le nom Android `User[] metas` — Android l'enveloppe
    /// lui-même artificiellement dans `"["+meta+"]"` avant de le décoder en tableau d'1 élément,
    /// juste pour réutiliser son décodeur `User[]` existant ; décodé ici directement comme un objet
    /// unique, plus simple et fidèle au VRAI contrat réseau).
    func lookupByPhoneOrEmail(_ query: String) async throws -> User? {
        let value = try await APIClient.shared.post(["phoneOrEmail": query], endpoint: "isPhoneOrEmailExiste")
        guard let data = value["user"]?.rawData else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }
}
