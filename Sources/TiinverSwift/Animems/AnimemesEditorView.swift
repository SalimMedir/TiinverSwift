import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Assemble un écran d'éditeur RÉEL autour du moteur Animems déjà porté (`AnimationComposer`/
/// `AnimationObjectData`/`LayerRenderer`/`ShapeFactory`/`AnimemesExporter`, lus en entier le
/// 2026-08-15) — port de `AnimemesCompound.java`/`compound_animemes_layout.xml`, PAS une réécriture
/// du moteur.
///
/// **Parité UI/comportement avec Android reconstruite depuis une capture d'écran réelle
/// (2026-08-16)**, précédée d'un audit dédié call-chain sur CHAQUE contrôle visible (pas deviné
/// depuis les icônes) : barre du haut (vitesse d'animation/capture automatique/ratio/son), barre
/// d'outils verticale droite (texte/dessin/emoji/sticker/image/répéter-fond/formes/modèles
/// communautaires), contrôles de zoom gauche, barre de lecture, timeline, rangée d'outils du bas
/// (Generate with AI/Compose/Load compose/Modèle/supprimer/réinitialiser/chronologie/undo).
///
/// **Éléments confirmés RÉELS par l'audit et câblés ici** (voir `AnimemesEditorState.swift` pour
/// le détail de chaque nouvelle méthode) : dessin libre (`ic_paint`→`drawPath`, nouveau
/// `AnimemesDrawingView.swift`), sticker/emoji (`ic_smile`/`ic_sticker`, `addSticker`), son
/// (`AnimemesExporter.audioURL` — déjà pris en charge par l'exporteur, seul le point d'entrée UI
/// manquait), capture automatique (approximée par un keyframe auto-enregistré en fin de glissement,
/// voir doc de `autoCaptureEnabled`), ratio de canevas (`spinnerResolution`, contrôle aussi la
/// résolution d'export), suppression du calque sélectionné (`remover`, distinct de `undo`),
/// réinitialisation de l'animation du calque sélectionné (`reset_animation`).
///
/// **Confirmés RÉELS mais délibérément PAS reproduits, code mort ou hors périmètre documenté** :
/// "Generate with AI" (`btn_ai_generate`) — bouton et gestionnaire RÉELS côté Android, mais
/// `aiObjectDelegate` n'est JAMAIS assigné nulle part dans le dépôt (`grep` exhaustif) : au tap,
/// Android lui-même ne fait RIEN de visible (juste un log "aiObjectDelegate not set"). Bouton
/// affiché ici pour la parité visuelle, mais SANS action câblée, fidèle à ce comportement réel —
/// PAS une fonctionnalité inventée. "Compose"/"Load compose" (`btn_recompose`/
/// `btn_recompose_gallery`) — RÉELS et fonctionnels côté Android (fusion de calques + rechargement
/// local), mais périmètre comparable à une fonctionnalité séparée à part entière (persistance
/// locale dédiée, `RecomposeManager`, jamais lue en détail) — DIFFÉRÉS, boutons affichés en grisé
/// plutôt que masqués (la capture les montre, les masquer serait un écart visuel de plus).
/// "Répéter l'image de fond" (`ic_repeate`) — approximé par un aplatissement de la frame courante
/// en nouveau calque statique, pas la reconstruction exacte de `onRepeateImage`/`CroperView`.
struct AnimemesEditorView: View {
    var onClose: () -> Void

