import CoreData

/// Permet à `CoreDataRepository<Entity>` d'appeler `Entity.fetchRequest()` de façon générique.
///
/// Chaque entité du modèle est déclarée `codeGenerationType="class"` dans le `.xcdatamodel`
/// (voir `TiinverModel.xcdatamodeld`), donc Xcode génère déjà `class func fetchRequest() ->
/// NSFetchRequest<Self>` pour chacune au moment du build — on ne fait ici que déclarer la
/// conformance au protocole pour que le générique puisse s'appuyer dessus.
protocol CoreDataFetchable: NSManagedObject {
    static func fetchRequest() -> NSFetchRequest<Self>
}

extension AccountEntity: CoreDataFetchable {}
extension ActivityEntity: CoreDataFetchable {}
extension ReactionEntity: CoreDataFetchable {}
extension CommentEntity: CoreDataFetchable {}
extension SuggestEntity: CoreDataFetchable {}
extension MessageEntity: CoreDataFetchable {}
extension GroupMessageEntity: CoreDataFetchable {}
extension GroupMembershipEntity: CoreDataFetchable {}
extension NotificationEntity: CoreDataFetchable {}
extension FCMTokenEntity: CoreDataFetchable {}
extension GroupMemberEntity: CoreDataFetchable {}
extension ContactEntity: CoreDataFetchable {}
extension RosterEntity: CoreDataFetchable {}
extension FileTransferEntity: CoreDataFetchable {}

// Store séparé TiinverAnalyticsModel (voir AnalyticsCoreDataStack.swift) — conformance déclarée
// ici aussi, le protocole n'étant pas lié à un store en particulier.
extension ViewEventEntity: CoreDataFetchable {}
extension AiConversationEntity: CoreDataFetchable {}

// Store séparé TiinverNotificationsModel (voir NotiCoreDataStack.swift).
extension NotiEntity: CoreDataFetchable {}
