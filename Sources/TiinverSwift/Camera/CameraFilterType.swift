import MetalPetal

/// Port de `editor/filter/FilterType.java` (enum Android à 43 valeurs).
///
/// ⚠️ **Comportement Android reproduit fidèlement, pas corrigé** : dans `FilterType.
/// createGlFilter(FilterType, Context)`, seuls les 23 premiers `case` du `switch` (jusqu'à et y
/// compris `VIGNETTE`) sont du code réellement compilé — TOUS les cas suivants (`DEFAULT`,
/// `BILATERAL_BLUR`, `BOX_BLUR`, `CGA_COLORSPACE`, `CROSSHATCH`, `GAUSSIAN_FILTER`, `HALFTONE`,
/// `INVERT`, `LOOK_UP_TABLE_SAMPLE`, `LUMINANCE_THRESHOLD`, `OVERLAY`, `SOLARIZE`,
/// `SPHERE_REFRACTION`, `SWIRL`, `TONE_CURVE_SAMPLE`, `WATERMARK`, `WEAK_PIXEL`,
/// `WHITE_BALANCE`, `ZOOM_BLUR`, `BITMAP_OVERLAY_SAMPLE`) sont à l'intérieur d'un bloc de
/// commentaire Java `/* ... */` (voir `FilterType.java` lignes ~158-219) — le `switch` tombe donc
/// systématiquement sur `default: return new GlMonochromeFilter();` pour ces 20 valeurs. Ce n'est
/// pas un oubli de portage : le carrousel de filtres (`BaseCameraFragment.touchListener`, swipe
/// gauche/droite) fait défiler les 43 valeurs de l'enum, mais 20 d'entre elles affichent
/// silencieusement Monochrome côté Android en production. Reproduit ici à l'identique.
enum CameraFilterType: Int, CaseIterable {
    case beautyFilter
    case defaultFilter
    case bilateralBlur
    case boxBlur
    case brightness
    case bulgeDistortion
    case cgaColorspace
    case contrast
    case crosshatch
    case exposure
    case filterGroupSample
    case gamma
    case gaussianFilter
    case grayScale
    case halftone
    case haze
    case highlightShadow
    case hue
    case invert
    case lookUpTableSample
    case luminance
    case luminanceThreshold
    case monochrome
    case opacity
    case overlay
    case pixelation
    case posterize
    case rgb
    case saturation
    case sepia
    case sharp
    case solarize
    case sphereRefraction
    case swirl
    case toneCurveSample
    case tone
    case vibrance
    case vignette
    case watermark
    case weakPixel
    case whiteBalance
    case zoomBlur
    case bitmapOverlaySample

    /// Port de `FilterType.createGlFilter`. Renvoie une closure plutôt qu'un objet filtre unique
    /// pour couvrir aussi bien le cas simple (un seul `MTIUnaryImageRenderingFilter`) que
    /// `FILTER_GROUP_SAMPLE` (chaîne Sepia → Vignette, port de `GlFilterGroup`).
    func makeFilter() -> (MTIImage) -> MTIImage {
        switch self {
        case .beautyFilter:
            let f = TiinverBeautyFilter()
            return { f.applied(to: $0) }
        case .brightness:
            let f = TiinverBrightnessFilter()
            f.brightness = 0.2
            return { f.applied(to: $0) }
        case .bulgeDistortion:
            let f = TiinverBulgeDistortionFilter()
            return { f.applied(to: $0) }
        case .contrast:
            let f = TiinverContrastFilter()
            f.contrast = 2.5
            return { f.applied(to: $0) }
        case .exposure:
            let f = TiinverExposureFilter()
            return { f.applied(to: $0) }
        case .filterGroupSample:
            let sepia = TiinverSepiaFilter()
            let vignette = TiinverVignetteFilter()
            return { vignette.applied(to: sepia.applied(to: $0)) }
        case .gamma:
            let f = TiinverGammaFilter()
            f.gamma = 2
            return { f.applied(to: $0) }
        case .grayScale:
            let f = TiinverGrayScaleFilter()
            return { f.applied(to: $0) }
        case .haze:
            let f = TiinverHazeFilter()
            f.slope = -0.5
            return { f.applied(to: $0) }
        case .highlightShadow:
            let f = TiinverHighlightShadowFilter()
            return { f.applied(to: $0) }
        case .hue:
            let f = TiinverHueFilter()
            return { f.applied(to: $0) }
        case .luminance:
            let f = TiinverLuminanceFilter()
            return { f.applied(to: $0) }
        case .monochrome:
            let f = TiinverMonochromeFilter()
            return { f.applied(to: $0) }
        case .opacity:
            let f = TiinverOpacityFilter()
            return { f.applied(to: $0) }
        case .pixelation:
            let f = TiinverPixelationFilter()
            return { f.applied(to: $0) }
        case .posterize:
            let f = TiinverPosterizeFilter()
            return { f.applied(to: $0) }
        case .rgb:
            let f = TiinverRGBFilter()
            f.red = 0
            return { f.applied(to: $0) }
        case .saturation:
            let f = TiinverSaturationFilter()
            return { f.applied(to: $0) }
        case .sepia:
            let f = TiinverSepiaFilter()
            return { f.applied(to: $0) }
        case .sharp:
            let f = TiinverSharpenFilter()
            f.sharpness = 4
            return { f.applied(to: $0) }
        case .tone:
            let f = TiinverToneFilter()
            return { f.applied(to: $0) }
        case .vibrance:
            let f = TiinverVibranceFilter()
            f.vibrance = 3
            return { f.applied(to: $0) }
        case .vignette:
            let f = TiinverVignetteFilter()
            return { f.applied(to: $0) }
        default:
            // Voir commentaire de tête de fichier : les 20 valeurs restantes tombent sur ce
            // repli Monochrome côté Android réel (code mort commenté, jamais exécuté).
            let f = TiinverMonochromeFilter()
            return { f.applied(to: $0) }
        }
    }
}

extension MTIUnaryImageRenderingFilter {
    /// Équivalent de `GlFilter.draw(texName, fbo)` — applique CE filtre à une image d'entrée et
    /// renvoie l'image transformée. `outputImage` est nil uniquement si `inputImage` ne l'a pas
    /// été (voir `MTIUnaryImageRenderingFilter.outputImage`, vérifié dans le `.m` réel du SDK) —
    /// ne peut donc pas arriver ici puisqu'on vient de l'assigner.
    func applied(to image: MTIImage) -> MTIImage {
        inputImage = image
        return outputImage ?? image
    }
}
