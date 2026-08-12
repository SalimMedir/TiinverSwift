//
//  TiinverCameraShaders.metal
//  Port pixel-par-pixel des 22 filtres GLSL réellement atteignables depuis
//  `editor/filter/FilterType.createGlFilter` (voir `engine/.../gpuv/egl/filter/Gl*.java`),
//  vers Metal Shading Language pour MetalPetal (`MTIUnaryImageRenderingFilter`).
//
//  Convention vérifiée directement dans les sources réelles de MetalPetal 1.10.0
//  (`Frameworks/MetalPetal/Shaders/Shaders.metal`, ex. la fonction `bulgeDistortion`) :
//  chaque fonction fragment reçoit `VertexOut vertexIn [[stage_in]]` (struct MetalPetal,
//  champ `textureCoordinate`), la texture source sur `[[texture(0)]]`/`[[sampler(0)]]`, et les
//  uniforms scalaires/vecteurs en `constant T & [[buffer(N)]]` dans l'ORDRE où ils apparaissent
//  dans le dictionnaire `parameters` Swift correspondant (voir `TiinverCameraFilters.swift`) —
//  ces fonctions ne sont PAS dans le namespace `metalpetal` (réservé aux shaders internes du
//  framework), une fonction globale suffit pour un filtre custom.
//
//  Les filtres Android qui calculaient les coordonnées de texels voisins dans le VERTEX shader
//  (`GlSharpenFilter`, `GlThreex3TextureSamplingFilter`/`GlToneFilter`, `BeautyFilter`) les
//  recalculent ici directement dans le FRAGMENT shader à partir de `sourceTexture.get_width()/
//  get_height()` — résultat mathématiquement identique sur un quad plein écran (l'offset est une
//  constante additive, l'interpolation bilinéaire d'un varying `centre + offset` équivaut à
//  `centre interpolé + offset` calculé par fragment), pas une approximation.

#include <metal_stdlib>
using namespace metal;

struct TCVertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
};

// MARK: - GlBrightnessFilter (brightness = 0.2 par défaut, FilterType.BRIGHTNESS)
fragment float4 tiinverBrightness(TCVertexOut vertexIn [[stage_in]],
                                   texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                   sampler sourceSampler [[sampler(0)]],
                                   constant float &brightness [[buffer(0)]]) {
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    return float4(c.rgb + float3(brightness), c.a);
}

// MARK: - GlContrastFilter (contrast = 2.5 par défaut, FilterType.CONTRAST)
fragment float4 tiinverContrast(TCVertexOut vertexIn [[stage_in]],
                                 texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                 sampler sourceSampler [[sampler(0)]],
                                 constant float &contrast [[buffer(0)]]) {
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    return float4((c.rgb - float3(0.5)) * contrast + float3(0.5), c.a);
}

// MARK: - GlSaturationFilter (saturation = 1.0 par défaut = no-op, comportement Android reproduit tel quel)
fragment float4 tiinverSaturation(TCVertexOut vertexIn [[stage_in]],
                                   texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                   sampler sourceSampler [[sampler(0)]],
                                   constant float &saturation [[buffer(0)]]) {
    constexpr float3 luminanceWeighting = float3(0.2125, 0.7154, 0.0721);
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    float luminance = dot(c.rgb, luminanceWeighting);
    float3 grey = float3(luminance);
    return float4(mix(grey, c.rgb, saturation), c.a);
}

// MARK: - GlGrayScaleFilter (aucun uniform)
fragment float4 tiinverGrayScale(TCVertexOut vertexIn [[stage_in]],
                                  texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                  sampler sourceSampler [[sampler(0)]]) {
    constexpr float3 weight = float3(0.2125, 0.7154, 0.0721);
    float luminance = dot(sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate).rgb, weight);
    return float4(float3(luminance), 1.0);
}

