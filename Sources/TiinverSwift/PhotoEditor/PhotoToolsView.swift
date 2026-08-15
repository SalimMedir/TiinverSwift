import SwiftUI

/// Port de la portion "outils" de `CroperView.java` (`handleFlip`/`handleRemoveBackground`) et du
/// sous-ensemble PRINCIPAL d'`ImageEditorCompound.java` (peinture libre `ic_paint`, texte
/// `containerEditText`) — écran intercalé entre le recadrage (`PhotoCropView`/`FreeformCropView`)
/// et la légende dans `PublishComposeView`, 2026-08-16. Périmètre volontairement réduit vs Android :
/// PAS de glisser-déposer du texte une fois placé (Android le permet), PAS de stickers/emoji, PAS
/// d'image composée (ajout d'une seconde image) — voir `MIGRATION_AUDIT.md`.
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
                            .font(.system(size: 30, weight: .bold))
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
                if !strokes.isEmpty || !texts.isEmpty {
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

    private func undo() {
        if !texts.isEmpty {
            texts.removeLast()
        } else if !strokes.isEmpty {
            strokes.removeLast()
        }
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

    private static func draw(_ stroke: DrawnStroke, in context: GraphicsContext) {
        guard stroke.points.count > 1 else { return }
        var path = Path()
        path.move(to: stroke.points[0])
        for point in stroke.points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
    }

    /// Aplatit l'image + les traits de peinture + le texte en une seule image bitmap avant
    /// publication (`ImageEditorCompound.saveImageWithPaint`/`saveImageWithText` côté Android — même
    /// principe, résolution finale ajustée à la résolution PIXEL de l'image source plutôt qu'à la
    /// taille d'affichage, via `ImageRenderer.scale`).
    @MainActor
    private func flatten() -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0, !strokes.isEmpty || !texts.isEmpty else {
            return displayedImage
        }
        let composed = ZStack {
            Image(uiImage: displayedImage).resizable().aspectRatio(contentMode: .fit)
            Canvas { context, _ in
                for stroke in strokes { Self.draw(stroke, in: context) }
            }
            ForEach(texts) { item in
                Text(item.text)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(item.color)
                    .position(item.position)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: composed)
        renderer.scale = max(displayedImage.size.width / canvasSize.width, 1) * displayedImage.scale
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
}
