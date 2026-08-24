import CoreGraphics
import Foundation

/// Port de `engine/template/MotionTemplateManager.java` (551 lignes, lu en entier) — extraction
/// d'un `MotionTemplate` depuis un `AnimationComposer`, réapplication sur un calque cible (avec
/// remise à l'échelle vers un canevas différent), persistance locale fichier par fichier.
///
/// **`MASK` (piste legacy issue d'un calque étiqueté `"mask_…"`, masque BAKÉ dans le bitmap) PAS
/// reproduit, délibérément** — confirmé en lisant `applyMaskLegacy`/`extractMaskFromLabel` : ce
/// chemin ne sert qu'à d'anciens calques Android créés avant l'introduction du rendu de masque
/// moderne (`appliedMaskType`, `MASK_RENDER`). Le port Swift de l'éditeur (masques câblés le
/// 2026-08-16, voir `AnimemesEditorState.setMaskType`) ne produit JAMAIS de calque étiqueté
/// `"mask_…"` — seul `MASK_RENDER` (masque moderne, rendu live par `LayerRenderer`) peut exister
/// dans un modèle créé par CETTE app. Portée réintroduite si l'import de modèles créés par une
/// très vieille version d'Android devient un besoin réel, pas avant.
///
/// **Piège de fidélité identifié en lisant `apply()` ligne par ligne** : le `switch` Android sur
/// `kd.propertyName` (lignes 292-315) ne gère QUE opacity/color/cornerRadius/feather/mask*
/// (9 propriétés) — PAS `PROP_MATRIX` (matrice complète, keyframes explicites du bouton ◆,
/// `AnimemesEditorState.recordKeyframe`), qui tombe dans le `default: Log.w(...)`. Un modèle qui
/// capture un calque avec des keyframes matricielles les EXTRAIT (`extractKeyframes` n'exclut
/// rien) mais ne les RÉAPPLIQUE JAMAIS à la relecture — donnée mais inerte, fidèlement comme
/// l'original, pas une lacune de ce portage.
enum MotionTemplateManager {
    static let filePrefix = "motion_template_"
    private static let maxFeatherPx: Float = 80

    // MARK: - Extraction (port de `extract`)

    static func extract(
        composer: AnimationComposer, canvasWidth: Int, canvasHeight: Int,
        hasAudio: Bool, audioLocalPath: String?
    ) -> MotionTemplate {
        var realMaxFrames = 0
        for obj in composer.layers where !obj.transforms.isEmpty {
            realMaxFrames = max(realMaxFrames, obj.transforms.count)
        }

        var tracks: [MotionTrack] = []
        for obj in composer.layers {
            guard !obj.transforms.isEmpty else { continue }

            var track = MotionTrack()
            track.label = obj.label
            track.offsetX = obj.offsetX
            track.offsetY = obj.offsetY
            track.objectWidth = Double(obj.width)
            track.objectHeight = Double(obj.height)
            track.startFrame = 0
            track.endFrame = obj.transforms.count - 1
            track.locked = obj.locked
            track.holdLast = obj.holdLast

            if let type = obj.objectType {
                if obj.hasAppliedMask, let maskType = obj.appliedMaskType {
                    track.objectType = "MASK_RENDER"
                    track.maskTypeName = maskType.androidName
                    track.maskInverted = obj.maskInverted
                    track.maskFeather = obj.maskFeather
                    track.maskOffsetX = obj.maskOffsetX
                    track.maskOffsetY = obj.maskOffsetY
                    track.maskScale = obj.maskScale
                    track.maskMirrorGap = obj.maskMirrorGap
                    track.maskRotation = obj.maskRotation
                    if let last = obj.transforms.last { track.maskOpacity = last.opacity }
                    track.maskColor = obj.shapeColor
                } else {
                    track.objectType = type.rawValue
                    if obj.isShape {
                        track.shapeColor = obj.shapeColor
                        track.shapeOpacity = obj.shapeOpacity
                        track.shapeCornerRadius = obj.shapeCornerRadius
                        track.shapeLineThickness = obj.shapeLineThickness
                        track.shapeStrokeWidth = obj.shapeStrokeWidth
                        track.shapeW = obj.shapeW
                        track.shapeH = obj.shapeH
                    }
                }
            }

            // Matrices bitmap normalisées (translation divisée par la taille du canevas SOURCE).
            var matrices: [[Float]] = []
            for t in obj.transforms {
                var values = t.matrixValues
                if values.count >= 6 {
                    values[2] /= Float(max(1, canvasWidth))
                    values[5] /= Float(max(1, canvasHeight))
                }
                matrices.append(values)
            }
            track.matrices = matrices

            // maskAutoFrames — décomposition Matrix → {offsetX, offsetY, scale, rotation}.
            if obj.hasMaskTransforms {
                var frames: [[Float]] = []
                for mt in obj.maskTransforms {
                    let v = mt.matrixValues
                    guard v.count >= 6 else { continue }
                    let offsetX = v[2] / Float(max(1, canvasWidth))
                    let offsetY = v[5] / Float(max(1, canvasHeight))
                    let scaleX = v[0], scaleY = v[4]
                    let scale = (abs(scaleX) + abs(scaleY)) / 2
                    // Port de `Math.atan2(vals[MSKEW_X], vals[MSCALE_X])` — indices 1 et 0.
                    let rotation = atan2(v[1], v[0]) * 180 / .pi
                    frames.append([offsetX, offsetY, scale, rotation])
                }
                track.maskAutoFrames = frames
            }

            track.keyframes = extractKeyframes(obj)
            tracks.append(track)
        }

        return MotionTemplate(
            id: UUID().uuidString,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            canvasWidth: canvasWidth, canvasHeight: canvasHeight,
            hasAudio: hasAudio,
            audioLocalPath: hasAudio ? audioLocalPath : nil,
            audioFileName: hasAudio ? audioLocalPath.map { URL(fileURLWithPath: $0).lastPathComponent } : nil,
            totalFrames: realMaxFrames, tracks: tracks
        )
    }

