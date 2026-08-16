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

    /// Décodage tolérant (2026-08-16) : `ChatRepository` décode `[MessageLib]` via
    /// `try? JSONDecoder().decode(...)` — si UN SEUL message du tableau a un champ numérique
    /// envoyé en chaîne par le backend (même cause racine que `FeedActivity`/`User`, voir
    /// `LenientDecoding.swift`), le décodage de TOUT le tableau échoue et `try?` retombe
    /// silencieusement sur `nil` → historique de conversation vide, symptôme identique à un
    /// Feed vide. `= 0`/`= false` sur ces propriétés ne sert PAS de repli au décodage (piège Swift
    /// documenté — seul l'initialiseur memberwise en bénéficie, jamais `Decodable` synthétisé).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try container.decodeIfPresent(String.self, forKey: .messageId)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        sender = try container.decodeIfPresent(String.self, forKey: .sender)
        receiver = try container.decodeIfPresent(String.self, forKey: .receiver)
        nikname = try container.decodeIfPresent(String.self, forKey: .nikname)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        giftId = try container.decodeIfPresent(String.self, forKey: .giftId)
        verb = try container.decodeIfPresent(String.self, forKey: .verb)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        objectUrl = try container.decodeIfPresent(String.self, forKey: .objectUrl)
        thumbnailUri = try container.decodeIfPresent(String.self, forKey: .thumbnailUri)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        localFileDirection = try container.decodeIfPresent(String.self, forKey: .localFileDirection)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        status = container.decodeLenientIntIfPresent(forKey: .status) ?? 0
        vu = try container.decodeIfPresent(String.self, forKey: .vu)
        regroupage = try container.decodeIfPresent(String.self, forKey: .regroupage)
        stamp = try container.decodeIfPresent(String.self, forKey: .stamp)
        deliverTime = try container.decodeIfPresent(String.self, forKey: .deliverTime)
        resource = try container.decodeIfPresent(String.self, forKey: .resource)
        versionCode = container.decodeLenientIntIfPresent(forKey: .versionCode) ?? 0
        isQuoted = container.decodeLenientBoolIfPresent(forKey: .isQuoted) ?? false
        quoteMessage = try container.decodeIfPresent(String.self, forKey: .quoteMessage)
        quoteTitle = try container.decodeIfPresent(String.self, forKey: .quoteTitle)
        quoteObject = try container.decodeIfPresent(String.self, forKey: .quoteObject)
        quoteDuration = try container.decodeIfPresent(String.self, forKey: .quoteDuration)
        width = try container.decodeIfPresent(String.self, forKey: .width)
        height = try container.decodeIfPresent(String.self, forKey: .height)
        duration = try container.decodeIfPresent(String.self, forKey: .duration)
        imageByte = try container.decodeIfPresent([UInt8].self, forKey: .imageByte)
        groupType = try container.decodeIfPresent(String.self, forKey: .groupType)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        token = try container.decodeIfPresent(String.self, forKey: .token)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        mgGraphic = try container.decodeIfPresent(String.self, forKey: .mgGraphic)
        senderFcmId = try container.decodeIfPresent(String.self, forKey: .senderFcmId)
        receiverFcmId = try container.decodeIfPresent(String.self, forKey: .receiverFcmId)
        creationDate = try container.decodeIfPresent(String.self, forKey: .creationDate)
        isFileUploaded = container.decodeLenientIntIfPresent(forKey: .isFileUploaded) ?? 0
        isFileDownloaded = container.decodeLenientIntIfPresent(forKey: .isFileDownloaded) ?? 0
        userId = container.decodeLenientStringIfPresent(forKey: .userId)
        share = try container.decodeIfPresent(String.self, forKey: .share)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        lucrative = container.decodeLenientIntIfPresent(forKey: .lucrative) ?? 0
        price = container.decodeLenientIntIfPresent(forKey: .price) ?? 0
        belongsToCurrentUser = container.decodeLenientBoolIfPresent(forKey: .belongsToCurrentUser) ?? false
    }

    /// Port des constantes `MessageLib.CHAT`/`CHATGROUP`/`CALL`/`CALLGROUP`.
    enum WireType {
        static let chat = "chat"
        static let chatGroup = "chatgroup"
        static let call = "call"
        static let callGroup = "callgroup"
    }
}
