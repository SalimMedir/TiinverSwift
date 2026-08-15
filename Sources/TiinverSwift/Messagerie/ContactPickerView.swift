import SwiftUI

/// Port de `contacts/ContactsFragment.java` + `contacts/ChooseFragment.java` (lus en entier,
/// 2026-08-15) — étape 1 de la création de groupe : liste des contacts Tiinver
/// (`ConnectedUsersRepository`), sélection multiple (case à cocher par ligne, comme
/// `Adapter.LAYOUT_CHANGE`/`onMemberSelected`/`onMemberRemoved`), bouton "Suivant" (FAB
/// `nextToGroup` côté Android) vers `GroupCreationView` (port de `contacts/Group.java`).
struct ContactPickerView: View {
    @StateObject private var viewModel = ContactPickerViewModel()
    @State private var goToGroupCreation = false

    var body: some View {
        List(viewModel.candidates) { candidate in
            Button {
                viewModel.toggle(candidate)
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: candidate.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                        Circle().fill(Color(.secondarySystemBackground))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.displayName).font(.body).foregroundStyle(.primary)
                        if let username = candidate.username { Text(username).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName: viewModel.selected.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.selected.contains(candidate.id) ? Color.accentColor : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        // R.string.creer_groupe (chaîne réelle du titre de l'Activity Contact, écran "créer groupe").
        .navigationTitle("Créer un groupe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Suivant") { goToGroupCreation = true }
                    .disabled(viewModel.selected.isEmpty)
            }
        }
        .navigationDestination(isPresented: $goToGroupCreation) {
            GroupCreationView(members: viewModel.selectedCandidates)
        }
        .task { await viewModel.load() }
        .overlay {
            if viewModel.isLoading { ProgressView() }
            else if viewModel.candidates.isEmpty {
                Text("Aucun contact").foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class ContactPickerViewModel: ObservableObject {
    @Published private(set) var candidates: [GroupMemberCandidate] = []
    @Published private(set) var isLoading = false
    @Published var selected: Set<String> = []

    private let repository = ContactsRepository.shared

    var selectedCandidates: [GroupMemberCandidate] {
        candidates.filter { selected.contains($0.id) }
    }

    func load() async {
        guard let userId = UserSession.shared.myId else { return }
        isLoading = true
        defer { isLoading = false }
        candidates = (try? await repository.connectedUsers(userId: userId)) ?? []
    }

    func toggle(_ candidate: GroupMemberCandidate) {
        if selected.contains(candidate.id) { selected.remove(candidate.id) } else { selected.insert(candidate.id) }
    }
}
