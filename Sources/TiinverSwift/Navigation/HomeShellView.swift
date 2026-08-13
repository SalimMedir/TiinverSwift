import SwiftUI
import Foundation
import UserNotifications

/// Port de la coquille post-connexion `Activity/ui/HomeActivity.java` +
/// `view/navigation/NavigationCompound.java` + `Activity/adapter/MyPagerAdapter.java`.
///
/// **Barre de navigation à 5 items, RECONFIRMÉE au tour du 2026-08-13** (correction d'une
/// interprétation antérieure) — lu en entier cette fois `navigation_layout.xml` (le layout RÉEL de
/// `NavigationCompound`, jamais lu avant ce tour, seul le `.java` l'avait été), pas seulement le
/// code Java des listeners : 5 `MenuItemView` dans UNE SEULE barre horizontale (`LinearLayout`,
/// poids égal), dans cet ORDRE EXACT gauche→droite : `navigation_home` (Accueil),
/// `navigation_chat` (Chat), `navigation_trophy` (Créateurs), `navigation_notifications`
/// (Notifications), `navigation_profile` (Profil). **Nuance comportementale RÉELLE, vérifiée dans
/// `NavigationCompound.java` (`click` listener)** : SEULS les 3 premiers participent à la machine
/// d'état `setSelected(true/false)` (ce sont les vrais onglets du `ViewPager`, contenu qui change
/// en place) — `navigation_notifications`/`navigation_profile` déclenchent le listener SANS jamais
/// être marqués sélectionnés : ils lancent une Activity séparée (`ShowNoti`/`AddPerfilFoto`) qui se
/// superpose, puis reviennent à l'onglet précédent une fois fermées. Reproduit fidèlement ici : 5
/// items visuellement dans la MÊME barre `TabView`, mais taper Notifications/Profil présente une
/// `sheet` PUIS restaure immédiatement `selectedTab` à sa valeur précédente (`.onChange`) —
/// exactement le motif "action déguisée en onglet, jamais réellement sélectionnée" observé côté
/// Android, ni un vrai 5ᵉ/6ᵉ onglet à contenu permanent (ce qui trahirait le comportement réel), ni
/// des boutons de barre d'outils séparés (ce qui trahirait la disposition visuelle réelle — les 2
/// précédents tours de portage avaient fait ce compromis faute d'avoir lu `navigation_layout.xml`).
///
/// - Badge `navigation_chat` = somme de `wk_roster.unreadCount` (`NavigationCompound.
///   cursorWorkerTask`, `ROSTER_URI`) → `RosterRepository` (déjà écrit, module 2). Badge
///   `navigation_notifications` = `NotiDatabase.countUnread()` → `NotiRepository`/
///   `NotificationCenterViewModel` (déjà écrits, module 4).
/// - Icônes : SF Symbols choisis par équivalence SÉMANTIQUE, pas une traduction littérale des noms
///   de drawables Android (conforme aux conventions iOS demandées, pas un portage visuel brut) —
///   `ic_dashboard_black_24dp`→`house.fill`, `ic_email_black_24dp`→`message.fill` (icône "email"
///   Android pour une fonction de CHAT, `message.fill` plus juste sémantiquement côté iOS),
///   `trophy_24px`→`trophy.fill`, `ic_notifications_black_24dp`→`bell.fill`,
///   `ic_person_black_24dp`→`person.crop.circle.fill`.
///
/// PAS porté ici, volontairement : le gate de mise à jour forcée par Firebase Remote Config
/// (déjà porté séparément, voir `RootRouterView.swift`) ; les 3 `scheduleDynamicWorker`
/// (WorkManager, contenu suggéré/boost) — équivalent `BGTaskScheduler`, différé au module 18 comme
/// la synchro de vues (voir décision module 2 sur `ViewSyncWorker`).
struct HomeShellView: View {
    let user: User

