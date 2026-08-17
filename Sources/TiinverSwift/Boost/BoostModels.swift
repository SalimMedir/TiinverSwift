import Foundation

/// Port de `models/advertising/AdsData.java` — sert À LA FOIS de ligne de liste ("Mes Boosts") ET
/// d'objet "overview" agrégé (`boost/overviews/{userId}`, MÊME type côté Android bien que les
/// champs n'aient pas tous un sens pour un agrégat — reproduit tel quel, pas séparé en 2 types).
struct AdsData: Codable, Identifiable {
    var objective: String?
    var message: String?
    var status: String?
    var start_at: String?
    var budget_points: Double?
    var duration_days: String?
    var city: String?
    var country: String?
    var delivered: String?
    var total_spent: String?
    var active_days: String?
    var objectUrl: String?
    var object: String?
    var boostId: Int?
    var activityId: Int?
    var views: Int?
    var likes: Int?
    var followers: Int?
    var total_watch_time: Double?
    var avg_watch_time: Double?
    var cdn_provider: String?
    var cdn_content_id: String?
    var cdn_content_url: String?
    var cdn_thumbnail_url: String?

    var id: Int { boostId ?? 0 }

    /// Port de `getObjectUrl()` — même priorité `cdn_content_id` que `FeedActivity`/
    /// `BubbleStatusPhoto` ailleurs dans ce portage (chaîne littérale `"NULL"`, pas la valeur JSON
    /// `null`, vérifié dans le getter Android).
    var resolvedObjectUrl: String? {
        let hasContentId = cdn_content_id != nil && cdn_content_id != "NULL" && !(cdn_content_id?.isEmpty ?? true)
        return hasContentId ? cdn_content_url : objectUrl
    }
}

/// Port de `models/advertising/Audience.java` — ciblage envoyé en JSON RE-ENCODÉ dans le champ
/// texte `"targeting"` de `boost/create`/`create2` (`gson.toJson(audience)`, PAS un objet JSON
/// imbriqué natif — reproduit à l'identique via un encodage manuel plutôt que de supposer que
/// l'API accepterait un objet imbriqué).
struct Audience: Codable {
    var country: [String]
    var gender: [String]
    var age_min: String
    var age_max: String
}

/// Port de `models/TagModel.java` — suggestion de pays pour `countryTagInput`
/// (`searchs/{key}/{s}` → `{error, results: TagModel[]}`).
struct TagModel: Codable, Identifiable {
    var tag: String?
    var total_views: String?
    var id: String { tag ?? UUID().uuidString }
}
