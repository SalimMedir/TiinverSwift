import AVFoundation
import Foundation

/// **Ajouté le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-033, Phase B P1-15)** — port de
/// `messagerie/AudioManager.java` (capture UNIQUEMENT — `MediaRecorder`, `AudioSource.MIC`,
/// `OutputFormat.THREE_GPP`, `AudioEncoder.AMR_NB`, ligne 105-112) pour
/// `ChatView`/`ChatViewModel.sendMedia(object: "audio", ...)`.
///
/// **Écart technique documenté, pas une invention** : Android encode réellement en AMR_NB/3GP.
/// `AVAudioRecorder` (AVFoundation) n'expose PUBLIQUEMENT aucun encodeur AMR — capture donc en
/// AAC/`.m4a` (réglage standard, haute qualité, le seul largement disponible sans bibliothèque de
/// codec tierce). `ChatMediaUploadService.MessageMediaKind.audio` étiquette déjà
/// INCONDITIONNELLEMENT tout objet "audio" comme `audio/3gpp`/`.3gp` (comportement EXISTANT, non
/// modifié ici) — le fichier envoyé au CDN est donc du contenu AAC réel sous une étiquette `.3gp`.
/// **Risque réel non résolu par ce correctif** : la lecture d'un message vocal envoyé par iOS
/// pourrait échouer côté récepteur Android si son décodeur suppose strictement un flux AMR_NB —
/// nécessite un test croisé réel iOS→Android pour confirmer, documenté explicitement plutôt que
/// masqué.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var startDate: Date?
    private var timer: Timer?

    private static func hasMicPermission() async -> Bool {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return true
        }
    }

    /// Port de `MessageEventLayout.startRecording`/`recordPermited` — démarre l'enregistrement si
    /// le micro est autorisé (déclenche la demande système si `.undetermined`, comme
    /// `listener.askPermission()` côté Android). Retourne `false` sans effet si refusé — l'appelant
    /// affiche l'alerte "Micro requis" (même motif que `CallCoordinator.micPermissionDenied`).
    func start() async -> Bool {
        guard await Self.hasMicPermission() else { return false }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard recorder.record() else { return false }
        self.recorder = recorder
        startDate = Date()
        isRecording = true
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startDate = self.startDate else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startDate)
            }
        }
        return true
    }

    /// Port de `endRecord` — arrête et retourne l'URL locale + durée en millisecondes. `nil` si
    /// l'enregistrement a duré moins d'une seconde (port de
    /// `OnRecordListener.onLessThanSecond` → `cancelRecord()`, Android annule un enregistrement
    /// trop court plutôt que de l'envoyer).
    func stop() -> (url: URL, durationMillis: Int)? {
        guard let recorder, isRecording else { teardown(); return nil }
        let duration = startDate.map { Date().timeIntervalSince($0) } ?? 0
        let url = recorder.url
        recorder.stop()
        teardown()
        guard duration >= 1 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, Int(duration * 1000))
    }

    /// Port de `cancelRecord` — annule sans envoyer, supprime le fichier local.
    func cancel() {
        guard let recorder else { teardown(); return }
        let url = recorder.url
        recorder.stop()
        try? FileManager.default.removeItem(at: url)
        teardown()
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        startDate = nil
        isRecording = false
        elapsedSeconds = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
