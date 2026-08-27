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
    /// Port de l'aperçu optimiste `AddPerfilFoto.onFileReady` (V5-F-074) — image locale affichée
    /// IMMÉDIATEMENT au choix, avant même le début de l'upload réseau.
    @State private var pendingAvatarImage: UIImage?
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
            postsGridFooter
        }
        .navigationTitle(viewModel.profile.map { "@\($0.username ?? "")" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            await viewModel.loadProfile()
            await viewModel.loadInitialPosts()
        }
        .fullScreenCover(isPresented: $showDetail) {
            // Port de `ProfileFeedFragment.OnclickMoreExpand` — SEUL menu Android à câbler
            // `R.id.download` (V4-F-007, voir `FeedMediaDownloader.swift`).
            // notifiesAuthor: true — port de `ProfileFeedFragment.notifyUser`, câblé sur les 3 mêmes
            // interactions (like/commentaire/partage) que Feed (V4-F-030).
            FeedDetailPagerView(posts: viewModel.posts, startIndex: detailStartIndex, includesDownload: true, notifiesAuthor: true, onClose: { showDetail = false })
        }
        .confirmationDialog(
            viewModel.isBlocked ? "Débloquer cet utilisateur ?" : "Bloquer cet utilisateur ?", // R.string.unblock / block_info
            isPresented: $showBlockConfirm, titleVisibility: .visible
        ) {
            Button(viewModel.isBlocked ? "Débloquer" : "Bloquer", role: .destructive) { Task { await viewModel.toggleBlock() } }
        }
        // Port du `Toast` `errorLoad` d'échec de `toggleBlock()` (V5-F-065, voir `ProfileViewModel.toggleBlock`).
        .alert("Échec du blocage", isPresented: Binding(get: { viewModel.blockError != nil }, set: { if !$0 { viewModel.blockError = nil } })) {
            Button("OK", role: .cancel) { viewModel.blockError = nil }
        } message: {
            Text(viewModel.blockError ?? "")
        }
        .sheet(isPresented: $showEditProfile) { EditProfileView() }
        .navigationDestination(isPresented: $showReport) {
            ReportView(targetId: viewModel.userId, username: viewModel.profile?.username ?? "", reportType: "user")
        }
        .onChange(of: avatarPickerItem) { item in
            guard let item else { return }
            Task {
                guard let raw = try? await item.loadTransferable(type: Data.self), let uiImage = UIImage(data: raw),
                      let jpegData = uiImage.jpegData(compressionQuality: 0.9)
                else { return }
                pendingAvatarImage = uiImage
                await viewModel.uploadProfilePicture(imageData: jpegData)
                pendingAvatarImage = nil
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

            // **Ajouté (V4-F-013, 2026-08-24)** — port de `ProfileAdapter2.HeaderViewHolder.
            // bindView` (lignes 257-303) : `userStatus`/`hasProgram`/`programs` étaient déjà
            // décodés (`User.swift`) mais jamais rendus ici.
            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.red.opacity(0.85), in: Capsule()) // R.id.status
            }
            if viewModel.profile?.hasProgram == true, let programs = viewModel.profile?.programs, !programs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(programs.enumerated()), id: \.offset) { _, program in
                        programBadge(program) // R.id.programBadge
                    }
                }
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

    /// Port de `ProfileAdapter2.HeaderViewHolder.bindView` (lignes 285-301) : `restricted`/
    /// `banned`/`warning`, textes EXACTS repris de `values-fr/strings.xml`
    /// (`restricted_message`/`banned_message`/`warning_message`).
    private var statusMessage: String? {
        switch viewModel.profile?.userStatus {
        case "restricted": return "Votre compte est restreint : certaines fonctionnalités sont limitées."
        case "banned": return "Votre compte est suspendu définitivement."
        case "warning": return "Attention : Veuillez respecter nos conditions d'utilisation."
        default: return nil
        }
    }

    /// Port de `ProgramView.createBadge` (`view/ProgramView.java:76-158`) — icône/couleur/libellé
    /// par type de programme (`premium`/`ambassador`/`creator`/`partner`), couleurs reprises de
    /// `values/colors.xml`. `premium` affiche en plus le niveau (`label + " · " + level`).
    @ViewBuilder
    private func programBadge(_ program: User.Program) -> some View {
        let attributes = Self.programBadgeAttributes(program)
        HStack(spacing: 4) {
            Image(systemName: attributes.icon)
            Text(attributes.text)
        }
        .font(.caption2.bold())
        .foregroundStyle(attributes.fg)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(attributes.bg, in: Capsule())
    }

    private static func programBadgeAttributes(_ program: User.Program) -> (icon: String, fg: Color, bg: Color, text: String) {
        let icon: String
        let fg: Color
        let bg: Color
        let label: String
        switch program.program {
        case "premium":
            icon = "crown.fill"
            fg = Color(red: 0x85 / 255, green: 0x64 / 255, blue: 0x04 / 255)
            bg = Color(red: 0xFF / 255, green: 0xF3 / 255, blue: 0xCD / 255)
            label = "premium"
        case "ambassador":
            icon = "megaphone.fill"
            fg = Color(red: 0x15 / 255, green: 0x65 / 255, blue: 0xC0 / 255)
            bg = Color(red: 0xE3 / 255, green: 0xF2 / 255, blue: 0xFD / 255)
            label = "ambassadeur"
        case "creator":
            icon = "paintbrush.fill"
            fg = Color(red: 0x5E / 255, green: 0x35 / 255, blue: 0xB1 / 255)
            bg = Color(red: 0xED / 255, green: 0xE7 / 255, blue: 0xF6 / 255)
            label = "créateur"
        case "partner":
            icon = "hand.raised.fill"
            fg = Color(red: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255)
            bg = Color(red: 0xE8 / 255, green: 0xF5 / 255, blue: 0xE9 / 255)
            label = "partenaire"
        default:
            icon = "star.fill"
            fg = Color.secondary
            bg = Color.secondary.opacity(0.15)
            label = program.program ?? ""
        }
        if program.program == "premium", let level = program.level {
            return (icon, fg, bg, "\(label) · \(level.capitalized)")
        }
        return (icon, fg, bg, label)
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
    /// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-074, Phase B P2)** — Android
    /// (`AddPerfilFoto.onFileReady`) affiche le bitmap local recadré IMMÉDIATEMENT, avant même le
    /// début de l'upload réseau. `CDNAsyncImage` ne réagit qu'à un changement d'URL (`.task(id:
    /// url)`) — tant que l'ancien avatar CDN reste affiché (cas de la quasi-totalité des
    /// utilisateurs), le placeholder `isUploadingPhoto` restait inatteignable : aucun retour visuel
    /// pendant tout l'upload. `pendingAvatarImage` (peuplé par `.onChange(of: avatarPickerItem)`
    /// ci-dessus) prend maintenant la priorité d'affichage tant que non-nil.
    /// **Corrigé le 2026-08-27 (échec CI, run 33027551088)** — logique conditionnelle
    /// (`pendingAvatarImage` présent ou non) EXTRAITE dans une fonction ordinaire ci-dessous : un
    /// corps `@ViewBuilder` applique sa transformation de result builder à CHAQUE instruction, y
    /// compris une affectation `image = ...` dans une branche `if/else` — Swift interprète alors
    /// cette affectation elle-même comme une "expression de vue" via `buildExpression`, qui échoue
    /// puisqu'une affectation ne produit aucune `View` (`() `). Confirmé par le compilateur réel en
    /// CI (`error: 'buildExpression' is unavailable: this expression does not conform to 'View'`,
    /// lignes 354/356) — jamais détectable par relecture seule dans cet environnement sans Xcode.
    /// Un simple `let framed = avatarImage(profile)...` (liaison SANS branchement conditionnel
    /// direct dans le corps `@ViewBuilder`) est en revanche pleinement supporté.
    private func avatarImage(_ profile: User?) -> AnyView {
        if let pendingAvatarImage {
            return AnyView(Image(uiImage: pendingAvatarImage).resizable().aspectRatio(contentMode: .fill))
        }
        return AnyView(
            CDNAsyncImage(url: URL(string: profile?.profile ?? ""), targetSize: CGSize(width: 84, height: 84)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
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
        )
    }

    @ViewBuilder
    private func avatar(_ profile: User?) -> some View {
        let framed = avatarImage(profile)
            .frame(width: 84, height: 84).clipShape(Circle())
        // Port de `ProfileAdapter2.java:281-285` (état `profilepicturestateloading==3`, icône
        // d'erreur superposée) — V4-F-009 : `photoUploadFailed` n'était lu nulle part côté vue
        // avant ce correctif. Coin HAUT-droit (pas bas-droit, déjà occupé par le bouton caméra
        // ci-dessous) pour éviter toute collision visuelle des deux superpositions.
        .overlay(alignment: .topTrailing) {
            if viewModel.photoUploadFailed {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .red)
                    .background(Circle().fill(.white))
            }
        }

        if viewModel.isCurrentUser {
            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                framed.overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .blue)
                }
            }
            .disabled(viewModel.isUploadingPhoto)
        } else {
            framed
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
                // V4-F-073 — tuile de grille 3 colonnes (`ProfileView.columns`, spacing 2).
                CDNAsyncImage(url: thumb, targetSize: CGSize(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width / 3)) { $0.resizable().aspectRatio(1, contentMode: .fill).clipped() } placeholder: {
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

    /// Pied de la grille paginée — port de `ProfileAdapter2.FooterViewHolder` (V4-F-010) :
    /// shimmer/vide pendant le chargement (`isLoadingPosts`), icône+texte+bouton "Réessayer" sur
    /// échec de pagination (`postsLoadError`, type 2 Android), rien une fois la page chargée avec
    /// succès (type 1). L'état "aucune publication" (grille vide, chargement terminé, pas d'erreur)
    /// n'a PAS d'équivalent explicite trouvé côté Android (aucune vue "empty" dans
    /// `ProfileAdapter2`/`UserProfile`/`AddPerfilFoto`) — ajouté ici comme simple confort UX pour ne
    /// pas laisser un espace blanc inexpliqué, PAS présenté comme un port de parité Android.
    @ViewBuilder
    private var postsGridFooter: some View {
        if viewModel.isLoadingPosts {
            ProgressView().padding()
        } else if viewModel.postsLoadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                Text("Impossible de charger les publications.").font(.caption).foregroundStyle(.secondary)
                Button("Réessayer") { Task { await viewModel.loadMorePosts() } }
                    .font(.caption.bold())
            }
            .padding()
        } else if viewModel.posts.isEmpty, !viewModel.isLoadingProfile {
            Text("Aucune publication").font(.caption).foregroundStyle(.secondary).padding()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isCurrentUser {
            // **Ajouté (V4-F-015, 2026-08-24)** — port de `AddPerfilFoto.shareProfile()`
            // (lignes 413-419) : texte + lien EXACTS repris de `values-fr/strings.xml`
            // (`profile_link_share_msg`).
            if let username = viewModel.profile?.username, !username.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: "Découvrez mon profil sur Tiinver :\nhttps://tiinver.com/user/\(username)") {
                        Image(systemName: "square.and.arrow.up")
                    } // R.id.action_share
                }
            }
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
