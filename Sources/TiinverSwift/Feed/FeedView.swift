import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Port de `Activity/ui/MainFragment.java` + `Activity/adapter/ActivityAdapter.java` — **corrigé le
/// 2026-08-15 (test Appetize réel)** : la version précédente de ce fichier construisait l'écran
/// d'accueil comme un pager plein écran façon Reels/TikTok (`TabView` pivoté, un item à la fois),
/// une hypothèse jamais vérifiée visuellement (commentaire d'origine : "non vérifié visuellement
/// faute d'environnement macOS/Xcode"). **C'était faux** : `MainFragment.java:707`
/// (`PreLoadingGridLayoutManager(..., 2, VERTICAL, false)`) confirme une vraie **grille 2 colonnes**
/// (`RecyclerView`/`GridLayoutManager`), confirmée par capture d'écran réelle fournie par
/// l'utilisateur. Le pager plein écran existe bien côté Android, mais PAS comme écran principal —
/// `MainFragment.OnAdapterItemClicked` (ligne 1108) montre qu'un tap sur une cellule de la grille
/// ouvre CE pager en plein écran, positionné sur l'item tapé (`onArticleSelected(1, arg)` avec
/// `GlobalMedias.selectedItemId`). Architecture corrigée en conséquence : grille = écran principal,
/// pager plein écran = écran de détail atteint par tap, réutilisant le code du pager existant
/// (`FeedDetailPagerView` ci-dessous, ex-corps de ce fichier avant correction).
struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showCamera = false
    @State private var showDetail = false
    @State private var detailStartIndex = 0
    @State private var pendingMedia: PublishMedia?
    @State private var showAnimems = false
    @State private var pendingTrimURL: URL?
    @State private var moreActionsPost: FeedActivity?
    @State private var reportTargetPost: FeedActivity?
    @State private var showReportReasons = false
    @State private var blockTargetPost: FeedActivity?
    @State private var commentsPost: FeedActivity?

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

    /// Port de `feed_header_layout.xml` — item `TYPE_HEADER` en position 0 du `RecyclerView`
    /// (`ActivityAdapter.HeaderViewHolder`), pas un composant décoratif mort : `contacts_suggest`
    /// (carrousel horizontal de comptes à suivre) est bien câblé (`sugestionRecycle.setAdapter(
    /// mAdapterSuggest)`, `ActivityAdapter.java:327`) — la ligne commentée du même nom dans
    /// `MainFragment.onViewCreated` (`// sugestionRecycle.setAdapter(mAdapterSuggest)`) est un
    /// résidu mort d'un champ dupliqué SANS RAPPORT, pas la preuve d'un adapter jamais branché
    /// (conclusion précédente FAUSSE, corrigée le 2026-08-17 après relecture complète de
    /// `ActivityAdapter.java`). Toujours affiché au-dessus du fil, MÊME quand celui-ci est vide,
    /// fidèle à Android où le header est un item d'adapter indépendant du contenu.
    private var homeHeader: some View {
        VStack(spacing: 12) {
            SuggestionsCarouselView()
            // Port de `feed_header_layout.xml`'s `<AdView ads:adUnitId="…5840810574"/>` — MÊME ID
            // bannière que `AdMobIdentifiers.bannerWallet` (vérifié, valeur numérique identique),
            // réutilisé tel quel plutôt que dupliqué sous un second nom.
            AdBannerView(adUnitID: AdMobIdentifiers.resolvedBanner(AdMobIdentifiers.bannerWallet))
                .frame(height: 50)
            WinFreeCoinsBannerView()
        }
        .padding(.top, 8)
    }

    var body: some View {
        Group {
            if viewModel.posts.isEmpty {
                ScrollView {
                    homeHeader
                    emptyOrStatusState
                }
                .refreshable { await viewModel.reset() }
            } else {
                ScrollView {
                    homeHeader
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(Array(viewModel.posts.enumerated()), id: \.offset) { index, post in
                            FeedGridCell(
                                post: post,
                                onLike: { viewModel.toggleLike(post) },
                                onComment: { commentsPost = post },
                                onShare: { Task { await viewModel.toggleShare(post) } },
                                onMore: { moreActionsPost = post }
                            )
                                .onTapGesture {
                                    detailStartIndex = index
                                    showDetail = true
                                }
                                .onAppear {
                                    // Port de `PreLoadingGridLayoutManager` (pagination anticipée) —
                                    // même seuil que l'ancien pager (2 items avant la fin).
                                    if index == viewModel.posts.count - 2 {
                                        Task { await viewModel.loadNextPage() }
                                    }
                                }
                        }
                    }
                    .padding(1)
                }
                .refreshable { await viewModel.reset() }
            }
        }
        .task { await viewModel.loadInitial() }
        .overlay(alignment: .bottomTrailing) {
            // Positionnement bottom-trailing standard (le layout XML exact de
            // `fragment_main.xml` n'a pas été fourni/lu) — comportement du bouton, lui, vérifié
            // contre le code réel (`requestPermission()`).
            cameraFAB
                .padding(.trailing, 20)
                .padding(.bottom, 90)
        }
        .fullScreenCover(isPresented: $showDetail) {
            FeedDetailPagerView(
                viewModel: viewModel, startIndex: detailStartIndex,
                onComment: { commentsPost = $0 }, onMore: { moreActionsPost = $0 },
                onClose: { showDetail = false }
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(
                onClose: { showCamera = false },
                onPhotoCaptured: { image in
                    // Port de `onArticleSelected(2, args)` côté `CameraActivity` → `MediaEditor`
                    // (`editor/media/MediaEditor.java`, lu en entier le 2026-08-15) → `PublishFragment`.
                    showCamera = false
                    pendingMedia = .photo(image)
                },
                onVideoRecorded: { url, _ in
                    // Port de `onArticleSelected(7, args)` — Android route vers un écran de
                    // prévisualisation avant `PublishFragment` (fragment non identifié précisément
                    // dans l'ordre de portage) ; ici la vidéo va directement à la légende/publication,
                    // même destination finale (`PublishFragment`/`activity/add`), juste sans l'étape
                    // de prévisualisation intermédiaire.
                    showCamera = false
                    pendingMedia = .video(url)
                },
                onImagePickedFromGallery: { url in
                    // Port de la branche image de `pickMedia` → `onArticleSelected(2, bundle)` →
                    // `MediaEditor` → `PublishFragment`.
                    showCamera = false
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        pendingMedia = .photo(image)
                    }
                },
                onVideoPickedFromGallery: { url in
                    // Port de la branche vidéo de `pickMedia` → `onArticleSelected(10, bundle)` →
                    // `MediaTrim` → `PublishFragment` — recadrage temporel câblé le 2026-08-16
                    // (`MediaTrimView.swift`, nouveau).
                    showCamera = false
                    pendingTrimURL = url
                },
                onOpenAnimems: {
                    // Port de `onArticleSelected(5, ...)` côté `CameraActivity` → `MemesFragment`.
                    showCamera = false
                    showAnimems = true
                }
            )
        }
        .fullScreenCover(item: $pendingMedia) { media in
            PublishComposeView(
                media: media,
                onPublished: { pendingMedia = nil; Task { await viewModel.reset() } },
                onCancel: { pendingMedia = nil }
            )
        }
        .fullScreenCover(isPresented: Binding(get: { pendingTrimURL != nil }, set: { if !$0 { pendingTrimURL = nil } })) {
            if let url = pendingTrimURL {
                MediaTrimView(
                    sourceURL: url,
                    onTrimmed: { trimmedURL in
                        pendingTrimURL = nil
                        pendingMedia = .video(trimmedURL)
                    },
                    onCancel: { pendingTrimURL = nil }
                )
            }
        }
        .fullScreenCover(isPresented: $showAnimems) {
            AnimemesEditorView(onClose: { showAnimems = false })
        }
        .sheet(item: $commentsPost) { post in
            CommentsView(activityId: post.id)
        }
        // Port de `OnclickMoreExpand` (bottom sheet à 5 items, `layout_post_action.xml`) —
        // `delete_content` TOUJOURS affiché (MÊME libellé "Supprimer" qu'on soit propriétaire ou
        // non, fidèle à l'original : `titles[0]` est un texte STATIQUE côté Android, pas conditionné
        // par la propriété — seul le COMPORTEMENT diffère, voir `FeedViewModel.deleteOwnPost` vs
        // `hideOthersPost`) ; `copy_link`/`unfollow`/`block_content`/`report_content` masqués pour
        // ses propres publications (`setIdHideContent`, `username.equals(mediaObjects.getUsername())`).
        .confirmationDialog("Actions", isPresented: Binding(get: { moreActionsPost != nil }, set: { if !$0 { moreActionsPost = nil } }), titleVisibility: .hidden) {
            if let post = moreActionsPost {
                let isOwnPost = post.actor == UserSession.shared.myId
                Button("Supprimer", role: .destructive) {
                    if isOwnPost {
                        Task { await viewModel.deleteOwnPost(post) }
                    } else {
                        viewModel.hideOthersPost(post)
                    }
                }
                if !isOwnPost {
                    Button("Copier le lien") {
                        if let token = post.token { UIPasteboard.general.string = "https://tiinver.com/post/\(token)" }
                    }
                    Button("Ne plus suivre @\(post.username ?? "")") { Task { await viewModel.unfollow(post) } }
                    Button("Bloquer @\(post.username ?? "")", role: .destructive) { blockTargetPost = post }
                    Button("Signaler le post") { reportTargetPost = post; showReportReasons = true }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
        // Port de `Report` (`R.array.report_setting_array`, 8 motifs) — sélection d'un motif avant
        // envoi (`Report.onItemClick`/`report()`).
        .confirmationDialog("Motif du signalement", isPresented: $showReportReasons, titleVisibility: .visible) {
            ForEach(Self.reportReasons, id: \.self) { reason in
                Button(reason) {
                    if let post = reportTargetPost { Task { await viewModel.report(post, reason: reason) } }
                }
            }
            Button("Annuler", role: .cancel) { reportTargetPost = nil }
        }
        // Port du dialogue de confirmation `block()` (`MyFragmentDialog`, type=5) — seule action du
        // menu "..." à demander une confirmation explicite avant envoi côté Android.
        .alert(
            "Bloquer @\(blockTargetPost?.username ?? "") ?", isPresented: Binding(get: { blockTargetPost != nil }, set: { if !$0 { blockTargetPost = nil } })
        ) {
            Button("Annuler", role: .cancel) { blockTargetPost = nil }
            Button("Bloquer", role: .destructive) {
                if let post = blockTargetPost { Task { await viewModel.block(post) } }
                blockTargetPost = nil
            }
        } message: {
            Text("Vous ne verrez plus le contenu de cette personne, et elle ne pourra plus voir le vôtre.")
        }
    }

    /// Port de `R.array.report_setting_array` (`strings.xml:516-525`).
    private static let reportReasons = [
        "Nudité", "Violence", "Harcèlement", "Fausse information",
        "Vente non autorisée", "Discours de haine", "Terrorisme", "Moins de 13 ans",
    ]

    /// État affiché tant qu'aucun post n'est chargé — distingue explicitement les 3 cas
    /// auparavant indiscernables (écran blanc dans tous les cas) : chargement en cours, erreur
    /// (réseau OU session absente/invalide — `FeedViewModel.loadNextPage()`), et flux réellement
    /// vide (chargement terminé, aucune erreur, mais 0 post reçu du serveur).
    @ViewBuilder
    private var emptyOrStatusState: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView()
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                Button("Réessayer") { Task { await viewModel.loadNextPage() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "film").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Aucune vidéo à afficher pour le moment").foregroundStyle(.secondary)
            }
            // Panneau de diagnostic AFFICHÉ À L'ÉCRAN (pas seulement console, potentiellement
            // inaccessible depuis Appetize) — demande explicite de l'utilisateur suite à plusieurs
            // tours de rapports "Home vide" non résolus par la seule lecture de code. TEMPORAIRE,
            // à retirer une fois la cause racine confirmée par un run réel.
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
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Port de `MainFragment.requestPermission()` — vérifie `Manifest.permission.CAMERA` AVANT de
    /// lancer l'écran caméra (pas seulement au moment d'utiliser `AVCaptureSession`, pour éviter
    /// d'afficher un écran caméra vide pendant que la boîte de dialogue système apparaît). Sur
    /// refus, redirige vers les réglages système comme le fait `onPermissionDenied()` côté
    /// Android (`ACTION_APPLICATION_DETAILS_SETTINGS`).
    private var cameraFAB: some View {
        Button {
            requestCameraPermissionThenPresent()
        } label: {
            Image(systemName: "camera.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.accentColor))
                .shadow(radius: 4)
        }
    }

    private func requestCameraPermissionThenPresent() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    }
                }
            }
        default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}

