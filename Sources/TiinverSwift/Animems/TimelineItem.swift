import Foundation

/// Port de `model/TimelineItem.java` — un bloc dans la piste de la timeline (représentation
/// UI-facing d'un calque, distincte d'`AnimationObjectData` qui porte les données réelles).
/// `struct` (comme `Keyframe`) : la méthode `copy()` Android n'a pas d'équivalent nécessaire,
/// la copie-à-l'assignation étant déjà le comportement par défaut d'un `struct` Swift.
struct TimelineItem {
    let id: String
    var label: String = "Item"
    /// ARGB packé — même convention que partout ailleurs dans ce module.
    var color: UInt32 = 0xFF4C_AF50
    var track: Int = 0
    var startFrame: Int = 0
    /// `-1` = jusqu'à la fin.
    var endFrame: Int = -1
    var minDurationFrames: Int = 1
    var locked: Bool = false
    var visibility: Bool = false
    var recomposeGroupId: String?

    init(id: String) { self.id = id }

    func visibleEnd(totalFrames: Int) -> Int {
        endFrame >= 0 ? endFrame : max(0, totalFrames - 1)
    }

    func durationVisible(totalFrames: Int) -> Int {
        max(1, visibleEnd(totalFrames: totalFrames) - startFrame + 1)
    }
}
