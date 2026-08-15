import SwiftUI

/// Port de `editor/media/MediaEditor.java` (recadrage, `ImageEditorCompound`/`CroperView`) +
/// `PublishFragment.java` (légende/hashtags) — lus en entier, 2026-08-15. Périmètre RÉEL
/// reproduit : recadrage (déjà porté, `PhotoCropView`, réutilisé tel quel) puis légende +
/// hashtags. **Peinture/texte/stickers d'`ImageEditorCompound` volontairement PAS repris** — usage
/// confirmé secondaire par rapport au flux de publication principal (crop → légende → publication),
/// à porter dans une passe dédiée si nécessaire. Catégorie/IA-consent d'Android également PAS
/// reproduits : confirmé qu'ils ne sont PAS envoyés au serveur par `HttpFileUploader.
/// uploadRequestBody` malgré leur présence dans l'UI Android — reproduire le comportement RÉEL, pas
/// l'écran local.
enum PublishMedia: Identifiable {
    case photo(UIImage)
    case video(URL)

    /// Un seul média en attente à la fois (`FeedView.pendingMedia`) — identifiant constant
    /// suffisant, pas besoin d'un identifiant par contenu.
    var id: String { if case .photo = self { "photo" } else { "video" } }
}

struct PublishComposeView: View {
    let media: PublishMedia
    var onPublished: () -> Void
    var onCancel: () -> Void

    @State private var croppedImage: UIImage?
    @State private var showCrop: Bool
    @State private var caption = ""
    @State private var isPublishing = false
    @State private var errorText: String?

    init(media: PublishMedia, onPublished: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.media = media
        self.onPublished = onPublished
        self.onCancel = onCancel
        if case .photo = media { _showCrop = State(initialValue: true) } else { _showCrop = State(initialValue: false) }
    }

    var body: some View {
        if case .photo(let image) = media, showCrop {
            PhotoCropView(
                image: image,
                onCropped: { croppedImage = $0; showCrop = false },
                onCancelled: onCancel
            )
            .ignoresSafeArea()
        } else {
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
            onPublished()
        } catch {
            errorText = "La publication a échoué. Réessaie."
        }
    }
}

private struct VideoThumbnailPreview: View {
    let url: URL
    var body: some View {
        Image(systemName: "video.fill")
            .font(.system(size: 40))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(Color(.secondarySystemBackground))
    }
}
