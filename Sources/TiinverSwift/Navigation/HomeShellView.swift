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
    @State private var deepLinkUserId: String?
    @State private var deepLinkPost: FeedActivity?
    @State private var deepLinkRoster: RosterModel?
    @State private var showSettings = false
    /// Port de `INDEX=7` (`ShareActivity.java:182`) — **ajouté le 2026-08-20
    /// (MIGRATION_PARITY_AUDIT_V3.md V3-F-137, Phase B P1)** : `showSettings` n'a qu'UN seul
    /// déclencheur dans tout le projet (ce switch, `.settingsAccount`), donc toujours fraîche au
    /// moment où le sheet lit sa valeur — pas de risque d'état périmé à réinitialiser.
    @State private var settingsStartAtAccount = false
    @State private var showAnimems = false
    @State private var showReferral = false

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

            // isActive: V4-F-028 — signale à `CreatorOfWeekView` chaque retour sur cet onglet
            // (`TabView` garde ses onglets vivants entre deux sélections, `.task` ne se
            // redéclenche jamais tout seul), port de `CreatorFragment.onResume`.
            NavigationStack { CreatorOfWeekView(isActive: selectedTab == 2) }
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
        // Bandeau de diagnostic (2026-08-16, demande explicite de l'utilisateur : "il faut afficher
        // le userId pourqu'on puisse de savoir si réellement la session fonctionne") — sa cause
        // racine (session vide) est confirmée corrigée depuis (données réelles observées : vrais
        // pseudos/compteurs de likes visibles sur de vraies captures Appetize). **CORRIGÉ le
        // 2026-08-17** (retour utilisateur explicite : "ce type de log ne doit JAMAIS être visible
        // en dehors d'un mode debug explicite") — `#if DEBUG` NE SUFFIT PAS ici : `codemagic.yaml`
        // compile ses DEUX workflows via `xcodebuild build` SANS `-configuration`, qui build en
        // Debug par défaut, donc CHAQUE build Appetize testée par l'utilisateur reste en
        // configuration Debug (vérifié dans le fichier, pas supposé) — un `#if DEBUG` n'aurait
        // masqué le bandeau nulle part en pratique. Repli sur un drapeau `UserDefaults` explicite,
        // désactivé par défaut (jamais visible tant que personne ne l'active manuellement).
        .safeAreaInset(edge: .top) {
            if UserDefaults.standard.bool(forKey: "DebugShowSessionBanner") {
                userIdDebugBanner
            }
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
        // Port des destinations de `ShareActivity.processUrl`/`joinGroup` (`DeepLinkRouter.swift`,
        // 2026-08-16) — même motif `sheet(item:)`/`fullScreenCover` que le reste de l'écran.
        .sheet(isPresented: Binding(get: { deepLinkUserId != nil }, set: { if !$0 { deepLinkUserId = nil } })) {
            if let userId = deepLinkUserId {
                NavigationStack { ProfileView(userId: userId, isCurrentUser: false) }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { deepLinkPost != nil }, set: { if !$0 { deepLinkPost = nil } })) {
            if let post = deepLinkPost {
                // notifiesAuthor: true — un lien profond `/post/{token}` route côté Android par
                // `ShareActivity.getActivities` → `SplashActivity` → contexte `MainFragment` normal
                // (`notifyUser` câblé là aussi), pas un viewer dédié séparé (V4-F-030).
                FeedDetailPagerView(posts: [post], startIndex: 0, notifiesAuthor: true, onClose: { deepLinkPost = nil })
            }
        }
        .fullScreenCover(isPresented: Binding(get: { deepLinkRoster != nil }, set: { if !$0 { deepLinkRoster = nil } })) {
            if let roster = deepLinkRoster {
                NavigationStack { ChatView(target: roster) }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView(startAtAccount: settingsStartAtAccount) }
        }
        .fullScreenCover(isPresented: $showAnimems) {
            AnimemesEditorView(onClose: { showAnimems = false })
        }
        .sheet(isPresented: $showReferral) {
            NavigationStack { ReferralView() }
        }
        .task {
            await notificationsViewModel.refresh()
            await refreshChatUnreadCount()
            // Port de `ShareActivity` (`ShareActivity.java:140-291`), qui résout puis lance
            // DIRECTEMENT l'écran cible (`startActivity`) sans dépendre qu'une autre Activity soit
            // déjà à l'écran et à l'écoute — **ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md
            // V4-F-002, Phase B P1)** : consomme ICI un lien profond déjà résolu AVANT ce montage
            // (cold start, écran de login/AuthCoordinatorView) — `.onChange(of: deepLinks.pending)`
            // ci-dessous ne réagit QUE sur une transition nil→valeur survenant APRÈS l'attachement
            // du modificateur, jamais pour une valeur déjà présente à l'attachement (silencieusement
            // perdu avant ce correctif).
            if let destination = deepLinks.consume() {
                handleDeepLink(destination)
            }
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
        .onChange(of: deepLinks.pending) { _ in
            guard let destination = deepLinks.consume() else { return }
            handleDeepLink(destination)
        }
        // Port de `ShareActivity.onError` → `showDialog()` (V3-F-138, DeepLinks complémentaire) —
        // affiche l'échec de résolution d'un lien profond (user/post/group introuvable, réseau),
        // auparavant totalement silencieux côté iOS.
        .alert(
            "Erreur",
            isPresented: Binding(get: { deepLinks.errorMessage != nil }, set: { if !$0 { deepLinks.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deepLinks.errorMessage ?? "")
        }
    }

    /// Bandeau TEMPORAIRE (voir commentaire sur `.safeAreaInset` ci-dessus) — compare 3 valeurs en
    /// une ligne pour trancher précisément OÙ la session se perd s'il y a un problème :
    /// `user.id` = ce que l'objet reçu au moment de la connexion contenait RÉELLEMENT (permet de
    /// voir si le décodage du login a lui-même trouvé un id, indépendamment de la persistance) ;
    /// `myId` = ce qui est RÉELLEMENT lu depuis `UserSession.shared` (persisté, ce que Feed/Profile
    /// utilisent) ; `apiKey` = présence du jeton d'authentification (Keychain), séparé de `myId`
    /// (UserDefaults) — un écart entre les deux isolerait un problème Keychain spécifique.
    private var userIdDebugBanner: some View {
        let sessionId = UserSession.shared.myId
        let hasKey = UserSession.shared.apiKey != nil
        let ok = sessionId != nil && hasKey
        // 2026-08-17 : ajoute directement ici le JSON brut capturé par `AuthEndpoints.
        // captureRawUserJSONIfIdMissing` (désormais câblé sur LES DEUX chemins, login ET
        // inscription) — plus besoin de naviguer jusqu'à Feed/Profile pour le voir.
        let rawJSON = UserSession.shared.debugLastLoginRawUserJSON
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text("userId(objet reçu)=\(user.id.map(String.init) ?? "nil") · userId(session persistée)=\(sessionId ?? "nil") · apiKey=\(hasKey ? "présent" : "nil")")
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if let rawJSON {
                Text("JSON user reçu (id manquant) : \(rawJSON)")
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
            }
            // 2026-08-17 : statut RÉEL de la dernière écriture Keychain (voir `KeychainStore.swift`
            // — cause confirmée de `apiKey=nil` malgré un login décodé correctement : build
            // Appetize compilé SANS signature de code, `SecItemAdd` peut échouer silencieusement).
            if let keychainStatus = KeychainStore.lastSaveStatusDescription {
                Text("Keychain écriture apiKey : \(keychainStatus)")
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ok ? Color.green : Color.red)
    }

    /// Port de `NavigationCompound.cursorWorkerTask` (partie badge messagerie) :
    /// `SELECT unreadCount FROM wk_roster WHERE unreadCount > 0`, sommé.
    private func refreshChatUnreadCount() async {
        let roster = RosterRepository()
        let rows = (try? await roster.query(predicate: NSPredicate(format: "unreadCount > 0"))) ?? []
        chatUnreadCount = rows.reduce(0) { $0 + Int($1.unreadCount) }
    }

    /// Port de la table de dispatch `ShareActivity.processUrl` — extrait de l'ancien corps de
    /// `.onChange(of: deepLinks.pending)` pour être partagé avec `.task` (voir V4-F-002 ci-dessus,
    /// consommation d'un lien déjà en attente au montage).
    private func handleDeepLink(_ destination: DeepLinkDestination) {
        switch destination {
        case .home: selectedTab = 0
        case .notifications: showNotifications = true
        case .profile: showProfile = true
        case .chat: selectedTab = 1
        case .userProfile(let userId): deepLinkUserId = userId
        case .post(let post): deepLinkPost = post
        case .groupChat(let roster): deepLinkRoster = roster
        case .settingsAccount:
            settingsStartAtAccount = true
            showSettings = true
        case .animems: showAnimems = true
        case .referral: showReferral = true
        }
    }
}
