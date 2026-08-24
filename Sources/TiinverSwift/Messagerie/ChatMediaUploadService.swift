import Foundation

/// Port de `messagerie/service/UploadFileOrDataService.java` (lu en entier, GAP-004, 2026-08-15) —
/// pièces jointes chat (photo/vidéo/audio/doc). **Protocole ENTIÈREMENT différent** de
/// `APIClient.uploadMultipart` (profil/certification, backend Tiinver) : PUT binaire DIRECT vers
/// BunnyCDN storage, pas de multipart, pas de `Authorization: apiKey` (header `AccessKey` séparé,
/// clé statique dédiée au stockage). Voir `MIGRATION_AUDIT.md` GAP-004 pour la comparaison complète
/// des 3 protocoles d'upload du projet.
///
/// Clés/zone reprises À L'IDENTIQUE de `UploadFileOrDataService.java` (`STORAGE_ZONE`/
/// `STORAGE_API_KEY`, codées en dur côté Android — pas une régression introduite par le portage,
/// note sécurité déjà signalée dans `MIGRATION_AUDIT.md`). `bunnyApiKey`/`videoLibraryId` (Android)
/// confirmés jamais utilisés par aucune méthode appelée depuis `prapare()` — code mort, PAS repris.
final class ChatMediaUploadService {
    static let shared = ChatMediaUploadService()
    private init() {}

    private let storageZone = "tiinver-media"
    private let storageAPIKey = "75ef8922-9f01-40d9-a71c66e21a22-a056-4615"
    private let storageBaseURL = "https://storage.bunnycdn.com"
    private let cdnBaseURL = "https://cdn.tiinver.com"

    struct Result {
        var objectUrl: String
        var thumbnailUrl: String?
    }

    enum UploadError: Error { case httpFailure(Int) }

    /// Port de `prapare()`/`uploadMediaAndThumbnail()`/`uploadMediaToBunny()` — branche vidéo (2 PUT :
    /// média + thumbnail) vs branche générique (1 PUT), dispatch identique sur `object == "video"`.
    ///
    /// **2 bugs "double slash" trouvés en lisant Android, PAS reproduits** : (1)
    /// `uploadMediaToBunny` (branche non-vidéo) construit l'URL de PUT avec un `fileName` déjà
    /// préfixé d'un `/` PUIS concatène encore un `/` avant — `.../{folder}//{fileName}` ; (2)
    /// `uploadMediaAndThumbnail` (branche vidéo) construit l'URL CDN finale avec `cdn_base_url`
    /// (déjà terminé par `/`) PUIS un `/` supplémentaire — `.../tiinver.com//{folder}/...`. Les deux
    /// sont clairement accidentels (incohérents entre les 2 branches, pas un protocole voulu) —
    /// reconstruites ici PROPREMENT et UNIFORMÉMENT pour les 2 branches plutôt que de répliquer une
    /// incohérence involontaire.
    func upload(
        messageId: String, object: String, fileURL: URL, thumbnailFileURL: URL?,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Result {
        let kind = MessageMediaKind(object: object)
        let folder = "tiinver/message/\(object)"
        let mediaName = "\(messageId)\(kind.fileExtension)"
        let objectUrl = try await put(localFile: fileURL, folder: folder, filename: mediaName, mimeType: kind.mimeType, progress: progress)

        var thumbnailUrl: String?
        if kind == .video, let thumbnailFileURL {
            let thumbName = "\(messageId)_thumb.jpg"
            thumbnailUrl = try await put(localFile: thumbnailFileURL, folder: folder, filename: thumbName, mimeType: "image/jpeg")
        }
        return Result(objectUrl: objectUrl, thumbnailUrl: thumbnailUrl)
    }

    /// Port du corps commun de `uploadToBunny`/`uploadMediaToBunny` — PUT direct, header `AccessKey`,
    /// pas de multipart. Retourne l'URL CDN publique (`cdn_base_url + folder + filename`, PAS
    /// `storage.bunnycdn.com`, distincts côté Android — confirmé dans `uploadToBunny` vs
    /// `saveMediaUrls`).
    ///
    /// **Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-064, Phase B P1)** — chargeait tout
    /// le fichier en RAM via `Data(contentsOf:)` avant l'envoi, contrairement à Android
    /// (`ProgressRequestBodyUri.writeTo`, `UploadFileOrDataService.java:242-267`) qui streame
    /// TOUTE pièce jointe (photo/vidéo/audio/doc, un seul chemin `uploadToBunny` pour les 4 types)
    /// par blocs de 8Ko directement depuis le disque, avec progression réelle. Même anti-pattern déjà
    /// corrigé pour l'upload vidéo du Feed (`FeedMediaUploader.uploadVideo`, V3-F-019/BUNNY-03) —
    /// réutilise ici le même `UploadProgressDelegate` (rendu interne pour ce partage) plutôt que d'en
    /// dupliquer un second.
    private func put(
        localFile: URL, folder: String, filename: String, mimeType: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let remoteURL = URL(string: "\(storageBaseURL)/\(storageZone)/\(folder)/\(filename)")!
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PUT"
        request.setValue(storageAPIKey, forHTTPHeaderField: "AccessKey")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let delegate = progress.map { UploadProgressDelegate(onProgress: $0) }
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: localFile, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UploadError.httpFailure(status)
        }
        return "\(cdnBaseURL)/\(folder)/\(filename)"
    }
}

/// Port de `models/activity/MyMediaType.java` (4 constantes, lu en entier) — reproduit À
/// L'IDENTIQUE, y compris l'extension `.webp` pour les photos alors que le MIME type déclaré est
/// `image/jpeg` (incohérence RÉELLE mais DÉLIBÉRÉE côté Android : constante unique utilisée
/// PARTOUT, contrairement aux 2 bugs "double slash" ci-dessus qui divergent entre 2 fonctions —
/// donc gardée telle quelle, pas "corrigée").
enum MessageMediaKind: String {
    case audio, photo, video, doc

    init(object: String?) {
        self = MessageMediaKind(rawValue: object?.lowercased() ?? "") ?? .doc
    }

    var mimeType: String {
        switch self {
        case .audio: return "audio/3gpp"
        case .photo: return "image/jpeg"
        case .video: return "video/mp4"
        case .doc: return "application/octet-stream"
        }
    }

    var fileExtension: String {
        switch self {
        case .audio: return ".3gp"
        case .photo: return ".webp"
        case .video: return ".mp4"
        case .doc: return ".bin"
        }
    }
}
