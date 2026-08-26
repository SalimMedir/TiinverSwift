import AVFoundation
import AVKit
import SwiftUI

/// Port de `editor/MediaTrim.java` (délègue le gros du travail à `VideoTrimmerView`, composant tiers
/// non lu en détail — comportement reconstruit depuis le contrat observable de `MediaTrim.java` :
/// filmstrip + poignées début/fin, limite `setTrimeLimitMax(60000)` = 60s, callback `onVideo
/// (videoPath, isTrimmed)` → écran suivant). Republie le fichier source tel quel UNIQUEMENT quand
/// AUCUNE modification n'est demandée (ni trim temporel ni transformation) ; dans tous les autres
/// cas, ré-encode systématiquement via `AVMutableComposition`/`AVMutableVideoComposition`.
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
/// pilote maintenant ces 3 contrôles.
///
/// **Corrigé le 2026-08-20 (V3-F-124, Phase B P1)** — le chemin `AVAssetExportPresetPassthrough`
/// (imprécis, calé keyframe) qu'utilisait le correctif précédent pour "aucune transformation
/// géométrique" a été supprimé ; ce cas est désormais couvert par le même ré-encodage frame-exact
/// que tous les autres. **Affirmation FAUSSE de ce correctif, invalidée le 2026-08-25 (voir
/// ci-dessous, V5-F-037)** : "Android ne fait JAMAIS de remux/copie pour un trim temporel seul" —
/// l'analyse s'était arrêtée à `VideoTrimmerView.java` (qui ne fait qu'appeler
/// `VideoTransformer.process`) sans descendre dans `VideoTransformer.java`/`SimpleTrimmer.java`
/// pour voir le branchement interne réel.
///
/// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-037, Phase B P1-18)** — lecture
/// directe de `Utils/media/VideoTransformer.java:122-157` (`process()`) confirme un VRAI FAST PATH :
/// `needsTransform = (cropNorm != null) || (rotation != 0) || flipH` — cette condition NE TIENT PAS
/// COMPTE de `startMs`/`endMs`, donc pour l'immense majorité des trims (coupe temporelle seule,
/// sans rotation/flip/ratio), Android emprunte `SimpleTrimmer.trim()` (`SimpleTrimmer.java:26-66`,
/// `:107-127`) : remux SANS ré-encodage (<1s, aucune perte), calant le point de départ sur la
/// keyframe vidéo PRÉCÉDENTE la plus proche (`correctTimeToSyncSample`, potentiellement décalé de
/// tout un intervalle GOP, PAS frame-exact) — et ce MÊME point corrigé est appliqué À TOUTES LES
/// PISTES y compris audio (`SimpleTrimmer.java:124`, commentaire de code explicite : "c'est le
/// design voulu", garantissant vidéo/audio synchronisés au même instant redémarré — vérifié en
/// lisant le code, PAS le commentaire de tête de fichier de `SimpleTrimmer.java` lui-même, qui
/// affirme à tort/de façon obsolète que "l'audio, lui, démarre pile à startMs", contredit par le
/// code 25 lignes plus bas). Le SLOW PATH (ré-encodage OpenGL frame-exact) n'est utilisé QUE si
/// rotation≠0, flipH ou un crop est actif.
///
/// **Choix assumé pour iOS, PAS une fidélité Android (correction de la fausse affirmation
/// ci-dessus)** : reproduire fidèlement ce fast path exigerait de localiser les limites GOP/sync
/// sample réelles de l'asset source via l'introspection d'échantillons `AVAssetReader` (aucun
/// équivalent direct simple à `correctTimeToSyncSample` n'existe dans AVFoundation à haut niveau),
/// puis de synchroniser piste vidéo ET audio sur ce même point corrigé — un chantier à part entière,
/// avec un risque réel de désynchronisation audio/vidéo si mal implémenté. Le ré-encodage
/// frame-exact systématique déjà en place produit un résultat plus précis (coupe exacte au
/// timestamp demandé par l'utilisateur, jamais de contenu avant le point choisi) au prix d'un export
/// plus lent — CONSERVÉ délibérément comme compromis qualité > vitesse, documenté honnêtement ici
/// comme un écart assumé plutôt que la fausse "fidélité Android" affirmée par les 2 correctifs
/// précédents (V3-F-032/V3-F-124) sur ce fichier.
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
    /// Aspect ratio (largeur/hauteur) de la vidéo APRÈS correction d'orientation native
    /// (`preferredTransform`), AVANT toute rotation manuelle (`trimState.rotationDegrees`) —
    /// même première étape que `composeTransform`. **Ajouté le 2026-08-26
    /// (MIGRATION_PARITY_AUDIT_V5.md V5-F-038, Phase B P2)** pour l'aperçu de recadrage
    /// interactif — voir `cropOverlay`/`currentPreviewAspect`.
    @State private var orientedVideoAspect: CGFloat?
    @State private var cropCenterAtDragBegin: CGPoint = .zero
    /// **Ajouté le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-123, Phase B P0)** — voir `trim()` :
    /// tout échec réel bloque désormais l'écran avec un message, fidèle à Android
    /// (`VideoTrimmerView.startTrimWithCrop`, Toast d'erreur, `callback.onVideo()` JAMAIS appelé en
    /// cas d'échec — `MediaTrim.onError` arrête simplement le trimmer sans avancer à l'écran
    /// suivant). Avant ce correctif, `onTrimmed(sourceURL)` était appelé sur CHAQUE chemin d'échec,
    /// publiant silencieusement le fichier ORIGINAL non coupé/non transformé comme si le trim avait
    /// réussi.
    @State private var errorText: String?

    /// Port de `videotrimmer.setTrimeLimitMax(60000)`.
    private static let maxDurationSeconds: Double = 60
    private static let minHandleSpacing: Double = 0.03

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let player {
                    VideoPlayer(player: player).frame(height: 240).background(Color.black)
                        .overlay { cropOverlay }
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
        .alert(
            "Échec du recadrage",
            isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
        ) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    /// Port de `CropOverlayView` (`:1-266`, montée par `setBtnCropRatioVisibility`/`applyRatio` —
    /// visible dès qu'un ratio ≠ Libre est sélectionné, PAS seulement pendant que le menu de choix
    /// est ouvert) — **ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-038, Phase B P2)**.
    /// Assombrit la zone hors recadrage, dessine le rectangle de recadrage (taille par défaut 90%,
    /// port de `resetCropRect`) et le rend déplaçable au doigt, clampé dans `videoRect` (port de
    /// `onTouchEvent`/`moveCropRect`) — jusqu'ici entièrement absent : le recadrage vidéo était
    /// invisible et toujours centré à 100%, sans aucune interaction possible.
    @ViewBuilder
    private var cropOverlay: some View {
        if case .ratio(let w, let h) = trimState.cropRatio, w > 0, h > 0 {
            GeometryReader { geo in
                let targetRatio = CGFloat(w) / CGFloat(h)
                let videoAspect = currentPreviewAspect
                let videoRect = Self.letterboxedRect(in: geo.size, aspect: videoAspect)
                let cropSizeNorm = VideoTrimState.cropNormSize(forTargetRatio: targetRatio, videoAspect: videoAspect)
                let cropSize = CGSize(width: cropSizeNorm.width * videoRect.width, height: cropSizeNorm.height * videoRect.height)
                let cropOrigin = CGPoint(
                    x: videoRect.minX + trimState.cropCenter.x * videoRect.width - cropSize.width / 2,
                    y: videoRect.minY + trimState.cropCenter.y * videoRect.height - cropSize.height / 2
                )
                ZStack {
                    // Assombrit tout SAUF le rectangle de recadrage (règle de remplissage
                    // pair-impair : le rectangle "trou" ajouté en second annule le premier là où
                    // ils se superposent) — technique SwiftUI standard, pas de dépendance externe.
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size))
                        path.addRect(CGRect(origin: cropOrigin, size: cropSize))
                    }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: cropSize.width, height: cropSize.height)
                        .position(x: cropOrigin.x + cropSize.width / 2, y: cropOrigin.y + cropSize.height / 2)
                        .contentShape(Rectangle())
                        .gesture(
                            // Port de `onTouchEvent` — un geste ne PEUT démarrer que si le doigt
                            // touche D'ABORD à l'intérieur du rectangle de recadrage
                            // (`ACTION_DOWN: if (cropRect.contains(x,y))`) : attacher le geste
                            // directement à la forme du rectangle (`.contentShape` bornée à sa
                            // propre taille) reproduit cette contrainte nativement, sans state
                            // supplémentaire.
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if value.translation == .zero { cropCenterAtDragBegin = trimState.cropCenter }
                                    guard videoRect.width > 0, videoRect.height > 0 else { return }
                                    let dx = value.translation.width / videoRect.width
                                    let dy = value.translation.height / videoRect.height
                                    trimState.cropCenter = cropCenterAtDragBegin
                                    trimState.moveCropCenter(dx: dx, dy: dy, cropSize: cropSizeNorm)
                                }
                        )
                }
            }
            .allowsHitTesting(true)
        }
    }

    /// Aspect ratio actuellement AFFICHÉ dans l'aperçu, après la rotation manuelle
    /// (`trimState.rotationDegrees` échange largeur/hauteur à 90°/270°, même logique que l'étape 2
    /// de `composeTransform`).
    private var currentPreviewAspect: CGFloat {
        let base = orientedVideoAspect ?? 1
        return (trimState.rotationDegrees == 90 || trimState.rotationDegrees == 270) ? 1 / base : base
    }

    /// Port de `calculateVideoRect` (`CropOverlayView.java`) — rectangle vidéo réellement affiché
    /// (hors bandes noires pillarbox/letterbox) à l'intérieur d'un conteneur de taille `size`.
    private static func letterboxedRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        guard aspect > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let containerAspect = size.width / size.height
        let drawSize: CGSize
        if aspect > containerAspect {
            drawSize = CGSize(width: size.width, height: size.width / aspect)
        } else {
            drawSize = CGSize(width: size.height * aspect, height: size.height)
        }
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        return CGRect(origin: origin, size: drawSize)
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
    ///
    /// **Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-059, Phase B P1)** — seule une
    /// borne MINIMALE (`minHandleSpacing`) était appliquée ; le cadrage initial (`load()`) limite
    /// bien la sélection par défaut à `maxDurationSeconds` si la vidéo est plus longue, mais rien
    /// n'empêchait ensuite d'ÉTENDRE la sélection au-delà par glissement. Port de
    /// `ProTimelineView.handleMove` (`DRAG_LEFT_PX`/`DRAG_RIGHT_PX`, lignes 685-713) : `selMaxWidthPx`
    /// (dérivé de `setTrimeLimitMax(60000)`, `MediaTrim.java:175`) est reclampé à CHAQUE déplacement
    /// de poignée, dans les DEUX directions — si la nouvelle largeur dépasserait la limite, c'est la
    /// poignée en cours de déplacement qui est ramenée à la largeur maximale (pas un blocage dur du
    /// geste), exactement le même comportement reproduit ici via `maxWidthFraction`.
    private func dragGesture(isStart: Bool, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if value.translation == .zero {
                    startFractionAtDragBegin = startFraction
                    endFractionAtDragBegin = endFraction
                }
                let delta = Double(value.translation.width / width)
                let maxWidthFraction = duration > 0 ? min(1, Self.maxDurationSeconds / duration) : 1
                if isStart {
                    let maxAllowed = endFraction - Self.minHandleSpacing
                    startFraction = min(max(0, startFractionAtDragBegin + delta), max(0, maxAllowed))
                    if endFraction - startFraction > maxWidthFraction {
                        startFraction = endFraction - maxWidthFraction
                    }
                } else {
                    let minAllowed = startFraction + Self.minHandleSpacing
                    endFraction = max(min(1, endFractionAtDragBegin + delta), min(1, minAllowed))
                    if endFraction - startFraction > maxWidthFraction {
                        endFraction = startFraction + maxWidthFraction
                    }
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
        // Port de `calculateVideoRect` (`CropOverlayView.java`) — nécessaire à l'aperçu de
        // recadrage interactif (`cropOverlay`). Même calcul d'orientation que l'étape 1 de
        // `composeTransform` ci-dessous (mais fait une seule fois ici, pas à chaque frame rendue).
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
            let naturalSize = try? await track.load(.naturalSize),
            let preferredTransform = try? await track.load(.preferredTransform)
        {
            let oriented = naturalSize.applying(preferredTransform)
            let width = abs(oriented.width), height = abs(oriented.height)
            if height > 0 { orientedVideoAspect = width / height }
        }
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

    /// Port du branchement `isTrimmed` de `onVideo(videoPath, isTrimmed)` d'Android
    /// (`VideoTrimmerView.next.setOnClickListener`, VideoTrimmerView.java:232-257) : `if (noTrim &&
    /// noTransform) { callback.onVideo(null, false); } else { startTrimWithCrop(); }`. Publie
    /// l'original tel quel UNIQUEMENT quand AUCUNE modification n'est demandée (ni trim temporel
    /// ni transformation géométrique) — un no-op légitime, PAS un échec. **Dans TOUS les autres
    /// cas, y compris un trim purement temporel sans transformation, Android ré-encode
    /// systématiquement** (`startTrimWithCrop()` est le SEUL chemin atteignable —
    /// `startTrimWithCrop2()` confirmé par grep exhaustif à ZÉRO appelant, code mort ; voir
    /// `MIGRATION_PARITY_AUDIT_V3.md V3-F-124`, qui invalide la justification "repli rapide sans
    /// transformation" de l'ancien commentaire ici).
    ///
    /// **Corrigé le 2026-08-20 (V3-F-124, Phase B P1)** — avant ce correctif, un trim PUREMENT
    /// temporel (sans rotation/flip/ratio, le cas majoritaire) utilisait
    /// `AVAssetExportPresetPassthrough` : rapide mais calé sur le keyframe le plus proche, donc
    /// imprécis (potentiellement plusieurs secondes de décalage selon le GOP). Android ne fait
    /// JAMAIS ça — aucun chemin Android ne remux/copie pour un trim temporel seul. Le chemin
    /// passthrough a été supprimé : tout trim non-no-op ré-encode désormais via
    /// `AVMutableComposition`/`AVMutableVideoComposition` (coupe frame-exacte), fidèle à Android,
    /// même quand `trimState == VideoTrimState()` (transformation identité, orientation native
    /// uniquement — voir `composeTransform`).
    ///
    /// **Corrigé le 2026-08-20 (V3-F-123, Phase B P0)** — TOUS les chemins d'ÉCHEC RÉEL (pas le cas
    /// de no-op légitime ci-dessus) appelaient auparavant `onTrimmed(sourceURL)`, republiant
    /// SILENCIEUSEMENT le fichier original NON coupé/NON transformé comme si l'export avait
    /// réussi — à l'inverse exact du comportement Android (`VideoTrimmerView.startTrimWithCrop` :
    /// Toast d'erreur explicite, `callback.onVideo()` **JAMAIS appelé** en cas d'échec, l'utilisateur
    /// reste bloqué sur l'écran de trim). Chaque échec RÉEL affiche maintenant `errorText`
    /// (`.alert`) et RETOURNE SANS appeler `onTrimmed` — l'utilisateur reste sur cet écran (peut
    /// réessayer via "Suivant" ou annuler), fidèle à Android.
    private func trim() async {
        guard duration > 0 else {
            errorText = "Impossible de lire la durée de la vidéo — réessaie ou annule."
            return
        }
        guard trimState != VideoTrimState() || startFraction > 0.001 || endFraction < 0.999 else {
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

        // Ré-encodage systématique (port de `startTrimWithCrop()`/`VideoTransformer.process`) —
        // frame-exact, que la modification soit un trim temporel seul, une transformation
        // géométrique seule, ou les deux. `composeTransform` avec `trimState ==
        // VideoTrimState()` renvoie une transformation identité (orientation native uniquement),
        // donc ce chemin unique couvre aussi le cas "trim seul" sans branche séparée.
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            errorText = "Impossible de lire la piste vidéo — réessaie ou annule."
            return
        }
        guard let (layerTransform, renderSize) = await Self.composeTransform(track: videoTrack, state: trimState) else {
            errorText = "Impossible d'appliquer la transformation — réessaie ou annule."
            return
        }

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            errorText = "Impossible de préparer l'export — réessaie ou annule."
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
            errorText = "Impossible de préparer l'export — réessaie ou annule."
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        // Port de `Mp4Faststart.process(...)` (`VideoTrimmerView.java:710-729`, appelé après
        // chaque ré-encodage, repli sur le fichier non-optimisé si CETTE passe échoue) —
        // **ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-061, Phase B P2)**. Équivalent
        // AVFoundation natif d'une relocalisation manuelle de l'atome `moov` (pas de post-passe
        // séparée nécessaire, contrairement à Android qui réécrit le fichier après coup) — même
        // objectif : `moov` en tête de fichier pour un démarrage/seek rapide en lecture
        // progressive, pertinent pour les chemins de lecture Bunny en repli MP4 direct (pas
        // uniquement HLS).
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously { continuation.resume() }
        }
        guard exportSession.status == .completed else {
            print("MEDIA TRIM: export a échoué — \(String(describing: exportSession.error))")
            errorText = "Le recadrage a échoué — réessaie ou annule."
            return
        }
        onTrimmed(outputURL)
    }

    /// Calcule la transformation combinée (orientation native du track + rotation utilisateur +
    /// miroir + recadrage positionné par l'utilisateur vers le ratio choisi, `state.cropCenter`)
    /// et la taille de rendu finale — **ajouté le
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

        // 4. Recadrage vers le ratio choisi — calcule le rectangle de recadrage dans le cadre
        // courant, puis translate pour que ce rectangle devienne le nouveau cadre de rendu
        // (0,0)→(renderSize). Port de `showRatioMenu`/`applyRatio`/`CropOverlayView.
        // getCropNormRelativeToVideo` — **corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md
        // V5-F-038, Phase B P2)** : utilisait auparavant TOUJOURS un rectangle centré à 100% de la
        // dimension contraignante (le commentaire précédent affirmait à tort "pas de recadrage
        // libre interactif pour la vidéo côté Android" — faux, `CropOverlayView.java` lu en entier
        // confirme un vrai recadrage déplaçable, marge par défaut 90%, voir `VideoTrimState.
        // cropNormSize`/`cropCenter`). `state.cropCenter`/`cropNormSize` (déjà normalisés
        // `[0,1]×[0,1]` relatifs à `size`, exactement l'espace dans lequel `size` vit ici) donnent
        // directement le rectangle final, sans recalcul de ratio séparé.
        guard case .ratio(let w, let h) = state.cropRatio, w > 0, h > 0 else {
            return (transform, size)
        }
        let targetRatio = CGFloat(w) / CGFloat(h)
        let videoAspect = size.width / size.height
        let cropSizeNorm = VideoTrimState.cropNormSize(forTargetRatio: targetRatio, videoAspect: videoAspect)
        let cropSize = CGSize(width: cropSizeNorm.width * size.width, height: cropSizeNorm.height * size.height)
        let cropOrigin = CGPoint(
            x: state.cropCenter.x * size.width - cropSize.width / 2,
            y: state.cropCenter.y * size.height - cropSize.height / 2
        )
        transform = transform.concatenating(CGAffineTransform(translationX: -cropOrigin.x, y: -cropOrigin.y))
        return (transform, cropSize)
    }

    private func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
