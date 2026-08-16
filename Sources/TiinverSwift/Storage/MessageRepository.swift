import CoreData
import Foundation

/// Port de la couche persistance de `messagerie/ui/ChatManager.java` (1508 lignes, lu en entier) —
/// écrit/lit `wk_messages` (`MessageEntity`, module 2). Le reste de `ChatManager.java` (construction
/// de `MessagePacket` depuis un `MessageLib`, notifications locales, gestion des appels manqués) est
/// couvert par `MessagePacket.swift`/`ChatRepository.swift`/`LocalNotificationBuilder.swift
/// (modules 4/11) plutôt que reproduit ici comme une seule classe monolithique — `ChatManager`
/// mélangeait délibérément ces responsabilités côté Android (un seul `Context`/`Socket` partagé),
/// la séparation ici suit les conventions déjà établies dans ce portage (`RosterRepository`,
/// `NotiRepository`).
///
/// **Découverte importante (relecture complète de `ChatManager.addGroupMessage`, module 11,
/// 2026-08-12)** : contrairement à ce que suggère son nom, `GroupMessageEntity`/`wk_gp_messages`
/// (module 2) N'EST PAS la table utilisée pour la messagerie de groupe réelle. Vérifié par grep
/// EXHAUSTIF sur tout `com.tiinver` : `wk_gp_messages` est créée par `Dbase.java` et `StubProvider`
/// sait la manipuler (cas générique du `ContentProvider`), mais AUCUNE constante d'URI ni AUCUN
/// appelant dans toute l'app n'insère/lit jamais dedans — table MORTE. `ChatManager.addGroupMessage`
/// (ligne 1190, lu en entier) écrit en réalité dans `infoContract.MSG_URI`, c'est-à-dire LA MÊME
/// table `wk_messages` que les messages privés (`MessageEntity`), différenciés uniquement par le
/// champ `type` ("chatgroup" vs "chat") — exactement comme `addMessage`. `addGroupMessage` ci-dessous
/// cible donc `messages` (pas `groupMessages`), pas une erreur de portage.
final class MessageRepository {
    private let messages: CoreDataRepository<MessageEntity>
    /// Conservé (modélise fidèlement `wk_gp_messages`, module 2) mais CONFIRMÉ INUTILISÉ par le
    /// code Android vivant — voir la note de tête de fichier. Aucune méthode de cette classe n'écrit
    /// dedans, intentionnellement.
    private let groupMessages: CoreDataRepository<GroupMessageEntity>
    private let roster: RosterRepository

    init(stack: CoreDataStack = .shared, roster: RosterRepository = RosterRepository()) {
        self.messages = CoreDataRepository(stack: stack)
        self.groupMessages = CoreDataRepository(stack: stack)
        self.roster = roster
    }

    /// Port de la branche `wk_messages` de `transportDataBackground.deleteaccount()` — voir
    /// `LocalDataPurger.swift`. `groupMessages` (`wk_gp_messages`) purgée aussi par cohérence bien
    /// que confirmée table MORTE côté Android (voir note de tête de fichier) — vide en pratique.
    func purgeAll() async throws {
        try await messages.delete(predicate: nil)
        try await groupMessages.delete(predicate: nil)
    }

    /// Port de `isMessageExist` — `wk_messages` uniquement, comme l'original (`infoContract.
    /// MSG_URI`), pas de vérification `wk_gp_messages` correspondante côté Android non plus.
    func messageExists(messageId: String) async throws -> Bool {
        try await messages.count(predicate: NSPredicate(format: "messageId == %@", messageId)) > 0
    }

    /// Port de `insertTextMessage` — écho local immédiat d'un message envoyé par l'utilisateur
    /// courant (`status=0`, `vu=false`, avant tout accusé de réception serveur). Met à jour
    /// `wk_roster` avec `isFromServer=false` (pas d'incrément `unreadCount`, l'expéditeur voit son
    /// propre message immédiatement) — vérifié : `insertTextMessage` appelle `RosterManager.
    /// updateRoster(context, message, false)` juste après l'insertion (ligne 497).
    func insertTextMessage(_ message: MessageLib) async throws {
        try await messages.insert { entity in
            Self.apply(message, to: entity, status: 0, vu: "false")
        }
        try await roster.updateRoster(message: message, isFromServer: false)
    }

