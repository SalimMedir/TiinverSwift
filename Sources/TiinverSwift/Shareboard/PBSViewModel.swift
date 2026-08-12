import Combine
import Foundation
import WebRTC

/// Port de `messagerie/ui/FragmentPbs.java` (810 lignes, lu en entier) + `messagerie/model/
/// PBSViewModel.java`/`PBSModel.java` (58+22 lignes) — orchestration du Shareboard temps réel :
/// pilote `PBSCanvasEngine` (moteur, partagé avec le module 14), une INSTANCE PROPRE de
/// `WebRTCConnection` (voir avertissement ci-dessous) et la signalisation socket (`ChatRepository`,
/// section "Signalisation Shareboard/PBS" ajoutée ci-contre). Un seul coordinateur `@MainActor`
/// plutôt que Fragment+ViewModel séparés, même choix que `CallCoordinator` (module 12) et pour la
/// même raison (pas d'équivalent iOS direct au cycle de vie Fragment Android).
///
/// **Écart délibéré vis-à-vis d'Android, documenté** : `FragmentPbs.webrtc =
/// RTConnection2.getInstance(requireActivity())` réutilise le MÊME singleton que `CallService`
/// (module 12) — un choix Android qui empêche structurellement un appel ET un Shareboard actifs
/// simultanément (ils se disputeraient la même `RTConnection2`). Ici, `CallCoordinator` et
/// `PBSViewModel` possèdent chacun leur PROPRE instance de `WebRTCConnection` (classe déjà non-
/// singleton, `final class` instanciable, voir `Calls/WebRTCConnection.swift`) : aucun point
/// d'entrée UI n'ouvre le Shareboard pendant qu'un appel est actif (`CallCoordinator.state`
/// contrôle seul l'affichage plein écran de `CallView`), donc la mutuelle exclusion d'Android n'est
/// PAS un comportement observable à préserver — la dupliquer aurait ajouté un couplage artificiel
/// entre deux fonctionnalités indépendantes pour un bénéfice nul dans ce portage.
@MainActor
final class PBSViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case waiting
        case connecting
        case connected
        case closed
    }

    @Published private(set) var connectionState: ConnectionState = .idle
    @Published var showStartButton: Bool
    @Published private(set) var connectedUserCount = 1

    let engine = PBSCanvasEngine()

    private let webrtc = WebRTCConnection()
    private let chatRepository = ChatRepository.shared
    private let receiver: String
    private let chatType: String
    private let profile: ChatProfile
    private var isWebRtcConnected = false
    private var isConnectedOnce = false
    private var seenMessageIds: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    /// Port de `FragmentPbs.STATUS` — `1` affiche le bouton "démarrer" (créateur du salon), toute
    /// autre valeur rejoint immédiatement un salon déjà ouvert par un pair.
    init(profile: ChatProfile, receiver: String, chatType: String, status: Int) {
        self.profile = profile
        self.receiver = receiver
        self.chatType = chatType
        showStartButton = status == 1
        engine.username = UserSession.shared.username
        webrtc.delegate = self
        engine.onLocalTouch = { [weak self] event in self?.sendTouch(event) }
        engine.onLocalObjectPlaced = { [weak self] data in self?.sendObject(data) }
        engine.onLocalPageChange = { [weak self] isNext in self?.sendPageChange(isNext: isNext) }
        subscribeToPBSEvents()
        if status != 1 {
            connectionState = .waiting
            fetchTurnAndStart(isOutgoing: false)
            chatRepository.joinRoom(packet(profile), chatType: chatType)
        }
    }

    /// Port du `startbtn.setOnClickListener` — le créateur du salon démarre effectivement la
    /// connexion WebRTC et notifie les pairs.
    func startTapped() {
        showStartButton = false
        connectionState = .waiting
        fetchTurnAndStart(isOutgoing: true)
        chatRepository.startRoom(packet(profile), chatType: chatType)
    }

    /// Port de `FragmentPbs.onStop` — quitte le salon et libère la connexion.
    func leave() {
        chatRepository.leaveRoom(packet(profile), chatType: chatType)
        webrtc.disconnect()
        seenMessageIds.removeAll()
    }

    /// Port de `PBSCompound.setMicrophoneMute` — micro coupé par défaut (`callBtn` non sélectionné
    /// au départ, port de `CallButton` dans `PBSCompound.onClick`).
    func setMicrophoneMuted(_ muted: Bool) {
        webrtc.setEnabled(!muted)
        webrtc.setSpeakerphoneOn(true)
    }

    // MARK: - TURN + démarrage WebRTC (port de `fetchTurnAndStart`/`startWebRTC`, IDENTIQUE au
    // motif de `CallCoordinator`, même endpoint `call/turn-credentials` — `TurnCredentialsFetcher`
    // est partagé par `CallService` ET `FragmentPbs` côté Android, pas une supposition).

    private func fetchTurnAndStart(isOutgoing: Bool) {
        Task {
            if let credentials = try? await Self.fetchTurnCredentials() {
                webrtc.setTurnCredentials(credentials)
            }
            if isOutgoing { configureOutgoing() } else { configureIncoming() }
        }
    }

    private static func fetchTurnCredentials() async throws -> TurnCredentials {
        let value = try await APIClient.shared.post([:], endpoint: "call/turn-credentials")
        guard let data = value.rawData else { throw JSONError.typeMismatch("turn-credentials") }
        return try JSONDecoder().decode(TurnCredentials.self, from: data)
    }

    /// Port de `FragmentPbs.configForOutgoingCall` — "outgoing" ici veut dire "je rejoins un salon
    /// déjà ouvert" (celui qui a appuyé sur "démarrer" est le RECEVEUR/initiateur, symétrie
    /// identique à `CallCoordinator`, vérifiée ligne à ligne contre l'original).
    private func configureOutgoing() {
        webrtc.setInitiator(false)
        webrtc.setPolite(true)
        webrtc.setAudioEnabled(true)
        webrtc.setVideoEnabled(false)
        webrtc.setEnabled(false)
        webrtc.start(withDataChannel: false)
    }

    /// Port de `FragmentPbs.configForIncomingCall` — "incoming" veut dire "j'ai démarré le salon" :
    /// initiateur de l'offre WebRTC ET créateur du canal de données (le Shareboard EN A besoin dans
    /// les deux sens, contrairement aux appels — voir le bug corrigé dans `WebRTCConnection.swift`).
    private func configureIncoming() {
        webrtc.setInitiator(true)
        webrtc.setPolite(false)
        webrtc.setAudioEnabled(true)
        webrtc.setVideoEnabled(false)
        webrtc.setEnabled(false)
        webrtc.start(withDataChannel: true)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.webrtc.onNegotiationNeeded()
        }
    }

    // MARK: - Envoi (port de `PBStreamActionListener` implémenté dans `FragmentPbs.onCreateView`)

    /// Port de `onSendPBSTouchSreamListner(MotionEventData)` — canal de données si connecté, repli
    /// socket sinon (vérifié : Android envoie TOUJOURS `mPBSViewModel.onTouchlistener` en LUS, même
    /// connecté, mais ne branche `webrtc.sendData` QUE si `isWebRtcConnected` ; reproduit tel quel).
    private func sendTouch(_ event: PBSTouchEvent) {
        let compressed = GraphicMessageCodec.encodeTouchEvent(event)
        if isWebRtcConnected {
            webrtc.sendData(compressed)
        } else {
            chatRepository.onTouchlistener(packet(raw: compressed), chatType: chatType)
        }
    }

    /// Port de `onSendPBStreamData(EditorData, String action)` — TOUJOURS par socket (Android ne
    /// branche jamais cette donnée sur le canal WebRTC, seul le flux tactile l'utilise).
    private func sendObject(_ data: PBSEditorData) {
        let compressed = GraphicMessageCodec.encodeEditorData(data)
        chatRepository.sendPBSData(packet(raw: compressed), chatType: chatType)
    }

    /// Port de `onNextPage`/`onBeforePage` — **PAS de clé `"packet"` ici**, contrairement à tous les
    /// autres émetteurs de ce fichier (vérifié : `FragmentPbs.PBStreamActionListener.onNextPage`/
    /// `onBeforePage` ne mettent QUE `"receiver"` dans le `JSONObject` envoyé).
    private func sendPageChange(isNext: Bool) {
        let payload = ["receiver": receiver]
        if isNext {
            chatRepository.onNextPage(payload, chatType: chatType)
        } else {
            chatRepository.onBeforePage(payload, chatType: chatType)
        }
    }

    // MARK: - Réception (port de l'`Observer<ChatModel>` de `onCreateView` + `onReceivePBStreamData`/
    // `setData`/`onWebrtcMessage`/`onJoinRoom`/`onLeftRoom`)

    private func subscribeToPBSEvents() {
        chatRepository.chatEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self, case .pbs(let pbsEvent) = event else { return }
                self.handle(pbsEvent)
            }
            .store(in: &cancellables)
    }

    private func handle(_ event: PBSEvent) {
        switch event {
        case .onReceiveData(let data):
            if GraphicMessageCodec.isTouchEvent(data), let touch = GraphicMessageCodec.decodeTouchEvent(data) {
                engine.receiveTouch(touch)
            } else if let object = GraphicMessageCodec.decodeEditorData(data) {
                engine.receiveObject(object)
            }
        case .onTouchListener(let data):
            guard let touch = GraphicMessageCodec.decodeTouchEvent(data) else { return }
            engine.receiveTouch(touch)
        case .nextPage:
            engine.receiveNextPage()
        case .precedentPage:
            engine.receivePreviousPage()
        case .webrtcMessage(let data):
            guard let data = data.data(using: .utf8), let message = try? JSONDecoder().decode(WebrtcData.self, from: data) else { return }
            webrtc.onMessage(message)
        case .joinRoom(let data), .onJoinPrivate(let data):
            guard let profile = Self.decodeProfile(data), !seenMessageIds.contains(profile.messageId ?? "") else { return }
            seenMessageIds.insert(profile.messageId ?? "")
            connectedUserCount += 1
        case .leaveRoom(let data):
            guard let profile = Self.decodeProfile(data), seenMessageIds.contains(profile.messageId ?? "") else { return }
            seenMessageIds.remove(profile.messageId ?? "")
            connectedUserCount = max(1, connectedUserCount - 1)
        case .onStart, .onStartPrivate:
            break // Port de `ONSTART`/`startWebRTC(false)` — déjà déclenché à l'initialisation ci-dessus.
        }
    }

    // MARK: - Helpers

    private func packet(_ profile: ChatProfile) -> [String: Any] {
        let data = (try? JSONEncoder().encode(profile)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ["receiver": receiver, "packet": data]
    }

    private func packet(raw: String?) -> [String: Any] {
        ["receiver": receiver, "packet": raw ?? ""]
    }

    private static func decodeProfile(_ jsonString: String) -> ChatProfile? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatProfile.self, from: data)
    }
}

