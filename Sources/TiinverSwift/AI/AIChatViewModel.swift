import UIKit

/// Port de `TiinverGeminiAIChat`'s état/logique (823 lignes) — VOIR `AIChatRepository.swift` pour
/// la trace complète des 2 endpoints. **Non porté, décision de portée documentée** : le mode
/// "supprimer l'arrière-plan" (`removeBgMode`, `RemoveBackground.removeBackgroundAdvanced`/
/// `removeBackgroundWithMLKit`, post-traitement local appliqué à l'image générée) — nécessiterait
/// un pipeline Vision/CoreML dédié équivalent, hors périmètre de cette passe ; la génération
/// d'image elle-même (le cœur de la fonctionnalité) reste pleinement fonctionnelle sans ce
/// post-traitement optionnel.
@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var inputText = ""
    @Published var selectedImage: UIImage?
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var quotaUsed = 0
    @Published var quotaLimit = 5
    @Published var quotaReached = false
    @Published var insufficientCoinsBalance: Double?

    /// Port de `IMAGE_COST = 50`.
    static let imageCost: Float = 50

    private let repository = AIChatRepository.shared
    private let conversations = AiConversationRepository()
    private var userId: Int64 { Int64(UserSession.shared.myId ?? "0") ?? 0 }

    /// Port de `onCreate`'s chargement Room + `THREE_DAYS` purge des messages expirés.
    func loadInitial() async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try? await conversations.deleteExpired(now: now)
        guard let rows = try? await conversations.conversation(userId: userId, now: now) else { return }
        messages = rows.compactMap { row -> AIChatMessage? in
            guard let role = row.role, let type = row.type, let content = row.content else { return nil }
            let kind: AIChatMessage.Kind = type == "image"
                ? .image(URL(fileURLWithPath: content)) : .text(content)
            return AIChatMessage(role: role == "user" ? .user : .assistant, kind: kind, stamp: row.stamp)
        }
    }

    /// Port de `callTextApi`/`sendButton` click — envoie le texte, persiste les deux côtés
    /// (utilisateur ET réponse) comme `saveToDb` le fait après chaque tour.
    func sendText() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        errorMessage = nil
        let stamp = Int64(Date().timeIntervalSince1970 * 1000)
        messages.append(AIChatMessage(role: .user, kind: .text(text), stamp: stamp))
        try? await conversations.insert(userId: userId, role: "user", type: "text", content: text, stamp: stamp, expiresAt: stamp + Self.threeDaysMs)

        isSending = true
        var pending = AIChatMessage(role: .assistant, kind: .text(""), stamp: stamp, isPending: true)
        messages.append(pending)
        defer { isSending = false }

        do {
            let reply = try await repository.sendMessage(text)
            quotaUsed = reply.used
            quotaLimit = reply.limit
            if reply.remaining <= 0 { quotaReached = true }
            messages.removeAll { $0.id == pending.id }
            let replyStamp = Int64(Date().timeIntervalSince1970 * 1000)
            messages.append(AIChatMessage(role: .assistant, kind: .text(reply.reply), stamp: replyStamp))
            try? await conversations.insert(userId: userId, role: "assistant", type: "text", content: reply.reply, stamp: replyStamp, expiresAt: replyStamp + Self.threeDaysMs)
        } catch AIChatError.quotaReached(let message) {
            messages.removeAll { $0.id == pending.id }
            quotaReached = true
            errorMessage = message
        } catch {
            messages.removeAll { $0.id == pending.id }
            errorMessage = "Une erreur est survenue."
        }
    }

    /// Port de `checkCoinsAndGenerateImage` — pré-vérification LOCALE (`coins < IMAGE_COST` bloque
    /// immédiatement), sinon laisse le serveur trancher (fidèle : Android n'empêche PAS l'appel si
    /// `coins == 0` faute d'avoir encore chargé le solde réel).
    func generateImage() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }
        let coins = UserSession.shared.coinsAmount
        if coins >= 0, coins < Double(Self.imageCost) {
            insufficientCoinsBalance = coins
            return
        }
        inputText = ""
        errorMessage = nil
        let image = selectedImage
        selectedImage = nil
        let stamp = Int64(Date().timeIntervalSince1970 * 1000)
        messages.append(AIChatMessage(role: .user, kind: .text(prompt), stamp: stamp))

        isSending = true
        let pending = AIChatMessage(role: .assistant, kind: .text(""), stamp: stamp, isPending: true)
        messages.append(pending)
        defer { isSending = false }

        do {
            let imageBase64 = image?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
            let result = try await repository.generateImage(prompt: prompt, imageBase64: imageBase64, imageMime: imageBase64 != nil ? "image/jpeg" : nil)
            messages.removeAll { $0.id == pending.id }
            guard let data = Data(base64Encoded: result.imageBase64), let url = Self.saveTempImage(data) else {
                errorMessage = "Une erreur est survenue."
                return
            }
            let replyStamp = Int64(Date().timeIntervalSince1970 * 1000)
            messages.append(AIChatMessage(role: .assistant, kind: .image(url), stamp: replyStamp))
            try? await conversations.insert(userId: userId, role: "assistant", type: "image", content: url.path, stamp: replyStamp, expiresAt: replyStamp + Self.threeDaysMs)
        } catch AIChatError.insufficientCoins(let balance, let message) {
            messages.removeAll { $0.id == pending.id }
            insufficientCoinsBalance = balance
            errorMessage = message
        } catch {
            messages.removeAll { $0.id == pending.id }
            errorMessage = "Une erreur est survenue."
        }
    }

    private static let threeDaysMs: Int64 = 3 * 24 * 60 * 60 * 1000

    /// Port de `saveTempImage` — sauvegarde locale de l'image générée, réutilisée pour l'affichage
    /// ET persistée dans `content` (chemin local), fidèle au schéma `AiConversationEntity`.
    private static func saveTempImage(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