    /// Port de `insertFileMessage` — variante `insertTextMessage` pour les objets nécessitant un
    /// envoi de fichier (`isFileUploaded` distingue le message texte immédiat du média encore en
    /// cours d'upload, voir `ChatManager.sendMessageFromCursor`). `thumbnailUri` sourcé du champ
    /// wire `thumbnailUri` (`message.getThumbnailUri()` ligne 519) — PAS `thumbnail_url`, à la
    /// différence de `addMessage`/`addGroupMessage` ci-dessous (vérifié champ par champ, vraie
    /// divergence Android entre les 2 chemins d'insertion, pas unifiée ici).
    func insertFileMessage(_ message: MessageLib) async throws {
        try await messages.insert { entity in
            Self.apply(message, to: entity, status: 0, vu: "false")
            entity.thumbnailUri = message.thumbnailUri
            entity.isFileUploaded = Int64(message.isFileUploaded)
        }
        try await roster.updateRoster(message: message, isFromServer: false)
    }

    /// Port de `addMessage(MessageLib)` (ligne 1089, lu en entier) — réception d'un message serveur
    /// (chat 1:1). Reproduit : (1) déduplication par `messageId`, (2) `conversationId` RECALCULÉ
    /// localement depuis `receiver`/`sender` (PAS le `conversationId` envoyé par le serveur), (3)
    /// contenu `message` substitué par `MgGraphic` si `object == "graphic"`, (4) `thumbnailUri`
    /// sourcé du champ wire `thumbnail_url` (`cv.put("thumbnail_uri", meta.getThumbnail_url())`
    /// ligne 1115 — PAS `thumbnailUri`, contrairement à `insertFileMessage`), (5) `wk_roster` mis à
    /// jour avec `isFromServer=true` (incrémente `unreadCount`, ligne 1138 `dbInsertMessageCrossPoint
    /// (..., true)`).
    ///
    /// **Branche `verb == "deletemessage"` sur message déjà existant DÉLIBÉRÉMENT NON REPRODUITE** —
    /// bug Android confirmé par analyse de flot de contrôle : le code source (lignes 1160-1170) a
    /// `} else if (!isMessageExist(messageId) && verb.equals("deletemessage")) {...}` — cette
    /// branche `else` n'est atteinte QUE si `isMessageExist(messageId) == true` (négation de la
    /// condition du premier `if`), auquel cas `!isMessageExist(messageId)` vaut FAUX : la
    /// sous-condition `&&` est donc TOUJOURS fausse, la branche est du code MORT, jamais exécutée en
    /// pratique. Reproduire cette branche comme "atteignable" (ce qu'une première version de ce
    /// fichier faisait, à tort) aurait été une amélioration silencieuse non documentée par rapport à
    /// l'original. La suppression réelle d'un message existant transite par un chemin SÉPARÉ côté
    /// Android : les listeners socket `ON_DELETE_PRIVATE_MESSAGE`/`ON_DELETE_GROUP_MESSAGE`
    /// (`ChatRepository.onDeleteMessage` → `AsyncDeleteMessage` → `deleteMessageForEveryOne`), déjà
    /// câblé dans `ChatRepository.swift.handleDeleteMessage`.
    @discardableResult
    func addMessage(_ meta: MessageLib) async throws -> MessagePacket? {
        let messageId = meta.messageId ?? "error"
        guard !(try await messageExists(messageId: messageId)) else { return nil }

        let conversationId = ConversationIdGenerator.conversationId(
            currentUser: meta.receiver ?? "", remoteUser: meta.sender ?? "")
        var stored = meta
        stored.conversationId = conversationId
        stored.username = meta.from
        stored.message = meta.object == "graphic" ? meta.mgGraphic : meta.message

        try await messages.insert { entity in
            Self.apply(stored, to: entity, status: 1, vu: "false")
            entity.thumbnailUri = meta.thumbnailUrl
            entity.stamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            entity.regroupage = meta.from
        }
        try await roster.updateRoster(message: stored, isFromServer: true)

        var packet = MessagePacket()
        packet.to = meta.from
        packet.from = meta.to
        packet.messageId = messageId
        packet.type = meta.type
        packet.object = meta.object
        return packet
    }

