import Foundation

/// Port de `core/AnimationUtils.java` — fonctions utilitaires pures (aucun état).
enum AnimationUtils {
    /// Port de `isAnimation` — détermine si le composer contient une véritable animation
    /// (plusieurs frames ou plusieurs transforms/bitmaps par calque).
    static func isAnimation(composer: AnimationComposer?, frameCount: Int) -> Bool {
        if frameCount > 2 { return true }
        guard let composer, !composer.layers.isEmpty else { return false }
        if composer.layers.contains(where: { $0.transforms.count > 2 }) { return true }
        if composer.layers.contains(where: { $0.bitmaps.count > 2 }) { return true }
        return false
    }

    /// Port de `isAutoCreatableTrack` — détermine si une piste peut être créée automatiquement
    /// sans nécessiter un calque existant de l'utilisateur.
    static func isAutoCreatableTrack(objectType: String?, label: String?) -> Bool {
        guard let objectType else { return false }
        if ["SHAPE_RECT", "SHAPE_CIRCLE", "SHAPE_LINE"].contains(objectType) { return true }
        if objectType == "MASK" { return true }
        if let label, label.hasPrefix("mask_") { return true }
        return false
    }

    /// Port de `updateMaskLabel` — met à jour la valeur feather dans le label d'un calque mask.
    /// Format : `"mask_{type}_{inverted}_{color}_{opacity}_{feather}"`.
    static func updateMaskLabel(_ label: String?, newFeather: Float) -> String? {
        guard let label, label.hasPrefix("mask_") else { return label }
        let parts = label.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6 else { return label }
        let featherString = String(format: "%.2f", newFeather)
        return "mask_\(parts[1])_\(parts[2])_\(parts[3])_\(parts[4])_\(featherString)"
    }

    /// Port de `makeMessengerLikeBackground` — dérive une couleur de fond "façon Messenger"
    /// (désaturée, éclaircie) depuis une couleur dominante ARGB. Conversion RGB→HSV→RGB manuelle
    /// reproduite formule par formule (pas de raccourci `UIColor`/`CGColor` HSB qui pourrait
    /// arrondir différemment).
    static func makeMessengerLikeBackground(dominantColor: UInt32) -> UInt32 {
        let r = Float((dominantColor >> 16) & 0xFF) / 255
        let g = Float((dominantColor >> 8) & 0xFF) / 255
        let b = Float(dominantColor & 0xFF) / 255

        let maxV = max(r, max(g, b))
        let minV = min(r, min(g, b))
        let delta = maxV - minV

        var h: Float = 0
        if delta > 0 {
            if maxV == r { h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maxV == g { h = 60 * (((b - r) / delta) + 2) }
            else { h = 60 * (((r - g) / delta) + 4) }
        }
        if h < 0 { h += 360 }

        var s: Float = maxV == 0 ? 0 : delta / maxV
        var v: Float = maxV

        s *= 0.4
        v = min(1, v + 0.25)

        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c

        var r2: Float = 0, g2: Float = 0, b2: Float = 0
        if h < 60 { r2 = c; g2 = x; b2 = 0 }
        else if h < 120 { r2 = x; g2 = c; b2 = 0 }
        else if h < 180 { r2 = 0; g2 = c; b2 = x }
        else if h < 240 { r2 = 0; g2 = x; b2 = c }
        else if h < 300 { r2 = x; g2 = 0; b2 = c }
        else { r2 = c; g2 = 0; b2 = x }

        // Conversion sécurisée : `UInt32(negativeFloat)` provoque un crash Swift (contrairement à
        // Java, où un `int` hors-borne "wrap" silencieusement) — clampé AVANT conversion plutôt
        // qu'après, pour ne jamais présenter une valeur négative à l'initialiseur `UInt32`.
        func toByte(_ v: Float) -> UInt32 {
            UInt32(max(0, min(255, (v * 255).rounded())))
        }
        let ri = toByte(r2 + m)
        let gi = toByte(g2 + m)
        let bi = toByte(b2 + m)

        return (0xFF << 24) | (ri << 16) | (gi << 8) | bi
    }
}
