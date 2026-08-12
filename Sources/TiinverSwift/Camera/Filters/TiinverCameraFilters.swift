import MetalPetal

/// Port des ~22 sous-classes `Gl*Filter extends GlFilter` réellement atteignables (voir
/// `CameraFilterType.swift`) vers le pattern `MTIUnaryImageRenderingFilter` de MetalPetal.
///
/// Chaque filtre custom MetalPetal nécessite sa PROPRE sous-classe (pas un seul type paramétré) :
/// `fragmentFunctionDescriptor` est une méthode de CLASSE (`+`), résolue par dispatch de classe —
/// c'est exactement le pattern que MetalPetal utilise lui-même en interne pour ses filtres
/// intégrés (`MTIBrightnessFilter`, `MTIContrastFilter`, etc., vérifiés directement dans
/// `MTIColorMatrixFilter.h/.m` du SDK réel avant d'écrire ce fichier). Reproduit ici avec un
/// nombre de sous-classes équivalent au nombre de sous-classes `Gl*Filter` Android d'origine.
///
/// Les noms de fonction (`tiinverBrightness`, etc.) correspondent exactement aux fonctions
/// `fragment` définies dans `TiinverCameraShaders.metal`.

// MARK: - Brightness (brightness = 0.2 par défaut, FilterType.BRIGHTNESS)
final class TiinverBrightnessFilter: MTIUnaryImageRenderingFilter {
    var brightness: Float = 0

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverBrightness")
    }

    override var parameters: [String: Any] {
        ["brightness": brightness]
    }
}

// MARK: - Contrast (contrast = 2.5 par défaut, FilterType.CONTRAST)
final class TiinverContrastFilter: MTIUnaryImageRenderingFilter {
    var contrast: Float = 1.2

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverContrast")
    }

    override var parameters: [String: Any] {
        ["contrast": contrast]
    }
}

// MARK: - Saturation (saturation = 1.0 par défaut = no-op, reproduit tel quel — Android n'appelle
// jamais setSaturation depuis FilterType.SATURATION)
final class TiinverSaturationFilter: MTIUnaryImageRenderingFilter {
    var saturation: Float = 1

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverSaturation")
    }

    override var parameters: [String: Any] {
        ["saturation": saturation]
    }
}

// MARK: - GrayScale (aucun uniform)
final class TiinverGrayScaleFilter: MTIUnaryImageRenderingFilter {
    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverGrayScale")
    }
}

// MARK: - Sepia (aucun uniform)
final class TiinverSepiaFilter: MTIUnaryImageRenderingFilter {
    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverSepia")
    }
}

// MARK: - Vignette (vignetteStart = 0.2, vignetteEnd = 0.85, center = (0.5, 0.5) — tous par défaut)
final class TiinverVignetteFilter: MTIUnaryImageRenderingFilter {
    var vignetteCenter = SIMD2<Float>(0.5, 0.5)
    var vignetteStart: Float = 0.2
    var vignetteEnd: Float = 0.85

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverVignette")
    }

    override var parameters: [String: Any] {
        [
            "vignetteCenter": MTIVector(value: vignetteCenter),
            "vignetteStart": vignetteStart,
            "vignetteEnd": vignetteEnd,
        ]
    }
}

// MARK: - Gamma (gamma = 2.0 par défaut, FilterType.GAMMA)
final class TiinverGammaFilter: MTIUnaryImageRenderingFilter {
    var gamma: Float = 1.2

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverGamma")
    }

    override var parameters: [String: Any] {
        ["gamma": gamma]
    }
}

// MARK: - Monochrome (intensity = 1.0 par défaut). Sert AUSSI de filtre de repli pour tous les cas
// de `CameraFilterType` dont le branchement Android réel est du code MORT (commenté dans
// `FilterType.java`, jamais exécuté) — voir `CameraFilterType.makeFilter()`.
final class TiinverMonochromeFilter: MTIUnaryImageRenderingFilter {
    var intensity: Float = 1

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverMonochrome")
    }

    override var parameters: [String: Any] {
        ["intensity": intensity]
    }
}

// MARK: - Opacity (opacity = 1.0 par défaut = no-op)
final class TiinverOpacityFilter: MTIUnaryImageRenderingFilter {
    var opacity: Float = 1

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverOpacity")
    }

    override var parameters: [String: Any] {
        ["opacity": opacity]
    }
}

// MARK: - Posterize (colorLevels = 10 par défaut)
final class TiinverPosterizeFilter: MTIUnaryImageRenderingFilter {
    var colorLevels: Float = 10

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverPosterize")
    }

    override var parameters: [String: Any] {
        ["colorLevels": colorLevels]
    }
}

