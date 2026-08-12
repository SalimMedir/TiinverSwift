import CoreGraphics
import Foundation

/// Port de la logique pure de `editor/view/ProTimelineView.java` (module 10, Trim/Timeline/
/// Waveform — 763 lignes, lu en entier) — fenêtre de sélection de trim façon "cassette
/// professionnelle". Même principe de séparation que `TimelineViewModel.swift` (module 8) : ce
/// fichier porte la géométrie/l'état, PAS le rendu `Canvas`/les gestes SwiftUI (différés).
///
/// **Deux espaces indépendants** (comportement Android reproduit à l'identique, voir commentaire
/// de tête de fichier original) :
///   - ESPACE ÉCRAN (pixels, `0...width`) : la fenêtre de sélection (`selLeftPx`/`selRightPx`) et
///     le playhead (`playheadPx`) y vivent, ne sortent jamais de l'écran.
///   - ESPACE TEMPS (millisecondes, `0...durationMs`) : la bande de vignettes y vit
///     (`viewStartMs`), défile sous la fenêtre fixe pendant la lecture ou le scroll utilisateur.
final class ProTimelineViewModel {
    // MARK: - Données

    private(set) var frameCount = 0
    private(set) var waveformData: [Float]?
    private(set) var durationMs: Int64 = 0

    // MARK: - Espace écran (pixels)

    private(set) var selLeftPx: CGFloat = 0
    private(set) var selRightPx: CGFloat = 0
    private(set) var playheadPx: CGFloat = 0

    // MARK: - Espace temps (millisecondes)

    private(set) var viewStartMs: Int64 = 0
    private(set) var viewWindowMs: Int64 = 0

    // MARK: - Timestamps dérivés

    private(set) var selStartMs: Int64 = 0
    private(set) var selEndMs: Int64 = 0
    private(set) var playheadMs: Int64 = 0

    // MARK: - Contraintes de sélection

    private var selMinWidthPx: CGFloat = 40
    private var selMaxWidthPx: CGFloat = 0
    private var minTrimMs: Int64 = 1000
    private var maxTrimMs: Int64 = 15000

    // MARK: - Scroll de la bande

    private var userScrolling = false
    private var scrollDownX: CGFloat = 0
    private var scrollDownViewStart: Int64 = 0

    // MARK: - Layout

    let marginPx: CGFloat = 8
    var touchHaloPx: CGFloat = 22

    // MARK: - Interaction

    enum DragMode { case none, dragLeft, dragRight, dragRegion, scroll }
    private(set) var mode: DragMode = .none
    private var downX: CGFloat = 0
    private var downSelLeftPx: CGFloat = 0
    private var downSelRightPx: CGFloat = 0

    private(set) var width: CGFloat = 0

    // MARK: - API publique

    /// Port de `setVideoFrames` — `frameCount` remplace `List<Bitmap> frames` (les vignettes
    /// elles-mêmes sont un souci d'affichage, pas de géométrie).
    func setVideoFrames(count: Int, durationMs videoDurationMs: Int64) {
        frameCount = count
        durationMs = max(0, videoDurationMs)
        viewStartMs = 0
        recalcWindow()
        initSelectionPx()
        syncTimestamps()
    }

    func setWaveform(_ normalizedSamples: [Float]?) {
        waveformData = normalizedSamples
    }

    /// Port de `setTrimLimits`.
    func setTrimLimits(minMs: Int64, maxMs: Int64) {
        minTrimMs = max(0, minMs)
        maxTrimMs = max(minTrimMs, maxMs)
        recalcWindow()
        clampSelectionPx()
        syncTimestamps()
    }

    /// Port de `onSizeChanged` — à appeler quand la largeur de la vue change.
    func resize(width newWidth: CGFloat) {
        width = newWidth
        if durationMs > 0 {
            recalcWindow()
            initSelectionPx()
            syncTimestamps()
        }
    }

