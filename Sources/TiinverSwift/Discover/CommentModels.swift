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

    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-047, Phase B P1-21)** — port de
    /// `CommentModel.java:300-330` : le serveur n'envoie, pour un commentaire-cadeau, que
    /// `object="gift"` et `comments="gift_thumb_name"` (l'identifiant technique du cadeau, dans
    /// `commentText` ci-dessus) — AUCUNE preuve que des champs séparés `giftEmoji`/`giftName`/
    /// `giftPrice`/`hasGift` soient envoyés par le backend pour cet endpoint (`resolveGift(Context)`
    /// résout ENTIÈREMENT l'affichage CÔTÉ CLIENT via `GiftCatalogHelper`, à partir de `object`/
    /// `commentText` seuls — ne lit jamais de getters gift directs). Les 4 champs décodés
    /// précédemment (supposant un serveur pré-résolu, jamais confirmé) sont retirés ; voir
    /// `CommentsView.commentLine` pour la résolution via `GiftCatalog.resolve(commentText)`,
    /// fidèle à `resolveGift`.
    var object: String?
    var isGiftComment: Bool { object == "gift" }

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
        object = try container.decodeIfPresent(String.self, forKey: .object)
    }

    /// Port de l'ajout optimiste `SentCmtToServer` (`MyBottomSheetDialogFragment.java:402-436`,
    /// V5-F-066) — commentaire local temporaire affiché avant confirmation serveur. `id` négatif
    /// dérivé de l'horloge, jamais un id serveur réel (les id serveur sont toujours positifs).
    init(optimisticText text: String) {
        id = -Int(Date().timeIntervalSince1970 * 1_000_000)
        username = UserSession.shared.username
        firstname = nil
        lastname = nil
        profile = UserSession.shared.profile
        certified = nil
        activityId = nil
        actor = UserSession.shared.myId.flatMap(Int.init)
        repliesCount = nil
        parentId = nil
        object_url = nil
        commentText = text
        action = nil
        status = 0
        isReply = false
        stamp = nil
        object = nil
    }
}
