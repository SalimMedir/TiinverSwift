import SwiftUI
import AVFoundation

/// Port de `CommunityTemplateGalleryView.java` (854 lignes, lu en entier) — grille de modèles de
/// mouvement communautaires, confirmée par un audit dédié comme une fonctionnalité RÉELLE et
/// accessible depuis l'UI Android (`btn_display_online_template`, PAS du code mort — voir
/// `CommunityTemplateRepository.swift` pour la traçabilité complète et la limitation de fidélité
/// assumée sur le contenu binaire téléchargé).
///
/// Fidèle à l'original : grille 2 colonnes, 4 filtres client-side (Tout/Avec son/1 piste/
/// Multi-pistes) appliqués sur la liste déjà récupérée, pagination infinie (20/page) déclenchée en
/// approchant la fin de la liste FILTRÉE affichée (même comportement qu'Android — un filtre actif
/// réduit ce qui déclenche la page suivante, ce n'est pas "corrigé" ici), aperçu de trajectoire
/// dessiné depuis les matrices déjà en cache (rien avant téléchargement), aperçu sonore
/// (stream direct ou fichier local une fois téléchargé), bouton "Utiliser →" qui télécharge puis
/// applique via le même chemin que les modèles locaux (`AnimemesEditorState.applyTemplate`).
///
/// **Amélioration mineure assumée, pas une divergence fonctionnelle** : les puces de filtre sont
/// visuellement mises en surbrillance selon `activeFilter` ici — côté Android, la coloration est
/// figée à la construction de la barre et ne se met jamais à jour visuellement après le premier tap
/// (bug cosmétique de l'original, sans effet sur le filtrage réel lui-même, qui fonctionne
/// correctement des deux côtés).
struct CommunityTemplateGalleryView: View {
    var onSelect: (MotionTemplate) -> Void
    var onClose: () -> Void

    @State private var remoteList: [TemplateRemoteModel] = []
    @State private var filtered: [TemplateRemoteModel] = []
    @State private var activeFilter = 0
    @State private var currentOffset = 0
    @State private var isLoading = false
    @State private var hasMoreData = true
    @State private var errorMessage: String?
    @State private var cachedByID: [String: MotionTemplate] = [:]
    @State private var downloadingID: String?
    @State private var previewPlayer: AVPlayer?
    @State private var currentPlayingId: String?

