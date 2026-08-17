import Foundation
import Alamofire

/// Réplique fidèlement le comportement réseau de `Http/TransportData.java` + `Http/MySingleton.java`.
///
/// Contraintes non négociables (voir TIINVER_IOS_PORT_ANALYSIS.md §6.3) — NE PAS "améliorer" :
///  - `Authorization`: apiKey brut, SANS préfixe "Bearer".
///  - `Content-Type: application/json; charset=utf-8`, `Accept: application/json` fixes.
///  - Pas de redirection HTTP suivie automatiquement
///    (MySingleton.OkHttpStack: `followRedirects(false)` + `setInstanceFollowRedirects(false)`).
///  - Timeout 20s, aucun retry automatique — les deux files Volley (normale et "NoRetries")
///    utilisent en réalité la même politique `DefaultRetryPolicy(20_000, 0, 1f)`, donc un seul
///    comportement à reproduire pour les deux (voir MySingleton.java:70-93).
///  - Enveloppe de réponse : champ "error" en STRING ("false" = succès) OU BOOLÉEN JSON natif
///    selon l'endpoint (confirmé le 2026-08-17 sur `login` par le JSON réel du backend — voir
///    `JSONValue.errorFieldNormalized`, qui tolère les deux), "message" sur erreur (voir
///    `JSONValue.isBackendSuccess`/`backendErrorMessage`).
///
/// **Contrainte ABANDONNÉE le 2026-08-17 (preuve réelle, pas une supposition)** : "corps JSON
/// envoyé même sur GET" (JsonObjectRequest envoie toujours un corps côté Android, y compris `{}`)
/// était documentée ci-dessus comme non-négociable, mais un test Appetize réel a montré que
/// TOUTE requête GET échouait avec `AFError.urlRequestValidationFailed(.bodyDataInGETRequest)` —
/// Alamofire (depuis 5.7) rejette désormais, par validation automatique AVANT tout envoi réseau,
/// une requête GET porteuse d'un corps HTTP, même vide. Vérifié par grep sur TOUT le projet :
/// AUCUN appel `.get(...)` n'envoie jamais de `params` non-vides (chaque endpoint encode ses
/// paramètres dans le CHEMIN de l'URL) — le corps `{}` n'a donc jamais eu la moindre utilité
/// fonctionnelle, c'était une fidélité purement cosmétique qui a fini par casser LITTÉRALEMENT
/// CHAQUE écran de lecture de l'app (Home/Feed, Profile, Créateurs, Notifications, Recherche,
/// Wallet, commentaires...). Les requêtes GET n'envoient plus de corps du tout.
final class APIClient {
    static let shared = APIClient()

    private let session: Session

    private init() {
        let redirectHandler = Redirector(behavior: .doNotFollow)
        let configuration = URLSessionConfiguration.af.default
        configuration.timeoutIntervalForRequest = 20
        session = Session(configuration: configuration, redirectHandler: redirectHandler)
    }

    private func headers() -> HTTPHeaders {
        var headers: HTTPHeaders = [
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json"
        ]
        if let apiKey = UserSession.shared.apiKey {
            headers.add(name: "Authorization", value: apiKey)
        }
        return headers
    }

    // MARK: - REST principal (infoContract.SERVER — ex TransportData.get/Post/volleyPut/volleyDelete)

    /// Équivalent de `TransportData.get(endpoint, callback)` — GET sans paramètres (corps `{}`).
    func get(_ endpoint: String) async throws -> JSONValue {
        try await request(baseURL: APIEnvironment.restBaseURL, endpoint: endpoint, method: .get, params: [:])
    }

    /// Équivalent de `TransportData.volleyGet(params, endpoint, metodo, callback)` /
    /// `getDataFromServer(params, endpoint, callBack)` — GET avec paramètres envoyés en corps JSON.
    func get(_ params: [String: String], endpoint: String) async throws -> JSONValue {
        try await request(baseURL: APIEnvironment.restBaseURL, endpoint: endpoint, method: .get, params: params)
    }

    /// Équivalent de `TransportData.Post(params, endpoint, callBack)`.
    func post(_ params: [String: String], endpoint: String) async throws -> JSONValue {
        try await request(baseURL: APIEnvironment.restBaseURL, endpoint: endpoint, method: .post, params: params)
    }

    /// Équivalent de `TransportData.volleyPut(...)`.
    func put(_ params: [String: String], endpoint: String) async throws -> JSONValue {
        try await request(baseURL: APIEnvironment.restBaseURL, endpoint: endpoint, method: .put, params: params)
    }

    /// Équivalent de `TransportData.volleyDelete(params, view, metodo)`.
    /// Note : l'en-tête "Accept" est omis à l'identique côté Android pour cette seule méthode
    /// (TransportData.java:1090, commenté) — reproduit ici (voir headersForDelete()).
    func delete(_ params: [String: String], endpoint: String) async throws -> JSONValue {
        try await request(baseURL: APIEnvironment.restBaseURL, endpoint: endpoint, method: .delete, params: params, headersOverride: headersForDelete())
    }