// MARK: - GlSepiaFilter (aucun uniform — matrice fixe, alpha forcé à 1 comme l'original : gl_FragColor.a jamais assigné)
fragment float4 tiinverSepia(TCVertexOut vertexIn [[stage_in]],
                              texture2d<float, access::sample> sourceTexture [[texture(0)]],
                              sampler sourceSampler [[sampler(0)]]) {
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    float r = dot(c.rgb, float3(.393, .769, .189));
    float g = dot(c.rgb, float3(.349, .686, .168));
    float b = dot(c.rgb, float3(.272, .534, .131));
    return float4(r, g, b, 1.0);
}

// MARK: - GlVignetteFilter (vignetteStart = 0.2, vignetteEnd = 0.85, center = (0.5, 0.5) — tous par défaut)
fragment float4 tiinverVignette(TCVertexOut vertexIn [[stage_in]],
                                 texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                 sampler sourceSampler [[sampler(0)]],
                                 constant float2 &vignetteCenter [[buffer(0)]],
                                 constant float &vignetteStart [[buffer(1)]],
                                 constant float &vignetteEnd [[buffer(2)]]) {
    float3 rgb = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate).rgb;
    float d = distance(vertexIn.textureCoordinate, vignetteCenter);
    float percent = smoothstep(vignetteStart, vignetteEnd, d);
    return float4(mix(rgb, float3(0.0), percent), 1.0);
}

// MARK: - GlGammaFilter (gamma = 2.0 par défaut, FilterType.GAMMA)
fragment float4 tiinverGamma(TCVertexOut vertexIn [[stage_in]],
                              texture2d<float, access::sample> sourceTexture [[texture(0)]],
                              sampler sourceSampler [[sampler(0)]],
                              constant float &gamma [[buffer(0)]]) {
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    return float4(pow(max(c.rgb, float3(0.0)), float3(gamma)), c.a);
}

// MARK: - GlMonochromeFilter (intensity = 1.0 par défaut ; c'est aussi le filtre de repli — voir
// CameraFilterType.swift — pour tous les cas de l'enum Android dont le code de branchement réel
// est commenté dans FilterType.java, donc jamais atteint : reproduit tel quel, pas "corrigé")
fragment float4 tiinverMonochrome(TCVertexOut vertexIn [[stage_in]],
                                   texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                   sampler sourceSampler [[sampler(0)]],
                                   constant float &intensity [[buffer(0)]]) {
    constexpr float3 luminanceWeighting = float3(0.2125, 0.7154, 0.0721);
    float4 textureColor = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    float luminance = dot(textureColor.rgb, luminanceWeighting);
    float4 desat = float4(float3(luminance), 1.0);
    float4 outputColor = float4(
        desat.r < 0.5 ? (2.0 * desat.r * 0.6) : (1.0 - 2.0 * (1.0 - desat.r) * (1.0 - 0.6)),
        desat.g < 0.5 ? (2.0 * desat.g * 0.45) : (1.0 - 2.0 * (1.0 - desat.g) * (1.0 - 0.45)),
        desat.b < 0.5 ? (2.0 * desat.b * 0.3) : (1.0 - 2.0 * (1.0 - desat.b) * (1.0 - 0.3)),
        1.0
    );
    return float4(mix(textureColor.rgb, outputColor.rgb, intensity), textureColor.a);
}

// MARK: - GlOpacityFilter (opacity = 1.0 par défaut = no-op)
fragment float4 tiinverOpacity(TCVertexOut vertexIn [[stage_in]],
                                texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                sampler sourceSampler [[sampler(0)]],
                                constant float &opacity [[buffer(0)]]) {
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    return float4(c.rgb, c.a * opacity);
}

// MARK: - GlPosterizeFilter (colorLevels = 10 par défaut)
fragment float4 tiinverPosterize(TCVertexOut vertexIn [[stage_in]],
                                  texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                  sampler sourceSampler [[sampler(0)]],
                                  constant float &colorLevels [[buffer(0)]]) {
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    return floor((c * colorLevels) + float4(0.5)) / colorLevels;
}