// MARK: - WebRTCConnectionDelegate (port de `webrtc.setWebRTCMessageListener` dans `onCreateView`)

extension PBSViewModel: WebRTCConnectionDelegate {
    func webRTCConnection(_ connection: WebRTCConnection, didProduce message: WebrtcData) {
        guard let data = try? JSONEncoder().encode(message), let json = String(data: data, encoding: .utf8) else { return }
        chatRepository.emitWebrtcMessage(packet(raw: json), chatType: chatType)
    }

    func webRTCConnectionDidConnect(_ connection: WebRTCConnection) {
        connectionState = .connected
        isConnectedOnce = true
        isWebRtcConnected = true
    }

    func webRTCConnectionDidClose(_ connection: WebRTCConnection) {
        connectionState = .closed
        isWebRtcConnected = false
    }

    func webRTCConnectionDidFail(_ connection: WebRTCConnection) {
        isWebRtcConnected = false
    }

    func webRTCConnectionIsChecking(_ connection: WebRTCConnection) {
        connectionState = .connecting
    }

    /// Port de `DataChannelResultListener.onResult` — un message reçu sur le canal de données
    /// (dessin en temps réel, le chemin RAPIDE, distinct du repli socket ci-dessus).
    func webRTCConnection(_ connection: WebRTCConnection, didReceiveData text: String) {
        if GraphicMessageCodec.isTouchEvent(text), let touch = GraphicMessageCodec.decodeTouchEvent(text) {
            engine.receiveTouch(touch)
        } else if let object = GraphicMessageCodec.decodeEditorData(text) {
            engine.receiveObject(object)
        }
    }
}
