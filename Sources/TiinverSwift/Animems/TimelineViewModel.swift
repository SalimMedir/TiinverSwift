import CoreGraphics
import Foundation

/// Port de la logique pure de `android/views/TimelineView.java` (1320 lignes, lu en entier) — le
/// morceau le plus volumineux du module 8. Sépare délibérément :
///   - CE FICHIER : modèle d'état + mathématiques de coordonnées/zoom/scroll/anti-chevauchement —
///     entièrement indépendant d'Android, directement testable, réutilisable par n'importe quel
///     rendu SwiftUI.
///   - NON PORTÉ (différé, comme documenté module 8) : `onDraw`/`drawRuler`/`drawPlayhead`/
///     `drawKeyframeMarkers`/`drawDiamond` (deviendront un `Canvas` SwiftUI), la physique de fling
///     `OverScroller`/`VelocityTracker` (pas d'équivalent direct — SwiftUI `DragGesture` fournit sa
///     propre vélocité, la ballistique devra être redessinée avec `.animation`, invérifiable sans
///     simulateur), la planification de l'appui long via `Handler`/`Runnable` (remplacé trivialement
///     par `.onLongPressGesture`, aucune logique à porter), et `toJson`/`fromJson` (JSON manuel
///     Android — `TimelineItem` étant déjà un type Swift natif, un `Codable` direct sur
///     `TimelineItem` couvrira le même besoin sans reproduire ce code, à ajouter au moment où la
///     persistance sera implémentée).
final class TimelineViewModel {
    // MARK: - Configuration (constantes de layout, `dp` déjà résolu en points)

    var leftPanelWidth: CGFloat = 92
    var trackHeight: CGFloat = 42
    var trackGap: CGFloat = 6
    let handleWidth: CGFloat = 14
    let keyframeMarkerSize: CGFloat = 8
    let rulerHeight: CGFloat = 20
    let longPressTimeoutMs: Int = 500

    // MARK: - État général

    var trackCount = 5
    var frameRate = 30
    private(set) var pxPerFrame: CGFloat = 8
    private(set) var totalFrames = 900
    let minTotalFrames = 60
    let maxTotalFrames = 200_000

    /// Frame qui s'aligne sur `x == leftPanelWidth` — voir `xAtFrame`.
    private(set) var scrollFrames = 0
    var scrollTracksPx: CGFloat = 0
    private(set) var maxScrollTracksPx: CGFloat = 0
    private(set) var playheadFrame = 0

    var items: [TimelineItem] = []
    var selectedId: String?
    /// Port de `selectedKeyframe` (`TimelineView.java:126`) — id du keyframe actuellement
    /// sélectionné (`Keyframe.id`, armé pour suppression au prochain tap dessus, `nil` si aucun) —
    /// **ajouté le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-049, Phase B P1)**.
    var selectedKeyframeId: String?
    var groupIconId: Int = -1
    /// `layers` sert uniquement à `hasActiveGroupSources`/keyframes — liste NON filtrée (voir note
    /// Android reproduite dans `hasActiveGroupSources`).
    var layers: [AnimationObjectData] = []

    private(set) var viewportWidth: CGFloat = 0
    private(set) var viewportHeight: CGFloat = 0

    struct TrackIcon {
        var trackIndex: Int
        var id: Int
        var itemId: String?
        var bounds: CGRect = .zero
    }
    private(set) var trackIcons: [Int: [TrackIcon]] = [:]

    // MARK: - Redimensionnement de la vue

    /// Port de `onSizeChanged`.
    func resize(to size: CGSize) {
        viewportWidth = size.width
        viewportHeight = size.height
        let visibleHeight = size.height - rulerHeight
        maxScrollTracksPx = max(0, totalTracksHeight - visibleHeight)
        scrollTracksPx = TimelineViewModel.clamp(scrollTracksPx, 0, maxScrollTracksPx)
        scrollFrames = TimelineViewModel.clampI(
            playheadFrame - contentHalfFrames, scrollMin, maxScrollFrames)
    }

    private var totalTracksHeight: CGFloat {
        CGFloat(trackCount) * (trackHeight + trackGap)
    }

