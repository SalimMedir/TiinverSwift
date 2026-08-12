import Foundation

/// Port de `models/chat/MessageLib.java` (929 lignes, module 11) — modèle de message reçu du
/// serveur (désérialisé par Gson depuis le tableau `"data"` des événements `new message`/
/// `new message group`) ET utilisé pour l'insertion locale (`ContentValues`→`wk_messages`/
/// `wk_gp_messages`, déjà modélisées `MessageEntity`/`GroupMessageEntity` au module 2).
///
/// **Portée délibérément réduite** : le fichier Android original mélange ~70 champs, dont une
/// bonne moitié est de l'état d'adaptateur RecyclerView TRANSITOIRE, jamais sérialisé ni persisté
/// (`isSelectedItem`, `viewType`, `hasDateSeparator`, `drawableId`, `position`, `isNewMessage`,
/// `animateOnWriting`, `isOnline`, `isTyping`, `userOnline`, `title`/`subTitle` calculés pour
/// l'affichage) — confirmés en lisant `ChatManager.getSpecifiqueMessage`/`addMessage` : ces champs
/// ne sont JAMAIS lus depuis le JSON serveur ni écrits en base, uniquement positionnés/lus par
/// l'adaptateur de liste (module non encore porté, voir `MessageListAdapter.java`). Seuls les
/// champs confirmés PAR TRIPLE RECOUPEMENT sont repris ici : (1) présents dans au moins un des 20
/// patrons JSON de `MessagePacket.getPacketString()` (lu en entier), (2) présents dans le mapping
/// `ContentValues` de `ChatManager.addMessage`/`insertTextMessage`/`insertFileMessage` (lu en
/// entier), (3) présents dans `MessageEntity`/`GroupMessageEntity` (Core Data, module 2, déjà
/// porté depuis `Dbase.java`). Les champs UI-only seront réintroduits comme état de vue SwiftUI
/// (PAS Codable) au moment de porter `MessageListAdapter.java`.
struct MessageLib: Codable, Equatable {
    var messageId: String?
    var conversationId: String?
    var type: String?
    var to: String?
    var from: String?
    var sender: String?
    var receiver: String?
    var nikname: String?
    var username: String?
    var message: String?
    var giftId: String?
    var verb: String?
    var object: String?

    var objectUrl: String?
    var thumbnailUri: String?
    var thumbnailUrl: String?
    var localFileDirection: String?

    var profile: String?
    var status: Int = 0
    var vu: String?
    var regroupage: String?
    var stamp: String?
    var deliverTime: String?
    var resource: String?
    var versionCode: Int = 0

    var isQuoted: Bool = false
    var quoteMessage: String?
    var quoteTitle: String?
    var quoteObject: String?
    var quoteDuration: String?

    var width: String?
    var height: String?
    var duration: String?
    var imageByte: [UInt8]?

    /// Port de `groupType`/`groupId`/`groupName`/`token`/`description` — présents uniquement pour
    /// `type == "chatgroup"`.
    var groupType: String?
    var groupId: String?
    var groupName: String?
    var token: String?
    var description: String?

    /// Port de `MgGraphic` — payload JSON DÉJÀ SÉRIALISÉ en chaîne côté Android
    /// (`getGraphicMessageJsonPacket` retourne `message` inchangé pour `object == "graphic"`) —
    /// stocké comme `String` brute, pas re-décodé ici (le format `GraphicMessageCodec`/
    /// `CompactTouchEvent` cité par le rapport de faisabilité §3.4 n'a pas été lu, module Message
    /// Graphic pas encore atteint).
    var mgGraphic: String?

    var senderFcmId: String?
    var receiverFcmId: String?
    var creationDate: String?
    var isFileUploaded: Int = 0
    var isFileDownloaded: Int = 0
    var userId: String?
    var share: String?
    var origin: String?

    /// Port de `lucrative`/`price`/`belongsToCurrentUser` — absents des 20 patrons JSON de
    /// `MessagePacket` (jamais envoyés sur le fil) mais lus par `RosterManager.updateRoster`
    /// (`ContentValues` de `wk_roster`, pas `wk_messages`) — ajoutés après coup en portant
    /// `RosterManager.java`, pas dans le premier passage triple-recoupement de ce fichier
    /// puisqu'ils ne recoupent QUE le mapping roster, pas les deux autres sources.
    var lucrative: Int = 0
    var price: Int = 0
    var belongsToCurrentUser: Bool = false

    enum CodingKeys: String, CodingKey {
        case messageId, conversationId, type, to, from, sender, receiver, nikname, username
        case message, giftId, verb, object
        case objectUrl = "object_url"
        case thumbnailUri = "thumbnailUri"
        case thumbnailUrl = "thumbnail_url"
        case localFileDirection
        case profile, status, vu, regroupage, stamp
        case deliverTime = "deliver_time"
        case resource, versionCode
        case isQuoted, quoteMessage, quoteTitle, quoteObject, quoteDuration
        case width, height, duration
        case imageByte = "image_byte"
        case groupType, groupId, groupName, token, description
        case mgGraphic = "MgGraphic"
        case senderFcmId, receiverFcmId, creationDate
        case isFileUploaded, isFileDownloaded
        case userId, share, origin
        case lucrative, price, belongsToCurrentUser
    }

    init() {}

    /// Port des constantes `MessageLib.CHAT`/`CHATGROUP`/`CALL`/`CALLGROUP`.
    enum WireType {
        static let chat = "chat"
        static let chatGroup = "chatgroup"
        static let call = "call"
        static let callGroup = "callgroup"
    }
}
