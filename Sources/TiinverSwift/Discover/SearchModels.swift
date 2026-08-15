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

    var thumbnailURL: URL? {
        guard let cdn_thumbnail_url, !cdn_thumbnail_url.isEmpty else { return nil }
        return URL(string: cdn_thumbnail_url)
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

    var label: String {
        switch self {
        case .all: return "Tout"
        case .posts: return "Publications"
        case .users: return "Comptes"
        case .hashtags: return "Hashtags"
        }
    }
}
