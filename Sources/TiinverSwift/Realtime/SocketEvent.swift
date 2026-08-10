import Foundation

/// Noms d'événements Socket.IO échangés avec le backend, reproduits à l'identique
/// (voir TIINVER_IOS_PORT_ANALYSIS.md §6.3, point 5, et messagerie/socketio/**, service/CallService.java).
/// NE PAS renommer/traduire — le serveur (hors périmètre du portage) reste inchangé.
enum SocketEvent {
    static let call = "CALL"
    static let acceptCall = "ACCEPT_CALL"
    static let endCall = "ENDCALL"
    static let ringing = "RINGING"
    static let webrtcMessage = "WEBRTC_MESSAGE"
    static let joinRoom = "JOIN_ROOM"
    static let leaveRoom = "LEAVE_ROOM"
    static let newMessage = "NEW_MESSAGE"
    static let newGroupMessage = "NEW_GROUP_MESSAGE"
    static let typing = "TYPING"
    static let stopTyping = "STOP_TYPING"
    static let displayed = "DISPLAYED"
    static let delivered = "DELIVERED"
    static let presence = "PRESENCE"
    static let offlineStatus = "OFFLINE_STATUS"
    static let onStartPrivatePBS = "ON_START_PRIVATE_PBS"
    static let onJoinPrivatePBS = "ON_JOIN_PRIVATE_PBS"
    static let onTouchListener = "ON_TOUCH_LISTENER"
    static let onReceiveData = "ON_RECEIVE_DATA"
    /// Émissions texte brut côté Android (pas de constante dédiée, chaînes littérales) — répliquées telles quelles.
    static let addUser = "add user"
    static let offlineStatusLegacy = "offline status"
}
