import Foundation

/// Port de `contacts/Group.java` (lu en entier, 2026-08-15) — création de groupe + invitation des
/// membres sélectionnés. Fidèle à `onButtonPressed()` (ligne 274) et à la boucle `POST membership`
/// (lignes 389-458).
@MainActor
final class GroupRepository {
    static let shared = GroupRepository()
    private init() {}

    struct CreatedGroup {
        var groupId: String
        var token: String
        var name: String
        var description: String?
        var profile: String?
    }

    /// Port de `Group.onButtonPressed()` — `POST group`. Champs fidèles à l'original, y COMPRIS la
    /// faute de frappe réelle du serveur (`type: "pivate"`, PAS "private" — reproduite telle quelle,
    /// une valeur "corrigée" ne matcherait pas ce que l'API attend). `description` réutilise le
    /// MÊME texte que `name` (Android n'a pas de champ description séparé dans ce formulaire,
    /// vérifié). `profile_picture` toujours vide (aucun upload d'avatar de groupe dans ce flux).
    func createGroup(name: String, isPrivate: Bool, isLucrative: Bool, price: Int, creatorId: String) async throws -> CreatedGroup {
        let params: [String: String] = [
            "name": name,
            "description": name,
            "token": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "creator": creatorId,
            "type": isPrivate ? "pivate" : "public",
            "lucrative": isLucrative ? "1" : "0",
            "price": isLucrative ? String(price) : "0",
            "profile_picture": "",
        ]
        let value = try await APIClient.shared.post(params, endpoint: "group")
        guard value.isBackendSuccess, let data = try? value.stringEncodedJSON("data") else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "group")
        }
        return CreatedGroup(
            groupId: (try? String(data.int("id"))) ?? "",
            token: data.optionalString("token") ?? "",
            name: data.optionalString("name") ?? name,
            description: data.optionalString("description"),
            profile: data.optionalString("profile")
        )
    }

    /// Port de la boucle `POST membership` (un appel par membre sélectionné, ligne 389-458) —
    /// échecs individuels ignorés (Android ne bloque pas la création de groupe si l'invitation d'UN
    /// membre échoue, chaque appel est indépendant dans la boucle d'origine).
    func addMembers(_ members: [GroupMemberCandidate], toGroupId groupId: String, inviterId: String) async {
        for member in members {
            let params: [String: String] = [
                "groupId": groupId,
                "userId": member.userId,
                "joined": "0",
                "invited": "1",
                "inviter": inviterId,
                "role": "user",
            ]
            _ = try? await APIClient.shared.post(params, endpoint: "membership")
        }
    }
}
