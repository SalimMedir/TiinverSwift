import SwiftUI

/// Port de `roster/ui/Roster.java` (lu en entier, 761 lignes) — écran-liste des conversations,
/// explicitement laissé de côté à la clôture du module 11 ("écran de liste des conversations...
/// fichier séparé, hors périmètre explicite de cette passe — `RosterModel` accepté en entrée, prêt
/// à être branché"). Ce fichier ferme ce gap : charge `wk_roster` (déjà porté, module 2,
/// `RosterRepository.rosterAll()`), affiche chaque conversation triée par `stamp` DESCENDANT —
/// fidèle au résultat FINAL affiché côté Android (le `CursorLoader` trie ASC en SQL, mais
/// `Roster.sortIt()` re-trie ensuite DESC en mémoire juste avant l'affichage ; seul cet ordre final
/// est reproduit ici, pas la requête SQL intermédiaire).
///
/// **PAS porté, décision de portée** (comme le reste de ce portage lorsqu'un sous-écran nécessite sa
/// propre passe de lecture dédiée) : sélection multiple/suppression (`ToolBarActionCompound`,
/// `RosterListAdapter.itemSelected`) ; assistant IA (`TiinverGeminiAIChat`, hors périmètre
/// `TIINVER_IOS_PORT_ANALYSIS.md`) ; mise à jour temps réel de la liste (présence en ligne/frappe/
/// nouveau message reçu pendant que l'écran est ouvert — `Roster.organizeAndDisplayMessage`, non
/// câblé, `refresh()` manuel via le bouton toolbar en attendant) ; `NewMessage.java` (recherche
/// téléphone/email pour un chat 1:1 direct, écran séparé du sélecteur de contacts). Recherche d'une
/// conversation existante et navigation vers `ChatView` sont portés.
///
/// **Création de groupe portée le 2026-08-15** (test Appetize réel, GAP fonctionnel) — port de
/// `Contact.class` (FAB `GoToContact`) : voir `ContactPickerView.swift`/`GroupCreationView.swift`.
/// **Parité UI avec Android confirmée par capture d'écran (2026-08-16)** — le point d'entrée réel
/// de la création de groupe est un FAB rose bas-droite (icône personnes+plus), PAS l'icône de
/// barre d'outils utilisée dans une version antérieure de ce fichier (`person.2.badge.plus` en
/// `.navigationBarTrailing`) : capture Android montre clairement `Roster.java`'s FAB `GoToContact`
/// (lignes 84,133-144, déjà identifié par le commentaire d'origine, mais le choix "convention
/// native, pas de FAB flottant standard en SwiftUI" s'est avéré être un ÉCART VISUEL réel gênant
/// la découverte du bouton, pas une simplification neutre — corrigé pour correspondre exactement).
/// La capture montre aussi 2 liens texte roses sous la liste des conversations ("+ Nouveau
/// message", "+ Invitez vos amis et votre famille") — "Nouveau message" reste hors périmètre
/// (`NewMessage.java`, recherche téléphone/email pour un chat 1:1 direct, toujours pas porté, voir
/// réserves de portée du fichier) mais affiché fidèlement même si son action reste un stub léger ;
/// "Invitez vos amis" reste le gap contacts déjà documenté (`CNContactStore` non porté).
struct RosterListView: View {
    @StateObject private var viewModel = RosterListViewModel()
    @State private var showContactPicker = false

