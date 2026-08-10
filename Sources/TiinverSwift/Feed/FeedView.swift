import SwiftUI
import AVKit

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
struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var currentIndex = 0

    var body: some View {
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
        .ignoresSafeArea()
        .task { await viewModel.loadInitial() }
        .onChange(of: currentIndex) { newIndex in
            preloadAround(newIndex)
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
