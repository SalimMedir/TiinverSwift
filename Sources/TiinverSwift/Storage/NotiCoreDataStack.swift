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
        // V7-F-024 : repli destructif sur échec, voir `CoreDataStackLoading`.
        CoreDataStackLoading.load(container, storeName: "TiinverNotificationsModel")
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
