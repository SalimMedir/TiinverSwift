import CoreGraphics
import Foundation
import QuartzCore

/// Port de `core/AnimationEngine.java` (398 lignes, lu en entier) — prépare la table de frames
/// (quel `Transform` local afficher pour chaque calque à chaque frame globale), pilote la lecture
/// (play/pause/stop), bake les keyframes en `Transform` par frame, lisse une trajectoire capturée
/// au doigt (algorithme Chaikin).
///
/// **`androidToGL_Matrix2`/le champ `glMatrix` de `Transform` NE SONT PAS portés, décision
/// assumée** — voir la note d'architecture dans `Transform.swift` : le pipeline de compositing
/// choisi ici est Core Graphics de bout en bout (aperçu ET export), confirmé par lecture de
/// `MemesView2.java` (seuls `PorterDuff.Mode.DST_IN`/`SRC_ATOP`/`CLEAR`, tous portables en
/// `CGBlendMode`). La conversion Android `Matrix` → matrice de projection OpenGL 4×4 (repère
/// [-1,1], Y inversé) n'a donc plus de destination : `Transform.cgAffineTransform` suffit
/// directement pour dessiner dans un `CGContext`. Si l'export choisit finalement un pipeline
/// Metal/MetalPetal (non exclu, juste pas prouvé nécessaire à ce stade), cette conversion sera à
/// réintroduire alors — pas oubliée, différée à une décision non encore prise.
final class AnimationEngine {
    // MARK: - Constantes

    private static let nsPerFrame: Int64 = 1_000_000_000 / 30
    private static let baseFrameIntervalMs: Double = 1000.0 / 30.0
    private static let chaikinIterations = 1

    // MARK: - État frames

    private(set) var totalFrame: Int = 0
    private(set) var totalFramesMinus1: Int = 0
    /// Lecture externe nécessaire à `AnimemesExporter` (port de `MP4Encoder.onAddFrame`, qui
    /// recalcule ces mêmes bornes — ici réutilisées directement plutôt que redupliquées).
    private(set) var startAt: [Int] = []
    private(set) var endAt: [Int] = []
    private var holdLast: [Bool] = []
    /// Port de `transformationArray[obj][frame] = indexLocalDuTransform` — `nil` si le calque
    /// n'est pas visible à cette frame (port de "continue" dans la boucle Android, qui laisse
    /// l'entrée à sa valeur par défaut `0` — reproduit ici explicitement par `nil` plutôt que par
    /// un `0` ambigu, comportement observable identique : rien n'est dessiné dans les deux cas
    /// pour ces cases, mais `nil` documente l'intention sans ambiguïté avec "frame locale 0").
    private(set) var transformationArray: [[Int?]] = []

    // MARK: - Playback

    private(set) var isPlaying = false
    var speedFactor: Int = 1
    var frameRate: Int = 30
    private var frameAccumulatorMs: Double = 0
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var lastTimestamp: CFTimeInterval?

    private var viewWidth: CGFloat = 1
    private var viewHeight: CGFloat = 1

    weak var delegate: AnimationEnginePlaybackDelegate?

    func setViewSize(width: CGFloat, height: CGFloat) {
        if width > 0 { viewWidth = width }
        if height > 0 { viewHeight = height }
    }

    // MARK: - Frame → ns

    func frameToNs(_ frame: Int) -> Int64 { Int64(frame) * Self.nsPerFrame }

    // MARK: - Prepare

    /// Port de `prepare`/`prepareFrame` — construit `transformationArray` pour tous les calques
    /// et toutes les frames, une fois, à partir des `startFrame`/`endFrame`/`holdLast` de chaque
    /// `AnimationObjectData` et de la longueur de son tableau `transforms`.
    func prepare(composer: AnimationComposer) {
        totalFrame = 0
        prepareFrame(composer: composer)
    }