// MARK: - RGB (red = 0.0, green = 1.0, blue = 1.0 par défaut — FilterType.RGB ne règle que `red`)
final class TiinverRGBFilter: MTIUnaryImageRenderingFilter {
    var red: Float = 1
    var green: Float = 1
    var blue: Float = 1

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverRGB")
    }

    override var parameters: [String: Any] {
        ["red": red, "green": green, "blue": blue]
    }
}

// MARK: - Hue (hue = 90.0 par défaut — ⚠️ bug d'unité Android reproduit tel quel, voir
// TiinverCameraShaders.metal)
final class TiinverHueFilter: MTIUnaryImageRenderingFilter {
    var hue: Float = 90

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverHue")
    }

    override var parameters: [String: Any] {
        ["hueAdjust": hue]
    }
}

// MARK: - Exposure (exposure = 1.0 par défaut, non modifié par FilterType.EXPOSURE)
final class TiinverExposureFilter: MTIUnaryImageRenderingFilter {
    var exposure: Float = 1

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverExposure")
    }

    override var parameters: [String: Any] {
        ["exposure": exposure]
    }
}

// MARK: - Luminance (aucun uniform)
final class TiinverLuminanceFilter: MTIUnaryImageRenderingFilter {
    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverLuminance")
    }
}

// MARK: - Haze (distance = 0.2, slope = -0.5 — FilterType.HAZE ne règle que `slope`)
final class TiinverHazeFilter: MTIUnaryImageRenderingFilter {
    var hazeDistance: Float = 0.2
    var slope: Float = 0

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverHaze")
    }

    override var parameters: [String: Any] {
        ["hazeDistance": hazeDistance, "slope": slope]
    }
}

// MARK: - HighlightShadow (shadows = 1.0, highlights = 0.0 par défaut, non modifiés)
final class TiinverHighlightShadowFilter: MTIUnaryImageRenderingFilter {
    var shadows: Float = 1
    var highlights: Float = 0

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverHighlightShadow")
    }

    override var parameters: [String: Any] {
        ["shadows": shadows, "highlights": highlights]
    }
}

// MARK: - Pixelation (pixel = 1.0 par défaut — quasi no-op, non modifié)
final class TiinverPixelationFilter: MTIUnaryImageRenderingFilter {
    var pixel: Float = 1

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverPixelation")
    }

    override var parameters: [String: Any] {
        ["pixel": pixel]
    }
}

// MARK: - BulgeDistortion (center = (0.5,0.5), radius = 0.25, scale = 0.5)
final class TiinverBulgeDistortionFilter: MTIUnaryImageRenderingFilter {
    var center = SIMD2<Float>(0.5, 0.5)
    var radius: Float = 0.25
    var scale: Float = 0.5

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverBulgeDistortion")
    }

    override var parameters: [String: Any] {
        ["center": MTIVector(value: center), "radius": radius, "scale": scale]
    }
}

// MARK: - Sharpen (sharpness = 4.0 — FilterType.SHARP)
final class TiinverSharpenFilter: MTIUnaryImageRenderingFilter {
    var sharpness: Float = 1

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverSharpen")
    }

    override var parameters: [String: Any] {
        ["sharpness": sharpness]
    }
}

// MARK: - Tone (threshold = 0.2, quantizationLevels = 10.0, non modifiés)
final class TiinverToneFilter: MTIUnaryImageRenderingFilter {
    var threshold: Float = 0.2
    var quantizationLevels: Float = 10

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverTone")
    }

    override var parameters: [String: Any] {
        ["threshold": threshold, "quantizationLevels": quantizationLevels]
    }
}

// MARK: - Vibrance (vibrance = 3.0 — FilterType.VIBRANCE)
final class TiinverVibranceFilter: MTIUnaryImageRenderingFilter {
    var vibrance: Float = 0

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverVibrance")
    }

    override var parameters: [String: Any] {
        ["vibrance": vibrance]
    }
}

// MARK: - BeautyFilter (smoothingIntensity = 0.8, blurSize = 2.5, brightnessBoost = 0.3,
// saturation = 1.3 — aucun réglage par défaut n'est modifié par FilterType.BEAUTY_FILTER)
final class TiinverBeautyFilter: MTIUnaryImageRenderingFilter {
    var smoothingIntensity: Float = 0.8
    var blurSize: Float = 2.5
    var brightnessBoost: Float = 0.3
    var saturation: Float = 1.3

    override class func fragmentFunctionDescriptor() -> MTIFunctionDescriptor {
        MTIFunctionDescriptor(name: "tiinverBeauty")
    }

    override var parameters: [String: Any] {
        [
            "smoothingIntensity": smoothingIntensity,
            "blurSize": blurSize,
            "brightnessBoost": brightnessBoost,
            "saturation": saturation,
        ]
    }
}
