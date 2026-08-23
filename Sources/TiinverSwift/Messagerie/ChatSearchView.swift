import SwiftUI

/// Port de `Recherche/ui/RechercheTiinver.java` en mode `tokenSearch="chat"` (`Roster.java:437`,
/// lu en entier le 2026-08-18, P1 — **corrige une note d'audit antérieure erronée** affirmant
/// qu'aucune extra ne distinguait les points d'entrée : `tokenSearch` EST bien lue et branchée,
/// juste jamais relue jusqu'à cette passe). Ce même `Activity` sert AUSSI le Search principal
/// (`tokenSearch="universal"`, déjà porté intégralement par `SearchView.swift`/`SearchRepository
/// .swift`) — DEUX écrans réellement distincts partageant un seul fichier source côté Android,
/// reproduits ici comme deux vues SwiftUI distinctes plutôt qu'un seul écran à mode caché, plus
/// idiomatique côté iOS.
///
/// Flux réel (`onQueryTextChange`/`RetrieveContacts`/`getItFromServeur`) : filtre D'ABORD les
/// conversations DÉJÀ dans le roster local (titre/dernier message/sous-titre contient la requête,
/// insensible à la casse) ; SEULEMENT si ce filtre local ne donne AUCUN résultat, repli serveur
/// `search/{myId}/{str}` → groupes publics REJOIGNABLES (pas encore dans le roster). Taper sur un
/// résultat, qu'il soit local ou serveur, ouvre directement `ChatView` — Android n'a PAS d'étape
/// de confirmation "rejoindre" séparée (`ChatAdapter`'s `itemView.setOnClickListener` construit le
/// `RosterModel` et lance `ActivityMsg` directement dans les deux cas, `ChatAdapter.java:291-313`).
struct ChatSearchView: View {
    @ObservedObject var rosterViewModel: RosterListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var serverGroups: [GroupRepository.GroupInfo] = []
    @State private var isSearchingServer = false
    @State private var searchTask: Task<Void, Never>?
    @State private var openTarget: RosterModel?

    private var localMatches: [RosterListViewModel.Row] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        // Port de `title.toLowerCase().contains(str) || message.toLowerCase().contains(str) ||
        // subTitle.toLowerCase().contains(str)` — filtre local sur les données DÉJÀ chargées par
        // `RosterListViewModel` (équivalent du `Cursor` local Android, mêmes lignes `wk_roster`).
        // Corrigé (V3-F-108, SEARCH complémentaire) : `message` (texte du dernier message,
        // `Row.lastMessage`) manquait au filtre — seuls `title`/`subtitle` étaient comparés, alors
        // qu'Android compare les 3 champs. Une recherche par mot-clé du contenu d'un message
        // échouait silencieusement côté iOS.
        return rosterViewModel.rows.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
                || ($0.lastMessage?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !localMatches.isEmpty {
                    Section {
                        ForEach(localMatches) { row in
                            Button { openTarget = row.rosterModel } label: {
                                ChatSearchRow(title: row.title, subtitle: row.subtitle, profile: row.profile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Port de la branche repli serveur — n'apparaît QUE si le filtre local est vide,
                    // fidèle à `searchOnLocal` (Android n'interroge JAMAIS le serveur si une
                    // correspondance locale existe déjà).
                    Section {
                        if isSearchingServer {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else if serverGroups.isEmpty {
                            Text("Aucun résultat").foregroundStyle(.secondary)
                        } else {
                            ForEach(serverGroups, id: \.id) { group in
                                Button {
                                    guard let myId = UserSession.shared.myId else { return }
                                    openTarget = group.rosterModel(myId: myId, myUsername: UserSession.shared.username)
                                } label: {
                                    // Port de `R.string.groupinfo`, corrigé avec `RosterListView.swift`/
                                    // `GroupRepository.swift` (V3-F-006, P1) — vraie traduction française.
                                    ChatSearchRow(title: group.name, subtitle: "onglet ici pour les informations sur le groupe", profile: group.profile)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Groupes")
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .onChange(of: query) { _ in scheduleServerSearchIfNeeded() }
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            // `navigationDestination(item:)` exige iOS 17 (déploiement iOS 16 de ce projet, voir
            // commit `e860d32`) — même contournement `isPresented:`+`Binding(get:set:)` que le
            // reste du code base (`FeedView.swift`/`MonetizationView.swift`/`ContactPickerView
            // .swift`). Rattaché DANS la `NavigationStack` propre à cette vue (présentée en
            // `.sheet`, donc pas d'ambiante héritée d'un parent) — un `.navigationDestination` posé
            // en dehors de sa `NavigationStack` ne s'enregistre pas correctement.
            .navigationDestination(isPresented: Binding(get: { openTarget != nil }, set: { if !$0 { openTarget = nil } })) {
                if let target = openTarget {
                    ChatView(target: target)
                }
            }
        }
    }

    /// Port du debounce `onQueryTextChange` (`RechercheTiinver.java`, 300ms) — ne lance le repli
    /// serveur QUE si le filtre local est vide, ANNULE toute recherche serveur précédente encore en
    /// vol si l'utilisateur continue de taper (`cancelDebounce`).
    private func scheduleServerSearchIfNeeded() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, localMatches.isEmpty, let myId = UserSession.shared.myId else {
            serverGroups = []
            isSearchingServer = false
            return
        }
        isSearchingServer = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let results = (try? await GroupRepository.shared.searchGroups(myId: myId, query: q)) ?? []
            guard !Task.isCancelled else { return }
            serverGroups = results
            isSearchingServer = false
        }
    }
}

private struct ChatSearchRow: View {
    let title: String
    let subtitle: String
    let profile: String?

    var body: some View {
        HStack(spacing: 12) {
            CDNAsyncImage(url: URL(string: profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Circle().fill(Color(.secondarySystemBackground))
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(.primary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
