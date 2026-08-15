import CoreGraphics
import Foundation
import UIKit

/// État de l'écran `AnimemesEditorView` — wrapper `ObservableObject` autour du moteur Animems déjà
/// porté (`AnimationComposer` et les `AnimationObjectData` qu'il contient sont des classes de
/// référence SANS `@Published` interne ; `version` est incrémenté à chaque mutation pour forcer
/// SwiftUI à redessiner le `Canvas`, seul mécanisme de notification nécessaire ici).
@MainActor
final class AnimemesEditorState: ObservableObject {
    let composer = AnimationComposer()
    let bitmapCache = BitmapCacheManager()
    let textRect: TextRect
    /// Port de la logique de geste tactile (`MemesView2.java`, voir `AnimemesGestureController`) —
    /// ajouté le 2026-08-16 (continuation post-Appetize) : translation/rotation/échelle réelles au
    /// lieu de la seule translation `offsetX`/`offsetY` de la version initiale.
    let gestureController = AnimemesGestureController()
    private let gestureEngine = AnimationEngine() // port de `touchUp` (lissage Chaikin), pas de lecture réelle utilisée ici

    @Published private(set) var version = 0
    @Published var isExporting = false
    @Published var exportError: String?
    @Published var selectedId: String?

    /// Port SIMPLIFIÉ de la durée d'un calque — 3s à 30 fps (`AnimemesExporter.frameRate`), tenu
    /// statique via `holdLast=true` plutôt qu'animé. Pas de timeline/keyframes détaillées dans
    /// cette passe (voir tête de fichier `AnimemesEditorView.swift`) — un export produit donc un
    /// clip fixe de 3s, PAS une vraie animation image par image. Documenté comme périmètre réduit
    /// assumé, pas une lacune découverte après coup.
    private static let durationFrames = 90

    init() {
        textRect = TextRect(font: .boldSystemFont(ofSize: 32), textColor: .white)
    }

    var layers: [AnimationObjectData] { composer.layers }

    private func configureNewObject(_ obj: AnimationObjectData, canvasSize: CGSize, size: CGSize) {
        obj.id = UUID().uuidString
        obj.transforms = [Transform()]
        obj.startFrame = 0
        obj.endFrame = Self.durationFrames - 1
        obj.holdLast = true
        obj.visible = true
        obj.offsetX = Int(canvasSize.width / 2 - size.width / 2)
        obj.offsetY = Int(canvasSize.height / 2 - size.height / 2)
    }

    func addImage(_ image: UIImage, canvasSize: CGSize) {
        // Port de `ic_add` → galerie → calque BITMAP. Redimensionnement AVANT ajout : `LayerRenderer`
        // dessine chaque bitmap à sa taille PIXEL native (`bmp.width`/`bmp.height`, pas de mise à
        // l'échelle appliquée par le moteur) — une photo caméra pleine résolution recouvrirait tout
        // le canevas sans ce redimensionnement préalable.
        guard let resized = Self.downscale(image, maxDimension: 220), let cgImage = resized.cgImage else { return }
        let obj = AnimationObjectData()
        obj.objectType = .bitmap
        obj.addBitmap(cgImage)
        configureNewObject(obj, canvasSize: canvasSize, size: CGSize(width: cgImage.width, height: cgImage.height))
        composer.addLayer(obj)
        version += 1
    }

