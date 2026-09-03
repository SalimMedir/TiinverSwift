# CHAT_AUDIT — Audit exhaustif du système de messagerie (chat) TiinverSwift vs Android

**Type de passe : AUDIT SEUL, LECTURE SEULE.** Aucun fichier Android, backend ou iOS n'a été modifié dans le cadre de ce document. Toute correction proposée en §33 est une proposition à valider, pas un changement appliqué.

**Sources analysées :**
- Android (référence fonctionnelle, source de vérité) : `C:\Users\helen\AndroidStudioProjects\tiinver`
- iOS (portage audité) : `C:\Users\helen\iOSProjects\TiinverSwift` (worktree `agent-a3e21d22e76811f57`)

**Convention** : chaque affirmation cite `fichier:ligne`. Toute affirmation qui ne peut pas être établie à partir du seul code source est marquée **NON DÉTERMINÉ — vérification backend/runtime nécessaire**, avec la vérification concrète qui la résoudrait.

**Contexte important découvert en cours d'audit** : ce dépôt iOS a déjà traversé neuf cycles d'audit de parité internes (`MIGRATION_PARITY_AUDIT_V1.md` → `V9.md`, `MIGRATION_PARITY_PROGRESS_V1.md` → `V7.md`), avec des correctifs déjà appliqués et documentés précisément sur la couche socket/chat (ex. V3-F-016, V3-F-023, V3-F-024, V5-F-056, V5-F-070, V5-F-071, V5-F-078, V6-F-011). Le code source contient des commentaires français très détaillés citant systématiquement le fichier/ligne Android d'origine — ces commentaires ont été utilisés comme point de départ mais **toutes les conclusions ci-dessous ont été vérifiées en lisant le code réel**, pas seulement les commentaires.

---

## 1. Résumé exécutif

L'observation déclenchante (JSON iOS réel avec `conversationId` et `nikname` vides, `resource:"iOS"`, `versionCode:"1000"`, et une absence perçue de réception temps réel) a été investiguée intégralement. Verdict global :

- **`conversationId` vide** : bug réel et confirmé, **CRITIQUE**. Cause : 4 points d'entrée de nouvelle conversation ne renseignent jamais `RosterModel.conversationId` avant l'envoi, alors que l'algorithme de génération (`ConversationIdGenerator`) existe et fonctionne correctement quand il est invoqué. Effet de bord découvert en cours d'audit : la ligne roster (liste des conversations) n'est **jamais créée** pour une toute nouvelle conversation à cause de ce même vide (garde `guard let conversationId = message.conversationId else { return }`).
- **`nikname` vide** : le mécanisme de transmission est fidèle à Android (relecture depuis un cache de session au moment de l'envoi), mais la valeur en cache elle-même est vide côté iOS pour ce compte. Cause exacte **NON DÉTERMINÉ** sans inspection de la réponse de connexion réelle du backend pour ce compte.
- **`sender`/`receiver`/`from`/`to`** : **conforme**, aucun bug — sémantique identique et vérifiée par le code des deux plateformes.
- **`resource`/`versionCode`** : différences **délibérées et documentées** dans le code iOS lui-même (commentaires + historique git), pas des bugs de portage. `versionCode="1000"` est un hack temporaire connu et déjà signalé dans `project.yml`, sans lien fonctionnel avec le protocole chat (champ passif côté Android).
- **`messageId`/`stamp`** : **conforme**, algorithme identique vérifié bit à bit contre l'exemple capturé sur les deux plateformes.
- **Matrice des types d'objet** : couverture large mais incomplète — `sticker`/`gif` non composables (réception seule), `doc` sans rendu dédié, `location` totalement absent, `subscribe/renewSubscription/footer/header` non confirmés côté iOS.
- **Quote/reply** : **pleinement implémenté et fidèle** des deux côtés, aucun bug trouvé.
- **Temps réel** : c'est le point le plus nuancé. Le code iOS possède une implémentation Socket.IO complète et fidèle (mêmes noms d'événements, y compris la faute d'orthographe `"delivred"`, même mécanisme d'authentification au handshake, même configuration de reconnexion), câblée dans le cycle de vie de l'app. Deux failles réelles et distinctes ont néanmoins été confirmées : (a) la liste des conversations (`RosterListView`) n'est **explicitement pas** mise à jour en temps réel (aveu inline dans le code : "non câblé, refresh() manuel en attendant") — **CRITIQUE confirmé** ; (b) l'authentification du handshake socket est **explicitement non vérifiée contre un serveur réel** par le code source lui-même — **NON DÉTERMINÉ, vérification runtime nécessaire**. De plus, Android dispose d'un filet de sécurité FCM→sync REST que iOS n'a **pas porté** (délibérément hors périmètre) — **HIGH**, absence de rattrapage en cas d'échec silencieux du socket.

**Décompte des constats** (détail en §32) : **5 CRITIQUES, 4 HIGH, 6 MEDIUM, 3 LOW**, plus 4 points explicitement marqués NON DÉTERMINÉ nécessitant une vérification backend/runtime indépendante de ce document.

---

## 2. Android — source de vérité