    /// Port de `addGroupMessage(MessageLib, boolean)` (ligne 1190, lu en entier) — réception d'un
    /// message de GROUPE, écrit dans `wk_messages`/`MessageEntity` (voir note de tête de fichier,
    /// PAS `wk_gp_messages`). Condition d'insertion reproduite à l'identique : message inexistant ET
    /// `groupId`/`token` tous deux non-nil. `conversationId` = `ConversationIdGenerator.
    /// groupConversationId(myId, groupId)`. `thumbnailUri` sourcé de `thumbnail_url`, mais
    /// SEULEMENT si non vide (`if (thumbUrl != null && !thumbUrl.isEmpty())`, ligne 1218 — sinon la
    /// colonne reste intacte, reproduit en laissant `entity.thumbnailUri` non touché plutôt que mis
    /// à `nil`).
    ///
    /// **Non reproduit ici, gap documenté** : les branches `verb == "deleteMember"`/`"addMember"`
    /// (lignes 1263-1281 — suppression locale d'un membre, flags `USER_ROOM_MEMBER`, émission
    /// `leaveRoom`) sont des effets de bord de GESTION DE GROUPE, hors périmètre de la couche
    /// persistance des messages ; à porter avec le module Groupes (pas encore atteint). La
    /// notification push locale (`MyFirebaseMessagingService.notificationShow`, branche
    /// `verb == "post"`) est également hors périmètre (module notifications).
    @discardableResult
    func addGroupMessage(_ meta: MessageLib) async throws -> MessagePacket? {
        let messageId = meta.messageId ?? "error"
        guard let groupId = meta.groupId, meta.token != nil else { return nil }
        guard !(try await messageExists(messageId: messageId)) else { return nil }

        let conversationId = ConversationIdGenerator.groupConversationId(currentUser: UserSession.shared.myId ?? "", remoteUser: groupId)
        var stored = meta
        stored.conversationId = conversationId
        stored.username = meta.from
        stored.message = meta.object == "graphic" ? meta.mgGraphic : meta.message

        try await messages.insert { entity in
            Self.apply(stored, to: entity, status: 1, vu: "false")
            if let thumbUrl = meta.thumbnailUrl, !thumbUrl.isEmpty {
                entity.thumbnailUri = thumbUrl
            }
            entity.stamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            entity.regroupage = meta.token
        }
        try await roster.updateRoster(message: stored, isFromServer: true)

        guard meta.verb == "post" else { return nil }
        var packet = MessagePacket()
        packet.to = meta.from
        packet.from = meta.to
        packet.messageId = messageId
        packet.type = meta.type
        packet.object = meta.object
        return packet
    }

    /// Port de `deleteMessageForEveryOne` — si le message existe déjà, le remplace par un
    /// "tombstone" (`message`/`verb`/`object = "deletemessage"`, `vu = true`) plutôt que de
    /// supprimer la ligne — reproduit à l'identique (permet d'afficher "message supprimé" côté UI,
    /// pas encore portée). Sinon (message inconnu localement, l'annonce de suppression est arrivée
    /// avant le message lui-même), insère un texte de repli via `insertTextMessageFromServer`
    /// (`isFromServer=true`) ou `insertTextMessage` (`isFromServer=false`) — les DEUX méthodes
    /// Android existent réellement et diffèrent (`object`/`verb` figés à `"text"`/`"post"`, `username`
    /// sourcé de `getFrom()` plutôt que `getUsername()`, plusieurs champs omis — voir
    /// `insertTextMessageFromServer` ci-dessous), pas une simplification à une seule méthode.
    func deleteMessageForEveryOne(_ message: MessageLib, isFromServer: Bool) async throws {
        let deliverTime = String(Int64(Date().timeIntervalSince1970 * 1000))
        if try await messageExists(messageId: message.messageId ?? "") {
            try await messages.update(predicate: NSPredicate(format: "messageId == %@", message.messageId ?? "")) { entity in
                entity.conversationId = message.conversationId
                entity.message = "deletemessage"
                entity.verb = "deletemessage"
                entity.object = "deletemessage"
                entity.vu = "true"
                entity.status = "0"
                entity.deliverTime = deliverTime
                entity.isQuoted = "false"
            }
        } else if isFromServer {
            try await insertTextMessageFromServer(message)
        } else {
            try await insertTextMessage(message)
        }
    }

