import Foundation

/// Port de `Recherche/ui/RechercheTiinver.java` (754 lignes — recherche/réseau seule lue en
/// détail, chrome RecyclerView/onglets ignoré) + `RecentSearchManager.java` (69, entier).
/// **`RechercheTiinver2.java` (681 lignes) CONFIRMÉ MORT** par grep exhaustif — seul
/// `RechercheTiinver.class` est instancié ailleurs dans le code (`MainFragment`/`FeedFragment`/
/// `Roster`/`MentionTextView`), même méthodologie que les autres clusters "v2" morts déjà trouvés
/// dans ce portage. `Recherche/SearchRepository.java` (le vrai fichier Android de ce nom) est VIDE
/// (4 lignes, classe sans corps) — toute la logique réseau vit en réalité dans l'Activity elle-même.
@MainActor
final class SearchRepository {
    static let shared = SearchRepository()
    private init() {}

    /// Port de `searchSuggest` — endpoint léger, pas de tri par onglet. `isFull: false`
    /// (V3-F-106) : `parseAndDisplay(object, isFull=false, tab)` garde explicitement
    /// `showPosts = isFull && (...)`, donc les résultats "posts" ne sont JAMAIS rendus sur ce
    /// chemin même si le serveur les inclut dans la réponse.
    func suggest(query: String) async throws -> SearchResults {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return SearchResults() }
        let value = try await APIClient.shared.get("content/search/suggest?q=\(encoded)")
        return try Self.decodeResults(value, isFull: false)
    }

    /// Port de `searchFull` — `types` dérivé de l'onglet actif (`getTypesForTab`). `isFull: true`.
    func search(query: String, tab: SearchTab) async throws -> SearchResults {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return SearchResults() }
        let value = try await APIClient.shared.get("content/search?q=\(encoded)&types=\(tab.apiTypes)&limit=10&offset=0")
        return try Self.decodeResults(value, isFull: true)
    }

    /// Port de `object.getBoolean("error")`/`JSONObject results = object.getJSONObject("results")` —
    /// **convention DIFFÉRENTE du reste du backend ici** : `"error"` est un VRAI booléen JSON sur
    /// cet endpoint (vérifié dans `parseAndDisplay`), pas la chaîne `"false"`/`"true"` habituelle
    /// (`JSONValue.isBackendSuccess`, qui NE S'APPLIQUE PAS ici — pas utilisée volontairement).
    ///
    /// **Corrigé (V3-F-002, SEARCH-02)** — `parseAndDisplay` (`RechercheTiinver.java:461-573`)
    /// distingue deux états bien différents au même point du flux : `error==true` → `showEmpty(
    /// "Aucun résultat")` (silencieux, chemin normal) ; `results` absent/malformé →
    /// `JSONException` remontée par `getJSONObject("results")`, catchée en dehors et affichée comme
    /// `showEmpty("Erreur de chargement")` (échec RÉEL, message différent). L'ancienne version de
    /// cette fonction avalait les deux cas dans le même `try?` → `SearchResults()` vide, rendant les
    /// deux états indiscernables côté iOS malgré `SearchView` ayant déjà le bon état `errorText`
    /// câblé (voir son commentaire `showEmpty("Erreur de chargement")`) — jamais atteint faute d'un
    /// throw ici. Seul le cas `error==true` reste silencieux ci-dessous ; tout échec de décodage de
    /// `results` (clé absente ou JSON malformé) propage maintenant l'erreur, fidèle à Android.
    ///
    /// **Corrigé (V3-F-106, SEARCH complémentaire)** — `parseAndDisplay` gate `showPosts = isFull
    /// && (tab=="all"||tab=="posts")` (`RechercheTiinver.java:421,461,528`) : le chemin suggestion
    /// (`isFull=false`) n'affiche JAMAIS de résultats "posts", même si le serveur les a inclus dans
    /// la réponse — cette garde manquait côté iOS (`decodeResults` ne recevait pas l'information
    /// `isFull`). `posts` vidé après décodage quand `isFull==false`, indépendant du comportement
    /// réel du serveur (défensif par construction, pas besoin d'inspection réseau pour trancher).
    private static func decodeResults(_ value: JSONValue, isFull: Bool) throws -> SearchResults {
        guard (try? value.bool("error")) != true else { return SearchResults() }
        guard let data = value["results"]?.rawData else {
            throw APIError.server(message: "results manquant")
        }
        var results = try JSONDecoder().decode(SearchResults.self, from: data)
        if !isFull { results.posts = [] }
        return results
    }
}

/// Port de `RecentSearchManager` — historique local, 10 entrées max, plus récente en tête.
/// Simplifié en `[String]`/`UserDefaults` direct (pas besoin du hack de concaténation `"|||"`
/// d'Android, artefact de son propre choix de stockage `SharedPreferences.getString`).
enum RecentSearchStore {
    private static let key = "tiinver_recent_searches"
    private static let maxItems = 10

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = all()
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        if list.count > maxItems { list = Array(list.prefix(maxItems)) }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func remove(_ entry: String) {
        var list = all()
        list.removeAll { $0 == entry }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
