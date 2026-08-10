import Foundation

/// Réplique `models/user/User.java` (519 lignes, désérialisé par Gson côté Android — champs
/// privés inclus, Gson ne respecte pas la visibilité Java). Tous les champs sont optionnels ici
/// car le backend ne renvoie jamais l'objet complet selon l'endpoint (login/register/profil
/// partiel/etc. renvoient des sous-ensembles différents de ce même modèle).
struct User: Codable, Equatable {
    var id: Int?
    var userId: Int?
    var email: String?
    var firstname: String?
    var lastname: String?
    var fullname: String?
    var nikname: String?
    var location: String?
    var school: String?
    var qualification: String?
    var birthday: String?
    var work: String?
    var apiKey: String?
    /// Champ distinct de `apiKey` côté Java (`apikey`, minuscule) — présent sur certaines réponses
    /// legacy. Conservé séparément pour fidélité, ne pas fusionner avec `apiKey`.
    var apikey: String?
    var phone: String?
    var password: String?
    var subscribe: String?
    var profile: String?
    var message: String?
    var stamp: String?
    var error: String?
    var username: String?
    var followers: String?
    var following: String?
    var emailVerified: String?
    var certified: String?
    var isCertified: Bool?
    var isFollowed: Bool?
    var etat: String?
    var warning: String?
    var gender: String?
    var coinsAmount: Double?
    var gems: Double?
    var gemsAmount: Double?
    var type: String?
    var provider: String?
    var providerId: String?
    var verificationCode: String?
    var link: String?
    var biography: String?
    var category: String?
    var referredBy: String?
    var referralCode: String?
    var userStatus: String?
    var hasProgram: Bool?
    var programs: [Program]?
    var username_blocked: String?
    var blocked_users: [BlockLib]?

    struct Program: Codable, Equatable {
        var program: String?
        var level: String?
        var status: String?
        var started_at: String?
        var ended_at: String?
    }

    /// Reproduit `User.getLastname()` : renvoie `" "` si `lastname` est nul ou littéralement `"null"`
    /// (chaîne, pas la valeur JSON null — artefact backend confirmé dans le code source Android).
    var displayLastname: String {
        guard let lastname, lastname != "null" else { return " " }
        return lastname
    }
}
