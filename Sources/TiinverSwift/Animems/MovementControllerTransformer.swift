import CoreGraphics
import Foundation

/// Port de `MemesView2.applySeekBarTransform`/`applySeekBarTransformOnAnchor`/
/// `controllerMovement` (`android/memes/MemesView2.java:1776-1864`, lu en entier) — logique de
/// transformation PRÉCISE par curseur pilotée par le panneau "Contrôle" (bascules zoom/rotation/
/// skew/haut/bas/gauche/droite/point d'ancrage + un slider d'angle), alternative au geste
/// tactile libre déjà porté dans `AnimemesGestureController`.
///
/// **Corrigé (2026-08-28, V6-F-002)** — panneau et logique de transformation entièrement absents
/// jusqu'ici (seul `MovementControllerState`, un pur conteneur de bascules, existait, jamais
/// instancié ni câblé à aucune UI ni logique).
///
/// **Portée volontairement réduite par rapport à Android** : Android permet AUSSI de déplacer le
/// point d'ancrage par glisser DIRECT sur le canevas quand le mode "point d'ancrage" est actif
/// (`anchorTouchExecute`/`touchDownAnchor`/`touchMoveOnlyAnchorPoint`, `MemesView2.java:1661-
/// 1672` — remplace ENTIÈREMENT la gestion tactile normale du canevas pendant ce mode). Non porté
/// ici pour éviter de perturber le routage tactile existant du canevas (`AnimemesGestureController`/
/// `combinedGesture`) pour une fonctionnalité secondaire. Le déplacement du point d'ancrage reste
/// possible via ce MÊME panneau (bascules haut/bas/gauche/droite + slider,
/// `applySeekBarTransformOnAnchor`, ligne 1789-1796), qui couvre le flux complet (position du
/// point d'ancrage PUIS transformation du calque autour de lui) sans toucher au canevas.
final class MovementControllerTransformer {
    private static let minScale: CGFloat = 0.3
    private static let maxScale: CGFloat = 15.0
    private static let maxSkew: Float = 0.8
    /// Port de `moveFactor = 5f` (`applySeekBarTransform`/`applySeekBarTransformOnAnchor`).
    private static let moveFactor: CGFloat = 5

    private var oldProgress: Int = 90
    /// Port de `anchorCenterX`/`anchorCenterY` — `nil` = pas de point d'ancrage positionné
    /// (équivalent du sentinel `0f`/`0f` côté Android, plus idiomatique en Swift qu'un couple de
    /// `Float` testés individuellement).
    private(set) var anchor: CGPoint?

    /// Port de `onStart` → `initControllerMovement()` (no-op côté Android) — mémorise le progrès
    /// de départ du slider pour que le premier `progressChanged` calcule un delta correct.
    func beginTracking(atProgress progress: Int) {
        oldProgress = progress
    }

    /// Port de `controllerMovement(progress)` — bascule entre le déplacement du point d'ancrage
    /// et la transformation du calque sélectionné selon l'état de la bascule "point d'ancrage".
    /// `selectedLayer` doit pointer vers la DERNIÈRE `Transform` du calque actuellement
    /// sélectionné (port de `objectInAction`, ici simplement `state.selectedId`).
    func progressChanged(_ progress: Int, state: MovementControllerState, selectedLayer: AnimationObjectData?) {
        let delta = CGFloat(progress - oldProgress)
        defer { oldProgress = progress }
        guard delta != 0 else { return }

        if state.anchorPoint {
            applyAnchorTranslation(delta: delta, state: state)
        } else if let obj = selectedLayer {
            applyLayerTransform(delta: delta, state: state, obj: obj)
        }
    }

    /// Réinitialise le point d'ancrage — port de la fermeture/réouverture du panneau côté Android
    /// (`anchorCenterX`/`Y` ne sont réinitialisés nulle part explicitement côté Android, mais un
    /// point d'ancrage qui survivrait à la fermeture du panneau et réapparaîtrait de façon
    /// invisible à la prochaine ouverture serait une source de confusion pire que la fidélité
    /// stricte ici — appelé à la fermeture du panneau).
    func reset() {
        anchor = nil
        oldProgress = 90
    }

    /// Port de `applySeekBarTransformOnAnchor` — déplace le point d'ancrage (translation
    /// seulement, fidèle à Android qui n'y lit QUE right/left/bottom/top, jamais rotation/skew/
    /// zoom pour l'ancre elle-même).
    private func applyAnchorTranslation(delta: CGFloat, state: MovementControllerState) {
        var dx: CGFloat = 0, dy: CGFloat = 0
        if state.right { dx = delta * Self.moveFactor }
        if state.left { dx = -delta * Self.moveFactor }
        if state.bottom { dy = delta * Self.moveFactor }
        if state.top { dy = -delta * Self.moveFactor }
        guard dx != 0 || dy != 0 else { return }
        let base = anchor ?? .zero
        anchor = CGPoint(x: base.x + dx, y: base.y + dy)
    }

