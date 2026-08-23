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
    /// Clé de STOCKAGE — MÊME valeur que `ChatMediaUploadService.storageAPIKey`, dupliquée ici
    /// plutôt que partagée : Android lui-même duplique ces littéraux dans 3 fichiers source
    /// distincts (`ActivityService.java`/`UploadFileOrDataService.java`/`ProfileService.java`),
    /// donc cette duplication est FIDÈLE à l'original, pas une dette technique introduite ici.
    private static let storageZone = "tiinver-media"
    private static let storageAPIKey = "75ef8922-9f01-40d9-a71c66e21a22-a056-4615"
    private static let storageBaseURL = "https://storage.bunnycdn.com"

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
    static func uploadPhoto(token: String, jpegData: Data) async throws -> PhotoResult {
        let folder = "tiinver/photos"
        let filename = "\(token).webp"
        let remoteURL = URL(string: "\(storageBaseURL)/\(storageZone)/\(folder)/\(filename)")!
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PUT"
        request.setValue(storageAPIKey, forHTTPHeaderField: "AccessKey")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: jpegData)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.httpFailure((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let relativePath = "\(folder)/\(filename)"
        return PhotoResult(cdnContentId: token, cdnContentUrl: relativePath)
    }

    /// Port de `getCdnVideoId`+`uploadFileToBunny` — DEUX appels réseau distincts vers la Video
    /// Library BunnyCDN, dans cet ordre : créer l'entrée (obtenir `guid`), PUIS uploader les octets.
    static func uploadVideo(token: String, videoData: Data) async throws -> VideoResult {
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

        let (_, response) = try await URLSession.shared.upload(for: request, from: videoData)
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
