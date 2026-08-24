import SwiftUI

/// Port de la portion "outils" de `CroperView.java` (`handleFlip`/`handleRemoveBackground`) et du
/// sous-ensemble PRINCIPAL d'`ImageEditorCompound.java` (peinture libre `ic_paint`, texte
/// `containerEditText`, stickers/emoji `ic_smile`/`EmojiView`) — écran intercalé entre le
/// recadrage (`PhotoCropView`/`FreeformCropView`) et la légende dans `PublishComposeView`,
/// 2026-08-16. Périmètre volontairement réduit vs Android : PAS de glisser-déposer du texte/
/// sticker une fois placé (Android le permet), PAS d'image composée (ajout d'une seconde image) —
/// voir `MIGRATION_AUDIT.md`.
///
/// **Stickers (2026-08-16, câblés après audit dédié)** : Android n'a PAS de catalogue de stickers
/// custom sur cet écran — `MediaEditor.java:30-32` importe `com.vanniktech.emoji.EmojiView`, un
/// clavier emoji Unicode STANDARD tiers (`emoji-google-compat`), pas un système d'assets/backend.
/// `onEmojiClick` (`MediaEditor.java:101-109`) rasterise le glyphe choisi (`BitmapManager.
/// getBitmapFromText`) et l'ajoute comme un calque bitmap ordinaire, positionné par défaut puis
/// déplaçable — CE portage réutilise directement le clavier emoji SYSTÈME d'iOS (via un `TextField`,
/// bouton globe pour basculer dessus) plutôt qu'une grille custom, fidèle au principe "clavier
/// emoji standard", pas une grille d'assets à maintenir.
struct PhotoToolsView: View {
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    @StateObject private var editorState = PhotoEditorState()
    @State private var displayedImage: UIImage
    @State private var strokes: [DrawnStroke] = []
    @State private var currentStroke: DrawnStroke?
    @State private var texts: [PlacedText] = []
    @State private var isDrawMode = false
    @State private var drawColor: Color = .red
    @State private var showTextPrompt = false
    @State private var newText = ""
    @State private var showStickerPrompt = false
    @State private var newSticker = ""
    @State private var canvasSize: CGSize = .zero
    @State private var errorText: String?

    init(sourceImage: UIImage, onDone: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onDone = onDone
        self.onCancel = onCancel
        _displayedImage = State(initialValue: sourceImage)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black
                    Image(uiImage: displayedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    Canvas { context, _ in
                        for stroke in strokes { Self.draw(stroke, in: context) }
                        if let currentStroke { Self.draw(currentStroke, in: context) }
                    }
                    .allowsHitTesting(false)
                    ForEach(texts) { item in
                        Text(item.text)
                            .font(.system(size: item.isSticker ? 64 : 30, weight: item.isSticker ? .regular : .bold))
                            .foregroundStyle(item.color)
                            .position(item.position)
                    }
                }
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { canvasSize = $0 }
            }
            .overlay {
                if editorState.isProcessing {
                    ProgressView(editorState.progressLabel)
                        .padding()
                        .background(.thinMaterial)
                        .cornerRadius(12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Suivant") { onDone(flatten()) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { toolbar }
            .alert("Ajouter du texte", isPresented: $showTextPrompt) {
                TextField("Texte", text: $newText)
                Button("Ajouter") { addText() }
                Button("Annuler", role: .cancel) { newText = "" }
            }
            // Port d'`onEmojiClick` — la sélection se fait via le clavier emoji SYSTÈME d'iOS
            // (bouton globe du `TextField`), voir note de tête de fichier.
            .alert("Ajouter un sticker", isPresented: $showStickerPrompt) {
                TextField("Emoji", text: $newSticker)
                Button("Ajouter") { addSticker() }
                Button("Annuler", role: .cancel) { newSticker = "" }
            } message: {
                Text("Touche le globe du clavier pour choisir un emoji.")
            }
        }
        .background(Color.black)
    }

    private var toolbar: some View {
        VStack(spacing: 12) {
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
            if isDrawMode {
                HStack(spacing: 14) {
                    ForEach([Color.red, .yellow, .blue, .green, .white, .black], id: \.self) { color in
                        Circle().fill(color).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(.white, lineWidth: drawColor == color ? 2 : 0))
                            .onTapGesture { drawColor = color }
                    }
                }
            }
            HStack(spacing: 26) {
                // Port de `handleFlip` — `CropImageView.setFlippedHorizontally`.
                Button { flipHorizontal() } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                // Port de `handleRemoveBackground`.
                Button { Task { await removeBackground() } } label: {
                    Image(systemName: "person.crop.rectangle.badge.xmark")
                }
                // Port de `ic_paint`.
                Button { isDrawMode.toggle() } label: {
                    Image(systemName: isDrawMode ? "pencil.tip.crop.circle.badge.plus" : "pencil.tip.crop.circle")
                }
                .tint(isDrawMode ? .yellow : .white)
                // Port de `containerEditText`/`ic_text`.
                Button { showTextPrompt = true } label: { Image(systemName: "textformat") }
                // Port de `ic_smile`/`EmojiView` — clavier emoji système, voir tête de fichier.
                Button { showStickerPrompt = true } label: { Image(systemName: "face.smiling") }
                // Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-057, Phase B P2) — voir
                // `undo()` : ce bouton ne concerne QUE la peinture côté Android, plus de garde sur
                // `texts`.
                if !strokes.isEmpty {
                    Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                }
            }
            .font(.title2)
            .foregroundStyle(.white)
        }
        .padding()
        .background(Color.black.opacity(0.85))
    }