    var body: some View {
        Group {
            if viewModel.rows.isEmpty && viewModel.hasLoaded {
                emptyState
            } else {
                List {
                    ForEach(viewModel.rows) { row in
                        NavigationLink {
                            ChatView(target: row.rosterModel)
                        } label: {
                            RosterRowView(row: row)
                        }
                    }
                    footerLinks
                }
                .listStyle(.plain)
            }
        }
        // R.string.chat = "Chats" (chaîne Android réelle, reprise verbatim) — teinte rose de
        // marque, fidèle à la capture (titre rendu dans la couleur d'accent, pas noir/systeme).
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Port du FAB `GoToContact` (`Roster.java:84,133-144`).
            Button { showContactPicker = true } label: {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(radius: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .navigationDestination(isPresented: $showContactPicker) {
            ContactPickerView()
        }
        .task { await viewModel.refresh() }
        .onChange(of: showContactPicker) { presented in
            // Reflète immédiatement le nouveau groupe dans la liste dès qu'on revient (pas
            // d'observation temps réel de `wk_roster`, voir réserves de portée ci-dessus).
            if !presented { Task { await viewModel.refresh() } }
        }
    }

    /// Port des 2 liens texte roses sous la liste (`Roster.java`, capture d'écran) — "Nouveau
    /// message" route vers le même sélecteur de contacts qu'un groupe (`NewMessage.java` — écran
    /// dédié recherche téléphone/email — reste hors périmètre, non re-créé ici) ; "Invitez vos
    /// amis" route vers `ReferralView` (déjà porté, module 15) — lien d'invitation générique,
    /// fidèle à l'intention du texte même si le flux contacts natif reste absent.
    private var footerLinks: some View {
        Section {
            Button { showContactPicker = true } label: {
                Label("Nouveau message", systemImage: "plus.circle.fill")
            }
            .foregroundStyle(Color.accentColor)
            NavigationLink {
                ReferralView()
            } label: {
                Label("Invitez vos amis et votre famille", systemImage: "person.badge.plus")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .listRowSeparator(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "message").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Aucune conversation").foregroundStyle(.secondary)
            Button { showContactPicker = true } label: {
                Label("Nouveau message", systemImage: "plus.circle.fill")
            }
            NavigationLink {
                ReferralView()
            } label: {
                Label("Invitez vos amis et votre famille", systemImage: "person.badge.plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RosterRowView: View {
    let row: RosterListViewModel.Row

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: row.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Circle().fill(Color(.secondarySystemBackground))
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(.headline).lineLimit(1)
                Text(row.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if row.unreadCount > 0 {
                Text("\(row.unreadCount)")
                    .font(.caption2.bold())
                    .padding(6)
                    .background(Circle().fill(.red))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
final class RosterListViewModel: ObservableObject {
    struct Row: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        let profile: String?
        let unreadCount: Int
        let stamp: String
        let rosterModel: RosterModel
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var hasLoaded = false

    private let repository = RosterRepository()

    /// Port de `Roster.messagePrivateRoster` (assemblage `Cursor` → `RosterModel`) + `Roster.
    /// sortIt()` (tri final DESC par `stamp`) — assemble chaque ligne `wk_roster` (+ son dernier
    /// message `wk_messages` associé, déjà joint par `RosterRepository.rosterAll()`) en un
    /// `RosterModel` prêt à être passé à `ChatView`, exactement comme `Roster.onItemClicked`
    /// transmet son `RosterModel` à `ActivityMsg` côté Android.
    func refresh() async {
        // Log de diagnostic temporaire (2026-08-16) — avant réception des captures Android, le
        // bouton "créer un groupe" avait été relu et confirmé présent/câblé (alors une icône de
        // toolbar) sans qu'aucun bug statique soit trouvé ; corrigé depuis en FAB fidèle à la
        // capture (voir doc de tête de fichier). Log laissé en place pour confirmer au prochain
        // test que l'écran est bien atteint et que `refresh()` s'exécute.
        print("ROSTER: refresh() started, myId=\(UserSession.shared.myId ?? "nil")")
        guard let entities = try? await repository.rosterAll() else {
            hasLoaded = true
            print("ROSTER: rosterAll() failed or returned nil")
            return
        }
        print("ROSTER: rosterAll() returned \(entities.count) rows")
        let currentUserId = UserSession.shared.myId ?? ""
        let currentUsername = UserSession.shared.username ?? ""
        let currentNikname = UserSession.shared.nikname ?? ""

        rows = entities.compactMap { pair -> Row? in
            let entity = pair.roster
            guard let conversationId = entity.conversationId else { return nil }
            let type = entity.type ?? ChatType.chat.wireValue
            let isGroup = type == ChatType.group.wireValue
            let title = isGroup ? (entity.groupName ?? "") : (entity.nikname ?? entity.username ?? "")
            // Port de `R.string.groupinfo` — chaîne Android réelle ("tab here for group info"),
            // reprise verbatim, PAS corrigée/traduite ici (le reste de l'app est en français, mais
            // cette chaîne précise ne l'est pas côté source non plus).
            let subtitle = isGroup ? "tab here for group info" : (entity.username ?? "")

            var model = RosterModel()
            model.id = Int(entity.localId)
            model.conversationId = conversationId
            model.messageId = entity.messageId
            model.userId = entity.userId
            model.token = entity.token
            model.groupType = entity.groupType
            model.type = type
            model.groupName = entity.groupName
            model.username = entity.username
            model.nikname = entity.nikname
            model.groupId = entity.groupId
            model.stamp = entity.stamp
            model.message = pair.lastMessage?.message ?? entity.lastMessage
            model.object = entity.object
            model.verb = entity.verb
            model.status = Int(entity.status)
            model.profile = entity.profile
            model.title = title
            model.subTitle = subtitle
            model.groupMember = true
            model.vu = entity.unreadCount <= 0
            model.belongsToCurrentUser = entity.belongsToCurrentUser == 1
            model.unreadCount = Int(entity.unreadCount)
            model.creator = "1"
            model.description = entity.rosterDescription
            model.price = Int(entity.price)
            model.lucrative = Int(entity.lucrative)
            model.versionCode = Int(entity.versionCode)
            model.currentUserId = currentUserId
            model.currentUsername = currentUsername
            model.currentNikname = currentNikname
            model.from = currentUsername
            model.to = isGroup ? entity.token : entity.username

            return Row(
                id: model.id,
                title: title,
                subtitle: subtitle,
                profile: entity.profile,
                unreadCount: Int(entity.unreadCount),
                stamp: entity.stamp ?? "0",
                rosterModel: model
            )
        }
        .sorted { (Int64($0.stamp) ?? 0) > (Int64($1.stamp) ?? 0) }

        hasLoaded = true
    }
}
