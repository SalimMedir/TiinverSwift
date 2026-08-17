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
        // `looselyEncodedJSON` plutôt que `stringEncodedJSON` seul — voir sa doc (2026-08-17) :
        // même lecture Android `getString`+Gson qui s'est révélée fausse sur `weekly_rank`, aucun
        // JSON réel de CET endpoint pour trancher, donc tolère les deux formes plutôt que d'en
        // supposer une seule (risque concret pour P0-F : create échoue silencieusement dans
        // `catch` de `GroupCreationView.create()` si l'hypothèse est fausse ici aussi).
        guard value.isBackendSuccess, let data = value.looselyEncodedJSON("data") else {
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

    /// Port de `GroupModel` (`ShareActivity.joinGroup`'s champ source) — champs RÉELLEMENT lus par
    /// `joinGroup()` pour construire le `RosterModel` de la conversation, voir `DeepLinkRouter.swift`.
    struct GroupInfo {
        var id: Int
        var token: String
        var name: String
        var nikname: String?
        var description: String?
        var profile: String?
        var price: Int
        var lucrative: Int
        var isMember: Bool
        var creator: String
        var type: String
    }

    /// Port de `ShareActivity.getGroup`/`connectToServeur` (`group/{myId}/{token}`, clé de réponse
    /// `"data"` — MÊME clé que `createGroup` ci-dessus, format cohérent entre les deux endpoints
    /// `group`) — résolution d'un lien profond `/group/{token}` (`DeepLinkRouter.swift`,
    /// 2026-08-16).
    func fetchGroup(token: String, myId: String) async throws -> GroupInfo {
        let value = try await APIClient.shared.get("group/\(myId)/\(token)")
        guard value.isBackendSuccess, let data = value.looselyEncodedJSON("data") else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "group")
        }
        return GroupInfo(
            id: (try? data.int("id")) ?? 0,
            token: data.optionalString("token") ?? token,
            name: data.optionalString("name") ?? "",
            nikname: data.optionalString("nikname"),
            description: data.optionalString("description"),
            profile: data.optionalString("profile"),
            price: (try? data.int("price")) ?? 0,
            lucrative: (try? data.int("lucrative")) ?? 0,
            isMember: (try? data.bool("isMember")) ?? false,
            creator: data.optionalString("creator") ?? "",
            type: data.optionalString("type") ?? "public"
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

    // MARK: - Gestion de groupe (GAP-011, audit du 2026-08-16) — port de
    // `messagerie/group/SettingGroupMessageFragmant.java`/`GroupDetailActivity.java`/
    // `AddGroupDescriptionActivity.java`, tous lus en entier.

    /// **Simplification de portage documentée, pas une invention.** Côté Android, la liste des
    /// membres n'est PAS un appel réseau direct dans l'écran de gestion : `GroupDetailActivity`
    /// lit une table SQLite locale (`infoContract.USER_URI`) synchronisée en tâche de fond
    /// (`MyBackgroundTask`, non porté — infrastructure de synchronisation locale hors périmètre de
    /// ce gap). L'appel réseau direct existe bel et bien mais est COMMENTÉ dans le fichier source
    /// Android lui-même (`getGroupMemebers()`, `SettingGroupMessageFragmant.java:485-539` :
    /// `GET membership/{groupId}`, réponse `{error, data: "<MemberModel[] JSON>"}`) — utilisé ici
    /// directement plutôt que de reconstruire toute une couche de synchronisation locale pour un
    /// seul écran.
    func fetchMembers(groupId: String) async throws -> [GroupMember] {
        let value = try await APIClient.shared.get("membership/\(groupId)")
        guard value.isBackendSuccess, let data = value.looselyEncodedJSON("data")?.rawData else { return [] }
        return (try? JSONDecoder().decode([GroupMember].self, from: data)) ?? []
    }

    /// Port de `TransportData.updateMember` (`Http/TransportData.java:175-190`) — `POST
    /// /member/update`, `column="roles"`, `value="admin"`/`"user"`.
    func updateMemberRole(userId: Int, groupId: String, creatorId: String, makeAdmin: Bool) async throws {
        let params: [String: String] = [
            "creator": creatorId, "groupId": groupId, "value": makeAdmin ? "admin" : "user", "column": "roles",
            "userId": String(userId),
        ]
        _ = try await APIClient.shared.post(params, endpoint: "/member/update")
    }

    /// Port de `SettingGroupMessageFragmant.deleteGroupMemebers` (lignes 542-548 pour les
    /// paramètres réseau — le reste de la méthode Android insère un message système local, déjà
    /// géré côté iOS par le rendu existant des messages système reçus via Socket.IO, pas dupliqué
    /// ici).
    func removeMember(userId: Int, groupId: String, creatorId: String) async throws {
        let params: [String: String] = ["userId": String(userId), "creator": creatorId, "groupId": groupId]
        _ = try await APIClient.shared.post(params, endpoint: "deleteMember")
    }

    /// Port de `AddGroupDescriptionActivity.updateGroup` (lignes 95-105) — endpoint générique
    /// `updategroup` par colonne, réutilisé aussi par le changement de photo côté Android
    /// (`sendFotoPerfilToServer`, type=4 multipart — pas porté ici, périmètre texte uniquement pour
    /// ce gap, voir avertissement `GroupDetailView.swift`).
    func updateDescription(_ description: String, groupId: String, creatorId: String, apiKey: String) async throws {
        let params: [String: String] = [
            "creator": creatorId, "id": groupId, "value": description, "column": "description", "apiKey": apiKey,
        ]
        _ = try await APIClient.shared.post(params, endpoint: "updategroup")
    }

    /// Port de `GroupDetailActivity.exit()` (lignes 260-271) — `POST leftgroup`.
    func leaveGroup(groupId: String, userId: String, apiKey: String) async throws {
        let params: [String: String] = ["groupId": groupId, "userId": userId, "apiKey": apiKey]
        _ = try await APIClient.shared.post(params, endpoint: "leftgroup")
    }
}
