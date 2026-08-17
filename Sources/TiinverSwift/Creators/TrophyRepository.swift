import Foundation

/// Port de `creatorOfweek/TrophyRepository.java` (lu en entier) — classement hebdomadaire des
/// créateurs. Endpoint réel confirmé : `GET weekly_rank`, convention "error" standard du backend
/// (chaîne `"false"` = succès, `JSONValue.isBackendSuccess`), réponse `data` = tableau JSON de
/// `CreatorModel`. **PAS porté, décoratif/hors périmètre** : réessai automatique après erreur réseau
/// (`attemptReconnectOverview`, délai fixe de 5s côté `CreatorFragment` — un simple bouton "Réessayer"
/// suffit côté iOS) ; bannière AdMob (`adView`), confettis (`KonfettiView`), animations de badge —
/// tous décoratifs, sans effet sur les données ou la navigation.
@MainActor
final class TrophyRepository {
    static let shared = TrophyRepository()
    private init() {}

    func weeklyRank() async throws -> [CreatorModel] {
        let value = try await APIClient.shared.get("weekly_rank")
        guard value.isBackendSuccess else { return [] }
        // **CORRIGÉ le 2026-08-17, cause racine réelle confirmée par le JSON réel fourni par
        // l'utilisateur** : `"data"` est un TABLEAU JSON DIRECT (`"data": [{...}, {...}]`), PAS
        // une chaîne contenant du JSON ré-encodé comme supposé précédemment (lecture de
        // `object.getString("data")` côté Android — `org.json.JSONArray.toString()` produit du
        // JSON valide en Java, mais l'ancien code ici utilisait `JSONValue.string(_:)`, dont le
        // repli `"\(value)"` sur une valeur non-`String` produit la représentation de débogage
        // Swift, PAS du JSON valide — le second décodage échouait donc TOUJOURS, quelle que soit
        // la donnée réelle, d'où "Impossible de charger le classement" à chaque fois). Décodage
        // direct du tableau maintenant, sans supposer un double encodage qui n'existe pas ici.
        guard let arrayData = value["data"]?.rawData else { return [] }
        return (try? JSONDecoder().decode([CreatorModel].self, from: arrayData)) ?? []
    }
}
