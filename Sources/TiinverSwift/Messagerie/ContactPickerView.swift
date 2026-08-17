import SwiftUI

/// Port de `contacts/ContactsFragment.java` + `contacts/ChooseFragment.java` + `contacts/
/// Contact.java` (les 3 lus en entier) — **CORRIGÉ le 2026-08-17** : cette vue avait été construite
/// comme un écran UNIQUE de sélection multiple, alors qu'Android est réellement composé de DEUX
/// écrans successifs partageant le même `Adapter`/la même liste (`Contact.onArticleSelected`) :
///
/// 1. **`ContactsFragment`** (mode `.browse` ci-dessous, écran RÉEL par défaut à l'ouverture,
///    `Contact.onCreate` → `onArticleSelected(0, null)`) — liste générale des contacts, tap sur une
///    ligne = **ouvre directement une conversation individuelle** (`Adapter.ContactHolder`,
///    `Intent(ActivityMsg.class)`), PLUS un en-tête cliquable dédié ("créer un groupe", icône ronde
///    rouge `ic_baseline_group_add_24` + `R.string.createGroup`, `R.id.createContact`) qui bascule
///    vers l'écran 2.
/// 2. **`ChooseFragment`** (mode `.selectForGroup` ci-dessous, `onArticleSelected(1, ...)`) — MÊME
///    liste, ré-affichée avec des cases à cocher (`Adapter.ViewHolder`, `LAYOUT_CHANGE`), bande de
///    "chips" des membres choisis (`memberShoosed`), FAB "suivant" (`nextToGroup`) → `Contact.
///    onArticleSelected(2, selection)` → `Group.java` (port : `GroupCreationView.swift`).
///
/// La version précédente de ce fichier sautait directement à l'écran 2 depuis TOUT point d'entrée
/// (FAB "créer groupe" ET lien "Nouveau message" de `RosterListView`), rendant le tap-pour-discuter
/// individuel de l'écran 1 totalement inaccessible — écart signalé explicitement par l'utilisateur
/// ("la liste de contacts... sert normalement aussi à ouvrir une conversation individuelle au
/// clic"), confirmé exact en relisant `Adapter.java`/`Contact.java` en entier.
struct ContactPickerView: View {
    private enum Mode { case browse, selectForGroup }

    @StateObject private var viewModel = ContactPickerViewModel()
    @State private var mode: Mode = .browse
    @State private var goToGroupCreation = false
    @State private var goToChat: GroupMemberCandidate?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if mode == .browse {
                    createGroupHeader
                } else {
                    header
                    if !viewModel.selectedCandidates.isEmpty { selectedChipsStrip }
                }
                Text("Mes Contacts")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                List(viewModel.candidates) { candidate in
                    Button {
                        if mode == .browse {
                            goToChat = candidate // Port de `ContactHolder` — tap = ouvrir la conversation.
                        } else {
                            viewModel.toggle(candidate) // Port de `Adapter.ViewHolder` — tap = coche/décoche.
                        }
                    } label: {
                        contactRow(candidate)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            if mode == .selectForGroup, !viewModel.selected.isEmpty {
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
        // `navigationDestination(item:)` exige iOS 17 (déploiement iOS 16 de ce projet) — même
        // contournement `isPresented`+`Binding(get:set:)` que le reste du code base (voir
        // `MonetizationView.swift`/`FeedView.swift`).
        .navigationDestination(isPresented: Binding(get: { goToChat != nil }, set: { if !$0 { goToChat = nil } })) {
            if let candidate = goToChat {
                ChatView(target: rosterModel(for: candidate))
            }
        }
        .task { await viewModel.load() }
        .overlay {
            if viewModel.isLoading { ProgressView() }
            else if viewModel.candidates.isEmpty {
                Text("Aucun contact").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func contactRow(_ candidate: GroupMemberCandidate) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                CDNAsyncImage(url: URL(string: candidate.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    Circle().fill(Color(.secondarySystemBackground))
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.accentColor, lineWidth: (mode == .selectForGroup && viewModel.selected.contains(candidate.id)) ? 2 : 0))
                if mode == .selectForGroup, viewModel.selected.contains(candidate.id) {
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

    /// Port de `Adapter.ContactHolder.binView`'s `Intent(ActivityMsg.class)` — mêmes champs
    /// `RosterModel` que `ProfileView.messageTarget` (`openConversation(User)`), construits ici
    /// depuis un `GroupMemberCandidate` plutôt qu'un `User` de profil.
    private func rosterModel(for candidate: GroupMemberCandidate) -> RosterModel {
        var target = RosterModel()
        target.type = ChatType.chat.wireValue
        target.nikname = candidate.displayName
        target.username = candidate.username
        target.to = candidate.username
        target.from = UserSession.shared.username
        target.currentUsername = UserSession.shared.username
        target.currentUserId = UserSession.shared.myId
        target.userId = candidate.userId
        target.title = candidate.displayName
        target.subTitle = candidate.username
        target.profile = candidate.profile
        return target
    }

    /// Port de `R.id.createContact` (`fragment_contacts.xml`) — en-tête cliquable de l'écran 1,
    /// bascule vers l'écran 2 (mode `.selectForGroup`).
    private var createGroupHeader: some View {
        Button {
            mode = .selectForGroup
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.accentColor))
                Text("Créer un groupe").font(.title3.bold()).foregroundStyle(.primary) // R.string.createGroup
                Spacer()
            }
            .padding()
        }
        .buttonStyle(.plain)
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
                        CDNAsyncImage(url: URL(string: candidate.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
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
