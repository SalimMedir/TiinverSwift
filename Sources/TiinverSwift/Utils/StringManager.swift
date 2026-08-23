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

    /// Port de `formatCount` (V3-F-100/101, SEARCH complémentaire) — dupliqué à l'identique dans
    /// `UniversalSearchAdapter.PostViewHolder`/`HashtagViewHolder` ET `HashtagProfile.java` côté
    /// Android, factorisé ici en un seul endroit plutôt que triplé, sans impact fonctionnel (même
    /// motif que `GoogleSignInCoordinator`, qui factorise 2 fichiers Android dupliqués).
    static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return String(count)
    }
}
