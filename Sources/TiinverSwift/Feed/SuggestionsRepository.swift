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
        if let nested = try? value.stringEncodedJSON("users"), let data = nested.rawData,
            let users = try? JSONDecoder().decode([User].self, from: data)
        {
            return users
        }
        if let data = value["users"]?.rawData, let users = try? JSONDecoder().decode([User].self, from: data) {
            return users
        }
        return []
    }
}
