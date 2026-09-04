import Combine
import Foundation
import SocketIO

/// Port de `messagerie/repository/ChatRepository.java` (1124 lignes, lu en entier) — hub central
/// d'enregistrement des listeners socket et de routage message/appel/PBS, singleton unique comme
/// l'original (le commentaire de tête du fichier Android documente un bug historique de DEUX
/// singletons désynchronisés, corrigé côté Android en un seul — reproduit directement en un seul
/// singleton ici, pas de bug équivalent à éviter côté Swift).
///
/// `MutableLiveData<ChatModel>`/`MutableLiveData<CallModel>` (Android, 4 flux dont 2 réellement
/// distincts après avoir vérifié que `incomingMessageLiveData`/`incomingChatLiveData` reçoivent
/// TOUJOURS la même valeur dans `sendLiveData` — jamais divergents) → deux `PassthroughSubject`
/// Combine (`chatEvents`, `callEvents`), publiés sur le thread principal comme
/// `postValue`/`Handler(Looper.getMainLooper()).post` l'exigeaient côté Android.
@MainActor
final class ChatRepository {
    static let shared = ChatRepository()

    let chatEvents = PassthroughSubject<ChatEvent, Never>()
    let callEvents = PassthroughSubject<CallEvent, Never>()

    /// Port de `CallService.isOnCall` — le module 12 (WebRTC/CallKit) possède la vraie source de
    /// vérité une fois écrit ; exposé ici comme point d'ancrage unique pour que le routage
    /// `unifiedWebrtcMessage`/`NewPrivateMessage`/`NewGroupMessage` (CE fichier) puisse être écrit
    /// et vérifié dès maintenant sans dépendre de l'existence du module 12.
    static var isOnCall = false

    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-016/023, Phase B P0-1)** —
    /// `let` → `var` : capturer le socket une seule fois à l'init figeait `nil` pour toujours si
    /// ce singleton était touché avant que `TiinverSocket` ait un socket réel (cas réel : ce
    /// fichier est déjà touché très tôt via `CallCoordinator.chatRepository`/`PBSViewModel`,
    /// potentiellement avant authentification) — port du bug CHAT-02 identifié dans l'audit V3,
    /// distinct du bug "connect() jamais appelé" (V3-F-016, ci-dessous) mais qui l'aurait de toute
    /// façon réintroduit une fois celui-ci corrigé seul. Reflète maintenant fidèlement `mSocket`
    /// (Android, champ mutable réassigné par `App.resetSocket()` — voir `attachToCurrentSocket()`).
    private var socket: SocketIOClient?
    private let messages: MessageRepository
    private var isConnected = false
    private var isReconnecting = false

    /// Port du constructeur `ChatRepository(Context)` (`ChatRepository.java:211-224`) —
    /// `getSocket()` (lazy, avec le token DISPONIBLE MAINTENANT, potentiellement absent avant
    /// login) + `connectSocket()` (idempotent) + `registerAllListeners()`. **Corrigé le
    /// 2026-08-19** : avant ce correctif, `connect(apiKey:)` n'était appelé nulle part dans tout
    /// le projet (confirmé par grep exhaustif, MIGRATION_PARITY_AUDIT_V3.md V3-F-016) — le socket
    /// ne se connectait donc jamais, quelle que soit la fidélité du reste de ce fichier.
    private init(messages: MessageRepository = MessageRepository()) {
        self.messages = messages
        TiinverSocket.shared.connect(apiKey: UserSession.shared.apiKey)
        self.socket = TiinverSocket.shared.socket
        registerAllListeners()
    }

    /// Port de la séquence `App.resetSocket()` → nouveau `mSocket` → ré-attachement des listeners
    /// — appelé APRÈS un login réussi (`RootRouterView.swift`), le cas réel où ce singleton a déjà
    /// pu être touché (et donc déjà créé un socket, potentiellement anonyme/sans jeton) AVANT que
    /// l'utilisateur ne se connecte. Sans cet appel explicite, le socket resterait bloqué sur le
    /// jeton (ou l'absence de jeton) capturé au tout premier accès à `ChatRepository.shared` —
    /// exactement le scénario réel derrière CHAT-02. Idempotent-sûr : recrée le socket même s'il
    /// était déjà valide, fidèle à `resetSocket()` qui ne fait pas de distinction.
    func attachToCurrentSocket() {
        TiinverSocket.shared.reset(apiKey: UserSession.shared.apiKey)
        self.socket = TiinverSocket.shared.socket
        isConnected = false
        registerAllListeners()
    }

    // MARK: - Enregistrement des listeners (port de `registerAllListeners`)

    private func registerAllListeners() {
        guard let socket else { return }

        socket.off(clientEvent: .connect)
        socket.off(clientEvent: .disconnect)
        socket.off(clientEvent: .error)
        socket.off(clientEvent: .reconnect)

        socket.on(clientEvent: .connect) { [weak self] _, _ in Task { @MainActor in self?.onConnected() } }
        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            Task { @MainActor in self?.onDisconnected(reason: (data.first as? String) ?? "unknown") }
        }
        socket.on(clientEvent: .error) { data, _ in
            let message = "\(data.first ?? "?")"
            print("❌ Erreur socket :", message)
            // Diagnostic temporaire (2026-09-04, audit "conversation instantanée") — voir
            // `SocketDiagnostics` pour le raisonnement complet.
            Task { @MainActor in SocketDiagnostics.shared.recordError(message) }
        }
        socket.on(clientEvent: .reconnect) { [weak self] _, _ in Task { @MainActor in self?.onConnected() } }

        socket.off(SocketEvent.newMessage)
        socket.off(SocketEvent.newGroupMessage)
        socket.off(SocketEvent.onDeletePrivateMessage)
        socket.off(SocketEvent.onDeleteGroupMessage)
        socket.off(SocketEvent.onResponse)
        socket.off(SocketEvent.presence)
        socket.off(SocketEvent.offlineStatus)
        socket.off(SocketEvent.typing)
        socket.off(SocketEvent.stopTyping)

        socket.on(SocketEvent.newMessage) { [weak self] data, _ in
            // Diagnostic temporaire (2026-09-04, audit "conversation instantanée").
            SocketDiagnostics.shared.recordLiveServerEvent(SocketEvent.newMessage)
            Task { @MainActor in await self?.handleNewMessage(data, isGroup: false) }
        }
        socket.on(SocketEvent.newGroupMessage) { [weak self] data, _ in
            SocketDiagnostics.shared.recordLiveServerEvent(SocketEvent.newGroupMessage)
            Task { @MainActor in await self?.handleNewMessage(data, isGroup: true) }
        }
        socket.on(SocketEvent.onDeletePrivateMessage) { [weak self] data, _ in
            Task { @MainActor in await self?.handleDeleteMessage(data) }
        }
        socket.on(SocketEvent.onDeleteGroupMessage) { [weak self] data, _ in
            Task { @MainActor in await self?.handleDeleteMessage(data) }
        }
        socket.on(SocketEvent.onResponse) { [weak self] data, _ in
            Task { @MainActor in await self?.handleResponse(data) }
        }
        // Port de `ChatManager.updateMessageStatus` (listener `offlineStatus`, ligne 763-774 de
        // `ChatRepository.java`) — **découverte tardive, listener manquant dans une première
        // version de ce fichier** : `ROOM.OFFLINE_STATUS` ("offline status") est utilisé pour DEUX
        // rôles distincts côté Android, confirmé en relisant `registerAllListeners`/`onConnected` —
        // (1) émis par le CLIENT à la connexion (`onConnected()` ci-dessous, déjà porté) pour
        // s'annoncer, ET (2) écouté pour recevoir un lot de statuts de livraison accumulés pendant
        // que le client était hors-ligne (`{"data":[MessageLib...]}`, chaque `messageId`/`status`
        // appliqué à `wk_messages` ET `wk_roster`) — PAS un doublon de `onResponse`/`handleResponse`
        // (celui-ci traite un SEUL message par appel, avec un format `{messageId,receiver,response}`
        // différent).
        socket.on(SocketEvent.offlineStatus) { [weak self] data, _ in
            Task { @MainActor in await self?.handleOfflineStatus(data) }
        }
        socket.on(SocketEvent.presence) { [weak self] data, _ in
            SocketDiagnostics.shared.recordLiveServerEvent(SocketEvent.presence)
            guard let dict = data.first as? [String: Any] else { return }
            let username = dict["username"] as? String ?? ""
            let online = (dict["online"] as? String) == "true"
            self?.chatEvents.send(.presence(username: username, online: online))
        }
        socket.on(SocketEvent.typing) { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            self?.chatEvents.send(.typing(username: dict["from"] as? String ?? "", isTyping: true))
        }
        socket.on(SocketEvent.stopTyping) { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            self?.chatEvents.send(.typing(username: dict["from"] as? String ?? "", isTyping: false))
        }

        // MARK: Appels
        socket.on(SocketEvent.call) { [weak self] data, _ in Task { @MainActor in self?.handleIncomingCall(data) } }
        socket.on(SocketEvent.acceptCall) { [weak self] _, _ in self?.callEvents.send(.acceptCall) }
        socket.on(SocketEvent.endCall) { [weak self] data, _ in
            self?.callEvents.send(.endCall(data: Self.stringify(data.first)))
        }
        socket.on(SocketEvent.ringing) { [weak self] data, _ in
            self?.callEvents.send(.ringing(data: Self.stringify(data.first)))
        }
        socket.on(SocketEvent.callBasic) { [weak self] data, _ in
            self?.callEvents.send(.busyCall(data: Self.stringify(data.first)))
        }
        socket.on(SocketEvent.webrtcMessage) { [weak self] data, _ in
            Task { @MainActor in self?.handleUnifiedWebrtcMessage(data) }
        }

        // MARK: Shareboard/PBS (module 13) — port des listeners `.on(ROOM.NEXT_PAGE, nextPage)`/
        // etc. de `registerAllListeners` (lignes 253-261 de `ChatRepository.java`), manquants
        // jusqu'ici (seul `webrtcMessage`, partagé avec les appels, était câblé au module 11/12).
        // `PBSEvent` existait déjà (module 11) mais rien ne l'alimentait encore.
        socket.on(SocketEvent.nextPage) { [weak self] _, _ in self?.chatEvents.send(.pbs(.nextPage)) }
        socket.on(SocketEvent.beforePage) { [weak self] _, _ in self?.chatEvents.send(.pbs(.precedentPage)) }
        socket.on(SocketEvent.joinRoom) { [weak self] data, _ in
            self?.chatEvents.send(.pbs(.joinRoom(data: Self.stringify(data.first))))
        }
        socket.on(SocketEvent.leaveRoom) { [weak self] data, _ in
            self?.chatEvents.send(.pbs(.leaveRoom(data: Self.stringify(data.first))))
        }
        socket.on(SocketEvent.onTouchListener) { [weak self] data, _ in
            self?.chatEvents.send(.pbs(.onTouchListener(data: Self.stringify(data.first))))
        }
        socket.on(SocketEvent.onReceiveData) { [weak self] data, _ in
            self?.chatEvents.send(.pbs(.onReceiveData(data: Self.stringify(data.first))))
        }
        socket.on(SocketEvent.startRoom) { [weak self] data, _ in
            guard let self, let profile = Self.decodeProfile(Self.stringify(data.first)) else { return }
            self.chatEvents.send(.pbs(.onStart(profile: profile, data: Self.stringify(data.first))))
        }
        socket.on(SocketEvent.onStartPrivatePBS) { [weak self] data, _ in
            guard let self, let profile = Self.decodeProfile(Self.stringify(data.first)) else { return }
            self.chatEvents.send(.pbs(.onStartPrivate(profile: profile, data: Self.stringify(data.first))))
        }
        socket.on(SocketEvent.onJoinPrivatePBS) { [weak self] data, _ in
            self?.chatEvents.send(.pbs(.onJoinPrivate(data: Self.stringify(data.first))))
        }
    }

    // MARK: - Connexion (port de `connected`/`reconnected`/`disconect`)

    private func onConnected() {
        isReconnecting = false
        // Diagnostic temporaire (2026-09-04, audit "conversation instantanée") — voir
        // `SocketDiagnostics` pour le raisonnement complet.
        SocketDiagnostics.shared.recordConnected()
        guard let socket, let username = UserSession.shared.username, !username.isEmpty else { return }
        isConnected = true
        let myId = UserSession.shared.myId ?? ""
        socket.emit(SocketEvent.addUser, username)
        socket.emit(SocketEvent.offlineStatus, ["id": myId, "username": username])
        socket.emit(SocketEvent.joinRoom, ["id": myId, "username": username])
        resumePendingUploads(currentUsername: username)
        resumePendingDownloads(currentUsername: username)
    }

    /// **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-078, Phase B P1-33)** — second
    /// mécanisme de reprise d'upload Android (`ChatManager.sendMessageFromCursor`, déclenché par
    /// `WorkManager` sur reconnexion réseau/sync périodique/notification push via
    /// `HttpConnectionService`/`NetworkStateReceiver`/`SyncAdapter`/`MyFirebaseMessagingService`),
    /// jusqu'ici absent côté iOS — seul `ChatViewModel.handleAppear` (affichage d'une bulle à
    /// l'écran) déclenchait une reprise. **Portée réduite documentée** : seul le déclencheur
    /// reconnexion socket (`onConnected()`, déjà appelé sur `.connect` ET `.reconnect`) est
    /// reproduit ici — ni scan périodique en arrière-plan (`BGTaskScheduler`, infrastructure déjà
    /// écartée pour la même famille de raisons dans V5-F-060, DIFFÉRÉ) ni scan à la réception d'une
    /// notification push, les deux hors périmètre de ce correctif P1 isolé. Pas de politique de
    /// retry/backoff dédiée (contrairement à `UploadChatWork`+`WorkManager`) : un échec laisse
    /// `isFileUploaded=0`, retenté au prochain `onConnected()` ou `handleAppear`, à l'identique de
    /// la politique déjà en place côté `ChatViewModel.requestUpload`.
    private func resumePendingUploads(currentUsername: String) {
        Task { [weak self] in
            guard let self, let pending = try? await self.messages.pendingUploads(currentUsername: currentUsername)
            else { return }
            for mlib in pending {
                guard let messageId = mlib.messageId, let object = mlib.object,
                      let localPath = mlib.localFileDirection, let fileURL = URL(string: localPath)
                else { continue }
                // Évite un double upload/double envoi socket si `ChatViewModel.requestUpload`
                // (bulle visible) a déjà réservé ce même message — voir `ChatMediaUploadService.
                // reserveUpload`.
                guard ChatMediaUploadService.shared.reserveUpload(messageId: messageId) else { continue }
                defer { ChatMediaUploadService.shared.releaseUpload(messageId: messageId) }
                let thumbnailURL = mlib.thumbnailUri.flatMap(URL.init(string:))
                do {
                    let result = try await ChatMediaUploadService.shared.upload(
                        messageId: messageId, object: object, fileURL: fileURL, thumbnailFileURL: thumbnailURL
                    )
                    try await self.messages.updateFileUploaded(messageId: messageId, objectUrl: result.objectUrl, thumbnailUri: result.thumbnailUrl)
                    var updated = mlib
                    updated.objectUrl = result.objectUrl
                    updated.isFileUploaded = 1
                    if let thumb = result.thumbnailUrl { updated.thumbnailUri = thumb }
                    if updated.type == ChatType.chat.wireValue {
                        self.sendPrivateMessage(updated)
                    } else if updated.type == ChatType.group.wireValue {
                        self.sendGroupMessage(updated)
                    }
                } catch {
                    // `isFileUploaded` reste à 0 — retenté au prochain `onConnected()`/`handleAppear`.
                }
            }
        }
    }

    /// **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-056, Phase B P3)** — symétrique de
    /// `resumePendingUploads` ci-dessus, côté téléchargement. Android délègue les deux sens
    /// (upload ET téléchargement) au même `android.app.DownloadManager`/`DownloadReceiver`, un
    /// service SYSTÈME persistant hors du process de l'app — le téléchargement survit à un kill
    /// d'app ou une coupure réseau, indépendamment de toute vue affichée. Avant ce correctif, le
    /// SEUL déclencheur de reprise de téléchargement côté iOS était `ChatViewModel.handleAppear`
    /// (bulle redevenue visible à l'écran) : un téléchargement en échec restait bloqué
    /// indéfiniment tant que l'utilisateur ne quittait/rentrait pas dans la conversation, même
    /// réseau revenu, app toujours ouverte. **Portée réduite documentée**, même politique que
    /// `resumePendingUploads`/V5-F-078 : seul le déclencheur reconnexion socket est reproduit (pas
    /// de vraie `URLSession` `background` survivant à un kill complet du process — écarté pour la
    /// même raison de risque/ampleur que le choix déjà fait pour l'upload en V5-F-098), pas de
    /// rafraîchissement visuel immédiat d'une bulle actuellement affichée dans une autre instance
    /// de `ChatViewModel` (Core Data est mis à jour, mais cette instance-ci n'a pas de référence à
    /// `items` d'un autre écran — un `handleAppear` ultérieur ou une réouverture de conversation le
    /// reflète). Réservation partagée via `ChatMediaDownloadService.reserveDownload` — évite une
    /// course avec `ChatViewModel.requestDownload` (bulle visible) sur le même message.
    private func resumePendingDownloads(currentUsername: String) {
        Task { [weak self] in
            guard let self, let pending = try? await self.messages.pendingDownloads(currentUsername: currentUsername)
            else { return }
            for mlib in pending {
                guard let messageId = mlib.messageId, let remoteURLString = mlib.objectUrl,
                      let remoteURL = URL(string: remoteURLString), remoteURL.scheme?.hasPrefix("http") == true
                else { continue }
                guard ChatMediaDownloadService.shared.reserveDownload(messageId: messageId) else { continue }
                defer { ChatMediaDownloadService.shared.releaseDownload(messageId: messageId) }
                do {
                    _ = try await ChatMediaDownloadService.shared.download(messageId: messageId, remoteURL: remoteURL, messages: self.messages)
                } catch {
                    // `isFileDownloaded` reste à 0 — retenté au prochain `onConnected()`/`handleAppear`.
                }
            }
        }
    }

    private func onDisconnected(reason: String) {
        isConnected = false
        // Diagnostic temporaire (2026-09-04, audit "conversation instantanée") — voir
        // `SocketDiagnostics` pour le raisonnement complet.
        SocketDiagnostics.shared.recordDisconnected(reason: reason)
        if let socket, let username = UserSession.shared.username, !username.isEmpty {
            let myId = UserSession.shared.myId ?? ""
            socket.emit(SocketEvent.leaveRoom, ["id": myId, "username": username])
        }
        // Port de `if ("io server disconnect".equals(reason)) attemptReconnect()` — reconnexion
        // manuelle uniquement si le SERVEUR a coupé la connexion (le client Socket.IO reconnecte
        // déjà automatiquement dans les autres cas, `TiinverSocket.connect` a `reconnects(true)`).
        if reason == "io server disconnect" { attemptReconnect() }
    }

    private func attemptReconnect() {
        guard !isReconnecting, let socket, socket.status != .connected else { return }
        isReconnecting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if let socket = self?.socket, socket.status != .connected { socket.connect() }
            self?.isReconnecting = false
        }
    }

    // MARK: - Messages entrants (port de `NewPrivateMessage`/`NewGroupMessage`)

    /// Port commun à `NewPrivateMessage`/`NewGroupMessage` — les deux listeners Android ont un
    /// corps IDENTIQUE hormis `chatManager.addMessage`/`addGroupMessage` (persistance
    /// `wk_messages`/`wk_gp_messages`) — consolidés ici, `isGroup` sélectionne le repository cible.
    private func handleNewMessage(_ data: [Any], isGroup: Bool) async {
        guard let payload = data.first as? [String: Any], let metas = Self.decodeMessages(from: payload) else { return }
        for meta in metas {
            if meta.object == "voicecall" {
                var packet = MessagePacket()
                packet.to = meta.from
                packet.from = meta.to
                packet.messageId = meta.messageId
                packet.type = meta.type
                packet.object = meta.object
                emitDelivered(packet)
                if !Self.isOnCall {
                    // Port de `lunchcall(Profile)` — appelé DIRECTEMENT côté Android (pas via
                    // LiveData), reproduit à l'identique : seuls `messageId`/`username`/`nikname`/
                    // `chatType` sont renseignés à ce stade (vérifié champ par champ sur
                    // `NewPrivateMessage`/`NewGroupMessage`) — `CallService.onStartCommand` re-dérive
                    // `RECEIVER = caller.getUsername()` plus tard, `CallCoordinator` fait de même
                    // via `profile.to ?? profile.username`.
                    var profile = ChatProfile()
                    profile.messageId = meta.messageId
                    profile.username = meta.from
                    profile.nikname = meta.nikname
                    profile.chatType = isGroup ? MessageLib.WireType.chatGroup : MessageLib.WireType.chat
                    Task { await CallCoordinator.shared.handleIncomingCall(profile: profile, chatType: profile.chatType ?? "") }
                } else {
                    // Port de `CallModel.ONCALL`/`sendCallLiveData` — un appel arrive alors qu'on
                    // est déjà en communication : publié comme événement (`CallCoordinator` décide
                    // de la réponse "occupé", voir `handle(_:)` cas `.onCall`).
                    callEvents.send(.onCall(data: Self.stringify(payload)))
                }
            } else if !isGroup {
                await processIncomingPrivateMessage(meta)
            } else {
                do {
                    // Port de `addGroupMessage` — voir `MessageRepository.swift` : écrit en réalité
                    // dans `wk_messages`/`MessageEntity` (PAS `wk_gp_messages`, table confirmée
                    // morte côté Android, voir l'en-tête de `MessageRepository.swift`).
                    if let packet = try await messages.addGroupMessage(meta) {
                        emitDelivered(packet)
                    }
                    chatEvents.send(.message(meta))
                    notifyIfNeeded(meta)
                    // Port de `ChatManager.addGroupMessage` (`verb.equals("deleteMember")`,
                    // `ChatManager.java:1330-1343`) — **ajouté le 2026-08-24
                    // (MIGRATION_PARITY_AUDIT_V4.md V4-F-039, Phase B P2)**. Placé ici (couche
                    // Realtime, qui possède déjà l'accès socket) plutôt que dans
                    // `MessageRepository.addGroupMessage` (couche Storage pure, cité par l'audit
                    // mais qui n'a aucun accès socket — layering délibérément séparé dans ce
                    // portage). `leaveRoom` est émis INCONDITIONNELLEMENT pour TOUT message
                    // `deleteMember` de groupe — vérifié ligne par ligne : contrairement à ce que
                    // suggère le texte de l'audit ("si l'utilisateur courant est retiré"), Android
                    // n'entoure PAS cet appel précis d'un `if (meta.getTo().equals(myUsername))`
                    // (ce `if` ne gate QUE le flag `USER_ROOM_MEMBER`, PAS l'émission `leaveRoom`
                    // juste en dessous) — reproduit fidèlement tel quel, même si cela ressemble à
                    // un bug Android (quitter la room socket même quand c'est un AUTRE membre qui a
                    // été retiré), sans le "corriger" silencieusement.
                    //
                    // **Non reproduits, gap documenté** : (1) la suppression de la ligne "USER_URI"
                    // en cache local (`ChatManager.java:1331-1332`) — pas d'équivalent dans ce
                    // portage, la liste des membres est TOUJOURS relue en direct depuis le réseau
                    // (`GroupRepository.fetchMembers`, voir tête de `GroupDetailView.swift`), aucune
                    // ligne locale ne peut rester périmée à purger ; (2) le flag persistant
                    // `USER_ROOM_MEMBER+token` (`Settings.setBooleanPreference`, `ChatManager.java:
                    // 1334,1346`) — vérifié que son SEUL site de lecture (`ActivityMsg.java:200`,
                    // `isGroupMember = Settings.getBooleanPreference(...)`) est IMMÉDIATEMENT
                    // écrasé par `isGroupMember = data.isGroupMember()` à la ligne 209 suivante, sans
                    // branche intermédiaire qui l'utiliserait — code mort à effet nul, non porté
                    // (voir consigne Phase B : ne pas porter du code Android mort/inutilisé).
                    if meta.verb == "deleteMember" {
                        leaveRoom(["receiver": meta.token ?? "", "packet": ""], chatType: ChatType.group.wireValue)
                    }
                } catch {
                    print("❌ ChatRepository.handleNewMessage (groupe):", error)
                }
            }
        }
    }

    /// Port du corps de la branche `!isGroup` de `NewPrivateMessage` (`ChatManager.addMessage`,
    /// puis `sendLiveData`/`fcms.notificationShow`) — **factorisée (2026-09-04)** hors de
    /// `handleNewMessage` pour être réutilisée à l'identique par `fetchPendingPrivateMessages`
    /// ci-dessous (filet HTTPS), exactement comme Android appelle la MÊME méthode
    /// `chatManager.addMessage(meta)` depuis le listener socket `NewPrivateMessage` ET depuis
    /// `ChatManager.prepareMessage` (repli HTTP `TiinverSyncWorker.getPrivateMessage`) — un seul
    /// pipeline de persistance/notification, deux déclencheurs.
    private func processIncomingPrivateMessage(_ meta: MessageLib) async {
        do {
            // Port de `addMessage` — voir `MessageRepository.swift` pour la persistance
            // (`wk_messages`/`MessageEntity`).
            if let packet = try await messages.addMessage(meta) {
                emitDelivered(packet)
            }
            chatEvents.send(.message(meta))
            notifyIfNeeded(meta)
        } catch {
            print("❌ ChatRepository.processIncomingPrivateMessage:", error)
        }
    }

    /// Port de `MyFirebaseMessagingService.onMessageReceived` → `TiinverSyncWorker.
    /// getPrivateMessage` (`:141-165`, `GET message/{myId}`) → `ChatManager.prepareMessage
    /// (JSONObject, false)` (`ChatManager.java:959-1021`) — filet de récupération HTTPS des
    /// messages privés en attente, déclenché à la réception d'un push (voir `AppDelegate.
    /// didReceiveRemoteNotification`), PAS un scan périodique en tâche de fond.
    ///
    /// **Ajouté (2026-09-04, audit forensique CHAT — item "absence du fallback HTTPS de
    /// réception")** — confirmé qu'Android reçoit RÉELLEMENT une partie substantielle de ses
    /// messages privés par ce chemin, pas seulement par Socket.IO :
    /// `MyFirebaseMessagingService.onMessageReceived` déclenche INCONDITIONNELLEMENT ce `GET
    /// message/{myId}` À CHAQUE push reçu, dont la réponse alimente le MÊME pipeline persistance/
    /// UI que le socket (`ChatManager.prepareMessage` appelle `chatManager.addMessage(meta)`, la
    /// méthode EXACTE qu'utilise aussi le listener socket `NewPrivateMessage`). Reproduit ici en
    /// réutilisant `processIncomingPrivateMessage` (factorisée ci-dessus) plutôt qu'un second
    /// pipeline parallèle — même enveloppe `{"data":[MessageLib,...]}` que le payload socket
    /// (vérifié : `ChatManager.prepareMessage` fait `js.getJSONArray("data")`, identique à
    /// `NewPrivateMessage`, tous deux décodables par `Self.decodeMessages(from:)` sans distinction).
    /// Le délai fixe de 2s d'Android (`WorkRequest.setInitialDelay`) n'est PAS reproduit — aucune
    /// contrainte système équivalente (WorkManager/contrainte réseau) ne le justifie côté iOS,
    /// l'appel se fait dès la réception du push comme le reste de `didReceiveRemoteNotification`.
    ///
    /// **Portée volontairement réduite** : seul `message/{myId}` (messages PRIVÉS) est porté — pas
    /// `group/message/{myId}` (endpoint distinct, `TiinverSyncWorker.getGroupMessage`, jamais
    /// mentionné dans le rapport forensique qui a motivé ce correctif), ni la re-livraison
    /// `voicecall`/`missedvoicecall` (un appel entrant reconstitué plusieurs secondes après coup
    /// via ce filet n'aurait aucun sens fonctionnel côté CallKit — la signalisation d'appel garde
    /// son propre mécanisme de réveil dédié, PushKit/VoIP, module 12, jamais concerné par ce gap).
    func fetchPendingPrivateMessages() async {
        guard let myId = UserSession.shared.myId, !myId.isEmpty else { return }
        guard let value = try? await APIClient.shared.get("message/\(myId)"),
            let dict = value.toDictionary(),
            let metas = Self.decodeMessages(from: dict)
        else { return }
        for meta in metas {
            guard meta.object != "voicecall", meta.object != "missedvoicecall" else { continue }
            await processIncomingPrivateMessage(meta)
        }
    }

    /// Port de `NewPrivateMessage`/`NewGroupMessage` → `fcms.notificationShow(context, meta)`
    /// (`ChatManager.java:1150/1254`) → `NotificationUtils.displayNotificationOrPushMessage` →
    /// `show(...)`. **Ajouté le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-075 NOTIF-04, Phase B
    /// P0-5)** — `LocalNotificationBuilder.chatMessageNotificationContent`/`.present` existaient
    /// déjà (déjà écrits pour porter `displayNotificationOrPushMessage`) mais n'étaient appelés
    /// NULLE PART depuis ce fichier, confirmé par recherche exhaustive avant ce correctif — un
    /// message entrant persistait bien localement et mettait à jour l'UI ouverte
    /// (`chatEvents.send`), mais ne déclenchait jamais de notification système.
    ///
    /// **Vérifié avant d'écrire ce correctif, pas supposé** : `NotificationUtils.show(...)`
    /// (lignes 342-381) N'UTILISE PAS `isActivityChatContext`/`isMainActivityContext` (calculés
    /// dans le constructeur mais jamais lus dans `show`/`displayNotificationOrPushMessage`) — la
    /// notification Android s'affiche donc INCONDITIONNELLEMENT à chaque message entrant, même si
    /// la conversation exacte est déjà ouverte à l'écran. Reproduit fidèlement ici : PAS de garde
    /// "conversation déjà ouverte" ajoutée qui n'existe pas côté Android, même si cela peut
    /// sembler redondant en UX.
    ///
    /// Exclu délibérément : `object == "voicecall"` — déjà géré par `CallCoordinator`/CallKit
    /// (UI d'appel entrant native iOS), une notification locale générique EN PLUS serait non
    /// standard sur cette plateforme (contrairement à Android qui n'a pas d'équivalent CallKit à
    /// respecter) ; branché dans le `if meta.object == "voicecall"` séparé ci-dessus, jamais dans
    /// cette fonction.
    private func notifyIfNeeded(_ meta: MessageLib) {
        let title = meta.nikname?.isEmpty == false ? meta.nikname! : (meta.username ?? meta.from ?? "Tiinver")
        let payload = LocalNotificationBuilder.ChatMessagePayload(
            title: title, message: meta.message ?? "", object: meta.object ?? "text"
        )
        LocalNotificationBuilder.present(LocalNotificationBuilder.chatMessageNotificationContent(payload))
    }

    /// Corrigé (V3-F-116, CHAT complémentaire) : la persistance Core Data était déjà correcte, mais
    /// aucun événement Combine n'était émis après — si la conversation concernée était déjà ouverte
    /// à l'écran, le message resté visible jusqu'à la fermeture/réouverture. `chatEvents.send(
    /// .messageDeleted(...))` après chaque persistance, même motif que `handleResponse`/
    /// `.messageStatus` pour les accusés de réception.
    private func handleDeleteMessage(_ data: [Any]) async {
        guard let payload = data.first as? [String: Any], let metas = Self.decodeMessages(from: payload) else { return }
        for meta in metas {
            try? await messages.deleteMessageForEveryOne(meta, isFromServer: true)
            if let messageId = meta.messageId, !messageId.isEmpty {
                chatEvents.send(.messageDeleted(messageId: messageId))
            }
        }
    }

    private func handleResponse(_ data: [Any]) async {
        guard let dict = data.first as? [String: Any],
            let messageId = dict["messageId"] as? String,
            let receiver = dict["receiver"] as? String,
            let response = dict["response"] as? String
        else { return }
        let status: MessageDeliveryStatus?
        switch response {
        case "sended": status = .sent
        case "delivered": status = .delivered
        case "displayed": status = .displayed
        case "reproduced": status = .reproduced
        default: status = nil
        }
        guard let status else { return }
        try? await messages.updateStatus(messageId: messageId, status: status.rawValue)
        chatEvents.send(.messageStatus(messageId: messageId, receiver: receiver, status: status))
    }

    /// Port de `ChatManager.updateMessageStatus(JSONObject)` — voir le commentaire sur le listener
    /// `offlineStatus` ci-dessus pour le contexte du double-rôle de cet événement.
    private func handleOfflineStatus(_ data: [Any]) async {
        guard let payload = data.first as? [String: Any], let metas = Self.decodeMessages(from: payload) else { return }
        for meta in metas {
            guard let messageId = meta.messageId else { continue }
            try? await messages.updateStatus(messageId: messageId, status: meta.status)
        }
    }

    /// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-030, Phase B P2)** — avant ce
    /// correctif, les deux branches ci-dessous exécutaient EXACTEMENT le même code
    /// (`callEvents.send(.onCall(...))`), alors qu'Android (`ChatRepository.onCall`,
    /// `:449-469`) diverge réellement : `!CallService.isOnCall` → `lunchcall(Profile)` établit un
    /// VRAI appel entrant (CallKit) ; `CallService.isOnCall` → publie juste `CallModel.ONCALL`
    /// (détection d'occupation, géré par `CallCoordinator.handle(.onCall)`). Le port précédent
    /// supposait cet événement `ROOM.CALL` mort/jamais émis indépendamment de "voicecall" — rien
    /// ne le garantit côté serveur, et le listener Android correspondant est bien vivant/réactif.
    private func handleIncomingCall(_ data: [Any]) {
        guard let payload = data.first else { return }
        if !Self.isOnCall {
            // Port de `lunchcall(gson.fromJson(args[0].toString(), Profile.class))` — `ROOM.CALL`
            // porte un `Profile` JSON DIRECT (contrairement à "voicecall", enveloppé dans un
            // `MessageLib` reconstruit champ par champ dans `handleNewMessage`), décodé tel quel
            // avec le même helper `decodeProfile` déjà utilisé pour les événements PBS
            // (`onStartRoom`/`onStartPrivatePBS`).
            guard let profile = Self.decodeProfile(Self.stringify(payload)) else { return }
            Task { await CallCoordinator.shared.handleIncomingCall(profile: profile, chatType: profile.chatType ?? "") }
        } else {
            callEvents.send(.onCall(data: Self.stringify(payload)))
        }
    }

    /// Port de `unifiedWebrtcMessage` — double-route un même événement `webrtcMessage` : vers les
    /// appels si `CallService.isOnCall`, sinon vers Shareboard/PBS (les deux fonctionnalités
    /// partagent CE MÊME nom d'événement côté serveur, distingué uniquement par l'état côté
    /// client — confirmé en lisant le commentaire Android "webrtcMessage → Call"/"webrtcMessage →
    /// PBS").
    private func handleUnifiedWebrtcMessage(_ data: [Any]) {
        guard let payload = data.first else { return }
        let dataString = Self.stringify(payload)
        if Self.isOnCall {
            callEvents.send(.webrtcMessage(data: dataString))
        } else {
            chatEvents.send(.pbs(.webrtcMessage(data: dataString)))
        }
    }

    // MARK: - Émission (port de la section "ÉMISSIONS SOCKET")

    func sendMessage(_ packet: MessagePacket) { socket?.emit(SocketEvent.newMessage, packet.packetJSON()) }
    func sendScheduledMessage(_ packet: MessagePacket) { socket?.emit(SocketEvent.scheduledNewMessage, packet.packetJSON()) }
    func updateMessage(_ packet: MessagePacket) { socket?.emit(SocketEvent.updateMessage, packet.packetJSON()) }
    func sendGroupMessage(_ packet: MessagePacket) { socket?.emit(SocketEvent.newGroupMessage, packet.packetForGroupJSON()) }
    func sendScheduledGroupMessage(_ packet: MessagePacket) { socket?.emit(SocketEvent.scheduledNewGroupMessage, packet.packetForGroupJSON()) }
    /// **Bug Android reproduit fidèlement** : `ChatRepository.updateGroupMessage` (ligne 959) émet
    /// `p.getPacketJson()` (l'enveloppe CHAT PRIVÉ — `messageId`/`type`/`to`/`from`/…) et NON
    /// `p.getPacketForGroupJson()` (`messageId`/`groupId`/`receiver`/…) contrairement à
    /// `sendGroupMessage`/`sendScheduledGroupMessage` (lignes 963-964, eux corrects) — incohérence
    /// réelle du côté Android, vérifiée en comparant les 3 méthodes côte à côte, PAS "corrigée" ici
    /// pour rester compatible avec ce que le serveur reçoit réellement pour une mise à jour de
    /// message de groupe.
    func updateGroupMessage(_ packet: MessagePacket) { socket?.emit(SocketEvent.updateGroupMessage, packet.packetJSON()) }
    /// Port de `ChatRepository.deletePrivateMessage(MessagePacket)` (ligne 962) — **bug trouvé et
    /// corrigé dans CE portage (pas dans l'original)** : la première version de ce fichier émettait
    /// à tort sur `SocketEvent.deletePrivateMessage` ("delete private message" = `ROOM.
    /// DELETE_PRIVATE_MESSAGE`, une constante différente utilisée par `ChatRepository.deleteMessage`
    /// — voir `deleteMessage(messageId:data:chatType:)` ci-dessous) au lieu de `SocketEvent.
    /// onDeletePrivateMessage` ("on delete private message" = `ROOM.ON_DELETE_PRIVATE_MESSAGE`),
    /// vérifié en relisant l'émission Android réelle ligne par ligne.
    func deletePrivateMessage(_ packet: MessagePacket) { socket?.emit(SocketEvent.onDeletePrivateMessage, packet.packetJSON()) }

    /// Port de `ChatRepository.deleteMessage(String messageId, Object data, String chatType)`
    /// (lignes 966-971) — DEUXIÈME chemin de suppression, distinct de `deletePrivateMessage`
    /// ci-dessus : pour un chat privé, émet `data` BRUT (pas une enveloppe `MessagePacket`) sur
    /// `ROOM.DELETE_PRIVATE_MESSAGE` ; pour un groupe, appelle `onDeleteMessage` (requête REST, PAS
    /// le socket). `chatType` comparé à `ChatType.getChatType(ChatType.GROUP)` côté Android →
    /// `ChatType.group.wireValue` ici.
    func deleteMessage(messageId: String, data: [String: Any], chatType: String) async {
        if chatType != ChatType.group.wireValue {
            socket?.emit(SocketEvent.deletePrivateMessage, data)
        } else {
            try? await onDeleteMessage(messageId: messageId)
        }
    }

    /// Port de `ChatManager.onDeleteMessage(String messageId)` — requête REST `GET deletemessage/
    /// {id}` (`TransportData.get`, PAS un événement socket), utilisée pour la suppression d'un
    /// message de GROUPE dans `deleteMessage(messageId:data:chatType:)` ci-dessus.
    @discardableResult
    func onDeleteMessage(messageId: String) async throws -> JSONValue {
        try await APIClient.shared.get("deletemessage/\(messageId)")
    }

    /// Port de `ChatRepository.sendMessageState(MessagePacket)` (ligne 990) — accusé de lecture
    /// ("displayed"/message vu), réutilise `getDelivredPacketJson()` comme l'original (mêmes 5
    /// champs que `delivred`/`typing`).
    func sendMessageState(_ packet: MessagePacket) { socket?.emit(SocketEvent.displayed, packet.delivredPacketJSON()) }

    func emitDelivered(_ packet: MessagePacket) { socket?.emit(SocketEvent.delivered, packet.delivredPacketJSON()) }
    func emitTyping(_ packet: MessagePacket) { socket?.emit(SocketEvent.typing, packet.typingPacketJSON) }
    func emitStopTyping(_ packet: MessagePacket) { socket?.emit(SocketEvent.stopTyping, packet.typingPacketJSON) }
    func emitPresence(username: String) { socket?.emit(SocketEvent.presence, username) }

    // MARK: - Signalisation d'appel (module 12) — port de `ChatRepository.onCall`/`onCallBusy`/
    // `onRinging`/`onCallEnd`/`onVoice`/`onWebrtcMessage`/`accepCall` (lignes 974-988, lues en
    // entier au module 11 mais délibérément PAS émises avant que le module 12 en ait besoin).
    // Toutes suivent le même motif : événement de groupe SANS suffixe, événement privé AVEC
    // `ROOM.PRIVATE_ACTION` ("PrivateAction") concaténé — vérifié identique pour les 6.

    private func callEventName(_ base: String, chatType: String) -> String {
        chatType == ChatType.group.wireValue ? base : base + SocketEvent.privateAction
    }

    func onCall(_ packet: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.call, chatType: chatType), packet) }
    /// Port de `onCallBusy` — PAS de variante groupe côté Android (`ROOM.CALLBASIC+PRIVATE_ACTION`
    /// systématique, la signalisation d'appel n'existe qu'en 1:1 dans ce protocole).
    func onCallBusy(_ packet: [String: Any]) { socket?.emit(SocketEvent.callBasic + SocketEvent.privateAction, packet) }
    func onRinging(_ packet: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.ringing, chatType: chatType), packet) }
    func onCallEnd(_ packet: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.endCall, chatType: chatType), packet) }
    func accepCall(_ packet: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.acceptCall, chatType: chatType), packet) }
    /// Port de `onWebrtcMessage(Object, String)` — ÉMISSION (distincte de
    /// `handleUnifiedWebrtcMessage`, la RÉCEPTION, ci-dessus).
    func emitWebrtcMessage(_ packet: [String: Any], chatType: String) {
        socket?.emit(callEventName(SocketEvent.webrtcMessage, chatType: chatType), packet)
    }

    /// Port de `ChatRepository.buildCallMessageLib` (helper privé) — construit le `MessageLib`
    /// commun à `calling`/`notifyMissedCall` (`object`/`verb` = le type d'appel : `"voicecall"`/
    /// `"missedvoicecall"`).
    private func buildCallMessageLib(profile: ChatProfile, chatType: String, object: String) -> MessageLib {
        var mlib = MessageLib()
        mlib.conversationId = profile.conversationId
        mlib.message = object
        mlib.type = chatType
        mlib.object = object
        mlib.verb = object
        mlib.status = 0
        mlib.vu = "false"
        mlib.origin = "ios"
        mlib.share = ""
        let now = Date()
        mlib.deliverTime = String(Int64(now.timeIntervalSince1970))
        mlib.profile = profile.profilePicture
        mlib.stamp = String(Int64(now.timeIntervalSince1970 * 1000))
        return mlib
    }

    // MARK: - Signalisation Shareboard/PBS (module 13) — port de `startRoom`/`joinRoom`/
    // `leaveRoom`/`sendData`/`onTouchlistener`/`onNextPage`/`onBeforePage` (lignes 980-987 de
    // `ChatRepository.java`) — même motif `group ? base : base+PrivateAction` que la signalisation
    // d'appel ci-dessus (`callEventName`, réutilisé tel quel).

    func joinRoom(_ data: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.joinRoom, chatType: chatType), data) }
    func leaveRoom(_ data: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.leaveRoom, chatType: chatType), data) }
    func startRoom(_ data: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.startRoom, chatType: chatType), data) }
    /// Port de `sendData` — diffusion socket d'un `EditorData` encodé (repli quand le canal de
    /// données WebRTC n'est pas encore connecté, voir `PBSViewModel.sendObject`).
    func sendPBSData(_ data: [String: Any], chatType: String) {
        socket?.emit(callEventName(SocketEvent.onReceiveData, chatType: chatType), data)
    }
    /// Port de `onTouchlistener` — repli socket du flux de dessin quand le canal de données WebRTC
    /// n'est pas encore connecté (voir `isWebRtcConnected` dans `FragmentPbs`/`PBSViewModel`).
    func onTouchlistener(_ data: [String: Any], chatType: String) {
        socket?.emit(callEventName(SocketEvent.onTouchListener, chatType: chatType), data)
    }
    func onNextPage(_ data: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.nextPage, chatType: chatType), data) }
    func onBeforePage(_ data: [String: Any], chatType: String) { socket?.emit(callEventName(SocketEvent.beforePage, chatType: chatType), data) }
    /// Port de `ChatRepository.calling` — signale un appel sortant EN COURS en envoyant un message
    /// `"voicecall"` normal via le canal de chat habituel (PAS un événement dédié) — c'est ce
    /// message qui déclenche `lunchcall`/l'écran d'appel entrant chez le destinataire, voir
    /// `handleNewMessage` (module 11) qui spécialise déjà `object == "voicecall"`.
    func calling(profile: ChatProfile, chatType: String, messageId: String) {
        var mlib = buildCallMessageLib(profile: profile, chatType: chatType, object: "voicecall")
        mlib.messageId = messageId
        if chatType == ChatType.group.wireValue {
            mlib.groupId = profile.groupId
            mlib.token = profile.token
            mlib.groupName = profile.groupName
            sendGroupMessage(mlib)
        } else {
            mlib.to = profile.to
            mlib.from = profile.username
            mlib.sender = UserSession.shared.myId
            mlib.receiver = profile.receiver
            sendPrivateMessage(mlib)
        }
    }

    /// Port de `ChatRepository.notifyMissedCall` — même principe que `calling`, message
    /// `"missedvoicecall"` envoyé via `updateMessage`/`updateGroupMessage` (PAS `sendMessage`,
    /// vérifié : l'original appelle bien `updateMessage(chatManager.sendPrivateMessage(...))`, pas
    /// `sendMessage`, asymétrie réelle avec `calling` reproduite telle quelle).
    func notifyMissedCall(profile: ChatProfile, chatType: String, object: String, messageId: String) {
        var mlib = buildCallMessageLib(profile: profile, chatType: chatType, object: object)
        if chatType == ChatType.group.wireValue {
            mlib.groupId = profile.groupId
            mlib.token = profile.token
            mlib.groupName = profile.groupName
            mlib.groupType = profile.groupType
            let packet = MessagePacket(fromGroup: mlib, currentNikname: UserSession.shared.nikname ?? "", myId: UserSession.shared.myId ?? "")
            updateGroupMessage(packet)
        } else {
            mlib.to = profile.to
            mlib.from = profile.username
            mlib.messageId = messageId
            mlib.sender = UserSession.shared.myId
            mlib.nikname = profile.nikname
            mlib.receiver = profile.receiver
            let packet = MessagePacket(fromPrivate: mlib, currentUsername: UserSession.shared.username ?? "")
            updateMessage(packet)
        }
    }

    /// Port de `sendPrivateMessage(Context, MessageLib, boolean)` — construit le `MessagePacket`
    /// (voir `ChatManager.sendPrivateMessage`, reproduit via `MessagePacket(from:currentUsername:)`
    /// ci-dessous) puis émet. Persistance locale (`insertTextMessage`) laissée à l'appelant, comme
    /// l'original ne la fait pas non plus dans cette méthode précise (elle est appelée séparément
    /// par l'écran de chat, pas encore porté).
    func sendPrivateMessage(_ mlib: MessageLib) {
        let packet = MessagePacket(fromPrivate: mlib, currentUsername: UserSession.shared.username ?? "")
        sendMessage(packet)
    }

    func sendGroupMessage(_ mlib: MessageLib) {
        let packet = MessagePacket(fromGroup: mlib, currentNikname: UserSession.shared.nikname ?? "", myId: UserSession.shared.myId ?? "")
        sendGroupMessage(packet)
    }

    /// Port de `ChatRepository.deletePrivateMessage(Context, MessageLib)` — construit le paquet via
    /// `MessagePacket(forDeletePrivate:)` (champs sourcés différemment de `sendPrivateMessage`, voir
    /// ce initialiseur) puis émet sur `ROOM.ON_DELETE_PRIVATE_MESSAGE`.
    func deletePrivateMessage(_ mlib: MessageLib) {
        let packet = MessagePacket(
            forDeletePrivate: mlib, currentUsername: UserSession.shared.username ?? "", myId: UserSession.shared.myId ?? "")
        deletePrivateMessage(packet)
    }

    /// Port de `ChatRepository.deleteGroupMessage(Context, MessageLib)` — **PAS un événement dédié** :
    /// l'original appelle `updateGroupMessage(chatManager.deleteGroupMessage(context, mlib))`, donc
    /// la suppression d'un message de groupe "pour tout le monde" passe par le canal
    /// `ROOM.UPDATE_GROUP_MESSAGE` (avec `verb`/`object` positionnés à `"deletemessage"` par
    /// l'appelant sur le `MessageLib` fourni, pas encore lu — `ChatFragmentTest.java`), pas par un
    /// événement de suppression séparé.
    func deleteGroupMessage(_ mlib: MessageLib) {
        let packet = MessagePacket(
            forDeleteGroup: mlib, currentNikname: UserSession.shared.nikname ?? "",
            myId: UserSession.shared.myId ?? "", currentProfile: UserSession.shared.profile ?? "")
        updateGroupMessage(packet)
    }

    // MARK: - Helpers

    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-090 SILENT-01, Phase B P0-1)** —
    /// décodait le tableau ENTIER en un seul appel (`decode([MessageLib].self, ...)`) : un décodage
    /// Swift `Array<Codable>` échoue en bloc dès le PREMIER élément mal formé (`width`/`height`/
    /// `duration` etc. envoyés en nombre plutôt qu'en chaîne par le serveur, cas déjà rencontré et
    /// corrigé pour Feed/Profil/Contacts/Groupes mais jamais reporté ici) — un seul message
    /// "problématique" dans un lot socket entrant (`new message`/`new message group`/suppression/
    /// statut hors-ligne) faisait disparaître TOUT le lot, silencieusement (`try?`), sans aucune
    /// trace. Remplacé par le même motif per-item + diagnostic déjà utilisé dans
    /// `FeedRepository.fetchTimeline`/`ProfileRepository`/`ContactsRepository`/`GroupRepository` :
    /// un message individuellement malformé est désormais écarté seul, pas tout le lot.
    private static func decodeMessages(from payload: [String: Any]) -> [MessageLib]? {
        guard let dataArray = payload["data"] as? [Any] else { return nil }
        let decoder = JSONDecoder()
        let decoded = dataArray.compactMap { item -> MessageLib? in
            guard let itemData = try? JSONSerialization.data(withJSONObject: item) else {
                print("CHAT SOCKET: impossible de sérialiser un message reçu — item=\(item)")
                return nil
            }
            do {
                return try decoder.decode(MessageLib.self, from: itemData)
            } catch {
                print("CHAT SOCKET: échec de décodage d'un message reçu — error=\(error) item=\(item)")
                return nil
            }
        }
        if decoded.count != dataArray.count {
            print("CHAT SOCKET: reçu \(dataArray.count) message(s), seulement \(decoded.count) décodé(s) avec succès — \(dataArray.count - decoded.count) silencieusement perdu(s), voir échecs de décodage ci-dessus")
        }
        return decoded
    }

    private static func decodeProfile(_ jsonString: String) -> ChatProfile? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatProfile.self, from: data)
    }

    private static func stringify(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        guard let data = try? JSONSerialization.data(withJSONObject: value),
            let s = String(data: data, encoding: .utf8)
        else { return "" }
        return s
    }
}
