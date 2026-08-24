import Foundation

/// Port de `NotiLikecmt/NotificationRepository.java` (partie "centre de notifications" — la
/// pagination générique de `retriaveData(...)`, utilisée ailleurs pour les suggestions d'amis,
/// n'est PAS un sujet "notifications push" et est laissée au module qui la consomme réellement,
/// pas encore identifié).
@MainActor
final class NotificationCenterViewModel: ObservableObject {
    @Published var notifications: [NotiEntity] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository: NotiRepository

    init(repository: NotiRepository = NotiRepository()) {
        self.repository = repository
    }

    /// Port de `NotificationRepository.fetchNotifications(userId)`.
    func fetchNotifications(userId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Convention CONFIRMÉE différente des autres endpoints : "error" est ici un booléen
            // JSON, pas la chaîne "false"/"true" habituelle — voir JSONValue.bool(_:).
            let json = try await APIClient.shared.get("notification2/\(userId)")
            guard try json.bool("error") == false else {
                errorMessage = "Erreur serveur"
                return
            }
            let array = try json.jsonArray("notifications")
            try await upsert(array)
            // **Corrigé (V4-F-072, 2026-08-24)** — port de `NotificationRepository.
            // fetchNotifications` (lignes 106-113) : Android résout `isRead` par ID EN MÉMOIRE
            // (`parseNotificationsOptimized`, une seule requête batch AVANT même l'upsert), donc
            // `triggerSystemNotifications` — bien qu'appelé après `pruneOld()` côté Android aussi —
            // ne re-requête jamais la base. `triggerSystemNotifications` ici re-requête PAR ID
            // (`repository.getById`) : appelé APRÈS `pruneOld()`, un id purgé (utilisateur avec
            // plus de 30 notifications non lues d'un coup) était silencieusement ignoré. Corrigé en
            // appelant `triggerSystemNotifications` AVANT `pruneOld()` — `upsert` ne touche jamais
            // `isRead` d'une ligne existante, donc la valeur lue reste identique à ce que
            // l'approche en mémoire d'Android calculerait, sans risque de purge entre-temps.
            await triggerSystemNotifications(for: array)
            try await repository.pruneOld()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Port de `NotificationRepository.parseNotificationsOptimized` + `NotiDao.insertAll` — le
    /// lookup O(1) de `isRead` existant de la version Java est un détail d'optimisation SQL sans
    /// équivalent nécessaire ici : `NotiRepository.insertAll` fait déjà un upsert par `id` en une
    /// seule passe Core Data, `isRead` de la ligne existante étant naturellement préservé tant
    /// qu'on ne l'écrase pas explicitement (ce que ce code se garde bien de faire, comme
    /// l'original).
    private func upsert(_ array: [JSONValue]) async throws {
        let entries: [(id: Int32, configure: (NotiEntity) -> Void)] = array.map { item in
            let id = Int32((try? item.int("id")) ?? 0)
            return (id, { row in
                row.id = id
                row.activityId = Int32((try? item.int("activity_id")) ?? 0)
                row.userId = Int32((try? item.int("userId")) ?? 0)
                row.object = item.optionalString("object") ?? ""
                row.objectUrl = item.optionalString("object_url")
                row.cdnContentId = item.optionalString("cdn_content_id")
                row.cdnThumbnailUrl = item.optionalString("cdn_thumbnail_url")
                row.cdnContentUrl = item.optionalString("cdn_content_url")
                row.verb = item.optionalString("verb") ?? ""
                row.payloadType = item.optionalString("payload_type") ?? ""
                row.commentText = item.optionalString("comment_text")
                row.firstname = item.optionalString("firstname") ?? ""
                row.lastname = item.optionalString("lastname") ?? ""
                row.profile = item.optionalString("profile")
                row.verified = Int32((try? item.int("verified")) ?? 0)
                row.type = item.optionalString("type") ?? "notification"
                row.stamp = item.optionalString("stamp") ?? ""
                row.status = Int32((try? item.int("status")) ?? 0)
                // isRead n'est PAS écrit ici : préserver l'état local existant (nouvelle ligne
                // Core Data → 0 par défaut, à l'identique du défaut `NotiEntity.isRead == 0`).
            })
        }
        try await repository.insertAll(entries)
    }

    func refresh() async {
        notifications = (try? await repository.getAll()) ?? []
        unreadCount = (try? await repository.countUnread()) ?? 0
    }

    /// Port de `NotificationRepository.triggerSystemNotifications` — notification système
    /// UNIQUEMENT pour les entrées non lues avec un `verb` renseigné, à l'identique de l'original.
    private func triggerSystemNotifications(for array: [JSONValue]) async {
        for item in array {
            guard let verb = item.optionalString("verb"), !verb.isEmpty else { continue }
            let id = Int32((try? item.int("id")) ?? 0)
            guard let row = try? await repository.getById(id), row.isRead == 0 else { continue }

            let firstname = row.firstname ?? ""
            let lastname = (row.lastname == "null" ? nil : row.lastname) ?? ""
            let nikname = "\(firstname) \(lastname)".trimmingCharacters(in: .whitespaces)

            let payload = LocalNotificationBuilder.ActivityPayload(
                title: nikname,
                verb: verb,
                object: row.object,
                payloadType: row.payloadType,
                message: row.commentText,
                myNikname: UserSession.shared.nikname
            )
            LocalNotificationBuilder.present(LocalNotificationBuilder.activityNotificationContent(payload))
        }
    }

    /// Port de `NotificationRepository.markAllRead()`.
    func markAllRead() async {
        try? await repository.markAllRead()
        await refresh()
    }

    /// Port de `NotificationRepository.deleteAll()`.
    func deleteAll() async {
        try? await repository.deleteAll()
        await refresh()
    }
}
