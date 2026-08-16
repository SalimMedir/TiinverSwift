import SwiftUI

/// Assemble un écran d'éditeur RÉEL autour du moteur Animems déjà porté (`AnimationComposer`/
/// `AnimationObjectData`/`LayerRenderer`/`ShapeFactory`/`AnimemesExporter`, lus en entier le
/// 2026-08-15) — port de `AnimemesCompound.java`/`compound_animemes_layout.xml`, PAS une réécriture
/// du moteur. Barre du haut (`close_animemes`/`save_animemes2`), rangée d'ajout d'objet (`ic_add`/
/// `ic_text`/`btn_shape`, PAS `ic_sticker` — nécessiterait le catalogue d'émojis/stickers, hors
/// périmètre de cette passe), `undo`, canevas avec déplacement/rotation/échelle réels au doigt
/// (2026-08-16, `AnimemesGestureController`), **timeline/keyframes/lecture câblés le 2026-08-16**
/// (`TimelineView`/`AnimationEngine`, moteur déjà porté, seul le câblage manquait — voir audit dans
/// `MIGRATION_AUDIT.md`). Masques/stickers PAS reproduits dans cette passe.
struct AnimemesEditorView: View {
    var onClose: () -> Void

    @StateObject private var state = AnimemesEditorState()
    @State private var canvasSize: CGSize = CGSize(width: 360, height: 640)
    @State private var showGalleryPicker = false
    @State private var showTextPrompt = false
    @State private var newText = ""
    @State private var lastMagnification: CGFloat = 1.0
    @State private var isPinching = false
    @State private var exportedURL: URL?
    @State private var showDurationSlider = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                playbackBar
                TimelineView(state: state)
                if showDurationSlider, let selectedId = state.selectedId, let obj = state.layers.first(where: { $0.id == selectedId }) {
                    durationSlider(for: obj)
                }
                toolbar
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Port de `close_animemes`.
                    Button { onClose() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Port de `save_animemes2` — `showSaveDialog()`/export réel.
                    if state.isExporting {
                        ProgressView()
                    } else {
                        Button {
                            state.export(canvasSize: canvasSize) { url in exportedURL = url }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(state.layers.isEmpty)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
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
        .sheet(item: Binding(get: { exportedURL.map(ExportedVideo.init) }, set: { exportedURL = $0?.url })) { export in
            ShareLink(item: export.url) { Label("Partager l'export", systemImage: "square.and.arrow.up") }
                .padding()
        }
    }

    /// Port de `MemesView2.onDraw` — rendu conscient du playhead (`LayerRenderer.drawObjectFrame`,
    /// 2026-08-16), remplace l'ancien rendu toujours-dernière-transform (`drawLastTransform`,
    /// équivalent à un playhead figé sur la dernière frame). `drawObjectFrame` interroge les pistes
    /// de keyframes EN DIRECT (voir note `AnimemesEditorState.preparePlayback`) — `localTransformIndex`
    /// n'est qu'un REPLI pour les calques sans keyframe matrice (transform unique posée par geste).
    private var canvas: some View {
        GeometryReader { geo in
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
            .background(Color(white: 0.08))
            .gesture(combinedGesture)
            .onAppear { canvasSize = geo.size; state.preparePlayback(canvasSize: geo.size) }
            .onChange(of: geo.size) { newSize in canvasSize = newSize; state.preparePlayback(canvasSize: newSize) }
            .onChange(of: state.version) { _ in state.preparePlayback(canvasSize: canvasSize) }
            // `version` force un redraw explicite après mutation des calques (le moteur Animems
            // est composé de classes de référence, pas de `@Published` internes — voir
            // `AnimemesEditorState`).
            .id(state.version)
        }
        .frame(height: 320)
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
    private var combinedGesture: some Gesture {
        SimultaneousGesture(SimultaneousGesture(dragGesture, magnificationGesture), rotationGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
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
                state.dragEnded()
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard state.selectedId != nil else { return }
                beginPinchIfNeeded()
                state.scaleChanged(incrementalFactor: value / lastMagnification)
                lastMagnification = value
            }
            .onEnded { _ in
                lastMagnification = 1.0
                isPinching = false
            }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                guard state.selectedId != nil else { return }
                beginPinchIfNeeded()
                state.rotationChanged(to: value.degrees)
            }
            .onEnded { _ in isPinching = false }
    }

    /// `MagnificationGesture`/`RotationGesture` n'exposent pas de callback "début de geste" distinct
    /// — le premier `onChanged` de L'UN OU L'AUTRE sert de déclencheur pour amorcer
    /// `AnimemesGestureController.pointerDown` (voir `AnimemesEditorState.beginPinchRotate()`),
    /// une seule fois par geste à deux doigts.
    private func beginPinchIfNeeded() {
        guard !isPinching else { return }
        isPinching = true
        state.beginPinchRotate()
    }

    private var toolbar: some View {
        HStack(spacing: 28) {
            // Port de `ic_add` (ajout photo).
            Button { showGalleryPicker = true } label: { Image(systemName: "photo") }
            // Port de `ic_text`.
            Button { showTextPrompt = true } label: { Image(systemName: "textformat") }
            // Port de `btn_shape` → `showShapeAddPanel()` — 3 formes directement (rect/cercle/ligne),
            // sans le panneau de sélection intermédiaire d'Android (accès direct, comportement
            // équivalent avec moins de taps).
            Button { state.addShape(.shapeRect, canvasSize: canvasSize) } label: { Image(systemName: "rectangle") }
            Button { state.addShape(.shapeCircle, canvasSize: canvasSize) } label: { Image(systemName: "circle") }
            Button { state.addShape(.shapeLine, canvasSize: canvasSize) } label: { Image(systemName: "line.diagonal") }
            Spacer()
            // Port de `undo` → `mView.deletePrecedenteDraw()`.
            Button { state.removeLast() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(state.layers.isEmpty)
        }
        .font(.title2)
        .foregroundStyle(.white)
        .padding()
        .background(Color.black)
    }
}

private struct ExportedVideo: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