/// Port de `ActivityAdapter.ViewHolder`/`les_pub_affiche2.xml` — cellule de grille : vignette
/// (photo ou 1ʳᵉ image vidéo), nom d'utilisateur, compteurs like/commentaire/partage en
/// surimpression bas-gauche (`nikname`/`ShowJaimeNum`/`commentQte`, mêmes champs que
/// `onBindView`/`video`/`photo`). **Câblage réel des interactions (2026-08-16)** — un audit dédié a
/// trouvé `OnLikeClicked`/`OnclickCommentaire`/`OnclickPrtg`/`OnclickMoreExpand`
/// (`MainFragment.java:1126-1360`) entièrement absents côté iOS malgré des endpoints déjà
/// identifiables (`reaction`/`deleteactivity`/`report`, voir `FeedRepository.swift`) — ces 3
/// compteurs sont maintenant de vrais boutons, plus un bouton "..." pour le menu d'actions
/// (`layout_post_action.xml`, 5 items).
struct FeedGridCell: View {
    let post: FeedActivity
    // Défauts no-op : `HashtagFeedView.swift` (résultats de recherche) réutilise cette cellule pour
    // son seul rendu visuel, sans les interactions — périmètre Search déjà audité séparément
    // (COMPLETE), pas étendu ici pour rester ciblé sur le gap Feed identifié par l'audit.
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onMore: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(.secondarySystemBackground)
            if let thumb = post.thumbnailURL {
                CDNAsyncImage(url: thumb) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            }
            if post.isVideo {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(4)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.username.map { "\($0)" } ?? "\(post.firstname ?? "") \(post.lastname ?? "")")
                    .font(.caption).bold().foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 10) {
                    Button(action: onLike) {
                        Label("\(post.likes ?? 0)", systemImage: post.isLiked == "true" ? "heart.fill" : "heart")
                            .foregroundStyle(post.isLiked == "true" ? .red : .white)
                    }
                    Button(action: onComment) {
                        Label("\(post.comment ?? 0)", systemImage: "message.fill").foregroundStyle(.white)
                    }
                    Button(action: onShare) {
                        Label("\(post.share ?? 0)", systemImage: "paperplane.fill").foregroundStyle(.white)
                    }
                }
                .font(.caption2).labelStyle(.titleAndIcon).buttonStyle(.plain)
            }
            .padding(8)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.caption).bold()
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(4)
        }
        .aspectRatio(0.8, contentMode: .fill)
        .clipped()
    }
}

