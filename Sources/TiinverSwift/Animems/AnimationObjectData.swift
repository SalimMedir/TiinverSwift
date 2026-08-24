import CoreGraphics
import Foundation

/// Port de `core/AnimationObjectData.java` (618 lignes, lu en entier) — l'objet "calque" central
/// du moteur Animems : bitmap/texte/forme/masque, une piste de keyframes par propriété animée, un
/// tableau de `Transform` par frame (rempli par capture de geste), bitmaps/textures avec
/// horodatages (GIF/texture animée).
///
/// `final class` (référence), PAS un `struct` comme `Keyframe`/`KeyframeTrack` : contrairement à
/// ceux-ci, cet objet est mutable par de très nombreux appelants qui s'attendent à muter
/// l'instance PARTAGÉE dans `AnimationComposer.layers` (ex. `obj.setVisible(false)` doit être vu
/// par tout code détenant une référence au même calque) — fidèle à la sémantique de référence de
/// la classe Java d'origine, pas un choix arbitraire.
final class AnimationObjectData {
    /// Port de `AnimationObjectData.Type` — 11 cas, noms Android VÉRIFIÉS un à un contre la
    /// déclaration réelle (`core/AnimationObjectData.java:21-23`), pas seulement déduits de
    /// l'usage. `androidName`/`init(androidName:)` nécessaires pour `SerializableAnimationObject`
    /// (sérialisation round-trip, doit produire/lire exactement les mêmes chaînes que
    /// `Type.valueOf(String)`/`Type.name()` côté Android).
    enum ObjectType: String {
        case bitmap = "BITMAP"
        case erase = "ERASE"
        case text = "TEXT"
        case path = "PATH"
        case line = "LINE"
        case clip = "CLIP"
        case sticker = "STICKER"
        case background = "BACKGROUND"
        case shapeRect = "SHAPE_RECT"
        case shapeCircle = "SHAPE_CIRCLE"
        case shapeLine = "SHAPE_LINE"
    }

    // MARK: - Masque — propriétés statiques

    var appliedMaskType: MaskType?
    var maskInverted: Bool = false

    private var _maskFeather: Float = 0
    var maskFeather: Float {
        get { _maskFeather }
        set { _maskFeather = max(0, min(1, newValue)) }
    }

    private var _maskOffsetX: Float = 0
    var maskOffsetX: Float {
        get { _maskOffsetX }
        set { _maskOffsetX = max(-2, min(2, newValue)) }
    }

    private var _maskOffsetY: Float = 0
    var maskOffsetY: Float {
        get { _maskOffsetY }
        set { _maskOffsetY = max(-2, min(2, newValue)) }
    }

    private var _maskScale: Float = 1
    var maskScale: Float {
        get { _maskScale }
        set { _maskScale = max(0.1, min(5, newValue)) }
    }

    private var _maskMirrorGap: Float = 0.06
    var maskMirrorGap: Float {
        get { _maskMirrorGap }
        set { _maskMirrorGap = max(0, min(0.5, newValue)) }
    }

    private var _maskRotation: Float = 0
    var maskRotation: Float {
        get { _maskRotation }
        set { _maskRotation = newValue.truncatingRemainder(dividingBy: 360) }
    }

    var hasAppliedMask: Bool { appliedMaskType != nil }

    // MARK: - Mask auto frames (mode isOnAutoMode)

    /// Port de `maskTransforms` — stockage direct par index, prioritaire sur les `KeyframeTrack`
    /// au rendu si non vide. **Confirmé implémenté le 2026-08-19** (ANIMEMS_PARITY_AUDIT_V1.md
    /// F-13) — `LayerRenderer.drawLastTransform`/`drawObjectFrame` (`LayerRenderer.swift:79-88`/
    /// `:169-177`) branchent bien sur `obj.hasMaskTransforms` en priorité avant de retomber sur
    /// l'interpolation `KeyframeTrack`. Ce commentaire indiquait auparavant ce comportement comme
    /// "pas encore écrit" — obsolète, corrigé.
    private(set) var maskTransforms: [Transform] = []

