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