/// Écran de DÉTAIL plein écran (port de `MainFragment.OnAdapterItemClicked` →
/// `onArticleSelected(1, arg)`, l'écran qui affichait auparavant TOUT l'accueil par erreur — voir
/// commentaire de tête de fichier) — un item à la fois, défilement vertical, positionné sur
/// `startIndex` (l'item tapé dans la grille, port de `GlobalMedias.selectedItemId`).
///
/// `TabView` en style `.page` est nativement horizontal ; la rotation (page tournée -90°, conteneur
/// tourné +90°) est le contournement standard pour obtenir un défilement vertical plein écran sur
/// iOS 16 sans dépendance tierce.
struct FeedDetailPagerView: View {
    // `@StateObject(wrappedValue:)` n'utilise sa valeur initiale QU'UNE FOIS par identité de vue
    // (première création), ignorant les valeurs passées aux reconstructions suivantes de `init()`
    // (SwiftUI ré-exécute `init()` à chaque re-rendu du parent, même pour une struct `View`) — donc
    // sûr d'utiliser ici pour LES DEUX cas : (a) `FeedViewModel()` fraîchement créé (post isolé,
    // lien profond) N'EST PAS recréé à chaque re-rendu, son état (likes/etc togglés) survit ; (b)
    // le `FeedViewModel` du fil principal transmis par `FeedView` reste le MÊME objet partagé (
    // sémantique de référence), ses mutations (`@Published posts`) restent visibles des deux côtés.
    // `@ObservedObject` aurait été un piège classique ici : recréer un `FeedViewModel()` DANS
    // `init()` avec `@ObservedObject` le referait à CHAQUE reconstruction du parent, perdant l'état
    // d'interaction (likes) entre deux re-rendus.
    @StateObject private var viewModel: FeedViewModel
    let startIndex: Int
    var onComment: (FeedActivity) -> Void = { _ in }
    var onMore: (FeedActivity) -> Void = { _ in }
    let onClose: () -> Void

