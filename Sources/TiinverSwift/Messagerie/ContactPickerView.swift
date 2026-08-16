import SwiftUI

/// Port de `contacts/ContactsFragment.java` + `contacts/ChooseFragment.java` (lus en entier,
/// 2026-08-15) — étape 1 de la création de groupe : liste des contacts Tiinver
/// (`ConnectedUsersRepository`), sélection multiple, vers `GroupCreationView` (port de
/// `contacts/Group.java`).
///
/// **Parité UI avec Android corrigée par capture d'écran (2026-08-16)** — 3 écarts visuels réels
/// trouvés et corrigés : (1) en-tête dédiée sous la barre de titre (icône ronde rose "personnes+"
/// + "creer groupe" en gras), pas seulement un titre de navigation ; (2) sélection indiquée par un
/// BADGE superposé au coin de l'avatar (coche sur fond sombre), pas une icône séparée à droite de
/// la ligne ; (3) une fois au moins un contact sélectionné, une bande horizontale de "chips"
/// (avatar + nom, fond gris) apparaît sous l'en-tête pour récapituler la sélection, ET le bouton
/// "Suivant" devient un FAB rond rose bas-droite (icône flèche d'envoi) plutôt qu'un bouton texte
/// de barre d'outils.
struct ContactPickerView: View {
    @StateObject private var viewModel = ContactPickerViewModel()
    @State private var goToGroupCreation = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                header
                if !viewModel.selectedCandidates.isEmpty { selectedChipsStrip }
                Text("Mes Contacts")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                List(viewModel.candidates) { candidate in
                    Button {
                        viewModel.toggle(candidate)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                AsyncImage(url: URL(string: candidate.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                                    Circle().fill(Color(.secondarySystemBackground))
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: viewModel.selected.contains(candidate.id) ? 2 : 0))
                                if viewModel.selected.contains(candidate.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.white, .black)
                                        .background(Circle().fill(.black))
                                        .font(.system(size: 16))
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.displayName).font(.body).foregroundStyle(.primary)
                                if let username = candidate.username { Text(username).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            if !viewModel.selected.isEmpty {
                Button { goToGroupCreation = true } label: {
                    Image(systemName: "arrow.up")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(radius: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
        // R.string.creer_groupe (chaîne réelle du titre de l'Activity Contact, écran "créer groupe")
        // — reste le titre de barre de navigation, la capture montre "Contact" (nom d'écran
        // générique) au-dessus de l'en-tête dédiée "creer groupe" — les deux sont fidèlement
        // reproduits ici, l'un via `navigationTitle`, l'autre via `header` ci-dessous.
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
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

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.accentColor))
            Text("creer groupe").font(.title3.bold())
            Spacer()
        }
        .padding()
    }

    private var selectedChipsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.selectedCandidates) { candidate in
                    VStack(spacing: 4) {
                        AsyncImage(url: URL(string: candidate.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                            Circle().fill(Color(.secondarySystemBackground))
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        Text(candidate.displayName).font(.caption2).lineLimit(1).frame(width: 50)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
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
