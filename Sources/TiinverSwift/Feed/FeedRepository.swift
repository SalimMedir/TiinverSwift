import CoreData
import Foundation

/// Port de `Activity/repository/ActivityRepository.getMediasPubFromServer`/
/// `Http/TransportData.addActivities` (flux réseau + cache local `wk_activities`).
final class FeedRepository {
    private let activities: CoreDataRepository<ActivityEntity>

    init(stack: CoreDataContextProviding = CoreDataStack.shared) {
        self.activities = CoreDataRepository(stack: stack)
    }

    /// Port de `td.get("feedtimeline/" + userId + "/" + limit + "/" + offset, ...)`.
    ///
    /// **Log de diagnostic temporaire (2026-08-16)** — `compactMap` avalait silencieusement tout
    /// item dont le décodage `Codable` échouait (ex. un champ non-optionnel dont le type JSON réel
    /// diffère de ce qu'attend `FeedActivity`), produisant un tableau final PLUS PETIT que le
    /// nombre d'éléments réellement reçus, SANS aucune erreur visible — symptôme indiscernable côté
    /// UI d'un flux réellement vide. Rendu visible ici plutôt que supposé correct.
    struct TimelineResult {
        var activities: [FeedActivity]
        /// Nombre RÉEL d'éléments reçus dans le tableau "activities" AVANT tout filtrage de
        /// décodage — permet à l'appelant (`FeedViewModel`) d'afficher à l'écran la distinction
        /// "reçu N, affiché M" plutôt que de ne connaître que M (voir note ci-dessous).
        var receivedCount: Int
    }