    @State private var currentIndex: Int
    /// Port de la navigation `nameContainer` → `UserProfile.class` (P0-C, 2026-08-17) — présenté
    /// depuis CE pager plutôt que remonté à l'appelant : Android ouvre `UserProfile` comme un
    /// nouvel écran empilé par-dessus le fullscreen, jamais en le fermant d'abord.
    @State private var openProfileUserId: String?

    /// Port ponctuel : quand ce pager est ouvert directement sur UN post isolé (résolution d'un lien
    /// profond `/post/{token}`, `DeepLinkRouter.swift`) plutôt que sur le fil complet, un
    /// `FeedViewModel` jetable suffit — les actions (like/commentaire/partage) restent
    /// fonctionnelles même hors contexte fil.
    init(posts: [FeedActivity], startIndex: Int, onClose: @escaping () -> Void) {
        let vm = FeedViewModel()
        vm.posts = posts
        _viewModel = StateObject(wrappedValue: vm)
        self.startIndex = startIndex
        self.onClose = onClose
        _currentIndex = State(initialValue: startIndex)
    }

    init(viewModel: FeedViewModel, startIndex: Int, onComment: @escaping (FeedActivity) -> Void = { _ in }, onMore: @escaping (FeedActivity) -> Void = { _ in }, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.startIndex = startIndex
        self.onComment = onComment
        self.onMore = onMore
        self.onClose = onClose
        _currentIndex = State(initialValue: startIndex)
    }