    /// 0-2 = onglets réels à contenu persistant (Accueil/Chat/Créateurs). 3/4 (Notifications/
    /// Profil) ne sont JAMAIS des valeurs stables de `selectedTab` — voir `.onChange` plus bas, qui
    /// les intercepte et restaure immédiatement `lastContentTab`, fidèle au fait qu'Android ne les
    /// marque jamais `setSelected(true)` non plus.
    @State private var selectedTab = 0
    @State private var lastContentTab = 0
    @StateObject private var notificationsViewModel = NotificationCenterViewModel()
    @StateObject private var deepLinks = DeepLinkCenter.shared
    @State private var chatUnreadCount = 0
    @State private var showNotifications = false
    @State private var showProfile = false
    @State private var showSearch = false

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { RosterListView() }
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .badge(chatUnreadCount)
                .tag(1)

            NavigationStack { CreatorOfWeekView() }
                .tabItem { Label("Créateurs", systemImage: "trophy.fill") }
                .tag(2)

            // Onglets 3/4 : pas de contenu propre (jamais réellement affichés, voir `.onChange`
            // ci-dessous qui les intercepte avant tout rendu perceptible) — uniquement présents
            // pour occuper leur position dans la barre à 5 items, fidèle à la disposition visuelle
            // réelle de `navigation_layout.xml`.
            Color.clear
                .tabItem { Label("Notifications", systemImage: "bell.fill") }
                .badge(notificationsViewModel.unreadCount)
                .tag(3)

            Color.clear
                .tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Port du point d'entrée `RechercheTiinver` (module 18, `MainFragment`/
                // `FeedFragment`/`Roster` ouvrent tous cette même Activity) — bouton de recherche
                // ajouté ici plutôt qu'un onglet dédié : aucun item "recherche" dans
                // `navigation_layout.xml` (5 items réels, tous identifiés), donc pas de position de
                // barre de navigation à lui attribuer fidèlement.
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
            }
        }
        .sheet(isPresented: $showNotifications, onDismiss: {
            Task { await notificationsViewModel.refresh() } // rafraîchit le badge après `markAllRead` dans la feuille
        }) {
            NotificationsListView()
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { ProfileView() }
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack { SearchView() }
        }
        .task {
            await notificationsViewModel.refresh()
            await refreshChatUnreadCount()
        }
        .onChange(of: notificationsViewModel.unreadCount) { count in
            // Équivalent du badge Android sur l'icône (pas de contrepartie directe dans
            // `NavigationCompound.java`, qui ne badge que la barre de navigation IN-APP — ajout
            // logique pour l'icône d'app, un badge standard iOS sans équivalent Android à imiter
            // au-delà du chiffre lui-même).
            UNUserNotificationCenter.current().setBadgeCount(count)
        }
        .onChange(of: selectedTab) { newValue in
            // Port du comportement RÉEL de `NavigationCompound.click` : taper Notifications/Profil
            // ne "sélectionne" jamais ces items (pas de `setSelected(true)` dans le source Android),
            // ils ouvrent un écran par-dessus puis reviennent à l'onglet précédent. Restaure donc
            // `selectedTab` IMMÉDIATEMENT plutôt que de laisser `Color.clear` s'afficher, même
            // brièvement.
            switch newValue {
            case 3:
                showNotifications = true
                selectedTab = lastContentTab
            case 4:
                showProfile = true
                selectedTab = lastContentTab
            default:
                lastContentTab = newValue
            }
        }
        .onChange(of: deepLinks.pending) { destination in
            guard let destination = deepLinks.consume() else { return }
            switch destination {
            case .notifications: showNotifications = true
            case .profile: showProfile = true
            case .chat: selectedTab = 1
            }
        }
    }

    /// Port de `NavigationCompound.cursorWorkerTask` (partie badge messagerie) :
    /// `SELECT unreadCount FROM wk_roster WHERE unreadCount > 0`, sommé.
    private func refreshChatUnreadCount() async {
        let roster = RosterRepository()
        let rows = (try? await roster.query(predicate: NSPredicate(format: "unreadCount > 0"))) ?? []
        chatUnreadCount = rows.reduce(0) { $0 + Int($1.unreadCount) }
    }
}
