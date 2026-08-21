import Foundation

/// Port de `TransportData.getSuggestionsUsers`/`MyBackgroundTask.getContentSuggested`
/// (`Http/TransportData.java:1256`, `back_sync/MyBackgroundTask.java:141`) — endpoint réel
/// `GET suggestions/{userId}`, alimente le carrousel horizontal de comptes à suivre affiché en
/// en-tête du fil (`feed_header_layout.xml`, `contacts_suggest` → `SuggestionsCarouselView`).
///
/// Côté Android, ces utilisateurs transitent par un cache SQLite local synchronisé en tâche de
/// fond (`infoContract.SUGGEST_URI`, `AdapterSuggestContact`/`CursorWorkerTask`) — délibérément
/// PAS reproduit ici : lecture réseau directe à chaque affichage, même simplification déjà
/// appliquée ailleurs dans ce portage pour tout ce qui relève du `ContentProvider`/`SyncAdapter`
/// Android sans équivalent iOS direct (voir `ProfileViewModel`/`FeedViewModel`, même motif).
@MainActor
final class SuggestionsRepository {
    static let shared = SuggestionsRepository()
    private init() {}

    func fetchSuggestions(userId: String) async throws -> [User] {
        let value = try await APIClient.shared.get("suggestions/\(userId)")
        guard value.isBackendSuccess else { return [] }
        // `js.getString("users")` + `Gson.fromJson(..., User[].class)` côté Android
        // (`TransportData.java:1261-1262`) : chaîne JSON ré-encodée à l'intérieur du champ
        // "users". Tolère AUSSI un tableau JSON direct par prudence — la même hypothèse de
        // double-encodage s'est révélée FAUSSE sur `weekly_rank` (voir `TrophyRepository.swift`,
        // cause racine confirmée le 2026-08-17 par JSON réel) : aucun JSON réel de CET endpoint
        // précis n'a encore été fourni par l'utilisateur, donc les deux formes sont essayées
        // plutôt que d'en supposer une seule sans preuve.
        if let nested = try? value.stringEncodedJSON("users"), let array = nested.toArray() {
            return Self.decodeUsers(array)
        }
        if let array = try? value.jsonArray("users") {
            return Self.decodeUsers(array)
        }
        return []
    }

    /// **Corrigé (V3-F-011, décodage per-item)** — `JSONDecoder().decode([User].self, ...)`
    /// décodait le tableau ENTIER en un bloc : un seul utilisateur suggéré dont un champ ne
    /// correspond pas exactement à `User` faisait disparaître TOUT le carrousel de suggestions,
    /// silencieusement (`try?` avalait l'erreur). Même motif déjà appliqué à
    /// `Realtime/ChatRepository.decodeMessages`/`Feed/FeedRepository.fetchTimeline` (V3-F-090) —
    /// réutilisé ici pour rester cohérent avec la convention déjà établie dans ce portage.
    private static func decodeUsers(_ items: [JSONValue]) -> [User] {
        let decoder = JSONDecoder()
        let decoded = items.compactMap { item -> User? in
            guard let data = item.rawData else {
                print("SUGGESTIONS: item.rawData nil for one user — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try decoder.decode(User.self, from: data)
            } catch {
                print("SUGGESTIONS: decode failure for one user — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != items.count {
            print("SUGGESTIONS: received=\(items.count) users, only \(decoded.count) decoded successfully — \(items.count - decoded.count) silently dropped, see decode failures above")
        }
        return decoded
    }
}