    private var posts: [FeedActivity] { viewModel.posts }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                TabView(selection: $currentIndex) {
                    ForEach(Array(posts.enumerated()), id: \.offset) { index, post in
                        Group {
                            if Self.isAdPosition(index, count: posts.count) {
                                FeedAdCell()
                            } else {
                                FeedDetailCell(
                                    post: post, isActive: index == currentIndex,
                                    onLike: { viewModel.toggleLike(post) },
                                    onComment: { onComment(post) },
                                    onShare: { Task { await viewModel.toggleShare(post) } },
                                    onMore: { onMore(post) },
                                    onOpenProfile: { if let actor = post.actor { openProfileUserId = actor } },
                                    onFollow: { Task { await viewModel.followFromDetail(post) } }
                                )
                            }
                        }
                            .frame(width: geo.size.height, height: geo.size.width)
                            .rotationEffect(.degrees(-90))
                            .tag(index)
                            .onAppear {
                                if index == posts.count - 2 { Task { await viewModel.loadNextPage() } }
                            }
                    }
                }
                .frame(width: geo.size.height, height: geo.size.width)
                .rotationEffect(.degrees(90), anchor: .topLeading)
                .offset(x: geo.size.width)
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .ignoresSafeArea()
            .onChange(of: currentIndex) { newIndex in
                preloadAround(newIndex)
            }
            .onAppear { preloadAround(currentIndex) }

            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .padding(.top, 8)
            .padding(.leading, 12)
        }
        .fullScreenCover(isPresented: Binding(get: { openProfileUserId != nil }, set: { if !$0 { openProfileUserId = nil } })) {
            if let userId = openProfileUserId {
                NavigationStack {
                    ProfileView(userId: userId, isCurrentUser: userId == UserSession.shared.myId)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Fermer") { openProfileUserId = nil }
                            }
                        }
                }
            }
        }
    }

    /// Port de `ViewPagerAdapter.isAdPosition` (`position > 0 && position < list.size() && position
    /// % ADS_ON_FEED_POST == 0`) — l'annonce REMPLACE le post à cette position plutôt que d'ajouter
    /// une page (voir note de `NativeAdLoader.adsOnFeedPost`).
    private static func isAdPosition(_ index: Int, count: Int) -> Bool {
        index > 0 && index < count && index % NativeAdLoader.adsOnFeedPost == 0
    }

    /// Port de `ExoPlayerManager.smartPreload`/`PreloadScheduler` (fenêtre `currentIndex ± 2`) —
    /// les posts non-vidéo (photos) sont ignorés, comme `"videos".equalsIgnoreCase(obj.getObject())`
    /// le fait déjà côté Android (`submitPreload`).
    private func preloadAround(_ index: Int, windowSize: Int = 2) {
        for offset in -windowSize...windowSize where offset != 0 {
            let target = index + offset
            guard posts.indices.contains(target) else { continue }
            let post = posts[target]
            guard post.isVideo, let url = post.playbackURL else { continue }
            VideoPlayerManager.shared.preload(url)
        }
    }
}