    private static let filterLabels = ["Tout", "Avec son", "1 piste", "Multi-pistes"]
    private static let filterColors: [Color] = [.green, .orange, .blue, .pink]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                content
            }
            .background(Color.black)
            .navigationTitle("Modèles de la communauté")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { stopPreviewSound(); onClose() }
                }
            }
        }
        .task { if remoteList.isEmpty { await fetchTemplates() } }
        .onDisappear { stopPreviewSound() }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.filterLabels.indices, id: \.self) { i in
                    let color = Self.filterColors[i]
                    let isActive = i == activeFilter
                    Button {
                        activeFilter = i
                        applyFilter()
                    } label: {
                        Text(Self.filterLabels[i])
                            .font(.system(size: 11))
                            .foregroundColor(isActive ? .white : color)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(isActive ? color : color.opacity(0.1)))
                            .overlay(Capsule().stroke(color.opacity(isActive ? 0 : 0.5), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && remoteList.isEmpty {
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, remoteList.isEmpty {
            Text(errorMessage)
                .foregroundStyle(Color(white: 0.5)).font(.system(size: 14))
                .multilineTextAlignment(.center).padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            Text("Aucun modèle disponible")
                .foregroundStyle(Color(white: 0.4)).font(.system(size: 14))
                .padding(.top, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(filtered) { remote in
                        card(for: remote)
                            .onAppear {
                                guard let idx = filtered.firstIndex(where: { $0.id == remote.id }) else { return }
                                if idx >= filtered.count - 4, !isLoading, hasMoreData {
                                    Task { await fetchTemplates() }
                                }
                            }
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Réseau (port de `fetchTemplates`/`applyFilter`)

    private func fetchTemplates() async {
        guard !isLoading, hasMoreData else { return }
        isLoading = true
        do {
            let result = try await CommunityTemplateRepository.fetchPublicTemplates(offset: currentOffset)
            hasMoreData = result.hasMore
            remoteList.append(contentsOf: result.templates)
            currentOffset += result.templates.count
            errorMessage = nil
            applyFilter()
        } catch {
            if currentOffset == 0 { errorMessage = "Erreur : \(error.localizedDescription)" }
            hasMoreData = false
        }
        isLoading = false
    }

    private func applyFilter() {
        switch activeFilter {
        case 1: filtered = remoteList.filter { $0.hasAudio }
        case 2: filtered = remoteList.filter { $0.trackCount == 1 }
        case 3: filtered = remoteList.filter { $0.trackCount > 1 }
        default: filtered = remoteList
        }
    }

    // MARK: - Carte (port de `RemoteAdapter.buildCard`/`VH.bind`)

    private func card(for remote: TemplateRemoteModel) -> some View {
        VStack(spacing: 0) {
            TrajectoryPreview(template: cachedByID[remote.id], remoteTrackCount: remote.trackCount, remoteHasAudio: remote.hasAudio)
                .frame(height: 90)
            Rectangle().fill(Color(white: 0.1)).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(remote.name.isEmpty ? "Sans nom" : remote.name)
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
                Text("par " + (remote.creatorName?.isEmpty == false ? remote.creatorName! : "Anonyme"))
                    .font(.system(size: 10)).foregroundColor(Color(white: 0.4))
                FlowLayout(spacing: 4) {
                    badge("\(remote.trackCount) piste" + (remote.trackCount > 1 ? "s" : ""), .blue)
                    badge("\(remote.totalFrames) frames", .green)
                    if remote.hasAudio { badge("🎵 son", .orange) }
                }
                .padding(.top, 6)
                HStack(spacing: 6) {
                    if remote.hasAudio, let audioCdnUrl = remote.audioCdnUrl, !audioCdnUrl.isEmpty {
                        Button { togglePreviewSound(remote) } label: {
                            Text(currentPlayingId == remote.id ? "■ Stop" : "▶ Son")
                                .font(.system(size: 11)).foregroundColor(.orange)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(Capsule().fill(Color.orange.opacity(0.1)))
                                .overlay(Capsule().stroke(Color.orange.opacity(0.5), lineWidth: 1))
                        }
                    }
                    Button { useTemplate(remote) } label: {
                        Text(downloadingID == remote.id ? "Téléchargement…" : "Utiliser →")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.green))
                            .opacity(downloadingID == remote.id ? 0.6 : 1)
                    }
                    .disabled(downloadingID == remote.id)
                }
                .padding(.top, 8)
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.14), lineWidth: 1))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9)).foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Utiliser (port de `onUseClicked`)

    private func useTemplate(_ remote: TemplateRemoteModel) {
        stopPreviewSound()
        downloadingID = remote.id
        Task {
            do {
                let template = try await CommunityTemplateRepository.downloadAndPrepare(remote)
                cachedByID[remote.id] = template
                downloadingID = nil
                onSelect(template)
            } catch {
                downloadingID = nil
            }
        }
    }

    // MARK: - Aperçu sonore (port de `onPreviewSound`/`playLocalSound`/`playStreamSound`)

    private func togglePreviewSound(_ remote: TemplateRemoteModel) {
        if currentPlayingId == remote.id {
            stopPreviewSound()
            return
        }
        stopPreviewSound()

        let url: URL
        if let cached = cachedByID[remote.id], cached.audioLocalAvailable, let path = cached.audioLocalPath {
            url = URL(fileURLWithPath: path)
        } else if let remoteURLString = remote.audioCdnUrl, let remoteURL = URL(string: remoteURLString) {
            url = remoteURL
        } else {
            return
        }

        let player = AVPlayer(url: url)
        previewPlayer = player
        currentPlayingId = remote.id
        player.play()

        let remoteId = remote.id
        Task {
            for await _ in NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime, object: player.currentItem) {
                if currentPlayingId == remoteId { stopPreviewSound() }
                break
            }
        }
    }

    private func stopPreviewSound() {
        previewPlayer?.pause()
        previewPlayer = nil
        currentPlayingId = nil
    }
}

