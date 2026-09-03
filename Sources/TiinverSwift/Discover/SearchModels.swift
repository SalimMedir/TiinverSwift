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
    ///
    /// **Corrigé (2026-09-03, JSON réel `content/search?q=sa` fourni par l'utilisateur)** —
    /// `followers`/`following` restaient décodés en `String` STRICT (`decodeIfPresent(String.self,
    /// ...)`), jamais passés au décodage tolérant appliqué au reste de ce même correctif ni au motif
    /// déjà établi ailleurs dans ce projet (`User.followers`/`following`, `LenientDecoding.swift`).
    /// La réponse réelle envoie `"followers": 0` — un NOMBRE JSON natif, pas une chaîne — donc CE
    /// champ précis levait une erreur de décodage pour CHAQUE utilisateur de la réponse, faisant
    /// échouer le tableau `users` entier (même mécanisme de propagation que documenté juste
    /// au-dessus pour `id`), d'où "Erreur de chargement" malgré `error: false` et une réponse par
    /// ailleurs bien formée. `decodeLenientStringIfPresent` (tolère `String` ET `Int`/`Double`
    /// natifs) remplace le décodage strict.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLenientInt(forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        certified = container.decodeLenientBoolIfPresent(forKey: .certified)
        isFollowed = container.decodeLenientBoolIfPresent(forKey: .isFollowed)
        followers = container.decodeLenientStringIfPresent(forKey: .followers)
        following = container.decodeLenientStringIfPresent(forKey: .following)
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

    /// **Corrigé (2026-09-03, JSON réel `content/search?q=sa`)** — 2 clés JSON réellement envoyées
    /// par CET endpoint ne correspondaient pas aux noms Swift synthétisés par défaut à partir des
    /// propriétés ci-dessus : `"comments"` (pluriel, pas `"comment"`) et `"certified"` (booléen —
    /// même convention que `SearchUserResult.certified` — pas `"isCertified"` en entier). Les DEUX
    /// étant `Int?`/optionnels côté Swift, le décodage ne LEVAIT aucune erreur (pas la cause de
    /// "Erreur de chargement", voir `SearchUserResult.followers` pour celle-ci) — mais silencieusement
    /// `nil` pour CHAQUE publication, perdant le nombre de commentaires et le badge certifié sans
    /// aucune trace. `CodingKeys` explicite pour mapper les 2 vers leurs vraies clés JSON.
    enum CodingKeys: String, CodingKey {
        case id, token, verb, object, object_url, message, likes
        case comment = "comments"
        case views, stamp, cdn_thumbnail_url, cdn_content_url, cdn_provider, cdn_content_id, isLiked, actor, username, firstname, profile
        // **Corrigé (2026-09-03)** — `case certified` (sans réaffectation) faisait échouer la
        // conformance `Encodable` auto-synthétisée : chaque cas de `CodingKeys` doit correspondre
        // au NOM DE LA PROPRIÉTÉ pour cette synthèse (`isCertified`), la valeur brute portant
        // séparément le nom de la clé JSON réelle (`"certified"`) — confirmé par l'erreur CI
        // "type 'SearchPostResult' does not conform to protocol 'Encodable'".
        case isCertified = "certified"
    }

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
        isCertified = container.decodeLenientBoolIfPresent(forKey: .isCertified).map { $0 ? 1 : 0 }
    }

    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-010, Phase B P1-6)** — le
    /// correctif V3-F-009 avait par erreur réutilisé la logique de priorité CDN générique de
    /// `FeedActivity.thumbnailURL` (conçue pour un endpoint différent où `object_url` fait foi),
    /// alors que `UniversalSearchAdapter.PostViewHolder.bind()` (Recherche/ui/
    /// UniversalSearchAdapter.java:270-282), le VRAI code Android pour CET endpoint
    /// (`content/search`), applique un fallback simple à deux étages : `cdn_thumbnail_url` non
    /// vide → l'utiliser ; sinon `cdn_content_url` non vide → l'utiliser ; sinon fond gris uni.
    /// Aucune branche vidéo/photo, aucune référence à `cdn_content_id` ni `object_url`.
    var thumbnailURL: URL? {
        let candidate: String?
        if let thumb = cdn_thumbnail_url, !thumb.isEmpty {
            candidate = thumb
        } else if let content = cdn_content_url, !content.isEmpty {
            candidate = content
        } else {
            candidate = nil
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
