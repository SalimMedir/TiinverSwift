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

/// Port de `ui/certification/CertificationRepository.java` (366 lignes, lu en entier le
/// 2026-08-15, GAP-004) : `POST certification/request` (soumission), `GET certification/{userId}`
/// (statut), `GET tiinver/tarification` (coût du palier "basic", pas porté ici — affiché par un
/// écran Android séparé, `CertificationPlanFragment`, hors périmètre de GAP-004 qui couvre
/// spécifiquement le transfert de fichier).
@MainActor
final class CertificationRepository {
    static let shared = CertificationRepository()
    private init() {}

    func status(userId: String) async throws -> CertificationStatus? {
        let value = try await APIClient.shared.get("certification/\(userId)")
        guard value.isBackendSuccess, let data = value["certification"]?.rawData else { return nil }
        return try? JSONDecoder().decode(CertificationStatus.self, from: data)
    }

    /// Port de `CertificationRepository.requestOK` (Android, lu en entier) — POST multipart DIRECT
    /// vers le backend Tiinver (`{SERVER}certification/request`, PAS BunnyCDN — voir
    /// `MIGRATION_AUDIT.md` GAP-004 pour la distinction avec les pièces jointes chat), même protocole que
    /// `ProfileRepository.uploadProfilePicture` (`APIClient.uploadMultipart`, déjà ajouté).
    /// Champs fidèles à `requestOK` : `userId`, `certificationLevel` (Android l'appelle
    /// TOUJOURS avec `"basic"` en dur depuis `CertificationRequestActivity.btnSubmitCertification`
    /// — aucun autre palier n'est jamais réellement envoyé malgré le paramètre générique, reproduit
    /// à l'identique plutôt qu'une sélection de palier non demandée par ce GAP), `format`="json".
    /// **Écart assumé sur le fichier** : Android nomme le fichier `{unixTime}.webp` mais l'envoie
    /// avec `MediaType.parse(documentUrl)` — `documentUrl` est un chemin/URI, PAS une chaîne MIME
    /// valide, donc ce `MediaType` est `null` en pratique (bug Android confirmé par lecture, pas une
    /// convention volontaire) ; ici le document est ré-encodé en JPEG avec un vrai `image/jpeg`,
    /// même stratégie que `ProfileRepository.uploadProfilePicture`.
    func submit(userId: String, documentData: Data) async throws {
        let unixTime = Int(Date().timeIntervalSince1970)
        let value = try await APIClient.shared.uploadMultipart(
            endpoint: "certification/request",
            fields: ["userId": userId, "certificationLevel": "basic", "format": "json"],
            fileFieldName: "documentUrl",
            filename: "\(unixTime).jpg",
            mimeType: "image/jpeg",
            fileData: documentData
        )
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "certification/request")
        }
    }
}