/// Port de `TrajectoryPreviewView` — trace la trajectoire de translation de chaque piste (déjà en
/// cache local uniquement, RIEN avant téléchargement, fidèle à l'original) ou un aperçu générique
/// par nombre de pistes annoncé par le serveur sinon.
private struct TrajectoryPreview: View {
    var template: MotionTemplate?
    var remoteTrackCount: Int
    var remoteHasAudio: Bool

    private static let colors: [Color] = [.green, .blue, .orange, .pink]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.05, green: 0.05, blue: 0.05)))
            for i in 1..<4 {
                let x = size.width * CGFloat(i) / 4
                let y = size.height * CGFloat(i) / 4
                context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(Color(white: 0.1)), lineWidth: 1)
                context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(Color(white: 0.1)), lineWidth: 1)
            }

            if let template, !template.tracks.isEmpty {
                drawTrajectories(context: context, size: size, template: template)
            } else {
                drawPlaceholder(context: context, size: size)
            }
        }
    }

    private func drawTrajectories(context: GraphicsContext, size: CGSize, template: MotionTemplate) {
        for (t, track) in template.tracks.enumerated() where !track.matrices.isEmpty {
            let color = Self.colors[t % Self.colors.count]
            let step = max(1, track.matrices.count / 40)
            var prev: CGPoint?
            var path = Path()

            for i in stride(from: 0, to: track.matrices.count, by: step) {
                let vals = track.matrices[i]
                guard vals.count >= 6 else { continue }
                let tx = min(max(CGFloat(vals[2]), 0.05), 0.95)
                let ty = min(max(CGFloat(vals[5]), 0.05), 0.95)
                let point = CGPoint(x: tx * size.width, y: ty * size.height)
                if let prev {
                    path.move(to: prev); path.addLine(to: point)
                } else {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)), with: .color(color))
                }
                prev = point
            }
            context.stroke(path, with: .color(color), lineWidth: 2.5)
            if let prev {
                context.fill(Path(ellipseIn: CGRect(x: prev.x - 7, y: prev.y - 7, width: 14, height: 14)), with: .color(color))
            }
        }
        drawBadgeText(context: context, size: size, text: "\(template.tracks.count) obj" + (template.hasAudio ? " 🎵" : ""))
    }

    private func drawPlaceholder(context: GraphicsContext, size: CGSize) {
        let count = max(1, min(remoteTrackCount, 4))
        for i in 0..<count {
            let color = Self.colors[i % Self.colors.count].opacity(0.25)
            let y = size.height * CGFloat(i + 1) / CGFloat(count + 1)
            context.stroke(Path { p in p.move(to: CGPoint(x: 10, y: y)); p.addLine(to: CGPoint(x: size.width - 10, y: y)) }, with: .color(color), lineWidth: 2.5)
        }
        context.draw(Text("Aperçu après téléchargement").font(.system(size: 9)).foregroundColor(Color(white: 0.27)), at: CGPoint(x: size.width / 2, y: size.height / 2))
        drawBadgeText(context: context, size: size, text: "\(remoteTrackCount) obj" + (remoteHasAudio ? " 🎵" : ""))
    }

    private func drawBadgeText(context: GraphicsContext, size: CGSize, text: String) {
        let bw: CGFloat = 50, bh: CGFloat = 14
        let rect = CGRect(x: size.width - bw - 4, y: size.height - bh - 4, width: bw, height: bh)
        context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(.black.opacity(0.8)))
        context.draw(Text(text).font(.system(size: 8)).foregroundColor(.white), at: CGPoint(x: rect.midX, y: rect.midY))
    }
}

/// Port du comportement `FlexboxLayout(wrap)` d'Android pour les badges — un simple `Layout`
/// SwiftUI (iOS 16+) qui enchaîne les sous-vues et retourne à la ligne quand la largeur disponible
/// est dépassée.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
