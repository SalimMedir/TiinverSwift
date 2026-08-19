import AVFoundation
import SwiftUI

/// Port de `editor/media/MediaEditor.java` (recadrage, `ImageEditorCompound`/`CroperView`) +
/// `PublishFragment.java` (légende/hashtags) — lus en entier, 2026-08-15. Flux RÉEL, mis à jour
/// 2026-08-16 : choix du mode de recadrage (rectangle/ovale/forme libre) → recadrage → outils
/// (`PhotoToolsView` : flip, suppression d'arrière-plan, peinture, texte) → légende + hashtags.
///
/// **Corrigé le 2026-08-19 (V3-F-017 BUNNY-01, Phase B P1)** — l'affirmation précédente
/// ("Catégorie/IA-consent PAS envoyés au serveur, confirmé dans `HttpFileUploader.
/// uploadRequestBody`") mélangeait 2 appels HTTP distincts : `uploadRequestBody` est le SEUL upload
/// binaire vers Bunny (où ces champs n'ont effectivement pas leur place), PAS l'appel de métadonnées
/// `activity/add` (`ActivityService.java`, séparé), qui les envoie bien réellement — voir
/// `FeedRepository.publish` pour la trace complète et la portée exacte de ce qui est maintenant
/// envoyé. Stickers/emoji et image composée (ajout d'une seconde image) restent hors périmètre —
/// voir `MIGRATION_AUDIT.md`.
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
    /// Port de `PublishFragment.java:274-283` (V3-F-058, Phase B P1) — `post.setOnClickListener`
    /// vérifie `getCurrentCategory()` AVANT de publier ; si vide, lance `CategoryActivity` et
    /// n'appelle `proceedToPublish` qu'après un choix confirmé (retour avec `categoryId` non vide).
    @State private var showCategoryPicker = false
    @State private var resolvedCategory: String?

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
            // Port de `CategoryActivity` (V3-F-058) — sélection FORCÉE avant publication quand le
            // compte n'a pas encore de catégorie, fidèle à `PublishFragment.categoryLauncher` :
            // `proceedToPublish` n'est appelé qu'après un `categoryId` non vide (annuler = aucune
            // publication, comme le commentaire Android "Si l'user est revenu sans choisir → on ne
            // fait rien").
            .fullScreenCover(isPresented: $showCategoryPicker) {
                CategoryPickerView(
                    currentCategoryId: resolvedCategory,
                    onSaved: { categoryId in
                        resolvedCategory = categoryId
                        showCategoryPicker = false
                        Task { await publish() }
                    },
                    onCancel: { showCategoryPicker = false }
                )
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
    ///
    /// **Bug réel trouvé et corrigé (2026-08-16, test Appetize : "je clique sur Publier mais rien
    /// ne se passe")** : les deux `guard` de cette fonction faisaient un `return` SILENCIEUX (pas
    /// d'erreur affichée, pas de fermeture d'écran) si `myId` était nil (session) OU si
    /// `croppedImage` était nil — dans les deux cas, l'utilisateur voit très exactement "rien ne se
    /// passe" en tapant Publier, sans le moindre indice de la cause. Les deux surfacent maintenant
    /// `errorText` (déjà affiché dans le formulaire) au lieu de disparaître silencieusement, fidèle
    /// à la consigne explicite de ne jamais laisser une erreur être invisible.
    private func publish() async {
        print("SESSION: myId=\(UserSession.shared.myId ?? "nil") apiKey.isEmpty=\(UserSession.shared.apiKey?.isEmpty ?? true) authenticated=\(UserSession.shared.isLoggedIn)")
        guard let actorId = UserSession.shared.myId else {
            errorText = "Session invalide — reconnecte-toi puis réessaie."
            print("PUBLISH REQUEST: aborted — UserSession.shared.myId is nil")
            return
        }

        // Port de `post.setOnClickListener` (`PublishFragment.java:274-283`, V3-F-058) — vérifie la
        // catégorie de compte AVANT de publier ; si absente, ouvre le sélecteur et ARRÊTE ici (la
        // publication reprend depuis `CategoryPickerView.onSaved`, qui rappelle `publish()`).
        if resolvedCategory == nil {
            if let profile = try? await ProfileRepository.shared.fetchProfile(userId: actorId, viewerId: actorId),
                let category = profile.category, !category.isEmpty
            {
                resolvedCategory = category
            } else {
                showCategoryPicker = true
                print("PUBLISH REQUEST: aborted — aucune catégorie de compte définie, sélecteur ouvert")
                return
            }
        }

        isPublishing = true
        errorText = nil
        defer { isPublishing = false }

        let hashtags = caption.split(separator: " ").filter { $0.hasPrefix("#") }.map { String($0.dropFirst()) }

        do {
            switch media {
            case .photo:
                guard let image = croppedImage, let jpegData = image.jpegData(compressionQuality: 0.9) else {
                    errorText = "Image invalide — reviens en arrière et réessaie."
                    print("PUBLISH REQUEST: aborted — croppedImage is nil or JPEG encoding failed")
                    return
                }
                print("PUBLISH REQUEST: object=photos captionLength=\(caption.count) fileBytes=\(jpegData.count) — flux réel : BunnyCDN Storage puis activity/add (métadonnées)")
                // Port de `ActivityService.java` `width`/`height` (V3-F-017) — dimensions réelles en
                // pixels de l'image publiée, pas la taille du `UIImage` mise à l'échelle pour l'écran.
                let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
                try await FeedRepository().publish(
                    actorId: actorId, object: "photos", message: caption, hashtags: hashtags,
                    fileData: jpegData, category: resolvedCategory, width: Int(pixelSize.width), height: Int(pixelSize.height)
                )
            case .video(let url):
                let videoData = try Data(contentsOf: url)
                print("PUBLISH REQUEST: object=videos captionLength=\(caption.count) fileBytes=\(videoData.count) — flux réel : BunnyCDN Video Library puis activity/add (métadonnées)")
                // Port de `ActivityService.java` `width`/`height`/`video_duration` (V3-F-017) —
                // dimensions natives + durée réelle de la vidéo publiée. Unité de `video_duration`
                // NON confirmée dans le code source Android lu cette passe (aucun producteur trouvé
                // de l'extra `"duration"` dans le flux Galerie de base, seulement transmis tel quel
                // par `PublishFragment`) — millisecondes retenues par convention Android standard
                // (`MediaMetadataRetriever`/`MediaPlayer.getDuration()`), à vérifier sur un test réel.
                let asset = AVURLAsset(url: url)
                var videoWidth: Int?
                var videoHeight: Int?
                var videoDurationMs: Int?
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                    let naturalSize = try? await track.load(.naturalSize),
                    let transform = try? await track.load(.preferredTransform)
                {
                    let oriented = naturalSize.applying(transform)
                    videoWidth = Int(abs(oriented.width))
                    videoHeight = Int(abs(oriented.height))
                }
                if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 {
                    videoDurationMs = Int(seconds * 1000)
                }
                try await FeedRepository().publish(
                    actorId: actorId, object: "videos", message: caption, hashtags: hashtags,
                    fileData: videoData, category: resolvedCategory, width: videoWidth, height: videoHeight,
                    videoDurationMs: videoDurationMs
                )
            }
            print("PUBLISH RESPONSE: success")
            publishedShareText = caption.isEmpty ? "Je viens de publier sur Tiinver !" : caption
            showShareSheet = true
        } catch {
            print("PUBLISH RESPONSE: error=\(error)")
            errorText = "La publication a échoué : \(error.localizedDescription)"
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
