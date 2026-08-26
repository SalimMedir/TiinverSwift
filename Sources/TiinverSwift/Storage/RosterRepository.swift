import CoreData

/// Repository pour `RosterEntity` (`wk_roster`) — cas particulier non couvert par
/// `CoreDataRepository<Entity>` générique, car `StubProvider.java` lui attache une opération
/// spécifique (voir `StubProvider.update`, cas `UNREAD_MESSAGE_COUNT`) :
///
/// `unreadmessagecount` : `UPDATE wk_roster SET unreadCount = unreadCount + 1 WHERE
/// conversationId = ?` — incrément atomique, pas un `update(values:)` classique.
///
/// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-072, Phase B P1-30)** — `rosterAll()`
/// reproduisait auparavant la requête `rosterall` de `StubProvider.java` (`SELECT * FROM wk_roster
/// AS r LEFT JOIN wk_messages AS m ON r.conversationId=m.conversationId ORDER BY stamp ASC`) via
/// un second `fetch` `MessageEntity` PAR ligne roster, `fetchLimit = 1`, SANS AUCUN tri —
/// `ROSTER_ALL_URI` (dont cette requête est le pendant Android) est CONFIRMÉ CODE MORT côté
/// Android : jamais requêté par aucun appelant réel, seul `ROSTER_URI` dénormalisé est utilisé par
/// `Roster.java` (l'écran RÉELLEMENT affiché), dont la colonne `wk_roster.lastMessage` est déjà
/// tenue à jour de façon fiable à chaque réception/envoi (`RosterManager.updateRoster*`, porté
/// fidèlement ci-dessous). Le résultat non trié de cette jointure inutile était par-dessus le
/// marché utilisé EN PRIORITÉ par `RosterListView` (`pair.lastMessage?.message ?? entity.
/// lastMessage`), masquant systématiquement la colonne fiable dès qu'une correspondance existait
/// (quasi toujours) — affichant potentiellement le PREMIER message jamais envoyé au lieu du
/// dernier. Supprimé entièrement : `rosterAll()` retourne désormais `[RosterEntity]` brut,
/// `entity.lastMessage` est l'UNIQUE source du texte affiché, sans requête `MessageEntity`
/// supplémentaire — plus simple ET plus fidèle au mécanisme Android réel que la jointure morte
/// qu'il reproduisait.
final class RosterRepository {
    private let stack: CoreDataStack
    private let roster: CoreDataRepository<RosterEntity>

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
        self.roster = CoreDataRepository(stack: stack)
    }

    /// Port de `Roster.java`'s lecture de `ROSTER_URI` (dénormalisé), triée par `stamp` ascendant
    /// comme l'original.
    func rosterAll() async throws -> [RosterEntity] {
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let rosterRequest = RosterEntity.fetchRequest()
            rosterRequest.sortDescriptors = [NSSortDescriptor(key: "stamp", ascending: true)]
            return try context.fetch(rosterRequest)
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

    // MARK: - Port de `roster/RosterManager.java` (234 lignes, lu en entier)
    //
    // `RosterManager.create(Context, Cursor, String)` N'EST PAS porté : son unique effet utile
    // (`updateRoster(context, mlib, false)`) est en commentaire dans le source Android lui-même
    // (ligne 69, `// updateRoster(...)`) — confirmé par grep qu'aucun appelant n'invoque
    // `RosterManager.create` ailleurs dans le projet ; c'est du code mort côté Android, pas porté ici
    // plutôt que reproduit comme un no-op.

    /// Port de `RosterManager.updateRoster(Context, MessageLib, boolean)` (`updateRoster1`) — crée
    /// ou met à jour la ligne `wk_roster` de la conversation. `userId` = `message.sender` si le
    /// message vient du serveur, sinon `message.userId` (reproduit tel quel). Incrémente
    /// `unreadCount` uniquement si `isFromServer`.
    ///
    /// **Asymétrie Android reproduite** : `lucrative`/`price` ne sont écrits QUE sur la branche
    /// UPDATE de `ContentValues` (absents de la branche INSERT, vérifié ligne par ligne) — une
    /// nouvelle ligne conserve donc la valeur par défaut de la colonne (0 des deux côtés).
    func updateRoster(message: MessageLib, isFromServer: Bool) async throws {
        guard let conversationId = message.conversationId else { return }
        let userId = isFromServer ? (message.sender ?? "") : (message.userId ?? "")
        if isFromServer {
            try await incrementUnreadCount(conversationId: conversationId)
        }
        let predicate = NSPredicate(format: "conversationId == %@", conversationId)
        let exists = try await roster.count(predicate: predicate) > 0
        if exists {
            try await roster.update(predicate: predicate) { entity in
                Self.apply(message, userId: userId, isFromServer: isFromServer, to: entity)
                entity.lucrative = Int64(message.lucrative)
                entity.price = Int64(message.price)
            }
        } else {
            try await roster.insert { entity in
                Self.apply(message, userId: userId, isFromServer: isFromServer, to: entity)
            }
        }
    }

    private static func apply(_ message: MessageLib, userId: String, isFromServer: Bool, to entity: RosterEntity) {
        entity.userId = userId
        entity.conversationId = message.conversationId
        entity.messageId = message.messageId
        entity.token = message.token
        entity.groupType = message.groupType
        entity.type = message.type
        entity.groupName = message.groupName
        entity.username = message.username
        entity.nikname = message.nikname
        entity.regroupage = message.regroupage
        entity.groupId = message.groupId
        entity.lastMessage = message.message
        entity.object = message.object
        entity.verb = message.verb
        entity.status = Int64(message.status)
        entity.profile = message.profile
        entity.belongsToCurrentUser = isFromServer ? 0 : 1
        entity.versionCode = Int64(message.versionCode)
        entity.rosterDescription = message.description
        entity.stamp = message.stamp
    }

    /// Port de `RosterManager.updateRoster(Context, Profile, boolean)` (`updateRoster2`) — variante
    /// PBS/Shareboard : `lastMessage`/`object`/`verb` figés à `"shareboard"`, `status` figé à `1`
    /// (constantes littérales côté Android, pas de champ `Profile` correspondant). Les deux branches
    /// (create/update) portent ici EXACTEMENT les mêmes champs (contrairement à la variante
    /// `MessageLib` ci-dessus) — vérifié, `Profile`/`ChatProfile` n'a pas de `lucrative`/`price`.
    func updateRoster(profile: ChatProfile, isFromServer: Bool) async throws {
        guard let conversationId = profile.conversationId else { return }
        let userId = isFromServer ? (profile.sender ?? "") : (profile.userId ?? "")
        if isFromServer {
            try await incrementUnreadCount(conversationId: conversationId)
        }
        let predicate = NSPredicate(format: "conversationId == %@", conversationId)
        let exists = try await roster.count(predicate: predicate) > 0
        let configure: (RosterEntity) -> Void = { entity in
            entity.userId = userId
            entity.conversationId = conversationId
            entity.messageId = profile.messageId
            entity.token = profile.token
            entity.groupType = profile.groupType
            entity.type = profile.chatType
            entity.groupName = profile.groupName
            entity.username = profile.username
            entity.nikname = profile.nikname
            entity.regroupage = profile.regroupage
            entity.groupId = profile.groupId
            entity.lastMessage = "shareboard"
            entity.object = "shareboard"
            entity.verb = "shareboard"
            entity.status = 1
            entity.belongsToCurrentUser = isFromServer ? 0 : 1
            entity.versionCode = Int64(profile.versionCode ?? "") ?? 0
            entity.rosterDescription = profile.description
            entity.stamp = profile.stamp
        }
        if exists {
            try await roster.update(predicate: predicate, configure)
        } else {
            try await roster.insert(configure)
        }
    }

    /// Port de `RosterManager.updateRosterWithLastMessageAfterDeletion` — met à jour le dernier
    /// message affiché d'une conversation après une suppression, SEULEMENT si la ligne existe déjà
    /// (pas de branche insertion côté Android, reproduit tel quel : une conversation inexistante
    /// n'est pas créée par cet appel).
    func updateRosterWithLastMessageAfterDeletion(_ message: MessageLib) async throws {
        guard let conversationId = message.conversationId else { return }
        let predicate = NSPredicate(format: "conversationId == %@", conversationId)
        guard try await roster.count(predicate: predicate) > 0 else { return }
        try await roster.update(predicate: predicate) { entity in
            entity.messageId = message.messageId
            entity.lastMessage = message.message
            entity.object = message.object
            entity.verb = message.verb
            entity.status = Int64(message.status)
            entity.belongsToCurrentUser = message.belongsToCurrentUser ? 1 : 0
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
