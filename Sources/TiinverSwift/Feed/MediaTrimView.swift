import AVFoundation
import AVKit
import SwiftUI

/// Port de `editor/MediaTrim.java` (délègue le gros du travail à `VideoTrimmerView`, composant tiers
/// non lu en détail — comportement reconstruit depuis le contrat observable de `MediaTrim.java` :
/// filmstrip + poignées début/fin, limite `setTrimeLimitMax(60000)` = 60s, callback `onVideo
/// (videoPath, isTrimmed)` → écran suivant). Recadrage réel via `AVAssetExportSession(.
/// presetPassthrough)` + `timeRange` (pas de ré-encodage complet — rapide, fidèle au flux source,
/// même stratégie qu'Android quand `isTrimmed==false` ne retouche pas le fichier).
struct MediaTrimView: View {
    let sourceURL: URL
    var onTrimmed: (URL) -> Void
    var onCancel: () -> Void

    @State private var duration: Double = 0
    @State private var startFraction: Double = 0
    @State private var endFraction: Double = 1
    @State private var startFractionAtDragBegin: Double = 0
    @State private var endFractionAtDragBegin: Double = 1
    @State private var thumbnails: [UIImage] = []
    @State private var isProcessing = false
    @State private var player: AVPlayer?

    /// Port de `videotrimmer.setTrimeLimitMax(60000)`.
    private static let maxDurationSeconds: Double = 60
    private static let minHandleSpacing: Double = 0.03

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let player {
                    VideoPlayer(player: player).frame(height: 240).background(Color.black)
                } else {
                    Color.black.frame(height: 240)
                }
                filmstrip
                HStack {
                    Text(formatted(startFraction * duration))
                    Spacer()
                    Text(formatted((endFraction - startFraction) * duration)).bold()
                    Spacer()
                    Text(formatted(endFraction * duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Recadrer la vidéo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Button("Suivant") { Task { await trim() } }
                    }
                }
            }
        }
        .task { await load() }
    }

    private var filmstrip: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width / CGFloat(max(1, thumbnails.count)))
                            .clipped()
                    }
                }
                Rectangle().fill(Color.black.opacity(0.55))
                    .frame(width: max(0, startFraction * geo.size.width))
                Rectangle().fill(Color.black.opacity(0.55))
                    .frame(width: max(0, (1 - endFraction) * geo.size.width))
                    .offset(x: endFraction * geo.size.width)
                handleView(x: startFraction * geo.size.width)
                    .gesture(dragGesture(isStart: true, width: geo.size.width))
                handleView(x: endFraction * geo.size.width)
                    .gesture(dragGesture(isStart: false, width: geo.size.width))
            }
        }
        .frame(height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func handleView(x: CGFloat) -> some View {
        Rectangle()
            .fill(Color.yellow)
            .frame(width: 14, height: 60)
            .contentShape(Rectangle())
            .offset(x: x - 7)
    }

    /// Poignées pilotées par DELTA (`value.translation`), PAS par `value.location` — `location`
    /// serait relative au petit rectangle de la poignée (14pt de large), pas à la largeur totale du
    /// filmstrip, une erreur de repère facile à commettre avec `DragGesture` sur une vue étroite.
    private func dragGesture(isStart: Bool, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if value.translation == .zero {
                    startFractionAtDragBegin = startFraction
                    endFractionAtDragBegin = endFraction
                }
                let delta = Double(value.translation.width / width)
                if isStart {
                    let maxAllowed = endFraction - Self.minHandleSpacing
                    startFraction = min(max(0, startFractionAtDragBegin + delta), max(0, maxAllowed))
                } else {
                    let minAllowed = startFraction + Self.minHandleSpacing
                    endFraction = max(min(1, endFractionAtDragBegin + delta), min(1, minAllowed))
                }
            }
    }

    private func load() async {
        let asset = AVURLAsset(url: sourceURL)
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 {
            duration = seconds
            if seconds > Self.maxDurationSeconds {
                endFraction = Self.maxDurationSeconds / seconds
            }
        }
        player = AVPlayer(url: sourceURL)
        await generateThumbnails(asset: asset)
    }

    private func generateThumbnails(asset: AVURLAsset) async {
        guard duration > 0 else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let count = 8
        var images: [UIImage] = []
        for index in 0..<count {
            let time = CMTime(seconds: duration * Double(index) / Double(count), preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                images.append(UIImage(cgImage: cgImage))
            }
        }
        thumbnails = images
    }

    /// Port du branchement `isTrimmed` de `onVideo(videoPath, isTrimmed)` — si la sélection couvre
    /// (quasiment) tout le fichier, publie l'original tel quel (pas de recadrage réel effectué côté
    /// Android non plus dans ce cas). Sinon, `AVAssetExportSession(.presetPassthrough)` — copie des
    /// échantillons sans réencodage, rapide, adapté à un simple recadrage temporel.
    private func trim() async {
        guard duration > 0, startFraction > 0.001 || endFraction < 0.999 else {
            onTrimmed(sourceURL)
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            onTrimmed(sourceURL)
            return
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startFraction * duration, preferredTimescale: 600),
            end: CMTime(seconds: endFraction * duration, preferredTimescale: 600)
        )
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously { continuation.resume() }
        }
        if exportSession.status == .completed {
            onTrimmed(outputURL)
        } else {
            onTrimmed(sourceURL)
        }
    }

    private func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