Racine : `C:\Users\helen\AndroidStudioProjects\tiinver`, package `com.tiinver`. Persistance via SQLite pur (`Dbase.java`, **pas** Room — le module `roomDatabase` du dépôt est une zone fonctionnelle sans rapport avec le chat, confirmé par absence dans le graphe d'appel `messagerie`/`ChatRepository`/`ChatManager`). Le point d'entrée écran chat actif est confirmé être `ChatFragmentTest.java` (`ActivityMsg.java` L326-387 n'instancie que celui-ci) ; `ChatFragmentTestDeprecate.java` est du code mort malgré sa taille comparable — à ne jamais utiliser comme référence.

---

## 3. Architecture chat Android

| Rôle | Fichier | Classe / méthodes clés |
|---|---|---|
| Fabrique/options socket | `app/src/main/java/com/tiinver/messagerie/socketio/SocketInit.java` | `buildOptions(apiKey)`, `createSocket(apiKey)` |
| Singleton socket applicatif | `app/src/main/java/com/tiinver/App.java` | `getSocket()` L91-109, `connectSocket()` L118-128, `disconnectSocket()` L136-151, `resetSocket()` L157-171, `attachSocketLifecycleListeners()` L181-217 |
| Hub d'événements socket (singleton) | `app/src/main/java/com/tiinver/messagerie/repository/ChatRepository.java` (1179 lignes) | constantes `ROOM` L107-144, `registerAllListeners()` L234-278, `sendMessage/sendGroupMessage` L962-1004 |
| Logique métier / écriture DB | `app/src/main/java/com/tiinver/messagerie/ui/ChatManager.java` (1572 lignes) | `sendPrivateMessage()` L689-727, `sendGroupMessage()` L729-767, `addMessage()` L1156-1238, `addGroupMessage()` L1257-1351, `updateMessageStatus()` L1239-1255 |
| Générateur conversationId | `app/src/main/java/com/tiinver/messagerie/ui/ConversationIdGenerator.java` | `generateConversationId`, `generateGroupConversationId` |
| Constructeur de paquet fil | `app/src/main/java/com/tiinver/models/chat/MessagePacket.java` (1037 lignes) | `getPacketJson()`, `getPacketString()` L349-433 + builders par type L439-1033 |
| Modèle message | `app/src/main/java/com/tiinver/models/chat/MessageLib.java` | tous les champs `sender/receiver/from/to/nikname/object/verb/resource/giftId/status/stamp/isQuoted/quote*` |
| Fragment chat actif | `app/src/main/java/com/tiinver/messagerie/ui/ChatFragmentTest.java` (~3300 lignes) | `sendMessageText()` L2416, `sendMessageGift()` L2364, `onTextMessage()` L869-873 |
| Composant saisie | `app/src/main/java/com/tiinver/messagerie/layout/MessageEventLayout.java` | `interface MessageEventListener` L53-63 |
| Activity hôte | `app/src/main/java/com/tiinver/messagerie/ui/ActivityMsg.java` | instancie `ChatFragmentTest` L326-387 |
| ViewModel (fin délégateur) | `app/src/main/java/com/tiinver/messagerie/model/ChatViewModel.java` | délègue 1:1 à `ChatRepository` |
| Réseau REST | `app/src/main/java/com/tiinver/Http/TransportData.java` | `Post()`, `get()`, `volleyGet()`, `getDataFromServer()` |
| Récepteur FCM | `app/src/main/java/com/tiinver/back_sync/MyFirebaseMessagingService.java` | `onMessageReceived()` L83-120, `onNewToken()` L75-78 |
| Worker de sync arrière-plan | `app/src/main/java/com/tiinver/service/TiinverSyncWorker.java` | `doWork()` → `visiteServeur()` L75-114 |
| Schéma SQLite | `app/src/main/java/com/tiinver/Dbase.java` | `wk_messages` L31, `wk_roster` L38 |
| ContentProvider | `app/src/main/java/com/tiinver/back_sync/StubProvider.java` | `MSG_URI`, `ROSTER_URI` |
| Cache session | `app/src/main/java/com/tiinver/manager/SessionManager.java` | `getUser()`, `saveUser()` |
| Adaptateur RecyclerView | `app/src/main/java/com/tiinver/messagerie/ui/adapter/MessageListAdapter.java` | `getItemViewType()` L1210 |

---

## 4. Architecture chat iOS

| Rôle | Fichier | Type / membres clés |
|---|---|---|
| UI de composition/envoi | `Sources/TiinverSwift/Messagerie/ChatView.swift` | `ChatView` (546 lignes) |
| Logique métier chat | `Sources/TiinverSwift/Messagerie/ChatViewModel.swift` | `ChatViewModel` (903 lignes) — `sendText`, `sendMedia`, `sendGift`, `sendGraphic`, `handleAppear`, `subscribeToRealtimeEvents`, `onIncoming` |
| Rendu des bulles | `Sources/TiinverSwift/Messagerie/ChatBubbleViews.swift` | `ChatBubbleRow`, `TextBubbleBody`, `AudioBubbleBody`, `MediaImageBubbleBody`, `VideoBubbleBody`, `GiftBubbleBody`, `GraphicPlaceholderBubbleBody` |
| Liste des conversations | `Sources/TiinverSwift/Messagerie/RosterListView.swift` | `RosterListViewModel`, `refresh()` L223 |
| Nouvelle conversation 1:1 | `Sources/TiinverSwift/Messagerie/NewMessageView.swift` | `rosterTarget` L29-48 |
| Modèle enveloppe fil | `Sources/TiinverSwift/Models/MessagePacket.swift` | `MessagePacket` — `packetJSON()`, `buildPacketString()` |
| Modèle message local/reçu | `Sources/TiinverSwift/Models/MessageLib.swift` | `MessageLib: Codable`, décodage custom L124-177 |
| Identité conversation | `Sources/TiinverSwift/Models/RosterModel.swift` | `RosterModel` |
| Algorithme conversationId | `Sources/TiinverSwift/Models/ConversationIdGenerator.swift` | `ConversationIdGenerator` L11-13 |
| Transport socket | `Sources/TiinverSwift/Realtime/TiinverSocket.swift` | `TiinverSocket` (Socket.IO-Client-Swift) |
| Hub d'événements socket | `Sources/TiinverSwift/Realtime/ChatRepository.swift` | `ChatRepository` (761 lignes) |
| Noms d'événements socket | `Sources/TiinverSwift/Realtime/SocketEvent.swift` | `SocketEvent` (78 lignes) |
| Bus d'événements Combine | `Sources/TiinverSwift/Models/ChatEvent.swift` | `ChatEvent`, `MessageDeliveryStatus`, `PBSEvent` |
| Détection réseau | `Sources/TiinverSwift/Realtime/NetworkMonitor.swift` | `NetworkMonitor` (`NWPathMonitor`) |
| Persistance locale messages | `Sources/TiinverSwift/Storage/MessageRepository.swift` | `MessageRepository` (Core Data, `MessageEntity`), `SerialTaskQueue` L493-511 |
| Persistance roster | `Sources/TiinverSwift/Storage/RosterRepository.swift` | `RosterRepository` (Core Data, `RosterEntity`), `updateRoster()` L79-80 |
| Client REST | `Sources/TiinverSwift/Networking/APIClient.swift` | `APIClient` (Alamofire) |
| État session utilisateur | `Sources/TiinverSwift/Security/UserSession.swift` | `UserSession` (UserDefaults + Keychain), `nikname` L72-75 |
| Enregistrement FCM | `Sources/TiinverSwift/Notifications/PushTokenRegistrar.swift` | `PushTokenRegistrar` |
| Délégué push | `Sources/TiinverSwift/App/AppDelegate.swift` | `AppDelegate` |
| Contenu notifications locales | `Sources/TiinverSwift/Notifications/LocalNotificationBuilder.swift` | `LocalNotificationBuilder` |
| Routage post-login/reprise session | `Sources/TiinverSwift/Navigation/RootRouterView.swift` | `attachToCurrentSocket()` appelé L59, L180 ; `startNetworkMonitor()` L177-181 |

---

## 5. Cycle de vie de la conversation

**Android** : `conversationId` est calculé **une seule fois**, systématiquement, dans `ChatFragmentTest.init()` L1433, **avant** que l'écran de chat puisse même charger ses messages (le `CursorLoader` filtre `"conversationId=?"`, L1442/L1456-1466) — il n'existe donc structurellement aucun chemin pour ouvrir un écran de chat Android sans `conversationId` déjà résolu, que la conversation soit nouvelle ou existante.

**iOS** : deux chemins distincts, avec un écart réel :
- **Conversation existante** (depuis `RosterListView`) : `conversationId` correctement propagé depuis `RosterEntity.conversationId` (`RosterListView.swift:257`).
- **Nouvelle conversation** (recherche téléphone/email, profil, contact, membre de groupe) : **`conversationId` n'est jamais assigné** au `RosterModel` cible construit par :
  - `NewMessageView.swift:29-48` (`rosterTarget`)
  - `ProfileView.swift:319-334` (`messageTarget`)
  - `Messagerie/ContactPickerView.swift:129-136` (`rosterModel(for:)`)
  - `Messagerie/GroupDetailView.swift:370-381` (`chatTarget`)

  Vérifié par grep direct : `NewMessageView.swift` ne contient **aucune** occurrence du mot `conversationId`.

Voir §8 pour la trace complète et l'effet de cascade sur le roster.

---

## 6. Cycle de vie du message

Voir §20 (envoi) et §21 (réception) pour le détail étape par étape. En résumé, sur les deux plateformes le message suit : construction locale → écho optimiste immédiat (statut `0`/pending) → émission Socket.IO → accusé serveur (`status` 1→2→3) → mise à jour UI. La différence structurelle notable : Android construit le paquet fil par **concaténation de chaînes manuelle** (`MessagePacket.getPacketString()`, pas de sérialiseur JSON réel), tandis qu'iOS utilise des dictionnaires Swift assemblés puis sérialisés (`MessagePacket.packetJSON()`), ce qui élimine par construction les artefacts de concaténation de `null` (voir §16).

---

## 7. Protocole de charge utile (payload)

### Exemple iOS annoté

```json
{"conversationId":"", "from":"SO_95", "isQuoted":"false", "message":"Ok",
 "messageId":"1961788470043124", "nikname":"", "object":"text",
 "profile":"https://cdn.tiinver.com/...", "receiver":"197", "resource":"iOS",
 "sender":"196", "stamp":"1788470043124", "status":"0", "to":"IssaMahamat",
 "type":"chat", "verb":"post", "versionCode":"1000"}
```
`messageId = sender + stamp = "196" + "1788470043124" = "1961788470043124"` — vérifié exact (§11).

### Exemple Android annoté

```json
{"messageId":"244141788462517668", "conversationId":"24414_2594", "type":"chat",
 "to":"Tiinver", "sender":"24414", "receiver":"2594", "from":"SIM2%",
 "nikname":"SIM 2% Afla  ", "message":"Salut je suis à la recherche d'un producteur svp",
 "giftId":"null", "verb":"post", "object":"text",
 "profile":"https://cdn.tiinver.com/...", "status":"0", "stamp":"1788462517668",
 "resource":"null", "versionCode":"380", "isQuoted":"false"}
```
`conversationId = sort(["24414","2594"]).join("_") = "24414_2594"` — vérifié exact (§8). `messageId = "24414"+"1788462517668" = "244141788462517668"` — vérifié exact (§11).

Les deux échantillons confirment la même forme de champ (18 clés côté Android incluant `giftId`, 15 côté iOS **sans** `giftId` — écart réel, voir §16).

---

## 8. conversationId

**Génération — identique algorithmiquement des deux côtés** (tri lexicographique des deux identifiants numériques, joints par `"_"`) :

Android, `ConversationIdGenerator.java` L22-31 :
```java
List<String> userIds = Arrays.asList(currentUser, remoteUser);
Collections.sort(userIds);
return TextUtils.join("_", userIds);
```
iOS, `ConversationIdGenerator.swift:11-13` :
```swift
static func conversationId(currentUser: String, remoteUser: String) -> String {
    [currentUser, remoteUser].sorted().joined(separator: "_")
}
```
**Qui génère** : 100 % client, aucune génération serveur, aucun round-trip requis, sur les deux plateformes.

**Où c'est stocké** : Android — colonnes `conversationId TEXT` dans `wk_messages` et `wk_roster` (`Dbase.java` L31, L38). iOS — `RosterEntity.conversationId` / `MessageEntity` (Core Data, `Storage/RosterRepository.swift`, `Storage/MessageRepository.swift`).

**Confiance sur réception** : sur les deux plateformes, le `conversationId` reçu sur le fil n'est **pas** utilisé tel quel — il est **recalculé localement** à partir de `sender`/`receiver` (Android : `ChatManager.addMessage()` L1161 ; iOS : `ChatViewModel.onIncoming()` L353, `MessageRepository.swift:131-132/187`). Ce choix garantit que les deux pairs convergent vers la même valeur indépendamment de ce que le serveur a réellement relayé.

**CAUSE EXACTE DU `conversationId` VIDE OBSERVÉ SUR IOS (CHAT-F-001, CRITIQUE)** :

`ChatViewModel.buildOutgoingBase(object:)` (`ChatViewModel.swift:549`) copie `target.conversationId` tel quel dans `mlib.conversationId`. `MessagePacket.init(fromPrivate:)` (`MessagePacket.swift:68`) le recopie sans modification, et `commonFields()` (`MessagePacket.swift:280`) sérialise `"conversationId": conversationId ?? ""`.

Le `target: RosterModel` provient, pour une **nouvelle** conversation, de l'un des 4 sites listés en §5 — **aucun n'appelle `ConversationIdGenerator`**. L'exemple capturé (`from:"SO_95"`, `to:"IssaMahamat"`) est cohérent avec exactement ce chemin (premier message à un contact nouvellement trouvé).

**Effet de cascade découvert pendant l'audit (aggrave la sévérité)** : `RosterRepository.updateRoster(message:isFromServer:)` (`Storage/RosterRepository.swift:79-80`) commence par :
```swift
guard let conversationId = message.conversationId else { return }
```
Cette méthode est appelée par le chemin d'écho optimiste local de **tout** message sortant (`MessageRepository.insertTextMessage`/`insertFileMessage`, appelés par chaque `ChatViewModel.send*`). Donc, quand `conversationId` est vide (exactement le scénario ci-dessus), **la ligne roster de la nouvelle conversation n'est ni créée ni mise à jour** — la conversation n'apparaît dans `RosterListView` qu'après qu'une réponse du pair arrive (le calcul y est correct côté réception, §8 ci-dessus).

**Verdict Android** : `"24414_2594"` correspond exactement à `generateConversationId(myId="24414", remoteId="2594")` — aucune anomalie Android à corriger, l'algorithme est toujours invoqué avant tout envoi possible côté Android structure d'écran.

---

## 9. sender / receiver / from / to

**Preuve Android** — `ChatFragmentTest.sendMessageText()` L2416-2465 :
```java
mlib.setTo(userData.getTo());           // to       = handle/username du pair
mlib.setFrom(currentUsername);          // from     = MON username
mlib.setSender(myId);                   // sender   = MON id numérique
mlib.setReceiver(userData.getUserId()); // receiver = id numérique du pair
```
Puis `ChatManager.sendPrivateMessage()` L699-707 réécrit `from` depuis le cache session (`Settings.getStringPreference(..., USERNAME)`), pas depuis `mlib.getFrom()` — une resource de vérité différente pour la même valeur, mais sémantiquement équivalente (les deux sont "mon propre username").

**Preuve iOS** — `ChatViewModel.buildOutgoingBase(object:)` (`ChatViewModel.swift:545-582`) puis `MessagePacket.init(fromPrivate:currentUsername:)` (`MessagePacket.swift:71-74`) :
```swift
mlib.to = target.to                 // to       = username du pair
mlib.from = currentUsername         // from     = MON username (session, pas mlib.from — même écart qu'Android)
mlib.sender = myId                  // sender   = MON id numérique
mlib.receiver = target.userId       // receiver = id numérique du pair
```

**Verdict : CONFORME.** `from`/`to` = usernames, `sender`/`receiver` = identifiants numériques, sur les deux plateformes, avec le même écart mineur (`from` réécrit depuis le cache session plutôt que depuis l'objet en mémoire) répliqué fidèlement. Confirmé exact contre l'exemple capturé : `sender="196"`, `receiver="197"`, `from="SO_95"`, `to="IssaMahamat"`. Aucun bug.

---

## 10. nickname (`nikname`)

**Android** : au login, mis en cache SharedPreferences par `SessionManager.saveUser()` (`SessionManager.java` L41-57) : `editor.putString(infoContract.NIKNAME, user.getNikname())`. À l'envoi, **relu frais** depuis ce cache dans `ChatManager.sendPrivateMessage()` L690, **pas** depuis la copie en mémoire de `MessageLib` (qui, elle, est peuplée avec le nikname du **pair**, pas le sien — `ChatFragmentTest.sendMessageText()` L2423 : `mlib.setNikname(userData.getNikname())`, valeur ensuite écrasée pour le paquet fil mais potentiellement incorrecte pour la ligne DB locale de l'écho — anomalie Android préexistante, non liée au bug iOS, signalée pour information).

**iOS** : `MessagePacket.init(fromPrivate:currentUsername:)` (`MessagePacket.swift:75`) :
```swift
nikname = UserSession.shared.nikname
```
`UserSession.nikname` (`Security/UserSession.swift:72-75`) lit `UserDefaults["nikname"]`, écrit uniquement par `UserSession.save(_:)` (`UserSession.swift:158` : `nikname = user.nikname`), appelé après connexion. `User.nikname` (`Models/User.swift:14,98`) est décodé normalement depuis la clé JSON `"nikname"` de la réponse de connexion — **aucun hardcodage à vide dans le code**, le mécanisme est structurellement équivalent à celui d'Android (cache de session, lu au moment de l'envoi).

**CAUSE EXACTE (CHAT-F-002)** : la valeur en cache (`UserSession.shared.nikname`) est vide/nil au moment de l'envoi pour ce compte. Deux explications possibles, non tranchables par le code seul :
1. La réponse de connexion backend pour ce compte spécifique renvoie un `nikname` vide/absent.
2. Le compte n'a simplement jamais eu de nikname configuré côté backend.

**NON DÉTERMINÉ — vérification backend/runtime nécessaire** : inspecter la réponse JSON réelle de l'endpoint de connexion pour le compte `SO_95`/utilisateur `196`, et vérifier si le champ `nikname` y est bien présent et non vide. Si le backend l'envoie correctement, il faudra alors auditer plus finement pourquoi `UserSession.save()` ne l'a pas persisté (hors périmètre de ce que le code seul permet de trancher).

**Différence architecturale à noter** : Android relit le cache à **chaque** envoi (5 sites d'appel identifiés : `ChatManager.java` L221, L345, L611, L651, L690, L730), donc une mise à jour du nikname en cours de session serait immédiatement reflétée. iOS lit `UserSession.shared.nikname` de la même façon à chaque appel de `MessagePacket.init` — mécanisme équivalent, pas de differance de fraîcheur trouvée.

---

## 11. messageId

**Android** — répété à chaque site d'envoi (`ChatFragmentTest.sendMessageText()` L2417-2418) :
```java
long unixTime = System.currentTimeMillis();
String messageId = myId + unixTime;   // concaténation de chaînes
```

**iOS** — `ChatViewModel.swift:546-548` :
```swift
let unixMillis = Int64(Date().timeIntervalSince1970 * 1000)
mlib.messageId = myId + String(unixMillis)
```

**Verdict : CONFORME, algorithme identique** — `<id utilisateur numérique><13 chiffres epoch ms>`, sans séparateur, sans composant aléatoire. Vérifié exact sur les deux échantillons capturés (§7). Risque de collision identique et réel sur les deux plateformes si le même utilisateur envoie deux messages dans la même milliseconde — aucune plateforme n'a de garde contre ce cas (ni UUID, ni compteur de séquence). Ce n'est **pas** un écart de portage, c'est un risque déjà présent dans la référence Android, reproduit fidèlement.

**Usage identique des deux côtés** : dédoublonnage avant insertion (Android `ChatManager.isMessageExist()` L73-82 ; iOS `MessageRepository.messageExists(messageId:)` L52-54), correspondance d'accusé de réception par `messageId`, cible de suppression. Ni Android ni iOS n'a de `quoteMessageId` distinct — la citation est dénormalisée (voir §18), pas référencée par id, sur les deux plateformes.

---

## 12. stamp

**Android** : `String.valueOf(System.currentTimeMillis())` (`ChatFragmentTest.sendMessageText()` L2453), millisecondes, généré côté client uniquement, jamais substitué par une valeur serveur. Utilisé comme clé de tri principale (`ORDER BY stamp`, `ChatManager.getSpecifiqueMessage()` L85).

**iOS** : `ChatViewModel.swift:573` : `mlib.stamp = String(Int64(Date().timeIntervalSince1970 * 1000))` — même unité (ms), même origine (client), même usage.

**Verdict : CONFORME.** Point notable découvert côté iOS uniquement : `deliverTime` (champ distinct de `stamp`) est calculé en **secondes**, pas en millisecondes (`ChatViewModel.swift:574` : `String(Int64(Date().timeIntervalSince1970))`) — une vraie différence d'unité entre deux champs de temps voisins dans le même fichier. Il n'a pas été possible dans cette passe de confirmer si `deliver_time` côté Android (présent dans l'enveloppe `getPacketJson()`, `MessagePacket.java` L295-311) est en secondes ou millisecondes — **NON DÉTERMINÉ**, à vérifier en relisant les sites d'assignation de `deliver_time` côté Android avant de considérer ceci comme un bug iOS à corriger.

**Gestion d'horloge erronée** : **NON DÉTERMINÉ des deux côtés** — aucun code de correction/validation d'horloge trouvé ni sur Android ni sur iOS.

---

## 13. status

**Machine à états Android**, `ChatRepository.onResponse` (L735-765) :
```
0 (pending, création locale) → 1 "sended" (accusé serveur) → 2 "delivered" (livré au destinataire) → 3 "displayed" (lu) ; 4 "reproduced" (lecture audio) partage l'icône de 3.
```

**Machine à états iOS**, `MessageDeliveryStatus` (`Models/ChatEvent.swift:27-32`) :
```swift
enum MessageDeliveryStatus: Int {
    case sent = 1, delivered = 2, displayed = 3, reproduced = 4
}
```
Statut initial `0` avant tout accusé (`ChatViewModel.swift:567`), mis à jour via le listener socket `"on response"` (`ChatRepository.handleResponse`, `Realtime/ChatRepository.swift:445-461`), mappant `"sended"/"delivered"/"displayed"/"reproduced"` exactement comme Android.

**Verdict : CONFORME**, valeurs, noms et transitions identiques. Confirmé exact contre l'échantillon (`"status":"0"` sur les deux exemples capturés).

---

## 14. resource

**Android** : par défaut `android.os.Build.MODEL` (modèle d'appareil réel, ex. `"SM-A125F"`), assigné à chaque envoi standard (`ChatFragmentTest.sendMessageText()` L2449). **Exception confirmée** : les messages construits via `ChatRepository.buildCallMessageLib()` (L1042-1049, messages liés aux appels) n'appellent jamais `setResource()`, donc restent `null` Java → concaténés en la chaîne littérale `"null"` dans le paquet fil (`MessagePacket.java`, concaténation de chaînes, pas un sérialiseur). C'est le mécanisme confirmé qui produit `"resource":"null"` pour les flux liés aux appels. **NON DÉTERMINÉ** pourquoi l'échantillon Android capturé précisément (un message `object:"text"`, `versionCode:"380"`) montre `"null"` alors que le code actuel de `ChatFragmentTest` pour un texte standard devrait renseigner le modèle d'appareil réel — hypothèse la plus probable : révision de build plus ancienne que celle lue dans ce dépôt, non vérifiable sans accès à l'historique de version exact du build `380`.

**iOS** : littéral codé en dur `"iOS"`, `ChatViewModel.swift:570` : `mlib.resource = "iOS"`, avec justification inline (`MessagePacket.swift:218-223`) — pas d'équivalent significatif à `Build.MODEL` sans table de correspondance identifiant→nom d'appareil, remplacé délibérément par le nom de plateforme.

**Verdict : différence délibérée et documentée, PAS un bug.** Confirmé côté Android que ce champ n'est consommé par **aucune** logique conditionnelle côté client (`ChatManager.addMessage()` L1196 le stocke tel quel, sans branchement) — c'est une métadonnée passive (diagnostic/analytique côté serveur probable). Aucune action corrective nécessaire.

---

## 15. versionCode

**Android** : `MessagePacket.java` L16 : `public int versionCode = BuildConfig.VERSION_CODE;` — numéro de build Gradle réel, non modifiable message par message. Stocké tel quel en réception (`wk_messages.versionCode`, défaut `126`). **Aucune logique côté client ne relit ce champ pour une décision de protocole** — métadonnée passive, présumée utilisée côté serveur (analytics/gating de compatibilité).

**iOS** : deux sites lisent la même clé `Info.plist` `CFBundleVersion` :
- `ChatViewModel.swift:571`
- `MessagePacket.swift:225` (jamais réécrit depuis `mlib` dans aucun des 4 initialiseurs `MessagePacket`)

`CFBundleVersion = "1000"` dans `project.yml`. **Historique git confirmé** (commit `b81aacf`, "Fix: CFBundleVersion et app_expire_* releves pour test Appetize.io (temporaire)", 2026-08-13) :
> Le projet Firebase est partagé avec l'app Android en production (versionCode réel **378**, vérifié dans `app/build.gradle`)... relevé à "1000" (marge au-dessus de 378, pas un nombre au hasard)... **TEMPORAIRE**... à remettre à une valeur réelle avant soumission App Store.

Donc : le vrai `versionCode` Android est **378** (l'échantillon capturé dans cette tâche affiche `380`, une build légèrement différente — écart d'échantillonnage, pas une contradiction avec le commit). `"1000"` sur iOS est un artifice **volontaire et déjà documenté** pour satisfaire la porte de mise à jour forcée de Firebase Remote Config pendant les tests Appetize.io — son apparition dans le protocole chat est un **effet de bord non anticipé** du partage de la même clé `CFBundleVersion` entre deux fonctionnalités (gating de version + métadonnée chat).

**Verdict : problème déjà connu et déjà tracé dans le dépôt** (`project.yml`), pas une découverte nouvelle de cet audit — mais confirmé impactant réellement la charge utile chat, ce qui n'était peut-être pas explicite au moment où le hack a été introduit. **NON DÉTERMINÉ** si le backend effectue un contrôle quelconque sur `versionCode` (gating, compatibilité) qui rendrait `"1000"` fonctionnellement dangereux plutôt que seulement cosmétique — à vérifier côté backend.

---

## 16. giftId

**Android** : `MessageLib.giftId` (`MessageLib.java` L224), `String` sans défaut → `null` Java si jamais assigné. `MessagePacket.getTextPrivateMessageNoquotedPattern()` L449 inclut **toujours** `"\"giftId\":\""+giftId+"\","` — concaténation de chaînes brute, donc `null` devient la chaîne littérale `"null"` (pas un JSON `null`, une vraie chaîne de 4 caractères). Le champ est **inconditionnellement présent** dans tous les patterns texte/gift.

**iOS** : `MessageLib.giftId` et `MessagePacket.giftId` existent comme champs et sont copiés (`MessagePacket.swift:69`), **mais ne sont jamais sérialisés sur le fil** : `commonFields(isGroup:)` (`MessagePacket.swift:278-294`) ne contient **aucune** clé `"giftId"`.

**CHAT-F-012 (MEDIUM, écart de forme protocolaire réel)** : contrairement à Android qui envoie systématiquement `"giftId":"<valeur ou 'null'>"` pour **tout** message (texte inclus), iOS n'envoie **jamais** cette clé, pour aucun type de message. Le catalogue/prix du cadeau est en pratique transmis par un appel REST séparé (`POST message/gift`, `WalletRepository.swift:171-175`, params `sender/receiver/price/messageId`) — identique au flux Android (`ChatRepository.sendGift()` L1087-1133, même endpoint, mêmes params) — donc la fonctionnalité cadeau elle-même n'est probablement pas cassée. **NON DÉTERMINÉ** si le backend (ou d'éventuels clients Android en écoute) suppose la présence systématique de la clé `giftId` dans le JSON du message socket lui-même (au-delà de l'appel REST dédié) — à vérifier côté backend/parsing serveur.

---

## 17. Matrice des types d'objet (`object`)

| `object` | Android : verb / builder | Android : champs additionnels | iOS : rendu | iOS : composable ? | Conforme ? |
|---|---|---|---|---|---|
| `text` | `post` / `getTextPrivateMessage[No]QuotedPattern` | `message` | `TextBubbleBody` | Oui — `sendText()` | Oui |
| `gift` | `post` / même builder que `text` | `giftId`, `message` (inutilisé) | `GiftBubbleBody` | Oui — `sendGift(giftId:)` | Partiel (voir §16, `giftId` absent du fil) |
| `graphic` | — / `getGraphicPrivateMessage…Pattern` | `MgGraphic` (JSON brut) | `GraphicPlaceholderBubbleBody` (replay `PBSCanvasEngine`) | Oui — `sendGraphic(payload:)` | Oui |
| `audio` | — / `getAudioPrivateMessagePattern[No]Quoted` | `object_url`, `duration` | `AudioBubbleBody` (forme d'onde **aléatoire**, reproduit `new Random().nextInt(50)` d'Android à l'identique) | Oui — enregistreur vocal | Oui |
| `video` | — / `getVideoPrivateMessagePattern[No]Quoted` | `object_url`, `thumbnail_url`, `image_byte`, `width`, `height`, `duration` | `VideoBubbleBody` | Oui — `attachVideo` | Oui |
| `photo`, `gif`, `sticker` | partagent **un seul builder** (`case "photo","gif","sticker":`) | `object_url`, `image_byte`, `width`, `height` | `photo` : `MediaImageBubbleBody` ; `gif`/`sticker` : même vue en **réception** | `photo` : oui. `gif`/`sticker` : **NON** — sélecteur GIF/sticker = placeholder littéral (`ChatView.swift:366-369`, texte "à porter") | Écart confirmé — gap fonctionnel |
| `information`, `missedvoicecall` | routés vers le pattern texte, jamais cités | — | `SystemInfoRow` / `MissedCallBubbleRow` | Générés système uniquement | Oui (réception) |
| `voicecall` | traité hors `MessagePacket`, inline dans les listeners d'appel | — | Idem, routé vers le sous-système d'appel | n/a | Oui |
| `subscribe`, `renewSubscription`, `footer`, `header` | absents du switch → `default:` (bug Android préexistant : retombe sur le builder **privé** même en groupe) | `price`, `lucrative`, `creator`, `regroupage` | **Non confirmé côté iOS dans cette passe** | **NON DÉTERMINÉ** | À vérifier |
| `deletemessage` | `verb="deletemessage"`, traité spécialement | — | Texte italique "message supprimé" | Généré par les flux de suppression uniquement | Oui |
| `doc` | **NON DÉTERMINÉ côté Android** (aucune preuve directe trouvée dans cette passe, à confirmer par une lecture ciblée) | — | **Aucune vue dédiée** — retombe sur `TextBubbleBody` par défaut ; pas de `case "doc"` dans `objectFields()` (donc `object_url` jamais envoyé) | Non composable | Gap confirmé côté iOS |
| `location` | **NON DÉTERMINÉ côté Android** (non recherché explicitement dans cette passe) | — | **Aucun support** — ni champ modèle, ni bulle, ni composition | Non composable | Gap potentiel, à confirmer côté Android d'abord |

**Verdict global §17** : la couverture iOS est large pour les types réellement utilisés en pratique (texte, média, cadeau, graphique, audio), mais présente des gaps réels et vérifiés : `sticker`/`gif` non composables, `doc` sans rendu dédié, et `subscribe`/`renewSubscription`/`footer`/`header`/`location` **non confirmés** côté iOS dans cette passe — nécessitent une vérification de code ciblée supplémentaire avant de les classer définitivement gap ou non-applicable.

---

## 18. Quote / reply

**Android** — déclenchement UI par balayage (`MessageSwipeController`, `ChatFragmentTest.onStart()` L1054-1091) :
```java
quoteTitle    = isCurrentUser ? currentUsername : mAdapter.get(listIndex).getUsername();
quoteObject   = mAdapter.get(listIndex).getObject();
quoteDuration = mAdapter.get(listIndex).getQuoteDuration();
// quoteMessage : texte tronqué à 40 caractères pour "text", placeholder localisé pour audio/photo/video/graphic
```
`isQuoted = true` (L2123). **Aucune référence au `messageId` d'origine, à la photo de profil, ni à `object_url` n'est incluse** — uniquement des copies dénormalisées (titre, extrait tronqué ou placeholder, type, durée). Forme fil (`MessagePacket.getTextPrivateMessageQuotedPattern()` L461-486) : 4 champs additionnels `quoteTitle`, `quoteMessage`, `quoteObject`, `quoteDuration`, avec un pattern symétrique quoted/non-quoted pour chaque type de média. `isQuoted` stocké et transmis comme **chaîne** `"true"`/`"false"`, pas un booléen JSON natif — confirmé exact contre l'échantillon `"isQuoted":"false"`.

**iOS** — pleinement implémenté et symétrique :
- Modèle : `MessageLib.isQuoted/quoteMessage/quoteTitle/quoteObject/quoteDuration` (`MessageLib.swift:50-54`), décodage **tolérant** via `decodeLenientBoolIfPresent` (`MessageLib.swift:151`) pour absorber les booléens envoyés comme chaînes par le backend.
- Composition : `ChatViewModel.startQuote(for:)` (`ChatViewModel.swift:788-803`), UI `ChatView.quoteBar` (`ChatView.swift:295-310`), déclenchée par balayage (`ChatBubbleViews.swift:68-71`).
- Envoi : `buildOutgoingBase()` (`ChatViewModel.swift:575-579`) + `MessagePacket.quoteFields()` (`MessagePacket.swift:323-325`), fusionné uniquement `if isQuoted` (`MessagePacket.swift:264-265`).
- Réception : `QuoteBoxView` (`ChatBubbleViews.swift:146-158`).

**Verdict : CONFORME, aucun bug.** Ni Android ni iOS ne référence le message d'origine par `messageId` — comportement identique et volontairement reproduit à l'identique, pas une régression iOS.

---

## 19. Endpoints API

| Fonction | Android | iOS | Identique ? | Problème |
|---|---|---|---|---|
| Envoi message (texte/gift/graphic/quote) | Socket.IO `emit("new message"/"new message group", ...)` | Socket.IO `emit(SocketEvent.newMessage, ...)` | Oui | Aucun — aucun endpoint REST dédié d'envoi sur aucune des deux plateformes |
| Upload média (photo/vidéo/audio) | REST `POST {SERVER}message` via `UploadChatWork` (WorkManager) | PUT direct **BunnyCDN** (`storage.bunnycdn.com`, header `AccessKey`) via `ChatMediaUploadService` | **Non** — pipelines différents | Écart architectural réel, voir note ci-dessous |
| Confirmation cadeau | REST `POST message/gift` (`sender,receiver,price,messageId`) | REST `POST message/gift` (mêmes params) | Oui | Aucun |
| Sync de secours (déclenchée FCM) | REST `GET message/{myId}`, `GET group/message/{myId}`, `GET messagestatus/{myUsername}` | **Absent** — non porté | **Non** | Voir §24, HIGH |
| Historique paginé (groupe) | `GET group/{groupId}/messages?lastDate=&limit=` | `GET group/{groupId}/messages?lastDate=&limit=` (`GroupRepository.swift:387`) | Oui | Aucun |
| Suppression message | `GET deletemessage/{messageId}` | `GET deletemessage/{messageId}` (`ChatRepository.swift:554-556`) | Oui | Aucun |
| Recherche conversation/groupe | `search/{myId}/{query}` (Android, présumé côté groupe) | Recherche locale en mémoire confirmée (`ChatSearchView.swift`) ; appel réseau **non confirmé** dans cette passe | NON DÉTERMINÉ | À vérifier |
| Enregistrement token FCM | `POST user {id, column:"fcmId", value:token}` | `POST user {id, column:"fcmId", value:token}` (`PushTokenRegistrar.swift:41-59`) | Oui | Aucun |

**Note sur l'upload média** : Android utilise son propre backend REST (`POST message`) pour l'upload direct des fichiers, tandis qu'iOS pousse directement vers BunnyCDN avec une clé d'accès dédiée. **NON DÉTERMINÉ** si cela reflète une migration backend plus récente (adoption de BunnyCDN) que le code Android lu dans ce dépôt n'a pas encore intégrée, ou une divergence introduite côté iOS sans confirmation backend — à trancher avec l'équipe backend/produit avant toute action.

---

## 20. Pipeline d'envoi (SEND)

**Android**, texte privé, étape par étape : UI (`MessageEventLayout` → `onTextMessage`) → `ChatFragmentTest.sendMessageText()` L2416 (construction `MessageLib`, `messageId`, `conversationId` précalculé, `to/from/sender/receiver`, `nikname` pair, `object/verb/status/resource/stamp`) → insertion optimiste SQLite (`status=0`) → `sendSimpleMessage()` L3002 → `ChatViewModel.sendPrivateMessage()` → `ChatManager.sendPrivateMessage()` L689 (re-dérivation `nikname`/`username`/`profile` depuis le cache session) → `MessagePacket.getPacketJson()` (empaquetage `packet` stringifié) → `ChatRepository.sendMessage()` L964 : `socket.emit("new message", packetJson)` → round-trip serveur (**NON DÉTERMINÉ**, code serveur hors dépôt) → accusé `"on response"` → mise à jour statut + UI.

**iOS**, texte privé : `ChatView` composeur → `ChatViewModel.sendText()` (`ChatViewModel.swift:395-404`) → `buildOutgoingBase(object:"text")` (`:545-582`, construction `MessageLib` complète) → `appendOptimistic(mlib)` (`:590-593`, écho immédiat) → `MessageRepository.insertTextMessage(mlib)` (Core Data, `status=0`) → **découplé** : la transmission réseau réelle se déclenche à `ChatViewModel.handleAppear(of:)` (`:601-618`, quand la bulle devient visible) → `send(mlib)` → `chatRepository.sendPrivateMessage(mlib)` → `MessagePacket(fromPrivate:currentUsername:)` → `socket.emit(SocketEvent.newMessage, packet.packetJSON())` (`ChatRepository.swift:514`).

**Différence structurelle notable** : Android déclenche l'émission socket immédiatement après l'insertion locale (dans le même flux synchrone `sendSimpleMessage`) ; iOS **découple** l'émission et ne l'exécute que lorsque la bulle devient visible à l'écran (`handleAppear`). Cela reproduit fidèlement un comportement Android équivalent basé sur la visibilité RecyclerView (non contredit par les preuves recueillies), mais introduit une dépendance à l'affichage effectif de la bulle pour déclencher l'envoi réel — **NON DÉTERMINÉ** si un cas limite (bulle jamais rendue visible, ex. liste très longue ou vue quittée avant layout) pourrait retarder indéfiniment l'émission réelle côté iOS ; mérite un test ciblé (voir §34).

---

## 21. Pipeline de réception (RECEIVE) — hors temps réel, voir §22 pour le mécanisme temps réel lui-même

**Android** : listener socket → `chatManager.addMessage(meta)` (persistance SQLite + dédoublonnage `messageId`) → `ChatModel` → `sendLiveData()` → `MutableLiveData` statique → `ChatViewModel.observeForever` → Fragment (`CursorLoader` sur `MSG_URI`, notifié automatiquement par `ContentResolver.notifyChange()` implicite lors de l'insertion).

**iOS** : listener socket → `ChatRepository.handleNewMessage()` (`:312-398`, décodage défensif élément par élément) → persistance Core Data (`MessageRepository.addMessage`, dédoublonnage `messageId` via `SerialTaskQueue` actor pour éviter une race sur deux livraisons concurrentes) → `chatEvents.send(.message(meta))` (Combine `PassthroughSubject`) → `ChatViewModel.subscribeToRealtimeEvents()` → filtrage par correspondance conversation (`meta.from == target.to` pour le privé) → `onIncoming()` → insertion dans `items` + son de réception.

**Verdict : CONFORME dans la structure.** Les deux pipelines suivent le même schéma général (persistance d'abord, notification/événement ensuite, UI en observateur). Aucun bug structurel trouvé dans cette partie hors temps réel proprement dit.

---

## 22. Architecture temps réel — SECTION LA PLUS CRITIQUE

**Verdict Android (§14/§15 du rapport de recherche)** : mécanisme confirmé = **Socket.IO exclusivement**, événements `"new message"`/`"new message group"`, connexion WebSocket permanente maintenue pour toute la durée de vie de l'app, listeners enregistrés une seule fois à la construction du singleton `ChatRepository` et jamais désenregistrés pour les événements de message central (contrairement aux listeners typing/presence, activés/désactivés par écran). FCM **n'est pas** le canal temps réel — confirmé explicitement par le commentaire `// Ne RIEN parser ici` dans `MyFirebaseMessagingService.onMessageReceived()` (L99) : chaque push FCM déclenche uniquement un `TiinverSyncWorker` de synchronisation REST différé de 2 secondes, jamais un rendu direct du contenu.

**Verdict iOS** : contrairement à l'hypothèse implicite de l'observation déclenchante ("mécanisme absent"), **le code source montre une implémentation Socket.IO complète et fidèle** :
- Bibliothèque `Socket.IO-Client-Swift`, pas de WebSocket brut, pas de polling.
- **Noms d'événements identiques bit à bit à Android**, y compris la faute d'orthographe volontairement reproduite `"delivred"` (`SocketEvent.swift:58-61`, commentaire explicite justifiant de ne pas "corriger" l'orthographe pour ne pas casser le protocole serveur).
- **Authentification au handshake** via `socket.connect(withPayload: ["token": apiKey], ...)` (`TiinverSocket.swift:82-91`), documentée comme équivalent réel de `IO.Options.auth` d'Android après une correction explicite du 2026-08-19 (remplacement de `.connectParams`, qui n'atteignait pas `handshake.auth`).
- **Configuration de reconnexion identique** : tentatives infinies, backoff 1s→30s, `randomizationFactor 0.5`, `forceWebsockets(true)`.
- **Câblage confirmé dans le cycle de vie de l'app** : `ChatRepository.shared.attachToCurrentSocket()` appelé après connexion/reprise de session (`RootRouterView.swift:59`) et sur regain de connectivité réseau (`RootRouterView.swift:177-181`, via `NetworkMonitor.start(onRegainedConnectivity:)`) — vérifié directement dans cette passe, ce point était marqué incertain par le rapport de recherche initial et est désormais confirmé câblé.
- **Routage vers la bonne conversation** confirmé correct pour le chat 1:1 : `ChatViewModel.handle(_:)` (`ChatViewModel.swift:324`) filtre par `meta.from == target.to` (comparaison de username, indépendante du bug `conversationId` de §8 — donc le bug conversationId **ne casse pas** le routage temps réel du chat ouvert).

**Deux failles réelles et distinctes confirmées malgré cette implémentation par ailleurs fidèle :**

1. **CHAT-F-009a (CRITIQUE, confirmé)** — la **liste des conversations** (`RosterListView`) n'est **explicitement pas** mise à jour en temps réel. Aveu inline dans le code source lui-même (`RosterListView.swift:15-17`) :
   > "mise à jour temps réel de la liste (présence en ligne/frappe/nouveau message reçu pendant que l'écran est ouvert — `Roster.organizeAndDisplayMessage`, **non câblé**, `refresh()` manuel via le bouton toolbar en attendant)."

   C'est un gap fonctionnel réel, déjà connu de l'équipe (documenté comme dette technique intentionnelle), qui explique précisément un symptôme du type "je suis sur la liste des conversations et je ne vois pas arriver le nouveau message sans tirer/rafraîchir manuellement."

2. **CHAT-F-009b (NON DÉTERMINÉ — vérification runtime nécessaire)** — pour le cas où l'observation déclenchante concerne un écran de **conversation ouverte** (`ChatView`) et non la liste : le code montre que le mécanisme *devrait* fonctionner, mais le commentaire de tête de `TiinverSocket.swift` (L30-32) affirme explicitement : *"Reste à vérifier sur une connexion réelle que le serveur associe bien la session au bon utilisateur après ce changement (aucun test réel possible dans cette session)"*. Autrement dit, **le code source lui-même documente que l'authentification du handshake socket n'a jamais été validée contre un serveur réel**. Cette passe d'audit, étant elle-même statique, ne peut pas non plus confirmer ou infirmer si la connexion socket s'établit et s'authentifie réellement au runtime. **Vérification requise** : capturer les logs du client Socket.IO iOS (état `connected`/`disconnected`, erreurs de handshake) pendant un envoi croisé entre deux appareils réels, ou instrumenter côté serveur pour confirmer la réception effective du `token` dans `socket.handshake.auth.token`.

**Verdict global §22** : l'affirmation "absence du mécanisme temps réel iOS" **n'est pas confirmée par le code** — un mécanisme complet et soigneusement porté existe. Ce qui est confirmé, c'est (a) un gap réel et documenté sur l'écran liste, et (b) un point d'incertitude runtime explicitement reconnu par le code source concernant l'authentification socket, non vérifiable statiquement.

---

## 23. Socket / WebSocket — détails de configuration

| Paramètre | Android | iOS | Identique ? |
|---|---|---|---|
| URL | `infoContract.SERVERIO_URL = "https://api.tiinver.com:2020"` (`infoContract.java:160`) | `APIEnvironment.socketURL` (valeur exacte non re-vérifiée dans cette relecture ciblée — présumée alignée, à confirmer) | NON DÉTERMINÉ (valeur exacte iOS) |
| Namespace | par défaut (`/`) | par défaut (`/`) | Oui |
| Transport | `["websocket"]` uniquement, pas de polling | `forceWebsockets(true)` | Oui |
| Authentification | `IO.Options.auth = {"token": apiKey}` au handshake | `connect(withPayload: ["token": apiKey], ...)` au paquet CONNECT | Oui en intention ; non vérifié en pratique (§22) |
| Reconnexion | illimitée, 1s→30s, `randomizationFactor 0.5` | illimitée, 1s→30s, `randomizationFactor 0.5` | Oui |
| Timeout connexion | 10000 ms | 10 s | Oui |
| Rejoindre une salle | `"add user"`, `"offline status"`, `"joinRoom"` (par username) après connexion | `SocketEvent.addUser`, `.offlineStatus`, `.joinRoom` présents dans le registre d'événements ; câblage exact au `on connect` **non re-vérifié ligne à ligne** dans cette passe | NON DÉTERMINÉ (câblage exact du post-connect) |
| Heartbeat | non configuré explicitement (défauts bibliothèque) | non configuré explicitement (défauts bibliothèque) | NON DÉTERMINÉ (valeurs par défaut des deux bibliothèques, potentiellement différentes entre `socket.io-client-java` et `Socket.IO-Client-Swift`) |

---

## 24. FCM

| Aspect | Android | iOS | Conforme ? |
|---|---|---|---|
| Rôle temps réel | Aucun — confirmé (`// Ne RIEN parser ici`) | Aucun — confirmé (commentaire explicite : hors périmètre) | Oui, intention identique |
| Déclenche une sync REST de rattrapage | **Oui** — chaque push déclenche `TiinverSyncWorker` (`GET message/{myId}`, `GET group/message/{myId}`, `GET messagestatus/{myUsername}`) après 2s | **Non** — `AppDelegate.didReceiveRemoteNotification` (L114-128) n'appelle que `fetchNotifications` (notifications d'activité), jamais de resynchronisation chat | **Non conforme — HIGH** |
| Enregistrement token | `onNewToken()` sauvegarde **localement seulement** (TODO non résolu dans le code Android lui-même) ; enregistrement serveur réel via `requestNewFCMToken()`, site d'appel non confirmé | `PushTokenRegistrar.handleFCMToken` → `POST user {fcmId}` (`PushTokenRegistrar.swift:41-59`) | iOS semble plus complet ici, mais NON DÉTERMINÉ si Android appelle réellement `requestNewFCMToken()` quelque part |
| Ouverture de la conversation depuis une notification | **NON DÉTERMINÉ** (code de tap-intent non localisé dans cette passe côté Android) | **Confirmé cassé** — `AppDelegate.userNotificationCenter(_:didReceive:)` (L171-185) route toute catégorie autre que `"activity"`, y compris `"chat_message"`, vers `.home` — alors que `DeepLinkDestination.chat`/`.groupChat` existent mais ne sont pas utilisés par ce handler | Gap confirmé côté iOS, MEDIUM |

**CHAT-F-010 (HIGH)** : l'absence du filet de sécurité "FCM → sync REST" côté iOS est le constat le plus significatif de cette section. Même si le socket fonctionne correctement dans la majorité des cas, Android dispose d'une redondance structurelle (le socket ET un mécanisme de rattrapage FCM+REST périodique) qui protège contre toute déconnexion silencieuse ou perte d'événement. iOS ne dispose d'**aucun** filet équivalent — si le socket est déconnecté ou son authentification échoue silencieusement (cf. §22), rien ne rattrape les messages manqués tant que l'utilisateur ne rouvre pas manuellement l'écran concerné.

---

## 25. Persistance

| Aspect | Android | iOS |
|---|---|---|
| Moteur | SQLite pur via `SQLiteOpenHelper` + `ContentProvider` (`Dbase.java`, **pas** Room) | Core Data (`MessageEntity`, `RosterEntity`) |
| Clé de dédoublonnage | `messageId`, vérifié avant chaque insertion (`ChatManager.isMessageExist()`) | `messageId`, vérifié avant chaque insertion (`MessageRepository.messageExists(messageId:)`), **plus** une protection contre les races de livraisons concurrentes via un acteur `SerialTaskQueue` dédié (`MessageRepository.swift:493-511`) — protection supplémentaire non présente de façon aussi explicite côté Android |
| Ordre | tri par `stamp` (client), `_id` autoincrement en tiebreak | tri par `stamp`, pagination (`MessageRepository.page`) |
| Dédoublonnage UI additionnel | `MessageDiffCallback.areItemsTheSame()` par `messageId` | dédoublonnage en mémoire par `messageId` dans `ChatViewModel.onIncoming()` avant append |

**Verdict : CONFORME, voire plus robuste côté iOS** sur la protection anti-race de dédoublonnage concurrent — aucun bug trouvé.

---

## 26. Reconnexion

**Android** : reconnexion gérée à deux niveaux redondants — configuration native de la bibliothèque (`reconnection=true`) ET logique applicative manuelle (`App.attachSocketLifecycleListeners()`, `ChatRepository.attemptReconnect()` avec retry différé de 3s sur déconnexion serveur explicite).

**iOS** : reconnexion native de la bibliothèque (même configuration), plus détection réelle de perte/reprise réseau via `NetworkMonitor` (`NWPathMonitor`) qui déclenche `ChatRepository.attachToCurrentSocket()` sur regain de connectivité — câblage confirmé dans cette passe (`RootRouterView.swift:177-181`).

**Rattrapage des messages manqués pendant une absence** : Android dispose du filet FCM+`TiinverSyncWorker` (§24) en plus du socket. iOS n'a **aucun** équivalent — au retour au premier plan ou à la reconnexion réseau, iOS ne fait que relancer le socket et retenter les téléversements/téléchargements en attente (`ChatRepository.resumePendingUploads`/`resumePendingDownloads`), mais **aucun appel REST de type "donne-moi les messages manqués depuis le timestamp X" n'a été trouvé** sur aucune des deux plateformes pour le contenu des messages eux-mêmes — le rattrapage de contenu dépend entièrement de la re-livraison côté serveur via le socket (comportement serveur, hors dépôt, **NON DÉTERMINÉ**).

---

## 27. Authentification

| Aspect | Android | iOS |
|---|---|---|
| REST | Header `Authorization: <apiKey>` brut, sans préfixe `Bearer` (`TransportData.java`) | Header `Authorization: <apiKey>` brut, sans préfixe `Bearer` (`APIClient.swift:42-51`) |
| Socket | `apiKey` dans `IO.Options.auth` au handshake | `apiKey` dans le payload `connect(withPayload:)` au paquet CONNECT |
| Source de l'apiKey | `SessionManager.getUser(context).getApikey()` | `UserSession` (Keychain) |
| Renouvellement après re-login | `App.resetSocket()` doit être appelé explicitement | `TiinverSocket.reset(apiKey:)` doit être appelé explicitement, câblé via `attachToCurrentSocket()` |

**Verdict : CONFORME.** Même schéma d'authentification des deux côtés (header brut sans schéma, token socket au handshake). Aucun écart trouvé qui expliquerait, à lui seul, une absence de livraison temps réel — sous réserve du point non déterminé de §22 sur la validation runtime réelle du handshake.

---

## 28. Analyse du parsing JSON

**Risque connu de ce projet** (booléens/entiers envoyés comme chaînes par le backend, ex. `"isQuoted":"false"`) : **iOS s'en protège explicitement**. `MessageLib.init(from:)` (`MessageLib.swift:124-177`) utilise un décodeur `Codable` **personnalisé**, pas la synthèse automatique :
- `status`, `versionCode`, `isFileUploaded`, `isFileDownloaded`, `lucrative`, `price` → `decodeLenientIntIfPresent`
- `isQuoted`, `belongsToCurrentUser` → `decodeLenientBoolIfPresent` (gère `"false"`/`"true"` en chaîne **et** les booléens JSON natifs)
- `userId` → `decodeLenientStringIfPresent`

Le même schéma est appliqué à `User.init(from:)` (`User.swift:90-146`). C'est un pattern déjà généralisé dans ce dépôt (`LenientDecoding.swift`, référencé mais non relu intégralement dans cette passe) suite à des bugs similaires déjà rencontrés et corrigés ailleurs dans l'app (Feed/Profil/Contacts).

`ChatRepository.decodeMessages` (`Realtime/ChatRepository.swift:727-746`) décode le tableau entrant **élément par élément** (pas en bloc), pour éviter qu'un seul message malformé ne fasse échouer le décodage de tout le lot — documenté comme un bug déjà rencontré et corrigé (`V3-F-090`).

**Verdict : iOS est structurellement mieux protégé qu'une simple synthèse `Codable` naïve ne le serait**, et gère explicitement la classe de bug redoutée par cette tâche. Aucune action corrective nécessaire ici — à l'inverse, ce point est une force du portage.

---

## 29. Comportement UI

| Aspect | Android (référence) | iOS |
|---|---|---|
| Alignement bulle | selon expéditeur | `MessageBubbleAlignment.forMessage(belongsToCurrentUser)` (`ChatBubbleViews.swift:16-19`) — conforme |
| Ordre / auto-scroll | RecyclerView, scroll auto sur nouvel item | `ScrollViewReader` + `.onChange(of: items.last?.id)`, explicitement **pas** déclenché sur pagination (prepend), documenté comme port fidèle (`ChatView.swift:157-192`) |
| Icônes de statut | drawables `ic_acuser_inchat_0..3` | `DeliveryStatusIcon` (`ChatBubbleViews.swift:117-131`) — mêmes 4 états |
| Titre conversation | nom/nikname du pair | `.navigationTitle` utilise le `target.nikname` **local** (correctement peuplé aux points d'entrée nouvelle conversation, contrairement au champ fil vide de §10) — donc le titre d'écran n'est **pas** affecté par le bug nikname du §10 |
| Quote/reply UI | swipe-to-reply | swipe-to-reply, symétrique (§18) |
| Erreurs / retry média | **NON DÉTERMINÉ** (non tracé en détail côté Android dans cette passe) | overlay triangle d'exclamation sur échec (`ChatBubbleViews.swift:231-233,274-276`), retry silencieux au prochain `handleAppear`, pas de compteur de tentatives |

---

## 30. Tableau de synthèse Android vs iOS

| Domaine | Android | iOS | Conforme ? | Sévérité |
|---|---|---|---|---|
| conversationId (conversation existante) | Toujours résolu avant ouverture écran | Correct | Oui | — |
| conversationId (nouvelle conversation) | N/A (toujours résolu) | **Jamais assigné** à 4 points d'entrée | **Non** | **CRITIQUE** |
| Roster créé pour nouvelle conversation | Toujours | **Jamais** (effet de cascade du bug ci-dessus) | **Non** | **CRITIQUE** |
| nikname transmis | Cache session, non vide en pratique | Cache session, vide pour ce compte | NON DÉTERMINÉ | MEDIUM |
| sender/receiver/from/to | Sémantique documentée | Identique | Oui | — |
| resource | Build.MODEL (ou "null" cas exceptionnel) | "iOS" (délibéré, documenté) | Oui (délibéré) | — |
| versionCode | BuildConfig réel (378) | Hack temporaire partagé avec Remote Config (1000) | Non, mais déjà connu/tracé | MEDIUM |
| messageId | myId+epochMs | Identique | Oui | — |
| stamp | epochMs client | Identique | Oui | — |
| deliverTime/deliver_time (unité) | NON DÉTERMINÉ | Secondes | NON DÉTERMINÉ | LOW (à vérifier) |
| status | 0→1→2→3(/4) | Identique | Oui | — |
| giftId sur le fil | Toujours présent (même si "null") | **Jamais présent** | **Non** | MEDIUM |
| object: sticker/gif composition | Supporté | **Non composable** (placeholder) | Non | MEDIUM |
| object: doc | Supporté (rendu non confirmé) | **Pas de rendu dédié** | Non confirmé | MEDIUM |
| object: subscribe/renew/footer/header | Supporté (via bug de fallback) | **Non confirmé** | NON DÉTERMINÉ | MEDIUM (à vérifier) |
| quote/reply | Implémenté | Implémenté, symétrique | Oui | — |
| Mécanisme temps réel (existence) | Socket.IO | Socket.IO, événements identiques | Oui (en code) | — |
| Temps réel — écran liste conversations | NON DÉTERMINÉ (présumé réactif via ContentProvider) | **Explicitement non câblé** | Non | **CRITIQUE** |
| Temps réel — écran conversation ouverte | Fonctionne (référence) | Câblé correctement en code ; auth handshake non vérifiée en runtime | NON DÉTERMINÉ | **CRITIQUE (à vérifier)** |
| FCM comme filet de rattrapage | Oui (sync REST 2s après push) | **Absent** | Non | **HIGH** |
| Tap notification → bonne conversation | NON DÉTERMINÉ | **Confirmé cassé** (route toujours vers `.home`) | Non | MEDIUM |
| Persistance / dédoublonnage | SQLite, dédoublonné par messageId | Core Data, dédoublonné + protection anti-race supplémentaire | Oui (iOS plus robuste) | — |
| Authentification REST/Socket | Header brut + auth handshake | Identique | Oui | — |
| Parsing JSON tolérant | N/A (Java, typage différent) | Décodage personnalisé tolérant, déjà généralisé | Oui (force iOS) | — |
| Upload média | REST propre backend | BunnyCDN direct | Non | MEDIUM (à confirmer avec produit/backend) |

---

## 31. Causes racines

1. **CHAT-F-001 (conversationId vide)** — omission de code : les constructeurs de `RosterModel` pour une nouvelle conversation (`NewMessageView`, `ProfileView`, `ContactPickerView`, `GroupDetailView`) n'invoquent jamais `ConversationIdGenerator`, alors que l'algorithme existe et est correct. Cause directe : absence d'un point de passage obligé (contrairement à Android où `ChatFragmentTest.init()` calcule systématiquement la valeur avant que l'écran de chat ne puisse exister).
2. **CHAT-F-002 (nikname vide)** — mécanisme de transmission fidèle à Android ; cause profonde probablement en amont (donnée de session/backend), NON DÉTERMINÉ sans accès à la réponse de connexion réelle.
3. **CHAT-F-009a (liste non temps réel)** — décision de portée explicitement documentée dans le code (`RosterListView.swift:15-17`), pas un oubli caché — mais reste un vrai gap fonctionnel vis-à-vis d'Android.
4. **CHAT-F-009b (auth handshake non vérifiée)** — le correctif du 2026-08-19 (remplacement de `.connectParams` par `withPayload`) est correct en théorie d'après la documentation de la bibliothèque citée dans le commentaire, mais n'a jamais été validé contre un serveur réel — risque résiduel documenté par les auteurs du code eux-mêmes.
5. **CHAT-F-010 (absence de filet FCM)** — décision de portée délibérée lors d'un module antérieur ("le reste de `TiinverSyncWorker`... n'est PAS porté ici"), jamais rattrapée depuis.
6. **CHAT-F-012 (giftId absent du fil)** — `commonFields()` du `MessagePacket` iOS n'a simplement jamais inclus cette clé ; à rapprocher du fait que le flux fonctionnel du cadeau passe par un appel REST séparé, ce qui a pu masquer l'absence de la clé sur le canal socket.
7. **CHAT-F-015 (versionCode="1000")** — collision non anticipée entre deux fonctionnalités partageant la même clé `Info.plist`, déjà documentée comme dette temporaire dans `project.yml`.

---

## 32. Classification de sévérité

**CRITIQUE (5)**
- CHAT-F-001 — `conversationId` vide pour toute nouvelle conversation créée depuis recherche/profil/contact/groupe.
- CHAT-F-001b — effet de cascade : ligne roster jamais créée pour une nouvelle conversation tant qu'aucune réponse n'est reçue.
- CHAT-F-009a — liste des conversations non mise à jour en temps réel (aveu de code).
- CHAT-F-009b — authentification du handshake socket non vérifiée contre un serveur réel (risque documenté par le code lui-même, impact potentiellement bloquant pour tout le temps réel si le handshake échoue silencieusement).
- CHAT-F-010b (recoupement avec HIGH ci-dessous, compté ici car sans filet de rattrapage, une panne silencieuse du socket = perte de messages sans aucune récupération automatique) — voir note.

**HIGH (4)**
- CHAT-F-010 — absence du filet de sécurité FCM→sync REST côté iOS.
- CHAT-F-002 — nikname vide (fonctionnalité visible, cause encore incertaine).
- CHAT-F-011 — tap sur notification chat n'ouvre jamais la bonne conversation.
- Écart pipeline média (REST Android vs BunnyCDN iOS) — HIGH car touche potentiellement la fiabilité de l'envoi de médias, à confirmer avec le produit/backend avant correction.

**MEDIUM (6)**
- CHAT-F-012 — `giftId` absent du fil JSON côté iOS.
- CHAT-F-015 — `versionCode="1000"` (déjà connu, déjà tracé).
- Gap `sticker`/`gif` non composables.
- Gap `doc` sans rendu dédié.
- Types `subscribe/renewSubscription/footer/header` non confirmés côté iOS.
- Recherche de conversation : appel réseau non confirmé (`ChatSearchView`).

**LOW (3)**
- `resource="iOS"` (délibéré, sans impact fonctionnel confirmé).
- Différence d'unité `deliverTime` (secondes) vs `stamp` (millisecondes) — impact non confirmé.
- Anomalie Android préexistante (nikname de l'écho local sourcé depuis le pair) — non actionnable côté iOS, mentionnée pour information seulement.

---

## 33. Corrections proposées (PROPOSITION UNIQUEMENT — rien n'a été appliqué)

> Rappel : ceci est un audit en lecture seule. Aucune de ces propositions n'a été implémentée. Elles nécessitent validation produit/backend avant tout développement.

1. **CHAT-F-001** : à l'un des 4 points d'entrée de nouvelle conversation (`NewMessageView.swift:29-48`, `ProfileView.swift:319-334`, `ContactPickerView.swift:129-136`, `GroupDetailView.swift:370-381`), appeler `ConversationIdGenerator.conversationId(currentUser: myId, remoteUser: target.userId)` et l'assigner à `target.conversationId` avant tout envoi — reproduit exactement le comportement Android où l'ID est résolu avant l'ouverture de l'écran de chat.
2. **CHAT-F-002** : vérifier d'abord côté backend/runtime (voir §10) avant toute correction de code — si le backend renvoie bien le nikname, investiguer `UserSession.save()`/`AuthSessionPersistence`.
3. **CHAT-F-009a** : câbler `RosterListView` sur `chatRepository.chatEvents` (le même bus Combine déjà utilisé par `ChatViewModel`) pour mettre à jour la ligne concernée sans nécessiter de tir manuel du bouton "refresh" — décision de portée à valider avec le produit car explicitement documentée comme différée, pas oubliée.
4. **CHAT-F-009b** : valider en priorité par un test runtime réel avant toute autre correction du temps réel — c'est un prérequis pour distinguer un vrai bug de code d'un problème serveur.
5. **CHAT-F-010** : évaluer si un filet de sécurité équivalent (sync REST déclenchée sur réception d'un push FCM) doit être porté depuis `TiinverSyncWorker`, ou si l'équipe accepte le risque en s'appuyant uniquement sur le socket avec sa reconnexion automatique.
6. **CHAT-F-011** : inclure `conversationId`/cible dans le `userInfo` de la notification locale (`LocalNotificationBuilder`) et router `"chat_message"` vers `DeepLinkDestination.chat`/`.groupChat` dans `AppDelegate.userNotificationCenter`.
7. **CHAT-F-012** : ajouter la clé `"giftId"` (valeur ou chaîne `"null"` par fidélité stricte au protocole Android) dans `MessagePacket.commonFields()`, sous réserve de confirmation backend que cette clé est réellement consommée.
8. **CHAT-F-015** : dissocier `CFBundleVersion` (gating Remote Config) du champ `versionCode` du protocole chat — introduire une constante dédiée reflétant un vrai numéro de version avant soumission App Store, comme déjà noté dans `project.yml`.
9. Gaps de types d'objet (`sticker`/`gif` composables, `doc`, `subscribe`/etc.) : à prioriser selon l'usage réel mesuré côté produit, après confirmation de leur présence/absence exacte côté Android pour les types marqués NON DÉTERMINÉ.

---

## 34. Tests requis — matrice de 22 scénarios

| # | Scénario | Attendu Android | Réel iOS (statique) | Écart | Cause | Correction |
|---|---|---|---|---|---|---|
| 1 | A→B texte, conversation existante | Livraison instantanée | Devrait fonctionner (routage correct §22) | NON DÉTERMINÉ sans test runtime | Auth handshake non vérifiée | Test runtime prioritaire |
| 2 | B→A texte, conversation existante | Idem | Idem | Idem | Idem | Idem |
| 3 | Messages rapides multiples | Ordonnés par stamp | Idem, dédoublonnage supplémentaire (SerialTaskQueue) | Non attendu | — | — |
| 4 | Nouvelle conversation (recherche tél/email) | conversationId résolu, roster créé | **conversationId vide, roster non créé** | **Oui, confirmé** | CHAT-F-001 | §33.1 |
| 5 | Conversation existante depuis liste | conversationId correct | Correct | Non | — | — |
| 6 | Message cité (quote) | Fonctionne | Fonctionne (code symétrique) | Non attendu | — | — |
| 7 | Réponse à un message cité | Fonctionne | Fonctionne | Non attendu | — | — |
| 8 | Image | Fonctionne | Fonctionne | Non attendu | — | — |
| 9 | Vidéo | Fonctionne | Fonctionne | Non attendu | — | — |
| 10 | Audio | Fonctionne | Fonctionne (forme d'onde simulée sur les deux plateformes) | Non attendu | — | — |
| 11 | Cadeau (gift) | `giftId` sur le fil + REST | `giftId` **absent** du fil, REST présent | Oui | CHAT-F-012 | §33.7 |
| 12 | Sticker/GIF | Composable | **Non composable** (placeholder) | Oui | Gap §17 | §33.9 |
| 13 | Type objet non répertorié (doc/location) | NON DÉTERMINÉ côté Android | Non rendu/non composable | NON DÉTERMINÉ | — | À investiguer d'abord côté Android |
| 14 | Message reçu, app ouverte, écran conversation ouvert | Instantané | Devrait être instantané (code correct) | NON DÉTERMINÉ | CHAT-F-009b | Test runtime |
| 15 | Message reçu, app ouverte, écran liste conversations | Instantané (présumé) | **Non instantané, confirmé** | Oui | CHAT-F-009a | §33.3 |
| 16 | Message reçu, app en arrière-plan | Notification + sync via FCM | Notification locale seulement, pas de sync garantie | Potentiellement | CHAT-F-010 | §33.5 |
| 17 | Perte réseau | Reconnexion auto + retry | Reconnexion auto + retry (`NetworkMonitor`) | Non attendu | — | — |
| 18 | Reconnexion après perte réseau | Reprise silencieuse | Reprise silencieuse, câblage confirmé | Non attendu | — | — |
| 19 | Message dupliqué (double livraison) | Dédoublonné par messageId | Dédoublonné, protection anti-race supplémentaire | Non attendu | — | — |
| 20 | messageId erroné/collision | Non géré explicitement (risque partagé) | Idem | Non attendu (risque partagé, pas une régression) | — | — |
| 21 | conversationId erroné/absent | N/A (toujours résolu) | **Confirmé absent pour nouvelle conversation** | Oui | CHAT-F-001 | §33.1 |
| 22 | Statuts sent/delivered/read | 0→1→2→3 | 0→1→2→3, identique | Non attendu | — | — |

Les scénarios 1, 2, 14 et 16 nécessitent un **test sur appareils réels** (deux comptes, deux appareils, app ouverte simultanément) — ils ne peuvent pas être tranchés par la seule lecture de code, conformément à la consigne de ne jamais deviner un comportement runtime.

---

## 35. Fichiers à modifier (si les corrections proposées en §33 sont validées)

- `Sources/TiinverSwift/Messagerie/NewMessageView.swift` — assigner `conversationId` (CHAT-F-001)
- `Sources/TiinverSwift/Messagerie/ProfileView.swift` — assigner `conversationId` (CHAT-F-001)
- `Sources/TiinverSwift/Messagerie/ContactPickerView.swift` — assigner `conversationId` (CHAT-F-001)
- `Sources/TiinverSwift/Messagerie/GroupDetailView.swift` — assigner `conversationId` (CHAT-F-001)
- `Sources/TiinverSwift/Messagerie/RosterListView.swift` — câblage temps réel (CHAT-F-009a)
- `Sources/TiinverSwift/Messagerie/RosterListViewModel.swift` (si distinct — à confirmer) — même sujet
- `Sources/TiinverSwift/App/AppDelegate.swift` — routage tap-notification vers la conversation (CHAT-F-011)
- `Sources/TiinverSwift/Notifications/LocalNotificationBuilder.swift` — inclusion `conversationId` dans `userInfo` (CHAT-F-011)
- `Sources/TiinverSwift/Models/MessagePacket.swift` — ajout `giftId` dans `commonFields()` (CHAT-F-012, sous réserve de confirmation backend)
- `project.yml` / configuration de build — dissociation `versionCode` chat vs `CFBundleVersion` Remote Config (CHAT-F-015, sous réserve de décision produit)
- Fichier de configuration socket (`APIEnvironment` ou équivalent) — aucune modification anticipée tant que CHAT-F-009b n'est pas tranché par un test runtime

**Aucune de ces modifications n'a été appliquée dans le cadre de cet audit.**
