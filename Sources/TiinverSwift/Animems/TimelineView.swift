import SwiftUI

/// Port du rendu/geste de `android/views/TimelineView.java` (`onDraw`/`drawRuler`/`drawPlayhead`/
/// `drawKeyframeMarkers`/`onTouchEvent`'s `Mode` state machine) au-dessus du modèle pur déjà porté
/// (`TimelineViewModel.swift`). Un seul `DragGesture` détermine le MODE au premier callback (comme
/// `onDown` côté Android choisit `Mode.PAN/DRAG/RESIZE_LEFT/RESIZE_RIGHT/SCRUB`), puis délègue au
/// modèle pour toute la durée du geste. Physique de fling (`OverScroller`/`VelocityTracker`)
/// délibérément PAS reproduite (voir tête de fichier `TimelineViewModel.swift`) — scroll direct
/// uniquement, pas d'inertie post-relâchement.
///
/// **CORRIGÉ le 2026-08-17 (P0-5)** : ce fichier portait la MÊME classe de bug que GAP-024 (déjà
/// corrigée sur le canevas principal, `AnimemesEditorView.swift`), jamais portée jusqu'ici à ce
/// fichier sœur — trouvée en le relisant intégralement pour cet audit plutôt que supposé correct
/// du fait que le canevas principal l'était déjà. Le `Canvas` ci-dessous portait `.id(state.version)`
/// EN PLUS de `.gesture(combinedDragGesture)`, ET `combinedDragGesture`/`magnificationGesture`
/// appelaient `state.bumpVersion()` (le compteur STRUCTUREL) à CHAQUE frame de pan/scrub/glisser-
/// item/redimensionner/pincer-zoomer — changer `.id()` détruit et recrée la vue (donc son
/// `UIGestureRecognizer` sous-jacent) : le geste s'auto-interrompait à CHAQUE mouvement du doigt,
/// rendant pan/scrub/déplacement d'item/redimensionnement/zoom de la timeline non fonctionnels
/// au-delà du tout premier micro-mouvement. `.id()` retiré (le redessin continue de fonctionner
/// sans lui : `TimelineView` est `@ObservedObject var state`, donc TOUTE mutation `@Published` de
/// `state`, y compris `renderVersion`, ré-évalue déjà `body`) ; les gestes continus utilisent
/// désormais `state.bumpRenderVersion()` au lieu de `state.bumpVersion()` (voir sa doc) pour éviter
/// aussi de relancer `preparePlayback()` à chaque frame — même motif que `renderVersion` sur le
/// canevas principal.
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
        /// Port du `return true` de `onDown` après un hit-test keyframe réussi (`TimelineView.java:
        /// 833-850`) — la touche est ENTIÈREMENT consommée par la sélection/suppression du
        /// keyframe, aucun scrub/pan/drag/resize ne doit démarrer pour le reste de ce geste
        /// (`minimumDistance: 0` rappelle `onChanged` à chaque frame, y compris si l'utilisateur
        /// bouge le doigt après le tap initial) — **ajouté le 2026-08-23 (V4-F-049, Phase B P1)**.
        case keyframeTap
        /// Port du même `return true` d'`onDown`, cette fois après un tap sur l'icône verrou/
        /// visibilité d'une piste (`e.getX() < leftPanelWidthPx`, `TimelineView.java:852-870`) —
        /// **ajouté le 2026-08-23 (V4-F-050, Phase B P1)**.
        case iconTap
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
                drawTrackIcons(&context, model: model)
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
                    // Port de `kfSelectPaint` (contour blanc, 2dp) — dessiné PAR-DESSUS le losange
                    // plein quand ce keyframe est sélectionné (`TimelineView.java:704`,
                    // `if (kf == selectedKeyframe) drawDiamond(c, ..., kfSelectPaint)`) — **ajouté
                    // le 2026-08-23 (V4-F-049, Phase B P1)**.
                    if kf.id == model.selectedKeyframeId {
                        context.stroke(diamond, with: .color(.white), lineWidth: 2)
                    }
                }
            }
        }
    }

    /// Port de `drawTrackIcons` (`TimelineView.java:589-612`) — icônes verrou/visibilité par
    /// piste, dans le panneau gauche (jusqu'ici entièrement vide côté iOS) — **ajouté le
    /// 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-050, Phase B P1)**.
    private func drawTrackIcons(_ context: inout GraphicsContext, model: TimelineViewModel) {
        for item in model.items {
            guard let obj = model.layers.first(where: { $0.id == item.id }) else { continue }
            for kind: TimelineViewModel.TrackIconKind in [.lock, .visibility] {
                let rect = model.iconScreenRect(trackIndex: item.track, kind: kind)
                let symbolName: String
                switch kind {
                case .lock: symbolName = obj.locked ? "lock.fill" : "lock.open"
                case .visibility: symbolName = obj.visible ? "eye.fill" : "eye.slash.fill"
                }
                let resolved = context.resolve(Image(systemName: symbolName).foregroundColor(.white.opacity(0.85)))
                context.draw(resolved, in: rect)
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
                    // Port de `onDown`'s hit-test keyframe PRIORITAIRE (`TimelineView.java:833-850`)
                    // — vérifié AVANT `resolveMode`/le repli scrub-pan-item, exactement comme
                    // Android teste `hitTestKeyframeMarker` en premier et consomme entièrement la
                    // touche (`return true`) en cas de succès, sans jamais atteindre le reste de
                    // `onDown`. **Ajouté le 2026-08-23 (V4-F-049, Phase B P1)** — `hitTestKeyframeMarker`/
                    // `AnimationObjectData.removeKeyframe` existaient déjà (portés, zéro appelant).
                    if let hit = model.hitTestKeyframeMarker(x: value.startLocation.x, y: value.startLocation.y) {
                        dragMode = .keyframeTap
                        if hit.keyframe.id == model.selectedKeyframeId {
                            // 2ᵉ tap sur le keyframe déjà sélectionné → suppression (port de
                            // `tappedKf == selectedKeyframe` → `onKeyframeDeleteRequested`).
                            state.deleteKeyframe(layerId: hit.layerId, propertyName: hit.propertyName, keyframeId: hit.keyframe.id)
                            model.selectedKeyframeId = nil
                        } else {
                            // 1er tap (ou tap sur un AUTRE keyframe) → (ré)sélection, PAS de
                            // suppression (port de la branche `else` → `onKeyframeSelected`, qui ne
                            // fait rien côté Android au-delà de mémoriser la sélection).
                            model.selectedKeyframeId = hit.keyframe.id
                        }
                    } else if let iconHit = model.hitTestTrackIcon(x: value.startLocation.x, y: value.startLocation.y) {
                        // Port du bloc icône de `onDown` (`e.getX() < leftPanelWidthPx`,
                        // `TimelineView.java:852-870`) → `onTrackIconClicked`
                        // (`AnimemesCompound.java:1639-1681`) — **ajouté le 2026-08-23 (V4-F-050,
                        // Phase B P1)**.
                        dragMode = .iconTap
                        switch iconHit.kind {
                        case .lock: state.toggleLocked(layerId: iconHit.itemId)
                        case .visibility: state.toggleVisible(layerId: iconHit.itemId)
                        }
                    } else {
                        let mode = Self.resolveMode(at: value.startLocation, model: model)
                        dragMode = mode
                        switch mode {
                        case .dragItem(let id, _, _, _, _), .resizeLeft(let id, _, _, _), .resizeRight(let id, _):
                            state.selectedId = id
                        case .scrub, .pan, .keyframeTap, .iconTap:
                            break
                        }
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
                case .keyframeTap, .iconTap:
                    // Touche entièrement consommée par le tap initial (sélection/suppression de
                    // keyframe, ou bascule verrou/visibilité, déjà appliquées ci-dessus) — tout
                    // mouvement ultérieur du doigt pendant CE geste est ignoré, fidèle au
                    // `return true` d'`onDown` qui empêche `mode` de basculer vers
                    // PAN/DRAG/RESIZE/SCRUB pour la suite de ce flux tactile.
                    break
                }
                // `renderVersion`, PAS `bumpVersion()` — voir note de tête de fichier (P0-5) :
                // ceci s'exécute à CHAQUE frame de ce geste continu. Redondant mais inoffensif pour
                // `.keyframeTap`/`.iconTap` (qui ont déjà appelé `bumpVersion()` via
                // `state.deleteKeyframe`/`toggleLocked`/`toggleVisible`) — `renderVersion` déclenche
                // un simple redessin en plus.
                state.bumpRenderVersion()
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
                // `renderVersion` — même raison que ci-dessus (geste continu, chaque frame de pincement).
                state.bumpRenderVersion()
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
