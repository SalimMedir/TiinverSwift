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

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]

    var body: some View {
        Group {
            if viewModel.posts.isEmpty {
                emptyOrStatusState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(Array(viewModel.posts.enumerated()), id: \.offset) { index, post in
                            FeedGridCell(post: post)
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
                posts: viewModel.posts, startIndex: detailStartIndex,
                onLoadMore: { Task { await viewModel.loadNextPage() } },
                onClose: { showDetail = false }
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(
                onClose: { showCamera = false },
                onPhotoCaptured: { _ in
                    // Port de `onArticleSelected(2, args)` côté `CameraActivity` → `MediaEditor`
                    // (module 9, "Éditeur photo simple", PAS encore porté). Referme la caméra
                    // pour l'instant, sans enchaîner sur un éditeur qui n'existe pas encore —
                    // TODO explicite à reprendre au module 9, pas une case oubliée.
                    showCamera = false
                },
                onVideoRecorded: { _, _ in
                    // Port de `onArticleSelected(7, args)` côté `CameraActivity` → `MediasDisplay`
                    // (fragment pas encore identifié dans l'ordre de portage à 18 modules — à
                    // rattacher au moment venu, comme `Roster.java`/`CreatorFragment.java` au
                    // module 6). Referme la caméra sans enchaîner, TODO explicite.
                    showCamera = false
                },
                onImagePickedFromGallery: { _ in
                    // Port de la branche image de `pickMedia` → `onArticleSelected(2, bundle)` →
                    // `MediaEditor` (module 9, pas encore porté). TODO explicite.
                    showCamera = false
                },
                onVideoPickedFromGallery: { _ in
                    // Port de la branche vidéo de `pickMedia` → `onArticleSelected(10, bundle)` →
                    // `MediaTrim` (module non encore identifié dans l'ordre de portage). TODO
                    // explicite.
                    showCamera = false
                },
                onOpenAnimems: {
                    // Port de `onArticleSelected(5, ...)` côté `CameraActivity` → `MemesFragment`
                    // (module 8, pas encore commencé à ce stade — voir `CameraView.swift`).
                }
            )
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
/// (photo ou 1ʳᵉ image vidéo), nom d'utilisateur, compteurs like/commentaire en surimpression bas-
/// gauche (`nikname`/`ShowJaimeNum`/`commentQte`, mêmes champs que `onBindView`/`video`/`photo`).
private struct FeedGridCell: View {
    let post: FeedActivity

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(.secondarySystemBackground)
            if let thumb = post.thumbnailURL {
                AsyncImage(url: thumb) { phase in
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
                    Label("\(post.likes ?? 0)", systemImage: "heart.fill")
                    Label("\(post.comment ?? 0)", systemImage: "message.fill")
                }
                .font(.caption2).foregroundStyle(.white).labelStyle(.titleAndIcon)
            }
            .padding(8)
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
private struct FeedDetailPagerView: View {
    let posts: [FeedActivity]
    let startIndex: Int
    let onLoadMore: () -> Void
    let onClose: () -> Void

    @State private var currentIndex: Int

    init(posts: [FeedActivity], startIndex: Int, onLoadMore: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.posts = posts
        self.startIndex = startIndex
        self.onLoadMore = onLoadMore
        self.onClose = onClose
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                TabView(selection: $currentIndex) {
                    ForEach(Array(posts.enumerated()), id: \.offset) { index, post in
                        FeedDetailCell(post: post, isActive: index == currentIndex)
                            .frame(width: geo.size.height, height: geo.size.width)
                            .rotationEffect(.degrees(-90))
                            .tag(index)
                            .onAppear {
                                if index == posts.count - 2 { onLoadMore() }
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
                AsyncImage(url: thumb) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
            } else {
                Color.black
            }

            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.username.map { "@\($0)" } ?? "")
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let message = post.message, !message.isEmpty {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .background(Color.black)
        .clipped()
    }
}
