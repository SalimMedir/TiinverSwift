import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI

/// Port de `editor/MediasDisplay.java` (727 lignes, lu en entier le 2026-09-01) — écran de revue
/// intercalé entre la capture/le recadrage d'une vidéo et `PublishFragment`, pour LES TROIS sources
/// (Caméra, Galerie après `MediaTrim`, export Animems — confirmé par `inputOutputPath.contains(
/// "ANIMEMES") → isAnimemes = true`, `MediasDisplay.java:169-171`) : preview de la vidéo, ajout
/// OPTIONNEL d'une musique de fond OU d'une voix off (mutuellement remplaçables, jamais les deux en
/// un seul appel de fusion — voir `MediasDisplay.startMerge`), fusion audio réelle via
/// `VideoEditor.MixAudioVideo()`, puis transmission à Publish.
///
/// **Confirmé en traçant `CameraActivity.onArticleSelected`/`MediaTrim.next.setOnClickListener`
/// (`onArticleSelected(7, ...)`, case 7 = `MediasDisplay`) : `MediaTrim` (recadrage) et
/// `MediasDisplay` (musique/voix off) sont deux écrans DISTINCTS, PAS interchangeables.** Seule la
/// Galerie traverse `MediaTrim` (recadrage géométrique, pertinent pour un import externe) ; les 3
/// sources traversent TOUTES `MediasDisplay` (revue + son), jamais `MediaTrim` pour Caméra/Animems.
///
/// **Musique — écart assumé, documenté** : `MusicShooserDialog` (Android) présente une
/// bibliothèque de sons propre à l'app (`MusicPlayerRecyclerView`/`GridViewManager`, fichiers non
/// disponibles dans ce dépôt Swift). Reproduit ici via le sélecteur SYSTÈME iOS
/// (`MPMediaPickerController`, bibliothèque musicale de l'utilisateur) — même FONCTION (choisir un
/// morceau à mélanger), technologie différente faute d'accès aux mêmes assets sonores.
///
/// **Aucune dépendance FFmpeg** — voir `MediaAudioMerger.swift` pour la justification complète.
struct MediasDisplayView: View {
    let sourceURL: URL
    var onDone: (URL) -> Void
    var onCancel: () -> Void

    @State private var currentURL: URL
    @State private var player: AVPlayer
    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var isMerging = false
    @State private var errorText: String?
    @State private var showMusicPicker = false
    @State private var pendingVoiceOverURL: URL?
    @State private var showKeepRecordingConfirm = false
    /// Garde contre les répétitions de `.onChanged` du geste presser-maintenir — `VoiceRecorder.
    /// start()` ne doit être appelé QU'UNE FOIS par appui, pas à chaque micro-mouvement du doigt
    /// pendant qu'il reste posé.
    @State private var isPressingVoiceButton = false

