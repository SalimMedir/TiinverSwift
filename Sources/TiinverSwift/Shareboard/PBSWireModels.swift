import CoreGraphics
import Foundation

/// Port de `com.animems.engine.model.pbs.MotionEventData` (110 lignes, lu en entier) — UN
/// événement tactile brut (down/move/up), diffusé en temps réel pendant le dessin collaboratif
/// (Shareboard, module 13) ou accumulé localement pour un envoi différé (Message Graphic, module
/// 14). Les valeurs `actionMasked` reproduisent EXACTEMENT les constantes `android.view.MotionEvent`
/// (API publique Android bien connue, pas devinée) : `ACTION_DOWN=0`, `ACTION_UP=1`,
/// `ACTION_MOVE=2`, `ACTION_POINTER_DOWN=5`, `ACTION_POINTER_UP=6` — nécessaire car ces entiers
/// voyagent SUR LE FIL (`CompactTouchEvent.a`) et doivent rester compréhensibles par tout pair
/// Android encore en circulation.
struct PBSTouchEvent: Equatable {
    var messageId: String = ""
    var actionMasked: Int = PBSTouchAction.down.rawValue
    var pointerCount: Int = 1
    var x: [CGFloat] = [0, 0]
    var y: [CGFloat] = [0, 0]
    var paintSize: Int = 10
    var paintColor: Int = 0
    var type: String?
    var action: String?
    var remoteScreenW: Int = 0
    var remoteScreenH: Int = 0
}

/// Constantes `android.view.MotionEvent` réellement utilisées par `PBSView.java`
/// (`executeTouchEventOutput`/`drawPathProcessOuput` — switch exhaustif vérifié : seuls ces 5 cas
/// sont traités, `ACTION_CANCEL`/`ACTION_OUTSIDE` ignorés côté Android aussi).
enum PBSTouchAction: Int {
    case down = 0
    case up = 1
    case move = 2
    case pointerDown = 5
    case pointerUp = 6
}

/// Port de `com.animems.engine.model.pbs.EditorData` (599 lignes) — représente À LA FOIS un objet
/// graphique placé (image/sticker/bulle de texte) ET un trait de dessin libre (`page.paintList`),
/// exactement comme l'original réutilise LA MÊME classe Java pour les deux rôles (`PBSView.
/// initPathDraw`/`addData` opèrent toutes deux sur `EditorData`) — préservé ici plutôt que scindé
/// en deux types Swift séparés, pour rester fidèle au modèle de page Android (`Page.page`/
/// `Page.paintList`, voir `PBSPage.swift`) et ne pas réinventer une architecture non vérifiée.
///
/// **Champs de rendu/animation avancés d'Android NON repris** (`cachedText`/`cachedTextRect`/
/// `seekMatrix`/`initialSkewX`/`initialSkewY`/`lineCount`/`baseLine`/`diffX`/`diffY`/`midPointX`/
/// `midPointY`/`zoomWidth`/`zoomHeight`/`position`/`scale`/`degre`) — vérifiés un par un : AUCUN
/// n'est lu par `GraphicMessageCodec` (ne voyage jamais sur le fil) ni par la boucle de rendu
/// `onDraw`/`startDraw` de `PBSView` pour le chemin normal (dessin/bulle texte/image/sticker) ;
/// ce sont des scratch-fields internes à la gestion tactile bas niveau d'Android (`touchMove`/
/// `getMidPoint`/`getDegre`), remplacés ici par les gestes natifs SwiftUI
/// (`MagnificationGesture`/`RotationGesture`/`DragGesture`, voir `PBSCanvasView.swift`) qui gèrent
/// cet état en interne — décision documentée, pas un oubli.
///
/// **Piège de nommage Android préservé tel quel** : `textWidth`/`textHeight` servent de
/// **position X/Y** pour une bulle de texte (`PBSView.writeText` : `x = getTextWidth(); y =
/// getTextHeight()`), PAS de dimensions — confirmé en lisant `writeText`/`PBSCompound.onClick`
/// (`data2.setTextHeight(et.getY()); data2.setTextWidth(et.getX())`). Gardé sous ces noms pour que
/// `GraphicMessageCodec` (qui sérialise `tw`/`th` sur le fil) reste un miroir direct de
/// `CompactEditorData`, pas "corrigé" en `posX`/`posY` qui casserait la lisibilité du mapping fil.
struct PBSEditorData: Identifiable, Equatable {
    var id: String = UUID().uuidString // messageId
    var type: String?
    var action: String?
    var username: String?
    var textColor: Int = 0
    var containerColor: Int = 0
    var text: String?
    var textWidth: CGFloat = 0 // position X d'une bulle de texte, voir avertissement ci-dessus
    var textHeight: CGFloat = 0 // position Y d'une bulle de texte
    var left: CGFloat = 0
    var top: CGFloat = 0
    var posX: CGFloat = 0
    var posY: CGFloat = 0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var bitmapWidth: Int = 0
    var bitmapHeight: Int = 0
    var bitmapData: Data?
    /// Port de `EditorData.path`/`paint` — uniquement peuplé pour un trait de dessin libre
    /// (`type == "drawPath"`), coordonnées locales à la vue au moment du tracé.
    var strokePoints: [CGPoint] = []
    var paintColor: Int = 0
    var paintWidth: CGFloat = 4
    /// Port de `EditorData.matrix` — transformation appliquée par le geste utilisateur
    /// (déplacer/pincer/pivoter un objet placé), `CGAffineTransform` remplaçant
    /// `android.graphics.Matrix` (mêmes 6 degrés de liberté utiles ici, pas de perspective).
    var transform: CGAffineTransform = .identity
    var bound: CGRect = .zero
}

/// Port de `com.tiinver.messagerie.webrtc` / `PBSCompound.PBSStreamActionListener` — une page du
/// Shareboard (`com.animems.engine.android.memes.Page`, 27 lignes) : objets placés + traits de
/// dessin libre, décomposés en deux listes comme l'original (`page`/`paintList`).
struct PBSPage: Equatable {
    var objects: [PBSEditorData] = []
    var strokes: [PBSEditorData] = []
}
