import Foundation

enum JSONError: Error, LocalizedError {
    case missingKey(String)
    case typeMismatch(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let key): return "Clé JSON manquante: \(key)"
        case .typeMismatch(let key): return "Type JSON inattendu pour: \(key)"
        }
    }
}

/// Wrapper JSON dynamique volontairement proche de `org.json.JSONObject` (Android).
///
/// Le backend Tiinver ne renvoie pas une enveloppe homogène : selon l'endpoint, le payload
/// utile est soit un champ "data" contenant une chaîne JSON ré-encodée (parsée une seconde fois
/// via Gson côté Android), soit un tableau exposé directement sous une clé nommée par endpoint
/// ("activities", "notifications", "users", "donnees", "userData"...). `TransportData.java` gère
/// ça au cas par cas plutôt qu'avec un modèle unique — reproduit ici tel quel plutôt que
/// "corrigé" en une enveloppe propre qui n'existe pas côté serveur (voir
/// TIINVER_IOS_PORT_ANALYSIS.md §6.3 : ne pas normaliser les contrats non négociables).
struct JSONValue {
    let raw: Any

    init(_ raw: Any) { self.raw = raw }

    static func parse(_ data: Data) throws -> JSONValue {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue(obj)
    }

    private var dict: [String: Any]? { raw as? [String: Any] }
    private var array: [Any]? { raw as? [Any] }

    subscript(key: String) -> JSONValue? {
        guard let value = dict?[key] else { return nil }
        return JSONValue(value)
    }

    func string(_ key: String) throws -> String {
        guard let value = dict?[key] else { throw JSONError.missingKey(key) }
        if let s = value as? String { return s }
        return "\(value)"
    }

    func optionalString(_ key: String) -> String? {
        dict?[key] as? String
    }

    func int(_ key: String) throws -> Int {
        guard let value = dict?[key] else { throw JSONError.missingKey(key) }
        if let i = value as? Int { return i }
        if let s = value as? String, let i = Int(s) { return i }
        throw JSONError.typeMismatch(key)
    }

    /// Pour les (rares) endpoints où "error" est un vrai booléen JSON plutôt que la convention
    /// chaîne ("false"/"true") documentée sur `isBackendSuccess` — ex. "notification2/{userId}"
    /// (`NotiLikecmt/NotificationRepository.java`: `object.getBoolean("error")`), à ne pas
    /// uniformiser silencieusement : chaque endpoint a sa propre convention, fidèlement reproduite.
    func bool(_ key: String) throws -> Bool {
        guard let value = dict?[key] else { throw JSONError.missingKey(key) }
        if let b = value as? Bool { return b }
        throw JSONError.typeMismatch(key)
    }

    func jsonArray(_ key: String) throws -> [JSONValue] {
        guard let value = dict?[key] as? [Any] else { throw JSONError.missingKey(key) }
        return value.map(JSONValue.init)
    }

    func toArray() -> [JSONValue]? {
        array?.map(JSONValue.init)
    }

    func toDictionary() -> [String: Any]? { dict }

    /// Ré-encode `raw` en `Data` pour le passer à `JSONDecoder` — utilisé quand un sous-arbre de
    /// la réponse (ex. l'objet "user" imbriqué, ou un élément de tableau "activities") doit être
    /// décodé en `Codable` strict plutôt que traversé dynamiquement.
    ///
    /// **Correctif** : cette propriété était déjà référencée (`meta.rawData`) dans
    /// `AuthEndpoints.decodeUser` depuis le module 1, mais n'existait pas encore ici — trouvée en
    /// tentant de réutiliser le même mécanisme pour `FeedRepository.fetchTimeline` (module 6).
    /// N'aurait pas compilé au premier build réel ; ajoutée maintenant plutôt que découverte plus
    /// tard sans contexte.
    var rawData: Data? {
        try? JSONSerialization.data(withJSONObject: raw)
    }

    /// Équivalent de `Gson.fromJson(js.getString("data"), Type[].class)` côté Android : certains
    /// endpoints encodent le payload utile comme chaîne JSON à l'intérieur du champ "data" plutôt
    /// que comme objet imbriqué. Reparse cette chaîne.
    func stringEncodedJSON(_ key: String) throws -> JSONValue {
        let s = try string(key)
        guard let data = s.data(using: .utf8) else { throw JSONError.typeMismatch(key) }
        return try JSONValue.parse(data)
    }

    /// **CAUSE RACINE RÉELLE, CONFIRMÉE le 2026-08-17 par le JSON brut réel fourni par
    /// l'utilisateur** (pas une hypothèse) : `TransportData.java`'s convention "error" = CHAÎNE
    /// ("false"/"true") documentée comme non-négociable NE TIENT PAS sur l'endpoint `login` —
    /// réponse réelle observée : `"error": false` (BOOLÉEN JSON natif). `optionalString("error")`
    /// renvoyait `nil` pour cette valeur (`dict?[key] as? String` échoue sur un `Bool`), donc
    /// `isBackendSuccess`/`AuthEndpoints.parseLoginResponse` (qui utilisait directement
    /// `json.string("error")`, `throws` sur toute valeur non-`String`... en pratique la
    /// stringification de repli de `string(_:)` produisait une valeur ne correspondant JAMAIS
    /// exactement à `"false"`) ne reconnaissait jamais un login pourtant réussi. Résultat observé :
    /// `LoginView` naviguait quand même vers Home (car le dernier repli de `parseLoginResponse`
    /// recopiait `message` — "Login Successful" — dans `etat`, que `LoginView.handle` reconnaît),
    /// MAIS avec un `User()` ENTIÈREMENT VIDE (le vrai `decodeUser(meta)` n'était jamais atteint) —
    /// explique EXACTEMENT le symptôme "connexion propre, session vide" observé depuis plusieurs
    /// tours. Tolère maintenant LES DEUX conventions plutôt que de supposer laquelle un endpoint
    /// donné utilise.
    var errorFieldNormalized: String {
        if let s = dict?["error"] as? String { return s }
        if let b = dict?["error"] as? Bool { return b ? "true" : "false" }
        return "true" // forme inattendue : ne JAMAIS supposer un succès par défaut
    }

    var isBackendSuccess: Bool {
        errorFieldNormalized == "false"
    }

    /// Présent sur la plupart des réponses d'erreur (TransportData.java: response.getString("message")).
    var backendErrorMessage: String? {
        optionalString("message")
    }
}
