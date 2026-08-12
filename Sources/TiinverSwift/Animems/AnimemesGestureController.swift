import CoreGraphics
import Foundation

/// Port de la logique de geste tactile de `engine/android/memes/MemesView2.java` (lu en entier :
/// `GestureListener`/`ScaleListener`/`onTouchEvent`/`touchDown`/`touchMove`/`touchUp`/
/// `translation`/`rotate`/`scale`/`safePostScale`/`isPointInsideObject`/`bringLayerToFront`/
/// `handleMaskEditTouch`/`maskApplyDrag`/`cummulateMaskTransform`/`cummuleMatrix`) — état et
/// mathématiques du déplacement/redimensionnement/rotation d'un calque, et du mode d'édition de
/// masque, INDÉPENDAMMENT de l'API de geste concrète qui pilote ces méthodes.
///
/// **Ce fichier porte la LOGIQUE (vérifiable, testable indépendamment de l'UI), pas le CÂBLAGE
/// SwiftUI des gestes lui-même** (`DragGesture`/`MagnificationGesture`/`RotationGesture`, dans
/// une future `AnimemesCanvasView` pas encore écrite) — même séparation que `LayerRenderer`
/// (logique de rendu) vs la future vue qui l'invoque. Raison : la logique de transformation de
/// matrice (`translation`/`rotate`/`scale`, `isPointInsideObject` par inversion de matrice) est
/// un port direct fidèle, vérifiable ligne à ligne contre l'original — le câblage des gestes
/// SwiftUI multi-touch simultanés (glisser+pincer+pivoter en même temps sur un `View`) ne peut
/// PAS être vérifié sans simulateur/device réel, et sa composition exacte (`SimultaneousGesture`)
/// est notoirement délicate à obtenir juste du premier coup — séparer les deux évite qu'une
/// incertitude d'assemblage de gestes ne contamine la logique mathématique déjà fiable.
///
/// **Différence de sémantique Android→SwiftUI, assumée et documentée AVANT le câblage réel** :
/// `ScaleGestureDetector.getScaleFactor()`/la rotation d'Android sont déjà INCRÉMENTAUX
/// (delta depuis le dernier événement) ; `MagnificationGesture`/`RotationGesture` de SwiftUI
/// rapportent une valeur CUMULATIVE depuis le début du geste. Les méthodes ci-dessous attendent
/// des valeurs INCRÉMENTALES (fidèles à l'API Android d'origine, pas reformulées) — la future vue
/// SwiftUI qui les appelle devra donc calculer le delta par rapport à la dernière valeur connue
/// avant d'appeler `applyScale`/`applyRotation`, pas leur passer la valeur cumulative brute.
///
/// **Piège d'ordre de composition identifié et corrigé AVANT tout build** : Android compose
/// `matrix.postTranslate`/`postRotate`/`postScale` — le "post" signifie que la nouvelle opération
/// s'applique APRÈS la matrice existante, dans le repère de DESTINATION (écran). `CGAffineTransform
/// .translatedBy`/`.rotated(by:)`/`.scaledBy` de Core Graphics ont la sémantique INVERSE : ils
/// appliquent la nouvelle opération AVANT `self` (équivalent de `preTranslate`/`preRotate`/
/// `preScale` Android, PAS `post*`). Un appel direct `tfm.cgAffineTransform.translatedBy(...)` à
/// la place de `postTranslate` aurait donc traduit le geste dans le mauvais repère dès qu'un
/// calque est pivoté/mis à l'échelle — corrigé en construisant explicitement la composante "post"
/// comme une transformation autonome, puis `self.concatenating(composantePost)` (`concatenating`
/// signifie "applique `self` en premier, puis l'argument" — l'ordre exact nécessaire pour un
/// équivalent fidèle de `post*`).
final class AnimemesGestureController {
    private static let minScale: CGFloat = 0.3
    private static let maxScale: CGFloat = 15.0
    /// Port de `ScaleListener.onScale` — clamp du facteur incrémental par événement (évite les
    /// sauts de zoom brusques d'un détecteur bruité), PAS le clamp global `MIN_SCALE`/`MAX_SCALE`
    /// (appliqué séparément dans `scale(...)`/`safePostScale`).
    private static let perEventScaleClampRange: ClosedRange<CGFloat> = 0.95...1.05

    private(set) var objectInAction: Int = -1
    private var oldPoint: CGPoint = .zero
    private var oldAngleDegrees: CGFloat = 0
    private var midPoint: CGPoint = .zero

    // MARK: - Sélection / hit-test

