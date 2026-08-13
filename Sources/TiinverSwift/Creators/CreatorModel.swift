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
}
