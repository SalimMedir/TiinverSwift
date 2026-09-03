import Foundation
import UIKit

/// Port de `models/chat/MessagePacket.java` (1016 lignes, module 11) — enveloppe envoyée sur le
/// socket pour un message sortant.
///
/// **Découverte de protocole importante, vérifiée en lisant le fichier en entier (PAS devinée)** :
/// `getPacketJson()` (l'enveloppe RÉELLEMENT émise, `mSocket.emit(ROOM.NEW_MESSAGE, data)`) ne
/// sérialise PAS directement les champs du message — elle enveloppe un DOCUMENT JSON INTERNE
/// (champ `"packet"`, de type STRING) construit par 20 méthodes `get*Pattern()` quasi identiques
/// selon `(chat|group) × (text|graphic|audio|video|photo/gif/sticker) × (isQuoted ? oui : non)` —
/// c'est-à-dire du JSON-dans-une-chaîne-JSON (double encodage), PAS une simple sérialisation Gson
/// du contenu. Consolidé ici en UNE fonction paramétrée (`buildPacketString`) plutôt que 20
/// méthodes dupliquées — même ensemble de champs par combinaison, vérifié champ par champ contre
/// les 20 méthodes originales.
///
/// **Amélioration délibérée, documentée, PAS une divergence silencieuse** : l'original Android
/// construit ce document interne par concaténation de chaînes SANS échappement JSON des valeurs
/// (`"\"message\":\""+message+"\""`) — un message contenant un caractère `"` casserait le JSON
/// produit. Ici, `JSONSerialization` construit le document interne avec un échappement correct.
/// Ceci reste interopérable : le serveur relaie `"packet"` de façon opaque (constaté dans
/// `ChatRepository`/`ChatManager`, jamais parsé côté serveur d'après le flux observé), et tout
/// destinataire (Android ou iOS) qui décode `"packet"` comme du JSON standard décodera un document
/// PLUS SOUVENT valide, jamais moins, qu'avec la concaténation naïve d'origine.
struct MessagePacket {
    var messageId: String?
    var description: String?
    var conversationId: String?
    var groupName: String?
    var groupId: String?
    var token: String?
    var groupType: String?
    var type: String?
    var to: String?
    var from: String?
    var sender: String?
    var receiver: String?
    var object: String?
    var verb: String?
    var message: String?
    var objectUrl: String?
    var thumbnailUrl: String?
    var profile: String?
    var status: String?
    var stamp: String?
    var creationDate: String?
    var deliverTime: String?
    var nikname: String?
    var width: String?
    var height: String?
    var duration: String?
    var imageByte: [UInt8]?
    var quoteDuration: String?
    var quoteMessage: String?
    var quoteTitle: String?
    var quoteObject: String?
    var giftId: String?
    var isQuoted = false

    init() {}

    /// Port de `ChatManager.sendPrivateMessage(Context, MessageLib)` — construit le paquet sortant
    /// depuis un message local (chat 1:1). `from` = nom d'utilisateur COURANT (pas
    /// `mlib.getFrom()`) — reproduit tel quel, l'original ré-attribue délibérément l'expéditeur au
    /// compte connecté plutôt que de faire confiance au champ du `MessageLib` fourni.
    init(fromPrivate mlib: MessageLib, currentUsername: String) {
        self.init()
        conversationId = mlib.conversationId
        giftId = mlib.giftId
        type = mlib.type
        to = mlib.to
        from = currentUsername
        sender = mlib.sender
        receiver = mlib.receiver
        nikname = UserSession.shared.nikname
        messageId = mlib.messageId
        message = mlib.message
        object = mlib.object
        verb = mlib.verb
        objectUrl = mlib.objectUrl
        thumbnailUrl = mlib.thumbnailUri
        height = mlib.height
        width = mlib.width
        duration = mlib.duration
        imageByte = mlib.imageByte
        profile = UserSession.shared.profile
        status = String(mlib.status)
        deliverTime = mlib.deliverTime
        stamp = mlib.stamp
        creationDate = mlib.creationDate
        isQuoted = mlib.isQuoted
        quoteTitle = mlib.quoteTitle
        quoteMessage = mlib.quoteMessage
        quoteObject = mlib.quoteObject
        quoteDuration = mlib.quoteDuration
        if let r = mlib.resource { resource = r }
    }

