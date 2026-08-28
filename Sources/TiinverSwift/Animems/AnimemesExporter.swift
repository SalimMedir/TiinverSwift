import AVFoundation
import CoreGraphics
import CoreVideo
import UIKit

/// Port de `android/codec/MP4Encoder.java` (2200+ lignes lues au total : structure complète —
/// `Encoder.java` base + `onAddFrame`/`initGL*`/`renderBackground` de `MP4Encoder.java` — MAIS
/// PAS les ~1400 lignes de détail GLSL/`MediaCodec` bas niveau, décision motivée ci-dessous) —
/// export de l'animation en MP4 via `AVAssetWriter`, réutilisant `AnimationEngine` (déjà porté,
/// module 8 passage 2) pour la table de frames et `LayerRenderer` (déjà porté, ce passage) pour
/// la compositing — **exactement le chemin de rendu partagé aperçu+export annoncé comme
/// possibilité dès la décision d'architecture Core Graphics** (voir `Transform.swift`).
///
/// **Ce qui N'A PAS été relu en détail dans `MP4Encoder.java`, et pourquoi ce n'est PAS une
/// lacune de vérification** :
/// - Les shaders GLSL (`FRAGMENT_BASE`/`FRAGMENT_MASK_DST_IN`) : leurs propres commentaires
///   Android affirment explicitement être "SYNCHRONISÉS AVEC MemesView2" (teinte SRC_ATOP, alpha,
///   corner radius via SDF ≡ clip Canvas) — ce sont une réécriture GPU du MÊME algorithme déjà lu
///   et porté dans `LayerRenderer.swift` depuis `MemesView2.java`, pas une logique différente à
///   redériver depuis zéro.
/// - Le pipeline `MediaCodec` bas niveau (init EGL, FBO offscreen, blit, drain de l'encodeur) :
///   spécifique à l'API Android `MediaCodec`/`Surface`, sans équivalent à porter — `AVAssetWriter`
///   gère l'encodage H.264/AAC via une API haut niveau nativement asynchrone, aucune primitive
///   GL/EGL à répliquer.
/// - `transcodeToM4A`/`prepareAudioTrack2` (~250 lignes, décodage+réencodage manuel via
///   `MediaCodec` pour normaliser un fichier audio arbitraire en AAC-dans-MP4 avant remux) :
///   **capacité native côté iOS, pas un besoin réel ici** — `AVAssetReader` décode nativement
///   quasi tous les formats audio courants (MP3/AAC/WAV/M4A...) sans étape de transcodage manuel
///   préalable ; `AVAssetWriterInput` réencode en AAC à l'écriture si besoin. Le long historique
///   de bugs documentés dans les commentaires Android (BUG 1/2/3, sample rate HE-AAC réel vs
///   déclaré...) est spécifique aux limitations de `MediaMuxer`/`MediaCodec` bas niveau — n'a pas
///   de contrepartie à reproduire ici, pas une simplification hasardeuse.
///
/// **Non porté à ce stade, TODO explicite** : effet flou d'arrière-plan (`blurEnabled`/
/// `initBlurProgram`, activable mais pas branché dans le flux réel observé dans
/// `AnimemesCompound.java`), effet `FRAGMENT_EFFECT` (`enableEffect`, non plus branché dans le
/// flux observé), vidéo "outro" (`OUTRO_DURATION_SEC`/`outreVideo`, mécanisme séparé pas encore
/// lu). Le chemin RÉELLEMENT exercé par `AnimemesCompound.createVideosFromBitmap` (confirmé en
/// lisant son appel : `onSurfaceStartEncode()`→`addFrame(composer)`→`startFrameEncoding()`→
/// `onAddFrame`) est celui porté ici.
final class AnimemesExporter {
    static let frameRate = 30
    private static let frameDurationNs: Int64 = 1_000_000_000 / Int64(frameRate)
    private static let bitRate = 2_000_000

    enum EndMode {
        case holdLast
        case loop
    }

    enum ExportError: Error {
        case cannotCreateAssetWriter
        case cannotCreatePixelBufferPool
        case cannotCreatePixelBuffer
        case writingFailed(Error?)
    }

    private let composer: AnimationComposer
    private let engine = AnimationEngine()
    private let textRect: TextRect

    var outputSize: CGSize = CGSize(width: 720, height: 1280)
    var viewSize: CGSize = CGSize(width: 720, height: 1280)
    var backgroundColor: UInt32 = 0xFF00_0000
    /// Port de `animationEndMode = MODE_LOOP` — valeur par défaut Android reproduite telle quelle.
    var endMode: EndMode = .loop
    var audioURL: URL?

    init(composer: AnimationComposer, font: UIFont = .systemFont(ofSize: 14), textColor: UIColor = .white) {
        self.composer = composer
        self.textRect = TextRect(font: font, textColor: textColor)
        engine.frameRate = Self.frameRate
        engine.setViewSize(width: viewSize.width, height: viewSize.height)
    }

