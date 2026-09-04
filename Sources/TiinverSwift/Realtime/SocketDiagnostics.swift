import Combine
import Foundation

/// **Ajouté (2026-09-04, diagnostic temporaire — audit "conversation instantanée")** — expose
/// visuellement, sans avoir besoin de la console Xcode (indisponible en test via Appetize), l'état
/// RÉEL du cycle de vie de la socket : ce que `ChatRepository.registerAllListeners()`/`onConnected`/
/// `onDisconnected` savent déjà en interne (imprimé au mieux via `print()`, invisible en dehors
/// d'une session de debug locale), republié ici pour `SocketDiagnosticsView`.
///
/// Objet séparé de `ChatRepository` (qui n'est PAS un `ObservableObject`, utilisé par de nombreux
/// appelants non-UI) plutôt que d'y ajouter `@Published`/`ObservableObject` — évite tout risque de
/// régression sur un type déjà largement utilisé, pour un besoin purement diagnostique et temporaire.
@MainActor
final class SocketDiagnostics: ObservableObject {
    static let shared = SocketDiagnostics()

    @Published private(set) var status: String = "Jamais connectée"
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var connectAttempts: Int = 0
    /// Port de `App.java`'s log `"✅ Socket initialisé avec auth token"`/`"⚠️ ... sans auth token"` —
    /// ne montre JAMAIS la valeur du jeton lui-même, seulement sa présence, pour ne pas exposer un
    /// secret d'authentification à l'écran.
    @Published private(set) var lastConnectHadPayload: Bool?
    /// Nombre d'événements `presence`/`typing`/`new message`/`new message group` REÇUS depuis le
    /// lancement — un compteur à 0 après plusieurs minutes de connexion "Connectée" indiquerait que
    /// le serveur accepte la connexion transport mais ne pousse jamais rien à cette socket
    /// (cohérent avec un jeton d'authentification non reconnu côté serveur).
    @Published private(set) var liveServerEventsReceivedCount: Int = 0
    @Published private(set) var lastLiveServerEventName: String?

    let socketURL = APIEnvironment.socketURL

    private init() {}

    func recordLiveServerEvent(_ name: String) {
        liveServerEventsReceivedCount += 1
        lastLiveServerEventName = name
        lastEventAt = Date()
    }

    func recordConnectAttempt(hadPayload: Bool) {
        connectAttempts += 1
        lastConnectHadPayload = hadPayload
        status = "Connexion en cours…"
        lastEventAt = Date()
    }

    func recordConnected() {
        status = "Connectée"
        lastEventAt = Date()
    }

    func recordDisconnected(reason: String) {
        status = "Déconnectée"
        lastErrorMessage = reason
        lastEventAt = Date()
    }

    func recordError(_ message: String) {
        status = "Erreur"
        lastErrorMessage = message
        lastEventAt = Date()
    }
}
