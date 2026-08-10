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
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Impossible de charger le store Core Data TiinverAnalyticsModel : \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