    func addMaskTransform(_ t: Transform) { maskTransforms.append(t) }
    func clearMaskTransforms() { maskTransforms.removeAll() }
    var hasMaskTransforms: Bool { !maskTransforms.isEmpty }

    /// Port de `getMaskTransformAt` — `holdLast` : si l'index dépasse la liste, retourne le
    /// dernier élément.
    func maskTransform(at index: Int) -> Transform? {
        guard !maskTransforms.isEmpty else { return nil }
        return maskTransforms[min(index, maskTransforms.count - 1)]
    }

    // MARK: - Keyframe system

    private(set) var keyframeTracks: [String: KeyframeTrack] = [:]

    @discardableResult
    func getOrCreateTrack(_ propertyName: String) -> KeyframeTrack {
        if let existing = keyframeTracks[propertyName] { return existing }
        let track = KeyframeTrack(propertyName: propertyName)
        keyframeTracks[propertyName] = track
        return track
    }

    /// Nommé `keyframeTrack` plutôt que `track` — collision réelle évitée avec le champ `track`
    /// (`Int`, index de calque/plan, port de `AnimationObjectData.track` Android) : Swift ne
    /// permet pas de résoudre `obj.track(x)` entre une propriété stockée `track: Int` et une
    /// méthode `track(_:)` du même nom (contrairement à un chevauchement légitime propriété/
    /// méthode avec arguments différents ailleurs), `Int` n'étant pas "appelable" — corrigé avant
    /// tout build, relecture propre du fichier venant d'être écrit.
    func keyframeTrack(_ propertyName: String) -> KeyframeTrack? { keyframeTracks[propertyName] }
    func removeTrack(_ propertyName: String) { keyframeTracks.removeValue(forKey: propertyName) }
    var hasKeyframes: Bool { keyframeTracks.values.contains { !$0.isEmpty } }

    /// Port de `KeyframeTrack.removeKeyframe(id)` + `if (track.isEmpty()) obj.removeTrack(
    /// propertyName)` (`AnimemesCompound.onKeyframeDeleteRequested`, `AnimemesCompound.java:
    /// 1360-1371`) — **ajouté le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-049, Phase B P1)**.
    @discardableResult
    func removeKeyframe(propertyName: String, keyframeId: String) -> Bool {
        guard var track = keyframeTracks[propertyName] else { return false }
        guard track.removeKeyframe(id: keyframeId) else { return false }
        if track.isEmpty {
            keyframeTracks.removeValue(forKey: propertyName)
        } else {
            keyframeTracks[propertyName] = track
        }
        return true
    }

    /// Port de `getKeyframeTracks().clear()` (appelé par `MotionTemplateManager.apply` avant de
    /// réappliquer les keyframes d'un modèle) — pas un besoin apparu ailleurs jusqu'ici.
    func clearAllKeyframes() { keyframeTracks.removeAll() }

    private func addKeyframe(_ propertyName: String, timestampNs: Int64, value: [Float]) {
        var track = getOrCreateTrack(propertyName)
        track.addKeyframe(timestampNs: timestampNs, value: value)
        keyframeTracks[propertyName] = track
    }

    // ── Keyframes visuels ────────────────────────────────────────────────

