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

/// Port des 3 champs `content_type`/`style`/`template_id` propagés UNIQUEMENT pour une publication
/// issue de l'éditeur Animems (`AnimemesCompound.java:2597-2648`, V5-F-083) — `nil` pour tout autre
/// flux de publication (Galerie/caméra), voir `PublishComposeView.animemsMetadata`.
struct AnimemsPublishMetadata {
    /// `AnimemesEditorState.activeCommunityTemplateId` — `nil` sauf si un modèle COMMUNAUTAIRE
    /// (pas un modèle sauvegardé localement) est actif au moment de l'export. Utilisé UNIQUEMENT
    /// pour une vidéo/animation (`createImage()` côté Android n'inclut jamais `template_id`).
    var templateId: String?
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
    /// `nil` pour tout flux de publication standard (Galerie/caméra) — renseigné uniquement par
    /// `AnimemesEditorView` (V5-F-083, voir `AnimemsPublishMetadata`).
    var animemsMetadata: AnimemsPublishMetadata?
    var onPublished: () -> Void
    var onCancel: () -> Void

    @State private var stage: Stage
    @State private var croppedImage: UIImage?
    @State private var freeformPath = Path()
    @State private var caption = ""
    @State private var isPublishing = false
    /// Port du callback `onProgress(percentage)` (V3-F-019, BUNNY-03) — `nil` tant qu'aucun octet
    /// n'a été envoyé (photo, ou vidéo pas encore démarrée) ; fraction 0...1 une fois l'upload
    /// vidéo en cours, fidèle à `updateView(progress)` Android.
    @State private var videoUploadProgress: Double?
    @State private var errorText: String?
    @State private var showShareSheet = false
    @State private var publishedShareText: String?
    /// Port de `PublishFragment.java:274-283` (V3-F-058, Phase B P1) — `post.setOnClickListener`
    /// vérifie `getCurrentCategory()` AVANT de publier ; si vide, lance `CategoryActivity` et
    /// n'appelle `proceedToPublish` qu'après un choix confirmé (retour avec `categoryId` non vide).
    @State private var showCategoryPicker = false
    @State private var resolvedCategory: String?
    /// Port de la `CheckBox` `R.id.acceptAi` (`fragment_publish.xml:86-92`,
    /// `@string/allow_my_content_for_ai_training`) — **ajouté le 2026-08-24
    /// (MIGRATION_PARITY_AUDIT_V4.md V4-F-029, Phase B P1)** : décoché par défaut, fidèle à l'état
    /// initial d'une `CheckBox` Android sans `android:checked="true"` explicite dans le layout.
    @State private var acceptAiConsent = false

    private static let captionLimit = 80

