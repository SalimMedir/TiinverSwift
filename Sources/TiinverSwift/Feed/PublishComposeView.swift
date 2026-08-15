import AVFoundation
import SwiftUI

/// Port de `editor/media/MediaEditor.java` (recadrage, `ImageEditorCompound`/`CroperView`) +
/// `PublishFragment.java` (légende/hashtags) — lus en entier, 2026-08-15. Flux RÉEL, mis à jour
/// 2026-08-16 : choix du mode de recadrage (rectangle/ovale/forme libre) → recadrage → outils
/// (`PhotoToolsView` : flip, suppression d'arrière-plan, peinture, texte) → légende + hashtags.
/// Catégorie/IA-consent d'Android PAS reproduits : confirmé qu'ils ne sont PAS envoyés au serveur
/// par `HttpFileUploader.uploadRequestBody` malgré leur présence dans l'UI Android — reproduire le
/// comportement RÉEL, pas l'écran local. Stickers/emoji et image composée (ajout d'une seconde
/// image) restent hors périmètre — voir `MIGRATION_AUDIT.md`.
enum PublishMedia: Identifiable {
    case photo(UIImage)
    case video(URL)

    /// Un seul média en attente à la fois (`FeedView.pendingMedia`) — identifiant constant
    /// suffisant, pas besoin d'un identifiant par contenu.
    var id: String { if case .photo = self { "photo" } else { "video" } }
}

struct PublishComposeView: View {
    private enum Stage {
        case cropModeChoice
        case cropping(PhotoCropView.Shape)
        case freeformCropping
        case tools
        case caption
    }

    let media: PublishMedia
    var onPublished: () -> Void
    var onCancel: () -> Void

    @State private var stage: Stage
    @State private var croppedImage: UIImage?
    @State private var freeformPath = Path()
    @State private var caption = ""
    @State private var isPublishing = false
    @State private var errorText: String?
    @State private var showShareSheet = false
    @State private var publishedShareText: String?

    private static let captionLimit = 80

    init(media: PublishMedia, onPublished: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.media = media
        self.onPublished = onPublished
        self.onCancel = onCancel
        if case .photo = media { _stage = State(initialValue: .cropModeChoice) } else { _stage = State(initialValue: .caption) }
    }

