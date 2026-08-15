import Foundation
import WebRTC

/// Port de `messagerie/webrtc/RTConnection2.java` (801 lignes, lu en entier, module 12) — moteur
/// WebRTC audio uniquement (aucune trace de `VideoTrack`/`VideoCapturer` dans tout le fichier
/// Android malgré un flag `isVideoEnabled` présent mais toujours mis à `false` par les deux
/// appelants réels, `CallService.configForOutgoingCall`/`configForIncomingCall` — confirmé, pas
/// une simplification de ce portage).
///
/// **`RTConnection.java`/`RTConnection3.java` (775/790 lignes) CONFIRMÉS MORTS** — même méthodologie
/// que le cluster "v2" du module 10 (`VideoTransformer`) : grep exhaustif montre que SEUL
/// `RTConnection2` est instancié en dehors de son propre fichier (`CallService.java`, `App.java`,
/// `FragmentPbs.java`), `RTConnection`/`RTConnection3` ne sont référencés que par eux-mêmes. Pas
/// lus, pas portés.
///
/// **Bibliothèque vérifiée avant usage (pas devinée)** : `stasel/WebRTC` (SPM, déjà déclarée dans
/// `project.yml` depuis un module antérieur) — binaires prébuilts du VRAI `libwebrtc` Google, API
/// Swift confirmée par lecture directe du dépôt de démonstration officiel `stasel/WebRTC-iOS`
/// (`WebRTCClient.swift`) ET du header Objective-C réel `RTCConfiguration.h` (nommage exact des
/// enums `RTCTcpCandidatePolicy`/`RTCBundlePolicy`/`RTCRtcpMuxPolicy`/`RTCEncryptionKeyType`/
/// `RTCContinualGatheringPolicy`/`RTCSdpSemantics`, pontés en Swift sans le préfixe `RTC*`).
final class WebRTCConnection: NSObject {
    private static let AUDIO_TRACK_ID = "ARDAMSa0"
    private static let AUDIO_CODEC_OPUS = "opus"

    /// Port de `PeerConnectionFactory.builder().createPeerConnectionFactory()` — usine partagée,
    /// comme le `private static let factory` de `WebRTCClient.swift` (stasel/WebRTC-iOS, vérifié).
    /// `RTCInitializeSSL()` doit être appelé une fois avant toute utilisation (confirmé par la
    /// même source).
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    weak var delegate: WebRTCConnectionDelegate?

    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?
    private var audioSource: RTCAudioSource?
    private var audioConstraints: RTCMediaConstraints?
    private var sdpMediaConstraints: RTCMediaConstraints?
    private var turnCredentials: TurnCredentials?
    var messageId: String?

    private var isInitiator = false
    private var isAudioEnabled = false
    private var isVideoEnabled = false
    private var polite = false
    private var makingOffer = false
    private var ignoreOffer = false
    private var hasAttemptedIceRestart = false
    private var isPeerConnectionReady = false
    private var pendingMessages: [WebrtcData] = []

    func setTurnCredentials(_ credentials: TurnCredentials) { turnCredentials = credentials }
    func setPolite(_ value: Bool) { polite = value }
    func setInitiator(_ value: Bool) { isInitiator = value }
    func setAudioEnabled(_ value: Bool) { isAudioEnabled = value }
    func setVideoEnabled(_ value: Bool) { isVideoEnabled = value }

    // MARK: - Démarrage (port de `start`/`startALL`)

