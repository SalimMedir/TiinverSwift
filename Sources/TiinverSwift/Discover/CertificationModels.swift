import Foundation

/// Port de `models/certification/Certification.java` (104, entier).
struct CertificationStatus: Codable, Equatable {
    var pk_id: Int?
    var userId: Int?
    var is_certified: Int?
    var status: String?
    var level: String?
    var doc_url: String?
    var requested_at: String?
    var approved_at: String?
    var rejected_at: String?
    var reason: String?
    var expire_at: String?
}

/// Port de `ui/certification/CertificationRepository.java` (endpoints seuls vérifiés — `POST
/// certification/request`/`GET certification/{userId}`/`GET tiinver/tarification`, 366 lignes au
/// total, PAS lu en entier). **Soumission d'une NOUVELLE demande (upload de document justificatif,
/// `MultipartBody`/`addFormDataPart`) PAS portée** — même gap que le transfert de fichiers du
/// module 11/17 (`UploadFileOrDataService.java` toujours pas lu). Seule la CONSULTATION du statut
/// est implémentée.
@MainActor
final class CertificationRepository {
    static let shared = CertificationRepository()
    private init() {}

    func status(userId: String) async throws -> CertificationStatus? {
        let value = try await APIClient.shared.get("certification/\(userId)")
        guard value.isBackendSuccess, let data = value["certification"]?.rawData else { return nil }
        return try? JSONDecoder().decode(CertificationStatus.self, from: data)
    }
}
