# MIGRATION_PARITY_PROGRESS_V3.md — Journal de progression, V3

Compagnon de `MIGRATION_PARITY_AUDIT_V3.md`. Journalise l'avancement de PHASE B (correction par
lots) au fur et à mesure — PAS pendant PHASE A (audit), qui ne modifie aucun code.

---

## 2026-08-19 — PHASE A terminée, PHASE B pas encore commencée

`MIGRATION_PARITY_AUDIT_V3.md` créé. Méthode : 9 agents de recherche en parallèle (Search+nav,
Chat/Socket/WebRTC, Feed/Grid/Media, Bunny/Upload/Publish, Galerie/Éditeur photo-vidéo,
Auth/Profil/Groupes, Notifications/DeepLinks/Paiements/Boost, Views/code-orphelin/silent-bugs,
cartographie Android exhaustive) + 2 vérifications personnelles décisives sur des points à fort
enjeu contradictoires ou extrêmes (voir §3 de l'audit : priorité d'URL média Feed, connexion
Socket.IO jamais établie). 98 constats numérotés (V3-F-001 à V3-F-098), dont 8 P0 confirmés
figurant dans la liste finale priorisée (§29 de l'audit).

Aucune correction de code effectuée dans cette passe — audit uniquement, conformément à la
consigne explicite de l'utilisateur.

**Feu vert reçu — PHASE B démarrée à partir du commit `52ce4ae`.**

---

## 2026-08-19 — Lot 1 : P0-1 (Socket Chat ne se connecte jamais) + P0-4 (Logout ne réinitialise pas le routing)

**Finding ID** : V3-F-016 / V3-F-023 / V3-F-090 (P0-1), V3-F-051 (P0-4)

**Commit** : `57fd300`

**Fichiers modifiés** : `Realtime/TiinverSocket.swift`, `Realtime/ChatRepository.swift`,
`Navigation/RootRouterView.swift`, `Security/UserSession.swift`, `Settings/SettingSubViews.swift`

**Nature du correctif** :
- P0-1 — Confirmé par 2 greps indépendants qu'aucun appel à `TiinverSocket.connect(apiKey:)`
  n'existait nulle part dans le projet (seule la déclaration de la méthode). Réécrit
  `TiinverSocket` avec un cycle de vie fidèle à `App.java`
  (`getSocket()`/`connectSocket()`/`resetSocket()`/`disconnectSocket()`, lu ligne par ligne) :
  `ensureSocket`/`connect`/`reset`/`disconnect`, `reset` appelé après authentification réussie
  (port de `HomeActivity.onNetworkChange` → `resetSocket()`+`connectSocket()`). `ChatRepository`
  appelle maintenant réellement `attachToCurrentSocket()`. `decodeMessages` passé d'un décodage de
  tableau entier (`try?`, tout ou rien) à un `compactMap` élément par élément avec logs
  diagnostiques, même schéma que `FeedRepository`/`ProfileRepository`.
- P0-4 — Ajout de `Notification.Name.userDidLogout`, posté depuis `logout()`/`deleteAccount()`
  dans `SettingAccountView`, écouté par `RootRouterView` pour remettre `authenticatedUser = nil`
  (aucun état `UserSession`/ViewModel résiduel ne garde l'utilisateur connecté après un logout
  sans force-quit) — comparé directement à `transportDataBackground.java:176-180`
  (`Intent(SplashActivity)` avec `FLAG_ACTIVITY_NEW_TASK|FLAG_ACTIVITY_CLEAR_TASK`).

**Build/CI** : run GitHub Actions déclenché sur `57fd300` — **succès** (vérifié avant de passer au
lot suivant).

**Statut post-build** : BUILD_VALIDATED.

**Test réel requis** : oui — connexion socket après login, relance app, background/foreground,
logout SANS force-quit (vérifier qu'aucun écran authentifié ne reste accessible).

**Résultat du test réel** : non effectué (hors périmètre de ce lot — pas de test Appetize déclenché
pendant ce travail par lots, conformément à la consigne permanente de l'utilisateur).

**Statut final** : BUILD_VALIDATED pour les deux findings (P0-1 et P0-4). PAS
COMPLETE_PARITY_VALIDATED tant qu'un test réel n'a pas confirmé le comportement.

---

## 2026-08-19 — Lot 2 : P0-2 (Priorité d'URL média Feed/Search incorrecte)

**Finding ID** : V3-F-009

**Commit** : `afc44bf`

**Fichiers modifiés** : `Feed/FeedActivity.swift`, `Discover/SearchModels.swift`

**Nature du correctif** : Contradiction personnellement vérifiée contre `MediaObject.java:352-357`
(ancienne implémentation simple commentée juste au-dessus de la vraie méthode `getObject_url()` —
preuve d'un changement de comportement délibéré côté Android) et les deux call sites réels
(`VideoPlaybackCoordinator.tryPlayAt`, `BubbleStatusPhoto.setMediaObject`) : la priorité réelle est
`cdn_content_url` si `cdn_content_id` est valide (non `null`/`"NULL"`/vide), sinon repli sur
`object_url` — un correctif antérieur iOS avait confondu le NOM de la méthode Java
(`getObject_url()`) avec le champ JSON `object_url` lui-même. Ajout de
`FeedActivity.effectiveObjectURLString`/`playbackURL`, correction de la branche photo de
`thumbnailURL` (branche vidéo déjà correcte, `cdn_thumbnail_url`) ; correction identique de
`SearchPostResult.thumbnailURL`. `fallbackPlaybackURL` et `asFeedActivity` confirmés déjà corrects,
non modifiés.

**Build/CI** : run GitHub Actions sur `afc44bf` — **succès**.

**Statut post-build** : BUILD_VALIDATED.

**Test réel requis** : oui — vérifier affichage photo/vidéo en Grid ET en plein écran pour du
contenu avec `cdn_content_id` valide ET invalide.

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED.

---

## 2026-08-19 — Lot 3 : P0-3 (Export Animems → publication réelle Tiinver)

**Finding ID** : V3-F-022

**Commit** : `5164acf`

**Fichiers modifiés** : `Animems/AnimemesEditorView.swift`

**Nature du correctif** : Le `ShareLink` système seul (mécanisme précédent) n'est PAS une parité
avec le flux Android (`AnimemsCompound.java`/`MemesFragment.java` → export → compose/publication
Tiinver réelle via le pipeline Bunny). Ajout d'une option "Publier sur Tiinver" à côté du
`ShareLink` existant (conservé) : conversion asynchrone du fichier exporté (`Self.publishMedia
(from:)`, photo vs vidéo par extension) vers `PublishMedia`, puis présentation de
`PublishComposeView` (réutilisé tel quel — même écran, même pipeline Bunny que la publication
Galerie normale) via `.fullScreenCover(item:)`.

**Build/CI** : run GitHub Actions sur `5164acf` — **succès**.

**Statut post-build** : BUILD_VALIDATED.

**Test réel requis** : oui — créer un Animems, exporter, choisir "Publier sur Tiinver", confirmer
apparition dans le Feed avec le média correctement uploadé sur Bunny.

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED.

---

## 2026-08-19 — Lot 4 : P0-5 (Notifications chat en arrière-plan)

**Finding ID** : V3-F-075

**Commit** : `6f5f0ca`

**Fichiers modifiés** : `Realtime/ChatRepository.swift`

**Nature du correctif** : Comparé à `ChatManager.java` (`NewPrivateMessage`/`NewGroupMessage` →
`meta.setTitle(meta.getNikname())` puis `fcms.notificationShow(context, meta)`, appelé
inconditionnellement — `NotificationUtils.show()` calcule `isActivityChatContext`/
`isMainActivityContext` mais ne les lit JAMAIS, confirmé aux lignes 342-381). Ajout de
`ChatRepository.notifyIfNeeded(_:)`, appelé après `chatEvents.send(.message(meta))` dans les DEUX
branches (`!isGroup` et groupe) de `handleNewMessage`, construisant et affichant une notification
locale via `LocalNotificationBuilder`. Délibérément PAS appelé pour `meta.object == "voicecall"`
(géré séparément par `CallCoordinator`/CallKit).

**Build/CI** : run GitHub Actions sur `6f5f0ca` — **succès**.

**Statut post-build** : BUILD_VALIDATED.

**Test réel requis** : oui — recevoir un message en arrière-plan/app fermée, vérifier
l'affichage de la notification système avec titre/contenu corrects.

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED.

---

## 2026-08-19 — Lot 5 : P0-6 (Recadrage/rotation/miroir vidéo n'affectait pas réellement l'export)

**Finding ID** : V3-F-032 (GALERIE-01)

**Commit** : `f519361`

**Fichiers modifiés** : `Feed/MediaTrimView.swift`, `Media/VideoTrimState.swift`

**Nature du correctif** : Contradiction résolue avant tout correctif — le commentaire de tête de
`VideoTrimState.swift` affirmait le pipeline Android `VideoTransformer` "confirmé MORT/non branché
prod" ; relecture fraîche de `VideoTrimmerView.java` a confirmé un `import
com.animems.engine.Utils.media.VideoTransformer` réel et un appel réel
`VideoTransformer.process(params, callback)` dans `startTrimWithCrop()` (ligne 700, méthode
activement appelée par l'écran de trim monté en production), avec `startTrimWithCrop2()`
(lignes 807-854) comme repli rapide SANS transformation en parallèle — architecture à deux chemins,
pas du code mort. Commentaire corrigé. Côté iOS : montage des contrôles pivot/flip/ratio (état déjà
écrit dans `VideoTrimState.swift` mais jamais branché à aucune vue) ; `trim()` bascule maintenant
réellement entre le chemin rapide (`AVAssetExportPresetPassthrough`, aucune transformation active)
et un chemin de ré-encodage complet (`AVMutableComposition` + `AVMutableVideoComposition`/
`AVMutableVideoCompositionLayerInstruction`, `AVAssetExportPresetHighestQuality`) qui compose
`track.preferredTransform` (orientation caméra native) + rotation utilisateur (pivot centré,
recentrage pour 90°/270°) + miroir horizontal (pivot centré) + recadrage centré vers le ratio choisi
(via `renderSize`) — les boutons ne se contentent plus de changer un état affiché, la transformation
géométrique choisie affecte réellement le fichier exporté.

**Build/CI** : run GitHub Actions 32287826052 sur `f519361` — **succès** (vérifié).

**Statut post-build** : BUILD_VALIDATED.

**Test réel requis** : oui, impérativement — la composition de matrices (`composeTransform`) n'a
JAMAIS été exécutée sur device/simulateur dans cette session (aucun test Appetize déclenché,
conformément à la consigne permanente). Vérifier concrètement : rotation 90°/180°/270°, miroir,
chaque ratio préréglage (16:9/9:16/1:1/4:3), et la combinaison rotation+ratio, sur au moins une
vidéo tournée en portrait ET une en paysage (pour couvrir `preferredTransform` non-identité).

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED. PAS COMPLETE_PARITY_VALIDATED — le risque d'erreur dans la
composition de `CGAffineTransform` (ordre de concaténation, signe de rotation, recentrage
post-rotation 90/270°) est réel et ne peut être exclu sans un test visuel effectif du fichier
exporté.

---

## 2026-08-19 — Lot 6 : P0-7 (Achat StoreKit non persisté côté serveur — risque financier)

**Finding ID** : V3-F-084 (PAY-03)

**Commit** : `9c5dd02`

**Fichiers modifiés** : `Wallet/CoinStoreManager.swift`

**Nature du correctif** : Investigation d'abord, conformément à la consigne stricte de ne jamais
simuler une validation serveur inexistante :
- `WalletRepository.submitPurchasseRequest`/`submitPurchasseByCrypto` (Android) attendent un
  payload mobile money/crypto (numéro de transaction saisi à la main), incompatible avec une
  preuve d'achat StoreKit (`transactionId`/`originalTransactionId` Apple) — réutiliser ces
  endpoints aurait été un mensonge fonctionnel, écarté.
- Confirmé qu'AUCUN endpoint backend n'accepte actuellement une preuve d'achat StoreKit ;
  `storekit/verify-purchase`, déjà appelé côté client, retourne 404 (`APIClient`
  `.validate(statusCode: 200..<300)` lève, avalé auparavant par un `try?`).
- Tracé le mécanisme de perte complet : `transaction.finish()` était appelé inconditionnellement
  après l'échec silencieux du rapport serveur — reçu Apple consommé, aucune nouvelle tentative
  possible. La prochaine relecture du profil personnel (`ProfileViewModel.swift:99-100`) écrase
  ensuite `UserSession.shared.coinsAmount` avec la valeur serveur (jamais incrémentée), effaçant
  silencieusement et définitivement le crédit local — argent réel dépensé, crédit perdu, aucune
  trace.

Correctif appliqué : **cycle de vie StoreKit local uniquement, AUCUN nouveau chemin réseau créé**.
`creditAndReport` retourne maintenant si le serveur a réellement confirmé (`isBackendSuccess`) ;
`transaction.finish()` n'est appelé QUE dans ce cas. Sinon la transaction est laissée
délibérément non terminée — StoreKit la redélivre automatiquement au prochain lancement via
`Transaction.updates`, donnant un vrai point de nouvelle tentative une fois l'endpoint serveur
créé, au lieu d'une perte silencieuse et irréversible. `lastError` informe désormais l'utilisateur
quand l'achat a réussi côté Apple mais n'est pas confirmé côté serveur.

**Travail backend requis, documenté dans le code (`CoinStoreManager.swift`, commentaire de
`creditAndReport`), PAS implémenté ici** : créer `storekit/verify-purchase` côté serveur —
recevoir `userId`/`productId`/`transactionId`/`originalTransactionId`, vérifier auprès de l'App
Store Server API (`https://api.storekit.itunes.apple.com/inApps/v1/transactions/{transactionId}`,
+ fallback sandbox), ne créditer `coinsAmount` qu'après vérification réussie, et rendre l'opération
idempotente sur un `transactionId` déjà traité (pas de double crédit en cas de rejeu).

**Build/CI** : run GitHub Actions 32292309223 sur `9c5dd02` — **succès** (vérifié).

**Statut post-build** : BUILD_VALIDATED pour le correctif client lui-même (le cycle de vie StoreKit
est maintenant correct et compile).

**Test réel requis** : oui — mais insuffisant pour la parité complète tant que l'endpoint serveur
n'existe pas. Un test réel confirmerait seulement que l'achat sandbox se déroule, que l'erreur
s'affiche, et qu'aucun crash ne survient ; il NE PEUT PAS prouver un crédit serveur durable, qui
reste structurellement impossible sans le travail backend documenté ci-dessus.

**Résultat du test réel** : non effectué.

**Statut final** : **V3-F-084 reste FUNCTIONALLY_FAILED** au sens strict de la parité (l'argent
réel dépensé n'est toujours jamais durablement crédité côté serveur) — ce lot réduit le risque de
perte silencieuse et documente précisément le travail serveur manquant, mais NE DOIT PAS être
présenté comme une résolution complète. Aucune déclaration COMPLETE_PARITY_* n'est faite ici,
conformément à la consigne explicite de l'utilisateur pour ce P0 spécifiquement.

---

## 2026-08-19 — Lot 8 : P0-8 (Transport auth socket + bug frère WebRTC `makingOffer`)

**Finding ID** : V3-F-024 (CHAT-03) + V3-F-026 (WEBRTC-01) — regroupés dans le même lot car §7/§29
de l'audit notent explicitement que WEBRTC-01 dépend des correctifs socket pour être atteignable.

**Commit** : `136388b`

**Fichiers modifiés** : `Realtime/TiinverSocket.swift`, `Calls/WebRTCConnection.swift`

**Nature du correctif** :
- **V3-F-024** — L'incertitude "MEDIUM confidence" du finding original a été résolue avec preuve,
  pas devinée. Vérifié : `SocketInit.java:37` (Android) envoie un vrai `opts.auth = {"token":
  apiKey}` (`socket.io-client-java`), lu côté serveur via `socket.handshake.auth.token`
  (commentaire Java ligne 35). Vérifié via la documentation officielle générée de la bibliothèque
  Swift épinglée (`Socket.IO-Client-Swift` 16.1.1, dernière version publiée au 2026-08-19,
  confirmé via la liste des tags GitHub) : `SocketIOClientOption` n'a AUCUN cas `.auth` —
  `.connectParams` (utilisé jusqu'ici) envoie le jeton comme paramètre de requête Engine.IO
  (`handshake.query`), un canal DIFFÉRENT de `handshake.auth` que le serveur ne lit pas d'après le
  commentaire Android. Vérifié en revanche que `SocketIOClient.connect(withPayload:timeoutAfter:
  withHandler:)` existe bien et envoie son paramètre comme charge utile du paquet CONNECT
  Socket.IO v4 — le vrai équivalent de `IO.Options.auth`. `.connectParams` est retiré de la
  configuration ; le jeton est maintenant transmis via `withPayload`, envoyé frais à chaque
  `connect()`/`reset()` plutôt que figé dans la configuration mémoïsée du `SocketManager`.
- **V3-F-026** — En relisant `createOffer()`, le bug réel est l'inverse de l'intitulé du finding :
  la branche ÉCHEC (`guard...else`) remettait déjà `makingOffer=false` correctement ; c'est la
  branche SUCCÈS qui ne le faisait jamais, contrairement à `iceRestart()` juste au-dessus qui le
  fait explicitement après `sendMessage`. Conséquence réelle : après la première offre réussie de
  l'initiateur, `makingOffer` reste bloqué à `true` pour toute la durée de l'appel, ce qui fait
  traiter chaque offre entrante suivante comme une collision — cassant potentiellement toute
  renégociation ultérieure (changement caméra, reprise réseau) pour le pair initiateur. Corrigé
  pour suivre exactement le motif de `iceRestart()`.

**Build/CI** : run GitHub Actions 32294052929 sur `136388b` — **succès** (vérifié).

**Statut post-build** : BUILD_VALIDATED pour les deux findings.

**Test réel requis** : oui pour les deux — (1) connexion socket réelle avec un compte authentifié,
confirmer côté serveur/logs que l'utilisateur est bien identifié (pas seulement que le WebSocket
s'ouvre) ; (2) appel WebRTC avec au moins une renégociation après la première offre (ex. coupure
réseau puis reprise, changement de caméra) pour confirmer que `makingOffer` ne bloque plus les
offres suivantes.

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED pour V3-F-024 et V3-F-026. PAS COMPLETE_PARITY_VALIDATED —
aucun des deux correctifs n'a été observé fonctionner sur une connexion/appel réel dans cette
session.

---

<!--
Gabarit pour chaque entrée de PHASE B, à dupliquer :

## AAAA-MM-JJ — Lot N : <titre du lot>

**Finding ID** : V3-F-XXX

**Commit** : `<hash>`

**Fichiers modifiés** : <liste>

**Nature du correctif** : <résumé>

**Build/CI** : <run URL, statut>

**Statut post-build** : BUILD_VALIDATED / échec (préciser)

**Test réel requis** : <oui/non, quoi tester précisément>

**Résultat du test réel** : <à remplir seulement après un test réel effectif — ne jamais présumer>

**Statut final** : <statut mis à jour selon la taxonomie V3, ne JAMAIS utiliser
COMPLETE_PARITY_VALIDATED sans un résultat de test réel positif documenté ci-dessus>
-->

## 2026-08-19 — Phase B, P1 : début (méthode identique aux P0, poursuite automatique autorisée)

Les 8 P0 sont tous BUILD_VALIDATED ou (P0-7) mitigés avec dépendance backend documentée. Poursuite
automatique vers les items P1 de l'audit (§8), même méthode stricte, sans nouvel audit.

## 2026-08-19 — Lot P1-A : V3-F-069/070 (Groupes payants — catalogue de prix + abonnement inerte)

**Commit** : `e330e6c` — CI verte (run 32296613502).

**V3-F-070** — gap réel plus sévère que décrit : `ChatListItem.subscriptionRequired`/
`.subscriptionRenewal` n'étaient construits nulle part (confirmé par grep), la bannière ne
s'affichait JAMAIS. Chaîne Android complète retracée (`ChatFragmentTest.java` :
`!isGroupMember()` → bannière immédiate ; `checkSubcribtion()` → `GET
group/checksubscription/{userId}/{groupId}` ; `Subscribe.bind`/`RenewSubscription.bind` → `POST
group/subscribe`/`group/renewsubscription` ; `subscribeSuccefully()` → message système local).
Implémenté intégralement : `GroupRepository.checkSubscription/subscribeToGroup/
renewGroupSubscription`, `ChatListItem` étendu avec `groupId`/`creatorId`,
`ChatViewModel.checkGroupSubscription()` appelé sur CHAQUE `loadInitial()` de groupe (pas
seulement `lucrative`, fidèle à Android), `resolveGroupSubscription()` avec vérification de solde
AVANT l'appel réseau (`>` strict, comme Android), retrait de bannière + déblocage composeur +
message "a rejoint" UNIQUEMENT sur confirmation serveur réelle.

**V3-F-069** — contradiction résolue AVANT tout correctif : le finding original affirmait que les
vraies valeurs Android sont 250/500/1250/2500/5000. Tracé `Group.java` directement : ces 5 valeurs
ne sont que les LIBELLÉS du spinner (`prixList`) ; le prix RÉELLEMENT soumis vient de
`getPrice(position)`, qui pour un spinner à 5 éléments ne peut jamais renvoyer que 100/200/400/500
(bug réel Android de libellé/valeur, confirmé). iOS envoyait déjà ces 4 valeurs correctement ;
seuls 3 choix morts (700/800/1000, inatteignables sur Android) ont été retirés — PAS de
remplacement par 250/500/1250/2500/5000, qui aurait cassé la parité réelle des valeurs soumises.

**Test réel requis** : oui pour les deux — un groupe payant réel, un utilisateur non-membre et un
autre avec abonnement expiré, pour confirmer bannières + déblocage composeur + crédit correct.

**Statut final** : V3-F-070 → BUILD_VALIDATED. V3-F-069 → requalifié COMPLETE_PARITY_CANDIDATE
(la prémisse du finding original était fausse, la valeur réellement soumise était déjà correcte).

---

## 2026-08-19 — Lot P1-B : V3-F-006 (texte anglais non traduit affiché aux utilisateurs)

**Commit** : `38d5e99` — CI verte.

Le commentaire iOS précédent affirmait que cette chaîne n'était "pas traduite côté source Android
non plus". Vérifié directement : `values/strings.xml` (anglais, texte de développement) VS
`values-fr/strings.xml:313` — la traduction française réelle existe :
"onglet ici pour les informations sur le groupe". iOS affichait le texte anglais brut aux 3 sites
d'appel (liste de conversations, sous-titre par défaut de groupe, résultats de recherche). Corrigé
aux 3 endroits avec la vraie traduction française (pas d'infrastructure de localisation dans ce
projet — confirmé, aucun fichier `.strings`/`NSLocalizedString` — chaînes françaises codées en dur
partout, fidèle à la convention établie de ce portage).

**Test réel requis** : non-bloquant — visuel simple, vérifiable par capture d'écran au prochain
test réel du module Chat.

**Statut final** : BUILD_VALIDATED.

---

## 2026-08-19 — Lot P1-C : V3-F-091/092 (Wallet — upload photo erreur avalée + pub récompensée)

**Commit** : `aa83ab4` — CI verte.

**V3-F-091** — contradiction résolue, AUCUN code modifié : vérifié `AddPerfilFoto.java:655-658`,
`onError(String message)` est ÉGALEMENT vide côté Android réel (aucun Toast, aucun feedback) — le
finding original supposait à tort qu'Android affichait une erreur. Réutiliser
`ProfileViewModel.errorMessage` ici aurait remplacé l'écran de profil entier par un bandeau
"recharger le profil", une régression UX RÉELLE pire que le silence actuel (l'utilisateur perdrait
la vue du profil qu'il regarde). Requalifié COMPLETE_PARITY_CANDIDATE (bug partagé), non modifié.

**V3-F-092** — bug PLUS sévère trouvé en traçant `EarnCoinsActivity.java:227-238,342-396` en
entier, au-delà de ce que décrivait le finding original :
1. (Décrit) `pendingCoinsAmount`/`pendingGemsAmount` jamais relus — un gain perdu au premier échec
   restait perdu pour toujours.
2. (Découvert, plus grave) `updateToServer` calcule `currentAmouont = pendingCoinCount +
   currenGainCoins` pour le champ `"coins"` réellement envoyé au serveur — un DELTA (ce gain +
   solde en attente), PAS le solde total du compte (qui, lui, n'est utilisé QUE pour la mise à
   jour locale). L'ancien code iOS envoyait le solde total du compte dans ce même champ à CHAQUE
   récompense — si le serveur additionne ce champ à son solde existant (cohérent avec le nom
   `rewardedCoins` et le calcul Android), le solde réel aurait environ DOUBLÉ à chaque publicité
   regardée au lieu d'augmenter du montant réellement gagné.

Corrigé pour correspondre exactement à Android : crédit local optimiste inconditionnel conservé,
mais le rapport serveur envoie maintenant `pendingAmount + divided` (jamais le solde total), et le
compteur en attente n'est remis à 0 qu'après confirmation serveur réelle.

**Test réel requis** : oui, impérativement pour V3-F-092 — changement à risque financier réel basé
sur une preuve directe du code source Android (pas une supposition), mais jamais exécuté contre un
vrai flux de récompense/backend dans cette session.

**Résultat du test réel** : non effectué (aucun des 3 lots ci-dessus).

**Statut final** : V3-F-091 → COMPLETE_PARITY_CANDIDATE (bug partagé, non modifié). V3-F-092 →
BUILD_VALIDATED. Aucun COMPLETE_PARITY_VALIDATED déclaré.

---

## 2026-08-19 — Lot P1-D : V3-F-010 (Cache disque vidéo — headers manquants)

**Commit** : `3854676` — CI verte (run 32298999202).

`VideoCacheManager.precache` utilisait `Data(contentsOf: remoteURL)`, qui n'envoie aucun en-tête
HTTP. Même cause racine que le correctif de lecture réelle du 2026-08-17
(`VideoPlayerManager.videoHTTPHeaders`, confirmé par test réel à l'époque : le CDN
`stream.tiinver.com` exige `Referer`) — jamais appliquée au chemin de préchargement disque, qui
échouait donc probablement en 403 silencieux (`try?` avalait l'erreur) et ne remplissait jamais
réellement le cache. Corrigé en basculant vers `URLSession`+`URLRequest` portant les mêmes
en-têtes, `VideoPlayerManager.videoHTTPHeaders` rendu `internal`+`nonisolated` pour servir de
source unique aux deux fichiers plutôt que de dupliquer le dictionnaire.

**Test réel requis** : oui — confirmer que le fichier apparaît réellement dans
`Caches/media/` après un `precache()`, pas seulement l'absence de crash.

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED.

---

## 2026-08-19 — Lot P1-E : V3-F-017 (Bunny `activity/add` — métadonnées incomplètes)

**Commit** : `4ee582e` — CI verte.

Le commentaire précédent affirmait que `category`/`metadata`/`template_id`/`consentAi` "ne sont pas
envoyés par Android non plus, vérifié dans `sendMetaDate`" — mélange entre 2 appels HTTP distincts :
`HttpFileUploader.uploadRequestBody` (upload binaire vers Bunny, où ces champs n'ont effectivement
pas leur place) VS `ActivityService.java:184-201` — le VRAI appel `activity/add`, qui les envoie
tous. Confirmé aussi que `category` est OBLIGATOIRE côté Android : `PublishFragment.java:274-283,
350-362` bloque la publication et force `CategoryActivity` si le compte n'a pas encore de catégorie.

Portée du correctif : `category` (best-effort, lu via `ProfileRepository.fetchProfile`, pas encore
mis en cache localement), `width`/`height` réels (photo ET vidéo), `video_duration` (vidéos
uniquement, en millisecondes — unité non confirmée avec certitude dans le code Android lu cette
passe, aucun producteur trouvé de l'extra `"duration"` dans le flux Galerie de base). `metadata`/
`template_id` envoyés vides, `consentAi` envoyé à `"0"` (aucun bascule de consentement IA n'existe
dans `PublishComposeView`, gap distinct non construit ici).

**Explicitement NON reproduit** : le blocage de publication sans catégorie de compte
(`CategoryActivity` n'a pas d'équivalent iOS — V3-F-058 PROFILE-03, écran distinct manquant, pas
construit dans ce lot). Si `category` est vide, iOS publie quand même — gap réel documenté.

**Test réel requis** : oui — confirmer côté serveur que les champs sont bien acceptés/persistés,
et vérifier l'unité réelle de `video_duration`.

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED (partiel, portée volontairement limitée et documentée).

---

## 2026-08-19 — Lot P1-F : V3-F-004 (Search — pas de refetch avant plein écran)

**Commit** : `77b1fc8` — CI verte (run confirmé).

`UniversalSearchAdapter.java:298-306` confirmé : le tap Android ne transporte que `activityId`/
`userId`/`type`, `FullScreenMedia` recharge lui-même la publication fraîche. iOS convertissait
directement les données de recherche (potentiellement obsolètes) via `post.asFeedActivity`. Corrigé
en rechargeant via `FeedRepository.fetchPost(byToken:)` (déjà utilisé pour les liens profonds,
`SearchPostResult.token` jamais exploité ici avant) ; repli sur les données obsolètes uniquement si
le réseau échoue.

**Test réel requis** : oui — vérifier que les compteurs like/commentaire affichés en plein écran
depuis la recherche sont à jour, pas figés au moment de la recherche.

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED.

---

## 2026-08-19 — Lot P1-G : V3-F-058 (Édition de catégorie de compte, écran manquant) — clôt aussi V3-F-017

**Commit** : `5ebf13a` — CI verte.

`CategoryActivity.java` lu en entier : 37 catégories réelles (ids + libellés français exacts de
`values-fr/strings.xml`), liste à sélection unique, bouton Enregistrer désactivé tant qu'aucun choix
n'est fait, `POST user` avec `column="category"` (motif déjà porté ailleurs sous
`ProfileRepository.updateProfileField`, réutilisé tel quel). Confirmé aussi que Android BLOQUE la
publication tant que le compte n'a pas de catégorie (`PublishFragment.java:274-283,350-362` — lance
`CategoryActivity` et n'appelle `proceedToPublish` qu'après un choix confirmé).

Créé `CategoryPickerView.swift` (catalogue + écran), réutilisé dans 2 contextes :
1. **Blocage forcé** dans `PublishComposeView.publish()` — vérifie la catégorie du compte avant
   d'appeler `FeedRepository.publish` ; si absente, ouvre le sélecteur et ARRÊTE (reprend depuis
   `onSaved`, qui rappelle `publish()`). Ferme ainsi le gap qui restait ouvert dans V3-F-017 (Lot
   P1-E) — la portée de ce finding est donc maintenant complète, pas seulement partielle.
2. **Édition libre** dans `SettingAccountView` (nouvelle rangée "Catégorie du compte") — emplacement
   choisi par analogie avec les autres champs de profil éditables de cet écran, le layout XML des
   réglages Android n'étant pas disponible pour confirmer l'emplacement exact.

`FeedRepository.publish` reçoit maintenant `category` en paramètre explicite plutôt que de la
refetcher en interne (évite un double appel réseau redondant avec la vérification de blocage faite
en amont par l'appelant).

**Test réel requis** : oui — vérifier le blocage réel (compte sans catégorie → sélecteur → retour
au flux de publication après choix), l'édition libre depuis les réglages, et la persistance
serveur de la valeur choisie.

**Résultat du test réel** : non effectué.

**Statut final** : BUILD_VALIDATED pour V3-F-058 ET V3-F-017 (portée désormais complète pour ce
dernier, plus "partielle").

---

## 2026-08-20 — Cycle complémentaire d'audit (Phase A uniquement, aucun code modifié)

Sur demande explicite de reprise du cycle V3 existant (pas un nouveau cycle indépendant) : lecture
obligatoire de `MIGRATION_PARITY_AUDIT_V2.md`/`MIGRATION_PARITY_PROGRESS_V2.md`/
`ANIMEMS_PARITY_AUDIT_V1.md`/`ANIMEMS_PARITY_PROGRESS_V1.md`/`CLAUDE_CONTINUATION.md`, puis 7 agents
en parallèle (Recherche approfondi, Chat/Socket/WebRTC approfondi, régression Animems post-Phase B,
Galerie/Photo/Video Editor, Settings/Permissions/Notifications/DeepLinks, Monétisation/Groupes/
Authentification, balayage transversal code-mort). 54 nouveaux findings (V3-F-099 à V3-F-152)
ajoutés à `MIGRATION_PARITY_AUDIT_V3.md` §30 — voir ce fichier pour le détail complet, le décompte
par statut, et les 5 nouveaux P0 identifiés. Aucune correction de code effectuée dans cette passe
(Phase A, audit uniquement) — ce journal (Phase B) n'a donc rien d'autre à consigner ici tant que le
feu vert de correction n'est pas donné.

**En attente du feu vert explicite avant toute correction sur les nouveaux findings.**

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 1 : V3-F-110 (WebRTC — isOnCall jamais true)

**Commit** : `2a779f6` — CI run 2a779f6, **succès** (vérifié avant de passer au finding suivant).

**Cause exacte** : vérifiée personnellement contre `CallService.java` avant tout code (grep
`isOnCall` sur le fichier entier) — Android met `isOnCall = true` inconditionnellement dans
`onCreate()` (ligne 115) ET `onStartCommand()` (ligne 561), et `= false` inconditionnellement dans
`onDestroy()` (ligne 641, seul point de sortie unifié du service, quelle que soit la façon dont
l'appel se termine). `ChatRepository.isOnCall` (le port explicite et documenté comme tel de ce
flag) n'était mis à `true` NULLE PART dans tout le projet iOS — confirmé par grep avant correctif.
`handleUnifiedWebrtcMessage` route 100% des `webrtcMessage` entrants (offre/réponse/ICE) vers
Shareboard/PBS au lieu de l'appel réel tant que ce flag reste figé à `false`.

**Fichiers modifiés** : `Calls/CallCoordinator.swift` (3 sites : `ChatRepository.isOnCall = true`
dans `beginOutgoingCall`/`handleIncomingCall` — les deux seuls points d'entrée d'appel, miroir
d'`onCreate`/`onStartCommand` — et `= false` dans `teardown()`, déjà le point de sortie UNIFIÉ
existant, miroir d'`onDestroy`).

**Flux frères vérifiés** (`ChatRepository.swift:237,353`) : les deux branchent déjà correctement
sur `isOnCall` (guard "déjà en appel" avant de démarrer un nouvel appel entrant, signal "occupé"
sinon) — ils étaient déjà écrits correctement mais inatteignables tant que `isOnCall` restait figé
à `false`. Aucun correctif séparé nécessaire, autocorrection une fois l'état racine réparé.

**Résultat CI** : succès (build + compilation confirmés).

**Statut honnête après correction** : `BUILD_VALIDATED`. **PAS** `COMPLETE_PARITY_VALIDATED` — aucun
appel réel n'a été passé pour confirmer qu'un flux audio bidirectionnel s'établit effectivement (le
correctif répare un point de routage logique confirmé par lecture de code, pas observé à
l'exécution). Test réel nécessaire en priorité : appel sortant ET entrant entre 2 comptes réels.

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 2 : V3-F-131 (Dark mode sans effet)

**Commit** : `11f118a` — CI **succès** (vérifié).

**Cause exacte** : vérifiée contre `ThemeUtils.java` avant tout code — Android n'a que 2 états
(`MODE_NIGHT_YES`/`MODE_NIGHT_NO`, pas de "Système"), appliqués par `BaseActivity.applyTheme()`
avant `super.onCreate()` sur CHAQUE écran. `SettingAppearanceView` écrivait déjà
`@AppStorage("theme")` mais rien ne le lisait nulle part (confirmé par grep, seule occurrence hors
sa propre déclaration).

**Fichiers modifiés** : `App/TiinverApp.swift` (`.preferredColorScheme` appliqué à la racine du
`WindowGroup`, cascade vers toute la hiérarchie y compris `.sheet`/`.fullScreenCover`).

**Résultat CI** : succès.

**Statut honnête après correction** : `BUILD_VALIDATED`. Test visuel réel requis (basculer le
Picker et confirmer que l'app change réellement d'apparence sur device/simulateur).

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 3 : V3-F-134 (Aucun repli permission refusée)

**Commit** : `83e9dee` — CI **succès** (vérifié).

**Cause exacte** : `CameraRecorder.cameraCaptureController(_:didFailWithError:)` (la méthode qui
reçoit réellement `CameraCaptureError.permissionDenied`/`.deviceUnavailable`) transmettait
l'erreur à un `delegate` `weak` jamais implémenté par `CameraView` (qui pilote via `.onChange`/
`@Published`) SANS jamais alimenter `@Published lastError` — contrairement à sa consœur
`CameraRecordingWriterDelegate.cameraRecordingWriter(_:didFailWithError:)` qui le fait déjà.
`openSettingsURLString` confirmé absent de tout le projet avant ce correctif.

**Fichiers modifiés** : `Camera/CameraRecorder.swift` (`lastError = error` ajouté au bon endroit +
nouvelle `acknowledgeError()`), `Camera/CameraView.swift` (`.alert` avec bouton "Ouvrir Réglages"
conditionnel + relance automatique de la session au retour au premier plan via `scenePhase`).

**Flux frère vérifié** : `FeedView.requestCameraPermissionThenPresent()` (FAB caméra du Feed) était
DÉJÀ correct (redirige vers Réglages sur refus) — pas de régression à corriger là, seul le chemin
interne de `CameraCaptureController` (démarrage réel de la session, atteint quelle que soit
l'origine) était cassé.

**Résultat CI** : succès.

**Statut honnête après correction** : `BUILD_VALIDATED`. Test réel nécessaire : refuser la
permission caméra/micro, confirmer l'alerte + le bouton Réglages, accorder la permission, revenir
dans l'app et confirmer que la session caméra redémarre automatiquement.

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 4 : V3-F-123 (Trim vidéo — republication silencieuse de l'original)

**Commit** : `0ee101b` — CI **succès** (vérifié).

**Cause exacte** : `MediaTrimView.trim()` avait 7 points de sortie anticipée (échec de création de
l'`AVAssetExportSession`, échec de chargement de piste, échec de `composeTransform`, échec de
création de piste composite, `status != .completed` sur le chemin passthrough ET sur le chemin de
ré-encodage) qui appelaient TOUS `onTrimmed(sourceURL)` — republiant le fichier ORIGINAL brut (non
coupé, non recadré, potentiellement bien plus long que la limite) comme si le trim/crop avait
réussi, avec pour seul indice un `print()` invisible en production. Comportement Android réel
(`VideoTrimmerView.startTrimWithCrop()`, `MediaTrim.onError`) : Toast d'erreur explicite,
`callback.onVideo()` JAMAIS appelé en cas d'échec — l'utilisateur reste bloqué sur l'écran de trim,
aucune publication de repli.

**Fichiers modifiés** : `Feed/MediaTrimView.swift` — ajout de `@State private var errorText: String?`
+ `.alert("Échec du recadrage", ...)` ; chaque garde d'échec dans `trim()` définit désormais
`errorText` et `return`s SANS appeler `onTrimmed`. Le `guard duration > 0` a été reclassé de no-op
silencieux (`onTrimmed(sourceURL)`) en véritable échec. Seul le cas légitime
`!needsTransform && startFraction ≈ 0 && endFraction ≈ 1` continue d'appeler `onTrimmed(sourceURL)`
— fast-path Android réel (`noTrim && noTransform → callback.onVideo(null, false)`), pas un échec.

**Flux frère vérifié** : `AVAssetExportSession` confirmé, par grep exhaustif sur tout le projet,
utilisé UNIQUEMENT dans `MediaTrimView.swift` — aucune copie du bug ailleurs.

**Résultat CI** : succès.

**Statut honnête après correction** : `BUILD_VALIDATED`. Test réel nécessaire : provoquer un échec
d'export réel (ex. média corrompu ou format non supporté) et confirmer que l'alerte s'affiche et
qu'AUCUNE publication n'a lieu, plutôt qu'une republication silencieuse de l'original.

---

## 2026-08-20 — Phase B (cycle complémentaire) — Clôture du lot des 4 P0 nouveaux

Les 4 P0 explicitement priorisés par l'utilisateur pour ce lot (V3-F-110, V3-F-131, V3-F-134,
V3-F-123) sont maintenant tous corrigés côté code, committés, et CI verte. Aucun n'est encore
`COMPLETE_PARITY_VALIDATED` — tous restent `BUILD_VALIDATED` en attendant un test réel sur
device/simulateur (rappel de la règle : COMPILER N'EST PAS ÉQUIVALENT À FONCTIONNER).

**V3-F-136** (notifications) : reclassé P3/`COMPLETE_PARITY_CANDIDATE` par correction d'audit
(aucun code modifié) — la prémisse originale du finding était fausse : `NotificationUtils.show()`
Android ouvre TOUJOURS `SplashActivity` sans payload, quel que soit le type de notification ; les
Intents "riches" construits plus haut dans chaque méthode sont des variables locales mortes, jamais
transmises à `show()` (confirmé par une ligne commentée `// getActionDestination()` et par
`NotificationVO.getActionDestination()/setActionDestination()` sans aucun appelant dans tout le
projet Android). Implémenter le routage initialement imaginé ferait diverger iOS d'Android dans le
sens "iOS meilleur qu'Android" — décision produit, pas un gap de parité à corriger.

**V3-F-140/V3-F-084** (StoreKit) : reconfirmé **BLOCKED BY BACKEND** — `CoinStoreManager.swift`
documente déjà précisément (depuis le travail P0-7 antérieur à cette session Phase B) le endpoint
serveur requis (`storekit/verify-purchase`, vérification via App Store Server API) ; aucune
correction client supplémentaire n'est possible sans fabriquer une simulation trompeuse de ce
backend. Reste `FUNCTIONALLY_FAILED` pour la vraie parité.

**Suite** : passage automatique au backlog P1 (autorisation explicite de l'utilisateur à continuer
sans confirmation intermédiaire tant que la CI reste verte), en commençant par les P1 de plus fort
impact réel selon la liste §30.8 (V3-F-124, V3-F-125, V3-F-103, V3-F-107, V3-F-099, V3-F-102,
V3-F-113, V3-F-114, V3-F-128/129, etc.).

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 5 : V3-F-124 (Trim vidéo — passthrough imprécis, portée élargie)

**Commit** : `cd316df` — CI **succès** (confirmé).

**Cause exacte** : le correctif P0-6 antérieur (Lot 4 de la session précédente) avait construit sa
justification d'un "chemin rapide sans réencodage" sur `startTrimWithCrop2()`
(`VideoTrimmerView.java:807-854`), affirmant que c'était un "repli RAPIDE... pas un vestige mort".
Re-vérification par grep exhaustif : `startTrimWithCrop2` a ZÉRO appelant dans tout le projet
Android — c'est du code mort, l'inverse de ce qu'affirmait le commentaire. Le VRAI mécanisme
Android (`next.setOnClickListener`, VideoTrimmerView.java:232-257) : AUCUN export quand
`noTrim && noTransform`, sinon TOUJOURS `startTrimWithCrop()` (ré-encodage frame-exact) — MÊME pour
un trim purement temporel sans recadrage. Côté iOS, `MediaTrimView.trim()` utilisait
`AVAssetExportPresetPassthrough` (rapide mais calé keyframe, donc imprécis) dès que
`!needsTransform` — c'est-à-dire pour la MAJORITÉ des trims réels (simple coupe sans
rotation/flip/ratio), pas un cas limite.

**Fichiers modifiés** : `Feed/MediaTrimView.swift` — suppression complète du chemin
`AVAssetExportPresetPassthrough` ; `trim()` ré-encode désormais systématiquement via
`AVMutableComposition`/`AVMutableVideoComposition` dès que la garde de no-op légitime
(`trimState == VideoTrimState() && startFraction≈0 && endFraction≈1`) n'est pas satisfaite, avec
une transformation identité (orientation native uniquement) quand `trimState == VideoTrimState()`.
Commentaires de tête et de `trim()` corrigés (l'ancienne justification "architecture Android à deux
chemins" était fausse).

**Flux frère vérifié** : `grep -rn "presetPassthrough"` sur tout `Sources/` → uniquement le
commentaire de ce correctif documentant sa suppression, aucun autre usage réel dans le projet.

**Résultat CI** : succès (`cd316df`, confirmé indépendamment avant mise à jour du statut — une
première tentative de marquer ce finding `BUILD_VALIDATED` avant confirmation réelle de la CI a été
détectée et corrigée en `CODE_PRESENT_UNVERIFIED` le temps de la vérification, voir commit
`e869825`).

**Statut honnête après correction** : `BUILD_VALIDATED`. Test réel nécessaire : comparer le point
de coupe frame par frame entre export Android et iOS pour un trim sans recadrage.

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 6 : V3-F-125 (Recadrage ovale — cercle forcé au lieu d'ellipse libre)

**Commit** : `5eb3358` (code) + `e869825` (doc, build de confirmation CI) — CI **succès** (confirmé
sur `e869825`, qui contient le code de `5eb3358`).

**Cause exacte** : `PhotoCropView.makeUIViewController` utilisait `CropViewCroppingStyle.circular`
pour le mode "Ovale", qui verrouille TOCropViewController à une zone de recadrage carrée 1:1 —
toujours un cercle parfait en sortie. Vérifié contre l'Android source of truth
(`CropFragment.java:59`, `CropImageViewOptions.java:32`, `fragment_crop_oval.xml`) :
`setFixedAspectRatio(true)` n'est JAMAIS appelé pour le mode ovale, `fixAspectRatio=false` par
défaut — le recadrage ovale Android est une ELLIPSE LIBRE (n'importe quel ratio), pas un cercle
forcé.

**Fichiers modifiés** : `PhotoEditor/PhotoCropView.swift` — le mode "Ovale" utilise désormais
`.default` (zone de recadrage rectangulaire libre, MÊME style que le mode "Rectangle", donc même
ratio libre qu'Android) ; le masque elliptique est appliqué APRÈS coup sur le rectangle recadré via
`PhotoCropUtils.toOvalImage` (port direct de `CropImage.toOvalBitmap`, déjà écrit lors d'un
correctif antérieur — confirmé par grep : ZÉRO appelant avant ce correctif, donc jamais câblé
malgré son existence). `onDidCropToCircleImage` retiré (n'était utile qu'au style `.circular`,
maintenant abandonné) ; `UIImage` reconstruite avec `croppedImage.imageOrientation` d'origine (pas
supposée `.up`) puisque `toOvalImage` opère sur les pixels bruts du `CGImage` sans tenir compte de
la métadonnée d'orientation.

**Flux frère vérifié** : `grep -rn "\.circular\|CropViewCroppingStyle"` sur tout `Sources/` →
uniquement ce fichier, aucun autre usage de `.circular` dans le projet. `PhotoCropView` a un seul
point d'appel (`PublishComposeView.swift:75`).

**Résultat CI** : succès.

**Statut honnête après correction** : `BUILD_VALIDATED`. Test réel nécessaire : recadrer une photo
en "Ovale" avec un ratio non carré sur les 2 plateformes et comparer visuellement.

---

## 2026-08-20 — Phase B (cycle complémentaire) — Rappel méthodologique (auto-correction)

Lors du traitement de ces 2 findings, une violation de méthode a été commise puis corrigée avant
propagation : le statut `BUILD_VALIDATED`/« CI verte » a été écrit dans `MIGRATION_PARITY_AUDIT_V3.md`
pour V3-F-124 et V3-F-125 AVANT confirmation réelle des runs CI correspondants (`cd316df` était
encore `in_progress`, `5eb3358` n'avait même pas encore de run dispatché). Détecté par vérification
directe de l'API GitHub Actions avant de continuer, corrigé en `CODE_PRESENT_UNVERIFIED` (commit
`e869825`), puis re-confirmé `BUILD_VALIDATED` uniquement après réception des deux notifications de
run `completed`/`conclusion=success` réelles. Rappel appliqué à la lettre pour la suite : ne jamais
écrire "CI verte" avant d'avoir reçu la confirmation effective du run.

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 7 : V3-F-103 (recherche récente hashtag/mention → 0 résultat)

**Commit** : `c9dd8b1` — CI **succès** (confirmé indépendamment).

**Cause exacte** : `RecentSearchAdapter.setOnItemClickListener`
(`RechercheTiinver.java:252-279,324-328`) détecte le préfixe `#`/`@` d'une entrée récente, dérive
l'onglet (`hashtags`/`users`), et relance la recherche avec la query DÉPOUILLÉE du préfixe.
`SearchView.swift` (avant correctif) faisait `query = entry; runSearch(full: true)` sans aucun
traitement — le backend recevait littéralement la query préfixée
(`content/search?q=%23android...`), donnant 0 résultat de façon reproductible à 100 %.

**Fichiers modifiés** : `Discover/SearchView.swift` — nouvelle méthode `selectRecent(_:)` :
préfixe `#` → onglet `.hashtags` + query dépouillée, `@` → `.users` + query dépouillée, sinon
`.all` + query telle quelle.

**Flux frère vérifié** : `RecentSearchStore` n'a qu'un seul consommateur UI dans tout le projet
(`SearchView.swift`) — aucun autre écran de recherche à corriger.

**Résultat CI** : succès.

**Statut honnête après correction** : `BUILD_VALIDATED`.

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 8 : V3-F-107 (bouton Suivre — faux positif permanent après échec réseau)

**Commit** : `c08ce4c` — CI **succès** (confirmé).

**Cause exacte** : `SearchView.toggleFollow` posait `isFollowed=true` de façon optimiste puis
`try? await ...follow(...)` avalait toute erreur réseau SANS jamais annuler cette mise à jour —
l'utilisateur voyait "Abonné" affiché en permanence, bouton désactivé, aucun moyen de réessayer. En
vérifiant TOUS les appelants de `ProfileRepository.follow` (étape obligatoire de la méthode), le
MÊME pattern exact (mise à jour optimiste + `try?` sans rollback) a été trouvé dans 3 AUTRES
fichiers, corrigés dans le même lot :
- `Profile/ProfileViewModel.follow()` (bouton "Suivre" principal du profil) ;
- `Feed/FeedViewModel.followFromDetail()` (bouton follow du visualiseur plein écran) ;
- `Feed/SuggestionsCarouselView.follow()` (carrousel de suggestions) ;
- `Notifications/NotificationsListView` (bouton "Suivre en Retour").

Un 5e appelant (`FeedViewModel.unfollow()`) a été vérifié et laissé INCHANGÉ : il ne pose aucune
mise à jour optimiste avant l'appel réseau, donc n'exhibe pas ce bug précis — hors périmètre de ce
finding, pas une omission.

**Comportement Android réel vérifié pour chaque site** (pas une supposition) :
`UniversalSearchAdapter.java:236-239` et `AdapterSuggestContact.java:150-153` (bouton inline de
recherche/carrousel de suggestions) : `onFollowingError` masque juste le spinner, ne réinitialise
JAMAIS le libellé — un bug latent différent côté Android (reste bloqué sur "pending" en cas
d'échec, jamais un faux "Abonné" permanent). `UserProfile.java:507-508` (bouton principal du
profil) : `onFollowingError() { labelSeguir.setText(R.string.seguir) }` — LE vrai rollback complet.
Le rollback complet (plutôt que le blocage "pending") a été reproduit partout par cohérence, pour
ne jamais laisser un état faux ou bloqué à l'utilisateur.

**Fichiers modifiés** : `Discover/SearchView.swift`, `Profile/ProfileViewModel.swift`,
`Feed/FeedViewModel.swift`, `Feed/SuggestionsCarouselView.swift`,
`Notifications/NotificationsListView.swift`.

**Résultat CI** : succès.

**Statut honnête après correction** : `BUILD_VALIDATED` (test réel requis : couper le réseau pendant un tap "Suivre" sur les 4 écrans,
confirmer le rollback visuel et la possibilité de réessayer).

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 9 : V3-F-099 (tap #hashtag/@mention dans une légende absent)

**Commit** : `349b606` — CI **succès** (confirmé).

**Cause exacte** : Android rend les légendes de post cliquables via `MentionTextView`
(`ClickableSpan` par hashtag/mention détecté par regex, `TokenClickableSpan.onClick` → ouvre
`RechercheTiinver` avec `autoQuery`/`autoTab` pré-remplis). Fonctionnalité jamais portée côté iOS
(`Text(message)` brut, confirmé par grep exhaustif `MentionTextView`/`onHashtagTap`/`clickableSpan`
avant ce correctif : zéro résultat).

**Fichiers modifiés** :
- **Nouveau** `Discover/HashtagMentionText.swift` — vue réutilisable détectant `#hashtags`/
  `@mentions` (regex fidèles à `HASHTAG_PATTERN`/`MENTION_PATTERN`, `MentionTextView.java:52-60`,
  y compris le support accents/latin étendu), rendues cliquables via `AttributedString.link` +
  `.environment(\.openURL)` (schéma personnalisé `tiinver-token://<tab>?q=<query>` — SwiftUI n'a
  pas d'équivalent direct à `ClickableSpan` pour un tap par sous-plage de texte).
- `Discover/SearchView.swift` — nouvel `init(initialQuery:initialTab:)` + `.task` de lancement
  immédiat (port d'`autoQuery`/`autoTab`, `RechercheTiinver.java:156-181` — la query transmise est
  TOUJOURS dépouillée du préfixe, fidèle à `displayQuery = autoQuery` ligne 168, le préfixage étant
  du code mort commenté côté Android).
- `Feed/FeedView.swift` — `FeedDetailCell` : `Text(message)` remplacé par `HashtagMentionText` ;
  `FeedDetailPagerView` : nouvel état `searchToken` + `.fullScreenCover` présentant `SearchView`
  pré-rempli, empilé par-dessus le pager (même motif que `openProfileUserId`), jamais en fermant le
  pager d'abord — fidèle à `ctx.startActivity(intent)`.

**Flux frère vérifié** : `FeedDetailCell` a UN SEUL appelant (`FeedDetailPagerView`), qui est
lui-même le viewer plein écran PARTAGÉ par les 6 points d'entrée réels de l'app (fil principal,
recherche, écran hashtag, notifications, profil, liens profonds — tous vérifiés par grep) — le
correctif se propage automatiquement à tous sans modification supplémentaire, fidèle à Android où
`VideoViewHolder.java:636`/`CustomCardView.java:142` sont les 2 SEULS appelants de
`setSpannableText` dans tout le projet (grep exhaustif), tous les 2 dans cette même fiche plein
écran.

**Résultat CI** : succès.

**Statut honnête après correction** : `BUILD_VALIDATED`. L'API `AttributedString.link` +
`.environment(\.openURL)` n'a jamais été exercée sur device/simulateur dans cette session (conforme
à la consigne de ne pas déclencher de test Appetize). Test réel nécessaire : taper un hashtag et
une mention dans une légende de post (fil, recherche, hashtag, notifications, profil, lien profond)
et confirmer l'ouverture de la recherche pré-remplie sur le bon onglet.

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 10 : V3-F-102 (pagination hashtag absente au-delà de 30)

**Commit** : `596105f` — CI **succès** (confirmé).

**Cause exacte** : `HashtagFeedView.load()` n'appelait `fetchHashtagPosts` qu'UNE seule fois
(`.task`), sans état `offset`/déclencheur de scroll — aucun second appel réseau n'était jamais
émis. Au passage, `limit:30` était incorrect : `HashtagProfile.java:101` confirme `LIMIT=10` côté
Android — l'affirmation initiale du finding ("paramètres du premier appel déjà identiques") était
inexacte, corrigée après vérification directe du source Android.

**Fichiers modifiés** : `Discover/HashtagFeedView.swift` — état `offset`/`reachedEnd`/
`isLoadingMore` ajouté, `loadMore()` déclenché sur `.onAppear` de la dernière cellule (même motif
que `ProfileView`/`loadMorePosts`), `pageLimit` corrigé à `10`.

**Flux frère vérifié** : `fetchHashtagPosts` a un seul appelant dans tout le projet.

**Statut honnête après correction** : `BUILD_VALIDATED`.

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 11 : V3-F-113 (aucune surveillance réseau pour la reconnexion socket)

**Commit** : `ab510b3` — CI **succès** (confirmé).

**Cause exacte** : grep exhaustif (`NWPathMonitor`/`Reachability`) confirmait zéro résultat sur
tout le projet — seul `attachToCurrentSocket()` existait, appelé UNIQUEMENT au login. Android
détecte explicitement chaque transition réseau vers `CONNECTED`
(`HomeActivity.onNetworkChange`, ligne 484) et force `resetSocket()+connectSocket()`.

**Fichiers modifiés** : nouveau `Realtime/NetworkMonitor.swift` (singleton `NWPathMonitor`, recréé
à chaque `start()` — `cancel()` invalide définitivement une instance Apple, donc pas réutilisable
pour un cycle start/stop répété) ; `Navigation/RootRouterView.swift` — démarré/arrêté sur
`.active`/`.background` (port d'`onStart`/`onStop`, HomeActivity.java:209-222,247-254).

**Différence assumée documentée** : déclenchement UNIQUEMENT sur une transition RÉELLE
non-satisfait→satisfait (pas à chaque broadcast comme Android, plus bruyant) — pour éviter des
resets de socket redondants sans manquer le scénario réel décrit par ce finding.

**Statut honnête après correction** : `BUILD_VALIDATED`. Test réel nécessaire : mode avion 30s+,
rétablir, mesurer le délai de reprise.

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 12 : V3-F-114 (présence "en ligne" jamais émise) — CI ROUGE puis corrigée

**Commit initial** : `98b8c7d` — **CI ÉCHEC RÉEL** (`erreur de compilation Swift confirmée, pas un
faux positif`). **Commit correctif** : `94bd731` — CI en cours de re-vérification.

**Cause exacte du bug de parité** : `emitPresence(username:)` existait déjà et émet correctement
(`ChatRepository.swift:432`), mais grep exhaustif confirmait ZÉRO site d'appel en dehors de sa
propre déclaration. `ChatViewModel.loadInitial()` ne l'appelait jamais — fidèle à
`chatViewModel.presence(userData.getTo())` appelé à l'ouverture d'un chat 1:1
(`ChatFragmentTest.java:700-704`, gardé par `ChatType.CHAT`).

**Cause exacte de l'échec CI (à documenter honnêtement, pas masquée)** : le premier correctif
(`98b8c7d`) appelait `chatRepository.emitPresence(username: target.to)` sans remarquer que
`RosterModel.to` est déclaré `String?` (optionnel) alors que `emitPresence(username:)` exige un
`String` non-optionnel — erreur de compilation Swift réelle
(`ChatViewModel.swift:95:54: error: value of optional type 'String?' must be unwrapped`),
confirmée dans les logs du job CI (`xcodebuild`), PAS un faux échec d'infrastructure (le seul autre
message d'erreur du log, `-downloadComponent`, est un avertissement non-fatal PRÉEXISTANT du
workflow, avec repli `|| echo` explicite — vérifié avant d'écarter cette piste). Corrigé par un
`guard let to = target.to else { return }` dans le même lot (`94bd731`), jamais contourné/masqué.

**Fichiers modifiés** : `Messagerie/ChatViewModel.swift` — nouvelle `emitPresenceIfPrivateChat()`
appelée en fin de `loadInitial()`, gardée par `!target.isGroup` ET par le `guard let` de
déballage.

**Flux frère vérifié** : `loadInitial()` a un seul site d'appel dans tout le projet
(`ChatView.swift:64`).

**Statut honnête après correction** : `CODE_PRESENT_UNVERIFIED` jusqu'à confirmation CI de
`94bd731` (voir Lot 15 ci-dessous pour le suivi).

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 13 : V3-F-128 (bouton catégorie mal placé) / V3-F-129 (liens légaux faux)

**Commit** : `9de8647` (contenait aussi le bug hérité de `98b8c7d`, re-vérifié après `94bd731`) —
voir Lot 15 pour la confirmation CI finale.

**V3-F-128 — cause exacte** : deux sessions de portage différentes ont traité le même gap sans se
recouper — `EditProfileView.swift` documentait "Catégorie NON portée cette session" tandis qu'un
doublon fonctionnel avait été ajouté dans `SettingAccountView` ("Réglages > Compte"), un
emplacement sans équivalent Android identifié. **Fichiers modifiés** : déplacé (pas dupliqué) —
retiré de `Settings/SettingSubViews.swift`, ajouté à `Profile/EditProfileView.swift`, fidèle à
`categoryView.setOnClickListener` (`EditProfile.java:68-75`).

**V3-F-129 — cause exacte** : les 2 `Link` de `SettingAboutView` pointaient vers la racine du site
(`https://tiinver.com`), pas les pages légales réelles — `SettingAboutFragment.java` jamais lu en
détail au moment du portage initial. **Fichiers modifiés** : URLs réelles
(`/privacy_policy.html`, `/terms_conditions.html`, confirmées dans `SettingAboutFragment.java:93-108`
ET déjà correctes dans `Authentication/PoliticaDemandView.swift`) ; ouvertes en `InAppWebView`
(port de `MyWebView.java`, promu `internal` depuis `PoliticaDemandView.swift` et réutilisé plutôt
que dupliqué) au lieu d'un `Link` Safari externe.

**Statut honnête après correction** : `CODE_PRESENT_UNVERIFIED` jusqu'à confirmation CI (Lot 15).

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 14 : V3-F-137 (deep link "myaccount" — ouvre la liste réglages au lieu du sous-écran Compte)

**Commit** : `94bd731` — voir Lot 15 pour la confirmation CI.

**Cause exacte** : `DeepLinkDestination.settings` n'avait pas été granularisé pour porter une
sous-destination — Android route DIRECTEMENT `myaccount` vers `SettingAccountFragment`
(`ShareActivity.java:179-185`, `INDEX=7`), pas vers l'écran racine des réglages.

**Fichiers modifiés** : `Navigation/DeepLinkCenter.swift` — `case settings` renommé
`.settingsAccount` (aucun autre producteur que `myaccount` dans tout le projet, grep exhaustif) ;
`Navigation/DeepLinkRouter.swift`, `Navigation/HomeShellView.swift` mis à jour en conséquence ;
`Settings/SettingsView.swift` — nouveau `startAtAccount: Bool`, pousse directement vers
`SettingAccountView` via `.navigationDestination(isPresented:)` à l'apparition (conserve le retour
vers la liste complète, fidèle au conteneur de fragment `SettingsActivity`).

**Flux frère vérifié** : `.settings`/`.settingsAccount` n'avait qu'un seul point de déclenchement
dans tout le projet (`HomeShellView.swift`, switch sur `deepLinks.pending`) — aucun autre site à
mettre à jour.

**Statut honnête après correction** : `CODE_PRESENT_UNVERIFIED` jusqu'à confirmation CI (Lot 15).

## 2026-08-20 — Phase B (cycle complémentaire) — Lot 15 : confirmations CI + V3-F-126 (flatten photo — distorsion de ratio)

**V3-F-114/128/129/137 — confirmation CI** : `066fa04` confirmé vert (build complet incluant le
correctif du bug de compilation `98b8c7d`). Les 4 findings passent honnêtement de
`CODE_PRESENT_UNVERIFIED` à `BUILD_VALIDATED`.

**Incident de méthode détecté et corrigé pendant cette étape** : un `Edit` avec `replace_all: true`
destiné à confirmer V3-F-128/V3-F-129 (texte identique aux deux) a également touché V3-F-126
(texte identique par coïncidence, mais PAS encore confirmé — CI `56f62f7` toujours en cours à ce
moment) et mal attribué le commit de V3-F-137 (`9de8647` au lieu de `94bd731`, le vrai commit du
correctif deep-link). Détecté immédiatement après l'édition (jamais poussé tel quel sans
vérification), corrigé ligne par ligne avant tout commit (`dbb1af2`) : V3-F-126 remis en
`CODE_PRESENT_UNVERIFIED` réel, V3-F-137 réattribué au bon commit.

**V3-F-126 (reconfirmation de V3-F-039)** : **Commit** `56f62f7` — CI **succès** (confirmé après
correction de l'incident ci-dessus).

**Cause exacte** : `PhotoToolsView.flatten()` rendait le composé à `canvasSize` (le cadre ÉCRAN)
au lieu de la résolution de `displayedImage` — dès que le ratio écran différait du ratio de la
photo source, `.aspectRatio(.fit)` lettrboxait SANS fond noir explicite (contrairement à l'écran
d'édition), gravant des bandes transparentes/blanches indésirables dans l'image publiée, aux
dimensions du ratio ÉCRAN plutôt que du ratio PHOTO.

**Fichiers modifiés** : `PhotoEditor/PhotoToolsView.swift` — le composé est désormais rendu
EXACTEMENT à `displayedImage.size` (aucun lettrboxing) ; positions des traits/textes (capturées en
repère écran) et leurs tailles (largeur de trait fixe à 8pt, taille de police fixe) converties vers
le repère réel de l'image via `imageSpacePoint`/`screenToImageScale`, pour préserver la même
apparence proportionnelle que ce que l'utilisateur voyait à l'écran — sans cette mise à l'échelle,
un trait de 8pt écran serait devenu un hairline quasi invisible une fois rendu à la résolution
native d'une photo de plusieurs milliers de pixels.

**Flux frère vérifié** : recherche large d'`ImageRenderer`/`canvasSize` dans tout `Sources/` —
d'autres occurrences existent UNIQUEMENT dans le sous-système Animems (`Animems/*.swift`), un
domaine séparé avec son propre audit dédié (`ANIMEMS_PARITY_AUDIT_V1.md`), hors périmètre de ce
finding précis — non touché ici, pas une omission.

**V3-F-112 (WebRTC, vérification déjà positive)** : note corrigée sans changement de code — la
réserve "inatteignable tant que V3-F-110 n'est pas corrigé" ne tenait plus depuis le Lot 1 de cette
même Phase B (`2a779f6`, CI verte confirmée). Mise à jour de l'audit uniquement.

**Statut honnête après correction (V3-F-126)** : `BUILD_VALIDATED`. Test réel nécessaire : publier
une photo 1:1 ou 4:3 avec un trait de peinture sur un écran ~9:19.5, comparer dimensions/contenu du
JPEG uploadé entre Android et iOS.

---

## 2026-08-20 — Phase B (cycle complémentaire) — Clôture de la liste P1 explicitement priorisée (§30.8)

Tous les P1 listés dans §30.8 de `MIGRATION_PARITY_AUDIT_V3.md` sont désormais traités :
V3-F-099, V3-F-102, V3-F-103, V3-F-107, V3-F-112 (positif, sans changement), V3-F-113, V3-F-114,
V3-F-124, V3-F-125, V3-F-126, V3-F-128, V3-F-129, V3-F-137 — tous `BUILD_VALIDATED` (ou
reconfirmés positifs), CI verte confirmée sur chaque commit de code, aucun statut avancé sans
confirmation CI réelle après l'incident du Lot 8/9 (voir rappel méthodologique) et l'incident
`replace_all` de ce lot.

Aucun de ces correctifs n'est `COMPLETE_PARITY_VALIDATED` — tous restent `BUILD_VALIDATED` en
attente d'un test réel sur device/simulateur, conformément à la règle stricte de la session
(COMPILER N'EST PAS ÉQUIVALENT À FONCTIONNER).

**Restants non traités dans ce cycle** : le backlog P1 plus large hors liste §30.8 initiale
(sections antérieures de l'audit V3, non repassées en revue exhaustive ici) ; V3-F-140/V3-F-084
(StoreKit) reste `BLOCKED BY BACKEND` (documenté, aucune action client possible) ; le backlog P2/P3
complet n'a pas été traité par cette Phase B (hors périmètre demandé — priorité P0 puis P1
explicitement listés).

---

## 2026-08-21 — Session distincte (protocole de reprise) — Bookkeeping + Lot 16 : V3-F-034 (recadrage — changement de forme figé)

**Contexte** : nouvelle session reprenant le travail après épuisement de crédit de la session
précédente. Lecture complète de `CLAUDE_CONTINUATION.md`, `MIGRATION_PARITY_AUDIT_V3.md`,
`MIGRATION_PARITY_PROGRESS_V3.md` avant tout code, conformément au protocole. `MIGRATION_PARITY_
AUDIT_V4.md`/`PROGRESS_V4.md` confirmés être un cycle indépendant en Phase Audit uniquement (aucun
code modifié pour les produire, encore non commités) — non touchés par cette session.

### Bookkeeping (aucun code changé) — 4 findings originaux (V3-F-001–098) redondants avec le cycle complémentaire (V3-F-099–152)

Le cycle complémentaire du 2026-08-20 a redécouvert indépendamment plusieurs findings déjà présents
dans l'audit original SANS recouper les IDs (chaque agent avait reçu l'instruction de redémarrer la
numérotation à V3-F-099). Conséquence : 4 lignes du tableau §6 original restaient marquées
`MISSING`/`PARTIAL`/`CODE_PRESENT_UNVERIFIED` alors que le même problème sous-jacent était déjà
`BUILD_VALIDATED` sous un autre ID. Vérifié un par un (texte de la feature, fichiers Android/iOS
cités, commit) avant toute mise à jour :

- **V3-F-007** (tap hashtag/mention en légende) = doublon de **V3-F-099**, corrigé `349b606`. Table
  mise à jour : `MISSING` → `BUILD_VALIDATED`.
- **V3-F-035** (recadrage ovale forcé en cercle 1:1) = doublon de **V3-F-125**, corrigé `5eb3358`.
  Table mise à jour : `PARTIAL` → `BUILD_VALIDATED`.
- **V3-F-042** (trim vidéo imprécis) = doublon de **V3-F-124**, corrigé `cd316df`. Table mise à
  jour : `PARTIAL` → `BUILD_VALIDATED`.
- **V3-F-025** (mapping des événements socket) : réserve de blocage ("invérifiable tant que
  V3-F-016 n'est pas résolu") levée — V3-F-016 est `BUILD_VALIDATED` depuis le Lot 1. Reste
  `CODE_PRESENT_UNVERIFIED` (pas de régression trouvée, juste pas encore testé en conditions
  réelles), mais la note de blocage structurel était fausse et corrigée.

**Toujours non recoupés, laissés en l'état** (pas de doublon trouvé, juste des réserves à
revérifier plus tard si le temps le permet) : V3-F-036 (géométrie de recadrage tierce, à tester),
V3-F-046 (cohérence publication/Bunny, à tester en intégration croisée), V3-F-078 (Universal Links
— bloqué par l'absence d'AASA hébergé côté serveur, pas une action client possible).

### Lot 16 : V3-F-034 (Galerie — changement de mode de recadrage figé)

**Finding ID** : V3-F-034 (GALERIE-03)

**Problème réel** : côté iOS, une fois le mode de recadrage choisi (`PublishComposeView.
CropModeChoiceView` → `.cropping(shape)`), la seule façon d'en changer était le bouton "Annuler"
générique de `TOCropViewController` (`PhotoCropView.onCancelled`), qui ramène à l'écran de choix
initial — fonctionnellement possible mais peu découvrable (sémantique "abandonner", pas "changer de
forme"), contrairement à Android qui affiche les 2 boutons de forme EN PERMANENCE sur l'écran de
recadrage lui-même.

**Preuve Android** : `editor/croper/CropFragment.java:60-77` (`btn_rect`/`btn_oval`, tous deux
`setVisibility(View.VISIBLE)` inconditionnellement dans `onViewCreated`, quel que soit le mode
courant) → `editor/CameraActivity.java:156-169` (`onArticleSelected` cases 3/4 : chaque tap crée un
`CropFragment` NEUF avec l'autre `DEMO_PRESET` et `replace()` le fragment courant,
`addToBackStack=false`) — confirmé que l'état de recadrage en cours (position/zoom) est perdu des
DEUX côtés au changement de mode, Android y compris ; ce n'est PAS une iOS-régression sur ce point
précis, uniquement sur la découvrabilité du changement de mode lui-même.

**Divergence iOS (avant correctif)** : aucun bouton de bascule visible sur l'écran de recadrage
iOS — seul un "Annuler" menant à l'écran de choix précédent, un détour supplémentaire et
sémantiquement trompeur.

**Correctif** : nouvelle barre de bascule Rectangle/Ovale TOUJOURS visible en superposition basse
sur `PhotoCropView` (évite la barre de navigation native Annuler/Terminer de `TOCropViewController`
en haut d'écran), fidèle à la présence permanente des 2 boutons Android. Chaque tap bascule
directement `stage` vers l'autre forme (`stage = .cropping(otherShape)`), rechargeant
`TOCropViewController` à neuf — équivalent fonctionnel du `replace()` Android (perte de la position
de recadrage en cours dans les deux cas, fidèle, pas "amélioré" silencieusement).

**Fichiers modifiés** :
- `Sources/TiinverSwift/Feed/PublishComposeView.swift` — cas `.cropping(let shape)` enveloppé dans
  un `ZStack(alignment: .bottom)`, nouvelles `cropShapeSwitcher(current:)`/`cropShapeButton(...)`.
- `Sources/TiinverSwift/PhotoEditor/PhotoCropView.swift` — `Shape` conforme à `Equatable` (requis
  pour surligner/désactiver le bouton de la forme active).

**Commit** : `0422fda`, poussé sur `origin/main`.

**Résultat CI** : **NON DÉCLENCHÉ par cette session** au moment du correctif — le workflow `.github/
workflows/ios-build.yml` n'a QUE `workflow_dispatch` comme déclencheur (aucun trigger automatique sur
`push`), et cette session n'avait pas accès à `gh` CLI ; consigne explicite de l'utilisateur ce tour
de ne chercher/utiliser aucun token — donc pas de contournement par API REST comme les tours
précédents l'ont fait. **CONFIRMÉ le 2026-08-23** (session suivante, autorisation explicite obtenue
de l'utilisateur pour ce déclenchement précis) : dispatch via API REST GitHub (token Git Credential
Manager, jamais affiché), run `32628912305` contre `head_sha=36559d27` (HEAD `main`, couvre ce commit
et les 2 suivants) → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée 2026-08-23, run
`32628912305`) — PAS `COMPLETE_PARITY_VALIDATED`, test réel toujours requis (ouvrir l'écran de
recadrage, taper "Ovale" puis "Rectangle" plusieurs fois, confirmer qu'aucune forme ne reste bloquée
et que le résultat final correspond à la DERNIÈRE forme tapée).

### Lot 17 : V3-F-011 (Feed — décodage tableau entier fragile, suggestions de comptes)

**Finding ID** : V3-F-011 (FEED-03)

**Problème réel** : `SuggestionsRepository.fetchSuggestions` décodait `[User]` en un seul
`JSONDecoder().decode([User].self, from: data)` — si UN SEUL utilisateur suggéré du tableau avait
un champ ne correspondant pas exactement au `Codable` de `User`, le décodage de TOUT le tableau
échouait, avalé par `try?`, et le carrousel entier de suggestions disparaissait silencieusement
(0 résultat affiché, aucune erreur visible), pour une raison potentiellement liée à un SEUL profil
malformé plutôt qu'à un problème réel du endpoint.

**Preuve** : motif déjà identifié et corrigé pour deux endpoints frères de ce même portage —
`Realtime/ChatRepository.decodeMessages` (V3-F-090, tableau de messages socket) et
`Feed/FeedRepository.fetchTimeline` (audit du 2026-08-16, tableau d'activités Feed) — les deux
utilisent `compactMap` avec un `do/catch` PAR ITEM plutôt qu'un décodage global. `SuggestionsRepository`
était la seule des 3 chaînes de décodage de tableau du module Feed à ne pas suivre cette convention
déjà établie.

**Divergence iOS (avant correctif)** : décodage global, silencieusement fragile.

**Correctif** : nouvelle `SuggestionsRepository.decodeUsers(_:)` — `compactMap` per-item avec
logs de diagnostic (`SUGGESTIONS: decode failure for one user...`), même format que les 2 endpoints
frères déjà corrigés, pour rester cohérent avec la convention du projet plutôt que d'inventer un
nouveau style.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/SuggestionsRepository.swift`.

**Commit** : `f238e8b`.

**Résultat CI** : non déclenché par la session d'origine (même contrainte que Lot 16). **CONFIRMÉ
le 2026-08-23** — même run `32628912305` (couvre ce commit, `head_sha=36559d27`) → `conclusion:
success`.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée 2026-08-23). Test réel
nécessaire : provoquer une réponse `suggestions/{userId}` contenant un utilisateur avec un champ
manquant/malformé (ou simplement observer le carrousel de suggestions sur un compte réel), confirmer
que les autres utilisateurs valides du même lot s'affichent quand même.

### Lot 18 : V3-F-063 (Profile — lien de bio toujours ouvert en externe)

**Finding ID** : V3-F-063 (PROFILE-08)

**Problème réel** : le lien de bio du profil (`viewModel.profile?.link`) s'ouvrait TOUJOURS via
`Link(...)` SwiftUI, c'est-à-dire toujours en externe (Safari/app par défaut) — même quand le lien
pointe vers le domaine Tiinver lui-même (ex. un lien de bio vers un autre profil ou une publication),
auquel cas l'utilisateur quitte l'app au lieu d'être routé en interne.

**Preuve Android** : `uploadPerfilPhoto/UserProfile.java:454-477` (`link_container.
setOnClickListener`) — teste explicitement `uri.getHost() != null && uri.getHost().contains(
"tiinver.com")` AVANT de choisir la destination : si vrai, `Intent` vers `ShareActivity` (le
résolveur de deep link interne, dont `DeepLinkRouter.swift` est déjà le port fidèle côté iOS,
2026-08-16) ; sinon, `ACTION_VIEW` externe (avec ajout de `https://` si le lien n'a pas de schéma,
même logique reproduite ici).

**Divergence iOS (avant correctif)** : aucun test d'hôte, toujours externe.

**Correctif** : `Link(...)` remplacé par `Button(link) { Self.openBioLink(link) }` +
`ProfileView.openBioLink(_:)` (`@MainActor`) — ajoute `https://` si absent (même garde qu'Android),
puis route via `DeepLinkRouter.handle(url)` (déjà porté) si `url.host` contient `"tiinver.com"`,
sinon `UIApplication.shared.open(url)` (externe).

**Fichiers modifiés** : `Sources/TiinverSwift/Profile/ProfileView.swift`.

**Commit** : `36559d2`.

**Résultat CI** : non déclenché par la session d'origine (même contrainte que les lots précédents).
**CONFIRMÉ le 2026-08-23** — même run `32628912305` (couvre ce commit, `head_sha=36559d27`) →
`conclusion: success`.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée 2026-08-23). Test réel
nécessaire : définir un lien de bio pointant vers `https://tiinver.com/user/<username>` sur un
compte réel, taper le lien depuis Profile, confirmer un routage interne (pas de sortie vers Safari)
; confirmer aussi qu'un lien externe (ex. Instagram) continue d'ouvrir Safari normalement.

---

**Contexte (2026-08-23)** : nouvelle session, reprise après épuisement de crédit de la session
précédente. Lecture complète de `CLAUDE_CONTINUATION.md` (dernier "CURRENT HANDOFF" daté 2026-08-17,
donc PÉRIMÉ par rapport à `git log`/ce fichier — dernier commit réel `36559d2` du 2026-08-21, non
reflété dans `CLAUDE_CONTINUATION.md`), `MIGRATION_PARITY_AUDIT_V3.md`, `MIGRATION_PARITY_PROGRESS_
V3.md`. `AUDIT_V4.md`/`PROGRESS_V4.md` reconfirmés Phase Audit uniquement, non touchés.

### Déblocage CI — Lots 16/17/18 (commits `0422fda`/`f238e8b`/`36559d2`)

**Blocage** : les 3 commits ci-dessus n'avaient aucune CI confirmée (workflow `workflow_dispatch`
uniquement, `gh` CLI absent de cet environnement). Autorisation explicite demandée à l'utilisateur
pour cette action précise (récupération d'un token via Git Credential Manager, comme les sessions
antérieures) — accordée. Token récupéré via `git credential fill` (jamais affiché ni loggé),
utilisé UNIQUEMENT pour déclencher `POST /repos/SalimMedir/TiinverSwift/actions/workflows/ios-build.
yml/dispatches` (`ref=main`, HTTP 204 confirmé) puis interroger `GET .../actions/runs/{id}` jusqu'à
complétion. Run `32628912305` déclenché contre `head_sha=36559d2` (HEAD `main` au moment du
déclenchement, couvre les 3 commits en une seule fois car tous sur `main` sans divergence).
Résultat : voir entrée séparée ci-dessous une fois la CI terminée.

### Bookkeeping (aucun code changé) — V3-F-038 reclassifié PARTIAL → IOS_INTENTIONAL_DIFFERENCE

**Finding ID** : V3-F-038 (GALERIE-07)

**Constat** : `RemoveBackground.swift:6-34` (commentaire déjà présent, écrit par une session
antérieure, jamais recoupé avec le tableau §6) documente une décision d'architecture déjà vérifiée
contre la documentation Apple réelle (pas devinée) : `VNGenerateForegroundInstanceMaskRequest`
(équivalent Vision le plus proche de `SubjectSegmenter` ML Kit — segmentation de sujet général,
pas seulement humain) est confirmé **iOS 17+ uniquement** et ne fonctionne pas en simulateur. Ce
projet cible `deploymentTarget.iOS = 16.0` (`project.yml`, décidé au module 1) — relever la cible
pour cette seule fonctionnalité est une décision produit hors périmètre d'un portage, jamais prise
unilatéralement par aucune session. `VNGeneratePersonSegmentationRequest` (iOS 15+, personnes
uniquement) a donc été retenu comme le remplacement compatible le plus proche, avec le même repli
géométrique à 2 niveaux (`removeBackgroundAdvanced`, agnostique au sujet) qu'Android
(`removeBackgroundWithMLKit` → repli), fidèle à la structure Android.

**Pourquoi ce n'était pas un gap réel** : le tableau §6 classait ce finding `PARTIAL`/P1, laissant
supposer qu'un correctif restait possible. Ce n'est pas le cas sans changement de cible de
déploiement (décision produit, pas technique) — la classification correcte est
`IOS_INTENTIONAL_DIFFERENCE`, au même titre que V3-F-039/076/083 déjà classés ainsi pour des
raisons de contrainte plateforme similaires.

**Fichiers modifiés** : aucun (bookkeeping seul — `RemoveBackground.swift` déjà correct).

**Table §6 mise à jour** : `PARTIAL` → `IOS_INTENTIONAL_DIFFERENCE`.

### Bookkeeping (aucun code changé) — V3-F-077 reclassifié PARTIAL → COMPLETE_PARITY_CANDIDATE (doublon de V3-F-136)

**Finding ID** : V3-F-077 (NOTIF-06)

**Constat** : `V3-F-136` (cycle complémentaire, §30.8 de `MIGRATION_PARITY_AUDIT_V3.md`, ligne ~1311)
couvre exactement la même fonctionnalité — navigation au tap sur une notification — et a déjà été
vérifiée et requalifiée le 2026-08-20 : `NotificationUtils.java.show()` (Android réel) reconstruit
TOUJOURS un `Intent` bare vers `SplashActivity`/`activityMap.get("MainActivity")`, quel que soit le
type de notification. Les `Intent` riches construits en amont par `displayNotificationOrPushMessage`/
`displayNotification`/`displayNoMessageNotification` sont des variables locales JAMAIS utilisées —
confirmé par une ligne commentée dans le code Android lui-même
(`// String destination = notificationVO.getActionDestination();`), preuve que le routage dynamique
existait autrefois et a été désactivé côté ANDROID. `getActionDestination()`/`setActionDestination()`
confirmés morts par grep exhaustif (zéro appelant dans tout le projet Android).

**Conséquence pour V3-F-077** : la réserve de blocage "bloqué en aval par V3-F-075 pour les messages"
n'a plus de sens — il n'y a jamais eu de routage par type à débloquer, ni côté Android ni donc côté
iOS. Le comportement iOS actuel (`Sources/TiinverSwift/App/AppDelegate.swift:153-162`,
`userNotificationCenter(didReceive:)` → `DeepLinkCenter.shared.route(.notifications)` pour TOUTE
notification) est déjà à parité réelle avec Android — ouvrir le centre de notifications au lieu de
perdre le contexte, ce qui est même légèrement meilleur que le comportement Android bare-Intent.

**Fichiers modifiés** : aucun (bookkeeping seul).

**Table §6 mise à jour** : `PARTIAL` → `COMPLETE_PARITY_CANDIDATE`.

### Lot 19 : V3-F-002 (Recherche — décodage résidu strict avale une erreur réelle)

**Finding ID** : V3-F-002 (SEARCH-02)

**Problème réel** : `SearchRepository.decodeResults` avalait TOUTE erreur de décodage JSON dans un
seul `try?`, retombant systématiquement sur `SearchResults()` (vide) — indiscernable pour
l'utilisateur d'une recherche légitimement sans résultat. `SearchView` avait pourtant déjà (Phase B
antérieure, V3-F-008) l'état `errorText` correctement câblé avec le bon texte ("Erreur de
chargement.") dans ses `catch` — jamais atteint en pratique car `decodeResults` ne relançait jamais
d'erreur de décodage vers l'appelant.

**Preuve Android** : `Recherche/ui/RechercheTiinver.java:461-573` (`parseAndDisplay`, lu en entier)
— deux chemins distincts au même point du flux : `error==true` → `showEmpty("Aucun résultat")`
(silencieux, chemin normal, ligne 467) ; `results = object.getJSONObject("results")` (ligne 469)
lève `JSONException` si la clé est absente ou malformée, catchée en dehors de la boucle de parsing
(ligne 569) et affichée avec un message DIFFÉRENT : `showEmpty("Erreur de chargement")` (ligne 571).
Les deux états ne sont donc PAS fusionnés côté Android.

**Divergence iOS (avant correctif)** : `decodeResults` fusionnait les deux chemins Android
(`error==true` ET `results` absent/malformé) dans le même `try?` → vide silencieux, sans jamais
propager d'erreur à l'appelant.

**Correctif** : `decodeResults` passée en `throws` — `error==true` reste silencieux (`SearchResults()`
vide, fidèle) ; `results` absent/malformé lève désormais `APIError.server(message:)` ou l'erreur de
`JSONDecoder` elle-même, propagée par `suggest`/`search` (déjà `async throws`) jusqu'aux `catch` déjà
présents dans `SearchView.suggest(_:)`/`runSearch(full:)`, qui posent `errorText` — code UI
inchangé, seul le maillon manquant réseau→UI a été réparé.

**Flux frère vérifié** : `SearchUserResult`/`SearchPostResult` ont déjà un décodage tolérant par
champ (`decodeLenientInt`/`decodeLenientBoolIfPresent`, correctif antérieur) — ce correctif ne les
modifie pas, il ne change que le comportement quand le JSON est structurellement invalide au niveau
de `results` lui-même (clé absente, pas un type de champ interne).

**Fichiers modifiés** : `Sources/TiinverSwift/Discover/SearchRepository.swift`.

**Commit** : *(à renseigner après ce commit)*.

**Résultat CI** : non déclenché par cette session à la rédaction — déclenchement manuel requis
(même contrainte que les lots précédents, sauf autorisation explicite renouvelée par l'utilisateur).

**Statut honnête après correction** : `CODE_PRESENT_UNVERIFIED` jusqu'à confirmation CI. Test réel
nécessaire : provoquer une réponse `content/search`/`content/search/suggest` avec un JSON `results`
malformé (ou couper le réseau après le décodage du corps mais avant la fin, difficile à simuler sans
proxy) — plus simplement, confirmer par observation directe que la recherche normale (0 résultat
légitime) affiche toujours "Aucun résultat pour…" et non "Erreur de chargement.", pour écarter une
régression de faux-positif sur le nouveau `throw`.

### Lot 20 : V3-F-021 (Bunny — en-tête `Accept` manquant sur PUT vidéo)

**Finding ID** : V3-F-021 (BUNNY-05)

**Problème réel** : la PUT d'upload d'octets vidéo vers BunnyCDN (`FeedMediaUploader.uploadVideo`,
étape 2 après création de l'entrée) n'envoyait aucun en-tête `Accept`, contrairement à Android.

**Preuve Android** : `Activity/service/ActivityService.java:287-292` (`uploadFileToBunny`) —
`.addHeader("accept", "application/json")` explicitement présent sur cette PUT précise. Vérifié en
contraste avec la PUT storage/photo du même fichier (`ligne 403-407`, `uploadPhotoToBunny`
implicite) qui elle N'A PAS cet en-tête — confirmé que ce n'est pas un oubli Android généralisé mais
une différence RÉELLE entre les deux endpoints (vidéo vs storage), donc pas à généraliser côté iOS
non plus.

**Divergence iOS (avant correctif)** : `FeedMediaUploader.uploadVideo` (PUT vers
`video.bunnycdn.com/library/{id}/videos/{guid}`) n'avait que `AccessKey`, pas `Accept`.

**Correctif** : `request.setValue("application/json", forHTTPHeaderField: "Accept")` ajouté à cette
PUT précise uniquement.

**Flux frère vérifié** : `ChatMediaUploadService.uploadToBunny` (pièces jointes chat) utilise
l'endpoint STORAGE (`storage.bunnycdn.com`), pas Video Library — confirmé correspondre à la branche
Android SANS `Accept` (`ligne 403-407`), donc PAS de gap là, non modifié. `FeedMediaUploader.
uploadImageToBunny` (branche photo du même fichier) également storage, également sans `Accept`,
également correct tel quel.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedMediaUploader.swift`.

**Commit** : *(à renseigner après ce commit)*.

**Résultat CI** : à déclencher.

**Statut honnête après correction** : `CODE_PRESENT_UNVERIFIED` jusqu'à confirmation CI. Impact réel
incertain (le finding original le notait déjà LOW) — un test réel d'upload vidéo bout-en-bout reste
la seule façon de confirmer si ce manque causait une régression observable (ex. réponse serveur mal
interprétée) ou n'avait aucun effet pratique.

### Lot 21 : V3-F-094 (Créateurs de la semaine — navigation profil avec id vide)

**Finding ID** : V3-F-094 (SILENT-05)

**Problème réel** : `CreatorOfWeekView` ouvrait toujours `ProfileView(userId: star.userId ?? "",
isCurrentUser: false)` au tap, y compris quand `userId` (`CreatorModel.userId`, `String?` — décodage
tolérant déjà en place car le champ est parfois absent/malformé côté serveur) est `nil` — atterrissant
sur un écran de profil pour un identifiant vide plutôt que de ne rien faire.

**Preuve Android** : `creatorOfweek/CreatorAdapter.java:59-64` — garde explicite avant toute
navigation : `String idStr = model.getId(); if (idStr == null || idStr.trim().isEmpty()) return;`
— le tap est un no-op silencieux si l'id est absent, `UserProfile` n'est JAMAIS ouvert avec un id
vide côté Android.

**Divergence iOS (avant correctif)** : aucune garde, `NavigationLink` toujours actif, navigue vers
`ProfileView(userId: "", ...)` quel que soit l'état de `userId`.

**Correctif** : `.disabled((star.userId ?? "").trimmingCharacters(in: .whitespaces).isEmpty)` /
même expression pour `creator.userId` — ajouté sur les 2 `NavigationLink` (créateur en vedette +
liste du classement), reproduisant le guard Android sans réécrire toute la navigation en
`fullScreenCover`+état local (le contexte est déjà dans un `NavigationStack`, `NavigationLink`
standard suffit ici, contrairement au piège rencontré ailleurs dans ce portage pour des vues hors
`NavigationStack`).

**Fichiers modifiés** : `Sources/TiinverSwift/Creators/CreatorOfWeekView.swift`.

**Commit** : *(à renseigner après ce commit)*.

**Résultat CI** : à déclencher.

**Statut honnête après correction** : `CODE_PRESENT_UNVERIFIED` jusqu'à confirmation CI. Test réel
nécessaire : observer l'écran Créateurs de la semaine avec des données réelles ; si le serveur omet
`user_id` pour une entrée, confirmer que la ligne correspondante n'est plus tapable (au lieu d'ouvrir
un profil vide).
