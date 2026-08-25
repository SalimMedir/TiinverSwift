import Foundation
import Photos

/// Port de `ProfileFeedFragment.addingDownloadingFileToQueue`/`checkBestQualityAndDownload`/
/// `extractVideoId`/`downloadFile` (`uploadPerfilPhoto/ProfileFeedFragment.java:769-849`).
///
/// **Corrigé (V5-F-006, 2026-08-24)** — le commentaire précédent affirmait que Profile était "le
/// SEUL contexte Android où Télécharger est réellement câblé", sur la base de la vérification de 3
/// menus "..." (`MainFragment.OnclickMoreExpand:1260-1367` ; `FullScreenMedia.
/// OnclickMoreExpand:485-494` ; `HashtagProfile.OnclickMoreExpand:637-646` — aucun des 3 ne liste
/// `R.id.download`) — analyse INCOMPLÈTE : un 4ᵉ menu existe, `FeedFragment.OnclickMoreExpand`
/// (`Activity/ui/FeedFragment.java:1246-1247,1360-1365`), la classe RÉELLE du plein écran atteint
/// depuis la grille Home (pas `MainFragment`), qui liste bien `R.id.download`, masqué uniquement
/// sur les posts PROPRES via `idContentHide`. Reproduit maintenant pour `ProfileView` ET
/// `FeedView` (grille Home) via `FeedDetailPagerView(includesDownload: true)` dans les deux cas.
enum FeedMediaDownloader {
    enum DownloadError: LocalizedError {
        case photoLibraryDenied
        case noSourceURL
        case networkFailure

        var errorDescription: String? {
            switch self {
            case .photoLibraryDenied: return "Accès à vos photos refusé. Autorisez-le dans Réglages pour télécharger."
            case .noSourceURL: return "Fichier introuvable."
            case .networkFailure: return "Le téléchargement a échoué. Vérifiez votre connexion."
            }
        }
    }

    /// Port de `downloadFile` (`format` selon `model.getObject()` : `.webp` photo / `.mp4` vidéo,
    /// `Referer: https://tiinver.com` — MÊME valeur littérale qu'`urlExists`, ligne 839). Android
    /// enregistre dans le dossier public `Downloads` via `DownloadManager` ; `PHPhotoLibrary` est
    /// l'équivalent iOS le plus proche pour un média destiné à l'app Photos de l'utilisateur.
    static func download(_ post: FeedActivity) async throws {
        let status = await requestAddOnlyAuthorization()
        guard status == .authorized || status == .limited else { throw DownloadError.photoLibraryDenied }

        guard let sourceURL = await resolvedSourceURL(for: post) else { throw DownloadError.noSourceURL }

        var request = URLRequest(url: sourceURL)
        request.setValue("https://tiinver.com", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { throw DownloadError.networkFailure }

        let ext = post.isVideo ? "mp4" : "webp"
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try data.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        try await PHPhotoLibrary.shared().performChanges {
            if post.isVideo {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tmpURL)
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tmpURL)
            }
        }
    }

    /// PHOTO : `model.getObject_url()` (méthode de priorité, port = `FeedActivity.playbackURL`, MÊME
    /// champ que la lecture — voir `FeedActivity.swift`). VIDÉO : sonde de qualité ci-dessous.
    private static func resolvedSourceURL(for post: FeedActivity) async -> URL? {
        post.isVideo ? await bestVideoDownloadURL(for: post) : post.playbackURL
    }

    /// Port de `checkBestQualityAndDownload` — sonde 720p → 480p → 360p (`urlExists`, HEAD +
    /// `Referer: https://tiinver.com`), repli sur `cdn_content_url` BRUT si aucune des 3 qualités ne
    /// répond 200 (`if (chosen == null) chosen = model.getCdn_content_url();`).
    private static func bestVideoDownloadURL(for post: FeedActivity) async -> URL? {
        for candidate in videoQualityCandidates(for: post) {
            if await urlExists(candidate) { return candidate }
        }
        return post.cdn_content_url.flatMap { URL(string: $0) }
    }

    /// Port de `extractVideoId` (premier segment de chemin de `cdn_content_url`) +
    /// `infoContract.CDN_STREAM_BASE_URL_V1` (= `APIEnvironment.cdnStreamBaseURL`).
    private static func videoQualityCandidates(for post: FeedActivity) -> [URL] {
        guard let cdn = post.cdn_content_url, !cdn.isEmpty,
            let videoId = URLComponents(string: cdn)?.path.split(separator: "/").first, !videoId.isEmpty
        else { return [] }
        return ["720p", "480p", "360p"].compactMap {
            URL(string: "\(APIEnvironment.cdnStreamBaseURL)\(videoId)/play_\($0).mp4")
        }
    }

    /// Port de `VideoPlaybackCoordinator.urlExists` (`Activity/service/VideoPlaybackCoordinator.java:214-228`) —
    /// HEAD, timeout 3s, succès UNIQUEMENT sur 200 (pas toute la plage 2xx, fidèle à
    /// `responseCode == HTTP_OK`).
    private static func urlExists(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        request.setValue("https://tiinver.com", forHTTPHeaderField: "Referer")
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current != .notDetermined { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
}
