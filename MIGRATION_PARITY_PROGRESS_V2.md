# MIGRATION_PARITY_PROGRESS_V2.md — Journal des corrections post-audit V2

**Ce fichier suit UNIQUEMENT le travail effectué APRÈS `MIGRATION_PARITY_AUDIT_V2.md`.** Chaque
entrée doit référencer le(s) FEATURE(s) concerné(s) dans l'audit V2, le commit, le run CI, et le
statut AVANT/APRÈS selon la taxonomie de l'audit V2. Un build vert = `BUILD_VALIDATED`, jamais
automatiquement un statut de parité supérieur — la mise à jour du statut dans l'audit V2 doit être
justifiée séparément (preuve réelle pour `COMPLETE_PARITY_VALIDATED`, comparaison documentée pour
`COMPLETE_PARITY_CANDIDATE`).

---

## Format de chaque entrée

```
### <date> — <FEATURE(s)> — <résumé court>
**Commit(s) :** 
**Run CI :** 
**Statut AVANT (audit V2) :** 
**Statut APRÈS :** 
**Preuve du changement de statut :** 
```

---

### 2026-08-17 — Galerie/Publication (P0-1) — Reconstruction du vrai pipeline de publication Feed
**Commit(s) :** `b639057`
**Run CI :** [32076424332](https://github.com/SalimMedir/TiinverSwift/actions/runs/32076424332) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `FUNCTIONALLY_FAILED` (haute confiance) — le fichier média (photo ou
vidéo) était envoyé en multipart directement à `activity/add`, un flux qu'aucun client Android réel
n'emprunte jamais.
**Statut APRÈS :** `BUILD_VALIDATED` — commit `b639057` — CI SUCCESS — test fonctionnel réel toujours
requis.
**Preuve du changement de statut :** Tracé en entier `Activity/service/ActivityService.java`
(`onStartCommand`/`sendMetaDate`/`uploadImageToBunny`/`getCdnVideoId`/`uploadFileToBunny`) — confirmé
que `httpFileUploader` n'est référencé que pour `.cancel(true)`, jamais pour un upload réel. Nouveau
fichier `Feed/FeedMediaUploader.swift` reproduit fidèlement les 2 flux BunnyCDN (Storage photo,
Video Library vidéo 2-étapes). `FeedRepository.publish` réécrit : upload CDN d'abord, PUIS
`POST activity/add` avec métadonnées texte SEULEMENT (`cdn_content_id`/`cdn_content_url`/
`cdn_thumbnail_url`/`cdn_provider`/`object_url`, jamais de fichier). CI verte confirmée sur ce commit
précis. **Reste non prouvé** : qu'un post publié depuis iOS apparaît réellement dans `feedtimeline`
avec un média lisible côté client (Android ou iOS), et que `AVPlayer`/`VideoPlayerManager` lit
correctement le HLS `.m3u8` retourné par la Video Library — nécessite un test Appetize global, pas
demandé séparément ici par instruction explicite de l'utilisateur (batching).

### 2026-08-17 — Home/Feed (P0-2) — Re-trace complète session→JSON→decode→ViewModel→Grid→Fullscreen
**Commit(s) :** (aucun — audit uniquement, pas de code changé, aucun gap trouvé)
**Run CI :** N/A
**Statut AVANT (audit V2) :** `COMPLETE_PARITY_CANDIDATE`
**Statut APRÈS :** `COMPLETE_PARITY_CANDIDATE` (inchangé)
**Preuve du changement de statut :** Relu intégralement `FeedRepository.fetchTimeline`,
`FeedViewModel.loadNextPage`, `FeedActivity.init(from:)`, `FeedView.body`/`FeedGridCell`/
`FeedDetailPagerView` sans supposer les correctifs de sessions précédentes suffisants (consigne
explicite de l'utilisateur : ne pas assumer). Chaque maillon a déjà une instrumentation de diagnostic
réelle et affichée à l'écran (pas seulement console) pour les 3 causes historiques de "feed vide sans
erreur" (session invalide silencieuse, décodage `compactMap` avalant les échecs, `errorMessage`/
`isLoading` jamais rendus). Chaîne Grid→tap→Fullscreen vérifiée intacte. **Aucun nouveau gap trouvé** —
conclusion honnête : rien à corriger ici, mais aucune preuve de test réel post-derniers-correctifs
n'existe non plus, donc le statut reste `COMPLETE_PARITY_CANDIDATE` et non `_VALIDATED`.

