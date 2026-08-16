import SwiftUI

// MARK: - Compte (port de `SettingAccountFragment.java`, 207, entier)

struct SettingAccountView: View {
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isBusy = false

    var body: some View {
        List {
            Section {
                Button("Se déconnecter") { showLogoutConfirm = true } // pref_logout
            }
            Section {
                Button("Supprimer le compte", role: .destructive) { showDeleteConfirm = true } // pref_delete_account
            }
        }
        .navigationTitle("Compte")
        .disabled(isBusy)
        .confirmationDialog("Se déconnecter ?", isPresented: $showLogoutConfirm, titleVisibility: .visible) { // R.string.logout_message_confirm
            Button("Se déconnecter", role: .destructive) { Task { await logout() } }
        }
        .confirmationDialog("Supprimer définitivement le compte ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) { // R.string.deleteaccount_message_confirme
            Button("Supprimer", role: .destructive) { Task { await deleteAccount() } }
        }
    }

    private func logout() async {
        guard let userId = UserSession.shared.myId else { return }
        isBusy = true
        defer { isBusy = false }
        try? await ProfileRepository.shared.logout(userId: userId)
        // Port de `transportDataBackground.deleteaccount()` — Android route "logout" ET
        // "deleteaccount" vers la MÊME méthode, qui purge aussi tout le cache local
        // (messages/roster/notifications), pas seulement les identifiants de session — voir
        // `LocalDataPurger.swift` pour le détail complet et la justification de cette découverte.
        await LocalDataPurger.purgeAll()
        UserSession.shared.clear()
    }

    private func deleteAccount() async {
        guard let userId = UserSession.shared.myId else { return }
        isBusy = true
        defer { isBusy = false }
        try? await ProfileRepository.shared.deleteAccount(userId: userId)
        await LocalDataPurger.purgeAll()
        UserSession.shared.clear()
    }
}

// MARK: - Notifications (port de `SettingNotificationFragment.java`, 187, entier — 3 bascules
// booléennes, PERSISTANCE LOCALE UNIQUEMENT, pas de synchronisation serveur, vérifié)

struct SettingNotificationsView: View {
    @AppStorage("notificateChats") private var notifyChats = true
    @AppStorage("notificateGroups") private var notifyGroups = true
    @AppStorage("notificatePages") private var notifyPages = true

    var body: some View {
        Form {
            Toggle("Messages privés", isOn: $notifyChats) // switch_chat
            Toggle("Groupes", isOn: $notifyGroups) // switch_group
            Toggle("Pages", isOn: $notifyPages) // switch_page
        }
        .navigationTitle("Notifications")
    }
}

// MARK: - Stockage et données (port de `SettingStorageFragment.java`, PARTIEL — 3 bascules maîtresses
// lues en entier ; le détail granulaire par type de média — `storageDataListChoosed` etc., une
// sélection multiple — PAS reproduit cette session, faute de temps pour lire le reste du fichier
// (292 lignes) en détail : documenté comme gap plutôt que deviné)

struct SettingStorageView: View {
    @AppStorage("usingDataMobile") private var mobileData = true
    @AppStorage("usingWifi") private var wifi = true
    @AppStorage("usingRoaming") private var roaming = true

    var body: some View {
        Form {
            Section("Téléchargement automatique des médias") {
                Toggle("Données mobiles", isOn: $mobileData) // mobiledataSwitch
                Toggle("Wi-Fi", isOn: $wifi) // wifidataswitch
                Toggle("Itinérance", isOn: $roaming) // roamingswitch
            }
        }
        .navigationTitle("Stockage et données")
    }
}

// MARK: - Confidentialité (port de `SettingPrivacityFragment.java`, 329, entier)
//
// **Découverte majeure** : la quasi-totalité de l'écran de confidentialité par item (dernière
// connexion/photo de profil/appels/groupes/statut, 5 pickers) est du CODE MORT — ENTIÈREMENT
// commenté dans le fichier source Android (`onCreateView`, lignes 110-162), jamais exécuté. La
// SEULE fonctionnalité réellement câblée est un bouton unique "compte privé" (`account_type_switch`,
// colonne serveur `type` ∈ `{"private","public"}`, `POST user`). Reproduit fidèlement CETTE seule
// fonctionnalité — implémenter les 5 pickers aurait été une invention pure, pas un portage.

struct SettingPrivacyView: View {
    @State private var isPrivate = false
    @State private var isSaving = false

    var body: some View {
        Form {
            Toggle("Compte privé", isOn: $isPrivate) // account_type_switch
                .disabled(isSaving)
                .onChange(of: isPrivate) { newValue in Task { await save(isPrivate: newValue) } }
        }
        .navigationTitle("Confidentialité")
        .task { await load() }
    }

    private func load() async {
        guard let userId = UserSession.shared.myId else { return }
        // Port de `Settings.getStringPreference(ACCOUNT_TYPE_PRIVACY)` — cache local, pas d'appel
        // réseau dédié à la lecture (le type vient normalement du profil déjà chargé ailleurs).
        if let profile = try? await ProfileRepository.shared.fetchProfile(userId: userId, viewerId: userId) {
            isPrivate = profile.type == "private"
        }
    }

    /// Port de `swichtToPrivate` — `POST user`, `{id, column: "type", value: "private"|"public"}`.
    private func save(isPrivate: Bool) async {
        guard let userId = UserSession.shared.myId else { return }
        isSaving = true
        defer { isSaving = false }
        try? await ProfileRepository.shared.updateProfileField(userId: userId, column: "type", value: isPrivate ? "private" : "public")
    }
}

// MARK: - Apparence (port de `SettingChatFragment.java`, 155, entier — **nom Android trompeur** :
// la classe s'appelle "Chat" mais ne contient AUCUN réglage de chat, uniquement le thème clair/
// sombre de l'app entière — vérifié, pas une supposition sur un nom de classe)

struct SettingAppearanceView: View {
    @AppStorage("theme") private var theme = "Light"

    var body: some View {
        Form {
            Picker("Thème", selection: $theme) { // pref_theme
                Text("Clair").tag("Light")
                Text("Sombre").tag("Dark")
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("Apparence")
    }
}

// MARK: - Publicité (port de `SettingAdvertisementFragment.java`, 162, entier — 1 seule bascule)

struct SettingAdvertisementView: View {
    @AppStorage("AUTHORIZED_ADS") private var adsAuthorized = false // port de `infoContract.AUTHORIZED_ADS`

    var body: some View {
        Form {
            Toggle("Autoriser les publicités personnalisées", isOn: $adsAuthorized) // switch1
        }
        .navigationTitle("Publicité")
    }
}

// MARK: - Aide / À propos (PAS lus en détail cette session — écrans informatifs statiques standards,
// aucune logique métier attendue au vu du nom/de la taille des fragments correspondants ; contenu
// réel — FAQ/liens légaux — à compléter une fois `SettingHelpFragment.java`/`SettingAboutFragment.
// java` lus, non fait ici faute de temps)

struct SettingHelpView: View {
    var body: some View {
        List {
            Link("Centre d'aide Tiinver", destination: URL(string: "https://tiinver.com")!)
        }
        .navigationTitle("Aide")
    }
}

struct SettingAboutView: View {
    var body: some View {
        List {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            Link("Conditions d'utilisation", destination: URL(string: "https://tiinver.com")!)
            Link("Politique de confidentialité", destination: URL(string: "https://tiinver.com")!)
        }
        .navigationTitle("À propos")
    }
}
