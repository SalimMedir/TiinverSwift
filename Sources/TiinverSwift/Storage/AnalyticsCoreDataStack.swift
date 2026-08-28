import CoreData

/// Pile Core Data indépendante pour le schéma "analytics/chat IA", réplique de la base Room
/// `tiinver_db` gérée par `com.tiinver.db.AppDatabase.java` (entités `ViewEvent`,
/// `AiConversationEntity` — voir TIINVER_IOS_PORT_ANALYSIS.md §2.2, confirmé ACTIF et SÉPARÉ de
/// StubProvider). Volontairement une pile distincte de `CoreDataStack`/`TiinverModel` — ne pas
/// fusionner (voir MIGRATION_PROGRESS.md, décision module 2).
final class AnalyticsCoreDataStack {
    static let shared = AnalyticsCoreDataStack()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "TiinverAnalyticsModel")
        // V7-F-024 : repli destructif sur échec, voir `CoreDataStackLoading`.
        CoreDataStackLoading.load(container, storeName: "TiinverAnalyticsModel")
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
