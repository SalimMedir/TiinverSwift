import SwiftUI

/// Assemble un écran d'éditeur RÉEL autour du moteur Animems déjà porté (`AnimationComposer`/
/// `AnimationObjectData`/`LayerRenderer`/`ShapeFactory`/`AnimemesExporter`, lus en entier le
/// 2026-08-15) — port MINIMAL mais FONCTIONNEL de `AnimemesCompound.java`/`compound_animemes_
/// layout.xml`, PAS une réécriture du moteur. Barre du haut minimale (`close_animemes`/
/// `save_animemes2`), rangée d'ajout d'objet (`ic_add`/`ic_text`/`btn_shape`, PAS `ic_sticker` —
/// nécessiterait le catalogue d'émojis/stickers, hors périmètre de cette passe), `undo`, canevas
/// avec déplacement/rotation/échelle réels au doigt (2026-08-16, `AnimemesGestureController` —
/// masques/keyframes/timeline détaillée PAS reproduits dans cette passe, voir `MIGRATION_AUDIT.md`
/// pour le périmètre exact laissé de côté).
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
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

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                context.withCGContext { cgContext in
                    for obj in state.layers {
                        guard obj.visible else { continue }
                        switch obj.objectType {
                        case .bitmap, .shapeRect, .shapeCircle, .shapeLine:
                            LayerRenderer.drawLastTransform(
                                obj, in: cgContext, currentNs: 0, isSliderPreview: true,
                                bitmapCache: state.bitmapCache, viewSize: size
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
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { newSize in canvasSize = newSize }
            // `version` force un redraw explicite après mutation des calques (le moteur Animems
            // est composé de classes de référence, pas de `@Published` internes — voir
            // `AnimemesEditorState`).
            .id(state.version)
        }
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