    /// Port de `insertTextMessageFromServer` (ligne 429, lu en entier) — repli texte utilisé
    /// UNIQUEMENT par `deleteMessageForEveryOne(isFromServer: true)` ci-dessus quand une suppression
    /// arrive pour un message jamais reçu localement. **Champs figés/différents de
    /// `insertTextMessage`, vérifiés ligne par ligne, PAS une erreur de portage** : `object`/`verb`
    /// codés en dur à `"text"`/`"post"` (ignorant `message.object`/`message.verb` réels — le
    /// contenu affiché sera donc toujours traité comme un texte simple, jamais comme un média,
    /// même si le message original en était un) ; `username = message.from` (pas `.username`) ;
    /// `versionCode`/`width`/`height`/`duration`/`resource`/`isFileUploaded` omis (colonnes
    /// laissées à leur défaut Core Data, comme l'original omet ces clés de `ContentValues`).
    private func insertTextMessageFromServer(_ message: MessageLib) async throws {
        try await messages.insert { entity in
            entity.messageId = Int64(message.messageId ?? "") ?? 0
            entity.conversationId = message.conversationId
            entity.usernameFrom = message.from
            entity.usernameTo = message.to
            entity.type = message.type
            entity.message = message.message
            entity.giftId = message.giftId
            entity.token = message.token
            entity.groupType = message.groupType
            entity.groupId = Int64(message.groupId ?? "") ?? 0
            entity.username = message.from
            entity.nikname = message.nikname
            entity.groupName = message.groupName
            entity.object = "text"
            entity.verb = "post"
            entity.sender = Int64(message.sender ?? "") ?? 0
            entity.receiver = Int64(message.receiver ?? "") ?? 0
            entity.status = "0"
            entity.vu = "false"
            entity.profile = message.profile
            entity.regroupage = message.from
            entity.stamp = message.stamp
            entity.deliverTime = message.deliverTime
            entity.isQuoted = String(message.isQuoted)
            entity.quoteMessage = message.quoteMessage
            entity.quoteTitle = message.quoteTitle
            entity.quoteObject = message.quoteObject
            entity.quoteDuration = message.quoteDuration
        }
        try await roster.updateRoster(message: message, isFromServer: false)
    }

    /// Port de `deleteMessageForme` — suppression LOCALE uniquement (pas de notification au reste
    /// de la conversation), `wk_messages` seulement comme l'original.
    func deleteMessageForMe(messageId: String) async throws {
        try await messages.delete(predicate: NSPredicate(format: "messageId == %@", messageId))
    }

    /// Port de `updateMessageStatus` — met à jour `status` sur `wk_messages` ET `wk_roster` (les
    /// deux dans l'original, `context.getContentResolver().update` appelé sur `MSG_URI` PUIS
    /// `ROSTER_URI` avec le même `ContentValues`, lignes 1180-1183).
    func updateStatus(messageId: String, status: Int) async throws {
        try await messages.update(predicate: NSPredicate(format: "messageId == %@", messageId)) { entity in
            entity.status = String(status)
        }
        try await roster.update(predicate: NSPredicate(format: "messageId == %@", messageId)) { entity in
            entity.status = Int64(status)
        }
    }