    @StateObject private var state = AnimemesEditorState()
    @State private var canvasSize: CGSize = CGSize(width: 360, height: 640)
    @State private var showGalleryPicker = false
    @State private var showTextPrompt = false
    @State private var newText = ""
    @State private var showStickerPrompt = false
    @State private var newSticker = ""
    @State private var showDrawing = false
    @State private var showAudioPicker = false
    @State private var showShapePanel = false
    @State private var lastMagnification: CGFloat = 1.0
    @State private var isPinching = false
    @State private var exportedURL: URL?
    @State private var showDurationSlider = false
    @State private var lastMaskDragTranslation: CGSize = .zero
    @State private var lastMaskMagnification: CGFloat = 1.0
    @State private var lastMaskRotationDegrees: CGFloat = 0
    @State private var showSaveOptions = false
    @State private var showTemplateGallery = false
    @State private var showCommunityGallery = false
    /// Port de `showPanelEditor`/`LayerEditorPanel` — voir
    /// `AnimemesEditorState.snapshotLayerEditor()` pour le raisonnement complet (déclencheur bouton
    /// dédié plutôt qu'appui long sur la timeline, Phase B Lot 3).
    @State private var showLayerEditor = false
    @State private var layerEditorSnapshot: LayerEditorPanelState?
    /// Port de `ShapeAddPanel`→`ShapePreviewEditorPanel` — voir
    /// `AnimemesEditorState.beginAddingShape(_:canvasSize:)`/`finalizeShape(_:canvasSize:)` (Phase
    /// B Lot 5). `AnimationObjectData` étant une classe, cet objet en cours de configuration est
    /// muté EN PLACE par le panneau avant confirmation — pas encore ajouté à `composer.layers`
    /// tant que "Ajouter" n'a pas été pressé.
    @State private var pendingShapeData: AnimationObjectData?
    @State private var showShapeConfigPanel = false
    /// Port de `btn_bezier` (`AnimemesCompound.java:1970-1980`, confirmé réel par DEUX lectures
    /// indépendantes cette session, résolvant le risque mono-source noté au §18.2 de
    /// `ANIMEMS_PARITY_AUDIT_V1.md`). **Fidélité importante trouvée en traçant ce bouton** :
    /// `bezierEditor.setOnControlPointChangedListener(...)` (l'API RÉELLE de sortie de
    /// `BezierEditorView.java`, confirmée par lecture de ce fichier) n'est JAMAIS appelé dans
    /// `AnimemesCompound.java` — la courbe éditée n'est donc consommée NULLE PART côté Android,
    /// `Keyframe.EasingType` (4 valeurs fixes : linear/easeIn/easeOut/easeInOut) n'a d'ailleurs pas
    /// de cas pour une courbe custom. C'est un outil visuel réellement togglable mais SANS effet
    /// sur l'animation, des deux côtés — reproduit tel quel ici (afficher/masquer un
    /// `BezierEditorView.swift` déjà entièrement porté, sans le relier au moteur de keyframes) :
    /// le relier réellement au easing serait AJOUTER une fonctionnalité qu'Android lui-même
    /// n'expose pas, pas combler un écart de parité.
    @State private var showBezierEditor = false
    @State private var bezierPoints = BezierControlPoints.easeInOutDefault
    @State private var templateSavedToast = false
    @State private var showTimeline = true
    @State private var showRightTools = true
    @State private var selectedSpeedIndex = 0
    @State private var selectedRatioIndex = 0

