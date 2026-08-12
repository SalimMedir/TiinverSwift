import SwiftUI

/// Port de `view/seekbar/WaveformSeekBar.java` (module 11, Messagerie — reclassé depuis le module
/// 10 après vérification par grep, voir `MIGRATION_PROGRESS.md` : seuls consommateurs réels
/// `messagerie/layout/BubbleMessageAudioCompound.java`/`messagerie/ui/viewholders/
/// MessageAudioViewHolder.java`, bulles de message vocal du chat). **Bibliothèque tierce vendorisée
/// confirmée** (recherche : structure/API identique à `massoudss/waveformSeekBar`, package Maven
/// `com.github.massoudss:waveformSeekBar`) — portée directement plutôt que remplacée par une
/// dépendance SPM : contrairement à `TOCropViewController` (~5000 lignes de géométrie tactile
/// complexe), l'algorithme réel ici est compact (calcul de largeur/espacement de barres +
/// normalisation d'amplitude, ~150 lignes utiles) — un port fidèle direct est plus simple et moins
/// risqué qu'une nouvelle dépendance externe pour ce besoin précis.
///
/// **Ne génère PAS les échantillons audio** (confirmé en lisant le fichier Android en entier) :
/// `WaveformSeekBar`/`Waveform` REÇOIVENT un `int[]` déjà calculé (`setWaveform`), l'extraction PCM
/// elle-même se fait ailleurs (probablement `Utils/media/**`, pas encore identifié pour la
/// messagerie — à retrouver en portant `BubbleMessageAudioCompound.java`, pas fait cette passe).
enum WaveformLayout {
    /// Port de `calculateWaveDimensions` — calcule largeur/espacement de barre pour remplir
    /// `contentWidth` avec `waveCount` barres, espacement de bord distinct de l'espacement inter-
    /// barres (`edgeWaveGap`), reproduit à l'identique.
    struct Metrics {
        var waveWidth: CGFloat
        var waveGap: CGFloat
        var edgeWaveGap: CGFloat
    }

    static let defaultEdgeGap: CGFloat = 2

    static func calculateWaveDimensions(
        waveCount: Int, contentWidth: CGFloat, preferredWaveGap: CGFloat, maxWaveWidth: CGFloat = -1
    ) -> Metrics {
        guard waveCount > 0, contentWidth > 0 else { return Metrics(waveWidth: 0, waveGap: 0, edgeWaveGap: 0) }

        var edgeWaveGap = min(defaultEdgeGap, contentWidth / 40)
        let edgeWaveGapCount: CGFloat = 2
        let waveGapCount = waveCount - 1

        let totalGap = preferredWaveGap > 0
            ? preferredWaveGap * CGFloat(waveGapCount) + edgeWaveGap * edgeWaveGapCount
            : 0
        let remainingSpace = max(0, contentWidth - totalGap)
        var waveWidth = remainingSpace / CGFloat(waveCount)

        if maxWaveWidth > 0, waveWidth > maxWaveWidth { waveWidth = maxWaveWidth }
        if waveWidth <= 0 { waveWidth = min(1, contentWidth / CGFloat(waveCount)) }

        var waveGap: CGFloat
        if waveGapCount > 0 {
            waveGap = (contentWidth - waveWidth * CGFloat(waveCount) - edgeWaveGap * edgeWaveGapCount)
                / CGFloat(waveGapCount)
            if waveGap < 0 { waveGap = 0 }
        } else {
            waveGap = 0
            edgeWaveGap = (contentWidth - waveWidth * CGFloat(waveCount)) / 2
        }

        return Metrics(waveWidth: waveWidth, waveGap: waveGap, edgeWaveGap: edgeWaveGap)
    }

    /// Port de `calculateDiscretePosition` — convertit un pourcentage de progression `[0, 1]` en
    /// index de barre "actif", en tenant compte du fait que les barres de bord n'occupent QUE la
    /// moitié de la largeur de pourcentage d'une barre normale (reproduit à l'identique, formule
    /// non triviale conservée telle quelle).
    static func discretePosition(count: Int, percent: Float) -> Int {
        if percent < 0.001 { return -1 }
        if percent > 0.999 { return count - 1 }
        let normalWavePercent = 1 / Float(count - 1)
        let missingEdgeWavePercent = normalWavePercent / 2
        let actualPercent = (percent + missingEdgeWavePercent) / (1 + missingEdgeWavePercent * 2)
        return Int(Float(count) * actualPercent)
    }

    /// Port de `blendWaveforms` — interpolation entre deux jeux de barres de même longueur
    /// (utilisée par l'animation de transition Android, `ANIM_DURATION=200ms` — l'animation
    /// elle-même est laissée à l'appelant SwiftUI, via `.animation(_:value:)` sur `waves`, pas
    /// reproduite ici comme un minuteur manuel).
    static func blend(start: [Int], end: [Int], factor: Float) -> [Int] {
        guard start.count == end.count, let startMax = start.max(), startMax != 0 else { return end }
        let normalizer = Float(end.max() ?? 0) / Float(startMax)
        return zip(start, end).map { s, e in
            let normalizedStart = Float(s) * normalizer
            return Int(normalizedStart + (Float(e) - normalizedStart) * factor)
        }
    }
}

/// Port du rendu (`onDraw`) — barres arrondies, colorées selon la position par rapport à
/// `progressPercent`. Types d'arrondi (`WaveCornerType.NONE/AUTO/EXACTLY`) simplifiés à un seul
/// paramètre `cornerRadius` fourni par l'appelant (AUTO = `waveWidth/2`, comportement le plus
/// utilisé par `BubbleMessageAudioCompound`, à confirmer en portant ce fichier).
struct WaveformSeekBar: View {
    let waves: [Int]
    var progressPercent: Float = 0
    var waveGap: CGFloat = 2
    var backgroundColor: Color = .gray.opacity(0.4)
    var progressColor: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            let metrics = WaveformLayout.calculateWaveDimensions(
                waveCount: waves.count, contentWidth: geo.size.width, preferredWaveGap: waveGap)
            let maxWave = max(waves.max() ?? 1, 1)
            let activeIndex = WaveformLayout.discretePosition(count: waves.count, percent: progressPercent)

            Canvas { context, size in
                var x = metrics.edgeWaveGap
                for (i, wave) in waves.enumerated() {
                    let amplitude = CGFloat(wave) / CGFloat(maxWave)
                    let barHeight = max(2, amplitude * size.height)
                    let rect = CGRect(x: x, y: (size.height - barHeight) / 2, width: metrics.waveWidth, height: barHeight)
                    let path = Path(roundedRect: rect, cornerRadius: metrics.waveWidth / 2)
                    context.fill(path, with: .color(i <= activeIndex ? progressColor : backgroundColor))
                    x += metrics.waveWidth + metrics.waveGap
                }
            }
        }
    }
}
