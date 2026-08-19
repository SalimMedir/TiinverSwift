import AVFoundation
import AVKit
import SwiftUI

/// Port de `editor/MediaTrim.java` (délègue le gros du travail à `VideoTrimmerView`, composant tiers
/// non lu en détail — comportement reconstruit depuis le contrat observable de `MediaTrim.java` :
/// filmstrip + poignées début/fin, limite `setTrimeLimitMax(60000)` = 60s, callback `onVideo
/// (videoPath, isTrimmed)` → écran suivant). Recadrage temporel réel via `AVAssetExportSession(.
/// presetPassthrough)` + `timeRange` quand AUCUNE transformation géométrique n'est demandée (pas de
/// ré-encodage complet — rapide, fidèle au flux source, même stratégie qu'Android quand
/// `isTrimmed==false` ne retouche pas le fichier).
///
/// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-032 GALERIE-01, Phase B P0-6)** —
/// avant ce correctif, cet écran ne portait QUE le trim temporel : aucun bouton pivot/flip/ratio,
/// contrairement à `VideoTrimmerView.java` (lu en entier pour ce correctif) qui expose `btnPivot`
/// (rotation cyclique 0→90→180→270°), `btnFlip` (miroir horizontal) et `btnCropRatio`
/// (`showRatioMenu`, 5 préréglages Libre/16:9/9:16/1:1/4:3), tous RÉELLEMENT appliqués à l'export
/// via `VideoTransformer.process(params, callback)` (`VideoTrimmerView.java:670-742`, import réel
/// `com.animems.engine.Utils.media.VideoTransformer` — **vérifié directement dans le code source
/// actuel avant d'écrire ce correctif**, car le commentaire de tête de `VideoTrimState.swift`
/// affirmait à tort que ce pipeline était mort/non branché ; il est réellement importé et appelé
/// depuis l'écran de trim actif). `VideoTrimState.swift` (état pur, déjà écrit, jamais monté)
/// pilote maintenant ces 3 contrôles ; `trim()` bascule sur un export RÉELLEMENT ré-encodé
/// (`AVMutableVideoComposition`, `.presetHighestQuality` — le passthrough ne permet PAS de
/// transformation géométrique) dès qu'une rotation/un flip/un ratio non-libre est actif, exactement
/// comme `startTrimWithCrop()` (transformation réelle) vs `startTrimWithCrop2()` (repli rapide sans
/// transformation, `VideoTrimmerView.java:807-854`) côté Android — même architecture à deux chemins,
/// pas une simplification de ce portage.
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
    @State private var trimState = VideoTrimState()

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
                // Port de `btnPivot`/`btnFlip`/`btnCropRatio`→`showRatioMenu`
                // (`VideoTrimmerView.java:370-410,216-218`) — **ajouté le 2026-08-19, Phase B
                // P0-6**. `trimState` (déjà porté, `VideoTrimState.swift`) pilote maintenant
                // réellement l'export ci-dessous, pas seulement l'affichage de ces boutons.
                HStack(spacing: 24) {
                    Button {
                        trimState.cyclePivot()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "rotate.right")
                            Text(trimState.rotationDegrees == 0 ? "Pivoter" : "\(trimState.rotationDegrees)°").font(.caption2)
                        }
                    }
                    Button {
                        trimState.toggleFlip()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            Text("Miroir").font(.caption2)
                        }
                        .foregroundStyle(trimState.flippedHorizontally ? Color.accentColor : .primary)
                    }
                    Menu {
                        Button("Libre") { trimState.cropRatio = .free }
                        ForEach(VideoTrimState.presets, id: \.label) { preset in
                            Button(preset.label) { trimState.cropRatio = preset.ratio }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "crop")
                            Text(cropRatioLabel).font(.caption2)
                        }
                    }
                }
                .font(.title3)
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

    private var cropRatioLabel: String {
        switch trimState.cropRatio {
        case .free: return "Libre"
        case .ratio:
            return VideoTrimState.presets.first { $0.ratio == trimState.cropRatio }?.label ?? "Ratio"
        }
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

    /// Port du branchement `isTrimmed` de `onVideo(videoPath, isTrimmed)`, ÉTENDU le 2026-08-19
    /// (Phase B P0-6) au branchement réel `startTrimWithCrop()` (transformation) vs
    /// `startTrimWithCrop2()` (repli rapide) d'Android : si AUCUNE transformation géométrique
    /// n'est active (`trimState == VideoTrimState()`) ET que la sélection couvre (quasiment) tout
    /// le fichier, publie l'original tel quel. Si une transformation est active, TOUJOURS ré-encoder
    /// (même si le trim temporel est un no-op) — un `AVAssetExportSession` ne peut pas combiner
    /// `.presetPassthrough` avec un `videoComposition`, la transformation exige un ré-encodage
    /// complet côté Android aussi (`VideoTransformer.process`, jamais un simple remux dans ce cas).
    private func trim() async {
        let needsTransform = trimState != VideoTrimState()
        guard duration > 0 else {
            onTrimmed(sourceURL)
            return
        }
        guard needsTransform || startFraction > 0.001 || endFraction < 0.999 else {
            onTrimmed(sourceURL)
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        let asset = AVURLAsset(url: sourceURL)
        let timeRange = CMTimeRange(
            start: CMTime(seconds: startFraction * duration, preferredTimescale: 600),
            end: CMTime(seconds: endFraction * duration, preferredTimescale: 600)
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")

        guard needsTransform else {
            // Chemin rapide (port de `startTrimWithCrop2()`) — copie des échantillons sans
            // réencodage, aucune transformation géométrique à appliquer.
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                onTrimmed(sourceURL)
                return
            }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.timeRange = timeRange
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exportSession.exportAsynchronously { continuation.resume() }
            }
            onTrimmed(exportSession.status == .completed ? outputURL : sourceURL)
            return
        }

        // Chemin transformation réelle (port de `startTrimWithCrop()`/`VideoTransformer.process`) —
        // recadrage/rotation/miroir appliqués via `AVMutableVideoComposition`, PAS un simple remux.
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            onTrimmed(sourceURL)
            return
        }
        guard let (layerTransform, renderSize) = await Self.composeTransform(track: videoTrack, state: trimState) else {
            onTrimmed(sourceURL)
            return
        }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            onTrimmed(sourceURL)
            return
        }
        try? compTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
            let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        {
            try? compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
        layerInstruction.setTransform(layerTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else {
            onTrimmed(sourceURL)
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously { continuation.resume() }
        }
        if exportSession.status == .completed {
            onTrimmed(outputURL)
        } else {
            print("MEDIA TRIM: export avec transformation a échoué — \(String(describing: exportSession.error))")
            onTrimmed(sourceURL)
        }
    }

    /// Calcule la transformation combinée (orientation native du track + rotation utilisateur +
    /// miroir + recadrage centré vers le ratio choisi) et la taille de rendu finale — **ajouté le
    /// 2026-08-19, Phase B P0-6**. Port de la composition géométrique de `VideoTransformer`
    /// (`Params.rotation`/`flipH`/`cropNorm`, non lu ligne à ligne — reconstruit via l'API native
    /// `AVMutableVideoCompositionLayerInstruction.setTransform`, équivalent fonctionnel documenté
    /// dans `VideoTrimState.swift`, PAS une librairie tierce à auditer). **Nécessite une
    /// vérification sur device/simulateur réel** (rotation/recadrage géométrique jamais exécutés
    /// dans cette session, conforme à la consigne de ne pas déclencher de test Appetize) — la
    /// composition de matrices est documentée étape par étape ci-dessous pour faciliter cette
    /// vérification.
    private static func composeTransform(track: AVAssetTrack, state: VideoTrimState) async -> (transform: CGAffineTransform, renderSize: CGSize)? {
        guard let naturalSize = try? await track.load(.naturalSize),
            let preferredTransform = try? await track.load(.preferredTransform)
        else { return nil }

        // 1. Taille "debout" après la transform native du track (correction d'orientation caméra).
        let orientedSize = naturalSize.applying(preferredTransform)
        var size = CGSize(width: abs(orientedSize.width), height: abs(orientedSize.height))
        var transform = preferredTransform

        // 2. Rotation utilisateur (cycle 90°), pivot autour du CENTRE de la taille "debout" — pas
        // autour de l'origine (qui décalerait le contenu hors cadre).
        if state.rotationDegrees != 0 {
            let radians = CGFloat(state.rotationDegrees) * .pi / 180
            let cx = size.width / 2, cy = size.height / 2
            let pivotRotation = CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(CGAffineTransform(rotationAngle: radians))
                .concatenating(CGAffineTransform(translationX: cx, y: cy))
            transform = transform.concatenating(pivotRotation)
            if state.rotationDegrees == 90 || state.rotationDegrees == 270 {
                // Une rotation de 90/270° échange largeur/hauteur du cadre de rendu — la rotation
                // ci-dessus reste centrée sur l'ANCIEN centre, donc une translation de recentrage
                // vers le NOUVEAU cadre (dimensions inversées) est nécessaire.
                let newSize = CGSize(width: size.height, height: size.width)
                let recenter = CGAffineTransform(
                    translationX: (newSize.width - size.width) / 2, y: (newSize.height - size.height) / 2)
                transform = transform.concatenating(recenter)
                size = newSize
            }
        }

        // 3. Miroir horizontal, pivot autour du centre.
        if state.flippedHorizontally {
            let cx = size.width / 2
            let pivotFlip = CGAffineTransform(translationX: -cx, y: 0)
                .concatenating(CGAffineTransform(scaleX: -1, y: 1))
                .concatenating(CGAffineTransform(translationX: cx, y: 0))
            transform = transform.concatenating(pivotFlip)
        }

        // 4. Recadrage centré vers le ratio choisi — calcule le rectangle de recadrage dans le
        // cadre courant, puis translate pour que ce rectangle devienne le nouveau cadre de rendu
        // (0,0)→(renderSize). Port de `showRatioMenu`/`applyRatio` (préréglages, pas de recadrage
        // libre interactif pour la vidéo côté Android, contrairement à la photo).
        guard case .ratio(let w, let h) = state.cropRatio, w > 0, h > 0 else {
            return (transform, size)
        }
        let targetRatio = CGFloat(w) / CGFloat(h)
        let currentRatio = size.width / size.height
        let cropSize: CGSize
        let cropOrigin: CGPoint
        if currentRatio > targetRatio {
            let newWidth = size.height * targetRatio
            cropSize = CGSize(width: newWidth, height: size.height)
            cropOrigin = CGPoint(x: (size.width - newWidth) / 2, y: 0)
        } else {
            let newHeight = size.width / targetRatio
            cropSize = CGSize(width: size.width, height: newHeight)
            cropOrigin = CGPoint(x: 0, y: (size.height - newHeight) / 2)
        }
        transform = transform.concatenating(CGAffineTransform(translationX: -cropOrigin.x, y: -cropOrigin.y))
        return (transform, cropSize)
    }

    private func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
