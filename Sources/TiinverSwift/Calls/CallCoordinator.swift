import AVFoundation
import CallKit
import Combine
import Foundation
import WebRTC

/// Port de `messagerie/service/CallService.java` (835 lignes, lu en entier) +
/// `messagerie/ui/call/CallViewModel.java` (110, entier) — orchestration centrale d'un appel :
/// pilote `WebRTCConnection` (moteur), `CallKitManager` (écran système/audio), `VoIPPushManager`
/// (réveil app tuée) et la signalisation socket (`ChatRepository.callEvents`/méthodes d'émission
/// d'appel, module 12 ci-dessus). Remplace `CallService`+`CallViewModel` par UN SEUL coordinateur
/// `@MainActor` plutôt que Service Android + ViewModel séparés — la séparation Android existait
/// pour des raisons de cycle de vie Android (Service survit à l'Activity), qui n'ont pas
/// d'équivalent iOS direct (pas de "Service" en arrière-plan indépendant équivalent hors
/// PushKit/CallKit, déjà gérés séparément ici).
///
/// **Asymétrie négociateur/poli PRÉSERVÉE À L'IDENTIQUE, vérifiée dans `CallService.
/// configForOutgoingCall`/`configForIncomingCall`** : l'APPELANT (`startOutgoingCall`) N'EST PAS
/// l'initiateur de l'offre WebRTC (`isInitiator=false`, `polite=true`) — c'est le RECEVEUR
/// (`acceptIncomingCall`) qui crée l'offre (`isInitiator=true`, `polite=false`). Contre-intuitif
/// mais vérifié à la lecture, pas deviné.
@MainActor
final class CallCoordinator: ObservableObject {
    static let shared = CallCoordinator()

    enum State: Equatable {
        case idle
        case outgoing(callerName: String)
        case incoming(callerName: String)
        case connecting
        case connected
        case ended
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isMuted = false
    @Published private(set) var isSpeakerOn = false
    /// Port de `Utils/PermissionRequest.java:62-99` (vérification/demande explicite AVANT l'appel)
    /// — trouvé MANQUANT par l'audit WebRTC complet du 2026-08-16 : rien ne vérifiait la permission
    /// micro avant de démarrer WebRTC, laissant l'OS afficher son invite implicite au milieu de la
    /// mise en place de l'appel plutôt qu'un contrôle explicite en amont côté app.
    @Published private(set) var micPermissionDenied = false

    var activeCallUUID: UUID? { callUUID }

    private let webrtc = WebRTCConnection()
    private let callKit = CallKitManager.shared
    private let chatRepository = ChatRepository.shared
    private let voip = VoIPPushManager.shared

    private var callUUID: UUID?
    private var profile: ChatProfile?
    private var chatType: String = ChatType.chat.wireValue
    private var messageId: String?
    private var isOutgoingCall = false
    private var isRinging = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        webrtc.delegate = self
        callKit.delegate = self
        voip.delegate = self
        subscribeToCallEvents()
    }

    // MARK: - Démarrage

    /// À appeler une fois au lancement de l'app (voir `AppDelegate`).
    func start() {
        // Port de l'intégration CallKit+WebRTC standard (AUCUN équivalent Android — `AudioManager`
        // n'a pas cette notion) : `useManualAudio=true` empêche `RTCAudioSession` d'activer sa
        // propre session audio de façon autonome — SEUL `CXProviderDelegate.provider(_:didActivate:)`
        // (voir `CallKitManager`/`CallCoordinator` ci-dessous) doit déclencher l'activation réelle,
        // confirmé par le header `RTCAudioSession.h` réel (commentaire "current known use case…
        // when CallKit activates the audio unit").
        RTCAudioSession.sharedInstance().useManualAudio = true
        voip.registerForVoIPPushes()
    }

