import CoreGraphics
import Foundation
import UIKit

/// État de l'écran `AnimemesEditorView` — wrapper `ObservableObject` autour du moteur Animems déjà
/// porté (`AnimationComposer` et les `AnimationObjectData` qu'il contient sont des classes de
/// référence SANS `@Published` interne ; `version` est incrémenté à chaque mutation pour forcer
/// SwiftUI à redessiner le `Canvas`, seul mécanisme de notification nécessaire ici).
///
/// **2026-08-16 (continuation post-Appetize, audit complet `AnimemesCompound.java`/`TimelineView.
/// java`) — le moteur (`AnimationEngine`/`KeyframeTrack`/`TimelineViewModel`/masques) était déjà
/// porté en quasi-totalité mais jamais câblé ici** : timeline (`TimelineViewModel`, 435 lignes),
/// enregistrement de keyframes explicite (`AnimationObjectData.addMatrixKeyframe` et consorts),
/// lecture/pause réelle (`AnimationEngine.play`/`pause`/`CADisplayLink`) sont maintenant câblés
/// ci-dessous — la note précédente documentant un export "3s statique, pas de vraie timeline" est
/// donc PÉRIMÉE, remplacée par le câblage réel.
@MainActor
final class AnimemesEditorState: ObservableObject {
    let composer = AnimationComposer()
    let bitmapCache = BitmapCacheManager()
    let textRect: TextRect
    /// Port de la logique de geste tactile (`MemesView2.java`, voir `AnimemesGestureController`) —
    /// ajouté le 2026-08-16 (continuation post-Appetize) : translation/rotation/échelle réelles au
    /// lieu de la seule translation `offsetX`/`offsetY` de la version initiale.
    let gestureController = AnimemesGestureController()
    /// Partagé entre le lissage de geste (`touchUp`) ET la lecture/timeline réelle (`play`/`pause`/
    /// `prepare`/`applyInterpolation`) — un seul moteur, comme côté Android (`MemesView2.mEngine`),
    /// pas deux instances qui divergeraient sur `totalFramesMinus1`/`transformationArray`.
    let engine = AnimationEngine()
    /// Port de `TimelineView` (modèle pur, `TimelineViewModel.swift`, déjà porté) — un item par
    /// calque, synchronisé via `syncTimeline()` après chaque ajout/suppression de calque.
    let timeline = TimelineViewModel()

    @Published private(set) var version = 0
    @Published var isExporting = false
    @Published var exportError: String?
    @Published var selectedId: String?
    @Published private(set) var isPlaying = false
    /// Port du mode d'édition de masque (`MaskAddPanel`/`MaskPreviewEditorPanel` →
    /// `mView.startMaskEditMode`/`stopMaskEditMode`, `AnimemesCompound.java:1033-1310`) — quand
    /// actif, le geste principal du canevas (`AnimemesEditorView.combinedGesture`) est remplacé par
    /// `maskEditGesture`, qui pilote `maskOffsetX/Y`/`maskScale`/`maskRotation` au lieu de la
    /// matrice de transformation de l'objet.
    @Published var isMaskEditMode = false

    /// Port de `configureNewObject`/durée par défaut d'un nouveau calque — 3s à 30 fps
    /// (`AnimemesExporter.frameRate`), point de départ ÉDITABLE ensuite via la timeline
    /// (`setDuration(seconds:)`/glissement des poignées `TimelineView`), pas une limite figée
    /// contrairement à la version précédente de cette passe.
    private static let durationFrames = 90

    init() {
        textRect = TextRect(font: .boldSystemFont(ofSize: 32), textColor: .white)
        engine.delegate = self
        timeline.layers = composer.layers
    }

    var layers: [AnimationObjectData] { composer.layers }

    /// Force un redraw explicite (voir tête de fichier) — exposé pour `TimelineView`, dont les
    /// gestes mutent `TimelineViewModel` directement (classe de référence, comme le reste du
    /// moteur) sans passer par une méthode dédiée de cet état.
    func bumpVersion() { version += 1 }

