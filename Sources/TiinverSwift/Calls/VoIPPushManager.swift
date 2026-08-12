import Foundation
import PushKit

/// Développement NOUVEAU (module 12) — AUCUN équivalent Android : `CallService`/`ChatManager.
/// lunchcall` ne démarrent l'écran d'appel entrant que si l'app tourne déjà (processus vivant,
/// socket connecté) — Android laisse FCM réveiller le processus normalement pour les autres
/// notifications, sans mécanisme dédié "appel" séparé. **iOS interdit structurellement cette
/// approche** : une app tuée/suspendue ne reçoit PAS de notification silencieuse fiable à temps
/// pour un appel entrant. PushKit (notifications VoIP) est le SEUL mécanisme Apple garantissant un
/// réveil immédiat, MAIS avec une contrepartie stricte et documentée par Apple elle-même : **toute
/// notification VoIP reçue DOIT déclencher `CXProvider.reportNewIncomingCall` de façon synchrone
/// dans `pushRegistry(_:didReceiveIncomingPushWith:for:completion:)`, sous peine de résiliation de
/// l'app par iOS** (règle App Store, pas une simple recommandation) — voir `CallCoordinator.swift`
/// pour le point d'appel réel.
///
/// **API vérifiée avant écriture** : `PKPushRegistry`/`PKPushRegistryDelegate` — signatures
/// confirmées via les bindings Xamarin officiels (`xamarin/apple-api-docs`, PKPushRegistry.xml/
/// IPKPushRegistryDelegate.xml), recoupées avec la documentation Apple sur l'obligation
/// `reportNewIncomingCall` (règle largement documentée dans l'écosystème CallKit/PushKit,
/// confirmée par recherche croisée, pas une seule source).
@MainActor
final class VoIPPushManager: NSObject {
    static let shared = VoIPPushManager()

    weak var delegate: VoIPPushManagerDelegate?

    private var registry: PKPushRegistry?

    private override init() { super.init() }

    /// À appeler une fois au démarrage de l'app (voir `AppDelegate`) — enregistre l'app pour les
    /// push VoIP. Le jeton (`PKPushCredentials.token`) est envoyé au backend par
    /// `CallCoordinator.voIPPushManager(_:didUpdateToken:)` → `VoIPTokenRegistrar.register` (`POST
    /// user/voip-token`) — endpoint appelé côté client, **implémentation serveur PAS faite ici**
    /// (backend PHP séparé, voir MIGRATION_PROGRESS.md section "Backend à implémenter —
    /// PushKit/VoIP" pour la spécification complète).
    func registerForVoIPPushes() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }
}

@MainActor
protocol VoIPPushManagerDelegate: AnyObject {
    func voIPPushManager(_ manager: VoIPPushManager, didUpdateToken token: Data)
    /// `completion` DOIT être appelé après (et seulement après) que l'appel a été signalé à
    /// CallKit (`CallKitManager.reportIncomingCall`) — voir avertissement de tête de fichier.
    func voIPPushManager(_ manager: VoIPPushManager, didReceiveIncomingCallPayload payload: [AnyHashable: Any], completion: @escaping () -> Void)
    func voIPPushManagerDidInvalidateToken(_ manager: VoIPPushManager)
}

extension VoIPPushManager: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.voIPPushManager(self, didUpdateToken: token)
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }
        let dictionaryPayload = payload.dictionaryPayload
        Task { @MainActor [weak self] in
            guard let self else {
                completion()
                return
            }
            self.delegate?.voIPPushManager(self, didReceiveIncomingCallPayload: dictionaryPayload, completion: completion)
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.voIPPushManagerDidInvalidateToken(self)
        }
    }
}
