import CoreGraphics
import Foundation

/// Port de `MemesView2.recomposeObjects`/`computeRecomposeBounds` (lus en entier au passage
/// précédent du module 8) — fige plusieurs calques sélectionnés (chacun avec son propre timing)
/// en une seule séquence de bitmaps, réutilisable comme un GIF (bouton "recompose" de
/// `AnimemesCompound.performRecompose`).
///
/// **Portée** : ce fichier porte la logique pure de fusion (candidate filtering, calcul du nombre
/// de frames, rendu, construction du calque résultat) — la partie ORCHESTRATION UI de
/// `AnimemesCompound.performRecompose` (lue en entier, lignes ~3438-3573 de
/// `AnimemesCompound.java`) reste explicitement HORS scope ici et documentée comme différée :
/// - `AnimemesRecomposeNameSheet` (dialogue de nommage) et `RecomposeManager.save` (persistance
///   disque des frames en PNG) — système de sauvegarde SÉPARÉ de la fusion elle-même, purement
///   UI/IO, aucune logique de rendu. Pas encore lu, pas encore porté.
/// - Le fanion `timelineView.addTrackIcon(...)`/icône groupe "▼" et le filtrage de la timeline par
///   groupe (`enterGroupView`/`exitGroupView`/`applyDefaultTimelineFilter`/`syncVisibilityIcon`) —
///   dépendent de `TimelineView` (vue custom non encore portée, item 4 du plan module 8).
/// Ce qui EST porté ici est directement appelable dès que la timeline UI existe : `recompose(...)`
/// produit le calque `AnimationObjectData` prêt à insérer, exactement comme le fait
/// `performRecompose` avant d'appeler `addToTimeline`.
enum AnimemesRecompose {
    /// Port de `AnimemesCompound.RECOMPOSE_SAMPLE_INTERVAL_MS` — 33ms ≈ 30fps, cohérent avec le
    /// frameRate fixe de `AnimationEngine`. Confirmé PAS être en unité GIF-encoder (1-10, cf.
    /// `getSpecificTime2`) malgré la ressemblance de nom avec `getBitmapChangeFrequence`
    /// (111-3330ms) — les deux sont des systèmes de durée différents, non réutilisés ici.
    static let sampleIntervalMs = 33

    /// Port de `AnimemesCompound.MAX_RECOMPOSE_FRAMES`.
    static let maxFrames = 40

    /// Port de `getRecomposeCandidates` — calques éligibles à la fusion : ni verrouillés, ni
    /// masqués.
    static func candidates(from layers: [AnimationObjectData]) -> [AnimationObjectData] {
        layers.filter { !$0.locked && $0.visible }
    }

    /// Port de `computeDefaultTotalFrames`.
    static func defaultTotalFrames(for objects: [AnimationObjectData]) -> Int {
        let longest = objects.reduce(1) { max($0, $1.transforms.count) }
        return min(maxFrames, longest)
    }

    /// Port de la portion "construction du calque résultat" de `performRecompose` (après l'appel à
    /// `recomposeObjects`, avant `addToTimeline`). Ne modifie PAS `candidates` en place (Android
    /// bascule `src.setVisible(false)`/`setRecomposeGroupId` sur les sources APRÈS insertion dans
    /// la timeline — hors scope ici, laissé à l'appelant UI comme documenté ci-dessus).
    ///
    /// Retourne `nil` si la fusion échoue (aucune frame produite) — reproduit
    /// `if (frames.isEmpty()) { Toast... ; return; }`.
    static func buildComposedLayer(from candidates: [AnimationObjectData]) -> AnimationObjectData? {
        let totalFrames = defaultTotalFrames(for: candidates)
        let frames = recompose(
            objects: candidates, totalFrames: totalFrames, frameDurationMs: sampleIntervalMs)
        guard let firstFrame = frames.first else { return nil }

        let bounds = computeBounds(candidates)
        let offsetX = Int(bounds.origin.x.rounded())
        let offsetY = Int(bounds.origin.y.rounded())

        let data = AnimationObjectData()
        data.objectType = .bitmap
        data.setBitmaps(frames)
        data.width = CGFloat(firstFrame.width)
        data.height = CGFloat(firstFrame.height)
        data.offsetX = offsetX
        data.offsetY = offsetY
        data.bound = CGRect(
            x: CGFloat(offsetX), y: CGFloat(offsetY),
            width: CGFloat(firstFrame.width), height: CGFloat(firstFrame.height))
        data.isBackgroundTransparent = true
        data.visible = true
        data.bitmapChangeIntervalMs = sampleIntervalMs

        // Port de `new Matrix()` (identité) + `transform.setFrameIndex((int) currentTimeMillis())`
        // — Android utilise l'horodatage comme identifiant de frame arbitraire mais non-nul ici
        // (une seule transform statique pour ce calque composé) ; reproduit à l'identique plutôt
        // que simplifié à 0, au cas où `frameIndex` serait utilisé ailleurs comme clé de cache.
        var transform = Transform()
        transform.frameIndex = Int(Date().timeIntervalSince1970 * 1000)
        data.transforms = [transform]

        data.label = "compose"
        return data
    }

