import Foundation

/// Port de `models/roster/RosterModel.java` (lu en entier) — identité d'UNE conversation ouverte
/// (passé à `ChatFragmentTest.newInstance(RosterModel)` côté Android). Construit à partir de
/// `RosterEntity` (Core Data, module 2) + `UserSession` (utilisateur courant) par l'écran de liste
/// des conversations — **cet écran-liste (`RosterFragment`/équivalent, PAS lu cette session, hors
/// périmètre explicite "MessageListAdapter + ViewHolders + ChatFragmentTest") reste à porter** ;
/// `ChatView`/`ChatViewModel` ci-dessous acceptent un `RosterModel` déjà construit, exactement comme
/// `ChatFragmentTest` reçoit le sien via `Bundle`/`ARG_OBJECT`.
struct RosterModel: Equatable {
    var id: Int = 0
    var conversationId: String?
    var from: String?
    var to: String?
    var messageId: String?
    var userId: String?
    var sender: String?
    var receiver: String?
    var currentUserId: String?
    var currentNikname: String?
    var currentUsername: String?
    var token: String?
    var groupType: String?
    /// Port de `type` — `"chat"`/`"chatgroup"` (`ChatType.wireValue`).
    var type: String = ChatType.chat.wireValue
    var groupName: String?
    var username: String?
    var nikname: String?
    var groupId: String?
    var stamp: String?
    var message: String?
    var object: String?
    var verb: String?
    var status: Int = 0
    var profile: String?
    var title: String?
    var subTitle: String?
    var groupMember: Bool = false
    var newMessage: Bool = false
    var vu: Bool = false
    var belongsToCurrentUser: Bool = false
    var isOnline: Bool = false
    var isTyping: Bool = false
    var unreadCount: Int = 0
    var creator: String?
    var description: String?
    var price: Int = 0
    var lucrative: Int = 0
    var versionCode: Int = 126

    /// Port de `MessageLib.WireType`/`ChatType.getChatType(ChatType.GROUP)` — vrai si la
    /// conversation est un groupe, PAS un chat 1:1.
    var isGroup: Bool { type == ChatType.group.wireValue }
}
