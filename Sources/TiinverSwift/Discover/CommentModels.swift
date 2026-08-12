import Foundation

/// Port de `models/activity/comments/CommentModel.java` (368 lignes, champs lus en entier) —
/// `extends User` côté Android (Gson sérialise les champs hérités ET propres dans le même JSON
/// plat) ; Swift n'a pas d'héritage de struct, donc les champs `User` pertinents sont recopiés à
/// plat ici plutôt que composés, pour rester un miroir direct du JSON reçu.
struct Comment: Codable, Identifiable, Equatable {
    var id: Int
    var username: String?
    var firstname: String?
    var lastname: String?
    var profile: String?
    var certified: String?

    var activityId: Int?
    var actor: Int?
    var repliesCount: Int?
    var parentId: String?
    var object_url: String?
    var commentText: String?
    var action: String?
    var status: Int?
    var isReply: Bool?
    var stamp: String?

    /// Port du "commentaire cadeau" (`giftEmoji`/`giftName`/`giftPrice`/`hasGift`) — commentaire
    /// payant en pièces, même catalogue que `GiftCatalog` (module 11). **Envoi PAS porté cette
    /// session** — `CommentRepository.debitCoins`/endpoint `comment/add` identifiés mais l'UI de
    /// sélection de cadeau (`GiftAdapter.java`, pas lu) ne l'est pas ; lecture seule ici.
    var giftEmoji: String?
    var giftName: String?
    var giftPrice: Int?
    var hasGift: Bool?

    var belongsToCurrentUser: Bool { actor.map { String($0) == UserSession.shared.myId } ?? false }
}