    var body: some View {
        switch stage {
        case .cropModeChoice:
            if case .photo(let image) = media {
                CropModeChoiceView(
                    image: image,
                    onChoose: { shape in stage = .cropping(shape) },
                    onFreeform: { stage = .freeformCropping },
                    onCancel: onCancel
                )
            }
        case .cropping(let shape):
            if case .photo(let image) = media {
                PhotoCropView(
                    image: image,
                    shape: shape,
                    onCropped: { croppedImage = $0; stage = .tools },
                    onCancelled: { stage = .cropModeChoice }
                )
                .ignoresSafeArea()
            }
        case .freeformCropping:
            if case .photo(let image) = media, let cgImage = image.cgImage {
                FreeformCropStepView(
                    sourceImage: cgImage,
                    path: $freeformPath,
                    onValidate: { viewSize in
                        if let cropped = FreeformCropView.croppedImage(source: cgImage, path: freeformPath, viewSize: viewSize) {
                            croppedImage = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
                        } else {
                            croppedImage = image
                        }
                        stage = .tools
                    },
                    onCancel: { stage = .cropModeChoice }
                )
            }
        case .tools:
            if let croppedImage {
                PhotoToolsView(
                    sourceImage: croppedImage,
                    onDone: { self.croppedImage = $0; stage = .caption },
                    onCancel: { stage = .cropModeChoice }
                )
            }
        case .caption:
            NavigationStack {
                Form {
                    Section {
                        preview
                            .frame(maxWidth: .infinity)
                            .listRowInsets(EdgeInsets())
                    }
                    Section("Légende") {
                        // Port de `HashtagComposerView` (limite 80 caractères côté Android) —
                        // extraction des hashtags reproduite (mots commençant par "#"), l'UI de
                        // suggestion en direct N'EST PAS reproduite (secondaire, pas envoyée au
                        // serveur telle quelle de toute façon).
                        TextEditor(text: $caption)
                            .frame(minHeight: 80)
                            .onChange(of: caption) { newValue in
                                if newValue.count > Self.captionLimit {
                                    caption = String(newValue.prefix(Self.captionLimit))
                                }
                            }
                        Text("\(caption.count)/\(Self.captionLimit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
                .navigationTitle("Nouvelle publication")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Button("Publier") { Task { await publish() } }
                        }
                    }
                }
            }
            // Port de `PublishFragment` → partage natif après publication réussie
            // (`PublishFragment.java:499-526`). `onDismiss` ferme l'écran de composition qu'on ait
            // partagé ou non — le partage est une option offerte après coup, pas un blocage.
            .sheet(isPresented: $showShareSheet, onDismiss: onPublished) {
                if let publishedShareText {
                    ActivityShareSheet(items: [publishedShareText])
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch media {
        case .photo:
            if let croppedImage {
                Image(uiImage: croppedImage).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 280)
            }
        case .video(let url):
            VideoThumbnailPreview(url: url)
        }
    }

    /// Port de `MainFragment`/`FeedFragment` (réception `token="publication"`) → `publish(data)` →
    /// `ActivityService`/`HttpFileUploader` (type=0) → `POST activity/add`.
    private func publish() async {
        guard let actorId = UserSession.shared.myId else { return }
        isPublishing = true
        errorText = nil
        defer { isPublishing = false }

        let hashtags = caption.split(separator: " ").filter { $0.hasPrefix("#") }.map { String($0.dropFirst()) }
        let unixTime = Int(Date().timeIntervalSince1970)

        do {
            switch media {
            case .photo:
                guard let image = croppedImage, let jpegData = image.jpegData(compressionQuality: 0.9) else { return }
                try await FeedRepository().publish(
                    actorId: actorId, object: "photos", message: caption, hashtags: hashtags,
                    fileData: jpegData, mimeType: "image/jpeg", filename: "\(unixTime).webp"
                )
            case .video(let url):
                let videoData = try Data(contentsOf: url)
                try await FeedRepository().publish(
                    actorId: actorId, object: "videos", message: caption, hashtags: hashtags,
                    fileData: videoData, mimeType: "video/mp4", filename: "\(unixTime).mp4"
                )
            }
            publishedShareText = caption.isEmpty ? "Je viens de publier sur Tiinver !" : caption
            showShareSheet = true
        } catch {
            errorText = "La publication a échoué. Réessaie."
        }
    }
}

/// Port du `UIActivityViewController` déclenché par `PublishFragment.java:499-526` après
/// publication — texte seul (le fichier média est déjà envoyé au serveur à ce stade, on ne
/// partage pas le binaire local).
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Port de `CroperView` (choix rectangle/ovale/forme libre AVANT le recadrage) — Android présente
/// ces trois modes comme des boutons distincts plutôt qu'un recadreur unique paramétrable.
private struct CropModeChoiceView: View {
    let image: UIImage
    var onChoose: (PhotoCropView.Shape) -> Void
    var onFreeform: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                VStack(spacing: 14) {
                    Button { onChoose(.rectangle) } label: { Label("Rectangle", systemImage: "crop") }
                    Button { onChoose(.oval) } label: { Label("Ovale", systemImage: "circle") }
                    Button { onFreeform() } label: { Label("Forme libre", systemImage: "lasso") }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Recadrage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
            }
        }
    }
}

/// Enveloppe `FreeformCropView` (pur moteur de tracé, sans chrome) avec une barre d'outils
/// annuler/valider — `viewSize` transmis à `onValidate` est celui mesuré par `GeometryReader` au
/// moment du tracé, requis par `FreeformCropView.croppedImage(source:path:viewSize:)`.
private struct FreeformCropStepView: View {
    let sourceImage: CGImage
    @Binding var path: Path
    var onValidate: (CGSize) -> Void
    var onCancel: () -> Void

    @State private var measuredSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                FreeformCropView(sourceImage: sourceImage, path: $path)
                    .onAppear { measuredSize = geo.size }
                    .onChange(of: geo.size) { measuredSize = $0 }
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Valider") { onValidate(measuredSize) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct VideoThumbnailPreview: View {
    let url: URL
    @State private var thumbnail: UIImage?
    @State private var durationText: String?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color(.secondarySystemBackground)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .shadow(radius: 4)
            if let durationText {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(durationText)
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .task { await loadMetadata() }
    }

    /// Port de `PublishFragment.java:213-217,597-643` (miniature Glide + durée) — extraction réelle
    /// via `AVAssetImageGenerator`/`AVURLAsset.duration` plutôt que l'icône statique de la première
    /// passe de ce portage.
    private func loadMetadata() async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let cgImage = try? await generator.image(at: .zero).image {
            thumbnail = UIImage(cgImage: cgImage)
        }
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 {
            let totalSeconds = Int(seconds)
            durationText = String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
        }
    }
}
