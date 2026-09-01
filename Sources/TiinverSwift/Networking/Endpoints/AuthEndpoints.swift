import Foundation

/// Réplique `Authentification/AuthRepository.java` + `Authentification/AutentificationWenack.java`.
///
/// Convention backend observée sur ces endpoints (à ne pas "nettoyer" — voir
/// TIINVER_IOS_PORT_ANALYSIS.md §6.3) : le champ "error" n'est pas binaire, il prend l'une de
/// plusieurs valeurs chaîne selon l'endpoint : `"false"` (succès), `"true"` (échec fonctionnel,
/// ex. mauvais identifiants), ou un code spécifique comme `"mailExist"`. Le message utilisateur à
/// afficher est systématiquement recopié dans `User.etat`, exactement comme le fait le code
/// Android d'origine (`user.setEtat(message)`), pour rester un portage fidèle plutôt qu'une
/// réinterprétation propre du contrat.
enum AuthEndpoints {

    /// Équivalent de `AuthRepository.setLogin(user, provider)`.
    static func login(username: String, password: String, provider: String) async throws -> User {
        let params = [
            "token": "normal",
            "provider": provider,
            "username": username,
            "password": password
        ]
        let json = try await APIClient.shared.postAuth(params, endpoint: "login")
        return try parseLoginResponse(json)
    }

    /// Équivalent de `AuthRepository.setLoginWithGoogle(user, provider)` — malgré son nom, générique
    /// côté réseau (`provider` est un `String` libre, jamais contraint à `"google"` par cette
    /// fonction ; confirmé par le propriétaire du projet, 2026-09-01 : le backend accepte n'importe
    /// quelle valeur, ce champ ne sert qu'à identifier la source de connexion). Réutilisée telle
    /// quelle pour "Sign in with Apple" (`provider: "apple"`, voir
    /// `AppleSignInCoordinator.swift`/`LoginView.swift`) plutôt que dupliquée.
    static func loginWithGoogle(providerId: String, email: String, provider: String) async throws -> User {
        let params = [
            "token": "normal",
            "provider": provider,
            "providerId": providerId,
            "email": email
        ]
        let json = try await APIClient.shared.postAuth(params, endpoint: "login")
        return try parseLoginResponse(json)
    }

    /// Équivalent de `AuthRepository.setRegister(user, provider)`.
    static func register(user: User, provider: String) async throws -> User {
        var params: [String: String] = [
            "provider": provider,
            "email": user.email ?? "",
            "phone": user.phone ?? "",
            "password": user.password ?? "",
            "fullname": user.fullname ?? "",
            "username": user.username ?? ""
        ]
        params["referredBy"] = user.referredBy ?? ""
        let json = try await APIClient.shared.postAuth(params, endpoint: "register")
        return try parseRegisterResponse(json, includesUserObject: false)
    }

    /// Équivalent de `AuthRepository.setRegisterWithGoogle(user, provider)`.
    static func registerWithProvider(user: User, provider: String) async throws -> User {
        let params: [String: String] = [
            "provider": provider,
            "providerId": user.providerId ?? "",
            "email": user.email ?? "",
            "phone": user.phone ?? "",
            "fullname": user.fullname ?? "",
            "username": user.username ?? "",
            "referredBy": user.referredBy ?? ""
        ]
        let json = try await APIClient.shared.postAuth(params, endpoint: "register")
        return try parseRegisterResponse(json, includesUserObject: true)
    }

    /// Équivalent de `AuthRepository.setPasswordForgotted(user, usingEmail)`.
    static func passwordForgotten(user: User, usingEmail: Bool) async throws -> User {
        let params: [String: String] = [
            "phoneOrEmail": usingEmail ? (user.email ?? "") : (user.phone ?? ""),
            "newPassword": user.password ?? "",
            "verificationCode": user.verificationCode ?? ""
        ]
        let json = try await APIClient.shared.postAuth(params, endpoint: "forgotpassword")
        return parseForgotPasswordResponse(json)
    }

    // MARK: - Parsing des réponses (ex LoginProcess / InscriptionProcess / registerWithProvider / mdpOublierProcess)

    /// Diagnostic (2026-08-16, captures Appetize) : un test réel avec un compte EXISTANT a montré
    /// une navigation propre vers Home (donc `error=="false"` et `decodeUser` n'a PAS levé
    /// d'exception — le décodage a réussi) mais `UserSession.shared.myId` restait nil ensuite.
    /// Toutes les causes déjà explorées (race condition, échec de décodage avalé, memberwise init
    /// manquant) sont exclues par ce scénario précis : un décodage RÉUSSI peut quand même produire
    /// `user.id == nil` si la clé JSON réelle du champ id sur CET endpoint diffère de
    /// "id"/"userId" (ex. casse différente, imbrication différente) — `User.id`/`userId` sont
    /// Optional, donc l'absence de la clé ne fait PAS échouer le décodage, juste silencieusement
    /// `nil`. Capture le dictionnaire JSON brut REÇU dans ce cas précis pour trancher au prochain
    /// test réel, sans deviner davantage.
    ///
    /// **Étendu (2026-08-17)** à `parseRegisterResponse` en plus de `parseLoginResponse` — un test
    /// réel avec le nouveau bandeau permanent (`HomeShellView.userIdDebugBanner`) a confirmé
    /// `userId(objet reçu)=nil` mais SANS que ce diagnostic apparaisse dans les panneaux
    /// Feed/Profile, preuve que le test précédent est passé par l'inscription (Google OU email),
    /// PAS par le login simple — ce diagnostic n'était câblé que sur `parseLoginResponse`. Les DEUX
    /// chemins l'appellent maintenant, quel que soit celui réellement emprunté au prochain test.
    private static func captureRawUserJSONIfIdMissing(_ user: User, meta: JSONValue) {
        if user.id == nil {
            UserSession.shared.debugLastLoginRawUserJSON = "\(meta.toDictionary() ?? [:])"
        } else {
            UserSession.shared.debugLastLoginRawUserJSON = nil // décodage réussi normalement, pas de trace périmée à garder
        }
    }

