import Foundation

/// Port de `Utils/CacheProvider.java` (`SimpleCache` ExoPlayer + `LeastRecentlyUsedCacheEvictor`).
///
/// AVFoundation n'a pas d'équivalent direct à `SimpleCache` (cache disque intégré au lecteur,
/// avec éviction LRU automatique) — `AVPlayer` s'appuie sur la mise en cache HTTP standard
/// (`URLCache`), non persistante entre lancements et non plafonnée par taille de la même façon.
/// Ce type reproduit le comportement observable (dossier de cache dédié, taille plafonnée à
/// `min(espace libre / 3, 1 Go)`, éviction du moins récemment utilisé) par un cache disque manuel
/// : téléchargement dans `Caches/media/`, horodatage de dernier accès dans les attributs du
/// fichier, éviction par le plus ancien quand la limite est dépassée.
final class VideoCacheManager {
    static let shared = VideoCacheManager()

    private let directory: URL
    private let maxBytes: Int64
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.tiinver.videocache", qos: .utility)

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("media", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Port de `Math.min(freeSpace / 3, 1_073_741_824)` (CacheProvider.java:23).
        let attributes = try? fileManager.attributesOfFileSystem(forPath: caches.path)
        let freeSpace = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        maxBytes = min(freeSpace / 3, 1024 * 1024 * 1024)
    }

    /// Chemin de cache local pour une URL distante — n'existe pas forcément encore sur disque.
    func localURL(for remoteURL: URL) -> URL {
        let key = remoteURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return directory.appendingPathComponent(key)
    }

    func isCached(_ remoteURL: URL) -> Bool {
        fileManager.fileExists(atPath: localURL(for: remoteURL).path)
    }

    /// Port de `ExoPlayerManager.preCachePrefix`/`submitPrecache` — télécharge en arrière-plan
    /// vers le cache disque, sans bloquer la lecture (équivalent `precacheExecutor`).
    func precache(_ remoteURL: URL) {
        queue.async { [weak self] in
            guard let self, !self.isCached(remoteURL) else { return }
            guard let data = try? Data(contentsOf: remoteURL) else { return } // best-effort, comme l'original (catch Exception silencieux)
            try? data.write(to: self.localURL(for: remoteURL))
            self.evictIfNeeded()
            self.touch(remoteURL)
        }
    }

    private func touch(_ remoteURL: URL) {
        let path = localURL(for: remoteURL)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
    }

    /// Port de `LeastRecentlyUsedCacheEvictor` : supprime les fichiers les plus anciens
    /// (par date de modification) jusqu'à repasser sous `maxBytes`.
    private func evictIfNeeded() {
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var entries = items.compactMap { url -> (url: URL, size: Int64, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let date = values.contentModificationDate else { return nil }
            return (url, Int64(size), date)
        }

        var totalSize = entries.reduce(0) { $0 + $1.size }
        guard totalSize > maxBytes else { return }

        entries.sort { $0.date < $1.date }
        for entry in entries {
            guard totalSize > maxBytes else { break }
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
        }
    }
}