    private func subscribeToCallEvents() {
        chatRepository.callEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                Task { @MainActor in self.handle(event) }
            }
            .store(in: &cancellables)
    }

    private func handle(_ event: CallEvent) {
        switch event {
        case .onCall(let data):
            // Port de `CallActivity.onCall`/`IncomingCallActivity.onCall` — un AUTRE appel arrive
            // alors qu'on est déjà en communication avec quelqu'un d'autre → occupé. **Émission
            // `ROOM.CALL` (réception ici) confirmée jamais déclenchée par le client Android
            // lui-même** (`ChatRepository.onCall`/`CallViewModel.onCall`, grep exhaustif : aucun
            // appelant dans `CallService.java`, seul `onCallEnd`/`onCallBusy` le sont) — écouteur
            // conservé par fidélité (le serveur pourrait l'émettre indépendamment), gestion locale
            // reproduite sans en dépendre pour le flux normal (qui passe par le message
            // `"voicecall"`, voir `calling`).
            guard let incoming = Self.decodeProfile(data), callUUID != nil, incoming.username != profile?.username else { return }
            chatRepository.onCallBusy(["receiver": incoming.username ?? "", "packet": data])
        case .ringing:
            isRinging = true
            if isOutgoingCall, let uuid = callUUID { callKit.reportOutgoingCallConnecting(uuid: uuid) }
        case .acceptCall:
            break // Port de `stopoutgoingSound()` — CallKit arrête déjà sa propre tonalité système.
        case .endCall(let data):
            guard let incoming = Self.decodeProfile(data), incoming.messageId == messageId else { return }
            endCallFromRemote(reason: .remoteEnded)
        case .busyCall:
            endCallFromRemote(reason: .unanswered)
        case .webrtcMessage(let data):
            guard let message = Self.decodeWebrtcData(data) else { return }
            webrtc.onMessage(message)
        case .webrtcStatus, .declineCall, .elapsedTime:
            break // Port de `WEBRTC_STATUS`/`ELAPSEDTIME` — remplacés par `WebRTCConnectionDelegate`
            // et l'affichage natif de durée d'appel de CallKit, respectivement.
        }
    }

    // MARK: - Appel sortant (port de `CallService.configForOutgoingCall`/`calling`/
    // `onStartCommand(callType == OUTGOINGCALL)`)

    /// Port du point d'entrée `onStartCommand`/`CallModel.OUTGOINGCALL` — démarre un appel vers
    /// `profile`. `chatType`/`messageId` suivent les mêmes conventions que `MessageLib`/
    /// `ChatProfile` (module 11).
    func startOutgoingCall(profile: ChatProfile, chatType: String) {
        guard state == .idle else { return }
        micPermissionDenied = false
        Task {
            guard await Self.hasMicPermission() else {
                self.micPermissionDenied = true
                return
            }
            self.beginOutgoingCall(profile: profile, chatType: chatType)
        }
    }

    private func beginOutgoingCall(profile: ChatProfile, chatType: String) {
        guard state == .idle else { return }
        // Port de `CallService.onCreate()`/`onStartCommand()` (lignes 115/561, tous deux inconditionnels
        // dès que le service démarre un appel) — **ajouté le 2026-08-20, MIGRATION_PARITY_AUDIT_V3.md
        // V3-F-110, Phase B P0** : `ChatRepository.isOnCall` n'était JAMAIS mis à `true` nulle part
        // dans le projet (confirmé par grep exhaustif avant ce correctif), ce qui faisait router TOUTE
        // la signalisation WebRTC entrante (offre/réponse/ICE, `handleUnifiedWebrtcMessage`) vers le
        // flux Shareboard/PBS au lieu de l'appel réel — un appel ne pouvait jamais établir de flux
        // audio. `CallCoordinator` est le seul "service d'appel" côté iOS (voir commentaire de tête de
        // fichier), donc ce point d'entrée (et `handleIncomingCall` ci-dessous) sont les équivalents
        // fidèles de `onCreate`/`onStartCommand`.
        ChatRepository.isOnCall = true
        let uuid = UUID()
        callUUID = uuid
        self.profile = profile
        self.chatType = chatType
        messageId = profile.messageId
        isOutgoingCall = true
        isRinging = false
        state = .outgoing(callerName: profile.nikname ?? profile.username ?? "")
        callKit.requestStartCall(uuid: uuid, calleeName: profile.nikname ?? profile.username ?? "")
    }

    /// Acquitte l'alerte de permission refusée (voir `CallView.swift`) — l'utilisateur a vu le
    /// message, `micPermissionDenied` peut redevenir `false` sans relancer de demande système.
    func acknowledgeMicPermissionDenied() {
        micPermissionDenied = false
    }

    /// Port de `PermissionRequest.checkAndRequestPermission` — chemin rapide si déjà déterminé,
    /// sinon invite système. `AVAudioSession.requestRecordPermission` (PAS `AVAudioApplication`,
    /// iOS 17+ uniquement — incompatible avec `deploymentTarget: 16.0`, `project.yml`).
    private static func hasMicPermission() async -> Bool {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return true
        }
    }

    // MARK: - Appel entrant (port de `lunchcall`/`onStartCommand(callType == INCOMINGCALL)`)

    /// Port de `ChatManager.lunchcall(Profile)` — déclenché par `ChatRepository.handleNewMessage`
    /// (module 11) quand un message `object == "voicecall"` arrive PENDANT que le socket est
    /// connecté (app active). Le cas "app tuée" passe par `VoIPPushManagerDelegate` ci-dessous, qui
    /// appelle la MÊME méthode après avoir reconstruit un `ChatProfile` depuis le payload push.
    ///
    /// `onReported` (optionnel) est appelé DÈS QUE `CXProvider.reportNewIncomingCall` a rendu la
    /// main — AVANT le fetch TURN/démarrage WebRTC, qui peuvent prendre plusieurs centaines de ms.
    /// Utilisé exclusivement par `VoIPPushManagerDelegate` pour appeler `completion()` au plus tôt
    /// (voir avertissement Apple sur le délai de traitement d'un push VoIP, `VoIPPushManager.swift`)
    /// — le déclenchement socket normal (app déjà active) n'en a pas besoin, `onReported` reste nil.
    func handleIncomingCall(profile: ChatProfile, chatType: String, onReported: (() -> Void)? = nil) async {
        guard state == .idle else {
            onReported?()
            return
        }
        // Port de `CallService.onCreate()`/`onStartCommand()` — voir le commentaire détaillé dans
        // `beginOutgoingCall` ci-dessus (MIGRATION_PARITY_AUDIT_V3.md V3-F-110, Phase B P0). Réglé
        // AVANT `reportIncomingCall` (comme Android le fait dès `onCreate`, avant toute autre étape) —
        // un message `webrtcMessage` pourrait théoriquement arriver dès que l'appel est engagé, pas
        // seulement après le report CallKit.
        ChatRepository.isOnCall = true
        let uuid = UUID()
        callUUID = uuid
        self.profile = profile
        self.chatType = chatType
        messageId = profile.messageId
        isOutgoingCall = false
        state = .incoming(callerName: profile.nikname ?? profile.username ?? "")
        // `reportIncomingCall` DOIT être appelé inconditionnellement (contrat CallKit : un push
        // VoIP reçu sans `reportNewIncomingCall` immédiat expose l'app à des pénalités système) —
        // la vérification de permission micro vient APRÈS, avant `fetchTurnAndStart` (le point réel
        // d'engagement du micro), pas avant le report lui-même.
        try? await callKit.reportIncomingCall(uuid: uuid, callerName: profile.nikname ?? profile.username ?? "")
        onReported?()
        guard await Self.hasMicPermission() else {
            micPermissionDenied = true
            callKit.requestEndCall(uuid: uuid)
            return
        }
        await fetchTurnAndStart(isOutgoing: false)
    }

    // MARK: - TURN + démarrage WebRTC (port de `fetchTurnAndStart`/`startWebRTC`)

    private func fetchTurnAndStart(isOutgoing: Bool) async {
        webrtc.messageId = messageId
        if let credentials = try? await Self.fetchTurnCredentials() {
            webrtc.setTurnCredentials(credentials)
        }
        // Port du fallback STUN-only silencieux si `fetchTurnAndStart` échoue (`onError` se
        // contente de continuer sans credentials TURN, reproduit par le `try?` ci-dessus).
        if isOutgoing {
            configureOutgoing()
        } else {
            configureIncoming()
        }
    }

    private static func fetchTurnCredentials() async throws -> TurnCredentials {
        let value = try await APIClient.shared.post([:], endpoint: "call/turn-credentials")
        guard let data = value.rawData else { throw JSONError.typeMismatch("turn-credentials") }
        return try JSONDecoder().decode(TurnCredentials.self, from: data)
    }

    /// Port de `configForOutgoingCall` — voir l'avertissement d'asymétrie en tête de fichier.
    private func configureOutgoing() {
        webrtc.setInitiator(false)
        webrtc.setPolite(true)
        webrtc.setAudioEnabled(true)
        webrtc.setVideoEnabled(false)
        webrtc.setEnabled(false)
        webrtc.start(withDataChannel: false)
        // PAS de `onNegotiationNeeded()` ici — l'appelant attend l'offre du receveur, fidèle à
        // l'original (commentaire Android explicite sur ce point).
    }

    /// Port de `configForIncomingCall` — délai de 500ms avant de déclencher la négociation,
    /// reproduit tel quel (le commentaire Android ne justifie pas la valeur précise, gardée par
    /// fidélité plutôt que retirée).
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

    // MARK: - Fin d'appel

    private func endCallFromRemote(reason: CXCallEndedReason) {
        guard let uuid = callUUID else { return }
        callKit.reportCallEnded(uuid: uuid, reason: reason)
        teardown()
    }

    private func teardown() {
        // Port de `CallService.onDestroy()` (ligne 641, inconditionnel, seul point de sortie du
        // cycle de vie du "service" d'appel côté Android) — voir V3-F-110 / `beginOutgoingCall`
        // ci-dessus. `teardown()` est déjà le point de sortie UNIFIÉ de `CallCoordinator` (appelé
        // depuis `endCallFromRemote`, `performEndCall`, `callKitManagerDidReset`), fidèle à
        // `onDestroy` qui s'exécute quelle que soit la façon dont l'appel se termine.
        ChatRepository.isOnCall = false
        webrtc.disconnect()
        callUUID = nil
        profile = nil
        messageId = nil
        isRinging = false
        state = .ended
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.state = .idle
        }
    }
}

