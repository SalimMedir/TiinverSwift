import SwiftUI

/// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-012, Phase B P2)** — port de
/// `setting/FragmentProfile.java` (247, entier, cas 9 de `SettingsActivity`), un écran lecture
/// seule ENTIÈREMENT absent côté iOS jusqu'ici : nickname/localisation/travail/qualification/
/// école/username/genre/date de naissance/téléphone/email, chargés depuis `getuserbyid` (même
/// endpoint qu'Android via son cache local synchronisé, `ContentResolver.query(ACCOUNT_URI)`).
/// Chaîne de navigation réelle Android : Réglages → Compte (`SettingAccountFragment`, bouton
/// `pref_personnel_info`, ligne 97-105) → CET écran (case 9) → bouton `editbtn` (ligne 73-80) →
/// formulaire d'édition (case 10, `EditPersonalInformationView` déjà porté) — AUCUN accès direct
/// au formulaire d'édition n'existe côté Android (confirmé par `grep onFragmentInteraction\(10\)`
/// = un seul appelant, ce bouton précis). Reproduite ici via `SettingAccountView` (nouvelle entrée)
/// ET conservée comme destination du raccourci racine déjà existant (`SettingsView`, qui pointait
/// directement vers le formulaire d'édition avant ce correctif — redirigé vers ce résumé).
struct PersonalInformationSummaryView: View {
    @State private var profile: User?

    var body: some View {
        List {
            Section {
                row("Pseudo", profile?.nikname) // tv, R.id.LeNom
                row("Nom d'utilisateur", profile?.username.map { "@\($0)" }) // tv5, R.id.username
                row("Localisation", profile?.location) // tv1, R.id.LeLocation
                row("Métier", profile?.work) // tv2, R.id.LeTravail
                row("Qualification", profile?.qualification) // tv3, R.id.LeQualification
                row("Établissement", profile?.school) // tv4, R.id.LeEtude
                row("Genre", displayGender(profile?.gender)) // R.id.gender
                row("Date de naissance", profile?.birthday) // R.id.birthday
            }
            // Port de `phoneView`/`emailView` (`FragmentProfile.java:59,61`) — seul endroit de
            // toute l'app où le téléphone/email enregistré de l'utilisateur est visible.
            Section {
                row("Téléphone", profile?.phone)
                row("Email", profile?.email)
            }
            Section {
                NavigationLink("Modifier") { EditPersonalInformationView() } // editbtn
            }
        }
        .navigationTitle("Informations personnelles")
        .task { await load() }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—").foregroundStyle(.secondary)
        }
    }

    /// Port de `FragmentProfile.getGender` — "M"/"F" sont les 2 SEULES valeurs Android, mêmes
    /// libellés que `EditPersonalInformationView`'s `genderSpinner`.
    private func displayGender(_ raw: String?) -> String? {
        switch raw {
        case "M": return "Homme"
        case "F": return "Femme"
        default: return raw
        }
    }

    private func load() async {
        guard let userId = UserSession.shared.myId else { return }
        profile = try? await ProfileRepository.shared.fetchProfile(userId: userId, viewerId: userId)
    }
}
