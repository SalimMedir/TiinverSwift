import Foundation

/// Port de `models/template/TemplateRemoteModel.java` — métadonnées d'un modèle de mouvement
/// communautaire renvoyées par `GET templates/list/{limit}/{offset}` (voir `CommunityTemplateRepository`
/// pour le contenu binaire et sa limitation de fidélité). Décodage volontairement tolérant, fidèle
/// à `json.optString`/`optInt`/`optBoolean` côté Android (défauts identiques, y compris
/// `trackCount`→1 et les dimensions de canevas→1080×1920) — un `Codable` strict ferait échouer tout
/// l'appel sur un seul champ absent, ce qu'Android ne fait jamais pour ce modèle.
struct TemplateRemoteModel: Identifiable {
    var id: String
    var name: String
    var cdnUrl: String
    var audioCdnUrl: String?
    var audioFileName: String?
    var hasAudio: Bool
    var trackCount: Int
    var totalFrames: Int
    var canvasWidth: Int
    var canvasHeight: Int
    var createdAt: Int64
    var creatorName: String?
}

extension TemplateRemoteModel: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id = "template_id"
        case name
        case cdnUrl = "cdn_url"
        case audioCdnUrl = "audio_cdn_url"
        case audioFileName = "audio_file"
        case hasAudio = "has_audio"
        case trackCount = "track_count"
        case totalFrames = "total_frames"
        case canvasWidth = "canvas_width"
        case canvasHeight = "canvas_height"
        case createdAt = "created_at"
        case creatorName = "creator"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        cdnUrl = (try? c.decode(String.self, forKey: .cdnUrl)) ?? ""
        audioCdnUrl = (try? c.decodeIfPresent(String.self, forKey: .audioCdnUrl)) ?? nil
        audioFileName = (try? c.decodeIfPresent(String.self, forKey: .audioFileName)) ?? nil
        hasAudio = (try? c.decode(Bool.self, forKey: .hasAudio)) ?? false
        trackCount = (try? c.decode(Int.self, forKey: .trackCount)) ?? 1
        totalFrames = (try? c.decode(Int.self, forKey: .totalFrames)) ?? 0
        canvasWidth = (try? c.decode(Int.self, forKey: .canvasWidth)) ?? 1080
        canvasHeight = (try? c.decode(Int.self, forKey: .canvasHeight)) ?? 1920
        createdAt = (try? c.decode(Int64.self, forKey: .createdAt)) ?? 0
        creatorName = (try? c.decodeIfPresent(String.self, forKey: .creatorName)) ?? nil
    }
}