// MARK: - CallKitManagerDelegate (port des actions utilisateur — répondre/raccrocher/muet côté
// écran système CallKit — et de `provider(_:didActivate:)`, équivalent de
// `webrtc.setMode(MODE_IN_COMMUNICATION)`)

extension CallCoordinator: CallKitManagerDelegate {
    func callKitManagerDidReset(_ manager: CallKitManager) {
        teardown()
    }

    func callKitManager(_ manager: CallKitManager, performStartCall uuid: UUID, completion: @escaping (Bool) -> Void) {
        guard let profile else {
            completion(false)
            return
        }
        completion(true)
        callKit.reportOutgoingCallConnecting(uuid: uuid)
        Task {
            await self.fetchTurnAndStart(isOutgoing: true)
            self.chatRepository.calling(profile: profile, chatType: self.chatType, messageId: profile.messageId ?? "")
        }
    }

    /// Port de `CallService.callAccepted()` — accepte l'appel : notifie le socket
    /// (`accepCall`), démarre l'animation de durée (déléguée à CallKit ici), active le micro.
    func callKitManager(_ manager: CallKitManager, performAnswerCall uuid: UUID, completion: @escaping (Bool) -> Void) {
        guard let profile else {
            completion(false)
            return
        }
        completion(true)
        state = .connecting
        webrtc.setEnabled(true)
        let packet = ["receiver": profile.to ?? profile.username ?? "", "packet": (try? Self.encodeJSONString(profile)) ?? ""]
        chatRepository.accepCall(packet, chatType: chatType)
    }

