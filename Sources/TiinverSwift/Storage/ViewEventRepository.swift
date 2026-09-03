import CoreData

/// Port de `db/ViewEventDao.java` + de la logique cumulative de `Utils/ViewTracker.java` (partie
/// "écriture locale").
///
/// **Mise à jour (2026-08-28, V6-F-019)** — la synchronisation réseau (immédiate au seuil +
/// tentative au retour au premier plan) est désormais câblée, voir `ViewEventSyncService.swift`
/// (port de `ViewSyncWorker.java`) et son appel dans `FeedView.swift`/`RootRouterView.swift`. Seul
/// le job PÉRIODIQUE d'arrière-plan (`WorkManager`/`BGTaskScheduler`, 15 min) reste hors périmètre
/// (déjà déféré par V5-F-060, chantier d'infrastructure à part entière).
/// Sérialise les appels `record()` (2026-08-28, V7-F-017) — `findExisting` puis `update`/`insert`
/// sont 2 opérations Core Data SÉPARÉES, chacune sur son propre contexte d'arrière-plan (voir
/// `CoreDataRepository`) : sans cette file, deux `record()` concurrents pour le MÊME
/// `(activityId, userId)` (deux flushs rapprochés, ex. swipes rapides) pouvaient chacun lire "pas
/// de ligne existante"/une valeur périmée puis écrire indépendamment — incrément de watchtime
/// perdu, ou lignes dupliquées jamais fusionnées (aucune contrainte d'unicité applicative
/// n'existe). Port de l'exécuteur mono-thread dédié d'Android (`ViewTracker.dbExecutor =
/// Executors.newSingleThreadExecutor()`), qui sérialise déjà TOUS les appels `record()` côté Java.
/// Une simple isolation d'acteur NE suffirait PAS ici : Swift autorise la ré-entrance d'un acteur
/// entre deux `await` internes à une même méthode, donc un enchaînement explicite de `Task`
/// (chacune n'aboutissant qu'après la précédente ET son propre travail) est nécessaire pour une
/// vraie exclusion mutuelle bout en bout.
private actor RecordQueue {
    static let shared = RecordQueue()
    private var tail: Task<Int, Error> = Task { 0 }

    func run(_ operation: @escaping () async throws -> Int) async throws -> Int {
        let previousTail = tail
        let newTail = Task<Int, Error> {
            _ = try? await previousTail.value
            return try await operation()
        }
        tail = newTail
        return try await newTail.value
    }
}

/// **Ajouté (2026-09-03)** — crash `EXC_BAD_ACCESS`/`snapshot_get_int32` reproductible en scroll
/// rapide du feed, remonté par capture physique : `CoreDataRepository.query()` renvoie des
/// `NSManagedObject` (`ViewEventEntity`) vivants, liés au contexte d'arrière-plan PRIVÉ où ils ont
/// été fetchés (`context.perform { ... return try context.fetch(request) }`, `CoreDataRepository.
/// swift`), une fois SORTIS de ce `context.perform`. `ViewEventSyncService.sync()` (`@MainActor`)
/// lisait ensuite directement leurs propriétés (`event.scrollPosition`, etc.) sur l'acteur
/// principal — accès CROSS-THREAD interdit par Core Data (chaque `NSManagedObject` n'est sûr à lire
/// que sur la queue de SON PROPRE contexte), cause exacte de l'accès invalide rapporté. Un DTO valeur
/// pur, entièrement projeté DEPUIS l'intérieur du `context.perform` d'origine (`pending()`
/// ci-dessous), élimine cette fuite : plus aucune lecture de propriété Core Data ne se produit hors
/// de la queue qui possède l'objet.
struct PendingViewEvent {
    let localId: Int64
    let userId: String?
    let activityId: Int32
    let watchtime: Int64
    let scrollPosition: Int32
    let replayCount: Int32
    let exitPoint: Int32
}

final class ViewEventRepository {
    private let repo: CoreDataRepository<ViewEventEntity>
    private let stack: CoreDataContextProviding
    static let syncThreshold = 5 // ViewTracker.SYNC_THRESHOLD

    init(stack: CoreDataContextProviding = AnalyticsCoreDataStack.shared) {
        self.repo = CoreDataRepository(stack: stack)
        self.stack = stack
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

        // V7-F-017 : find-then-write sérialisé bout en bout, voir la doc de `RecordQueue`.
        return try await RecordQueue.shared.run { [repo] in
            if try await self.findExisting(activityId: activityId, userId: userId) != nil {
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
                    // **Corrigé (2026-08-28, V6-F-019)** — `localId` (équivalent du "_id"
                    // auto-incrémenté SQLite côté Android, voir le commentaire de tête de
                    // `TiinverModel.xcdatamodeld`) n'était JAMAIS assigné ici, restant à sa valeur
                    // par défaut (0) pour CHAQUE ligne : sans conséquence tant que rien n'appelait
                    // `delete(localId:)`, mais `ViewEventSyncService.sync()` (port de
                    // `ViewSyncWorker.java`) en dépend pour supprimer UNE SEULE ligne confirmée
                    // envoyée au serveur — avec `localId` toujours à 0, ce prédicat aurait supprimé
                    // TOUTES les lignes en attente dès le premier succès réseau, y compris celles
                    // pas encore envoyées. Tirage aléatoire 64 bits (collision pratiquement
                    // impossible sur le volume de lignes en attente avant purge à 7 jours) plutôt
                    // qu'un compteur — pas de source d'auto-incrément fiable disponible ici
                    // (plusieurs contextes d'arrière-plan concurrents).
                    row.localId = Int64.random(in: 1...Int64.max)
                }
            }
            return try await repo.count()
        }
    }

    /// Port de `ViewEventDao.getPending()`.
    ///
    /// Fetch direct (contourne `CoreDataRepository.query()`, qui renverrait des `ViewEventEntity`
    /// vivants hors de leur contexte d'origine — voir la doc de `PendingViewEvent` ci-dessus) : la
    /// projection en DTO se fait ICI, DANS le même `context.perform`, avant que quoi que ce soit ne
    /// quitte la queue du contexte qui possède réellement ces objets.
    func pending() async throws -> [PendingViewEvent] {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = ViewEventEntity.fetchRequest()
            let rows = try context.fetch(request)
            return rows.map { row in
                PendingViewEvent(
                    localId: row.localId, userId: row.userId, activityId: row.activityId,
                    watchtime: row.watchtime, scrollPosition: row.scrollPosition,
                    replayCount: row.replayCount, exitPoint: row.exitPoint
                )
            }
        }
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

    /// **Ajouté (2026-08-28, V7-F-023)** — purge ciblée pour `LocalDataPurger` (déconnexion/
    /// suppression de compte) : aucune méthode ne permettait jusqu'ici d'effacer les événements de
    /// visionnage en attente d'un utilisateur spécifique.
    func deleteAll(userId: String) async throws {
        try await repo.delete(predicate: NSPredicate(format: "userId == %@", userId))
    }

    /// Port de `ViewEventDao.count()`.
    func count() async throws -> Int {
        try await repo.count()
    }
}
