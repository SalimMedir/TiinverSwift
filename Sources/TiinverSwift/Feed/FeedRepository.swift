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
    /// **Portée de ce correctif** : `category` (best-effort, lu depuis le profil courant), `width`/
    /// `height` (dimensions réelles du média) envoyés. `metadata`/`template_id` envoyés vides,
    /// `consentAi` envoyé à `"0"` — valeurs par défaut fidèles à un post Galerie standard sans
    /// gabarit Animems ni consentement IA explicite (aucun bascule de consentement IA n'existe dans
    /// `PublishComposeView` actuellement — gap distinct, non construit ici). **NE reproduit PAS** le
    /// blocage de publication tant qu'aucune catégorie n'est définie (`CategoryActivity` n'a pas
    /// d'équivalent iOS — MIGRATION_PARITY_AUDIT_V3.md V3-F-058 PROFILE-03, écran distinct non
    /// construit dans ce lot) : si `category` est vide, la publication continue quand même côté
    /// iOS, contrairement à Android — gap documenté, pas silencieusement fermé.
    func publish(
        actorId: String, object: String, message: String, hashtags: [String], fileData: Data,
        category: String? = nil, width: Int? = nil, height: Int? = nil, videoDurationMs: Int? = nil
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

        print("FEED PUBLISH: step=1/2 uploading to BunnyCDN object=\(object) token=\(token) bytes=\(fileData.count)")
        do {
            if object == "videos" {
                let result = try await FeedMediaUploader.uploadVideo(token: token, videoData: fileData)
                cdnContentId = result.cdnContentId
                cdnContentUrl = result.cdnContentUrl
                cdnThumbnailUrl = result.cdnThumbnailUrl
            } else {
                let result = try await FeedMediaUploader.uploadPhoto(token: token, jpegData: fileData)
                cdnContentId = result.cdnContentId
                cdnContentUrl = result.cdnContentUrl
            }
        } catch {
            print("FEED PUBLISH: step=1/2 BunnyCDN upload FAILED error=\(error)")
            throw error
        }
        print("FEED PUBLISH: step=1/2 BunnyCDN upload OK cdn_content_url=\(cdnContentUrl)")

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
            // Port de `ActivityService.java:186-197` — voir le commentaire de tête pour la portée
            // exacte de ce correctif (V3-F-017).
            "metadata": "",
            "template_id": "",
            "consentAi": "0",
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

    /// Port de `ActivityAdapter.deleteMyPost` — `POST deleteactivity {id, actor}`, réservé aux
    /// publications propres (garde faite côté appelant, `FeedViewModel.deleteOwnPost`).
    func deleteActivity(id: Int, actorId: String) async throws {
        let value = try await APIClient.shared.post(["id": String(id), "actor": actorId], endpoint: "deleteactivity")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "deleteactivity") }
    }

    /// Port de `Report.report()` — endpoint `report`. `target_id`/`report_type` VIDES depuis ce
    /// point d'entrée précis (Feed) : `MainFragment.OnclickMoreExpand` (`report_content`) ne les
    /// renseigne PAS dans l'intent lancé vers `Report.java` (seuls `userId`/`username`/`nikname` le
    /// sont) — reproduit fidèlement (un signalement déclenché depuis le Feed cible l'UTILISATEUR,
    /// pas la publication précise, au niveau de CET appel réseau), pas "corrigé" en inventant un
    /// `target_id` qu'Android lui-même n'envoie pas ici.
    func reportUser(userId: String, username: String, message: String) async throws {
        let params: [String: String] = ["userId": userId, "username": username, "message": message, "target_id": "", "report_type": ""]
        let value = try await APIClient.shared.post(params, endpoint: "report")
        guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ?? "report") }
    }
}