    private func addText() {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let offset = CGFloat(texts.count) * 24
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2 + offset)
        texts.append(PlacedText(text: trimmed, position: center, color: drawColor))
        newText = ""
    }

    /// Port d'`onEmojiClick` → `BitmapManager.getBitmapFromText` + `addBitmap` — un emoji est un
    /// calque comme un autre (ici : un `PlacedText` avec `isSticker=true`, rendu SANS tinte de
    /// couleur puisqu'un glyphe emoji porte déjà sa propre couleur, contrairement au texte).
    private func addSticker() {
        let trimmed = newSticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let offset = CGFloat(texts.count) * 24
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2 + offset)
        texts.append(PlacedText(text: trimmed, position: center, color: .primary, isSticker: true))
        newSticker = ""
    }

    /// **Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-057, Phase B P2)** — port de
    /// `ImageViewCanvas.deletePrecedenteDraw` (`:317-326`, entier), déclenché par `R.id.undo`
    /// (`ImageEditorCompound.java:458-460`) : ne retire QUE le dernier `strokes` (peinture,
    /// `composer.getPaintLayers()` côté Android) — `texts` (texte/stickers, `PROP_MATRIX`/
    /// `AnimationObjectData` distincts côté Android) n'est JAMAIS touché par ce bouton précis, ils
    /// sont individuellement supprimables via une icône dédiée SÉPARÉE
    /// (`ImageViewCanvas.deleteObjectById`) — délibérément PAS portée ici (RECOMMANDATION de
    /// l'audit elle-même : "évaluer si la suppression individuelle par tap vaut la peine d'être
    /// portée" — hors périmètre de cette correction, qui vise uniquement la sémantique erronée du
    /// bouton "annuler" existant, pas une nouvelle fonctionnalité de sélection/suppression
    /// individuelle de texte/sticker). Avant ce correctif, `undo()` retirait TOUJOURS le dernier
    /// TEXTE en premier (peu importe l'ordre chronologique réel), ce qu'Android ne fait jamais
    /// depuis ce bouton.
    private func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
    }

    private func flipHorizontal() {
        guard let cgImage = displayedImage.cgImage else { return }
        let flipped: UIImage.Orientation = displayedImage.imageOrientation == .upMirrored ? .up : .upMirrored
        displayedImage = UIImage(cgImage: cgImage, scale: displayedImage.scale, orientation: flipped)
    }

    private func removeBackground() async {
        guard let cgImage = displayedImage.cgImage else { return }
        errorText = nil
        guard let result = await editorState.removeBackground(from: cgImage) else {
            errorText = "Aucun sujet détecté."
            return
        }
        displayedImage = UIImage(cgImage: result, scale: displayedImage.scale, orientation: displayedImage.imageOrientation)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isDrawMode else { return }
                if value.translation == .zero {
                    currentStroke = DrawnStroke(points: [value.location], color: drawColor)
                } else {
                    currentStroke?.points.append(value.location)
                }
            }
            .onEnded { _ in
                guard isDrawMode, let stroke = currentStroke, stroke.points.count > 1 else {
                    currentStroke = nil
                    return
                }
                strokes.append(stroke)
                currentStroke = nil
            }
    }

    private static func draw(_ stroke: DrawnStroke, in context: GraphicsContext, lineWidth: CGFloat = 8) {
        guard stroke.points.count > 1 else { return }
        var path = Path()
        path.move(to: stroke.points[0])
        for point in stroke.points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    /// Aplatit l'image + les traits de peinture + le texte en une seule image bitmap avant
    /// publication (`ImageEditorCompound.saveImageWithPaint`/`saveImageWithText` côté Android — même
    /// principe, résolution finale ajustée à la résolution PIXEL de l'image source plutôt qu'à la
    /// taille d'affichage, via `ImageRenderer.scale`).
    ///
    /// **Corrigé le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-126, reconfirmation de V3-F-039,
    /// Phase B P1)** — avant ce correctif, le composé était rendu à `canvasSize` (le cadre ÉCRAN,
    /// `GeometryReader`), pas à la résolution de `displayedImage` : dès que le ratio écran différait
    /// du ratio de la photo source (cas courant), l'image `.aspectRatio(.fit)` était lettrboxée
    /// SANS fond noir explicite (contrairement à l'écran d'édition), gravant des bandes
    /// transparentes/blanches indésirables dans l'image publiée, avec les dimensions finales du
    /// ratio ÉCRAN plutôt que du ratio PHOTO. Le composé est maintenant rendu EXACTEMENT à
    /// `displayedImage.size` (aucun `.aspectRatio`/lettrboxing nécessaire, l'image occupe tout le
    /// cadre) ; les positions des traits/textes (capturées en repère ÉCRAN, `canvasSize`) et leurs
    /// tailles (largeur de trait, taille de police — fixées en points ÉCRAN) sont converties vers
    /// le repère réel de l'image via `screenToImageScale`/`imageSpacePoint`, pour que le résultat
    /// final ait EXACTEMENT la même apparence proportionnelle que ce que l'utilisateur voyait à
    /// l'écran, fidèle à Android (`ImageEditorCompound` bake le contenu à la résolution pixel de la
    /// photo, jamais à la résolution d'affichage).
    @MainActor
    private func flatten() -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0, !strokes.isEmpty || !texts.isEmpty else {
            return displayedImage
        }
        let imageSize = displayedImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return displayedImage }

        // Port de l'aspect-fit implicite d'`.aspectRatio(contentMode: .fit)` dans l'écran d'édition
        // — même formule, calculée explicitement ici pour convertir les coordonnées écran → image.
        let screenToImageScale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * screenToImageScale, height: imageSize.height * screenToImageScale)
        let origin = CGPoint(x: (canvasSize.width - fittedSize.width) / 2, y: (canvasSize.height - fittedSize.height) / 2)

        func imageSpacePoint(_ screenPoint: CGPoint) -> CGPoint {
            CGPoint(x: (screenPoint.x - origin.x) / screenToImageScale, y: (screenPoint.y - origin.y) / screenToImageScale)
        }

        let transformedStrokes = strokes.map { DrawnStroke(points: $0.points.map(imageSpacePoint), color: $0.color) }
        let transformedTexts = texts.map { item -> PlacedText in
            var copy = item
            copy.position = imageSpacePoint(item.position)
            return copy
        }
        let imageSpaceLineWidth = 8 / screenToImageScale

        let composed = ZStack {
            Image(uiImage: displayedImage)
            Canvas { context, _ in
                for stroke in transformedStrokes { Self.draw(stroke, in: context, lineWidth: imageSpaceLineWidth) }
            }
            ForEach(transformedTexts) { item in
                Text(item.text)
                    .font(.system(size: (item.isSticker ? 64 : 30) / screenToImageScale, weight: item.isSticker ? .regular : .bold))
                    .foregroundStyle(item.color)
                    .position(item.position)
            }
        }
        .frame(width: imageSize.width, height: imageSize.height)

        let renderer = ImageRenderer(content: composed)
        renderer.scale = displayedImage.scale
        return renderer.uiImage ?? displayedImage
    }
}

struct DrawnStroke {
    var points: [CGPoint]
    var color: Color
}

struct PlacedText: Identifiable {
    let id = UUID()
    var text: String
    var position: CGPoint
    var color: Color
    /// `true` pour un emoji ajouté via `PhotoToolsView.addSticker` — rendu plus grand, sans
    /// pertinence de `color` (un glyphe emoji ignore `.foregroundStyle`).
    var isSticker: Bool = false
}
