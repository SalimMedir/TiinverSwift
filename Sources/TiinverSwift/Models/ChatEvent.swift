import Foundation

/// Port des petits modèles d'événement de `messagerie/model/**` (`ChatModel.java`/
/// `PresenceModel.java`/`TypingModel.java`/`MessageStatusModel.java`, 87+22+22+31 lignes, tous lus
/// en entier) et de `models/chat/call/CallModel.java` (44 lignes) — consolidés en DEUX `enum` Swift
/// à valeurs associées plutôt qu'un type "tag entier + N champs nullable dont un seul est
/// pertinent" (`ChatModel.type`/`CallModel.type`), plus idiomatique et rend les combinaisons
/// invalides irreprésentables (contrairement à l'original, où rien n'empêche par ex.
/// `ChatModel.setType(PRESENCE)` avec un `message` non-null oublié).
enum ChatEvent {
    case message(MessageLib)
    case messageStatus(messageId: String, receiver: String, status: MessageDeliveryStatus)
    case presence(username: String, online: Bool)
    case typing(username: String, isTyping: Bool)
    case pbs(PBSEvent)
}

/// Port des constantes `MessageStatusModel`/`ChatRepository.onResponse` (`"sended"`/`"delivered"`/
/// `"displayed"`/`"reproduced"` → 1/2/3/4, valeurs `status` stockées telles quelles dans
/// `wk_messages`/`wk_roster`).
enum MessageDeliveryStatus: Int {
    case sent = 1
    case delivered = 2
    case displayed = 3
    case reproduced = 4
}

/// Port des événements Shareboard/PBS routés par `ChatRepository` (`PBSModel.type`,
/// `ChatModel.PBS`+`ON_START_PRIVATE_PBS`/`NEXT_PAGE`/etc.) — payload `data` laissé en `String`
/// JSON brut (comme l'original, `PBSModel.data`), le module Shareboard/PBS (13) n'étant pas
/// encore porté pour décoder sa forme exacte.
enum PBSEvent {
    case nextPage
    case precedentPage
    case joinRoom(data: String)
    case leaveRoom(data: String)
    case onReceiveData(data: String)
    case onTouchListener(data: String)
    /// Port de `ChatModel.ON_START_PRIVATE_PBS`/`ONSTART` — les deux portent un `Profile`
    /// (devenu `ChatProfile`) en plus du `data` brut, contrairement aux autres cas PBS.
    case onStartPrivate(profile: ChatProfile, data: String)
    case onStart(profile: ChatProfile, data: String)
    case onJoinPrivate(data: String)
    case webrtcMessage(data: String)
}

/// Port de `models/chat/call/CallModel.java` (constantes `ACCEPT_CALL`/`END_CALL`/`BUSY_CALL`/
/// `RINGING`/`WEBRTC_MESSAGE`/`ONCALL`/`WEBRTC_STATUS`/`DECLINE_CALL`/`ELAPSEDTIME` → un seul
/// `type`, ici un cas d'enum par constante). `OUTGOINGCALL`/`INCOMINGCALL`/`BACKGROUND`/
/// `FOREGROUND` (101/102/201/202) appartiennent au module 12 (CallService, pas encore porté) —
/// non repris ici, ce ne sont pas des types d'événement `ChatRepository` mais des extras
/// `Intent`/`CallService`.
enum CallEvent {
    case acceptCall
    case endCall(data: String)
    case busyCall(data: String)
    case ringing(data: String)
    case webrtcMessage(data: String)
    /// Port de `ONCALL` — reçu quand un appel arrive alors qu'un autre est déjà en cours
    /// (`CallService.isOnCall == true`), ou en écho d'un message `"voicecall"` reçu pendant un
    /// appel actif (`ChatRepository.NewPrivateMessage`/`NewGroupMessage`).
    case onCall(data: String)
    case webrtcStatus(Int)
    case declineCall
    case elapsedTime
}
