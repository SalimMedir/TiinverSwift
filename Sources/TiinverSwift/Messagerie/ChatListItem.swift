import Foundation

/// Port du contenu de `MessageListAdapter.messages` (`LinkedList<MessageLib>`, module 11, lu en
/// entier) — côté Android, les séparateurs de date, le bandeau de description de groupe et les
/// bandeaux d'abonnement sont des `MessageLib` SYNTHÉTIQUES injectées dans la même liste que les
/// vrais messages (`object == "date"`/`"header"`/`"subscribe"`/`"renewSubscription"`), distinguées
/// à l'affichage par `getItemViewType`. Reproduit ici en `enum` Swift à cas associés plutôt qu'en
/// `MessageLib` synthétique — plus sûr (un vrai message ne peut pas être confondu avec un
/// séparateur), et évite de polluer `MessageLib` (module Realtime, Codable) avec des champs
/// UI-only comme le proposait la note de tête de ce fichier.
enum ChatListItem: Identifiable, Equatable {
    case message(MessageLib)
    /// Port de `object == "date"` (`StringUtils.getDate`, injecté par `displayMessageOnInicialPage`/
    /// `displayMoreMessageOnScroll`/`addMessage` à chaque changement de jour calendaire). `dayKey`
    /// (`"année-jourDeL'année"`) identifie le jour représenté — **amélioration documentée par
    /// rapport à l'original** : `ChatFragmentTest.removeMessageAndUpdateSeparators` retrouve le
    /// séparateur à supprimer par ÉGALITÉ DE STAMP avec le message supprimé, ce qui ne fonctionne
    /// que si le message supprimé est exactement celui qui a déclenché la création du séparateur —
    /// supprimer un AUTRE message du même jour (le dernier restant, mais pas le déclencheur) laisse
    /// le séparateur orphelin pour toujours côté Android. `dayKey` permet de retrouver le
    /// séparateur par JOUR plutôt que par message déclencheur précis, ce qui corrige ce cas sans
    /// changer le comportement observable dans le cas normal.
    case dateSeparator(id: String, dayKey: String, text: String)
    /// Port de `object == "header"` (`ChatFragmentTest.displayHeader`) — bandeau description de
    /// groupe, affiché uniquement si `RosterModel.description` est non vide.
    case groupHeader(id: String, description: String)
    /// Port de `object == "subscribe"`/`"renewSubscription"` (`displaySubscriptionInfo`/
    /// `renewSubscription`) — bandeau de paiement groupe. **Action de paiement réelle PAS portée**
    /// (dépend du module 15 Wallet/Paiements, pas encore atteint) — le bandeau s'affiche, le bouton
    /// "s'abonner" est un point d'ancrage documenté, pas une action fonctionnelle.
    case subscriptionRequired(id: String, groupName: String, price: Int)
    case subscriptionRenewal(id: String, price: Int)

    var id: String {
        switch self {
        case .message(let m): return m.messageId ?? UUID().uuidString
        case .dateSeparator(let id, _, _): return "date-\(id)"
        case .groupHeader(let id, _): return "header-\(id)"
        case .subscriptionRequired(let id, _, _): return "sub-\(id)"
        case .subscriptionRenewal(let id, _): return "renew-\(id)"
        }
    }

    /// Port de `getAdapterPosition(LinkedList<MessageLib>, String id)`/`isMessageOnView` —
    /// déduplication par `messageId` avant insertion.
    var messageId: String? {
        if case .message(let m) = self { return m.messageId }
        return nil
    }

    var stamp: String? {
        if case .message(let m) = self { return m.stamp }
        return nil
    }

    var dayKey: String? {
        if case .dateSeparator(_, let dayKey, _) = self { return dayKey }
        return nil
    }
}
