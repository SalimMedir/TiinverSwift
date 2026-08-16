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

    /// Décodage tolérant (2026-08-16) — même cause racine que `FeedActivity`/`User`
    /// (`LenientDecoding.swift`) : `id` non-optionnel ferait échouer le décodage de CHAQUE
    /// commentaire dès qu'UN SEUL arrive avec un champ numérique en chaîne.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLenientInt(forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        certified = try container.decodeIfPresent(String.self, forKey: .certified)
        activityId = container.decodeLenientIntIfPresent(forKey: .activityId)
        actor = container.decodeLenientIntIfPresent(forKey: .actor)
        repliesCount = container.decodeLenientIntIfPresent(forKey: .repliesCount)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        object_url = try container.decodeIfPresent(String.self, forKey: .object_url)
        commentText = try container.decodeIfPresent(String.self, forKey: .commentText)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        status = container.decodeLenientIntIfPresent(forKey: .status)
        isReply = container.decodeLenientBoolIfPresent(forKey: .isReply)
        stamp = try container.decodeIfPresent(String.self, forKey: .stamp)
        giftEmoji = try container.decodeIfPresent(String.self, forKey: .giftEmoji)
        giftName = try container.decodeIfPresent(String.self, forKey: .giftName)
        giftPrice = container.decodeLenientIntIfPresent(forKey: .giftPrice)
        hasGift = container.decodeLenientBoolIfPresent(forKey: .hasGift)
    }
}
