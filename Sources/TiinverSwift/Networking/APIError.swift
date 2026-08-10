import Foundation

enum APIError: Error, LocalizedError {
    case transport(Error)
    case invalidResponse
    case server(message: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .transport(let error): return error.localizedDescription
        case .invalidResponse: return "Réponse serveur invalide."
        case .server(let message): return message
        case .decoding(let error): return "Erreur de décodage: \(error.localizedDescription)"
        }
    }
}
