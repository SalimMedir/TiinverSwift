# MIGRATION_PARITY_PROGRESS_V7.md — Journal du cycle d'audit V7

## 2026-08-28 — Phase A : audit complet, aucune correction

### Contexte de départ

Cycle V7 lancé directement après la clôture complète du cycle V6 (26/26 findings corrigés, tous
poussés sur `main`, CI verte confirmée — voir `MIGRATION_PARITY_AUDIT_V6.md`/`CLAUDE_CONTINUATION.md`
section Phase F). Consigne explicite de l'utilisateur pour ce nouveau cycle : **audit uniquement,
aucune modification de code, aucun refactor, aucun changement de comportement** — seuls les documents
d'audit V7 pouvaient être créés/modifiés pendant cette phase.

### Préparation (avant tout lancement d'agent)

Lecture de `CLAUDE_CONTINUATION.md` (section Phase F + Phase E), puis extraction compacte (via grep
ciblé plutôt que lecture intégrale, vu la taille des documents — `MIGRATION_PARITY_AUDIT_V5.md` fait
3813 lignes, `MIGRATION_AUDIT.md` 2335, `MIGRATION_PARITY_AUDIT_V4.md` 2422) de l'inventaire complet
des cycles précédents :
- **V5** : 99 findings (V5-F-001 à 099), extraction ID+DOMAINE+STATUT confirmant ~95% `BUILD_VALIDATED`,
  le reste `DUPLICATE`/`IOS_INTENTIONAL_DIFFERENCE`/`DIFFÉRÉ`.
- **V6** : 26 findings, tous traités ce même jour dans la session précédente (19 `BUILD_VALIDATED`
  avec CI run 33156167515 confirmé, 3 `DIFFÉRÉ`, 1 `IOS_INTENTIONAL_DIFFERENCE`).
