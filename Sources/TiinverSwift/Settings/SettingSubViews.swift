import SwiftUI

// MARK: - Compte (port de `SettingAccountFragment.java`, 207, entier)

struct SettingAccountView: View {
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isBusy = false

    var body: some View {
        List {
            // Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-012, Phase B P2) — port de
            // `SettingAccountFragment.java:97-105` (`pref_personnel_info`, `onFragmentInteraction(9)`
            // → `FragmentProfile`) — entrée manquante ici avant ce correctif.
            Section {
                NavigationLink("Informations personnelles") { PersonalInformationSummaryView() }
            }
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
        // Port du reset de pile de tâches Android (`FLAG_ACTIVITY_CLEAR_TASK` vers `SplashActivity`
        // — **ajouté le 2026-08-19, MIGRATION_PARITY_AUDIT_V3.md V3-F-051, Phase B P0-4**. Sans ce
        // signal, `RootRouterView.authenticatedUser` restait peuplé et l'utilisateur restait
        // visuellement sur `HomeShellView` avec une session sous-jacente vide.
        NotificationCenter.default.post(name: .userDidLogout, object: nil)
    }

    private func deleteAccount() async {
        guard let userId = UserSession.shared.myId else { return }
        isBusy = true
        defer { isBusy = false }
        try? await ProfileRepository.shared.deleteAccount(userId: userId)
        await LocalDataPurger.purgeAll()
        UserSession.shared.clear()
        NotificationCenter.default.post(name: .userDidLogout, object: nil)
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
    /// Port de la distinction Android entre `setOnClickListener` (tap utilisateur → appel réseau,
    /// `swichtToPrivate`) et `setChecked()` programmatique (revert sur échec, NE redéclenche PAS le
    /// listener) — **ajouté le 2026-08-23 (V4-F-017)** : `.onChange(of:)` de SwiftUI ne fait PAS
    /// cette distinction (un revert programmatique de `isPrivate` le redéclenche comme un tap réel),
    /// ce flag évite qu'un revert n'envoie un second appel réseau non désiré.
    @State private var isReverting = false

    var body: some View {
        Form {
            Toggle("Compte privé", isOn: $isPrivate) // account_type_switch
                .disabled(isSaving)
                .onChange(of: isPrivate) { newValue in
                    if isReverting { isReverting = false; return }
                    Task { await save(isPrivate: newValue) }
                }
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
    ///
    /// **Corrigé le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-017, Phase B P1)** — `try?`
    /// avalait tout échec (réseau OU rejet backend, `updateProfileField` lève désormais correctement
    /// via `isBackendSuccess`) et laissait le toggle sur sa nouvelle position jamais persistée.
    /// Vérifié dans `SettingPrivacityFragment.swichtToPrivate` (lignes 294-328, entier) :
    /// `onError` fait explicitement `account_type_switch.setChecked(!isChecked)` — remet le switch à
    /// son état PRÉCÉDENT, SANS second appel réseau (`setChecked` ne passe pas par le
    /// `setOnClickListener` qui déclenche `swichtToPrivate`). Reproduit ici via `isReverting`.
    private func save(isPrivate: Bool) async {
        guard let userId = UserSession.shared.myId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await ProfileRepository.shared.updateProfileField(userId: userId, column: "type", value: isPrivate ? "private" : "public")
        } catch {
            isReverting = true
            self.isPrivate = !isPrivate
        }
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

// MARK: - Aide / À propos
// `SettingHelpFragment.java` toujours pas lu en détail cette session (FAQ localisée fr/en, bouton
// support avec handler VIDE côté Android aussi — voir V3-F-130, P2, non traité ici). En revanche
// `SettingAboutFragment.java` (V3-F-129, Phase B P1) A ÉTÉ lu en détail le 2026-08-20 : le
// commentaire précédent ("PAS lus en détail... aucune logique métier attendue") était devenu
// obsolète/contredit — ce fragment contient bien 2 URLs légales réelles, pas juste des libellés
// statiques.

/// Port de `SettingHelpFragment.java:88-119` (V3-F-130) — FAQ localisée fr/en selon
/// `Locale.getDefault().getLanguage()`, ET adresse support affichée (`ClickSpan.clickify(support,
/// "support@tiinver.com", ...)`, `onClick` VIDE côté Android réel — le bouton support est mort des
/// deux côtés, fidèlement reproduit : texte affiché mais pas actionnable).
struct SettingHelpView: View {
    @State private var webViewURL: URL?

    private var faqURL: URL {
        let isFrench = Locale.current.language.languageCode?.identifier == "fr"
        return URL(string: isFrench ? "https://tiinver.com/faq_fr.html" : "https://tiinver.com/faq_en.html")!
    }

    var body: some View {
        List {
            Button("FAQ") { webViewURL = faqURL }
            LabeledContent("Support", value: "support@tiinver.com")
        }
        .navigationTitle("Aide")
        .sheet(isPresented: Binding(get: { webViewURL != nil }, set: { if !$0 { webViewURL = nil } })) {
            if let webViewURL {
                InAppWebView(url: webViewURL)
            }
        }
    }
}

struct SettingAboutView: View {
    /// **Corrigé le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-129, Phase B P1)** — avant ce
    /// correctif, les 2 `Link` pointaient vers la racine du site (`https://tiinver.com`), pas les
    /// pages légales réelles (problème de conformité RGPD/App Store review potentiel). Les vraies
    /// URLs (`ClickSpan.clickify`, `SettingAboutFragment.java:93-108`) sont confirmées par
    /// `PoliticaDemandView.swift` (onboarding, MÊMES 2 URLs déjà correctes là-bas). Ouvertes en
    /// `InAppWebView` (port de `MyWebView.java`, réutilisé depuis `PoliticaDemandView.swift`,
    /// rendu `internal` pour l'occasion) plutôt qu'en `Link` Safari externe, fidèle à
    /// `Intent(getActivity(), MyWebView.class)`.
    @State private var webViewURL: URL?

    var body: some View {
        List {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            Button("Conditions d'utilisation") { webViewURL = URL(string: "https://tiinver.com/terms_conditions.html") }
            Button("Politique de confidentialité") { webViewURL = URL(string: "https://tiinver.com/privacy_policy.html") }
        }
        .navigationTitle("À propos")
        .sheet(isPresented: Binding(get: { webViewURL != nil }, set: { if !$0 { webViewURL = nil } })) {
            if let webViewURL {
                InAppWebView(url: webViewURL)
            }
        }
    }
}
