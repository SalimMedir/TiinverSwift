import Combine
import CoreGraphics
import Foundation

/// Port de `com.animems.engine.android.pbs.PBSView` (1411 lignes, lu en entier) — moteur d'état du
/// canevas collaboratif, DÉCOUPLÉ de son rendu (`PBSCanvasView.swift`, SwiftUI) contrairement à
/// l'original qui mélange état + `onDraw`/`onTouch` dans une seule `View` Android. Partagé À
/// L'IDENTIQUE par le Shareboard temps réel (module 13, `PBSSession`) ET Message Graphic (module
/// 14, capture locale puis lecture en bulle de chat) — les DEUX écrans/l'affichage lecture-seule
/// instancient ce moteur, confirmé en lisant `FragmentPbs.java`/`FragmentMessageGraphic.java` : les
/// deux réutilisent LITTÉRALEMENT `PBSCompound`/`PBSView`, pas deux moteurs séparés comme le
/// laissait supposer le découpage "module 13"/"module 14" du plan de portage initial.
///
/// **Portée volontairement réduite par rapport à l'original, documentée point par point** :
/// - Le pinch/rotate/drag d'un objet placé (image/texte/sticker) n'est PAS resynchronisé en direct
///   sur le fil pendant le geste (Android le fait via le MÊME canal `onSendPBSTouchSreamListner`
///   que le dessin, avec un unique `Path`/`inputPath` partagé — implicitement, un SEUL geste
///   distant à la fois peut être rejoué correctement, limitation réelle d'Android reproduite
///   fidèlement pour le dessin ci-dessous). Ici, un objet déplacé est simplement re-publié en
///   entier (`onLocalObjectPlaced`, même canal que le placement initial) une fois le geste terminé
///   — moins fluide à voir chez les autres pendant le geste, mais un geste SwiftUI natif
///   (`DragGesture`/`MagnificationGesture`/`RotationGesture`) plutôt qu'une réplique manuelle de la
///   trigonométrie `getMidPoint`/`getDegre` d'Android.
/// - La suppression d'un objet (glisser vers l'icône poubelle) N'EST PAS synchronisée non plus —
///   vérifié : Android ne le fait pas non plus (`executeDeleterObjeect` n'appelle jamais
///   `pbStreamActionListener`), donc rien à porter ici, comportement identique par construction.
@MainActor
final class PBSCanvasEngine: ObservableObject {
    @Published var pages: [PBSPage] = [PBSPage()]
    @Published var pageIndex: Int = 0
    @Published var backgroundImageData: Data?
    @Published var isDrawing = false

    /// Port de `PBSView.action` — outil actif (`"drawPath"`/`"text"`/`"smile"`/`"media"`/nil).
    var action: String?
    var paintColor: Int = 0xFF000000 // ARGB noir opaque, port de `Color.BLACK`
    var paintWidth: CGFloat = 10
    var username: String?
    /// Port de `PBSCompound.setDataCompress` — 1 échantillon réseau tous les N (3 en temps réel
    /// Shareboard, 2 pour Message Graphic, vérifié dans les deux appelants Android).
    var dataCompressRate = 3
    /// Port de `getRealPosition`/`remoteScreenW`/`remoteScreenH` — taille de vue locale, mise à
    /// jour par `PBSCanvasView` (`GeometryReader`), nécessaire pour normaliser les coordonnées
    /// distantes ET annoncer notre propre taille aux pairs.
    var localViewSize: CGSize = .zero

    /// Port de `PBStreamActionListener.onSendPBSTouchSreamListner` — émis pendant un tracé local,
    /// throttlé par `dataCompressRate` comme l'original.
    var onLocalTouch: ((PBSTouchEvent) -> Void)?
    /// Port de `PBStreamActionListener.onSendPBStreamData` — émis à chaque objet placé/déplacé.
    var onLocalObjectPlaced: ((PBSEditorData) -> Void)?
    /// Port de `PBStreamActionListener.onNextPage`/`onBeforePage`.
    var onLocalPageChange: ((Bool) -> Void)? // true = next, false = before

    private var localTouchCounter = 0
    private var localTouchCompressCounter = 0
    private var localMessageIdSeed = 0
    private var remoteInputStrokeIndex: Int?
    private var seenRemoteMessageIds: Set<String> = []

    var currentPage: PBSPage { pages[pageIndex] }

    // MARK: - Dessin local (port de `touchListener`/`drawPathProcessOuput`)

    func beginLocalStroke(at point: CGPoint) {
        guard action == "drawPath" else { return }
        isDrawing = true
        var stroke = PBSEditorData()
        stroke.type = "drawPath"
        stroke.action = "drawPath"
        stroke.strokePoints = [point]
        stroke.paintColor = paintColor
        stroke.paintWidth = paintWidth
        pages[pageIndex].strokes.append(stroke)
        localTouchCompressCounter = 0
        sendLocalTouch(action: .down, point: point)
    }

    func continueLocalStroke(to point: CGPoint) {
        guard action == "drawPath", var last = pages[pageIndex].strokes.last else { return }
        last.strokePoints.append(point)
        pages[pageIndex].strokes[pages[pageIndex].strokes.count - 1] = last
        localTouchCompressCounter += 1
        if localTouchCompressCounter >= dataCompressRate {
            localTouchCompressCounter = 0
            sendLocalTouch(action: .move, point: point)
        }
    }

    func endLocalStroke(at point: CGPoint) {
        guard action == "drawPath" else { return }
        isDrawing = false
        sendLocalTouch(action: .up, point: point)
    }

