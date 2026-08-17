import Foundation
import UIKit

/// Port de `SplashActivity.java:56-65` (lien de parrainage) + `ShareActivity.java:140-334`
/// (`processUri`/`processUrl`/`getGroup`/`getUser`/`getPost`/`joinGroup`, lus en entier) — routage
/// des liens profonds entrants. Trouvé ENTIÈREMENT MANQUANT côté iOS par un audit dédié du
/// 2026-08-16 (zéro schéma déclaré, zéro `.onOpenURL`, zéro routage) — voir `project.yml` pour la
/// déclaration des schémas `myapp`/`tiinver` et sa justification (pas de vrai Universal Link
/// `https://` possible sans AASA hébergé côté serveur, hors du contrôle de ce dépôt).
@MainActor
enum DeepLinkRouter {
    /// Port de `processUri` (dispatch schéma) — `myapp://parrainage?code=...` (parrainage, EXACT
    /// même schéma qu'Android) et `tiinver://{path}` (repli propre à ce portage pour les chemins
    /// `https://tiinver.com/...`, voir `project.yml`).
    static func handle(_ url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return }
        switch scheme {
        case "myapp":
            handleReferral(url)
        case "tiinver", "https", "http":
            Task { await handleContentLink(url) }
        default:
            break
        }
    }

    /// Port de `SplashActivity.java:56-65` — `myapp://parrainage?code=XXX` stocke le code dans
    /// `REFERRED_BY` (`UserDefaults`, MÊME CLÉ que celle déjà lue par `RegisterView.swift`/
    /// `SignUpWithGoogleView.swift` — ces deux écrans portaient déjà le côté LECTURE du parrainage,
    /// jamais le côté ÉCRITURE avant ce tour, trouvé en cherchant les usages existants de
    /// `"REFERRED_BY"` avant d'écrire quoi que ce soit ici).
    private static func handleReferral(_ url: URL) {
        guard url.host?.lowercased() == "parrainage",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else { return }
        UserDefaults.standard.set(code, forKey: "REFERRED_BY")
    }

    /// Port de `ShareActivity.processUrl` — `path.split("/")`, `s[1]` = le premier segment
    /// (`user`/`post`/`group`/`myaccount`/`animemes`/`update`/`offer`), `s[2]` = l'identifiant.
    private static func handleContentLink(_ url: URL) async {
        var segments = url.pathComponents.filter { $0 != "/" }
        // Pour `https://tiinver.com/user/johndoe`, "tiinver.com" est le HOST et "user"/"johndoe"
        // sont bien dans `pathComponents`. Pour le schéma propre `tiinver://user/johndoe`, en
        // revanche, "user" atterrit dans `url.host` (`scheme://host/path`), PAS dans
        // `pathComponents` — réinjecté explicitement ici pour que les deux transports produisent
        // la même liste de segments logiques, fidèle à `path.split("/")` côté Android.
        if url.scheme?.lowercased() == "tiinver", let host = url.host, !host.isEmpty {
            segments.insert(host, at: 0)
        }
        guard let first = segments.first else { return }

        switch first {
        case "user":
            guard segments.count > 1 else { return }
            await routeToUser(username: segments[1])
        case "post":
            guard segments.count > 1 else { return }
            await routeToPost(token: segments[1])
        case "group":
            guard segments.count > 1 else { return }
            await routeToGroup(token: segments[1])
        case "myaccount":
            DeepLinkCenter.shared.route(.settings)
        case "animemes":
            DeepLinkCenter.shared.route(.animems)
        case "update":
            // Port de `UpdateApp` (Activity dédiée) — repli simple et fidèle à l'intention du lien :
            // ouvrir la fiche App Store. Le gate de mise à jour forcée AUTOMATIQUE existe déjà
            // séparément (`RootRouterView.checkForceUpdate`, Remote Config) — ce lien n'a pas besoin
            // de le redéclencher, seulement d'amener l'utilisateur vers l'App Store.
            // **`appStoreId` PAS renseigné** — l'app n'est pas encore publiée, aucun identifiant App
            // Store réel n'existe à ce stade. À compléter avant que ce lien soit réellement utile en
            // production (actuellement un no-op silencieux, pas une URL invalide qui échouerait).
            let appStoreId: String? = nil
            if let appStoreId, let appStoreURL = URL(string: "itms-apps://itunes.apple.com/app/\(appStoreId)") {
                await UIApplication.shared.open(appStoreURL)
            }
        case "offer":
            DeepLinkCenter.shared.route(.referral)
        default:
            break
        }
    }

    /// Port de `getUser(String username)` → `connectToServeur(url,"user")` → `getUser(User)`.
    private static func routeToUser(username: String) async {
        guard let user = try? await ProfileRepository.shared.fetchUser(byUsername: username), let id = user.id else { return }
        DeepLinkCenter.shared.route(.userProfile(userId: String(id)))
    }

    /// Port de `getPost(String token)` → `connectToServeur(url,"post")` → `getActivities(activityLib)`.
    private static func routeToPost(token: String) async {
        guard let post = try? await FeedRepository().fetchPost(byToken: token) else { return }
        DeepLinkCenter.shared.route(.post(post))
    }

    /// Port de `getGroup(String token)` → `connectToServeur(url,"group")` → `joinGroup(GroupModel,…)`
    /// — construction du `RosterModel` déléguée à `GroupRepository.GroupInfo.rosterModel(myId:
    /// myUsername:)` (extraite le 2026-08-18, P1, pour être réutilisée à l'identique par la
    /// recherche de groupe, `ChatSearchView.swift` — MÊME opération qu'un lien profond de groupe :
    /// ouvrir/rejoindre un groupe connu seulement par son id/token).
    private static func routeToGroup(token: String) async {
        guard let myId = UserSession.shared.myId else { return }
        guard let info = try? await GroupRepository.shared.fetchGroup(token: token, myId: myId) else { return }
        DeepLinkCenter.shared.route(.groupChat(info.rosterModel(myId: myId, myUsername: UserSession.shared.username)))
    }
}
