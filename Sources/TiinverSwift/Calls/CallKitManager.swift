import AVFoundation
import CallKit
import Foundation

/// Développement NOUVEAU (module 12) — CallKit n'a AUCUN équivalent Android à porter : côté
/// Android, `CallActivity`/`IncomingCallActivity` dessinent leur propre écran plein écran
/// (capteur de proximité géré manuellement, wake lock, notification système avec actions
/// Accepter/Refuser via `IncomingCall`/`CallLauncherService`, lecture de sonnerie manuelle). Sur
/// iOS, CallKit fournit NATIVEMENT l'écran d'appel système (verrouillage compris), l'intégration
/// à l'app Téléphone/historique, ET gère lui-même la session audio + le capteur de proximité
/// pendant un appel — la majeure partie de la "plomberie" Android (capteur, wake lock, service de
/// notification à actions) n'a donc PAS de contrepartie à écrire ici, remplacée par l'intégration
/// système.
///
/// **API vérifiée avant écriture (pas devinée)** : `CXProvider`/`CXProviderConfiguration`/
/// `CXCallController`/`CXCallUpdate`/`CXHandle`/`CXStartCallAction`/`CXAnswerCallAction`/
/// `CXEndCallAction`/`CXSetMutedCallAction`/`CXCallEndedReason` — signatures confirmées via
/// `developer.apple.com/documentation/callkit` (fetch direct) et recoupées avec les bindings
/// Xamarin officiels (`xamarin/apple-api-docs`, mêmes signatures sous forme C#, utilisées comme
/// second recoupement quand la page Apple ne rendait pas son contenu JS). `CXProviderConfiguration
/// (localizedName:)` est signalé DÉPRÉCIÉ depuis iOS 14 dans la documentation (remplacé par un
/// `init()` + propriété `localizedName` réglable séparément) mais reste l'initialiseur RÉELLEMENT
/// documenté et fonctionnel dans toutes les sources consultées — utilisé tel quel, à revoir sur un
/// vrai Xcode récent si un avertissement de dépréciation apparaît (aucun accès macOS pour vérifier
/// depuis cet environnement Windows, voir contrainte d'environnement en tête de
/// MIGRATION_PROGRESS.md).
@MainActor
final class CallKitManager: NSObject {
    static let shared = CallKitManager()

    weak var delegate: CallKitManagerDelegate?

    private let provider: CXProvider
    private let callController = CXCallController()

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "Tiinver")
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: - Appel entrant (port de `CallService.showIncomingCallNotification`/
    // `playIncomingRingtone` — CallKit affiche l'écran système ET joue la sonnerie lui-même dès
    // `reportNewIncomingCall`, aucune notification/MediaPlayer manuel nécessaire)

    /// Port du déclenchement de `IncomingCallActivity` (`CallService.onStartCommand`,
    /// `callType == CallModel.INCOMINGCALL`). `uuid` est un identifiant CallKit LOCAL (pas
    /// `messageId` — CallKit exige un vrai `UUID`), la correspondance `uuid ↔ messageId` est tenue
    /// par `CallCoordinator`.
    func reportIncomingCall(uuid: UUID, callerName: String) async throws {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.reportNewIncomingCall(with: uuid, update: update) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    // MARK: - Appel sortant (port du déclenchement de `CallActivity`,
    // `callType == CallModel.OUTGOINGCALL`)

    func requestStartCall(uuid: UUID, calleeName: String) {
        let handle = CXHandle(type: .generic, value: calleeName)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = false
        request(CXTransaction(action: action))
    }

    /// Port de `sendWebrtcStatusToActivity(WebrtcData.CONNECTED, ...)` côté sortant — CallKit
    /// affiche "Connecting…" puis doit être informé explicitement de la connexion réelle
    /// (contrairement à Android où `subtitleView.setText` suffisait, ici c'est un vrai appel
    /// d'API requis pour que l'app Téléphone/l'historique reflètent l'état correct).
    func reportOutgoingCallConnecting(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
    }

    func reportOutgoingCallConnected(uuid: UUID) {
        provider.reportOutgoingCall(with: uuid, connectedAt: nil)
    }

    // MARK: - Fin d'appel (port de `remoteEnd`/`stopServiceIfRunning`/`onCallEnd`/`onOutgoingCallEnd`)

    func requestEndCall(uuid: UUID) {
        request(CXTransaction(action: CXEndCallAction(call: uuid)))
    }

    /// Port de la fin d'appel déclenchée par le SERVEUR (l'autre partie a raccroché/refusé/n'a pas
    /// répondu) — PAS une action locale, donc `reportCall(with:endedAt:reason:)` directement
    /// plutôt qu'une transaction `CXCallController` (qui suppose une action UTILISATEUR locale).
    func reportCallEnded(uuid: UUID, reason: CXCallEndedReason) {
        provider.reportCall(with: uuid, endedAt: nil, reason: reason)
    }

    func setMuted(uuid: UUID, muted: Bool) {
        request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted)))
    }

    private func request(_ transaction: CXTransaction) {
        callController.request(transaction) { [weak self] error in
            if let error { self?.delegate?.callKitManager(self ?? CallKitManager.shared, requestDidFailWith: error) }
        }
    }
}

