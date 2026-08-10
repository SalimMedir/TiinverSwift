import CoreData

/// Pile Core Data indépendante pour le "centre de notifications" paginé, réplique de la base Room
/// `tiinver_notifications.db` (`models/notification/NotiDatabase.java`). TROISIÈME store distinct
/// du projet — voir le commentaire en tête de `TiinverNotificationsModel.xcdatamodeld` pour la
/// justification de la séparation d'avec `TiinverModel` (wk_noti) et `TiinverAnalyticsModel`.
final class NotiCoreDataStack {
    static let shared = NotiCoreDataStack()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "TiinverNotificationsModel")
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Impossible de charger le store Core Data TiinverNotificationsModel : \(error)")
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