    /// Port de `extractKeyframes` — extrait TOUTES les pistes, y compris `matrix` (voir note de
    /// tête de fichier sur l'asymétrie extract/apply, fidèle à l'original).
    private static func extractKeyframes(_ obj: AnimationObjectData) -> [MotionTrack.KeyframeData] {
        var list: [MotionTrack.KeyframeData] = []
        for (propertyName, kfTrack) in obj.keyframeTracks {
            guard !kfTrack.isEmpty else { continue }
            for kf in kfTrack.keyframes {
                list.append(MotionTrack.KeyframeData(propertyName: propertyName, timestampNs: kf.timestampNs, values: kf.value))
            }
        }
        return list
    }

    // MARK: - Application (port de `apply`)

    static func apply(_ template: MotionTemplate, to targetObj: AnimationObjectData, trackIndex: Int, targetCanvasWidth: Int, targetCanvasHeight: Int) {
        guard trackIndex >= 0, trackIndex < template.tracks.count else { return }
        let track = template.tracks[trackIndex]
        let cW = targetCanvasWidth, cH = targetCanvasHeight
        // Port de `MotionTemplateManager.apply` (`:225-226,240-241`) — **corrigé le 2026-08-24
        // (MIGRATION_PARITY_AUDIT_V4.md V4-F-047, Phase B P2)**. Avant ce correctif, la
        // dénormalisation de la translation était LINÉAIRE (`valeur × targetCanvasWidth` seul) ;
        // Android multiplie EN PLUS par `scaleX = targetCanvasWidth / templateCanvasWidth` — une
        // formule quadratique en `targetCanvasWidth` quand le canevas cible diffère du canevas de
        // capture (`template.canvasWidth`/`canvasHeight`). Décision Phase B explicite : reproduire
        // le comportement Android tel quel (même s'il se lit comme une erreur d'arithmétique —
        // appliquer un facteur d'échelle DEUX FOIS, une fois par la multiplication directe et une
        // fois par `scaleX`), fidèle à la politique appliquée sur tout ce cycle d'audit ("reproduire
        // fidèlement le comportement Android réel, y compris ses défauts, sauf code mort/
        // inatteignable" — CE chemin est le SEUL exécuté à chaque application de template, pas un
        // cas rare). PAS documenté comme `IOS_INTENTIONAL_DIFFERENCE` — l'audit lui-même notait que
        // l'écart se lisait comme un oubli plutôt qu'une décision consciente, confirmé par
        // l'absence totale de commentaire sur ce point avant ce correctif.
        let scaleX = Float(targetCanvasWidth) / Float(max(1, template.canvasWidth))
        let scaleY = Float(targetCanvasHeight) / Float(max(1, template.canvasHeight))

        if track.isShape {
            applyShape(track, targetObj, cW, cH)
        } else if track.isMaskRender {
            applyMaskRender(track, targetObj, cW, cH)
        }

        // Matrices bitmap — dénormalisées vers le canevas CIBLE.
        var newTransforms: [Transform] = []
        for saved in track.matrices {
            guard saved.count >= 6 else { continue }
            var values = saved
            values[2] *= Float(cW) * scaleX
            values[5] *= Float(cH) * scaleY
            newTransforms.append(Transform(matrixValues: values))
        }
        targetObj.transforms = newTransforms
        targetObj.startFrame = track.startFrame
        targetObj.endFrame = track.endFrame
        targetObj.locked = track.locked
        targetObj.holdLast = track.holdLast

        // maskAutoFrames — reconstruction Matrix depuis {offsetX, offsetY, scale, rotation}.
        targetObj.clearMaskTransforms()
        if let maskAutoFrames = track.maskAutoFrames, !maskAutoFrames.isEmpty {
            let cx = CGFloat(cW) / 2, cy = CGFloat(cH) / 2
            for maf in maskAutoFrames where maf.count >= 4 {
                let offsetX = CGFloat(maf[0]) * CGFloat(cW)
                let offsetY = CGFloat(maf[1]) * CGFloat(cH)
                let scale = CGFloat(maf[2])
                let rotationRadians = CGFloat(maf[3]) * .pi / 180

                // Port de `Matrix m = new Matrix(); m.postScale(scale,scale,cx,cy);
                // m.postRotate(rotation,cx,cy); m.postTranslate(offsetX,offsetY);` — même motif
                // "post" que `AnimemesGestureController.rotate`/`scale` (voir tête de fichier de
                // ce dernier) : `current.concatenating(op)` = applique `current` D'ABORD puis `op`,
                // exactement l'ordre de `post*` sur une matrice qui commence identité.
                let scaleAroundPivot = CGAffineTransform(translationX: -cx, y: -cy)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: cx, y: cy))
                let rotateAroundPivot = CGAffineTransform(translationX: -cx, y: -cy)
                    .concatenating(CGAffineTransform(rotationAngle: rotationRadians))
                    .concatenating(CGAffineTransform(translationX: cx, y: cy))
                let translate = CGAffineTransform(translationX: offsetX, y: offsetY)

                let final = CGAffineTransform.identity
                    .concatenating(scaleAroundPivot)
                    .concatenating(rotateAroundPivot)
                    .concatenating(translate)

                targetObj.addMaskTransform(Transform(matrixValues: Transform.matrixValues(from: final)))
            }
        }

        // Keyframes manuels — SEULES les 9 propriétés qu'Android réapplique réellement (voir note
        // de tête de fichier : `matrix` extrait mais jamais réappliqué, fidèle à l'original).
        targetObj.clearAllKeyframes()
        for kd in track.keyframes {
            let v0 = kd.values.first ?? 0
            switch kd.propertyName {
            case KeyframeTrack.PropertyName.opacity: targetObj.addOpacityKeyframe(ts: kd.timestampNs, v: v0)
            case KeyframeTrack.PropertyName.color: targetObj.addColorKeyframe(ts: kd.timestampNs, argb: Keyframe.floatArrayToArgb(kd.values))
            case KeyframeTrack.PropertyName.cornerRadius: targetObj.addCornerRadiusKeyframe(ts: kd.timestampNs, v: v0)
            case KeyframeTrack.PropertyName.feather: targetObj.addFeatherKeyframe(ts: kd.timestampNs, v: v0)
            case KeyframeTrack.PropertyName.maskOffsetX: targetObj.addMaskOffsetXKeyframe(ts: kd.timestampNs, v: v0)
            case KeyframeTrack.PropertyName.maskOffsetY: targetObj.addMaskOffsetYKeyframe(ts: kd.timestampNs, v: v0)
            case KeyframeTrack.PropertyName.maskScale: targetObj.addMaskScaleKeyframe(ts: kd.timestampNs, v: v0)
            case KeyframeTrack.PropertyName.maskMirrorGap: targetObj.addMaskMirrorGapKeyframe(ts: kd.timestampNs, v: v0)
            case KeyframeTrack.PropertyName.maskRotation: targetObj.addMaskRotationKeyframe(ts: kd.timestampNs, v: v0)
            default: break
            }
        }
    }

    /// Port d'`applyShape` — reconstruit un calque forme via `ShapeFactory.rerender` (déjà porté,
    /// même stratégie que l'original : rasteriser une nouvelle bitmap à l'échelle du canevas cible).
    private static func applyShape(_ track: MotionTrack, _ targetObj: AnimationObjectData, _ cW: Int, _ cH: Int) {
        guard let type = AnimationObjectData.ObjectType(rawValue: track.objectType ?? "") else { return }

        let srcW = track.objectWidth > 0 ? Int(track.objectWidth) : cW
        let srcH = track.objectHeight > 0 ? Int(track.objectHeight) : cH
        let scale = min(Float(cW) / Float(max(1, srcW)), Float(cH) / Float(max(1, srcH)))

        targetObj.objectType = type
        targetObj.shapeColor = track.shapeColor
        targetObj.shapeOpacity = track.shapeOpacity
        targetObj.shapeCornerRadius = track.shapeCornerRadius
        targetObj.shapeLineThickness = track.shapeLineThickness
        targetObj.shapeStrokeWidth = track.shapeStrokeWidth
        targetObj.shapeW = max(4, Int((Float(track.shapeW) * scale).rounded()))
        targetObj.shapeH = max(4, Int((Float(track.shapeH) * scale).rounded()))
        targetObj.visible = true
        targetObj.isBackgroundTransparent = true

        guard let image = ShapeFactory.rerender(targetObj, canvasW: cW, canvasH: cH) else { return }
        targetObj.setBitmaps([image])
        targetObj.width = CGFloat(image.width)
        targetObj.height = CGFloat(image.height)
        let offsetX = cW / 2 - image.width / 2
        let offsetY = cH / 2 - image.height / 2
        targetObj.offsetX = offsetX
        targetObj.offsetY = offsetY
        targetObj.bound = CGRect(x: offsetX, y: offsetY, width: image.width, height: image.height)
    }

    /// Port d'`applyMaskRender` — masque MODERNE : pas de bitmap baké, seules les propriétés
    /// `appliedMaskType`/`maskOffsetX/Y`/etc sont restaurées, `LayerRenderer.drawObjectFrame` fait
    /// le compositing réel au rendu (voir câblage des masques du 2026-08-16). Un bitmap 1×1
    /// transparent tient lieu de calque hôte si l'objet n'en a pas déjà un (le masque a besoin
    /// d'UN bitmap sur lequel se composer).
    private static func applyMaskRender(_ track: MotionTrack, _ targetObj: AnimationObjectData, _ cW: Int, _ cH: Int) {
        guard let maskType = track.maskTypeName.flatMap(MaskType.init(androidName:)) else { return }

        targetObj.appliedMaskType = maskType
        targetObj.maskInverted = track.maskInverted
        targetObj.maskFeather = track.maskFeather
        targetObj.maskOffsetX = track.maskOffsetX
        targetObj.maskOffsetY = track.maskOffsetY
        targetObj.maskScale = track.maskScale
        targetObj.maskMirrorGap = track.maskMirrorGap
        targetObj.maskRotation = track.maskRotation
        targetObj.visible = true
        targetObj.isBackgroundTransparent = true
        targetObj.objectType = .bitmap

        if !targetObj.hasValidBitmaps || targetObj.width <= 0 {
            guard let context = CGContext(
                data: nil, width: max(1, cW), height: max(1, cH), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let placeholder = context.makeImage() else { return }
            targetObj.setBitmaps([placeholder])
            targetObj.width = CGFloat(cW)
            targetObj.height = CGFloat(cH)
            targetObj.offsetX = 0
            targetObj.offsetY = 0
            targetObj.bound = CGRect(x: 0, y: 0, width: cW, height: cH)
        }

        if var last = targetObj.transforms.last {
            last.opacity = track.maskOpacity
            targetObj.transforms[targetObj.transforms.count - 1] = last
        }
    }

    // MARK: - Persistance (port de `save`/`load`/`loadAll`/`delete`/`getFile`)
    //
    // `context.getFilesDir()` (stockage privé persistant de l'app) → `Application Support`
    // (équivalent iOS : privé à l'app, persistant, pas destiné à être vu par l'utilisateur —
    // contrairement à `Documents`, qui apparaît dans l'app Fichiers si `UIFileSharingEnabled` est
    // activé, non souhaité ici pour des données internes).

    private static var storageDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MotionTemplates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(id: String) -> URL {
        storageDirectory.appendingPathComponent(filePrefix + id).appendingPathExtension("json")
    }

    static func save(_ template: MotionTemplate) {
        guard let data = try? JSONEncoder().encode(template) else { return }
        try? data.write(to: fileURL(id: template.id))
    }

    static func load(id: String) -> MotionTemplate? {
        guard let data = try? Data(contentsOf: fileURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(MotionTemplate.self, from: data)
    }

    /// Port de `loadAll` — trié par date de création décroissante (le plus récent en premier),
    /// comportement d'affichage raisonnable non explicitement spécifié côté Android (qui ne trie
    /// pas), amélioration mineure assumée plutôt qu'un oubli de portage.
    static func loadAll() -> [MotionTemplate] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else { return [] }
        let templates = files
            .filter { $0.lastPathComponent.hasPrefix(filePrefix) }
            .compactMap { url -> MotionTemplate? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(MotionTemplate.self, from: data)
            }
        return templates.sorted { $0.createdAt > $1.createdAt }
    }

    static func delete(id: String) {
        try? FileManager.default.removeItem(at: fileURL(id: id))
    }
}
