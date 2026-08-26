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
    /// **Ajouté le 2026-08-17** (GAP-024, piste secondaire) — `version` pilote À LA FOIS le
    /// redessin du `Canvas` (via `@StateObject`/`@Published`, `AnimemesEditorView.body` se
    /// ré-évalue à chaque mutation) ET `.onChange(of: state.version)` → `preparePlayback()`
    /// (`AnimemesEditorView.swift`), qui relance `AnimationEngine.prepare(composer:)` — un
    /// recalcul de TOUTE la timeline pensé pour un changement STRUCTUREL (keyframe enregistrée,
    /// calque ajouté/retiré), pas pour chaque micro-mise à jour continue d'un geste en cours
    /// (glisser/pincer/pivoter, plusieurs fois par seconde). Les fonctions de geste CONTINU
    /// (`dragMoved`/`rotationChanged`/`scaleChanged`/`maskOffsetChanged`/`maskScaleChanged`/
    /// `maskRotationChanged`) incrémentent désormais CE compteur au lieu de `version` — `@StateObject`
    /// observe l'ObservableObject entier, donc le redessin continue de se déclencher normalement,
    /// mais `.onChange(of: state.version)` ne voit plus ces mises à jour continues et ne relance
    /// `preparePlayback` que pour les changements réellement structurels.
    @Published private(set) var renderVersion = 0
    @Published var isExporting = false
    @Published var exportError: String?
    /// Référence forte retenant `AnimemesExporter` pendant toute la durée de son pipeline vidéo
    /// asynchrone (**corrigé V5-F-094, 2026-08-24**) — sans elle, `exporter` n'était qu'une
    /// variable locale de `export(canvasSize:completion:)` : ARC la désallouait dès le retour
    /// (synchrone) de cette fonction, avant que `videoInput.requestMediaDataWhenReady` (callback
    /// ASYNCHRONE rappelé plus tard sur une autre file) ne s'exécute — la capture `[weak self]`
    /// à l'intérieur d'`AnimemesExporter.export` retrouvait alors `self == nil` à chaque rappel,
    /// aucune frame n'était jamais écrite et `completion` n'était jamais invoquée, laissant
    /// `isExporting` bloqué à `true` indéfiniment. Fidèle à `AnimemesCompound.encoder` côté
    /// Android (champ persistant de la vue pendant toute la durée de l'encodage,
    /// `AnimemesCompound.java:259,3317`) : libérée uniquement dans la completion (succès ou échec).
    private var activeExporter: AnimemesExporter?
    @Published var selectedId: String?
    @Published private(set) var isPlaying = false
    /// Port du mode d'édition de masque (`MaskAddPanel`/`MaskPreviewEditorPanel` →
    /// `mView.startMaskEditMode`/`stopMaskEditMode`, `AnimemesCompound.java:1033-1310`) — quand
    /// actif, le geste principal du canevas (`AnimemesEditorView.combinedGesture`) est remplacé par
    /// `maskEditGesture`, qui pilote `maskOffsetX/Y`/`maskScale`/`maskRotation` au lieu de la
    /// matrice de transformation de l'objet.
    @Published var isMaskEditMode = false
    /// Port de `auto_checkbox`/`automateCapture` (`AnimemesCompound.java:1900-1904`, confirmé réel
    /// par audit dédié du 2026-08-16 sur les captures Android) — Android enregistre en continu de
    /// nouvelles frames pendant le geste quand actif. **Approximation assumée, documentée** : le
    /// moteur ici utilise un modèle "keyframe explicite" (bouton ◆, voir `recordKeyframe()`) plutôt
    /// que la capture continue frame-par-frame d'Android — activer ce bouton enregistre
    /// automatiquement un keyframe à la FIN de chaque glissement (`dragEnded()`) au lieu d'exiger un
    /// tap manuel sur ◆, ce qui rapproche le comportement observable sans réécrire le moteur vers un
    /// modèle de capture continue distinct.
    @Published var autoCaptureEnabled = false
    /// Port du fichier `.tmpl`/piste audio de l'export (`AnimemesExporter.audioURL`, déjà pris en
    /// charge par l'exporteur — seul le point d'entrée UI "Ajouter un son" manquait). `nil` = pas de
    /// son, fidèle au comportement par défaut d'Android (aucun son tant que l'utilisateur n'en
    /// choisit pas un).
    @Published var audioURL: URL?
    /// Diagnostic AFFICHÉ À L'ÉCRAN (HUD temporaire) — demande explicite de l'utilisateur suite au
    /// rapport "les transformations ne fonctionnent pas réellement dans Appetize" : trace la chaîne
    /// GESTURE → CONTROLLER → STATE → TRANSFORM à chaque étape, visible sans accès console.
    @Published var gestureDiagnostics: String = "Aucun geste reçu pour l'instant."
    private var gestureEventCount = 0

    /// Port de `configureNewObject`/durée par défaut d'un nouveau calque — 3s à 30 fps
    /// (`AnimemesExporter.frameRate`), point de départ ÉDITABLE ensuite via la timeline
    /// (`setDuration(seconds:)`/glissement des poignées `TimelineView`), pas une limite figée
    /// contrairement à la version précédente de cette passe.
    private static let durationFrames = 90

    /// **Ajouté le 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-23, P0)** — source de vérité UNIQUE
    /// pour la police/couleur du texte dans Animems, partagée par `textRect` (canvas live + export
    /// image statique, ci-dessous) ET explicitement passée à `AnimemesExporter` dans `export()`.
    /// Avant ce correctif, `AnimemesExporter.init` avait ses PROPRES valeurs par défaut
    /// (`.systemFont(14)`) jamais écrasées par son seul appelant — tout calque TEXTE apparaissait
    /// nettement plus petit et non-gras dans la vidéo exportée que dans l'éditeur. En nommant les
    /// deux constantes ici et en les passant explicitement au constructeur de l'exporteur (au lieu
    /// de compter sur des valeurs par défaut qui coïncideraient), un futur changement de police ne
    /// peut plus dériver silencieusement entre éditeur et export.
    static let textFont: UIFont = .boldSystemFont(ofSize: 32)
    static let textColor: UIColor = .white

    init() {
        textRect = TextRect(font: Self.textFont, textColor: Self.textColor)
        engine.delegate = self
        timeline.layers = composer.layers
    }

    var layers: [AnimationObjectData] { composer.layers }

    /// Force un redraw explicite (voir tête de fichier) — exposé pour `TimelineView`, dont les
    /// gestes mutent `TimelineViewModel` directement (classe de référence, comme le reste du
    /// moteur) sans passer par une méthode dédiée de cet état.
    ///
    /// **NE PLUS appeler depuis un geste CONTINU (pan/scrub/dragItem/resize/pinch-zoom Timeline) —
    /// voir `bumpRenderVersion()` ci-dessous.** Historiquement `TimelineView.swift` appelait CETTE
    /// méthode à CHAQUE frame de geste (`onChanged`), ce qui, combiné à `.id(state.version)` sur le
    /// `Canvas` porteur du geste (retiré le 2026-08-17, P0-5), interrompait le geste lui-même à
    /// chaque mouvement (même classe de bug que GAP-024 sur le canevas principal, jamais portée
    /// jusqu'ici à ce fichier sœur) — ET, indépendamment de ce bug, sur-déclenchait
    /// `.onChange(of: state.version) → preparePlayback()` à chaque frame de pan/scrub/drag/resize/
    /// zoom (même sur-déclenchement que GAP-024 partie 2, jamais porté ici non plus).
    func bumpVersion() { version += 1 }

    /// **Ajouté le 2026-08-17 (P0-5)** — équivalent Timeline de `renderVersion` (voir sa doc de tête
    /// de fichier) : à utiliser par les gestes CONTINUS de `TimelineView` (pan/scrub/dragItem/
    /// resizeLeft/resizeRight/pinch-zoom, plusieurs fois par seconde) à la place de `bumpVersion()`
    /// — déclenche le redessin (`@ObservedObject` observe tout l'`ObservableObject`) SANS relancer
    /// `preparePlayback()`/`engine.prepare()` à chaque frame. Les changements réellement structurels
    /// (`applyTimelineItemsToLayers()`, appelé une seule fois à la FIN d'un drag/resize) continuent
    /// d'utiliser `version` via `bumpVersion()`/l'incrément direct existant.
    func bumpRenderVersion() { renderVersion += 1 }

    /// Port de `AnimemesCompound.onKeyframeDeleteRequested` (`AnimemesCompound.java:1360-1371`) —
    /// **ajouté le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-049, Phase B P1)**. `version`
    /// (pas `renderVersion`) : suppression = changement STRUCTUREL réel (le calque perd un
    /// keyframe, ses valeurs interpolées à la frame courante peuvent changer), fidèle au double
    /// `timelineView.invalidate()` + `mView.postInvalidate()` d'Android (redessine AUSSI le
    /// canevas principal, pas seulement la timeline) — `bumpVersion()` relance `preparePlayback()`
    /// via `.onChange(of: state.version)`, `bumpRenderVersion()` ne le ferait pas.
    func deleteKeyframe(layerId: String, propertyName: String, keyframeId: String) {
        guard let obj = layers.first(where: { $0.id == layerId }) else { return }
        guard obj.removeKeyframe(propertyName: propertyName, keyframeId: keyframeId) else { return }
        version += 1
    }

    /// Port de `onTrackIconClicked` (branche verrou, `AnimemesCompound.java:1645-1656`) —
    /// **ajouté le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-050, Phase B P1)**. Bascule
    /// toujours un résultat observable (jamais de no-op silencieux, fidèle au commentaire Android
    /// explicite sur ce point). `version` (pas `renderVersion`) : Android appelle `mView.prepare()`
    /// + `applyInterpolation()` + `postInvalidate()` après CE clic — changement structurel, pas un
    /// geste continu.
    func toggleLocked(layerId: String) {
        guard let obj = layers.first(where: { $0.id == layerId }) else { return }
        obj.locked.toggle()
        version += 1
    }

    /// Port de `onTrackIconClicked` (branche visibilité, lignes 1657-1666) — même remarque que
    /// `toggleLocked` ci-dessus.
    func toggleVisible(layerId: String) {
        guard let obj = layers.first(where: { $0.id == layerId }) else { return }
        obj.visible.toggle()
        version += 1
    }

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

    /// **Remplace le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-089, Phase B P1)** l'ancien
    /// `addText(_:canvasSize:)` qui créait un calque `.text` dynamique (police/couleur codées en
    /// dur, aucun style utilisateur) via l'alerte système minimale. Port fidèle de
    /// `ProTextEditorView.onTextConfirmed(Bitmap, String)` (`AnimemesCompound.java:471-480`) : côté
    /// Android, le bouton texte ouvre TOUJOURS `ProTextEditorView` (police/couleur/taille/
    /// alignement/fond réglables), et le résultat confirmé est un bitmap DÉJÀ rastérisé
    /// (`editText.draw(canvas)`) ajouté via `onNewAddBitmap(textBitmap, "text", true, false)` — un
    /// calque BITMAP comme n'importe quel autre, PAS le type `AnimationObjectData.Type.TEXT`
    /// (confirmé par grep exhaustif : `setObjectType(...TEXT)` n'est appelé NULLE PART dans le
    /// moteur Android actuel — ce type existe mais est mort côté source). `isBackgroundTrans=true`
    /// pour ce chemin : le bitmap texte est ajouté à sa taille NATIVE (pas de redimensionnement
    /// canevas/2 comme pour une image importée), fidèlement reproduit ici en passant `image.size`
    /// telle quelle à `configureNewObject`, sans passer par `Self.downscale` (réservé à
    /// `addImage`). Le rendu du bitmap lui-même (police/couleur/fond/arrondi/alignement) est fait
    /// par l'appelant (`ProTextEditorView.swift`, nouvelle vue SwiftUI qui consomme
    /// `ProTextEditorState` déjà porté) — cette méthode ne fait qu'insérer le résultat comme
    /// calque, comme `addFreehandDrawing`/`addCapturedPaintFrames` ci-dessous.
    func addStyledText(_ image: UIImage, canvasSize: CGSize) {
        guard let cgImage = image.cgImage else { return }
        let obj = AnimationObjectData()
        obj.objectType = .bitmap
        obj.addBitmap(cgImage)
        configureNewObject(obj, canvasSize: canvasSize, size: image.size)
        composer.addLayer(obj)
        syncTimeline()
        version += 1
    }

    /// Port de `showShapeAddPanel()`→`ShapeAddPanel` (choix du type) — ouvre le panneau de
    /// configuration (`ShapePreviewEditorPanelState.makeDefault`, déjà porté) plutôt que d'ajouter
    /// directement avec des valeurs codées en dur. **Remplacé le 2026-08-19
    /// (ANIMEMS_PARITY_AUDIT_V1.md F-21, Phase B Lot 5)** — voir `finalizeShape(_:canvasSize:)`
    /// pour la suite du flux (`ShapePreviewEditorPanel`→confirmation).
    func beginAddingShape(_ type: AnimationObjectData.ObjectType, canvasSize: CGSize) -> AnimationObjectData {
        ShapePreviewEditorPanelState.makeDefault(
            shapeType: type, canvasW: Int(canvasSize.width), canvasH: Int(canvasSize.height)
        )
    }

    /// Port de `ShapePreviewEditorPanel.OnConfirmListener.onConfirm(data)` →
    /// `addShapeFromData(data)` → `ShapeFactory.rerenderShape(data, ...)` — rastérise la forme
    /// TELLE QUE CONFIGURÉE par l'utilisateur dans le panneau (couleur/opacité/arrondi/épaisseur/
    /// contour, déjà écrites dans `data` par les contrôles du panneau) et l'ajoute comme nouveau
    /// calque, centré comme les autres formes (`configureNewObject`).
    func finalizeShape(_ data: AnimationObjectData, canvasSize: CGSize) {
        guard let image = ShapeFactory.rerender(data, canvasW: Int(canvasSize.width), canvasH: Int(canvasSize.height))
        else { return }
        data.addBitmap(image)
        let size = CGSize(width: max(data.shapeW, 4), height: max(data.shapeH, 4))
        configureNewObject(data, canvasSize: canvasSize, size: size)
        composer.addLayer(data)
        syncTimeline()
        version += 1
    }

    // MARK: - Gestes (port de `MemesView2.java` via `AnimemesGestureController`, 2026-08-16)

    /// Port de `touchDown` — teste si `point` tombe dans un calque (du dernier au premier, ordre
    /// d'affichage = ordre de dessin, le dernier dessiné est visuellement au-dessus) et l'arme pour
    /// le geste en cours.
    ///
    /// **CAUSE RACINE RÉELLE trouvée et corrigée ici (2026-08-16)** : cette méthode comparait
    /// directement `point` (repère écran) à `$0.bound` (repère LOCAL du calque, confirmé par
    /// `LayerRenderer` : `context.concatenate(tfm.cgAffineTransform)` PUIS `obj.bound =
    /// CGRect(offsetX, offsetY, ...)` — le repère local, exactement comme Android
    /// `drawBitmapLastTransform` : `canvas.concat(matrix)` puis `obj.getBound().set(offsetX,
    /// offsetY, ...)`, JAMAIS pré-multiplié par la matrice). Dès qu'un calque a été déplacé/
    /// pivoté/redimensionné ne serait-ce qu'une fois, son repère local ne coïncide plus avec le
    /// repère écran — un tap sur sa position VISIBLE ne retombait plus dans `bound` non-transformé,
    /// donc la resélection (et par extension tout geste suivant) échouait silencieusement. La
    /// même classe de bug que le hit-test Android `touchDown`/`isPointInsideObject`, qui inverse
    /// TOUJOURS la matrice du calque avant de comparer au `bound` local — logique déjà correctement
    /// portée dans `AnimemesGestureController.isPoint(_:insideObjectAt:composer:)` mais jamais
    /// utilisée ici, qui réimplémentait sa propre version (fausse) au lieu d'en déléguer le test.
    func selectObject(at point: CGPoint) -> String? {
        gestureEventCount += 1
        guard let index = (0..<layers.count).reversed().first(where: { gestureController.isPoint(point, insideObjectAt: $0, composer: composer) }) else {
            selectedId = nil
            // Diagnostic AFFICHÉ À L'ÉCRAN — si CE message apparaît en tapant directement sur un
            // objet visible, la cause est soit `obj.bound` jamais rempli (aucun rendu réussi
            // avant ce tap), soit un décalage de repère de coordonnées entre le geste et le rendu.
            let boundsDump = layers.map { "\($0.objectType?.rawValue ?? "?"):\($0.bound.map { String(describing: $0) } ?? "bound=nil")" }.joined(separator: " | ")
            gestureDiagnostics = "TAP #\(gestureEventCount) at \(point) → AUCUNE sélection. \(layers.count) calque(s) : \(boundsDump.isEmpty ? "aucun" : boundsDump)"
            return nil
        }
        selectedId = layers[index].id
        gestureController.touchDown(at: point, objectIndex: index, composer: composer)
        gestureDiagnostics = "TAP #\(gestureEventCount) at \(point) → SÉLECTIONNÉ calque #\(index) (\(layers[index].objectType?.rawValue ?? "?"), id=\(selectedId ?? "?"))"
        return selectedId
    }

    /// Port de `GestureListener.onLongPress` (`MemesView2.java:1571-1574`) — **ajouté le
    /// 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-052, Phase B P2)**. Même hit-test top-to-bottom
    /// que `selectObject(at:)` ci-dessus (`(0..<layers.count).reversed().first(where:)`, aucune
    /// garde `locked` — fidèle : Android teste `isPointInsideObject` sans filtre de verrouillage
    /// ici non plus, un calque verrouillé reste sélectionnable/remontable, seule la manipulation
    /// est bloquée, cf. V4-F-050), s'arrête au PREMIER match (le plus haut = le plus proche du
    /// dessus visuellement) et appelle `bringLayerToFront` (déjà porté, jusqu'ici zéro appelant).
    @discardableResult
    func bringTopLayerToFront(at point: CGPoint) -> String? {
        guard let index = (0..<layers.count).reversed().first(where: { gestureController.isPoint(point, insideObjectAt: $0, composer: composer) })
        else { return nil }
        let id = layers[index].id
        gestureController.bringLayerToFront(index, composer: composer)
        syncTimeline()
        version += 1
        return id
    }

    private func index(of id: String) -> Int? { layers.firstIndex { $0.id == id } }

    /// Port de `touchMove` (translation à un doigt) — délègue à `AnimemesGestureController.
    /// touchMoveTranslate`, qui opère directement sur la matrice de la dernière `Transform` (PAS
    /// `offsetX`/`offsetY`, corrigé le 2026-08-16 — la version initiale mutait `offsetX`/`offsetY`
    /// directement, une simplification qui aurait mal composé avec la rotation/l'échelle ajoutées
    /// ici : Android ne touche JAMAIS `offsetX`/`offsetY` par geste, tout passe par la matrice).
    func dragMoved(to point: CGPoint) {
        guard let id = selectedId, let idx = index(of: id) else {
            gestureDiagnostics = "DRAG at \(point) → IGNORÉ, aucun calque sélectionné (selectedId=\(selectedId ?? "nil"))"
            return
        }
        // Port du garde `!composer.getLayers().get(objectInAction).isLocked()`
        // (`GestureListener.onScroll`, `MemesView2.java:1577-1579`) — **ajouté le 2026-08-23
        // (V4-F-050, Phase B P1)**. Vérifié : Android n'applique PAS ce garde dans `touchDown`
        // (`selectObject` reste donc volontairement non gardé, sélectionner un calque verrouillé
        // reste possible) — seule la TRANSLATION réelle est bloquée.
        guard !layers[idx].locked else {
            gestureDiagnostics = "DRAG at \(point) → IGNORÉ, calque #\(idx) verrouillé"
            return
        }
        gestureController.touchMoveTranslate(to: point, objectIndex: idx, composer: composer)
        renderVersion += 1
        let values = layers[idx].transforms.last?.matrixValues ?? []
        let tx = values.count > 2 ? values[2] : -1
        let ty = values.count > 5 ? values[5] : -1
        gestureDiagnostics = "DRAG at \(point) → calque #\(idx) déplacé, matrice tx=\(tx) ty=\(ty)"
    }

    func dragEnded() {
        guard let id = selectedId, let idx = index(of: id) else { return }
        gestureController.touchUp(objectIndex: idx, composer: composer, engine: engine)
        if autoCaptureEnabled { recordKeyframe() }
        gestureDiagnostics += " | DRAG END sur calque #\(idx)"
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
        // Port du garde de verrouillage — voir note de `dragMoved` ci-dessus. Vérifié dans
        // `MemesView2.java` : `rotate(...)` n'est appelée QUE depuis `executeTouchEvent`, elle-même
        // sautée pour tout calque verrouillé par la boucle de `onTouchEvent` (ligne 1604-1609) —
        // **ajouté le 2026-08-23 (V4-F-050, Phase B P1)**.
        guard !layers[idx].locked else { return }
        gestureController.rotate(to: newDegrees, objectIndex: idx, composer: composer)
        renderVersion += 1
        gestureDiagnostics = "ROTATE calque #\(idx) → \(String(format: "%.1f", newDegrees))°"
    }

    /// Port de `scale`/`ScaleListener.onScale` — `incrementalFactor` est le ratio ENTRE deux
    /// valeurs cumulatives successives de `MagnificationGesture` (calculé par l'appelant SwiftUI,
    /// voir `AnimemesEditorView` — `AnimemesGestureController.scale` attend un facteur PAR
    /// ÉVÉNEMENT, pas cumulatif, voir sa documentation).
    func scaleChanged(incrementalFactor: CGFloat) {
        guard let id = selectedId, let idx = index(of: id), let bound = layers[idx].bound else {
            gestureDiagnostics = "SCALE ignoré — selectedId=\(selectedId ?? "nil"), bound présent=\(selectedId.flatMap { index(of: $0) }.flatMap { layers[$0].bound } != nil)"
            return
        }
        // Port du garde `!composer.getLayers().get(objectInAction).isLocked()`
        // (`ScaleListener.onScale`, `MemesView2.java:1587`) — **ajouté le 2026-08-23 (V4-F-050,
        // Phase B P1)**.
        guard !layers[idx].locked else {
            gestureDiagnostics = "SCALE ignoré — calque #\(idx) verrouillé"
            return
        }
        let clamped = AnimemesGestureController.clampPerEventScaleFactor(incrementalFactor)
        gestureController.scale(factor: clamped, focus: CGPoint(x: bound.midX, y: bound.midY), objectIndex: idx, composer: composer)
        renderVersion += 1
        let values = layers[idx].transforms.last?.matrixValues ?? []
        let scaleX = values.count > 0 ? values[0] : -1
        gestureDiagnostics = "SCALE calque #\(idx) → facteur=\(String(format: "%.3f", clamped)) scaleX résultant=\(String(format: "%.3f", scaleX))"
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

    // MARK: - Panneau d'édition de calque (`LayerEditorPanel.java`)

    /// Port de `showPanelEditor` — trace Android complète : `LayerEditorPanel` s'ouvre via
    /// `onTrackLongPressed(TimelineItem)` (`AnimemesCompound.java:1634-1637`, listener
    /// `TimelineView.OnTimelineListener`, appui long sur une piste). **Note d'implémentation** :
    /// `TimelineView.swift` compose déjà `DragGesture`+`MagnificationGesture` pour pan/scrub/
    /// glisser-item/redimensionner/pincer-zoomer — ce fichier a subi 2 fois cette session la même
    /// classe de bug (`.id(state.version)` détruisant le geste en cours, GAP-024 et sa réplique
    /// P0-5). Ajouter un `LongPressGesture` tiers en composition avec ces deux gestes déjà fragiles
    /// risquerait de réintroduire cette classe de bug sans un vrai test réel pour le vérifier (voir
    /// ANIMEMS_PARITY_AUDIT_V1.md §18.1). Choix assumé : un bouton dédié dans `bottomToolbar`
    /// (même famille que "masque"/"supprimer"/"réinitialiser", déjà gatés sur `selectedId != nil`)
    /// déclenche `bound(to:)` au lieu du long-press — substitution de DÉCLENCHEUR, PAS
    /// d'invention de fonctionnalité : le panneau, ses réglages et son résultat final restent
    /// identiques à Android, seul le geste d'ouverture diffère (plus détectable qu'un appui long
    /// non indicé visuellement, cohérent avec l'objectif de parité fonctionnelle > parité de geste
    /// exacte quand l'un des deux est nettement plus sûr à implémenter que l'autre).
    func snapshotLayerEditor() -> LayerEditorPanelState? {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return nil }
        return LayerEditorPanelState.bound(to: obj)
    }

    /// Port de `applyPropertiesToLayerForPreview` — écrit directement dans la DERNIÈRE `Transform`
    /// du calque sélectionné (lue en direct par `LayerRenderer.resolveVisualProperties`/
    /// `drawText`/etc., pas besoin de dupliquer un bitmap de travail comme Android : le rendu Core
    /// Graphics est déjà un re-rendu live à chaque frame, l'aperçu est donc gratuit). `renderVersion`
    /// — appelé à chaque glissement de slider, plusieurs fois par seconde, aucun changement
    /// structurel (pas de nouvelle piste de keyframe tant que "Valider" n'a pas été pressé).
    func applyLayerEditorPreview(_ panel: LayerEditorPanelState) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }),
              var tfm = obj.transforms.last
        else { return }
        tfm.opacity = panel.opacity
        tfm.cornerRadius = panel.cornerRadius
        tfm.feather = panel.feather
        tfm.color = Self.packTint(color: panel.tintColor, strength: panel.tintStrength)
        obj.transforms[obj.transforms.count - 1] = tfm
        bumpRenderVersion()
    }

    /// Port de `validateAndCreateKeyframe` — Android crée là 4 keyframes visuels (opacité/teinte/
    /// arrondi/flou) à la frame COURANTE du playhead, en plus d'écrire la valeur finale (déjà fait
    /// par `applyLayerEditorPreview` ci-dessus, appelé juste avant par l'appelant SwiftUI). `tint`
    /// Android est `(tintColor, tintStrength)` séparés ; iOS n'a qu'UNE seule piste `color` (ARGB
    /// packé, l'alpha EST la force de teinte — voir `LayerRenderer.drawTinted`, qui applique déjà
    /// la teinte proportionnellement à l'alpha) : `tintStrength` est donc fusionné dans l'octet
    /// alpha de `addColorKeyframe` plutôt que porté comme piste séparée, fidèle au modèle de rendu
    /// déjà en place plutôt qu'une reproduction 1:1 de la séparation interne d'Android qui n'a pas
    /// d'équivalent utile ici. `version` (pas `renderVersion`) — même choix que `recordKeyframe()`
    /// ci-dessus, la création d'une piste de keyframe est traitée comme structurelle par convention
    /// existante dans ce fichier, pas une décision nouvelle prise isolément pour cette fonction.
    func validateLayerEditor(_ panel: LayerEditorPanelState) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        applyLayerEditorPreview(panel)
        let ns = timeline.frameToTimestampNs(timeline.playheadFrame)
        obj.addOpacityKeyframe(ts: ns, v: panel.opacity)
        obj.addCornerRadiusKeyframe(ts: ns, v: panel.cornerRadius)
        obj.addFeatherKeyframe(ts: ns, v: panel.feather)
        obj.addColorKeyframe(ts: ns, argb: Self.packTint(color: panel.tintColor, strength: panel.tintStrength))
        version += 1
    }

    /// Port de `cancelLayerEditorPreview` — restaure la DERNIÈRE `Transform` à l'état capturé par
    /// `snapshotLayerEditor()` avant toute modification (pas de duplication de bitmap nécessaire,
    /// voir note d'`applyLayerEditorPreview`).
    func cancelLayerEditor(_ original: LayerEditorPanelState) {
        applyLayerEditorPreview(original)
    }

    /// `tintStrength` (`[0, 1]`) devient l'octet alpha du ARGB packé — `tintColor` fourni par la
    /// palette est déjà opaque (`0xFF......`, voir `LayerEditorPanelState.palette`), seul l'alpha
    /// est recalculé ici.
    private static func packTint(color: UInt32, strength: Float) -> UInt32 {
        guard color != 0 else { return 0 }
        let alpha = UInt32(max(0, min(1, strength)) * 255) << 24
        return alpha | (color & 0x00FF_FFFF)
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
        renderVersion += 1
    }

    /// Port de `maskScaleChanged` — `incrementalFactor` PAR ÉVÉNEMENT, même contrat que
    /// `scaleChanged(incrementalFactor:)` (objet) ci-dessus.
    func maskScaleChanged(incrementalFactor: CGFloat) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        obj.maskScale *= Float(incrementalFactor)
        renderVersion += 1
    }

    /// Port de `maskRotationChanged` — `deltaDegrees` DELTA (pas cumulatif), calculé par l'appelant
    /// depuis `RotationGesture.value.degrees` (cumulatif) comme `maskOffsetChanged` ci-dessus.
    func maskRotationChanged(deltaDegrees: CGFloat) {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        obj.maskRotation += Float(deltaDegrees)
        renderVersion += 1
    }

    /// Port de `onRecomposeClicked`/`performRecompose` (`AnimemesCompound.java:3464-3556`) —
    /// **beaucoup plus simple que prévu par l'audit initial** : contrairement à l'hypothèse d'une
    /// UI de multi-sélection dédiée, Android n'en a AUCUNE — `getRecomposeCandidates()` prend
    /// simplement TOUS les calques non verrouillés et visibles (exactement
    /// `AnimemesRecompose.candidates(from:)`, déjà porté), sans sélection manuelle. Un seul tap
    /// suffit. **Ajouté le 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-20, Phase B Lot 9)** —
    /// `AnimemesRecompose.buildComposedLayer(from:)` (logique pure, déjà écrite et jamais appelée)
    /// fait tout le travail de fusion ; ce correctif n'ajoute que le point d'entrée et
    /// l'orchestration timeline. Port de `src.setVisible(false)` (masque les calques sources après
    /// fusion, sinon ils resteraient visibles EN PLUS du résultat fusionné, rendu incohérent) —
    /// **PAS porté** : `recomposeGroupId`/`btn_view_group`/`btn_group_back` (voir-le-groupe/
    /// retour), `RecomposeManager` (sauvegarde disque + `btn_recompose_gallery`/"Load compose"),
    /// `AnimemesRecomposeNameSheet` (nommage) — décision de périmètre déjà documentée dans l'en-tête
    /// d'`AnimemesRecompose.swift`, reconduite ici, pas un oubli.
    /// - Returns: `false` si moins de 2 calques candidats ou si la fusion échoue (port de
    ///   `compose_needs_two_layers`/`compose_failed`, l'appelant SwiftUI affiche l'alerte).
    @discardableResult
    func performRecompose() -> Bool {
        let candidates = AnimemesRecompose.candidates(from: layers)
        guard candidates.count >= 2, let result = AnimemesRecompose.buildComposedLayer(from: candidates)
        else { return false }
        composer.addLayer(result)
        for src in candidates { src.visible = false }
        syncTimeline()
        version += 1
        return true
    }

    /// Port de `btn_removebg`/`onRemoveBgClicked` (`AnimemesCompound.java:3853-3908`) — **ajouté le
    /// 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-29, Phase B Lot 11)**. Aucune implémentation
    /// n'existait dans le module Animems, mais `RemoveBackground.swift` (module Galerie/éditeur
    /// photo simple) est le port du MÊME fichier Android partagé (`Utils/RemoveBackground.java`,
    /// catégorie "A+G" — importé par `AnimemesCompound.java` ET `CroperView.java` côté Android) —
    /// réutilisé tel quel, pas réécrit. Traite CHAQUE bitmap du calque (pas seulement le courant,
    /// fidèle à `onRemoveBgClicked` qui boucle sur `obj.getBitmaps()` en entier — un calque à
    /// plusieurs frames/textures doit garder son fond retiré sur toutes ses frames). Repli sur le
    /// bitmap d'origine si les deux tentatives échouent (`out[0] != null ? out[0] : src`, pas
    /// d'erreur propagée). Traitement sur une file d'arrière-plan (`DispatchQueue.global`), fidèle
    /// au thread dédié + `runOnUi` d'Android plutôt qu'un blocage du thread principal.
    @Published var isRemovingBackground = false

    func removeBackgroundFromSelected() {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }), !obj.bitmaps.isEmpty
        else { return }
        isRemovingBackground = true
        let source = obj.bitmaps
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = source.map { src in
                RemoveBackground.removeBackgroundWithVision(src) ?? RemoveBackground.removeBackgroundAdvanced(src) ?? src
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRemovingBackground = false
                guard let target = self.layers.first(where: { $0.id == id }) else { return }
                target.setBitmaps(results)
                self.version += 1
            }
        }
    }

    /// Port de `btn_duplicate` (`AnimemesCompound.java:1959-1965` → `AnimationObjectData.
    /// duplicate(data)` COPIE PROFONDE, PAS `duplicate2` — confirmé par lecture directe du site
    /// d'appel, pas supposé depuis le nom de méthode le plus probable) →
    /// `duplicateTimeline(dup, item)`, qui ajoute le duplicata comme nouveau calque avec le MÊME
    /// label/couleur/plage de frames que la source, SANS le sélectionner automatiquement (fidèle :
    /// aucun `itemSelected.put(0, item)` dans `duplicateTimeline`, et aucune des fonctions
    /// `addImage`/`addStyledText`/`addShape`/`addSticker` de ce fichier ne sélectionne non plus le calque
    /// qu'elle vient de créer — cohérence avec le reste du fichier, pas une omission). **Ajouté le
    /// 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-30, Phase B Lot 4)** : `AnimationObjectData.
    /// duplicate(_:)` existait déjà (copie profonde complète, jamais appelée) — seul le point
    /// d'entrée UI manquait.
    func duplicateSelected() {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        let dup = AnimationObjectData.duplicate(obj)
        composer.addLayer(dup)
        syncTimeline()
        version += 1
    }

    /// Port d'`undo` → `mView.deletePrecedenteDraw()`.
    ///
    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-036, Phase B P1-17)** — le
    /// commentaire précédent affirmait à tort la fidélité à ce bouton Android précis. Vérifié
    /// `ImageViewCanvas.java:317-326` (`deletePrecedenteDraw`) : opère sur
    /// `composer.getPaintLayers()`, une `ArrayList` SÉPARÉE de `composer.getLayers()`
    /// (`core/AnimationComposer.java:10,46-47`) — retire le DERNIER TRAIT DE DESSIN LIBRE
    /// uniquement, jamais une image/un sticker/un texte, et ne fait RIEN si `paintLayers` est
    /// vide (garde ligne 318). L'ancien `dropLast()` sur `composer.layers` retirait le dernier
    /// calque TOUTES catégories confondues — perte de données silencieuse (undo d'un trait
    /// pouvait en réalité supprimer le dernier sticker/image/texte).
    ///
    /// **Écart architectural assumé, documenté** : Android stocke les traits dans un conteneur
    /// RÉELLEMENT séparé (jamais mêlé aux calques normaux, jamais animé, toujours composité en
    /// arrière-plan avant tout le reste — `drawPath(canvas)` appelé AVANT la boucle sur
    /// `getLayers()`). Séparer réellement le conteneur côté iOS obligerait à ajouter un second
    /// passage de rendu à CHAQUE site (canevas live, miniature, export MP4/image) — hors périmètre
    /// de ce correctif. Un trait reste donc un `AnimationObjectData` `.bitmap` ordinaire dans
    /// `composer.layers` (rendu, animation, export inchangés), marqué `isFreehandStroke = true`
    /// (`addFreehandDrawing` ci-dessous) — `removeLast()` retrouve et retire spécifiquement le
    /// DERNIER calque ainsi marqué (peu importe sa position dans `composer.layers`), laissant tout
    /// le reste intact, fidèle au comportement OBSERVABLE d'Android (jamais d'image/sticker/texte
    /// supprimé), sans reproduire la règle de composition "toujours en arrière-plan".
    func removeLast() {
        guard let index = composer.layers.lastIndex(where: { $0.isFreehandStroke }) else { return }
        let removedId = composer.layers[index].id
        var updated = composer.layers
        updated.remove(at: index)
        composer.setLayers(updated)
        if selectedId == removedId { selectedId = nil }
        syncTimeline()
        version += 1
    }

    /// Port de `remover` (rangée du bas, confirmé réel par audit du 2026-08-16) — supprime le calque
    /// SÉLECTIONNÉ précisément, PAS forcément le dernier ajouté (distinct de `removeLast()`/`undo`
    /// ci-dessus, qui reste le bouton `undo` séparé de la rangée d'outils du haut).
    func deleteSelected() {
        guard let id = selectedId, let idx = index(of: id) else { return }
        var updated = composer.layers
        updated.remove(at: idx)
        composer.setLayers(updated)
        selectedId = nil
        // **Ajouté le 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-11, lot mode masque)** — supprimer
        // le calque en cours d'édition de masque doit aussi fermer le mode : sinon `isMaskEditMode`
        // reste bloqué à `true` en arrière-plan (le panneau disparaît puisqu'il exige `selectedId`,
        // mais l'état ne se réinitialise pas), et le PROCHAIN calque sélectionné hériterait
        // silencieusement du geste de masque au lieu du geste de transformation normal
        // (`combinedGesture` teste `state.isMaskEditMode` avant tout).
        isMaskEditMode = false
        syncTimeline()
        version += 1
    }

    /// Port de `reset_animation` (confirmé réel par audit : réinitialise l'animation du calque
    /// SÉLECTIONNÉ à une frame unique / efface ses keyframes, PAS une réinitialisation de tout le
    /// document) — collapse `transforms` à la dernière transform courante et vide toutes les pistes
    /// de keyframes (`AnimationObjectData.clearAllKeyframes()`, déjà porté).
    func resetSelected() {
        guard let id = selectedId, let obj = layers.first(where: { $0.id == id }) else { return }
        if let last = obj.transforms.last { obj.transforms = [last] }
        obj.clearAllKeyframes()
        syncTimeline()
        engine.prepare(composer: composer)
        version += 1
    }

    /// Port de `displayStickerListener.onDisplay(EMOJI/STICKER)` (confirmé réel par audit :
    /// `ic_smile`/`ic_sticker`) — même approche que la Galerie (`PhotoToolsView.addSticker`, clavier
    /// emoji natif iOS plutôt qu'un catalogue d'assets, voir audit dédié 2026-08-16 confirmant
    /// qu'Android lui-même n'a pas de catalogue custom ici) : l'emoji est rasterisé en bitmap via
    /// `UIGraphicsImageRenderer` (même stratégie que `ShapeFactory` pour les formes) puis ajouté
    /// comme calque `.sticker` (déjà pris en charge par `LayerRenderer.drawSticker`, jamais câblé
    /// à un point d'ajout avant ce tour).
    func addSticker(_ emoji: String, canvasSize: CGSize) {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let size = CGSize(width: 96, height: 96)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let font = UIFont.systemFont(ofSize: 72)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = trimmed.size(withAttributes: attrs)
            let origin = CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
            trimmed.draw(at: origin, withAttributes: attrs)
        }
        guard let cgImage = image.cgImage else { return }
        let obj = AnimationObjectData()
        obj.objectType = .sticker
        obj.addBitmap(cgImage)
        configureNewObject(obj, canvasSize: canvasSize, size: size)
        composer.addLayer(obj)
        syncTimeline()
        version += 1
    }

    /// Port du crayon (`ic_paint` → `mView.setAction("drawPath")`, confirmé réel par audit :
    /// dessin libre directement sur le canevas Animems, DISTINCT du peintre de la Galerie) — reçoit
    /// le tracé déjà rasterisé en image (fond transparent) par la vue (réutilise le même mécanisme
    /// de tracé que `FreeformCropView`, module Galerie, plutôt qu'un nouveau moteur de dessin) et
    /// l'ajoute comme un calque bitmap ordinaire, animable comme n'importe quel autre calque.
    func addFreehandDrawing(_ image: UIImage, canvasSize: CGSize) {
        guard let cgImage = image.cgImage else { return }
        let obj = AnimationObjectData()
        obj.objectType = .bitmap
        // V5-F-036 (Phase B P1-17) — marque ce calque comme trait de dessin libre, seul type que
        // `removeLast()`/le bouton "undo" doivent pouvoir retirer, voir sa doc pour le détail
        // complet.
        obj.isFreehandStroke = true
        obj.addBitmap(cgImage)
        configureNewObject(obj, canvasSize: canvasSize, size: image.size)
        obj.offsetX = 0
        obj.offsetY = 0
        composer.addLayer(obj)
        syncTimeline()
        version += 1
    }

    /// Port du chemin `automateCapture == true` d'`ic_paint` (`PaintPreviewEditorPanel.java`,
    /// confirmé réel par l'audit export/outils : DEUX modes distincts derrière ce même bouton
    /// selon `auto_checkbox`, pas un seul comme le laissait supposer l'en-tête d'origine
    /// d'`AnimemesDrawingView.swift`). **Ajouté le 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-26,
    /// Phase B Lot 7)** — `PaintCaptureController.frames` (une image par capture, cadence
    /// `delayMs`) alimente `setBitmaps`/`bitmapChangeIntervalMs`, mécanisme de cyclage bitmap déjà
    /// existant et câblé (`advanceBitmapFrame`, `AnimationEngine.tick`) — pas de nouveau moteur de
    /// lecture nécessaire, juste un nouveau POINT D'ENTRÉE alimentant un chemin déjà fonctionnel.
    func addCapturedPaintFrames(_ frames: [CGImage], delayMs: Int, canvasSize: CGSize) {
        guard let first = frames.first else { return }
        let obj = AnimationObjectData()
        obj.objectType = .bitmap
        obj.setBitmaps(frames)
        obj.bitmapChangeIntervalMs = delayMs
        let size = CGSize(width: first.width, height: first.height)
        configureNewObject(obj, canvasSize: canvasSize, size: size)
        obj.offsetX = 0
        obj.offsetY = 0
        composer.addLayer(obj)
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
    /// **`renderVersion` depuis le 2026-08-17 (P0-5), PAS `version`** — seul appelant :
    /// `TimelineView`'s geste de scrub (`combinedDragGesture`, cas `.scrub`), invoqué à CHAQUE frame
    /// de mouvement du doigt sur la règle. `engine.seek(to:)` déplace bien la position de lecture à
    /// chaque frame (nécessaire pour un scrub fluide), mais `version += 1` aurait aussi relancé
    /// `preparePlayback()`/`engine.prepare()` (recalcul de TOUTE la timeline) à chaque frame — même
    /// sur-déclenchement que GAP-024, jamais porté jusqu'ici à cette fonction précise.
    func scrub(toFrame frame: Int) {
        if engine.isPlaying { engine.pause() }
        engine.seek(to: frame)
        timeline.setPlayheadFrame(frame, external: true)
        renderVersion += 1
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

    /// Port de `AnimemesCompound.isAnimation()` (`AnimationUtils.isAnimation(composer, FrameCount)`)
    /// — vrai si au moins un calque porte une trajectoire animée. Signal Swift équivalent le plus
    /// fiable disponible dans ce portage : présence d'une piste de keyframes non vide sur au moins
    /// un calque (`hasKeyframes`) — Android teste aussi le nombre de `Transform` capturées par
    /// geste en mode `automateCapture`, chemin non porté dans cette passe (voir `MIGRATION_AUDIT.md`).
    var hasAnimation: Bool {
        composer.layers.contains { $0.hasKeyframes }
    }

    // MARK: - Modèles de mouvement (port de `saveAsMotionTemplate`/`MotionTemplateManager`,
    // 2026-08-16) — sauvegarde/réapplication LOCALE uniquement, voir `MotionTemplateManager.swift`
    // pour la partie communautaire/upload PAS portée dans cette passe (ampleur comparable à un
    // portage de fonctionnalité complet à part entière, voir `MIGRATION_AUDIT.md`).

    /// Port de `saveAsMotionTemplate(name)` (le nom du modèle Android n'a pas d'équivalent stocké
    /// ici — `MotionTemplate` n'a pas de champ `name` dans le modèle Java relu, seulement `id`/
    /// `createdAt` ; la date de création sert d'étiquette d'affichage côté iOS, voir
    /// `MotionTemplateGalleryView`).
    @discardableResult
    func saveAsTemplate(canvasSize: CGSize) -> Bool {
        guard !composer.layers.isEmpty else { return false }
        let template = MotionTemplateManager.extract(
            composer: composer, canvasWidth: Int(canvasSize.width), canvasHeight: Int(canvasSize.height),
            hasAudio: false, audioLocalPath: nil
        )
        MotionTemplateManager.save(template)
        return true
    }

    /// Port de `applyMotionTemplateInternal`/`applyTemplateWithAutoCreate`
    /// (`AnimemesCompound.java:2697-2784`) — **remplace la simplification "piste 0 seulement sur
    /// le calque sélectionné"** (ANIMEMS_PARITY_AUDIT_V1.md F-19, Phase B Lot 10) par le vrai
    /// algorithme multi-piste : chaque piste `i` du template est appliquée dans l'ORDRE, soit à un
    /// NOUVEAU calque vide auto-créé (pistes forme/masque — `isAutoCreatableTrack`, elles génèrent
    /// leur propre bitmap via `ShapeFactory`/masque, pas besoin de contenu existant), soit au
    /// PROCHAIN calque existant non encore consommé dans l'ordre du tableau (pistes bitmap/texte —
    /// elles animent un contenu qui doit déjà exister, fidèle à `apply()` qui ne reconstruit jamais
    /// leur bitmap). **PAS porté** : redimensionnement du canvas d'édition à `template.canvasWidth/
    /// Height` (`mView.setCustomSize`) — le ratio d'export reste celui choisi par l'utilisateur
    /// dans `spinnerResolution`, changer silencieusement ce réglage depuis un template serait une
    /// action inattendue non demandée par l'audit ; les icônes de piste (`updateTrackIcon`) —
    /// détail visuel de la timeline Android, sans équivalent dans `TimelineView.swift` actuel.
    func applyTemplate(_ template: MotionTemplate, canvasSize: CGSize) {
        let tracks = template.tracks
        guard !tracks.isEmpty else { return }
        let cW = Int(canvasSize.width), cH = Int(canvasSize.height)

        let existingLayers = layers
        let neededExisting = tracks.filter { !Self.isAutoCreatableTrack($0) }.count
        if existingLayers.count < neededExisting, neededExisting > 0 {
            templateMismatch = (needed: neededExisting, has: existingLayers.count)
            pendingTemplateApplication = { [weak self] in self?.applyTemplateTracks(template, existingLayers: existingLayers, cW: cW, cH: cH) }
            return
        }
        applyTemplateTracks(template, existingLayers: existingLayers, cW: cW, cH: cH)
    }

    /// Port d'`AnimationUtils.isAutoCreatableTrack` — SHAPE_*/MASK_RENDER n'ont pas besoin d'un
    /// calque existant (ils génèrent leur propre bitmap). Le repli Android sur le préfixe de label
    /// `"mask_"` (pistes masque LEGACY) n'est PAS porté — fidèle à la décision déjà documentée en
    /// tête de fichier `MotionTemplateManager.swift` : ce port ne produit jamais un tel label.
    private static func isAutoCreatableTrack(_ track: MotionTrack) -> Bool {
        track.isShape || track.isMaskRender
    }

    /// Port de la boucle centrale d'`applyTemplateWithAutoCreate`.
    private func applyTemplateTracks(_ template: MotionTemplate, existingLayers: [AnimationObjectData], cW: Int, cH: Int) {
        var existingIndex = 0
        for (i, track) in template.tracks.enumerated() {
            let targetObj: AnimationObjectData
            if Self.isAutoCreatableTrack(track) {
                let obj = AnimationObjectData()
                obj.id = UUID().uuidString
                obj.visible = true
                obj.isBackgroundTransparent = true
                obj.transforms = [Transform()]
                obj.label = track.label ?? "auto"
                composer.addLayer(obj)
                targetObj = obj
            } else {
                guard existingIndex < existingLayers.count else { continue }
                targetObj = existingLayers[existingIndex]
                existingIndex += 1
            }
            MotionTemplateManager.apply(template, to: targetObj, trackIndex: i, targetCanvasWidth: cW, targetCanvasHeight: cH)
        }
        syncTimeline()
        version += 1
    }

    /// Port de `showTemplateMismatchDialog` — Android propose 3 boutons mais DEUX ("Appliquer
    /// quand même"/"Sur l'objet sélectionné") appellent la MÊME méthode avec les MÊMES arguments
    /// (lu ligne par ligne : aucune branche réelle ne les distingue), donc net-net seulement 2
    /// comportements réels existent (appliquer quand même / annuler) — reproduit avec exactement
    /// ces 2 options, pas une simplification par rapport à Android, une fidélité à son comportement
    /// RÉEL plutôt qu'à son apparence à 3 boutons.
    @Published var templateMismatch: (needed: Int, has: Int)?
    private var pendingTemplateApplication: (() -> Void)?

    func confirmTemplateMismatch() {
        pendingTemplateApplication?()
        pendingTemplateApplication = nil
        templateMismatch = nil
    }

    func cancelTemplateMismatch() {
        pendingTemplateApplication = nil
        templateMismatch = nil
    }

    /// Port de `save_animemes2` → `showSaveDialog()`/`saveBitmapDrawed()` — branche sur
    /// `isAnimation()` comme l'original : export vidéo réel si au moins un calque est animé, sinon
    /// sauvegarde d'une image statique (JPEG, qualité 70 comme `BitmapManager.fromBitmapToImage`
    /// côté Android, `createImage`). PAS de GIF — **vérifié le 2026-08-18 (P2) : `DEAD_CODE` côté
    /// Android lui-même**, pas un gap à combler. `android.codec.AnimatedGifEncoder.java`/
    /// `GIFView.java` existent dans le module `engine` mais ne sont référencés par AUCUN appelant
    /// (`grep` exhaustif) — `showSaveDialog()` (`AnimemesCompound.java`, le vrai menu de
    /// sauvegarde) n'expose que vidéo/template, jamais GIF. Construire cet export ici inventerait
    /// une fonctionnalité qu'Android n'expose jamais à l'utilisateur.
    func export(canvasSize: CGSize, completion: @escaping (URL?) -> Void) {
        guard !composer.layers.isEmpty else { return }
        guard hasAnimation else {
            completion(exportStaticImage(canvasSize: canvasSize))
            return
        }
        isExporting = true
        exportError = nil
        // Port de la note tête de fichier F-23 : passer explicitement la police/couleur réelles de
        // l'éditeur (`Self.textFont`/`Self.textColor`), au lieu de laisser l'exporteur retomber sur
        // ses propres valeurs par défaut divergentes — voir la note complète au-dessus de `init()`.
        let exporter = AnimemesExporter(composer: composer, font: Self.textFont, textColor: Self.textColor)
        exporter.outputSize = canvasSize
        exporter.viewSize = canvasSize
        exporter.audioURL = audioURL // port de "Ajouter un son" — déjà pris en charge par l'exporteur.
        activeExporter = exporter // V5-F-094 : retenu fortement pour toute la durée du pipeline async.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        exporter.export(to: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isExporting = false
                self.activeExporter = nil
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

    /// Port de `createImage` — aplatit l'état statique actuel des calques (dernière transform de
    /// chaque calque, pas de lecture de keyframes puisque `!hasAnimation` par construction ici) en
    /// une seule bitmap via le même chemin de rendu que l'aperçu figé (`LayerRenderer.
    /// drawLastTransform`), puis écrit un JPEG qualité 70 — mêmes réglages que
    /// `BitmapManager.fromBitmapToImage(context, bitmap, 3, 70)` (le paramètre `3` Android est un
    /// facteur d'échelle non pertinent ici, la bitmap est déjà à la résolution du canevas).
    private func exportStaticImage(canvasSize: CGSize) -> URL? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { context in
            for obj in composer.layers {
                guard obj.visible else { continue }
                switch obj.objectType {
                case .bitmap, .shapeRect, .shapeCircle, .shapeLine:
                    LayerRenderer.drawLastTransform(
                        obj, in: context.cgContext, currentNs: 0, isSliderPreview: true,
                        bitmapCache: bitmapCache, viewSize: canvasSize
                    )
                case .text:
                    LayerRenderer.drawText(obj, in: context.cgContext, textRect: textRect, viewSize: canvasSize)
                case .sticker:
                    LayerRenderer.drawSticker(obj, in: context.cgContext)
                default:
                    break
                }
            }
        }
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do {
            try jpegData.write(to: url)
            return url
        } catch {
            exportError = "L'export a échoué."
            return nil
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
///
/// **Corrigé le 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-05, P0)** : les 3 callbacks ci-dessous
/// bumpaient `version` — qui pilote `.onChange(of: state.version) { preparePlayback() }`
/// (`AnimemesEditorView.swift`), un rebuild O(objets×frames) de TOUTE la table de transformation
/// via `engine.prepare(composer:)`. `AnimationEngine.tick(...)` (`AnimationEngine.swift:211-218`)
/// appelle `didPlayFrame` PUIS `animationEngineDidInvalidate` À CHAQUE FRAME de lecture (~30×/s) —
/// ce qui déclenchait donc DEUX rebuilds complets par frame rendue pendant toute la durée de la
/// lecture. Or `preparePlayback()` n'est nécessaire QU'UNE FOIS, avant le début de la lecture
/// (`togglePlayback()` l'appelle déjà explicitement, ligne ~515, avant `engine.play(...)`) — la
/// table de transformation ne change pas pendant la lecture elle-même (aucun calque/keyframe n'est
/// ajouté/retiré), seul le playhead avance, ce qui necessite un REDESSIN, pas un rebuild structurel.
/// Les 3 callbacks utilisent donc maintenant `bumpRenderVersion()` (même mécanisme léger déjà
/// utilisé par les gestes continus, voir sa doc de tête de fichier) — `animationEngineDidPause`
/// n'a jamais eu besoin de toucher `version`/`renderVersion` (aucun changement visuel à ce moment,
/// `isPlaying = false` suffit à mettre à jour l'icône play/pause via `@Published`).
extension AnimemesEditorState: AnimationEnginePlaybackDelegate {
    nonisolated func animationEngine(_ engine: AnimationEngine, didPlayFrame frame: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.timeline.setPlayheadFrame(frame, external: false)
            self.isPlaying = true
            self.bumpRenderVersion()
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
            self.bumpRenderVersion()
        }
    }

    nonisolated func animationEngineDidInvalidate(_ engine: AnimationEngine) {
        Task { @MainActor [weak self] in self?.bumpRenderVersion() }
    }
}