    /// Port de `updatePlayhead` — appelé à ~30fps pendant la lecture. Retourne `true` si la
    /// sélection a bouclé (port du callback `onLoop`, l'appelant doit alors relancer la lecture à
    /// `selStartMs`).
    @discardableResult
    func updatePlayhead(currentPositionMs: Int64) -> Bool {
        guard durationMs > 0, viewWindowMs > 0 else { return false }

        if currentPositionMs >= selEndMs {
            playheadMs = selStartMs
            playheadPx = selLeftPx
            viewStartMs = msUnderPx(selLeftPx, selStartMs)
            viewStartMs = ProTimelineViewModel.clampL(viewStartMs, 0, max(0, durationMs - viewWindowMs))
            return true
        }

        playheadMs = ProTimelineViewModel.clampL(currentPositionMs, selStartMs, selEndMs)
        let selLen = selEndMs - selStartMs
        if selLen > 0 {
            let progress = CGFloat(playheadMs - selStartMs) / CGFloat(selLen)
            playheadPx = selLeftPx + progress * (selRightPx - selLeftPx)
            playheadPx = ProTimelineViewModel.clampF(playheadPx, selLeftPx, selRightPx)
        } else {
            playheadPx = selLeftPx
        }

        if !userScrolling {
            viewStartMs = msUnderPx(playheadPx, playheadMs)
            viewStartMs = ProTimelineViewModel.clampL(viewStartMs, 0, max(0, durationMs - viewWindowMs))
        }
        return false
    }

    var selectionDurationMs: Int64 { max(0, selEndMs - selStartMs) }

    // MARK: - Gestion de la fenêtre

    /// Port de `recalcWindow` — `maxTrimMs` occupe au maximum 80% de la largeur visible.
    private func recalcWindow() {
        guard durationMs > 0 else { viewWindowMs = 1; return }
        let w = width > 0 ? width : 1080

        let desired = Int64(Double(maxTrimMs) / 0.80)
        viewWindowMs = min(desired, durationMs)
        viewWindowMs = max(viewWindowMs, 2000)

        selMinWidthPx = CGFloat(minTrimMs) / CGFloat(viewWindowMs) * w
        selMaxWidthPx = CGFloat(maxTrimMs) / CGFloat(viewWindowMs) * w
        selMinWidthPx = max(selMinWidthPx, 30)
        selMaxWidthPx = min(selMaxWidthPx, w - 2 * marginPx)
    }

    private func initSelectionPx() {
        guard width > 0 else { return }
        let targetW = selMaxWidthPx > 0 ? selMaxWidthPx : width * 0.8
        let center = width / 2
        selLeftPx = max(marginPx, center - targetW / 2)
        selRightPx = min(width - marginPx, selLeftPx + targetW)
        playheadPx = selLeftPx
    }

    private func clampSelectionPx() {
        guard width > 0 else { return }
        var w = selRightPx - selLeftPx
        w = max(selMinWidthPx, min(selMaxWidthPx, w))
        selLeftPx = max(marginPx, selLeftPx)
        selRightPx = selLeftPx + w
        if selRightPx > width - marginPx {
            selRightPx = width - marginPx
            selLeftPx = max(marginPx, selRightPx - w)
        }
        playheadPx = ProTimelineViewModel.clampF(playheadPx, selLeftPx, selRightPx)
    }

    /// Port de `syncTimestamps`.
    private func syncTimestamps() {
        selStartMs = pxToMs(selLeftPx)
        selEndMs = pxToMs(selRightPx)
        let selWidthPx = selRightPx - selLeftPx
        if selWidthPx > 0 {
            let progress = (playheadPx - selLeftPx) / selWidthPx
            let selLen = selEndMs - selStartMs
            playheadMs = selStartMs + Int64(Double(progress) * Double(selLen))
        } else {
            playheadMs = selStartMs
        }
        selStartMs = ProTimelineViewModel.clampL(selStartMs, 0, durationMs)
        selEndMs = ProTimelineViewModel.clampL(selEndMs, selStartMs, durationMs)
        playheadMs = ProTimelineViewModel.clampL(playheadMs, selStartMs, selEndMs)
    }

    // MARK: - Conversions pixels <-> temps

    func msToX(_ ms: Int64) -> CGFloat {
        guard viewWindowMs > 0, width > 0 else { return 0 }
        return CGFloat(ms - viewStartMs) / CGFloat(viewWindowMs) * width
    }