- **PHYSICAL_DEVICE_VALIDATION_V5.md** : 8 bugs de test physique, tous `CODE_COMPLETE`/fusionnés.
- **V2/V3/V4** : V2 entièrement résolu (0 finding ouvert). V3 (54 findings) et V4 (75 findings)
  quasi-entièrement résolus, avec une poignée d'items réellement encore ouverts et
  non-corrigibles-par-code-seul identifiés et notés pour ne pas être re-signalés par erreur pendant
  le V7 : `V4-F-003` (pas de vrais Universal Links, nécessite un AASA hébergé + entitlement),
  `V4-F-004` (pas d'extension de partage iOS, nécessite un nouveau target Xcode), `V3-F-140`
  (vérification serveur StoreKit 2 absente, endpoint backend `storekit/verify-purchase` inexistant).
- Recherche exhaustive de tous les documents de migration/audit dans les deux dépôts (`find`
  `-iname "*migration*"`/`"*audit*"`/`"*parity*"`) — confirmé qu'aucun autre document pertinent
  n'existait au-delà de ceux déjà connus, côté iOS comme côté Android (`AUDIT_ANIMEMES_IOS_
  MIGRATION.md`, `TIINVER_IOS_PORT_ANALYSIS.md`, `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` côté Android —
  documents de référence du port initial, déjà pleinement digérés par les cycles précédents).

### Dispatch des agents

10 agents de recherche `Explore` (read-only) lancés en parallèle, chacun avec :
- Le périmètre exact de son domaine (checklist détaillée fournie par l'utilisateur).
- La liste précise des findings V5/V6 déjà couverts dans son domaine (pour éviter toute redite),
  avec instruction explicite de grep les documents précédents avant de rédiger quoi que ce soit.
- La méthode en 9 étapes (Android→iOS→flux complet→modèles de données→conditions→callbacks→
  erreurs→arrière-plan→classification) et le format de sortie standardisé (bloc fenced identique au
  format V6, avec ajout d'un champ NIVEAU DE CONFIANCE et VALIDATION explicite
  PHYSICAL_VALIDATION_REQUIRED/CODE_VERIFIABLE/CI_VERIFIABLE demandés spécifiquement pour V7).

Domaines : Animems Éditeur, Animems Timeline/Export/Publication (2 lots séparés vu la taille du
domaine, priorité maximale de l'utilisateur), ChatGroup, Search, Promotion/Boost, Video Statistics
(avec instruction explicite de re-vérifier indépendamment le pipeline watch-time construit lors de la
session V6 précédente, jamais audité par un tiers), Feed/Home/Profile, Notifications+Auth/Compte/
Sécurité (combinés, 2 domaines de portée modérée), Network/Socket.IO/Concurrence (transversal),
Persistance/Cache+UI/UX/Navigation (combinés, transversaux).

### Incidents pendant l'exécution

- **Agent Network/Socket.IO/Concurrence** : a échoué 3 fois avant de réussir au 4ᵉ lancement — 1
  limite de session utilisateur atteinte pendant l'exécution (résolue automatiquement après
  réinitialisation, message utilisateur "J'ai atteint ma limite d'utilisation... Veuillez continuer"
  traité comme confirmation de reprise), 1 blocage de flux ("stalled: no progress for 600s"), 1 perte
  de connexion infrastructure ("Connection lost mid-response"). Relancé avec un budget resserré
  (~25-30 appels d'outils, priorité à UN sweep exhaustif bien fait — les 187 sites `Task {}` — plutôt
  qu'à plusieurs findings superficiels) — même stratégie que celle qui avait débloqué l'agent
  transversal équivalent du cycle V6. Succès au 4ᵉ essai, rapport complet et de bonne qualité.
- **Interruption de process entre la 8ᵉ et la 9ᵉ notification d'agent** : le processus Claude Code a
  été redémarré par l'environnement pendant l'attente des dernières notifications (cause exacte non
  déterminée — pas une action de l'utilisateur). Reprise sans perte de données : les résultats des 4
  agents déjà complétés au moment de l'interruption (Feed/Home/Profile, Video Statistics,
  Notifications+Auth, Persistance+UI/UX) avaient déjà été sauvegardés dans des fichiers scratch
  individuels (`scratchpad/v7/*.md`) au fur et à mesure de leur réception — confirmé intact par
  relecture avant de poursuivre. Seul l'agent Network/Concurrence restait à relancer après reprise.

### Résultat

**27 findings** produits (V7-F-001 à V7-F-027) — voir `MIGRATION_PARITY_AUDIT_V7.md` pour le détail
complet. Répartition : 1 P0 (sécurité), 3 P1, 15 P2, 8 P3. 3 `IOS_INTENTIONAL_DIFFERENCE` confirmées
(aucune action requise), 1 `SHARED_BACKEND_ISSUE` (bug Android fidèlement reproduit, candidat
légitime à une correction iOS indépendante — décision produit nécessaire).

**Aucun finding V5/V6 recréé** — chaque agent a explicitement vérifié et cité les findings déjà
couverts dans son domaine avant de rédiger quoi que ce soit de nouveau ; les rapports individuels
contiennent chacun une section "vérifié, sans divergence significative"/"déjà couvert" listant ce qui
a été confirmé correct sans donner lieu à un nouveau finding.

### Constat le plus significatif de ce cycle

Le passage d'un audit de 6ᵉ génération (V6, encore riche en fonctionnalités *totalement absentes*,
ex. V6-F-019 pipeline watch-time) à un audit de 7ᵉ génération trouvant majoritairement des **lacunes
de câblage fines** dans du code déjà largement porté (garde de réentrance oubliée sur UN SEUL des N
call-sites d'un pattern par ailleurs correct, ordre de callbacks SwiftUI non garanti là où Android a
un lecteur unique séquentiel, asymétrie entre chemin "aperçu" et chemin "export") — signe que le
projet mûrit et que les cycles suivants devront probablement se concentrer davantage sur la
validation physique (device réel) que sur l'audit de code statique, plusieurs findings V7 (notamment
V7-F-015/016, le pipeline watch-time) ne pouvant être définitivement tranchés que par instrumentation
sur appareil réel.

### Findings les plus critiques identifiés (résumé, voir section 6 de l'audit pour le détail)

1. V7-F-022 (P0, sécurité) — apiKey en clair dans UserDefaults inconditionnellement.
2. V7-F-015 (P1) — watch-time jamais mis en pause en arrière-plan, surcomptage direct des stats créateur.
3. V7-F-004 (P1) — recadrage timeline texte/sticker ignoré à l'export MP4 Animems.
4. V7-F-007 (P1) — sortie de groupe sans écho système local, roster jamais mis à jour.
5. V7-F-016 (P2, impact potentiel maximal) — ordre onAppear/onDisappear SwiftUI non garanti, pourrait
   zéroer le watch-time du cas d'usage le plus fréquent (swipe vidéo→vidéo) — à valider en priorité.

### Prochaine étape (obsolète, voir Phase B ci-dessous)

~~Décision de l'utilisateur sur la phase de correction B — quels findings traiter, dans quel ordre.~~
L'utilisateur a fourni l'ordre de priorité complet immédiatement après ce rapport — voir Phase B.

---

## 2026-08-28 — Phase B : correction complète des 27 findings V7

Consigne explicite de l'utilisateur : traiter tout le backlog V7 en une seule campagne, sans
s'arrêter demander quel finding traiter, jusqu'à ce qu'il ne reste plus aucun finding corrigeable en
code. Ordre imposé : P0/P1 d'abord (V7-F-022, 015, 004, 007), puis tous les P2/P3 listés
explicitement (V7-F-002/003/005/006/008/009/012/013/016/017/018/019/020/021/023/024/025/026/027).
V7-F-001 n'était pas dans la liste explicite de l'utilisateur (probable oubli, le finding P2 existe
bel et bien dans l'audit et est clairement corrigible par code) — traité quand même dans le lot
Animems, conformément à l'objectif final explicite ("traiter les 27 findings V7, sauf ceux qui
nécessitent réellement une infrastructure ou un chantier explicitement différé").

### Lot 1 — P0/P1 (commits `dc8c21e`, `bf7f233`, `62c4f16`)

- **V7-F-022** (P0, sécurité) — `KeychainStore.saveAPIKey` écrivait `UserDefaults` de façon
  inconditionnelle, avant même la tentative Keychain. Corrigé : repli posé APRÈS échec RÉEL de
  `SecItemAdd` uniquement, `loadAPIKey()` migre silencieusement toute valeur de repli pré-existante.
  **Découverte supplémentaire pendant la correction** (pas dans l'audit initial) : une SECONDE copie
  en clair de l'apiKey était écrite dans `AccountEntity` (Core Data) par `AuthSessionPersistence.
  persist` — jamais relue nulle part (grep exhaustif), écriture supprimée.
- **V7-F-015** (P1) — watch-time jamais mis en pause en arrière-plan. `FeedDetailPagerView` observe
  désormais `scenePhase` : flush+record sur toute transition hors `.active`, reprise au retour.
- **V7-F-016** (P2, traité dans le même lot car même domaine/mêmes fichiers) — ordre `onAppear`/
  `onDisappear` SwiftUI non garanti entre 2 cellules vidéo distinctes. Consolidé dans le point
  d'entrée déterministe unique déjà utilisé pour les photos (`.onChange(of: currentIndex)` →
  `handlePageChanged`) : capture de la position de sortie AVANT tout flush, reprise uniforme
  photo/vidéo. Fermeture de l'ancien câblage `onVideoPlaybackActiveChanged` (devenu mort).
- **V7-F-017**/**V7-F-018** (P3, même lot) — `RecordQueue` (acteur, chaînage de `Task`) sérialise
  `ViewEventRepository.record()` bout en bout ; `ViewEventSyncService.sync()` désormais aussi
  déclenchée depuis `RootRouterView.onAppear` (lancement à froid, pas seulement `.onChange(of:
  scenePhase)` qui ne se déclenche jamais pour l'état initial).
- **V7-F-004** (P1) — garde `startAt`/`endAt` manquante pour les calques texte/sticker dans
  `AnimemesExporter.render(frame:into:)`, ajoutée en miroir exact du cas bitmap/shape.
- **V7-F-007** (P1) — `GroupDetailView.leaveGroup()` était la seule mutation de groupe du fichier
  sans `insertSystemMessage` — ajouté (`verb="leftGroup"`, port fidèle de `GroupDetailActivity.
  exit()`).

**CI run [33193844334](https://github.com/SalimMedir/TiinverSwift/actions/runs/33193844334) —
`completed`/`success`** (contre le code réellement poussé, commit `62c4f16`).

### Lot 2 — Animems P2/P3 (commit `6b982d3`)

- **V7-F-001** — `MovementControllerTransformer`/panneau "Contrôle" : capture automatique de
  keyframe absente au relâchement du curseur (contrairement au drag direct). Ajouté
  `movementControllerEndTracking()`, appelé depuis `onEditingChanged(false)` et
  `closeMovementController()`.
- **V7-F-002** — les 4 panneaux de zone timeline (masque/bezier/Contrôle/chronologie) ne se
  réinitialisaient jamais mutuellement. Chaque bouton d'ouverture ferme désormais explicitement les
  3 autres.
- **V7-F-003** — plage du curseur d'angle alignée sur `90...190` (au lieu de `0...180`), fidèle au
  `SeekBar` Android réel (`max=100`, décalage `+90`).
- **V7-F-005** — export Animems enveloppé dans `beginBackgroundTask`/`endBackgroundTask`, même
  pattern que `PublishComposeView.publish()` déjà dans ce dépôt.
- **V7-F-006** — `state.exportError` câblé à une `.alert`, miroir de `publishConversionError` 4
  lignes plus bas dans le même fichier.

### Lot 3 — ChatGroup (commit `882dc44`)

- **V7-F-008** — `GroupCreationView.create()` (membres initiaux) ET `AddGroupMemberView.submit()`
  (ajout après coup) n'inséraient aucun message système "X a ajouté Y". `GroupCreationView` insère
  désormais un message par membre (même motif inline que son propre message "createGroup").
  `AddGroupMemberView` n'a délibérément aucune métadonnée de groupe (nom/jeton/profil) — son
  callback `onAdded` transmet maintenant les membres ajoutés à `GroupDetailView`, qui possède déjà
  `insertSystemMessage` et la métadonnée nécessaire.
- **V7-F-009** — **DIFFÉRÉ**, pas corrigé. Le commentaire existant affirme que "pivate" est la
  valeur RÉELLEMENT attendue par le serveur (fait, pas hypothèse) — invérifiable sans accès
  backend ; changer sans confirmation risquerait de casser un flux de création de groupe
  fonctionnel pour un gain incertain.

### Lot 4 — Promotion/Boost (commit `9bff2fc`)

- **V7-F-012** — objectif publicitaire par défaut corrigé de "likes" à "views" (le vrai défaut
  Android, `radioView` pré-coché).
- **V7-F-013** — borne basse du curseur d'âge minimum relevée de 13 à 18 ans, fidèle au
  `RangeSlider` Android (`valueFrom="18"`).

### Lot 5 — Notifications (commit `178770a`)

- **V7-F-019** — vignette de notification : remplacement de la 3ᵉ logique de priorité CDN
  indépendante par `reconstructedPost?.thumbnailURL` (logique centrale déjà correcte et validée
  physiquement, BUG 1 du 2026-08-27).
- **V7-F-020** — `willPresent` ne montre plus de bannière pour une notification sans
  `categoryIdentifier` reconnu (candidate "notification-only" générique), fidèle au no-op réel
  d'Android pour ce cas précis.
- **V7-F-021** — nouveau champ Core Data `NotiEntity.systemNotificationShown` (schéma
  `TiinverNotificationsModel.xcdatamodeld` modifié, attribut optionnel avec valeur par défaut —
  migration légère automatique, pas de `NSPersistentStoreDescription` dédié nécessaire pour ce
  changement précis) gate la re-présentation d'une notification système déjà montrée.

### Lot 6 — UI/UX, Boost, Statistiques transversal (commit `9c2fdbb`)

- **V7-F-025** — bouton "Fermer" de `CommentsView` câblé à `@Environment(\.dismiss)`.
- **V7-F-026** — `CreateBoostView.scheduleCountrySearch` re-vérifie `Task.isCancelled` après
  l'appel réseau, pas seulement avant, même correctif déjà appliqué ailleurs pour ce motif
  (`ChatSearchView`/`NewMessageView`/`SearchView`).
- **V7-F-027** — `ViewEventSyncService` passé `@MainActor` avec un flag `isSyncing`, même motif que
  `NotificationCenterViewModel.isSyncing` déjà établi dans ce projet.

### Lot 7 — Persistance (commit `37a8b69`)

- **V7-F-023** — `LocalDataPurger.purgeAll()` purge désormais aussi `AiConversationRepository`
  (conversations IA) et `ViewEventRepository` (événements de visionnage en attente), scopés par
  `userId`, capturé avant tout appel purge (les deux appelants clarent la session APRÈS
  `purgeAll()`). Va au-delà de la stricte parité Android (même lacune côté Android, non corrigée
  là-bas) — dans le sens de l'intention affichée par l'utilisateur en se déconnectant/supprimant
  son compte.
- **V7-F-024** — nouveau `CoreDataStackLoading.swift`, filet de sécurité partagé par les 3 piles
  Core Data : sur échec de `loadPersistentStores`, supprime le store fautif et retente une fois
  avant d'abandonner (approxime `fallbackToDestructiveMigration()` d'Android), remplace un
  `fatalError` inconditionnel.

### Lot final — CI de clôture

Poussé (commit `37a8b69`), CI relancée : run
[33195329910](https://github.com/SalimMedir/TiinverSwift/actions/runs/33195329910) — **`completed`/
`success`**, confirmé contre le code réellement poussé (tous les 9 commits Phase B inclus). Tous les
findings `CODE_COMPLETE, CI_PENDING` promus `BUILD_VALIDATED` dans `MIGRATION_PARITY_AUDIT_V7.md`.

### Bilan Phase B

22 findings corrigés en code, tous `BUILD_VALIDATED` (CI run 33195329910, confirmée contre le code
réellement poussé — pas seulement "le code semble correct"), 3 `IOS_INTENTIONAL_DIFFERENCE`
(V7-F-010/011/014, déjà correctement traitées à l'audit, aucune action), 1 `DIFFÉRÉ` (V7-F-009).
Aucun test physique/screenshot intermédiaire — uniquement compilation/lecture de code, conformément
à la consigne explicite de conserver les ressources de build.

**Ce qui restera à tester physiquement** (au-delà de la compilation) : tous les correctifs
comportementaux ne peuvent être définitivement validés que sur device réel — en particulier
V7-F-016 (ordre onAppear/onDisappear, gravité potentielle la plus élevée du lot), V7-F-015 (flush au
passage en arrière-plan), V7-F-001/002/003 (gestes du panneau Contrôle), V7-F-004 (rendu du MP4
exporté), V7-F-005 (survie de l'export en arrière-plan), V7-F-009 restera `DIFFÉRÉ` tant qu'une
vérification backend n'est pas possible.
