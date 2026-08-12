import CoreGraphics
import UIKit

/// Port du cœur du rendu de `engine/android/memes/MemesView2.java` pour les calques
/// BITMAP/SHAPE_RECT/SHAPE_CIRCLE/SHAPE_LINE — `drawBitmapLastTransform` (aperçu statique, avec
/// cache) et `drawObjectFrame` (lecture/scrubbing, sans cache — chaque frame a des valeurs
/// différentes). Les deux méthodes Android partagent l'essentiel de leur logique paint/masque/
/// clip, factorisée ici en un seul helper interne `composite(...)` — **MAIS une vraie différence
/// de comportement entre les deux existe et est préservée, pas effacée par la factorisation** :
/// `drawBitmapLastTransform` dessine TOUJOURS une bulle de fond (rayon de repli 10 si
/// `cornerRadius<=0`) tant que le fond n'est pas transparent, alors que `drawObjectFrame` ne
/// dessine AUCUNE bulle si `cornerRadius<=0` (pas de repli à 10). Un premier jet de ce fichier
/// avait accidentellement fusionné les deux comportements en un seul — corrigé avant tout build
/// via `bubbleRadius: CGFloat?` calculé différemment aux deux sites d'appel.
///
/// **TEXT (`writeText`) et STICKER (`drawShap`) également portés ci-dessous** (`drawText`/
/// `drawSticker`) — les deux ont un état PAR CALQUE (`AnimationObjectData`), contrairement à
/// PATH/LINE/CLIP/ERASE.
///
/// **PATH/LINE/CLIP/ERASE (`drawPath`/`drawLine`/`clipPath`/`erase`) NON portés, décision
/// motivée** : lus dans `MemesView2.java` — ce ne sont PAS des calques avec un état persistant
/// dans `AnimationObjectData` comme les autres types, mais le rendu du GESTE DE DESSIN EN COURS
/// (champs `path`/`inicialX/Y`/`finalX/Y` de niveau CLASSE, un seul geste actif à la fois,
/// jamais lié à un `obj` précis). `clipPath` est d'ailleurs un corps VIDE côté Android
/// (`private void clipPath(Canvas canvas, int i) {}`) — confirmé mort/jamais implémenté, pas un
/// oubli de lecture. Porter `drawPath`/`drawLine`/`erase` a du sens seulement une fois la
/// gestion de geste tactile elle-même conçue (pas encore le cas) — prématuré de porter le rendu
/// d'un état qui n'existe pas encore côté Swift. `recomposeObjects`/`computeRecomposeBounds`
/// (fusion de calques en séquence GIF) également pas encore portés.
///
/// **Repère de coordonnées** : contrairement à `MaskFactory`/`BitmapGeometry` (contextes bitmap
/// créés manuellement, origine bas-gauche par défaut), ce renderer suppose un `CGContext` DÉJÀ
/// en repère Y-vers-le-bas comme celui fourni par UIKit dans `UIView.draw(_:)`/`CALayer.draw(in:)`
/// — donc AUCUN flip appliqué ici. Si ce renderer est un jour appelé depuis un contexte bitmap
/// manuel (ex. export vers `CVPixelBuffer` dans le futur port de `MP4Encoder.java`), l'appelant
/// devra appliquer le même flip que `MaskFactory` avant d'invoquer ces fonctions — pas un oubli,
/// une responsabilité laissée à l'appelant comme documenté ici.
enum LayerRenderer {
    static let maxFeatherPx: CGFloat = 250