    private func pxToMs(_ px: CGFloat) -> Int64 {
        guard viewWindowMs > 0, width > 0 else { return viewStartMs }
        return viewStartMs + Int64(Double(px / width) * Double(viewWindowMs))
    }

    private func msUnderPx(_ px: CGFloat, _ ms: Int64) -> Int64 {
        guard viewWindowMs > 0, width > 0 else { return 0 }
        return ms - Int64(Double(px / width) * Double(viewWindowMs))
    }

    // MARK: - Touch (port de onTouchEvent/handleMove/pickMode)

    func touchDown(at x: CGFloat) {
        userScrolling = true
        scrollDownX = x
        scrollDownViewStart = viewStartMs
        mode = pickMode(x)
        downX = x
        downSelLeftPx = selLeftPx
        downSelRightPx = selRightPx
    }

    /// Retourne `true` si la sélection a changé pendant ce mouvement (port de la notification
    /// `listener.onSelectionChanged`), et le timestamp de scrub courant si en mode `.scroll` (port
    /// de `listener.onUserScrub`).
    func touchMove(to x: CGFloat) -> (selectionChanged: Bool, scrubMs: Int64?) {
        let w = width
        switch mode {
        case .scroll:
            let dxPx = x - scrollDownX
            let frac = dxPx / w
            let dxMs = Int64(Double(frac) * Double(viewWindowMs))
            viewStartMs = ProTimelineViewModel.clampL(
                scrollDownViewStart - dxMs, 0, max(0, durationMs - viewWindowMs))
            syncTimestamps()
            return (false, playheadMs)

        case .dragLeft:
            var newLeft = downSelLeftPx + (x - downX)
            newLeft = max(marginPx, newLeft)
            newLeft = min(selRightPx - selMinWidthPx, newLeft)
            if selRightPx - newLeft > selMaxWidthPx { newLeft = selRightPx - selMaxWidthPx }
            selLeftPx = newLeft
            playheadPx = ProTimelineViewModel.clampF(playheadPx, selLeftPx, selRightPx)
            syncTimestamps()
            return (true, nil)

        case .dragRight:
            var newRight = downSelRightPx + (x - downX)
            newRight = min(w - marginPx, newRight)
            newRight = max(selLeftPx + selMinWidthPx, newRight)
            if newRight - selLeftPx > selMaxWidthPx { newRight = selLeftPx + selMaxWidthPx }
            selRightPx = newRight
            playheadPx = ProTimelineViewModel.clampF(playheadPx, selLeftPx, selRightPx)
            syncTimestamps()
            return (true, nil)

        case .dragRegion:
            let width0 = downSelRightPx - downSelLeftPx
            var newLeft = downSelLeftPx + (x - downX)
            newLeft = max(marginPx, newLeft)
            newLeft = min(w - marginPx - width0, newLeft)
            let relFrac = width0 > 0 ? (playheadPx - selLeftPx) / width0 : 0.5
            selLeftPx = newLeft
            selRightPx = newLeft + width0
            playheadPx = ProTimelineViewModel.clampF(selLeftPx + relFrac * width0, selLeftPx, selRightPx)
            syncTimestamps()
            return (true, nil)

        case .none:
            return (false, nil)
        }
    }

    /// Port du bloc `ACTION_UP`/`ACTION_CANCEL` — retourne `(selStartMs, selEndMs)` (port de
    /// `listener.onSelectionFinished`).
    func touchUp() -> (Int64, Int64) {
        userScrolling = false
        mode = .none
        return (selStartMs, selEndMs)
    }

    private func pickMode(_ x: CGFloat) -> DragMode {
        if abs(x - selLeftPx) <= touchHaloPx { return .dragLeft }
        if abs(x - selRightPx) <= touchHaloPx { return .dragRight }
        if x > selLeftPx && x < selRightPx { return .dragRegion }
        return .scroll
    }

    // MARK: - Helpers

    private static func clampL(_ v: Int64, _ lo: Int64, _ hi: Int64) -> Int64 { max(lo, min(hi, v)) }
    private static func clampF(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }
}
