import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Port de `Utils/RemoveBackground.java` (module 9, Éditeur photo simple — voir aussi la mention
/// de ce même fichier au module 8, `AnimemesCompound.java` section "REMOVE BACKGROUND", jamais lue
/// en détail à l'époque : c'est le même fichier, partagé entre les deux éditeurs — `RemoveBackground`
/// est catégorie "A+G" du rapport `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`, importé à la fois par
/// `AnimemesCompound.java` et `CroperView.java`).
///
/// **Décision d'architecture (vérifiée, pas devinée)** : `removeBackgroundWithMLKit` (Android)
/// appelle `SubjectSegmenter` de Google ML Kit (segmentation de sujet GÉNÉRALE — personnes, objets,
/// animaux) via réflexion. Le rapport `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.3 recommande le
/// framework Vision d'Apple en remplacement. Deux candidats Vision vérifiés contre la documentation
/// Apple réelle avant de choisir (WebSearch, pas deviné) :
/// - `VNGenerateForegroundInstanceMaskRequest` (segmentation de sujet GÉNÉRALE, l'équivalent le
///   plus proche de `SubjectSegmenter`) — confirmé **iOS 17+ uniquement**, et confirmé NE
///   FONCTIONNE PAS dans le simulateur (device réel requis, pas de CPU fallback). Incompatible
///   avec `deploymentTarget.iOS = "16.0"` de ce projet (`project.yml`, décidé au module 1) —
///   changer la cible de déploiement pour une seule fonctionnalité est une décision produit qui
///   dépasse ce portage, pas prise unilatéralement ici (même principe que la décision différée
///   `ScrollView`/`.scrollTargetBehavior(.paging)` du module 6).
/// - `VNGeneratePersonSegmentationRequest` — confirmé **iOS 15+** (compatible avec la cible
///   actuelle), mais segmente UNIQUEMENT les personnes (pas un sujet général comme un objet/animal
///   posé sur un fond uni) — écart fonctionnel réel vs `SubjectSegmenter`, documenté ici, pas
///   masqué.
/// **Choix retenu** : `VNGeneratePersonSegmentationRequest` comme chemin principal (compatible
/// iOS 16), `removeBackgroundAdvanced` (ci-dessous, port fidèle de l'algorithme Android, agnostique
/// au sujet) comme repli — reproduit la même structure à deux niveaux que l'original Android
/// (`removeBackgroundWithMLKit` → `removeBackgroundAdvanced` en cas d'échec), avec le premier étage
/// remplacé par une API différente pour la raison ci-dessus. **Point à documenter pour l'utilisateur
/// produit** : passer à `VNGenerateForegroundInstanceMaskRequest` (sujets non-humains) nécessiterait
/// de relever `deploymentTarget.iOS` à 17.0 — décision à prendre séparément, pas ici.
enum RemoveBackground {
    /// Port de `removeBackgroundWithMLKit` — segmentation de personne via Vision. `nil` si aucune
    /// personne n'est détectée dans l'image (équivalent du `cb.onError(...)` Android, l'appelant
    /// doit alors retomber sur `removeBackgroundAdvanced`, comme `CroperView.handleRemoveBackground`
    /// le fait déjà côté Android).
    ///
    /// Vérifié contre la documentation Apple réelle (pas deviné) : `qualityLevel`/
    /// `outputPixelFormat` sont des propriétés réelles de `VNGeneratePersonSegmentationRequest`
    /// (`.accurate` = plus précis mais plus lent, adapté à une image statique unique comme ici,
    /// contrairement à `.fast` recommandé pour de la vidéo) ; `kCVPixelFormatType_OneComponent8`
    /// produit un masque niveaux de gris 8-bit, direct pour `CIBlendWithMask`. Masque : blanc =
    /// sujet (personne) conservé, noir = arrière-plan (transparent) — polarité confirmée par
    /// documentation/exemples Apple, pas supposée.
    static func removeBackgroundWithVision(_ image: CGImage) -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let mask = request.results?.first else { return nil }

        let ciImage = CIImage(cgImage: image)
        var maskImage = CIImage(cvPixelBuffer: mask.pixelBuffer)
        // Port de `getForegroundBitmap()` — le masque Vision est produit à la résolution du
        // modèle, pas forcément celle de l'image source ; mis à l'échelle avant le blend comme
        // `CIBlendWithMask` l'exige (dimensions identiques attendues entre `inputImage` et
        // `maskImage`).
        let scaleX = ciImage.extent.width / maskImage.extent.width
        let scaleY = ciImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(ciImage, forKey: kCIInputImageKey)
        blend.setValue(maskImage, forKey: kCIInputMaskImageKey)
        blend.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        guard let output = blend.outputImage else { return nil }

        let context = CIContext()
        return context.createCGImage(output, from: ciImage.extent)
    }

    /// Port de `removeBackgroundAdvanced` — repli géométrique sans détection de sujet : échantillonne
    /// la couleur de fond sur les 4 bordures (bandes de `BORDER` px), puis rend transparent tout pixel
    /// dont la distance perceptuelle (pondération luminance 0.299R/0.587G/0.114B, identique à
    /// l'original) à cette couleur de fond est sous un seuil, avec une rampe alpha lissée (pas
    /// binaire) sur une bande de transition — reproduit les constantes Android à l'identique
    /// (`TOLERANCE = 55`, `SOFT_BAND = 25`, `BORDER = clamp(min(W,H)/15, 2, 20)`).
    static func removeBackgroundAdvanced(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, var pixels = pixelData(of: image) else { return nil }

        let border = max(2, min(20, min(w, h) / 15))
        let tolerance: Float = 55
        let softBand: Float = 25

        // ── 1. Échantillonnage des bordures ─────────────────────────────
        var sumR = 0, sumG = 0, sumB = 0, count = 0
        func accumulate(_ x: Int, _ y: Int) {
            let i = (y * w + x) * 4
            sumR += Int(pixels[i]); sumG += Int(pixels[i + 1]); sumB += Int(pixels[i + 2])
            count += 1
        }
        for x in 0..<w {
            for y in 0..<border { accumulate(x, y) }
            for y in max(0, h - border)..<h { accumulate(x, y) }
        }
        for y in border..<max(border, h - border) {
            for x in 0..<border { accumulate(x, y) }
            for x in max(0, w - border)..<w { accumulate(x, y) }
        }
        guard count > 0 else { return nil }
        let bgR = Float(sumR / count), bgG = Float(sumG / count), bgB = Float(sumB / count)

        // ── 2. Masque alpha avec rampe lissée ────────────────────────────
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[i]), g = Float(pixels[i + 1]), b = Float(pixels[i + 2])
            let dr = abs(r - bgR), dg = abs(g - bgG), db = abs(b - bgB)
            let dist = dr * 0.299 + dg * 0.587 + db * 0.114

            let originalAlpha = pixels[i + 3]
            let newAlpha: UInt8
            if dist < tolerance - softBand {
                newAlpha = 0
            } else if dist > tolerance {
                newAlpha = originalAlpha
            } else {
                let t = (dist - (tolerance - softBand)) / softBand
                newAlpha = UInt8(Float(originalAlpha) * t * t)
            }
            pixels[i + 3] = newAlpha
        }

        // ── 3. Affinement des bords (1 passe d'érosion 3×3), sur le MÊME buffer ─
        // Port de `applyEdgeRefinement` — appliqué ici directement sur `pixels` (pas de
        // round-trip via un `CGImage` intermédiaire, qui aurait forcé une pré-multiplication par
        // le nouvel alpha à la relecture et corrompu les octets RGB des pixels de bordure
        // fraîchement rendus semi-transparents par l'étape 2 ci-dessus — un seul encodage final en
        // `CGImage` straight-alpha, à la toute fin).
        if w > 2, h > 2 {
            let alphaBefore = pixels
            func alpha(_ x: Int, _ y: Int) -> UInt8 { alphaBefore[(y * w + x) * 4 + 3] }
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) {
                    let a = alpha(x, y)
                    if a == 0 || a == 255 { continue }
                    let minNeighbour = min(alpha(x, y - 1), alpha(x, y + 1), alpha(x - 1, y), alpha(x + 1, y))
                    if minNeighbour < 30 {
                        pixels[(y * w + x) * 4 + 3] = UInt8(Float(a) * 0.6)
                    }
                }
            }
        }

        // `Self.` requis : le paramètre `image: CGImage` de cette fonction masque le nom de la
        // méthode statique `image(fromRGBAPixels:width:height:)` dans cette portée (Checkpoint 3 —
        // "cannot call value of non-function type 'CGImage'", l'appel sans préfixe résolvait vers
        // le paramètre local, pas la méthode).
        return Self.image(fromRGBAPixels: pixels, width: w, height: h)
    }

    // MARK: - Helpers pixels bruts

    /// Lecture RGBA8 straight-alpha (canaux indépendants, comme `android.graphics.Color`). Le
    /// dessin passe par un contexte `.premultipliedLast` (seul format qu'un `CGContext` accepte en
    /// écriture pour RGBA) — sans perte pour l'entrée réelle de cette fonction : une photo tout
    /// juste recadrée est TOUJOURS totalement opaque (alpha=255 partout), et à alpha=255 la
    /// pré-multiplication est un no-op (`RGB × 255/255 = RGB`). Utilisée UNIQUEMENT pour la lecture
    /// initiale de `removeBackgroundAdvanced` — l'affinement des bords qui suit opère directement
    /// sur ce même buffer `[UInt8]` sans repasser par cette fonction (voir sa note dédiée).
    private static func pixelData(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }

    /// Reconstruit un `CGImage` STRAIGHT-alpha (PAS pré-multiplié) directement depuis les octets —
    /// via `CGImage.init(...)`/`CGDataProvider` plutôt qu'un `CGContext.makeImage()` : un
    /// `CGContext` ne peut être créé qu'en pré-multiplié, ce qui aurait exigé de pré-multiplier RGB
    /// par le nouvel alpha (souvent 0) avant écriture pour rester cohérent — `CGImage` (donnée pure,
    /// jamais dessiné DANS) accepte directement `.last` (straight alpha), évitant cette étape et
    /// préservant exactement les octets RGB calculés ci-dessus quel que soit le nouvel alpha.
    private static func image(fromRGBAPixels pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
