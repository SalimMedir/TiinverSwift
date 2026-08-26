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
    ///
    /// **Corrigé (V5-F-045, 2026-08-24)** — `MyBottomSheetDialogFragment.java:498` :
    /// `map.put("comment", data.getCommentText())`, la clé réseau est `"comment"`. `"commentText"`
    /// n'est qu'un nom de champ Java interne (`CommentModel.commentText`), jamais sérialisé tel
    /// quel vers cet endpoint — confirmé distinct de `"comment_text"` (snake_case), la clé lue par
    /// `NotificationRepository.java:176` sur un endpoint DIFFÉRENT. Envoyer la mauvaise clé
    /// laissait le texte du commentaire probablement vide/absent côté serveur, sans qu'aucune
    /// erreur ne soit levée (seul `isBackendSuccess` est vérifié, pas le contenu retourné).
    func post(activityId: Int, text: String, parentId: Int?) async throws {
        var params = ["activityId": String(activityId), "comment": text, "userId": UserSession.shared.myId ?? ""]
        if let parentId { params["parentId"] = String(parentId) }
        _ = try await APIClient.shared.post(params, endpoint: "comment")
    }

    /// Port de `CommentViewModel.debitCoins`/`MyBottomSheetDialogFragment.onPost` (branche
    /// `object=="gift"`) — **ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-048, Phase B
    /// P2)**. Endpoint DISTINCT de `post(activityId:text:parentId:)` ci-dessus : `comment/add`
    /// (PAS `comment`), débit + commentaire en une SEULE requête serveur (vérifié
    /// `CommentRepository.java:240-247` : `td.Post(map, "comment/add", ...)`), pas de second appel
    /// réseau séparé côté client. Réponse `{"error": bool}` — `isBackendSuccess` gère déjà les deux
    /// conventions bool/string (voir `JSONValue.errorFieldNormalized`), fidèle au
    /// `object.getBoolean("error")` de ce callback précis (Android utilise `getBoolean` ICI,
    /// PAS `getString("error").equals("false")` comme `postComment` juste au-dessus — divergence
    /// réelle déjà neutralisée génériquement côté iOS).
    ///
    /// **Vérification financière** : AUCUNE mutation de solde ici — `senderId`/`amount` sont
    /// transmis au serveur qui applique le débit RÉEL server-side ; le solde local
    /// (`UserSession.shared.coinsAmount`) n'est décrémenté par l'appelant QU'APRÈS un succès
    /// confirmé (voir `CommentsView.sendGift`), jamais ici ni de façon optimiste — fidèle à
    /// `onPost` Android, qui ne touche `userCoinBalance` que dans la branche `Result.SUCCESS` de
    /// CE callback (jamais avant l'envoi).
    func sendGift(activityId: Int, userId: String, giftId: String, receiverId: String, amount: Int) async throws {
        let params = [
            "activityId": String(activityId), "userId": userId,
            "comment": giftId, "object": "gift",
            "senderId": userId, "receiverId": receiverId, "amount": String(amount),
        ]
        let value = try await APIClient.shared.post(params, endpoint: "comment/add")
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "comment/add")
        }
    }
}
