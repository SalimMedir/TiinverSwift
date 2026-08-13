import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Port partiel de `Activity/ui/MainFragment.java` (RecyclerView plein écran + `ExoPlayerManager`)
/// — défilement vertical, une vidéo à la fois, lecteur unique réutilisé entre les cellules.
///
/// `TabView` en style `.page` est nativement horizontal ; la rotation (page tournée -90°, conteneur
/// tourné +90°) est le contournement standard pour obtenir un défilement vertical plein écran sur
/// iOS 16 sans dépendance tierce — **non vérifié visuellement faute d'environnement macOS/Xcode**,
/// à confirmer au premier build réel (voir contrainte d'environnement en tête de
/// MIGRATION_PROGRESS.md). Si le rendu réel s'avère insatisfaisant, remplacer par un
/// `ScrollView` + `.scrollTargetBehavior(.paging)` (iOS 17+, plus simple mais relèverait la cible
/// de déploiement — décision à prendre avec l'utilisateur, pas unilatéralement ici).
///
/// **Point d'entrée réel du module 7 (Caméra), câblé ici** : `R.id.fab` de `MainFragment`
/// (`fab.setOnClickListener` → `requestPermission()` → vérifie `Manifest.permission.CAMERA` →
/// `startActivity(CameraActivity.class)`) — retrouvé par grep de `CameraActivity.class` dans tout
/// le dépôt Android (7 lanceurs distincts au total : `MainFragment` (le vrai FAB principal),
/// `FeedFragment`, `TiinverGeminiAIChat`, `ShareActivity`, `ReferralActivity`,
/// `MonetizationActivity` — seul le FAB de `MainFragment` est câblé ici, les autres points
/// d'entrée secondaires appartiennent à des modules pas encore portés). `CameraActivity` est une
/// **Activity Android à part entière** (pas une position `HomeActivity.onArticleSelected` comme
/// supposé dans une note précédente de ce fichier avant vérification) — `.fullScreenCover` est
/// l'équivalent iOS le plus proche de `startActivity` (nouvel écran plein écran, pas une feuille
/// modale partielle).
struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var currentIndex = 0
    @State private var showCamera = false

    var body: some View {
        ZStack {
            if viewModel.posts.isEmpty {
                // 2026-08-13 — état visible AJOUTÉ (audit post-Appetize.io) : ce cas (aucun post
                // encore chargé) précédait un écran totalement blanc, sans distinction possible
                // entre "en cours de chargement", "erreur réseau/session" et "flux réellement vide"
                // — confirmé par lecture complète de ce fichier AVANT correction, `viewModel.
                // isLoading`/`errorMessage` n'étaient référencés NULLE PART dans le corps de cette
                // vue. Les 3 états sont maintenant visibles ; le flux vidéo plein écran (ci-dessous)
                // ne s'affiche qu'une fois au moins un post chargé, comme avant.
                emptyOrStatusState
            } else {
                feedPager
            }
        }
        .ignoresSafeArea()
        .task { await viewModel.loadInitial() }
        .onChange(of: currentIndex) { newIndex in
            preloadAround(newIndex)
        }
        .overlay(alignment: .bottomTrailing) {
            // Positionnement bottom-trailing standard (le layout XML exact de
            // `fragment_main.xml` n'a pas été fourni/lu) — comportement du bouton, lui, vérifié
            // contre le code réel (`requestPermission()`).
            cameraFAB
                .padding(.trailing, 20)
                .padding(.bottom, 90)
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

    private var feedPager: some View {
        GeometryReader { geo in
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.posts.enumerated()), id: \.offset) { index, post in
                    FeedCell(post: post, isActive: index == currentIndex)
                        .frame(width: geo.size.height, height: geo.size.width)
                        .rotationEffect(.degrees(-90))
                        .tag(index)
                        .onAppear {
                            if index == viewModel.posts.count - 2 {
                                Task { await viewModel.loadNextPage() }
                            }
                        }
                }
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90), anchor: .topLeading)
            .offset(x: geo.size.width)
            .tabViewStyle(.page(indexDisplayMode: .never))
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
                    .tint(.white)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Réessayer") { Task { await viewModel.loadNextPage() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "film").font(.system(size: 40)).foregroundStyle(.white.opacity(0.6))
                Text("Aucune vidéo à afficher pour le moment").foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
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

    /// Port de `ExoPlayerManager.smartPreload`/`PreloadScheduler` (fenêtre `currentIndex ± 2`) —
    /// les posts non-vidéo (photos) sont ignorés, comme `"videos".equalsIgnoreCase(obj.getObject())`
    /// le fait déjà côté Android (`submitPreload`).
    private func preloadAround(_ index: Int, windowSize: Int = 2) {
        for offset in -windowSize...windowSize where offset != 0 {
            let target = index + offset
            guard viewModel.posts.indices.contains(target) else { continue }
            let post = viewModel.posts[target]
            guard post.isVideo, let url = post.playbackURL else { continue }
            VideoPlayerManager.shared.preload(url)
        }
    }
}

private struct FeedCell: View {
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
