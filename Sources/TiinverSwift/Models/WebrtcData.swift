import Foundation

/// Port de `models/webrtc/WebrtcData.java` (lu en entier, module 12) — message de signalisation
/// WebRTC échangé via l'événement socket `webrtcMessage` (voir `ChatRepository.handleUnifiedWebrtcMessage`,
/// module 11 protocole). `candidateAdaptertype` (type d'adaptateur réseau Android — WiFi/cellulaire/VPN,
/// `PeerConnection.AdapterType`) et `candidateUrl` ne sont JAMAIS lus par `RTConnection2.onMessage`/
/// `processMessage` (confirmé par lecture complète) — champs write-only côté Android, PAS repris ici.
struct WebrtcData: Codable, Equatable {
    var messageId: String?
    var type: String?
    var sdp: String?
    var id: String?
    var candidate: String?
    var label: Int = 0

    enum CodingKeys: String, CodingKey {
        case messageId, type, sdp, id, candidate, label
    }

    init() {}

    /// Port des constantes `WebrtcData.CONNECTED`/`CLOSE`/`FAILED`/`CHECKING` — statut de connexion
    /// ICE relayé à l'écran d'appel (`sendWebrtcStatusToActivity`, `CallModel.WEBRTC_STATUS`).
    enum ConnectionStatus: Int {
        case connected = 1
        case closed = 2
        case failed = 3
        case checking = 4
    }
}
