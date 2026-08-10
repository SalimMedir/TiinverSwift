import CoreData

/// Permet à `CoreDataRepository<Entity>` d'appeler `Entity.fetchRequest()` de façon générique.
///
/// Chaque entité du modèle est déclarée `codeGenerationType="class"` dans le `.xcdatamodel`
/// (voir `TiinverModel.xcdatamodeld`), donc Xcode génère déjà `class func fetchRequest() ->
/// NSFetchRequest<EntityConcrète>` (type concret, pas générique) pour chacune au moment du build.
///
/// `FetchResult` est un `associatedtype` (et non `Self` directement dans la signature) : un
/// protocole qui utilise `Self` imbriqué dans un paramètre générique (`NSFetchRequest<Self>`) ne
/// peut être satisfait que par une classe `final` (limitation du langage — covariance non prouvable
/// pour une sous-classe potentielle). Les classes d'entités Core Data générées par Xcode ne sont
/// PAS `final`, d'où `error: protocol 'CoreDataFetchable' requirement 'fetchRequest()' cannot be
/// satisfied by a non-final class` au premier build réel. Passer par un `associatedtype` (déduit
/// automatiquement par Swift depuis la méthode `fetchRequest()` déjà générée par Xcode pour
/// chaque entité, aucune déclaration supplémentaire nécessaire dans les `extension` ci-dessous)
/// contourne cette contrainte sans toucher au codegen Core Data ni exiger que les entités soient
/// `final`.
protocol CoreDataFetchable: NSManagedObject {
    associatedtype FetchResult: NSManagedObject = Self
    static func fetchRequest() -> NSFetchRequest<FetchResult>
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
