import Foundation

/// Port de `models/activity/comments/GiftCatalogHelper.java` (119 lignes, lu en entier) —
/// catalogue statique cadeau→(emoji, prix, nom) utilisé par `GiftBadgeView` (chat, module 11) et
/// `CommentModel.resolveGift` (commentaires, module 18, pas encore atteint).
///
/// **Corrigé (2026-09-04, correction du Gift tab, forensique CHAT_GIFT_FORENSIC)** — `name`
/// retombait sur l'identifiant technique brut (ex. `"gift_diamond_name"`), documenté comme un gap.
/// Le panneau cadeau réel (`GiftAdapter.onBindViewHolder`, `GiftAdapter.java:50`) affiche
/// `g.getLocalizedName(context)`, c'est-à-dire la VRAIE chaîne `R.string.gift_xxx_name` — ce
/// portage n'a pas de système de `Localizable.strings` construit pour ce module (comme partout
/// ailleurs dans ce codebase, les chaînes françaises sont écrites en dur directement au site
/// d'usage), donc les 12 noms sont recopiés ici tels quels depuis `values-fr/strings.xml:827-838`
/// (l'app est servie en français, jamais `values/strings.xml`, l'anglais de développement).
enum GiftCatalog {
    struct ResolvedGift {
        let emoji: String
        let name: String
        let price: Int
    }

    /// Port de `EMOJI_MAP`/`PRICE_MAP`/`NAME_RES_MAP` (les 3 tables Android, fusionnées ici car
    /// indexées par le même `giftId` et jamais utilisées séparément côté chat). `name` = valeur
    /// FRANÇAISE réelle de `R.string.gift_xxx_name` (`values-fr/strings.xml`), pas l'anglais de
    /// développement de `values/strings.xml`.
    private static let entries: [String: (emoji: String, name: String, price: Int)] = [
        "gift_thumb_name": ("👍", "Pouce", 5),
        "gift_fire_name": ("🔥", "Feu", 10),
        "gift_rose_name": ("🌹", "Rose", 15),
        "gift_love_name": ("❤️", "Amour", 25),
        "gift_rainbow_name": ("🌈", "Belle journée", 50),
        "gift_pearl_name": ("🐚", "Perle", 100),
        "gift_first_name": ("🥇", "1re place", 250),
        "gift_car_name": ("🚗", "Allons-y", 500),
        "gift_gold_name": ("🏅", "Or", 1000),
        "gift_elite_name": ("✈️", "Élite", 1500),
        "gift_diamond_name": ("💎", "Diamant", 2000),
        "gift_crown_name": ("👑", "Royauté", 3000),
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
        return ResolvedGift(emoji: entry.emoji, name: entry.name, price: entry.price)
    }

    /// Port de `GiftModel.getLocalizedName(Context)` — nom seul, sans emoji ni prix (`GiftAdapter`,
    /// grille de sélection du panneau).
    static func name(for giftId: String?) -> String {
        guard let giftId, let entry = entries[giftId] else { return "" }
        return entry.name
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
