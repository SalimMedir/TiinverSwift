import SwiftUI

/// Port PARTIEL de `uploadPerfilPhoto/AddPerfilFoto.java` (1164 lignes) — remplace le placeholder
/// `sheet` "Profil" de `HomeShellView.swift`.
///
/// **Portée volontairement réduite**, comme pour `Feed/FeedView.swift` (module 6) et
/// `Notifications/NotificationsListView.swift` (module 5) : `AddPerfilFoto.java` est en réalité
/// l'écran "Profil / Réglages" complet de l'app (photo de profil, grille de publications,
/// followers/following, portefeuille, monétisation) — or "Profil / Réglages" est le MODULE 17 de
/// l'ordre de portage, pas un sujet du module 5 (UI Shell). Ce fichier fournit donc un écran de
/// profil minimal mais RÉEL (pas un simple texte "pas encore porté"), affichant les informations
/// déjà disponibles localement (`UserSession`/`AccountEntity`, modules 1-2) — la grille de
/// publications (`ProfileAdapter2`), l'upload de photo, le portefeuille (`WalletActivity`, module
/// 15), la monétisation (`MonetizationActivity`, pas lu) et l'édition (`EditProfile.java`, pas lu)
/// sont explicitement différés au module 17.
struct ProfileView: View {
    @State private var account: AccountEntity?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AsyncImage(url: (account?.profile ?? UserSession.shared.profile).flatMap(URL.init)) {
                        $0.resizable()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())

                    Text(displayName)
                        .font(.title2.bold())
                    if let username = account?.username ?? UserSession.shared.username {
                        Text("@\(username)").foregroundStyle(.secondary)
                    }
                    if let bio = account?.biography, !bio.isEmpty {
                        Text(bio).font(.footnote).multilineTextAlignment(.center)
                    }

                    // Port de `EditProfileBut`/`container_wallet`/`container_monetization` —
                    // écrans cibles pas encore lus (`EditProfile.java`, `WalletActivity.java`,
                    // `MonetizationActivity.java`), boutons désactivés plutôt qu'un lien mort.
                    HStack {
                        Button("Modifier le profil") {}.disabled(true)
                        Button("Portefeuille") {}.disabled(true) // module 15
                    }
                    .font(.footnote)

                    // Port de `follower`/`following` (compteurs) — nécessite un endpoint profil
                    // pas encore identifié/lu ; `AccountEntity` (Core Data) ne les stocke pas.
                    Text("Abonnés / Abonnements — pas encore câblés (endpoint profil non identifié)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Divider()

                    // Port de `ProfileAdapter2`/la grille de publications — différé au module 17.
                    Text("Grille de publications — différée au module 17 (Profil / Réglages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                }
                .padding()
            }
            .navigationTitle("Profil")
            .task { await loadAccount() }
        }
    }

    private var displayName: String {
        let first = account?.firstname ?? UserSession.shared.firstname ?? ""
        let last = account?.lastname ?? UserSession.shared.lastname ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? (UserSession.shared.username ?? "") : full
    }

    private func loadAccount() async {
        guard let myId = UserSession.shared.myId, let id = Int64(myId) else { return }
        let accounts = CoreDataRepository<AccountEntity>()
        account = try? await accounts.first(predicate: NSPredicate(format: "id == %lld", id))
    }
}
