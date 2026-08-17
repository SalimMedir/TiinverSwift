import Foundation

/// Port de `uploadPerfilPhoto/ProfileRepository.java` (lu en entier) + méthodes REST éparpillées
/// dans `UserProfile.java`/`AddPerfilFoto.java`/`SettingAccountFragment.java` (tous lus en entier,
/// module 17) — profil (affichage/édition), follow/block, déconnexion/suppression de compte.
@MainActor
final class ProfileRepository {
    static let shared = ProfileRepository()
    private init() {}

    /// Port de `data.volleyGet(..., "getuserbyid/"+userId+"/"+myId, ...)` (`UserProfile.onCreate`).
    func fetchProfile(userId: String, viewerId: String) async throws -> User {
        let value = try await APIClient.shared.get("getuserbyid/\(userId)/\(viewerId)")
        guard value.isBackendSuccess, let data = value["userData"]?.rawData else {
            throw JSONError.typeMismatch("getuserbyid")
        }
        return try JSONDecoder().decode(User.self, from: data)
    }

    /// Port de `ShareActivity.getUser`/`connectToServeur` (`getuser/{username}`, résolution d'un
    /// lien profond `/user/{username}`, `DeepLinkRouter.swift`, 2026-08-16) — clé de réponse
    /// `"userData"` JSON-encodée en CHAÎNE sur CET endpoint précis (`object.getString("userData")`
    /// côté Android), contrairement à `getuserbyid` ci-dessus où `userData` est un objet JSON
    /// imbriqué : deux endpoints différents, vérifiés séparément plutôt que supposés identiques.
    func fetchUser(byUsername username: String) async throws -> User {
        let value = try await APIClient.shared.get("getuser/\(username)")
        guard value.isBackendSuccess, let data = try? value.stringEncodedJSON("userData"), let raw = data.rawData else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "getuser")
        }
        return try JSONDecoder().decode(User.self, from: raw)
    }

    /// Port de `getMediasPubFromServer(actor, userId, limit, offset)` — posts d'UN profil
    /// spécifique (`actor`), PAS le fil personnalisé du visiteur (`FeedRepository.fetchTimeline`,
    /// module 6, endpoint différent à 3 segments). Endpoint réel vérifié dans
    /// `ProfileRepository.java:153` (`"feedtimeline/" + actor + "/" + userId + "/" + limit + "/" +
    /// offset`, clé de réponse `"activities"`, `gson.fromJson(jsn.toString(), activityLib[].class)`)
    /// — confirmé identique côté iOS lors du re-trace P0-3 (2026-08-17), rien à corriger sur ce point.
    ///
    /// **CORRIGÉ le 2026-08-17 (P0-3)** : `try? JSONDecoder().decode([FeedActivity].self, ...)`
    /// avalait TOUT le tableau dès qu'UN SEUL item échouait au décodage (le décodage `Codable` d'un
    /// `Array` s'arrête et lève à la PREMIÈRE erreur d'élément — contrairement à `compactMap`, il ne
    /// saute pas l'élément fautif) — `try?` transformait ça en `nil` → `?? []`, rendant la grille
    /// Profile silencieusement vide, EXACTEMENT la même classe de bug déjà trouvée et corrigée dans
    /// `FeedRepository.fetchTimeline` (2026-08-16) mais jamais portée ici. Corrigé avec le même motif
    /// per-item + diagnostic console.
    func fetchUserPosts(actor: String, viewerId: String, limit: Int, offset: Int) async throws -> [FeedActivity] {
        let value = try await APIClient.shared.get("feedtimeline/\(actor)/\(viewerId)/\(limit)/\(offset)")
        guard let array = try? value.jsonArray("activities") else { return [] }
        return Self.decodeActivitiesLeniently(array, context: "PROFILE POSTS")
    }

    /// Port de `getPostsByHashtag`/`HashtagWorkerTask` — même format de réponse (`"activities"`)
    /// que `fetchUserPosts`, endpoint différent.
    ///
    /// **CORRIGÉ le 2026-08-17 (P0-3, même cause racine que `fetchUserPosts` ci-dessus, trouvée dans
    /// le même fichier lors du même passage)** : même remplacement `try?` global → décodage per-item.
    func fetchHashtagPosts(tag: String, limit: Int, offset: Int) async throws -> [FeedActivity] {
        let value = try await APIClient.shared.get("content/hashtag/\(tag)/posts/\(limit)/\(offset)")
        guard let array = try? value.jsonArray("activities") else { return [] }
        return Self.decodeActivitiesLeniently(array, context: "HASHTAG POSTS")
    }

    /// Décodage per-item partagé — même motif que `FeedRepository.TimelineResult`'s `compactMap` :
    /// un item dont le décodage échoue est SAUTÉ (avec un diagnostic console explicite), pas
    /// silencieusement transformé en tableau vide entier.
    private static func decodeActivitiesLeniently(_ array: [JSONValue], context: String) -> [FeedActivity] {
        let decoded = array.compactMap { item -> FeedActivity? in
            guard let data = item.rawData else {
                print("\(context): item.rawData nil for one activity — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(FeedActivity.self, from: data)
            } catch {
                print("\(context): decode failure for one activity — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("\(context): received=\(array.count) activities, only \(decoded.count) decoded successfully — \(array.count - decoded.count) silently dropped, see decode failures above")
        }
        return decoded
    }

    /// Port de `TransportData.Following`/`data.getFollowing` — endpoint `follow`,
    /// `{userId, followId}` (vérifié dans `TransportData.java`, ligne 1428).
    func follow(userId: String, followerId: String) async throws {
        _ = try await APIClient.shared.post(["userId": userId, "followId": followerId], endpoint: "follow")
    }

    /// Port de `UserProfile.block(username, userId)` — endpoint `block`, réponse `message` ∈
    /// `{"USER BLOCKED", "USER UNBLOCKED"}` (bascule automatique côté serveur selon l'état actuel,
    /// PAS un paramètre `blocked: Bool` envoyé par le client).
    func toggleBlock(myUsername: String, myId: String, targetUsername: String, targetUserId: String) async throws -> Bool {
        let params = ["username": myUsername, "username_blocked": targetUsername, "userId": myId, "user_blocked_id": targetUserId]
        let value = try await APIClient.shared.post(params, endpoint: "block")
        return (try? value.string("message")) == "USER BLOCKED"
    }

    /// Port de `EditProfile.UpdateProfileData`/`EditPersonalInformation.UpdateProfileData` — motif
    /// commun IDENTIQUE dans les deux fichiers : `POST user` avec `{id, column, value}` par champ
    /// modifié (mêmes conventions que `PushTokenRegistrar`/`BuyCoinsActivity.updateToServer` déjà
    /// rencontrées ailleurs dans ce portage).
    func updateProfileField(userId: String, column: String, value: String) async throws {
        _ = try await APIClient.shared.post(["id": userId, "column": column, "value": value], endpoint: "user")
    }

    /// Port de `ProfileRepository.uploadPhotoProfile` (`HttpFileUploader`, type=2,
    /// `uploadRequestBodyPerfil`) — `UploadFileOrDataService.java`/`HttpFileUploader.java` lus en
    /// entier (GAP-004, 2026-08-15) : ce flux est un POST multipart DIRECT vers le backend Tiinver
    /// (`{SERVER}user`), PAS BunnyCDN (BunnyCDN n'est utilisé QUE pour les pièces jointes chat —
    /// protocole entièrement différent, voir `MIGRATION_AUDIT.md` GAP-004). Champs fidèles à
    /// `uploadRequestBodyPerfil` : `id`=userId, `column`="profile_picture", `format`="json",
    /// fichier nommé `wn_image.jpeg` (nom fixe côté Android, pas dynamique). Réponse `{error,
    /// object_url}` — même convention `error` string que `JSONValue.isBackendSuccess`.
    func uploadProfilePicture(userId: String, imageData: Data) async throws -> String {
        let value = try await APIClient.shared.uploadMultipart(
            endpoint: "user",
            fields: ["id": userId, "column": "profile_picture", "format": "json"],
            fileFieldName: "object_url",
            filename: "wn_image.jpeg",
            mimeType: "image/jpeg",
            fileData: imageData
        )
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "uploadProfilePicture")
        }
        return try value.string("object_url")
    }

    /// Port de `SettingAccountFragment.logout`/`deleteAccount` — endpoints `logout`/`deleteaccount`,
    /// `{userId}`.
    func logout(userId: String) async throws {
        _ = try await APIClient.shared.post(["userId": userId], endpoint: "logout")
    }

    func deleteAccount(userId: String) async throws {
        _ = try await APIClient.shared.post(["userId": userId], endpoint: "deleteaccount")
    }
}
