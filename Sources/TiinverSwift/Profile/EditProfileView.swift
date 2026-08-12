import SwiftUI

/// Port de `EditProfile.java` (190, entier) — biographie/lien/catégorie. **Catégorie NON portée
/// cette session** : `CategoryActivity` (écran séparé, sélection dans une taxonomie non lue) — le
/// champ reste affiché en lecture seule ici, modification différée.
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var biography = ""
    @State private var link = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Biographie") { // R.id.biographyInput
                    TextField("Biographie (160 caractères max)", text: $biography, axis: .vertical)
                        .onChange(of: biography) { newValue in
                            if newValue.count > 160 { biography = String(newValue.prefix(160)) }
                        }
                    Text("\(biography.count)/160").font(.caption2).foregroundStyle(.secondary) // R.id.charCounter
                }
                Section("Lien") { // R.id.linkInput
                    TextField("https://...", text: $link).keyboardType(.URL).autocapitalization(.none)
                }
            }
            .navigationTitle("Modifier le profil")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { Task { await save() } }.disabled(isSaving) } // R.id.guardarProfile
            }
        }
    }

    /// Port de `EditProfile.UpdateProfileData` — un champ n'est envoyé QUE s'il n'est pas vide
    /// (fidèle : Android ne permet pas d'effacer un champ existant depuis cet écran).
    private func save() async {
        guard let userId = UserSession.shared.myId else { return }
        isSaving = true
        defer { isSaving = false }
        if !biography.trimmingCharacters(in: .whitespaces).isEmpty {
            try? await ProfileRepository.shared.updateProfileField(userId: userId, column: "biography", value: biography)
        }
        if !link.trimmingCharacters(in: .whitespaces).isEmpty {
            try? await ProfileRepository.shared.updateProfileField(userId: userId, column: "link", value: link)
        }
        dismiss()
    }
}