    /// Port de `start()`/`startALL()` — `withDataChannel` sélectionne la variante (côté Android,
    /// `configForIncomingCall` appelle `startALL()` avec canal de données, `configForOutgoingCall`
    /// appelle `start()` sans — asymétrie réelle reproduite telle quelle, pas harmonisée).
    func start(withDataChannel: Bool) {
        createMediaConstraints()
        createAudioTrack()
        peerConnection = createPeerConnection()
        if withDataChannel {
            let config = RTCDataChannelConfiguration()
            dataChannel = peerConnection?.dataChannel(forLabel: "tinverChannel", configuration: config)
            // Bug trouvé (module 13, Shareboard) : le canal créé localement n'avait jamais son
            // `.delegate` assigné, donc aucun message entrant ne pouvait jamais être reçu — dormant
            // tant que seuls les appels (module 12) utilisaient cette classe (ils n'envoient rien sur
            // le canal), révélé par la relecture de `RTCDataChannel.h`/`WebRTCClient.swift` (référence
            // `stasel/WebRTC-iOS`, méthode `createDataChannel()`) avant de porter le Shareboard, qui EN
            // A besoin dans les deux sens.
            dataChannel?.delegate = self
        }
        startStreamingAudio()
        isPeerConnectionReady = true
        drainPendingMessages()
    }

