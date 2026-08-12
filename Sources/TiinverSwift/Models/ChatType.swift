import Foundation

/// Port de `messagerie/ChatType.java` (module 11).
enum ChatType {
    case group
    case chat

    /// Port de `ChatType.getChatType` — valeur de fil `"chat"`/`"chatgroup"`, utilisée comme
    /// valeur du champ `type` dans `MessageLib`/`MessagePacket` ET comme suffixe de sélection
    /// public/groupe pour plusieurs émissions socket (`ChatRepository.java`).
    var wireValue: String {
        switch self {
        case .group: return "chatgroup"
        case .chat: return "chat"
        }
    }
}
