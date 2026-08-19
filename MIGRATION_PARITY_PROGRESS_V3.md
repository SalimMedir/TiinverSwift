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