    private func createMediaConstraints() {
        let pairs: [RTCMediaConstraint] = isAudioEnabled
            ? [
                RTCMediaConstraint(key: "googEchoCancellation", value: "true"),
                RTCMediaConstraint(key: "googAutoGainControl", value: "true"),
                RTCMediaConstraint(key: "googHighpassFilter", value: "true"),
                RTCMediaConstraint(key: "googNoiseSuppression", value: "true"),
            ]
            : [
                RTCMediaConstraint(key: "googEchoCancellation", value: "false"),
                RTCMediaConstraint(key: "googAutoGainControl", value: "false"),
                RTCMediaConstraint(key: "googHighpassFilter", value: "false"),
                RTCMediaConstraint(key: "googNoiseSuppression", value: "false"),
            ]
        audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) }), optionalConstraints: nil)
        sdpMediaConstraints = makeSdpConstraints(iceRestart: false)
    }

    private struct RTCMediaConstraint { let key: String; let value: String }

    private func makeSdpConstraints(iceRestart: Bool) -> RTCMediaConstraints {
        var mandatory = ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": isVideoEnabled ? "true" : "false"]
        if iceRestart { mandatory["IceRestart"] = "true" }
        return RTCMediaConstraints(mandatoryConstraints: mandatory, optionalConstraints: nil)
    }

    private func createAudioTrack() {
        guard let audioConstraints else { return }
        let source = Self.factory.audioSource(with: audioConstraints)
        let track = Self.factory.audioTrack(with: source, trackId: Self.AUDIO_TRACK_ID)
        track.isEnabled = false
        audioSource = source
        localAudioTrack = track
    }

    private func startStreamingAudio() {
        guard let peerConnection, let localAudioTrack else { return }
        peerConnection.add(localAudioTrack, streamIds: ["ARDAMS"])
    }

    // MARK: - PeerConnection (port de `createPeerConnection`)

    private func createPeerConnection() -> RTCPeerConnection? {
        var iceServers: [RTCIceServer] = []
        if let data = turnCredentials?.iceServers {
            for url in data.urls {
                if url.hasPrefix("stun:") {
                    iceServers.append(RTCIceServer(urlStrings: [url]))
                } else {
                    iceServers.append(RTCIceServer(urlStrings: [url], username: data.username, credential: data.credential))
                }
            }
        } else {
            iceServers.append(RTCIceServer(urlStrings: ["stun:stun.cloudflare.com:3478"]))
            iceServers.append(RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]))
        }

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.tcpCandidatePolicy = .enabled
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.continualGatheringPolicy = .gatherContinually
        config.keyType = .ECDSA
        config.sdpSemantics = .unifiedPlan
        config.iceBackupCandidatePairPingInterval = 2000

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return Self.factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }

    /// Port de `iceReStart` — reproduit le garde-fou "une seule tentative" (`hasAttemptedIceRestart`).
    private func iceRestart() {
        guard !hasAttemptedIceRestart, let peerConnection else { return }
        hasAttemptedIceRestart = true
        makingOffer = true
        let constraints = makeSdpConstraints(iceRestart: true)
        peerConnection.offer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp else {
                self?.makingOffer = false
                return
            }
            let munged = Self.preferCodec(sdp.sdp, codec: Self.AUDIO_CODEC_OPUS)
            let newDesc = RTCSessionDescription(type: sdp.type, sdp: munged)
            peerConnection.setLocalDescription(newDesc) { _ in }
            self.sendMessage(type: "offer", sdp: sdp.sdp)
            self.makingOffer = false
        }
    }

    /// Port de `createOffer()`.
    func createOffer() {
        guard let peerConnection, let sdpMediaConstraints else { return }
        makingOffer = true
        peerConnection.offer(for: sdpMediaConstraints) { [weak self] sdp, error in
            guard let self, let sdp else {
                self?.makingOffer = false
                return
            }
            let munged = Self.preferCodec(sdp.sdp, codec: Self.AUDIO_CODEC_OPUS)
            let newDesc = RTCSessionDescription(type: sdp.type, sdp: munged)
            peerConnection.setLocalDescription(newDesc) { _ in }
            self.sendMessage(type: "offer", sdp: sdp.sdp)
        }
    }

    /// Port de `doAnswer()`.
    private func doAnswer() {
        guard let peerConnection, let sdpMediaConstraints else { return }
        peerConnection.answer(for: sdpMediaConstraints) { [weak self] sdp, error in
            guard let self, let sdp else { return }
            let munged = Self.preferCodec(sdp.sdp, codec: Self.AUDIO_CODEC_OPUS)
            let newDesc = RTCSessionDescription(type: sdp.type, sdp: munged)
            peerConnection.setLocalDescription(newDesc) { _ in }
            self.sendMessage(type: "answer", sdp: sdp.sdp)
        }
    }

    /// Port de `onnegotiationneeded()`.
    func onNegotiationNeeded() {
        if isInitiator { createOffer() }
    }

    /// **Saut vers `MainActor` nécessaire** : appelée depuis les blocs de complétion `offer`/
    /// `answer`/`iceReStart` de libwebrtc, qui s'exécutent sur un thread interne (pas garanti
    /// `MainActor`) — `delegate` est de type `WebRTCConnectionDelegate` (`@MainActor`), l'appeler
    /// directement depuis ce contexte serait une erreur de compilation (isolement d'acteur).
    private func sendMessage(type: String, sdp: String) {
        var message = WebrtcData()
        message.messageId = "\(type)_\(messageId ?? "")"
        message.type = type
        message.sdp = sdp
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.webRTCConnection(self, didProduce: message)
        }
    }

    // MARK: - Réception de messages (port de `onMessage`/`processMessage`/`drainPendingMessages`)

    func onMessage(_ message: WebrtcData) {
        guard peerConnection != nil, isPeerConnectionReady else {
            pendingMessages.append(message)
            return
        }
        process(message)
    }

    private func drainPendingMessages() {
        guard !pendingMessages.isEmpty else { return }
        let queued = pendingMessages
        pendingMessages.removeAll()
        for message in queued { process(message) }
    }

    private func process(_ message: WebrtcData) {
        guard let peerConnection, let type = message.type else { return }

        if type != "candidate" {
            let offerCollision = type == "offer" && (makingOffer || peerConnection.signalingState != .stable)
            ignoreOffer = !polite && offerCollision
            guard !ignoreOffer else { return }

            let sdpType: RTCSdpType = type == "offer" ? .offer : .answer
            let munged = Self.preferCodec(message.sdp ?? "", codec: Self.AUDIO_CODEC_OPUS)
            let description = RTCSessionDescription(type: sdpType, sdp: munged)
            peerConnection.setRemoteDescription(description) { [weak self] error in
                guard let self else { return }
                // Port de `RTConnection2.onSetFailure` (`RTConnection2.java:657-661`) : Android
                // remet `makingOffer=false` MÊME en cas d'échec, sinon un pair resterait bloqué
                // indéfiniment sans pouvoir jamais recréer d'offre après un seul échec SDP.
                guard error == nil else {
                    self.makingOffer = false
                    return
                }
                if sdpType == .answer { self.makingOffer = false }
                if sdpType == .offer { self.doAnswer() }
            }
        } else {
            guard let sdpMid = message.id, let candidateSdp = message.candidate else { return }
            let candidate = RTCIceCandidate(sdp: candidateSdp, sdpMLineIndex: Int32(message.label), sdpMid: sdpMid)
            // Port de `addIceCandidate(IceCandidate)` — vérifié dans le header réel
            // `RTCPeerConnection.h` : `-(void)addIceCandidate:` n'a PAS de variante à bloc de
            // complétion (contrairement à `offer`/`answer`/`setLocalDescription`/
            // `setRemoteDescription`), juste `peerConnection.add(candidate)`.
            peerConnection.add(candidate)
        }
    }

    // MARK: - Contrôles audio (port de `setSpeakerphoneOn`/`setMicrophoneMute`/`setEnable`)
    //
    // Android pilote `AudioManager` directement. Sur iOS, la session audio de l'appel est activée/
    // désactivée par CallKit lui-même (`CXProviderDelegate.provider(_:didActivate:)`/
    // `didDeactivate:`, voir `CallKitManager.swift`) — ces méthodes ne pilotent QUE l'état WebRTC
    // (piste locale, sortie haut-parleur via `RTCAudioSession.overrideOutputAudioPort`), pas la
    // catégorie de session elle-même (déjà configurée par CallKit à ce stade).

    func setSpeakerphoneOn(_ on: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        try? session.overrideOutputAudioPort(on ? .speaker : .none)
        session.unlockForConfiguration()
    }

    func setMicrophoneMute(_ muted: Bool) {
        localAudioTrack?.isEnabled = !muted
    }

    func setEnabled(_ enabled: Bool) {
        localAudioTrack?.isEnabled = enabled
    }

    func sendData(_ text: String) {
        guard let dataChannel, let data = text.data(using: .utf8) else { return }
        dataChannel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    /// Port de `disconnect()`.
    func disconnect() {
        isPeerConnectionReady = false
        hasAttemptedIceRestart = false
        makingOffer = false
        turnCredentials = nil
        pendingMessages.removeAll()

        localAudioTrack?.isEnabled = false
        localAudioTrack = nil
        audioSource = nil

        dataChannel?.close()
        dataChannel = nil

        peerConnection?.close()
        peerConnection = nil
    }

    // MARK: - Préférence de codec (port de `preferCodec`/`movePayloadTypesToFront`/
    // `findMediaDescriptionLine`/`joinString` — manipulation SDP textuelle pure, indépendante de
    // toute API WebRTC, portée telle quelle)

    private static func preferCodec(_ sdp: String, codec: String) -> String {
        var lines = sdp.components(separatedBy: "\r\n")
        guard let mLineIndex = lines.firstIndex(where: { $0.hasPrefix("m=audio ") }) else { return sdp }

        guard let regex = try? NSRegularExpression(pattern: "^a=rtpmap:(\\d+) \(codec)(/\\d+)+\\r?$") else { return sdp }
        var payloadTypes: [String] = []
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range), let r = Range(match.range(at: 1), in: line) {
                payloadTypes.append(String(line[r]))
            }
        }
        guard !payloadTypes.isEmpty else { return sdp }

        let parts = lines[mLineIndex].components(separatedBy: " ")
        guard parts.count > 3 else { return sdp }
        let header = Array(parts[0..<3])
        var unpreferred = Array(parts[3...])
        unpreferred.removeAll { payloadTypes.contains($0) }
        lines[mLineIndex] = (header + payloadTypes + unpreferred).joined(separator: " ")

        return lines.joined(separator: "\r\n")
    }
}