// MARK: - GlRGBFilter (red = 0.0, green = 1.0, blue = 1.0 par défaut — FilterType.RGB ne règle que `red`)
fragment float4 tiinverRGB(TCVertexOut vertexIn [[stage_in]],
                            texture2d<float, access::sample> sourceTexture [[texture(0)]],
                            sampler sourceSampler [[sampler(0)]],
                            constant float &red [[buffer(0)]],
                            constant float &green [[buffer(1)]],
                            constant float &blue [[buffer(2)]]) {
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    return float4(c.r * red, c.g * green, c.b * blue, 1.0);
}

// MARK: - GlHueFilter (hue = 90.0 par défaut — ⚠️ BUG ANDROID REPRODUIT TEL QUEL : le commentaire
// Java indique une plage 0-360 (degrés) mais le shader original ajoute `hueAdjust` DIRECTEMENT à
// une valeur d'angle en RADIANS (`atan(Q,I)`) sans conversion — un défaut hérité du GLSL source,
// pas une erreur de portage. `atan(Q,I)` GLSL 2-arguments = `atan2(Q,I)` en MSL (nom différent,
// même sémantique).
fragment float4 tiinverHue(TCVertexOut vertexIn [[stage_in]],
                            texture2d<float, access::sample> sourceTexture [[texture(0)]],
                            sampler sourceSampler [[sampler(0)]],
                            constant float &hueAdjust [[buffer(0)]]) {
    constexpr float4 kRGBToYPrime = float4(0.299, 0.587, 0.114, 0.0);
    constexpr float4 kRGBToI = float4(0.595716, -0.274453, -0.321263, 0.0);
    constexpr float4 kRGBToQ = float4(0.211456, -0.522591, 0.31135, 0.0);
    constexpr float4 kYIQToR = float4(1.0, 0.9563, 0.6210, 0.0);
    constexpr float4 kYIQToG = float4(1.0, -0.2721, -0.6474, 0.0);
    constexpr float4 kYIQToB = float4(1.0, -1.1070, 1.7046, 0.0);

    float4 color = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    float YPrime = dot(color, kRGBToYPrime);
    float I = dot(color, kRGBToI);
    float Q = dot(color, kRGBToQ);

    float hue = atan2(Q, I);
    float chroma = sqrt(I * I + Q * Q);

    hue += (-hueAdjust);

    Q = chroma * sin(hue);
    I = chroma * cos(hue);

    float4 yIQ = float4(YPrime, I, Q, 0.0);
    color.r = dot(yIQ, kYIQToR);
    color.g = dot(yIQ, kYIQToG);
    color.b = dot(yIQ, kYIQToB);
    return color;
}

// MARK: - GlExposureFilter (exposure = 1.0 par défaut — c.-à-d. ×2, valeur Android non modifiée
// par FilterType.EXPOSURE, reproduite telle quelle)
fragment float4 tiinverExposure(TCVertexOut vertexIn [[stage_in]],
                                 texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                 sampler sourceSampler [[sampler(0)]],
                                 constant float &exposure [[buffer(0)]]) {
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    return float4(c.rgb * pow(2.0, exposure), c.a);
}

// MARK: - GlLuminanceFilter (aucun uniform)
fragment float4 tiinverLuminance(TCVertexOut vertexIn [[stage_in]],
                                  texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                  sampler sourceSampler [[sampler(0)]]) {
    constexpr float3 W = float3(0.2125, 0.7154, 0.0721);
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    float luminance = dot(c.rgb, W);
    return float4(float3(luminance), c.a);
}

// MARK: - GlHazeFilter (distance = 0.2, slope = -0.5 — FilterType.HAZE ne règle que `slope`)
fragment float4 tiinverHaze(TCVertexOut vertexIn [[stage_in]],
                             texture2d<float, access::sample> sourceTexture [[texture(0)]],
                             sampler sourceSampler [[sampler(0)]],
                             constant float &hazeDistance [[buffer(0)]],
                             constant float &slope [[buffer(1)]]) {
    float4 color = float4(1.0);
    float d = vertexIn.textureCoordinate.y * slope + hazeDistance;
    float4 c = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    c = (c - d * color) / (1.0 - d);
    return c;
}