    /// Port de `isPointInsideObject` — inverse la matrice de la DERNIÈRE `Transform` du calque et
    /// teste si le point (repère écran) tombe dans `obj.bound` (repère local du calque).
    func isPoint(_ point: CGPoint, insideObjectAt index: Int, composer: AnimationComposer) -> Bool {
        guard index >= 0, index < composer.layers.count else { return false }
        let obj = composer.layers[index]
        guard let bound = obj.bound, let tfm = obj.transforms.last else { return false }
        // `CGAffineTransform.inverted()` N'EST PAS optionnelle (contrairement à
        // `android.graphics.Matrix.invert(Matrix)`, qui retourne un `boolean` de succès) : sur une
        // transformation non inversible (déterminant nul — cas limite non rencontré en pratique,
        // les matrices de ce moteur partent toujours de l'identité via échelle/rotation/
        // translation), Core Graphics renvoie la transformation D'ORIGINE inchangée plutôt qu'un
        // signal d'échec. Différence de comportement documentée, pas une garde silencieusement
        // perdue lors du portage.
        let inverse = tfm.cgAffineTransform.inverted()
        let local = point.applying(inverse)
        return bound.contains(local)
    }

    /// Port de `bringLayerToFront` — déplace le calque en fin de tableau (dernier = dessiné
    /// au-dessus dans `startDraw`/`LayerRenderer`, ordre de dessin = ordre du tableau).
    func bringLayerToFront(_ index: Int, composer: AnimationComposer) {
        guard index >= 0, index < composer.layers.count else { return }
        var layers = composer.layers
        let obj = layers.remove(at: index)
        layers.append(obj)
        composer.setLayers(layers)
    }

    // MARK: - Toucher simple (déplacement)

    /// Port de `touchDown(MotionEvent, int)` — teste si le point touché tombe dans le calque `i`
    /// (repère local, matrice inversée) ; si oui, arme `objectInAction`/`obj.moveObject` pour la
    /// suite du geste.
    func touchDown(at point: CGPoint, objectIndex i: Int, composer: AnimationComposer) {
        oldPoint = point
        guard i >= 0, i < composer.layers.count else { return }
        let obj = composer.layers[i]
        guard let tfm = obj.transforms.last else { return }
        let localPoint = point.applying(tfm.cgAffineTransform.inverted())
        if let bound = obj.bound, bound.contains(localPoint) {
            obj.moveObject = true
            objectInAction = i
        }
    }

    /// Port de `touchMove` (branche translation à un doigt) — delta depuis le dernier point connu.
    func touchMoveTranslate(to point: CGPoint, objectIndex i: Int, composer: AnimationComposer) {
        guard i >= 0, i < composer.layers.count, composer.layers[i].moveObject, objectInAction == i else { return }
        translation(dx: point.x - oldPoint.x, dy: point.y - oldPoint.y, objectIndex: i, composer: composer)
        oldPoint = point
    }

    /// Port de `translation` — translate la matrice de la dernière `Transform` et met à jour
    /// `obj.bound` (mappé par la matrice, comme l'original — PAS recalculé depuis zéro).
    func translation(dx: CGFloat, dy: CGFloat, objectIndex i: Int, composer: AnimationComposer) {
        guard i >= 0, i < composer.layers.count else { return }
        let obj = composer.layers[i]
        guard var tfm = obj.transforms.last else { return }
        // Port de `postTranslate` — voir note de composition en tête de fichier.
        let translated = tfm.cgAffineTransform.concatenating(CGAffineTransform(translationX: dx, y: dy))
        tfm.matrixValues = Transform.matrixValues(from: translated)
        obj.transforms[obj.transforms.count - 1] = tfm
        if let bound = obj.bound {
            obj.bound = bound.applying(translated)
        }
    }

    /// Port de `touchUp` — fin de geste : réinitialise l'état, applique le lissage Chaikin si le
    /// calque a accumulé des `Transform` en mode capture automatique (port de
    /// `ENABLE_TRANSFORM_SMOOTH`, `true` en dur côté Android — reproduit tel quel).
    func touchUp(objectIndex i: Int, composer: AnimationComposer, engine: AnimationEngine) {
        guard i >= 0, i < composer.layers.count else { objectInAction = -1; return }
        composer.layers[i].moveObject = false
        engine.smoothObjectTransforms(composer.layers[i])
    }

    // MARK: - Rotation / échelle (geste à deux doigts)

    /// Port de `touchPointerDown` (amorce rotation/pinch) — enregistre l'angle/point milieu de
    /// référence pour les deltas incrémentaux suivants.
    func pointerDown(point0: CGPoint, point1: CGPoint) {
        oldAngleDegrees = Self.degrees(point0, point1)
        midPoint = CGPoint(x: (point0.x + point1.x) / 2, y: (point0.y + point1.y) / 2)
    }

