# CHAT_RUNTIME_VALIDATION — Passe de vérification statique approfondie (suivi de CHAT_AUDIT.md)

**Type de passe : VÉRIFICATION SEULE, LECTURE SEULE.** Aucun fichier Android ou iOS n'a été modifié. Ce document est un suivi de `CHAT_AUDIT.md` (racine du dépôt iOS) — il ne le remplace pas, il resserre 7 points précis avec des preuves ligne par ligne re-vérifiées contre le HEAD actuel (`git status` confirmé propre, `CHAT_AUDIT.md` lui-même non versionné/`untracked` — donc le code n'a pas bougé depuis sa rédaction : les écarts de numéros de ligne trouvés ci-dessous, quand il y en a, sont des imprécisions mineures de l'audit original, pas une dérive du code).

**Contrainte d'environnement, rappelée explicitement** : aucun appareil, simulateur ou instance d'app en cours d'exécution n'est disponible ici. Tout ce qui suit est une analyse **statique** du code source. Là où seul un test avec deux comptes réels échangeant des messages Socket.IO permettrait de trancher, ce document l'indique explicitement par **NON DÉTERMINÉ — validation runtime nécessaire**, avec la procédure exacte qu'un humain devrait suivre.

---

## Statuts (résumé exécutif)

| # | Point | Statut |
|---|---|---|
| 1 | conversationId | **confirmé** |
| 2 | socket connection (établissement + trace réception) | **confirmé** (au niveau code ; pas runtime) |
| 3 | socket authentication (handshake) | **NON DÉTERMINÉ** — le code source lui-même admet ne jamais avoir été validé contre un serveur réel |
| 4 | message receive realtime | **confirmé** que le code existe et est câblé de bout en bout pour un chat ouvert ; **NON DÉTERMINÉ** que cela fonctionne réellement en conditions réseau réelles (dépend du point 3) |
| 5 | ChatView update | **confirmé** |
| 6 | RosterList realtime update | **non confirmé** (= confirmé ABSENT — aucune mise à jour temps réel des lignes du roster) |
| 7 | FCM fallback | **non confirmé côté iOS** (absent) ; **confirmé nécessaire, pas un nice-to-have**, d'après l'architecture Android elle-même |
| 8 | nickname | **déterminé** — mécanisme de code correct de bout en bout, aucun bug trouvé ; la valeur vide observée est une question de données backend, pas de code |
| 9 | object types | voir matrice complète §6 — mixte : OK pour text/photo/video/audio/graphic, PARTIAL pour gift, FAIL pour sticker/gif (envoi) et doc (envoi+réception) ; location non applicable (absent des deux plateformes) |
| 10 | quote/reply | **résultat révisé** : mécanisme central confirmé symétrique, MAIS 2 vrais écarts trouvés que l'audit original n'avait pas signalés (`giftId` jamais sérialisé sur AUCUN paquet, `quoteDuration` jamais affiché à la réception) — le verdict "aucun bug" de l'audit original ne tient pas entièrement |

---

## 1. conversationId — **confirmé**

**Symbole exact vérifié** : `Sources/TiinverSwift/Models/ConversationIdGenerator.swift`
```swift
// lignes 8-17
enum ConversationIdGenerator {
    private static let separator = "_"
    static func conversationId(currentUser: String, remoteUser: String) -> String {
        [currentUser, remoteUser].sorted().joined(separator: separator)
    }
    static func groupConversationId(currentUser: String, remoteUser: String, type: String = "chatgroup") -> String {
        [currentUser, remoteUser, type].sorted().joined(separator: separator)
    }
}
```
Ce générateur existe et fonctionne correctement — confirmé aussi appelé ailleurs dans le code, ex. `GroupDetailView.swift:479` (`systemMessage.conversationId = ConversationIdGenerator.groupConversationId(...)`, pour les messages système de groupe).

**Les 4 points d'entrée re-vérifiés — aucun n'appelle `ConversationIdGenerator`, ni n'assigne `conversationId` de quelque façon que ce soit :**