// MARK: - GlHighlightShadowFilter (shadows = 1.0, highlights = 0.0 par défaut, non modifiés)
fragment float4 tiinverHighlightShadow(TCVertexOut vertexIn [[stage_in]],
                                        texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                        sampler sourceSampler [[sampler(0)]],
                                        constant float &shadows [[buffer(0)]],
                                        constant float &highlights [[buffer(1)]]) {
    constexpr float3 luminanceWeighting = float3(0.3, 0.3, 0.3);
    float4 source = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    float luminance = dot(source.rgb, luminanceWeighting);
    float shadow = clamp((pow(luminance, 1.0 / (shadows + 1.0)) + (-0.76) * pow(luminance, 2.0 / (shadows + 1.0))) - luminance, 0.0, 1.0);
    float highlight = clamp((1.0 - (pow(1.0 - luminance, 1.0 / (2.0 - highlights)) + (-0.8) * pow(1.0 - luminance, 2.0 / (2.0 - highlights)))) - luminance, -1.0, 0.0);
    float3 result = float3(0.0) + ((luminance + shadow + highlight) - 0.0) * ((source.rgb - float3(0.0)) / (luminance - 0.0));
    return float4(result, source.a);
}

// MARK: - GlPixelationFilter (pixel = 1.0 par défaut — quasi no-op, valeur Android non modifiée)
fragment float4 tiinverPixelation(TCVertexOut vertexIn [[stage_in]],
                                   texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                   sampler sourceSampler [[sampler(0)]],
                                   constant float &pixel [[buffer(0)]]) {
    float2 textureSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    float imageWidthFactor = 1.0 / textureSize.x;
    float imageHeightFactor = 1.0 / textureSize.y;
    float2 uv = vertexIn.textureCoordinate;
    float dx = pixel * imageWidthFactor;
    float dy = pixel * imageHeightFactor;
    float2 coord = float2(dx * floor(uv.x / dx), dy * floor(uv.y / dy));
    float3 tc = sourceTexture.sample(sourceSampler, coord).rgb;
    return float4(tc, 1.0);
}

// MARK: - GlBulgeDistortionFilter (center = (0.5,0.5), radius = 0.25, scale = 0.5 — coordonnées
// NORMALISÉES [0,1] comme le GLSL Android d'origine, PAS les coordonnées en pixels utilisées par
// le filtre `bulgeDistortion` intégré à MetalPetal — fonction custom pour rester fidèle à
// l'original, volontairement pas la version native de MetalPetal (formule en pixels différente).
fragment float4 tiinverBulgeDistortion(TCVertexOut vertexIn [[stage_in]],
                                        texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                        sampler sourceSampler [[sampler(0)]],
                                        constant float2 &center [[buffer(0)]],
                                        constant float &radius [[buffer(1)]],
                                        constant float &scale [[buffer(2)]]) {
    float2 textureCoordinateToUse = vertexIn.textureCoordinate;
    float dist = distance(center, vertexIn.textureCoordinate);
    textureCoordinateToUse -= center;
    if (dist < radius) {
        float percent = 1.0 - ((radius - dist) / radius) * scale;
        percent = percent * percent;
        textureCoordinateToUse = textureCoordinateToUse * percent;
    }
    textureCoordinateToUse += center;
    return sourceTexture.sample(sourceSampler, textureCoordinateToUse);
}