    // MARK: - API publique (setters avec effets de bord, port des setters Android)

    func setPxPerFrame(_ v: CGFloat) {
        pxPerFrame = TimelineViewModel.clamp(v, 1, 200)
    }

    /// Port de `setTotalFrames` — jamais sous `minTotalFrames`, jamais sous ce qu'exigent les
    /// items existants (`requiredTotalFrames`).
    func setTotalFrames(_ f: Int) {
        let minEnd = requiredTotalFrames
        totalFrames = TimelineViewModel.clampI(f, max(minTotalFrames, minEnd), maxTotalFrames)
        scrollFrames = TimelineViewModel.clampI(scrollFrames, scrollMin, maxScrollFrames)
    }

    /// Port de `setPlayheadFrame(frame, external)`. `external == false` recentre le scroll (piloté
    /// par le moteur de lecture) ; `external == true` ne fait que mettre à jour le compteur (scrub
    /// manuel de l'utilisateur, la vue reste où il l'a laissée).
    func setPlayheadFrame(_ frame: Int, external: Bool) {
        playheadFrame = TimelineViewModel.clampI(frame, 0, max(0, totalFrames - 1))
        if !external {
            scrollFrames = TimelineViewModel.clampI(
                playheadFrame - contentHalfFrames, scrollMin, maxScrollFrames)
        }
    }

    /// Port de `addItem` — résout l'anti-chevauchement avant insertion, étend `totalFrames` si
    /// besoin.
    func addItem(_ item: TimelineItem) {
        var it = item
        clamp(&it)
        let fixed = resolveOverlap(skipId: it.id, track: it.track, start: it.startFrame, end: visibleEnd(it))
        it.startFrame = fixed.0
        it.endFrame = fixed.1
        items.append(it)
        setTotalFrames(totalFrames)
    }

    /// Port de `removeItem`.
    func removeItem(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trackIndex = items[index].track
        items.remove(at: index)
        if selectedId == id { selectedId = nil }
        if var icons = trackIcons[trackIndex] {
            icons.removeAll { $0.itemId == id }
            if icons.isEmpty { trackIcons.removeValue(forKey: trackIndex) } else { trackIcons[trackIndex] = icons }
        }
    }

    /// Port de `frameToTimestampNs`.
    func frameToTimestampNs(_ frame: Int) -> Int64 {
        let nsPerFrame: Int64 = frameRate > 0 ? 1_000_000_000 / Int64(frameRate) : 33_333_333
        return Int64(frame) * nsPerFrame
    }

    private func timestampNsToFrame(_ ns: Int64) -> Int {
        let nsPerFrame: Int64 = frameRate > 0 ? 1_000_000_000 / Int64(frameRate) : 33_333_333
        return TimelineViewModel.clampI(Int(ns / nsPerFrame), 0, totalFrames - 1)
    }

    // MARK: - Icônes de piste

    /// Port de `addTrackIcon`.
    func addTrackIcon(trackIndex: Int, iconId: Int, itemId: String?) {
        guard trackIndex >= 0 else { return }
        var icons = trackIcons[trackIndex] ?? []
        if icons.contains(where: { $0.id == iconId && $0.itemId == itemId }) { return }
        icons.append(TrackIcon(trackIndex: trackIndex, id: iconId, itemId: itemId))
        trackIcons[trackIndex] = icons
    }

    func clearTrackIcons(trackIndex: Int) {
        trackIcons.removeValue(forKey: trackIndex)
    }

    func findItemByTrack(_ track: Int) -> TimelineItem? {
        if let selectedId, let selected = items.first(where: { $0.id == selectedId }), selected.track == track {
            return selected
        }
        return items.first { $0.track == track }
    }

    /// Port de `hasActiveGroupSources` — voir commentaire Android reproduit : on scanne `layers`
    /// (liste complète, non filtrée), PAS `items` (liste déjà filtrée pour l'affichage), seule
    /// source fiable pour savoir si un groupe recompose a encore des sources réelles.
    func hasActiveGroupSources(_ groupId: String?) -> Bool {
        guard let groupId else { return false }
        return layers.contains { $0.recomposeGroupId == groupId && $0.id != groupId }
    }