    /// Port de `drawBitmapLastTransform` — dessine un calque avec sa DERNIÈRE `Transform`
    /// (aperçu statique, hors lecture/scrubbing), en utilisant le cache feather/mask partagé.
    static func drawLastTransform(
        _ obj: AnimationObjectData,
        in context: CGContext,
        currentNs: Int64,
        isSliderPreview: Bool,
        bitmapCache: BitmapCacheManager,
        viewSize: CGSize
    ) {
        guard let tfm = obj.transforms.last else { return }
        guard let bmp = obj.currentBitmap else { return }

        context.saveGState()
        context.concatenate(tfm.cgAffineTransform)

        let offsetX = CGFloat(obj.offsetX), offsetY = CGFloat(obj.offsetY)
        let padding: CGFloat = 5
        obj.bound = CGRect(
            x: offsetX - padding, y: offsetY - padding,
            width: CGFloat(bmp.width) + padding * 2, height: CGFloat(bmp.height) + padding * 2
        )

        let (opacity, color, cornerRadius, feather) = resolveVisualProperties(
            obj, transform: tfm, currentNs: currentNs, isSliderPreview: isSliderPreview
        )
        let featherPx = feather * feather * maxFeatherPx

        let bmpToDraw = bitmapCache.cachedFeatheredImage(source: bmp, featherPx: featherPx)
        let featherApplied = bmpToDraw !== bmp

        let maskOffset: (x: CGFloat, y: CGFloat, scale: CGFloat, gap: CGFloat, rotation: CGFloat)?
        if obj.hasAppliedMask {
            if isSliderPreview {
                maskOffset = (
                    CGFloat(obj.maskOffsetX), CGFloat(obj.maskOffsetY), CGFloat(obj.maskScale),
                    CGFloat(obj.maskMirrorGap), CGFloat(obj.maskRotation)
                )
            } else if obj.hasMaskTransforms, let lastMaskTfm = obj.maskTransform(at: obj.maskTransformsCount - 1) {
                maskOffset = decomposeMaskTransform(lastMaskTfm, fallbackGap: CGFloat(obj.maskMirrorGap), viewSize: viewSize)
            } else {
                let ns = currentNs
                maskOffset = (
                    CGFloat(obj.interpolatedMaskOffsetX(at: ns)), CGFloat(obj.interpolatedMaskOffsetY(at: ns)),
                    CGFloat(obj.interpolatedMaskScale(at: ns)), CGFloat(obj.interpolatedMaskMirrorGap(at: ns)),
                    CGFloat(obj.interpolatedMaskRotation(at: ns))
                )
            }
        } else {
            maskOffset = nil
        }
        let maskFeatherPx = isSliderPreview
            ? CGFloat(obj.maskFeather) * maxFeatherPx
            : CGFloat(obj.interpolatedFeather(at: currentNs)) * maxFeatherPx

        let maskImage: CGImage? = maskOffset.map { m in
            bitmapCache.cachedMaskImage(
                for: obj, bmpW: bmpToDraw.width, bmpH: bmpToDraw.height,
                maskOffX: m.x, maskOffY: m.y, maskScl: m.scale, maskGap: m.gap, maskRot: m.rotation,
                maskFeatherPx: maskFeatherPx
            )
        } ?? nil

        // Port de `drawBitmapLastTransform` : bulle TOUJOURS dessinée si fond non transparent,
        // rayon de repli 10 si `cornerRadius<=0` (DIFFÉRENT de `drawObjectFrame`, voir ci-dessous).
        let bubbleRadius: CGFloat? = obj.isBackgroundTransparent ? nil : (cornerRadius > 0 ? CGFloat(cornerRadius) : 10)

        composite(
            bmpToDraw, maskImage: maskImage, featherApplied: featherApplied, featherPx: featherPx,
            offsetX: offsetX, offsetY: offsetY, opacity: opacity, color: color,
            cornerRadius: CGFloat(cornerRadius), bubbleRadius: bubbleRadius, hasAppliedMask: obj.hasAppliedMask,
            bound: obj.bound ?? .zero, in: context
        )

        context.restoreGState()
    }

