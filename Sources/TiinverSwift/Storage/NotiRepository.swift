import CoreData

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
    func getAll() async throws -> [NotiEntity] {
        try await repo.query(sortDescriptors: [NSSortDescriptor(key: "stamp", ascending: false)])
    }

    /// Port de `NotiDao.getById(id)`.
    func getById(_ id: Int32) async throws -> NotiEntity? {
        try await repo.first(predicate: NSPredicate(format: "id == %d", id))
    }

    /// Port de `NotiDao.countUnread()`.
    func countUnread() async throws -> Int {
        try await repo.count(predicate: NSPredicate(format: "isRead == 0"))
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
