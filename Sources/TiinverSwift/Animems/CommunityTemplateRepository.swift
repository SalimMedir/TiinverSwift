import Foundation

/// Port de `TiinverTemplateFetcher.java`/`TiinverTemplateDownloader.java`/`TiinverTemplateRepository.java`
/// — modèles de mouvement COMMUNAUTAIRES (parcourir/télécharger/appliquer), confirmés par un audit
/// dédié (2026-08-16) comme une fonctionnalité RÉELLE et accessible depuis l'UI Android
/// (`btn_display_online_template` → `MemesFragment.showCommunityTemplates` →
/// `CommunityTemplateGalleryView.java`), contrairement à l'UPLOAD/publication communautaire
/// (`AnimemesActionSheet.java` — la ligne "Publier le modèle" du bottom sheet est ENTIÈREMENT
/// COMMENTÉE dans le source Android lui-même, zéro appelant vivant, code mort confirmé — NON porté
/// ici, voir `MIGRATION_AUDIT.md`).
///
/// **Limitation de fidélité assumée et documentée, PAS une lacune de portage** : côté Android, le
/// fichier `.tmpl` téléchargé depuis le CDN est une sérialisation Java (`Serializable`, MÊME format
/// binaire que la sauvegarde locale via `SerializableManager`). Ce format n'a AUCUN équivalent
/// portable côté Swift — ni producible ni relisible ici (`MotionTemplateManager` iOS utilise JSON
/// `Codable`, un format entièrement différent, sans rapport binaire avec le sérialiseur Java).
/// Android lui-même anticipe ce cas de figure : `TiinverTemplateDownloader.rebuildFromRemote`
/// (fichier `.tmpl` illisible/ancien format → reconstruction d'un `MotionTemplate` SANS pistes de
/// mouvement, uniquement les métadonnées). Reproduit ici SYSTÉMATIQUEMENT plutôt qu'en repli
/// occasionnel : aucun fichier `.tmpl` réel (qu'il vienne d'un ancien upload Android ou d'un futur,
/// l'upload étant lui-même du code mort côté Android) ne sera jamais un JSON Swift valide. Résultat
/// honnête : la liste/pagination/filtres/aperçu-son d'un modèle communautaire sont pleinement
/// fonctionnels, mais l'application réelle du MOUVEMENT (`matrices`) ne l'est pas tant que le
/// backend n'expose pas une représentation interopérable — exactement la même limitation
/// qu'Android rencontrerait avec un fichier `.tmpl` corrompu, gérée par le même repli.
enum CommunityTemplateRepository {
    private static let pageSize = 20

    struct FetchResult {
        var templates: [TemplateRemoteModel]
        var hasMore: Bool
    }

    /// Port de `TiinverTemplateFetcher.fetchPublicTemplates` — `GET templates/list/{limit}/{offset}`,
    /// authentifié (`Authorization: <apikey>`, géré automatiquement par `APIClient`, même convention
    /// que le reste de l'app — pas besoin de reproduire la vérification manuelle `Non authentifié`
    /// d'Android : un appel sans apiKey renverra simplement une erreur serveur, gérée par le
    /// `catch` de l'appelant comme n'importe quel autre échec réseau).
    static func fetchPublicTemplates(offset: Int) async throws -> FetchResult {
        let value = try await APIClient.shared.get("templates/list/\(pageSize)/\(offset)")
        guard let data = value["templates"]?.rawData else { return FetchResult(templates: [], hasMore: false) }
        let templates = (try? JSONDecoder().decode([TemplateRemoteModel].self, from: data)) ?? []
        return FetchResult(templates: templates, hasMore: templates.count == pageSize)
    }

    /// Port de `downloadAndPrepare` — cache local d'abord (`MotionTemplateManager.load`, même
    /// identifiant que la sauvegarde locale), sinon télécharge `remote.cdnUrl` (en-tête `Referer`
    /// identique à l'original) et tente un décodage JSON ; en cas d'échec (voir note de tête de
    /// fichier — le cas réel en pratique), reconstruit un modèle SANS pistes depuis les seules
    /// métadonnées, fidèle à `rebuildFromRemote`. Le son, quand présent, est réellement téléchargé
    /// et fonctionnel (simple fichier audio, aucun problème de sérialisation).
    static func downloadAndPrepare(_ remote: TemplateRemoteModel) async throws -> MotionTemplate {
        if let cached = MotionTemplateManager.load(id: remote.id) {
            return cached
        }

        var template = await fetchTemplateFile(remote) ?? rebuildFromRemote(remote)

        if remote.hasAudio, let audioCdnUrl = remote.audioCdnUrl {
            template.hasAudio = true
            template.audioFileName = remote.audioFileName
            if let localPath = await downloadAudio(from: audioCdnUrl, templateId: remote.id, fileName: remote.audioFileName) {
                template.audioLocalPath = localPath
            }
        }

        MotionTemplateManager.save(template)
        return template
    }

    private static func fetchTemplateFile(_ remote: TemplateRemoteModel) async -> MotionTemplate? {
        guard let url = URL(string: remote.cdnUrl) else { return nil }
        var request = URLRequest(url: url)
        request.addValue("https://tiinver.com", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(MotionTemplate.self, from: data)
    }

    /// Port de `rebuildFromRemote` — reconstruction "métadonnées seules", sans pistes de mouvement
    /// (voir note de tête de fichier).
    private static func rebuildFromRemote(_ remote: TemplateRemoteModel) -> MotionTemplate {
        MotionTemplate(
            id: remote.id, createdAt: remote.createdAt,
            canvasWidth: remote.canvasWidth, canvasHeight: remote.canvasHeight,
            hasAudio: remote.hasAudio, audioLocalPath: nil, audioFileName: remote.audioFileName,
            totalFrames: remote.totalFrames, tracks: []
        )
    }

    /// Port de `downloadAudio` — écrit dans le cache (équivalent `context.getCacheDir()` : fichier
    /// re-téléchargeable, pas une donnée à conserver indéfiniment, contrairement au `.tmpl` lui-même
    /// qui vit dans `Application Support` via `MotionTemplateManager`).
    private static func downloadAudio(from urlString: String, templateId: String, fileName: String?) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.addValue("https://tiinver.com", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }

        let name = fileName ?? "\(templateId).mp3"
        let dest = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? data.write(to: dest)
        return dest.path
    }
}
