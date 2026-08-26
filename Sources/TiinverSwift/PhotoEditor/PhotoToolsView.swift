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
///
/// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-085, Phase B P1-34)** — port de
/// `ImageViewCanvas.java` `GestureListener`/`ScaleListener`/la rotation à deux doigts
/// (`:1156-1358`) : chaque texte/sticker placé peut désormais être glissé (un doigt), redimensionné
/// (pincer, bornes `MIN_SCALE`/`MAX_SCALE` = 0.3...5.0, valeurs EXACTES d'`ImageViewCanvas.java:
/// 73-74`) et pivoté librement (rotation à deux doigts) — voir `PlacedItemView` ci-dessous. Le
/// commentaire de tête ci-dessus affirmait auparavant "PAS de glisser-déposer du texte/sticker une
/// fois placé" comme un périmètre volontairement réduit ; ce n'était en réalité jamais formalisé
/// comme un écart évalué, corrigé par ce finding. **Écart mineur assumé** : pas d'indicateur visuel
/// de sélection dédié (`objectInAction`/surbrillance côté Android) — SwiftUI route déjà chaque
/// geste au bon calque via son propre hit-testing (`ForEach($texts)`, un geste par vue), rendant un
/// état de sélection explicite superflu pour le comportement observable (glisser/pincer/pivoter
/// fonctionne directement sur l'élément touché), juste sans highlight visuel pendant la
/// manipulation.
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
    /// Port de `isBorderText`/`btn_textContainer` (V5-F-087) — bascule persistante, comme côté
    /// Android (`v.isSelected()`), appliquée au PROCHAIN texte ajouté.
    @State private var textHasContainer = false
    @State private var newText = ""
    @State private var showStickerPrompt = false
    @State private var newSticker = ""
    @State private var canvasSize: CGSize = .zero
    @State private var errorText: String?
    /// Port du bouton "recadrer à nouveau" (`ic_repeate`/`onRepeateImage`, V5-F-086) — absent
    /// jusqu'ici de ce portage.
    @State private var showRecrop = false

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
                    ForEach($texts) { $item in
                        PlacedItemView(item: $item)
                            .allowsHitTesting(!isDrawMode)
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
            // Port de `onRepeateImage` (`ImageEditorCompound.java:861-885`, V5-F-086) — Android
            // instancie directement `CroperView` (recadrage rectangle simple, PAS le choix de forme
            // proposé en amont du flux de publication) sur une capture de l'état courant du canevas.
            .fullScreenCover(isPresented: $showRecrop) {
                PhotoCropView(
                    image: flatten(),
                    onCropped: { cropped in
                        // Port de `mView.clearBoard()` + `onNewAddBitmap(bitmap, "bitmap", true, true)`
                        // — remplace TOUT le composite courant par le résultat recadré, efface
                        // l'historique de traits/texte précédent.
                        displayedImage = cropped
                        strokes = []
                        texts = []
                        showRecrop = false
                    },
                    onCancelled: { showRecrop = false }
                )
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
                // Port de `btn_textContainer` (`ImageEditorCompound.java:441-457`, V5-F-087) —
                // bascule fond opaque du PROCHAIN texte ajouté (noir-sur-blanc si actif).
                Button { textHasContainer.toggle() } label: { Image(systemName: "character.textbox") }
                    .tint(textHasContainer ? .yellow : .white)
                // Port de `ic_smile`/`EmojiView` — clavier emoji système, voir tête de fichier.
                Button { showStickerPrompt = true } label: { Image(systemName: "face.smiling") }
                // Port de `ic_repeate`/`onRepeateImage` (V5-F-086) — recadrer à nouveau le composite
                // courant (traits + texte + image déjà ajoutés).
                Button { showRecrop = true } label: { Image(systemName: "crop.rotate") }
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
        // Port de `isBorderText` (V5-F-087) — Android FORCE noir-sur-blanc pendant que la bascule
        // est active, ignore tout autre choix de couleur ; `drawColor` (palette libre) reste la
        // couleur utilisée quand la bascule est inactive, comportement déjà en place.
        let textColor: Color = textHasContainer ? .black : drawColor
        texts.append(PlacedText(text: trimmed, position: center, color: textColor, hasContainer: textHasContainer))
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
    /// principe de composition, résolution finale via `ImageRenderer.scale` — voir la note
    /// V5-F-088 ci-dessous pour la résolution EXACTE, qui diffère délibérément d'Android).
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
    /// l'écran.
    ///
    /// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-088, Phase B P3)** — le
    /// commentaire ci-dessus affirmait à tort que ce composé "à la résolution pixel de la photo" est
    /// fidèle à Android. Vérifié par lecture directe : `ImageEditorCompound.fitBitmapToView`
    /// (`:240-280`) redimensionne la photo de base à la largeur d'écran MESURÉE (`availableWidth`)
    /// AVANT tout ajout de peinture/texte, et `createImage` (`:818-825`) exporte via
    /// `getBitmapFromView(mView)` — les dimensions de la VUE écran, PAS celles de la photo source.
    /// Android exporte donc TOUJOURS à la résolution d'AFFICHAGE (souvent bien inférieure à une
    /// photo 12 MP+), jamais à la résolution pixel native. Ce composé iOS, lui, est rendu à
    /// `imageSize = displayedImage.size` (résolution PIXEL complète post-recadrage) — **divergence
    /// INTENTIONNELLE assumée**, pas une fidélité par erreur : une image finale de meilleure
    /// qualité/résolution qu'Android pour la même action, sans régression identifiée, jugée
    /// préférable à reproduire le plafonnement Android. Dimensions de sortie donc NON identiques
    /// entre les deux plateformes pour une même photo — à garder en tête pour tout test de parité
    /// s'appuyant sur les dimensions du fichier exporté.
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
                    .padding(item.hasContainer ? 6 / screenToImageScale : 0)
                    .background(item.hasContainer ? Color.white : Color.clear)
                    .scaleEffect(item.scale)
                    .rotationEffect(item.rotation)
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
    /// **Ajouté le 2026-08-26 (V5-F-085, Phase B P1-34)** — port de `ImageViewCanvas.scale`/
    /// `PROP_MATRIX`, manipulable via pincer-zoomer (`PlacedItemView`). Bornes `MIN_SCALE`/
    /// `MAX_SCALE` EXACTES d'`ImageViewCanvas.java:73-74` appliquées dans `PlacedItemView`, pas ici.
    var scale: CGFloat = 1
    /// Port de `ImageViewCanvas.rotate` (rotation libre à deux doigts) — angle appliqué via
    /// `.rotationEffect`, aucune borne côté Android (rotation libre 360°), reproduit à l'identique.
    var rotation: Angle = .zero
    /// Port de `isBorderText`/`btn_textContainer` (`ImageEditorCompound.java:441-457`, V5-F-087) —
    /// bascule texte noir-sur-fond-blanc (`true`, `containerColor=white`+`textColor=black`, ANDROID
    /// FORCE ces 2 couleurs, ignore tout choix de palette pendant que la bascule est active) vs
    /// l'état par défaut `false` (fond transparent, couleur de premier plan libre — `color`
    /// ci-dessus, déjà porté). Sans pertinence pour un sticker/emoji (jamais basculable côté
    /// Android non plus, bouton visible UNIQUEMENT en mode texte).
    var hasContainer: Bool = false
}

/// **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-085, Phase B P1-34)** — port de
/// `ImageViewCanvas.GestureListener`/`ScaleListener`/rotation à deux doigts, appliqués ICI à un
/// calque individuel (texte ou sticker) plutôt qu'au canevas entier, contrairement à `drawGesture`
/// (mode peinture, attaché au `ZStack` global) : SwiftUI route chaque geste au calque effectivement
/// touché via son propre hit-testing, reproduisant l'effet observable de la sélection
/// `objectInAction` d'Android sans avoir besoin d'un état de sélection explicite séparé (voir note
/// de tête de fichier pour l'écart mineur assumé : pas de surbrillance visuelle pendant la
/// manipulation).
private struct PlacedItemView: View {
    @Binding var item: PlacedText

    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1
    @GestureState private var rotateBy: Angle = .zero

    private static let minScale: CGFloat = 0.3
    private static let maxScale: CGFloat = 5.0

    var body: some View {
        Text(item.text)
            .font(.system(size: item.isSticker ? 64 : 30, weight: item.isSticker ? .regular : .bold))
            .foregroundStyle(item.color)
            // Port de `isBorderText`/`et.setContainerColor` (V5-F-087) — fond opaque plein derrière
            // le texte, PAS pertinent pour un sticker (jamais basculable côté Android).
            .padding(item.hasContainer ? 6 : 0)
            .background(item.hasContainer ? Color.white : Color.clear)
            .scaleEffect(item.scale * magnifyBy)
            .rotationEffect(item.rotation + rotateBy)
            .position(x: item.position.x + dragOffset.width, y: item.position.y + dragOffset.height)
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                item.position.x += value.translation.width
                item.position.y += value.translation.height
            }
    }

    /// Port de `ScaleListener.onScale` — clampe DÉJÀ pendant le geste (pas seulement au relâché),
    /// fidèle à `ImageViewCanvas.scale` qui corrige `scaleFactor` en temps réel dès que la borne est
    /// dépassée (`:1371-1374`), pas seulement au `onEnded`.
    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in
                let proposed = item.scale * value
                if proposed < Self.minScale {
                    state = Self.minScale / item.scale
                } else if proposed > Self.maxScale {
                    state = Self.maxScale / item.scale
                } else {
                    state = value
                }
            }
            .onEnded { value in
                let proposed = item.scale * value
                item.scale = min(max(proposed, Self.minScale), Self.maxScale)
            }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .updating($rotateBy) { value, state, _ in state = value }
            .onEnded { value in item.rotation += value }
    }
}
