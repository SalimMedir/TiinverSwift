import SwiftUI

/// Port de `setting/EditPersonalInformation.java` (235, entier) — nom complet/localisation/emploi/
/// études/qualification/date de naissance/genre.
struct EditPersonalInformationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fullname = ""
    @State private var location = ""
    @State private var work = ""
    @State private var school = ""
    @State private var qualification = ""
    @State private var birthday = Date()
    @State private var showBirthdayPicker = false
    @State private var gender = "M"
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
                        Text(birthdayFormatter.string(from: birthday)).foregroundStyle(.secondary)
                    }
                }
                Picker("Genre", selection: $gender) { // R.id.genderSpinner — "M"/"F" (2 seules valeurs Android)
                    Text("Homme").tag("M") // R.string.man
                    Text("Femme").tag("F") // R.string.women
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
                    DatePicker("Date de naissance", selection: $birthday, displayedComponents: .date)
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
    /// par ligne dans le fichier source, pas unifié).
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
        try? await repository.updateProfileField(userId: userId, column: "birthday", value: birthdayFormatter.string(from: birthday))
        try? await repository.updateProfileField(userId: userId, column: "gender", value: gender)
        dismiss()
    }
}
