import CoreData

/// Pile Core Data unique pour le schéma "chat/utilisateurs/groupes", réplique de la base SQLite
/// `wenackbdd_@Sm66461027.db` gérée par `Dbase.java`/`back_sync/StubProvider.java` côté Android
/// (voir TIINVER_IOS_PORT_ANALYSIS.md §2.2 — confirmé ACTIF, magasin de données principal du chat).
///
/// Ne PAS fusionner avec un futur store pour `com.tiinver.db.AppDatabase.java` (Room, historique de
/// vues + chat IA Gemini) : c'est une base Android séparée et indépendante, à modéliser plus tard
/// comme une deuxième pile Core Data distincte (voir MIGRATION_PROGRESS.md, note module 2).
final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "TiinverModel")
        // V7-F-024 : repli destructif sur échec (ex. futur changement de schéma), voir
        // `CoreDataStackLoading` — remplace un `fatalError` inconditionnel.
        CoreDataStackLoading.load(container, storeName: "TiinverModel")
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    func saveViewContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            assertionFailure("Échec de sauvegarde Core Data : \(error)")
        }
    }
}