    /// Port de `ChatManager.sendGroupMessage(Context, MessageLib)`. `sender` = `myId` COURANT
    /// (pas `mlib.getSender()`), `from`/`nikname`/`profile` restent ceux du `MessageLib` fourni —
    /// asymétrie réelle avec `init(fromPrivate:currentUsername:)` reproduite telle quelle (vérifiée
    /// en comparant les deux méthodes Android côte à côte, pas une faute de frappe de portage).
    init(fromGroup mlib: MessageLib, currentNikname: String, myId: String) {
        self.init()
        conversationId = mlib.conversationId
        type = mlib.type
        to = mlib.to
        sender = myId
        receiver = mlib.receiver
        from = mlib.from
        nikname = currentNikname
        messageId = mlib.messageId
        groupId = mlib.groupId
        token = mlib.token
        groupName = mlib.groupName
        message = mlib.message
        object = mlib.object
        verb = mlib.verb
        objectUrl = mlib.objectUrl
        thumbnailUrl = mlib.thumbnailUri
        height = mlib.height
        width = mlib.width
        duration = mlib.duration
        imageByte = mlib.imageByte
        profile = mlib.profile
        status = String(mlib.status)
        deliverTime = mlib.deliverTime
        stamp = mlib.stamp
        creationDate = mlib.stamp
        isQuoted = mlib.isQuoted
        quoteTitle = mlib.quoteTitle
        quoteMessage = mlib.quoteMessage
        quoteObject = mlib.quoteObject
        quoteDuration = mlib.quoteDuration
        description = mlib.description
        if let r = mlib.resource { resource = r }
    }

    /// Port de `ChatManager.deletePrivateMessage(Context, MessageLib)` — construit le paquet de
    /// suppression "pour tout le monde" (chat 1:1). **Asymétrie réelle avec `init(fromPrivate:
    /// currentUsername:)` vérifiée en comparant les deux méthodes Android côte à côte, PAS une
    /// simplification en un seul initialiseur partagé** : ici `sender` = `myId` de la session
    /// COURANTE (`Settings.MYID`), alors que `sendPrivateMessage` utilise `mlib.getSender()` tel
    /// quel ; et `giftId` n'est PAS repris ici (absent des deux côtés de `deletePrivateMessage`,
    /// contrairement à `sendPrivateMessage` qui le porte).
    init(forDeletePrivate mlib: MessageLib, currentUsername: String, myId: String) {
        self.init()
        description = mlib.description
        conversationId = mlib.conversationId
        type = mlib.type
        to = mlib.to
        sender = myId
        receiver = mlib.receiver
        from = currentUsername
        nikname = UserSession.shared.nikname
        messageId = mlib.messageId
        message = mlib.message
        object = mlib.object
        verb = mlib.verb
        objectUrl = mlib.objectUrl
        thumbnailUrl = mlib.thumbnailUri
        height = mlib.height
        width = mlib.width
        duration = mlib.duration
        imageByte = mlib.imageByte
        profile = UserSession.shared.profile
        status = String(mlib.status)
        deliverTime = mlib.deliverTime
        stamp = mlib.stamp
        creationDate = mlib.creationDate
        isQuoted = mlib.isQuoted
        quoteTitle = mlib.quoteTitle
        quoteMessage = mlib.quoteMessage
        quoteObject = mlib.quoteObject
        quoteDuration = mlib.quoteDuration
        if let r = mlib.resource { resource = r }
    }

    /// Port de `ChatManager.deleteGroupMessage(Context, MessageLib)`. Même schéma de champs que
    /// `sendGroupMessage`, sauf `profile` : ici la session COURANTE (`Settings.PROFILE`), alors que
    /// `init(fromGroup:currentNikname:myId:)` reprend `mlib.getProfile()` — asymétrie réelle
    /// vérifiée côte à côte, reproduite telle quelle.
    init(forDeleteGroup mlib: MessageLib, currentNikname: String, myId: String, currentProfile: String) {
        self.init()
        description = mlib.description
        conversationId = mlib.conversationId
        type = mlib.type
        to = mlib.to
        sender = myId
        receiver = mlib.receiver
        from = mlib.from
        nikname = currentNikname
        messageId = mlib.messageId
        groupId = mlib.groupId
        token = mlib.token
        groupName = mlib.groupName
        message = mlib.message
        object = mlib.object
        verb = mlib.verb
        objectUrl = mlib.objectUrl
        height = mlib.height
        width = mlib.width
        duration = mlib.duration
        imageByte = mlib.imageByte
        profile = currentProfile
        status = String(mlib.status)
        deliverTime = mlib.deliverTime
        stamp = mlib.stamp
        creationDate = mlib.stamp
        isQuoted = mlib.isQuoted
        quoteTitle = mlib.quoteTitle
        quoteMessage = mlib.quoteMessage
        quoteObject = mlib.quoteObject
        quoteDuration = mlib.quoteDuration
        if let r = mlib.resource { resource = r }
    }

