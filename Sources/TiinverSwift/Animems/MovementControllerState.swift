import Foundation

/// Port de l'état de `android/views/MovementControllerHandlerView.java` — panneau de
/// bascules (zoom/rotation/skew/top/bottom/left/right/point d'ancrage) + un slider d'angle,
/// pilotant un mode de transformation PRÉCIS par curseur (alternative au geste tactile direct).
///
/// **Découverte importante (dernière passe module 8)** : en lisant `MemesView2.setZoom` et les
/// usages des champs `zoom`/`rotation`/`skew`/`top`/`bottom`/`left`/`right`/`anchorPoint` (grep sur
/// tout le fichier), ces bascules NE GATENT PAS le geste tactile libre (drag/pincer/tourner) déjà
/// porté dans `AnimemesGestureController.swift` (`translation`/`rotate`/`scale`, lignes ~1780-2000
/// de `MemesView2.java` d'après la lecture précédente) — c'est un système SÉPARÉ et ADDITIF :
/// quand `anchorPoint == true`, le slider d'angle du panneau pilote `applySeekBarTransformOnAnchor`
/// (`MemesView2.java` ligne ~1781) et `anchorTouchExecute` (ligne ~1602), qui appliquent un
/// déplacement/rotation/skew/zoom incrémental au calque sélectionné, contraint par les bascules
/// actives (ex. `right`/`left` bornent le déplacement horizontal à `dx = ±delta * moveFactor`,
/// ligne ~1792/1844). Ni `applySeekBarTransformOnAnchor` ni `anchorTouchExecute` n'ont été lus —
/// seul l'état des bascules (ce fichier) est porté. Voir section "Points à vérifier en priorité"
/// du journal module 8 : ce mode d'édition par curseur reste ENTIÈREMENT non porté (pas seulement
/// la vue SwiftUI, la logique de transformation elle-même).
struct MovementControllerState: Equatable {
    var zoom = false
    var rotation = false
    var skew = false
    var top = false
    var bottom = false
    var left = false
    var right = false
    var anchorPoint = false

    /// Port du slider d'angle — `finalProgress = progress + 90` (le `SeekBar` Android part de 0,
    /// décalé de 90° pour centrer la plage utile autour de l'angle neutre).
    static func angleDegrees(fromSeekProgress progress: Int) -> Int {
        progress + 90
    }
}

/// Port de `MovementControllerHandlerView.ZOOM/ROTATION/SKEW/TOP/BOTTOM/LEFT/RIGHT/ANCHOR_POINT`
/// et de `MovementControllerHandlerListener` (`onAction`/`onProgress`/`onStart`/`onStop`).
enum MovementControllerField {
    case zoom, rotation, skew, top, bottom, left, right, anchorPoint
}

protocol MovementControllerHandlerListener: AnyObject {
    func movementController(didToggle field: MovementControllerField, isChecked: Bool)
    func movementController(didChangeProgress progress: Int)
    func movementControllerDidStartTracking()
    func movementControllerDidStopTracking()
}