    /// Port de `drawObjectFrame` — dessine un calque à une frame `t` ARBITRAIRE (lecture/
    /// scrubbing), sans cache (chaque frame a ses propres valeurs interpolées). `origin` = coin
    /// soustrait après application de la matrice (0,0 à l'écran ; coin de bounding box pour un
    /// futur rendu offscreen de type `recomposeObjects`, pas encore porté).
    static func drawObjectFrame(
        _ obj: AnimationObjectData,
        transform tfm: Transform,
        frameIndex t: Int,
        in context: CGContext,
        currentNs: Int64,
        origin: CGPoint = .zero,
        bitmapOverride: CGImage? = nil,
        viewSize: CGSize
    ) {
        context.saveGState()
        context.translateBy(x: -origin.x, y: -origin.y)

        let matrixToUse: CGAffineTransform
        if obj.hasTransformKeyframes {
            if let interpolated = obj.interpolatedMatrixValues(at: currentNs) {
                matrixToUse = Transform(matrixValues: interpolated).cgAffineTransform
            } else {
                matrixToUse = obj.transforms.last?.cgAffineTransform ?? .identity
            }
        } else {
            matrixToUse = tfm.cgAffineTransform
        }
        context.concatenate(matrixToUse)

        guard let bmp = bitmapOverride ?? obj.currentBitmap else {
            context.restoreGState()
            return
        }

        let offsetX = CGFloat(obj.offsetX), offsetY = CGFloat(obj.offsetY)
        let padding: CGFloat = 5
        obj.bound = CGRect(
            x: offsetX - padding, y: offsetY - padding,
            width: CGFloat(bmp.width) + padding * 2, height: CGFloat(bmp.height) + padding * 2
        )

        let (opacity, color, cornerRadius, feather) = resolveVisualProperties(
            obj, transform: tfm, currentNs: currentNs, isSliderPreview: false
        )
        let featherPx = feather * feather * maxFeatherPx
        let bmpToDraw = BitmapCacheManager.applyFeather(bmp, featherPx: featherPx) ?? bmp
        let featherApplied = bmpToDraw !== bmp

        var maskImage: CGImage?
        if obj.hasAppliedMask, let maskType = obj.appliedMaskType {
            let m: (x: CGFloat, y: CGFloat, scale: CGFloat, gap: CGFloat, rotation: CGFloat)
            if let maskTfm = obj.maskTransform(at: t) {
                m = decomposeMaskTransform(maskTfm, fallbackGap: CGFloat(obj.maskMirrorGap), viewSize: viewSize)
            } else {
                m = (
                    CGFloat(obj.interpolatedMaskOffsetX(at: currentNs)), CGFloat(obj.interpolatedMaskOffsetY(at: currentNs)),
                    CGFloat(obj.interpolatedMaskScale(at: currentNs)), CGFloat(obj.interpolatedMaskMirrorGap(at: currentNs)),
                    CGFloat(obj.interpolatedMaskRotation(at: currentNs))
                )
            }
            let maskFeatherPx = CGFloat(obj.maskFeather) * maxFeatherPx
            maskImage = MaskFactory.createMaskScaled(
                type: maskType, width: bmpToDraw.width, height: bmpToDraw.height,
                inverted: obj.maskInverted, featherRadius: maskFeatherPx,
                scale: m.scale, offsetX: m.x, offsetY: m.y, mirrorGap: m.gap, rotation: m.rotation
            )
        }

        // Port de `drawObjectFrame` : bulle dessinée SEULEMENT si `cornerRadius>0` (PAS de repli
        // à 10, contrairement à `drawBitmapLastTransform` — différence Android confirmée, voir
        // commentaire de tête de fichier).
        let bubbleRadius: CGFloat? = (!obj.isBackgroundTransparent && cornerRadius > 0) ? CGFloat(cornerRadius) : nil

        composite(
            bmpToDraw, maskImage: maskImage, featherApplied: featherApplied, featherPx: featherPx,
            offsetX: offsetX, offsetY: offsetY, opacity: opacity, color: color,
            cornerRadius: CGFloat(cornerRadius), bubbleRadius: bubbleRadius, hasAppliedMask: obj.hasAppliedMask,
            bound: obj.bound ?? .zero, in: context
        )

        context.restoreGState()
    }

    // MARK: - TEXT

    /// Constantes de layout de `writeText` — `outerPadding = round(16*dp)`/`bubblePadding =
    /// round(8*dp)` côté Android (mise à l'échelle densité manuelle). Sur iOS, un point DÉJÀ
    /// indépendant de la densité — pas de multiplication par `dp` nécessaire, simplification
    /// légitime par différence de plateforme (pas un oubli).
    private static let outerPadding: CGFloat = 16
    private static let bubblePadding: CGFloat = 8
    private static let cells: CGFloat = 2