    /// Port de `rotate` — tourne la matrice AUTOUR de `midPoint` (enregistré à `pointerDown`), en
    /// écrasant `obj.bound` par la matrice mise à jour (mappée, pas recalculée).
    func rotate(to newAngleDegrees: CGFloat, objectIndex i: Int, composer: AnimationComposer) {
        guard i >= 0, i < composer.layers.count else { return }
        let obj = composer.layers[i]
        guard var tfm = obj.transforms.last else { return }
        let deltaDegrees = oldAngleDegrees - newAngleDegrees
        let radians = deltaDegrees * .pi / 180
        // Port de `postRotate(rotate, midPoint.x, midPoint.y)` — rotation autour de `midPoint`,
        // composée APRÈS `tfm` (voir note de composition en tête de fichier) : la composante
        // "post" (translation vers l'origine, rotation, translation retour) est construite comme
        // une transformation autonome via `concatenating` (self=premier terme appliqué), PUIS
        // concaténée après `tfm`.
        let pivotRotation = CGAffineTransform(translationX: -midPoint.x, y: -midPoint.y)
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: midPoint.x, y: midPoint.y))
        let rotated = tfm.cgAffineTransform.concatenating(pivotRotation)
        tfm.matrixValues = Transform.matrixValues(from: rotated)
        obj.transforms[obj.transforms.count - 1] = tfm
        oldAngleDegrees = newAngleDegrees
        if let bound = obj.bound {
            obj.bound = bound.applying(rotated)
        }
    }

    /// Port de `scale`+`safePostScale` — échelle autour de `focus`, avec DOUBLE garde-fou fidèle
    /// à l'original : (1) `scale()` rejette le geste ENTIER si la nouvelle échelle dépasserait
    /// `[MIN_SCALE, MAX_SCALE]` (`return` silencieux, la matrice n'est PAS modifiée du tout) ;
    /// (2) `safePostScale` (appelé seulement si (1) passe) reclame le FACTEUR pour ne jamais
    /// dépasser exactement la borne plutôt que de la dépasser puis rejeter au prochain appel —
    /// les deux gardes coexistent dans l'original, reproduites toutes les deux, pas fusionnées.
    func scale(factor: CGFloat, focus: CGPoint, objectIndex i: Int, composer: AnimationComposer) {
        guard i >= 0, i < composer.layers.count else { return }
        let obj = composer.layers[i]
        guard var tfm = obj.transforms.last else { return }
        let values = tfm.matrixValues
        guard values.count >= 6 else { return }
        let newScaleX = CGFloat(values[0]) * factor
        let newScaleY = CGFloat(values[4]) * factor
        guard newScaleX >= Self.minScale, newScaleX <= Self.maxScale,
              newScaleY >= Self.minScale, newScaleY <= Self.maxScale else { return }

        let currentScale = (CGFloat(values[0]) + CGFloat(values[4])) / 2
        var safeFactor = factor
        let newScale = currentScale * factor
        if newScale < Self.minScale { safeFactor = Self.minScale / currentScale }
        else if newScale > Self.maxScale { safeFactor = Self.maxScale / currentScale }

        // Port de `safePostScale`/`matrix.postScale(sx, sy, px, py)` — même construction "post"
        // que `rotate` ci-dessus (composante autonome, puis concaténée après `tfm`).
        let pivotScale = CGAffineTransform(translationX: -focus.x, y: -focus.y)
            .concatenating(CGAffineTransform(scaleX: safeFactor, y: safeFactor))
            .concatenating(CGAffineTransform(translationX: focus.x, y: focus.y))
        let scaled = tfm.cgAffineTransform.concatenating(pivotScale)
        tfm.matrixValues = Transform.matrixValues(from: scaled)
        obj.transforms[obj.transforms.count - 1] = tfm

        guard let bmp = obj.currentBitmap else { return }
        let localBound = CGRect(x: obj.offsetX, y: obj.offsetY, width: CGFloat(bmp.width), height: CGFloat(bmp.height))
        obj.bound = localBound.applying(scaled)
    }

    /// Clamp le facteur d'un ÉVÉNEMENT de pincement individuel (port de `ScaleListener.onScale`,
    /// `Math.max(0.95f, Math.min(scaleFactor, 1.05f))`) — à appliquer par l'appelant AVANT de
    /// transmettre le facteur à `scale(factor:focus:objectIndex:composer:)`.
    static func clampPerEventScaleFactor(_ factor: CGFloat) -> CGFloat {
        max(perEventScaleClampRange.lowerBound, min(factor, perEventScaleClampRange.upperBound))
    }

    static func degrees(_ p0: CGPoint, _ p1: CGPoint) -> CGFloat {
        atan2(p0.x - p1.x, p0.y - p1.y) * 180 / .pi
    }
}
