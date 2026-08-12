import Foundation

/// Port de `model/PlaylistEntry.java` — trivial, tous les champs `let` comme l'original (Android
/// les déclare `final`).
struct PlaylistEntry {
    let id: String
    let label: String
    let track: Int
    let startFrame: Int
    let endFrame: Int
    let durationFrames: Int
    /// ARGB packé.
    let color: UInt32
}
