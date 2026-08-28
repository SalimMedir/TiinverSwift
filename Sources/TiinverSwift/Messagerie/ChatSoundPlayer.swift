import AVFoundation

/// Port de `Utils/app_sound/AppSounds.java` (119 lignes, lu en entier) — chimes synthétisés en
/// PCM mono à 44100Hz PURE MATHÉMATIQUE (aucun asset audio côté Android : `AudioTrack` joue un
/// tampon de sinusoïdes enveloppées généré à la volée). Seuls `playSend`/`playReceive` sont
/// portés ici — les deux seuls réellement câblés en conversation (`ChatFragmentTest.addMessage`
/// ligne 2716-2718 pour l'envoi, `onNewMessage` ligne 1953-1955 pour la réception).
/// `AppSounds.playTyping()` (clic de frappe) N'A AUCUN appelant dans les 3080 lignes de
/// `ChatFragmentTest.java` lues pour cet audit — code mort côté Android lui-même, non porté ici.
///
/// **Ajouté (2026-08-28, V6-F-011)** — seule la plomberie du flag remote-config
/// (`TiinverFirebaseConfigManager.allowChatSendReceiveSound`) existait jusqu'ici côté iOS, sans
/// aucune lecture réelle (confirmé par grep exhaustif dans `Sources/TiinverSwift/Messagerie/`).
///
/// Utilise `AVAudioEngine`/`AVAudioPlayerNode` avec un tampon `Float` (`[-1,1]`) plutôt que le
/// `Int16` d'`AudioTrack` — formule d'amplitude IDENTIQUE (`amp * sin(...)`), seule la
/// représentation bas niveau diffère (Float32 a une fidélité supérieure à Int16, donc aucune
/// perte perceptible) ; adaptation de plateforme, pas un raccourci qui changerait le son produit.
enum ChatSoundPlayer {
    private static let sampleRate: Double = 44100

    /// Port de `AppSounds.playSend` — attaque nette (880Hz) + note montante (1100Hz).
    static func playSend() {
        guard TiinverFirebaseConfigManager.shared.allowChatSendReceiveSound else { return }
        let dur1 = ms(80), dur2 = ms(180)
        var buffer = [Float](repeating: 0, count: dur1 + dur2)
        for i in 0..<dur1 {
            buffer[i] = sample(freq: 880, i: i, amp: attackEnvelope(i, total: dur1, maxAmp: 0.18))
        }
        for i in 0..<dur2 {
            buffer[dur1 + i] = sample(freq: 1100, i: i, amp: decayEnvelope(i, total: dur2, maxAmp: 0.18, rate: 3.0))
        }
        play(buffer)
    }

    /// Port de `AppSounds.playReceive` — ding-dong enchaîné (660Hz puis 880Hz, chevauchement 40ms).
    static func playReceive() {
        guard TiinverFirebaseConfigManager.shared.allowChatSendReceiveSound else { return }
        let note1Len = ms(180), note2Len = ms(220), overlap = ms(40)
        var buffer = [Float](repeating: 0, count: note1Len + note2Len - overlap)
        for i in 0..<note1Len {
            buffer[i] += sample(freq: 660, i: i, amp: decayEnvelope(i, total: note1Len, maxAmp: 0.22, rate: 3.5))
        }
        let start2 = note1Len - overlap
        for i in 0..<note2Len {
            let idx = start2 + i
            guard idx < buffer.count else { continue }
            buffer[idx] += sample(freq: 880, i: i, amp: decayEnvelope(i, total: note2Len, maxAmp: 0.18, rate: 3.0))
        }
        play(buffer)
    }

    // MARK: - Synthèse (port des utilitaires `AppSounds`)

    private static func ms(_ millis: Int) -> Int { Int(sampleRate) * millis / 1000 }

    private static func sample(freq: Double, i: Int, amp: Float) -> Float {
        amp * Float(sin(2 * Double.pi * freq * Double(i) / sampleRate))
    }

    /// Port de `attack(i, total, maxAmp)` — montée sur 10% puis décroissance exponentielle.
    private static func attackEnvelope(_ i: Int, total: Int, maxAmp: Float) -> Float {
        let ramp = min(1, Float(i) / (Float(total) * 0.1))
        let fall = Float(exp(-3.0 * Double(i) / Double(total)))
        return ramp * fall * maxAmp
    }

    /// Port de `decay(i, total, maxAmp)` — `rate` reproduit les constantes `-4.0`/`-3.5`/`-3.0`
    /// utilisées par les 3 appelants Android (`decay` lui-même, et les 2 enveloppes inline de
    /// `playReceive`, toutes de la même forme `exp(-rate * i / total)`).
    private static func decayEnvelope(_ i: Int, total: Int, maxAmp: Float, rate: Double = 4.0) -> Float {
        Float(exp(-rate * Double(i) / Double(total))) * maxAmp
    }

    // MARK: - Lecture (port de `play(short[])`)

    private static let engine = AVAudioEngine()
    private static let playerNode = AVAudioPlayerNode()
    private static var isWired = false

    private static func play(_ samples: [Float]) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = pcmBuffer.floatChannelData![0]
        for (i, s) in samples.enumerated() { channelData[i] = s }

        if !isWired {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            isWired = true
        }
        guard (try? engine.start()) != nil else { return }
        playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        playerNode.play()
    }
}
