import Foundation

/// Port de `comments/controller/CommentRepository.java` (282 lignes, entier).
@MainActor
final class CommentRepository {
    static let shared = CommentRepository()
    private init() {}

    /// Port de `getComment` — commentaires de premier niveau.
    func comments(activityId: Int, limit: Int, offset: Int) async throws -> [Comment] {
        let value = try await APIClient.shared.get("comment/\(activityId)/\(limit)/\(offset)")
        guard value.isBackendSuccess else { return [] }
        return Self.decodeComments(value["comments"]?.toArray())
    }

    /// Port de `getReplay` — **chemin d'URL EXACT préservé, avec le `/` de tête intégré à la
    /// chaîne elle-même** (`"/comment/replay/"+activityId+...`, vérifié ligne par ligne — un
    /// artefact du concat Android, PAS corrigé pour rester fidèle à ce qui est réellement envoyé
    /// sur le fil, même si `APIClient` normalise probablement le double slash résultant).
    func replies(commentId: Int, limit: Int, offset: Int) async throws -> [Comment] {
        let value = try await APIClient.shared.get("/comment/replay/\(commentId)/\(limit)/\(offset)")
        guard value.isBackendSuccess else { return [] }
        return Self.decodeComments(value["comments"]?.toArray())
    }

    /// Corrigé (V3-F-093, SILENT-04) : `comments`/`replies` décodaient le tableau ENTIER en un seul
    /// `try?` — plusieurs champs de `Comment` (`username`/`firstname`/.../`giftName`) ne sont PAS
    /// lenient (`decodeIfPresent(String.self,...)` strict sur le TYPE si la clé est présente), donc
    /// UN SEUL commentaire avec un champ de type inattendu faisait échouer TOUTE la liste d'un
    /// coup, vidée silencieusement en `[]`. Même motif déjà corrigé pour `TrophyRepository.
    /// weeklyRank`/`WalletRepository.transactions` — `compactMap` per-item avec diagnostic.
    private static func decodeComments(_ array: [JSONValue]?) -> [Comment] {
        guard let array else { return [] }
        let decoded = array.compactMap { item -> Comment? in
            guard let data = item.rawData else {
                print("COMMENTS: item.rawData nil for one comment — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(Comment.self, from: data)
            } catch {
                print("COMMENTS: decode failure for one comment — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("COMMENTS: received=\(array.count), only \(decoded.count) usable — \(array.count - decoded.count) skipped, see above")
        }
        return decoded
    }

    /// Port de `postComment` — `POST comment`, `parentId` présent uniquement pour une réponse.
    func post(activityId: Int, text: String, parentId: Int?) async throws {
        var params = ["activityId": String(activityId), "commentText": text, "userId": UserSession.shared.myId ?? ""]
        if let parentId { params["parentId"] = String(parentId) }
        _ = try await APIClient.shared.post(params, endpoint: "comment")
    }
}
