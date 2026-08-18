import Foundation

/// Port des appels réseau de `ai/TiinverGeminiAIChat.java` (823 lignes, lu en entier, 2026-08-18,
/// P2) — assistant conversationnel IA (texte + génération d'image), intégralement proxifié par le
/// backend Tiinver (`ai/chat`/`ai/image/generate`) : AUCUNE clé API Google/Gemini côté client,
/// vérifié en cherchant `generativelanguage`/`GEMINI`/`gemini-` dans tout le fichier (0 résultat) —
/// contrairement à `ai/TiinverAIChat.java` (fichier VOISIN, PAS celui-ci, jamais référencé comme
/// point d'entrée réel, `OPENAI_API_KEY` en dur) qui, lui, appelle OpenAI directement — ce fichier
/// n'est PAS celui exercé (aucun appelant trouvé pour `TiinverAIChat.class`, seulement pour
/// `TiinverGeminiAIChat.class` depuis `Roster.java`/`MonetizationActivity.java`/`MainFragment.java`).
@MainActor
final class AIChatRepository {
    static let shared = AIChatRepository()
    private init() {}

    /// Port de `callTextApi` — `POST ai/chat {message}`. `action == 0` (succès) porte
    /// `{reply, used, remaining, limit}` ; l'échec porte `{quota: Bool, message}` (jamais
    /// `error`/`isBackendSuccess`, convention DIFFÉRENTE des autres endpoints Tiinver — ce fichier
    /// distingue succès/échec via `action` de son propre `Callback`, pas via le champ `error`
    /// standard, reproduit fidèlement plutôt qu'uniformisé).
    func sendMessage(_ text: String) async throws -> AIChatReply {
        let value = try await APIClient.shared.post(["message": text], endpoint: "ai/chat")
        if let reply = value.optionalString("reply") {
            return AIChatReply(
                reply: reply,
                used: (try? value.int("used")) ?? 0,
                remaining: (try? value.int("remaining")) ?? 0,
                limit: (try? value.int("limit")) ?? 5
            )
        }
        let message = value.optionalString("message") ?? "Une erreur est survenue."
        if (try? value.bool("quota")) == true {
            throw AIChatError.quotaReached(message: message)
        }
        throw AIChatError.generic(message: message)
    }

    /// Port de `callImageApi` — `POST ai/image/generate {prompt, image_base64?, image_mime?}`.
    /// `IMAGE_COST = 50` pièces (vérification LOCALE rapide côté appelant avant d'appeler cette
    /// méthode, voir `AIChatViewModel.generateImage` — le serveur reste l'arbitre final, fidèle à
    /// `checkCoinsAndGenerateImage`'s commentaire "laisser le serveur décider").
    func generateImage(prompt: String, imageBase64: String?, imageMime: String?) async throws -> AIImageResult {
        var params = ["prompt": prompt]
        if let imageBase64 { params["image_base64"] = imageBase64 }
        if let imageMime { params["image_mime"] = imageMime }
        let value = try await APIClient.shared.post(params, endpoint: "ai/image/generate")
        if let b64 = value.optionalString("image_base64"), !b64.isEmpty {
            return AIImageResult(imageBase64: b64)
        }
        let message = value.optionalString("message") ?? "Une erreur est survenue."
        if (try? value.bool("insufficient")) == true {
            let balance = (try? value.string("current_balance")).flatMap(Double.init) ?? 0
            throw AIChatError.insufficientCoins(currentBalance: balance, message: message)
        }
        throw AIChatError.generic(message: message)
    }
}
