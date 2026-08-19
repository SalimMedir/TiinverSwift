import Foundation

/// Port de `models/search/SearchModel.java` (utilisé par `RechercheTiinver.java` ET
/// `Following/FollowList.java` — même forme réutilisée pour les résultats "utilisateur" de la
/// recherche ET la liste abonnés/abonnements) + les champs `SearchResultModel` (interne à
/// `RechercheTiinver.java`, PAS un fichier séparé — classe imbriquée) lus dans
/// `parseAndDisplay`. Noms de champs JSON vérifiés (`u.optString(...)`) plutôt que devinés.
struct SearchUserResult: Codable, Identifiable, Hashable {
    var id: Int
    var username: String?
    var firstname: String?
    var lastname: String?
    var profile: String?
    var certified: Bool?
    var isFollowed: Bool?
    var followers: String?
    var following: String?
    var location: String?
    var biography: String?
    var category: String?

    /// Décodage tolérant (2026-08-16) : MÊME cause racine que `FeedActivity.id`/`User.id` (voir
    /// `LenientDecoding.swift`) — `id` non-optionnel décodé strictement faisait échouer TOUT le
    /// tableau `users` d'un coup dès qu'UN SEUL résultat arrivait avec un `id` en chaîne
    /// (`SearchResults.init(from:)` utilise `decodeIfPresent([SearchUserResult].self, ...)`, qui
    /// échoue sur le tableau ENTIER si un seul élément lève une erreur — pas un `compactMap`
    /// tolérant par élément), rattaché au P0 historique "résultats de recherche invisibles".
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLenientInt(forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        certified = container.decodeLenientBoolIfPresent(forKey: .certified)
        isFollowed = container.decodeLenientBoolIfPresent(forKey: .isFollowed)
        followers = try container.decodeIfPresent(String.self, forKey: .followers)
        following = try container.decodeIfPresent(String.self, forKey: .following)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        biography = try container.decodeIfPresent(String.self, forKey: .biography)
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }
}

/// Port du bloc "HASHTAGS" de `parseAndDisplay` (`tag`/`post_count`/`total_views`).
struct SearchHashtagResult: Codable, Identifiable, Hashable {
    var tag: String
    var post_count: Int?
    var total_views: Int?

    var id: String { tag }
}

/// Port du bloc "POSTS" de `parseAndDisplay` — dédié plutôt que réutilisant `FeedActivity` (module
/// 6) : `actor` arrive ici comme ENTIER JSON (`p.getInt("actor")`), alors que `FeedActivity.actor`
/// est une chaîne (vérifié dans `activityLib.java`, module 6) — vraie divergence entre les deux
/// endpoints, PAS unifiée pour ne pas casser le décodage strict de l'un ou l'autre.
struct SearchPostResult: Codable, Identifiable, Hashable {
    var id: Int
    var token: String?
    var verb: String?
    var object: String?
    var object_url: String?
    var message: String?
    var likes: Int?
    var comment: Int?
    var views: Int?
    var stamp: String?
    var cdn_thumbnail_url: String?
    var cdn_content_url: String?
    var cdn_provider: String?
    var cdn_content_id: String?
    var isLiked: Bool?
    var actor: Int
    var username: String?
    var firstname: String?
    var profile: String?
    var isCertified: Int?

