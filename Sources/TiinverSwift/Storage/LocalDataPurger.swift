import Foundation

/// Port de `transportDataBackground.deleteaccount()` (`transportDataBackground.java:147-181`) —
/// Android route à la fois `"logout"` ET `"deleteaccount"` vers CETTE MÊME méthode (`switch` sur
/// l'action, deux `case` identiques, vérifié en lisant le fichier en entier lors de l'audit
/// Auth/session du 2026-08-16), qui purge SharedPreferences, `AccountManager`, ET toutes les tables
/// `ContentResolver` locales (suggestions, images, notifications, commentaires, FCM, likes,
/// messages, utilisateurs, roster) — même une simple déconnexion efface tout le cache local
/// Android.
///
/// **Lacune trouvée par cet audit** : `UserSession.clear()` (côté iOS) ne purgeait QUE les
/// identifiants de session (apiKey/myId/profile/username/...), jamais les caches Core Data
/// (Chat/Roster/Notifications) — sur un appareil partagé, les messages/roster/notifications d'un
/// utilisateur précédent restaient visibles après déconnexion OU suppression de compte. Fermé ici :
/// mêmes 4 caches sensibles qu'Android (activités/fil, roster, messages, notifications) purgés au
/// même moment que `UserSession.clear()`, appelé par les DEUX flux (`SettingSubViews.logout`/
/// `deleteAccount`), fidèle à la convergence Android sur une seule méthode partagée.
///
/// **Corrigé (2026-08-28, V7-F-023)** — le paragraphe précédent affirmait que `AiConversationRepository`/
/// `ViewEventRepository` n'avaient "aucun écran consommateur à ce jour, donc nécessairement vides en
/// pratique" : devenu FAUX entre-temps (dérive de documentation, jamais réévaluée après coup).
/// `AIChatView` est un écran réel, atteignable depuis `RosterListView`, qui écrit réellement des
/// conversations (TTL 3 jours côté client) ; `ViewEventRepository` a été câblé à un vrai flux
/// réseau lors de la session V6-F-019. Les deux sont désormais purgés ici aussi, scopés par
/// utilisateur (Android a la MÊME lacune sur son équivalent `AppDatabase`/`ai_conversations`/
/// `ViewEvent` — ceci va donc au-delà de la stricte parité, dans le sens de l'intention affichée
/// par l'utilisateur au moment de se déconnecter/supprimer son compte).
///
/// **Toujours non purgé, délibérément** : le cache HTTP/fichiers (`cacheDir`) — Android le vide
/// aussi, mais rien dans ce répertoire côté iOS ne contient de données utilisateur PERSISTANTES au
/// sens de cet audit (fichiers audio de modèles de mouvement communautaires re-téléchargeables,
/// images temporaires déjà gérées par leurs propres flux).
enum LocalDataPurger {
    static func purgeAll() async {
        // Lu AVANT toute purge — les deux appelants (`SettingSubViews.logout()`/`deleteAccount()`)
        // appellent `UserSession.shared.clear()` seulement APRÈS `purgeAll()`, mais la valeur est
        // capturée explicitement ici plutôt que supposée encore valide au milieu des purges async.
        let myId = UserSession.shared.myId
        async let activities: Void = purgeActivities()
        async let roster: Void = purgeRoster()
        async let messages: Void = purgeMessages()
        async let notifications: Void = purgeNotifications()
        async let aiConversations: Void = purgeAiConversations(userId: myId)
        async let viewEvents: Void = purgeViewEvents(userId: myId)
        _ = await (activities, roster, messages, notifications, aiConversations, viewEvents)
    }

    private static func purgeActivities() async {
        try? await FeedRepository().purgeCache()
    }

    private static func purgeRoster() async {
        try? await RosterRepository().delete(predicate: nil)
    }

    private static func purgeMessages() async {
        try? await MessageRepository().purgeAll()
    }

    private static func purgeNotifications() async {
        try? await NotiRepository().deleteAll()
    }

    private static func purgeAiConversations(userId: String?) async {
        guard let userId, let id = Int64(userId) else { return }
        try? await AiConversationRepository().clearConversation(userId: id)
    }

    private static func purgeViewEvents(userId: String?) async {
        guard let userId else { return }
        try? await ViewEventRepository().deleteAll(userId: userId)
    }
}
