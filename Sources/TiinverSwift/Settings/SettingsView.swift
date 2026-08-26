import SwiftUI

/// Port de `setting/SettingsActivity.java` (193, entier) — menu de réglages. **Découverte
/// importante en lisant les fragments un par un** : plusieurs entrées du menu Android sont, à
/// l'usage réel, très différentes de ce que leur nom suggère ou sont partiellement mortes — voir
/// les avertissements de chaque écran ci-dessous, tous vérifiés par lecture complète du fragment
/// correspondant (PAS supposés à partir du nom de classe seul).
struct SettingsView: View {
    /// Port de `Intent(SettingsActivity) putExtra(INDEX, 7)` (`ShareActivity.java:179-185`, lien
    /// profond `myaccount`) — **ajouté le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-137,
    /// Phase B P1)**. Android ouvre `SettingsActivity` DIRECTEMENT sur `SettingAccountFragment`
    /// (INDEX=7), pas sur la liste racine — `pushAccount` reproduit ce saut direct au premier
    /// affichage, sans perdre la possibilité de revenir à la liste complète (fidèle au conteneur
    /// de fragment `SettingsActivity`, pas un écran isolé sans retour).
    var startAtAccount: Bool = false
    @State private var pushAccount = false

    var body: some View {
        List {
            Section {
                NavigationLink("Compte") { SettingAccountView() } // case 7, SettingAccountFragment
                // Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-012, Phase B P2) — menait
                // DIRECTEMENT au formulaire d'édition (case 10) ; Android n'a AUCUN accès direct à
                // ce formulaire (`grep onFragmentInteraction(10)` = 1 seul appelant, le bouton
                // "Modifier" de l'écran lecture seule ci-dessous) — redirigé vers ce résumé (case 9).
                NavigationLink("Informations personnelles") { PersonalInformationSummaryView() }
                NavigationLink("Certification") { CertificationView() } // module 18, ui/certification
            }
            Section {
                NavigationLink("Confidentialité") { SettingPrivacyView() } // case 4
                NavigationLink("Notifications") { SettingNotificationsView() } // case 3
                NavigationLink("Stockage et données") { SettingStorageView() } // case 5
                NavigationLink("Apparence") { SettingAppearanceView() } // case 2, SettingChatFragment (nom Android trompeur — voir avertissement du fichier)
                NavigationLink("Publicité") { SettingAdvertisementView() } // case 11
            }
            Section {
                NavigationLink("Aide") { SettingHelpView() } // case 6
                NavigationLink("À propos") { SettingAboutView() } // case 8
                // Port de `header_updateapp` (`Adapter.java:171-176`→`BlankFragment.onAppUpdate()`
                // →`UpdateApp.java`) — **ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md
                // V5-F-051, Phase B P2)**. Dernière entrée du menu racine côté Android
                // (`item_headers_of_settings.xml`, `header_updateapp` après `header_about`),
                // toujours visible (pas conditionnée), ouvrant la fiche App/Play Store —
                // `UpdateAppView` (déjà porté) n'avait jusqu'ici qu'un seul appelant, le blocage
                // forcé de `RootRouterView` : aucun moyen d'y accéder manuellement.
                NavigationLink("Mise à jour") { UpdateAppView() }
            }
        }
        .navigationTitle("Réglages")
        .navigationDestination(isPresented: $pushAccount) { SettingAccountView() }
        .onAppear {
            if startAtAccount { pushAccount = true }
        }
    }
}
