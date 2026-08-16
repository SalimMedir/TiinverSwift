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
/// **Non purgés, délibérément** : `AiConversationRepository`/`ViewEventRepository` — modules de
/// stockage déjà portés mais SANS aucun écran consommateur à ce jour (voir leurs propres
/// commentaires de tête de fichier), donc nécessairement vides en pratique ; et le cache HTTP/
/// fichiers (`cacheDir`) — Android le vide aussi, mais rien dans ce répertoire côté iOS ne contient
/// de données utilisateur PERSISTANTES au sens de cet audit (fichiers audio de modèles de mouvement
/// communautaires re-téléchargeables, images temporaires déjà gérées par leurs propres flux) ;
/// élargir la purge à ces deux périmètres reste possible si un besoin réel apparaît.
enum LocalDataPurger {
    static func purgeAll() async {
        async let activities: Void = purgeActivities()
        async let roster: Void = purgeRoster()
        async let messages: Void = purgeMessages()
        async let notifications: Void = purgeNotifications()
        _ = await (activities, roster, messages, notifications)
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
}
