import SwiftUI

/// Port de `setting/EditPersonalInformation.java` (235, entier) — nom complet/localisation/emploi/
/// études/qualification/date de naissance/genre.
///
/// **BUG DE CORRUPTION DE DONNÉES TROUVÉ ET CORRIGÉ le 2026-08-18 (P2)** : côté Android, AUCUN
/// champ de cet écran n'est pré-rempli à l'ouverture (`EditPersonalInformation.java` n'a AUCUNE
/// logique de chargement — ni `onResume`, ni requête `ContentProvider`, contrairement à
/// `EditProfile.java` voisin qui, lui, pré-remplit bio/lien/catégorie via `onResume()`). Chaque
/// champ Android est donc une `EditText`/`TextView` VIDE par défaut, et `UpdateProfileData()`
/// n'envoie QUE les champs non-vides (`!X.getText().toString().trim().isEmpty()`) — un champ
/// jamais touché n'est simplement PAS envoyé, sans écraser la valeur existante côté serveur.
/// La version précédente de ce fichier reproduisait cette garde pour `fullname`/`location`/`work`/
/// `school`/`qualification` (types `String`, `""` par défaut = "vide" représentable), MAIS PAS pour
/// `birthday`/`gender` : `Date()` n'a pas d'équivalent "vide" et `gender = "M"` est une chaîne
/// TOUJOURS non-vide — ces 2 champs étaient donc envoyés à CHAQUE sauvegarde, quel que soit
/// l'écran touché par l'utilisateur, écrasant silencieusement la date de naissance réelle par la
/// date du jour et le genre réel par "M" dès qu'un utilisateur modifiait ne serait-ce que sa
/// qualification. Corrigé en rendant `birthday`/`gender` `Optional` (`nil` = "non touché", fidèle
/// à la sémantique "TextView vide" d'Android) plutôt que de leur donner une valeur par défaut
/// systématiquement non-vide.
struct EditPersonalInformationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fullname = ""
    @State private var location = ""
    @State private var work = ""
    @State private var school = ""
    @State private var qualification = ""
    @State private var birthday: Date?
    @State private var showBirthdayPicker = false
    @State private var gender: String?
    @State private var isSaving = false

    private let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy" // format exact du date_picker Android non confirmé (layout non lu) — ISO courant retenu
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom complet", text: $fullname) // R.id.fullname
                TextField("Localisation", text: $location) // R.id.LeLocation
                Button {
                    showBirthdayPicker = true
                } label: {
                    HStack {
                        Text("Date de naissance") // R.id.birthday
                        Spacer()
                        Text(birthday.map { birthdayFormatter.string(from: $0) } ?? "—").foregroundStyle(.secondary)
                    }
                }
                // Port de `genderSpinner` — `gender` (`R.id.gender`, la `TextView` réellement
                // envoyée) reste VIDE tant que l'utilisateur n'a pas explicitement choisi une
                // valeur dans le sélecteur (`onItemSelected`), fidèle à Android : pas de
                // pré-sélection "Homme" par défaut qui serait envoyée sans action de l'utilisateur.
                Picker("Genre", selection: $gender) { // R.id.genderSpinner — "M"/"F" (2 seules valeurs Android)
                    Text("Non renseigné").tag(String?.none)
                    Text("Homme").tag(String?.some("M")) // R.string.man
                    Text("Femme").tag(String?.some("F")) // R.string.women
                }
                TextField("Métier", text: $work) // R.id.LeTravail
                TextField("Établissement", text: $school) // R.id.LeEtude
                TextField("Qualification", text: $qualification) // R.id.LeQualification
            }
            .navigationTitle("Informations personnelles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { Task { await save() } }.disabled(isSaving) } // R.id.guardarProfile
            }
            .sheet(isPresented: $showBirthdayPicker) {
                NavigationStack {
                    DatePicker("Date de naissance", selection: Binding(get: { birthday ?? Date() }, set: { birthday = $0 }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .navigationTitle("Date de naissance")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showBirthdayPicker = false } } }
                }
                .presentationDetents([.medium])
            }
        }
    }

    /// Port de `EditPersonalInformation.UpdateProfileData` — **asymétrie réelle préservée** : la
    /// colonne locale Core Data (`ContentValues`) diffère du nom de colonne envoyé au serveur pour
    /// `work`/`school` (`work`/`school` en local, `work_At`/`school_At` côté REST — vérifié ligne
    /// par ligne dans le fichier source, pas unifié). **`birthday`/`gender` envoyés SEULEMENT s'ils
    /// ont été explicitement touchés** (voir note de tête de fichier — corrige un bug de
    /// corruption de données trouvé cette passe : ces 2 champs étaient auparavant envoyés à CHAQUE
    /// sauvegarde, écrasant silencieusement les valeurs réelles par des valeurs par défaut).
    private func save() async {
        guard let userId = UserSession.shared.myId else { return }
        isSaving = true
        defer { isSaving = false }
        let repository = ProfileRepository.shared
        if !fullname.trimmingCharacters(in: .whitespaces).isEmpty {
            try? await repository.updateProfileField(userId: userId, column: "firstname", value: fullname)
        }
        if !location.trimmingCharacters(in: .whitespaces).isEmpty {
            try? await repository.updateProfileField(userId: userId, column: "location", value: location)
        }
        if !work.trimmingCharacters(in: .whitespaces).isEmpty {
            try? await repository.updateProfileField(userId: userId, column: "work_At", value: work)
        }
        if !school.trimmingCharacters(in: .whitespaces).isEmpty {
            try? await repository.updateProfileField(userId: userId, column: "school_At", value: school)
        }
        if !qualification.trimmingCharacters(in: .whitespaces).isEmpty {
            try? await repository.updateProfileField(userId: userId, column: "qualification", value: qualification)
        }
        if let birthday {
            try? await repository.updateProfileField(userId: userId, column: "birthday", value: birthdayFormatter.string(from: birthday))
        }
        if let gender {
            try? await repository.updateProfileField(userId: userId, column: "gender", value: gender)
        }
        dismiss()
    }
}