    func fetchTimeline(userId: Int, limit: Int, offset: Int) async throws -> TimelineResult {
        let json = try await APIClient.shared.get("feedtimeline/\(userId)/\(limit)/\(offset)")
        let array = try json.jsonArray("activities")
        let decoded = array.compactMap { item -> FeedActivity? in
            guard let data = item.rawData else {
                print("FEED RESPONSE: item.rawData nil for one activity — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(FeedActivity.self, from: data)
            } catch {
                print("FEED RESPONSE: decode failure for one activity — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("FEED RESPONSE: received=\(array.count) activities, only \(decoded.count) decoded successfully — \(array.count - decoded.count) silently dropped, see decode failures above")
        }
        return TimelineResult(activities: decoded, receivedCount: array.count)
    }

    /// Port de `ShareActivity.getPost`/`connectToServeur` (`getactivity/{token}`, clé de réponse
    /// `"activity"`) — résolution d'un lien profond `/post/{token}` (`DeepLinkRouter.swift`,
    /// 2026-08-16).
    func fetchPost(byToken token: String) async throws -> FeedActivity {
        let value = try await APIClient.shared.get("getactivity/\(token)")
        guard value.isBackendSuccess, let data = try? value.stringEncodedJSON("activity"),
              let raw = data.rawData
        else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "getactivity") }
        return try JSONDecoder().decode(FeedActivity.self, from: raw)
    }

    /// Port de `TransportData.addActivities` : cache local plafonné à 10 lignes. Reproduit
    /// FIDÈLEMENT la politique observée (pas "corrigée") — au-delà de 10 lignes déjà en cache,
    /// TOUTES les lignes existantes sont supprimées avant de réinsérer le nouveau lot, plutôt que
    /// d'évincer seulement les plus anciennes une à une (la logique d'éviction sélective par id
    /// est en commentaire dans le fichier source Android, jamais activée).
    func cache(_ items: [FeedActivity]) async throws {
        let existingCount = try await activities.count()
        if existingCount >= 10 {
            try await activities.delete(predicate: nil)
        }
        for item in items {
            try await activities.insert { row in
                row.id = Int64(item.id)
                row.actor = item.actor
                row.verb = item.verb
                row.object = item.object
                row.objectUrl = item.object_url
                row.cdnThumbnailUrl = item.cdn_thumbnail_url
                row.cdnContentId = item.cdn_content_id
                row.message = item.message
                row.likes = Int64(item.likes ?? 0)
                row.comment = Int64(item.comment ?? 0)
                row.share = Int64(item.share ?? 0)
                row.isLiked = item.isLiked
                row.stamp = item.stamp
                row.userId = item.userId.map(String.init)
                row.firstname = item.firstname
                row.lastname = item.lastname
                row.profile = item.profile
                row.location = item.location
                row.username = item.username
                row.certified = item.certified
                row.followers = item.followers
                row.following = item.following
                row.origin = "server"
                row.isNew = "true"
            }
        }
    }

    func cachedActivities() async throws -> [ActivityEntity] {
        try await activities.query(sortDescriptors: [NSSortDescriptor(key: "stamp", ascending: false)])
    }

    /// Port de la branche `wk_activities` de `transportDataBackground.deleteaccount()` — voir
    /// `LocalDataPurger.swift`.
    func purgeCache() async throws {
        try await activities.delete(predicate: nil)
    }

    /// **CORRIGÉ le 2026-08-17 (`MIGRATION_PARITY_AUDIT_V2.md` P0-1, cause racine réelle confirmée
    /// en traçant `Activity/service/ActivityService.java` en entier, PAS `HttpFileUploader.java`
    /// comme le supposait le commentaire précédent — voir `FeedMediaUploader.swift` pour la trace
    /// complète)** : le fichier média n'est JAMAIS envoyé au backend Tiinver directement. Flux réel
    /// en 2 étapes : (1) upload direct vers BunnyCDN (`FeedMediaUploader.uploadPhoto`/`uploadVideo`,
    /// Storage pour les photos, Video Library HLS pour les vidéos) ; (2) `POST activity/add` avec
    /// SEULEMENT des métadonnées texte (`cdn_content_id`/`cdn_content_url`/`cdn_thumbnail_url`/
    /// `cdn_provider`/`object_url`) — jamais de fichier.
    ///
    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-017 BUNNY-01, Phase B P1)** — la
    /// prétention "category/metadata/template_id/consentAi non envoyés par Android non plus,
    /// vérifié dans sendMetaDate" était fausse, un mélange entre 2 appels HTTP DIFFÉRENTS :
    /// `HttpFileUploader.uploadRequestBody` (upload binaire multipart vers Bunny, où ces champs
    /// n'ont effectivement pas leur place) VS `ActivityService.java:184-201` — le VRAI appel
    /// `activity/add`, qui envoie bien `category`/`video_duration`/`width`/`height`/`metadata`/
    /// `template_id`/`consentAi`. Confirmé aussi (`PublishFragment.java:274-283,350-362`) que
    /// `category` est OBLIGATOIRE et BLOQUE la publication tant que l'utilisateur n'a pas défini de
    /// catégorie de compte (`CategoryActivity`, écran forcé si `ACCOUNT_URI.category` est vide).
    ///
    /// **Portée du correctif V3-F-017** : `category` (best-effort, lu depuis le profil courant),
    /// `width`/`height` (dimensions réelles du média) envoyés. `metadata`/`template_id` envoyés
    /// vides, `consentAi` envoyé à `"0"` — le gap "aucun bascule de consentement IA n'existe dans
    /// `PublishComposeView`" était explicitement documenté ici comme NON construit dans ce lot.
    ///
    /// **Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-029, Phase B P1)** — ce gap est
    /// maintenant comblé : `PublishComposeView` porte un vrai bascule de consentement IA (port de
    /// la `CheckBox` `R.id.acceptAi`, `fragment_publish.xml:86-92`, libellé exact
    /// `@string/allow_my_content_for_ai_training`), `consentAi` envoyé fidèlement, et `metadata`
    /// construit comme un vrai JSON reproduisant `models/MediaMetaData.java` (`getImageMetadata`/
    /// `getVideoMetadata`, `PublishFragment.java:544-639`, lus en entier) — voir `MediaMetaData`
    /// ci-dessous pour le détail champ par champ, y compris les 2 champs Android confirmés TOUJOURS
    /// `null`/`0` (`style`/`content_type`/`bitRate` : déclarés dans `MediaMetaData.java` mais AUCUN
    /// `setStyle`/`setContent_type`/`setBitRate` trouvé nulle part dans `PublishFragment.java` —
    /// reproduit fidèlement tel quel, PAS une omission de ce portage). `template_id` reste vide :
    /// aucun gabarit Animems n'est sélectionnable depuis ce flux Galerie standard côté Android non
    /// plus (`template_id` n'a de valeur réelle que pour un post exporté depuis l'éditeur Animems,
    /// flux séparé). **NE reproduit toujours PAS** le blocage de publication tant qu'aucune
    /// catégorie n'est définie (V3-F-058, gap distinct déjà documenté, hors périmètre de CE lot).
    enum PublishError: Error { case missingMedia }

