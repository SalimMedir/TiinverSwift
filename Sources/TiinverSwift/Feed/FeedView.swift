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

/// Port de `R.array.report_setting_array` (`strings.xml:516-525`) — partagé par `FeedView` (menu
/// "..." de la grille) et `FeedDetailPagerView` (menu "..." du plein écran), deux implémentations
/// Android SÉPARÉES (`MainFragment.OnclickMoreExpand` / `ProfileFeedFragment`+`FullScreenMedia`+
/// `HashtagProfile.OnclickMoreExpand`) qui utilisent néanmoins la MÊME liste de motifs.
///
/// Accès interne (pas `private`) — **corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md
/// V4-F-021, Phase B P1)** : réutilisée par `ReportView` (seul point d'entrée réel du
/// signalement DEPUIS Profile), qui avait sa propre liste de 6 motifs inventés
/// ("Spam"/"Autre" absents d'Android, 4 vrais motifs manquants) au lieu de cette liste déjà
/// correcte — même motif de partage de constante que `UploadProgressDelegate` (V4-F-064) plutôt
/// que dupliquer une 2ᵉ liste divergente.
let feedReportReasons = [
    "Nudité", "Violence", "Harcèlement", "Fausse information",
    "Vente non autorisée", "Discours de haine", "Terrorisme", "Moins de 13 ans",
]

/// Port de `ViewPagerAdapter.isAdPosition` (`position > 0 && position < list.size() && position
/// % ADS_ON_FEED_POST == 0`) — l'annonce REMPLACE le post à cette position plutôt que d'ajouter
/// un élément supplémentaire (voir note de `NativeAdLoader.adsOnFeedPost`). Accès fichier (pas
/// `private` d'une seule struct) — **partagé depuis le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md
/// V5-F-008, Phase B P2)** entre `FeedDetailPagerView` (pager plein écran, déjà câblé) et
/// `FeedView` (grille Home, jusque-là dépourvue de toute publicité, voir `feedGridSegments`
/// ci-dessous) : `ActivityAdapter.isAdPosition`/`ViewPagerAdapter.isAdPosition` utilisent la MÊME
/// constante `ADS_ON_FEED_POST=7` côté Android — pas une coïncidence à dupliquer en 2 formules
/// pouvant diverger.
func isAdPosition(_ index: Int, count: Int) -> Bool {
    index > 0 && index < count && index % NativeAdLoader.adsOnFeedPost == 0
}

struct FeedView: View {
    // Port de `MainFragment.OnLikeClicked`/`OnclickCommentaire`/`OnclickPrtg` → `notifyUser` —
    // câblé pour ce contexte (V4-F-030).
    @StateObject private var viewModel = FeedViewModel(notifiesAuthorOnInteraction: true)
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
    /// Port de `promoteBtn` (`view/CustomCardView.java:373-381`, visible UNIQUEMENT pour ses
    /// propres posts, `mediaObject.getActor().equals(mediaObject.getCurrentUserId())`) — bouton
    /// dédié côté Android (rail du plein écran), regroupé ici dans le menu "..." existant plutôt
    /// qu'une icône supplémentaire dédiée (rail déjà dense à 4 boutons + "...", même principe de
    /// simplification de portage que d'autres réagencements déjà documentés dans ce fichier).
    @State private var boostTargetPost: FeedActivity?
    /// Port de `statisticBtn` (`view/CustomCardView.java:238-243`, MÊME garde que `promoteBtn`
    /// ci-dessus, propres posts uniquement) — voir `StatisticsView.swift`, 2026-08-18 P2.
    @State private var statsTargetPost: FeedActivity?

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

    /// Port de `ActivityAdapter.isAdPosition`/`getItemViewType`→`TYPE_ITEM_ADS` — **ajouté le
    /// 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-008, Phase B P2)**. Vérifié directement :
    /// `ActivityAdapter.java:158-161` (`isAdPosition`, `position % ADS_ON_FEED_POST == 0`) et
    /// `:179-181` (`getItemCount() = mediaObjects.size() + 2` — l'annonce REMPLACE un post plutôt
    /// que d'agrandir la liste, contrairement à une simple insertion) ; `MainFragment.
    /// java:709-723` (`SpanSizeLookup` force `span=2`, c'est-à-dire une ligne PLEINE LARGEUR, aux
    /// positions publicitaires). Découpe `viewModel.posts` en tronçons consécutifs de posts,
    /// séparés par `.ad` à chaque `isAdPosition` — le `body` rend chaque tronçon dans son propre
    /// `LazyVGrid` (2 colonnes) et chaque `.ad` comme `FeedGridAdCell()` pleine largeur entre les
    /// deux, reproduisant le même effet visuel que le `span=2` Android (qui force lui aussi un
    /// retour à la ligne) sans avoir besoin d'un span par-item que `LazyVGrid` n'expose pas.
    private var feedGridSegments: [FeedGridSegment] {
        var segments: [FeedGridSegment] = []
        var current: [FeedGridItem] = []
        for (index, post) in viewModel.posts.enumerated() {
            if isAdPosition(index, count: viewModel.posts.count) {
                if !current.isEmpty {
                    segments.append(.posts(current))
                    current = []
                }
                segments.append(.ad)
            }
            current.append(FeedGridItem(index: index, post: post))
        }
        if !current.isEmpty { segments.append(.posts(current)) }
        return segments
    }