    /// Décodage tolérant (2026-08-16) — même cause racine que `SearchUserResult` ci-dessus,
    /// `id`/`actor` sont ici les DEUX champs non-optionnels de cette struct.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLenientInt(forKey: .id)
        token = try container.decodeIfPresent(String.self, forKey: .token)
        verb = try container.decodeIfPresent(String.self, forKey: .verb)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        object_url = try container.decodeIfPresent(String.self, forKey: .object_url)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        likes = container.decodeLenientIntIfPresent(forKey: .likes)
        comment = container.decodeLenientIntIfPresent(forKey: .comment)
        views = container.decodeLenientIntIfPresent(forKey: .views)
        stamp = try container.decodeIfPresent(String.self, forKey: .stamp)
        cdn_thumbnail_url = try container.decodeIfPresent(String.self, forKey: .cdn_thumbnail_url)
        cdn_content_url = try container.decodeIfPresent(String.self, forKey: .cdn_content_url)
        cdn_provider = try container.decodeIfPresent(String.self, forKey: .cdn_provider)
        cdn_content_id = try container.decodeIfPresent(String.self, forKey: .cdn_content_id)
        isLiked = container.decodeLenientBoolIfPresent(forKey: .isLiked)
        actor = try container.decodeLenientInt(forKey: .actor)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        isCertified = container.decodeLenientIntIfPresent(forKey: .isCertified)
    }

    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-009, Phase B P0-2)** — même
    /// correctif que `FeedActivity.thumbnailURL`/`effectiveObjectURLString` (voir ce fichier pour
    /// la preuve complète, `MediaObject.getObject_url()` lu ligne par ligne) : cette structure
    /// duplique les mêmes champs CDN pour son propre rendu de résultat de recherche (`SearchView.
    /// postRow`, pas seulement via `asFeedActivity`), donc la même correction de priorité
    /// (`cdn_content_url` prioritaire quand `cdn_content_id` est valide, sinon repli `object_url`)
    /// s'y applique identiquement pour la branche photo — la branche vidéo (`cdn_thumbnail_url`)
    /// était déjà correcte, non modifiée.
    var thumbnailURL: URL? {
        let isVideo = object?.caseInsensitiveCompare("videos") == .orderedSame
        let hasContentId = cdn_content_id != nil && cdn_content_id != "NULL" && !(cdn_content_id?.isEmpty ?? true)
        let candidate: String?
        if isVideo {
            candidate = hasContentId ? cdn_thumbnail_url : object_url
        } else {
            candidate = hasContentId ? (cdn_content_url ?? object_url) : object_url
        }
        guard let candidate, !candidate.isEmpty else { return nil }
        return URL(string: candidate)
    }

    /// Port de `UniversalSearchAdapter.java:298-306` (tap sur un résultat "publication" → écran
    /// plein écran) — convertit vers `FeedActivity` pour réutiliser `FeedDetailPagerView`
    /// (`FeedView.swift`) tel quel plutôt que construire un second visualiseur plein écran.
    /// `actor` : `Int` ici vs `String?` sur `FeedActivity` (divergence documentée dans
    /// `SearchPostResult`), converti simplement en chaîne.
    var asFeedActivity: FeedActivity {
        FeedActivity(
            id: id, actor: String(actor), token: token, verified: nil, verb: verb,
            lastname: nil, firstname: firstname, object: object, likes: likes, views: views,
            isLiked: isLiked == true ? "true" : "false", stamp: stamp, comment: comment, share: nil,
            object_url: object_url, message: message, userId: actor, profile: profile, location: nil,
            certified: isCertified == 1 ? "true" : "false", followers: nil, following: nil,
            username: username, cdn_content_id: cdn_content_id, cdn_content_url: cdn_content_url,
            cdn_thumbnail_url: cdn_thumbnail_url
        )
    }
}

/// Port de `parseAndDisplay` — enveloppe complète `{error, results: {users, hashtags, posts}}`.
///
/// **`init(from:)` custom ajouté le 2026-08-15 (test Appetize réel, résultats de recherche jamais
/// affichés)** — `RechercheTiinver.java` garde CHAQUE catégorie avec `results.has("users")`/
/// `has("hashtags")`/`has("posts")` (`parseAndDisplay`, lignes 474/506/529) : le serveur OMET la
/// clé entière d'une catégorie non demandée (`tab=posts` → réponse `{"posts":[...]}` SEULEMENT,
/// pas `"users":[]`/`"hashtags":[]`). Le `Decodable` auto-synthétisé de Swift NE respecte PAS une
/// valeur par défaut sur un type non-optionnel quand la clé JSON est absente (seul un `Optional`
/// bénéficie de cette tolérance) — il lève `keyNotFound`, avalé par le `try?` de
/// `SearchRepository.decodeResults`, qui retombe alors sur `SearchResults()` (vide) MÊME quand le
/// serveur a réellement renvoyé des résultats dans la seule catégorie demandée. Corrigé en
/// décodant chaque tableau avec `decodeIfPresent(...) ?? []`, fidèle au `.has(...)` Android.
struct SearchResults: Codable {
    var users: [SearchUserResult] = []
    var hashtags: [SearchHashtagResult] = []
    var posts: [SearchPostResult] = []

    enum CodingKeys: String, CodingKey { case users, hashtags, posts }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent([SearchUserResult].self, forKey: .users) ?? []
        hashtags = try container.decodeIfPresent([SearchHashtagResult].self, forKey: .hashtags) ?? []
        posts = try container.decodeIfPresent([SearchPostResult].self, forKey: .posts) ?? []
    }
}

/// Port de `currentTab`/`getTypesForTab` — 4 onglets réels (vérifié dans `setupTabs`/`selectTab`).
enum SearchTab: String, CaseIterable {
    case all, posts, users, hashtags

    var apiTypes: String {
        switch self {
        case .all: return "users,posts,hashtags"
        case .posts: return "posts"
        case .users: return "users"
        case .hashtags: return "hashtags"
        }
    }

    // Parité UI avec Android corrigée par capture d'écran (2026-08-16) : "Tous" (pas "Tout"),
    // "Utilisateur" (pas "Comptes") — libellés exacts des onglets vus sur la capture réelle.
    var label: String {
        switch self {
        case .all: return "Tous"
        case .posts: return "Publications"
        case .users: return "Utilisateur"
        case .hashtags: return "Hashtags"
        }
    }
}