/// Port de `WebRTCMessageListener.java` (interface, lue en entier) — `onMessage` transmet un SDP/
/// ICE candidate PRÊT À ÉMETTRE (l'appelant est responsable de l'envoi sur le socket, comme
/// `CallService.webRTCMessageListener`).
@MainActor
protocol WebRTCConnectionDelegate: AnyObject {
    func webRTCConnection(_ connection: WebRTCConnection, didProduce message: WebrtcData)
    func webRTCConnectionDidConnect(_ connection: WebRTCConnection)
    func webRTCConnectionDidClose(_ connection: WebRTCConnection)
    func webRTCConnectionDidFail(_ connection: WebRTCConnection)
    func webRTCConnectionIsChecking(_ connection: WebRTCConnection)
    /// Port du canal de données (`RTCDataChannel`) — utilisé par le Shareboard (module 13), pas par
    /// les appels (module 12, qui n'envoient jamais rien sur `dataChannel`) — implémentation par
    /// défaut vide ci-dessous pour que `CallCoordinator` n'ait rien à faire.
    func webRTCConnection(_ connection: WebRTCConnection, didReceiveData text: String)
}

extension WebRTCConnectionDelegate {
    func webRTCConnection(_ connection: WebRTCConnection, didReceiveData text: String) {}
}