1. `Sources/TiinverSwift/Messagerie/NewMessageView.swift:29-48` — `private var rosterTarget: RosterModel?`. Construit `target` avec `type/nikname/username/to/from/userId/sender/receiver/title/subTitle/profile/currentUsername/currentUserId/currentNikname` (17 assignations, lignes 32-46) — **aucune n'est `conversationId`**. Grep direct : zéro occurrence de `conversationId` dans tout le fichier.
2. `Sources/TiinverSwift/Profile/ProfileView.swift:319-334` — `private var messageTarget: RosterModel?`. Même motif, 10 champs assignés (lignes 322-332), **aucun `conversationId`**. Le commentaire de tête (lignes 315-318) énumère explicitement les champs reproduits et `conversationId` n'y figure pas. Zéro occurrence dans tout le fichier.
3. `Sources/TiinverSwift/Messagerie/ContactPickerView.swift:129-143` — `private func rosterModel(for candidate: GroupMemberCandidate) -> RosterModel`. Même motif, 10 champs assignés (lignes 131-141), **aucun `conversationId`**. Zéro occurrence dans tout le fichier.
4. `Sources/TiinverSwift/Messagerie/GroupDetailView.swift:370-385` — `private func chatTarget(for member: GroupMember) -> RosterModel?`. Construit un `RosterModel` de type `chat` (pas `group`) pour démarrer une conversation 1:1 avec un membre du groupe, 10 champs assignés (lignes 373-383), **aucun `conversationId`** — et, fait notable non signalé par l'audit original, ni `sender` ni `receiver` non plus (seul `userId` est renseigné). C'est la seule occurrence de `conversationId` dans tout le fichier (ligne 479, `chatTarget` n'est pas cette fonction — voir ci-dessus).

**`RosterModel.conversationId`** (`Sources/TiinverSwift/Models/RosterModel.swift:12`) : `var conversationId: String?` — optionnel, donc `RosterModel()` (appelé sans argument dans les 4 sites ci-dessus) le laisse `nil` par défaut.

**Effet de cascade — `RosterRepository.updateRoster` re-vérifié contre le HEAD actuel (numéros de ligne exacts, légèrement différents de l'audit original qui citait "79-80")** :
```swift
// Sources/TiinverSwift/Storage/RosterRepository.swift
79  func updateRoster(message: MessageLib, isFromServer: Bool) async throws {
80      guard let conversationId = message.conversationId else { return }
```
Confirmé exact : la fonction est bien `updateRoster(message:isFromServer:)`, la garde est bien à la ligne 80, elle sort immédiatement (sans créer ni mettre à jour de ligne `wk_roster`/`RosterEntity`) si `conversationId` est `nil`. Cette méthode est appelée par le chemin d'écho optimiste de tout message sortant.

**Le correctif proposé par l'audit original tiendrait** : appeler `ConversationIdGenerator.conversationId(currentUser:remoteUser:)` (ou `.groupConversationId` pour le cas groupe) à chacun des 4 sites, avant de renvoyer `target`, résoudrait le bug à la source — la fonction existe, est pure, ne dépend d'aucun état supplémentaire (juste `myId` et l'id du pair, tous deux déjà disponibles à ces 4 sites), et est déjà invoquée avec succès ailleurs dans le code (`GroupDetailView.swift:479`).

**Scénario vérifié** : lecture directe des 4 fichiers + du générateur + du repository, comparaison ligne à ligne. **Résultat : confirmé, bug réel, correctif proposé viable.**

---

## 2. socket connection — **confirmé** (trace de code, pas runtime)

Trace complète de la réception d'un événement `"new message"`, fichier:ligne par fichier:ligne (vérifiée contre le HEAD actuel) :

1. **Nom d'événement** — `Sources/TiinverSwift/Realtime/SocketEvent.swift:49` : `static let newMessage = "new message"` (et `:55` pour `"new message group"`).
2. **Enregistrement du listener** — `Sources/TiinverSwift/Realtime/ChatRepository.swift:98-103` (dans `registerAllListeners()`) :
   ```swift
   socket.on(SocketEvent.newMessage) { [weak self] data, _ in
       Task { @MainActor in await self?.handleNewMessage(data, isGroup: false) }
   }
   ```
   Précédé d'un `socket.off(...)` (lignes 88-89) pour éviter les doublons de handler lors d'un `attachToCurrentSocket()`/reconnect.
3. **Parsing du payload** — `handleNewMessage` (`ChatRepository.swift:312-398`), décodage élément par élément via `decodeMessages` (`:727-746`) — un seul message malformé dans le lot n'empêche pas le décodage des autres (`compactMap`), avec log explicite du nombre perdu (`:743`).
4. **Publication interne** — `chatEvents.send(.message(meta))` (`ChatRepository.swift:349` pour le privé, `:362` pour le groupe), `PassthroughSubject` Combine déclaré `:20`.
5. **Abonnement ViewModel** — `ChatViewModel.subscribeToRealtimeEvents()` (`ChatViewModel.swift:311-319`), appelé depuis `init` (`:78`).
6. **Filtrage par conversation** — `ChatViewModel.swift:321-327` :
   ```swift
   let isPrivateMatch = !target.isGroup && meta.type == ChatType.chat.wireValue && meta.from == target.to
   let isGroupMatch = target.isGroup && meta.type == ChatType.group.wireValue && meta.token == target.token
   guard isPrivateMatch || isGroupMatch else { return }
   await onIncoming(meta)
   ```
   Ce filtrage compare des usernames (`meta.from == target.to`), **indépendant du bug conversationId du §1** — donc le bug conversationId ne casse pas le routage temps réel d'un chat déjà ouvert.
7. **Mise à jour d'état** — `onIncoming` (`ChatViewModel.swift:345-364`) déduplique par `messageId` puis ajoute à `@Published private(set) var items` (`:12`).

**Configuration socket re-vérifiée** — `Sources/TiinverSwift/Networking/APIEnvironment.swift:13` : `static let socketURL = "https://api.tiinver.com:2020"` — **identique bit à bit** à `infoContract.SERVERIO_URL` côté Android. L'audit original avait marqué ce point "NON DÉTERMINÉ (valeur exacte iOS)" faute d'avoir re-vérifié la valeur ; **c'est désormais confirmé identique**, ce point est réglé.

**Scénario vérifié** : lecture complète de la chaîne d'appel de bout en bout, du nom d'événement à la mutation d'état observable par SwiftUI. **Résultat : confirmé au niveau code — l'implémentation existe, est cohérente, et le câblage est réel (pas juste des symboles inutilisés).** Reste NON DÉTERMINÉ : si le serveur envoie effectivement l'événement et si le socket est bien connecté/authentifié en pratique (voir §3).

---

## 3. socket authentication — **NON DÉTERMINÉ** (admis par le code source lui-même)

`Sources/TiinverSwift/Realtime/TiinverSocket.swift`, commentaire de tête (lignes 13-32), citation exacte de la conclusion (lignes 30-32) :

> "**Reste à vérifier sur une connexion réelle** que le serveur associe bien la session au bon utilisateur après ce changement (aucun test réel possible dans cette session, conformément à la consigne permanente de ne pas déclencher Appetize)."

Ce commentaire est **toujours présent tel quel** dans le HEAD actuel — l'audit original ne l'a pas mal cité.

**Vérification structurelle du code** (indépendante des commentaires) — `connect(apiKey:)` (`TiinverSocket.swift:82-91`) :
```swift
func connect(apiKey: String?) {
    guard let socket = ensureSocket() else { return }
    switch socket.status {
    case .connected, .connecting: return
    default:
        let payload: [String: Any]? = (apiKey?.isEmpty == false) ? ["token": apiKey!] : nil
        socket.connect(withPayload: payload, timeoutAfter: 10, withHandler: nil)
    }
}
```
Structurellement cohérent avec l'envoi du token dans le paquet CONNECT Socket.IO v4 (équivalent visé de `IO.Options.auth = {"token": apiKey}` côté Android, lu serveur comme `socket.handshake.auth.token`). Le code **a l'air correct** pour cette intention, mais **rien dans le dépôt ne le prouve contre un serveur réel** — aucun test, aucun mock, aucune trace de log de succès de handshake (voir §4 ci-dessous, absence totale de logs positifs).

Note structurelle supplémentaire : si `apiKey` est `nil`/vide, `payload` devient `nil` et le socket tente quand même `connect(withPayload: nil, ...)` — une connexion anonyme est possible par construction (cas pré-authentification).

**Scénario vérifié** : lecture complète du fichier, du commentaire de tête au corps de `connect(apiKey:)`. **Résultat : NON DÉTERMINÉ, exactement comme le code l'admet lui-même — ceci ne peut PAS être tranché statiquement.**

**Procédure de validation runtime (pour un humain avec deux comptes/appareils réels)** :
1. Se connecter sur l'app iOS avec un compte de test.
2. Sur le serveur (ou via un proxy/logging côté backend, hors périmètre de ce dépôt), vérifier que `socket.handshake.auth.token` contient bien la valeur d'`apiKey` de ce compte au moment du `CONNECT`.
3. Sans accès serveur, un test indirect côté client : envoyer un message depuis iOS et vérifier qu'un event `"on response"` arrive bien avec un `messageId` correspondant (voir §4, Scénario B) — une absence totale de réponse serveur après plusieurs tentatives serait un signal (mais pas une preuve définitive) d'échec d'authentification.

---

## 4. message receive realtime — **confirmé** que le code existe et est câblé ; **NON DÉTERMINÉ** en conditions réelles

Le code du chemin de réception (§2) est réel, complet, et câblé de bout en bout jusqu'à la mutation de l'état observable SwiftUI. Ce n'est **pas** une hypothèse "le mécanisme est absent" — un mécanisme complet existe.

**Point important découvert lors de cette passe (absent de l'audit original)** : il n'existe **aucun log positif** ("connecté", "authentifié", "message reçu avec succès") nulle part dans la chaîne de réception. Grep exhaustif de `ChatRepository.swift` : seuls des logs d'ERREUR existent :
- `ChatRepository.swift:84` — `print("❌ Erreur socket :", data.first ?? "?")`
- `ChatRepository.swift:352` — `print("❌ ChatRepository.handleNewMessage:", error)` (échec de persistance, privé)
- `ChatRepository.swift:394` — idem pour groupe
- `ChatRepository.swift:732/738` — échecs de décodage par élément
- `ChatRepository.swift:743` — uniquement si le compte décodé diffère du compte reçu (donc un lot 100% propre n'imprime **rien**)
- `onConnected()` (`ChatRepository.swift:190-200`) n'a **aucun log**, ni succès ni échec, sur la connexion elle-même.
- Aucun `emitWithAck` nulle part dans le dépôt (grep confirmé) — les envois sont "fire-and-forget", le seul accusé possible est l'event serveur asynchrone `"on response"`.

**Conséquence pratique** : un testeur humain ne peut PAS prouver "connecté + authentifié" ou "événement reçu" par la seule absence d'erreur dans la console Xcode de façon fiable — il doit observer l'UI. C'est en soi un gap d'observabilité à noter séparément (pas demandé explicitement par cette tâche mais pertinent pour la procédure runtime ci-dessous).

**Scénario vérifié** : câblage de code confirmé réel et complet. **Résultat : confirmé (le code existe et est correctement câblé) / NON DÉTERMINÉ (fonctionnement réel en conditions réseau, dépend entièrement du point §3).**

### Procédure de validation runtime — Scénario A (Android envoie, iOS a la conversation ouverte)

1. **Connexion+auth** : pas de log positif direct. Vérifier l'**absence** de `"❌ Erreur socket :"` (`ChatRepository.swift:84`) après le lancement/connexion.
2. **Événement reçu** : vérifier l'**absence** de `"CHAT SOCKET: impossible de sérialiser un message reçu"` (`:732`), `"CHAT SOCKET: échec de décodage..."` (`:738`), ou `"❌ ChatRepository.handleNewMessage:"` (`:352`/`:394`). Si l'une de ces lignes apparaît, l'événement est bien arrivé mais a échoué à se parser/persister — le texte d'erreur identifiera le champ fautif.
3. **Routage vers le `ChatView` ouvert** — aucun log, **preuve uniquement par l'UI** :
   - La nouvelle bulle apparaît dans la liste (`ChatView.swift:171`, `ForEach(viewModel.items)`) avec auto-scroll (`:187`).
   - Le son de réception joue (`ChatSoundPlayer.playReceive()`, `ChatViewModel.swift:363` — uniquement si le message ne vient pas de l'utilisateur courant).
   - Une notification locale se déclenche même conversation déjà ouverte (`ChatRepository.notifyIfNeeded`, `:422-428` — comportement intentionnel, pas un bug).
   - Si rien n'apparaît malgré l'absence d'erreur : vérifier que `meta.from`/`meta.token` reçus correspondent bien à `target.to`/`target.token` de l'écran ouvert (`ChatViewModel.swift:324-326`) — un décalage ici échoue silencieusement, sans aucun log.

### Procédure de validation runtime — Scénario B (iOS envoie, Android a la conversation ouverte)

1. Déclencher `sendText()` (`ChatViewModel.swift:395-404`) → `socket.emit(SocketEvent.newMessage, packet.packetJSON())` (`ChatRepository.swift:514`) — pas de log sur l'émission elle-même.
2. Confirmer l'émission par l'UI : la bulle apparaît immédiatement (écho optimiste local, `appendOptimistic`, `:401`) avec l'icône `checkmark` (statut 1 = envoyé, `DeliveryStatusIcon`, `ChatBubbleViews.swift:118-129`).
3. Accusé serveur (`"on response"`) : `handleResponse` (`ChatRepository.swift:445-462`) décode `{messageId, receiver, response}` et met à jour le statut. **À observer visuellement** : l'icône passe de `checkmark` → `checkmark.circle` (livré) → `checkmark.circle.fill` teinté (affiché/lu). Aucun log ici non plus.

### Procédure de validation runtime — Scénario C (iOS sur la liste des conversations, pas dans un chat)

Voir §6 ci-dessous — dissociation attendue entre le badge (live) et le contenu de la ligne (statique).

---

## 5. ChatView update — **confirmé**

Suite directe du §2/§4 : `onIncoming(_:)` (`ChatViewModel.swift:345-364`) mute `@Published private(set) var items: [ChatListItem]` (`ChatViewModel.swift:12`). `ChatView` détient le view model via `@StateObject private var viewModel: ChatViewModel` (`ChatView.swift:9`), rend `ForEach(viewModel.items)` (`ChatView.swift:171`), et déclenche l'auto-scroll via `.onChange(of: viewModel.items.last?.id)` (`ChatView.swift:187`). C'est le mécanisme d'observation standard SwiftUI (`@Published` + `ObservableObject` + `@StateObject`) — une mutation de `items` provoque nécessairement un re-render de la vue tant que celle-ci est montée à l'écran.

**Scénario vérifié** : lecture directe de la déclaration `@Published`, du point de mutation, et du point de rendu SwiftUI. **Résultat : confirmé — si l'événement arrive et passe le filtrage §2 étape 6, la mise à jour visuelle de `ChatView` est garantie par construction du binding SwiftUI**, sous réserve toujours que l'événement arrive réellement (§3/§4, NON DÉTERMINÉ en conditions réelles).

---

## 6. RosterList realtime update — **non confirmé** (= absence confirmée)

`Sources/TiinverSwift/Messagerie/RosterListView.swift` lu intégralement (306 lignes ; `RosterListView` et `RosterListViewModel` vivent dans le même fichier, pas de fichier séparé).

**Commentaire d'aveu, toujours présent aux mêmes lignes citées par l'audit original** (`RosterListView.swift:15-17`) :
> "mise à jour temps réel de la liste (présence en ligne/frappe/nouveau message reçu pendant que l'écran est ouvert — `Roster.organizeAndDisplayMessage`, **non câblé**, `refresh()` manuel via le bouton toolbar en attendant)."

**Grep exhaustif du fichier** : zéro occurrence de `chatEvents`, `ChatEvent`, `NotificationCenter`, `.sink(`, `PassthroughSubject`, `.onReceive(`. `RosterListViewModel.refresh()` (`:223-304`) ne fait qu'un fetch Core Data ponctuel (`repository.rosterAll()`), déclenché par `.task` au premier affichage (`:116`) et par deux `.onChange` liés à la fermeture de sheets (contact picker / nouveau message, `:117-124`) — **aucun de ces déclencheurs n'est piloté par le socket**. `RosterRepository.swift` confirmé également sans aucune référence à `chatEvents`/`ChatEvent`/`Combine`/`sink`/`PassthroughSubject`.

**Nuance découverte lors de cette passe, absente de l'audit original** : `Sources/TiinverSwift/Navigation/HomeShellView.swift:178-181` s'abonne bel et bien à `ChatRepository.shared.chatEvents` :
```swift
.onReceive(ChatRepository.shared.chatEvents) { event in
    guard case .message = event else { return }
    Task { await refreshChatUnreadCount() }
}
```
Mais ceci ne recalcule qu'un compteur `@State private var chatUnreadCount` au niveau de la coquille d'onglets (badge de l'onglet "Chat" + badge de l'icône app, `HomeShellView.swift:53,78,271-274,281-283`), via un nouveau fetch Core Data (`RosterRepository().query(...)`) — **entièrement déconnecté de `RosterListViewModel.rows`**. Ce compteur global peut donc s'incrémenter en temps réel pendant qu'un utilisateur observe la liste des conversations, **alors même que la ligne concrète de cette conversation (dernier message, horodatage, badge non-lu par ligne, réordonnancement) reste figée** jusqu'au prochain refresh manuel ou changement d'écran.

**Scénario vérifié** : lecture complète des deux fichiers concernés + grep exhaustif. **Résultat : non confirmé — l'absence de mise à jour temps réel du CONTENU des lignes du roster est confirmée réelle et inchangée. Seul le badge global (onglet + icône app) est temps réel ; les lignes elles-mêmes ne le sont pas.**

**Procédure de validation runtime** : avec iOS posé sur l'écran liste des conversations (pas dans un chat), faire envoyer un message par l'autre appareil. Observer : (a) le badge numérique sur l'onglet "Chat" en bas de l'écran — attendu : s'incrémente sans action utilisateur ; (b) la ligne de la conversation concernée dans la liste — attendu (d'après le code) : reste inchangée (ancien dernier message, ancien horodatage, pas de remontée en haut de liste) tant que l'utilisateur ne tire pas pour rafraîchir ou ne tape pas le bouton toolbar `arrow.clockwise` (`RosterListView.swift:82-88`). Cette dissociation badge-live/ligne-figée est la preuve la plus nette à chercher sur un appareil réel.

---

## 7. FCM fallback — **non confirmé côté iOS (absent)** ; **confirmé nécessaire**, pas un nice-to-have

### Android — lecture complète de `MyFirebaseMessagingService.onMessageReceived()` (`back_sync/MyFirebaseMessagingService.java:83-120`)

Les deux branches de distinction data/notification payload sont vides ou commentées (lignes 86-98) — Android ne rend jamais un push FCM directement. Commentaire explicite, ligne 99 : `// Ne RIEN parser ici`. Le corps utile, **inconditionnel** (hors du `if/else if` de branchement, donc déclenché par **tout** push reçu, data ou notification) :
```java
109  OneTimeWorkRequest syncWork = new OneTimeWorkRequest.Builder(TiinverSyncWorker.class)
110          .setInputData(data)
111          .setInitialDelay(2, TimeUnit.SECONDS)
112          .build();
115  WorkManager.getInstance(this).enqueueUniqueWork("FCM_SYNC_WORK", ExistingWorkPolicy.KEEP, syncWork);
```
`TiinverSyncWorker.visiteServeur()` (`service/TiinverSyncWorker.java:75-114`) appelle ensuite trois endpoints REST réels de rattrapage de contenu (pas un simple ping) :
- `GET group/message/{myId}` (`:118`)
- `GET message/{myId}` (`:144`)
- `GET messagestatus/{myUsername}` (`:170`)

**Aucun autre mécanisme de rattrapage n'existe côté Android** : `ActivityMsg.onResume()`/`onStart()` (`:140-167`) ne font rien de tel ; le seul autre chemin trouvé est `HomeActivity.onNetworkChange()` (`:482-500`), qui reconnecte le socket ET appelle `refreshSyncAdapter()` (un `ContentProvider`/`SyncAdapter` séparé), mais les listeners `connected`/`reconnected` du socket lui-même (`ChatRepository.java:858-897`) ne font que rejoindre les salons de présence — **ils ne rappellent jamais les 3 endpoints ci-dessus**.

### iOS — vérifié : aucun équivalent

`AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` (`AppDelegate.swift:114-128`) appelle uniquement `NotificationCenterViewModel().fetchNotifications(userId:)` → `GET notification2/{userId}` — l'endpoint des notifications d'**activité** (likes/commentaires/abonnements), sans rapport avec le chat. Le commentaire du fichier lui-même (lignes 105-113) documente la décision de portage : *"le reste de TiinverSyncWorker (sync des messages de chat privés/groupe, ChatRepository) ... n'est PAS porté ici."* `PushTokenRegistrar.swift` et `LocalNotificationBuilder.swift` confirmés limités à l'enregistrement de token et à la construction de contenu de notification — aucune logique de sync. Grep exhaustif du dépôt iOS : zéro occurrence de `message/{id}`, `group/message/{id}` ou `messagestatus/{username}` en `GET` nulle part.

### Verdict

L'architecture Android traite le socket reconnecté de façon symétrique à iOS (rejoindre les salons, jamais rappeler les endpoints de rattrapage) — donc ce mécanisme n'est **pas** une défense contre une instabilité du socket au premier plan. Il comble un trou structurel que **aucune plateforme ne peut éviter autrement** : app en arrière-plan ou tuée, socket fermé par l'OS, message livré serveur-side sans transport ouvert pour le porter — seul un push peut réveiller l'app, et Android traite systématiquement ce réveil comme un déclencheur de réconciliation REST, jamais comme un canal de rendu. C'est une architecture délibérée de premier ordre (confirmé par le `// Ne RIEN parser ici` et l'enqueue inconditionnel dédupliqué), pas un filet accessoire.

**Conclusion : mécaniquement nécessaire, pas un nice-to-have**, spécifiquement pour le cas app-arrière-plan/tuée — exactement le cas qu'un socket vivant ne peut structurellement pas couvrir, sur aucune des deux plateformes. Sans équivalent iOS, un message envoyé à un destinataire iOS en arrière-plan ou tué n'est récupéré que si l'utilisateur rouvre manuellement la conversation ou tire pour rafraîchir — reproduisant sur iOS exactement le mode de défaillance que l'architecture Android a été conçue pour éliminer.

---

## 8. nickname — **déterminé** (mécanisme de code correct ; cause de la valeur vide observée = donnée backend, pas un bug de code)

Trace complète de bout en bout, re-vérifiée ligne par ligne contre le HEAD actuel :

1. **Clé JSON** — `User.swift:14` : `var nikname: String?`. Pas de `CodingKeys` personnalisé déclaré nulle part dans le fichier (grep confirmé) → Swift synthétise automatiquement une clé JSON `"nikname"` correspondant exactement au nom de la propriété. `init(from:)` décode simplement : `User.swift:98` : `nikname = try container.decodeIfPresent(String.self, forKey: .nikname)` — pas de mauvais nommage, pas de mauvaise gestion d'optionnel, aucun chemin qui ne l'assigne jamais.
2. **Parsing de la réponse login/register** — `Sources/TiinverSwift/Networking/Endpoints/AuthEndpoints.swift` :
   - `parseLoginResponse` (`:119-136`) : si `error == "false"`, décode `json["user"]` via `decodeUser(meta)` (`:182-185`, `JSONDecoder().decode(User.self, from: data)` — chemin standard, aucune transformation supplémentaire sur `nikname`).
   - Ce fichier documente lui-même, en commentaire, plusieurs bugs **réels et déjà corrigés** de ce pipeline (`errorFieldNormalized` pour un champ `"error"` envoyé en booléen JSON natif au lieu de la chaîne attendue, `captureRawUserJSONIfIdMissing` pour un `id` silencieusement `nil` malgré un décodage réussi) — ce qui montre que ce chemin de code a déjà été audité en profondeur pour ce type de bug précisément, et qu'aucun défaut équivalent n'a été trouvé ou documenté concernant `nikname` spécifiquement.
   - Un décodage JSON qui échouerait sur un `nikname` de type inattendu (ex. nombre au lieu de chaîne) lèverait une `DecodingError` propagée par `throws` — cela **ne produirait pas** un nikname silencieusement vide, mais une erreur visible/propagée. Donc l'hypothèse "bug de parsing silencieux" est exclue par la structure même du code (`decodeIfPresent` ne peut retourner `nil` silencieusement que si la clé est absente ou vaut JSON `null` — pas en cas de type incompatible).
3. **Persistance session** — `Sources/TiinverSwift/Security/UserSession.swift:151-160` (`save(_ user: User)`), ligne 158 : `nikname = user.nikname` — assignation directe, sans condition, sans transformation.
4. **Propriété de cache** — `UserSession.swift:72-75` : `var nikname: String? { get { defaults.string(forKey: Keys.nikname) } set { defaults.set(newValue, forKey: Keys.nikname) } }`, clé `Keys.nikname = "nikname"` (`:20`). Lecture/écriture UserDefaults standard, aucun bug trouvé.
5. **Appel de `save()`** — confirmé câblé : `Sources/TiinverSwift/Authentication/AuthSessionPersistence.swift:20` : `UserSession.shared.save(user) // Port de SessionManager.saveUser(context, user)`.
6. **Relecture à l'envoi** — `Sources/TiinverSwift/Models/MessagePacket.swift:75` (init privé) et `:155` (init groupe) : `nikname = UserSession.shared.nikname` — lu frais à chaque construction de paquet, pas une copie figée. Sérialisé ligne 282 : `"nikname": nikname ?? ""` — **ceci explique exactement la chaîne vide observée dans le JSON capturé** (`"nikname":""`) si `UserSession.shared.nikname` est `nil` au moment de l'envoi.

**Verdict** : la chaîne complète (clé JSON → décodage → persistance → relecture → sérialisation) est correcte et sans défaut de code identifiable à aucune étape. Si le nikname apparaît vide dans un paquet envoyé, la cause la plus probable et la seule qui survive à cette relecture est que **le champ `"nikname"` était absent ou vide dans la réponse JSON réelle du endpoint login/register pour ce compte précis** (clé absente → `decodeIfPresent` retourne `nil` silencieusement, comportement JSON standard et attendu, pas un bug).

**Scénario vérifié** : lecture complète des 4 fichiers de la chaîne (User.swift, AuthEndpoints.swift, UserSession.swift, AuthSessionPersistence.swift, MessagePacket.swift). **Résultat : déterminé — aucun bug de code trouvé ; la cause de la valeur vide observée nécessite l'inspection de la réponse JSON réelle du backend pour ce compte, un point qui reste NON DÉTERMINÉ mais qui n'est plus un point ouvert côté code.**

---

## 9. Matrice des types d'objet — résultats

| Type | SEND iOS | Preuve | RECEIVE iOS | Preuve | Note Android |
|---|---|---|---|---|---|
| **text** | **OK** | `ChatView.swift:346-349,405-409` → `ChatViewModel.sendText()` `:395-404` → `buildOutgoingBase` `:545-582` → `send(mlib)` `:625-631` → `ChatRepository.sendPrivateMessage` → `socket.emit(...)` `ChatRepository.swift:514` | **OK** | `ChatBubbleViews.swift:76` `case "text","ai": TextBubbleBody` | Audit §17 : Oui/Oui, inchangé |
| **photo** | **OK** | Bouton trombone `ChatView.swift:336` → `GalleryPickerView` `:378-390` → `attachImage` `ChatViewModel.swift:484-500` → upload BunnyCDN réel (`requestUpload` `:672-715`) → `sendMedia(object:"photo",...)` | **OK** | `ChatBubbleViews.swift:78-79` `case "photo","sticker","gif": MediaImageBubbleBody` (chargement réel `CDNAsyncImage`) | Audit §17 : Oui/Oui, inchangé |
| **video** | **OK** | `attachVideo(url:)` `ChatViewModel.swift:509-525` (miniature réelle `AVAssetImageGenerator`) → `sendMedia(object:"video",...)` | **OK** | `ChatBubbleViews.swift:80` `case "video": VideoBubbleBody` | Audit §17 : Oui/Oui, inchangé |
| **audio** | **OK** | `voiceRecordGesture` `ChatView.swift:418-438` → `sendMedia(object:"audio",...)` `:434-437` (enregistreur réel `VoiceRecorder`) | **OK** | `ChatBubbleViews.swift:77` `case "audio": AudioBubbleBody` (forme d'onde aléatoire, fidèle à Android) | Audit §17 : Oui/Oui, inchangé |
| **gift** | **PARTIAL** | `sendGift(giftId:)` `ChatViewModel.swift:438-457` fonctionne réellement (vérif solde + `POST message/gift` REST) — MAIS `MessagePacket.objectFields()` n'a **aucun `case "gift"`** (repli `default:` `:301,318-320`) : `giftId` n'est **jamais** sérialisé dans le JSON socket, pour aucun type de message | **OK (vue) mais dépend du gap d'envoi** | `ChatBubbleViews.swift:81` `case "gift": GiftBubbleBody`, lit `message.giftId` `:292` — vide pour un message reçu d'un autre client iOS puisque le champ n'a jamais été émis | Audit §16/§17 : "Partiel", confirmé inchangé — même builder que `text` |
| **graphic** | **OK** | Bouton toolbar `ChatView.swift:491` → `MessageGraphicComposeView` `:114-116` → `sendGraphic(payload:)` `ChatViewModel.swift:412-418` → `objectFields() case "graphic"` `MessagePacket.swift:303-304` | **OK** | `ChatBubbleViews.swift:82` `case "graphic": GraphicPlaceholderBubbleBody` — rejeu réel `PBSCanvasEngine` `:309-319`, pas un simple placeholder statique malgré le nom | Audit §17 : Oui/Oui, inchangé |
| **sticker / gif** | **FAIL** | Bouton `face.smiling` `ChatView.swift:337` ouvre une sheet dont le corps entier est `Text("Sélecteur de GIF/stickers — à porter...")` `:366-369` — aucun appel ViewModel n'existe | **OK** | `ChatBubbleViews.swift:78-79` route vers `MediaImageBubbleBody`, un chemin réel dédié (partagé avec `photo`) | Audit §17, mêmes lignes : composition NON (placeholder), réception OK — inchangé |
| **doc** | **FAIL** | Aucun sélecteur de fichier arbitraire dans `ChatView.swift`, aucune méthode `attachDoc`/`sendDoc`. Même en théorie, `objectFields()` n'a pas de `case "doc"` → repli `default:` (`object_url` jamais envoyé) | **FAIL** | Aucun `case "doc"` dans le switch de `ChatBubbleViews.swift` (`:74-89`) → repli `default: TextBubbleBody` `:87`, affiche `message.message` (vide pour un doc, dont le contenu est dans `object_url`, jamais lu par cette vue) | **Réglé (était NON DÉTERMINÉ côté Android dans l'audit original)** : grep ciblé confirme qu'Android **possède** un vrai support doc — `UploadChatWork.java:85 case "doc":`, `UploadFileOrDataService.java:185,199`, types `MessageType.DOC1/DOC2` câblés dans `MessageListAdapter.java:1234-1237`. **Gap réel confirmé côté iOS**, pas une parité — Android envoie et affiche `doc`, iOS ne fait ni l'un ni l'autre |
| **location** | **FAIL** | Aucune UI, aucune méthode ViewModel, aucun champ modèle pour des coordonnées | **FAIL** | Aucun cas nulle part | **Réglé (était NON DÉTERMINÉ côté Android)** : grep exhaustif du package chat Android (`messagerie/`) — zéro occurrence de `"location"` comme type d'objet chat (les seules occurrences de `"location"` trouvées concernent des permissions GPS ailleurs dans l'app, sans rapport). **Ce n'est PAS une régression** — la fonctionnalité n'existe dans le protocole chat sur aucune des deux plateformes |

**Verdict §9** : la couverture iOS confirme la structure de l'audit original pour text/photo/video/audio/graphic/gift/sticker-gif. Deux points marqués "NON DÉTERMINÉ" par l'audit original sont désormais tranchés : **`doc` est un vrai gap iOS confirmé** (Android a un vrai support, iOS n'en a aucun), et **`location` n'est pas un gap** (absent des deux plateformes, comportement identique).

---

## 10. quote/reply — résultats (verdict révisé par rapport à l'audit original)

### (a) Envoi — comparaison champ par champ

Chaîne de construction re-tracée : `ChatViewModel.startQuote(for:)` (`ChatViewModel.swift:788-803`, troncature à 40 caractères pour le texte + placeholders localisés pour audio/photo/video/graphic — parité confirmée avec `ChatFragmentTest.java:1066-1087`, y compris l'absence de cas pour `gift`/`doc`/`sticker`/`location`, qui ne sont donc pas "quotables" sur aucune des deux plateformes, ce n'est pas un gap) → `buildOutgoingBase` (`:545-582`, copie `quoteTitle/quoteMessage/quoteObject/quoteDuration`, `:575-579`) → `MessagePacket` (copie aux 4 initialiseurs, `MessagePacket.swift:91-95,134,175,214`) → `quoteFields()` (`:323-325`, émet les 4 clés) fusionné uniquement `if isQuoted` (`:264-265`).

JSON reconstruit pour un message texte cité, comparé champ par champ à `getTextPrivateMessageQuotedPattern()` Android (`MessagePacket.java:461-486`) : **les 4 champs de citation et `isQuoted` (chaîne `"true"/"false"`) correspondent exactement.**

**Écart réel trouvé, non signalé par l'audit original** : Android inclut systématiquement une clé `"giftId"` (valeur ou littéral `"null"`) dans **tout** paquet, y compris un message texte cité. Vérifié : iOS **n'émet jamais cette clé, pour aucun type d'objet, y compris `text`** — `commonFields()`/`objectFields()` (`MessagePacket.swift:278-321`) ne l'incluent nulle part, alors que le champ `MessagePacket.giftId` existe bien comme propriété. Ce n'est pas limité au cas `gift` (§9) — c'est une absence de clé sur la totalité du protocole sortant iOS. Sévérité probablement faible (absence de clé plutôt que valeur `"null"`, le serveur tolère déjà des clés manquantes par ailleurs, §28 de l'audit original) mais c'est un écart de forme protocolaire réel et vérifiable.

### (b) Réception — parsing et rendu

**Parsing** : `MessageLib.init(from:)` (`MessageLib.swift:124-177`) — `isQuoted` via `decodeLenientBoolIfPresent` (`:151`, tolère `Bool` natif et chaînes `"true"/"1"/"false"/"0"`), `quoteTitle/quoteMessage/quoteObject/quoteDuration` via `decodeIfPresent(String.self,...)` (`:152-155`) — correct, aucun défaut trouvé.

**Rendu — écart réel trouvé, non signalé par l'audit original** : `QuoteBoxView` (`ChatBubbleViews.swift:146-158`) ne prend que `title`/`message` en paramètres — **`quoteDuration` n'est jamais lu ni affiché**, alors qu'il est intégralement calculé (`ChatViewModel.swift:802`), transmis (`MessagePacket.swift:95,134,175,214,324`), persisté (`MessageRepository.swift:281,460`) et décodé (`MessageLib.swift:155`) tout au long du pipeline. Grep exhaustif de la couche de rendu confirmé : aucun autre consommateur de `quoteDuration`. **Conséquence concrète** : une citation d'un message audio ou vidéo s'affiche sur iOS sans aucune indication de durée. Ceci contredit le "aucun bug" de l'audit original — c'est un défaut réel, entièrement vérifiable depuis le seul code iOS, indépendamment de ce que fait Android côté rendu (le code Android de rendu de bulle pertinent, `BubbleMessage.java`, n'a pas pu être confirmé comme étant le chemin réellement actif — le layout XML `salon_msg.xml` qu'il référence est absent du dépôt Android fourni — donc la comparaison précise avec Android sur ce point précis reste **NON DÉTERMINÉ côté Android**, mais le défaut iOS lui-même est confirmé indépendamment).

### Verdict révisé

Le mécanisme central de citation (copie dénormalisée sans référence à `messageId`, déclenchement par balayage, gating par type d'objet identique à Android, `isQuoted` en chaîne) reste confirmé fidèle et symétrique — cette partie du verdict original tient. Mais **"aucun bug trouvé" ne tient pas à cette relecture plus fine** : deux écarts réels et vérifiables ont été trouvés, absents de l'audit original :
1. `giftId` jamais sérialisé dans aucun paquet sortant (pas seulement pour `gift` — pour tous les types), MEDIUM/LOW selon tolérance backend déjà établie ailleurs.
2. `quoteDuration` calculé/transmis/persisté/décodé mais jamais affiché — un vrai défaut de rendu, silencieux, à corriger (fil `quoteDuration` jusqu'à `QuoteBoxView` et l'afficher pour les citations audio/vidéo).

---

## Note finale — les 5 constats CRITIQUES de l'audit original survivent-ils ?

- **CHAT-F-001 (conversationId vide, nouvelle conversation)** : **survit intact**, confirmé avec preuves ligne par ligne re-vérifiées (§1 ci-dessus).
- **CHAT-F-001b (roster jamais créé, effet de cascade)** : **survit intact**, la garde `RosterRepository.swift:80` est confirmée exacte.
- **CHAT-F-009a (RosterListView non temps réel)** : **survit intact**, avec une nuance nouvelle et non triviale : le badge global (onglet + icône app) EST temps réel via `HomeShellView.swift:178-181`, seul le contenu des lignes ne l'est pas — cette précision affine mais ne contredit pas le constat.
- **CHAT-F-009b (auth handshake non vérifiée runtime)** : **survit intact**, le commentaire d'aveu est toujours présent mot pour mot dans le code actuel.
- **CHAT-F-010 (absence filet FCM)** : **survit et se renforce** — cette passe apporte une preuve architecturale (pas seulement une constatation d'absence) qu'Android traite ce filet comme un mécanisme de premier ordre et non accessoire, ce qui renforce la sévérité plutôt que de la nuancer.

**Constats supplémentaires trouvés par cette passe, absents de l'audit original** : (a) `quoteDuration` jamais rendu à l'écran malgré un pipeline complet — nouveau défaut concret ; (b) `giftId` absent de la totalité du protocole sortant iOS, pas seulement des messages `gift` — élargit la portée de CHAT-F-012 ; (c) `doc` est un vrai gap confirmé (Android le supporte réellement) alors que l'audit original l'avait marqué NON DÉTERMINÉ côté Android ; (d) `location` n'est PAS un gap — absent des deux plateformes, à retirer de la liste des écarts potentiels ; (e) `GroupDetailView.chatTarget` n'assigne ni `sender` ni `receiver` en plus de `conversationId` — à vérifier séparément si cela cause un défaut additionnel lors de l'envoi du premier message à un membre de groupe.
