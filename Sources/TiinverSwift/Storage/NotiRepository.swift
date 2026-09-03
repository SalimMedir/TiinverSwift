import CoreData

/// **Ajouté (2026-09-03)** — DTO valeur, même raisonnement que `PendingViewEvent`
/// (`ViewEventRepository.swift`, voir sa doc pour le crash `EXC_BAD_ACCESS` de fond) : `getAll()`/
/// `getById(_:)` renvoyaient auparavant des `NotiEntity` (`NSManagedObject`) vivants, dont
/// `NotificationCenterViewModel`/`NotificationsListView` lisaient ensuite les propriétés bien après
/// le `context.perform` d'origine — accès cross-thread interdit par Core Data. Porte uniquement les
/// champs réellement consommés par ces deux appelants.
struct NotiItem {
    let id: Int32
    let activityId: Int32
    let userId: Int32
    let object: String?
    let objectUrl: String?
    let cdnContentId: String?
    let cdnThumbnailUrl: String?
    let cdnContentUrl: String?
    let verb: String?
    let payloadType: String?
    let commentText: String?
    let firstname: String?
    let lastname: String?
    let profile: String?
    let type: String?
    let isRead: Int32
    let systemNotificationShown: Bool
}

/// Port de `models/notification/NotiDao.java` (store `TiinverNotificationsModel`, voir
/// `NotiCoreDataStack.swift`).
final class NotiRepository {
    private let stack: CoreDataContextProviding
    private let repo: CoreDataRepository<NotiEntity>

    init(stack: CoreDataContextProviding = NotiCoreDataStack.shared) {
        self.stack = stack
        self.repo = CoreDataRepository(stack: stack)
    }

    /// Port de `NotiDao.insertAll` (`OnConflictStrategy.REPLACE` sur la clé primaire serveur
    /// `id`, PAS `localId`/`NSManagedObjectID`) : une ligne existante avec le même `id` serveur
    /// est mise à jour en place, sinon une nouvelle ligne est créée.
    func insertAll(_ notifications: [(id: Int32, configure: (NotiEntity) -> Void)]) async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            for entry in notifications {
                let request = NotiEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %d", entry.id)
                request.fetchLimit = 1
                let row = try context.fetch(request).first ?? NotiEntity(context: context)
                entry.configure(row)
            }
            if context.hasChanges { try context.save() }
        }
    }

    /// Port de `NotiDao.getByIds(ids)`.
    func getByIds(_ ids: [Int32]) async throws -> [NotiEntity] {
        // `[Int32]` ne se pont pas automatiquement en `NSArray`/`%@` dans un format `NSPredicate` —
        // conversion explicite en `NSNumber` pour un comportement fiable et vérifiable.
        let boxed = ids.map { NSNumber(value: $0) }
        return try await repo.query(predicate: NSPredicate(format: "id IN %@", boxed))
    }

    /// Port de `NotiDao.getAllLive()` — sans l'observation continue de `LiveData` (module UI pas
    /// encore atteint pour cet écran) : simple lecture triée par `stamp` décroissant.
    ///
    /// **Corrigé (2026-09-03)** — voir la doc de `NotiItem` ci-dessus : projection en DTO faite ICI,
    /// DANS le `context.perform` d'origine, avant que les objets ne quittent la queue du contexte
    /// qui les possède.
    func getAll() async throws -> [NotiItem] {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = NotiEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "stamp", ascending: false)]
            return try context.fetch(request).map(Self.toItem)
        }
    }

    /// Port de `NotiDao.getById(id)`.
    ///
    /// **Corrigé (2026-09-03)** — même correctif et même raisonnement que `getAll()` ci-dessus.
    func getById(_ id: Int32) async throws -> NotiItem? {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = NotiEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %d", id)
            request.fetchLimit = 1
            return try context.fetch(request).first.map(Self.toItem)
        }
    }

    private static func toItem(_ row: NotiEntity) -> NotiItem {
        NotiItem(
            id: row.id, activityId: row.activityId, userId: row.userId,
            object: row.object, objectUrl: row.objectUrl, cdnContentId: row.cdnContentId,
            cdnThumbnailUrl: row.cdnThumbnailUrl, cdnContentUrl: row.cdnContentUrl,
            verb: row.verb, payloadType: row.payloadType, commentText: row.commentText,
            firstname: row.firstname, lastname: row.lastname, profile: row.profile,
            type: row.type, isRead: row.isRead, systemNotificationShown: row.systemNotificationShown
        )
    }

    /// Port de `NotiDao.countUnread()`.
    func countUnread() async throws -> Int {
        try await repo.count(predicate: NSPredicate(format: "isRead == 0"))
    }

    /// **Ajouté (2026-08-28, V7-F-021)** — divergence délibérée d'un bug Android confirmé
    /// (`NotificationRepository.triggerSystemNotifications` re-déclenche une notification système
    /// pour CHAQUE entrée non lue à CHAQUE fetch, sans dédoublonnage). Marque qu'une notification
    /// système locale a déjà été présentée pour cet `id`, pour ne plus la re-présenter tant
    /// qu'elle reste non lue.
    func markSystemNotificationShown(_ id: Int32) async throws {
        try await repo.update(predicate: NSPredicate(format: "id == %d", id)) { row in
            row.systemNotificationShown = true
        }
    }

    /// Port de `NotiDao.markAllRead()`.
    func markAllRead() async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            let request = NotiEntity.fetchRequest()
            let rows = try context.fetch(request)
            for row in rows { row.isRead = 1 }
            if context.hasChanges { try context.save() }
        }
    }

    /// Port de `NotiDao.deleteAll()`.
    func deleteAll() async throws {
        try await repo.delete(predicate: nil)
    }

    /// Port de `NotiDao.pruneOld()` : ne garde que les 30 lignes les plus récentes par `stamp`.
    func pruneOld(keeping: Int = 30) async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            let request = NotiEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "stamp", ascending: false)]
            let rows = try context.fetch(request)
            guard rows.count > keeping else { return }
            for row in rows[keeping...] { context.delete(row) }
            if context.hasChanges { try context.save() }
        }
    }
}
