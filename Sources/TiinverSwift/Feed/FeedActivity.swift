import Foundation

/// Port de `models/activity/activityLib.java` — DTO de désérialisation JSON pour l'endpoint
/// `feedtimeline/{userId}/{limit}/{offset}` (voir `Activity/repository/ActivityRepository.java`,
/// champ `"activities"`). Noms de champs Gson vérifiés dans le fichier source (correspondance
/// directe nom de champ Java ↔ clé JSON, pas d'annotation `@SerializedName`) plutôt que devinés.
struct FeedActivity: Codable, Identifiable, Equatable {
    var id: Int
    var actor: String?
    var token: String?
    var verified: Bool?
    var verb: String?
    var lastname: String?
    var firstname: String?
    /// Type de média : "videos" | "photo" | ... (voir `ExoPlayerManager`,
    /// `"videos".equalsIgnoreCase(obj.getObject())`).
    var object: String?
    var likes: Int?
    var views: Int?
    var isLiked: String?
    var stamp: String?
    var comment: Int?
    var share: Int?
    var object_url: String?
    var message: String?
    var userId: Int?
    var profile: String?
    var location: String?
    var certified: String?
    var followers: String?
    var following: String?
    var username: String?
    var cdn_content_id: String?
    var cdn_content_url: String?
    var cdn_thumbnail_url: String?

    /// URL à lire : privilégie le CDN si disponible, sinon l'URL brute — même logique que
    /// `NotiEntity.getDisplayUrl()` (module 4), appliquée ici au flux vidéo plutôt qu'aux
    /// notifications.
    var playbackURL: URL? {
        if let cdn = cdn_content_url, !cdn.isEmpty { return URL(string: cdn) }
        guard let raw = object_url else { return nil }
        return URL(string: raw)
    }

    var thumbnailURL: URL? {
        guard let thumb = cdn_thumbnail_url, !thumb.isEmpty else { return nil }
        return URL(string: thumb)
    }

    var isVideo: Bool {
        object?.caseInsensitiveCompare("videos") == .orderedSame
    }
}
