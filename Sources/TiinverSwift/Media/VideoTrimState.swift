import CoreGraphics
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
/// trim réellement monté en production. **`startTrimWithCrop2()` citée ici comme "repli rapide en
/// parallèle" — confirmée code MORT par le correctif V3-F-124 suivant (grep exhaustif, zéro
/// appelant)** : `next.setOnClickListener` appelle TOUJOURS `startTrimWithCrop()`, jamais son
/// homonyme. Le VRAI fast path Android n'est PAS `startTrimWithCrop2()` mais interne à
/// `VideoTransformer.process()` lui-même — voir `MediaTrimView.swift` (V5-F-037, 2026-08-25) pour
/// le détail complet et le choix assumé de ne pas le reproduire côté iOS.
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
    var cropRatio: CropRatio = .free {
        didSet {
            // Port de `applyRatio`→`setAspectRatio`→`resetCropRect` (`CropOverlayView.java:243-266`)
            // — Android recentre TOUJOURS le cadre de recadrage au changement de ratio, avant toute
            // interaction utilisateur. **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md
            // V5-F-038, Phase B P2)**.
            cropCenter = CGPoint(x: 0.5, y: 0.5)
        }
    }

    /// Centre du rectangle de recadrage, normalisé `[0,1]×[0,1]` RELATIF à `videoRect` (le
    /// rectangle vidéo réellement affiché, hors bandes noires — 0.5,0.5 = centré, valeur par
    /// défaut/réinitialisée à chaque changement de ratio). Port de `CropOverlayView.cropRect`
    /// (stocké en coordonnées de vue absolues côté Android, ici normalisé pour rester indépendant
    /// de la taille d'aperçu SwiftUI — même principe que `getCropNormRelativeToVideo()`, déjà
    /// normalisé côté Android pour l'encodage final). **Ajouté le 2026-08-26
    /// (MIGRATION_PARITY_AUDIT_V5.md V5-F-038, Phase B P2)** — absent avant ce correctif, le
    /// recadrage vidéo n'avait aucun état de position, toujours centré à 100% sans possibilité de
    /// déplacement (voir `MediaTrimView.composeTransform` pour le calcul de rendu correspondant).
    var cropCenter = CGPoint(x: 0.5, y: 0.5)

    /// Port de `resetCropRect` — taille du rectangle de recadrage, normalisée `[0,1]×[0,1]`
    /// relative à `videoRect`, pour un ratio cible et un ratio vidéo (`videoAspect = largeur/
    /// hauteur` de `videoRect`) donnés. Marge par défaut de 90% (`maxW/maxH = vw/vh * 0.90`),
    /// PAS 100% — écart trouvé par cet audit (V5-F-038) : le recadrage précédent utilisait toujours
    /// 100% de la dimension contraignante.
    static func cropNormSize(forTargetRatio targetRatio: CGFloat, videoAspect: CGFloat) -> CGSize {
        guard targetRatio > 0, videoAspect > 0 else { return CGSize(width: 0.9, height: 0.9) }
        let maxW: CGFloat = 0.9, maxH: CGFloat = 0.9
        // Port fidèle de la comparaison Android (`maxW/ratioW*ratioH <= maxH`) mais en unités
        // normalisées : la largeur normalisée doit être convertie en unités "hauteur" via
        // `videoAspect` pour rester comparable à `maxH` (les deux fractions sont relatives à des
        // dimensions physiquement différentes de `videoRect`).
        if (maxW * videoAspect) / targetRatio <= maxH {
            let cw = maxW
            let ch = (cw * videoAspect) / targetRatio
            return CGSize(width: cw, height: ch)
        } else {
            let ch = maxH
            let cw = (ch / videoAspect) * targetRatio
            return CGSize(width: cw, height: ch)
        }
    }

    /// Port du handler de `btnPivot` — cycle 0→90→180→270→0.
    mutating func cyclePivot() {
        rotationDegrees = (rotationDegrees + 90) % 360
    }

    /// Port du handler de `btnFlip` (`setFlippedHorizontally`).
    mutating func toggleFlip() {
        flippedHorizontally.toggle()
    }

    /// Port de `moveCropRect` — déplace `cropCenter` de `(dx,dy)` (fractions normalisées de
    /// `videoRect`, mêmes unités que `cropCenter`/`cropNormSize`), clampé pour que le rectangle de
    /// recadrage reste ENTIÈREMENT dans `videoRect` (jamais le centre lui-même, la MARGE
    /// disponible dépend de la taille du rectangle — un rectangle plus grand a moins de marge de
    /// déplacement, exactement le clamp `moveCropRect` d'Android sur `cropRect` vs `videoRect`).
    mutating func moveCropCenter(dx: CGFloat, dy: CGFloat, cropSize: CGSize) {
        let halfW = min(0.5, cropSize.width / 2), halfH = min(0.5, cropSize.height / 2)
        let newX = min(max(cropCenter.x + dx, halfW), 1 - halfW)
        let newY = min(max(cropCenter.y + dy, halfH), 1 - halfH)
        cropCenter = CGPoint(x: newX, y: newY)
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
