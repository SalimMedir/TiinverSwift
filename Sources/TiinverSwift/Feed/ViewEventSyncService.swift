import Foundation

/// Port de `service/worker/ViewSyncWorker.java` (122 lignes, lu en entier) — la moitié "réseau" de
/// `Utils/ViewTracker.java`/`db/ViewEventDao.java`, jusqu'ici jamais portée côté iOS (voir tête de
/// `Storage/ViewEventRepository.swift`) : le stockage local cumulait déjà fidèlement watchtime/
/// scrollPosition/replayCount/exitPoint, mais rien ne les envoyait jamais au serveur.
///
/// **Ajouté (2026-08-28, V6-F-019)**. Android orchestre ce code via `WorkManager`
/// (`PeriodicWorkRequest` 15 min + `OneTimeWorkRequest` immédiat dès que `ViewEventDao.count() >=
/// SYNC_THRESHOLD`, voir `ViewTracker.startPeriodicSync`/`startImmediateSync`). Le pendant iOS
/// complet d'un job périodique en arrière-plan (`BGTaskScheduler`) est un chantier
/// d'infrastructure à part entière, DÉLIBÉRÉMENT hors périmètre ici — déjà déféré par V5-F-060.
/// Seuls les 2 déclencheurs "best effort" suivants sont câblés à la place :
///  1. Immédiat dès que `ViewEventRepository.record(...)` fait passer le nombre de lignes en
///     attente à `ViewEventRepository.syncThreshold` (5) — voir `FeedView.swift`
///     (`FeedDetailPagerView.recordView`), port de `startImmediateSync`.
///  2. Une tentative au retour au premier plan de l'app (`scenePhase == .active`, voir
///     `RootRouterView.swift`) — pour vider les lignes laissées par une session tuée avant tout
///     déclenchement du seuil (Android obtient cette couverture via son job périodique 15 min ;
///     ce déclencheur ponctuel est la meilleure approximation atteignable sans construire tout le
///     chantier `BGTaskScheduler`).
enum ViewEventSyncService {
    private static let sevenDaysMs: Int64 = 7 * 24 * 60 * 60 * 1000

    /// Port de `ViewSyncWorker.doWork()` : purge les vues de plus de 7 jours, puis envoie CHAQUE
    /// ligne en attente individuellement à `addview`, en s'arrêtant au TOUT PREMIER échec — les
    /// lignes restantes demeurent en attente pour la prochaine tentative, fidèle au `break`
    /// Android (`for (ViewEvent event : pending) { ... if (!success) break; }`) : pas de tentative
    /// "au mieux" sur les lignes suivantes une fois le serveur suspecté injoignable.
    static func sync() async {
        let repo = ViewEventRepository()

        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - sevenDaysMs
        try? await repo.deleteOlderThan(cutoffMillis: cutoff)

        guard let pending = try? await repo.pending(), !pending.isEmpty else { return }

        for event in pending {
            var params: [String: String] = [
                "userId": event.userId ?? "",
                "activityId": String(event.activityId),
                "watchtime": String(event.watchtime),
                "scrollPosition": String(event.scrollPosition),
                "replayCount": String(event.replayCount),
            ]
            // Port de `event.exitPoint >= 0 ? String.valueOf(event.exitPoint) : ""`
            // (`ViewSyncWorker.java:75-77`) — chaîne VIDE si non applicable, PAS "-1".
            params["exitPoint"] = event.exitPoint >= 0 ? String(event.exitPoint) : ""

            do {
                let value = try await APIClient.shared.post(params, endpoint: "addview")
                guard value.isBackendSuccess else { break } // Rejet applicatif — arrêt, comme Android.
                try await repo.delete(localId: event.localId)
            } catch {
                break // Échec transport (réseau, timeout...) — même arrêt de boucle qu'Android.
            }
        }
    }
}
