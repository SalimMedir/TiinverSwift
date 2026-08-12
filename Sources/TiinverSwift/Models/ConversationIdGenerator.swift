import Foundation

/// Port de `messagerie/ui/ConversationIdGenerator.java` (module 11) — identifiant de conversation
/// DÉTERMINISTE (tri alphabétique des deux participants, jointure par `_`), pour que les DEUX
/// parties calculent EXACTEMENT le même id sans dépendre de qui est `from`/`to` — vérifié réutilisé
/// tel quel à la réception d'un message (`ChatManager.addMessage`, `getGenarateConversationId`
/// recalculé localement plutôt que de faire confiance au `conversationId` envoyé par le serveur).
enum ConversationIdGenerator {
    private static let separator = "_"

    static func conversationId(currentUser: String, remoteUser: String) -> String {
        [currentUser, remoteUser].sorted().joined(separator: separator)
    }

    static func groupConversationId(currentUser: String, remoteUser: String, type: String = "chatgroup") -> String {
        [currentUser, remoteUser, type].sorted().joined(separator: separator)
    }
}
