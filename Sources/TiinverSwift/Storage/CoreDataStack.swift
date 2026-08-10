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
        container.loadPersistentStores { _, error in
            if let error {
                // Équivalent Android : SQLiteOpenHelper échouerait aussi de façon fatale si la base
                // ne peut pas être ouverte/créée — pas de dégradation silencieuse possible ici non plus.
                fatalError("Impossible de charger le store Core Data TiinverModel : \(error)")
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

    func saveViewContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            assertionFailure("Échec de sauvegarde Core Data : \(error)")
        }
    }
}
