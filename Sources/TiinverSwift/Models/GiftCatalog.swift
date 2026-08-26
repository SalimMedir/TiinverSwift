import Foundation

/// Port de `models/activity/comments/GiftCatalogHelper.java` (119 lignes, lu en entier) —
/// catalogue statique cadeau→(emoji, prix, nom) utilisé par `GiftBadgeView` (chat, module 11) et
/// `CommentModel.resolveGift` (commentaires, module 18, pas encore atteint). Les chaînes de nom
/// (`R.string.gift_xxx_name`) ne sont pas encore localisées côté Swift (`Localizable.strings` pas
/// encore construit pour ce module) — `name` retombe sur l'identifiant technique en attendant,
/// documenté plutôt que deviné.
enum GiftCatalog {
    struct ResolvedGift {
        let emoji: String
        let name: String
        let price: Int
    }

    /// Port de `EMOJI_MAP`/`PRICE_MAP` (les deux tables Android, fusionnées ici car indexées par le
    /// même `giftId` et jamais utilisées séparément côté chat).
    private static let entries: [String: (emoji: String, price: Int)] = [
        "gift_thumb_name": ("👍", 5),
        "gift_fire_name": ("🔥", 10),
        "gift_rose_name": ("🌹", 15),
        "gift_love_name": ("❤️", 25),
        "gift_rainbow_name": ("🌈", 50),
        "gift_pearl_name": ("🐚", 100),
        "gift_first_name": ("🥇", 250),
        "gift_car_name": ("🚗", 500),
        "gift_gold_name": ("🏅", 1000),
        "gift_elite_name": ("✈️", 1500),
        "gift_diamond_name": ("💎", 2000),
        "gift_crown_name": ("👑", 3000),
    ]

    /// Port de `buildGiftCatalog()` (`MyBottomSheetDialogFragment.java:115-130`) — MÊME ordre
    /// (prix croissant) que la grille Android, `entries` (dictionnaire, ordre non garanti) ne
    /// suffit pas seul pour ça. **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-048,
    /// Phase B P2)** pour la grille de sélection du panneau cadeau-commentaire, jusque-là jamais
    /// construite côté iOS (`resolve`/`emoji`/`price` suffisaient à l'AFFICHAGE d'un cadeau déjà
    /// choisi, pas à l'énumération pour un sélecteur).
    static let orderedGiftIds: [String] = [
        "gift_thumb_name", "gift_fire_name", "gift_rose_name", "gift_love_name",
        "gift_rainbow_name", "gift_pearl_name", "gift_first_name", "gift_car_name",
        "gift_gold_name", "gift_elite_name", "gift_diamond_name", "gift_crown_name",
    ]

    /// Port de `GiftCatalogHelper.resolve(Context, String)`.
    static func resolve(_ giftId: String?) -> ResolvedGift? {
        guard let giftId, let entry = entries[giftId] else { return nil }
        return ResolvedGift(emoji: entry.emoji, name: giftId, price: entry.price)
    }

    /// Port de `getEmojiForStringId` — retombe sur 🎁 si l'id est inconnu.
    static func emoji(for giftId: String?) -> String {
        guard let giftId, let entry = entries[giftId] else { return "🎁" }
        return entry.emoji
    }

    /// Port de `getPriceForStringId`.
    static func price(for giftId: String?) -> Int {
        guard let giftId, let entry = entries[giftId] else { return 0 }
        return entry.price
    }

    static func isKnown(_ giftId: String?) -> Bool {
        guard let giftId else { return false }
        return entries[giftId] != nil
    }
}
