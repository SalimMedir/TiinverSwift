import Foundation

/// Port de `models/groupModel/GroupModel.java` — utilisé À LA FOIS pour lister les "contacts"
/// Tiinver (`GET connectedusers/{userId}`, PAS le carnet d'adresses du téléphone) ET pour
/// transporter un membre sélectionné vers l'écran de création de groupe (`ChooseFragment` →
/// `Group.java`, même type Java des deux côtés — voir `ConnectedUsersRepository.java`/
/// `contacts/Group.java`, lus en entier, 2026-08-15).
struct GroupMemberCandidate: Codable, Identifiable, Hashable {
    var userId: String
    var username: String?
    var firstname: String?
    var lastname: String?
    var profile: String?

    var id: String { userId }

    var displayName: String {
        let name = [firstname, lastname].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (username ?? "") : name
    }
}
