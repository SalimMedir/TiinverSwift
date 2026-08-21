import PhotosUI
import SwiftUI

/// Port consolidé de `UserProfile.java` (1198, sections chrome Android non pertinentes ignorées —
/// immersion plein écran, gestion manuelle barre de statut) + `AddPerfilFoto.java` (1164) — voir
/// `ProfileViewModel.swift` pour la justification de la fusion en un seul écran. Upload de la
/// photo de profil porté le 2026-08-15 (GAP-004) via `PhotosPicker` natif plutôt que le sélecteur
/// custom + `CroperView` Android — écart d'architecture assumé (voir `MIGRATION_AUDIT.md` GAP-004) :
/// Android recadre AVANT l'envoi, ici l'image est envoyée telle quelle (re-encodée en JPEG),
/// le serveur affiche déjà l'avatar en cercle recadré côté client de toute façon.
struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var showBlockConfirm = false
    @State private var showEditProfile = false
    @State private var showReport = false
    @State private var avatarPickerItem: PhotosPickerItem?
    /// **CAUSE RACINE RÉELLE (P0-D, 2026-08-17, confirmée par relecture du code — pas une
    /// hypothèse)** : la grille de posts n'avait ABSOLUMENT AUCUN geste de tap câblé (`postCell`
    /// était rendu nu, sans `.onTapGesture` ni navigation), contrairement à `FeedView`'s
    /// `FeedGridCell` qui, elle, ouvrait déjà `FeedDetailPagerView`. Réutilise CE MÊME pager
    /// plein écran (déjà reconstruit avec parité Android en P0-C) plutôt que d'en dupliquer un
    /// second — fidèle à la simplification déjà assumée par ce fichier (`UserProfile`+
    /// `AddPerfilFoto` fusionnés), Android duplique `ProfileFeedFragment`/`FeedFragment` (code
    /// quasi identique), iOS ne le fait pas.
    @State private var showDetail = false
    @State private var detailStartIndex = 0

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
                ForEach(Array(viewModel.posts.enumerated()), id: \.element.id) { index, post in
                    postCell(post)
                        .onTapGesture {
                            detailStartIndex = index
                            showDetail = true
                        }
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
        .fullScreenCover(isPresented: $showDetail) {
            FeedDetailPagerView(posts: viewModel.posts, startIndex: detailStartIndex, onClose: { showDetail = false })
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
        .onChange(of: avatarPickerItem) { item in
            guard let item else { return }
            Task {
                guard let raw = try? await item.loadTransferable(type: Data.self),
                      let jpegData = UIImage(data: raw)?.jpegData(compressionQuality: 0.9)
                else { return }
                await viewModel.uploadProfilePicture(imageData: jpegData)
                avatarPickerItem = nil
            }
        }
    }

    /// **Correction UX (2026-08-16, retour explicite de l'utilisateur)** : cet écran affichait
    /// AUPARAVANT soit le profil complet (données présentes), soit UNIQUEMENT un message d'erreur
    /// (données absentes) — les deux étaient mutuellement exclusifs (`if let profile = ... else
    /// if error ... else ...`), ce qui masquait TOUT le chrome de l'écran (avatar, abonnés,
    /// boutons "MODIFIER LE PROFIL"/portefeuille/monétisation) dès qu'une erreur survenait, y
    /// compris une simple absence de session. Android affiche TOUJOURS la structure complète de
    /// l'écran avec des valeurs vides/placeholder tant que les données n'ont pas encore chargé —
    /// reproduit ici : le chrome se construit désormais à partir de `viewModel.profile`
    /// (`Optional`) directement, avec des replis explicites (`?? "0"`, avatar en cercle vide),
    /// PLUTÔT que de conditionner l'affichage ENTIER de l'écran sur sa présence. L'erreur/le
    /// diagnostic s'affichent maintenant comme un bandeau EN PLUS de ce chrome, jamais à sa place.
    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            avatar(viewModel.profile)

            HStack(spacing: 4) {
                Text(viewModel.profile?.firstname ?? "").font(.headline)
                Text(viewModel.profile?.displayLastname ?? " ").font(.headline)
                if viewModel.profile?.certified == "1" { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue) }
            }
            if let warning = viewModel.profile?.warning, !warning.isEmpty {
                Text(warning).font(.caption).foregroundStyle(.orange) // R.id.warning
            }

            HStack(spacing: 32) {
                NavigationLink { FollowListView(userId: viewModel.userId, type: .followers) } label: { // R.id.follower
                    stat(viewModel.profile?.followers ?? "0", "Abonnés")
                }
                NavigationLink { FollowListView(userId: viewModel.userId, type: .following) } label: { // R.id.following
                    stat(viewModel.profile?.following ?? "0", "Abonnements")
                }
            }
            .buttonStyle(.plain)

            if let bio = viewModel.profile?.biography, !bio.isEmpty { Text(bio).font(.subheadline).multilineTextAlignment(.center) }
            if let link = viewModel.profile?.link, !link.isEmpty {
                // **Corrigé (V3-F-063)** — `UserProfile.java:454-477` (`link_container.
                // setOnClickListener`) : Android teste `uri.getHost().contains("tiinver.com")` AVANT
                // d'ouvrir le lien — un lien vers le propre domaine Tiinver route en INTERNE
                // (`ShareActivity`, le même résolveur de deep link que `DeepLinkRouter.swift` porte
                // déjà côté iOS), SEULS les liens externes ouvrent le navigateur système
                // (`ACTION_VIEW`). `Link(...)` (SwiftUI) ouvrait TOUJOURS en externe, quel que soit
                // l'hôte — un lien de bio vers un autre profil/post Tiinver quittait l'app au lieu
                // d'y router directement.
                Button(link) { Self.openBioLink(link) }
                    .font(.caption)
            }

            actionRow

            if viewModel.isLoadingProfile {
                ProgressView().padding(.top, 4)
            } else if let errorMessage = viewModel.errorMessage {
                // Port du même correctif que `FeedView.emptyOrStatusState` — rend visible ce qui
                // était auparavant un écran blanc indiscernable d'un profil vide (voir
                // `ProfileViewModel.errorMessage`). Bandeau EN PLUS du chrome ci-dessus, plus à sa
                // place — voir note de tête de `header`.
                VStack(spacing: 12) {
                    Text(errorMessage).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Réessayer") { Task { await viewModel.loadProfile() } }
                        .buttonStyle(.borderedProminent)
                    diagnosticsPanel
                }
                .padding(.top, 4)
            }
        }
        .padding()
    }

    /// Panneau de diagnostic AFFICHÉ À L'ÉCRAN (pas seulement console) — voir
    /// `ProfileViewModel.diagnostics`, même motif que `FeedView`.
    @ViewBuilder
    private var diagnosticsPanel: some View {
        if !viewModel.diagnostics.isEmpty {
            ScrollView {
                Text(viewModel.diagnostics)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)
            .padding(8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if viewModel.isCurrentUser {
            // Parité UI avec Android corrigée par capture d'écran (2026-08-16) : 2 boutons ronds
            // "portefeuille"/"monétisation" côte à côte, PUIS un large bouton "MODIFIER LE PROFIL"
            // en dessous — pas 2 boutons texte côte à côte comme la version précédente de ce
            // fichier. **Corrigé le 2026-08-17** (retour explicite de l'utilisateur : "monétisation
            // m'amène dans la même page que wallet") : `wallet/MonetizationActivity.java` EST bien
            // un écran Android séparé (117 lignes, lu en entier) — l'affirmation précédente
            // "aucun écran dédié identifié" était fausse, jamais revérifiée après la première
            // passe. Voir `MonetizationView.swift`, nouveau.
            VStack(spacing: 12) {
                HStack(spacing: 32) {
                    NavigationLink { WalletView() } label: { // R.id.container_wallet
                        roundIconButton(systemImage: "creditcard.fill", label: "portefeuille", tint: .blue)
                    }
                    NavigationLink { MonetizationView() } label: {
                        roundIconButton(systemImage: "dollarsign.circle.fill", label: "monétisation", tint: .green)
                    }
                }
                Button {
                    showEditProfile = true // R.id.EditProfileBut
                } label: {
                    Text("MODIFIER LE PROFIL").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
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

    /// Port de `AddPerfilFoto` (bouton édition avatar, SON PROPRE profil uniquement — l'avatar
    /// d'autrui, `UserProfile.java`, n'a pas ce bouton) — `PhotosPicker` enveloppe l'avatar
    /// directement plutôt qu'un bouton "crayon" séparé superposé, comportement équivalent
    /// (un seul point de tap pour changer la photo) avec moins de vues.
    /// `profile: User?` (2026-08-16) — voir note de tête de `header` : l'avatar doit rester visible
    /// (cercle placeholder gris + icône silhouette, comme Android affiche un avatar générique tant
    /// que l'image réelle n'a pas chargé) même quand `viewModel.profile` est encore `nil`.
    @ViewBuilder
    private func avatar(_ profile: User?) -> some View {
        let image = CDNAsyncImage(url: URL(string: profile?.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
            if viewModel.isUploadingPhoto {
                ProgressView()
            } else {
                Color(.secondarySystemBackground)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 84, height: 84).clipShape(Circle())

        if viewModel.isCurrentUser {
            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                image.overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .blue)
                }
            }
            .disabled(viewModel.isUploadingPhoto)
        } else {
            image
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Port de `UserProfile.java:454-477` (V3-F-063) — voir avertissement au site d'appel. Ajoute
    /// `https://` si absent (fidèle à Android : `!link.startsWith("http://") &&
    /// !link.startsWith("https://")`) AVANT de tester l'hôte, sinon `URL(string:)` échouerait sur
    /// un lien sans schéma et le test d'hôte tomberait toujours en externe.
    @MainActor
    private static func openBioLink(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let withScheme = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme) else { return }
        if let host = url.host, host.contains("tiinver.com") {
            DeepLinkRouter.handle(url)
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func roundIconButton(systemImage: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tint))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func postCell(_ post: FeedActivity) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb = post.thumbnailURL {
                CDNAsyncImage(url: thumb) { $0.resizable().aspectRatio(1, contentMode: .fill).clipped() } placeholder: {
                    Color(.secondarySystemBackground).aspectRatio(1, contentMode: .fill)
                }
            } else {
                Color(.secondarySystemBackground).aspectRatio(1, contentMode: .fill)
            }
            if post.isVideo {
                Image(systemName: "play.fill")
                    .foregroundStyle(.white)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            // Parité UI avec Android (capture d'écran 2026-08-16) — compteur de vues en surimpression
            // bas-gauche de chaque vignette, icône œil, `post.views` déjà porté mais jamais affiché.
            Label("\(post.views ?? 0)", systemImage: "eye.fill")
                .font(.caption2).foregroundStyle(.white)
                .padding(4)
                .shadow(radius: 2)
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
