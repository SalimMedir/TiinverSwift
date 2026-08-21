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
                NavigationLink("Informations personnelles") { EditPersonalInformationView() } // case 10
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
            }
        }
        .navigationTitle("Réglages")
        .navigationDestination(isPresented: $pushAccount) { SettingAccountView() }
        .onAppear {
            if startAtAccount { pushAccount = true }
        }
    }
}
