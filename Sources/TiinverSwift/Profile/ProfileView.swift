import SwiftUI

/// Port consolidé de `UserProfile.java` (1198, sections chrome Android non pertinentes ignorées —
/// immersion plein écran, gestion manuelle barre de statut) + `AddPerfilFoto.java` (1164, sections
/// upload photo NON portées, voir avertissement `ProfileRepository.uploadProfilePicture`) — voir
/// `ProfileViewModel.swift` pour la justification de la fusion en un seul écran.
struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var showBlockConfirm = false
    @State private var showEditProfile = false
    @State private var showReport = false

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    init(userId: String, isCurrentUser: Bool) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(userId: userId, isCurrentUser: isCurrentUser))
    }

    /// Port du point d'entrée `navigation_profile` (`HomeShellView`, bouton barre du haut) —
    /// lance `AddPerfilFoto` (SON PROPRE profil) côté Android, jamais `UserProfile` (profil
    /// d'autrui) depuis ce bouton précis.
    init() {
        self.init(userId: UserSession.shared.myId ?? "", isCurrentUser: true)
    }

    var body: some View {
        ScrollView {
            header
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.posts, id: \.id) { post in
                    postCell(post)
                        .onAppear {
                            if post.id == viewModel.posts.last?.id { Task { await viewModel.loadMorePosts() } }
                        }
                }
            }
        }
        .navigationTitle(viewModel.profile.map { "@\($0.username ?? "")" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            await viewModel.loadProfile()
            await viewModel.loadInitialPosts()
        }
        .confirmationDialog(
            viewModel.isBlocked ? "Débloquer cet utilisateur ?" : "Bloquer cet utilisateur ?", // R.string.unblock / block_info
            isPresented: $showBlockConfirm, titleVisibility: .visible
        ) {
            Button(viewModel.isBlocked ? "Débloquer" : "Bloquer", role: .destructive) { Task { await viewModel.toggleBlock() } }
        }
        .sheet(isPresented: $showEditProfile) { EditProfileView() }
        .navigationDestination(isPresented: $showReport) {
            ReportView(targetId: viewModel.userId, username: viewModel.profile?.username ?? "", reportType: "user")
        }
    }

    @ViewBuilder
    private var header: some View {
        if let profile = viewModel.profile {
            VStack(spacing: 8) {
                AsyncImage(url: URL(string: profile.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    Color(.secondarySystemBackground)
                }
                .frame(width: 84, height: 84).clipShape(Circle())

                HStack(spacing: 4) {
                    Text(profile.firstname ?? "").font(.headline)
                    Text(profile.displayLastname).font(.headline)
                    if profile.certified == "1" { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue) }
                }
                if let warning = profile.warning, !warning.isEmpty {
                    Text(warning).font(.caption).foregroundStyle(.orange) // R.id.warning
                }

                HStack(spacing: 32) {
                    NavigationLink { FollowListView(userId: viewModel.userId, type: .followers) } label: { // R.id.follower
                        stat(profile.followers ?? "0", "Abonnés")
                    }
                    NavigationLink { FollowListView(userId: viewModel.userId, type: .following) } label: { // R.id.following
                        stat(profile.following ?? "0", "Abonnements")
                    }
                }
                .buttonStyle(.plain)

                if let bio = profile.biography, !bio.isEmpty { Text(bio).font(.subheadline).multilineTextAlignment(.center) }
                if let link = profile.link, !link.isEmpty {
                    Link(link, destination: URL(string: link.hasPrefix("http") ? link : "https://\(link)") ?? URL(string: "https://tiinver.com")!)
                        .font(.caption)
                }

                actionRow
            }
            .padding()
        } else if viewModel.isLoadingProfile {
            ProgressView().padding()
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if viewModel.isCurrentUser {
            HStack {
                Button("Modifier le profil") { showEditProfile = true } // R.id.EditProfileBut
                NavigationLink("Portefeuille") { WalletView() } // R.id.container_wallet
            }
            .buttonStyle(.bordered)
        } else {
            HStack {
                Button(viewModel.isFollowing ? "Abonné" : "Suivre") { Task { await viewModel.follow() } } // R.id.butSeguir
                    .disabled(viewModel.isFollowing)
                if let target = messageTarget {
                    NavigationLink("Message") { ChatView(target: target) } // R.id.message, port de `openConversation`
                }
            }
            .buttonStyle(.bordered)
        }
    }

    /// Port de `openConversation(User)` — construit le `RosterModel` avec les mêmes champs que
    /// l'original (`type`/`nikname`/`username`/`to`/`from`/`currentUsername`/`currentUserId`/
    /// `userId`/`title`/`subTitle`/`profile`), visible uniquement pour les profils publics
    /// (`metas.getType().equals(PUBLIC)`, `message.setVisibility(VISIBLE)` conditionnel).
    private var messageTarget: RosterModel? {
        guard let profile = viewModel.profile, profile.type == "public", let username = profile.username else { return nil }
        var target = RosterModel()
        target.type = ChatType.chat.wireValue
        target.nikname = "\(profile.firstname ?? "") \(profile.displayLastname)"
        target.username = username
        target.to = username
        target.from = UserSession.shared.username
        target.currentUsername = UserSession.shared.username
        target.currentUserId = UserSession.shared.myId
        target.userId = viewModel.userId
        target.title = target.nikname
        target.subTitle = username
        target.profile = profile.profile
        return target
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func postCell(_ post: FeedActivity) -> some View {
        ZStack(alignment: .topTrailing) {
            if let thumb = post.thumbnailURL {
                AsyncImage(url: thumb) { $0.resizable().aspectRatio(1, contentMode: .fill).clipped() } placeholder: {
                    Color(.secondarySystemBackground).aspectRatio(1, contentMode: .fill)
                }
            } else {
                Color(.secondarySystemBackground).aspectRatio(1, contentMode: .fill)
            }
            if post.isVideo { Image(systemName: "play.fill").foregroundStyle(.white).padding(4) }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isCurrentUser {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") } // R.id.action_setting
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Signaler", systemImage: "flag") { showReport = true } // R.id.report
                    Button(viewModel.isBlocked ? "Débloquer" : "Bloquer", systemImage: "hand.raised", role: .destructive) {
                        showBlockConfirm = true
                    } // R.id.block
                } label: { Image(systemName: "ellipsis.circle") } // R.id.moreShow
            }
        }
    }
}