/// Port de `CustomPeerConnectionObserver`/l'observateur anonyme de `createPeerConnection` — les
/// callbacks WebRTC arrivent sur un thread interne à libwebrtc (pas le thread principal, confirmé
/// par `WebRTCClient.swift` de référence), d'où le saut explicite vers le `MainActor` avant de
/// notifier le délégué (équivalent du `Handler(Looper.getMainLooper()).post` implicite d'Android,
/// qui poste `sendWebrtcStatusToActivity` via `LocalBroadcastManager`, toujours reçu sur le thread
/// principal côté `CallActivity`).
extension WebRTCConnection: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let remoteTrack = stream.audioTracks.first { remoteTrack.isEnabled = true }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onNegotiationNeeded()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch newState {
            case .connected, .completed:
                self.delegate?.webRTCConnectionDidConnect(self)
            case .checking:
                self.delegate?.webRTCConnectionIsChecking(self)
            case .closed:
                self.delegate?.webRTCConnectionDidClose(self)
            case .failed:
                self.delegate?.webRTCConnectionDidFail(self)
                self.iceRestart()
            case .disconnected:
                // Port du commentaire Android : DISCONNECTED se contente d'attendre une reprise
                // spontanée de libwebrtc ou une transition vers FAILED — aucun repli/timeout forcé,
                // fidèle à l'original (voir note "Android 16 / local-network permission" côté
                // Android, non vérifiable depuis cet environnement Windows).
                break
            default: break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        var message = WebrtcData()
        message.messageId = "candidate_\(messageId ?? "")"
        message.type = "candidate"
        message.label = Int(candidate.sdpMLineIndex)
        message.id = candidate.sdpMid
        message.candidate = candidate.sdp
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.webRTCConnection(self, didProduce: message)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    /// Port du canal de données ouvert par le PAIR DISTANT (le côté qui n'a pas appelé
    /// `start(withDataChannel: true)` lui-même — vérifié contre `WebRTCClient.swift` de référence,
    /// méthode `peerConnection(_:didOpen:)`, qui stocke la référence mais **n'assigne PAS son
    /// `.delegate`** dans la démo — écart corrigé ici volontairement : sans `.delegate = self` sur
    /// CE canal précis, aucun message reçu par ce pair ne déclencherait jamais de callback (le
    /// Shareboard a besoin des deux sens, contrairement à la démo qui n'illustre qu'un envoi simple).
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        self.dataChannel = dataChannel
        dataChannel.delegate = self
    }
}

/// Port de `DataChannelResultListener.java` (interface Android) — réception des messages du canal
/// de données, utilisée par le Shareboard (module 13). Signatures vérifiées contre le header réel
/// `RTCDataChannel.h`/la démo `stasel/WebRTC-iOS` (`WebRTCClient: RTCDataChannelDelegate`).
extension WebRTCConnection: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let text = String(data: buffer.data, encoding: .utf8) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.webRTCConnection(self, didReceiveData: text)
        }
    }
}
