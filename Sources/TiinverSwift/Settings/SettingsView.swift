import SwiftUI

/// Port de `setting/SettingsActivity.java` (193, entier) — menu de réglages. **Découverte
/// importante en lisant les fragments un par un** : plusieurs entrées du menu Android sont, à
/// l'usage réel, très différentes de ce que leur nom suggère ou sont partiellement mortes — voir
/// les avertissements de chaque écran ci-dessous, tous vérifiés par lecture complète du fragment
/// correspondant (PAS supposés à partir du nom de classe seul).
struct SettingsView: View {
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
    }
}
