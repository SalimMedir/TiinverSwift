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
    private let queue = DispatchQueue(label: "com.tiinver.videocache", qos: .utility, attributes: .concurrent)
    /// Port de `precacheExecutor = Executors.newFixedThreadPool(2)` (`ExoPlayerManager.java:87`)
    /// — **ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-055, Phase B P2)**. La `queue`
    /// ci-dessus était auparavant SÉRIELLE (1 seul précache à la fois) : un seul téléchargement
    /// lent retardait la mise en cache de TOUTES les vidéos suivantes de la fenêtre `currentIndex
    /// ±2`, alors qu'Android peut continuer sur son second thread. `queue` rendue `.concurrent`,
    /// ce sémaphore plafonne à 2 précaches simultanés (fidèle au pool à 2 threads), pas à un
    /// nombre illimité.
    private let concurrencyLimiter = DispatchSemaphore(value: 2)

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
    ///
    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-010 FEED-02, Phase B P1)** —
    /// `Data(contentsOf: remoteURL)` n'envoie AUCUN en-tête HTTP ; le CDN de streaming
    /// (`stream.tiinver.com`) exige `Referer`, cause racine déjà confirmée par test réel pour la
    /// lecture elle-même (voir `VideoPlayerManager.videoHTTPHeaders`, `ExoPlayerManager.
    /// initDataSources` côté Android) — le préchargement disque souffrait du même 403 probable,
    /// donc ne remplissait jamais réellement le cache malgré l'absence d'erreur visible (`try?`
    /// avalait silencieusement l'échec). Bascule vers `URLSession` + `URLRequest` portant les
    /// MÊMES en-têtes que la lecture réelle, une seule source de vérité
    /// (`VideoPlayerManager.videoHTTPHeaders`).
    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-058, Phase B P1-24)** — port du
    /// streaming disque `CacheWriter`/`SimpleCache` (`CacheWorker.java:66-69,231-234`, écrit en
    /// flux par blocs bornés). Utilisait `URLSession.shared.dataTask`, dont le callback reçoit la
    /// vidéo ENTIÈRE déjà bufférisée en mémoire comme `Data` avant l'écriture disque — appelé
    /// automatiquement pour chaque vidéo de la fenêtre `currentIndex±2` PENDANT le défilement du
    /// Feed (voir `VideoPlayerManager.preload`), un scénario d'usage normal, pas un cas limite.
    /// `downloadTask` écrit directement sur disque par blocs bornés, fidèle au streaming Android.
    ///
    /// **Revu le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-055, Phase B P2)** — deux écarts
    /// identifiés contre `ExoPlayerManager.preCachePrefix(url, 2_000_000L)` : (1) file d'attente à
    /// 1 thread au lieu de 2 (`precacheExecutor`) — CORRIGÉ, voir `concurrencyLimiter` ci-dessus ;
    /// (2) téléchargement du fichier ENTIER au lieu d'un préfixe plafonné à 2 Mo —
    /// **DÉLIBÉRÉMENT NON reproduit, écart architectural documenté, PAS un oubli**.
    /// `preCachePrefix` n'est sûr côté Android QUE parce que la lecture réelle passe par le MÊME
    /// `CacheDataSource` ExoPlayer segmenté (octets en cache servis depuis le disque, le RESTE
    /// transparence basculé sur le réseau live, sans discontinuité) — vérifié directement
    /// `VideoPlayerManager.swift:87` : `isCached(url) ? localURL(for: url) : url` — côté iOS, un
    /// fichier "en cache" est chargé comme asset LOCAL COMPLET par `AVPlayerItem`, PAS via un
    /// data source segmenté équivalent. Plafonner ce téléchargement à 2 Mo produirait un fichier
    /// LOCAL TRONQUÉ qu'`isCached()` marquerait pourtant "en cache" — `VideoPlayerManager`
    /// tenterait alors de lire CE fichier tronqué comme la vidéo complète, provoquant un arrêt de
    /// lecture après ~quelques secondes pour CHAQUE vidéo précachée. Reproduire fidèlement le
    /// plafond 2 Mo introduirait donc une régression de lecture RÉELLE et PIRE que la
    /// surconsommation de données actuelle (qui, elle, produit toujours une lecture locale
    /// complète et fiable une fois le téléchargement terminé) — cf. politique du projet de ne pas
    /// porter un comportement Android qui ne fonctionnerait pas correctement dans l'architecture
    /// de cache iOS existante sans une refonte plus large (data source AVFoundation segmenté,
    /// hors périmètre d'un correctif P2 isolé).
    func precache(_ remoteURL: URL) {
        queue.async { [weak self] in
            guard let self, !self.isCached(remoteURL) else { return }
            self.concurrencyLimiter.wait()
            defer { self.concurrencyLimiter.signal() }
            var request = URLRequest(url: remoteURL)
            for (field, value) in VideoPlayerManager.videoHTTPHeaders {
                request.setValue(value, forHTTPHeaderField: field)
            }
            let semaphore = DispatchSemaphore(value: 0)
            let task = URLSession.shared.downloadTask(with: request) { tempURL, response, _ in
                defer { semaphore.signal() }
                guard let tempURL, let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
                let destination = self.localURL(for: remoteURL)
                try? self.fileManager.removeItem(at: destination) // même tolérance à l'écrasement que l'ancien `data.write(to:)`
                try? self.fileManager.moveItem(at: tempURL, to: destination)
            }
            task.resume()
            semaphore.wait() // Cette closure s'exécute déjà sur `queue` (utility, dédiée), pas le thread principal.
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
