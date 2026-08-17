import Foundation

/// Port de `advertising/ui/AdsRepository.java` (504 lignes, lu en entier, 2026-08-18, P1) — système
/// de "Boost" (campagne publicitaire payante pour un post, `MISSING` confirmé par l'audit V2, 5
/// classes Android sans AUCUN équivalent iOS avant cette passe).
@MainActor
final class AdsRepository {
    static let shared = AdsRepository()
    private init() {}

    /// Port de `getBoostOverview` — `GET boost/overviews/{userId}`, clé `"boosts"` = UN SEUL objet
    /// `AdsData` (agrégat), lu par Android via `getString`+Gson (chaîne JSON re-encodée) —
    /// `looselyEncodedJSON` tolère aussi la forme objet imbriqué direct, jamais confirmée par un
    /// JSON réel de cet endpoint précis (même prudence que `ContactsRepository`/`GroupRepository`).
    func fetchOverview(userId: String) async throws -> AdsData {
        let value = try await APIClient.shared.get("boost/overviews/\(userId)")
        guard value.isBackendSuccess, let data = value.looselyEncodedJSON("boosts")?.rawData else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "boost/overviews")
        }
        return try JSONDecoder().decode(AdsData.self, from: data)
    }

    /// Port de `getMyBoosts` — `GET boost/myboost/{userId}/{limit}/{offset}`, clé `"boosts"` = un
    /// TABLEAU cette fois (`object.getJSONArray`, forme DIFFÉRENTE de `fetchOverview` ci-dessus —
    /// vérifié dans le fichier source, pas supposé identique). Décodage per-item + diagnostic, même
    /// motif défensif que `FeedRepository.fetchTimeline`/`ContactsRepository.connectedUsers`.
    func fetchMyBoosts(userId: String, limit: Int, offset: Int) async throws -> [AdsData] {
        let value = try await APIClient.shared.get("boost/myboost/\(userId)/\(limit)/\(offset)")
        guard value.isBackendSuccess, let array = value.looselyEncodedJSON("boosts")?.toArray() else { return [] }
        let decoded = array.compactMap { item -> AdsData? in
            guard let data = item.rawData else { return nil }
            do {
                return try JSONDecoder().decode(AdsData.self, from: data)
            } catch {
                print("BOOST: decode failure for one item — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("BOOST: received=\(array.count) items, only \(decoded.count) decoded — \(array.count - decoded.count) dropped")
        }
        return decoded
    }

    /// Port de `getSugestionFromServeur(key, s)` — `GET searchs/{key}/{s}`, clé `"results"`
    /// (`TagModel[]`) — réutilisé ici UNIQUEMENT pour `key="country"` (autocomplétion pays du
    /// ciblage), même endpoint générique qu'Android partage avec d'autres usages non portés ici
    /// (hors périmètre Boost).
    func searchTags(key: String, query: String) async throws -> [TagModel] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let value = try await APIClient.shared.get("searchs/\(key)/\(encoded)")
        guard value.isBackendSuccess, let array = value.looselyEncodedJSON("results")?.toArray() else { return [] }
        return array.compactMap { item in
            guard let data = item.rawData else { return nil }
            return try? JSONDecoder().decode(TagModel.self, from: data)
        }
    }

    /// Port de `collectDataForApi()` — un boost = un `HashMap<String,String>` unique, réutilisé PAR
    /// LES 3 appels réseau ci-dessous (`boostContent`/`boostContent2`/même forme). `targeting` =
    /// `Audience` ré-encodé en chaîne JSON (`gson.toJson`), PAS un objet imbriqué — reproduit à
    /// l'identique.
    struct BoostRequest {
        var userId: String
        var activityId: Int
        var objective: String
        var objectiveTarget: Int
        var budgetPoints: Int
        var durationDays: Int
        var placement: String
        var dailyLimit: Int
        var audience: Audience

        func params() -> [String: String] {
            let targetingJSON = (try? JSONEncoder().encode(audience)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return [
                "userId": userId,
                "activityId": String(activityId),
                "objectif": objective,
                "objectifCible": String(objectiveTarget),
                "budgetPoints": String(budgetPoints),
                "durationDays": String(durationDays),
                "placement": placement,
                "dailyLimit": String(dailyLimit),
                "targeting": targetingJSON,
            ]
        }
    }

    /// Port de `boostContent`/`boostContent2` — DEUX endpoints distincts selon la devise choisie
    /// (`usingCoins` côté Android), MÊME payload, reproduit avec un paramètre explicite plutôt qu'un
    /// booléen ambigu au call site.
    func createBoost(_ request: BoostRequest, useGems: Bool) async throws {
        let endpoint = useGems ? "boost/create2" : "boost/create"
        let value = try await APIClient.shared.post(request.params(), endpoint: endpoint)
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? endpoint) }
    }

    /// Port de `boostUpdate`/`BoostDashboardFragment.update` — `{userId, boostId, key:"status",
    /// value:action}`.
    func updateStatus(userId: String, boostId: Int, value newValue: String) async throws {
        let params = ["userId": userId, "boostId": String(boostId), "key": "status", "value": newValue]
        let value = try await APIClient.shared.post(params, endpoint: "boost/update")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "boost/update") }
    }

    /// Port de `CommandeActivity.collectDataForApi()`/`boostCancel` — MÊME forme que
    /// `updateStatus` ci-dessus (`key:"status", value:"cancel"`), endpoint DIFFÉRENT
    /// (`boost/cancel2`, pas `boost/update`) — vérifié dans le fichier source, pas supposé.
    func cancelBoost(userId: String, boostId: Int) async throws {
        let params = ["userId": userId, "boostId": String(boostId), "key": "status", "value": "cancel"]
        let value = try await APIClient.shared.post(params, endpoint: "boost/cancel2")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "boost/cancel2") }
    }
}
