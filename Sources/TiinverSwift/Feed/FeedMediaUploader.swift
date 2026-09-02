import Foundation

/// **Port de `Activity/service/ActivityService.java` (lu en entier, 2026-08-17, `MIGRATION_PARITY_
/// AUDIT_V2.md` P0-1)** — CAUSE RACINE RÉELLE de la publication Feed jamais fonctionnelle : le
/// flux précédent (`FeedRepository.publish`) envoyait le fichier média DIRECTEMENT en multipart à
/// `activity/add`. Ce n'est PAS ce que fait le vrai client Android, confirmé en traçant l'entrée
/// réelle `ActivityService.onStartCommand` (démarré par `MainFragment`/`FeedFragment` via
/// `ACTION_UPLOAD`, PAS `HttpFileUploader` — ce dernier n'est référencé dans ce fichier que pour
/// `cancel(true)`, jamais pour effectuer un upload ; l'ancien commentaire de `FeedRepository.swift`
/// citant `HttpFileUploader.uploadRequestBody` pour ce cas précis était erroné, probablement une
/// confusion avec le flux DISTINCT d'upload de photo de profil) :
///
/// 1. Le fichier média est uploadé DIRECTEMENT vers BunnyCDN (JAMAIS vers le backend Tiinver) :
///    - **Photo** (`uploadImageToBunny`) : `PUT https://storage.bunnycdn.com/tiinver-media/
///      tiinver/photos/{token}.webp`, en-tête `AccessKey` (clé de STOCKAGE, MÊME zone/clé que
///      `ChatMediaUploadService` — confirmé identique par comparaison directe des deux fichiers
///      source Android). `Content-Type: application/octet-stream`.
///    - **Vidéo** (`uploadVideoToCdn`→`getCdnVideoId`+`uploadFileToBunny`) : DEUX appels vers la
///      Video Library BunnyCDN (PAS le Storage — clé `AccessKey` DIFFÉRENTE, `bunnyApiKey`,
///      jamais utilisée ailleurs dans le projet iOS avant ce fichier) : (a) `POST https://
///      video.bunnycdn.com/library/471609/videos` avec `{"title": token}` → réponse `{"guid":...}`
///      ; (b) `PUT https://video.bunnycdn.com/library/471609/videos/{guid}` = octets bruts, SANS
///      `Content-Type` explicite (vérifié : Android passe `null` comme `MediaType` pour cette PUT
///      précise, contrairement à la branche photo).
/// 2. SEULEMENT ENSUITE, `POST activity/add` avec les métadonnées en PARAMÈTRES TEXTE — JAMAIS de
///    fichier binaire envoyé à cet endpoint (voir `FeedRepository.publish`, qui consomme ce type).
enum FeedMediaUploader {
    /// Clé de STOCKAGE — MÊME valeur que `ChatMediaUploadService.storageAPIKey`, dupliquée dans ces
    /// deux fichiers : Android lui-même duplique ces littéraux dans 3 fichiers source distincts
    /// (`ActivityService.java`/`UploadFileOrDataService.java`/`ProfileService.java`). **Accès
    /// interne (pas `private`)** : `ProfileRepository.uploadProfilePicture` (V4-F-008, port de
    /// `ProfileService.java`, le 3ᵉ fichier Android ci-dessus) RÉUTILISE ces constantes plutôt que
    /// de les redupliquer une 3ᵉ fois — écart délibéré par rapport à la triplication Android, pour
    /// éviter une occurrence supplémentaire en clair de la clé d'accès dans le dépôt, sans changer
    /// le comportement réseau (même zone, même clé, même hôte).
    static let storageZone = "tiinver-media"
    static let storageAPIKey = "75ef8922-9f01-40d9-a71c66e21a22-a056-4615"
    static let storageBaseURL = "https://storage.bunnycdn.com"

    /// Clé de la VIDEO LIBRARY — DISTINCTE de la clé de stockage ci-dessus (vérifié dans
    /// `ActivityService.java:54-55` : `bunnyApiKey` ≠ `storageApiKey`), absente de tout le projet
    /// iOS avant ce fichier (`grep "video.bunnycdn\|471609"` = 0 résultat avant ce correctif).
    private static let videoLibraryId = "471609"
    private static let videoLibraryAPIKey = "5ae72e8e-638f-4cd6-9fcb433e9ab6-e49b-463e"
    private static let videoLibraryBaseURL = "https://video.bunnycdn.com/library"

    enum UploadError: Error { case httpFailure(Int), missingGuid }

    struct PhotoResult { var cdnContentId: String; var cdnContentUrl: String }
    struct VideoResult { var cdnContentId: String; var cdnContentUrl: String; var cdnThumbnailUrl: String }

