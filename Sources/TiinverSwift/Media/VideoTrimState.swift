import Foundation

/// Port de l'état (rotation/flip/ratio) de `view/trimmer/VideoTrimmerView.java` (module 10) — la
/// géométrie de la fenêtre de trim elle-même est portée séparément dans `ProTimelineViewModel.swift`
/// (port direct de `editor/view/ProTimelineView.java`, 763 lignes, lu en entier).
///
/// **Décision d'architecture pour l'export** (comme MetalPetal/Vision/TOCropViewController aux
/// modules 7-9) : Android pilote l'export via ExoPlayer (aperçu) + un pipeline de transformation
/// custom (`Utils/media/VideoTransformer`, confirmé MORT/non branché prod par
/// `TIINVER_IOS_PORT_ANALYSIS.md` §2.2 — cluster "v2" jamais atteint car non déclaré dans le
/// manifest Android, message de commit `c5c2c3d` "WIP: passthrough trimmer... non branché prod").
/// Remplacé par `AVAssetExportSession`+`AVMutableComposition` (trim via `timeRange`) +
/// `AVMutableVideoComposition`/`AVMutableVideoCompositionLayerInstruction` (rotation/recadrage,
/// `setTransform(_:at:)`) — API native Apple de haut niveau, pas une librairie tierce à vérifier
/// comme TOCropViewController/Vision, mais À VÉRIFIER contre la documentation réelle au moment
/// d'écrire l'export lui-même (pas encore fait ici — seul l'état est porté cette passe).
/// `Utils/media/VideoFrameExtractorCodecAsync.java` (355 lignes, extraction de vignettes) a un
/// équivalent natif direct `AVAssetImageGenerator` — non porté ligne à ligne pour la même raison.
struct VideoTrimState: Equatable {
    /// Port du cycle `currentRotation` — 0 → 90 → 180 → 270 → 0, un cran par appui sur le bouton
    /// pivot (`btnPivot`).
    private(set) var rotationDegrees: Int = 0
    private(set) var flippedHorizontally = false

    enum CropRatio: Equatable {
        case free
        case ratio(w: Float, h: Float)
    }
    var cropRatio: CropRatio = .free

    /// Port du handler de `btnPivot` — cycle 0→90→180→270→0.
    mutating func cyclePivot() {
        rotationDegrees = (rotationDegrees + 90) % 360
    }

    /// Port du handler de `btnFlip` (`setFlippedHorizontally`).
    mutating func toggleFlip() {
        flippedHorizontally.toggle()
    }

    /// Port de `applyRatio` — libellé affiché (`tvRatioLabel`), les préréglages réels
    /// (`btnRatio169`/`btnRatio916`/`btnRatio11`/`btnRatio43`/`btnRatioFree`) sont de la
    /// construction de vue Android, non reprise ici (boutons SwiftUI standard à l'appelant).
    static let presets: [(label: String, ratio: CropRatio)] = [
        ("16:9", .ratio(w: 16, h: 9)),
        ("9:16", .ratio(w: 9, h: 16)),
        ("1:1", .ratio(w: 1, h: 1)),
        ("4:3", .ratio(w: 4, h: 3)),
    ]
}
