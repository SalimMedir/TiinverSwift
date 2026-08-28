import SwiftUI

/// Port de `messagerie/group/AddGroupMemberActivity.java` (entier, GAP-011, audit du 2026-08-16) —
/// ajout de participants à un groupe EXISTANT. Réutilise `ContactsRepository.connectedUsers` (déjà
/// porté, module 11) et `GroupRepository.addMembers` (déjà porté pour la CRÉATION de groupe, même
/// endpoint `POST membership` qu'Android utilise pour les deux cas) — pas de nouveau code réseau,
/// juste un nouvel écran de sélection dédié à ce point d'entrée précis (le sélecteur de contacts
/// existant, `ContactPickerView.swift`, est dédié au flux de CRÉATION et n'a délibérément pas été
/// modifié ici pour éviter un conflit avec un travail en cours sur ce fichier).
struct AddGroupMemberView: View {
    let groupId: String
    let existingMemberIds: Set<Int>
    /// **Élargi (2026-08-28, V7-F-008)** — transmet désormais les membres réellement ajoutés
    /// (auparavant `() -> Void`) : cette vue n'a délibérément aucune connaissance du nom/jeton/
    /// profil du groupe (voir la doc de tête de fichier, "portée dédiée"), donc l'écho système
    /// local ("X a ajouté Y", `insertSystemMessage`, qui a besoin de ce contexte) est construit
    /// par l'appelant (`GroupDetailView`), pas ici.
    var onAdded: ([GroupMemberCandidate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [GroupMemberCandidate] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var availableCandidates: [GroupMemberCandidate] {
        candidates.filter { !existingMemberIds.contains(Int($0.userId) ?? -1) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if availableCandidates.isEmpty {
                    // `ContentUnavailableView` est iOS 17+, incompatible avec `deploymentTarget:
                    // 16.0` (`project.yml`) — état vide reconstruit manuellement, même motif que
                    // `FeedView.emptyOrStatusState`.
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Aucun contact à ajouter").foregroundStyle(.secondary)
                    }
                } else {
                    List(availableCandidates) { candidate in
                        HStack {
                            Text(candidate.displayName)
                            Spacer()
                            if selected.contains(candidate.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(candidate.id) }
                    }
                }
            }
            .navigationTitle("Ajouter des participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter (\(selected.count))") { Task { await submit() } }
                        .disabled(selected.isEmpty || isSubmitting)
                }
            }
            .task { await loadContacts() }
            .alert("Erreur", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func loadContacts() async {
        guard let myId = UserSession.shared.myId else { return }
        isLoading = true
        defer { isLoading = false }
        candidates = (try? await ContactsRepository.shared.connectedUsers(userId: myId)) ?? []
    }

    private func submit() async {
        guard let myId = UserSession.shared.myId else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let members = candidates.filter { selected.contains($0.id) }
        await GroupRepository.shared.addMembers(members, toGroupId: groupId, inviterId: myId)
        onAdded(members)
        dismiss()
    }
}
