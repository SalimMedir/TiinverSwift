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
/// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-024 CHAT-03, Phase B P0-8)** —
/// l'incertitude précédemment documentée ici est résolue avec preuve à l'appui, pas devinée.
/// Confirmé : `SocketInit.java:37` (Android) envoie `opts.auth = {"token": apiKey}`, un vrai champ
/// `IO.Options.auth` de `socket.io-client-java`, lu côté serveur via `socket.handshake.auth.token`
/// (commentaire Java ligne 35). Confirmé aussi (documentation officielle de la bibliothèque Swift
/// épinglée, `Socket.IO-Client-Swift` 16.1.1 — dernière version publiée, vérifiée via la page
/// `SocketIOClientOption` du site de docs généré) : `SocketIOClientConfiguration`/
/// `SocketIOClientOption` n'a AUCUN cas `.auth` — `.connectParams` (utilisé par l'ancienne version
/// de ce fichier) envoie le jeton comme paramètre de requête Engine.IO (`handshake.query`), PAS
/// comme `handshake.auth`, un canal différent que le serveur ne lit pas d'après le commentaire
/// Android. En revanche `SocketIOClient` expose bien `connect(withPayload:timeoutAfter:
/// withHandler:)` (vérifié sur la page de docs `SocketIOClient`) : le paramètre `withPayload`
/// envoie un dictionnaire comme charge utile du paquet CONNECT Socket.IO v4 pour ce namespace —
/// c'est le mécanisme réellement équivalent à `IO.Options.auth`, PAS `.connectParams`. `.
/// connectParams` est donc retiré de la configuration ci-dessous ; le jeton est maintenant transmis
/// via `withPayload` au moment de `connect()`, ce qui a un avantage supplémentaire : il n'est plus
/// figé dans une configuration mémoïsée à la construction (`ensureSocket`), il est envoyé frais à
/// chaque appel de `connect()`/`reset()`. **Reste à vérifier sur une connexion réelle** que le
/// serveur associe bien la session au bon utilisateur après ce changement (aucun test réel possible
/// dans cette session, conformément à la consigne permanente de ne pas déclencher Appetize).
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
    /// Le jeton n'est plus passé ici (voir `connect(apiKey:)`, P0-8) — cette fonction ne construit
    /// plus qu'une configuration transport SANS auth, mémoïsée une seule fois comme côté Android
    /// (`getSocket()` construit le `Socket` une fois, l'auth est envoyée séparément à chaque
    /// `connect()` via le paquet CONNECT, pas figée dans les options de transport).
    private func ensureSocket() -> SocketIOClient? {
        if let socket { return socket }
        let config: SocketIOClientConfiguration = [
            .forceNew(false),
            .reconnects(true),
            .reconnectAttempts(-1),   // Integer.MAX_VALUE côté Android == retries illimités
            .reconnectWait(1),        // reconnectionDelay = 1000ms
            .reconnectWaitMax(30),    // reconnectionDelayMax = 30000ms
            .randomizationFactor(0.5),
            .secure(true),
            .forceWebsockets(true)    // transports = ["websocket"], pas de fallback polling
        ]

        guard let url = URL(string: APIEnvironment.socketURL) else { return nil }
        let manager = SocketIO.SocketManager(socketURL: url, config: config)
        self.manager = manager
        self.socket = manager.defaultSocket
        return socket
    }

    /// Port de `App.connectSocket()` — IDEMPOTENT : ne (re)lance une connexion que si le socket
    /// n'est pas déjà connecté/en cours de connexion, fidèle au `if (!socket.connected())`
    /// original (`App.java:120-129`). Le jeton est transmis via `withPayload`, port réel de
    /// `IO.Options.auth` (voir le commentaire de tête de fichier, P0-8) — envoyé frais à chaque
    /// appel, jamais figé dans une configuration mémoïsée.
    func connect(apiKey: String?) {
        guard let socket = ensureSocket() else { return }
        switch socket.status {
        case .connected, .connecting:
            return
        default:
            let payload: [String: Any]? = (apiKey?.isEmpty == false) ? ["token": apiKey!] : nil
            // Diagnostic temporaire (2026-09-04, audit "conversation instantanée") — voir
            // `SocketDiagnostics` pour le raisonnement complet.
            Task { @MainActor in SocketDiagnostics.shared.recordConnectAttempt(hadPayload: payload != nil) }
            socket.connect(withPayload: payload, timeoutAfter: 10, withHandler: nil)
        }
    }

    /// Port de `App.resetSocket()` (`App.java:157-171`) — détruit le socket existant (avec le
    /// jeton potentiellement obsolète/absent d'AVANT le login, cas réel si `ChatRepository.shared`
    /// a été touché une première fois avant authentification) et le recrée avec le jeton COURANT.
    /// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-071, Phase B P2)** — le
    /// commentaire précédent écartait `removeAllHandlers()` par prudence ("API non confirmée
    /// disponible"), sans vérifier : `.off(_:)`/`.off(clientEvent:)` sont déjà utilisés ailleurs
    /// dans ce même projet (`ChatRepository.registerAllListeners`), donc l'API `SocketIOClient` est
    /// bien disponible dans cette version — `removeAllHandlers()` (même famille d'API, présente
    /// depuis les toutes premières versions publiées de la bibliothèque) l'est tout autant. Port
    /// fidèle d'`App.resetSocket()` (`App.java:157-171` : `mSocket.off()` PUIS `disconnect()`, dans
    /// cet ordre) — retire tous les handlers de l'ANCIEN socket AVANT de le déconnecter, pour qu'un
    /// événement `.disconnect` en attente de dispatch (comportement interne de la bibliothèque non
    /// garanti synchrone) ne puisse plus jamais exécuter `ChatRepository.onDisconnected` avec des
    /// données déjà réassignées au nouveau socket — risque documenté d'un `leaveRoom` parasite émis
    /// juste après une reconnexion, auparavant écarté par la seule désallocation ARC (non garantie
    /// immédiate/synchrone). Pas d'équivalent iOS aux 3 listeners `.io()`/Manager retirés côté
    /// Android (`EVENT_RECONNECT`/`_ATTEMPT`/`_ERROR`) — aucun listener n'est enregistré sur
    /// `manager` nulle part dans ce projet (grep exhaustif), rien à nettoyer à ce niveau.
    func reset(apiKey: String?) {
        socket?.removeAllHandlers()
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
    /// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-071, Phase B P2)** — même
    /// correctif que `reset(apiKey:)` ci-dessus, même source Android (`disconnectSocket()`,
    /// `App.java:136-151` : `mSocket.off()` PUIS `disconnect()`, identique à `resetSocket()`).
    func disconnect() {
        socket?.removeAllHandlers()
        socket?.disconnect()
        manager = nil
        socket = nil
    }
}