/// Port consolidé de ce que `CallService`/`CallActivity`/`IncomingCallActivity` faisaient
/// manuellement (boutons répondre/raccrocher/couper le micro, activation de la session audio) —
/// ici, ce sont des rappels du SYSTÈME (l'utilisateur a touché "Répondre" sur l'écran CallKit
/// natif, pas un bouton dessiné par l'app).
@MainActor
protocol CallKitManagerDelegate: AnyObject {
    func callKitManagerDidReset(_ manager: CallKitManager)
    func callKitManager(_ manager: CallKitManager, performStartCall uuid: UUID, completion: @escaping (Bool) -> Void)
    func callKitManager(_ manager: CallKitManager, performAnswerCall uuid: UUID, completion: @escaping (Bool) -> Void)
    func callKitManager(_ manager: CallKitManager, performEndCall uuid: UUID, completion: @escaping (Bool) -> Void)
    func callKitManager(_ manager: CallKitManager, performSetMuted muted: Bool, forCall uuid: UUID)
    func callKitManager(_ manager: CallKitManager, didActivate audioSession: AVAudioSession)
    func callKitManager(_ manager: CallKitManager, didDeactivate audioSession: AVAudioSession)
    func callKitManager(_ manager: CallKitManager, requestDidFailWith error: Error)
}

/// Port de `CXProviderDelegate` — les callbacks CallKit arrivent potentiellement hors `MainActor`
/// (la documentation ne garantit pas le thread), d'où le saut explicite vers `MainActor` avant de
/// notifier le délégué, même motif que `WebRTCConnection`.
extension CallKitManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.callKitManagerDidReset(self)
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.callKitManager(self, performStartCall: action.callUUID) { success in
                if success { action.fulfill() } else { action.fail() }
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.callKitManager(self, performAnswerCall: action.callUUID) { success in
                if success { action.fulfill() } else { action.fail() }
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.callKitManager(self, performEndCall: action.callUUID) { success in
                if success { action.fulfill() } else { action.fail() }
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.callKitManager(self, performSetMuted: action.isMuted, forCall: action.callUUID)
            action.fulfill()
        }
    }

    /// Port de `webrtc.setMode(AudioManager.MODE_IN_COMMUNICATION)` — CallKit délègue la propriété
    /// de la session audio à l'app UNIQUEMENT après ce rappel (documenté : configurer/activer
    /// `RTCAudioSession`/`AVAudioSession` AVANT ce point échoue silencieusement).
    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.callKitManager(self, didActivate: audioSession)
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.callKitManager(self, didDeactivate: audioSession)
        }
    }
}
