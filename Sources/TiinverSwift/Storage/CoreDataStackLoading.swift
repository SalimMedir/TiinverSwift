import CoreData

/// **Ajouté (2026-08-28, V7-F-024)** — filet de sécurité partagé par les 3 piles Core Data du
/// projet (`CoreDataStack`/`AnalyticsCoreDataStack`/`NotiCoreDataStack`), approchant
/// `Room.fallbackToDestructiveMigration()`. Aucun des 3 `.xcdatamodeld` n'a de chaîne de versions
/// de modèle — jusqu'ici, un échec de `loadPersistentStores` (ex. le jour où un futur changement
/// de schéma n'est pas accompagné d'une version + mapping) provoquait un `fatalError`
/// systématique au lancement pour TOUS les utilisateurs, jusqu'à correction et nouvelle soumission
/// App Store — contrairement à Android, qui se contente de perdre le cache silencieusement
/// (`Room.fallbackToDestructiveMigration()` pour `AppDatabase`, chaîne `onUpgrade` incrémentale
/// pour `Dbase`/`NotiDatabase`). Aucun des 3 stores iOS n'est la source de vérité d'une donnée —
/// tous rechargeables depuis le serveur ou reconstruits localement — donc une perte de cache local
/// (le pire cas de ce repli) est préférable à un crash permanent.
enum CoreDataStackLoading {
    /// Charge `container`, et sur échec, supprime le store fautif à son URL puis retente UNE fois
    /// avant d'abandonner (un 2ᵉ échec après recréation indique un problème plus profond —
    /// disque plein, permissions — qu'une migration ne résoudrait de toute façon pas).
    static func load(_ container: NSPersistentContainer, storeName: String) {
        container.loadPersistentStores { description, error in
            guard let error else { return }
            guard let url = description.url else {
                fatalError("Impossible de charger le store Core Data \(storeName) (pas d'URL pour tenter une récupération) : \(error)")
            }
            print("CORE DATA: échec du chargement de \(storeName) (\(error)) — suppression et recréation du store.")
            do {
                try container.persistentStoreCoordinator.destroyPersistentStore(at: url, ofType: description.type, options: nil)
            } catch {
                fatalError("Impossible de charger NI de réinitialiser le store Core Data \(storeName) : \(error)")
            }
            container.loadPersistentStores { _, retryError in
                if let retryError {
                    fatalError("Impossible de charger le store Core Data \(storeName), même après réinitialisation : \(retryError)")
                }
            }
        }
    }
}