    /// Sans `Content-Type` explicite : Alamofire calcule le `multipart/form-data; boundary=...`
    /// exact lui-même pour `upload(multipartFormData:)` — un `Content-Type` JSON fixe ici (comme
    /// `headers()`) casserait le parsing du corps côté serveur.
    private func multipartHeaders() -> HTTPHeaders {
        var headers: HTTPHeaders = ["Accept": "application/json"]
        if let apiKey = UserSession.shared.apiKey {
            headers.add(name: "Authorization", value: apiKey)
        }
        return headers
    }

    private func headersForDelete() -> HTTPHeaders {
        var headers: HTTPHeaders = ["Content-Type": "application/json; charset=utf-8"]
        if let apiKey = UserSession.shared.apiKey {
            headers.add(name: "Authorization", value: apiKey)
        }
        return headers
    }

    /// Équivalent multipart de `HttpFileUploader`/`CertificationRepository.requestOK` — POST direct
    /// vers le backend Tiinver (PAS BunnyCDN, voir `Chat/MediaUploadService` pour les pièces jointes
    /// chat qui suivent un protocole entièrement différent) avec des champs texte + un unique champ
    /// fichier, même convention de réponse (`error`/`message`) que le reste de l'API. Utilisé par
    /// `ProfileRepository.uploadProfilePicture` (endpoint `user`, champ `object_url`) et la
    /// soumission de certification (endpoint `certification/request`, champ `documentUrl`).
    func uploadMultipart(
        endpoint: String,
        fields: [String: String],
        fileFieldName: String,
        filename: String,
        mimeType: String,
        fileData: Data
    ) async throws -> JSONValue {
        let url = APIEnvironment.restBaseURL + endpoint
        return try await withCheckedThrowingContinuation { continuation in
            session.upload(multipartFormData: { form in
                for (key, value) in fields {
                    form.append(Data(value.utf8), withName: key)
                }
                form.append(fileData, withName: fileFieldName, fileName: filename, mimeType: mimeType)
            }, to: url, headers: multipartHeaders())
            .validate(statusCode: 200..<300)
            .responseData { response in
                switch response.result {
                case .success(let data):
                    do {
                        continuation.resume(returning: try JSONValue.parse(data))
                    } catch {
                        continuation.resume(throwing: APIError.decoding(error))
                    }
                case .failure(let error):
                    continuation.resume(throwing: APIError.transport(error))
                }
            }
        }
    }

    // MARK: - VPS (infoContract.VPS_SERVER — ex TransportData.postToVPS, file "NoRetries")

    func postToVPS(_ params: [String: String], endpoint: String) async throws -> JSONValue {
        try await request(baseURL: APIEnvironment.vpsBaseURL, endpoint: endpoint, method: .post, params: params)
    }

    // MARK: - Authentification (ex Authentification/AutentificationWenack.java)

    /// En-têtes du flux login/register/forgotpassword : ni "Accept" ni "Authorization"
    /// (AutentificationWenack.java:215-221 — "Accept" explicitement commenté dans le source,
    /// et pas d'apiKey à transmettre puisque la session n'est pas encore établie à ce stade).
    private func authHeaders() -> HTTPHeaders {
        ["Content-Type": "application/json; charset=utf-8"]
    }

    /// Équivalent de `AutentificationWenack.volleyPost(url, params, method)`.
    func postAuth(_ params: [String: String], endpoint: String) async throws -> JSONValue {
        try await request(baseURL: APIEnvironment.restBaseURL, endpoint: endpoint, method: .post, params: params, headersOverride: authHeaders())
    }

    // MARK: - Coeur

    private func request(
        baseURL: String,
        endpoint: String,
        method: HTTPMethod,
        params: [String: String],
        headersOverride: HTTPHeaders? = nil
    ) async throws -> JSONValue {
        let url = baseURL + endpoint
        // CAUSE RACINE RÉELLE, CONFIRMÉE le 2026-08-17 par l'erreur Alamofire remontée par un test
        // Appetize réel (`AFError.urlRequestValidationFailed(.bodyDataInGETRequest)`) — voir le
        // commentaire de tête de ce fichier. `URLEncoding.default` avec `params` vide (TOUJOURS le
        // cas pour un GET dans ce projet, vérifié) produit une requête SANS corps, la seule forme
        // qu'Alamofire moderne accepte pour une méthode GET.
        let encoding: ParameterEncoding = method == .get ? URLEncoding.default : JSONEncoding.default
        return try await withCheckedThrowingContinuation { continuation in
            session.request(
                url,
                method: method,
                parameters: params,
                encoding: encoding,
                headers: headersOverride ?? headers()
            )
            .validate(statusCode: 200..<300)
            .responseData { response in
                switch response.result {
                case .success(let data):
                    do {
                        continuation.resume(returning: try JSONValue.parse(data))
                    } catch {
                        continuation.resume(throwing: APIError.decoding(error))
                    }
                case .failure(let error):
                    continuation.resume(throwing: APIError.transport(error))
                }
            }
        }
    }
}
