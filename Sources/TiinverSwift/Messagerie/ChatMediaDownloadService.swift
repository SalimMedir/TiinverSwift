import Foundation

/// Port du téléchargement de pièce jointe chat, factorisé pour être appelé par 2 déclencheurs
/// distincts — `ChatViewModel.requestDownload` (bulle visible) ET `ChatRepository.
/// resumePendingDownloads` (reconnexion socket, **V5-F-056, 2026-08-26, Phase B P3**) — comme
/// `ChatMediaUploadService` l'est déjà pour l'upload (`requestUpload`/`resumePendingUploads`,
/// V5-F-078). Réservation PARTAGÉE (`reserveDownload`/`releaseDownload`) pour éviter qu'un
/// téléchargement déclenché par réapparition de bulle ET par reconnexion socket courent
/// concurremment sur le même message — même motif et même raisonnement de sûreté que
/// `ChatMediaUploadService.reserveUpload` (les deux appelants sont `@MainActor`-isolés,
/// `ChatViewModel`/`ChatRepository`, réservation synchrone sans `await` interne).
final class ChatMediaDownloadService {
    static let shared = ChatMediaDownloadService()
    private init() {}

    private var downloadingMessageIds: Set<String> = []

    @discardableResult
    func reserveDownload(messageId: String) -> Bool {
        guard !downloadingMessageIds.contains(messageId) else { return false }
        downloadingMessageIds.insert(messageId)
        return true
    }

    func releaseDownload(messageId: String) {
        downloadingMessageIds.remove(messageId)
    }

    /// Port de `downloadFile`/`DownloadReceiver.getDownloadedFilePath` — logique extraite de
    /// `ChatViewModel.requestDownload` (V5-F-056) pour être réutilisable par
    /// `ChatRepository.resumePendingDownloads`. Stockage `.applicationSupportDirectory`
    /// (non-évictable, V5-F-079) — voir la doc de `ChatViewModel.requestDownload` pour la
    /// justification complète.
    func download(messageId: String, remoteURL: URL, messages: MessageRepository) async throws -> URL {
        var request = URLRequest(url: remoteURL)
        request.setValue("https://tiinver.com", forHTTPHeaderField: "Referer")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw URLError(.badServerResponse)
        }
        let mediaDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let ext = remoteURL.pathExtension.isEmpty ? "bin" : remoteURL.pathExtension
        let localURL = mediaDirectory.appendingPathComponent(messageId).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        try await messages.updateFileDownloaded(messageId: messageId, localURL: localURL)
        return localURL
    }
}