    /// Port de `resource=android.os.Build.MODEL` — modèle d'appareil, envoyé tel quel côté serveur
    /// (champ informatif, pas un identifiant stable). `UIDevice.current.model` est l'équivalent le
    /// plus proche (ex. "iPhone" — Android `Build.MODEL` donne un nom de modèle précis type
    /// "SM-G991B" quand iOS ne distingue pas les modèles par défaut sans table de correspondance
    /// dédiée ; différence de plateforme documentée, pas un oubli).
    var resource: String = UIDevice.current.model
    /// Port de `versionCode=BuildConfig.VERSION_CODE` — `CFBundleVersion` est l'équivalent iOS.
    var versionCode: Int = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1

    /// Port de `getMessageSize` — longueur du document interne, PAS de l'enveloppe complète.
    var messageSize: Int { buildPacketString().utf8.count }

    /// Port de `getDelivredPacketJson`/`getTypingPacketJson` — mêmes 5 champs pour les deux
    /// (confirmé identique en comparant les deux méthodes Android côte à côte).
    func delivredPacketJSON() -> [String: Any] {
        ["messageId": messageId ?? "", "type": type ?? "", "to": to ?? "", "from": from ?? "", "object": object ?? ""]
    }

    var typingPacketJSON: [String: Any] { delivredPacketJSON() }

    /// Port de `getPacketJson` — enveloppe pour `ROOM.NEW_MESSAGE`/`ROOM.UPDATE_MESSAGE`/etc.
    /// (chat 1:1).
    func packetJSON() -> [String: Any] {
        [
            "messageId": messageId ?? "", "type": type ?? "", "to": to ?? "",
            "from": from ?? "", "messageSize": String(messageSize), "creationDate": stamp ?? "",
            "deliver_time": deliverTime ?? "", "packet": buildPacketString(),
        ]
    }

    /// Port de `getPacketForGroupJson` — enveloppe pour `ROOM.NEW_GROUP_MESSAGE`/etc.
    func packetForGroupJSON() -> [String: Any] {
        [
            "messageId": messageId ?? "", "groupId": groupId ?? "", "receiver": token ?? "",
            "messageSize": String(messageSize), "creationDate": stamp ?? "",
            "deliver_time": deliverTime ?? "", "packet": buildPacketString(),
        ]
    }