    private func prepareFrame(composer: AnimationComposer) {
        let objects = composer.layers
        let n = objects.count
        guard n > 0 else { return }

        var objLen = [Int](repeating: 0, count: n)
        var objStart = [Int](repeating: 0, count: n)
        var objEndInput = [Int](repeating: -1, count: n)
        var objHold = [Bool](repeating: false, count: n)

        for i in 0..<n {
            let obj = objects[i]
            objLen[i] = obj.transforms.count
            objStart[i] = max(0, obj.startFrame)
            objEndInput[i] = obj.endFrame
            objHold[i] = obj.holdLast
        }

        var provisionalMaxEnd = 0
        for i in 0..<n {
            let s = objStart[i], l = objLen[i]
            provisionalMaxEnd = max(provisionalMaxEnd, l > 0 ? s + l - 1 : s)
        }

        var explicitMaxEnd = 0
        var hasExplicit = false
        for e in objEndInput where e >= 0 {
            explicitMaxEnd = max(explicitMaxEnd, e)
            hasExplicit = true
        }

        totalFramesMinus1 = hasExplicit ? max(explicitMaxEnd, provisionalMaxEnd) : provisionalMaxEnd
        guard totalFramesMinus1 >= 0 else { return }

        var objEnd = [Int](repeating: 0, count: n)
        startAt = [Int](repeating: 0, count: n)
        endAt = [Int](repeating: 0, count: n)
        holdLast = [Bool](repeating: false, count: n)
        for i in 0..<n {
            var e = objEndInput[i]
            if e < 0 { e = totalFramesMinus1 }
            if e < objStart[i] { e = objStart[i] }
            if objHold[i] { e = totalFramesMinus1 }
            objEnd[i] = e
            startAt[i] = objStart[i]
            endAt[i] = objEnd[i]
            holdLast[i] = objHold[i]
        }

        transformationArray = Array(repeating: Array(repeating: nil, count: totalFramesMinus1 + 1), count: n)
        for f in 0...totalFramesMinus1 {
            renderSceneIntoTableInternal(objects: objects, objLen: objLen, objStart: objStart, objEnd: objEnd, objHold: objHold, frame: f)
        }
    }

    private func renderSceneIntoTableInternal(objects: [AnimationObjectData], objLen: [Int], objStart: [Int], objEnd: [Int], objHold: [Bool], frame f: Int) {
        for iObj in 0..<objects.count {
            let l = objLen[iObj]
            guard l > 0 else { continue }
            let s = objStart[iObj], e = objEnd[iObj]
            guard f >= s, f <= e else { continue }
            var local = f - s
            if local >= l {
                guard objHold[iObj] else { continue }
                local = l - 1
            }
            if f <= totalFramesMinus1 { transformationArray[iObj][f] = local }
        }
    }

    // MARK: - Seek / play / pause / stop

    func seek(to frame: Int) { totalFrame = frame }

    func play(composer: AnimationComposer, layer: Int) {
        guard !composer.layers.isEmpty else { return }
        startPlayback(composer: composer, layer: layer)
    }

    func pause() {
        guard isPlaying else { return }
        stopDisplayLink()
        isPlaying = false
        delegate?.animationEngineDidPause(self)
    }

    func stop() {
        totalFrame = 0
        if displayLink != nil {
            stopDisplayLink()
            delegate?.animationEngineDidEnd(self)
        }
    }

    private func startPlayback(composer: AnimationComposer, layer: Int) {
        stopDisplayLink()
        lastTimestamp = nil
        frameAccumulatorMs = 0

        let proxy = DisplayLinkProxy { [weak self] timestamp in
            self?.tick(composer: composer, layer: layer, timestamp: timestamp)
        }
        displayLinkProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        lastTimestamp = nil
    }

    /// Port du `TimeListener` de `startAnimatorTime` — `deltaTime` Android (ms depuis le dernier
    /// tick) reconstitué ici depuis les horodatages `CADisplayLink` successifs (`CFTimeInterval`,
    /// secondes).
    private func tick(composer: AnimationComposer, layer: Int, timestamp: CFTimeInterval) {
        guard layer >= 0, layer < composer.layers.count else { return }
        let transforms = composer.layers[layer].transforms
        guard !transforms.isEmpty else { return }

        let deltaMs: Double
        if let last = lastTimestamp {
            deltaMs = (timestamp - last) * 1000
        } else {
            deltaMs = 0
        }
        lastTimestamp = timestamp

        let frameInterval = Self.baseFrameIntervalMs / Double(max(speedFactor, 1))
        frameAccumulatorMs += deltaMs

        while frameAccumulatorMs >= frameInterval {
            frameAccumulatorMs -= frameInterval
            if totalFrame < totalFramesMinus1 {
                delegate?.animationEngine(self, didPlayFrame: totalFrame)
                isPlaying = true
                delegate?.animationEngineDidInvalidate(self)

                for obj in composer.layers { obj.advanceBitmapFrame(deltaMs: Int64(frameInterval)) }
                totalFrame += 1
            } else {
                delegate?.animationEngineDidEnd(self)
                stopDisplayLink()
                totalFrame = 0
                isPlaying = false
                break
            }
        }
    }

    // MARK: - Interpolation / bake

    /// Port de `applyInterpolation` — bake les pistes de keyframes visuelles ET matricielles en
    /// `Transform` par frame pour chaque calque.
    func applyInterpolation(composer: AnimationComposer) {
        for obj in composer.layers {
            obj.bakeKeyframesToTransforms(frameRate: frameRate)
            if obj.hasTransformKeyframes { bakeMatrixKeyframesToTransforms(obj) }
        }
    }