    /// Port de `ActivityAdapter.FooterViewHolder` (`:259-291`, `case 2` = icône erreur + texte +
    /// bouton "Réessayer" visible) — **ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md
    /// V5-F-054, Phase B P2)**. Même motif que `ProfileView.postsGridFooter`/`ProfileViewModel.
    /// postsLoadError` (déjà porté pour la grille Profil, jamais reproduit ici) : avant ce
    /// correctif, `viewModel.errorMessage` était bien renseigné par `fetchPage()` sur un échec de
    /// pagination, mais `FeedView` ne le lisait QUE dans `emptyOrStatusState`, elle-même
    /// conditionnée à `posts.isEmpty` — dès qu'un post était déjà affiché (le cas réel de toute
    /// pagination en cours de scroll), un échec réseau arrêtait silencieusement la croissance du
    /// flux sans aucune indication ni moyen de relancer manuellement. Réutilise `errorMessage`
    /// directement (pas de nouveau flag dupliqué : `fetchPage()` le remet déjà à `nil` avant
    /// chaque tentative, exactement le même cycle que `postsLoadError`).
    @ViewBuilder
    private var feedGridFooter: some View {
        if viewModel.isLoading {
            ProgressView().padding()
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                Button("Réessayer") { Task { await viewModel.loadNextPage() } }
                    .font(.caption.bold())
            }
            .padding()
        }
    }

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
                    // **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-008, Phase B P2)**
                    // — voir doc de `feedGridSegments` : plusieurs `LazyVGrid` consécutifs
                    // (un par tronçon de posts) séparés par `FeedGridAdCell()` aux positions
                    // publicitaires, plutôt qu'un unique `LazyVGrid` (qui ne peut pas faire
                    // occuper 2 colonnes à un seul item).
                    VStack(spacing: 1) {
                        ForEach(Array(feedGridSegments.enumerated()), id: \.offset) { _, segment in
                            switch segment {
                            case .posts(let items):
                                LazyVGrid(columns: columns, spacing: 1) {
                                    ForEach(items) { item in
                                        FeedGridCell(
                                            post: item.post,
                                            onLike: { viewModel.toggleLike(item.post) },
                                            onComment: { commentsPost = item.post; viewModel.notifyCommentOpened(item.post) },
                                            onShare: { Task { await viewModel.toggleShare(item.post) } },
                                            onMore: { moreActionsPost = item.post }
                                        )
                                            .onTapGesture {
                                                detailStartIndex = item.index
                                                showDetail = true
                                            }
                                            .onAppear {
                                                // Port de `PreLoadingGridLayoutManager` (pagination
                                                // anticipée) — même seuil que l'ancien pager (2
                                                // items avant la fin).
                                                if item.index == viewModel.posts.count - 2 {
                                                    Task { await viewModel.loadNextPage() }
                                                }
                                            }
                                    }
                                }
                            case .ad:
                                FeedGridAdCell()
                            }
                        }
                    }
                    .padding(1)
                    feedGridFooter
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
            // `showManagementActions: true` — SEUL contexte "..." avec Statistiques/Promouvoir (voir
            // `boostTargetPost`/`statsTargetPost` ci-dessus, propres posts du fil principal
            // uniquement, fidèle à `promoteBtn`/`statisticBtn` de `CustomCardView`).
            //
            // **Corrigé (V5-F-006, 2026-08-24)** — `includesDownload: true` ajouté. Vérifié
            // directement : `FeedFragment.java:1246-1247,1360-1365` (la classe RÉELLE du plein
            // écran atteint depuis la grille Home, `HomeActivity.java:787-796` →
            // `onArticleSelected(1,...)` → `FeedFragment.newInstance`) inclut bien `R.id.download`
            // dans son menu "...", câblé sur `addingDownloadingFileToQueue`/
            // `checkBestQualityAndDownload`, masqué uniquement sur les posts PROPRES via
            // `idContentHide` — déjà reproduit fidèlement par la garde `if !isOwnPost` existante
            // autour du bouton "Télécharger" (voir plus bas), il ne manquait que ce paramètre.
            FeedDetailPagerView(
                viewModel: viewModel, startIndex: detailStartIndex,
                showManagementActions: true, includesDownload: true, onClose: { showDetail = false }
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
            CommentsView(activityId: post.id, postActorId: post.actor)
        }
        // Port de `promoteBtn` — voir déclaration de `boostTargetPost` ci-dessus.
        .sheet(item: $boostTargetPost) { post in
            NavigationStack { BoostView(activityId: post.id) }
        }
        // Port de `statisticBtn` — voir déclaration de `statsTargetPost` ci-dessus.
        .sheet(item: $statsTargetPost) { post in
            NavigationStack { StatisticsView(activityId: post.id) }
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
                if isOwnPost {
                    Button("Statistiques") { statsTargetPost = post }
                    Button("Promouvoir") { boostTargetPost = post }
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
            ForEach(feedReportReasons, id: \.self) { reason in
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
        // Port du `Toast` d'échec de `deleteMyPost` (V4-F-032, voir `FeedViewModel.deleteOwnPost`).
        .alert("Échec de la suppression", isPresented: Binding(get: { viewModel.deleteError != nil }, set: { if !$0 { viewModel.deleteError = nil } })) {
            Button("OK", role: .cancel) { viewModel.deleteError = nil }
        } message: {
            Text(viewModel.deleteError ?? "")
        }
        // Port du `Toast` `errorLoad` d'échec de `block()` (V5-F-065, voir `FeedViewModel.block`).
        .alert("Échec du blocage", isPresented: Binding(get: { viewModel.blockError != nil }, set: { if !$0 { viewModel.blockError = nil } })) {
            Button("OK", role: .cancel) { viewModel.blockError = nil }
        } message: {
            Text(viewModel.blockError ?? "")
        }
    }

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

/// Port d'un `mediaObjects`+position — voir doc de `FeedView.feedGridSegments`. `id` = l'index
/// dans `viewModel.posts` (stable pour la durée d'affichage, comme le `id: \.offset` déjà utilisé
/// ailleurs dans ce fichier pour le même tableau).
private struct FeedGridItem: Identifiable {
    let index: Int
    let post: FeedActivity
    var id: Int { index }
}

/// Voir doc de `FeedView.feedGridSegments`.
private enum FeedGridSegment {
    case posts([FeedGridItem])
    case ad
}

/// Port de `AdsViewHolder`/`CustomAdsSmallView` — cellule publicitaire COMPACTE de la grille Home,
/// **distincte de `FeedAdCell`** (plein écran, réservée au pager de détail plus bas dans ce
/// fichier). **Ajoutée le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-008, Phase B P2)**.
/// Vérifié directement : `ActivityAdapter.java:205,217-231` (`AdsViewHolder.setPlaceholder` —
/// commentaire Android explicite : *"contrairement au feed plein écran (ViewPager2), la grille
/// tolère une hauteur réduite — pas de shimmer, juste une case basse et neutre le temps qu'une
/// annonce arrive"*, alpha 0.25, hauteur fixe 48dp tant qu'aucune annonce n'est chargée, puis
/// `WRAP_CONTENT` une fois chargée) — d'où un placeholder discret ici plutôt que le `ProgressView`
/// sur fond noir de `FeedAdCell`. `NativeAdContentView` (déjà porté, `AdMobManager.swift`) est
/// réutilisé tel quel : sa mise en page compacte (icône+titre/corps+CTA, ~56pt) correspond déjà au
/// "small template" qu'Android utilise ici, sans besoin d'un rendu séparé.
private struct FeedGridAdCell: View {
    @StateObject private var loader = NativeAdLoader()

    var body: some View {
        Group {
            if let nativeAd = loader.nativeAd {
                NativeAdContentView(nativeAd: nativeAd)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground).opacity(0.25))
                    .frame(height: 48)
            }
        }
        .onAppear { loader.load() }
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
            // Corrigé (2026-08-27, BUG 1, correctif final) — après 4 tours de diagnostic (données
            // reçues confirmées correctes sur l'appareil, CDN+Referer confirmés corrects au `curl`,
            // aucune erreur `AsyncImagePhase.failure` observée), convergé sur EXACTEMENT le pattern
            // déjà éprouvé et fonctionnel de `ProfileView.postCell` plutôt que de continuer à
            // deviner un mécanisme SwiftUI en cause : `.aspectRatio(...)` posé sur CHAQUE branche
            // individuellement (photo chargée / placeholder / pas d'URL), PAS sur le `ZStack`
            // entier comme avant (seule différence structurelle jamais isolée avec certitude entre
            // les deux grilles) — et variante `CDNAsyncImage(url:targetSize:content:placeholder:)`
            // (image/placeholder), identique à celle de Profile, plutôt que la variante `phase`
            // brute. Toute la scaffolding de diagnostic (bandeau, étiquettes par case) retirée —
            // objectif : converger vers l'implémentation dont le fonctionnement est confirmé,
            // plutôt que d'isoler la cause exacte de la divergence.
            if let thumb = post.thumbnailURL {
                // V4-F-073 — tuile de grille 2 colonnes (`FeedView.columns`/`HashtagFeedView.
                // columns`, `spacing: 1`, les deux écrans qui réutilisent cette cellule), largeur
                // ≈ moitié de l'écran.
                CDNAsyncImage(url: thumb, targetSize: CGSize(width: UIScreen.main.bounds.width / 2, height: UIScreen.main.bounds.width / 2)) {
                    $0.resizable().aspectRatio(0.8, contentMode: .fill).clipped()
                } placeholder: {
                    Color(.secondarySystemBackground).aspectRatio(0.8, contentMode: .fill)
                }
            } else {
                Color(.secondarySystemBackground).aspectRatio(0.8, contentMode: .fill)
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
    /// Port de `promoteBtn`/`statisticBtn` (`CustomCardView.java`, propres posts uniquement) — `true`
    /// SEULEMENT depuis le fil principal (`FeedView`) ; Android n'a AUCUN équivalent dans les menus
    /// "..." de `ProfileFeedFragment`/`FullScreenMedia`/`HashtagProfile` (vérifié par lecture des 4
    /// fichiers, V4-F-007).
    var showManagementActions = false
    /// Port de `R.id.download` (`layout_post_action.xml`) — `true` SEULEMENT depuis `ProfileView` :
    /// c'est le SEUL menu "..." Android où le download est réellement câblé (voir
    /// `FeedMediaDownloader.swift`, V4-F-007 — les 3 autres menus `MainFragment`/`FullScreenMedia`/
    /// `HashtagProfile` n'ont pas cet item, ou pointent vers un handler mort/erroné).
    var includesDownload = false
    let onClose: () -> Void

    @State private var currentIndex: Int
    /// Port de la navigation `nameContainer` → `UserProfile.class` (P0-C, 2026-08-17) — présenté
    /// depuis CE pager plutôt que remonté à l'appelant : Android ouvre `UserProfile` comme un
    /// nouvel écran empilé par-dessus le fullscreen, jamais en le fermant d'abord.
    @State private var openProfileUserId: String?

    /// Port de `TokenClickableSpan.onClick` → `Intent(ctx, RechercheTiinver.class)`
    /// (`MentionTextView.java:184-196`) — **ajouté le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md
    /// V3-F-099, Phase B P1)**. Présenté par-dessus ce pager (même empilement que
    /// `openProfileUserId` juste au-dessus), jamais en le fermant d'abord — fidèle à
    /// `ctx.startActivity(intent)` (nouvel écran Android empilé, pas un remplacement).
    @State private var searchToken: (query: String, tab: SearchTab)?

    // Port de `OnclickCommentaire`/`OnclickMoreExpand` (bottom sheet `layout_post_action.xml`) —
    // **ajouté le 2026-08-23 (V4-F-007, Phase B P0-3)** : ce pager plein écran affichait un bouton
    // "..." et un bouton commentaire RÉELLEMENT DÉCORATIFS pour 5 des 6 écrans qui le réutilisent
    // (`SearchView`/`HashtagFeedView`/`NotificationsListView`/`HomeShellView`/`ProfileView` passaient
    // tous par l'initialiseur `posts:` sans `onComment`/`onMore`, dont les valeurs par défaut étaient
    // des no-op) — état et boîtes de dialogue désormais INTERNES à cette vue plutôt que remontés par
    // fermeture à l'appelant, pour que les 6 écrans en bénéficient automatiquement sans câblage
    // séparé (comportement uniforme, fidèle à Android où CHAQUE fragment plein écran possède son
    // propre `OnclickMoreExpand` complet).
    @State private var moreActionsPost: FeedActivity?
    @State private var reportTargetPost: FeedActivity?
    @State private var showReportReasons = false
    @State private var blockTargetPost: FeedActivity?
    @State private var commentsPost: FeedActivity?
    @State private var boostTargetPost: FeedActivity?
    @State private var statsTargetPost: FeedActivity?
    @State private var downloadError: String?
    /// Port de `uniqueDowloadSet` (`ProfileFeedFragment.java:101,769-773`, V5-F-096) — un `post.id`
    /// une fois inséré n'est JAMAIS retiré (pas de `defer`/retrait au succès ou à l'échec, fidèle à
    /// Android : le `Set` n'est vidé qu'en recréant le Fragment, ici l'équivalent est la durée de
    /// vie de CETTE instance de pager). Un second tap sur "Télécharger" pour le même post — pendant
    /// le téléchargement OU même après qu'il soit terminé/ait échoué — est silencieusement ignoré.
    @State private var queuedDownloadPostIds: Set<Int> = []

    /// Port ponctuel : quand ce pager est ouvert directement sur UN post isolé (résolution d'un lien
    /// profond `/post/{token}`, `DeepLinkRouter.swift`) ou sur une liste jetable (résultats de
    /// recherche, hashtag) plutôt que sur le fil principal, un `FeedViewModel` jetable suffit — les
    /// actions (like/commentaire/partage/suppression/blocage/signalement) restent fonctionnelles
    /// même hors contexte fil.
    init(posts: [FeedActivity], startIndex: Int, includesDownload: Bool = false, notifiesAuthor: Bool = false, onClose: @escaping () -> Void) {
        let vm = FeedViewModel(notifiesAuthorOnInteraction: notifiesAuthor)
        vm.posts = posts
        _viewModel = StateObject(wrappedValue: vm)
        self.startIndex = startIndex
        self.includesDownload = includesDownload
        self.onClose = onClose
        _currentIndex = State(initialValue: startIndex)
    }

    init(viewModel: FeedViewModel, startIndex: Int, showManagementActions: Bool = false, includesDownload: Bool = false, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.startIndex = startIndex
        self.showManagementActions = showManagementActions
        self.includesDownload = includesDownload
        self.onClose = onClose
        _currentIndex = State(initialValue: startIndex)
    }

    private var posts: [FeedActivity] { viewModel.posts }

    /// Demande explicite (2026-08-27) : marges de zone sûre pour les seuls éléments de CONTRÔLE
    /// (bouton retour, rail d'actions/légende/"S'abonner") — le média reste plein écran bord à
    /// bord (`.ignoresSafeArea()` sur le pager, inchangé). **Corrigé (2ᵉ tour)** : la 1ʳᵉ version
    /// lisait ces marges via un `GeometryReader` EXTERNE enveloppant tout le `body` — un
    /// `GeometryReader` sans `.ignoresSafeArea()` occupe lui-même le rectangle RÉDUIT (zone sûre
    /// exclue), et PROPOSE cette taille réduite à ses enfants, y compris le `GeometryReader`
    /// interne du pager (qui ignore pourtant lui-même la zone sûre — imbrication de
    /// `GeometryReader` non standard et fragile) : `geo.size` (utilisé par le calcul de rotation)
    /// pouvait donc recevoir une largeur/hauteur légèrement DIFFÉRENTES de l'écran réel selon
    /// l'appareil, expliquant le débordement horizontal observé (rail d'actions/légende coupés à
    /// gauche ET à droite). Lues ici directement depuis la fenêtre (`UIWindowScene`), sans aucun
    /// `GeometryReader` supplémentaire dans l'arbre de vues du pager.
    private static var deviceSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets ?? .zero
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                TabView(selection: $currentIndex) {
                    ForEach(Array(posts.enumerated()), id: \.offset) { index, post in
                        Group {
                            if isAdPosition(index, count: posts.count) {
                                FeedAdCell()
                            } else {
                                FeedDetailCell(
                                    bottomSafeArea: Self.deviceSafeAreaInsets.bottom,
                                    post: post, isActive: index == currentIndex,
                                    onLike: { viewModel.toggleLike(post) },
                                    onComment: { commentsPost = post; viewModel.notifyCommentOpened(post) },
                                    onShare: { Task { await viewModel.toggleShare(post) } },
                                    onMore: { moreActionsPost = post },
                                    onOpenProfile: { if let actor = post.actor { openProfileUserId = actor } },
                                    onFollow: { Task { await viewModel.followFromDetail(post) } },
                                    onOpenSearch: { query, tab in searchToken = (query, tab) }
                                )
                            }
                        }
                            // BUG 2/3 (validation physique, 2026-08-27, corrigé une 2ᵉ fois le même
                            // jour après un retour de test réel confirmant un débordement bas d'écran)
                            // — `.rotationEffect` ne change JAMAIS la taille de layout qu'une vue
                            // remonte à son parent, seulement son RENDU visuel : un 1ᵉʳ correctif
                            // n'appliquait qu'un SEUL frame, AVANT la rotation, aux dimensions RÉELLES
                            // de l'écran (`geo.size`, non échangées) — nécessaire pour que le contenu
                            // (image/vidéo) se dispose avec les bonnes proportions, mais ce frame,
                            // n'étant pas affecté par la rotation qui suit, remontait TOUJOURS au
                            // `TabView` un encombrement de layout NON échangé (portrait), alors que le
                            // `TabView` lui-même réserve un encombrement ÉCHANGÉ (paysage, ligne
                            // suivante) — décalage qui faisait déborder le contenu (et le rail
                            // d'actions/l'avatar/le bouton "S'abonner" de `FeedDetailCell`, déjà
                            // câblés, lignes 901-989 plus bas) hors de l'écran réel. Pattern complet du
                            // contournement "TabView vertical par rotation" : DEUX frames par page —
                            // celui AVANT rotation (dimensions réelles, proportions du contenu) ET un
                            // second APRÈS rotation (dimensions échangées, ce que le `TabView` réserve
                            // réellement pour cette page) — seul ce 2ᵉ frame était manquant.
                            .frame(width: geo.size.width, height: geo.size.height)
                            .rotationEffect(.degrees(-90))
                            .frame(width: geo.size.height, height: geo.size.width)
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
            .padding(.top, Self.deviceSafeAreaInsets.top + 8)
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
        .fullScreenCover(isPresented: Binding(get: { searchToken != nil }, set: { if !$0 { searchToken = nil } })) {
            if let searchToken {
                NavigationStack {
                    SearchView(initialQuery: searchToken.query, initialTab: searchToken.tab)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Fermer") { self.searchToken = nil }
                            }
                        }
                }
            }
        }
        .sheet(item: $commentsPost) { post in
            CommentsView(activityId: post.id, postActorId: post.actor)
        }
        .sheet(item: $boostTargetPost) { post in
            NavigationStack { BoostView(activityId: post.id) }
        }
        .sheet(item: $statsTargetPost) { post in
            NavigationStack { StatisticsView(activityId: post.id) }
        }
        // Port de `OnclickMoreExpand` — voir `ProfileFeedFragment`/`FullScreenMedia`/
        // `HashtagProfile` selon l'écran d'origine (tous à 5 items de base ; Profile en a un 6ᵉ,
        // `download`, seul menu Android où cet item est réellement câblé — `includesDownload`).
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
                if isOwnPost, showManagementActions {
                    Button("Statistiques") { statsTargetPost = post }
                    Button("Promouvoir") { boostTargetPost = post }
                }
                if !isOwnPost {
                    Button("Copier le lien") {
                        if let token = post.token { UIPasteboard.general.string = "https://tiinver.com/post/\(token)" }
                    }
                    Button("Ne plus suivre @\(post.username ?? "")") { Task { await viewModel.unfollow(post) } }
                    Button("Bloquer @\(post.username ?? "")", role: .destructive) { blockTargetPost = post }
                    Button("Signaler le post") { reportTargetPost = post; showReportReasons = true }
                    if includesDownload {
                        // Port de `addingDownloadingFileToQueue` (V5-F-096) — `Set.add` retourne
                        // `false` si déjà présent, ignore silencieusement un second appel pour le
                        // même post, à l'identique ici.
                        Button("Télécharger") {
                            guard queuedDownloadPostIds.insert(post.id).inserted else { return }
                            Task {
                                do { try await FeedMediaDownloader.download(post) } catch {
                                    downloadError = error.localizedDescription
                                }
                            }
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
        // **Corrigé (V5-F-007, 2026-08-24)** — `includesTarget: true` : ce `confirmationDialog`
        // appartient à `FeedDetailPagerView` (plein écran, tous contextes parents confondus),
        // fidèle à `FeedFragment.java`/`ProfileFeedFragment.java`/`HashtagProfile.java` qui
        // remplissent tous `target_id`/`report_type="content"` pour un signalement de contenu
        // depuis LEUR plein écran respectif — contrairement au site frère de `FeedView` (grille,
        // ligne ~259 ci-dessus) qui reste fidèle à `MainFragment` (vide).
        .confirmationDialog("Motif du signalement", isPresented: $showReportReasons, titleVisibility: .visible) {
            ForEach(feedReportReasons, id: \.self) { reason in
                Button(reason) {
                    if let post = reportTargetPost { Task { await viewModel.report(post, reason: reason, includesTarget: true) } }
                }
            }
            Button("Annuler", role: .cancel) { reportTargetPost = nil }
        }
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
        .alert("Téléchargement impossible", isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
            Button("OK", role: .cancel) { downloadError = nil }
        } message: {
            Text(downloadError ?? "")
        }
        // Port du `Toast` d'échec de `deleteMyPost` (V4-F-032, voir `FeedViewModel.deleteOwnPost`).
        .alert("Échec de la suppression", isPresented: Binding(get: { viewModel.deleteError != nil }, set: { if !$0 { viewModel.deleteError = nil } })) {
            Button("OK", role: .cancel) { viewModel.deleteError = nil }
        } message: {
            Text(viewModel.deleteError ?? "")
        }
        // Port du `Toast` `errorLoad` d'échec de `block()` (V5-F-065, voir `FeedViewModel.block`).
        .alert("Échec du blocage", isPresented: Binding(get: { viewModel.blockError != nil }, set: { if !$0 { viewModel.blockError = nil } })) {
            Button("OK", role: .cancel) { viewModel.blockError = nil }
        } message: {
            Text(viewModel.blockError ?? "")
        }
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

/// Port de `RESIZE_MODE_ZOOM` (`AspectRatioFrameLayout`, `ActivityfeedViewPager.java:105`, la
/// vue vidéo du pager plein écran Android) — enveloppe minimale autour d'`AVPlayerLayer` plutôt
/// que le `VideoPlayer` SwiftUI/AVKit natif : ce dernier n'expose AUCUN moyen de remplacer son
/// `.resizeAspect` (letterboxé) fixe par un mode "remplir" (`.resizeAspectFill`), contrairement à
/// `AVPlayerLayer.videoGravity`, qui l'expose directement. Aucun contrôle de lecture natif
/// nécessaire ici (le tap joue/pause est déjà géré ailleurs, `VideoPlayer` était déjà `.disabled
/// (true)` pour la même raison) — une simple couche suffit, pas besoin d'`AVPlayerViewController`.
private struct FillVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

private struct FeedDetailCell: View {
    /// Demande explicite (2026-08-27) : le rail d'actions/bloc légende ne doit pas être collé au
    /// bord bas réel de l'appareil (sous la zone de geste de l'indicateur d'accueil) — transmis
    /// depuis `FeedDetailPagerView` (seul endroit qui a accès à la vraie zone sûre, en dehors de
    /// l'`.ignoresSafeArea()` du pager lui-même).
    var bottomSafeArea: CGFloat = 0
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
    /// Port de `TokenClickableSpan.onClick` — `query` = texte SANS préfixe, `tab` = `.hashtags`/
    /// `.users` (**ajouté le 2026-08-20, MIGRATION_PARITY_AUDIT_V3.md V3-F-099, Phase B P1**).
    var onOpenSearch: (_ query: String, _ tab: SearchTab) -> Void = { _, _ in }

    var body: some View {
        ZStack {
            // **Ajouté (V4-F-034, 2026-08-24)** — port de `ExoPlayerManager.java:198-330`, qui
            // détache explicitement le player de la vue précédente avant de l'attacher à la
            // nouvelle : `VideoPlayer(player:)` liait TOUJOURS le même `AVPlayer` PARTAGÉ, y
            // compris pour les cellules voisines que `TabView` garde potentiellement instanciées
            // pendant un swipe — un `AVPlayer` unique attaché à 2 `VideoPlayer` simultanés rend
            // ses images sur LES DEUX à la fois (comportement AVFoundation documenté, pas une
            // supposition). Le binding lui-même est maintenant gated sur `isActive`, pas
            // seulement le déclenchement de la lecture — la cellule inactive retombe sur la
            // vignette juste en dessous.
            if post.isVideo, let url = post.playbackURL, isActive {
                // Corrigé (2026-08-27, validation physique) — `VideoPlayer` (AVKit) natif SwiftUI
                // utilise TOUJOURS `.resizeAspect` (letterboxé, marges noires haut/bas + léger
                // décalage horizontal selon le ratio), sans AUCUN réglage exposé pour changer ce
                // comportement. Vérifié contre Android : `ActivityfeedViewPager.java:105`
                // (`videoSurfaceView.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_ZOOM)`) — le
                // plein écran Android recadre TOUJOURS la vidéo pour remplir l'écran, jamais de
                // letterboxing. `FillVideoPlayerView` (ci-dessous) reproduit ce comportement via
                // `AVPlayerLayer.videoGravity = .resizeAspectFill`, seul moyen d'obtenir ce réglage
                // (non exposé par le `VideoPlayer` SwiftUI).
                FillVideoPlayerView(player: VideoPlayerManager.shared.player)
                    .onAppear {
                        // Port de `VideoPlaybackCoordinator.tryPlayAt` — `fallbackURL` était
                        // jamais transmis avant le correctif V4 précédent malgré le mécanisme de
                        // repli déjà présent dans `VideoPlayerManager` (`handlePlaybackFailure`).
                        VideoPlayerManager.shared.playVideo(url: url, fallbackURL: post.fallbackPlaybackURL)
                    }
            } else if let thumb = post.thumbnailURL {
                // V4-F-073 — arrière-plan plein écran (viewer fullscreen) : décodage borné à la
                // taille d'écran réelle plutôt qu'à la résolution CDN d'origine, toujours un gain
                // mémoire pour une photo source généralement bien plus grande que l'écran.
                CDNAsyncImage(url: thumb, targetSize: UIScreen.main.bounds.size) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
            } else {
                Color.black
            }

            // `.zIndex(1)` — demande explicite (2026-08-27) : le rail d'actions/le bloc légende
            // n'apparaissaient pas de façon identique sur une photo vs une vidéo, malgré un code
            // strictement identique (bloc FRÈRE, pas enfant, de la branche média — voir ci-dessus).
            // `VideoPlayer` (AVKit) est un `UIViewControllerRepresentable` avec sa propre hiérarchie
            // UIKit, qui peut composer différemment de l'ordre normal SwiftUI (`ZStack` empile par
            // ordre de déclaration) qu'une simple `Image` — force ici explicitement cette superposition
            // au-dessus de N'IMPORTE QUEL type de média, plutôt que de compter implicitement sur
            // l'ordre de déclaration.
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    // Ordre EXACT de `reaction_pub_but.xml` (lu en entier, layout du vrai fullscreen
                    // Android) — auparavant inversé côté iOS (avatar/nom en premier, légende en
                    // dernier) : `message` (légende/hashtag) est le PREMIER enfant du bloc
                    // d'informations, suivi de la ligne avatar+pseudo+date, suivie du bouton
                    // "S'abonner". Capture Android fournie par l'utilisateur confirmant cet ordre
                    // visuel exact (2026-08-17).
                    VStack(alignment: .leading, spacing: 8) {
                        if let message = post.message, !message.isEmpty {
                            // Port de `message.setSpannableText(mediaObject.getMessage())`
                            // (`CustomCardView.java:142`/`VideoViewHolder.java:636`) — **corrigé le
                            // 2026-08-20 (V3-F-099, Phase B P1)** : `Text(message)` brut remplacé
                            // par `HashtagMentionText`, seul endroit Android où la légende est
                            // cliquable (confirmé par grep exhaustif : ces 2 fichiers sont les 2
                            // SEULS appelants de `setSpannableText` dans tout le projet Android).
                            HashtagMentionText(text: message, onToken: onOpenSearch)
                                .lineLimit(2)
                        }

                        // Port de `avatar`/`nameContainer`/`stamp` (`CustomCardView.init`/
                        // `setData`) — absents jusqu'ici du fullscreen iOS (gap confirmé par
                        // relecture du code Android réel, pas une hypothèse) : avatar rond +
                        // pseudo + date (`TimeUtils.getDate`, "yyyy-MM-dd HH:mm:ss" →
                        // "dd-MM-yy"), zone tapable entière → profil de l'auteur.
                        Button(action: onOpenProfile) {
                            HStack(spacing: 8) {
                                CDNAsyncImage(url: post.profile.flatMap(URL.init(string:)), targetSize: CGSize(width: 36, height: 36)) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Circle().fill(Color.white.opacity(0.2))
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(post.username.map { "@\($0)" } ?? "")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    if let date = Self.formattedStamp(post.stamp) {
                                        Text(date)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Port de `followBtn` — masqué sur ses propres posts (`getCurrentUserId()
                        // == getActor()`) et une fois déjà suivi (`isFollowed()`), jamais de
                        // bascule "ne plus suivre" depuis ce bouton précis (fidèle à Android).
                        if post.actor != UserSession.shared.myId, post.isFollowed != true {
                            Button(action: onFollow) {
                                Text("S'abonner")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(Color.white, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                    Spacer()
                    // Port de `OnLikeClicked`/`OnclickCommentaire`/`OnclickPrtg`/`OnclickMoreExpand`
                    // — rail d'actions verticale (même 4 interactions que la cellule de grille,
                    // voir `FeedGridCell`), emplacement standard pour un pager plein écran.
                    actionRail
                }
                .padding()
                // Demande explicite (2026-08-27, 2ᵉ tour) : le premier réglage (juste
                // `bottomSafeArea`, ~34pt sur un appareil à encoche) restait visuellement trop
                // petit — Android garde sa propre barre de navigation du bas visible même sur cet
                // écran plein écran (référence vidéo fournie), une hauteur comparable à une barre
                // d'onglets standard (~49pt de contenu), pas seulement l'indicateur d'accueil.
                .padding(.bottom, bottomSafeArea + 49)
            }
            .zIndex(1)
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

    /// Port de `Utils/TimeUtils.getDate` (lu en entier) — entrée `"yyyy-MM-dd HH:mm:ss"`, sortie
    /// `"dd-MM-yy"` EXACTEMENT (confirmé par la capture Android fournie : "01-05-26"). `en_US_POSIX`
    /// plutôt que `Locale.current` — motif Apple standard pour un format fixe non localisé (évite
    /// que le calendrier persan/hébreu d'un utilisateur ne fasse échouer silencieusement le parsing,
    /// contrairement à `Locale.getDefault()` côté Java qui n'a pas cette classe de piège).
    private static let inputStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    private static let outputStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MM-yy"
        return f
    }()
    private static func formattedStamp(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, let date = inputStampFormatter.date(from: raw) else { return nil }
        return outputStampFormatter.string(from: date)
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
