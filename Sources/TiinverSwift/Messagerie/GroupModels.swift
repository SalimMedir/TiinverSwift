import Foundation

/// Port de `models/groupModel/GroupModel.java` — utilisé À LA FOIS pour lister les "contacts"
/// Tiinver (`GET connectedusers/{userId}`, PAS le carnet d'adresses du téléphone) ET pour
/// transporter un membre sélectionné vers l'écran de création de groupe (`ChooseFragment` →
/// `Group.java`, même type Java des deux côtés — voir `ConnectedUsersRepository.java`/
/// `contacts/Group.java`, lus en entier, 2026-08-15).
struct GroupMemberCandidate: Codable, Identifiable, Hashable {
    var userId: String
    var username: String?
    var firstname: String?
    var lastname: String?
    var profile: String?

    var id: String { userId }

    var displayName: String {
        let name = [firstname, lastname].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (username ?? "") : name
    }

    /// **Suspect concret pour P0-F ("impossible de créer un groupe"), 2026-08-17** — bien que
    /// `GroupModel.java` déclare `userId` en `String`, Gson (`nextString()`) accepte silencieusement
    /// un NOMBRE JSON natif pour un champ `String` (même divergence que `User`/`FeedActivity`,
    /// confirmée par JSON réel ailleurs dans ce backend) alors que le `Decodable` STRICT
    /// auto-synthétisé de Swift, lui, échoue — faisant échouer le décodage de CHAQUE contact dès
    /// qu'UN SEUL arrive avec `userId` en nombre, `try?` (`ContactsRepository.connectedUsers`)
    /// avalant l'erreur en silence → liste de contacts vide → aucune sélection possible → chaîne de
    /// création de groupe bloquée dès la toute première étape, avant même l'écran de nommage.
    /// Aucun autre call site manuel de cet initialiseur memberwise dans le projet (vérifié) — sûr
    /// d'ajouter `init(from:)` sans en recréer un.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeLenientString(forKey: .userId)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
    }
}

/// Port de `models/chat/group/MemberModel.java` (`extends User`, lu en entier — GAP-011, audit du
/// 2026-08-16) — un membre d'un groupe EXISTANT, avec son rôle. Champs Gson sans `@SerializedName`
/// dans `User.java`/`MemberModel.java` (vérifié) : `userId`(Int)/`username`/`nikname`/`profile`/
/// `firstname`/`lastname`/`groupId`(Int)/`role` — mappage direct, pas de `CodingKeys`.
struct GroupMember: Codable, Identifiable, Hashable {
    var userId: Int
    var username: String?
    var firstname: String?
    var lastname: String?
    var nikname: String?
    var profile: String?
    var groupId: Int
    var role: String?

    var id: Int { userId }

    var isAdmin: Bool { role == "admin" }

    var displayName: String {
        let name = [firstname, lastname].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        if let nikname, !nikname.isEmpty { return nikname }
        return username ?? ""
    }
}