    /// Port de `models/MediaMetaData.java` — noms de champs Gson EXACTS (aucune `@SerializedName`
    /// côté Android, donc aucun renommage ici non plus). Sérialisé dans le champ texte `metadata`
    /// d'`activity/add` (`ActivityService.sendMetaDate`).
    struct MediaMetaData: Encodable {
        var width: Int
        var height: Int
        var duration: Double
        var fps: Int
        var bitRate: Int = 0
        var hasAudio: Bool
        var consentAi: Bool
        var license: String
        var format: String?
        var content_type: String?
        var style: String?
        var language: String?
        var country: String?
        var locale: String?
    }

    /// `fileData` (photo, déjà en mémoire post-recadrage/ré-encodage JPEG) et `videoFileURL`
    /// (vidéo, streamée depuis le disque — voir `FeedMediaUploader.uploadVideo`, V3-F-019) sont
    /// mutuellement exclusifs selon `object` ; `uploadProgress` (vidéo uniquement, fraction 0...1)
    /// est ignoré pour une photo (upload trop court pour qu'une barre de progression soit utile,
    /// fidèle à l'absence de source de streaming côté client pour ce cas précis — voir le
    /// commentaire de `FeedMediaUploader.uploadVideo`).
    func publish(
        actorId: String, object: String, message: String, hashtags: [String],
        fileData: Data? = nil, videoFileURL: URL? = nil,
        category: String? = nil, width: Int? = nil, height: Int? = nil, videoDurationMs: Int? = nil,
        consentAi: Bool = false, videoFps: Int? = nil, videoHasAudio: Bool? = nil,
        uploadProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // `category` : **corrigé le 2026-08-19 (V3-F-058 PROFILE-03)** — désormais transmis par
        // l'appelant (`PublishComposeView`, qui gère le blocage/sélection forcée, port de
        // `PublishFragment.java:274-283`) plutôt que refetché ici en interne (évitait un double
        // appel réseau redondant avec la vérification de blocage faite en amont).
        // Port de `Cryptography.generateUniqueBase64ID(myId)` — UNE SEULE valeur générée ici,
        // réutilisée comme nom de fichier BunnyCDN ET comme paramètre `token` de `activity/add`,
        // exactement comme Android réutilise le même `data.getToken()` aux deux endroits.
        let token = UUID().uuidString

        var cdnContentId: String
        var cdnContentUrl: String
        var cdnThumbnailUrl: String?

        print("FEED PUBLISH: step=1/2 uploading to BunnyCDN object=\(object) token=\(token)")
        do {
            if object == "videos" {
                guard let videoFileURL else { throw PublishError.missingMedia }
                let result = try await FeedMediaUploader.uploadVideo(
                    token: token, fileURL: videoFileURL, progress: uploadProgress
                )
                cdnContentId = result.cdnContentId
                cdnContentUrl = result.cdnContentUrl
                cdnThumbnailUrl = result.cdnThumbnailUrl
            } else {
                guard let fileData else { throw PublishError.missingMedia }
                let result = try await FeedMediaUploader.uploadPhoto(token: token, jpegData: fileData)
                cdnContentId = result.cdnContentId
                cdnContentUrl = result.cdnContentUrl
            }
        } catch {
            print("FEED PUBLISH: step=1/2 BunnyCDN upload FAILED error=\(error)")
            throw error
        }
        print("FEED PUBLISH: step=1/2 BunnyCDN upload OK cdn_content_url=\(cdnContentUrl)")

        // Port de `getImageMetadata`/`getVideoMetadata` (`PublishFragment.java:555-639`, lu en
        // entier) — voir `MediaMetaData` et le commentaire de tête pour le détail champ par champ
        // (V4-F-029). `duration` en SECONDES (`Double`) — distinct du `video_duration` en
        // millisecondes envoyé comme paramètre TOP-NIVEAU juste en dessous, les deux coexistent
        // réellement côté Android (`KEY_DURATION / 1_000_000f` vs `data.getDuration()`, 2 champs
        // séparés dans 2 endroits différents du payload, pas un doublon à fusionner).
        let deviceLocale = Locale.current
        let metadata = MediaMetaData(
            width: width ?? 0,
            height: height ?? 0,
            duration: object == "videos" ? Double(videoDurationMs ?? 0) / 1000.0 : 0,
            fps: object == "videos" ? (videoFps ?? 0) : 0,
            hasAudio: object == "videos" ? (videoHasAudio ?? false) : false,
            consentAi: consentAi,
            license: consentAi ? "ai_training_non_exclusive" : "no_ai",
            // Port de `getImageMetadata`'s `meta.setFormat(mimeType)` — SEULE la branche photo
            // fixe ce champ côté Android (`getVideoMetadata` ne l'appelle jamais), reproduit tel
            // quel : `format` reste `nil` pour une vidéo, fidèle au JSON Android réel.
            format: object == "videos" ? nil : "image/jpeg",
            // `style`/`content_type` : déclarés côté Android mais JAMAIS assignés dans
            // `PublishFragment.java` (aucun `style = ...`/`contentType = ...` trouvé par grep
            // exhaustif) — restent `null` dans CHAQUE publication Android réelle, reproduit à
            // l'identique plutôt qu'une valeur inventée.
            content_type: nil,
            style: nil,
            language: deviceLocale.language.languageCode?.identifier,
            country: deviceLocale.region?.identifier,
            locale: deviceLocale.identifier
        )
        let metadataJSON = (try? JSONEncoder().encode(metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? ""

        var params: [String: String] = [
            "token": token,
            "actor": actorId,
            "verb": "post",
            "object": object,
            "message": message,
            "hashtags": hashtags.joined(separator: ","),
            "format": "json",
            "cdn_provider": "bunny",
            "cdn_content_id": cdnContentId,
            "cdn_content_url": cdnContentUrl,
            "object_url": cdnContentUrl,
            // Port de `ActivityService.java:186-197` — voir `MediaMetaData` ci-dessus (V4-F-029).
            // `template_id` reste vide : aucun gabarit Animems n'est sélectionnable depuis ce flux
            // Galerie standard côté Android non plus (valeur réelle seulement pour un export
            // Animems, flux séparé, pas construit ici).
            "metadata": metadataJSON,
            "template_id": "",
            "consentAi": consentAi ? "1" : "0",
        ]
        if let cdnThumbnailUrl { params["cdn_thumbnail_url"] = cdnThumbnailUrl }
        if let category, !category.isEmpty { params["category"] = category }
        if let width { params["width"] = String(width) }
        if let height { params["height"] = String(height) }
        if object == "videos", let videoDurationMs { params["video_duration"] = String(videoDurationMs) }

        print("FEED PUBLISH: step=2/2 endpoint=activity/add actor=\(actorId) object=\(object)")
        let value: JSONValue
        do {
            value = try await APIClient.shared.post(params, endpoint: "activity/add")
        } catch {
            print("FEED PUBLISH: step=2/2 endpoint=activity/add transport error=\(error)")
            throw error
        }
        guard value.isBackendSuccess else {
            print("FEED PUBLISH: step=2/2 endpoint=activity/add backend error=\(value.backendErrorMessage ?? "?") raw=\(value.toDictionary() ?? [:])")
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "activity/add")
        }
        print("FEED PUBLISH: step=2/2 endpoint=activity/add SUCCESS")
    }

    /// Port de `MainFragment.OnLikeClicked`/`OnclickPrtg` — endpoint `reaction`, MÊMES paramètres
    /// envoyés dans les DEUX sens du bascule (Android ne distingue jamais "like" de "unlike", ni
    /// "share" de "unshare" au niveau réseau — le serveur bascule lui-même l'état ; l'affichage
    /// optimiste local est ce qui diffère, pas la requête). `message` retourné utilisé UNIQUEMENT
    /// par le partage, pour distinguer `SHARE`/`UNSHARE` (`infoContract.SHARE`/`UNSHARE`).
    @discardableResult
    func reaction(activityId: Int, userId: String, verb: String, object: String, status: String) async throws -> String? {
        let params: [String: String] = [
            "activityId": String(activityId), "userId": userId, "verb": verb, "object": object, "status": status,
        ]
        let value = try await APIClient.shared.post(params, endpoint: "reaction")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "reaction") }
        return value.optionalString("message")
    }

    /// Port de `notifyUser(id)` (`MainFragment.java:1193-1198` et ses équivalents
    /// `ProfileFeedFragment`/`HashtagProfile`) — `POST push {"userId": id}`, fire-and-forget, aucun
    /// callback côté Android (`data.Post(map, "push", null)`) — **ajouté le 2026-08-24
    /// (MIGRATION_PARITY_AUDIT_V4.md V4-F-030, Phase B P1)**. MÊME endpoint déjà porté séparément
    /// pour le Wallet (`WalletRepository.notifyTransferReceived`, nom Android identique
    /// `notifyUser` mais méthode PRIVÉE distincte côté Android — pas de code partagé à réutiliser).
    func notifyPostAuthor(userId: String) async throws {
        _ = try await APIClient.shared.post(["userId": userId], endpoint: "push")
    }

    /// Port de `ActivityAdapter.deleteMyPost` — `POST deleteactivity {id, actor}`, réservé aux
    /// publications propres (garde faite côté appelant, `FeedViewModel.deleteOwnPost`).
    func deleteActivity(id: Int, actorId: String) async throws {
        let value = try await APIClient.shared.post(["id": String(id), "actor": actorId], endpoint: "deleteactivity")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "deleteactivity") }
    }

    /// Port de `Report.report()` — endpoint `report`. `target_id`/`report_type` VIDES par défaut
    /// depuis la GRILLE (Feed) : `MainFragment.OnclickMoreExpand` (`report_content`) ne les
    /// renseigne PAS dans l'intent lancé vers `Report.java` (seuls `userId`/`username`/`nikname` le
    /// sont) — reproduit fidèlement pour ce contexte précis.
    ///
    /// **Corrigé (V5-F-007, 2026-08-24)** — ajout de `targetId`/`reportType`, remplis par
    /// `FeedDetailPagerView` (plein écran, tous contextes confondus : Home/Profile/Hashtag/
    /// Search/Notifications). Vérifié : `FeedFragment.java:1351-1359` (plein écran Home) remplit
    /// `target_id`/`report_type="content"` EN PLUS de userId/username/nikname pour un
    /// signalement de contenu — comportement DISTINCT de la grille (`MainFragment`), confirmé par
    /// `ProfileFeedFragment.java`/`HashtagProfile.java` (mêmes 2 champs remplis pour LEUR propre
    /// plein écran). `Report.java:70-71,149-150` lit ces extras et les envoie tels quels dans le
    /// `map` POST — aucune valeur par défaut ni transformation.
    func reportUser(userId: String, username: String, message: String, targetId: String = "", reportType: String = "") async throws {
        let params: [String: String] = ["userId": userId, "username": username, "message": message, "target_id": targetId, "report_type": reportType]
        let value = try await APIClient.shared.post(params, endpoint: "report")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "report") }
    }
}