    private func sendLocalTouch(action touchAction: PBSTouchAction, point: CGPoint) {
        localMessageIdSeed += 1
        var event = PBSTouchEvent()
        event.messageId = "touchId_\(localMessageIdSeed)"
        event.actionMasked = touchAction.rawValue
        event.pointerCount = 1
        event.x = [point.x, 0]
        event.y = [point.y, 0]
        event.paintSize = Int(paintWidth)
        event.paintColor = paintColor
        event.type = "drawPath"
        event.action = "drawPath"
        event.remoteScreenW = Int(localViewSize.width)
        event.remoteScreenH = Int(localViewSize.height)
        onLocalTouch?(event)
    }

    /// Port de `PBSView.deletePrecedenteDraw`.
    func undoLastStroke() {
        guard !pages[pageIndex].strokes.isEmpty else { return }
        pages[pageIndex].strokes.removeLast()
    }

    // MARK: - Objets placés (port de `PBSCompound.add`/`addSticker`/`onClick(ic_text)`)

    func placeObject(_ data: PBSEditorData) {
        pages[pageIndex].objects.append(data)
        onLocalObjectPlaced?(data)
    }

    func updateObject(_ data: PBSEditorData) {
        guard let index = pages[pageIndex].objects.firstIndex(where: { $0.id == data.id }) else { return }
        pages[pageIndex].objects[index] = data
    }

    /// Port de `PBSView.deleteObjectDrawed` — PAS synchronisé sur le fil, voir avertissement de
    /// tête de fichier.
    func deleteObject(id: String) {
        pages[pageIndex].objects.removeAll { $0.id == id }
    }

    // MARK: - Pages (port de `PBSView.next`/`before`)

    func nextPage(isFromMe: Bool) {
        pages.append(PBSPage())
        pageIndex += 1
        if isFromMe { onLocalPageChange?(true) }
    }

    func previousPage(isFromMe: Bool) {
        pageIndex = max(0, pageIndex - 1)
        if isFromMe { onLocalPageChange?(false) }
    }

    // MARK: - Réception distante (port de `PBSView.setTouchListener`/`drawPathProcessInput`/
    // `receiveData`)

    /// Port de `getRealPosition` — remise à l'échelle d'une coordonnée distante selon le rapport
    /// des tailles d'écran (l'expéditeur annonce la sienne via `remoteScreenW`/`H`).
    private func realPosition(local side: CGFloat, remote: Int, position: CGFloat) -> CGFloat {
        guard remote > 0 else { return position }
        return position * side / CGFloat(remote)
    }

    /// Port de `setTouchListener`/`drawPathProcessInput` — traite UN événement tactile distant.
    /// **Un seul trait distant "en cours" à la fois** (`remoteInputStrokeIndex`), limitation réelle
    /// d'Android reproduite (voir avertissement de tête de fichier) : `inputPath` y est un champ
    /// unique de `PBSView`, pas une table indexée par expéditeur.
    func receiveTouch(_ event: PBSTouchEvent) {
        guard !seenRemoteMessageIds.contains(event.messageId) else { return }
        seenRemoteMessageIds.insert(event.messageId)
        guard event.type == "drawPath" || event.action == "drawPath" else { return }

        let x = realPosition(local: localViewSize.width, remote: event.remoteScreenW, position: event.x[0])
        let y = realPosition(local: localViewSize.height, remote: event.remoteScreenH, position: event.y[0])
        let point = CGPoint(x: x, y: y)

        switch event.actionMasked {
        case PBSTouchAction.down.rawValue:
            var stroke = PBSEditorData()
            stroke.type = "drawPath"
            stroke.action = "drawPath"
            stroke.strokePoints = [point]
            stroke.paintColor = event.paintColor
            stroke.paintWidth = CGFloat(event.paintSize)
            pages[pageIndex].strokes.append(stroke)
            remoteInputStrokeIndex = pages[pageIndex].strokes.count - 1
        case PBSTouchAction.move.rawValue:
            guard let index = remoteInputStrokeIndex, index < pages[pageIndex].strokes.count else { return }
            pages[pageIndex].strokes[index].strokePoints.append(point)
        default:
            remoteInputStrokeIndex = nil
        }
    }

    /// Port de `PBSCompound.receiveData`/`FragmentPbs.setData` — un objet placé par un pair.
    func receiveObject(_ data: PBSEditorData) {
        guard !seenRemoteMessageIds.contains(data.id) else { return }
        seenRemoteMessageIds.insert(data.id)
        pages[pageIndex].objects.append(data)
    }

    func receiveNextPage() { pages.append(PBSPage()); pageIndex += 1 }
    func receivePreviousPage() { pageIndex = max(0, pageIndex - 1) }

    /// Port de `PBSView.reset`.
    func reset() {
        pages = [PBSPage()]
        pageIndex = 0
        backgroundImageData = nil
        seenRemoteMessageIds.removeAll()
        remoteInputStrokeIndex = nil
    }

    // MARK: - Message Graphic (module 14) — chargement en lecture seule d'un lot enregistré

    /// Port de `PBSView.displayWhenItReady`/`GraphicMessageCodec.decodeGraphicMessage` — reconstitue
    /// les traits à partir du lot compact stocké (`MessageLib.message`, après substitution
    /// `MgGraphic`), en rejouant chaque échantillon comme s'il arrivait du réseau.
    func loadRecordedBatch(_ json: String?) {
        reset()
        for event in GraphicMessageCodec.decodeGraphicMessage(json) {
            receiveTouch(event)
        }
        remoteInputStrokeIndex = nil
    }
}