    // MARK: - Timeline (port de `testTimeLine()`/`refreshTimelineItems`)

    /// Reconstruit les items de la timeline à partir des calques — appelé après chaque ajout/
    /// suppression de calque. Une piste PAR calque (`track = index`, `trackCount` élargi au besoin)
    /// : Android assigne les pistes via un algorithme non entièrement relu dans l'audit de ce tour
    /// (`TimelineView`/`AnimemesCompound` — assignation exacte piste-par-calque non vérifiée ligne à
    /// ligne) ; une piste dédiée par calque est fonctionnellement équivalente (chaque calque reste
    /// visible et manipulable indépendamment), documentée ici comme simplification assumée plutôt
    /// que devinée en silence.
    func syncTimeline() {
        timeline.layers = composer.layers
        timeline.trackCount = max(5, composer.layers.count)
        timeline.items = composer.layers.enumerated().map { index, obj in
            var item = TimelineItem(id: obj.id)
            item.label = obj.objectType?.rawValue.capitalized ?? "Layer"
            item.track = index
            item.startFrame = max(0, obj.startFrame)
            item.endFrame = obj.endFrame
            item.locked = obj.locked
            item.visibility = obj.visible
            item.recomposeGroupId = obj.recomposeGroupId
            return item
        }
        timeline.clampAll()
    }

    /// Port du glissement des poignées de bloc timeline — pousse `startFrame`/`endFrame` de
    /// `TimelineItem` (déjà mis à jour par `TimelineViewModel.dragItem`/`resizeLeft`/`resizeRight`)
    /// vers l'`AnimationObjectData` réel, puis re-prépare le moteur (`AnimemesCompound.
    /// testTimeLine().onItemChanged` → `mView.setStartObject/setEndObject` → `prepare()`).
    func applyTimelineItemsToLayers() {
        for item in timeline.items {
            guard let obj = composer.layers.first(where: { $0.id == item.id }) else { continue }
            obj.startFrame = item.startFrame
            obj.endFrame = item.endFrame
        }
        engine.prepare(composer: composer)
        version += 1
    }

