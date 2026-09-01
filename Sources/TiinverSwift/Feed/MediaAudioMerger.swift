import AVFoundation

/// Port du comportement (pas de la technologie) de `VideoEditor.MixAudioVideo()`/`AudioMixer`
/// (`engine/android/codec/`, lus en entier le 2026-09-01) — Android mixe l'audio ORIGINAL de la
/// vidéo avec UNE piste ajoutée (musique OU voix off, jamais les deux simultanément dans le même
/// appel — voir `MediasDisplay.startMerge`, un seul `audioUri` à la fois) via un mixeur PCM
/// échantillon-par-échantillon fait main (`AudioMixer.MixingType.PARALLEL` : moyenne pondérée par
/// le volume de chaque entrée, PAS un remplacement de piste).
///
/// **Confirmé en lisant `AudioMixer.java`/`VideoEditor.java` en entier : AUCUNE dépendance FFmpeg
/// réelle** — malgré le nom trompeur de l'interface `OptiFFMpegCallback`, tout le pipeline Android
/// utilise `MediaExtractor`/`MediaCodec`/`MediaMuxer` natifs. Reproduit ici via l'équivalent
/// AVFoundation natif — `AVMutableComposition` (pistes vidéo/audio multiples) + `AVMutableAudioMix`
/// (volume par piste) + `AVAssetExportSession` — qui obtient le MÊME comportement (mixage réel, pas
/// un remplacement) de façon plus robuste que de réimplémenter un mixeur PCM manuel : c'est
/// exactement la fonctionnalité pour laquelle ces API existent. **Aucune dépendance FFmpeg ajoutée
/// à iOS**, conformément à la consigne explicite.
enum MediaAudioMerger {
    enum MergeError: Error {
        case noVideoTrack
        case cannotCreateExportSession
        case exportFailed
    }

    /// Mixe l'audio propre de `videoURL` (s'il existe) avec `addedAudioURL` (musique ou voix off),
    /// tous deux audibles simultanément — jamais un remplacement pur et simple de la piste
    /// originale. `addedAudioVolume`/`originalVolume` : port de `AudioInput.getVolume()`, valeurs
    /// par défaut à 1.0 (Android n'expose aucun réglage de volume utilisateur pour ce mélange —
    /// grep exhaustif de `setVolume`/`getVolume` dans `MediasDisplay.java` : jamais appelé
    /// explicitement, seule la valeur par défaut de `AudioInput` compte).
    ///
    /// Port de `AudioMixer.MixingType.PARALLEL` + `loopingEnabled` (`AudioMixer.java:196-216`) —
    /// l'entrée la plus courte des deux boucle jusqu'à couvrir la durée de sortie (celle de la
    /// vidéo, systématiquement la plus longue en pratique pour ce cas d'usage : une musique/voix
    /// ajoutée dépasse rarement la durée d'une vidéo déjà limitée à 60s côté trim). Une piste
    /// ajoutée plus longue que la vidéo est simplement tronquée à la durée vidéo (Android fait de
    /// même : `outputDurationUs` = la plus longue durée parmi les entrées du mixeur, mais le
    /// `MediaMuxer` vidéo qui écrit en parallèle borne de toute façon le fichier final à la durée
    /// vidéo).
    static func merge(
        videoURL: URL, addedAudioURL: URL,
        addedAudioVolume: Float = 1.0, originalVolume: Float = 1.0
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: addedAudioURL)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw MergeError.noVideoTrack
        }
        let videoDuration = try await asset.load(.duration)
        guard videoDuration.isValid, videoDuration > .zero else { throw MergeError.noVideoTrack }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MergeError.exportFailed }
        try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        compVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

        var audioMixParams: [AVMutableAudioMixInputParameters] = []

        if let originalAudioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
            let compOriginalAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        {
            try? compOriginalAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: originalAudioTrack, at: .zero)
            let params = AVMutableAudioMixInputParameters(track: compOriginalAudioTrack)
            params.setVolume(originalVolume, at: .zero)
            audioMixParams.append(params)
        }

        if let addedTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first,
            let compAddedTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        {
            let addedDuration = try await audioAsset.load(.duration)
            var inserted = CMTime.zero
            while inserted < videoDuration {
                let remaining = videoDuration - inserted
                let chunk = min(remaining, addedDuration)
                guard chunk > .zero else { break }
                try? compAddedTrack.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: addedTrack, at: inserted)
                inserted = inserted + chunk
            }
            let params = AVMutableAudioMixInputParameters(track: compAddedTrack)
            params.setVolume(addedAudioVolume, at: .zero)
            audioMixParams.append(params)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParams

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw MergeError.cannotCreateExportSession }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.audioMix = audioMix
        exportSession.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously { continuation.resume() }
        }
        guard exportSession.status == .completed else { throw MergeError.exportFailed }
        return outputURL
    }
}
