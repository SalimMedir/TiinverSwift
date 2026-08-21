import Network

/// Port de `HomeActivity.networkStateReceiver`/`onNetworkChange`
/// (`HomeActivity.java:430-464,482-497`) — **ajouté le 2026-08-20
/// (MIGRATION_PARITY_AUDIT_V3.md V3-F-113, Phase B P1)**. Avant ce correctif, grep exhaustif
/// (`NWPathMonitor`/`Reachability`) donnait zéro résultat sur tout le projet : rien n'observait
/// activement les transitions réseau, seul le backoff interne du moteur Socket.IO agissait (hors
/// contrôle applicatif). Android détecte explicitement CHAQUE transition WiFi/Mobile vers
/// `CONNECTED` (`onNetworkChange`, ligne 484) et force `resetSocket()+connectSocket()`
/// immédiatement — équivalent exact ici à `ChatRepository.attachToCurrentSocket()`.
///
/// **Différence assumée, documentée** : Android déclenche sur CHAQUE broadcast `CONNECTIVITY_
/// ACTION` de type WiFi/Mobile en état `CONNECTED` (y compris un changement de point d'accès WiFi
/// alors que le réseau était déjà là) — plus bruyant que ce que le problème réel décrit par ce
/// finding exige ("pas de reconnexion forcée après coupure RÉELLE"). Ici, le déclenchement n'a
/// lieu QUE sur une transition RÉELLE non-satisfait → satisfait (`NWPath.Status`), pour éviter des
/// resets de socket redondants à chaque micro-changement d'interface tout en couvrant précisément
/// le scénario décrit (mode avion, tunnel, changement WiFi/4G avec coupure).
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Recréé à chaque `start()` plutôt que réutilisé : `NWPathMonitor.cancel()` invalide
    /// définitivement l'instance (API Apple — un `cancel()` n'est pas un "pause", un `start()`
    /// ultérieur sur la MÊME instance n'a pas de comportement garanti). Un cycle
    /// start/stop/start/stop répété (premier/arrière-plan de l'app, comme
    /// `onStart`/`onStop` d'Android) exige donc une NOUVELLE instance à chaque démarrage.
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.tiinver.networkmonitor")
    private var lastStatus: NWPath.Status?
    private var onRegainedConnectivity: (() -> Void)?

    private init() {}

    /// Port de `registerReceiver(networkStateReceiver, ...)` (`HomeActivity.java:211-219`, appelé
    /// depuis `onStart`) — `onRegained` est invoqué sur le thread principal à chaque transition
    /// vers `.satisfied`, fidèle à `onNetworkChange` → `App.resetSocket()+connectSocket()`.
    func start(onRegainedConnectivity: @escaping () -> Void) {
        stop() // sûr même si déjà arrêté ; évite 2 moniteurs actifs en cas de double appel
        self.onRegainedConnectivity = onRegainedConnectivity
        lastStatus = nil
        let newMonitor = NWPathMonitor()
        newMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let previous = self.lastStatus
            self.lastStatus = path.status
            if path.status == .satisfied, previous != nil, previous != .satisfied {
                DispatchQueue.main.async { self.onRegainedConnectivity?() }
            }
        }
        monitor = newMonitor
        newMonitor.start(queue: queue)
    }

    /// Port d'`unregisterReceiver(networkStateReceiver)` (`HomeActivity.java:250-253`, appelé
    /// depuis `onStop`).
    func stop() {
        monitor?.cancel()
        monitor = nil
        lastStatus = nil
    }
}