### 2026-08-17 — Profile (P0-3) — Décodage per-item pour `fetchUserPosts`/`fetchHashtagPosts`
**Commit(s) :** `da89974`
**Run CI :** [32077274517](https://github.com/SalimMedir/TiinverSwift/actions/runs/32077274517) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `COMPLETE_PARITY_CANDIDATE` (cœur), gap silencieux non détecté
**Statut APRÈS :** `BUILD_VALIDATED` — commit `da89974` — CI SUCCESS — test fonctionnel réel
toujours requis
**Preuve du changement de statut :** `ProfileRepository.fetchUserPosts`/`fetchHashtagPosts`
utilisaient `try? JSONDecoder().decode([FeedActivity].self, ...) ?? []` — un seul post au format
inattendu aurait vidé silencieusement toute la grille Profile. Remplacé par un décodage per-item +
diagnostic console (même motif que `FeedRepository.fetchTimeline`). Endpoint grille re-vérifié
contre `ProfileRepository.java:153` (identique). Chaîne Grid→tap→Fullscreen vérifiée intacte.

### 2026-08-17 — Chat/Messaging (P0-4) — Décodage per-item pour contacts + membres de groupe
**Commit(s) :** `07f3e51`
**Run CI :** [32077495705](https://github.com/SalimMedir/TiinverSwift/actions/runs/32077495705) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `COMPLETE_PARITY_CANDIDATE` (création de groupe 3 écrans), historique
`FUNCTIONALLY_FAILED` déjà corrigé une fois pour la cause précise `userId` numérique
**Statut APRÈS :** `BUILD_VALIDATED` — commit `07f3e51` — CI SUCCESS — test fonctionnel réel toujours requis
**Preuve du changement de statut :** Re-vérifié la chaîne FAB→`ContactPickerView`→`GroupCreationView`
intacte (aucune régression). Trouvé et corrigé un point de fragilité résiduel : `ContactsRepository.
connectedUsers` et `GroupRepository.fetchMembers` décodaient encore le tableau ENTIER via `try?`,
laissant la possibilité qu'UN SEUL contact/membre non conforme revienne à faire disparaître toute la
liste silencieusement — exactement la classe de bug déjà identifiée comme suspecte dans un commentaire
de code préexistant pour P0-F, mais dont seule la cause ponctuelle (pas le point de fragilité
structurel) avait été corrigée. Remplacé par le même motif per-item + diagnostic que Feed/Profile.

### 2026-08-17 — Animems (P0-5) — `.id(state.version)` interrompait TOUS les gestes Timeline
**Commit(s) :** `e7736af`
**Run CI :** [32077883055](https://github.com/SalimMedir/TiinverSwift/actions/runs/32077883055) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `CODE_PRESENT_UNVERIFIED`/`FUNCTIONALLY_FAILED`→corrigé (GAP-024,
canevas principal uniquement) pour le geste ; Timeline jamais spécifiquement auditée jusqu'ici pour
cette classe de bug précise
**Statut APRÈS :** `BUILD_VALIDATED` — commit `e7736af` — CI SUCCESS — test fonctionnel réel toujours requis
**Preuve du changement de statut :** Relu intégralement `TimelineView.swift` (jamais relu lors du
correctif GAP-024 initial ni de l'audit V2 Phase 1, qui s'étaient arrêtés à `AnimemesEditorView.swift`/
`AnimemesEditorState.swift`/`AnimemesGestureController.swift`) — trouvé le MÊME `.id(state.version)`
sur un `Canvas` porteur de `.gesture()`, en PIRE : `combinedDragGesture`/`magnificationGesture`
appelaient `state.bumpVersion()` à CHAQUE frame de geste (contre seulement certaines fonctions sur le
canevas principal), garantissant l'auto-interruption de pan/scrub/glisser-item/redimensionner/
pincer-zoomer dès le premier mouvement du doigt — Timeline entièrement non-utilisable en pratique.
Corrigé avec le motif GAP-024 exact : `.id()` retiré, nouveau `AnimemesEditorState.
bumpRenderVersion()` utilisé par les gestes continus + `scrub(toFrame:)` (au lieu de `bumpVersion()`/
`version += 1` direct), pour éviter aussi le sur-déclenchement de `preparePlayback()` par frame.

### 2026-08-18 — Chat/Messaging (P1) — Implémentation de la recherche de groupe/conversation
**Commit(s) :** `eae0e8e`
**Run CI :** [32079879361](https://github.com/SalimMedir/TiinverSwift/actions/runs/32079879361) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `MISSING` confirmé
**Statut APRÈS :** `BUILD_VALIDATED` — commit `eae0e8e` — CI SUCCESS — test fonctionnel réel toujours requis
**Preuve du changement de statut :** Lu `Recherche/ui/ChatAdapter.java:291-313` (click handler,
manquant de la passe précédente) — confirmé qu'Android ouvre directement `ActivityMsg` au tap, sans
étape "rejoindre" séparée. Nouveau `ChatSearchView.swift` : filtre local des conversations
(`RosterListViewModel.rows`) + repli serveur `GroupRepository.searchGroups` (`search/{myId}/{str}`,
décodage per-item avec diagnostics) si aucun résultat local, debounce 300ms fidèle à l'original.
Construction du `RosterModel` extraite en `GroupRepository.GroupInfo.rosterModel(myId:myUsername:)`,
réutilisée par `DeepLinkRouter.routeToGroup` (corrige au passage son `subTitle` vide — chaîne réelle
`"tab here for group info"` identifiée depuis `RosterListViewModel.refresh()`). Icône loupe ajoutée
à la toolbar de `RosterListView`.

### 2026-08-18 — Chat/Messaging (P1) — Implémentation des réglages de conversation 1:1
**Commit(s) :** `bcbb05e`
**Run CI :** [32080225502](https://github.com/SalimMedir/TiinverSwift/actions/runs/32080225502) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `MISSING` confirmé (seul un raccourci direct-vers-profil existait)
**Statut APRÈS :** `BUILD_VALIDATED` — commit `bcbb05e` — CI SUCCESS — test fonctionnel réel toujours requis
**Preuve du changement de statut :** Lu `setting/SettingPrivateMessageFragmant.java` (238 lignes,
entier) — confirmé hébergé par `messagerie/ui/ProfileDetailActivity.java`, la MÊME Activity que
`SettingGroupMessageFragmant`/`GroupDetailView.swift` (déjà porté) selon `chatType`, atteint en tapant
le titre de la conversation (`ActivityMsg.titleContainer`). Nouveau `PrivateMessageSettingView.swift` :
rangée profil (`profile_btn`), interrupteur "livraison instantanée" + heure de livraison programmée
(100% `UserDefaults`/`@AppStorage`, AUCUN appel réseau côté Android non plus dans ce fichier précis),
bouton "Bloquer" reproduit FIDÈLEMENT (Android ne fait QUE changer le label ici, aucune persistance
ni appel réseau — pas "corrigé" en un vrai toggle, qui existe déjà ailleurs, `ProfileViewModel.
toggleBlock`). Le bouton "person.circle" du chat 1:1 (raccourci direct-profil documenté comme gap
volontairement borné) ouvre désormais ce vrai écran.

### 2026-08-18 — Galerie/Publication (P1) — Implémentation du système Boost
**Commit(s) :** `7d57f93`
**Run CI :** [32080739229](https://github.com/SalimMedir/TiinverSwift/actions/runs/32080739229) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `MISSING` total, 5 classes Android sans équivalent iOS
**Statut APRÈS :** `BUILD_VALIDATED` — commit `7d57f93` — CI SUCCESS — test fonctionnel réel toujours requis
**Preuve du changement de statut :** Lu en entier les 5 fichiers Android (`AdsRepository.java` 504
lignes, `CreateBoostFragment.java` 497, `BoostDashboardFragment.java` 243, `BoostActivity.java` 68,
`CommandeActivity.java` 163, + modèles `AdsData`/`Audience`/`TagModel`). Nouveau dossier
`Sources/TiinverSwift/Boost/` (6 fichiers) : `AdsRepository.swift` (7 endpoints réels tracés :
`boost/overviews/{userId}`, `boost/myboost/{userId}/{limit}/{offset}`, `boost/create`/`create2`
selon devise, `boost/update`, `boost/cancel2`, `searchs/country/{s}`), `BoostView.swift` (conteneur
2 onglets), `CreateBoostView.swift` (formules `estimateReach` EXACTES — views×4/likes÷3/followers÷5
division entière —, garde budget<5 silencieuse fidèle), `BoostDashboardView.swift`/
`BoostDetailView.swift` (vue d'ensemble + liste paginée + annulation). Point d'entrée : action
"Promouvoir" dans le menu "..." du Feed pour ses propres posts (`isOwnPost`, même garde que
`promoteBtn`/`CustomCardView.java:238`). Bug Android reproduit fidèlement (pas corrigé) : la
déduction locale de solde après succès écrit toujours dans `coinsAmount`, même en payant par
gemmes.

### 2026-08-18 — Profile (P2) — Implémentation de StatisticsActivity (statistiques par post)
**Commit(s) :** `174c0d9`
**Run CI :** [32164904331](https://github.com/SalimMedir/TiinverSwift/actions/runs/32164904331) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `MISSING` confirmé (GAP-016 historique)
**Statut APRÈS :** `PARTIAL` (`BUILD_VALIDATED` — CI SUCCESS) — point d'entrée Feed câblé,
point d'entrée Profile (fullscreen) restant, test fonctionnel réel toujours requis
**Preuve du changement de statut :** Lu `Activity/ui/StatisticsActivity.java` (228 lignes, entier) +
`models/activity/StatisticModel.java` (entier). `AdsRepository.fetchStatistics` ajouté (`activity/
statistics/{activityId}/{userId}`, clé `"statistics"`). Nouveau `StatisticsView.swift`. **Bug
Android reproduit fidèlement, PAS corrigé** : la boucle `for (Map.Entry entry : genderDist)`/
`ageDist` réaffecte les 3 variables (homme/femme/inconnu, ou les 6 tranches d'âge) à CHAQUE
itération plutôt que seulement pour la clé courante — un dictionnaire à plusieurs entrées ne peut
peupler qu'UN SEUL champ (le dernier itéré), les autres retombant à "--" ; reproduit à l'identique
plutôt que "corrigé" en un mappage propre qu'Android n'affiche jamais dans la pratique. Point
d'entrée : action "Statistiques" ajoutée au menu "..." du Feed pour ses propres posts (même garde
`isOwnPost` que "Promouvoir"). **Écart honnête non comblé cette passe** : le point d'entrée
équivalent depuis le fullscreen de PROFIL (`FeedDetailPagerView(posts:startIndex:onClose:)`,
initialiseur SANS `onMore`) n'a pas été câblé — Feed seulement, d'où `PARTIAL` plutôt que
`COMPLETE_PARITY_CANDIDATE`.

### 2026-08-18 — Animems (P2) — Reclassification de l'export GIF en `DEAD_CODE`
**Commit(s) :** `1892ae8` (commentaires seulement, aucune fonctionnalité ajoutée)
**Run CI :** [32165179496](https://github.com/SalimMedir/TiinverSwift/actions/runs/32165179496) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `MISSING` confirmé
**Statut APRÈS :** `DEAD_CODE` — aucun travail requis, la fonctionnalité n'existe pas dans le flux
Android réel non plus
**Preuve du changement de statut :** `grep "AnimatedGifEncoder\|GIFView"` exhaustif sur tout le
module `engine` — ces 2 classes (1282+ lignes) ne sont référencées par AUCUN appelant en dehors
d'elles-mêmes. Lu `AnimemesCompound.java:2960-2966` (`showSaveDialog()`, le VRAI menu de sauvegarde
réellement exercé, `AnimemesActionSheet.ActionListener`) : seulement 3 actions exposées
(`onPublishAnimation`→vidéo, `onSaveTemplate`, `onPublishTemplate`) — aucune action GIF. Même
classe de code mort que `RechercheTiinver2.java`/`TrimBenchActivity.java`/`FullscreenActivity.java`
déjà confirmés cette session. **Décision explicite : ne PAS construire cet export côté iOS** —
inventer une fonctionnalité qu'Android lui-même n'expose jamais à l'utilisateur irait à l'encontre
de la mission de parité. Commentaires mis à jour dans `AnimemesEditorState.swift`/
`MIGRATION_PARITY_AUDIT_V2.md` pour refléter la classification correcte plutôt que de laisser un
gap fantôme dans le décompte.

### 2026-08-18 — Chat/Messaging (P2) — Implémentation de NewMessage (recherche téléphone/email)
**Commit(s) :** `2e48d79`
**Run CI :** [32165684226](https://github.com/SalimMedir/TiinverSwift/actions/runs/32165684226) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `MISSING` confirmé
**Statut APRÈS :** `BUILD_VALIDATED` — commit `2e48d79` — CI SUCCESS — test fonctionnel réel toujours requis
**Preuve du changement de statut :** Lu `roster/NewMessage.java` (196 lignes, entier).
`ContactsRepository.lookupByPhoneOrEmail` ajouté (`POST isPhoneOrEmailExiste {phoneOrEmail}`,
réponse `{user: {...}}` — objet unique, malgré le nom Android `User[] metas` qui enveloppe
artificiellement `"["+meta+"]"` pour réutiliser un décodeur tableau existant). Nouveau
`NewMessageView.swift`, câblé aux 2 liens "+ Nouveau message" de `RosterListView` (footer + état
vide), qui pointaient auparavant vers `ContactPickerView` en attendant. **Écart assumé documenté** :
Android insère le premier message directement en local (`ContentValues`/`ContentProvider`) SANS
appel réseau visible dans ce fichier précis (dépend probablement d'une synchronisation locale en
tâche de fond, `MyBackgroundTask`, déjà hors périmètre ailleurs dans ce portage) — reproduire
l'insertion locale seule aurait laissé le message jamais livré ; à la place, le texte tapé est
transmis en pré-remplissage à `ChatView` (nouveau paramètre `initialInputText`), qui l'envoie
réellement via son pipeline `sendText()` déjà fonctionnel.

### 2026-08-18 — Chat/Messaging (P2) — Implémentation de l'assistant IA Gemini
**Commit(s) :** `3df3d7a`
**Run CI :** [32177241332](https://github.com/SalimMedir/TiinverSwift/actions/runs/32177241332) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `PARTIAL` probable (seule la couche de stockage portée)
**Statut APRÈS :** `BUILD_VALIDATED` — commit `3df3d7a` — CI SUCCESS — mode suppression
d'arrière-plan explicitement non porté, test fonctionnel réel toujours requis
**Preuve du changement de statut :** Lu `ai/TiinverGeminiAIChat.java` (823 lignes, entier).
**Correction d'audit importante** : le fichier voisin `ai/TiinverAIChat.java` (avec
`OPENAI_API_KEY` en dur, trouvé en cherchant les clés API dans le module `ai`) N'EST PAS le fichier
réellement exercé — `grep "TiinverAIChat.class"` = 0 appelant, alors que `TiinverGeminiAIChat.class`
a 3 vrais appelants (`Roster.java:443`, `MonetizationActivity.java:109`, `MainFragment.java:1456`).
`TiinverGeminiAIChat` proxifie tout via le backend Tiinver (`POST ai/chat`/`POST ai/image/generate`)
— confirmé AUCUNE clé API Google/Gemini côté client. Nouveaux `AIChatModels.swift`/
`AIChatRepository.swift`/`AIChatViewModel.swift`/`AIChatView.swift` : chat texte avec compteur de
quota (`used`/`limit`/`remaining`), génération d'image (jointe optionnelle), dialogue solde
insuffisant (`IMAGE_COST = 50` pièces, pré-vérification locale puis le serveur tranche, fidèle à
`checkCoinsAndGenerateImage`), persistance via `AiConversationRepository` déjà porté (purge des
messages expirés à 3 jours au chargement). **Non porté, documenté** : mode "supprimer
l'arrière-plan" (post-traitement local de l'image générée, `RemoveBackground.
removeBackgroundAdvanced`/`removeBackgroundWithMLKit`) — nécessiterait un pipeline Vision/CoreML
dédié, le cœur texte+image reste pleinement fonctionnel sans lui. Câblé depuis la toolbar
`RosterListView` (icône sparkles), même point d'entrée logique que les 3 confirmés côté Android.

### 2026-08-18 — Discover/Certification (P2) — Vérification champ par champ + correctif `expire_at`
**Commit(s) :** `a2952b3`
**Run CI :** [32177565133](https://github.com/SalimMedir/TiinverSwift/actions/runs/32177565133) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** `CODE_PRESENT_UNVERIFIED` — correspondance non vérifiée en détail
**Statut APRÈS :** `COMPLETE_PARITY_CANDIDATE`
**Preuve du changement de statut :** Lu les 9 fichiers du module `ui/certification` (351+229 lignes
au total). Confirmé `CertificationRequestFragment.java` `DEAD_CODE` (0 appelant — le vrai onglet
"dashboard" de `CertificationActivity` est `CertificationState.java`, jamais lu par les passes
précédentes à cause du nom proche). Comparé `CertificationState.java` (4 champs affichés :
niveau/statut/date de demande/date d'expiration) champ par champ contre `CertificationView.swift` —
trouvé `expire_at` décodé (`CertificationStatus.expire_at`) mais jamais rendu à l'écran, corrigé.
Confirmé `btnRenew`/`btnCancel` non câblés côté Android lui-même (aucun `setOnClickListener` dans
tout le fichier) — absence fidèle côté iOS, pas un gap. Endpoints `certification/request`
(multipart)/`certification/{userId}` déjà fidèles depuis GAP-004 (session antérieure), RAS.

### 2026-08-18 — Wallet (P2) — Résolution des 5 écrans Wallet secondaires
**Commit(s) :** `c6a9f56`
**Run CI :** [32177918727](https://github.com/SalimMedir/TiinverSwift/actions/runs/32177918727) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** correspondance non déterminée pour les 5 écrans
**Statut APRÈS :** 4/5 confirmés SUPERSEDED (StoreKit 2, aucun travail requis) ; 1/5
(`TransactionTutorialActivity`) `BUILD_VALIDATED` — commit `c6a9f56` — CI SUCCESS
**Preuve du changement de statut :** Lu les 5 fichiers Android (441 lignes au total).
`SelectAmountActivity`/`RechargeCoinsActvity`/`PeerToPeerActivity` (vide, atteint uniquement depuis
`RechargeCoinsActvity`) font tous partie du flux d'achat manuel déjà remplacé par StoreKit 2
(`CoinStoreManager.swift`, décision de conformité App Store 3.1.1/3.1.5 documentée lors d'une
session antérieure). `UseBankCardFragment` utilise l'API Google Pay (`com.google.android.gms.
wallet`), exclusive à Android, aucun équivalent iOS pertinent (StoreKit couvre déjà le même besoin).
Seul `TransactionTutorialActivity` (2 vidéos YouTube retrait/achat, IDs `C_F2V6qTaGc`/
`fYxdI6DVlac`, atteint aussi depuis `WithdrawActivity` — TOUJOURS actif, PAS remplacé) était un vrai
gap. Implémenté `TransactionTutorialView.swift` (lecteur `WKWebView`/`embed` YouTube, même approche
que `PoliticaDemandView.swift`), câblé en icône "?" toolbar depuis `WithdrawView.swift` ET
`BuyCoinsView.swift` (son analogue le plus proche de `SelectAmountActivity`/`PurchaseActivity`).

### 2026-08-18 — Chat/Messaging (P2) — Renommage de groupe + filtre membres + correctif fraîcheur description
**Commit(s) :** `91adca3`
**Run CI :** [32178357069](https://github.com/SalimMedir/TiinverSwift/actions/runs/32178357069) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** correspondance non vérifiée pour 3 fichiers Android
**Statut APRÈS :** `COMPLETE_PARITY_CANDIDATE` (inchangé, gap comblé DANS la même feature) —
`BUILD_VALIDATED` — commit `91adca3` — CI SUCCESS
**Preuve du changement de statut :** Lu `AddGroupDescriptionActivity.java` (déjà couvert, RAS),
`ChangeGroupTopicActivity.java` (168 lignes) et `FilterGroupMemberList.java` (410 lignes) en entier.
**Vrai gap trouvé** : `ChangeGroupTopicActivity` (renommage du groupe, `POST updategroup
column="name"`) n'avait AUCUNE UI côté iOS — `groupName` était un `let` immuable dans
`GroupDetailView.swift`. Implémenté : `GroupRepository.updateName`, bouton "Modifier le nom" (admin
seulement, même emplacement que "Modifier la description"), feuille de saisie, message système
local `verb="groupNameChanged"` (même motif que `groupDescriptionChanged` déjà en place).
**Corrigé au passage** (même classe de bug, trouvée en comparant) : `groupDescription` était aussi
`let` — l'en-tête restait figé sur l'ancienne description après une modification réussie ; converti
en `@State`, mis à jour après succès. `FilterGroupMemberList` confirmé fonctionnellement équivalent
au flux membres déjà en place (même simplification "endpoint direct" déjà documentée), seule
différence réelle = un filtre de recherche (`.searchable`), ajouté.

### 2026-08-18 — Navigation/Auth (P2) — Reclassification de 3 fichiers en DEAD_CODE, vérification SplashActivity
**Commit(s) :** documentation uniquement, aucun changement de code (rien à porter)
**Run CI :** N/A
**Statut AVANT (audit V2) :** `FacebookActivity.java` `MISSING probable`, `DebutWenack2.java` 🟡 à
investiguer, `SplashActivity.java`/`SplashActivity2.java` groupés en une seule ligne 🟡
**Statut APRÈS :** les 3 confirmés `DEAD_CODE` ; `SplashActivity.java` (le seul vrai lanceur)
confirmé ✅ fidèlement porté
**Preuve du changement de statut :** Vérifié `AndroidManifest.xml` — SEULE `SplashActivity`
(PAS `SplashActivity2`) porte `category.LAUNCHER`. `SplashActivity2.java` (261 lignes) et
`DebutWenack2.java` (359 lignes, commentaire de tête trompeur "Start the MainActivity") confirmés
0 appelant chacun dans tout le projet Android (`grep` exhaustif) — vrai code mort, pas des variantes
alternatives actives. Lu `SplashActivity.java` en entier (265 lignes) et comparé à
`RootRouterView.swift` : routage fidèle (`expire/version → UpdateAppView`, `SessionManager.getUser()
→ Home sinon Login`), y compris une divergence produit délibérée déjà documentée (comparaison de
version retirée sur demande explicite du propriétaire du projet — `version_code` Remote Config
partagé avec Android en production, jamais pensé pour un `CFBundleVersion` iOS indépendant).
`FacebookActivity.java` (23 lignes) : inflate un layout statique, AUCUNE logique, `LoginButton`/
`LoginManager` (vraie API Facebook Login) introuvables dans tout le projet, 0 appelant — confirmé
mort, `FacebookSdk.sdkInitialize()` dans `MainActivity.java` est un reliquat jamais suivi d'un
vrai flux.

### 2026-08-18 — Search (P2) — Vérification de la valeur exacte du debounce
**Commit(s) :** (à committer avec ce lot — commentaire seulement)
**Run CI :** à dispatcher après commit
**Statut AVANT (audit V2) :** 🟡 `CODE_PRESENT_UNVERIFIED` — valeur exacte du debounce non lue
**Statut APRÈS :** ✅ vérifié
**Preuve du changement de statut :** `RechercheTiinver.java:85` (`DEBOUNCE_DELAY_MS = 300`) et
`:399-402` (`query.length() >= 2` → recherche complète, sinon suggestions) comparés à
`SearchView.swift:95,97` (`Task.sleep(nanoseconds: 300_000_000)`, `newValue.count < 2`) — identiques
sur les deux points. Commentaire mis à jour pour refléter la vérification (aucun changement
fonctionnel).

### 2026-08-18 — Profile (P2) — Vérification édition profil + correctif corruption birthday/gender
**Commit(s) :** `bf8100c`
**Run CI :** [32179186193](https://github.com/SalimMedir/TiinverSwift/actions/runs/32179186193) — `status: completed`, `conclusion: success`
**Statut AVANT (audit V2) :** 🟡 `CODE_PRESENT_UNVERIFIED`
**Statut APRÈS :** `COMPLETE_PARITY_CANDIDATE`
**Preuve du changement de statut :** Lu `EditProfile.java` (190 lignes) et
`EditPersonalInformation.java` (235 lignes) en entier, comparé champ par champ à
`EditProfileView.swift`/`EditPersonalInformationView.swift` — les 9 champs/colonnes REST
correspondent exactement, y compris l'asymétrie réelle `work`/`school` (local) vs `work_At`/
`school_At` (serveur), déjà documentée et confirmée exacte. **Bug de corruption de données trouvé
et corrigé** : `EditPersonalInformation.java` N'A AUCUNE logique de pré-remplissage (contrairement
à `EditProfile.java` voisin, qui pré-remplit via `onResume()`+`ContentProvider`) — chaque champ
Android est une `TextView` vide par défaut, et `UpdateProfileData()` n'envoie que les champs
non-vides. La version Swift reproduisait cette garde pour les 5 champs `String` (`""` = vide
représentable), MAIS PAS pour `birthday`(`Date`)/`gender`(`String` défaut `"M"`) — types Swift ne
pouvant pas nativement représenter "non touché", ces 2 champs étaient donc envoyés À CHAQUE
sauvegarde, écrasant silencieusement la date de naissance réelle par la date du jour et le genre
réel par "M" dès qu'un utilisateur modifiait n'importe quel autre champ de cet écran. Corrigé en
rendant `birthday`/`gender` `Optional` (`nil` = non touché), envoyés seulement si explicitement
renseignés — fidèle à la sémantique "TextView vide" d'Android sur CES 2 champs précis.
