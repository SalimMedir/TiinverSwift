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
    /// Port de `CroperView`/`onBitmapCroperListerner` — voir doc du `.fullScreenCover` plus bas
    /// (V5-F-035).
    @State private var pendingCropImage: UIImage?
    // V5-F-034 (Phase B P1-16) — voir `onVideoPicked` du `GalleryPickerView` ci-dessous : import
    // vidéo (recadrage temporel + extraction de trames) non porté, alerte explicite à la place
    // d'une fermeture silencieuse.
    @State private var showVideoImportUnsupportedAlert = false
    @State private var showTextPrompt = false
    @State private var showStickerPrompt = false
    @State private var newSticker = ""
    @State private var showDrawing = false
    /// Port du mode `automateCapture == true` d'`ic_paint` — voir doc du bouton dans
    /// `rightToolbar` (Phase B Lot 7).
    @State private var showPaintCapture = false
    @State private var showAudioPicker = false
    /// **Ajoutés (2026-08-28, V6-F-003)** — sélecteur vidéo dédié au bouton "Extraire" (piste
    /// audio d'une vidéo → musique de fond), voir `AnimemesEditorState.
    /// extractAudioAsBackgroundMusic(from:)`.
    @State private var showExtractAudioPicker = false
    @State private var showExtractAudioFailedAlert = false
    @State private var showShapePanel = false
    @State private var lastMagnification: CGFloat = 1.0
    @State private var isPinching = false
    @State private var exportedURL: URL?
    /// Port du chaînage `bundleDeliver(RESULT_IMAGE|RESULT_VIDEO)` → `MediaEditor`/`MediaTrim` →
    /// `PublishFragment` (`MemesFragment.java:327-351/410-433`, `CameraActivity.java:138-208`) —
    /// **ajouté le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-022 BUNNY-06, Phase B P0-3)**.
    /// Avant ce correctif, `exportedURL` n'alimentait QU'un `ShareLink` système — aucun chemin ne
    /// menait à `PublishComposeView`/`FeedRepository.publish`, contrairement à Android où l'export
    /// Animems rejoint TOUJOURS le pipeline de publication standard (crop/trim intermédiaire puis
    /// `PublishFragment`, le MÊME écran final que pour une photo/vidéo caméra/galerie classique).
    /// Choix assumé, documenté : le résultat Animems est injecté directement comme `PublishMedia`
    /// dans `PublishComposeView` — CE portage a déjà unifié tout le recadrage/les outils dans cet
    /// écran unique (`PhotoCropView`/`PhotoToolsView`), donc reproduire un second écran
    /// intermédiaire séparé (`MediaEditor`/`MediaTrim` d'Android) réinventerait un chemin qui existe
    /// déjà — l'utilisateur retrouve exactement le même recadrage/légende qu'une photo/vidéo
    /// classique, la parité FONCTIONNELLE (pas la parité d'écran) est respectée.
    @State private var pendingPublishMedia: PublishMedia?
    @State private var publishConversionError: String?
    @State private var showDurationSlider = false
    /// Port de `GestureListener.onLongPress` (`MemesView2.java:1571-1574`) — **ajouté le
    /// 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-052, Phase B P2)**. Mis à jour par le PREMIER
    /// callback de `dragGesture` (`minimumDistance: 0`, déclenché immédiatement au touché, avant
    /// tout mouvement) — sert de position pour `longPressGesture` ci-dessous, un `LongPressGesture`
    /// seul n'exposant aucune coordonnée. Câblé via `.simultaneousGesture` (modificateur SÉPARÉ de
    /// `.gesture(combinedGesture)`, PAS fusionné dedans) — délibérément, pour ne PAS toucher à la
    /// composition `SimultaneousGesture` déjà fragile de `combinedGesture` (voir son historique de
    /// régressions documenté juste au-dessus). **Nécessite une vérification sur device réel**
    /// (aucun simulateur/Xcode disponible dans cet environnement) : confirmer qu'un appui long
    /// immobile déclenche bien `longPressGesture` SANS que le mouvement minimal du doigt pendant la
    /// pression ne fasse dévier `dragGesture` vers un déplacement de calque non désiré.
    @State private var lastTouchLocation: CGPoint = .zero
    /// Port de `onFingerMoving` — voir doc de `deleteDropZoneIcon`/`isInDeleteDropZone` (V5-F-040).
    @State private var isDraggingSelectedObject = false
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
    /// Port de `compose_needs_two_layers`/`compose_failed` — voir `state.performRecompose()`.
    @State private var recomposeFailedAlert = false
    @State private var showTimeline = true
    /// Port de `controlle_movement`/`movement_controller_view` — **ajouté (2026-08-28,
    /// V6-F-002)**. Remplace la zone timeline pendant qu'il est ouvert, fidèle à
    /// `AnimemesCompound.java:1857-1874` (`frameList`/`timelineView` masqués tant que le panneau
    /// est visible).
    @State private var showMovementController = false
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
            #if DEBUG
            // **Corrigé (V4-F-055, 2026-08-24)** — HUD de diagnostic temporaire (voir commentaire
            // de tête de `gestureDiagnosticsHUD`) affiché SANS garde jusqu'ici, visible par tous
            // les utilisateurs en toute configuration de build. Gaté derrière `#if DEBUG` : le
            // pipeline de gestes qu'il diagnostiquait a depuis été éprouvé sur plusieurs cycles de
            // correction, mais reste utile en développement plutôt que d'être supprimé.
            gestureDiagnosticsHUD
            #endif
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
            } else if showMovementController {
                MovementControllerPanelView(state: state)
            } else if showTimeline {
                TimelineView(state: state)
                if showDurationSlider, let selectedId = state.selectedId, let obj = state.layers.first(where: { $0.id == selectedId }) {
                    durationSlider(for: obj)
                }
            }
            bottomToolbar
        }
        // **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-057, Phase B P1-23)** — port
        // de `MemesFragment.onPause`/`onStop`/`onDestroyView` (`:144-176`, appellent tous
        // `animemes_compound.pause()` + `stopView()`) : Android arrête TOUJOURS explicitement la
        // lecture/le rendu par frame en quittant l'écran. Sans ceci, quitter l'éditeur pendant que
        // `isPlaying == true` (bouton retour, changement d'onglet, mise en arrière-plan) laissait
        // le `CADisplayLink` du `AnimationEngine` actif indéfiniment dans le run loop principal —
        // `RunLoop.main` retient fortement le `CADisplayLink`/son target `DisplayLinkProxy`
        // INDÉPENDAMMENT de `AnimationEngine` (capturé `[weak self]`, voir `startPlayback`), donc
        // rien ne l'invalidait jamais. `engine.stop()` invalide déjà le lien (`stopDisplayLink()`)
        // et est sans effet si aucune lecture n'est en cours (`if displayLink != nil` guard).
        // **Étendu (revue B1, 2026-08-31)** — `state.cancelActiveCapture()` invalide le
        // `CADisplayLink` de capture automatique s'il tournait encore (geste en cours au moment où
        // cette vue disparaît, ex. fermeture programmatique de l'écran plutôt qu'un relâchement
        // normal du doigt, qui aurait sinon déclenché `dragEnded()`) — sans cet appel, il continuerait
        // de tourner tant que l'app reste au premier plan, même hors écran Animems.
        .onDisappear {
            state.engine.stop()
            state.cancelActiveCapture()
        }
        .background(Color.black)
        .statusBarHidden(false)
        .sheet(isPresented: $showGalleryPicker) {
            GalleryPickerView(
                onImagePicked: { url in
                    showGalleryPicker = false
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        pendingCropImage = image
                    }
                },
                // **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-034, Phase B P1-16)**
                // — Android [`AnimemesCompound.java:2108-2113,2251-2253`, `MemesFragment.java:
                // 386-388,551-587,233-267`] ouvre un vrai écran de recadrage temporel
                // (`VideoTrimmerView`) puis extrait une séquence de bitmaps ajoutée comme calque
                // animé (`addBitmaps(bitmaps, 33)`) — non porté ici (recadrage temporel +
                // extraction de trames pour l'éditeur Animems spécifiquement, périmètre distinct
                // du trim vidéo du Feed déjà porté dans `MediaTrimView.swift`). Avant ce correctif,
                // la vidéo choisie était silencieusement jetée sans AUCUNE indication ; port du
                // repli minimal explicitement autorisé par l'audit ("à défaut, au minimum afficher
                // un message d'erreur explicite plutôt que fermer silencieusement la feuille")
                // plutôt que d'improviser le pipeline d'extraction complet sans preuve suffisante
                // de la géométrie canevas/calque attendue par `AnimemesEditorState`.
                onVideoPicked: { _ in
                    showGalleryPicker = false
                    showVideoImportUnsupportedAlert = true
                },
                onCancel: { showGalleryPicker = false }
            )
        }
        // Port de `AnimemesCompound.add(MediaDataDetail)` (`:2441-2469`) — Android instancie un
        // `CroperView` et n'appelle `onNewAddBitmap` (calque ajouté au canevas) que dans
        // `onBitmapCropedResult`, APRÈS validation du recadrage ; `onClose()` referme sans rien
        // ajouter, l'annulation restant possible tant que le calque n'existe pas encore.
        // **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-035, Phase B P2)** — avant ce
        // correctif, `state.addImage` était appelé IMMÉDIATEMENT depuis `onImagePicked`, sans
        // aucune étape de recadrage/aperçu/annulation intermédiaire : l'image devenait un calque
        // permanent dès la sélection. Réutilise `PhotoCropView` (déjà porté, `PhotoEditor/
        // PhotoCropView.swift`, wrapper `TOCropViewController`) — le MÊME composant qui remplace
        // déjà `CroperView.java` pour la publication Feed/Profil (`PublishComposeView.swift`) —
        // plutôt que de réinventer un second recadreur. `shape: .rectangle` par défaut : Android
        // n'affiche aucun sélecteur de forme dans CE flux précis (contrairement à
        // `PublishComposeView`, qui propose Rectangle/Ovale) — `CroperView` y est instancié sans
        // configuration de forme, zone de recadrage rectangulaire libre uniquement.
        .fullScreenCover(isPresented: Binding(get: { pendingCropImage != nil }, set: { if !$0 { pendingCropImage = nil } })) {
            if let image = pendingCropImage {
                PhotoCropView(
                    image: image,
                    onCropped: { cropped in
                        state.addImage(cropped, canvasSize: canvasSize)
                        pendingCropImage = nil
                    },
                    onCancelled: { pendingCropImage = nil }
                )
                .ignoresSafeArea()
            }
        }
        .alert("Vidéo non prise en charge", isPresented: $showVideoImportUnsupportedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("L'ajout d'une vidéo comme calque animé n'est pas encore disponible sur iOS. Choisissez une image à la place.")
        }
        // **Ajouté (2026-08-28, V6-F-003)** — port de `onExtracSonFromVideo` : sélecteur vidéo
        // système dédié (filtre `.videos`, pas le sélecteur mixte image+vidéo de "Ajouter un
        // média"), extrait la piste audio et la définit comme musique de fond sur succès.
        .sheet(isPresented: $showExtractAudioPicker) {
            GalleryPickerView(
                onImagePicked: { _ in showExtractAudioPicker = false },
                onVideoPicked: { url in
                    showExtractAudioPicker = false
                    Task {
                        let ok = await state.extractAudioAsBackgroundMusic(from: url)
                        if !ok { showExtractAudioFailedAlert = true }
                    }
                },
                onCancel: { showExtractAudioPicker = false },
                filter: .videos
            )
        }
        .alert("Extraction audio échouée", isPresented: $showExtractAudioFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Impossible d'extraire la piste audio de cette vidéo — réessaie avec une autre vidéo.")
        }
        .fullScreenCover(isPresented: $showTextPrompt) {
            ProTextEditorView(
                onConfirm: { image in
                    state.addStyledText(image, canvasSize: canvasSize)
                    showTextPrompt = false
                },
                onCancel: { showTextPrompt = false }
            )
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
        .fullScreenCover(isPresented: $showPaintCapture) {
            PaintCaptureSheetView(
                canvasSize: canvasSize,
                onDone: { frames, delayMs in
                    state.addCapturedPaintFrames(frames, delayMs: delayMs, canvasSize: canvasSize)
                    showPaintCapture = false
                },
                onCancel: { showPaintCapture = false }
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
            VStack(spacing: 16) {
                // Port du choix réel `PublishFragment` — le chemin principal Android, ajouté ici
                // (voir doc de `pendingPublishMedia`).
                Button {
                    Task {
                        if let media = await Self.publishMedia(from: export.url) {
                            pendingPublishMedia = media
                            exportedURL = nil
                        } else {
                            publishConversionError = "Impossible de préparer ce fichier pour la publication."
                        }
                    }
                } label: {
                    Label("Publier sur Tiinver", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                ShareLink(item: export.url) { Label("Partager l'export", systemImage: "square.and.arrow.up") }
            }
            .padding()
            .presentationDetents([.height(160)])
        }
        .fullScreenCover(item: $pendingPublishMedia) { media in
            PublishComposeView(
                media: media,
                // Port de `template_id` (V5-F-083) — `nil` sauf si un modèle COMMUNAUTAIRE (pas un
                // modèle sauvegardé localement) était actif au moment de l'export, voir
                // `AnimemesEditorState.applyTemplate`.
                animemsMetadata: AnimemsPublishMetadata(templateId: state.activeCommunityTemplateId),
                onPublished: {
                    pendingPublishMedia = nil
                    onClose() // Port du retour à l'app hôte après `PublishFragment` réussi — Android
                    // ne revient JAMAIS dans l'éditeur Animems après une publication réussie.
                },
                onCancel: { pendingPublishMedia = nil }
            )
        }
        .alert("Publication impossible", isPresented: Binding(get: { publishConversionError != nil }, set: { if !$0 { publishConversionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publishConversionError ?? "")
        }
        // **Corrigé (2026-08-28, V7-F-006)** — `state.exportError` était calculé (échec MP4,
        // notamment celui que corrige V6-F-008) mais jamais lu par aucune vue : l'utilisateur ne
        // voyait rien de plus qu'un bouton d'export redevenu cliquable, sans indice. Même pattern
        // que `publishConversionError` juste au-dessus.
        .alert("Export impossible", isPresented: Binding(get: { state.exportError != nil }, set: { if !$0 { state.exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.exportError ?? "")
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
        .alert("Impossible de fusionner", isPresented: $recomposeFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Il faut au moins 2 calques visibles et non verrouillés pour utiliser Compose.")
        }
        // Port de `showTemplateMismatchDialog` — voir `AnimemesEditorState.templateMismatch`.
        .alert(
            "Template incomplet",
            isPresented: Binding(
                get: { state.templateMismatch != nil },
                set: { if !$0 { state.cancelTemplateMismatch() } }
            )
        ) {
            Button("Appliquer quand même") { state.confirmTemplateMismatch() }
            Button("Annuler", role: .cancel) { state.cancelTemplateMismatch() }
        } message: {
            if let mismatch = state.templateMismatch {
                Text("Ce modèle nécessite \(mismatch.needed) photo(s)/objet(s). Vous en avez \(mismatch.has).")
            }
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
                            case .text, .sticker:
                                // **Corrigé (2026-08-30, audit Animems profond)** — même résolution
                                // que le cas bitmap/forme ci-dessus (frame COURANTE dans le tableau
                                // dense `obj.transforms`, pas systématiquement la dernière entrée) :
                                // `drawText`/`drawSticker` recevaient jusqu'ici uniquement `currentNs`
                                // (pour la piste de keyframes éparse) et dérivaient leur transform en
                                // interne via `obj.transforms.last`, ignorant totalement une animation
                                // capturée dans le tableau dense (capture automatique).
                                let localIndex = state.localTransformIndex(forLayer: index, frame: frame)
                                let tfm = localIndex.flatMap { obj.transforms.indices.contains($0) ? obj.transforms[$0] : nil }
                                    ?? obj.transforms.last ?? Transform()
                                if obj.objectType == .text {
                                    LayerRenderer.drawText(obj, in: cgContext, textRect: state.textRect, viewSize: size, transform: tfm, currentNs: ns)
                                } else {
                                    LayerRenderer.drawSticker(obj, in: cgContext, transform: tfm, currentNs: ns)
                                }
                            default:
                                break
                            }
                        }
                    }
                }
                .frame(width: fitSize.width, height: fitSize.height)
                .background(Color(white: 0.08))
                .gesture(combinedGesture)
                // V4-F-052 — modificateur SÉPARÉ de `.gesture(combinedGesture)` ci-dessus,
                // délibérément, pour ne pas toucher à sa composition déjà fragile (voir doc de
                // `longPressGesture`).
                .simultaneousGesture(longPressGesture)
                .onAppear {
                    canvasSize = fitSize
                    state.preparePlayback(canvasSize: fitSize)
                    zoomState.updateMinZoom(targetSize: fitSize, parentSize: outerGeo.size)
                }
                .onChange(of: fitSize) { newSize in
                    canvasSize = newSize
                    state.preparePlayback(canvasSize: newSize)
                    zoomState.updateMinZoom(targetSize: newSize, parentSize: outerGeo.size)
                }
                .onChange(of: state.version) { _ in state.preparePlayback(canvasSize: canvasSize) }
                // **Corrigé le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-048, Phase B P1)** —
                // résout le risque documenté ci-dessous (`zoomControls`) : `.scaleEffect` appliqué
                // ICI, APRÈS `.gesture(combinedGesture)` dans la chaîne de modificateurs, PAS avant.
                // `.scaleEffect` est un `GeometryEffect` SwiftUI de premier ordre — placé en aval
                // (donc englobant) d'un `.gesture()` déjà posé, il ne change QUE le rendu visuel ;
                // SwiftUI continue de convertir les coordonnées tactiles physiques vers l'espace
                // LOCAL non-transformé du `Canvas` avant de les reporter dans `value.location`/
                // `value.translation` de `combinedGesture` — exactement le motif standard pour un
                // contenu zoomable qui gère lui-même des gestes internes (geste AU-DESSUS/avant la
                // transform, transform en dernier). `state.dragMoved`/`selectObject`/etc. continuent
                // donc de recevoir des coordonnées canevas NON mises à l'échelle, sans aucune
                // correction `/currentScale` nécessaire côté `AnimemesEditorState`. Port fidèle de
                // `CanvasZoomController.applyZoom` (`setPivotX/Y` au centre, `setScaleX/Y`) —
                // `anchor: .center`, le défaut de `.scaleEffect`, correspond déjà au pivot centré
                // qu'Android fixe explicitement.
                .scaleEffect(zoomState.currentScale)

                // Port de `drawDeleterIcon` — voir sa doc complète (V5-F-040). Même `.frame` que
                // le `Canvas` ci-dessus pour hériter du même centrage par défaut de ce `ZStack`
                // (donc de la même origine locale que `canvasSize`, sans calcul de décalage
                // supplémentaire) — mais délibérément SANS `.scaleEffect` (voir doc).
                deleteDropZoneIcon
                    .frame(width: fitSize.width, height: fitSize.height)
                    .allowsHitTesting(false)

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

    /// Port de `MemesView2.drawDeleterIcon`/`mDeleteBound` (`:1355-1361`) — zone VISUELLE de
    /// l'icône corbeille : carré 70×70 démarrant au centre horizontal du canevas, `top=10`.
    /// **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-040, Phase B P2)**.
    private static func deleteDropZoneVisualRect(canvasWidth: CGFloat) -> CGRect {
        CGRect(x: canvasWidth / 2, y: 10, width: 70, height: 70)
    }

    /// Port de `executeDeleterObjeect` (`MemesView2.java:1765-1769`) — zone de DÉTECTION au
    /// relâchement, plus généreuse que la zone visuelle (`mDeleteBound.left-30` à
    /// `mDeleteBound.right+80`, `y` de 10 à 100) : reproduite ici en coordonnées canevas LOCALES
    /// (mêmes coordonnées que `value.location` du geste — non affectées par `zoomState.
    /// currentScale`, voir doc de `.scaleEffect` sur `canvasArea`), fidèle à `event.getX()/getY()`
    /// côté Android (coordonnées de vue, également non affectées par un éventuel zoom externe).
    private static func isInDeleteDropZone(_ point: CGPoint, canvasWidth: CGFloat) -> Bool {
        let visual = deleteDropZoneVisualRect(canvasWidth: canvasWidth)
        return point.x >= visual.minX - 30 && point.x <= visual.maxX + 80 && point.y >= 10 && point.y <= 100
    }

    /// Port de `drawDeleterIcon` — icône affichée pendant qu'un calque sélectionné est glissé
    /// (`onFingerMoving && !isOnAutoMode`). **Approximation assumée, documentée** : positionnée en
    /// espace ÉCRAN (haut du conteneur du canevas), PAS à l'intérieur du groupe qui reçoit
    /// `zoomState.currentScale` (celui-ci enveloppe UNIQUEMENT le `Canvas` lui-même, voir
    /// commentaire détaillé sur `.scaleEffect` dans `canvasArea` — le sortir de ce groupe pour le
    /// zoomer avec le contenu aurait exigé de restructurer cette composition de gestes documentée
    /// comme fragile) : à zoom par défaut (le cas courant), la position visuelle correspond
    /// exactement à la zone de dépôt réelle ; à un niveau de zoom différent, l'icône reste fixe à
    /// l'écran alors que le contenu du canevas zoome sous elle — la LOGIQUE de suppression, elle,
    /// reste fidèle à 100% (coordonnées canevas locales, indépendantes du zoom, voir
    /// `isInDeleteDropZone`).
    @ViewBuilder
    private var deleteDropZoneIcon: some View {
        if isDraggingSelectedObject, !state.autoCaptureEnabled {
            let visual = Self.deleteDropZoneVisualRect(canvasWidth: canvasSize.width)
            Image(systemName: "trash.circle.fill")
                .resizable()
                .frame(width: visual.width, height: visual.height)
                .foregroundStyle(.white, Color.red)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .position(x: visual.midX, y: visual.midY)
        }
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
    ///
    /// **Remplacé le 2026-08-19 (ANIMEMS_PARITY_AUDIT_V1.md F-40, Phase B Lot 8)** : les boutons
    /// pilotaient un simple `@State displayZoom` local jamais réellement appliqué au canevas
    /// (aucun `.scaleEffect`/transform nulle part) — **un deuxième bug trouvé pendant ce lot, pas
    /// dans l'audit initial** : le zoom affichait un pourcentage qui changeait mais ne zoomait
    /// visuellement RIEN, un cas exact de "bouton qui ne modifie que l'UI" (Phase A5). Remplacé par
    /// `CanvasZoomState`/`CanvasZoomControls` (`CanvasZoomController.swift`, port fidèle de
    /// `computeMinZoom`/`zoom(delta)`/`reset`, orphelin jusqu'ici) pour au moins porter l'ALGORITHME
    /// correct (clamp `[minZoom dynamique, 4.0]`, pas `[0.5, 3]` fixe). Le zoom ne zoomait ENCORE
    /// pas visuellement le canevas après ce lot, risque documenté et délibérément laissé ouvert par
    /// prudence (voir git history de ce commentaire pour le raisonnement complet sur la classe de
    /// fragilité gestuelle en cause).
    ///
    /// **Corrigé le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-048, Phase B P1)** — le risque
    /// ci-dessus est résolu par construction plutôt que contourné : `.scaleEffect(zoomState.
    /// currentScale)` est appliqué dans `canvasArea` APRÈS `.gesture(combinedGesture)` dans la
    /// chaîne de modificateurs (voir ce fichier, `canvasArea`) — `.scaleEffect` étant un
    /// `GeometryEffect` SwiftUI de premier ordre, SwiftUI continue de convertir les coordonnées
    /// tactiles physiques vers l'espace LOCAL non-transformé du `Canvas` avant de les reporter dans
    /// `combinedGesture`, exactement le motif standard pour un contenu zoomable qui gère aussi ses
    /// propres gestes internes (geste posé AVANT/en-dessous de la transform, transform en dernier
    /// dans la chaîne). AUCUNE correction `/currentScale` n'a donc été nécessaire dans
    /// `AnimemesEditorState` — `state.dragMoved`/`selectObject`/etc. reçoivent toujours des
    /// coordonnées canevas non mises à l'échelle. Ce raisonnement s'appuie sur le comportement
    /// documenté de SwiftUI (non vérifiable empiriquement dans cet environnement sans Xcode/
    /// simulateur) — DEVICE_TEST_REQUIRED avant `COMPLETE_PARITY_VALIDATED` : zoomer via les
    /// boutons +/−, confirmer (1) l'effet visuel réel sur le canevas, ET (2) qu'un geste de
    /// glissement/pincement/rotation sur un objet à `currentScale != 1.0` continue de le déplacer/
    /// redimensionner/tourner de façon cohérente avec le doigt (pas de dérive de coordonnées).
    @StateObject private var zoomState = CanvasZoomState()
    private var zoomControls: some View {
        // `CanvasZoomControls` porte déjà son propre fond/contour (voir sa définition dans
        // `CanvasZoomController.swift`) — pas de second habillage ici, contrairement à l'ancienne
        // version inline qui avait le sien.
        CanvasZoomControls(state: zoomState)
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
                // Port de `ic_paint` — branche sur `automateCapture` comme Android
                // (`AnimemesCompound.java:2078-2095`, confirmé réel par l'audit export/outils :
                // DEUX modes derrière ce même bouton, pas un seul). **Modifié le 2026-08-19,
                // ANIMEMS_PARITY_AUDIT_V1.md F-26, Phase B Lot 7.**
                Button {
                    if state.autoCaptureEnabled { showPaintCapture = true } else { showDrawing = true }
                } label: { Image(systemName: "pencil") } // ic_paint
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

    /// Port de `onRepeateImage`/`ic_repeate` (`AnimemesCompound.java:2541-2555`) — aplatit l'état
    /// VISIBLE COURANT en un nouveau calque bitmap.
    ///
    /// **Corrigé (2026-08-31, finding F1 de la revue finale Animems)** — utilisait auparavant
    /// `LayerRenderer.drawLastTransform`/`obj.transforms.last` inconditionnellement, quelle que soit
    /// la position du playhead. Vérifié précisément côté Android : `getBitmapFromView(mView)`
    /// capture littéralement ce que `MemesView2.onDraw` affiche À CET INSTANT — mais `onDraw`
    /// bascule lui-même entre 3 chemins selon l'état (`playPreview`/`seekDraw`, tous deux résolus
    /// PAR FRAME, si lecture ou scrub actifs ; `startDraw`→`drawBitmapLastTransform`, TOUJOURS
    /// `.last`, dès que l'écran est simplement immobile — `MemesView2.java:759-772`). Le bouton
    /// "répéter fond" étant un tap de barre d'outils, quasi toujours pressé hors lecture/scrub
    /// actifs, une comparaison Android littérale resterait donc souvent sur `.last` aussi.
    ///
    /// **Ce qui tranche réellement en faveur de ce correctif** : le canevas live iOS
    /// (`canvasArea` ci-dessus) N'A PAS ce chemin "immobile → `.last`" — c'est un choix
    /// architectural DÉJÀ fait et déjà audité (voir sa doc de tête : "remplace l'ancien rendu
    /// toujours-dernière-transform, équivalent à un playhead figé sur la dernière frame") : le
    /// canevas iOS affiche TOUJOURS la frame résolue au playhead courant, lecture ou non. Capturer
    /// "ce qui est visuellement à l'écran" côté iOS — l'intention réelle de `getBitmapFromView`,
    /// au-delà de son implémentation Android particulière — exige donc de suivre le MÊME mécanisme
    /// que ce canevas (`localTransformIndex`/`transformationArray`), pas de le contredire.
    /// `LayerRenderer.drawObjectFrame` remplace donc `drawLastTransform` pour bitmap/forme (même
    /// substitution déjà faite pour le canevas live, 2026-08-16) ; le repli `?? obj.transforms.last`
    /// reste le filet de sécurité standard (avant tout `prepare()`, calque hors bornes de frame).
    ///
    /// **`clearBoard()` — vérifié, PAS un remplacement complet, voir `AnimemesEditorState.
    /// removeFreehandStrokes()` pour la preuve et la justification complète** : appelé ici APRÈS la
    /// capture (le nouveau calque doit contenir un rendu des traits de dessin encore présents) et
    /// AVANT l'ajout du nouveau calque aplati (même ordre qu'Android :
    /// `getBitmapFromView`→`clearBoard()`→`onNewAddBitmap`), pour éviter que les traits déjà
    /// "bakés" dans l'image ne soient aussi dessinés une seconde fois en tant que calques distincts.
    /// Les autres types de calque (image/texte/sticker/forme) restent volontairement intacts,
    /// fidèle à Android qui empile, ne remplace jamais toute la composition.
    private func repeatBackgroundImage() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let frame = state.timeline.playheadFrame
        let ns = state.timeline.frameToTimestampNs(frame)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { context in
            for (index, obj) in state.layers.enumerated() {
                guard obj.visible else { continue }
                let localIndex = state.localTransformIndex(forLayer: index, frame: frame)
                let tfm = localIndex.flatMap { obj.transforms.indices.contains($0) ? obj.transforms[$0] : nil }
                    ?? obj.transforms.last ?? Transform()
                switch obj.objectType {
                case .bitmap, .shapeRect, .shapeCircle, .shapeLine:
                    LayerRenderer.drawObjectFrame(
                        obj, transform: tfm, frameIndex: localIndex ?? 0, in: context.cgContext,
                        currentNs: ns, viewSize: canvasSize
                    )
                case .text:
                    LayerRenderer.drawText(obj, in: context.cgContext, textRect: state.textRect, viewSize: canvasSize, transform: tfm, currentNs: ns)
                case .sticker:
                    LayerRenderer.drawSticker(obj, in: context.cgContext, transform: tfm, currentNs: ns)
                default:
                    break
                }
            }
        }
        state.removeFreehandStrokes()
        state.addFreehandDrawing(image, canvasSize: canvasSize)
    }

    /// Port de la barre de lecture (`AnimemesCompound.java:2007-2019` — bouton play/pause unique) +
    /// bouton ◆ + accès à la durée du calque sélectionné.
    ///
    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-043, Phase B P1-19)** — voir le
    /// commentaire du bouton ◆ ci-dessous : appelait auparavant inconditionnellement
    /// `state.recordKeyframe()`, alors qu'Android [`AnimemesCompound.java:859-871`,
    /// `onKeyframeButtonClicked`] ne le fait QUE si le mode "controller de mouvement"
    /// (`controller_mode_activate`, jamais porté côté iOS — `MovementControllerState` confirmé
    /// jamais instancié) est actif ; en mode timeline PAR DÉFAUT (le SEUL mode existant côté iOS),
    /// le même bouton Android ouvre `showPanelEditor(sel)` sans créer aucun keyframe.
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

            // Port du bouton ◆ (`AnimemesCompound.java:859-871`, `onKeyframeButtonClicked`) —
            // branche `controller_mode_activate == false` (mode timeline par défaut, le SEUL
            // existant côté iOS) : ouvre le panneau de propriétés (`showPanelEditor(sel)`), MÊME
            // action que le bouton "propriétés" (voir bottomToolbar) — AUCUN keyframe créé.
            // `state.recordKeyframe()` (branche `controller_mode_activate == true`) n'est plus
            // appelé depuis CE bouton — reste utilisé ailleurs (`dragEnded()`, gardé par
            // `autoCaptureEnabled`, concern distinct du bouton ◆ lui-même, inchangé ici).
            Button {
                if let snapshot = state.snapshotLayerEditor() {
                    layerEditorSnapshot = snapshot
                    showLayerEditor = true
                }
            } label: {
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
                lastTouchLocation = value.location
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
                //
                // **Vérifié le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-091, Phase B P3)** —
                // `IOS_INTENTIONAL_DIFFERENCE` assumée, PAS un oubli de portage. Android
                // (`MemesView2.touchDown`, `:1642-1659`) ne réinitialise JAMAIS `objectInAction` sur
                // un tap dans le vide (grep exhaustif de `objectInAction = -1` : uniquement lors
                // d'une suppression, jamais lors d'un tap manqué) — la sélection reste "collante"
                // indéfiniment. `selectObject(at:)` (`AnimemesEditorState.swift`) désélectionne
                // explicitement dès qu'aucun calque ne contient le point tapé, PRÉCISÉMENT pour
                // éviter le bug de sélection bloquée décrit ci-dessus, découvert lors du portage —
                // reproduire la persistance Android réintroduirait ce même bug déjà corrigé.
                // Comportement iOS jugé plus prévisible, conservé délibérément.
                //
                // **Même décision couvre V5-F-092** (`GestureListener.onScroll`, `MemesView2.java:
                // 1575-1580` — translate `objectInAction` sur TOUT glissement une fois un calque
                // sélectionné, même démarré depuis le vide) : c'est la MÊME racine Android que
                // V5-F-091 (`touchDown` ne réinitialise jamais la sélection sur un miss), vue sous
                // un angle différent par un agent d'audit distinct — pas un second gap indépendant.
                // Reproduire V5-F-092 sans reproduire aussi V5-F-091 serait incohérent (un
                // glissement démarré dans le vide ré-désélectionnerait AVANT de pouvoir continuer à
                // déplacer l'ancien calque, via ce même `selectObject(at:)` juste en dessous) ; les
                // deux découlent du même choix assumé de ne PAS reproduire la sélection "collante".
                if value.translation == .zero {
                    _ = state.selectObject(at: value.startLocation)
                }
                state.dragMoved(to: value.location)
                // Port de `onFingerMoving = true` (`executeTouchEvent`, `ACTION_MOVE`) — pilote
                // l'affichage de l'icône corbeille (`deleteDropZoneIcon`), voir sa doc (V5-F-040).
                isDraggingSelectedObject = state.selectedId != nil
            }
            .onEnded { value in
                if state.isMaskEditMode {
                    lastMaskDragTranslation = .zero
                } else {
                    state.dragEnded()
                    // Port de `executeDeleterObjeect` (`MemesView2.java:1765-1769`), appelé APRÈS
                    // `touchUp` sur `ACTION_UP` — **ajouté le 2026-08-26
                    // (MIGRATION_PARITY_AUDIT_V5.md V5-F-040, Phase B P2)**. Voir doc de
                    // `Self.isInDeleteDropZone` pour la zone exacte.
                    if !state.autoCaptureEnabled, Self.isInDeleteDropZone(value.location, canvasWidth: canvasSize.width) {
                        state.deleteSelected()
                    }
                }
                isDraggingSelectedObject = false
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
                    endPinchIfNeeded()
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
                    endPinchIfNeeded()
                }
            }
    }

    /// Port de `GestureListener.onLongPress` (`MemesView2.java:1571-1574`) — **ajouté le
    /// 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-052, Phase B P2)**. `LongPressGesture` seul
    /// (pas de composition `.sequenced`/`.simultaneously`, pour rester aussi simple que possible
    /// dans un fichier à l'historique documenté de régressions de composition de gestes) — la
    /// position vient de `lastTouchLocation`, tenue à jour par le PREMIER callback de `dragGesture`
    /// (déclenché immédiatement au touché, `minimumDistance: 0`). PAS de garde `isMaskEditMode` —
    /// vérifié qu'Android n'a aucun équivalent "appui long" dans `handleMaskEditTouch`, ce geste ne
    /// s'applique donc qu'au mode normal ; en mode masque, `bringTopLayerToFront` resterait
    /// inoffensif (juste une réorganisation de calques) mais n'est de toute façon jamais le calque
    /// visé pendant l'édition d'un masque, laissé tel quel plutôt qu'ajouter une garde non demandée
    /// par la source Android.
    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in state.bringTopLayerToFront(at: lastTouchLocation) }
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

    /// **Ajouté (2026-08-30, audit Animems profond)** — symétrique de `beginPinchIfNeeded()` :
    /// `MagnificationGesture` et `RotationGesture` sont deux reconnaisseurs INDÉPENDANTS qui se
    /// terminent quasi simultanément sur un même geste physique à 2 doigts (les deux `.onEnded`
    /// se déclenchent l'un après l'autre) — `isPinching` sert ici de garde anti-double-déclenchement
    /// (le premier `.onEnded` à s'exécuter effectue le travail et repasse `isPinching` à `false`,
    /// le second n'a alors plus rien à faire). Appelle `state.dragEnded()` — nom historique, mais
    /// c'est bien le même point de sortie PARTAGÉ que la fin d'un glisser (voir sa doc : port de
    /// `touchUp()`, `MemesView2.java`, qui traite glisser/pincer/pivoter de façon identique) : sans
    /// cet appel, aucune keyframe n'était jamais capturée pour un calque animé par pincement/
    /// rotation, même avec la capture automatique active — seule la translation l'était.
    private func endPinchIfNeeded() {
        guard isPinching else { return }
        isPinching = false
        state.dragEnded()
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
                // Port de `btn_recompose` (**ajouté le 2026-08-19, ANIMEMS_PARITY_AUDIT_V1.md
                // F-20, Phase B Lot 9**) — voir `AnimemesEditorState.performRecompose()` : Android
                // n'exige aucune sélection manuelle, un seul tap fusionne tous les calques visibles
                // non verrouillés (≥2 requis).
                bottomButton(icon: "square.on.square", label: "Compose") {
                    if !state.performRecompose() { recomposeFailedAlert = true }
                }
                // "Load compose" (`btn_recompose_gallery`) reste DIFFÉRÉ — dépend de
                // `RecomposeManager` (persistance disque dédiée), toujours hors périmètre de ce lot
                // (voir en-tête d'`AnimemesRecompose.swift`).
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
                // **Corrigé (2026-08-28, V7-F-002)** — ouvrir ce panneau ne réinitialisait aucun
                // des 3 autres (bezier/Contrôle/chronologie), tous des `@State` `Bool` indépendants
                // combinés par une simple chaîne if/else-if à priorité fixe : un panneau resté
                // silencieusement `true` en arrière-plan pouvait réapparaître de façon inattendue en
                // refermant celui affiché par-dessus. Chaque bouton d'ouverture ferme désormais
                // explicitement les 3 autres avant de s'activer.
                bottomButton(icon: "circle.dashed", label: "masque") {
                    showBezierEditor = false
                    if showMovementController { state.closeMovementController() }
                    showMovementController = false
                    showTimeline = false
                    state.isMaskEditMode = true
                }
                    .disabled(state.selectedId == nil)
                // Port de `controlle_movement` (`AnimemesCompound.java:1857-1874`) — **ajouté
                // (2026-08-28, V6-F-002)**. Simple bascule côté Android, sans garde de sélection
                // sur le bouton lui-même (la transformation du calque sélectionné, elle, no-op
                // silencieusement sans sélection — voir `MovementControllerTransformer`).
                bottomButton(icon: "dial.min", label: "Contrôle") {
                    showMovementController.toggle()
                    if showMovementController {
                        state.isMaskEditMode = false
                        showBezierEditor = false
                        showTimeline = false
                    } else {
                        state.closeMovementController()
                    }
                }
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
                    if showBezierEditor {
                        // V7-F-002 : voir la note complète sur le bouton "masque" plus haut.
                        state.isMaskEditMode = false
                        if showMovementController { state.closeMovementController() }
                        showMovementController = false
                        showTimeline = false
                    }
                }
                // Port de `btn_removebg` (**ajouté le 2026-08-19, ANIMEMS_PARITY_AUDIT_V1.md F-29,
                // Phase B Lot 11**) — voir `AnimemesEditorState.removeBackgroundFromSelected()`.
                Group {
                    if state.isRemovingBackground {
                        VStack(spacing: 4) { ProgressView().tint(.white); Text("fond").font(.caption2) }
                            .foregroundStyle(.white)
                    } else {
                        bottomButton(icon: "person.crop.rectangle", label: "fond") {
                            state.removeBackgroundFromSelected()
                        }
                        .disabled(state.selectedId == nil)
                    }
                }
                bottomButton(icon: "trash", label: "supprimer") { state.deleteSelected() }
                    .disabled(state.selectedId == nil)
                bottomButton(icon: "arrow.counterclockwise", label: "réinitialiser") { state.resetSelected() }
                    .disabled(state.selectedId == nil)
                bottomButton(icon: "clock", label: "chronologie") { showTimeline.toggle() }
                // Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-036, Phase B P1-17) —
                // était `.disabled(state.layers.isEmpty)` : actif dès qu'il y avait N'IMPORTE
                // QUEL calque (sticker/image/texte inclus), permettant de supprimer silencieusement
                // le dernier élément placé même en l'absence de tout trait de dessin. Gardé
                // maintenant sur la présence d'un trait undoable spécifiquement, fidèle à la garde
                // `paintLayers` vide d'Android (`ImageViewCanvas.java:318`) — voir `removeLast()`.
                bottomButton(icon: "arrow.uturn.backward", label: "undo") { state.removeLast() }
                    .disabled(!state.layers.contains { $0.isFreehandStroke })
                // Port de `extract_c`/`extract` (**Ajouté 2026-08-28, V6-F-003**) — voir
                // `AnimemesEditorState.extractAudioAsBackgroundMusic(from:)`. Aucune dépendance à
                // `selectedId`, fidèle à Android (action globale, pas liée au calque sélectionné).
                Group {
                    if state.isExtractingAudio {
                        VStack(spacing: 4) { ProgressView().tint(.white); Text("extraire").font(.caption2) }
                            .foregroundStyle(.white)
                    } else {
                        bottomButton(icon: "waveform.badge.plus", label: "extraire") { showExtractAudioPicker = true }
                    }
                }
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

private extension AnimemesEditorView {
    /// Convertit le fichier exporté par Animems (`AnimemesEditorState.export`) en `PublishMedia` —
    /// **ajouté le 2026-08-19, Phase B P0-3**. Distingue image/vidéo par extension : `export()`
    /// écrit systématiquement un `.mp4` pour une animation (`AnimemesExporter`) ou un `.jpg` pour
    /// une image statique (`exportStaticImage`, `BitmapManager.fromBitmapToImage`-équivalent) —
    /// pas d'ambiguïté possible, les deux fonctions n'écrivent jamais l'extension de l'autre.
    static func publishMedia(from url: URL) async -> PublishMedia? {
        let ext = url.pathExtension.lowercased()
        if ext == "mp4" || ext == "mov" {
            return .video(url)
        }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return .photo(image)
    }
}
