import AVFoundation

protocol VideoPlayerStateCallback: AnyObject {
    func onBuffering()
    func onRebuffering()
    func onReady()
    func onError()
    func onFirstFrameRendered()
}

/// Port de `Activity/service/ExoPlayerManager.java`.
///
/// Un seul `AVPlayer` partagé et réutilisé entre les cellules du feed (comme le `player` unique
/// d'ExoPlayerManager, jamais un lecteur par cellule) — évite le coût mémoire/CPU de N lecteurs
/// simultanés dans une liste défilante. Pas de portage direct de `DefaultPreloadManager`/
/// `MediaSourceCache` (spécifiques à Media3, sans équivalent AVFoundation) : le préchargement est
/// reproduit par un warm-up d'`AVURLAsset` (`loadValuesAsynchronously`) pour les items suivants,
/// et par `VideoCacheManager.precache` pour le cache disque — même intention (préparer les
/// prochaines vidéos avant qu'elles soient visibles), mécanisme natif différent.
@MainActor
final class VideoPlayerManager {
    static let shared = VideoPlayerManager()

    let player = AVPlayer()

    private var currentVideoURL: URL?
    private var currentFallbackURL: URL?
    private var isFallbackActive = false
    private var hasBeenReady = false

    private weak var stateCallback: VideoPlayerStateCallback?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?

    private let preloadAssets = NSCache<NSURL, AVURLAsset>()

    private init() {
        player.actionAtItemEnd = .none // REPEAT_MODE_ONE côté ExoPlayer — la boucle est gérée via l'observer de fin (voir loopIfNeeded)
    }

    /// **CAUSE RACINE RÉELLE confirmée le 2026-08-17 par test réel** : le CDN de streaming
    /// (`stream.tiinver.com`) exige un en-tête `Referer` — port fidèle de `ExoPlayerManager.
    /// initDataSources` (`headers.put("Referer", "https://stream.tiinver.com")`, valeur EXACTE
    /// reprise du fichier source Android). Aucun `AVURLAsset` de ce fichier ne passait cet
    /// en-tête (ni `User-Agent`) — chaque vidéo du Feed échouait à charger silencieusement, jamais
    /// de lecture possible malgré une session/réseau désormais fonctionnels.
    /// Visibilité `internal` + `nonisolated` (pas `private`) — **réutilisé depuis le 2026-08-19 par
    /// `VideoCacheManager.precache` (MIGRATION_PARITY_AUDIT_V3.md V3-F-010 FEED-02, Phase P1)**, qui
    /// souffrait EXACTEMENT de la même cause racine (`Data(contentsOf:)` sans `Referer` → 403
    /// probable → cache jamais rempli) — même en-têtes, même serveur, une seule source de vérité.
    /// `nonisolated` explicite : `VideoCacheManager` n'est PAS `@MainActor` (file d'attente dédiée),
    /// un simple `static let` hériterait sinon de l'isolation `@MainActor` de cette classe.
    nonisolated static let videoHTTPHeaders = ["User-Agent": "TiinverPlayer/1.0", "Referer": "https://stream.tiinver.com"]

    // **Correctif CI du 2026-08-17** : `AVURLAssetHTTPHeaderFieldsKey` n'est PAS exposée au
    // compilateur Swift (clé interne ObjC jamais déclarée côté Swift dans le SDK AVFoundation —
    // confirmé, échec "cannot find 'AVURLAssetHTTPHeaderFieldsKey' in scope" en CI) alors qu'elle
    // fonctionne bien à l'exécution une fois passée comme chaîne littérale identique — contournement
    // standard et documenté pour ce cas précis, pas une invention : on passe la même valeur de clé
    // sous forme de `String` brute plutôt que via le symbole manquant.
    private static let httpHeaderFieldsOptionKey = "AVURLAssetHTTPHeaderFieldsKey"