    // MARK: - Zoom (pinch)

    /// Port de `ScaleGestureDetector`'s `onScaleBegin` — capture la frame sous le point focal AVANT
    /// zoom, pour pouvoir la re-ancrer après (voir `applyPinchZoom`).
    func pivotFrame(atFocusX focusX: CGFloat) -> Int {
        frameAtX(focusX)
    }

    /// Port de `onScale` — zoom autour de `pivotFrame` (capturé par `pivotFrame(atFocusX:)` au
    /// début du geste), pour que le point sous les doigts reste stable pendant le pincement.
    func applyPinchZoom(scaleFactor: CGFloat, pivotFrame: Int, focusX: CGFloat) {
        setPxPerFrame(pxPerFrame * scaleFactor)
        scrollFrames = TimelineViewModel.clampI(
            Int((CGFloat(pivotFrame) - (focusX - leftPanelWidth) / pxPerFrame).rounded()),
            scrollMin, maxScrollFrames)
    }

    // MARK: - Pan / scrub

    /// Port de la branche horizontale de `onMove`'s `Mode.PAN` — fait défiler le contenu et
    /// resynchronise `playheadFrame` (le playhead reste toujours centré pendant un pan).
    func pan(scrollFramesAtDown: Int, deltaPx: CGFloat) {
        scrollFrames = TimelineViewModel.clampI(
            Int((CGFloat(scrollFramesAtDown) - deltaPx / pxPerFrame).rounded()), scrollMin, maxScrollFrames)
        playheadFrame = TimelineViewModel.clampI(scrollFrames + contentHalfFrames, 0, totalFrames - 1)
    }

    /// Port de `scrubToX` (mode `SCRUB`, drag sur la règle).
    func scrub(toX x: CGFloat) {
        setPlayheadFrame(frameAtX(x), external: false)
    }

    // MARK: - Drag / resize d'un item (port de `onMove`'s `Mode.DRAG/RESIZE_LEFT/RESIZE_RIGHT`)

    /// Port de la branche `DRAG`.
    func dragItem(id: String, startDown: Int, endDown: Int, dxFrame: Int, newTrack: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let track = TimelineViewModel.clampI(newTrack, 0, trackCount - 1)
        let fixed = resolveOverlap(skipId: id, track: track, start: startDown + dxFrame, end: endDown + dxFrame)
        items[index].track = track
        items[index].startFrame = fixed.0
        items[index].endFrame = fixed.1
    }

    /// Port de la branche `RESIZE_LEFT`.
    func resizeLeft(id: String, startDown: Int, endDown: Int, dxFrame: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        var newStart = clampFrame(startDown + dxFrame)
        let minStart = max(0, endDown - item.minDurationFrames + 1)
        newStart = TimelineViewModel.clampI(newStart, 0, minStart)
        let fixed = resolveOverlapResizeLeft(skipId: id, track: item.track, start: newStart, end: endDown)
        items[index].startFrame = fixed.0
        items[index].endFrame = fixed.1
    }

