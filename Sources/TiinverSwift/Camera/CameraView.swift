import SwiftUI

/// Port de `editor/camera/BaseCameraFragment.java` (711 lignes) + `editor/CircleCaptureButton.java`
/// (bouton de capture, lu en entier).
///
/// "ANIMEMES" (3ᵉ item du menu, `onArticleSelected(5, ...)`) : closure `onOpenAnimems`, reste un
/// no-op assumé tant que le module 8 (Moteur Animems) n'existe pas — voir `bottomBar` plus bas.
struct CameraView: View {
    @StateObject private var recorder = CameraRecorder()

    @State private var filterIndex = 0
    @State private var isRecording = false
    @State private var recordingElapsed: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var recordingStartTask: DispatchWorkItem?
    @State private var showGalleryPicker = false

    var lensFacing: LensFacing = .back
    var onClose: () -> Void = {}
    var onPhotoCaptured: (UIImage) -> Void = { _ in }
    var onVideoRecorded: (URL, TimeInterval) -> Void = { _, _ in }
    /// Port de la branche image de `pickMedia` (`mFragmentListener.onArticleSelected(2, bundle)`
    /// avec `style=gallery` → `MediaEditor`, module 9, pas encore porté).
    var onImagePickedFromGallery: (URL) -> Void = { _ in }
    /// Port de la branche vidéo de `pickMedia` (`onArticleSelected(10, bundle)` → `MediaTrim`,
    /// module non identifié dans l'ordre de portage à 18 modules, pas encore porté).
    var onVideoPickedFromGallery: (URL) -> Void = { _ in }
    var onOpenAnimems: () -> Void = {}

    /// Port de `BaseCameraFragment.btnCapture.setVideoDuration(20000)` (20 secondes max).
    private let maxRecordingDuration: TimeInterval = 20

    /// Port de `CircleCaptureButton.captureListeer` — `mHandler.postDelayed(action, 1000)` : le
    /// seuil RÉEL entre "tap = photo" et "appui long = vidéo" est de très exactement 1000 ms, lu
    /// directement dans le fichier source (pas une estimation comme dans un premier jet de ce
    /// fichier, qui utilisait `minimumDuration: 0.35` sans base — corrigé, voir journal).
    private let captureHoldThreshold: TimeInterval = 1.0

