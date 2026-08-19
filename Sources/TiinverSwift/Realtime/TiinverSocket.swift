import Foundation
import SocketIO

/// Réplique fidèlement `messagerie/socketio/SocketInit.java`.
///
/// Contrat serveur non négociable (voir TIINVER_IOS_PORT_ANALYSIS.md §6.3, point 4) :
///  - `transports` forcé à `["websocket"]`, pas de fallback polling.
///  - `secure = true`.
///  - Authentification via `auth: {"token": apiKey}` transmise AU HANDSHAKE (pas un header HTTP).
///  - Reconnection infinie avec backoff 1s → 30s, `randomizationFactor = 0.5`.
///  - Timeout de connexion 10s.
///
/// ⚠️ DÉCISION AUTONOME À VÉRIFIER SUR MACOS (voir MIGRATION_PROGRESS.md, journal de décisions) :
/// `Socket.IO-Client-Swift` (16.x) n'expose pas avec certitude un équivalent 1:1 du champ `auth`
/// du protocole Socket.IO v4 (celui que le serveur lit via `socket.handshake.auth.token`, cf.
/// commentaire Java `SocketInit.java:35`). L'option `.connectParams` ci-dessous envoie les données
/// comme paramètres de requête Engine.IO (`handshake.query`), ce qui est l'approche la plus
/// proche disponible dans la configuration déclarative de la lib, mais CE N'EST PAS
/// garanti identique à `handshake.auth` côté serveur — à valider dès qu'un premier build/run
/// réel est possible (device ou simulateur macOS), en vérifiant côté serveur quel champ du
/// handshake reçoit effectivement le token. Si `handshake.auth.token` reste vide, il faudra
/// examiner la version exacte de la lib pour une option `auth` dédiée, ou construire le socket
/// manuellement via `SocketManager(socketURL:config:)` avec une configuration plus bas niveau.
final class TiinverSocket {
    static let shared = TiinverSocket()

    private var manager: SocketIO.SocketManager?
    private(set) var socket: SocketIOClient?

    private init() {}

    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-016/023, Phase B P0-1)** — cette
    /// classe correspondait fidèlement à `SocketInit.createSocket(apiKey)` (construction) mais
    /// n'avait pas d'équivalent des 3 méthodes RÉELLEMENT appelées côté Android
    /// (`App.getSocket()`/`connectSocket()`/`resetSocket()`, `App.java:88-171`) — résultat : rien
    /// n'appelait jamais `connect(apiKey:)` nulle part dans le projet (confirmé par grep exhaustif,
    /// 2 fois indépendamment), le socket ne se connectait donc JAMAIS en pratique.
    ///
    /// Port fidèle de la séparation Android `getSocket()` (lazy, mémoïsé, NE connecte PAS) /
    /// `connectSocket()` (idempotent, connecte seulement si nécessaire) / `resetSocket()` (détruit
    /// et recrée avec un nouveau token, utilisé après un login qui a lieu APRÈS qu'un premier
    /// singleton anonyme ait déjà pu être créé — voir `ChatRepository.swift` pour le point d'appel
    /// réel de `reset(apiKey:)`).
    private func ensureSocket(apiKey: String?) -> SocketIOClient? {
        if let socket { return socket }
        var config: SocketIOClientConfiguration = [
            .forceNew(false),
            .reconnects(true),
            .reconnectAttempts(-1),   // Integer.MAX_VALUE côté Android == retries illimités
            .reconnectWait(1),        // reconnectionDelay = 1000ms
            .reconnectWaitMax(30),    // reconnectionDelayMax = 30000ms
            .randomizationFactor(0.5),
            .secure(true),
            .forceWebsockets(true)    // transports = ["websocket"], pas de fallback polling
        ]
        if let apiKey, !apiKey.isEmpty {
            config.insert(.connectParams(["token": apiKey]))
        }

        guard let url = URL(string: APIEnvironment.socketURL) else { return nil }
        let manager = SocketIO.SocketManager(socketURL: url, config: config)
        self.manager = manager
        self.socket = manager.defaultSocket
        return socket
    }

    /// Port de `App.connectSocket()` — IDEMPOTENT : ne (re)lance une connexion que si le socket
    /// n'est pas déjà connecté/en cours de connexion, fidèle au `if (!socket.connected())`
    /// original (`App.java:120-129`).
    func connect(apiKey: String?) {
        guard let socket = ensureSocket(apiKey: apiKey) else { return }
        switch socket.status {
        case .connected, .connecting:
            return
        default:
            socket.connect(timeoutAfter: 10, withHandler: nil)
        }
    }

    /// Port de `App.resetSocket()` (`App.java:157-171`) — détruit le socket existant (avec le
    /// jeton potentiellement obsolète/absent d'AVANT le login, cas réel si `ChatRepository.shared`
    /// a été touché une première fois avant authentification) et le recrée avec le jeton COURANT.
    func reset(apiKey: String?) {
        // Pas de `removeAllHandlers()` (API non confirmée disponible dans cette version de la
        // bibliothèque, non utilisée ailleurs dans ce projet) — `disconnect()` suffit, l'ancienne
        // instance `SocketIOClient` est de toute façon abandonnée juste après (ARC), ses handlers
        // ne peuvent plus jamais se déclencher une fois `socket = nil` ci-dessous.
        socket?.disconnect()
        manager = nil
        socket = nil
        connect(apiKey: apiKey)
    }

    /// Port de `App.disconnectSocket()` — **PAS appelé au logout** côté Android (vérifié :
    /// l'unique site d'appel réel est `App.onTerminate()`, PAS un flux de déconnexion utilisateur,
    /// malgré ce que suggère le commentaire de tête de la méthode Android elle-même) — reproduit
    /// fidèlement : cette méthode reste disponible mais n'est pas câblée au logout iOS non plus
    /// (voir `SettingSubViews.logout()`), pour rester fidèle au comportement RÉEL Android, pas à
    /// son commentaire aspirant.
    func disconnect() {
        socket?.disconnect()
        manager = nil
        socket = nil
    }
}
