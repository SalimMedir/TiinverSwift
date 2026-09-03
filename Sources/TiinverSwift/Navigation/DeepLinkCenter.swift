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
    /// Port du repli `default:` de `ShareActivity.processUrl` (lignes 207-210) — un segment de
    /// chemin non reconnu lance `SplashActivity` plutôt que de ne rien faire (V4-F-005 audit V4,
    /// P3, 2026-08-24).
    case home
    case notifications
    case chat
    /// **Ajouté (2026-09-03)** — pas un lien profond réel côté Android (aucun `case` correspondant
    /// dans `ShareActivity.processUrl`), réutilise ce mécanisme existant pour un besoin PUREMENT
    /// iOS : la barre à 5 onglets custom du pager plein écran (`FeedDetailPagerView`,
    /// `showsHomeTabBar`) a besoin de sélectionner l'onglet "Créateurs" (2) de `HomeShellView`
    /// après fermeture — aucun autre canal de communication n'existe déjà entre ces 2 vues, et ce
    /// mécanisme `pending`/`consume()` fait exactement ce qu'il faut sans en inventer un second.
    case creators
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
    /// Port de `ShareActivity.onError` → `showDialog()` (V3-F-138, DeepLinks complémentaire) — un
    /// lien profond dont la résolution réseau échoue (user/post/group introuvable, coupure réseau)
    /// ouvrait l'app sans AUCUNE indication, contrairement à Android qui affiche une boîte de
    /// dialogue (`R.string.errorLoad`, texte EXACT repris ci-dessous depuis `values-fr/strings.xml`).
    @Published var errorMessage: String?

    private init() {}

    func route(_ destination: DeepLinkDestination) {
        pending = destination
    }

    func consume() -> DeepLinkDestination? {
        defer { pending = nil }
        return pending
    }

    func showError() {
        errorMessage = "Pas de connexion internet, réessayer plus tard"
    }
}
