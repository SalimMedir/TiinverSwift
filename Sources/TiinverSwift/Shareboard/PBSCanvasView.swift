import SwiftUI
import UIKit

/// Port du rendu de `PBSView.onDraw`/`startDraw`/`drawPath`/`writeText`/`drawBitmap`/`drawShap` +
/// des gestes tactiles (`touchListener`/`touchDown`/`touchMove`/`executeDeleterObjeect`), réécrit en
/// SwiftUI natif plutôt que traduit ligne à ligne : les traits libres sont dessinés dans un
/// `Canvas` (chemins vectoriels), les objets placés (texte/image/sticker) sont de VRAIES vues
/// SwiftUI empilées au-dessus (`Text`/`Image` avec `DragGesture`/`MagnificationGesture`/
/// `RotationGesture` natifs), plutôt que hit-testées manuellement dans une boucle `onDraw` comme
/// l'original — voir l'avertissement de portée dans `PBSCanvasEngine.swift`.
///
/// **Effets décoratifs Android NON repris, délibérément différés** : icône "Tiinver" embossée
/// (`drawTiinverIcon`, `EmbossMaskFilter`/`BlurMaskFilter`), carrousel de bannières publicitaires
/// (`BannerAdapter`/`ViewPager2`), tutoriel `TapTargetView` au premier lancement — purement
/// décoratifs/publicitaires, sans impact sur la fonction collaborative principale, non portés pour
/// rester dans le temps imparti à ce module ; documentés ici plutôt que silencieusement omis.
struct PBSCanvasView: View {
    @ObservedObject var engine: PBSCanvasEngine
    var isInteractive: Bool = true

    @State private var draggingObjectId: String?
    @State private var isOverDeleteZone = false
    @State private var isStrokeInProgress = false
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var pinchRotation: Angle = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(white: 0.97)
                if let backgroundImageData = engine.backgroundImageData, let uiImage = UIImage(data: backgroundImageData) {
                    Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill).clipped()
                }

                Canvas { context, _ in
                    for stroke in engine.currentPage.strokes {
                        guard stroke.strokePoints.count > 1 else { continue }
                        var path = Path()
                        path.move(to: stroke.strokePoints[0])
                        for point in stroke.strokePoints.dropFirst() { path.addLine(to: point) }
                        context.stroke(
                            path, with: .color(Self.color(fromARGB: stroke.paintColor)),
                            style: StrokeStyle(lineWidth: stroke.paintWidth, lineCap: .round, lineJoin: .round))
                    }
                }
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .allowsHitTesting(isInteractive)

                ForEach(engine.currentPage.objects) { object in
                    objectView(object)
                        .allowsHitTesting(isInteractive)
                }

                if isOverDeleteZone {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white, .red)
                        .position(x: proxy.size.width / 2, y: 44)
                }
            }
            .onAppear { engine.localViewSize = proxy.size }
            .onChange(of: proxy.size) { newValue in engine.localViewSize = newValue }
        }
    }

    // MARK: - Dessin libre (port de `touchListener` cas `action == "drawPath"`)

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isStrokeInProgress {
                    engine.continueLocalStroke(to: value.location)
                } else {
                    isStrokeInProgress = true
                    engine.beginLocalStroke(at: value.location)
                }
            }
            .onEnded { value in
                isStrokeInProgress = false
                engine.endLocalStroke(at: value.location)
            }
    }

    // MARK: - Objets placés (port de `touchDown`/`touchMove`/`executeDeleterObjeect`)

    @ViewBuilder
    private func objectView(_ object: PBSEditorData) -> some View {
        let isDragged = draggingObjectId == object.id
        let liveOffset = isDragged ? dragTranslation : .zero
        let liveScale = isDragged ? pinchScale : 1
        let liveRotation = isDragged ? pinchRotation : .zero

        content(for: object)
            .scaleEffect(liveScale)
            .rotationEffect(liveRotation)
            .position(
                x: (object.type == "text" ? object.textWidth : object.posX) + liveOffset.width,
                y: (object.type == "text" ? object.textHeight : object.posY) + liveOffset.height)
            .gesture(objectGesture(for: object))
    }

    @ViewBuilder
    private func content(for object: PBSEditorData) -> some View {
        switch object.type {
        case "text":
            Text(object.text ?? "")
                .foregroundStyle(Self.color(fromARGB: object.textColor))
                .padding(8)
                .background(Self.color(fromARGB: object.containerColor), in: RoundedRectangle(cornerRadius: 8))
        case "media1", "media2", "smile":
            if let data = object.bitmapData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: max(24, CGFloat(object.bitmapWidth)), height: max(24, CGFloat(object.bitmapHeight)))
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        default:
            Color.clear.frame(width: 1, height: 1)
        }
    }

    /// Port de `touchDown`/`touchMove`/`touchPointerDown`(`modo==1`/`modo==2`) — un geste composite
    /// natif remplace la trigonométrie manuelle (`getMidPoint`/`getDegre`/`getDistance`) de
    /// l'original.
    private func objectGesture(for object: PBSEditorData) -> some Gesture {
        let drag = DragGesture()
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onChanged { value in
                draggingObjectId = object.id
                isOverDeleteZone = value.location.y < 90 && abs(value.location.x - engine.localViewSize.width / 2) < 60
            }

        let pinch = MagnificationGesture()
            .updating($pinchScale) { value, state, _ in state = value }
        let rotate = RotationGesture()
            .updating($pinchRotation) { value, state, _ in state = value }

        return SimultaneousGesture(drag, SimultaneousGesture(pinch, rotate))
            .onEnded { _ in
                defer { draggingObjectId = nil }
                if isOverDeleteZone {
                    engine.deleteObject(id: object.id)
                    isOverDeleteZone = false
                    return
                }
                var updated = object
                if object.type == "text" {
                    updated.textWidth += dragTranslation.width
                    updated.textHeight += dragTranslation.height
                } else {
                    updated.posX += dragTranslation.width
                    updated.posY += dragTranslation.height
                }
                engine.updateObject(updated)
                engine.onLocalObjectPlaced?(updated)
            }
    }

    /// Port de `Color.argb`/les entiers couleur Android (`Paint.setColor(int)`, ARGB empaqueté sur
    /// 32 bits) — même disposition de bits que `android.graphics.Color`.
    static func color(fromARGB value: Int) -> Color {
        let a = Double((value >> 24) & 0xFF) / 255
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a == 0 ? 1 : a)
    }
}
