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
        // Corrigé (V3-F-093, SILENT-04) : décodage du tableau ENTIER en un seul `try?` — un seul
        // créateur avec un champ non-lenient de type inattendu (`firstname`/`profilePicture`,
        // `String?` mais pas `decodeLenientStringIfPresent`, contrairement à `userId`) faisait
        // échouer TOUT le classement d'un coup, vidé silencieusement en `[]`. Même motif déjà
        // corrigé pour `SuggestionsRepository.decodeUsers`/`ChatRepository.decodeMessages`/
        // `FeedRepository.fetchTimeline` — `compactMap` per-item avec diagnostic, pas un décodage
        // global.
        guard let array = value["data"]?.toArray() else { return [] }
        let decoded = array.compactMap { item -> CreatorModel? in
            guard let data = item.rawData else {
                print("TROPHY: item.rawData nil for one creator — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(CreatorModel.self, from: data)
            } catch {
                print("TROPHY: decode failure for one creator — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("TROPHY: received=\(array.count) creators, only \(decoded.count) usable — \(array.count - decoded.count) skipped, see above")
        }
        return decoded
    }
}