    /// Port de `R.array.frame_duration_array2` (`values-fr/strings.xml`, position 0 = "très
    /// rapide", confirmée par capture d'écran) — voir `AnimemesEditorState.autoCaptureEnabled` pour
    /// la limite assumée sur l'effet réel de ce réglage (modèle de moteur différent d'Android).
    private static let speedOptions = ["très rapide", "rapide", "normal", "lent", "très lent"]
    /// Port de `R.array.resolution` (`values/strings.xml`) — ordre confirmé par capture (9:16 par
    /// défaut).
    private static let ratioOptions: [(label: String, ratio: CGFloat)] = [
        ("9:16", 9.0 / 16.0), ("16:9", 16.0 / 9.0), ("3:4", 3.0 / 4.0), ("1:1", 1.0),
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            gestureDiagnosticsHUD
            canvasArea
            playbackBar
            if state.isMaskEditMode, let selectedId = state.selectedId, let obj = state.layers.first(where: { $0.id == selectedId }) {
                maskPanel(for: obj)
            } else if showBezierEditor {
                // Port de `bezierEditor` remplaçant timeline/frameList/mRecyclerView pendant
                // qu'il est visible (`AnimemesCompound.java:1972-1975`) — même agencement ici,
                // remplace la zone timeline plutôt que de se superposer.
                BezierEditorView(points: $bezierPoints)
                    .frame(height: 220)
                    .background(Color.black)
            } else if showTimeline {
                TimelineView(state: state)
                if showDurationSlider, let selectedId = state.selectedId, let obj = state.layers.first(where: { $0.id == selectedId }) {
                    durationSlider(for: obj)
                }
            }
            bottomToolbar
        }
        .background(Color.black)
        .statusBarHidden(false)
        .sheet(isPresented: $showGalleryPicker) {
            GalleryPickerView(
                onImagePicked: { url in
                    showGalleryPicker = false
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        state.addImage(image, canvasSize: canvasSize)
                    }
                },
                onVideoPicked: { _ in showGalleryPicker = false },
                onCancel: { showGalleryPicker = false }
            )
        }
        .alert("Ajouter du texte", isPresented: $showTextPrompt) {
            TextField("Texte", text: $newText)
            Button("Ajouter") { state.addText(newText, canvasSize: canvasSize); newText = "" }
            Button("Annuler", role: .cancel) { newText = "" }
        }
        .alert("Ajouter un emoji", isPresented: $showStickerPrompt) {
            TextField("Emoji", text: $newSticker)
            Button("Ajouter") { state.addSticker(newSticker, canvasSize: canvasSize); newSticker = "" }
            Button("Annuler", role: .cancel) { newSticker = "" }
        } message: {
            Text("Touche le globe du clavier pour choisir un emoji.")
        }
        .fullScreenCover(isPresented: $showDrawing) {
            AnimemesDrawingView(
                canvasSize: canvasSize,
                onDone: { image in
                    state.addFreehandDrawing(image, canvasSize: canvasSize)
                    showDrawing = false
                },
                onCancel: { showDrawing = false }
            )
        }
        .confirmationDialog("Ajouter une forme", isPresented: $showShapePanel, titleVisibility: .visible) {
            Button("Rectangle") {
                pendingShapeData = state.beginAddingShape(.shapeRect, canvasSize: canvasSize)
                showShapeConfigPanel = true
            }
            Button("Cercle") {
                pendingShapeData = state.beginAddingShape(.shapeCircle, canvasSize: canvasSize)
                showShapeConfigPanel = true
            }
            Button("Ligne") {
                pendingShapeData = state.beginAddingShape(.shapeLine, canvasSize: canvasSize)
                showShapeConfigPanel = true
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showShapeConfigPanel) {
            if let data = pendingShapeData {
                ShapePreviewEditorPanelView(
                    data: data, canvasSize: canvasSize,
                    onConfirm: { finalized in
                        state.finalizeShape(finalized, canvasSize: canvasSize)
                        showShapeConfigPanel = false
                        pendingShapeData = nil
                    },
                    onCancel: {
                        showShapeConfigPanel = false
                        pendingShapeData = nil
                    }
                )
            }
        }
        .fileImporter(isPresented: $showAudioPicker, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { state.audioURL = url }
        }
        .sheet(item: Binding(get: { exportedURL.map(ExportedVideo.init) }, set: { exportedURL = $0?.url })) { export in
            ShareLink(item: export.url) { Label("Partager l'export", systemImage: "square.and.arrow.up") }
                .padding()
        }
        .confirmationDialog("Enregistrer", isPresented: $showSaveOptions, titleVisibility: .visible) {
            Button("Exporter la vidéo") { state.export(canvasSize: canvasSize) { url in exportedURL = url } }
            Button("Enregistrer comme modèle") {
                if state.saveAsTemplate(canvasSize: canvasSize) { templateSavedToast = true }
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showTemplateGallery) {
            MotionTemplateGalleryView(
                onSelect: { template in
                    state.applyTemplate(template, canvasSize: canvasSize)
                    showTemplateGallery = false
                },
                onClose: { showTemplateGallery = false }
            )
        }
        .sheet(isPresented: $showCommunityGallery) {
            CommunityTemplateGalleryView(
                onSelect: { template in
                    state.applyTemplate(template, canvasSize: canvasSize)
                    showCommunityGallery = false
                },
                onClose: { showCommunityGallery = false }
            )
        }
        .alert("Modèle enregistré", isPresented: $templateSavedToast) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showLayerEditor) {
            if let snapshot = layerEditorSnapshot, let selectedId = state.selectedId,
               let obj = state.layers.first(where: { $0.id == selectedId }) {
                LayerEditorPanelView(
                    objectType: obj.objectType, original: snapshot,
                    onPreview: { state.applyLayerEditorPreview($0) },
                    onValidate: { state.validateLayerEditor($0) },
                    onCancel: { state.cancelLayerEditor($0) },
                    onDismiss: { showLayerEditor = false }
                )
            }
        }
    }

    // MARK: - Barre du haut (port de `spinner`/`auto_checkbox`/`spinnerResolution`/`btn_add_sound`,
    // `close_animemes`/`save_animemes2` — tous confirmés réels par l'audit du 2026-08-16)

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { onClose() } label: { // close_animemes
                    Image(systemName: "xmark")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
                VStack(alignment: .center, spacing: 0) {
                    Text("Vitesse d'animation").font(.caption2).foregroundStyle(.secondary)
                    Picker("Vitesse", selection: $selectedSpeedIndex) {
                        ForEach(Self.speedOptions.indices, id: \.self) { i in Text(Self.speedOptions[i]).tag(i) }
                    }
                    .pickerStyle(.menu)
                }
                Spacer()
                saveButton // save_animemes2
            }

            HStack {
                Button {
                    state.autoCaptureEnabled.toggle() // auto_checkbox
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.autoCaptureEnabled ? "checkmark.square.fill" : "square")
                        Text("Capture automatique").font(.caption)
                    }
                }
                .foregroundStyle(.primary)
                Spacer()
                Picker("Ratio", selection: $selectedRatioIndex) { // spinnerResolution
                    ForEach(Self.ratioOptions.indices, id: \.self) { i in Text(Self.ratioOptions[i].label).tag(i) }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Button { showAudioPicker = true } label: { // btn_add_sound
                    Label(state.audioURL == nil ? "Ajouter un son" : (state.audioURL?.lastPathComponent ?? "Son ajouté"), systemImage: "music.note")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(.primary)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    /// HUD de diagnostic AFFICHÉ À L'ÉCRAN (pas seulement console) — demande explicite de
    /// l'utilisateur suite au rapport "les transformations ne fonctionnent pas réellement dans
    /// Appetize". Trace GESTURE → CONTROLLER → STATE → TRANSFORM en direct, TEMPORAIRE, à retirer
    /// une fois la cause racine confirmée par un run réel.
    private var gestureDiagnosticsHUD: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("selectedId=\(state.selectedId ?? "nil") · calques=\(state.layers.count) · canvasSize=\(Int(canvasSize.width))×\(Int(canvasSize.height))")
                .font(.system(size: 9, design: .monospaced))
            Text(state.gestureDiagnostics)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(2)
        }
        .foregroundStyle(.green)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black)
    }

    private var saveButton: some View {
        Group {
            if state.isExporting {
                ProgressView()
            } else {
                Button {
                    if state.hasAnimation {
                        showSaveOptions = true
                    } else {
                        state.export(canvasSize: canvasSize) { url in exportedURL = url }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor, in: Circle())
                }
                .disabled(state.layers.isEmpty)
            }
        }
    }

    // MARK: - Canevas (port de `MemesView2.onDraw`, ratio/zoom/toolbar superposés)

    /// Port de `MemesView2.onDraw` — rendu conscient du playhead (`LayerRenderer.drawObjectFrame`,
    /// 2026-08-16), remplace l'ancien rendu toujours-dernière-transform (`drawLastTransform`,
    /// équivalent à un playhead figé sur la dernière frame). `drawObjectFrame` interroge les pistes
    /// de keyframes EN DIRECT (voir note `AnimemesEditorState.preparePlayback`) — `localTransformIndex`
    /// n'est qu'un REPLI pour les calques sans keyframe matrice (transform unique posée par geste).
    private var canvasArea: some View {
        GeometryReader { outerGeo in
            let fitSize = Self.fittedSize(for: Self.ratioOptions[selectedRatioIndex].ratio, in: outerGeo.size)
            ZStack {
                Canvas { context, size in
                    context.withCGContext { cgContext in
                        let frame = state.timeline.playheadFrame
                        let ns = state.timeline.frameToTimestampNs(frame)
                        for (index, obj) in state.layers.enumerated() {
                            guard obj.visible else { continue }
                            switch obj.objectType {
                            case .bitmap, .shapeRect, .shapeCircle, .shapeLine:
                                let localIndex = state.localTransformIndex(forLayer: index, frame: frame)
                                let tfm = localIndex.flatMap { obj.transforms.indices.contains($0) ? obj.transforms[$0] : nil }
                                    ?? obj.transforms.last ?? Transform()
                                LayerRenderer.drawObjectFrame(
                                    obj, transform: tfm, frameIndex: localIndex ?? 0, in: cgContext,
                                    currentNs: ns, viewSize: size
                                )
                            case .text:
                                LayerRenderer.drawText(obj, in: cgContext, textRect: state.textRect, viewSize: size)
                            case .sticker:
                                LayerRenderer.drawSticker(obj, in: cgContext)
                            default:
                                break
                            }
                        }
                    }
                }
                .frame(width: fitSize.width, height: fitSize.height)
                .background(Color(white: 0.08))
                .gesture(combinedGesture)
                .onAppear { canvasSize = fitSize; state.preparePlayback(canvasSize: fitSize) }
                .onChange(of: fitSize) { newSize in canvasSize = newSize; state.preparePlayback(canvasSize: newSize) }
                .onChange(of: state.version) { _ in state.preparePlayback(canvasSize: canvasSize) }

                zoomControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 8)

                rightToolbar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            .frame(width: outerGeo.size.width, height: outerGeo.size.height)
        }
        .frame(height: 360)
    }

    /// Ajuste `available` au ratio largeur/hauteur demandé, en restant dans les deux dimensions.
    private static func fittedSize(for ratio: CGFloat, in available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return available }
        let byWidth = CGSize(width: available.width, height: available.width / ratio)
        if byWidth.height <= available.height { return byWidth }
        return CGSize(width: available.height * ratio, height: available.height)
    }

    /// Port des contrôles de zoom gauche (`+`/`1.0x`/`-`/`fit`) — zoom VISUEL du canevas dans son
    /// conteneur, indépendant de `canvasSize` (résolution réelle des calques/de l'export, pilotée
    /// par le ratio ci-dessus) : Android sépare aussi le zoom d'affichage (`ScaleGestureDetector`
    /// sur `MemesView2`) de la résolution d'export (`spinnerResolution`), deux réglages distincts.
    @State private var displayZoom: CGFloat = 1.0
    private var zoomControls: some View {
        VStack(spacing: 6) {
            Button { displayZoom = min(3, displayZoom + 0.25) } label: {
                Image(systemName: "plus").frame(width: 32, height: 32)
            }
            Text(String(format: "%.1fx", displayZoom)).font(.caption2)
            Button { displayZoom = max(0.5, displayZoom - 0.25) } label: {
                Image(systemName: "minus").frame(width: 32, height: 32)
            }
            Button { displayZoom = 1.0 } label: {
                Text("fit").font(.caption2)
            }
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Port de la barre d'outils verticale droite (`compound_animemes_layout.xml:196-331`) — ordre
    /// EXACT confirmé par l'audit : chevron (réduire/agrandir) / Tt (texte) / crayon (dessin) /
    /// smiley (emoji) / image+ (sticker) / + (image galerie) / boucle (répéter fond) / formes /
    /// étincelle (modèles communautaires).
    private var rightToolbar: some View {
        VStack(spacing: 14) {
            Button { showRightTools.toggle() } label: {
                Image(systemName: showRightTools ? "chevron.up" : "chevron.down")
            }
            if showRightTools {
                Button { showTextPrompt = true } label: { Text("Tt").font(.headline.bold()) } // ic_text
                Button { showDrawing = true } label: { Image(systemName: "pencil") } // ic_paint
                Button { showStickerPrompt = true } label: { Image(systemName: "face.smiling") } // ic_smile
                Button { showStickerPrompt = true } label: { Image(systemName: "photo.badge.plus") } // ic_sticker — même clavier emoji natif que ic_smile, voir doc de tête de fichier PhotoToolsView sur l'absence de catalogue custom côté Android
                Button { showGalleryPicker = true } label: { Image(systemName: "plus") } // ic_add
                Button { repeatBackgroundImage() } label: { Image(systemName: "arrow.triangle.2.circlepath") } // ic_repeate
                Button { showShapePanel = true } label: { Image(systemName: "square.on.circle") } // btn_shape
                Button { showCommunityGallery = true } label: { Image(systemName: "sparkles") } // btn_display_online_template
            }
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(10)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
    }

    /// Port approximé d'`onRepeateImage`/`ic_repeate` (confirmé réel par l'audit : aplatit l'état
    /// visible courant en un nouveau calque bitmap statique via `CroperView`) — réutilise le même
    /// chemin de rendu que l'export image statique (`LayerRenderer.drawLastTransform`) plutôt que de
    /// reconstruire `CroperView`, puis ajoute le résultat comme nouveau calque via
    /// `addFreehandDrawing` (même signature : image déjà à l'échelle du canevas).
    private func repeatBackgroundImage() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { context in
            for obj in state.layers {
                guard obj.visible else { continue }
                switch obj.objectType {
                case .bitmap, .shapeRect, .shapeCircle, .shapeLine:
                    LayerRenderer.drawLastTransform(
                        obj, in: context.cgContext, currentNs: 0, isSliderPreview: true,
                        bitmapCache: state.bitmapCache, viewSize: canvasSize
                    )
                case .text:
                    LayerRenderer.drawText(obj, in: context.cgContext, textRect: state.textRect, viewSize: canvasSize)
                case .sticker:
                    LayerRenderer.drawSticker(obj, in: context.cgContext)
                default:
                    break
                }
            }
        }
        state.addFreehandDrawing(image, canvasSize: canvasSize)
    }

    /// Port de la barre de lecture (`AnimemesCompound.java:2007-2019` — bouton play/pause unique) +
    /// bouton ◆ (`captureTransformKeyframe`, voir `AnimemesEditorState.recordKeyframe`) + accès à la
    /// durée du calque sélectionné.
    private var playbackBar: some View {
        HStack(spacing: 20) {
            Button {
                state.togglePlayback(canvasSize: canvasSize)
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor, in: Circle())
            }
            .disabled(state.layers.isEmpty)

            Text(String(format: "%.1fs", Double(state.timeline.playheadFrame) / Double(max(1, state.engine.frameRate))))
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))

            Spacer()

            // Port du bouton ◆ — enregistre un keyframe matrice pour le calque sélectionné à la
            // position actuelle du playhead (modèle "marqueur explicite", voir audit).
            Button { state.recordKeyframe() } label: {
                Image(systemName: "diamond.fill")
            }
            .disabled(state.selectedId == nil)

            Button { showDurationSlider.toggle() } label: {
                Image(systemName: "timer")
            }
            .disabled(state.selectedId == nil)

            Button { showTimeline.toggle() } label: { // chevron bas de la capture, sous le bouton lecture
                Image(systemName: showTimeline ? "chevron.down" : "chevron.up")
            }
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    /// Port du glissement de poignée de durée (raccourci équivalent, voir
    /// `AnimemesEditorState.setSelectedDuration`) — durée en secondes du calque sélectionné.
    private func durationSlider(for obj: AnimationObjectData) -> some View {
        let totalFrames = max(1, state.engine.totalFramesMinus1 + 1)
        let currentSeconds = Double(obj.endFrame - obj.startFrame + 1) / Double(max(1, state.engine.frameRate))
        return HStack {
            Text("Durée").font(.caption).foregroundStyle(.white.opacity(0.7))
            Slider(
                value: Binding(
                    get: { currentSeconds },
                    set: { state.setSelectedDuration(seconds: $0) }
                ),
                in: 0.5...Double(max(1, totalFrames * 2)) / Double(max(1, state.engine.frameRate))
            )
            Text(String(format: "%.1fs", currentSeconds)).font(.caption.monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    /// Port RÉEL de `MemesView2.onTouchEvent` (translation/rotation/échelle simultanées, 2026-08-16)
    /// — délègue entièrement à `AnimemesGestureController` via `AnimemesEditorState`. `obj.bound`
    /// est rempli par le DERNIER passage de rendu (`LayerRenderer.drawLastTransform`/`drawText`,
    /// effet de bord sur l'objet lui-même) — utilisé ici pour la détection de calque touché, sans
    /// duplication de la logique de hit-test.
    ///
    /// Les trois gestes sont combinés via `SimultaneousGesture` pour permettre pincer+pivoter+
    /// glisser en une seule interaction (comme les deux doigts d'Android le permettent nativement).
    /// `RotationGesture`/`MagnificationGesture` rapportent des valeurs CUMULATIVES depuis le début
    /// du geste — voir les commentaires de `beginPinchRotate()`/`rotationChanged(to:)`/
    /// `scaleChanged(incrementalFactor:)` dans `AnimemesEditorState` pour la réconciliation avec
    /// l'API par delta d'`AnimemesGestureController`.
    ///
    /// **Mode masque (2026-08-16) fusionné DANS ces mêmes gestes plutôt que dans un second jeu de
    /// gestes séparé** — une première tentative câblait `combinedGesture`/`maskEditGesture` comme
    /// deux compositions `SimultaneousGesture` DISTINCTES, choisies par ternaire selon `isMaskEditMode`
    /// (`.gesture(cond ? maskEditGesture : combinedGesture)`). Le premier build réel couvrant ce
    /// fichier a échoué à répétition sur cette approche (`some Gesture` opaque non unifiable entre
    /// deux déclarations distinctes malgré une structure identique, PUIS ambiguïté de type-checking
    /// même après érasure explicite via `AnyGesture` — deux échecs de compilation successifs, jamais
    /// vérifiables localement faute d'environnement macOS). Corrigé en éliminant le problème à la
    /// racine : UN SEUL jeu de gestes (`some Gesture` simple, pas d'érasure de type nécessaire), dont
    /// chaque `onChanged`/`onEnded` bascule sur `state.isMaskEditMode` À L'EXÉCUTION plutôt que le
    /// type du geste lui-même changeant selon le mode.
    private var combinedGesture: some Gesture {
        SimultaneousGesture(SimultaneousGesture(dragGesture, magnificationGesture), rotationGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if state.isMaskEditMode {
                    let delta = CGSize(
                        width: value.translation.width - lastMaskDragTranslation.width,
                        height: value.translation.height - lastMaskDragTranslation.height
                    )
                    lastMaskDragTranslation = value.translation
                    state.maskOffsetChanged(deltaTranslation: delta, canvasSize: canvasSize)
                    return
                }
                // `translation == .zero` marque le PREMIER callback d'un nouveau geste
                // (`minimumDistance: 0`) — ré-arme la sélection à chaque nouveau toucher plutôt
                // qu'une seule fois, sinon `selectedId` resterait bloqué sur le premier calque
                // touché et tous les gestes suivants continueraient à le déplacer, même après un
                // toucher ailleurs sur le canevas.
                if value.translation == .zero {
                    _ = state.selectObject(at: value.startLocation)
                }
                state.dragMoved(to: value.location)
            }
            .onEnded { _ in
                if state.isMaskEditMode {
                    lastMaskDragTranslation = .zero
                } else {
                    state.dragEnded()
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if state.isMaskEditMode {
                    state.maskScaleChanged(incrementalFactor: value / lastMaskMagnification)
                    lastMaskMagnification = value
                    return
                }
                guard state.selectedId != nil else { return }
                beginPinchIfNeeded()
                state.scaleChanged(incrementalFactor: value / lastMagnification)
                lastMagnification = value
            }
            .onEnded { _ in
                if state.isMaskEditMode {
                    lastMaskMagnification = 1.0
                } else {
                    lastMagnification = 1.0
                    isPinching = false
                }
            }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                if state.isMaskEditMode {
                    let delta = value.degrees - lastMaskRotationDegrees
                    lastMaskRotationDegrees = value.degrees
                    state.maskRotationChanged(deltaDegrees: delta)
                    return
                }
                guard state.selectedId != nil else { return }
                beginPinchIfNeeded()
                state.rotationChanged(to: value.degrees)
            }
            .onEnded { _ in
                if state.isMaskEditMode {
                    lastMaskRotationDegrees = 0
                } else {
                    isPinching = false
                }
            }
    }

    /// `MagnificationGesture`/`RotationGesture` n'exposent pas de callback "début de geste" distinct
    /// — le premier `onChanged` de L'UN OU L'AUTRE sert de déclencheur pour amorcer
    /// `AnimemesGestureController.pointerDown` (voir `AnimemesEditorState.beginPinchRotate()`),
    /// une seule fois par geste à deux doigts. Mode masque uniquement — `maskRotationChanged`/
    /// `maskScaleChanged` n'ont pas besoin d'un tel amorçage (deltas directs, pas de matrice
    /// `AnimemesGestureController` à réinitialiser).
    private func beginPinchIfNeeded() {
        guard !isPinching else { return }
        isPinching = true
        state.beginPinchRotate()
    }

    /// Port de `MaskAddPanel` (choix du type) + `MaskPreviewEditorPanel` (inversion/flou/écart
    /// miroir) — le décalage/l'échelle/la rotation se pilotent par geste direct sur le canevas
    /// (`combinedGesture`, branche `isMaskEditMode` ci-dessus), pas par ce panneau (fidèle à
    /// Android : `MaskEditController` pilote CE sous-ensemble via le canevas, le panneau ne porte
    /// que les réglages scalaires).
    private func maskPanel(for obj: AnimationObjectData) -> some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // **Ajouté le 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-11, trouvé pendant le
                    // câblage du point d'entrée ci-dessus)** — port de `onDismiss()`
                    // (`AnimemesCompound.java:1067-1071`, `closeBtn`→`onCancelClicked()` dans
                    // `MaskPreviewEditorPanel.java:199/352`), DISTINCT de `onRemoveMask()`
                    // (`AnimemesCompound.java:1044-1064`, notre "Aucun" ci-dessous) : Android ferme
                    // le panneau SANS effacer le masque déjà appliqué. Avant ce correctif, "Aucun"
                    // était la SEULE façon de sortir du mode masque côté iOS — rouvrir le panneau
                    // pour ajuster un réglage puis fermer aurait donc SUPPRIMÉ un masque déjà
                    // appliqué, une perte de données pour l'utilisateur, pas seulement une lacune.
                    Button { state.isMaskEditMode = false } label: {
                        Image(systemName: "checkmark").font(.caption.bold())
                    }
                    Button {
                        state.setMaskType(nil)
                        state.isMaskEditMode = false
                    } label: {
                        Text("Aucun").font(.caption.bold())
                    }
                    ForEach(MaskType.allCases, id: \.self) { type in
                        Button { state.setMaskType(type) } label: {
                            Text(type.displayName)
                                .font(.caption.bold())
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(obj.appliedMaskType == type ? Color.accentColor : Color(white: 0.2))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }
            if obj.appliedMaskType != nil {
                HStack {
                    Toggle(isOn: Binding(get: { obj.maskInverted }, set: { _ in state.toggleMaskInverted() })) {
                        Text("Inverser").font(.caption)
                    }
                    .toggleStyle(.button)
                    .tint(.accentColor)
                }
                .padding(.horizontal)
                HStack {
                    Text("Flou").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Slider(value: Binding(get: { Double(obj.maskFeather) }, set: { state.setMaskFeather(Float($0)) }), in: 0...1)
                }
                .padding(.horizontal)
                if obj.appliedMaskType == .mirror {
                    HStack {
                        Text("Écart").font(.caption).foregroundStyle(.white.opacity(0.7))
                        Slider(value: Binding(get: { Double(obj.maskMirrorGap) }, set: { state.setMaskMirrorGap(Float($0)) }), in: 0...0.5)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(Color.black)
    }

    /// Port de la rangée du bas (`compound_animemes_layout.xml:460-938`) — voir doc de tête de
    /// fichier pour le détail RÉEL/DIFFÉRÉ/MORT de chaque bouton, confirmé par audit dédié.
    private var bottomToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 26) {
                bottomButton(icon: "sparkles.rectangle.stack", label: "Generate with AI") {
                    // Confirmé code mort côté Android (aiObjectDelegate jamais assigné) — bouton
                    // affiché pour la parité visuelle, SANS action (fidèle au comportement réel :
                    // Android lui-même ne fait rien de visible au tap).
                }
                bottomButton(icon: "square.on.square", label: "Compose") {}
                    .opacity(0.4)
                    .disabled(true)
                bottomButton(icon: "square.stack", label: "Load compose") {}
                    .opacity(0.4)
                    .disabled(true)
                bottomButton(icon: "square.grid.2x2", label: "Modèle") { showTemplateGallery = true }
                // Port de `btn_mask` (`AnimemesCompound.java:1986-1988` — `showMaskAddPanel();
                // v.setSelected(true)`) — **ajouté le 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-11,
                // P0)**. Avant ce correctif, `isMaskEditMode` n'était JAMAIS mis à `true` nulle
                // part dans le projet : le moteur de masque (7 formes, rendu, gestes) était
                // entièrement câblé mais 100% inaccessible, faute de point d'entrée. Android exige
                // un calque sélectionné avant d'ouvrir le panneau (`showMaskPreviewEditor` retourne
                // immédiatement si `obj == null`, `AnimemesCompound.java:1143-1148`) — reproduit
                // ici par `.disabled(state.selectedId == nil)`. La sortie du mode (bouton "Aucun"
                // dans `maskPanel(for:)`, qui appelle déjà `state.setMaskType(nil)` +
                // `state.isMaskEditMode = false`) existait déjà et n'a pas besoin d'être ajoutée.
                bottomButton(icon: "circle.dashed", label: "masque") { state.isMaskEditMode = true }
                    .disabled(state.selectedId == nil)
                // Port de `showPanelEditor`/`LayerEditorPanel` (**ajouté le 2026-08-19,
                // ANIMEMS_PARITY_AUDIT_V1.md F-28, Phase B Lot 3**) — voir la doc complète sur
                // `AnimemesEditorState.snapshotLayerEditor()` pour le raisonnement sur le
                // déclencheur (bouton dédié au lieu de l'appui long Android sur la timeline).
                bottomButton(icon: "slider.horizontal.3", label: "propriétés") {
                    if let snapshot = state.snapshotLayerEditor() {
                        layerEditorSnapshot = snapshot
                        showLayerEditor = true
                    }
                }
                .disabled(state.selectedId == nil)
                // Port de `btn_duplicate` (**ajouté le 2026-08-19, ANIMEMS_PARITY_AUDIT_V1.md
                // F-30, Phase B Lot 4**) — voir `AnimemesEditorState.duplicateSelected()`.
                bottomButton(icon: "plus.square.on.square", label: "dupliquer") { state.duplicateSelected() }
                    .disabled(state.selectedId == nil)
                // Port de `btn_bezier` (**ajouté le 2026-08-19, ANIMEMS_PARITY_AUDIT_V1.md F-27,
                // Phase B Lot 6**) — voir la note complète sur `showBezierEditor` ci-dessus :
                // toggle réel côté Android, SANS effet sur l'animation des deux côtés.
                bottomButton(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "bezier") {
                    showBezierEditor.toggle()
                }
                bottomButton(icon: "trash", label: "supprimer") { state.deleteSelected() }
                    .disabled(state.selectedId == nil)
                bottomButton(icon: "arrow.counterclockwise", label: "réinitialiser") { state.resetSelected() }
                    .disabled(state.selectedId == nil)
                bottomButton(icon: "clock", label: "chronologie") { showTimeline.toggle() }
                bottomButton(icon: "arrow.uturn.backward", label: "undo") { state.removeLast() }
                    .disabled(state.layers.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private func bottomButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct ExportedVideo: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
