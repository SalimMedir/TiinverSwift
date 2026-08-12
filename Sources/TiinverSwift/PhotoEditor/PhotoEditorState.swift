import CoreGraphics
import SwiftUI

/// Port de la logique d'état de `android/views/CroperView.java` — orchestration du recadrage
/// (voir `PhotoCropView.swift`, `TOCropViewController`), du mode "freeform" (`FreeformCropView.swift`)
/// et de la suppression d'arrière-plan à deux niveaux (`RemoveBackground.swift`). Construction de
/// vue Android (`LinearLayout`/animations de bouton/overlay de progression) non reprise — pure
/// présentation SwiftUI standard, aucune logique à porter (voir tête de fichier `PhotoCropView.swift`).
@MainActor
final class PhotoEditorState: ObservableObject {
    enum Mode {
        case rect
        case freeform
    }

    @Published var mode: Mode = .rect
    @Published var cropShape: PhotoCropView.Shape = .rectangle
    @Published private(set) var isProcessing = false
    @Published var progressLabel = ""

    /// Port de `handleRemoveBackground` — étage 1 : `VNGeneratePersonSegmentationRequest` (voir
    /// `RemoveBackground.swift` pour la justification du choix vs `SubjectSegmenter` Android) ;
    /// étage 2 (si l'étage 1 ne détecte aucune personne) : repli géométrique
    /// `removeBackgroundAdvanced`, agnostique au sujet — même structure à deux niveaux que
    /// l'original, exécutée hors du thread principal comme `CroperView.executor`.
    func removeBackground(from source: CGImage) async -> CGImage? {
        isProcessing = true
        progressLabel = "Removing background…"
        defer { isProcessing = false }

        let result = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            if let vision = RemoveBackground.removeBackgroundWithVision(source) {
                return vision
            }
            return RemoveBackground.removeBackgroundAdvanced(source)
        }.value

        return result
    }
}
