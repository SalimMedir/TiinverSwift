import CoreData

/// Port de `db/dao/AiConversationDao.java` (historique du chat IA Gemini, table `ai_conversations`
/// / entité `AiConversationEntity`). Écran consommateur (`TiinverGeminiAIChat.java`) pas encore
/// porté — module non explicitement numéroté dans l'ordre de portage, à rattacher au moment venu
/// (voir MIGRATION_PROGRESS.md). Seule la couche de stockage est portée ici, avec le reste du
/// module 2.
final class AiConversationRepository {
    private let repo: CoreDataRepository<AiConversationEntity>

    init(stack: CoreDataContextProviding = AnalyticsCoreDataStack.shared) {
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
    func conversation(userId: Int64, now: Int64) async throws -> [AiConversationEntity] {
        try await repo.query(
            predicate: NSPredicate(format: "userId == %lld AND expiresAt > %lld", userId, now),
            sortDescriptors: [NSSortDescriptor(key: "stamp", ascending: true)]
        )
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
