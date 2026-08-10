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

    /// Équivalent de `SocketInit.createSocket(apiKey)`.
    func connect(apiKey: String?) {
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

        guard let url = URL(string: APIEnvironment.socketURL) else { return }
        let manager = SocketIO.SocketManager(socketURL: url, config: config)
        self.manager = manager
        self.socket = manager.defaultSocket
        socket?.connect(timeoutAfter: 10, withHandler: nil)
    }

    func disconnect() {
        socket?.disconnect()
        manager = nil
        socket = nil
    }
}
