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

    /// Initialiseur memberwise explicite — un `struct` Swift perd son initialiseur memberwise
    /// AUTOMATIQUE dès qu'un initialiseur personnalisé (ici `init(from decoder:)` ci-dessous) est
    /// déclaré. `SearchModels.swift`'s `SearchPostResult.asFeedActivity` construit un
    /// `FeedActivity` directement par nom de paramètre (PAS via JSON) — sans cet initialiseur
    /// explicite, cet appel ne compile plus (cause réelle d'un échec de build découvert au premier
    /// run CI après l'ajout de `init(from:)` ci-dessous, corrigé avant tout autre travail).
    init(
        id: Int, actor: String? = nil, token: String? = nil, verified: Bool? = nil, verb: String? = nil,
        lastname: String? = nil, firstname: String? = nil, object: String? = nil, likes: Int? = nil,
        views: Int? = nil, isLiked: String? = nil, stamp: String? = nil, comment: Int? = nil,
        share: Int? = nil, object_url: String? = nil, message: String? = nil, userId: Int? = nil,
        profile: String? = nil, location: String? = nil, certified: String? = nil, followers: String? = nil,
        following: String? = nil, username: String? = nil, cdn_content_id: String? = nil,
        cdn_content_url: String? = nil, cdn_thumbnail_url: String? = nil
    ) {
        self.id = id; self.actor = actor; self.token = token; self.verified = verified; self.verb = verb
        self.lastname = lastname; self.firstname = firstname; self.object = object; self.likes = likes
        self.views = views; self.isLiked = isLiked; self.stamp = stamp; self.comment = comment
        self.share = share; self.object_url = object_url; self.message = message; self.userId = userId
        self.profile = profile; self.location = location; self.certified = certified
        self.followers = followers; self.following = following; self.username = username
        self.cdn_content_id = cdn_content_id; self.cdn_content_url = cdn_content_url
        self.cdn_thumbnail_url = cdn_thumbnail_url
    }

    /// Décodage manuel : `id` (seul champ non-optionnel) doit tolérer une chaîne numérique en plus
    /// d'un `Int` JSON natif — voir `LenientDecoding.swift` pour la cause racine confirmée (le
    /// backend ne garantit pas le type JSON de ses champs numériques, déjà géré côté `JSONValue`
    /// mais jamais ici, ce qui faisait échouer le décodage de CHAQUE activité dès que le serveur
    /// envoyait `"id"` en chaîne, produisant un feed vide sans erreur visible). `encode(to:)` reste
    /// synthétisé automatiquement par le compilateur (jamais utilisé — ce modèle n'est que reçu).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLenientInt(forKey: .id)
        actor = try container.decodeIfPresent(String.self, forKey: .actor)
        token = try container.decodeIfPresent(String.self, forKey: .token)
        verified = container.decodeLenientBoolIfPresent(forKey: .verified)
        verb = try container.decodeIfPresent(String.self, forKey: .verb)
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        likes = container.decodeLenientIntIfPresent(forKey: .likes)
        views = container.decodeLenientIntIfPresent(forKey: .views)
        isLiked = try container.decodeIfPresent(String.self, forKey: .isLiked)
        stamp = try container.decodeIfPresent(String.self, forKey: .stamp)
        comment = container.decodeLenientIntIfPresent(forKey: .comment)
        share = container.decodeLenientIntIfPresent(forKey: .share)
        object_url = try container.decodeIfPresent(String.self, forKey: .object_url)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        userId = container.decodeLenientIntIfPresent(forKey: .userId)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        certified = try container.decodeIfPresent(String.self, forKey: .certified)
        followers = try container.decodeIfPresent(String.self, forKey: .followers)
        following = try container.decodeIfPresent(String.self, forKey: .following)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        cdn_content_id = try container.decodeIfPresent(String.self, forKey: .cdn_content_id)
        cdn_content_url = try container.decodeIfPresent(String.self, forKey: .cdn_content_url)
        cdn_thumbnail_url = try container.decodeIfPresent(String.self, forKey: .cdn_thumbnail_url)
    }
}
