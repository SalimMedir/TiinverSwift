import SwiftUI

/// Port du rendu/geste de `android/views/TimelineView.java` (`onDraw`/`drawRuler`/`drawPlayhead`/
/// `drawKeyframeMarkers`/`onTouchEvent`'s `Mode` state machine) au-dessus du modèle pur déjà porté
/// (`TimelineViewModel.swift`). Un seul `DragGesture` détermine le MODE au premier callback (comme
/// `onDown` côté Android choisit `Mode.PAN/DRAG/RESIZE_LEFT/RESIZE_RIGHT/SCRUB`), puis délègue au
/// modèle pour toute la durée du geste. Physique de fling (`OverScroller`/`VelocityTracker`)
/// délibérément PAS reproduite (voir tête de fichier `TimelineViewModel.swift`) — scroll direct
/// uniquement, pas d'inertie post-relâchement.
struct TimelineView: View {
    @ObservedObject var state: AnimemesEditorState

    @State private var dragMode: DragMode?
    @State private var lastMagnification: CGFloat = 1.0

    private enum DragMode {
        case scrub
        case pan(scrollFramesAtDown: Int)
        case dragItem(id: String, startDown: Int, endDown: Int, track: Int, startX: CGFloat)
        case resizeLeft(id: String, startDown: Int, endDown: Int, startX: CGFloat)
        case resizeRight(id: String, anchorX: CGFloat)
    }

    var body: some View {
        let model = state.timeline
        let height = model.rulerHeight + CGFloat(model.trackCount) * (model.trackHeight + model.trackGap) + 8
        GeometryReader { geo in
            Canvas { context, size in
                drawRuler(&context, model: model, size: size)
                for item in model.items {
                    drawItem(item, &context, model: model)
                }
                drawKeyframeMarkers(&context, model: model)
                drawPlayhead(&context, model: model, size: size)
            }
            .background(Color(white: 0.1))
            .clipped()
            .gesture(combinedDragGesture(model: model))
            .simultaneousGesture(magnificationGesture(model: model))
            .onAppear { model.resize(to: geo.size) }
            .onChange(of: geo.size) { model.resize(to: $0) }
        }
        .frame(height: height)
        .id(state.version)
    }

    // MARK: - Dessin