    /// Port de `applySeekBarTransform` — transforme la dernière `Transform` du calque sélectionné
    /// autour du point d'ancrage (s'il est positionné) ou du centre du calque (repli, fidèle à
    /// Android : `if (anchorCenterX != 0 || anchorCenterY != 0) { ... } else { bound.centerX/Y }`).
    private func applyLayerTransform(delta: CGFloat, state: MovementControllerState, obj: AnimationObjectData) {
        guard var tfm = obj.transforms.last else { return }
        let center: CGPoint
        if let anchor { center = anchor } else if let bound = obj.bound { center = CGPoint(x: bound.midX, y: bound.midY) } else { return }

        var dx: CGFloat = 0, dy: CGFloat = 0
        if state.right { dx = delta * Self.moveFactor }
        if state.left { dx = -delta * Self.moveFactor }
        if state.bottom { dy = delta * Self.moveFactor }
        if state.top { dy = -delta * Self.moveFactor }

        // Port de la construction "post" — voir la note de composition en tête
        // d'`AnimemesGestureController.swift` (`concatenating`, pas `.translatedBy`/`.rotated`).
        var result = tfm.cgAffineTransform
        if dx != 0 || dy != 0 {
            result = result.concatenating(CGAffineTransform(translationX: dx, y: dy))
        }
        if state.rotation {
            let radians = delta * 5 * .pi / 180
            result = result.concatenating(Self.pivoted(CGAffineTransform(rotationAngle: radians), around: center))
        }
        if state.skew {
            let deltaSkew = Float(delta) * 0.002
            let values = Transform.matrixValues(from: result)
            // Port de `MSKEW_X`/`MSKEW_Y` — indices 1/3 dans `matrixValues` (voir le mapping
            // documenté en tête de `Transform.swift`).
            let skewXOk = abs(values[1] + deltaSkew) <= Self.maxSkew
            let skewYOk = abs(values[3] + deltaSkew) <= Self.maxSkew
            if skewXOk || skewYOk {
                let kx: CGFloat = skewXOk ? CGFloat(deltaSkew) : 0
                let ky: CGFloat = skewYOk ? CGFloat(deltaSkew) : 0
                // Port de `matrix.postSkew(kx, ky, px, py)` — matrice de cisaillement `[[1,kx,0],
                // [ky,1,0],[0,0,1]]` (même convention de champs qu'Android, voir `Transform.
                // cgAffineTransform`), pivotée comme rotation/échelle ci-dessus/dessous.
                let skewTransform = CGAffineTransform(a: 1, b: ky, c: kx, d: 1, tx: 0, ty: 0)
                result = result.concatenating(Self.pivoted(skewTransform, around: center))
            }
        }
        if state.zoom {
            let scale = 1 + delta * 0.05
            if scale > 0 {
                let values = Transform.matrixValues(from: result)
                let newScaleX = CGFloat(values[0]) * scale
                let newScaleY = CGFloat(values[4]) * scale
                if newScaleX >= Self.minScale, newScaleX <= Self.maxScale,
                    newScaleY >= Self.minScale, newScaleY <= Self.maxScale {
                    result = result.concatenating(Self.pivoted(CGAffineTransform(scaleX: scale, y: scale), around: center))
                }
            }
        }

        tfm.matrixValues = Transform.matrixValues(from: result)
        obj.transforms[obj.transforms.count - 1] = tfm
        // Port du bloc final de `applySeekBarTransform` — `obj.bound` n'est recalculé QUE si le
        // calque a un bitmap courant (`if (bmp == null) { oldProgress = progress; return; }`,
        // AVANT `setBound`) : pour un calque sans bitmap (texte/forme), la matrice est bien
        // mutée ci-dessus (fidèle), seul le rectangle `bound` mis en cache pour le hit-testing
        // n'est pas rafraîchi par CE chemin précis, exactement comme Android.
        if let bmp = obj.currentBitmap {
            let localBound = CGRect(x: CGFloat(obj.offsetX), y: CGFloat(obj.offsetY), width: CGFloat(bmp.width), height: CGFloat(bmp.height))
            obj.bound = localBound.applying(result)
        }
    }

    private static func pivoted(_ transform: CGAffineTransform, around point: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -point.x, y: -point.y)
            .concatenating(transform)
            .concatenating(CGAffineTransform(translationX: point.x, y: point.y))
    }
}