    /// Port de la branche `RESIZE_RIGHT` — calcul en pixels flottants depuis le point de départ
    /// (`resizeRightAnchorX`) pour éviter le tremblement dû aux arrondis répétés, reproduit à
    /// l'identique.
    func resizeRight(id: String, resizeRightAnchorX: CGFloat, deltaPixels: CGFloat) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        let newRightPx = resizeRightAnchorX + deltaPixels
        var newEnd = Int(((newRightPx - leftPanelWidth) / pxPerFrame).rounded()) + scrollFrames
        let minEnd = item.startFrame + item.minDurationFrames - 1
        newEnd = max(newEnd, minEnd)
        let fixed = resolveOverlapResizeRight(skipId: id, track: item.track, start: item.startFrame, end: newEnd)
        items[index].startFrame = fixed.0
        items[index].endFrame = fixed.1
    }

    // MARK: - Anti-chevauchement

    private func overlaps(track: Int, start s: Int, end e: Int, skipId: String?) -> Bool {
        items.contains { it in
            if let skipId, skipId == it.id { return false }
            if it.track != track { return false }
            let se = visibleEnd(it)
            return !(e < it.startFrame || se < s)
        }
    }

    /// Port de `resolveOverlap` — pousse l'item après le premier bloc en conflit, en boucle
    /// (garde-fou `totalFrames * 2` itérations comme l'original).
    func resolveOverlap(skipId: String?, track: Int, start: Int, end: Int) -> (Int, Int) {
        var s = clampFrame(start)
        var e = clampFrame(max(end, s))
        let dur = max(1, e - s + 1)
        var tryS = s, tryE = e
        var guardCount = totalFrames * 2
        while overlaps(track: track, start: tryS, end: tryE, skipId: skipId), guardCount > 0 {
            guardCount -= 1
            tryS = tryE + 1
            tryE = tryS + dur - 1
            if tryE >= totalFrames { setTotalFrames(tryE + 1) }
        }
        s = clampFrame(tryS); e = clampFrame(tryE)
        return (s, e)
    }

    /// Port de `resolveOverlapResizeLeft`.
    func resolveOverlapResizeLeft(skipId: String, track: Int, start: Int, end: Int) -> (Int, Int) {
        var s = clampFrame(start)
        let e = clampFrame(max(end, s))
        var leftBound = 0
        for it in items {
            if it.id == skipId || it.track != track { continue }
            let se = visibleEnd(it)
            if se < s, se + 1 > leftBound { leftBound = se + 1 }
        }
        s = max(s, leftBound)
        if s > e { s = e }
        return (s, e)
    }

    /// Port de `resolveOverlapResizeRight`.
    func resolveOverlapResizeRight(skipId: String, track: Int, start: Int, end: Int) -> (Int, Int) {
        let s = max(0, start)
        var e = end
        if e >= totalFrames { setTotalFrames(e + 1) }
        e = max(e, s)
        var rightBound = totalFrames - 1
        for it in items {
            if it.id == skipId || it.track != track { continue }
            if it.startFrame > s { rightBound = min(rightBound, it.startFrame - 1) }
        }
        e = min(e, rightBound)
        if e < s { e = s }
        return (s, e)
    }

    // MARK: - Géométrie

    /// Port de `itemRect` — largeur minimale garantie (poignées + marge), sauf pendant un resize
    /// droit actif sur l'item sélectionné (marge minimale réduite pour laisser l'utilisateur
    /// rétrécir davantage).
    func itemRect(_ it: TimelineItem, isResizingRightOn selectedId: String?) -> CGRect {
        let top = rulerHeight + CGFloat(it.track) * (trackHeight + trackGap)
        let left = xAtFrame(it.startFrame)
        var right = xAtFrame(visibleEnd(it) + 1)

        if selectedId != it.id {
            let minWidth = max(handleWidth * 2 + 12, pxPerFrame * CGFloat(it.minDurationFrames))
            if right - left < minWidth { right = left + minWidth }
        } else {
            let absoluteMin = handleWidth * 2 + 4
            if right - left < absoluteMin { right = left + absoluteMin }
        }
        return CGRect(x: left, y: top, width: right - left, height: trackHeight)
    }

    func inLeftHandle(_ rect: CGRect, x: CGFloat) -> Bool { x >= rect.minX && x <= rect.minX + handleWidth }
    func inRightHandle(_ rect: CGRect, x: CGFloat) -> Bool { x >= rect.maxX - handleWidth && x <= rect.maxX }

    /// Port de `hitTestItem` — parcourt en ordre inverse (les items dessinés en dernier, donc
    /// visuellement au-dessus, gagnent le hit-test).
    func hitTestItem(x: CGFloat, y: CGFloat) -> TimelineItem? {
        let yy = y + scrollTracksPx
        for it in items.reversed() {
            if itemRect(it, isResizingRightOn: nil).contains(CGPoint(x: x, y: yy)) { return it }
        }
        return nil
    }

    /// Port de `hitTestKeyframeMarker`.
    func hitTestKeyframeMarker(x: CGFloat, y: CGFloat) -> (layerId: String, propertyName: String, keyframe: Keyframe)? {
        let yWithScroll = y + scrollTracksPx
        for obj in layers where obj.hasKeyframes {
            guard let trackIndex = findTrackIndex(forLayerId: obj.id), trackIndex >= 0 else { continue }
            let trackY = rulerHeight + CGFloat(trackIndex) * (trackHeight + trackGap) + trackHeight / 2
            if abs(yWithScroll - trackY) > keyframeMarkerSize { continue }
            for (propertyName, track) in obj.keyframeTracks {
                for kf in track.keyframes {
                    let markerX = xAtFrame(timestampNsToFrame(kf.timestampNs))
                    if abs(x - markerX) <= keyframeMarkerSize {
                        return (obj.id, propertyName, kf)
                    }
                }
            }
        }
        return nil
    }

    private func findTrackIndex(forLayerId layerId: String) -> Int? {
        items.first { $0.id == layerId }?.track
    }

    // MARK: - Coordonnées (port de la section "Coordinate helpers")

    /// Position x du playhead fixe (toujours au centre horizontal de la zone scrollable).
    func playheadX() -> CGFloat {
        leftPanelWidth + contentHalfWidth
    }

    /// Port de `contentQuarterWidth`/`contentHalfWidth` — nommage Android trompeur conservé tel
    /// quel dans le commentaire d'origine : c'est effectivement un QUART de la largeur scrollable
    /// totale qui sert de demi-largeur de référence pour le centrage (`contentHalfWidth() ==
    /// contentQuarterWidth()`, reproduit tel quel malgré l'apparente incohérence de nommage).
    private var contentHalfWidth: CGFloat {
        max(0, (viewportWidth - leftPanelWidth) / 4)
    }

    private var contentHalfFrames: Int {
        Int((contentHalfWidth / max(1, pxPerFrame)).rounded())
    }

    /// Port de `xAtFrame`.
    func xAtFrame(_ frame: Int) -> CGFloat {
        leftPanelWidth + (CGFloat(frame - scrollFrames) * pxPerFrame).rounded()
    }

    /// Port de `frameAtX`.
    func frameAtX(_ x: CGFloat) -> Int {
        clampFrame(Int(((x - leftPanelWidth) / pxPerFrame).rounded()) + scrollFrames)
    }

    func trackAtY(_ y: CGFloat) -> Int {
        let block = trackHeight + trackGap
        let rel = max(0, y + scrollTracksPx - rulerHeight)
        return TimelineViewModel.clampI(Int(rel / block), 0, trackCount - 1)
    }

    func visibleEnd(_ it: TimelineItem) -> Int { it.visibleEnd(totalFrames: totalFrames) }

    var framesVisible: Int {
        max(1, Int((viewportWidth / max(1, pxPerFrame)).rounded()))
    }

    /// Port de `maxScrollFrames` — autorise à défiler jusqu'à amener la dernière frame au centre.
    var maxScrollFrames: Int {
        max(0, totalFrames - 1 + contentHalfFrames)
    }

    /// Port de `scrollMin` — autorise à défiler jusqu'à amener la frame 0 au centre.
    var scrollMin: Int {
        -contentHalfFrames
    }

    // MARK: - Clamp

    private func clamp(_ it: inout TimelineItem) {
        it.track = TimelineViewModel.clampI(it.track, 0, trackCount - 1)
        it.startFrame = clampFrame(it.startFrame)
        if it.endFrame >= 0 {
            let minEnd = it.startFrame + it.minDurationFrames - 1
            it.endFrame = clampFrame(max(it.endFrame, minEnd))
        }
    }

    /// Port de `clampAll`.
    func clampAll() {
        for i in items.indices { clamp(&items[i]) }
        setTotalFrames(totalFrames)
    }

    /// Port de `requiredTotalFrames`.
    private var requiredTotalFrames: Int {
        items.reduce(minTotalFrames) { max($0, visibleEnd($1) + 1) }
    }

    private func clampFrame(_ f: Int) -> Int {
        TimelineViewModel.clampI(f, 0, max(0, totalFrames - 1))
    }

    private static func clampI(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }
    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }
}