    private static func makeAsset(url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: [httpHeaderFieldsOptionKey: videoHTTPHeaders])
    }

    func setStateCallback(_ callback: VideoPlayerStateCallback?) {
        stateCallback = callback
    }

    /// Port de `ExoPlayerManager.playVideo` (branche SEEK + branche NORMAL).
    func playVideo(url: URL, nextURL: URL? = nil, fallbackURL: URL? = nil) {
        hasBeenReady = false

        if url == currentVideoURL {
            player.seek(to: .zero)
            player.play()
            return
        }

        currentFallbackURL = fallbackURL
        isFallbackActive = false
        currentVideoURL = url
        stateCallback?.onBuffering()

        let localURL = VideoCacheManager.shared.isCached(url) ? VideoCacheManager.shared.localURL(for: url) : url
        let asset = preloadAssets.object(forKey: url as NSURL) ?? Self.makeAsset(url: localURL)
        let item = AVPlayerItem(asset: asset)
        // Meilleur équivalent atteignable de `LoadControlUtils.createFastStartLoadControl`
        // (`minBufferForPlayback`/`maxBuffer` ExoPlayer) : AVFoundation n'expose pas de contrôle
        // de buffer aussi fin, seulement cette durée cible de buffer avant lecture.
        item.preferredForwardBufferDuration = 2

        observe(item)
        player.replaceCurrentItem(with: item)
        player.play()

        if let nextURL {
            preload(nextURL)
        }
    }

    /// Port de `ExoPlayerManager.smartPreload`/`submitPreload` — warm-up réseau d'un `AVURLAsset`
    /// pour l'item suivant, sans le jouer. Port de `cacheVideos`/`submitPrecache` pour le cache
    /// disque (best-effort, silencieux, comme l'original). Appelé en fenêtre `currentIndex ± 2`
    /// par `FeedView.preloadAround` — équivalent de `PreloadScheduler.getIndicesToPreload`
    /// (windowSize par défaut 2), PAS des états de préchargement étagés de
    /// `MyTargetPreloadStatusControl`/`DefaultPreloadManager` (`SOURCE_PREPARED`/
    /// `TRACKS_SELECTED`/`specifiedRangeLoaded`, spécifiques à l'architecture interne de Media3,
    /// sans équivalent public dans AVFoundation) : chaque URL de la fenêtre reçoit ici le même
    /// traitement, sans granularité intermédiaire. `Preloader.java` (polling du buffer via
    /// `getBufferedPosition()` jusqu'à 4s) non plus reproduit : `AVPlayerItem` n'expose pas de
    /// lecteur de préchargement séparé de la même façon ; le warm-up `AVURLAsset` + le cache
    /// disque sont le meilleur équivalent atteignable sans réécrire une architecture propre à
    /// AVFoundation.
    func preload(_ url: URL) {
        guard preloadAssets.object(forKey: url as NSURL) == nil else { return }
        let asset = Self.makeAsset(url: url)
        preloadAssets.setObject(asset, forKey: url as NSURL)
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration"], completionHandler: nil)
        VideoCacheManager.shared.precache(url)
    }

    func pause() { player.pause() }
    func resume() { player.play() }

    /// Port de `ExoPlayerManager.detachCurrentView`.
    func detach() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentVideoURL = nil
        currentFallbackURL = nil
        isFallbackActive = false
        hasBeenReady = false
        removeObservers()
    }

    private func observe(_ item: AVPlayerItem) {
        removeObservers()

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleStatusChange(item)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.player.seek(to: .zero); self?.player.play() } // REPEAT_MODE_ONE
        }

        errorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackFailure() }
        }
    }

    private func handleStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            hasBeenReady = true
            stateCallback?.onReady()
            stateCallback?.onFirstFrameRendered()
        case .failed:
            handlePlaybackFailure()
        default:
            if !hasBeenReady {
                stateCallback?.onBuffering()
            } else {
                stateCallback?.onRebuffering()
            }
        }
    }

    /// Port de `mainPlayerListener.onPlayerError` — bascule vers `currentFallbackUrl` (MP4) si
    /// disponible et pas déjà tenté, sinon signale l'erreur au callback.
    private func handlePlaybackFailure() {
        if let fallbackURL = currentFallbackURL, !isFallbackActive {
            isFallbackActive = true
            hasBeenReady = false
            stateCallback?.onBuffering()
            let item = AVPlayerItem(asset: Self.makeAsset(url: fallbackURL))
            observe(item)
            player.replaceCurrentItem(with: item)
            player.play()
        } else {
            stateCallback?.onError()
        }
    }

    private func removeObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
        endObserver = nil
        errorObserver = nil
    }

    /// Port de `ExoPlayerManager.release()`.
    func release() {
        detach()
        preloadAssets.removeAllObjects()
    }
}
