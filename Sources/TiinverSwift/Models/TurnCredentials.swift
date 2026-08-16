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

    private enum CodingKeys: String, CodingKey { case error, iceServers, ttl }

    /// Décodage tolérant (2026-08-16) — `error`/`ttl` risquent la même divergence de type que
    /// partout ailleurs dans ce backend (voir `LenientDecoding.swift`) ; `= false`/`= 0` ne sert
    /// pas de repli au décodage `Decodable` synthétisé (piège Swift documenté).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = container.decodeLenientBoolIfPresent(forKey: .error) ?? false
        iceServers = try container.decodeIfPresent(IceServersData.self, forKey: .iceServers)
        ttl = container.decodeLenientIntIfPresent(forKey: .ttl) ?? 0
    }

    struct IceServersData: Codable, Equatable {
        var urls: [String] = []
        var username: String?
        var credential: String?
    }
}