    var body: some View {
        ZStack {
            CameraPreviewView(recorder: recorder) { normalizedPoint in
                recorder.changeManualFocusPoint(normalizedPoint)
            }
            .ignoresSafeArea()
            .gesture(swipeToChangeFilterGesture)

            VStack {
                topBar
                Spacer()
                if isRecording {
                    Text(formattedElapsed)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.4)))
                }
                bottomBar
            }
            .padding(.bottom, 24)
        }
        .background(Color.black)
        .onAppear {
            recorder.setFilter(CameraFilterType.allCases[filterIndex])
            recorder.start(lensFacing: lensFacing)
        }
        .onDisappear {
            recorder.release()
        }
        // `recorder.lastRecordedURL`/`delegate` : voir commentaire de tête de fichier sur
        // `CameraRecorderDelegate` — piloté ici par `.onChange` plutôt que par le `delegate`
        // `weak` de `CameraRecorder` (mal adapté à une `View` de type `struct`, qui n'a pas
        // d'identité stable à laquelle un délégué faible pourrait s'accrocher).
        // Forme à un seul paramètre de `.onChange` (iOS 16 minimum du projet — la variante à deux
        // paramètres `{ old, new in }` exige iOS 17, non disponible ici).
        .onChange(of: recorder.lastRecordedURL) { url in
            guard let url else { return }
            onVideoRecorded(url, recordingElapsed)
        }
        .sheet(isPresented: $showGalleryPicker) {
            GalleryPickerView(
                onImagePicked: { url in
                    showGalleryPicker = false
                    onImagePickedFromGallery(url)
                },
                onVideoPicked: { url in
                    showGalleryPicker = false
                    onVideoPickedFromGallery(url)
                },
                onCancel: { showGalleryPicker = false }
            )
        }
    }

    // MARK: - Barre du haut : fermer + bascule caméra (port de `R.id.close`/`R.id.switch_camera`)

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            Spacer()
            if recorder.isFlashSupported {
                Button(action: { recorder.switchFlashMode() }) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
            }
            Button(action: { recorder.switchCamera() }) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
        }
        .padding()
    }

    // MARK: - Barre du bas : menu GALLERI/CAMERA/ANIMEMES (port de `mRecyclerBottom`) + capture

    /// "GALLERI" : port de `doSelection(layoutPosition == 0)` → `pickImageOrVideo()` (branche
    /// Android R+, système). La branche Android < R (`requestStoragePermission()` +
    /// `onArticleSelected(8, null)` → fragment `Gallery` interne) n'a PAS d'équivalent iOS
    /// nécessaire : `PHPickerViewController` ne demande AUCUNE permission bibliothèque photos
    /// (design privacy-first d'Apple, à la différence des deux branches Android) — pas un oubli,
    /// une simplification légitime par différence de plateforme.
    private var bottomBar: some View {
        VStack(spacing: 24) {
            captureButton

            HStack(spacing: 48) {
                Button("GALLERI") { showGalleryPicker = true }
                Text("CAMERA").fontWeight(.bold)
                Button("ANIMEMES", action: onOpenAnimems)
            }
            .font(.caption)
            .foregroundStyle(.white)
        }
    }

    /// Port de `CircleCaptureButton` — lu en entier (`captureListeer`/`OnTouchListener` +
    /// `action`/`Runnable` programmé via `mHandler.postDelayed(action, 1000)`).
    ///
    /// **Comportement RÉEL confirmé par lecture du fichier, corrige le premier jet de cette
    /// méthode** (qui utilisait `.onLongPressGesture(pressing:)` — inadapté : son paramètre
    /// `pressing` se déclenche IMMÉDIATEMENT au toucher, pas après `minimumDuration`, ce qui
    /// aurait démarré un enregistrement dès le premier contact du doigt, jamais après le vrai
    /// seuil d'1 seconde) :
    /// - `ACTION_DOWN` programme un minuteur de 1000 ms (`mHandler.postDelayed`).
    /// - Si le doigt se lève AVANT (`ACTION_UP` → `terminateRecording()`, `isVideoInit` encore
    ///   faux) : `listener.onCapture()` → **photo**. Le minuteur en attente est annulé
    ///   (`removeCallbacks`).
    /// - Si le minuteur atteint son terme AVANT le relâchement : `isVideoInit=true`,
    ///   `listener.onRecord(true)` → **démarre la vidéo**.
    /// - Au relâchement après ce seuil : `listener.onRecord(false)` → **arrête la vidéo**.
    ///
    /// Reproduit ici avec `DragGesture(minimumDistance: 0)` (détecte le toucher sans exiger de
    /// déplacement) + un `DispatchWorkItem` programmé à `captureHoldThreshold` (1 s) et annulé au
    /// relâchement anticipé — équivalent direct de `postDelayed`/`removeCallbacks`, pas une
    /// approximation.
    ///
    /// **Non reproduit, confirmé sans effet observable après lecture attentive** :
    /// `MINIMUM_VIDEO_DURATION_MILLIS`/`isRecordTooShort`/`actionListener.onDurationTooShortError`
    /// — `actionListener` n'est JAMAIS assigné dans tout le fichier (reste `null`), et
    /// `onLongPressEnd()` remet `isRecording` à `false` AVANT de tester `else if (isRecording)`
    /// pour décider d'appeler `actionListener.onEndRecord()` — ce test est donc TOUJOURS faux à
    /// cet endroit précis, rendant toute la branche `actionListener` morte dans les deux cas
    /// (aucun risque de `NullPointerException` malgré `actionListener == null`, mais aucun effet
    /// non plus). Confirmé par analyse de flux, pas supposé — rien à porter ici.
    private var captureButton: some View {
        Circle()
            .strokeBorder(.white, lineWidth: 4)
            .background(Circle().fill(isRecording ? .red : .white.opacity(0.25)))
            .frame(width: 76, height: 76)
            .gesture(captureGesture)
    }

    private var captureGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard recordingStartTask == nil, !isRecording else { return }
                let task = DispatchWorkItem { startRecording() }
                recordingStartTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + captureHoldThreshold, execute: task)
            }
            .onEnded { _ in
                recordingStartTask?.cancel()
                recordingStartTask = nil
                if isRecording {
                    stopRecording()
                } else if let image = recorder.capturePhoto() {
                    onPhotoCaptured(image)
                }
            }
    }

    // MARK: - Carrousel de filtres (port de `BaseCameraFragment.touchListener`, swipe gauche/droite)

    private var swipeToChangeFilterGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let count = CameraFilterType.allCases.count
                if value.translation.width < 0 {
                    filterIndex = (filterIndex + 1) % count
                } else {
                    filterIndex = (filterIndex - 1 + count) % count
                }
                recorder.setFilter(CameraFilterType.allCases[filterIndex])
            }
    }

    // MARK: - Enregistrement (port de `BaseCameraFragment.appRecord`)

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordingElapsed = 0
        let url = Self.videoFileURL()
        recorder.startRecording(to: url)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingElapsed += 0.1
            if recordingElapsed >= maxRecordingDuration {
                stopRecording()
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        recorder.stopRecording()
    }

    private var formattedElapsed: String {
        let minutes = Int(recordingElapsed) / 60
        let seconds = Int(recordingElapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Port de `BaseCameraFragment.getVideoFilePath`/`getVideoFileName` — dossier `Movies` Android
    /// remplacé par le répertoire `tmp` de l'app (pas d'équivalent "dossier public Films" sur iOS
    /// sans passer par `PHPhotoLibrary`, qui interviendra à l'export final, pas au moment de
    /// l'écriture du fichier temporaire).
    private static func videoFileURL() -> URL {
        let name = DateFormatter.tiinverVideoFileName.string(from: Date()) + ".mp4"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}

private extension DateFormatter {
    static let tiinverVideoFileName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM_dd-HHmmss"
        return formatter
    }()
}
