import Foundation

/// Port du routage `Intent`/`activityMap` de `back_sync/NotificationUtils.java` (`show()`,
/// `displayNoMessageNotification`, `displayNotificationOrPushMessage`) — chaque notification
/// système Android transporte une destination (`MainActivity`/`ActivityMsg`/...) ; ici, un seul
/// point central publie la destination demandée, observé par `HomeShellView` (module 5) pour
/// ouvrir le bon écran au tap, à l'identique de l'intention d'origine.
enum DeepLinkDestination: Equatable {
    case notifications
    case chat
    case profile
}

@MainActor
final class DeepLinkCenter: ObservableObject {
    static let shared = DeepLinkCenter()
    @Published var pending: DeepLinkDestination?

    private init() {}

    func route(_ destination: DeepLinkDestination) {
        pending = destination
    }

    func consume() -> DeepLinkDestination? {
        defer { pending = nil }
        return pending
    }
}
