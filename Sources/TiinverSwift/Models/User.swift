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

    /// Initialiseur memberwise explicite (tous les champs optionnels, sans arguments requis) — un
    /// `struct` Swift perd son initialiseur memberwise AUTOMATIQUE dès qu'un initialiseur
    /// personnalisé (`init(from decoder:)` ci-dessous) est déclaré. `User()` (zéro argument) est
    /// appelé directement à plusieurs endroits du projet (`LoginView`/`RegisterView`/
    /// `SignUpWithGoogleView`/`NewPasswordView`/`AuthEndpoints`/`UserSession.cachedUser`) — sans cet
    /// initialiseur explicite, AUCUN de ces appels ne compile plus (même cause que le correctif
    /// équivalent sur `FeedActivity` — trouvée et corrigée avant tout autre travail).
    init() {}

    /// Décodage manuel : `id`/`userId` doivent tolérer une chaîne numérique en plus d'un `Int` JSON
    /// natif — MÊME cause racine que `FeedActivity` (voir `LenientDecoding.swift`), confirmée comme
    /// cause du Profile systématiquement vide (`getuserbyid` échouait à décoder `id` dès que le
    /// serveur l'envoyait en chaîne, `ProfileViewModel.loadProfile()` capturait l'exception, l'écran
    /// restait vide). `encode(to:)` reste synthétisé automatiquement (ce modèle sert aussi de corps
    /// de requête ailleurs — voir `AuthEndpoints`/`AuthSessionPersistence`, non affecté : ce sont
    /// des champs `String` construits manuellement, pas un `JSONEncoder().encode(user)`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLenientIntIfPresent(forKey: .id)
        userId = container.decodeLenientIntIfPresent(forKey: .userId)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        firstname = try container.decodeIfPresent(String.self, forKey: .firstname)
        lastname = try container.decodeIfPresent(String.self, forKey: .lastname)
        fullname = try container.decodeIfPresent(String.self, forKey: .fullname)
        nikname = try container.decodeIfPresent(String.self, forKey: .nikname)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        school = try container.decodeIfPresent(String.self, forKey: .school)
        qualification = try container.decodeIfPresent(String.self, forKey: .qualification)
        birthday = try container.decodeIfPresent(String.self, forKey: .birthday)
        work = try container.decodeIfPresent(String.self, forKey: .work)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        apikey = try container.decodeIfPresent(String.self, forKey: .apikey)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        subscribe = try container.decodeIfPresent(String.self, forKey: .subscribe)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        stamp = try container.decodeIfPresent(String.self, forKey: .stamp)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        // 2026-08-17 : `decodeLenientStringIfPresent` — le JSON RÉEL de `login` (fourni par
        // l'utilisateur) envoie ces 4 champs en NOMBRE (`"followers": 921`, `"following": 321`,
        // `"emailVerified": 1`, `"certified": 0`) alors que `User` les déclare `String?` — un
        // décodage strict aurait levé une exception ici, cassant `decodeUser(meta)` ENTIER dès que
        // le bug `errorFieldNormalized` (voir plus haut/`JSONValue.swift`) aurait été corrigé sans
        // ce correctif — cause racine confirmée par les données réelles, pas une supposition.
        followers = container.decodeLenientStringIfPresent(forKey: .followers)
        following = container.decodeLenientStringIfPresent(forKey: .following)
        emailVerified = container.decodeLenientStringIfPresent(forKey: .emailVerified)
        certified = container.decodeLenientStringIfPresent(forKey: .certified)
        isCertified = container.decodeLenientBoolIfPresent(forKey: .isCertified)
        isFollowed = container.decodeLenientBoolIfPresent(forKey: .isFollowed)
        etat = try container.decodeIfPresent(String.self, forKey: .etat)
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        coinsAmount = container.decodeLenientDoubleIfPresent(forKey: .coinsAmount)
        gems = container.decodeLenientDoubleIfPresent(forKey: .gems)
        gemsAmount = container.decodeLenientDoubleIfPresent(forKey: .gemsAmount)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
        verificationCode = try container.decodeIfPresent(String.self, forKey: .verificationCode)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        biography = try container.decodeIfPresent(String.self, forKey: .biography)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        referredBy = try container.decodeIfPresent(String.self, forKey: .referredBy)
        referralCode = try container.decodeIfPresent(String.self, forKey: .referralCode)
        userStatus = try container.decodeIfPresent(String.self, forKey: .userStatus)
        hasProgram = container.decodeLenientBoolIfPresent(forKey: .hasProgram)
        programs = try container.decodeIfPresent([Program].self, forKey: .programs)
        username_blocked = try container.decodeIfPresent(String.self, forKey: .username_blocked)
        blocked_users = try container.decodeIfPresent([BlockLib].self, forKey: .blocked_users)
    }
}
