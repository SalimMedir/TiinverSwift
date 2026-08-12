import Foundation

/// Port de `core/AnimationComposer.java` — conteneur des calques (`layers`) et des calques de
/// peinture libre (`paintLayers`), plus l'état de frame/horodatage courant et la couleur de fond.
/// `final class` (référence) — les calques qu'il contient (`AnimationObjectData`) sont eux-mêmes
/// des références partagées ailleurs (voir `AnimationObjectData.swift`), un `struct` conteneur
/// n'apporterait aucune sécurité de valeur réelle ici.
final class AnimationComposer {
    private(set) var layers: [AnimationObjectData] = []
    private(set) var paintLayers: [AnimationObjectData] = []

    var frameIndex: Int = 0
    var timestampNs: Int64 = 0

    /// Port du commentaire Android : `R.color.color2` (dépendance Android supprimée) remplacé par
    /// la valeur brute `0xFF1A1A1A`... **sauf que la valeur RÉELLE lue dans le fichier source est
    /// `0xFF0062A4`** (bleu), pas `0xFF1A1A1A` mentionné dans le commentaire Java lui-même — le
    /// commentaire Android est incohérent avec son propre code, reproduit ici avec la vraie valeur
    /// numérique du champ, pas celle du commentaire.
    var backgroundColor: UInt32 = 0xFF00_62A4
    var glbBackgroundColor: UInt32 = 0xFF00_62A4

    var hasAudio: Bool = false

    func addLayer(_ data: AnimationObjectData) { layers.append(data) }
    func setLayer(_ index: Int, _ data: AnimationObjectData) { layers[index] = data }
    func setLayers(_ list: [AnimationObjectData]) { layers = list }

    func addPaintLayer(_ data: AnimationObjectData) { paintLayers.append(data) }
    func setPaintLayers(_ list: [AnimationObjectData]) { paintLayers = list }
}