    /// Port de `uploadImageToBunny` — `cdn_content_url` retourné est un CHEMIN RELATIF
    /// (`"tiinver/photos/{token}.webp"`), PAS une URL absolue : c'est EXACTEMENT la chaîne que
    /// `sendMetaDate` envoie telle quelle à `activity/add` côté Android (`data.getCdn_content_url()`
    /// sans transformation). Le CDN de lecture (`cdn.tiinver.com`, voir `CDNAsyncImage`) est un
    /// domaine SÉPARÉ dont la relation exacte avec ce chemin relatif est gérée côté BACKEND (déjà
    /// confirmé fonctionnel pour LIRE les posts existants via `object_url` absolu en retour de
    /// `feedtimeline` — la normalisation relative→absolue est donc une responsabilité serveur, pas
    /// cliente, reproduite fidèlement en envoyant le même chemin relatif qu'Android).
    /// **Corrigé le 2026-09-02 (MIGRATION_PARITY_AUDIT_V9.md V9-F-024)** — `progress` optionnel
    /// ajouté, réutilisant `UploadProgressDelegate` (déjà porté pour `uploadVideo` ci-dessous) —
    /// Android fournit bien un callback de progression pour CETTE PUT aussi
    /// (`ProgressRequestBodyUri` enveloppe la PUT storage/photo ET la PUT vidéo, confirmé par
    /// lecture directe d'`ActivityService.java`, même mécanisme des deux côtés). Optionnel et
    /// par défaut `nil` pour ne pas casser les appelants existants — impact mineur en pratique
    /// (upload photo généralement court), mais fidélité complète à moindre coût.
    static func uploadPhoto(token: String, jpegData: Data, progress: (@Sendable (Double) -> Void)? = nil) async throws -> PhotoResult {
        let folder = "tiinver/photos"
        let filename = "\(token).webp"
        let remoteURL = URL(string: "\(storageBaseURL)/\(storageZone)/\(folder)/\(filename)")!
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PUT"
        request.setValue(storageAPIKey, forHTTPHeaderField: "AccessKey")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let delegate = progress.map { UploadProgressDelegate(onProgress: $0) }
        let (_, response) = try await URLSession.shared.upload(for: request, from: jpegData, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.httpFailure((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let relativePath = "\(folder)/\(filename)"
        return PhotoResult(cdnContentId: token, cdnContentUrl: relativePath)
    }

    /// Port de `getCdnVideoId`+`uploadFileToBunny` — DEUX appels réseau distincts vers la Video
    /// Library BunnyCDN, dans cet ordre : créer l'entrée (obtenir `guid`), PUIS uploader les octets.
    ///
    /// **Corrigé (V3-F-019, BUNNY-03)** — `ProgressRequestBodyUri.java` (`writeTo`, 8192 octets par
    /// bloc, `InputStream` sur `Uri.parse(data.getFileUri())`) streame la vidéo DIRECTEMENT depuis
    /// le fichier, jamais chargée intégralement en mémoire, et calcule une vraie progression
    /// (`uploaded*100/contentLength`, `callback.onProgress(...)`). L'ancienne version de cette
    /// fonction prenait un paramètre `Data` — l'appelant (`PublishComposeView`) avait DÉJÀ dû
    /// charger toute la vidéo via `Data(contentsOf:)` avant même d'appeler cette fonction, risque
    /// réel d'OOM sur une vidéo volumineuse. Prend maintenant directement l'URL du fichier et
    /// utilise `URLSession.upload(for:fromFile:delegate:)`, qui streame depuis le disque sans
    /// jamais matérialiser le fichier entier en `Data` ; `progress` (optionnel) reçoit une
    /// fraction 0...1 au fil de l'envoi via `UploadProgressDelegate`, port fidèle du callback
    /// `onProgress(percentage)` Android.
    static func uploadVideo(token: String, fileURL: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> VideoResult {
        let guid = try await createVideoLibraryEntry(title: token)

        let remoteURL = URL(string: "\(videoLibraryBaseURL)/\(videoLibraryId)/videos/\(guid)")!
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PUT"
        request.setValue(videoLibraryAPIKey, forHTTPHeaderField: "AccessKey")
        // PAS de Content-Type ici — fidèle à `uploadFileToBunny` (`MediaType` passé à `null` côté
        // Android pour cette PUT précise, contrairement à la branche photo).
        // Corrigé (V3-F-021, BUNNY-05) : `ActivityService.java:287-292` ajoute `addHeader("accept",
        // "application/json")` sur CETTE PUT précise (absent de la PUT photo/storage, ligne 403-407,
        // volontairement pas ajouté là) — manquait côté iOS.
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let delegate = progress.map { UploadProgressDelegate(onProgress: $0) }
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.httpFailure((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        // Port de `cdn_content_url = videoId + "/playlist.m3u8"` / `thumbnailUrl = videoId +
        // "/thumbnail.jpg"` — construits CÔTÉ CLIENT, pas retournés par l'API BunnyCDN.
        return VideoResult(
            cdnContentId: guid,
            cdnContentUrl: "\(guid)/playlist.m3u8",
            cdnThumbnailUrl: "\(guid)/thumbnail.jpg"
        )
    }

    /// Port de `getCdnVideoId` — `POST .../videos` avec `{"title": token}`, réponse `{"guid": ...}`.
    private static func createVideoLibraryEntry(title: String) async throws -> String {
        let remoteURL = URL(string: "\(videoLibraryBaseURL)/\(videoLibraryId)/videos")!
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "POST"
        request.setValue(videoLibraryAPIKey, forHTTPHeaderField: "AccessKey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.httpFailure((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let guid = json["guid"] as? String
        else {
            throw UploadError.missingGuid
        }
        return guid
    }
}

/// Port de `ProgressRequestBodyUri.UploadCallback`/`writeTo` (calcul `uploaded*100/contentLength`
/// à chaque bloc de 8192o écrit) — ici, `URLSessionTaskDelegate` fournit directement
/// `totalBytesSent`/`totalBytesExpectedToSend` sans avoir besoin de gérer le découpage par bloc
/// soi-même (`URLSession.upload(for:fromFile:)` s'en charge en interne). Fraction 0...1 plutôt que
/// 0...100 — conversion laissée à l'appelant UI, cohérent avec `ProgressView(value:)` SwiftUI natif.
/// Accès interne (pas `private`) — réutilisée par `ChatMediaUploadService` (V4-F-064, même besoin
/// de streaming progressif depuis le disque pour une pièce jointe chat), même motif que le
/// partage des constantes de stockage BunnyCDN entre `FeedMediaUploader`/`ProfileRepository`
/// (V4-F-008).
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
