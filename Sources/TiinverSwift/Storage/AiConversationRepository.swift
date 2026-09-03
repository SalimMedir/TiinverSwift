import CoreData

/// **Ajouté (2026-09-03)** — DTO valeur, même raisonnement que `PendingViewEvent`
/// (`ViewEventRepository.swift`, voir sa doc pour le crash `EXC_BAD_ACCESS` de fond) :
/// `conversation(userId:now:)` renvoyait auparavant des `AiConversationEntity` (`NSManagedObject`)
/// vivants, dont `AIChatViewModel.loadInitial()` lisait ensuite les propriétés bien après le
/// `context.perform` d'origine — accès cross-thread interdit par Core Data.
struct AiConversationMessage {
    let role: String?
    let type: String?
    let content: String?
    let stamp: Int64
}

/// Port de `db/dao/AiConversationDao.java` (historique du chat IA Gemini, table `ai_conversations`
/// / entité `AiConversationEntity`). Écran consommateur (`TiinverGeminiAIChat.java`) pas encore
/// porté — module non explicitement numéroté dans l'ordre de portage, à rattacher au moment venu
/// (voir MIGRATION_PROGRESS.md). Seule la couche de stockage est portée ici, avec le reste du
/// module 2.
final class AiConversationRepository {
    private let stack: CoreDataContextProviding
    private let repo: CoreDataRepository<AiConversationEntity>

    init(stack: CoreDataContextProviding = AnalyticsCoreDataStack.shared) {
        self.stack = stack
        self.repo = CoreDataRepository(stack: stack)
    }

    /// Port de `AiConversationDao.insert(message)`.
    @discardableResult
    func insert(userId: Int64, role: String, type: String, content: String, stamp: Int64, expiresAt: Int64) async throws -> NSManagedObjectID {
        try await repo.insert { row in
            row.userId = userId
            row.role = role
            row.type = type
            row.content = content
            row.stamp = stamp
            row.expiresAt = expiresAt
        }
    }

    /// Port de `AiConversationDao.getConversation(userId, now)` — messages non expirés, triés
    /// par `stamp` ascendant.
    ///
    /// **Corrigé (2026-09-03)** — voir la doc de `AiConversationMessage` ci-dessus : fetch direct
    /// (contourne `CoreDataRepository.query()`), projection en DTO faite ICI, DANS le
    /// `context.perform` d'origine, avant que les objets ne quittent la queue du contexte qui les
    /// possède.
    func conversation(userId: Int64, now: Int64) async throws -> [AiConversationMessage] {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = AiConversationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %lld AND expiresAt > %lld", userId, now)
            request.sortDescriptors = [NSSortDescriptor(key: "stamp", ascending: true)]
            return try context.fetch(request).map { row in
                AiConversationMessage(role: row.role, type: row.type, content: row.content, stamp: row.stamp)
            }
        }
    }

    /// Port de `AiConversationDao.deleteExpired(now)`.
    func deleteExpired(now: Int64) async throws {
        try await repo.delete(predicate: NSPredicate(format: "expiresAt <= %lld", now))
    }

    /// Port de `AiConversationDao.clearConversation(userId)`.
    func clearConversation(userId: Int64) async throws {
        try await repo.delete(predicate: NSPredicate(format: "userId == %lld", userId))
    }
}
