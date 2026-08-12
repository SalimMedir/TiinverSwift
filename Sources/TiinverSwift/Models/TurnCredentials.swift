import Foundation

/// Port de `models/webrtc/TurnResponse.java` (lu en entier, module 12) — réponse de l'endpoint
/// `call/turn-credentials` (credentials TURN Cloudflare à durée de vie limitée, `ttl`). Port de
/// `TurnCredentialsFetcher.java` : `POST call/turn-credentials`, en-tête `Authorization: {apiKey}`,
/// corps vide — reproduit via `APIClient.shared.post([:], endpoint:)`, déjà vérifié module 4
/// (mêmes conventions d'en-têtes/enveloppe que le reste de l'API).
struct TurnCredentials: Codable, Equatable {
    var error: Bool = false
    var iceServers: IceServersData?
    var ttl: Int = 0

    struct IceServersData: Codable, Equatable {
        var urls: [String] = []
        var username: String?
        var credential: String?
    }
}
