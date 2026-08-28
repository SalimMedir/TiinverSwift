import Foundation

/// Port de `Utils/WatchTimeTracker.java` (110 lignes, lu en entier) — machine à état PAR SESSION
/// de visionnage (temps cumulé, position de sortie maximale atteinte, nombre de replays), dont le
/// `Snapshot` produit à la fermeture/au changement d'item alimente `ViewEventRepository.
/// record(...)` (couche de stockage local, déjà portée séparément, module Storage).
///
/// **Ajouté (2026-08-28, V6-F-019)** — jusqu'ici jamais porté : rien côté iOS n'appelait
/// `ViewEventRepository.record(...)`, donc AUCUNE activité de visionnage vidéo/photo n'était
/// jamais transmise au serveur — sous-comptant silencieusement `total_watch_time`/
/// `avg_watch_time`/`completion_rate`/`view_rate_3sec` de chaque créateur pour toute vue
/// d'origine iOS. Voir `ViewEventSyncService.swift` (partie réseau, port de `ViewSyncWorker.java`)
/// et le câblage dans `FeedView.swift` (`FeedDetailPagerView`).
///
/// `SystemClock.elapsedRealtime()` (Android, horloge MONOTONE insensible aux ajustements
/// d'horloge murale) est reproduit ici par `DispatchTime.now()` (bâtie sur `mach_absolute_time`,
/// également monotone) — surtout PAS `Date()`/`Date().timeIntervalSince1970` : un saut d'horloge
/// murale (ajustement NTP, changement de fuseau/heure d'été) fausserait directement le calcul
/// `accumulatedWatchTimeMs += (now - sessionStartTimeMs)`, exactement le piège que le choix
/// d'horloge d'Android évite délibérément ici.
final class WatchTimeTracker {
    /// Port de `WatchTimeTracker.Snapshot` — types alignés EXACTEMENT sur les paramètres de
    /// `ViewEventRepository.record(watchtime:scrollPosition:replayCount:exitPoint:)` pour que les
    /// appelants n'aient aucun cast à faire.
    struct Snapshot {
        let watchTimeSec: Int64
        let scrollPosition: Int32
        let replayCount: Int32
        let exitPoint: Int32
    }

    private var accumulatedWatchTimeMs: Int64 = 0
    private var sessionStartTimeMs: Int64 = 0
    private var isTracking = false

    /// -1 = non défini (aucune position vidéo connue pour la session en cours).
    private var exitPointSec: Int32 = -1
    private var videoDuration: Int32 = 0

    /// Équivalent monotone de `SystemClock.elapsedRealtime()` — voir doc de tête de fichier.
    private static func nowMs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    /// Port de `resumeTracking()` — no-op si déjà en cours (empêche un double comptage sur un
    /// second appel sans pause intermédiaire, ex. deux callbacks `isPlaying=true` consécutifs).
    func resumeTracking() {
        guard !isTracking else { return }
        sessionStartTimeMs = Self.nowMs()
        isTracking = true
    }

    /// Port de `pauseTracking()` — no-op si pas en cours. C'est cet appariement strict
    /// resume/pause qui garantit que le temps ne s'accumule JAMAIS pendant une pause, un
    /// passage en arrière-plan, ou un seek — seulement entre un `resumeTracking()` et le
    /// `pauseTracking()` suivant.
    func pauseTracking() {
        guard isTracking else { return }
        accumulatedWatchTimeMs += (Self.nowMs() - sessionStartTimeMs)
        isTracking = false
    }

    /// Port de `flushSnapshotAndReset(boolean isPhoto)` — pause d'abord (capture la session en
    /// cours si active), calcule les 4 valeurs comportementales à partir de l'état ACCUMULÉ,
    /// PUIS réinitialise tout l'état interne.
    func flushSnapshotAndReset(isPhoto: Bool) -> Snapshot {
        pauseTracking()

        let watchTimeSec = accumulatedWatchTimeMs / 1000

        // Ex. : 35s regardées sur une vidéo de 10s = 3 replays (35/10 - 1 = 2).
        var replay: Int32 = 0
        if !isPhoto, videoDuration > 0, watchTimeSec > Int64(videoDuration) {
            replay = Int32(watchTimeSec / Int64(videoDuration)) - 1
            if replay < 0 { replay = 0 }
        }

        let scroll = scrollPosition(isPhoto: isPhoto)
        let exit = exitPoint(isPhoto: isPhoto)

        resetAll()

        return Snapshot(watchTimeSec: watchTimeSec, scrollPosition: scroll, replayCount: replay, exitPoint: exit)
    }

    /// Port de `setExitPoint(long positionMs)` — appelé quand la position du lecteur est connue
    /// (à la pause/à la sortie) ; ne fait QUE monter, jamais redescendre (fidèle à Android : un
    /// seek arrière ne doit pas faire "reculer" la position de sortie déjà atteinte).
    func setExitPoint(positionMs: Int64) {
        let positionSec = Int32(positionMs / 1000)
        if positionSec > exitPointSec {
            exitPointSec = positionSec
        }
    }

    /// Port de `setVideoDuration(long durationMs)` — appelé une fois la durée de la vidéo connue.
    func setVideoDuration(durationMs: Int64) {
        guard durationMs > 0 else { return }
        videoDuration = Int32(durationMs / 1000)
    }

    /// Port de `getScrollPosition(boolean isPhoto)` — pourcentage 0-100.
    private func scrollPosition(isPhoto: Bool) -> Int32 {
        if isPhoto { return 100 }
        guard videoDuration > 0, exitPointSec >= 0 else { return 0 }
        return min(100, Int32((Float(exitPointSec) * 100.0) / Float(videoDuration)))
    }

    /// Port de `getExitPoint(boolean isPhoto)` — seconde de sortie, -1 si photo ou non défini.
    private func exitPoint(isPhoto: Bool) -> Int32 {
        isPhoto ? -1 : exitPointSec
    }

    /// Port de `resetAll()`.
    private func resetAll() {
        accumulatedWatchTimeMs = 0
        sessionStartTimeMs = 0
        isTracking = false
        exitPointSec = -1
        videoDuration = 0
    }
}
