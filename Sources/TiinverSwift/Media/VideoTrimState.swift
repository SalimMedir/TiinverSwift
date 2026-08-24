import Foundation

/// Port de l'état (rotation/flip/ratio) de `view/trimmer/VideoTrimmerView.java` (module 10) — la
/// géométrie de la fenêtre de trim elle-même est portée séparément dans `ProTimelineViewModel.swift`
/// (port direct de `editor/view/ProTimelineView.java`, 763 lignes, lu en entier).
///
/// **Décision d'architecture pour l'export** (comme MetalPetal/Vision/TOCropViewController aux
/// modules 7-9) : Android pilote l'export via ExoPlayer (aperçu) + un pipeline de transformation
/// custom `Utils/media/VideoTransformer`.
///
/// **Correction du 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-032 GALERIE-01, Phase B P0-6)** —
/// le commentaire précédent affirmait ce pipeline "confirmé MORT/non branché prod" (citant
/// `TIINVER_IOS_PORT_ANALYSIS.md §2.2`). Cette affirmation était FAUSSE et a été invalidée par
/// relecture directe et fraîche de `VideoTrimmerView.java` (module 10) avant d'écrire le correctif
/// P0-6 : le fichier contient un `import com.animems.engine.Utils.media.VideoTransformer` réel et
/// un appel réel `VideoTransformer.process(params, callback)` à la ligne 700, à l'intérieur de
/// `startTrimWithCrop()` — méthode active, appelée depuis le bouton de validation de l'écran de
/// trim réellement monté en production. Une seconde méthode, `startTrimWithCrop2()`
/// (`VideoTrimmerView.java:807-854`), existe en parallèle comme repli RAPIDE sans transformation
/// (trim temporel seul, pas de recadrage/rotation) — architecture à deux chemins, pas un vestige
/// mort. `MediaTrimView.swift` porte maintenant les deux chemins à l'identique : export rapide
/// (`AVAssetExportPresetPassthrough`) quand aucune transformation n'est active, export
/// ré-encodé (`AVMutableComposition`+`AVMutableVideoComposition`, `.presetHighestQuality`) sinon.
/// `Utils/media/VideoFrameExtractorCodecAsync.java` (355 lignes, extraction de vignettes) reste à
/// part, avec un équivalent natif direct `AVAssetImageGenerator` — non porté ligne à ligne, ceci
/// n'est pas remis en cause par la correction ci-dessus (fichier distinct, rôle distinct).
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
        // **Ajouté (V4-F-062, 2026-08-24)** — `menu_crop_ratio.xml`/`showRatioMenu`
        // (`VideoTrimmerView.java:265-288`) propose 6 ratios (Libre/16:9/9:16/1:1/4:3/3:4) ;
        // "3:4" manquait, seul preset absent des 5 déjà portés (Libre géré à l'appelant).
        ("3:4", .ratio(w: 3, h: 4)),
    ]
}
