import Foundation

/// Port de `models/ai/AIMessage.java` — un message affiché dans `TiinverGeminiAIChat`, texte OU
/// image (`type`), utilisateur OU assistant (`role`). Persisté via `AiConversationRepository`
/// (déjà porté, module 2 — `AiConversationEntity`, `role`/`type`/`content` mêmes champs).
struct AIChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    enum Kind: Equatable { case text(String), image(URL) }

    let id = UUID()
    var role: Role
    var kind: Kind
    var stamp: Int64
    /// `true` pendant l'attente de la réponse serveur — port du "shimmer" (`AIMessage.shimmer()`).
    var isPending: Bool = false
}

/// Port de `callTextApi`'s réponse succès (`action == 0`) — `POST ai/chat {message}`.
struct AIChatReply {
    var reply: String
    var used: Int
    var remaining: Int
    var limit: Int
}

/// Port de `callImageApi`'s réponse succès — `POST ai/image/generate {prompt, image_base64?,
/// image_mime?}`.
struct AIImageResult {
    var imageBase64: String
}

/// Port de l'erreur `{quota: true, message}` (`ai/chat`) ou `{insufficient: true,
/// current_balance, message}` (`ai/image/generate`) — reproduit sous forme d'erreur Swift typée
/// plutôt que de deviner un format d'erreur générique unique pour les deux endpoints (leurs champs
/// diffèrent réellement, vérifié dans le code source Android).
enum AIChatError: Error {
    case quotaReached(message: String)
    case insufficientCoins(currentBalance: Double, message: String)
    case generic(message: String)
}
