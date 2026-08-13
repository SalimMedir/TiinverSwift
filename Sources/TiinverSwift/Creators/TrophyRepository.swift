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
        // Port fidèle de `object.getString("data")` (org.json, PAS `getJSONArray`) suivi de
        // `gson.fromJson(data, CreatorModel[].class)` — le champ "data" est une CHAÎNE contenant du
        // JSON encodé (double encodage), pas un tableau JSON imbriqué directement. Même motif déjà
        // identifié ailleurs dans ce backend (`JSONValue.stringEncodedJSON`, jusqu'ici déclaré mais
        // jamais utilisé — premier appel réel, pas un nouveau helper improvisé pour ce cas).
        let reparsed = try value.stringEncodedJSON("data")
        guard let arrayData = reparsed.rawData else { return [] }
        return (try? JSONDecoder().decode([CreatorModel].self, from: arrayData)) ?? []
    }
}