    /// Port de `computeRecomposeBounds` — rectangle englobant ABSOLU de plusieurs calques, à
    /// travers TOUTES leurs frames respectives (pas seulement la frame courante) — ne s'appuie
    /// PAS sur `obj.bound` (réinitialisé en espace local à chaque `drawObjectFrame`, donc peu
    /// fiable pour une frame arbitraire passée/future, comme documenté dans le commentaire
    /// Android d'origine).
    static func computeBounds(_ objects: [AnimationObjectData]) -> CGRect {
        var result: CGRect?
        for obj in objects {
            guard !obj.transforms.isEmpty else { continue }
            let w = obj.width, h = obj.height
            let ox = CGFloat(obj.offsetX), oy = CGFloat(obj.offsetY)
            let localRect = CGRect(x: ox, y: oy, width: w, height: h)
            for tfm in obj.transforms {
                let mapped = localRect.applying(tfm.cgAffineTransform)
                result = result?.union(mapped) ?? mapped
            }
        }
        return result ?? .zero
    }

    /// Port de `recomposeObjects` — génère la séquence de bitmaps composés. Chaque objet boucle
    /// sur SA PROPRE séquence de `Transform` (leur nombre peut différer d'un objet à l'autre) via
    /// un index modulo — PAS de gel sur la dernière frame (`holdLast`) : la boucle demandée est un
    /// vrai cycle, fidèle à l'original.
    ///
    /// - Parameter frameDurationMs: pilote UNIQUEMENT l'échantillonnage interne (conversion frame
    ///   locale → ns, pour les objets pilotés par keyframes/masque) — ne modifie PAS la vitesse de
    ///   lecture du résultat, qui reste celle réglée séparément via
    ///   `AnimationObjectData.bitmapChangeIntervalMs` sur l'objet composé résultant (reproduit
    ///   tel quel, même commentaire que l'original Android sur ce point).
    static func recompose(
        objects selectedObjects: [AnimationObjectData], totalFrames: Int, frameDurationMs: Int
    ) -> [CGImage] {
        guard !selectedObjects.isEmpty, totalFrames >= 1 else { return [] }

        let bounds = computeBounds(selectedObjects)
        let w = max(1, Int(bounds.width.rounded()))
        let h = max(1, Int(bounds.height.rounded()))

        var result: [CGImage] = []
        result.reserveCapacity(totalFrames)

        for f in 0..<totalFrames {
            guard let context = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            // Contexte bitmap créé manuellement — flip Y nécessaire avant d'invoquer
            // `LayerRenderer` (voir sa note de tête de fichier : il suppose un contexte DÉJÀ
            // Y-vers-le-bas, comme `AnimemesExporter` doit déjà le faire pour la même raison).
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: 1, y: -1)

            for obj in selectedObjects {
                let tfs = obj.transforms
                guard !tfs.isEmpty else { continue }

                let localIdx = f % tfs.count
                let localNs = Int64(localIdx) * Int64(frameDurationMs) * 1_000_000
                let tfm = tfs[localIdx]

                let globalElapsedMs = Int64(f) * Int64(frameDurationMs)
                let bmpForFrame: CGImage?
                if obj.hasBitmapTimestamps {
                    bmpForFrame = obj.currentBitmap(forTime: globalElapsedMs * 1_000_000)
                } else if !obj.bitmaps.isEmpty {
                    let interval = obj.effectiveBitmapChangeIntervalMs
                    let bmpIdx: Int
                    if interval > 0 {
                        bmpIdx = Int((globalElapsedMs / interval) % Int64(obj.bitmaps.count))
                    } else {
                        bmpIdx = f % obj.bitmaps.count
                    }
                    bmpForFrame = obj.bitmaps[bmpIdx]
                } else {
                    bmpForFrame = obj.currentBitmap
                }

                context.saveGState()
                LayerRenderer.drawObjectFrame(
                    obj, transform: tfm, frameIndex: localIdx, in: context, currentNs: localNs,
                    origin: bounds.origin, bitmapOverride: bmpForFrame,
                    viewSize: CGSize(width: w, height: h)
                )
                context.restoreGState()
            }

            if let image = context.makeImage() {
                result.append(image)
            }
        }

        return result
    }
}