// MARK: - GlSharpenFilter (sharpness = 4.0 — FilterType.SHARP). Offsets 4-voisins calculés ici en
// fragment plutôt qu'en vertex varyings (voir note d'équivalence en tête de fichier).
fragment float4 tiinverSharpen(TCVertexOut vertexIn [[stage_in]],
                                texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                sampler sourceSampler [[sampler(0)]],
                                constant float &sharpness [[buffer(0)]]) {
    float2 textureSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    float imageWidthFactor = 1.0 / textureSize.x;
    float imageHeightFactor = 1.0 / textureSize.y;
    float2 uv = vertexIn.textureCoordinate;
    float2 leftUV = uv - float2(imageWidthFactor, 0.0);
    float2 rightUV = uv + float2(imageWidthFactor, 0.0);
    float2 topUV = uv + float2(0.0, imageHeightFactor);
    float2 bottomUV = uv - float2(0.0, imageHeightFactor);

    float centerMultiplier = 1.0 + 4.0 * sharpness;
    float edgeMultiplier = sharpness;

    float3 textureColor = sourceTexture.sample(sourceSampler, uv).rgb;
    float3 leftColor = sourceTexture.sample(sourceSampler, leftUV).rgb;
    float3 rightColor = sourceTexture.sample(sourceSampler, rightUV).rgb;
    float3 topColor = sourceTexture.sample(sourceSampler, topUV).rgb;
    float3 bottomColor = sourceTexture.sample(sourceSampler, bottomUV).rgb;

    float3 result = textureColor * centerMultiplier - (leftColor * edgeMultiplier + rightColor * edgeMultiplier + topColor * edgeMultiplier + bottomColor * edgeMultiplier);
    return float4(result, sourceTexture.sample(sourceSampler, bottomUV).a);
}

// MARK: - GlToneFilter (threshold = 0.2, quantizationLevels = 10.0, extends
// GlThreex3TextureSamplingFilter — 8 voisins 3x3, mêmes offsets recalculés en fragment)
fragment float4 tiinverTone(TCVertexOut vertexIn [[stage_in]],
                             texture2d<float, access::sample> sourceTexture [[texture(0)]],
                             sampler sourceSampler [[sampler(0)]],
                             constant float &threshold [[buffer(0)]],
                             constant float &quantizationLevels [[buffer(1)]]) {
    float2 textureSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    float texelWidth = 1.0 / textureSize.x;
    float texelHeight = 1.0 / textureSize.y;
    float2 uv = vertexIn.textureCoordinate;

    float2 widthStep = float2(texelWidth, 0.0);
    float2 heightStep = float2(0.0, texelHeight);
    float2 widthHeightStep = float2(texelWidth, texelHeight);
    float2 widthNegHeightStep = float2(texelWidth, -texelHeight);

    float2 leftUV = uv - widthStep;
    float2 rightUV = uv + widthStep;
    float2 topUV = uv - heightStep;
    float2 topLeftUV = uv - widthHeightStep;
    float2 topRightUV = uv + widthNegHeightStep;
    float2 bottomUV = uv + heightStep;
    float2 bottomLeftUV = uv - widthNegHeightStep;
    float2 bottomRightUV = uv + widthHeightStep;

    float4 textureColor = sourceTexture.sample(sourceSampler, uv);
    float bottomLeftIntensity = sourceTexture.sample(sourceSampler, bottomLeftUV).r;
    float topRightIntensity = sourceTexture.sample(sourceSampler, topRightUV).r;
    float topLeftIntensity = sourceTexture.sample(sourceSampler, topLeftUV).r;
    float bottomRightIntensity = sourceTexture.sample(sourceSampler, bottomRightUV).r;
    float leftIntensity = sourceTexture.sample(sourceSampler, leftUV).r;
    float rightIntensity = sourceTexture.sample(sourceSampler, rightUV).r;
    float bottomIntensity = sourceTexture.sample(sourceSampler, bottomUV).r;
    float topIntensity = sourceTexture.sample(sourceSampler, topUV).r;

    float h = -topLeftIntensity - 2.0 * topIntensity - topRightIntensity + bottomLeftIntensity + 2.0 * bottomIntensity + bottomRightIntensity;
    float v = -bottomLeftIntensity - 2.0 * leftIntensity - topLeftIntensity + bottomRightIntensity + 2.0 * rightIntensity + topRightIntensity;

    float mag = length(float2(h, v));
    float3 posterizedImageColor = floor((textureColor.rgb * quantizationLevels) + 0.5) / quantizationLevels;
    float thresholdTest = 1.0 - step(threshold, mag);
    return float4(posterizedImageColor * thresholdTest, textureColor.a);
}