private struct FeedDetailCell: View {
    let post: FeedActivity
    let isActive: Bool
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onMore: () -> Void = {}
    /// Port de `nameContainer.setOnClickListener` (`CustomCardView.setData`) — tap sur
    /// l'avatar/le nom ouvre le profil de l'AUTEUR du post (`post.actor`), PAS le profil personnel
    /// courant, même quand ce post appartient à l'utilisateur courant (Android ne fait pas non
    /// plus cette distinction ici : il construit toujours un `User` depuis les champs du post).
    var onOpenProfile: () -> Void = {}
    /// Port du bouton `followBtn` (visible seulement pour les posts d'AUTRUI non déjà suivis,
    /// `CustomCardView.setData`: `mediaObject.getCurrentUserId().equals(mediaObject.getActor())`
    /// → masqué).
    var onFollow: () -> Void = {}

    var body: some View {
        ZStack {
            if post.isVideo, let url = post.playbackURL {
                VideoPlayer(player: VideoPlayerManager.shared.player)
                    .disabled(true) // les contrôles natifs sont désactivés — l'appui joue/pause comme le tap Android d'origine
                    .onChange(of: isActive) { active in
                        if active {
                            VideoPlayerManager.shared.playVideo(url: url)
                        }
                    }
            } else if let thumb = post.thumbnailURL {
                CDNAsyncImage(url: thumb) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
            } else {
                Color.black
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Port de `avatar`/`nameContainer` (`CustomCardView.init`/`setData`) —
                        // absents jusqu'ici du fullscreen iOS (gap confirmé par relecture du code
                        // Android réel, pas une hypothèse) : avatar rond + pseudo, zone tapable
                        // entière → profil de l'auteur.
                        Button(action: onOpenProfile) {
                            HStack(spacing: 8) {
                                CDNAsyncImage(url: post.profile.flatMap(URL.init(string:))) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Circle().fill(Color.white.opacity(0.2))
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))

                                Text(post.username.map { "@\($0)" } ?? "")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        // Port de `followBtn` — masqué sur ses propres posts (`getCurrentUserId()
                        // == getActor()`) et une fois déjà suivi (`isFollowed()`), jamais de
                        // bascule "ne plus suivre" depuis ce bouton précis (fidèle à Android).
                        if post.actor != UserSession.shared.myId, post.isFollowed != true {
                            Button(action: onFollow) {
                                Text("Suivre")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(Color.white, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                        }

                        if let message = post.message, !message.isEmpty {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    // Port de `OnLikeClicked`/`OnclickCommentaire`/`OnclickPrtg`/`OnclickMoreExpand`
                    // — rail d'actions verticale (même 4 interactions que la cellule de grille,
                    // voir `FeedGridCell`), emplacement standard pour un pager plein écran.
                    actionRail
                }
                .padding()
            }
        }
        .background(Color.black)
        .clipped()
    }

    private var actionRail: some View {
        VStack(spacing: 20) {
            actionButton(icon: post.isLiked == "true" ? "heart.fill" : "heart", tint: post.isLiked == "true" ? .red : .white, count: post.likes ?? 0, action: onLike)
            actionButton(icon: "message.fill", tint: .white, count: post.comment ?? 0, action: onComment)
            actionButton(icon: "paperplane.fill", tint: .white, count: post.share ?? 0, action: onShare)
            Button(action: onMore) {
                Image(systemName: "ellipsis").font(.title2).foregroundStyle(.white)
            }
        }
    }

    private func actionButton(icon: String, tint: Color, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                Text("\(count)").font(.caption2).foregroundStyle(.white)
            }
        }
    }
}

/// Port de `AdsViewHolder`/`CustomAdsView` — page annonce native plein écran, une instance de
/// `NativeAdLoader` par position d'annonce (pas un pool partagé, voir note de tête de fichier
/// `AdMobManager.swift` sur la portée réduite de ce portage).
private struct FeedAdCell: View {
    @StateObject private var loader = NativeAdLoader()

    var body: some View {
        ZStack {
            Color.black
            if let nativeAd = loader.nativeAd {
                NativeAdContentView(nativeAd: nativeAd)
                    .padding(.horizontal, 24)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear { loader.load() }
    }
}