    /// Port CONSOLIDÉ des 20 méthodes `get*Pattern()` — dispatch `type` (chat/groupe) × `object`
    /// (voir switch ci-dessous, reproduit à l'identique de `getPacketString`), champs déterminés
    /// par `fields(for:isGroup:)`.
    func buildPacketString() -> String {
        let isGroup = type == ChatType.group.wireValue
        var fields = commonFields(isGroup: isGroup)
        fields.merge(objectFields()) { _, new in new }
        if isQuoted {
            fields.merge(quoteFields()) { _, new in new }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }

    /// Port des champs communs à TOUS les patrons — `messageId`/`conversationId`/`type`/`to`/
    /// `sender`/`receiver`/`from`/`nikname`/`verb`/`object`/`profile`/`status`/`stamp`/`resource`/
    /// `versionCode`/`isQuoted`, plus `groupId`/`token`/`groupType`/`groupName`/`description` en
    /// mode groupe (vérifié : les patrons groupe conservent AUSSI `to`/`sender`/`receiver`/`from`,
    /// pas remplacés par les champs de groupe, voir `getTextGroupMessageNoquotedPattern`).
    private func commonFields(isGroup: Bool) -> [String: Any] {
        var f: [String: Any] = [
            "messageId": messageId ?? "", "conversationId": conversationId ?? "", "type": type ?? "",
            "to": to ?? "", "sender": sender ?? "", "receiver": receiver ?? "", "from": from ?? "",
            "nikname": nikname ?? "", "verb": verb ?? "", "object": object ?? "", "profile": profile ?? "",
            "status": status ?? "", "stamp": stamp ?? "", "resource": resource,
            "versionCode": String(versionCode), "isQuoted": String(isQuoted),
        ]
        if isGroup {
            f["groupId"] = groupId ?? ""
            f["token"] = token ?? ""
            f["groupType"] = groupType ?? ""
            f["groupName"] = groupName ?? ""
            f["description"] = description ?? ""
        }
        // **Corrigé (2026-09-04, CHAT_CONSISTENCY_REVIEW.md)** — la propriété `giftId` était déjà
        // affectée (`init(fromPrivate:)`) mais jamais sérialisée : absente de TOUS les messages
        // sortants, gift compris. Port exact de `MessagePacket.java` : `giftId` n'apparaît QUE dans
        // `getTextPrivateMessageNoquotedPattern`/`...Quoted` (`:439-459`/`:461-...`) — jamais dans
        // les 2 patrons groupe (`getTextGroupMessage...`, aucune occurrence de `giftId` dans les
        // deux), ni dans les patrons dédiés audio/vidéo/photo-gif-sticker (aucune occurrence non
        // plus, ces 3 objets ont chacun leur propre patron sans ce champ) — mais présent pour
        // `text`/`gift`/`information`/`missedvoicecall`/tout objet non listé, qui retombent TOUS sur
        // le patron texte côté Android (`getPacketString`, `default: return
        // getTextPrivateMessageNoquotedPattern()`). Valeur par défaut `"null"` (chaîne, pas JSON
        // null) : `Arrays`/concaténation Java d'un champ `null` non initialisé produit littéralement
        // le texte `"null"` — confirmé par l'exemple réel capturé (`"giftId":"null"`).
        if !isGroup, !["audio", "video", "photo", "gif", "sticker"].contains(object ?? "") {
            f["giftId"] = giftId ?? "null"
        }
        return f
    }

    /// Port des champs spécifiques à `object` — `text`/`gift`/`information`/`missedvoicecall` →
    /// `message` seul ; `graphic` → `MgGraphic` (= `message`, déjà sérialisé, voir
    /// `getGraphicMessageJsonPacket`) ; `audio` → `message`+`object_url`+`duration` ; `video` →
    /// `message`+`object_url`+`thumbnail_url`+`image_byte`+`width`+`height`+`duration` ;
    /// `photo`/`gif`/`sticker` → `message`+`object_url`+`image_byte`+`width`+`height`.
    private func objectFields() -> [String: Any] {
        switch object {
        case "graphic":
            return ["MgGraphic": message ?? ""]
        case "audio":
            return ["message": message ?? "", "object_url": objectUrl ?? "", "duration": duration ?? ""]
        case "video":
            return [
                "message": message ?? "", "object_url": objectUrl ?? "", "thumbnail_url": thumbnailUrl ?? "",
                "image_byte": imageByteWireValue, "width": width ?? "", "height": height ?? "",
                "duration": duration ?? "",
            ]
        case "photo", "gif", "sticker":
            return [
                "message": message ?? "", "object_url": objectUrl ?? "", "image_byte": imageByteWireValue,
                "width": width ?? "", "height": height ?? "",
            ]
        default:
            return ["message": message ?? ""]
        }
    }

    private func quoteFields() -> [String: Any] {
        ["quoteTitle": quoteTitle ?? "", "quoteMessage": quoteMessage ?? "", "quoteObject": quoteObject ?? "", "quoteDuration": quoteDuration ?? ""]
    }

    /// Port de `"\"image_byte\":"+ Arrays.toString(image_byte)` — **remarqué en relisant
    /// attentivement la concaténation** : contrairement à TOUS les autres champs (encadrés de
    /// `\"..\"`, donc des chaînes JSON), celui-ci n'a PAS de guillemets autour de
    /// `Arrays.toString(...)` — le texte produit (`[1, 2, 3]` ou, si `image_byte` est `null`,
    /// littéralement `null` — `Arrays.toString(null)` renvoie la chaîne `"null"`, insérée SANS
    /// guillemets) forme donc un LITTÉRAL JSON (tableau de nombres, ou `null`), pas une chaîne.
    /// Reproduit en insérant un vrai `[Int]`/`NSNull` dans le dictionnaire plutôt qu'une `String`
    /// wire, pour que `JSONSerialization` produise le même littéral (pas de guillemets autour).
    private var imageByteWireValue: Any {
        guard let bytes = imageByte else { return NSNull() }
        return bytes.map { Int($0) }
    }
}