    init(media: PublishMedia, animemsMetadata: AnimemsPublishMetadata? = nil, onPublished: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.media = media
        self.animemsMetadata = animemsMetadata
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
                // Port de `CropFragment.java:60-77` (V3-F-034, vérifié contre `CameraActivity.
                // onArticleSelected` cases 3/4, `editor/CameraActivity.java:156-169`) — Android
                // affiche `btn_rect`/`btn_oval` EN PERMANENCE sur l'écran de recadrage lui-même
                // (les deux `RelativeLayout` sont rendus `VISIBLE` inconditionnellement dans
                // `onViewCreated`, quel que soit le mode courant) : changer de forme ne demande
                // JAMAIS de quitter l'écran de recadrage, juste un tap sur l'autre bouton, qui
                // recharge un `CropFragment` neuf dans l'autre forme (`openFragment(..., false)`,
                // `replace` — donc l'état de recadrage en cours est perdu des DEUX côtés, Android
                // y compris, pas une régression iOS). **Avant ce correctif**, la seule façon de
                // changer de forme côté iOS était le bouton "Annuler" générique de
                // `TOCropViewController` (`PhotoCropView.onCancelled`, sémantiquement "abandonner",
                // pas "changer de forme") qui ramène à `.cropModeChoice` — fonctionnellement
                // possible mais peu découvrable, contrairement au vrai comportement Android.
                // Ajout d'une barre d'outils explicite Rectangle/Ovale directement sur l'écran de
                // recadrage, fidèle à la présence permanente des 2 boutons Android — bascule
                // directement `stage` vers l'autre forme (équivalent du `replace` Android, sans
                // repasser par l'écran de choix intermédiaire).
                // Superposition en BAS (pas en haut) : `TOCropViewController` a sa propre barre de
                // navigation native Annuler/Terminer en haut de l'écran (confirmée lors du portage
                // initial du module 9, voir doc de tête de `PhotoCropView.swift`) — un ajout en haut
                // la recouvrirait.
                ZStack(alignment: .bottom) {
                    PhotoCropView(
                        image: image,
                        shape: shape,
                        onCropped: { croppedImage = $0; stage = .tools },
                        onCancelled: { stage = .cropModeChoice }
                    )
                    .ignoresSafeArea()
                    cropShapeSwitcher(current: shape)
                }
            }
        case .freeformCropping:
            // Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-056, Phase B P1) : le mode
            // rect/oval (`.cropping`, ci-dessus) passe par `TOCropViewController`, qui respecte
            // `imageOrientation` — seul CE mode opérait directement sur `image.cgImage` (buffer
            // brut, pixels non tournés), dessiné ensuite via `Image(decorative:)` dans
            // `FreeformCropView.body`, qui IGNORE `imageOrientation` (contrairement à
            // `Image(uiImage:)`). Une photo portrait EXIF (`imageOrientation != .up`) apparaissait
            // donc de côté/en miroir pendant le tracé ET dans le résultat composé. Normalise
            // d'abord vers `.up` (mêmes pixels que verrait Android après `rotateBitmapByExif`,
            // `BitmapLoadingWorkerTask.java:76`, appliqué en amont pour TOUS les sous-modes de
            // recadrage) avant d'extraire le `cgImage` passé à `FreeformCropStepView`.
            if case .photo(let image) = media {
                let normalizedImage = image.normalizedToUpOrientation()
                if let cgImage = normalizedImage.cgImage {
                    FreeformCropStepView(
                        sourceImage: cgImage,
                        path: $freeformPath,
                        onValidate: { viewSize in
                            if let cropped = FreeformCropView.croppedImage(source: cgImage, path: freeformPath, viewSize: viewSize) {
                                // Source déjà normalisée à `.up` : le résultat découpé l'est aussi,
                                // pas besoin de réappliquer `image.imageOrientation` (qui
                                // double-tournerait le résultat).
                                croppedImage = UIImage(cgImage: cropped, scale: normalizedImage.scale, orientation: .up)
                            } else {
                                croppedImage = image
                            }
                            stage = .tools
                        },
                        onCancel: { stage = .cropModeChoice }
                    )
                }
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
                    // Port de `R.id.acceptAi` — positionné juste au-dessus du bouton de partage
                    // côté Android (`layout_above="@+id/share"`), reproduit ici juste avant
                    // l'action de publication (V4-F-029).
                    Section {
                        Toggle("Autoriser l'utilisation de mon contenu pour l'entraînement de l'IA", isOn: $acceptAiConsent)
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
                            if let videoUploadProgress {
                                ProgressView(value: videoUploadProgress)
                            } else {
                                ProgressView()
                            }
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

    /// Port de `btn_rect`/`btn_oval` (`CropFragment.java:60-77`, V3-F-034) — barre de bascule de
    /// forme TOUJOURS visible sur l'écran de recadrage, fidèle à Android (les 2 boutons y sont
    /// affichés en permanence, pas seulement à l'écran de choix initial). Le bouton correspondant à
    /// la forme COURANTE est désactivé/surligné (Android ne désactive pas visuellement son propre
    /// bouton actif, mais retaper la même forme relance juste un recadrage identique côté Android —
    /// désactivé ici pour éviter une recharge inutile de `TOCropViewController`, différence
    /// mineure sans impact fonctionnel).
    private func cropShapeSwitcher(current: PhotoCropView.Shape) -> some View {
        HStack(spacing: 24) {
            cropShapeButton(.rectangle, systemImage: "crop", label: "Rectangle", isActive: current == .rectangle)
            cropShapeButton(.oval, systemImage: "circle", label: "Ovale", isActive: current == .oval)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 24)
    }

    private func cropShapeButton(_ shape: PhotoCropView.Shape, systemImage: String, label: String, isActive: Bool) -> some View {
        Button {
            stage = .cropping(shape)
        } label: {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(isActive ? .bold : .regular))
                .foregroundStyle(isActive ? Color.accentColor : .primary)
        }
        .disabled(isActive)
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
    ///
    /// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-076, Phase B P1-31)**
    /// — Android protège tout l'upload (BunnyCDN + `activity/add`) par un vrai `Service` en
    /// foreground (`ActivityService.onStartCommand`, `startForeground`), insensible à la mise en
    /// arrière-plan de l'app. Portée réduite documentée : plutôt que de porter l'infrastructure
    /// complète (file d'attente persistée en Core Data + reprise après échec réseau, cf.
    /// `FILE_TRANSFERT_URI`), on applique ici l'option "à défaut" de la RECOMMANDATION —
    /// `UIApplication.shared.beginBackgroundTask` enveloppe l'upload pour qu'il survive au passage
    /// en arrière-plan (~30s, prolongeable par iOS selon la charge système), au lieu d'être
    /// suspendu immédiatement comme un `Task` non protégé. La persistance/reprise après un échec
    /// réseau complet (app tuée, backgroundTask expiré) N'EST PAS traitée par ce correctif — hors
    /// périmètre du cas le plus fréquent (bascule brève vers une autre app / verrouillage d'écran
    /// pendant l'upload), qui est celui réellement corrigé ici.
    private func publish() async {
        var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "PublishUpload") {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
        defer {
            if backgroundTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskId)
            }
        }
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
        videoUploadProgress = nil
        errorText = nil
        defer { isPublishing = false }

        // **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-049, Phase B P2)** — port de
        // `PublishFragment.extractHashtags` (`Pattern.compile("#(\\w+)")`) via
        // `HashtagMentionText.extractHashtags`, réutilisant la même regex déjà portée pour
        // l'affichage. Le split-par-espace précédent laissait la ponctuation de fin collée
        // ("#sunset," → "sunset,") et ratait un hashtag sans espace précédent ("jour#tag").
        let hashtags = HashtagMentionText.extractHashtags(from: caption)

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
                    fileData: jpegData, category: resolvedCategory, width: Int(pixelSize.width), height: Int(pixelSize.height),
                    consentAi: acceptAiConsent,
                    // Port de `createImage()` (`AnimemesCompound.java:2597-2602`, V5-F-083) —
                    // `template_id` JAMAIS inclus pour une image statique, même côté Android.
                    contentType: animemsMetadata != nil ? "image" : nil,
                    style: animemsMetadata != nil ? "animemes" : nil
                )
            case .video(let url):
                // Corrigé (V3-F-019, BUNNY-03) : ne charge plus toute la vidéo en `Data` avant
                // l'upload (risque réel d'OOM sur une vidéo volumineuse) — `FeedRepository.publish`
                // prend maintenant directement l'URL du fichier et streame depuis le disque, fidèle
                // à `ProgressRequestBodyUri`/`InputStream` côté Android.
                let fileBytes = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
                print("PUBLISH REQUEST: object=videos captionLength=\(caption.count) fileBytes=\(fileBytes.flatMap { $0 } ?? -1) — flux réel : BunnyCDN Video Library puis activity/add (métadonnées)")
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
                // Port de `getVideoMetadata`'s extraction fps/piste audio (`PublishFragment.java:
                // 597-639`, V4-F-029) — MÊME piste vidéo déjà chargée ci-dessous pour width/height,
                // `nominalFrameRate` étant l'équivalent AVFoundation de `MediaFormat.KEY_FRAME_RATE`.
                var videoFps: Int?
                var videoHasAudio: Bool?
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                    let naturalSize = try? await track.load(.naturalSize),
                    let transform = try? await track.load(.preferredTransform)
                {
                    let oriented = naturalSize.applying(transform)
                    videoWidth = Int(abs(oriented.width))
                    videoHeight = Int(abs(oriented.height))
                    if let frameRate = try? await track.load(.nominalFrameRate), frameRate > 0 {
                        videoFps = Int(frameRate.rounded())
                    }
                }
                videoHasAudio = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
                if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0 {
                    videoDurationMs = Int(seconds * 1000)
                }
                try await FeedRepository().publish(
                    actorId: actorId, object: "videos", message: caption, hashtags: hashtags,
                    videoFileURL: url, category: resolvedCategory, width: videoWidth, height: videoHeight,
                    videoDurationMs: videoDurationMs, consentAi: acceptAiConsent,
                    videoFps: videoFps, videoHasAudio: videoHasAudio,
                    // Port de `createVideosFromBitmap()` (`AnimemesCompound.java:2645-2647`,
                    // V5-F-083) — `template_id` seulement si un modèle COMMUNAUTAIRE était actif.
                    contentType: animemsMetadata != nil ? "animation" : nil,
                    style: animemsMetadata != nil ? "animemes" : nil,
                    templateId: animemsMetadata?.templateId,
                    uploadProgress: { fraction in
                        Task { @MainActor in videoUploadProgress = fraction }
                    }
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

/// V4-F-056 — redessine le bitmap selon `imageOrientation` (`draw(in:)` la respecte, contrairement
/// à un accès direct à `.cgImage`) pour obtenir un buffer dont les pixels sont déjà dans le bon
/// sens. Nécessaire uniquement pour le chemin `FreeformCropView` (`Canvas`/`Image(decorative:)`,
/// qui ignore `imageOrientation`) — le mode rect/oval (`TOCropViewController`) n'en a pas besoin,
/// il respecte déjà l'orientation nativement.
private extension UIImage {
    func normalizedToUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
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
