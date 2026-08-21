import Foundation

/// Port du routage `Intent`/`activityMap` de `back_sync/NotificationUtils.java` (`show()`,
/// `displayNoMessageNotification`, `displayNotificationOrPushMessage`) — chaque notification
/// système Android transporte une destination (`MainActivity`/`ActivityMsg`/...) ; ici, un seul
/// point central publie la destination demandée, observé par `HomeShellView` (module 5) pour
/// ouvrir le bon écran au tap, à l'identique de l'intention d'origine.
///
/// **Étendu le 2026-08-16 (`DeepLinkRouter.swift`)** avec les destinations de `ShareActivity.
/// processUrl` (liens `https://tiinver.com/...`/`myapp://parrainage`, jamais portés avant ce
/// tour) — même mécanisme de file d'attente `pending`/`consume()` que les notifications push,
/// pas un second système parallèle.
enum DeepLinkDestination: Equatable {
    case notifications
    case chat
    case profile
    case userProfile(userId: String)
    case post(FeedActivity)
    case groupChat(RosterModel)
    /// Port de `case "myaccount": Intent(SettingsActivity) putExtra(INDEX, 7)`
    /// (`ShareActivity.java:179-185`) — **renommé de `.settings` le 2026-08-20
    /// (MIGRATION_PARITY_AUDIT_V3.md V3-F-137, Phase B P1)** : ce cas n'a JAMAIS eu d'autre
    /// producteur que le lien `myaccount` (grep exhaustif), donc jamais eu besoin d'être un
    /// "réglages génériques" — Android route DIRECTEMENT vers `SettingAccountFragment` (INDEX=7),
    /// pas vers l'écran racine des réglages. Avant ce correctif, iOS ouvrait `SettingsView` (la
    /// liste racine), obligeant un tap supplémentaire sur "Compte".
    case settingsAccount
    case animems
    case referral
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
