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
    private let stack: CoreDataStack
    private let messages: CoreDataRepository<MessageEntity>
    /// Conservé (modélise fidèlement `wk_gp_messages`, module 2) mais CONFIRMÉ INUTILISÉ par le
    /// code Android vivant — voir la note de tête de fichier. Aucune méthode de cette classe n'écrit
    /// dedans, intentionnellement.
    private let groupMessages: CoreDataRepository<GroupMessageEntity>
    private let roster: RosterRepository
    /// **Ajouté le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-070, Phase B P1-29)** — voir la
    /// doc de `SerialTaskQueue` et d'`addMessage`/`addGroupMessage` ci-dessous pour le raisonnement
    /// complet. Sérialise le couple vérifier-si-existe + insérer, seul point protégé par ce
    /// correctif (portée volontairement réduite, voir doc).
    private let insertSerializer = SerialTaskQueue()

    init(stack: CoreDataStack = .shared, roster: RosterRepository = RosterRepository()) {
        self.stack = stack
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
    ///
    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-070, Phase B P1-29)** — le
    /// couple `messageExists`+`insert` n'était protégé par AUCUN verrou : deux événements socket
    /// portant le MÊME `messageId` (redélivrance serveur après reconnexion, scénario réaliste)
    /// pouvaient chacun passer le `guard !messageExists` avant qu'aucun des deux n'ait terminé son
    /// `insert` — Core Data n'a aucune contrainte d'unicité sur `messageId` pour rattraper la
    /// course, produisant potentiellement 2 lignes `MessageEntity` pour le même message (bulle
    /// dupliquée persistante). Fidèle à Android : `ChatManager.addMessage` est `synchronized`, et
    /// le pipeline entier (1 thread de décodage + 1 Runnable atomique sur le Main Looper) garantit
    /// qu'un événement est traité intégralement avant le suivant. Désormais sérialisé via
    /// `insertSerializer` (voir sa doc pour la raison d'un utilitaire dédié plutôt qu'un simple
    /// `actor`, vulnérable à sa propre réentrance ici).
    ///
    /// **Portée délibérément réduite** : seul le risque de DOUBLON EN BASE (le plus sévère des 2
    /// impacts identifiés) est corrigé. L'ordre d'affichage entre 2 messages arrivés en rafale
    /// (l'autre impact cité) N'EST PAS traité ici — nécessiterait de sérialiser TOUT le pipeline
    /// d'événements socket (newMessage/newGroupMessage/onDeleteMessage/etc., pas seulement la
    /// persistance) ou de trier `ChatViewModel.items` par `stamp` à chaque insertion, un chantier
    /// plus large touchant l'architecture de dispatch temps réel — risque cosmétique mineur,
    /// auto-corrigé à la prochaine réouverture de la conversation (`loadInitial()` trie par
    /// `stamp`), documenté plutôt que deviné.
    @discardableResult
    func addMessage(_ meta: MessageLib) async throws -> MessagePacket? {
        try await insertSerializer.run { [self] in
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
    /// **Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-039, Phase B P2)** — les branches
    /// `verb == "deleteMember"`/`"addMember"` (`ChatManager.java:1330-1348`) sont des effets de bord
    /// socket/préférences (émission `leaveRoom`, flag `USER_ROOM_MEMBER`), hors du périmètre de
    /// CETTE couche persistance pure — câblées côté `ChatRepository.handleNewMessage` (couche
    /// Realtime, seule à posséder l'accès socket), voir ce fichier pour le détail complet
    /// (émission `leaveRoom` reproduite, suppression de ligne "USER_URI" locale et flag
    /// `USER_ROOM_MEMBER` délibérément NON portés — aucun équivalent local/code mort à effet nul,
    /// justifié en détail là-bas). La notification push locale
    /// (`MyFirebaseMessagingService.notificationShow`, branche `verb == "post"`) reste hors
    /// périmètre (module notifications).
    ///
    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-070, Phase B P1-29)** — même
    /// correctif et même raisonnement que `addMessage` ci-dessus (couple messageExists+insert
    /// sérialisé via `insertSerializer`, PARTAGÉ entre les deux méthodes puisque toutes deux
    /// interrogent/écrivent la MÊME table `wk_messages`).
    @discardableResult
    func addGroupMessage(_ meta: MessageLib) async throws -> MessagePacket? {
        try await insertSerializer.run { [self] in
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

    /// **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-078, Phase B P1-33)** — port du
    /// scan `isFileUploaded==0` indépendant de l'UI (`ChatManager.sendMessageFromCursor`, branche
    /// upload), déclenché côté Android par `WorkManager`/reconnexion réseau/notification push (voir
    /// `ChatRepository.resumePendingUploads`). Messages ENVOYÉS par l'utilisateur courant
    /// (`usernameFrom == currentUsername`), média pas encore uploadé, TOUTES conversations
    /// confondues — pas de filtre `conversationId`, fidèle à `sendMessageFromCursor` qui balaie
    /// TOUS les messages locaux, pas seulement ceux de la conversation actuellement affichée à
    /// l'écran (contrairement à `ChatViewModel.handleAppear`, seul déclencheur de reprise avant ce
    /// correctif).
    /// **Corrigé (2026-09-03)** — même bug de fond que celui corrigé dans `ViewEventRepository.
    /// pending()` (voir sa doc en tête de fichier) : `messages.query(...)` renvoie des
    /// `MessageEntity` (`NSManagedObject`) vivants, liés au contexte d'arrière-plan PRIVÉ où ils ont
    /// été fetchés, une fois SORTIS de son `context.perform`. Le `.map { Self.toMessageLib($0, ...) }`
    /// qui suivait lisait ensuite leurs propriétés (`entity.messageId`, etc.) HORS de cette queue —
    /// accès cross-thread interdit par Core Data. La projection en `MessageLib` (DTO valeur) se fait
    /// désormais ICI, DANS le `context.perform` d'origine, avant que les objets ne quittent la queue
    /// qui les possède.
    func pendingUploads(currentUsername: String) async throws -> [MessageLib] {
        let predicate = NSPredicate(format: "isFileUploaded == 0 AND usernameFrom == %@", currentUsername)
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = MessageEntity.fetchRequest()
            request.predicate = predicate
            let rows = try context.fetch(request)
            return rows
                .map { Self.toMessageLib($0, currentUsername: currentUsername) }
                .filter { ["audio", "photo", "video", "sticker", "gif"].contains($0.object ?? "") }
        }
    }

    /// Symétrique de `pendingUploads` ci-dessus, côté téléchargement — port du même principe de
    /// scan indépendant de l'UI (**V5-F-056, 2026-08-26, Phase B P3**), pour la reprise de
    /// téléchargement d'une pièce jointe reçue. Messages REÇUS d'autrui
    /// (`usernameFrom != currentUsername`), média pas encore téléchargé, TOUTES conversations
    /// confondues.
    /// **Corrigé (2026-09-03)** — même correctif et même raisonnement que `pendingUploads`
    /// ci-dessus : projection en `MessageLib` déplacée à l'intérieur du `context.perform` d'origine.
    func pendingDownloads(currentUsername: String) async throws -> [MessageLib] {
        let predicate = NSPredicate(format: "isFileDownloaded == 0 AND usernameFrom != %@", currentUsername)
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = MessageEntity.fetchRequest()
            request.predicate = predicate
            let rows = try context.fetch(request)
            return rows
                .map { Self.toMessageLib($0, currentUsername: currentUsername) }
                .filter { ["audio", "photo", "video", "sticker", "gif"].contains($0.object ?? "") }
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
    /// **Corrigé (2026-09-03)** — même correctif et même raisonnement que `pendingUploads`
    /// ci-dessus : projection en `MessageLib` déplacée à l'intérieur du `context.perform` d'origine.
    func page(conversationId: String, limit: Int, offset: Int, currentUsername: String) async throws -> [MessageLib] {
        let predicate = NSPredicate(format: "conversationId == %@", conversationId)
        let sort = [NSSortDescriptor(key: "stamp", ascending: false)]
        let context = stack.newBackgroundContext()
        return try await context.perform {
            let request = MessageEntity.fetchRequest()
            request.predicate = predicate
            request.sortDescriptors = sort
            request.fetchLimit = limit
            request.fetchOffset = offset
            let rows = try context.fetch(request)
            return rows.map { Self.toMessageLib($0, currentUsername: currentUsername) }.reversed()
        }
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

/// **Ajouté le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-070, Phase B P1-29)** — sérialise des
/// opérations async pour garantir qu'elles s'exécutent STRICTEMENT l'une après l'autre, jamais en
/// chevauchement, même si chaque opération contient elle-même des points de suspension internes
/// (ce qui est le cas ici : `messageExists` PUIS `insert`, deux `await` séparés).
///
/// **Pourquoi pas un simple `actor` ?** Un `actor` isole l'accès à son état mutable, mais reste
/// RÉENTRANT à chaque point de suspension : si la méthode protégée elle-même contient un `await`
/// interne, un DEUXIÈME appel peut commencer à s'exécuter PENDANT que le premier est suspendu sur
/// SON PROPRE `await` — recréant exactement la même course que celle qu'on cherche à éliminer
/// (`messageExists` de l'appel B pourrait s'exécuter entre le `messageExists` et l'`insert` de
/// l'appel A). Cette file utilitaire enchaîne explicitement chaque nouvelle opération à la fin de
/// la précédente via un `Task` de continuation, sans jamais laisser deux opérations protégées se
/// chevaucher, y compris à travers leurs propres `await` internes.
///
/// Port de l'atomicité qu'Android obtient nativement via `DecodeThreadPool` (1 seul thread de
/// décodage en pratique) + `Handler.post` (1 Runnable exécuté intégralement) +
/// `ChatManager.addMessage` `synchronized` — trois mécanismes distincts qui, ensemble, garantissent
/// qu'un événement socket entrant est traité de bout en bout avant que le suivant ne commence.
actor SerialTaskQueue {
    private var tail: Task<Void, Never>?

    func run<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let previous = tail
        return try await withCheckedThrowingContinuation { continuation in
            let task = Task {
                _ = await previous?.value
                do {
                    let result = try await operation()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            tail = Task { _ = await task.value }
        }
    }
}