    init(sourceURL: URL, onDone: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.sourceURL = sourceURL
        self.onDone = onDone
        self.onCancel = onCancel
        _currentURL = State(initialValue: sourceURL)
        _player = State(initialValue: AVPlayer(url: sourceURL))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VideoPlayer(player: player)
                    .frame(maxHeight: 420)
                    .background(Color.black)
                    .onAppear { player.play() }
                    // **Corrigé le 2026-09-02 (MIGRATION_PARITY_AUDIT_V9.md V9-F-011)** — l'affirmation
                    // précédente ("fidèle à Android", citant `MediasDisplay.java:573-578`'s
                    // `onCompletion`) était inexacte : `MediasDisplay` implémente bien
                    // `MediaPlayer.OnCompletionListener`, mais la preview réelle utilise `ExoPlayer`
                    // (`mVideoView.setPlayer`), jamais `android.media.MediaPlayer` — `onCompletion`
                    // est du code MORT, jamais invoqué (confirmé : aucun `MediaPlayer` instancié dans
                    // ce fichier, `myPlayerListener` — le vrai `Player.Listener` ExoPlayer — ne gère
                    // que `onPlaybackStateChanged`/`onVideoSizeChanged`, aucun `setRepeatMode`
                    // trouvé). La preview Android ne boucle donc PAS — elle joue une fois puis
                    // s'arrête. Le bouclage ci-dessous est une amélioration UX délibérée assumée,
                    // pas une reproduction du comportement Android réel.
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)) { _ in
                        player.seek(to: .zero)
                        player.play()
                    }

                if isMerging {
                    ProgressView("Fusion audio…")
                } else {
                    HStack(spacing: 40) {
                        Button {
                            showMusicPicker = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "music.note").font(.title2)
                                Text("Musique").font(.caption)
                            }
                        }

                        // Port du `touchListener` presser-maintenir (`MediasDisplay.java:431-456`,
                        // `ACTION_DOWN` démarre l'enregistrement, `ACTION_UP` l'arrête et ouvre
                        // `showNoticeDialog()`) — `DragGesture(minimumDistance: 0)` reproduit le
                        // même couple appui/relâchement qu'un `OnTouchListener` brut.
                        VStack(spacing: 4) {
                            Image(systemName: voiceRecorder.isRecording ? "mic.fill" : "mic")
                                .font(.title2)
                                .foregroundStyle(voiceRecorder.isRecording ? Color.red : Color.primary)
                            Text(voiceRecorder.isRecording ? formatted(voiceRecorder.elapsedSeconds) : "Voix off")
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    guard !isPressingVoiceButton else { return }
                                    isPressingVoiceButton = true
                                    Task {
                                        if !(await voiceRecorder.start()) {
                                            errorText = "Micro requis pour enregistrer une voix off."
                                            isPressingVoiceButton = false
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isPressingVoiceButton = false
                                    guard let result = voiceRecorder.stop() else { return }
                                    pendingVoiceOverURL = result.url
                                    showKeepRecordingConfirm = true
                                }
                        )

                        if currentURL != sourceURL {
                            Button {
                                currentURL = sourceURL
                                player.pause()
                                player = AVPlayer(url: sourceURL)
                                player.play()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward").font(.title2)
                                    Text("Retirer le son").font(.caption)
                                }
                            }
                        }
                    }
                }

                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Aperçu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Port de `save.setOnClickListener` (`MediasDisplay.java:258-286`) — transmet
                    // `currentURL` tel quel, fusionné ou non selon que l'utilisateur a ajouté un son,
                    // exactement comme `inputOutputPath` côté Android à ce même point.
                    Button("Suivant") {
                        player.pause()
                        onDone(currentURL)
                    }
                    .disabled(isMerging)
                }
            }
        }
        .sheet(isPresented: $showMusicPicker) {
            MusicPickerView { pickedURL in
                showMusicPicker = false
                guard let pickedURL else { return }
                Task { await mergeAudio(from: pickedURL) }
            }
        }
        // Port de `showNoticeDialog()` (`MediasDisplay.java:605-626`, `ask_for_save`) — demande
        // confirmation avant de fusionner une voix off fraîchement enregistrée.
        .alert("Garder cet enregistrement ?", isPresented: $showKeepRecordingConfirm) {
            Button("Garder") {
                if let url = pendingVoiceOverURL {
                    Task { await mergeAudio(from: url) }
                }
            }
            Button("Annuler", role: .cancel) {
                if let url = pendingVoiceOverURL {
                    try? FileManager.default.removeItem(at: url)
                }
                pendingVoiceOverURL = nil
            }
        }
    }

    /// Port de `startMerge`/`VideoEditor.MixAudioVideo()` — fusionne `audioURL` (musique OU voix
    /// off) avec `currentURL`, remplace la preview par le résultat. Une fusion ultérieure part
    /// TOUJOURS de `currentURL` (pas de `sourceURL`), fidèle à Android : `inputOutputPath` est
    /// réassigné après chaque fusion réussie (`MediasDisplay.java:498`), une seconde fusion
    /// s'applique donc au résultat de la première, pas à l'original.
    private func mergeAudio(from audioURL: URL) async {
        isMerging = true
        defer { isMerging = false }
        do {
            let merged = try await MediaAudioMerger.merge(videoURL: currentURL, addedAudioURL: audioURL)
            currentURL = merged
            player.pause()
            player = AVPlayer(url: merged)
            player.play()
        } catch {
            errorText = "La fusion audio a échoué — réessaie ou continue sans son ajouté."
        }
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Port de `MusicShooserDialog` (choix du morceau uniquement — voir doc de tête de
/// `MediasDisplayView` pour l'écart de source assumé) — enveloppe `MPMediaPickerController`.
/// `onPicked(nil)` = annulé ou morceau protégé DRM (Apple Music streaming, `assetURL == nil`, sans
/// équivalent Android — un fichier distant chiffré ne peut structurellement pas être extrait comme
/// fichier local pour un mélange audio, quelle que soit la plateforme).
private struct MusicPickerView: UIViewControllerRepresentable {
    var onPicked: (URL?) -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onPicked: (URL?) -> Void
        init(onPicked: @escaping (URL?) -> Void) { self.onPicked = onPicked }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            let url = mediaItemCollection.items.first?.assetURL
            onPicked(url)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            onPicked(nil)
        }
    }
}