// MARK: - GlVibranceFilter (vibrance = 3.0 — FilterType.VIBRANCE)
fragment float4 tiinverVibrance(TCVertexOut vertexIn [[stage_in]],
                                 texture2d<float, access::sample> sourceTexture [[texture(0)]],
                                 sampler sourceSampler [[sampler(0)]],
                                 constant float &vibrance [[buffer(0)]]) {
    float4 color = sourceTexture.sample(sourceSampler, vertexIn.textureCoordinate);
    float average = (color.r + color.g + color.b) / 3.0;
    float mx = max(color.r, max(color.g, color.b));
    float amt = (mx - average) * (-vibrance * 3.0);
    color.rgb = mix(color.rgb, float3(mx), amt);
    return color;
}

// MARK: - BeautyFilter (smoothingIntensity = 0.8, blurSize = 2.5, brightnessBoost = 0.3,
// saturation = 1.3 — aucun de ces 4 réglages n'est modifié par FilterType.BEAUTY_FILTER, tous les
// défauts internes de `BeautyFilter.java` sont donc utilisés tels quels). Flou 8-tap calculé en
// fragment (équivalent des `blurCoordinates[8]` du vertex shader Android).
fragment float4 tiinverBeauty(TCVertexOut vertexIn [[stage_in]],
                               texture2d<float, access::sample> sourceTexture [[texture(0)]],
                               sampler sourceSampler [[sampler(0)]],
                               constant float &smoothingIntensity [[buffer(0)]],
                               constant float &blurSize [[buffer(1)]],
                               constant float &brightnessBoost [[buffer(2)]],
                               constant float &saturation [[buffer(3)]]) {
    float2 textureSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    float texelWidthOffset = 1.0 / textureSize.x;
    float texelHeightOffset = 1.0 / textureSize.y;
    float2 texelOffset = float2(texelWidthOffset, texelHeightOffset) * blurSize;
    float2 center = vertexIn.textureCoordinate;

    float4 originalColor = sourceTexture.sample(sourceSampler, center);

    float4 sum = float4(0.0);
    sum += sourceTexture.sample(sourceSampler, center + texelOffset * float2(0.0, 1.0)) * 0.125;
    sum += sourceTexture.sample(sourceSampler, center + texelOffset * float2(1.0, 0.0)) * 0.125;
    sum += sourceTexture.sample(sourceSampler, center + texelOffset * float2(0.0, -1.0)) * 0.125;
    sum += sourceTexture.sample(sourceSampler, center + texelOffset * float2(-1.0, 0.0)) * 0.125;
    sum += sourceTexture.sample(sourceSampler, center + texelOffset * float2(1.0, 1.0)) * 0.1;
    sum += sourceTexture.sample(sourceSampler, center + texelOffset * float2(-1.0, 1.0)) * 0.1;
    sum += sourceTexture.sample(sourceSampler, center + texelOffset * float2(1.0, -1.0)) * 0.1;
    sum += sourceTexture.sample(sourceSampler, center + texelOffset * float2(-1.0, -1.0)) * 0.1;

    float4 smoothed = sum / 1.0;

    float r = originalColor.r;
    float g = originalColor.g;
    float b = originalColor.b;
    float diff = abs(r - g);
    float sumRGB = r + g + b;
    float skinTone = step(0.35, r) * step(0.2, g) * step(0.1, b);
    float notTooBright = step(sumRGB, 2.5);
    float notTooMuchDiff = step(diff, 0.4);
    float skinMask = skinTone * notTooBright * notTooMuchDiff;

    float4 smoothColor = mix(originalColor, smoothed, smoothingIntensity * skinMask);
    float3 detail = originalColor.rgb - smoothed.rgb;
    smoothColor.rgb += detail * 0.25 * skinMask;
    smoothColor.rgb += brightnessBoost;

    float gray = dot(smoothColor.rgb, float3(0.299, 0.587, 0.114));
    smoothColor.rgb = mix(float3(gray), smoothColor.rgb, saturation);

    return float4(smoothColor.rgb, originalColor.a);
}
