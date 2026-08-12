import CoreGraphics

/// Port de `model/DrawPathFrameData.java` — une frame d'un trait de peinture libre "en train de
/// se dessiner" (bitmap cropé à sa bounding box + position). `CGImage` n'a pas d'équivalent
/// `recycle()`/`isRecycled()` (ARC gère la libération mémoire) — méthode `recycle()` non portée,
/// pas un oubli : mettre la variable à `nil` suffit en Swift pour libérer la référence.
struct DrawPathFrameData {
    var image: CGImage
    var bounds: CGRect
    var strokeIndex: Int
    var frameIndex: Int
}
