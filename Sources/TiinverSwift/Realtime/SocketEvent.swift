import Foundation

/// Noms d'événements Socket.IO échangés avec le backend, reproduits à l'identique.
/// NE PAS renommer/traduire — le serveur (hors périmètre du portage) reste inchangé.
///
/// **Bug trouvé et corrigé au module 11 (2026-08-11)** : la version précédente de ce fichier
/// (module 1) utilisait des valeurs MAJUSCULE_SNAKE_CASE (`"CALL"`, `"ACCEPT_CALL"`,
/// `"NEW_MESSAGE"`...) — ce sont les noms des CONSTANTES Java du rapport `TIINVER_IOS_PORT_
/// ANALYSIS.md` §6.3 point 5, PAS les valeurs de chaîne littérales réellement émises sur le
/// socket. En lisant `messagerie/repository/ChatRepository.java` (classe interne `ROOM`, lignes
/// 107-144) pour le module 11, découvert que les vraies valeurs sont des chaînes `camelCase`/
/// `lowercase avec espaces` totalement différentes (`"call"`, `"acceptCall"`, `"new message"`,
/// `"new message group"`, `"delivred"` — faute d'orthographe RÉELLE côté serveur/Android,
/// reproduite telle quelle, PAS corrigée en "delivered"). Avec les valeurs précédentes, AUCUN
/// événement chat/appel n'aurait jamais été reconnu par le serveur — bug fonctionnel silencieux
/// (aurait compilé sans erreur, mais le chat/les appels n'auraient jamais fonctionné à
/// l'exécution). Toutes les valeurs ci-dessous sont désormais recopiées directement depuis
/// `ChatRepository.ROOM` (source de vérité unique confirmée par le commentaire de tête du fichier
/// Android lui-même : "UN SEUL SINGLETON... CONSTANTES ÉVÉNEMENTS SOCKET").
enum SocketEvent {
    // MARK: - Appels (WebRTC)
    static let call = "call"
    static let acceptCall = "acceptCall"
    static let endCall = "endCall"
    static let ringing = "ringing"
    static let callBasic = "callBasic"
    static let webrtcMessage = "webrtcMessage"
    static let onVoiceCall = "onVoice"

    // MARK: - Présence
    static let presence = "presence"
    static let offlineStatus = "offline status"

    // MARK: - Salles (Shareboard/PBS/groupes)
    static let joinRoom = "joinRoom"
    static let startRoom = "startRoom"
    static let leaveRoom = "leaveRoom"
    /// Suffixe concaténé à `leaveRoom` pour un salon privé (port de `ROOM.LEAVE_ROOM +
    /// ROOM.PRIVATE_ACTION` dans `ChatManager.leaveRoom`) — PAS un événement autonome.
    static let privateAction = "PrivateAction"
    static let nextPage = "nextPage"
    static let beforePage = "beforePage"
    static let onTouchListener = "onPbsTouchListener"
    static let onReceiveData = "onData"
    static let onStartPrivatePBS = "onStartPrivatePbs"
    static let onJoinPrivatePBS = "onJoinPrivatePbs"

    // MARK: - Messages
    static let newMessage = "new message"
    static let updateMessage = "update message"
    static let updateGroupMessage = "update group message"
    static let onDeletePrivateMessage = "on delete private message"
    static let deletePrivateMessage = "delete private message"
    static let onDeleteGroupMessage = "on delete group message"
    static let newGroupMessage = "new message group"
    static let scheduledNewMessage = "scheduled new message"
    static let scheduledNewGroupMessage = "scheduled new message group"
    /// Faute d'orthographe RÉELLE côté source Android (`ChatRepository.ROOM.DELIVERED =
    /// "delivred"`) — reproduite à l'identique, c'est un accusé de réception envoyé sur le fil,
    /// "corriger" l'orthographe romprait le protocole avec le serveur.
    static let delivered = "delivred"
    static let displayed = "displayed"
    static let reproduced = "reproduced"
    static let typing = "typing"
    static let stopTyping = "stop typing"

    // MARK: - Notifications push (relayées par socket, pas seulement APNs/FCM)
    static let pushNotificationById = "pushNotification_by_id"
    static let pushNotification = "pushNotification"

    // MARK: - Divers
    static let onResponse = "on response"

    /// Émissions texte brut côté Android (pas de constante `ROOM.*` dédiée, chaînes littérales
    /// directement dans le code) — vérifiées par grep dans `ChatRepository.java`, reproduites
    /// telles quelles.
    static let addUser = "add user"
}