    /// Port de `applyInterpolation2` — variante sans le bake matriciel.
    func applyInterpolation2(composer: AnimationComposer) {
        for obj in composer.layers { obj.bakeKeyframesToTransforms(frameRate: frameRate) }
    }

    /// Port de `bakeTransformKeyframesToGL`, SANS l'étape de conversion GL finale (voir note
    /// d'architecture en tête de fichier) — agrandit `obj.transforms` jusqu'à la dernière frame
    /// keyframée si besoin, puis écrit les valeurs de matrice interpolées dans chaque `Transform`.
    private func bakeMatrixKeyframesToTransforms(_ obj: AnimationObjectData) {
        guard viewWidth > 0, viewHeight > 0 else { return }
        let nsPerFrame = Int64(1_000_000_000) / Int64(frameRate)
        let totalFramesNeeded = computeTotalFramesNeeded(obj)
        guard totalFramesNeeded > 0 else { return }

        let savedLastValues = obj.transforms.last?.matrixValues

        while obj.transforms.count < totalFramesNeeded {
            var t = Transform()
            t.frameIndex = obj.transforms.count
            if let last = obj.transforms.last {
                t.opacity = last.opacity
                t.color = last.color
                t.cornerRadius = last.cornerRadius
                t.feather = last.feather
            }
            obj.transforms.append(t)
        }

        let lastIndex = obj.transforms.count - 1
        for f in 0..<lastIndex {
            let ns = Int64(f) * nsPerFrame
            guard let interpolated = obj.interpolatedMatrixValues(at: ns) else { continue }
            obj.transforms[f].matrixValues = interpolated
        }

        if let savedLastValues, !obj.transforms.isEmpty {
            obj.transforms[lastIndex].matrixValues = savedLastValues
        }
    }

    private func computeTotalFramesNeeded(_ obj: AnimationObjectData) -> Int {
        guard let track = obj.keyframeTrack(KeyframeTrack.PropertyName.matrix), !track.isEmpty else { return 0 }
        let nsPerFrame = Int64(1_000_000_000) / Int64(frameRate)
        guard let lastNs = track.keyframes.last?.timestampNs else { return 0 }
        return Int(lastNs / nsPerFrame) + 1
    }

    // MARK: - Smooth transforms — algorithme Chaikin

    /// Port de `smoothObjectTransforms` — lisse la trajectoire matricielle capturée (moyenne
    /// pondérée 1-2-1 glissante), sans l'étape de conversion GL (voir note d'architecture).
    func smoothObjectTransforms(_ obj: AnimationObjectData) {
        let list = obj.transforms
        guard list.count >= 3 else { return }

        let original = list.map(\.matrixValues)

        for i in 1..<(list.count - 1) {
            let a = original[i - 1], b = original[i], c = original[i + 1]
            var out = [Float](repeating: 0, count: 9)
            for k in 0..<9 { out[k] = (a[k] + b[k] * 2 + c[k]) / 4 }
            obj.transforms[i].matrixValues = out
        }
    }

    // MARK: - Chaikin — lissage de points

    /// Port de `chaikin(ArrayList<PointF>)`.
    func chaikin(_ input: [CGPoint]) -> [CGPoint] {
        var pts = input
        for _ in 0..<Self.chaikinIterations {
            guard pts.count >= 2 else { return pts }
            var out: [CGPoint] = [pts[0]]
            for i in 0..<(pts.count - 1) {
                let p0 = pts[i], p1 = pts[i + 1]
                out.append(CGPoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y))
                out.append(CGPoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y))
            }
            out.append(pts[pts.count - 1])
            pts = out
        }
        return pts
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Port de `AnimationEngine.PlaybackListener`.
protocol AnimationEnginePlaybackDelegate: AnyObject {
    func animationEngine(_ engine: AnimationEngine, didPlayFrame frame: Int)
    func animationEngineDidPause(_ engine: AnimationEngine)
    func animationEngineDidEnd(_ engine: AnimationEngine)
    func animationEngineDidInvalidate(_ engine: AnimationEngine)
}

/// `CADisplayLink` exige une cible Objective-C (`target:selector:`) — pas d'initialiseur à
/// fermeture native. Ce proxy privé relaie vers une closure Swift, évitant de rendre
/// `AnimationEngine` lui-même héritier de `NSObject` juste pour ce besoin.
private final class DisplayLinkProxy: NSObject {
    private let onTick: (CFTimeInterval) -> Void

    init(onTick: @escaping (CFTimeInterval) -> Void) {
        self.onTick = onTick
    }

    @objc func tick(_ link: CADisplayLink) {
        onTick(link.timestamp)
    }
}
