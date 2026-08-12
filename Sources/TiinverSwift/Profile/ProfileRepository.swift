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

    /// Port de `getMediasPubFromServer(actor, userId, limit, offset)` — posts d'UN profil
    /// spécifique (`actor`), PAS le fil personnalisé du visiteur (`FeedRepository.fetchTimeline`,
    /// module 6, endpoint différent à 3 segments).
    func fetchUserPosts(actor: String, viewerId: String, limit: Int, offset: Int) async throws -> [FeedActivity] {
        let value = try await APIClient.shared.get("feedtimeline/\(actor)/\(viewerId)/\(limit)/\(offset)")
        guard let data = value["activities"]?.rawData else { return [] }
        return (try? JSONDecoder().decode([FeedActivity].self, from: data)) ?? []
    }

    /// Port de `getPostsByHashtag`/`HashtagWorkerTask` — même format de réponse (`"activities"`)
    /// que `fetchUserPosts`, endpoint différent.
    func fetchHashtagPosts(tag: String, limit: Int, offset: Int) async throws -> [FeedActivity] {
        let value = try await APIClient.shared.get("content/hashtag/\(tag)/posts/\(limit)/\(offset)")
        guard let data = value["activities"]?.rawData else { return [] }
        return (try? JSONDecoder().decode([FeedActivity].self, from: data)) ?? []
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

    /// Port de `ProfileRepository.uploadPhotoProfile` — `HttpFileUploader` vers `POST user`
    /// (upload multipart, PAS encore porté ce module — voir avertissement dans le tableau détaillé :
    /// même gap que `requestUpload`/`requestDownload` du module 11, `UploadFileOrDataService.java`
    /// pas lu cette passe non plus).
    func uploadProfilePicture(userId: String, imageData: Data) async throws -> String {
        throw JSONError.typeMismatch("uploadProfilePicture — transfert multipart pas encore porté, voir MIGRATION_PROGRESS.md")
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
