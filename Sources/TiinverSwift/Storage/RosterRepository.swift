import CoreData

/// Repository pour `RosterEntity` (`wk_roster`) — cas particulier non couvert par
/// `CoreDataRepository<Entity>` générique, car `StubProvider.java` lui attache deux opérations
/// spécifiques (voir `StubProvider.query`/`update`, cas `ROSTER_ALL` et `UNREAD_MESSAGE_COUNT`) :
///
/// 1. `rosterall` : `SELECT * FROM wk_roster AS r LEFT JOIN wk_messages AS m
///    ON r.conversationId=m.conversationId ORDER BY stamp ASC` — jointure brute, pas une simple
///    lecture de table.
/// 2. `unreadmessagecount` : `UPDATE wk_roster SET unreadCount = unreadCount + 1 WHERE
///    conversationId = ?` — incrément atomique, pas un `update(values:)` classique.
///
/// Core Data n'a pas d'équivalent direct à une jointure SQL brute : on reproduit le même résultat
/// logique (chaque conversation de `wk_roster`, associée à son dernier message `wk_messages`
/// correspondant) en deux fetch Core Data + assemblage en mémoire, plutôt que par une requête
/// jointe native. Fidèle au résultat observable de `StubProvider`, pas à son implémentation SQL.
struct RosterWithLastMessage {
    let roster: RosterEntity
    let lastMessage: MessageEntity?
}

final class RosterRepository {
    private let stack: CoreDataStack
    private let roster: CoreDataRepository<RosterEntity>
    private let messages: CoreDataRepository<MessageEntity>

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
        self.roster = CoreDataRepository(stack: stack)
        self.messages = CoreDataRepository(stack: stack)
    }

    /// Équivalent de la requête `rosterall` (jointure `wk_roster` LEFT JOIN `wk_messages`
    /// ON `conversationId`), triée par `stamp` ascendant comme l'original.
    func rosterAll() async throws -> [RosterWithLastMessage] {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let rosterRequest = RosterEntity.fetchRequest()
            rosterRequest.sortDescriptors = [NSSortDescriptor(key: "stamp", ascending: true)]
            let rosterRows = try context.fetch(rosterRequest)

            return try rosterRows.map { row in
                var lastMessage: MessageEntity?
                if let conversationId = row.conversationId {
                    let messageRequest = MessageEntity.fetchRequest()
                    messageRequest.predicate = NSPredicate(format: "conversationId == %@", conversationId)
                    messageRequest.fetchLimit = 1
                    lastMessage = try context.fetch(messageRequest).first
                }
                return RosterWithLastMessage(roster: row, lastMessage: lastMessage)
            }
        }
    }

    /// Équivalent de `UPDATE wk_roster SET unreadCount = unreadCount + 1 WHERE conversationId = ?`
    /// (cas `UNREAD_MESSAGE_COUNT` de `StubProvider.update`). Toujours reproduit "1 ligne affectée"
    /// même si aucune ligne ne correspond, à l'identique du code Android d'origine
    /// (`rowsUpdated = 1;` codé en dur, indépendamment du résultat réel de l'`UPDATE`).
    @discardableResult
    func incrementUnreadCount(conversationId: String) async throws -> Int {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = RosterEntity.fetchRequest()
            request.predicate = NSPredicate(format: "conversationId == %@", conversationId)
            let rows = try context.fetch(request)
            for row in rows { row.unreadCount += 1 }
            if context.hasChanges { try context.save() }
            return 1
        }
    }

    func insert(_ configure: @escaping (RosterEntity) -> Void) async throws {
        try await roster.insert(configure)
    }

    func update(predicate: NSPredicate, _ configure: @escaping (RosterEntity) -> Void) async throws {
        try await roster.update(predicate: predicate, configure)
    }

    func delete(predicate: NSPredicate?) async throws {
        try await roster.delete(predicate: predicate)
    }

    func query(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor] = []) async throws -> [RosterEntity] {
        try await roster.query(predicate: predicate, sortDescriptors: sortDescriptors)
    }
}
