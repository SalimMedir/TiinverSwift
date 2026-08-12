import Foundation

/// Port de `engine/model/Profile.java` (module 11/12, lu en entier) — identité minimale transmise
/// lors d'une signalisation d'appel/PBS (`lunchcall`, `CallService` extras `"user"`). Nommé
/// `ChatProfile` (pas `Profile`) pour éviter toute confusion avec un futur type "profil
/// utilisateur" du module 17 (Profil/Réglages), qui n'est PAS le même concept — celui-ci est un
/// DTO de signalisation, pas un profil complet.
struct ChatProfile: Codable, Equatable {
    var messageId: String?
    var message: String?
    var versionCode: String?
    var title: String?
    var subtitle: String?
    var object: String?
    var conversationId: String?
    var username: String?
    var userId: String?
    var nikname: String?
    var profilePicture: String?
    var to: String?
    var groupId: String?
    var groupName: String?
    var description: String?
    var token: String?
    var chatType: String?
    var groupType: String?
    var stamp: String?
    var regroupage: String?
    var receiver: String?
    var sender: String?
    var resource: String?

    enum CodingKeys: String, CodingKey {
        case messageId, message, versionCode, title, subtitle, object, conversationId
        case username, userId, nikname
        case profilePicture = "profile_picture"
        case to, groupId, groupName, description, token, chatType, groupType, stamp
        case regroupage, receiver, sender, resource
    }

    init() {}
}
