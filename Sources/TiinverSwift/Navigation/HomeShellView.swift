import SwiftUI
import Foundation
import UserNotifications

/// Port de la coquille post-connexion `Activity/ui/HomeActivity.java` +
/// `view/navigation/NavigationCompound.java` + `Activity/adapter/MyPagerAdapter.java`.
///
/// Structure vérifiée dans le code source (pas devinée) :
/// - 3 onglets dans un `ViewPager` NON swipeable (`viewPager.setSwipeable(false)` — navigation
///   uniquement via la barre du bas), piloté par `NavigationCompound` : `MainFragment` (flux
///   vidéo, module 6 — `FeedView.swift`, ÉCRIT), `Roster` (liste des conversations — `Messagerie/
///   RosterListView.swift`, fermé le 2026-08-13 après découverte via test interactif Appetize.io
///   que ce gap déjà documenté au module 11 restait branché sur un placeholder), `CreatorFragment`
///   ("créateur de la semaine" — classement, `Creators/CreatorOfWeekView.swift`, confirmé N'
///   APPARTENIR À AUCUN des 18 modules de l'ordre de portage original, mini-module ajouté le
///   2026-08-13 après la même découverte). Voir MIGRATION_PROGRESS.md pour le détail complet des
///   deux fermetures.
/// - `navigation_notifications` et `navigation_profile` ne sont PAS des onglets du ViewPager :
///   ils lancent des Activity séparées (`ShowNoti`, `AddPerfilFoto`) — reproduit ici comme des
///   écrans présentés en `sheet`, pas des onglets `TabView`.
/// - Badge `navigation_chat` = somme de `wk_roster.unreadCount` (`NavigationCompound.
///   cursorWorkerTask`, `ROSTER_URI`) → `RosterRepository` (déjà écrit, module 2). Badge
///   `navigation_notifications` = `NotiDatabase.countUnread()` → `NotiRepository`/
///   `NotificationCenterViewModel` (déjà écrits, module 4).
///
/// PAS porté ici, volontairement : le gate de mise à jour forcée par Firebase Remote Config
/// (`HomeActivity.initRemoteConfigAndLoadValues`/`FirebaseConfigManager`, `UpdateApp` activity) —
/// même blocage SDK Firebase que les modules 3 et 4 (voir `LoginView.swift`,
/// `PushTokenRegistrar.swift`) ; les 3 `scheduleDynamicWorker` (WorkManager, contenu suggéré/
/// boost) — équivalent `BGTaskScheduler`, différé au module 18 comme la synchro de vues
/// (voir décision module 2 sur `ViewSyncWorker`).
struct HomeShellView: View {
    let user: User

    @State private var selectedTab = 0
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
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Port du point d'entrée `RechercheTiinver` (module 18, `MainFragment`/
                // `FeedFragment`/`Roster` ouvrent tous cette même Activity) — bouton de recherche
                // ajouté ici plutôt qu'un onglet dédié, aucun onglet "recherche" identifié dans la
                // barre de navigation à 3 onglets d'origine (`NavigationCompound.java`).
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNotifications = true
                } label: {
                    Image(systemName: "bell.fill")
                }
                .overlay(alignment: .topTrailing) {
                    if notificationsViewModel.unreadCount > 0 {
                        Text("\(notificationsViewModel.unreadCount)")
                            .font(.caption2)
                            .padding(4)
                            .background(Circle().fill(.red))
                            .foregroundStyle(.white)
                            .offset(x: 8, y: -8)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                }
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
