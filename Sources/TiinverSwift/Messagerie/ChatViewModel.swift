import AVFoundation
import Combine
import Foundation
import UIKit

/// Port de `messagerie/ui/ChatFragmentTest.java` (3080 lignes, lu en entier) — la logique métier de
/// l'écran de chat, SANS le chrome Android (immersive mode, `CursorLoader`, `ItemTouchHelper`,
/// `DownloadManager`/`ServiceConnection` — remplacés par des équivalents SwiftUI/async natifs, pas
/// pertinents à porter ligne à ligne). `ChatView.swift` est l'écran, ce fichier en est le cerveau.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var items: [ChatListItem] = []
    @Published var inputText: String = ""
    @Published private(set) var isLoadingPage = false
    @Published private(set) var isPeerOnline = false
    @Published private(set) var typingUsername: String?
    @Published var quote: QuoteState?
    @Published var selection: Set<String> = []
    @Published var isSelecting = false

    /// Port de `RosterModel` passé en argument de `ChatFragmentTest.newInstance` — identité de la
    /// conversation ouverte, fournie par l'appelant (écran de liste des conversations, PAS encore
    /// porté — voir `RosterModel.swift`).
    let target: RosterModel

    private let messages: MessageRepository
    private let roster: RosterRepository
    private let chatRepository: ChatRepository
    private var cancellables = Set<AnyCancellable>()

    private let pageSize = 100
    private var offset = 0
    private var previousDayComponents: DateComponents?
    private var typingResetTask: Task<Void, Never>?
    private var isTypingFlag = false

    private var currentUsername: String { UserSession.shared.username ?? "" }
    private var myId: String { UserSession.shared.myId ?? "" }

    /// Port de `QuoteView.showMessageQuote`/champs `quoteObject`/`quoteTitle`/`quoteMessage`/
    /// `quoteDuration` de `ChatFragmentTest`.
    struct QuoteState: Equatable {
        var object: String
        var title: String
        var message: String
        var duration: String?
    }

    init(
        target: RosterModel, messages: MessageRepository = MessageRepository(),
        roster: RosterRepository = RosterRepository(), chatRepository: ChatRepository? = nil
    ) {
        self.target = target
        self.messages = messages
        self.roster = roster
        // `chatRepository ?? .shared` évalué ICI, dans le corps de l'init (isolé `@MainActor` via
        // la classe englobante), plutôt qu'en valeur par défaut de paramètre (`= .shared`,
        // corrigé — Checkpoint 3, avertissement Swift 6 strict concurrency) : une expression de
        // valeur par défaut n'hérite pas garantiment de l'isolation d'acteur de l'init dans ce
        // mode de vérification, contrairement au corps de la fonction.
        self.chatRepository = chatRepository ?? .shared
        subscribeToRealtimeEvents()
    }

    // MARK: - Chargement / pagination (port de `loadInitialData`/`loadMoreData`/
    // `displayMessageOnInicialPage`/`displayMoreMessageOnScroll`)

    func loadInitial() async {
        offset = 0
        previousDayComponents = nil
        let page = try? await messages.page(
            conversationId: target.conversationId ?? "", limit: pageSize, offset: 0, currentUsername: currentUsername)
        var built: [ChatListItem] = []
        for mlib in page ?? [] { appendWithDateSeparator(mlib, into: &built) }
        items = built
        await markConversationRead()
    }

    /// Port de `loadMoreData` (déclenché par `onScrolled`/`RecyclerView` proche du haut, ou par le
    /// `FOOTER_TYPE`/`LoadMoreDataListener.readyToLoad` — les deux mènent au même
    /// `LoaderManager.restartLoader`, consolidé en une seule méthode ici).
    func loadMore() async {
        guard !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        offset += pageSize
        let page = try? await messages.page(
            conversationId: target.conversationId ?? "", limit: pageSize, offset: offset, currentUsername: currentUsername)
        guard let page, !page.isEmpty else { return }
        var prepended: [ChatListItem] = []
        for mlib in page { appendWithDateSeparator(mlib, into: &prepended) }
        items.insert(contentsOf: prepended, at: 0)
    }

    /// Port du corps commun à `displayMessageOnInicialPage`/`displayMoreMessageOnScroll`/`addMessage`
    /// — insère un séparateur de date SI le jour calendaire change depuis le dernier message inséré.
    private func appendWithDateSeparator(_ mlib: MessageLib, into list: inout [ChatListItem]) {
        guard let key = Self.dayKey(fromStampMillis: mlib.stamp) else {
            list.append(.message(mlib))
            return
        }
        if key != previousDayComponents.map(Self.dayKeyString) {
            list.append(.dateSeparator(id: mlib.messageId ?? UUID().uuidString, dayKey: key, text: ChatDateFormatting.date(fromStampMillis: mlib.stamp)))
            previousDayComponents = Calendar.current.dateComponents([.year, .day], from: Date(timeIntervalSince1970: (Double(mlib.stamp ?? "") ?? 0) / 1000))
        }
        list.append(.message(mlib))
    }

    private static func dayKey(fromStampMillis stamp: String?) -> String? {
        guard let ms = stamp.flatMap(Double.init) else { return nil }
        let components = Calendar.current.dateComponents([.year, .day], from: Date(timeIntervalSince1970: ms / 1000))
        return dayKeyString(components)
    }

    private static func dayKeyString(_ components: DateComponents) -> String {
        "\(components.year ?? 0)-\(components.day ?? 0)"
    }

    /// Port de `isVu(Context)` — remet `wk_roster.unreadCount` à 0 pour cette conversation.
    private func markConversationRead() async {
        guard let conversationId = target.conversationId else { return }
        try? await roster.update(predicate: NSPredicate(format: "conversationId == %@", conversationId)) { entity in
            entity.unreadCount = 0
        }
    }

    // MARK: - Événements temps réel (port de l'observer `chatViewModel.getIncomingMessage()` dans
    // `onViewCreated`, lignes 649-698 de `ChatFragmentTest.java`)

    private func subscribeToRealtimeEvents() {
        chatRepository.chatEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                Task { @MainActor in await self.handle(event) }
            }
            .store(in: &cancellables)
    }

    private func handle(_ event: ChatEvent) async {
        switch event {
        case .message(let meta):
            let isPrivateMatch = !target.isGroup && meta.type == ChatType.chat.wireValue && meta.from == target.to
            let isGroupMatch = target.isGroup && meta.type == ChatType.group.wireValue && meta.token == target.token
            guard isPrivateMatch || isGroupMatch else { return }
            await onIncoming(meta)
        case .messageStatus(let messageId, _, let status):
            updateStatus(messageId: messageId, status: status.rawValue)
        case .presence(let username, let online):
            guard username == target.to else { return }
            isPeerOnline = online
        case .typing(let username, let typing):
            guard username == target.to else { return }
            typingUsername = typing ? username : nil
        case .pbs:
            break // Shareboard — module 13, pas encore atteint.
        }
    }

    /// Port du bloc `normal==true` de `onNewMessage` (lignes 1852-1876) — dédup par `messageId`,
    /// substitution `MgGraphic`, recalcul de `conversationId`, insertion + son de réception.
    private func onIncoming(_ meta: MessageLib) async {
        guard !items.contains(where: { $0.messageId == meta.messageId }) else { return }
        var stored = meta
        if stored.object == "graphic" {
            stored.message = stored.mgGraphic
            stored.mgGraphic = nil
        }
        if !target.isGroup {
            stored.conversationId = ConversationIdGenerator.conversationId(currentUser: myId, remoteUser: meta.sender ?? "")
            stored.regroupage = meta.from
        } else {
            stored.conversationId = ConversationIdGenerator.groupConversationId(currentUser: myId, remoteUser: meta.groupId ?? "")
            stored.regroupage = meta.token
        }
        stored.belongsToCurrentUser = (meta.from == currentUsername)
        appendWithDateSeparator(stored, into: &items)
    }

    /// Port de `chatState(String messageId, int status)` — remplace l'entrée `.message` en place
    /// (Android reconstruit un `MessageLib` "T" complet ; ici on modifie juste `status` sur la copie
    /// struct existante, suffisant en Swift value-type).
    private func updateStatus(messageId: String, status: Int) {
        guard let index = items.firstIndex(where: { $0.messageId == messageId }) else { return }
        guard case .message(var mlib) = items[index] else { return }
        mlib.status = status
        items[index] = .message(mlib)
    }

    // MARK: - Envoi (port de `sendMessageText`/`sendMessageGift`/`prepareFileMessage`/
    // `prepareGifMessage`/`addMessage`, tous lus en entier)

    /// Port de `sendMessageText` + `addMessage` (écho optimiste immédiat) + persistance locale.
    func sendText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        var mlib = buildOutgoingBase(object: "text")
        mlib.message = text
        appendOptimistic(mlib)
        Task { try? await messages.insertTextMessage(mlib) }
        cancelQuote()
    }

    /// Port de `FragmentMessageGraphic.OnMessageSendedListener.onMessage` (câblé dans
    /// `ChatFragmentTest`, point d'entrée exact non lu cette passe — reconstruit ici par symétrie
    /// avec `sendText`/`sendMedia`) — `payload` est le lot compact déjà encodé
    /// (`GraphicMessageCodec.encodeTouchBatch`, voir `MessageGraphicComposeView`). Stocké dans
    /// `message` (PAS `mgGraphic`) : c'est `MessagePacket.packetJSON()` qui republie `message` sous
    /// la clé fil `MgGraphic` pour `object == "graphic"` (voir module 11 protocole).
    func sendGraphic(payload: String) {
        guard !payload.isEmpty else { return }
        var mlib = buildOutgoingBase(object: "graphic")
        mlib.message = payload
        appendOptimistic(mlib)
        Task { try? await messages.insertTextMessage(mlib) }
    }

    /// Port de `sendMessageGift` — construit le message "gift" et l'écho optimiste. **Le débit de
    /// pièces + commentaire serveur (`ChatFragmentTest.sendGift`, endpoint non identifié dans cette
    /// passe, dépend du module 15 Wallet) N'EST PAS appelé ici** — gap documenté, pas deviné.
    func sendGift(giftId: String) {
        var mlib = buildOutgoingBase(object: "gift")
        mlib.giftId = giftId
        appendOptimistic(mlib)
        Task { try? await messages.insertTextMessage(mlib) }
    }

    /// Port commun de `prepareFileMessage`/`prepareGifMessage` — construit un message média local
    /// (`isFileUploaded=0` sauf pour les GIF déjà hébergés, `isUploaded` en argument comme
    /// `prepareGifMessage(detail, object, isUploaded)`). `localThumbnailURI` : port de
    /// `mlib.setThumbnailUri(detail.getThumbnailUri())` (branche vidéo UNIQUEMENT de
    /// `prepareFileMessage`, ligne 2424-2427) — chemin LOCAL avant upload, `requestUpload` le
    /// remplace par l'URL CDN distante une fois `ChatMediaUploadService` terminé (GAP-004).
    func sendMedia(object: String, localFileURI: String, width: String?, height: String?, duration: String?, localThumbnailURI: String? = nil, alreadyUploaded: Bool = false) {
        var mlib = buildOutgoingBase(object: object)
        mlib.objectUrl = localFileURI
        mlib.localFileDirection = localFileURI
        mlib.width = width
        mlib.height = height
        mlib.duration = duration
        mlib.thumbnailUri = localThumbnailURI
        mlib.isFileUploaded = alreadyUploaded ? 1 : 0
        appendOptimistic(mlib)
        Task { try? await messages.insertFileMessage(mlib) }
    }

    /// Port de la branche `pickMedia`/`onArticleSelected(2|4, bundle)` (`ChatFragmentTest.java`,
    /// lignes 422-450, lu en entier) — calcule les métadonnées locales (largeur/hauteur/durée,
    /// `MediaDataDetail` côté Android construit par le même callback de sélection) avant d'appeler
    /// `sendMedia`. Point d'entrée appelé par `ChatView` après sélection dans `GalleryPickerView`
    /// (réutilisation du composant existant, module 7 Caméra — même picker `ImageAndVideo` que
    /// `pickMedia` Android, `PickVisualMedia.ImageAndVideo`).
    func attachMedia(url: URL, isVideo: Bool) {
        if isVideo {
            Task { await attachVideo(url: url) }
        } else {
            attachImage(url: url)
        }
    }

    private func attachImage(url: URL) {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
        sendMedia(
            object: "photo", localFileURI: url.absoluteString,
            width: String(Int(image.size.width * image.scale)),
            height: String(Int(image.size.height * image.scale)),
            duration: nil
        )
    }

    /// Génère une miniature locale via `AVAssetImageGenerator` — port INTENTIONNELLEMENT différent
    /// de `saveThumbnailToCache` (Android), qui est du code COMMENTÉ dans `prepareFileMessage`
    /// (ligne 2425, jamais exécuté) : `UploadFileOrDataService.uploadMediaAndThumbnail` utilise
    /// pourtant `data.getThumbnailUri()` SANS garde de nullité pour la branche vidéo — sans
    /// génération réelle, ce chemin échouerait en pratique côté Android lui-même. Reproduit le
    /// comportement INTENTIONNEL (upload média + miniature) avec une vraie génération plutôt que le
    /// code mort qui l'entoure.
    private func attachVideo(url: URL) async {
        let asset = AVURLAsset(url: url)
        let durationSeconds = (try? await asset.load(.duration))?.seconds ?? 0
        var width = 0, height = 0
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let naturalSize = try? await track.load(.naturalSize) {
            width = Int(abs(naturalSize.width))
            height = Int(abs(naturalSize.height))
        }
        sendMedia(
            object: "video", localFileURI: url.absoluteString,
            width: width > 0 ? String(width) : nil,
            height: height > 0 ? String(height) : nil,
            duration: String(Int(durationSeconds * 1000)),
            localThumbnailURI: Self.generateThumbnail(for: asset)
        )
    }

    private static func generateThumbnail(for asset: AVURLAsset) -> String? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil),
              let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
        else { return nil }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        guard (try? jpegData.write(to: destination)) != nil else { return nil }
        return destination.absoluteString
    }

    private func buildOutgoingBase(object: String) -> MessageLib {
        let unixMillis = Int64(Date().timeIntervalSince1970 * 1000)
        var mlib = MessageLib()
        mlib.messageId = myId + String(unixMillis)
        mlib.conversationId = target.conversationId
        mlib.nikname = target.nikname
        mlib.groupName = target.groupName
        mlib.groupId = target.groupId
        mlib.token = target.token
        mlib.description = target.description
        mlib.groupType = target.groupType
        mlib.lucrative = target.lucrative
        mlib.price = target.price
        mlib.to = target.to
        mlib.from = currentUsername
        mlib.sender = myId
        mlib.receiver = target.userId
        mlib.userId = target.userId
        mlib.type = target.type
        mlib.username = target.username
        mlib.object = object
        mlib.verb = "post"
        mlib.status = 0
        mlib.vu = "true"
        mlib.regroupage = target.isGroup ? target.token : target.username
        mlib.resource = "iOS" // Build.MODEL n'a pas d'équivalent direct, voir MessagePacket.resource
        mlib.versionCode = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1
        mlib.profile = target.profile
        mlib.stamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        mlib.deliverTime = String(Int64(Date().timeIntervalSince1970))
        mlib.isQuoted = quote != nil
        mlib.quoteTitle = quote?.title
        mlib.quoteMessage = quote?.message
        mlib.quoteObject = quote?.object
        mlib.quoteDuration = quote?.duration
        mlib.belongsToCurrentUser = true
        return mlib
    }

    /// Port du bloc `messageHandler.post { … }` d'`addMessage` — insère avec séparateur de date +
    /// scroll (délégué à la vue) ; le son d'envoi est laissé à `ChatView` (`AVFoundation`, pas ici).
    private func appendOptimistic(_ mlib: MessageLib) {
        appendWithDateSeparator(mlib, into: &items)
    }

    // MARK: - Cycle de vie d'une bulle visible (port du dispatch `onBindViewHolder` par
    // `viewType` — upload/download/accusé de lecture déclenchés à l'affichage, PAS au clic)

    /// Port consolidé des branches `if (message.getStatus()==0) sendSimpleMessage(message)` /
    /// `if (isFileUploaded==0) helper()` / `if (isFileDownloaded==0) downloadFile()` /
    /// `if (status<3) notifyBackMessageRead()` communes à TOUS les `onBindViewHolder` par type.
    func handleAppear(of mlib: MessageLib) {
        guard mlib.object != "date", mlib.object != "header" else { return }
        if mlib.belongsToCurrentUser {
            let needsUpload = ["audio", "photo", "video", "sticker", "gif"].contains(mlib.object ?? "") && mlib.isFileUploaded == 0
            if needsUpload {
                requestUpload(mlib)
            } else if mlib.status == 0 {
                send(mlib)
            }
        } else {
            let needsDownload = ["audio", "photo", "video", "sticker", "gif"].contains(mlib.object ?? "") && mlib.isFileDownloaded == 0
            if needsDownload {
                requestDownload(mlib)
            } else if mlib.status < 3 {
                markAsRead(mlib)
            }
        }
    }

    /// Port de `sendSimpleMessage(MessageLib)` (`ChatFragmentTest`, PAS `MessageListAdapter` —
    /// homonyme différent) — dispatch `sendPrivateMessage`/`sendGroupMessage` selon `type`.
    /// La branche "programmé" (`deliver_time` dans le futur, `isSchudeled`) n'est PAS reproduite :
    /// aucun point d'entrée UI pour programmer un message n'a été trouvé dans les 3080 lignes lues,
    /// probablement une fonctionnalité inachevée côté Android — non portée plutôt que devinée.
    private func send(_ mlib: MessageLib) {
        if mlib.type == ChatType.chat.wireValue {
            chatRepository.sendPrivateMessage(mlib)
        } else if mlib.type == ChatType.group.wireValue {
            chatRepository.sendGroupMessage(mlib)
        }
    }

    /// Port de `notifyBackMessageRead` (`MessageListAdapter`) — accusé "lu" (`ROOM.DISPLAYED`).
    private func markAsRead(_ mlib: MessageLib) {
        var packet = MessagePacket()
        packet.type = mlib.type
        packet.to = mlib.from
        packet.from = mlib.to
        packet.object = mlib.object
        packet.messageId = mlib.messageId
        chatRepository.sendMessageState(packet)
    }

    /// Port de `MessageActionListener.onUpload`/`checkAndUploadFile`/`upload(MessageLib)` —
    /// **implémenté le 2026-08-15 (GAP-004)**, `UploadFileOrDataService.java` lu en entier :
    /// upload direct BunnyCDN (`ChatMediaUploadService`, PAS `APIClient` — protocole différent, voir
    /// `MIGRATION_AUDIT.md` GAP-004), puis mise à jour Core Data (`updateFileUploaded`) ET de la
    /// liste affichée. Envoie ENSUITE le message via socket (`send(mlib)`) — Android compte sur un
    /// re-bind ultérieur de la vue (`onBindViewHolder`) pour rappeler `sendSimpleMessage` une fois
    /// `isFileUploaded` passé à 1 ; SwiftUI ne re-déclenche PAS `.onAppear` sur une simple mise à
    /// jour de contenu, donc l'envoi est déclenché explicitement ici pour un comportement observable
    /// équivalent (le message part bien vers le pair une fois l'upload terminé).
    private func requestUpload(_ mlib: MessageLib) {
        guard let messageId = mlib.messageId, let object = mlib.object,
              let localPath = mlib.localFileDirection, let fileURL = URL(string: localPath)
        else { return }
        let thumbnailURL = mlib.thumbnailUri.flatMap(URL.init(string:))
        Task {
            do {
                let result = try await ChatMediaUploadService.shared.upload(
                    messageId: messageId, object: object, fileURL: fileURL, thumbnailFileURL: thumbnailURL
                )
                try await messages.updateFileUploaded(messageId: messageId, objectUrl: result.objectUrl, thumbnailUri: result.thumbnailUrl)
                guard let index = items.firstIndex(where: { $0.messageId == messageId }),
                      case .message(var updated) = items[index]
                else { return }
                updated.objectUrl = result.objectUrl
                updated.isFileUploaded = 1
                if let thumb = result.thumbnailUrl { updated.thumbnailUri = thumb }
                items[index] = .message(updated)
                send(updated)
            } catch {
                // `isFileUploaded` reste à 0 — un prochain `handleAppear` (la bulle redevient
                // visible, ex. scroll) relance un nouvel essai, sans compteur de tentatives, comme
                // `checkAndUploadFile` (Android) qui relance aussi inconditionnellement.
            }
        }
    }

    /// Port de `MessageActionListener.onDowload`/`checkAndDownloadFile`/`downloadFile(...)` —
    /// **transfert réel PAS implémenté**, même raison que `requestUpload` (`DownloadReceiver.java`
    /// pas lu cette passe).
    private func requestDownload(_ mlib: MessageLib) {
        // TODO(module 11 suite) : lire DownloadReceiver.java, implémenter via URLSession download
        // task vers Caches/media/<dossier>, puis isFileDownloaded=1 + objectUrl local.
    }

    // MARK: - Citation (port de `showQuotedMessage`/`hideReplyLayout`/`MessageSwipeController`)

    func startQuote(for mlib: MessageLib) {
        guard !mlib.belongsToCurrentUser || mlib.status > 0, mlib.object != "information" else { return }
        let title = mlib.belongsToCurrentUser ? currentUsername : (mlib.username ?? "")
        let preview: String
        switch mlib.object {
        case "text":
            let text = mlib.message ?? ""
            preview = text.count > 40 ? String(text.prefix(40)) + ".." : text
        case "audio": preview = "Message vocal" // R.string.voice_message
        case "photo": preview = "Photo" // R.string.photo
        case "video": preview = "Vidéo" // R.string.video
        case "graphic": preview = "Graphique" // R.string.graphic
        default: return
        }
        quote = QuoteState(object: mlib.object ?? "", title: title, message: preview, duration: mlib.quoteDuration)
    }

    func cancelQuote() { quote = nil }

    // MARK: - Frappe (port de `onTyping(boolean)`/`onTyping(String)`/`stopTyping(String)` — voir
    // note ci-dessous sur la partie Android commentée)

    /// **Simplifié par rapport à l'original** : le corps réel de `MessageEventLayout.onTyping
    /// (boolean)` qui émettrait `SocketIO.Typing` est ENTIÈREMENT COMMENTÉ dans le source Android
    /// lu (lignes 830-836 de `ChatFragmentTest.java`) — seul le `Handler` de ré-armement
    /// (`composeTyping.sendEmptyMessageDelayed`) est actif, sans émission socket associée : la
    /// frappe entrante EST gérée (`onTyping(String)`/`stopTyping(String)` ci-dessus, réels), mais
    /// l'émission SORTANTE semble inachevée côté Android lui-même. Reproduit ici une émission
    /// fonctionnelle (via `ChatRepository.emitTyping`/`emitStopTyping`, vérifiés module 11
    /// protocole) plutôt que de reproduire un no-op — amélioration documentée, pas un écart
    /// silencieux.
    func onTextChanged() {
        if !isTypingFlag {
            isTypingFlag = true
            emitTyping(isTyping: true)
        }
        typingResetTask?.cancel()
        typingResetTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            isTypingFlag = false
            emitTyping(isTyping: false)
        }
    }

    private func emitTyping(isTyping: Bool) {
        var packet = MessagePacket()
        packet.object = "text"
        packet.type = target.type
        packet.to = target.isGroup ? target.token : target.username
        packet.from = currentUsername
        if isTyping { chatRepository.emitTyping(packet) } else { chatRepository.emitStopTyping(packet) }
    }

    // MARK: - Sélection / suppression (port de `onItemSelected`/`deleteMessageForme`/
    // `deleteMessageForEveryOne`/`removeMessageAndUpdateSeparators`)

    func toggleSelection(_ messageId: String) {
        if selection.contains(messageId) { selection.remove(messageId) } else { selection.insert(messageId) }
        isSelecting = !selection.isEmpty
    }

    func clearSelection() {
        selection.removeAll()
        isSelecting = false
    }

    /// Port de `deleteMessageForme` — retrait local uniquement.
    func deleteSelectedForMe() {
        for id in selection {
            removeMessageAndOrphanSeparator(id)
            Task { try? await messages.deleteMessageForMe(messageId: id) }
        }
        clearSelection()
    }

    /// Port de `deleteMessageForEveryOne` (map de sélection) — reconstruit un "tombstone" local et
    /// délègue au canal socket approprié (`ChatRepository.deletePrivateMessage`/`deleteGroupMessage`),
    /// UNIQUEMENT pour les messages propres (`isBelongsToCurrentUser`, reproduit la même garde que
    /// l'original).
    func deleteSelectedForEveryone() {
        for id in selection {
            guard let index = items.firstIndex(where: { $0.messageId == id }),
                case .message(var mlib) = items[index], mlib.belongsToCurrentUser
            else { continue }
            mlib.message = "deletemessage"
            mlib.object = "deletemessage"
            mlib.verb = "deletemessage"
            mlib.status = 0
            items[index] = .message(mlib)
            if mlib.type == ChatType.chat.wireValue {
                chatRepository.deletePrivateMessage(mlib)
            } else {
                chatRepository.deleteGroupMessage(mlib)
            }
            Task { try? await messages.deleteMessageForEveryOne(mlib, isFromServer: false) }
        }
        clearSelection()
    }

    /// Port de `removeMessageAndUpdateSeparators` — retire le message ET son séparateur de date
    /// s'il devient orphelin (aucun autre message ce jour-là).
    private func removeMessageAndOrphanSeparator(_ messageId: String) {
        guard let index = items.firstIndex(where: { $0.messageId == messageId }) else { return }
        let removedStamp = items[index].stamp
        items.remove(at: index)
        guard let key = Self.dayKey(fromStampMillis: removedStamp) else { return }
        let hasSiblingSameDay = items.contains { item in
            guard case .message = item else { return false }
            return Self.dayKey(fromStampMillis: item.stamp) == key
        }
        if !hasSiblingSameDay {
            items.removeAll { $0.dayKey == key }
        }
    }
}