    /// Port de `DownloadReceiver.getDownloadedFilePath` (GAP-003, 2026-08-16) —
    /// `ContentValues{isFileDownloaded=1, object_url=<chemin local>}` appliqué à `wk_messages`
    /// après un téléchargement réussi (voir `ChatViewModel.requestDownload`). Contrairement à
    /// l'upload, `object_url` est ici RÉÉCRIT avec le chemin LOCAL (Android : `Uri.fromFile(file)`,
    /// même colonne que l'URL distante — un seul champ sert aux deux, fidèle à l'original).
    func updateFileDownloaded(messageId: String, localURL: URL) async throws {
        try await messages.update(predicate: NSPredicate(format: "messageId == %@", messageId)) { entity in
            entity.objectUrl = localURL.absoluteString
            entity.isFileDownloaded = 1
        }
    }

    /// Port de `UploadFileOrDataService.saveMediaUrls`/`uploadMediaToBunny` (GAP-004, 2026-08-15) —
    /// `ContentValues{object_url, isFileUploaded=1[, thumbnail_uri]}` appliqué à `wk_messages`
    /// après un upload BunnyCDN réussi (voir `ChatMediaUploadService`). `thumbnailUri` optionnel :
    /// seule la branche vidéo en fournit un (`saveMediaUrls`), la branche générique
    /// (`uploadMediaToBunny`) ne touche QUE `object_url`/`isFileUploaded`, `thumbnailUri` reste
    /// intact si `nil` ici (comme Android ne l'inclut pas dans son `ContentValues` pour ce cas).
    func updateFileUploaded(messageId: String, objectUrl: String, thumbnailUri: String?) async throws {
        try await messages.update(predicate: NSPredicate(format: "messageId == %@", messageId)) { entity in
            entity.objectUrl = objectUrl
            entity.isFileUploaded = 1
            if let thumbnailUri { entity.thumbnailUri = thumbnailUri }
        }
    }

    /// Port de `ChatFragmentTest.onCreateLoader`/`displayMessageOnInicialPage`/
    /// `displayMoreMessageOnScroll` (les 3, lus en entier) — CursorLoader `MSG_URI` filtré
    /// `conversationId=?`, trié `stamp DESC`, paginé `LIMIT 100 OFFSET n`. `belongsToCurrentUser`
    /// recalculé ici (`currentUsername.equals(usernameFrom)`), PAS lu depuis une colonne stockée —
    /// fidèle à l'original qui recalcule aussi ce champ à chaque page plutôt que de le persister.
    /// Retourné trié PAR ORDRE CHRONOLOGIQUE croissant (le plus ancien en premier) — l'inversion
    /// `moveToLast()`/`moveToPrevious()` vs `moveToNext()` des deux méthodes Android d'origine
    /// produit le MÊME ordre final dans les deux cas, juste construit différemment ; l'appelant
    /// (`ChatViewModel`) décide d'ajouter en tête ou en queue de la liste affichée.
    func page(conversationId: String, limit: Int, offset: Int, currentUsername: String) async throws -> [MessageLib] {
        let predicate = NSPredicate(format: "conversationId == %@", conversationId)
        let sort = [NSSortDescriptor(key: "stamp", ascending: false)]
        let rows = try await messages.query(predicate: predicate, sortDescriptors: sort, limit: limit, offset: offset)
        return rows.map { Self.toMessageLib($0, currentUsername: currentUsername) }.reversed()
    }