    /// Port de `EditPersonalInformation`-style setter direct — change la durée du calque
    /// SÉLECTIONNÉ en secondes (raccourci pratique au-dessus du glissement de poignée timeline,
    /// équivalent fonctionnel : les deux chemins écrivent `startFrame`/`endFrame`).
    func setSelectedDuration(seconds: Double) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        let frames = max(1, Int((seconds * Double(engine.frameRate)).rounded()))
        obj.endFrame = obj.startFrame + frames - 1
        syncTimeline()
        engine.prepare(composer: composer)
        version += 1
    }

    private func configureNewObject(_ obj: AnimationObjectData, canvasSize: CGSize, size: CGSize) {
        obj.id = UUID().uuidString
        obj.transforms = [Transform()]
        obj.startFrame = 0
        obj.endFrame = Self.durationFrames - 1
        obj.holdLast = true
        obj.visible = true
        obj.offsetX = Int(canvasSize.width / 2 - size.width / 2)
        obj.offsetY = Int(canvasSize.height / 2 - size.height / 2)
    }

    func addImage(_ image: UIImage, canvasSize: CGSize) {
        // Port de `ic_add` → galerie → calque BITMAP. Redimensionnement AVANT ajout : `LayerRenderer`
        // dessine chaque bitmap à sa taille PIXEL native (`bmp.width`/`bmp.height`, pas de mise à
        // l'échelle appliquée par le moteur) — une photo caméra pleine résolution recouvrirait tout
        // le canevas sans ce redimensionnement préalable.
        guard let resized = Self.downscale(image, maxDimension: 220), let cgImage = resized.cgImage else { return }
        let obj = AnimationObjectData()
        obj.objectType = .bitmap
        obj.addBitmap(cgImage)
        configureNewObject(obj, canvasSize: canvasSize, size: CGSize(width: cgImage.width, height: cgImage.height))
        composer.addLayer(obj)
        syncTimeline()
        version += 1
    }

    func addText(_ text: String, canvasSize: CGSize) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let obj = AnimationObjectData()
        obj.objectType = .text
        obj.text = trimmed
        obj.backgroundColor = 0xB300_0000
        obj.objectColor = 0xFFFF_FFFF
        configureNewObject(obj, canvasSize: canvasSize, size: CGSize(width: 160, height: 60))
        composer.addLayer(obj)
        syncTimeline()
        version += 1
    }

    /// Port de `showShapeAddPanel()`/`btn_shape` — formes RASTÉRISÉES immédiatement
    /// (`ShapeFactory`, même stratégie que le moteur Android d'origine : "shapes are rasterized
    /// into Bitmap so they plug directly into the existing AnimationObjectData bitmap pipeline").
    func addShape(_ type: AnimationObjectData.ObjectType, canvasSize: CGSize) {
        let image: CGImage?
        let size: CGSize
        switch type {
        case .shapeRect:
            image = ShapeFactory.createRect(w: 150, h: 100, color: 0xFFFF_3B30, alpha: 1, cornerRadius: 12, strokeWidth: 0)
            size = CGSize(width: 150, height: 100)
        case .shapeCircle:
            image = ShapeFactory.createCircle(diameter: 140, color: 0xFF34_C759, alpha: 1, strokeWidth: 0)
            size = CGSize(width: 140, height: 140)
        case .shapeLine:
            image = ShapeFactory.createLine(length: 200, thickness: 8, color: 0xFF00_7AFF, alpha: 1)
            size = CGSize(width: 200, height: 12)
        default:
            return
        }
        guard let image else { return }
        let obj = AnimationObjectData()
        obj.objectType = type
        obj.addBitmap(image)
        configureNewObject(obj, canvasSize: canvasSize, size: size)
        composer.addLayer(obj)
        syncTimeline()
        version += 1
    }

    // MARK: - Gestes (port de `MemesView2.java` via `AnimemesGestureController`, 2026-08-16)

    /// Port de `touchDown` — teste si `point` tombe dans un calque (du dernier au premier, ordre
    /// d'affichage = ordre de dessin, le dernier dessiné est visuellement au-dessus) et l'arme pour
    /// le geste en cours.
    func selectObject(at point: CGPoint) -> String? {
        guard let index = layers.lastIndex(where: { $0.bound?.contains(point) ?? false }) else {
            selectedId = nil
            return nil
        }
        selectedId = layers[index].id
        gestureController.touchDown(at: point, objectIndex: index, composer: composer)
        return selectedId
    }

    private func index(of id: String) -> Int? { layers.firstIndex { $0.id == id } }

    /// Port de `touchMove` (translation à un doigt) — délègue à `AnimemesGestureController.
    /// touchMoveTranslate`, qui opère directement sur la matrice de la dernière `Transform` (PAS
    /// `offsetX`/`offsetY`, corrigé le 2026-08-16 — la version initiale mutait `offsetX`/`offsetY`
    /// directement, une simplification qui aurait mal composé avec la rotation/l'échelle ajoutées
    /// ici : Android ne touche JAMAIS `offsetX`/`offsetY` par geste, tout passe par la matrice).
    func dragMoved(to point: CGPoint) {
        guard let id = selectedId, let idx = index(of: id) else { return }
        gestureController.touchMoveTranslate(to: point, objectIndex: idx, composer: composer)
        version += 1
    }

    func dragEnded() {
        guard let id = selectedId, let idx = index(of: id) else { return }
        gestureController.touchUp(objectIndex: idx, composer: composer, engine: engine)
    }

    /// Port de `touchPointerDown` — amorce un geste rotation/pincement, pivot = centre du calque
    /// sélectionné (Android utilise le point milieu RÉEL des deux doigts ; `RotationGesture`/
    /// `MagnificationGesture` de SwiftUI ne donnent pas accès aux coordonnées de contact
    /// individuelles, seulement des valeurs scalaires cumulatives depuis le début du geste — le
    /// centre du calque est un pivot raisonnable et fidèle en pratique, écart assumé faute d'accès
    /// à la position réelle des doigts).
    func beginPinchRotate() {
        guard let id = selectedId, let idx = index(of: id), let bound = layers[idx].bound else { return }
        let center = CGPoint(x: bound.midX, y: bound.midY)
        // Points synthétiques choisis pour que `AnimemesGestureController.degrees(p0,p1) == 0` et
        // `midPoint == center` (voir le calcul dans `AnimemesGestureController.swift` :
        // `atan2(p0.x-p1.x, p0.y-p1.y)` — `p0`/`p1` alignés verticalement sur `center`, `p0` en
        // dessous de `p1`, donne `atan2(0, +) == 0`). Sert UNIQUEMENT à initialiser l'angle de
        // référence à 0°, cohérent avec `RotationGesture`, qui rapporte aussi un angle cumulatif
        // débutant à 0° — voir `rotationChanged(to:)` ci-dessous.
        gestureController.pointerDown(point0: CGPoint(x: center.x, y: center.y + 1), point1: CGPoint(x: center.x, y: center.y - 1))
    }

    /// Port de `rotate` — `newDegrees` est l'angle CUMULATIF rapporté par `RotationGesture`
    /// (identique en sémantique à `oldAngleDegrees` initialisé à 0 dans `beginPinchRotate`, voir
    /// note ci-dessus) : `AnimemesGestureController.rotate(to:)` calcule lui-même le delta interne,
    /// pas besoin de le calculer ici.
    func rotationChanged(to newDegrees: CGFloat) {
        guard let id = selectedId, let idx = index(of: id) else { return }
        gestureController.rotate(to: newDegrees, objectIndex: idx, composer: composer)
        version += 1
    }

    /// Port de `scale`/`ScaleListener.onScale` — `incrementalFactor` est le ratio ENTRE deux
    /// valeurs cumulatives successives de `MagnificationGesture` (calculé par l'appelant SwiftUI,
    /// voir `AnimemesEditorView` — `AnimemesGestureController.scale` attend un facteur PAR
    /// ÉVÉNEMENT, pas cumulatif, voir sa documentation).
    func scaleChanged(incrementalFactor: CGFloat) {
        guard let id = selectedId, let idx = index(of: id), let bound = layers[idx].bound else { return }
        let clamped = AnimemesGestureController.clampPerEventScaleFactor(incrementalFactor)
        gestureController.scale(factor: clamped, focus: CGPoint(x: bound.midX, y: bound.midY), objectIndex: idx, composer: composer)
        version += 1
    }

    // MARK: - Masques (port de `MaskAddPanel`/`MaskPreviewEditorPanel`, `AnimemesCompound.java:
    // 1033-1310`) — `MaskFactory`/`appliedMaskType`/`maskOffsetX/Y`/`maskScale`/`maskMirrorGap`/
    // `maskRotation`/`maskFeather`/`maskInverted` étaient déjà portés côté `AnimationObjectData`/
    // `LayerRenderer` (rendu déjà câblé, vérifié en relisant `LayerRenderer.drawObjectFrame`), seul
    // le câblage UI/geste manquait.

    /// Port de `MaskAddPanel` (choix du type) — applique/change le masque du calque sélectionné.
    /// `nil` retire le masque (`appliedMaskType = nil`, `hasAppliedMask` redevient `false`).
    func setMaskType(_ type: MaskType?) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        obj.appliedMaskType = type
        version += 1
    }

    func toggleMaskInverted() {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        obj.maskInverted.toggle()
        version += 1
    }

    func setMaskFeather(_ value: Float) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        obj.maskFeather = value
        version += 1
    }

    func setMaskMirrorGap(_ value: Float) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        obj.maskMirrorGap = value
        version += 1
    }

    /// Port du glisser-déposer direct du masque (`MaskEditController`/`maskApplyDrag`) —
    /// `deltaTranslation` est un DELTA (pas cumulatif, contrairement à `RotationGesture`/
    /// `MagnificationGesture` de SwiftUI) : l'appelant (`AnimemesEditorView.maskEditGesture`)
    /// calcule ce delta lui-même depuis `DragGesture.value.translation`, même motif que l'ancien
    /// `moveObject` avant le passage au geste matriciel. Normalisé par la taille du canevas —
    /// `maskOffsetX`/`Y` sont des fractions `[-2, 2]` de la largeur/hauteur (voir le clamp dans
    /// `AnimationObjectData`), pas des pixels.
    func maskOffsetChanged(deltaTranslation: CGSize, canvasSize: CGSize) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }),
              canvasSize.width > 0, canvasSize.height > 0
        else { return }
        obj.maskOffsetX += Float(deltaTranslation.width / canvasSize.width)
        obj.maskOffsetY += Float(deltaTranslation.height / canvasSize.height)
        version += 1
    }

    /// Port de `maskScaleChanged` — `incrementalFactor` PAR ÉVÉNEMENT, même contrat que
    /// `scaleChanged(incrementalFactor:)` (objet) ci-dessus.
    func maskScaleChanged(incrementalFactor: CGFloat) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        obj.maskScale *= Float(incrementalFactor)
        version += 1
    }

    /// Port de `maskRotationChanged` — `deltaDegrees` DELTA (pas cumulatif), calculé par l'appelant
    /// depuis `RotationGesture.value.degrees` (cumulatif) comme `maskOffsetChanged` ci-dessus.
    func maskRotationChanged(deltaDegrees: CGFloat) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        obj.maskRotation += Float(deltaDegrees)
        version += 1
    }

    /// Port d'`undo` → `mView.deletePrecedenteDraw()` — supprime le DERNIER calque ajouté (pas une
    /// pile d'annulation multi-niveaux généralisée, fidèle à ce bouton précis côté Android).
    func removeLast() {
        guard !composer.layers.isEmpty else { return }
        composer.setLayers(Array(composer.layers.dropLast()))
        syncTimeline()
        version += 1
    }

    // MARK: - Lecture / scrub (port de `MemesView2.play/pause`, bouton play `AnimemesCompound.
    // java:2007-2019` + `onPlayheadMoved`/`TimelineView.OnTimelineListener`)

    /// Port de `mView.prepare()` — à appeler avant toute lecture/scrub pour que
    /// `transformationArray` (table frame→transform locale, fenêtre `startFrame`/`endFrame` par
    /// calque) et `totalFramesMinus1` soient à jour par rapport à l'état actuel des calques.
    /// **`applyInterpolation()`/le bake matriciel PAS appelés ici, délibérément** : `LayerRenderer.
    /// drawObjectFrame` (vérifié en le relisant en entier) interroge DÉJÀ les pistes de keyframes en
    /// direct (`obj.hasTransformKeyframes`/`interpolatedMatrixValues(at:)`, `resolveVisualProperties`
    /// avec `isSliderPreview: false`) — le bake n'est nécessaire que pour l'export image-par-image
    /// (`AnimemesExporter`, qui le fait lui-même), pas pour cet aperçu live.
    func preparePlayback(canvasSize: CGSize) {
        engine.setViewSize(width: canvasSize.width, height: canvasSize.height)
        engine.prepare(composer: composer)
        timeline.setTotalFrames(max(1, engine.totalFramesMinus1 + 1))
    }

    /// Port du bouton lecture unique (`AnimemesCompound.java:2007-2019`, PAS de bouton "loop" —
    /// `ic_repeate` est en réalité "répéter l'image de fond", voir audit du 2026-08-16, sans
    /// rapport avec la lecture).
    func togglePlayback(canvasSize: CGSize) {
        if engine.isPlaying {
            engine.pause()
        } else {
            preparePlayback(canvasSize: canvasSize)
            engine.play(composer: composer, layer: 0)
        }
    }

    /// Port de `TimelineView.OnTimelineListener.onPlayheadMoved` → `mView.seek(frame)` — scrub
    /// manuel, met en pause la lecture en cours comme l'original.
    func scrub(toFrame frame: Int) {
        if engine.isPlaying { engine.pause() }
        engine.seek(to: frame)
        timeline.setPlayheadFrame(frame, external: true)
        version += 1
    }

    /// Index LOCAL (dans `obj.transforms`) à afficher pour le calque `layerIndex` à `frame`, lu
    /// dans `engine.transformationArray` (rempli par `preparePlayback`/`syncTimeline`). `nil` avant
    /// le premier `prepare()` ou si le calque n'est pas visible à cette frame (bornes/`nil`
    /// intentionnel de `AnimationEngine.transformationArray`, voir sa tête de fichier) —
    /// l'appelant (`AnimemesEditorView.canvas`) retombe alors sur `obj.transforms.last`.
    func localTransformIndex(forLayer layerIndex: Int, frame: Int) -> Int? {
        guard layerIndex >= 0, layerIndex < engine.transformationArray.count else { return nil }
        let row = engine.transformationArray[layerIndex]
        guard frame >= 0, frame < row.count else { return nil }
        return row[frame]
    }

    // MARK: - Keyframes explicites (port du bouton ◆, `AnimemesCompound.java:859-871,1321-1348`)

    /// Port de `captureTransformKeyframe` — enregistre un keyframe MATRICE pour le calque
    /// sélectionné À LA POSITION ACTUELLE DU PLAYHEAD, avec la dernière matrice transformée par
    /// geste (`obj.transforms.last`). Modèle "marqueur explicite" confirmé par l'audit Android
    /// (2026-08-16) — PAS un enregistrement continu pendant le geste : l'utilisateur transforme
    /// l'objet, positionne le playhead, puis appuie sur ce bouton pour figer un point clé.
    func recordKeyframe() {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }),
              let matrixValues = obj.transforms.last?.matrixValues
        else { return }
        let ns = timeline.frameToTimestampNs(timeline.playheadFrame)
        // Pas de re-bake ici (`applyInterpolation`) — `LayerRenderer.drawObjectFrame` lit déjà les
        // pistes de keyframes en direct (voir note de `preparePlayback`), le bake ne sert qu'à
        // l'export.
        obj.addMatrixKeyframe(ts: ns, matrixValues: matrixValues)
        version += 1
    }

    /// Port de `save_animemes2` → `showSaveDialog()` → export réel (`AnimemesCompound.
    /// createVideosFromBitmap`) — MP4 uniquement, pas de GIF (voir `AnimemesExporter`, aucun
    /// exporteur GIF porté).
    func export(canvasSize: CGSize, completion: @escaping (URL?) -> Void) {
        guard !composer.layers.isEmpty else { return }
        isExporting = true
        exportError = nil
        let exporter = AnimemesExporter(composer: composer)
        exporter.outputSize = canvasSize
        exporter.viewSize = canvasSize
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        exporter.export(to: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isExporting = false
                switch result {
                case .success(let outputURL):
                    completion(outputURL)
                case .failure:
                    self.exportError = "L'export a échoué."
                    completion(nil)
                }
            }
        }
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

/// Port de `MemesView2.PreviewAnimationListener` — les rappels `CADisplayLink` d'`AnimationEngine`
/// n'arrivent pas dans un contexte statiquement connu comme `@MainActor` (même motif que
/// `CallKitManager`/`CXProviderDelegate` déjà dans ce projet) : conformité `nonisolated`, saut
/// explicite vers `MainActor` avant de muter l'état.
extension AnimemesEditorState: AnimationEnginePlaybackDelegate {
    nonisolated func animationEngine(_ engine: AnimationEngine, didPlayFrame frame: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.timeline.setPlayheadFrame(frame, external: false)
            self.isPlaying = true
            self.version += 1
        }
    }

    nonisolated func animationEngineDidPause(_ engine: AnimationEngine) {
        Task { @MainActor [weak self] in self?.isPlaying = false }
    }

    nonisolated func animationEngineDidEnd(_ engine: AnimationEngine) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.timeline.setPlayheadFrame(0, external: false)
            self.version += 1
        }
    }

    nonisolated func animationEngineDidInvalidate(_ engine: AnimationEngine) {
        Task { @MainActor [weak self] in self?.version += 1 }
    }
}