    func addOpacityKeyframe(ts: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.opacity, timestampNs: ts, value: Keyframe.scalarValue(v)) }
    func addColorKeyframe(ts: Int64, argb: UInt32) { addKeyframe(KeyframeTrack.PropertyName.color, timestampNs: ts, value: Keyframe.colorValue(argb: argb)) }
    func addCornerRadiusKeyframe(ts: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.cornerRadius, timestampNs: ts, value: Keyframe.scalarValue(v)) }
    func addFeatherKeyframe(ts: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.feather, timestampNs: ts, value: Keyframe.scalarValue(v)) }

    func interpolatedOpacity(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.opacity), !t.isEmpty, let v = t.getValue(at: ns) else { return shapeOpacity }
        return max(0, min(1, v[0]))
    }
    func interpolatedColor(at ns: Int64) -> UInt32 {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.color), !t.isEmpty, let v = t.getValue(at: ns) else { return shapeColor }
        return Keyframe.floatArrayToArgb(v)
    }
    func interpolatedCornerRadius(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.cornerRadius), !t.isEmpty, let v = t.getValue(at: ns) else { return shapeCornerRadius }
        return max(0, v[0])
    }
    func interpolatedFeather(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.feather), !t.isEmpty, let v = t.getValue(at: ns) else { return maskFeather }
        return max(0, min(1, v[0]))
    }

    // ── Keyframes mask manuels ───────────────────────────────────────────

    func addMaskOffsetXKeyframe(ts: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.maskOffsetX, timestampNs: ts, value: Keyframe.scalarValue(v)) }
    func addMaskOffsetYKeyframe(ts: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.maskOffsetY, timestampNs: ts, value: Keyframe.scalarValue(v)) }
    func addMaskScaleKeyframe(ts: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.maskScale, timestampNs: ts, value: Keyframe.scalarValue(v)) }
    func addMaskMirrorGapKeyframe(ts: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.maskMirrorGap, timestampNs: ts, value: Keyframe.scalarValue(v)) }
    func addMaskRotationKeyframe(ts: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.maskRotation, timestampNs: ts, value: Keyframe.scalarValue(v)) }

    func interpolatedMaskOffsetX(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.maskOffsetX), !t.isEmpty, let v = t.getValue(at: ns) else { return maskOffsetX }
        return max(-2, min(2, v[0]))
    }
    func interpolatedMaskOffsetY(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.maskOffsetY), !t.isEmpty, let v = t.getValue(at: ns) else { return maskOffsetY }
        return max(-2, min(2, v[0]))
    }
    func interpolatedMaskScale(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.maskScale), !t.isEmpty, let v = t.getValue(at: ns) else { return maskScale }
        return max(0.1, min(5, v[0]))
    }
    func interpolatedMaskMirrorGap(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.maskMirrorGap), !t.isEmpty, let v = t.getValue(at: ns) else { return maskMirrorGap }
        return max(0, min(0.5, v[0]))
    }
    func interpolatedMaskRotation(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.maskRotation), !t.isEmpty, let v = t.getValue(at: ns) else { return maskRotation }
        return v[0]
    }

    // ── Keyframes transform (matrice) ────────────────────────────────────

    func addMatrixKeyframe(ts: Int64, matrixValues: [Float]) {
        guard matrixValues.count >= 9 else { return }
        addKeyframe(KeyframeTrack.PropertyName.matrix, timestampNs: ts, value: matrixValues)
    }

    /// Retourne `true` si des bitmaps valides sont présents (port de `hasValidBitmaps`, adapté :
    /// `CGImage` n'a pas d'équivalent `isRecycled()` — la présence dans le tableau suffit).
    var hasValidBitmaps: Bool { !bitmaps.isEmpty }

    func interpolatedMatrixValues(at ns: Int64) -> [Float]? {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.matrix), !t.isEmpty else { return nil }
        return t.getValue(at: ns)
    }
    var hasTransformKeyframes: Bool {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.matrix) else { return false }
        return !t.isEmpty
    }

    // ── Keyframes transform décomposés ───────────────────────────────────

    var kfTranslateX: Float = 0
    var kfTranslateY: Float = 0
    private var _kfScale: Float = 1
    var kfScale: Float {
        get { _kfScale }
        set { _kfScale = max(0.01, newValue) }
    }
    var kfRotation: Float = 0
    var kfSkewX: Float = 0
    var kfSkewY: Float = 0

    func addTranslateXKeyframe(ns: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.positionX, timestampNs: ns, value: Keyframe.scalarValue(v)) }
    func addTranslateYKeyframe(ns: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.positionY, timestampNs: ns, value: Keyframe.scalarValue(v)) }
    func addScaleKeyframe(ns: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.scale, timestampNs: ns, value: Keyframe.scalarValue(v)) }
    func addRotationKeyframe(ns: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.rotation, timestampNs: ns, value: Keyframe.scalarValue(v)) }
    func addSkewXKeyframe(ns: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.skewX, timestampNs: ns, value: Keyframe.scalarValue(v)) }
    func addSkewYKeyframe(ns: Int64, v: Float) { addKeyframe(KeyframeTrack.PropertyName.skewY, timestampNs: ns, value: Keyframe.scalarValue(v)) }

    func interpolatedTranslateX(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.positionX), !t.isEmpty, let v = t.getValue(at: ns) else { return kfTranslateX }
        return v[0]
    }
    func interpolatedTranslateY(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.positionY), !t.isEmpty, let v = t.getValue(at: ns) else { return kfTranslateY }
        return v[0]
    }
    func interpolatedScale(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.scale), !t.isEmpty, let v = t.getValue(at: ns) else { return kfScale }
        return max(0.01, v[0])
    }
    func interpolatedRotation(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.rotation), !t.isEmpty, let v = t.getValue(at: ns) else { return kfRotation }
        return v[0]
    }
    func interpolatedSkewX(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.skewX), !t.isEmpty, let v = t.getValue(at: ns) else { return kfSkewX }
        return v[0]
    }
    func interpolatedSkewY(at ns: Int64) -> Float {
        guard let t = keyframeTrack(KeyframeTrack.PropertyName.skewY), !t.isEmpty, let v = t.getValue(at: ns) else { return kfSkewY }
        return v[0]
    }

    // ── Bake keyframes → transforms ──────────────────────────────────────

    /// Port de `bakeKeyframesToTransforms` — remplit opacity/color/cornerRadius/feather sur
    /// CHAQUE `Transform` déjà présent dans `transforms` (tableau indexé par frame, rempli par
    /// ailleurs — capture de geste ou `AnimationEngine.bakeTransformKeyframesToGL`), à partir des
    /// pistes de keyframes correspondantes. Ne redimensionne PAS `transforms` (contrairement à
    /// `AnimationEngine.bakeTransformKeyframesToGL`, qui lui agrandit le tableau matrice) — fidèle
    /// à l'original, ce n'est pas une simplification.
    func bakeKeyframesToTransforms(frameRate: Int) {
        guard !transforms.isEmpty else { return }
        let nsPerFrame = Int64(1_000_000_000) / Int64(frameRate)
        for f in 0..<transforms.count {
            let ns = Int64(f) * nsPerFrame
            if let op = keyframeTrack(KeyframeTrack.PropertyName.opacity), !op.isEmpty, let v = op.getValue(at: ns) {
                transforms[f].opacity = v[0]
            }
            if let col = keyframeTrack(KeyframeTrack.PropertyName.color), !col.isEmpty, let v = col.getValue(at: ns), v.count >= 4 {
                transforms[f].color = Keyframe.floatArrayToArgb(v)
            }
            if let rad = keyframeTrack(KeyframeTrack.PropertyName.cornerRadius), !rad.isEmpty, let v = rad.getValue(at: ns) {
                transforms[f].cornerRadius = v[0]
            }
            if let fe = keyframeTrack(KeyframeTrack.PropertyName.feather), !fe.isEmpty, let v = fe.getValue(at: ns) {
                transforms[f].feather = max(0, min(1, v[0]))
            }
        }
    }

    // MARK: - Champs existants

    var objectIndex: Int = 0
    var transforms: [Transform] = []
    var objectType: ObjectType?
    var objectPath: String?
    var emojiBitmap: String?
    var locked: Bool = false
    var easing: [Float]?
    var id: String = ""
    var recomposeGroupId: String?
    var track: Int = 0
    var startFrame: Int = 0
    var endFrame: Int = -1
    var duration: Int = 0
    var padding: Int = 0
    var cachedMaxHeight: Int = 0
    var objectColor: UInt32 = 0
    var backgroundColor: UInt32 = 0
    var text: String?
    var bound: CGRect?
    var moveObject: Bool = false
    var visible: Bool = false
    var top: CGFloat = 0
    var right: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var offsetX: Int = 0
    var offsetY: Int = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var isBackgroundTransparent: Bool = false
    var start: Bool = false
    var holdLast: Bool = false
    var strokeWidth: Int = 0
    var size: Int = 0
    var presentationTime: Int64 = 0
    var label: String?
    var stickerPath: String?

    private(set) var bitmaps: [CGImage] = []
    private(set) var texturesId: [Int] = []
    private(set) var currentFrame: Int = 0
    private(set) var currentTexture: Int = 0
    private(set) var bitmapTimestamps: [Int64] = []
    private(set) var textureTimestamps: [Int64] = []

    // ── Forme (shape) ─────────────────────────────────────────────────────

    private var _shapeColor: UInt32 = 0xFFFF_FFFF
    var shapeColor: UInt32 {
        get { _shapeColor }
        set { _shapeColor = newValue }
    }
    private var _shapeOpacity: Float = 1.0
    var shapeOpacity: Float {
        get { _shapeOpacity }
        set { _shapeOpacity = max(0, min(1, newValue)) }
    }
    private var _shapeCornerRadius: Float = 0
    var shapeCornerRadius: Float {
        get { _shapeCornerRadius }
        set { _shapeCornerRadius = max(0, newValue) }
    }
    private var _shapeLineThickness: Float = 8
    var shapeLineThickness: Float {
        get { _shapeLineThickness }
        set { _shapeLineThickness = max(1, newValue) }
    }
    private var _shapeStrokeWidth: Float = 0
    var shapeStrokeWidth: Float {
        get { _shapeStrokeWidth }
        set { _shapeStrokeWidth = max(0, newValue) }
    }
    var shapeW: Int = 0
    var shapeH: Int = 0

    var isShape: Bool {
        objectType == .shapeRect || objectType == .shapeCircle || objectType == .shapeLine
    }
    var isMask: Bool { label?.hasPrefix("mask_") ?? false }

    // MARK: - Bitmaps / textures

    func addBitmap(_ b: CGImage) { bitmaps.append(b) }
    func setBitmaps(_ list: [CGImage]) { bitmaps = list }
    var currentBitmap: CGImage? {
        guard !bitmaps.isEmpty else { return nil }
        return bitmaps[currentFrame % bitmaps.count]
    }
    func nextFrame() {
        guard bitmaps.count > 1 else { return }
        currentFrame = (currentFrame + 1) % bitmaps.count
    }
    func goToLastFrame() {
        guard !bitmaps.isEmpty else { return }
        currentFrame = bitmaps.count - 1
    }
    func addBitmap(_ b: CGImage, timestamp: Int64) {
        bitmaps.append(b)
        bitmapTimestamps.append(timestamp)
    }
    var hasBitmapTimestamps: Bool { !bitmapTimestamps.isEmpty }

    /// Port de `getCurrentBitmapForTime` — dernière bitmap dont l'horodatage est `<= ns`.
    func currentBitmap(forTime ns: Int64) -> CGImage? {
        guard !bitmaps.isEmpty else { return nil }
        guard !bitmapTimestamps.isEmpty else { return currentBitmap }
        var idx = 0
        for i in 0..<min(bitmapTimestamps.count, bitmaps.count) {
            if bitmapTimestamps[i] <= ns { idx = i } else { break }
        }
        return bitmaps[idx]
    }

    func addTextureId(_ id: Int, timestamp: Int64) {
        texturesId.append(id)
        textureTimestamps.append(timestamp)
    }
    var hasTextureTimestamps: Bool { !textureTimestamps.isEmpty }

    func currentTexture(forTime ns: Int64) -> Int {
        guard !texturesId.isEmpty else { return 0 }
        guard !textureTimestamps.isEmpty else { return currentTextureId }
        var idx = 0
        for i in 0..<min(textureTimestamps.count, texturesId.count) {
            if textureTimestamps[i] <= ns { idx = i } else { break }
        }
        return texturesId[idx]
    }

    func setCurrentBitmapIndex(_ i: Int) {
        guard !bitmaps.isEmpty, i >= 0, i < bitmaps.count else { return }
        currentFrame = i
    }
    var currentBitmapIndex: Int { currentFrame }
    var currentTextureId: Int {
        guard !texturesId.isEmpty else { return 0 }
        return texturesId[currentTexture % texturesId.count]
    }
    func nextTexture() {
        guard texturesId.count > 1 else { return }
        currentTexture = (currentTexture + 1) % texturesId.count
    }
    func addTextureId(_ id: Int) { texturesId.append(id) }

    // ── Vitesse de défilement bitmap/texture — par-objet, fallback global ──

    /// -1 = non défini → repli sur `Transform.defaultBitmapChangeIntervalMs` (comportement
    /// inchangé pour tout objet existant, ex. GIFs importés).
    var bitmapChangeIntervalMs: Int = -1
    private var bitmapFrameAccumulatorMs: Int64 = 0
    private var textureFrameAccumulatorNs: Int64 = 0

    var effectiveBitmapChangeIntervalMs: Int64 {
        bitmapChangeIntervalMs > 0 ? Int64(bitmapChangeIntervalMs) : AnimationTiming.bitmapChangeIntervalMs
    }

    /// Port de `advanceBitmapFrame` — chaque objet accumule et franchit son propre seuil
    /// indépendamment (remplace l'ancien accumulateur partagé d'`AnimationEngine`).
    func advanceBitmapFrame(deltaMs: Int64) {
        guard bitmaps.count > 1 else { return }
        let interval = effectiveBitmapChangeIntervalMs
        guard interval > 0 else { return }
        bitmapFrameAccumulatorMs += deltaMs
        while bitmapFrameAccumulatorMs >= interval {
            bitmapFrameAccumulatorMs -= interval
            nextFrame()
        }
    }

    /// Port de `advanceTextureFrame` — équivalent pour le cycle de textures GL (unité ns pour
    /// correspondre à son accumulateur d'origine côté `MP4Encoder`).
    func advanceTextureFrame(deltaNs: Int64) {
        guard texturesId.count > 1 else { return }
        let intervalNs = effectiveBitmapChangeIntervalMs * 1_000_000
        guard intervalNs > 0 else { return }
        textureFrameAccumulatorNs += deltaNs
        while textureFrameAccumulatorNs >= intervalNs {
            textureFrameAccumulatorNs -= intervalNs
            nextTexture()
        }
    }

    // MARK: - Ré-échantillonnage (redimensionnement d'un bloc de timeline)

    /// Port de `AnimemesCompound.testTimeLine().resampleTransforms` (méthode privée du listener
    /// de timeline, remontée ici sur l'objet lui-même — plus logique en Swift qu'imbriquée dans
    /// un gestionnaire d'événements UI, aucune dépendance sur `TimelineView`/`MemesView2` dans le
    /// corps de la méthode elle-même, vérifié). Ré-échantillonne linéairement `transforms` vers
    /// `targetFrames` frames (ex. l'utilisateur étire/rétrécit un bloc dans la timeline en mode
    /// capture automatique). **`glMatrix`/`androidToGL_Matrix2` NON portés** — voir décision
    /// d'architecture Core Graphics (`Transform.swift`/`AnimationEngine.swift`) : seul
    /// `matrixValues` est recalculé, pas de conversion GL.
    ///
    /// **Écart de représentation NON encore confirmé, signalé plutôt que masqué** : la boucle
    /// Android scanne `transforms` À REBOURS pour trouver la DERNIÈRE entrée dont `getMatrix()`
    /// n'est PAS `null` (repli utilisé quand une entrée intermédiaire a `matrix == null`) — un
    /// état "pas de matrice" que `Transform.swift` (ici) ne peut pas représenter : son
    /// `matrixValues` est toujours un tableau de 9 éléments (identité par défaut), jamais vide.
    /// Dans TOUS les chemins de construction de `Transform` lus jusqu'ici (`bakeMatrixKeyframesTo
    /// Transforms`, `addShapeFromData`, `addMaskFromBitmap`), une matrice est explicitement
    /// assignée — donc ce cas "null" semble ne jamais se produire en pratique sur ces chemins,
    /// mais `MemesView2.java` (capture tactile de trajectoire, pas encore lu) pourrait en créer
    /// autrement. Simplifié ici en repli sur la DERNIÈRE entrée du tableau (`src.last`), à
    /// corriger si la lecture de `MemesView2.java` révèle un chemin où `matrix` reste réellement
    /// non défini.
    func resampleTransforms(targetFrames: Int) {
        let src = transforms
        let srcSize = src.count
        guard srcSize > 0, targetFrames != srcSize else { return }

        let lastValidTransform = src[srcSize - 1]

        var result: [Transform] = []
        result.reserveCapacity(targetFrames)

        for f in 0..<targetFrames {
            let srcPos = Float(srcSize - 1) * Float(f) / Float(max(1, targetFrames - 1))
            let lo = Int(srcPos.rounded(.down))
            let hi = min(lo + 1, srcSize - 1)
            let alpha = srcPos - Float(lo)

            let tLo = src[lo]
            let tHi = src[hi]

            var out = Transform()
            out.frameIndex = f
            out.duration = lastValidTransform.duration

            let vLo = tLo.matrixValues
            let vHi = tHi.matrixValues
            var vOut = [Float](repeating: 0, count: 9)
            for k in 0..<9 { vOut[k] = vLo[k] + alpha * (vHi[k] - vLo[k]) }
            out.matrixValues = vOut

            out.opacity = tLo.opacity + alpha * (tHi.opacity - tLo.opacity)
            out.cornerRadius = tLo.cornerRadius + alpha * (tHi.cornerRadius - tLo.cornerRadius)
            out.feather = tLo.feather + alpha * (tHi.feather - tLo.feather)

            let cLo = tLo.color, cHi = tHi.color
            if cLo == 0, cHi == 0 {
                out.color = 0
            } else {
                let a = Self.lerpByte((cLo >> 24) & 0xFF, (cHi >> 24) & 0xFF, alpha)
                let r = Self.lerpByte((cLo >> 16) & 0xFF, (cHi >> 16) & 0xFF, alpha)
                let g = Self.lerpByte((cLo >> 8) & 0xFF, (cHi >> 8) & 0xFF, alpha)
                let b = Self.lerpByte(cLo & 0xFF, cHi & 0xFF, alpha)
                out.color = (a << 24) | (r << 16) | (g << 8) | b
            }

            result.append(out)
        }

        transforms = result
    }

    /// Port de `resampleMaskTransforms` — même principe que `resampleTransforms`, appliqué à
    /// `maskTransforms` (mode masque en capture automatique). Ne ré-échantillonne QUE la matrice
    /// (opacity/color/cornerRadius/feather non repris ici non plus côté Android — vérifié, ce
    /// n'est pas un oubli de portage).
    func resampleMaskTransforms(targetFrames: Int) {
        let src = maskTransforms
        let srcSize = src.count
        guard srcSize > 0, targetFrames != srcSize else { return }

        var result: [Transform] = []
        result.reserveCapacity(targetFrames)

        for f in 0..<targetFrames {
            let srcPos = Float(srcSize - 1) * Float(f) / Float(max(1, targetFrames - 1))
            let lo = Int(srcPos.rounded(.down))
            let hi = min(lo + 1, srcSize - 1)
            let alpha = srcPos - Float(lo)

            let tLo = src[lo]
            let tHi = src[hi]

            var out = Transform()
            out.frameIndex = f

            let vLo = tLo.matrixValues
            let vHi = tHi.matrixValues
            var vOut = [Float](repeating: 0, count: 9)
            for k in 0..<9 { vOut[k] = vLo[k] + alpha * (vHi[k] - vLo[k]) }
            out.matrixValues = vOut

            result.append(out)
        }

        clearMaskTransforms()
        for t in result { addMaskTransform(t) }
    }

    private static func lerpByte(_ a: UInt32, _ b: UInt32, _ t: Float) -> UInt32 {
        UInt32(max(0, min(255, (Float(a) + t * (Float(b) - Float(a))).rounded())))
    }

    // MARK: - Duplicate

    /// Port de `AnimationObjectData.duplicate(AnimationObjectData)` — copie profonde complète.
    static func duplicate(_ data: AnimationObjectData) -> AnimationObjectData {
        let copy = AnimationObjectData()
        copy.id = String(Int64(Date().timeIntervalSince1970 * 1000))
        copy.duration = data.duration
        copy.label = data.label
        copy.objectType = data.objectType
        copy.width = data.width
        copy.height = data.height
        copy.bitmapChangeIntervalMs = data.bitmapChangeIntervalMs
        copy.visible = true
        copy.isBackgroundTransparent = data.isBackgroundTransparent
        copy.shapeColor = data.shapeColor
        copy.shapeOpacity = data.shapeOpacity
        copy.shapeCornerRadius = data.shapeCornerRadius
        copy.shapeLineThickness = data.shapeLineThickness
        copy.shapeStrokeWidth = data.shapeStrokeWidth
        copy.shapeW = data.shapeW
        copy.shapeH = data.shapeH
        copy.appliedMaskType = data.appliedMaskType
        copy.maskInverted = data.maskInverted
        copy.maskFeather = data.maskFeather
        copy.maskOffsetX = data.maskOffsetX
        copy.maskOffsetY = data.maskOffsetY
        copy.maskScale = data.maskScale
        copy.maskMirrorGap = data.maskMirrorGap
        copy.maskRotation = data.maskRotation

        for mt in data.maskTransforms { copy.addMaskTransform(mt) }

        copy.setBitmaps(data.bitmaps)
        if !data.bitmapTimestamps.isEmpty { copy.bitmapTimestamps.append(contentsOf: data.bitmapTimestamps) }
        if !data.textureTimestamps.isEmpty { copy.textureTimestamps.append(contentsOf: data.textureTimestamps) }
        copy.transforms = data.transforms
        if let bound = data.bound { copy.bound = bound }
        copy.offsetX = Int(data.width / 2)
        copy.offsetY = Int(data.height / 2)
        copy.track = data.track
        copy.startFrame = data.startFrame
        copy.endFrame = data.endFrame
        copy.objectColor = data.objectColor
        copy.backgroundColor = data.backgroundColor
        for (key, srcTrack) in data.keyframeTracks {
            var destTrack = KeyframeTrack(propertyName: srcTrack.propertyName)
            for kf in srcTrack.keyframes { destTrack.addKeyframe(timestampNs: kf.timestampNs, value: kf.value, easing: kf.easing) }
            copy.keyframeTracks[key] = destTrack
        }
        return copy
    }

    /// Port de `duplicate2` — copie légère (transforms/bitmaps PARTAGÉS, pas clonés, comme
    /// l'original : `d.setTransforms(data.getTransforms())`/`d.setBitmaps(data.getBitmaps())`
    /// réutilisent directement les mêmes listes/tableaux, contrairement à `duplicate` qui clone).
    static func duplicate2(_ data: AnimationObjectData) -> AnimationObjectData {
        let d = AnimationObjectData()
        d.id = String(Int64(Date().timeIntervalSince1970 * 1000))
        d.duration = data.duration
        d.transforms = data.transforms
        d.bound = data.bound
        d.offsetX = Int(data.width / 2)
        d.offsetY = Int(data.height / 2)
        d.label = data.label
        d.setBitmaps(data.bitmaps)
        d.visible = true
        d.width = data.width
        d.height = data.height
        d.objectType = data.objectType
        d.bitmapChangeIntervalMs = data.bitmapChangeIntervalMs
        return d
    }
}

/// Port de `core/Transform.BITMAP_CHANGE_INTERVAL_MS` (statique côté Android, centralisée ici en
/// dehors de `Transform` — un `struct` de valeur n'est pas l'endroit adapté à un état mutable
/// global partagé, contrairement à la classe Java d'origine).
enum AnimationTiming {
    static var bitmapChangeIntervalMs: Int64 = 333
}