    private func drawRuler(_ context: inout GraphicsContext, model: TimelineViewModel, size: CGSize) {
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: model.rulerHeight)), with: .color(.black.opacity(0.4)))
        let secondFrames = max(1, model.frameRate)
        var frame = (model.scrollFrames / secondFrames) * secondFrames
        while true {
            let x = model.xAtFrame(frame)
            if x > size.width { break }
            if x >= model.leftPanelWidth {
                context.stroke(
                    Path { $0.move(to: CGPoint(x: x, y: model.rulerHeight - 6)); $0.addLine(to: CGPoint(x: x, y: model.rulerHeight)) },
                    with: .color(.white.opacity(0.5)), lineWidth: 1
                )
                let label = "\(frame / secondFrames)s"
                context.draw(Text(label).font(.system(size: 9)).foregroundColor(.white.opacity(0.7)), at: CGPoint(x: x + 2, y: 6))
            }
            frame += secondFrames
        }
    }

    private func drawItem(_ item: TimelineItem, _ context: inout GraphicsContext, model: TimelineViewModel) {
        let rect = model.itemRect(item, isResizingRightOn: model.selectedId)
        guard rect.maxX >= model.leftPanelWidth, rect.minX <= model.viewportWidth else { return }
        let color = Self.color(fromPacked: item.color)
        let isSelected = model.selectedId == item.id
        let path = Path(roundedRect: rect.insetBy(dx: 1, dy: 2), cornerRadius: 6)
        context.fill(path, with: .color(color.opacity(0.85)))
        if isSelected {
            context.stroke(path, with: .color(.white), lineWidth: 2)
        }
        context.draw(
            Text(item.label).font(.system(size: 10, weight: .semibold)).foregroundColor(.white),
            at: CGPoint(x: rect.minX + model.handleWidth + 4, y: rect.midY)
        )
        if isSelected {
            let leftHandle = CGRect(x: rect.minX, y: rect.minY, width: model.handleWidth, height: rect.height)
            let rightHandle = CGRect(x: rect.maxX - model.handleWidth, y: rect.minY, width: model.handleWidth, height: rect.height)
            context.fill(Path(leftHandle), with: .color(.white.opacity(0.6)))
            context.fill(Path(rightHandle), with: .color(.white.opacity(0.6)))
        }
    }

    /// Port de `drawKeyframeMarkers` — losange par keyframe, couleur selon la propriété
    /// (`KeyframeTrack.markerColor`).
    private func drawKeyframeMarkers(_ context: inout GraphicsContext, model: TimelineViewModel) {
        for obj in model.layers {
            guard let track = model.items.first(where: { $0.id == obj.id })?.track else { continue }
            let y = model.rulerHeight + CGFloat(track) * (model.trackHeight + model.trackGap) + model.trackHeight / 2 - model.scrollTracksPx
            for (_, kfTrack) in obj.keyframeTracks {
                let color = Self.color(fromPacked: kfTrack.markerColor)
                for kf in kfTrack.keyframes {
                    let frame = Int(kf.timestampNs / max(1, Int64(1_000_000_000 / model.frameRate)))
                    let x = model.xAtFrame(frame)
                    guard x >= model.leftPanelWidth, x <= model.viewportWidth else { continue }
                    let size = model.keyframeMarkerSize
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: x, y: y - size))
                    diamond.addLine(to: CGPoint(x: x + size, y: y))
                    diamond.addLine(to: CGPoint(x: x, y: y + size))
                    diamond.addLine(to: CGPoint(x: x - size, y: y))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(color))
                }
            }
        }
    }

    private func drawPlayhead(_ context: inout GraphicsContext, model: TimelineViewModel, size: CGSize) {
        let x = model.playheadX()
        context.stroke(
            Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
            with: .color(.red), lineWidth: 2
        )
    }

    private static func color(fromPacked argb: UInt32) -> Color {
        Color(
            red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }

    // MARK: - Gestes

    /// Port de `onTouchEvent`'s `onDown` — détermine le `Mode` au PREMIER callback
    /// (`value.translation == .zero`), délègue ensuite au modèle pour la durée du geste.
    private func combinedDragGesture(model: TimelineViewModel) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    let mode = Self.resolveMode(at: value.startLocation, model: model)
                    dragMode = mode
                    switch mode {
                    case .dragItem(let id, _, _, _, _), .resizeLeft(let id, _, _, _), .resizeRight(let id, _):
                        state.selectedId = id
                    case .scrub, .pan:
                        break
                    }
                }
                guard let mode = dragMode else { return }
                switch mode {
                case .scrub:
                    model.scrub(toX: value.location.x)
                    state.scrub(toFrame: model.playheadFrame)
                case .pan(let scrollFramesAtDown):
                    model.pan(scrollFramesAtDown: scrollFramesAtDown, deltaPx: value.translation.width)
                case .dragItem(let id, let startDown, let endDown, let track, let startX):
                    let dxFrame = Int(((value.location.x - startX) / model.pxPerFrame).rounded())
                    let newTrack = model.trackAtY(value.location.y)
                    _ = track
                    model.dragItem(id: id, startDown: startDown, endDown: endDown, dxFrame: dxFrame, newTrack: newTrack)
                    model.selectedId = id
                case .resizeLeft(let id, let startDown, let endDown, let startX):
                    let dxFrame = Int(((value.location.x - startX) / model.pxPerFrame).rounded())
                    model.resizeLeft(id: id, startDown: startDown, endDown: endDown, dxFrame: dxFrame)
                case .resizeRight(let id, let anchorX):
                    model.resizeRight(id: id, resizeRightAnchorX: anchorX, deltaPixels: value.location.x - anchorX)
                }
                state.bumpVersion()
            }
            .onEnded { _ in
                if case .dragItem = dragMode { state.applyTimelineItemsToLayers() }
                if case .resizeLeft = dragMode { state.applyTimelineItemsToLayers() }
                if case .resizeRight = dragMode { state.applyTimelineItemsToLayers() }
                dragMode = nil
            }
    }

    private func magnificationGesture(model: TimelineViewModel) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let pivot = model.pivotFrame(atFocusX: model.viewportWidth / 2)
                model.applyPinchZoom(scaleFactor: value / lastMagnification, pivotFrame: pivot, focusX: model.viewportWidth / 2)
                lastMagnification = value
                state.bumpVersion()
            }
            .onEnded { _ in lastMagnification = 1.0 }
    }

    private static func resolveMode(at point: CGPoint, model: TimelineViewModel) -> DragMode {
        if point.y < model.rulerHeight {
            return .scrub
        }
        if let item = model.hitTestItem(x: point.x, y: point.y) {
            model.selectedId = item.id
            let rect = model.itemRect(item, isResizingRightOn: model.selectedId)
            if model.inLeftHandle(rect, x: point.x) {
                return .resizeLeft(id: item.id, startDown: item.startFrame, endDown: item.endFrame, startX: point.x)
            }
            if model.inRightHandle(rect, x: point.x) {
                return .resizeRight(id: item.id, anchorX: point.x)
            }
            return .dragItem(id: item.id, startDown: item.startFrame, endDown: item.endFrame, track: item.track, startX: point.x)
        }
        return .pan(scrollFramesAtDown: model.scrollFrames)
    }
}