    /// Port de `CallService.onOutgoingCallEnd`/`onIncomingCallEnd` — raccrocher LOCALEMENT :
    /// notifie le serveur (`onCallEnd`), et pour un appel entrant jamais décroché, signale un
    /// appel manqué (`notifyMissedCall`, port de `CallActivity.endCall`/`isCalleMissedCall`).
    func callKitManager(_ manager: CallKitManager, performEndCall uuid: UUID, completion: @escaping (Bool) -> Void) {
        defer { completion(true) }
        guard let profile else { return }
        let wasAnswered = state == .connected || state == .connecting
        let packet: [String: Any] = ["receiver": profile.to ?? profile.username ?? "", "packet": (try? Self.encodeJSONString(profile)) ?? ""]
        chatRepository.onCallEnd(packet, chatType: chatType)
        if !isOutgoingCall, !wasAnswered {
            chatRepository.notifyMissedCall(profile: profile, chatType: chatType, object: "missedvoicecall", messageId: messageId ?? "")
        }
        teardown()
    }

    func callKitManager(_ manager: CallKitManager, performSetMuted muted: Bool, forCall uuid: UUID) {
        isMuted = muted
        webrtc.setMicrophoneMute(muted)
    }

    /// Port de `webrtc.setMode(AudioManager.MODE_IN_COMMUNICATION)`/`setEnable(true)` —
    /// CallKit vient d'activer la session audio système, c'est le SEUL moment sûr pour configurer
    /// `RTCAudioSession` (voir avertissement CallKitManager.swift).
    func callKitManager(_ manager: CallKitManager, didActivate audioSession: AVAudioSession) {
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.audioSessionDidActivate(audioSession)
        rtcSession.isAudioEnabled = true

        // Port de `webrtc.setMode(AudioManager.MODE_IN_COMMUNICATION)` (RTConnection2.java:689-701)
        // — trouvé manquant par l'audit WebRTC complet du 2026-08-16 (HIGH PRIORITY) : aucune
        // catégorie/mode n'était réglé nulle part dans la pile d'appel, laissant le routage audio
        // WebRTC non garanti sur un vrai appareil malgré une compilation/exécution logique
        // correctes. Réglage ICI et SEULEMENT ici (pas avant `didActivate` — voir avertissement de
        // tête de fichier `CallKitManager.swift` : CallKit ne délègue la session audio à l'app qu'à
        // partir de ce rappel, toute configuration antérieure échoue silencieusement).
        rtcSession.lockForConfiguration()
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]
        config.mode = AVAudioSession.Mode.voiceChat.rawValue
        do {
            try rtcSession.setConfiguration(config, active: true)
        } catch {
            print("❌ RTCAudioSession configuration failed:", error)
        }
        rtcSession.unlockForConfiguration()
    }

    func callKitManager(_ manager: CallKitManager, didDeactivate audioSession: AVAudioSession) {
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.isAudioEnabled = false
        rtcSession.audioSessionDidDeactivate(audioSession)
    }

    func callKitManager(_ manager: CallKitManager, requestDidFailWith error: Error) {
        print("❌ CallKit transaction failed:", error)
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        webrtc.setSpeakerphoneOn(isSpeakerOn)
    }

    private static func encodeJSONString(_ profile: ChatProfile) throws -> String {
        let data = try JSONEncoder().encode(profile)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - WebRTCConnectionDelegate (port de `WebRTCMessageListener` implémenté par
// `CallService.webRTCMessageListener`)

extension CallCoordinator: WebRTCConnectionDelegate {
    func webRTCConnection(_ connection: WebRTCConnection, didProduce message: WebrtcData) {
        guard let profile, let data = try? JSONEncoder().encode(message), let json = String(data: data, encoding: .utf8) else { return }
        chatRepository.emitWebrtcMessage(["receiver": profile.to ?? profile.username ?? "", "packet": json], chatType: chatType)
    }

    func webRTCConnectionDidConnect(_ connection: WebRTCConnection) {
        state = .connected
        if isOutgoingCall, let uuid = callUUID { callKit.reportOutgoingCallConnected(uuid: uuid) }
    }

    func webRTCConnectionDidClose(_ connection: WebRTCConnection) {
        endCallFromRemote(reason: .remoteEnded)
    }

    func webRTCConnectionDidFail(_ connection: WebRTCConnection) {
        endCallFromRemote(reason: .failed)
    }

    func webRTCConnectionIsChecking(_ connection: WebRTCConnection) {
        state = .connecting
    }
}

// MARK: - VoIPPushManagerDelegate (port du réveil "app tuée" — AUCUN équivalent Android, voir
// avertissement `VoIPPushManager.swift`)

extension CallCoordinator: VoIPPushManagerDelegate {
    /// Port du point d'enregistrement — voir `VoIPTokenRegistrar.swift` pour l'appel réseau réel
    /// et la spécification de l'endpoint (`POST user/voip-token`, PAS encore implémenté côté
    /// serveur, voir MIGRATION_PROGRESS.md).
    func voIPPushManager(_ manager: VoIPPushManager, didUpdateToken token: Data) {
        Task { await VoIPTokenRegistrar.register(token) }
    }

    /// **Point le plus critique du module** : doit appeler `CallKitManager.reportIncomingCall`
    /// AVANT `completion()`, sous peine de résiliation de l'app par iOS (règle Apple, voir
    /// avertissement `VoIPPushManager.swift`). Le payload attendu (clés `username`/`nikname`/
    /// `messageId`/`chatType`/…) n'a PAS de définition serveur confirmée dans cette passe — la
    /// structure ci-dessous suppose un payload `ChatProfile`-compatible (cohérent avec le message
    /// `"voicecall"` normal, voir `calling`/`buildCallMessageLib`), à valider avec le serveur au
    /// moment de brancher l'envoi réel des push VoIP (dépend aussi du token ci-dessus).
    ///
    /// **`completion()` appelé DÈS QUE CallKit a été notifié, PAS après la préparation WebRTC
    /// complète** — une première version de ce fichier attendait `fetchTurnAndStart` (un appel
    /// réseau TURN) avant `completion()`, retardant inutilement le rappel PushKit au-delà de ce
    /// qu'exige Apple (signaler l'appel à CallKit, pas terminer toute la mise en place WebRTC) —
    /// corrigé via le paramètre `onReported` de `handleIncomingCall` ci-dessous.
    func voIPPushManager(_ manager: VoIPPushManager, didReceiveIncomingCallPayload payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
            let profile = try? JSONDecoder().decode(ChatProfile.self, from: data)
        else {
            completion()
            return
        }
        Task {
            await self.handleIncomingCall(profile: profile, chatType: profile.chatType ?? ChatType.chat.wireValue, onReported: completion)
        }
    }

    func voIPPushManagerDidInvalidateToken(_ manager: VoIPPushManager) {}
}

// MARK: - Décodage des payloads `CallEvent` (chaînes JSON brutes, port de `gson.fromJson`)

extension CallCoordinator {
    fileprivate static func decodeProfile(_ jsonString: String) -> ChatProfile? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatProfile.self, from: data)
    }

    fileprivate static func decodeWebrtcData(_ jsonString: String) -> WebrtcData? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WebrtcData.self, from: data)
    }
}
