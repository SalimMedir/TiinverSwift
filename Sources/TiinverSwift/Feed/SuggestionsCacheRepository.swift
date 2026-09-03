import CoreData

/// **Ajouté (2026-09-03, demande explicite)** — port du cache local `wk_suggest`
/// (`infoContract.SUGGEST_URI`, `AdapterSuggestContact`/`CursorWorkerTask`) que
/// `SuggestionsRepository.swift` avait délibérément laissé de côté (lecture réseau directe
/// uniquement) : décision produit explicite de l'utilisateur — la fonctionnalité doit exister des
/// DEUX côtés, pas seulement produire le même résultat visuel par un autre mécanisme. `SuggestEntity`
/// existait déjà dans `TiinverModel.xcdatamodeld` (schéma scaffoldé dès la mise en place du store
/// Core Data), mais n'était référencé nulle part dans le code — jamais câblé jusqu'ici.
///
/// `SuggestionsCarouselView.load()` affiche désormais CE cache immédiatement (rapide, disponible
/// même hors ligne ou avant que le réseau réponde — fidèle à Android, où l'UI lit systématiquement
/// depuis un `CursorLoader` sur la base locale, jamais directement le réseau), puis rafraîchit
/// depuis `SuggestionsRepository.fetchSuggestions` et remplace le cache par le résultat frais —
/// même stratégie "vider puis réinsérer" que `CursorWorkerTask` pour cette table précise (une petite
/// liste rafraîchissable, pas un flux cumulatif comme les messages).
@MainActor
final class SuggestionsCacheRepository {
    static let shared = SuggestionsCacheRepository()
    private let stack: CoreDataContextProviding

    private init(stack: CoreDataContextProviding = CoreDataStack.shared) {
        self.stack = stack
    }

    /// Fetch direct sur un contexte d'arrière-plan, projection en `User` ENTIÈREMENT dans
    /// `context.perform` — même leçon de sécurité Core Data que le correctif appliqué à
    /// `ViewEventRepository.pending()` (ne jamais laisser un `NSManagedObject` quitter la queue de
    /// son propre contexte) : `CoreDataRepository<Entity>.query()` générique n'est PAS utilisé ici
    /// pour cette raison.
    func cached() async throws -> [User] {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = SuggestEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "localId", ascending: true)]
            let rows = try context.fetch(request)
            return rows.map { row in
                var user = User()
                user.id = Int(row.id)
                user.firstname = row.firstname
                user.lastname = row.lastname
                user.username = row.username
                user.profile = row.profile
                user.certified = row.certified
                user.location = row.location
                user.followers = String(row.followers)
                user.following = String(row.following)
                return user
            }
        }
    }

    func replaceAll(_ users: [User]) async throws {
        let context = stack.newBackgroundContext()
        try await context.perform {
            let existing = try context.fetch(SuggestEntity.fetchRequest())
            for row in existing { context.delete(row) }
            for (index, user) in users.enumerated() {
                let row = SuggestEntity(context: context)
                row.localId = Int64(index)
                row.id = Int64(user.id ?? 0)
                row.firstname = user.firstname
                row.lastname = user.lastname
                row.username = user.username
                row.profile = user.profile
                row.certified = user.certified
                row.location = user.location
                row.followers = Int64(user.followers ?? "") ?? 0
                row.following = Int64(user.following ?? "") ?? 0
            }
            if context.hasChanges { try context.save() }
        }
    }
}
