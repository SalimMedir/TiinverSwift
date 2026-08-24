import SwiftUI

/// Port de `EditProfile.java` (190, entier) — biographie/lien/catégorie.
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var biography = ""
    @State private var link = ""
    @State private var isSaving = false
    /// Port de `categoryView.setOnClickListener` → `Intent(ctx, CategoryActivity.class)`
    /// (`EditProfile.java:68-75`), re-lu au retour sur `onResume` (lignes 86-129). **Corrigé le
    /// 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-128, Phase B P1)** — avant ce correctif, ce
    /// point d'entrée manquait ICI (documenté comme différé) alors qu'un doublon fonctionnel avait
    /// été ajouté au mauvais endroit (`Settings/SettingSubViews.swift`, `SettingAccountView`,
    /// "Réglages > Compte" — aucun équivalent Android identifié à cet emplacement). DÉPLACÉ ici
    /// plutôt que dupliqué plus longtemps, pour éviter la double-maintenance signalée par ce
    /// finding.
    @State private var showCategoryPicker = false
    @State private var currentCategoryId: String?
    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-011, Phase B P2)** — port de
    /// `EditProfile.onResume` (`EditProfile.java:86-128`) : la bio/le lien existants sont affichés
    /// EN PLACEHOLDER (`bioInput.setHint(biography)`/`linkView.setHint(link)`), PAS pré-remplis
    /// dans le champ éditable (`setText` n'est jamais appelé pour ces 2 champs, contrairement à
    /// `category`). Reproduit fidèlement ici — PAS une pré-saisie de `$biography`/`$link`, qui
    /// changerait le comportement de `save()` (`if !biography.isEmpty` : un champ non retouché
    /// resterait vide et ne serait donc PAS envoyé, fidèle à Android, qui ne permet pas non plus
    /// d'effacer un champ existant depuis cet écran).
    @State private var existingBiography: String?
    @State private var existingLink: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Biographie") { // R.id.biographyInput
                    TextField(existingBiography?.isEmpty == false ? existingBiography! : "Biographie (160 caractères max)", text: $biography, axis: .vertical)
                        .onChange(of: biography) { newValue in
                            if newValue.count > 160 { biography = String(newValue.prefix(160)) }
                        }
                    Text("\(biography.count)/160").font(.caption2).foregroundStyle(.secondary) // R.id.charCounter
                }
                Section("Lien") { // R.id.linkInput
                    TextField(existingLink?.isEmpty == false ? existingLink! : "https://...", text: $link).keyboardType(.URL).autocapitalization(.none)
                }
                Section {
                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text("Catégorie du compte").foregroundStyle(.primary)
                            Spacer()
                            Text(CategoryCatalog.label(forId: currentCategoryId) ?? "Non définie")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Modifier le profil")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { Task { await save() } }.disabled(isSaving) } // R.id.guardarProfile
            }
            .task { await loadCategory() }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerView(
                    currentCategoryId: currentCategoryId,
                    onSaved: { currentCategoryId = $0; showCategoryPicker = false },
                    onCancel: { showCategoryPicker = false }
                )
            }
        }
    }

    private func loadCategory() async {
        guard let userId = UserSession.shared.myId else { return }
        guard let profile = try? await ProfileRepository.shared.fetchProfile(userId: userId, viewerId: userId) else { return }
        currentCategoryId = profile.category
        existingBiography = profile.biography
        existingLink = profile.link
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
