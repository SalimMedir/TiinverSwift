import UserNotifications

/// Port partiel de `back_sync/NotificationUtils.java`.
///
/// Portés ici (contenu de notification uniquement — présentation via `UNUserNotificationCenter`,
/// pas de `NotificationCompat.Builder`/canaux Android à répliquer) :
/// - `displayNoMessageNotification` → `activityNotificationContent(...)` (like/comment/share/
///   follow/transfert/post/missedvoicecall).
/// - `displayNotificationOrPushMessage` → `chatMessageNotificationContent(...)` (aperçu de
///   message reçu).
///
/// PAS portés ici, volontairement :
/// - `showIncomingCallNotification`/`showOngoingNotification` — VoIP/CallKit, module 12 (Appels
///   WebRTC + CallKit), pas "notifications push" génériques.
/// - `showUploadFileNotification` — notification de progression d'envoi de fichier, rattachée au
///   module 11 (Messagerie), pas au socle push.
/// - `displaySuggestNotification` — notification de réengagement avec messages choisis
///   aléatoirement dans des `R.array` localisés (matin/après-midi/soir/nuit) : le contenu textuel
///   source (`strings.xml`) n'a pas été lu, DIFFÉRÉ plutôt qu'inventé.
///
/// Les textes ci-dessous sont des équivalents français directs des chaînes `R.string.*`
/// d'origine (mêmes clés en commentaire) — à remplacer par un vrai catalogue de chaînes
/// localisées quand ce sujet sera traité (pas encore un module de l'ordre de portage).
enum LocalNotificationBuilder {

    struct ActivityPayload {
        var title: String
        var verb: String // like | share | comment | follow | transfert | post | missedvoicecall
        var object: String?
        var payloadType: String?
        var message: String?
        var myNikname: String?
    }

    /// Port de `NotificationUtils.displayNoMessageNotification`.
    static func activityNotificationContent(_ payload: ActivityPayload) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = payload.title

        switch payload.verb {
        case "like":
            content.body = "a aimé votre publication" // R.string.unJme + R.string.yourPublication
        case "share":
            content.body = "a partagé votre publication" // R.string.share + R.string.yourPublication
        case "comment":
            if payload.payloadType == "gift" {
                // **Corrigé (V4-F-071, 2026-08-24)** — port de `NotificationUtils.java:311-319` :
                // `String.format("%s %s %s %s %s ", send_you_a_gift, emoji, giftName, as, comment)`,
                // reproduit tel quel y compris la tournure "en tant que commenter" un peu étrange
                // côté Android (`R.string.as` = "en tant que", `R.string.comment` = "commenter").
                // `payload.message` porte l'id du cadeau, comme `notificationVO.getMessage()`.
                // Emoji et nom résolus INDÉPENDAMMENT (comme Android : `getEmojiForStringId`
                // retombe sur 🎁, `nameRes == 0` retombe sur `R.string.gift` = "cadeau"), jamais un
                // repli "tout ou rien" — un id de cadeau inconnu affiche quand même 🎁 + "cadeau".
                let emoji = GiftCatalog.emoji(for: payload.message)
                let name = GiftCatalog.resolve(payload.message)?.name ?? "cadeau"
                content.body = "vous a envoyé un cadeau \(emoji) \(name) en tant que commenter"
            } else {
                content.body = "a commenté votre publication : « \(payload.message ?? "") »" // unCmt + yourPublication
            }
        case "follow":
            content.body = "a commencé à vous suivre" // R.string.new_follow_message
        case "transfert":
            content.body = "vous a transféré \(payload.object ?? "") coins" // transferred_you + coins
        case "post":
            content.body = "\(payload.myNikname ?? ""), nouvelle publication" // new_post
        case "missedvoicecall":
            content.body = "Appel manqué" // R.string.missedvoicecall
            content.categoryIdentifier = "missed_call"
        default:
            content.body = payload.message ?? ""
        }

        content.sound = .default
        return content
    }

    struct ChatMessagePayload {
        var title: String
        var message: String
        var object: String // text | graphic | gif | gift | sticker | photo | audio | doc | video | shareboard | missedvoicecall
    }

    /// Port de `NotificationUtils.displayNotificationOrPushMessage`.
    static func chatMessageNotificationContent(_ payload: ChatMessagePayload) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = payload.title

        switch payload.object {
        case "text":
            content.body = payload.message
        case "graphic":
            content.body = "Message graphique" // R.string.graphic
        case "gif":
            content.body = "GIF" // R.string.gif
        case "gift":
            // **Corrigé (V4-F-071, 2026-08-24)** — port de `NotificationUtils.java:123-129` :
            // `String.format("%s %s ", emoji, giftName)`. `payload.message` porte l'id du cadeau,
            // comme `notificationVO.getMessage()`. Même repli indépendant emoji/nom qu'en commentaire
            // ci-dessus.
            let emoji = GiftCatalog.emoji(for: payload.message)
            let name = GiftCatalog.resolve(payload.message)?.name ?? "cadeau"
            content.body = "\(emoji) \(name)"
        case "sticker":
            content.body = "Sticker" // R.string.sticker
        case "photo":
            content.body = "Photo" // R.string.photo
        case "audio":
            content.body = "Message audio" // R.string.audio
        case "doc":
            content.body = "Document" // R.string.document
        case "video":
            content.body = "Vidéo" // R.string.video
        case "shareboard":
            content.body = payload.message
        case "missedvoicecall":
            content.body = "Appel manqué" // R.string.missedvoicecall
            content.categoryIdentifier = "missed_call"
        default:
            content.body = payload.message
        }

        content.sound = .default
        return content
    }

    /// Affiche immédiatement (équivalent `notificationManager.notify(NOTIFICATION_ID, ...)`).
    static func present(_ content: UNMutableNotificationContent, identifier: String = UUID().uuidString) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
