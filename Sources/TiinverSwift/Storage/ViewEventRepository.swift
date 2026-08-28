import CoreData

/// Port de `db/ViewEventDao.java` + de la logique cumulative de `Utils/ViewTracker.java` (partie
/// "écriture locale").
///
/// **Mise à jour (2026-08-28, V6-F-019)** — la synchronisation réseau (immédiate au seuil +
/// tentative au retour au premier plan) est désormais câblée, voir `ViewEventSyncService.swift`
/// (port de `ViewSyncWorker.java`) et son appel dans `FeedView.swift`/`RootRouterView.swift`. Seul
/// le job PÉRIODIQUE d'arrière-plan (`WorkManager`/`BGTaskScheduler`, 15 min) reste hors périmètre
/// (déjà déféré par V5-F-060, chantier d'infrastructure à part entière).
final class ViewEventRepository {
    private let repo: CoreDataRepository<ViewEventEntity>
    static let syncThreshold = 5 // ViewTracker.SYNC_THRESHOLD

    init(stack: CoreDataContextProviding = AnalyticsCoreDataStack.shared) {
        self.repo = CoreDataRepository(stack: stack)
    }

    /// Port de `ViewEventDao.findExisting(activityId, userId)`.
    func findExisting(activityId: Int32, userId: String) async throws -> ViewEventEntity? {
        try await repo.first(predicate: NSPredicate(
            format: "activityId == %d AND userId == %@", activityId, userId
        ))
    }

    /// Port de `ViewTracker.record(...)` (partie stockage local seulement) : cumule le watchtime,
    /// garde le maximum de `scrollPosition`/`exitPoint`, additionne `replayCount` — à l'identique
    /// de la logique Java. Retourne le nombre total de lignes en attente après écriture, pour que
    /// l'appelant décide de déclencher une synchronisation immédiate au-delà de `syncThreshold`
    /// (équivalent de `ViewTracker.startImmediateSync`, laissé à la couche appelante).
    @discardableResult
    func record(
        userId: String,
        activityId: Int32,
        watchtime: Int64,
        scrollPosition: Int32 = 0,
        replayCount: Int32 = 0,
        exitPoint: Int32 = -1
    ) async throws -> Int {
        guard watchtime >= 1 else { return try await repo.count() }

        if let existing = try await findExisting(activityId: activityId, userId: userId) {
            try await repo.update(predicate: NSPredicate(
                format: "activityId == %d AND userId == %@", activityId, userId
            )) { row in
                row.watchtime += watchtime
                if scrollPosition > row.scrollPosition {
                    row.scrollPosition = scrollPosition
                }
                row.replayCount += replayCount
                if exitPoint >= 0 && (row.exitPoint < 0 || exitPoint > row.exitPoint) {
                    row.exitPoint = exitPoint
                }
            }
        } else {
            try await repo.insert { row in
                row.userId = userId
                row.activityId = activityId
                row.watchtime = watchtime
                row.scrollPosition = scrollPosition
                row.replayCount = replayCount
                row.exitPoint = exitPoint
                row.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
                // **Corrigé (2026-08-28, V6-F-019)** — `localId` (équivalent du "_id" auto-incrémenté
                // SQLite côté Android, voir le commentaire de tête de `TiinverModel.xcdatamodeld`)
                // n'était JAMAIS assigné ici, restant à sa valeur par défaut (0) pour CHAQUE ligne :
                // sans conséquence tant que rien n'appelait `delete(localId:)`, mais
                // `ViewEventSyncService.sync()` (nouveau, port de `ViewSyncWorker.java`) en dépend
                // pour supprimer UNE SEULE ligne confirmée envoyée au serveur — avec `localId`
                // toujours à 0, ce prédicat aurait supprimé TOUTES les lignes en attente dès le
                // premier succès réseau, y compris celles pas encore envoyées. Tirage aléatoire
                // 64 bits (collision pratiquement impossible sur le volume de lignes en attente
                // avant purge à 7 jours) plutôt qu'un compteur — pas de source d'auto-incrément
                // fiable disponible ici (plusieurs contextes d'arrière-plan concurrents).
                row.localId = Int64.random(in: 1...Int64.max)
            }
        }

        return try await repo.count()
    }

    /// Port de `ViewEventDao.getPending()`.
    func pending() async throws -> [ViewEventEntity] {
        try await repo.query()
    }

    /// Port de `ViewEventDao.deleteById(id)` — utilisé par `ViewSyncWorker` une fois la vue
    /// confirmée envoyée au serveur.
    func delete(localId: Int64) async throws {
        try await repo.delete(predicate: NSPredicate(format: "localId == %lld", localId))
    }

    /// Port de `ViewEventDao.deleteOlderThan(cutoff)` — `ViewSyncWorker` purge les vues de plus
    /// de 7 jours avant chaque synchronisation.
    func deleteOlderThan(cutoffMillis: Int64) async throws {
        try await repo.delete(predicate: NSPredicate(format: "createdAt < %lld", cutoffMillis))
    }

    /// Port de `ViewEventDao.count()`.
    func count() async throws -> Int {
        try await repo.count()
    }
}