    /// Port de `writeText` — calque TEXT : bulle de fond (`obj.backgroundColor`) + texte
    /// multi-ligne (`obj.text`, couleur `obj.objectColor`) via `TextRect`. **Effet de bord
    /// reproduit à l'identique** : si le calque n'a pas encore de bitmap "figé" (`obj.
    /// currentBitmap == nil`), une bitmap est générée et stockée dans `obj.bitmaps` — PAS
    /// consommée par le rendu live lui-même (qui redessine toujours le texte à la volée via
    /// `TextRect`), mais par d'autres consommateurs qui attendent un bitmap classique pour ce
    /// calque (export `MP4Encoder`, `recomposeObjects` — pas encore portés, mais le mécanisme de
    /// "baking" est reproduit dès maintenant pour rester cohérent avec eux le moment venu).
    static func drawText(_ obj: AnimationObjectData, in context: CGContext, textRect: TextRect, viewSize: CGSize) {
        guard let tfm = obj.transforms.last, let text = obj.text else { return }

        context.saveGState()
        context.setFillColor(cgColor(argb: obj.backgroundColor))

        let outerPaddingBoth = (cells + 1) * outerPadding
        let bubbleWidthMax = (viewSize.width - outerPaddingBoth) / cells
        let bubbleHeight = (viewSize.height - outerPaddingBoth) / cells
        let x = CGFloat(obj.offsetX), y = CGFloat(obj.offsetY)

        context.concatenate(tfm.cgAffineTransform)

        // Port de `mTextWidth = fontPaint.measureText(element.getText())` — largeur du texte SUR
        // UNE SEULE LIGNE (pas encore wrappé), calculée AVANT `prepare()`, comme l'original.
        let bubbleElementWidth = textRect.measureWidth(text) + 40
        let bubbleWidth = min(bubbleElementWidth, bubbleWidthMax)

        let paddingBoth = bubblePadding * 2
        let textHeight = CGFloat(textRect.prepare(
            text: text,
            maxWidth: Int((bubbleWidth - paddingBoth).rounded(.down)),
            maxHeight: Int((bubbleHeight - paddingBoth).rounded(.down))
        ))

        let bound = CGRect(x: x, y: y, width: bubbleWidth, height: textHeight + paddingBoth)
        obj.bound = bound
        context.addPath(CGPath(roundedRect: bound, cornerWidth: bubblePadding, cornerHeight: bubblePadding, transform: nil))
        context.fillPath()
        textRect.draw(in: context, left: x + bubblePadding, top: y + bubblePadding)

        context.restoreGState()

        if obj.currentBitmap == nil {
            // Port de `bmpH = Math.max(1, h + element.getBound().height())` — `bound.height`
            // vaut DÉJÀ `textHeight + paddingBoth` (voir ci-dessus), donc cette formule
            // additionne `textHeight` une seconde fois : la bitmap "figée" est plus haute que
            // nécessaire. Reproduit tel quel (comportement Android observable, probablement non
            // intentionnel mais pas confirmé comme un bug par l'auteur original) — PAS "corrigé"
            // silencieusement, cohérent avec la politique de ce portage.
            let bmpW = max(1, bound.width)
            let bmpH = max(1, textHeight + bound.height)
            if let baked = renderBakedText(textRect: textRect, backgroundColor: obj.backgroundColor, width: bmpW, height: bmpH) {
                obj.width = bmpW
                obj.height = bmpH
                obj.addBitmap(baked)
            }
        }
    }

