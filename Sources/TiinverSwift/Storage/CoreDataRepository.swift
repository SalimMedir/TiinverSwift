import CoreData

/// Abstraction commune à `CoreDataStack` (store `TiinverModel`) et `AnalyticsCoreDataStack`
/// (store `TiinverAnalyticsModel`) — permet à `CoreDataRepository<Entity>` de fonctionner avec
/// l'une ou l'autre pile sans dupliquer le type générique par store.
protocol CoreDataContextProviding {
    func newBackgroundContext() -> NSManagedObjectContext
}

extension CoreDataStack: CoreDataContextProviding {}
extension AnalyticsCoreDataStack: CoreDataContextProviding {}
extension NotiCoreDataStack: CoreDataContextProviding {}

/// Repository CRUD générique pour une entité d'un store Core Data (`TiinverModel` ou
/// `TiinverAnalyticsModel`).
///
/// Calque du dispatch de `back_sync/StubProvider.java` : ce `ContentProvider` unique route
/// `insert`/`update`/`delete`/`query` vers `SQLiteDatabase.insert/update/delete/query` par simple
/// nom de table, sans logique métier propre à chaque entité (deux exceptions notables, portées
/// séparément — voir `RosterRepository.swift` : la requête jointe `rosterall`
/// (`wk_roster LEFT JOIN wk_messages ON conversationId`) et l'incrément atomique
/// `UNREAD_MESSAGE_COUNT`). Pour toutes les autres tables, un seul type générique suffit plutôt
/// que 14 repositories quasi identiques — décision prise après avoir vérifié que StubProvider
/// lui-même ne fait rien de plus que ce dispatch générique pour elles (voir StubProvider.java).
final class CoreDataRepository<Entity: CoreDataFetchable> where Entity.FetchResult == Entity {
    private let stack: CoreDataContextProviding

    init(stack: CoreDataContextProviding = CoreDataStack.shared) {
        self.stack = stack
    }

    /// Équivalent de `ContentResolver.insert(uri, values)` → `db.insert(table, "", values)`.
    @discardableResult
    func insert(_ configure: @escaping (Entity) -> Void) async throws -> NSManagedObjectID {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let entity = Entity(context: context)
            configure(entity)
            try context.save()
            return entity.objectID
        }
    }

    /// Équivalent de `ContentResolver.update(uri, values, selection, args)` →
    /// `db.update(table, values, selection, args)`.
    @discardableResult
    func update(predicate: NSPredicate, _ configure: @escaping (Entity) -> Void) async throws -> Int {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = Entity.fetchRequest()
            request.predicate = predicate
            let results = try context.fetch(request)
            for entity in results { configure(entity) }
            if context.hasChanges { try context.save() }
            return results.count
        }
    }

    /// Équivalent de `ContentResolver.delete(uri, selection, args)` →
    /// `db.delete(table, selection, args)`. `predicate == nil` reproduit `selection == null`
    /// (efface toutes les lignes de la table), comme les appels `SUGGEST_URI, null, null` observés
    /// dans `TransportData.java`.
    @discardableResult
    func delete(predicate: NSPredicate?) async throws -> Int {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = Entity.fetchRequest()
            request.predicate = predicate
            let results = try context.fetch(request)
            for entity in results { context.delete(entity) }
            if context.hasChanges { try context.save() }
            return results.count
        }
    }

    /// Équivalent de `ContentResolver.query(uri, projection, selection, args, sortOrder)`.
    func query(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = [],
        limit: Int? = nil
    ) async throws -> [Entity] {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = Entity.fetchRequest()
            request.predicate = predicate
            request.sortDescriptors = sortDescriptors
            if let limit { request.fetchLimit = limit }
            return try context.fetch(request)
        }
    }

    /// Une seule ligne, ou `nil` — équivalent des multiples `Cursor c=...; if(c.moveToFirst())`
    /// observés dans `TransportData.java` (ex. `findExisting`, recherche par `id=?`).
    func first(predicate: NSPredicate, sortDescriptors: [NSSortDescriptor] = []) async throws -> Entity? {
        try await query(predicate: predicate, sortDescriptors: sortDescriptors, limit: 1).first
    }

    func count(predicate: NSPredicate? = nil) async throws -> Int {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = Entity.fetchRequest()
            request.predicate = predicate
            return try context.count(for: request)
        }
    }
}