    /// **CAUSE RACINE RÉELLE ET DÉFINITIVEMENT CONFIRMÉE (2026-08-17)** — voir
    /// `JSONValue.errorFieldNormalized` : la réponse RÉELLE de `login` envoie `"error": false` en
    /// BOOLÉEN JSON natif, pas la chaîne `"false"` supposée ici jusqu'à présent. L'ancien
    /// `try json.string("error")` ne matchait donc JAMAIS `"false"`, tombait dans le dernier repli
    /// (`User()` vide, `etat` recopié depuis `message`="Login Successful"), que `LoginView.handle`
    /// reconnaît quand même — d'où la navigation propre vers Home avec une session totalement
    /// vide, symptôme observé identiquement à travers de nombreux tours de diagnostic. Utilise
    /// maintenant `errorFieldNormalized`, qui tolère les deux conventions.
    private static func parseLoginResponse(_ json: JSONValue) throws -> User {
        let error = json.errorFieldNormalized
        if error == "false" {
            guard let meta = json["user"] else { throw JSONError.missingKey("user") }
            applyBlockedUsers(from: meta)
            var user = try decodeUser(meta)
            captureRawUserJSONIfIdMissing(user, meta: meta)
            user.etat = "Login Successful"
            return user
        } else if error == "true" {
            var user = User()
            user.etat = json.backendErrorMessage
            return user
        }
        var user = User()
        user.etat = json.backendErrorMessage
        return user
    }

    /// **CAUSE RACINE RÉELLE trouvée et corrigée ici (2026-08-16, captures Appetize)** : cette
    /// fonction avalait silencieusement tout échec de `decodeUser(meta)` via `try? ... ?? User()`
    /// — si le décodage du "user" imbriqué échouait (avant le correctif `LenientDecoding`, un `id`
    /// envoyé en chaîne suffisait), le code continuait comme si tout allait bien avec un `User()`
    /// VIDE (`id`/`apiKey` nil), MAIS `etat` restait renseigné avec le message de succès du
    /// backend ("User created successfully") — `SignUpWithGoogleView.handle(_:)` ne regarde QUE
    /// `user.etat`, jamais si le décodage a réellement réussi, donc il sauvegardait cette session
    /// VIDE et naviguait vers Home. Résultat observé sur Appetize : `myId=nil`/`apiKey=nil` sur
    /// TOUS les écrans authentifiés (Home/Feed/Profile/Créateurs), sans la moindre erreur visible,
    /// immédiatement après une inscription Google apparemment réussie. Propage maintenant l'échec
    /// de décodage comme une vraie erreur (`AuthViewModel.run`'s `catch` existe déjà et alimente
    /// `errorMessage` — seul le rendu de ce champ manquait côté vue, corrigé séparément dans
    /// `SignUpWithGoogleView.swift`).
    private static func parseRegisterResponse(_ json: JSONValue, includesUserObject: Bool) throws -> User {
        // 2026-08-17 : `errorFieldNormalized` (voir `parseLoginResponse`/`JSONValue.swift`) — même
        // divergence booléen/chaîne potentielle sur cet endpoint, non confirmée ici mais corrigée
        // par précaution avec la même méthode qui a résolu `login`.
        let error = json.errorFieldNormalized
        var user = User()
        // "false", "true", et "mailExist" partagent tous la même logique côté Android :
        // extraire "message" et le recopier dans etat (voir InscriptionProcess/registerWithProvider).
        if includesUserObject, error == "false", let meta = json["user"] {
            applyBlockedUsers(from: meta)
            user = try decodeUser(meta)
            captureRawUserJSONIfIdMissing(user, meta: meta)
        }
        user.etat = json.backendErrorMessage
        return user
    }

    private static func parseForgotPasswordResponse(_ json: JSONValue) -> User {
        var user = User()
        let error = json.errorFieldNormalized
        let message = json.backendErrorMessage
        // mdpOublierProcess ne traite QUE ces deux combinaisons précises — aucune autre valeur
        // de "error"/"message" ne produit de résultat côté Android (pas de branche else).
        if error == "false", message == "Password Changed" {
            user.etat = message
        } else if error == "true", message == "user not found" {
            user.etat = message
        }
        return user
    }

    private static func decodeUser(_ meta: JSONValue) throws -> User {
        guard let data = meta.rawData else { throw JSONError.typeMismatch("user") }
        return try JSONDecoder().decode(User.self, from: data)
    }

    /// Équivalent de la boucle `Settings.setBooleanPreference(context, username_blocked+BLOCKED, true)`
    /// dans LoginProcess/registerWithProvider — liste de blocage locale, clé par nom d'utilisateur.
    private static func applyBlockedUsers(from meta: JSONValue) {
        guard let blockedArray = try? meta.jsonArray("blocked_users") else { return }
        for entry in blockedArray {
            guard let username = entry.optionalString("username_blocked") else { continue }
            UserDefaults.standard.set(true, forKey: username + "_blocked")
        }
    }
}
