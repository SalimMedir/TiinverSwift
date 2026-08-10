import Foundation

/// Port partiel de `Utils/StringManager.java` — seule `getUserame` est portée, seule méthode
/// utilisée jusqu'ici (module 3 : `RegisterView.swift`, `LoginView.swift`/connexion Google).
enum StringManager {
    /// Port de `StringManager.getUserame(String)` : découpe par espace, concatène les deux
    /// premiers segments sans espace s'il y en a plusieurs, sinon renvoie le premier tel quel.
    static func username(fromFullname fullname: String) -> String {
        let parts = fullname.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts[0] + parts[1]
    }
}
