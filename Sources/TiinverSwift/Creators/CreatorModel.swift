import Foundation

/// Port de `models/creatorOfweek/CreatorModel.java` (35 lignes, lu en entier) — un élément du
/// classement hebdomadaire des créateurs. Noms de clés JSON = noms de champs Java LITTÉRAUX (GSON,
/// aucune annotation `@SerializedName` dans la classe source) — reproduits tels quels via
/// `CodingKeys`, pas déduits/devinés.
struct CreatorModel: Codable, Identifiable, Equatable {
    // `localId` stocké (pas recalculé à chaque accès) : un `id` recalculé via `UUID()` à chaque
    // lecture casserait l'identité SwiftUI d'une ligne de liste (`List`/`ForEach`) entre deux
    // rendus, même sans nouveau fetch — piège classique évité, pas deviné après coup.
    private let localId = UUID()
    var id: String { userId ?? localId.uuidString }

    var userId: String?
    var firstname: String?
    var profilePicture: String?
    var rankPosition: Int = 0
    var score: Double = 0
    var followers: Int = 0
    var isStar: Bool = false

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case firstname
        case profilePicture = "profile_picture"
        case rankPosition = "rank_position"
        case score
        case followers
        case isStar
    }

    /// Décodage tolérant (2026-08-16) : **`= 0`/`= false` sur ces propriétés N'EST PAS utilisé par
    /// la synthèse `Decodable` de Swift** — contrairement à l'initialiseur memberwise, le décodage
    /// JSON continue d'appeler `decode(Int.self, ...)` STRICT et lève une erreur si la clé est
    /// absente ou mal typée, la valeur par défaut ne sert JAMAIS de repli au décodage (piège Swift
    /// documenté, pas une supposition). Cette struct alimente l'écran Créateurs, qui échoue
    /// génériquement ("Impossible de charger le classement") sur le test Appetize réel — cause
    /// principale déjà attribuée à l'absence de session (voir `CLAUDE_CONTINUATION.md`), mais CE
    /// risque de décodage est réel et indépendant, donc fermé dans la même passe plutôt que laissé
    /// pour un futur incident distinct. `userId` reçoit en plus la tolérance INVERSE
    /// (`decodeLenientStringIfPresent`) : c'est un identifiant, très probablement envoyé comme
    /// NOMBRE JSON par ce même backend, pas comme chaîne.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = container.decodeLenientStringIfPresent(forKey: .userId)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        profilePicture = try container.decodeIfPresent(String.self, forKey: .profilePicture)
        rankPosition = container.decodeLenientIntIfPresent(forKey: .rankPosition) ?? 0
        score = container.decodeLenientDoubleIfPresent(forKey: .score) ?? 0
        followers = container.decodeLenientIntIfPresent(forKey: .followers) ?? 0
        isStar = container.decodeLenientBoolIfPresent(forKey: .isStar) ?? false
    }
}