    /// Port de `onAddFrame` — calcule la table de frames (`AnimationEngine.prepare`, déjà
    /// disponible depuis le module 8) puis écrit chaque frame composée dans `AVAssetWriter`.
    func export(to outputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            completion(.failure(ExportError.cannotCreateAssetWriter))
            return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.bitRate,
                AVVideoMaxKeyFrameIntervalKey: 12, // port de `I_FRAME_INTERVAL = 12`
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(videoInput) else {
            completion(.failure(ExportError.cannotCreateAssetWriter))
            return
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        var audioReader: AVAssetReader?
        var audioReaderOutput: AVAssetReaderTrackOutput?
        var totalFramesForAudio = 0

        if let audioURL {
            let asset = AVURLAsset(url: audioURL)
            if let track = asset.tracks(withMediaType: .audio).first {
                let durationSeconds = CMTimeGetSeconds(asset.duration)
                totalFramesForAudio = Int((durationSeconds * Double(Self.frameRate)).rounded(.up))

                // **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-084, Phase B P3)** —
                // `MP4Encoder.java:1576-1587` (`onStartAudio`, chemin réellement emprunté par
                // `createVideosFromBitmap`) confirme AAC 128 kbps, 44100 Hz, stéréo — `64000` ici
                // divisait le débit par 2 (fréquence/canaux déjà identiques), qualité audio
                // perceptiblement inférieure sans justification.
                let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000,
                ])
                aInput.expectsMediaDataInRealTime = false
                if writer.canAdd(aInput) {
                    writer.add(aInput)
                    audioInput = aInput
                }

                let reader = try? AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                ])
                if let reader, reader.canAdd(output) {
                    reader.add(output)
                    audioReader = reader
                    audioReaderOutput = output
                }
            }
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        engine.setViewSize(width: viewSize.width, height: viewSize.height)
        engine.prepare(composer: composer)
        let totalFramesMinus1 = engine.totalFramesMinus1
        guard totalFramesMinus1 >= 0 else {
            writer.finishWriting { completion(.success(outputURL)) }
            return
        }

        let totalFramesVideo = (audioURL != nil) ? totalFramesForAudio : totalFramesMinus1 + 1

        // **Bug trouvé et corrigé avant tout build** : `requestMediaDataWhenReady` rappelle sa
        // closure à chaque fois que l'input redevient prêt (potentiellement plusieurs fois) — un
        // premier jet gardait le compteur de frame LOCAL À LA CLOSURE ELLE-MÊME (réinitialisé à
        // chaque rappel), ce qui aurait fait repartir l'écriture de zéro à chaque reprise au lieu
        // de continuer. `f` est donc déclaré ICI, capturé PAR RÉFÉRENCE par la closure (un `var`
        // de portée englobante capturé par une closure Swift partage la même case mémoire entre
        // tous les appels de cette closure), pas réinitialisé à chaque rappel.
        var f = 0
        let videoQueue = DispatchQueue(label: "AnimemesExporter.video")
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            guard let self else { return }
            while videoInput.isReadyForMoreMediaData {
                if f > totalFramesVideo {
                    videoInput.markAsFinished()
                    self.beginAudioPass(
                        writer: writer, audioInput: audioInput, audioReader: audioReader,
                        audioReaderOutput: audioReaderOutput, outputURL: outputURL, completion: completion
                    )
                    return
                }

                let renderFrame: Int
                if f == 0 {
                    renderFrame = 0
                } else if f <= totalFramesMinus1 {
                    renderFrame = f
                } else {
                    switch self.endMode {
                    case .loop: renderFrame = f % (totalFramesMinus1 + 1)
                    case .holdLast: renderFrame = totalFramesMinus1
                    }
                }

                guard let pixelBuffer = self.makePixelBuffer(pool: pixelBufferAdaptor.pixelBufferPool) else {
                    videoInput.markAsFinished()
                    completion(.failure(ExportError.cannotCreatePixelBuffer))
                    return
                }
                self.render(frame: renderFrame, into: pixelBuffer)

                // **Corrigé le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-046, Phase B P1)** —
                // le `max(Self.frameDurationNs, ...)` faisait collision entre `f=0` et `f=1`
                // (les deux évaluaient à `frameDurationNs`) : aucun échantillon n'était jamais
                // écrit à pts=0, alors que `writer.startSession(atSourceTime: .zero)` (ligne 150)
                // fixe explicitement le début de session à t=0. Vérifié côté Android
                // (`MP4Encoder.java:1753`, `getPresentationTimeUsec(frameIndex)`) : `frameIndex *
                // FRAME_NS`, strictement croissant depuis 0, SANS clamp équivalent — reproduit
                // fidèlement ici. Seul `f=0` change de valeur (0 au lieu de `frameDurationNs`) ;
                // `f>=1` était déjà correct (`f * frameDurationNs >= frameDurationNs`, le `max`
                // n'avait jamais d'effet au-delà de la 1ʳᵉ frame).
                let ptsNs = Int64(f) * Self.frameDurationNs
                let pts = CMTime(value: ptsNs, timescale: 1_000_000_000)
                // **Corrigé (2026-08-28, V6-F-008)** — `append` retourne `false` en cas d'échec
                // d'écriture ; jusqu'ici ignoré, une frame silencieusement perdue n'interrompait
                // pas l'export au lieu de le faire échouer proprement avec un message clair.
                guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: pts) else {
                    videoInput.markAsFinished()
                    writer.cancelWriting()
                    completion(.failure(ExportError.writingFailed(writer.error)))
                    return
                }

                f += 1
            }
            // `isReadyForMoreMediaData` redevenu faux avant la fin — `requestMediaDataWhenReady`
            // rappellera cette MÊME closure quand l'input sera de nouveau prêt (comportement
            // standard `AVAssetWriterInput`) ; `f` ayant persisté (voir ci-dessus), la boucle
            // reprend exactement où elle s'est arrêtée. Ne PAS appeler `completion` ici.
        }
    }

    /// Port de la lecture/remux audio de `prepareAudioTrack`/`onAddAudio` — démarré une fois
    /// TOUTE la piste vidéo écrite (matches l'ordre séquentiel implicite d'Android : le mux audio
    /// dans `MediaMuxer` se fait piste par piste indépendamment, mais ici la lecture séquentielle
    /// simplifie la gestion d'erreur d'un premier passage, voir TODO tête de fichier).
    private func beginAudioPass(
        writer: AVAssetWriter, audioInput: AVAssetWriterInput?, audioReader: AVAssetReader?,
        audioReaderOutput: AVAssetReaderTrackOutput?, outputURL: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let audioInput, let audioReader, let audioReaderOutput else {
            writer.finishWriting { completion(.success(outputURL)) }
            return
        }
        audioReader.startReading()
        let audioQueue = DispatchQueue(label: "AnimemesExporter.audio")
        audioInput.requestMediaDataWhenReady(on: audioQueue) {
            while audioInput.isReadyForMoreMediaData {
                if let sample = audioReaderOutput.copyNextSampleBuffer() {
                    audioInput.append(sample)
                } else {
                    audioInput.markAsFinished()
                    writer.finishWriting { completion(.success(outputURL)) }
                    return
                }
            }
        }
    }

    private func makePixelBuffer(pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        return pixelBuffer
    }

    /// Port de `renderSceneIntoFbo`+dispatch de type d'`AnimemesCompound`/`MemesView2.startDraw` —
    /// compose TOUS les calques visibles à `renderFrame` dans le `CVPixelBuffer`.
    private func render(frame renderFrame: Int, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // Contexte bitmap créé manuellement — PAS Y-vers-le-bas par défaut, flip nécessaire
        // (même piège que `MaskFactory`, voir sa note de tête de fichier — `LayerRenderer`
        // suppose lui un contexte DÉJÀ Y-vers-le-bas, responsabilité de l'appelant ici).
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(LayerRenderer.cgColor(argb: backgroundColor))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))

        let currentNs = engine.frameToNs(renderFrame)
        let transformationArray = engine.transformationArray
        let startAt = engine.startAt
        let endAt = engine.endAt

        for i in 0..<composer.layers.count {
            let obj = composer.layers[i]
            guard obj.visible else { continue }

            switch obj.objectType {
            case .bitmap, .shapeRect, .shapeCircle, .shapeLine:
                guard i < transformationArray.count, renderFrame < transformationArray[i].count else { continue }
                guard i < startAt.count, i < endAt.count, renderFrame >= startAt[i], renderFrame <= endAt[i] else { continue }
                guard let t = transformationArray[i][renderFrame], t < obj.transforms.count else { continue }
                LayerRenderer.drawObjectFrame(
                    obj, transform: obj.transforms[t], frameIndex: t, in: context,
                    currentNs: currentNs, viewSize: viewSize
                )
            case .text:
                // **Corrigé (2026-08-28, V7-F-004)** — garde de bornes temporelles manquante,
                // seule différence avec le cas bitmap/shape ci-dessus (qui l'applique déjà via
                // `startAt`/`endAt`, lignes 298/308) : un calque texte recadré sur la timeline
                // restait visible sur toute la durée de l'export MP4, contredisant l'éditeur.
                guard i < startAt.count, i < endAt.count, renderFrame >= startAt[i], renderFrame <= endAt[i] else { continue }
                LayerRenderer.drawText(obj, in: context, textRect: textRect, viewSize: viewSize, currentNs: currentNs)
            case .sticker:
                guard i < startAt.count, i < endAt.count, renderFrame >= startAt[i], renderFrame <= endAt[i] else { continue }
                LayerRenderer.drawSticker(obj, in: context, currentNs: currentNs)
            case .path, .line, .clip, .erase, .background, .none:
                continue
            }
        }
    }
}