    private static func renderBakedText(textRect: TextRect, backgroundColor: UInt32, width: CGFloat, height: CGFloat) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(cgColor(argb: backgroundColor))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerWidth: bubblePadding, cornerHeight: bubblePadding, transform: nil))
        ctx.fillPath()
        textRect.draw(in: ctx, left: bubblePadding, top: bubblePadding)
        return ctx.makeImage()
    }

    // MARK: - STICKER

    /// Port de `drawShap` — le plus simple des types de calque : PAS de teinte/masque/feather/
    /// bulle, juste le bitmap courant dessiné à `offsetX`/`offsetY` avec la matrice du calque.
    /// `canvas.setMatrix(m)` (Android, REMPLACE tout le CTM) plutôt que `concat` — équivalent à
    /// `concatenate` ici puisqu'appelé juste après `saveGState()` sur un CTM de base supposé
    /// identité/vue, même hypothèse déjà posée pour `drawBitmapLastTransform`/`drawObjectFrame`.
    static func drawSticker(_ obj: AnimationObjectData, in context: CGContext) {
        guard let tfm = obj.transforms.last, let bmp = obj.currentBitmap else { return }
        context.saveGState()
        context.concatenate(tfm.cgAffineTransform)
        let offsetX = CGFloat(obj.offsetX), offsetY = CGFloat(obj.offsetY)
        obj.bound = CGRect(x: offsetX, y: offsetY, width: CGFloat(bmp.width), height: CGFloat(bmp.height))
        context.draw(bmp, in: CGRect(x: offsetX, y: offsetY, width: CGFloat(bmp.width), height: CGFloat(bmp.height)))
        context.restoreGState()
    }

    // MARK: - Résolution des propriétés visuelles (port du bloc commun aux deux méthodes)

    private static func resolveVisualProperties(
        _ obj: AnimationObjectData, transform tfm: Transform, currentNs: Int64, isSliderPreview: Bool
    ) -> (opacity: Float, color: UInt32, cornerRadius: Float, feather: Float) {
        if isSliderPreview {
            return (tfm.opacity, tfm.color, tfm.cornerRadius, tfm.feather)
        }
        let opTrack = obj.keyframeTrack(KeyframeTrack.PropertyName.opacity)
        let colTrack = obj.keyframeTrack(KeyframeTrack.PropertyName.color)
        let radTrack = obj.keyframeTrack(KeyframeTrack.PropertyName.cornerRadius)
        let featherTrack = obj.keyframeTrack(KeyframeTrack.PropertyName.feather)

        let opacity = (opTrack.map { !$0.isEmpty } ?? false) ? obj.interpolatedOpacity(at: currentNs) : tfm.opacity
        let color = (colTrack.map { !$0.isEmpty } ?? false) ? obj.interpolatedColor(at: currentNs) : tfm.color
        let cornerRadius = (radTrack.map { !$0.isEmpty } ?? false) ? obj.interpolatedCornerRadius(at: currentNs) : tfm.cornerRadius
        let feather = (featherTrack.map { !$0.isEmpty } ?? false) ? obj.interpolatedFeather(at: currentNs) : tfm.feather
        return (opacity, color, cornerRadius, feather)
    }

    /// Port de la décomposition de matrice de `drawBitmapLastTransform`/`drawObjectFrame` quand
    /// un `maskTransform` (capture automatique) est disponible : `MTRANS_X`/`MTRANS_Y` normalisés
    /// par la taille de la vue, `MSCALE_X`/`MSCALE_Y` moyennés, rotation extraite via
    /// `atan2(MSKEW_X, MSCALE_X)`. Reproduit tel quel — ordre des champs Android `Matrix.getValues()`
    /// documenté dans `Transform.swift`.
    private static func decomposeMaskTransform(
        _ maskTfm: Transform, fallbackGap: CGFloat, viewSize: CGSize
    ) -> (x: CGFloat, y: CGFloat, scale: CGFloat, gap: CGFloat, rotation: CGFloat) {
        let v = maskTfm.matrixValues
        guard v.count >= 6 else { return (0, 0, 1, fallbackGap, 0) }
        let w = viewSize.width > 0 ? viewSize.width : 1
        let h = viewSize.height > 0 ? viewSize.height : 1
        let offX = CGFloat(v[2]) / w
        let offY = CGFloat(v[5]) / h
        let scale = (abs(CGFloat(v[0])) + abs(CGFloat(v[4]))) / 2
        let rotation = atan2(CGFloat(v[1]), CGFloat(v[0])) * 180 / .pi
        return (offX, offY, scale, fallbackGap, rotation)
    }

    // MARK: - Composition (port du bloc commun paint/masque/clip)

    /// - Parameters:
    ///   - featherPx: rayon de flou EN POINTS déjà appliqué à `bmpToDraw` (0 si `!featherApplied`)
    ///     — port de `getFeatherMargin(featherPx) = ceil(featherPx)`, la marge ajoutée
    ///     symétriquement par `BitmapCacheManager.applyFeather`/`MaskFactory` autour de l'image.
    ///   - bubbleRadius: rayon de la bulle de fond à dessiner, `nil` = ne rien dessiner. Calculé
    ///     DIFFÉREMMENT par les deux appelants (voir commentaire de tête de fichier) — ce n'est
    ///     PAS simplement `cornerRadius`.
    private static func composite(
        _ bmpToDraw: CGImage, maskImage: CGImage?, featherApplied: Bool, featherPx: CGFloat,
        offsetX: CGFloat, offsetY: CGFloat, opacity: Float, color: UInt32,
        cornerRadius: CGFloat, bubbleRadius: CGFloat?, hasAppliedMask: Bool, bound: CGRect,
        in context: CGContext
    ) {
        let margin: CGFloat = featherApplied ? featherPx.rounded(.up) : 0
        let drawX = offsetX - margin
        let drawY = offsetY - margin
        let drawRect = CGRect(x: drawX, y: drawY, width: CGFloat(bmpToDraw.width), height: CGFloat(bmpToDraw.height))

        if !hasAppliedMask {
            if let bubbleRadius {
                let bubblePath = CGPath(
                    roundedRect: bound, cornerWidth: bubbleRadius, cornerHeight: bubbleRadius, transform: nil
                )
                context.addPath(bubblePath)
                context.setFillColor(UIColor(white: 1, alpha: 0x4D / 255.0).cgColor)
                context.fillPath()
            }
            if !featherApplied {
                let clipRect = CGRect(
                    x: offsetX, y: offsetY, width: CGFloat(bmpToDraw.width), height: CGFloat(bmpToDraw.height)
                )
                let clipPath = CGPath(
                    roundedRect: clipRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
                )
                context.addPath(clipPath)
                context.clip()
            }
        }

        // `opacity` doit s'appliquer UNE SEULE FOIS au résultat final (masqué+teinté), pas à
        // chaque couche de transparence imbriquée individuellement — `setAlpha` est "consommé"
        // par la couche EXTÉRIEURE (`beginTransparencyLayer`/`endTransparencyLayer` ci-dessous)
        // à sa fermeture ; remis à 1.0 juste après l'ouverture pour que la couche imbriquée de
        // `drawTinted` (teinte SRC_ATOP) ne réapplique pas la même opacité une seconde fois.
        context.saveGState()
        context.setAlpha(CGFloat(opacity))

        if hasAppliedMask, let maskImage {
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setAlpha(1)
            drawTinted(bmpToDraw, in: drawRect, color: color, context: context)
            context.setBlendMode(.destinationIn)
            context.draw(maskImage, in: drawRect)
            context.setBlendMode(.normal)
            context.endTransparencyLayer()
        } else {
            drawTinted(bmpToDraw, in: drawRect, color: color, context: context)
        }
        context.restoreGState()
    }

    /// Port de `kfPaint.setColorFilter(new PorterDuffColorFilter(color, PorterDuff.Mode.SRC_ATOP))`
    /// — teinte le bitmap dessiné par la couleur ARGB donnée, PROPORTIONNELLEMENT à l'alpha de
    /// cette couleur (alpha bas = teinte subtile, alpha 1.0 = remplacement total des RGB, silhouette
    /// de l'image conservée). Reproduit via une couche de transparence (`beginTransparencyLayer`)
    /// + remplissage `.sourceAtop` : la couche isole le bitmap comme "destination" pour l'opération
    /// atop, exact analogue Core Graphics d'un `ColorFilter` appliqué à un seul `drawBitmap`.
    private static func drawTinted(_ image: CGImage, in rect: CGRect, color: UInt32, context: CGContext) {
        if color == 0 {
            context.draw(image, in: rect)
            return
        }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.draw(image, in: rect)
        context.setBlendMode(.sourceAtop)
        context.setFillColor(cgColor(argb: color))
        context.fill(rect)
        context.setBlendMode(.normal)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Non-`private` : réutilisé par `AnimemesExporter` (couleur de fond de l'export) — même
    /// conversion ARGB→`CGColor` qu'ailleurs dans ce module, pas dupliquée une troisième fois.
    static func cgColor(argb: UInt32) -> CGColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255
        let r = CGFloat((argb >> 16) & 0xFF) / 255
        let g = CGFloat((argb >> 8) & 0xFF) / 255
        let b = CGFloat(argb & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: a).cgColor
    }
}

private extension AnimationObjectData {
    /// Nombre de `maskTransforms` — pas de propriété `count` publique directe sur
    /// `maskTransforms` dans `AnimationObjectData` (accès via `maskTransform(at:)` uniquement),
    /// ajouté ici pour la lisibilité du site d'appel.
    var maskTransformsCount: Int { maskTransforms.count }
}
