import SwiftUI

/// Port de `RechercheTiinver.java` — recherche universelle (comptes/publications/hashtags),
/// onglets + suggestions + historique local. UI reconstruite (mise en page XML non fournie), la
/// logique réseau/debounce/onglets est fidèle.
struct SearchView: View {
    @State private var query = ""
    @State private var tab: SearchTab = .all
    @State private var results = SearchResults()
    @State private var recent = RecentSearchStore.all()
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Onglet", selection: $tab) {
                ForEach(SearchTab.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: tab) { _ in runSearch(full: true) }

            List {
                if query.isEmpty {
                    Section("Recherches récentes") { // pas de libellé Android identifié (layout non fourni)
                        ForEach(recent, id: \.self) { entry in
                            Button(entry) { query = entry; runSearch(full: true) }
                        }
                        .onDelete { indices in
                            for index in indices { RecentSearchStore.remove(recent[index]) }
                            recent = RecentSearchStore.all()
                        }
                        if !recent.isEmpty {
                            Button("Tout effacer", role: .destructive) { RecentSearchStore.clearAll(); recent = [] }
                        }
                    }
                } else {
                    if !results.users.isEmpty {
                        Section("Comptes") { // R.string.user
                            ForEach(results.users) { user in
                                NavigationLink { ProfileView(userId: String(user.id), isCurrentUser: false) } label: {
                                    userRow(user)
                                }
                            }
                        }
                    }
                    if !results.hashtags.isEmpty {
                        Section("Hashtags") {
                            ForEach(results.hashtags) { tag in
                                Label("#\(tag.tag)", systemImage: "number")
                            }
                        }
                    }
                    if !results.posts.isEmpty {
                        Section("Publications") { // R.string equivalent non identifié
                            ForEach(results.posts) { post in postRow(post) }
                        }
                    }
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $query, prompt: "Rechercher")
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // port du debounce (DEBOUNCE_DELAY_MS, valeur exacte non lue)
                guard !Task.isCancelled else { return }
                if newValue.count < 2 {
                    if newValue.count >= 1 { await suggest(newValue) }
                } else {
                    runSearch(full: true)
                }
            }
        }
    }

    private func userRow(_ user: SearchUserResult) -> some View {
        HStack {
            AsyncImage(url: URL(string: user.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Color(.secondarySystemBackground)
            }
            .frame(width: 40, height: 40).clipShape(Circle())
            VStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Text("\(user.firstname ?? "") \(user.lastname ?? "")")
                    if user.certified == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.caption) }
                }
                Text("@\(user.username ?? "")").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func postRow(_ post: SearchPostResult) -> some View {
        HStack {
            if let thumb = post.thumbnailURL {
                AsyncImage(url: thumb) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading) {
                Text(post.message ?? "").lineLimit(2)
                Text("@\(post.username ?? "") · \(post.likes ?? 0) ❤️").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func suggest(_ text: String) async {
        results = (try? await SearchRepository.shared.suggest(query: text)) ?? SearchResults()
    }

    private func runSearch(full: Bool) {
        guard query.count >= 2 else { return }
        Task {
            isLoading = true
            defer { isLoading = false }
            results = (try? await SearchRepository.shared.search(query: query, tab: tab)) ?? SearchResults()
            RecentSearchStore.save(query)
            recent = RecentSearchStore.all()
        }
    }
}
