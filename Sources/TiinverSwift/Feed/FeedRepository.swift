import CoreData
import Foundation

/// Port de `Activity/repository/ActivityRepository.getMediasPubFromServer`/
/// `Http/TransportData.addActivities` (flux réseau + cache local `wk_activities`).
final class FeedRepository {
    private let activities: CoreDataRepository<ActivityEntity>

    init(stack: CoreDataContextProviding = CoreDataStack.shared) {
        self.activities = CoreDataRepository(stack: stack)
    }

    /// Port de `td.get("feedtimeline/" + userId + "/" + limit + "/" + offset, ...)`.
    func fetchTimeline(userId: Int, limit: Int, offset: Int) async throws -> [FeedActivity] {
        let json = try await APIClient.shared.get("feedtimeline/\(userId)/\(limit)/\(offset)")
        let array = try json.jsonArray("activities")
        return array.compactMap { item -> FeedActivity? in
            guard let data = item.rawData else { return nil }
            return try? JSONDecoder().decode(FeedActivity.self, from: data)
        }
    }

    /// Port de `TransportData.addActivities` : cache local plafonné à 10 lignes. Reproduit
    /// FIDÈLEMENT la politique observée (pas "corrigée") — au-delà de 10 lignes déjà en cache,
    /// TOUTES les lignes existantes sont supprimées avant de réinsérer le nouveau lot, plutôt que
    /// d'évincer seulement les plus anciennes une à une (la logique d'éviction sélective par id
    /// est en commentaire dans le fichier source Android, jamais activée).
    func cache(_ items: [FeedActivity]) async throws {
        let existingCount = try await activities.count()
        if existingCount >= 10 {
            try await activities.delete(predicate: nil)
        }
        for item in items {
            try await activities.insert { row in
                row.id = Int64(item.id)
                row.actor = item.actor
                row.verb = item.verb
                row.object = item.object
                row.objectUrl = item.object_url
                row.cdnThumbnailUrl = item.cdn_thumbnail_url
                row.cdnContentId = item.cdn_content_id
                row.message = item.message
                row.likes = Int64(item.likes ?? 0)
                row.comment = Int64(item.comment ?? 0)
                row.share = Int64(item.share ?? 0)
                row.isLiked = item.isLiked
                row.stamp = item.stamp
                row.userId = item.userId.map(String.init)
                row.firstname = item.firstname
                row.lastname = item.lastname
                row.profile = item.profile
                row.location = item.location
                row.username = item.username
                row.certified = item.certified
                row.followers = item.followers
                row.following = item.following
                row.origin = "server"
                row.isNew = "true"
            }
        }
    }

    func cachedActivities() async throws -> [ActivityEntity] {
        try await activities.query(sortDescriptors: [NSSortDescriptor(key: "stamp", ascending: false)])
    }

    /// Port de `HttpFileUploader.uploadRequestBody` (`type=0`, cas "publication", déclenché après
    /// `PublishFragment` côté Android via `MainFragment`/`FeedFragment`, `token="publication"`) —
    /// POST multipart vers `activity/add`. Champs `category`/`metadata`/`template_id`/`consentAi`
    /// **délibérément omis** : présents sur `UploadData` côté Android mais jamais inclus dans le
    /// corps RÉELLEMENT envoyé (vérifié dans `uploadRequestBody`, `HttpFileUploader.java`) — les
    /// ajouter ici "corrigerait" un comportement qu'Android lui-même n'a pas, pas une fidélité.
    func publish(actorId: String, object: String, message: String, hashtags: [String], fileData: Data, mimeType: String, filename: String) async throws {
        let params: [String: String] = [
            "token": UUID().uuidString,
            "actor": actorId,
            "verb": "post",
            "object": object,
            "message": message,
            "hashtags": hashtags.joined(separator: ","),
            "format": "json",
        ]
        let value = try await APIClient.shared.uploadMultipart(
            endpoint: "activity/add", fields: params, fileFieldName: "object_url",
            filename: filename, mimeType: mimeType, fileData: fileData
        )
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "activity/add")
        }
    }
}