    private static func toMessageLib(_ entity: MessageEntity, currentUsername: String) -> MessageLib {
        var mlib = MessageLib()
        mlib.messageId = entity.messageId == 0 ? nil : String(entity.messageId)
        mlib.conversationId = entity.conversationId
        mlib.from = entity.usernameFrom
        mlib.to = entity.usernameTo
        mlib.nikname = entity.nikname
        mlib.username = entity.username
        mlib.groupName = entity.groupName
        mlib.groupId = entity.groupId == 0 ? nil : String(entity.groupId)
        mlib.token = entity.token
        mlib.groupType = entity.groupType
        mlib.message = entity.message
        mlib.giftId = entity.giftId
        mlib.object = entity.object
        mlib.objectUrl = entity.objectUrl
        mlib.localFileDirection = entity.localFileDirection
        mlib.thumbnailUri = entity.thumbnailUri
        mlib.isFileUploaded = Int(entity.isFileUploaded)
        mlib.isFileDownloaded = Int(entity.isFileDownloaded)
        mlib.sender = entity.sender == 0 ? nil : String(entity.sender)
        mlib.receiver = entity.receiver == 0 ? nil : String(entity.receiver)
        mlib.verb = entity.verb
        mlib.status = Int(entity.status ?? "0") ?? 0
        mlib.resource = entity.resource
        mlib.deliverTime = entity.deliverTime
        mlib.profile = entity.profile
        mlib.type = entity.type
        mlib.isQuoted = entity.isQuoted == "true"
        mlib.quoteMessage = entity.quoteMessage
        mlib.quoteTitle = entity.quoteTitle
        mlib.quoteObject = entity.quoteObject
        mlib.quoteDuration = entity.quoteDuration
        mlib.width = entity.width
        mlib.height = entity.height
        mlib.duration = entity.duration
        mlib.description = entity.messageDescription
        mlib.regroupage = entity.regroupage
        mlib.stamp = entity.stamp
        mlib.versionCode = Int(entity.versionCode)
        mlib.belongsToCurrentUser = (entity.usernameFrom == currentUsername)
        return mlib
    }

    // MARK: - Mapping commun MessageLib -> MessageEntity

    private static func apply(_ message: MessageLib, to entity: MessageEntity, status: Int, vu: String) {
        entity.messageId = Int64(message.messageId ?? "") ?? 0
        entity.conversationId = message.conversationId
        entity.usernameFrom = message.from
        entity.usernameTo = message.to
        entity.type = message.type
        entity.message = message.message
        entity.giftId = message.giftId
        entity.token = message.token
        entity.groupType = message.groupType
        entity.groupName = message.groupName
        entity.nikname = message.nikname
        entity.username = message.username
        entity.groupId = Int64(message.groupId ?? "") ?? 0
        entity.messageDescription = message.description
        entity.sender = Int64(message.sender ?? "") ?? 0
        entity.receiver = Int64(message.receiver ?? "") ?? 0
        entity.senderFcmId = message.senderFcmId
        entity.receiverFcmId = message.receiverFcmId
        entity.object = message.object
        entity.objectUrl = message.objectUrl
        entity.localFileDirection = message.localFileDirection
        // `thumbnailUri` (colonne) N'EST PAS mappée ici : sa source wire diffère selon l'appelant
        // (`thumbnailUri` pour `insertFileMessage`, `thumbnail_url` pour `addMessage`/
        // `addGroupMessage` — vérifié champ par champ dans `ChatManager.java`), positionnée
        // explicitement par chaque méthode appelante plutôt que génériquement ici.
        entity.regroupage = message.regroupage
        entity.status = String(status)
        entity.vu = vu
        entity.profile = message.profile
        entity.isFileUploaded = Int64(message.isFileUploaded)
        entity.isFileDownloaded = Int64(message.isFileDownloaded)
        entity.resource = message.resource
        entity.versionCode = Int64(message.versionCode)
        entity.isQuoted = String(message.isQuoted)
        entity.quoteMessage = message.quoteMessage
        entity.quoteTitle = message.quoteTitle
        entity.quoteObject = message.quoteObject
        entity.quoteDuration = message.quoteDuration
        entity.deliverTime = message.deliverTime
        entity.duration = message.duration
        entity.height = message.height
        entity.width = message.width
        entity.stamp = message.stamp
        // `imageByte` NON mappé ici : `MessageEntity.imageByte` (module 2) est typé `String`
        // (probablement une empreinte/URI locale plutôt que les octets bruts, l'usage exact de
        // cette colonne n'a pas été retrouvé en lisant `ChatManager.java`) alors que
        // `MessageLib.imageByte` (ce fichier) est un vrai `[UInt8]` décodé du JSON serveur —
        // conversion différée plutôt que devinée, à trancher en portant l'écran de chat
        // (`MessageListAdapter`/`ChatFragmentTest`, pas encore lus).
    }
}