    func addText(_ text: String, canvasSize: CGSize) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let obj = AnimationObjectData()
        obj.objectType = .text
        obj.text = trimmed
        obj.backgroundColor = 0xB300_0000
        obj.objectColor = 0xFFFF_FFFF
        configureNewObject(obj, canvasSize: canvasSize, size: CGSize(width: 160, height: 60))
        composer.addLayer(obj)
        version += 1
    }

    /// Port de `showShapeAddPanel()`/`btn_shape` — formes RASTÉRISÉES immédiatement
    /// (`ShapeFactory`, même stratégie que le moteur Android d'origine : "shapes are rasterized
    /// into Bitmap so they plug directly into the existing AnimationObjectData bitmap pipeline").
    func addShape(_ type: AnimationObjectData.ObjectType, canvasSize: CGSize) {
        let image: CGImage?
        let size: CGSize
        switch type {
        case .shapeRect:
            image = ShapeFactory.createRect(w: 150, h: 100, color: 0xFFFF_3B30, alpha: 1, cornerRadius: 12, strokeWidth: 0)
            size = CGSize(width: 150, height: 100)
        case .shapeCircle:
            image = ShapeFactory.createCircle(diameter: 140, color: 0xFF34_C759, alpha: 1, strokeWidth: 0)
            size = CGSize(width: 140, height: 140)
        case .shapeLine:
            image = ShapeFactory.createLine(length: 200, thickness: 8, color: 0xFF00_7AFF, alpha: 1)
            size = CGSize(width: 200, height: 12)
        default:
            return
        }
        guard let image else { return }
        let obj = AnimationObjectData()
        obj.objectType = type
        obj.addBitmap(image)
        configureNewObject(obj, canvasSize: canvasSize, size: size)
        composer.addLayer(obj)
        version += 1
    }

    // MARK: - Gestes (port de `MemesView2.java` via `AnimemesGestureController`, 2026-08-16)

    /// Port de `touchDown` — teste si `point` tombe dans un calque (du dernier au premier, ordre
    /// d'affichage = ordre de dessin, le dernier dessiné est visuellement au-dessus) et l'arme pour
    /// le geste en cours.
    func selectObject(at point: CGPoint) -> String? {
        guard let index = layers.lastIndex(where: { $0.bound?.contains(point) ?? false }) else {
            selectedId = nil
            return nil
        }
        selectedId = layers[index].id
        gestureController.touchDown(at: point, objectIndex: index, composer: composer)
        return selectedId
    }

    private func index(of id: String) -> Int? { layers.firstIndex { $0.id == id } }

    /// Port de `touchMove` (translation à un doigt) — délègue à `AnimemesGestureController.
    /// touchMoveTranslate`, qui opère directement sur la matrice de la dernière `Transform` (PAS
    /// `offsetX`/`offsetY`, corrigé le 2026-08-16 — la version initiale mutait `offsetX`/`offsetY`
    /// directement, une simplification qui aurait mal composé avec la rotation/l'échelle ajoutées
    /// ici : Android ne touche JAMAIS `offsetX`/`offsetY` par geste, tout passe par la matrice).
    func dragMoved(to point: CGPoint) {
        guard let id = selectedId, let idx = index(of: id) else { return }
        gestureController.touchMoveTranslate(to: point, objectIndex: idx, composer: composer)
        version += 1
    }

    func dragEnded() {
        guard let id = selectedId, let idx = index(of: id) else { return }
        gestureController.touchUp(objectIndex: idx, composer: composer, engine: gestureEngine)
    }

    /// Port de `touchPointerDown` — amorce un geste rotation/pincement, pivot = centre du calque
    /// sélectionné (Android utilise le point milieu RÉEL des deux doigts ; `RotationGesture`/
    /// `MagnificationGesture` de SwiftUI ne donnent pas accès aux coordonnées de contact
    /// individuelles, seulement des valeurs scalaires cumulatives depuis le début du geste — le
    /// centre du calque est un pivot raisonnable et fidèle en pratique, écart assumé faute d'accès
    /// à la position réelle des doigts).
    func beginPinchRotate() {
        guard let id = selectedId, let idx = index(of: id), let bound = layers[idx].bound else { return }
        let center = CGPoint(x: bound.midX, y: bound.midY)
        // Points synthétiques choisis pour que `AnimemesGestureController.degrees(p0,p1) == 0` et
        // `midPoint == center` (voir le calcul dans `AnimemesGestureController.swift` :
        // `atan2(p0.x-p1.x, p0.y-p1.y)` — `p0`/`p1` alignés verticalement sur `center`, `p0` en
        // dessous de `p1`, donne `atan2(0, +) == 0`). Sert UNIQUEMENT à initialiser l'angle de
        // référence à 0°, cohérent avec `RotationGesture`, qui rapporte aussi un angle cumulatif
        // débutant à 0° — voir `rotationChanged(to:)` ci-dessous.
        gestureController.pointerDown(point0: CGPoint(x: center.x, y: center.y + 1), point1: CGPoint(x: center.x, y: center.y - 1))
    }

    /// Port de `rotate` — `newDegrees` est l'angle CUMULATIF rapporté par `RotationGesture`
    /// (identique en sémantique à `oldAngleDegrees` initialisé à 0 dans `beginPinchRotate`, voir
    /// note ci-dessus) : `AnimemesGestureController.rotate(to:)` calcule lui-même le delta interne,
    /// pas besoin de le calculer ici.
    func rotationChanged(to newDegrees: CGFloat) {
        guard let id = selectedId, let idx = index(of: id) else { return }
        gestureController.rotate(to: newDegrees, objectIndex: idx, composer: composer)
        version += 1
    }

    /// Port de `scale`/`ScaleListener.onScale` — `incrementalFactor` est le ratio ENTRE deux
    /// valeurs cumulatives successives de `MagnificationGesture` (calculé par l'appelant SwiftUI,
    /// voir `AnimemesEditorView` — `AnimemesGestureController.scale` attend un facteur PAR
    /// ÉVÉNEMENT, pas cumulatif, voir sa documentation).
    func scaleChanged(incrementalFactor: CGFloat) {
        guard let id = selectedId, let idx = index(of: id), let bound = layers[idx].bound else { return }
        let clamped = AnimemesGestureController.clampPerEventScaleFactor(incrementalFactor)
        gestureController.scale(factor: clamped, focus: CGPoint(x: bound.midX, y: bound.midY), objectIndex: idx, composer: composer)
        version += 1
    }

    /// Port d'`undo` → `mView.deletePrecedenteDraw()` — supprime le DERNIER calque ajouté (pas une
    /// pile d'annulation multi-niveaux généralisée, fidèle à ce bouton précis côté Android).
    func removeLast() {
        guard !composer.layers.isEmpty else { return }
        composer.setLayers(Array(composer.layers.dropLast()))
        version += 1
    }

    /// Port de `save_animemes2` → `showSaveDialog()` → export réel (`AnimemesCompound.
    /// createVideosFromBitmap`) — MP4 uniquement, pas de GIF (voir `AnimemesExporter`, aucun
    /// exporteur GIF porté).
    func export(canvasSize: CGSize, completion: @escaping (URL?) -> Void) {
        guard !composer.layers.isEmpty else { return }
        isExporting = true
        exportError = nil
        let exporter = AnimemesExporter(composer: composer)
        exporter.outputSize = canvasSize
        exporter.viewSize = canvasSize
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        exporter.export(to: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isExporting = false
                switch result {
                case .success(let outputURL):
                    completion(outputURL)
                case .failure:
                    self.exportError = "L'export a échoué."
                    completion(nil)
                }
            }
        }
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
