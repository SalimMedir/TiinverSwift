import Foundation

/// Port de `comments/controller/CommentRepository.java` (282 lignes, entier).
@MainActor
final class CommentRepository {
    static let shared = CommentRepository()
    private init() {}

    /// Port de `getComment` — commentaires de premier niveau.
    func comments(activityId: Int, limit: Int, offset: Int) async throws -> [Comment] {
        let value = try await APIClient.shared.get("comment/\(activityId)/\(limit)/\(offset)")
        guard value.isBackendSuccess, let data = value["comments"]?.rawData else { return [] }
        return (try? JSONDecoder().decode([Comment].self, from: data)) ?? []
    }

    /// Port de `getReplay` — **chemin d'URL EXACT préservé, avec le `/` de tête intégré à la
    /// chaîne elle-même** (`"/comment/replay/"+activityId+...`, vérifié ligne par ligne — un
    /// artefact du concat Android, PAS corrigé pour rester fidèle à ce qui est réellement envoyé
    /// sur le fil, même si `APIClient` normalise probablement le double slash résultant).
    func replies(commentId: Int, limit: Int, offset: Int) async throws -> [Comment] {
        let value = try await APIClient.shared.get("/comment/replay/\(commentId)/\(limit)/\(offset)")
        guard value.isBackendSuccess, let data = value["comments"]?.rawData else { return [] }
        return (try? JSONDecoder().decode([Comment].self, from: data)) ?? []
    }

    /// Port de `postComment` — `POST comment`, `parentId` présent uniquement pour une réponse.
    func post(activityId: Int, text: String, parentId: Int?) async throws {
        var params = ["activityId": String(activityId), "commentText": text, "userId": UserSession.shared.myId ?? ""]
        if let parentId { params["parentId"] = String(parentId) }
        _ = try await APIClient.shared.post(params, endpoint: "comment")
    }
}
