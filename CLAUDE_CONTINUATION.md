# CLAUDE_CONTINUATION.md — Mémoire persistante entre sessions Claude Code

**Ce fichier est la mémoire de continuité du portage Android → iOS de Tiinver.**
Une nouvelle session doit le lire EN PRIORITÉ, mais le CROISER avec `MIGRATION_AUDIT.md` (audit
détaillé, cartographie complète), `MIGRATION_PROGRESS.md` (journal chronologique complet, ~3500
lignes) et l'état réel du code + `git log` — ne jamais faire confiance aveuglément à un seul
document. Voir section 15 du prompt-cadre de ce projet : plusieurs sessions travaillent
successivement sur le même dépôt, ne jamais supposer être seul à l'avoir modifié.

---

## 0. BUILD CI — À LIRE EN PREMIER

**BUILD CI VALIDÉ :** Oui (GitHub Actions uniquement — voir stratégie double-CI ci-dessous,
Codemagic en attente d'un déclenchement manuel par l'utilisateur, jamais rapporté à ce jour)
**Build :** GitHub Actions run `31924498415` (workflow `ios-build.yml`)
**Commit :** `ef3a34b` ("feat(galerie): implement video trim (MediaTrim) before publish" — dernier
commit de la session, voir points 9-10 ci-dessous)
**Date :** 2026-08-16
**Résultat :** `** BUILD SUCCEEDED **`. Confirmé via l'API GitHub Actions (`status: completed,
conclusion: success`), pas seulement supposé.
**Historique complet des runs depuis le dernier point de reprise** (pour ne pas confondre) :
1. `31912698274` (commit `f2460f2`, Chat+Galerie+Animems minimal construits) — SUCCESS (session
   précédente, voir section 0ter).
2. `31916776657` (commit `d19e372`, gestes Animems réels + fix WebRTC glare + parité Galerie) —
   SUCCESS.
3. `31915767632` (commit `ab36462`, native ads câblées dans le pager Feed) — SUCCESS.
4. `31916776657`... voir plus haut, doublon d'affichage — le run suivant (commit `3f1c22d`,
   timeline/keyframes/lecture/masques Animems câblés pour la première fois) — **ÉCHEC** :
   `ProfileRepository()` appelé directement (`init` privé, singleton `.shared` requis) dans
   `HashtagFeedView.swift`/`SearchView.swift` (fonctionnalité Search du même lot).
5. `31917572782` (commit `b90ae3d`, fix ProfileRepository + panneau/geste masque câblés) —
   **ÉCHEC** : `error: conflicting arguments to generic parameter 'T' ('AnyGesture<(some
   Gesture).Value>' vs. 'AnyGesture<(some Gesture).Value>')` — deux propriétés `some Gesture`
   distinctes (`combinedGesture`/`maskEditGesture`) choisies par ternaire ne s'unifient PAS même
   structurellement identiques.
6. `31918239357` (commit `fd92885`, tentative de fix via type explicite `AnyGesture<ObjectGestureValue>`
   partagé + permission micro avant appel) — **ÉCHEC** : `error: type of expression is ambiguous
   without a type annotation` sur la construction imbriquée `AnyGesture(SimultaneousGesture(...))`.
7. `31918549314` (commit `0fa0de8`, tentative de fix via bindings `let` explicitement typés) —
   **ÉCHEC** : log non entièrement récupéré avant la décision de changer d'approche (téléchargement
   du log `xcodebuild` via l'API GitHub Actions systématiquement lent/tronqué pour ce projet — log
   complet ~25-27k lignes, dépendances Firebase compilées avant la cible propre, `curl --max-time
   590` en arrière-plan nécessaire, jamais en une seule commande synchrone).
8. `31923679579` (commit `e4b347a`, gestes fusionnés en UN SEUL jeu avec bascule `isMaskEditMode` à
   l'exécution plutôt que deux graphes de gestes différemment typés) — **SUCCESS.** Lot Animems
   timeline/keyframes/masques enfin confirmé compilé après 4 tentatives.
9. `31924209161` (commit `70692d5`, sauvegarde image statique pour composition Animems non animée)
   — **SUCCESS.**
10. `31924498415` (commit `ef3a34b`, recadrage temporel vidéo `MediaTrim` câblé dans la Galerie) —
    **SUCCESS.** Dernier run connu.

### CI VALIDATION — format demandé par l'utilisateur pour chaque commit important

**Commit :** `f2460f2` (englobe aussi `3dc83d3` Chat et `1aab36e` Galerie, même run)
**GitHub Actions :** Build ID `31912698274` — Result **SUCCESS**
**Codemagic :** Build ID — (aucun, déclenchement manuel par l'utilisateur, en attente de retour —
toujours vrai pour TOUS les commits du jour, aucun build Codemagic n'a encore été rapporté)
**Double validation :** NO (GitHub seul pour l'instant, sur les 2 derniers commits importants)
**Erreurs GitHub :** 0
**Erreurs Codemagic :** N/A (pas encore lancé)
**Prochaine tâche :** voir section 10.

### GAP CI — corrections Appetize non encore testées fonctionnellement

**Compilation Swift atteinte :** OUI (run `31911325017`, SUCCESS)
**Xcode :** 16.2 (sélection dynamique, dernière version disponible sur le runner)
**Runner :** `macos-14-arm64`, image GitHub Actions `20260629.0180.1`
**Erreur éventuelle :** aucune
**Test fonctionnel réel (Appetize) après ces corrections :** **NON EFFECTUÉ** — rappel explicite de
l'utilisateur, règle absolue de cette mission : un build vert signifie UNIQUEMENT que le code
compile, jamais que Home/Profile/Search fonctionnent réellement comme Android. Voir
`MIGRATION_AUDIT.md`, section "APPETIZE FUNCTIONAL TEST — 2026-08-15" pour le détail complet
problème par problème.

**Règle permanente adoptée cette session (explicite, utilisateur)** : à partir de maintenant,
chaque modification importante doit être testée sur le MÊME commit par les deux CI. Aucun
credential Codemagic disponible dans cet environnement (contrairement à GitHub, où Git Credential
Manager est déjà configuré et fonctionnel, confirmé par `git ls-remote` immédiat) —
**l'utilisateur déclenche Codemagic manuellement** sur son dashboard (codemagic.io), sur le même
commit que celui poussé et validé côté GitHub Actions. Le rôle de la session Claude Code : préparer
le code, committer, pousser, valider via GitHub Actions, PUIS signaler explicitement à l'utilisateur
que le commit est prêt pour un déclenchement Codemagic manuel — ne jamais prétendre avoir
lancé/vérifié Codemagic soi-même sans credential réel.

### Sécurité — token GitHub

Un token GitHub était présent en clair dans `git remote -v` en début de session (signalé par
l'utilisateur, déjà exposé une fois dans les logs de cette conversation avant la sécurisation —
**rotation recommandée, pas encore effectuée à la connaissance de cette session**). Remote nettoyé
(`git remote set-url` sans credential). Toutes les opérations Git/API suivantes utilisent **Git
Credential Manager** via `git credential fill` — jamais réaffiché, jamais écrit dans un fichier.
Vérifié qu'aucun fichier du dépôt/temporaire ne contient le motif de token.

---

## 0ter. CHAT/GALERIE/ANIMEMS — FICHE DE VALIDATION (construits le 2026-08-15, tour 7)

**Contexte** : les 3 GAPs identifiés par le test Appetize comme "fonctionnalités jamais
construites" (pas des bugs) ont été bâtis dans la MÊME session, sur instruction explicite de
l'utilisateur de ne pas s'arrêter entre chaque correction (quota Appetize limité → un seul test
global prévu, pas encore fait).

- **Chat (création de groupe)** : COMPLET — sélecteur de contacts + création de groupe, fidèle à
  `ContactsFragment`/`ChooseFragment`/`Group.java` (endpoints `connectedusers`/`group`/
  `membership` exacts, y compris la faute de frappe serveur `"pivate"`). Commit `3dc83d3`.
- **Galerie (MediaEditor + publication)** : PÉRIMÈTRE RÉDUIT ASSUMÉ — crop→légende→publication
  réelle (`POST activity/add`) fonctionnels ; peinture/texte/stickers sur la photo PAS repris
  (confirmés secondaires par l'investigation Android, `PublishFragment`/`ImageEditorCompound` lus
  en entier). `MediaTrim` (recadrage vidéo) pas repris non plus. Commit `1aab36e`.
- **Animems (écran éditeur)** : PÉRIMÈTRE MINIMAL ASSUMÉ, PAS LA PARITÉ COMPLÈTE — ajout photo/
  texte/forme, déplacement au doigt (translation seule), export MP4 statique 3s. PAS de rotation/
  échelle/masques/keyframes/timeline détaillée (GAP-006 reste un chantier à part entière, ~24 942
  lignes Android, déjà estimé à plusieurs semaines-ingénieur). Commit `f2460f2`.

**Compilation CI :** VALIDÉE (GitHub Actions, run `31912698274`, SUCCESS, 11/11 fichiers confirmés
compilés par leur chemin complet, 0 erreur, 0 warning — voir section 0).
**Tests réels sur appareil :** NON EFFECTUÉS — conforme à la consigne explicite de l'utilisateur
(un seul test Appetize global prévu à la fin du lot complet, pas encore fait à ce stade).

---

## 0bis. GAP-004 — FICHE DE VALIDATION (format demandé par l'utilisateur)

**Implémentation :** COMPLÈTE (les 3 usages : photo de profil, soumission certification, pièces
jointes chat — upload seulement, le téléchargement des pièces jointes REÇUES est un gap distinct,
voir section 4)
**Compilation CI :** VALIDÉE (GitHub Actions uniquement — Codemagic en attente, voir section 0)
**Build ID :** `31908841925`
**Commit :** `e4b1832`
**Résultat :** `BUILD SUCCEEDED`, 10/10 fichiers GAP-004 confirmés présents dans les invocations de
compilation réelles (chemin complet vérifié dans le log, pas une supposition)
**Fichiers compilés :** `Networking/APIClient.swift`, `Profile/ProfileRepository.swift`,
`Profile/ProfileViewModel.swift`, `Profile/ProfileView.swift`, `Discover/CertificationModels.swift`,
`Discover/CertificationView.swift`, `Messagerie/ChatMediaUploadService.swift`,
`Messagerie/ChatViewModel.swift`, `Messagerie/ChatView.swift`, `Storage/MessageRepository.swift`
**Erreurs :** 0
**Warnings :** 2, tous les deux dans du code PRÉ-EXISTANT de `ChatViewModel.swift`
(`markConversationRead`/`deleteSelectedForEveryone`) — 0 dans le code effectivement écrit pour
GAP-004
**Tests réels sur appareil :** NON EFFECTUÉS — rappel explicite de l'utilisateur à ne jamais
oublier : "compile réellement" ≠ "fonctionne" ≠ "validé sur device". Rien de ce qui suit n'a été
vérifié : sélection photo, upload profil réel (jamais touché un vrai serveur), certification réelle,
pièce jointe chat réelle, upload BunnyCDN réel, réception du message par l'autre participant,
téléchargement des pièces jointes (non implémenté).

---

## 1. ÉTAT ACTUEL (2026-08-15, fin de session)

Projet Android de référence : `C:\Users\helen\AndroidStudioProjects\tiinver`
Projet iOS cible : `C:\Users\helen\iOSProjects\TiinverSwift`

Les 18 modules du plan de portage initial sont "fermés" depuis le 2026-08-12, mais **aucune
compilation réelle n'a jamais eu lieu** depuis un environnement Windows sans Xcode — ni pendant le
portage initial, ni pendant cette session. Toute vérification passe par CI :
- `.github/workflows/ios-build.yml` (GitHub Actions, `workflow_dispatch` manuel, compilation seule)
- `codemagic.yaml` (2 workflows : `checkpoint-build` compilation seule, `visual-smoke-test`
  captures d'écran simulateur + `.zip` pour test interactif via Appetize.io)

**Dernier build CI confirmé : ÉCHEC le 2026-08-13**, 2 corrections appliquées (GoogleMobileAds
épinglé à 13.0.0+, `Tool` enum rendu `internal`) — **jamais reconfirmées par un nouveau build**.
Deux bugs visuels majeurs (feed blanc, navigation à 3 onglets au lieu de 5) corrigés par une session
parallèle le 2026-08-13, vérifiés par lecture de code uniquement, jamais vus tourner réellement.

## 2. DERNIÈRES DÉCOUVERTES (cette session, 2026-08-15)

1. **GAP-000 (démarrage) clos** — `App.java` (`onCreate()` réel, PAS `onCreate2()` qui est du code
   mort) comparé ligne par ligne à `AppDelegate.swift`. SDK Facebook (App Events/attribution pub,
   PAS de login) jamais porté côté iOS — P3, aucun impact utilisateur.
2. **GAP-008 (nouveau)** — `Storage/ViewEventRepository.swift` (stockage local watch-time,
   équivalent `ViewTracker.java`) **existe mais n'est appelé NULLE PART** dans tout le projet : ni
   enregistrement local depuis le feed, ni synchronisation périodique vers le serveur
   (`BGTaskScheduler` absent). Si le classement Créateurs/algorithme dépend de ces données côté
   serveur (à confirmer), le feed iOS ne contribue actuellement AUCUNE donnée de visionnage.
3. **GAP-004 (upload de fichiers) — l'hypothèse "un seul service partagé" de la session précédente
   était FAUSSE.** 3 protocoles réels, pas 1 :
   - Photo de profil + Certification → backend Tiinver, POST multipart, `APIClient.uploadMultipart`
   - Pièces jointes chat → BunnyCDN storage, PUT direct, `ChatMediaUploadService` (nouveau, séparé)
4. **2 bugs "double slash" trouvés dans `UploadFileOrDataService.java`** (Android) en le relisant
   précisément pour l'implémentation BunnyCDN — accidentels (incohérents entre 2 branches), NON
   reproduits côté iOS, corrigés uniformément. Détail complet dans `ChatMediaUploadService.swift`
   (commentaire de tête) et `MIGRATION_AUDIT.md` GAP-004.
5. **2 bugs Swift trouvés et corrigés AVANT de considérer le travail fini** (vérification statique,
   pas de compilation réelle possible) :
   - `.onChange(of:) { oldValue, newValue in }` (API iOS 17+) utilisée par erreur dans
     `ProfileView.swift` — `deploymentTarget: 16.0` (`project.yml`) ne la supporte pas, corrigée en
     forme à un seul paramètre.
   - `FirebaseConfigManager.shared` (n'existe pas) au lieu de `TiinverFirebaseConfigManager.shared`
     dans `CertificationView.swift`.

## 3. FONCTIONNALITÉS TERMINÉES CETTE SESSION

- **GAP-000** : audit du démarrage clos (voir `MIGRATION_AUDIT.md`).
- **GAP-004, entièrement clos** (les 3 usages) :
  - Upload photo de profil (`ProfileRepository.uploadProfilePicture` + `PhotosPicker` dans
    `ProfileView.swift`).
  - Soumission de certification (`CertificationRepository.submit` + section "Nouvelle demande" dans
    `CertificationView.swift`).
  - Pièces jointes chat, UPLOAD SEULEMENT (`ChatMediaUploadService.swift`, nouveau fichier ; bouton
    trombone dans `ChatView.swift` ; `ChatViewModel.attachMedia`/`requestUpload`).

## 4. FONCTIONNALITÉS EN COURS / PARTIELLES

Rien "en cours" au sens d'un travail interrompu à mi-chemin — chaque incrément ci-dessus est fermé
de bout en bout côté code. Mais GAP-004 lui-même a révélé 2 gaps ADJACENTS explicitement laissés de
côté (documentés, pas oubliés) :
- **Download des pièces jointes REÇUES** (`ChatViewModel.requestDownload`, toujours un `TODO` vide)
  — `DownloadReceiver.java` (Android) jamais lu. Upload ≠ download, protocole probablement différent
  (GET direct depuis l'URL CDN publique, pas de clé `AccessKey` nécessaire côté lecture — À VÉRIFIER,
  pas supposé).
- **Confirmation que le message avec pièce jointe atteint réellement l'autre participant** via
  Socket.IO une fois l'upload terminé — le code appelle `send(mlib)` (émission), mais l'événement
  socket exact et sa réception côté pair n'ont PAS été re-vérifiés (rattaché à GAP-003).

## 5. GAPS RESTANTS (par priorité, voir `MIGRATION_AUDIT.md` section 10 pour le détail complet)

- **P0** — Confirmer par un test CI/Appetize.io réel que le code compile ET que feed/navigation
  fonctionnent visuellement (jamais fait, ni avant cette session ni pendant).
- **P1** — GAP-003 (Chat, audit profond événement-par-événement, jamais refait depuis le portage
  initial) ; GAP-005 (Appels WebRTC/CallKit, jamais exécutés) ; GAP-006 (Animems, audit/parité
  COMPLÈTE — un écran minimal fonctionnel existe désormais, voir section 0ter, mais PAS la parité
  avec les 24 942 lignes Android) ; download pièces jointes chat (voir section 4 ci-dessus) ; Feed
  like/commentaire/partage (jamais portés, périmètre Checkpoint 1 exclu à l'époque) ; MediaEditor
  peinture/texte/stickers (Galerie, périmètre réduit assumé cette session, voir section 0ter).
- **P2** — GAP-008 (sync watch-time, voir section 2) ; Réglages (8 fragments à vérifier un par un) ;
  Recherche/Follow/Commentaires (audit ciblé) ; AdMob (jamais vu charger une vraie pub) ; rotation/
  échelle/masques/keyframes/timeline Animems (voir section 0ter, périmètre minimal actuel).
- **P3** — SDK Facebook (App Events) ; décoratifs Créateurs ; Statistiques/boost interne (jamais
  explorés en détail). **Contacts** : le sélecteur pour la création de GROUPE existe désormais
  (section 0ter) — reste un éventuel écran "Contacts" autonome si Android en a un hors du flux
  groupe (pas confirmé/investigué).

## 6. FICHIERS RÉCEMMENT MODIFIÉS (état final, TOUS COMMITÉS ET POUSSÉS sur `origin/main`)

```
Commit 8aeb5a6 : .github/workflows/ios-build.yml (fix sélection Xcode)
Commit e48dbed : .github/workflows/ios-build.yml (Metal Toolchain non bloquant — introduisait un bug YAML)
Commit a66c509 : .github/workflows/ios-build.yml (fix du bug YAML introduit par e48dbed)
Commit e4b1832 : "feat(migration): complete file upload migration (GAP-004)"
  MIGRATION_AUDIT.md                                     (GAP-000/GAP-004/GAP-008/section 12 CI)
  MIGRATION_PROGRESS.md                                  (4 entrées de journal 2026-08-15)
  Sources/TiinverSwift/Networking/APIClient.swift        (+ uploadMultipart, multipartHeaders)
  Sources/TiinverSwift/Profile/ProfileRepository.swift   (uploadProfilePicture implémenté)
  Sources/TiinverSwift/Profile/ProfileViewModel.swift    (+ uploadProfilePicture, isUploadingPhoto)
  Sources/TiinverSwift/Profile/ProfileView.swift         (+ PhotosPicker sur l'avatar)
  Sources/TiinverSwift/Discover/CertificationModels.swift (+ CertificationRepository.submit)
  Sources/TiinverSwift/Discover/CertificationView.swift  (+ section "Nouvelle demande")
  Sources/TiinverSwift/Messagerie/ChatMediaUploadService.swift  (NOUVEAU FICHIER, BunnyCDN)
  Sources/TiinverSwift/Messagerie/ChatViewModel.swift    (+ attachMedia/requestUpload implémenté)
  Sources/TiinverSwift/Messagerie/ChatView.swift         (+ bouton trombone)
  Sources/TiinverSwift/Storage/MessageRepository.swift   (+ updateFileUploaded)
Commit 3f5f880 : "fix(migration): resolve Appetize functional parity issues (P0: Home/Profile/Search)"
  Sources/TiinverSwift/Feed/FeedView.swift                       (réécrit : grille 2 colonnes + détail plein écran)
  Sources/TiinverSwift/Authentication/AuthSessionPersistence.swift (+ saveSession, sync)
  Sources/TiinverSwift/Authentication/LoginView.swift             (appel saveSession avant navigation)
  Sources/TiinverSwift/Authentication/SignUpWithGoogleView.swift  (idem)
  Sources/TiinverSwift/Authentication/EmailVerificationView.swift (idem)
  Sources/TiinverSwift/Discover/SearchModels.swift                (init(from:) tolérant clés absentes)
Commit 3dc83d3 : "feat(chat): implement group creation flow"
  Sources/TiinverSwift/Messagerie/GroupModels.swift              (NOUVEAU)
  Sources/TiinverSwift/Messagerie/ContactsRepository.swift       (NOUVEAU, GET connectedusers)
  Sources/TiinverSwift/Messagerie/GroupRepository.swift          (NOUVEAU, POST group+membership)
  Sources/TiinverSwift/Messagerie/ContactPickerView.swift        (NOUVEAU)
  Sources/TiinverSwift/Messagerie/GroupCreationView.swift        (NOUVEAU)
  Sources/TiinverSwift/Messagerie/RosterListView.swift           (+ bouton d'entrée)
Commit 1aab36e : "feat(feed): implement media publish flow (photo/video)"
  Sources/TiinverSwift/Feed/PublishComposeView.swift             (NOUVEAU)
  Sources/TiinverSwift/Feed/FeedRepository.swift                 (+ publish(), POST activity/add)
  Sources/TiinverSwift/Feed/FeedView.swift                       (fermetures caméra/galerie câblées)
Commit f2460f2 : "feat(animems): assemble minimal functional editor screen"
  Sources/TiinverSwift/Animems/AnimemesEditorView.swift          (NOUVEAU)
  Sources/TiinverSwift/Animems/AnimemesEditorState.swift         (NOUVEAU)
Non commité : CLAUDE_CONTINUATION.md (ce fichier — sera commité en fin de session, doc pure),
MIGRATION_AUDIT.md/MIGRATION_PROGRESS.md (section Appetize ajoutée après ce commit, à committer avec
ce fichier)
```

## 7. TESTS EFFECTUÉS

- **Vérification statique** (lecture manuelle) avant push : cohérence des types Swift, signatures
  d'appel, disponibilité API vs `deploymentTarget: 16.0`.
- **Comparaison Android ↔ iOS** : chaque endpoint/champ/header vérifié contre le fichier Android
  source correspondant, lu en entier (pas deviné). Pour la mission Appetize (ce tour), 6
  investigations Android↔iOS menées en parallèle par des agents dédiés, résultats croisés avec
  lecture directe du code avant toute correction.
- **Compilation CI RÉELLE, GitHub Actions** : run `31911325017`, commit `3f5f880`, **SUCCESS**
  confirmé, les 6 fichiers modifiés confirmés présents dans les invocations de compilation par leur
  chemin complet, 0 erreur, 1 warning pré-existant sans rapport.
- **Test fonctionnel réel sur Appetize.io (device réel)** — celui qui a RÉVÉLÉ tous les problèmes de
  cette section : Home vide, Profile vide, Search sans résultats, bouton créer-groupe Chat absent,
  sélection galerie sans effet, bouton Animems non fonctionnel. C'est ce test, pas une lecture de
  code, qui a permis de trouver la race condition de session et l'erreur d'architecture du feed.

## 8. TESTS IMPOSSIBLES/PAS ENCORE EFFECTUÉS

- **Compilation Codemagic** — en attente d'un déclenchement manuel par l'utilisateur, toujours vrai
  pour `e4b1832` ET `3f5f880` (aucun credential Codemagic disponible dans cet environnement).
- Exécution sur simulateur/device DEPUIS CETTE SESSION — jamais (pas de Xcode local) ; SEUL le test
  Appetize fourni PAR L'UTILISATEUR fait exception, et c'est justement lui qui a motivé cette
  section.
- **Retest Appetize des 3 corrections P0 de ce tour (Home/Profile/Search)** — PAS ENCORE FAIT. Le
  commit `3f5f880` compile (confirmé CI) mais n'a PAS été revu sur un device réel après correction.
- Chat (création de groupe), Galerie (MediaEditor), Animems (éditeur) — non implémentés, donc rien à
  tester (voir section "APPETIZE FUNCTIONAL TEST" de `MIGRATION_AUDIT.md`).
→ **Rappel permanent de l'utilisateur, à ne jamais oublier, règle absolue de la mission Appetize** :
un build CI vert signifie UNIQUEMENT que le code compile — jamais que Home/Profile/Search
fonctionnent réellement comme Android tant qu'un nouveau test Appetize ne l'a pas confirmé.

## 9. DÉCISIONS TECHNIQUES (cette session)

- **Pas de recadrage avant upload** (photo de profil ET document de certification) — Android
  recadre via `CroperView` avant envoi, iOS envoie l'image choisie telle quelle (juste ré-encodée en
  JPEG). Assumé : l'avatar est affiché en cercle recadré côté client de toute façon.
- **2 bugs "double slash" Android (BunnyCDN) corrigés, pas reproduits** — jugés accidentels
  (incohérents entre 2 fonctions), contrairement à `MyMediaType.IMAGE` (`.webp`/`image/jpeg`
  incohérent mais VOLONTAIRE et cohérent partout) qui LUI est reproduit à l'identique.
  Règle appliquée : un bug qui diverge entre 2 chemins de code n'est pas une "décision produit" à
  respecter ; une constante bizarre mais utilisée uniformément partout l'est.
- **Miniature vidéo chat générée réellement côté iOS** (`AVAssetImageGenerator`) alors qu'Android a
  ce code commenté/mort à cet endroit précis — sans génération réelle, l'upload de la miniature
  (`uploadMediaAndThumbnail`, qui suppose un `thumbnailUri` non nul) aurait été cassé même côté
  Android. Reproduit le comportement INTENTIONNEL (upload média+miniature), pas le bug qui l'entoure.
- **Bouton d'attache pièce jointe chat** : emplacement exact non identifiable dans les 3080 lignes
  déjà lues de `ChatFragmentTest.java` (probablement dans un layout XML non fourni) — branché sur
  une icône trombone, cohérent avec d'autres points d'entrée déjà non localisés précisément dans ce
  même fichier (bouton d'appel, Shareboard).
- **`CertificationPlanFragment.tarification()` (re-fetch réseau du prix) PAS porté** — redondant
  avec la valeur déjà disponible via Remote Config (`certificationPrice`), jugé hors périmètre
  strict de GAP-004 (transfert de fichier).
- **Feed reconstruit : grille = écran principal, pager plein écran = écran de détail** — pas une
  invention, port fidèle de `MainFragment.OnAdapterItemClicked` (Android ouvre RÉELLEMENT ce même
  pager plein écran, mais SEULEMENT au tap sur une cellule de la grille, jamais comme écran
  d'accueil). Le pager iOS pré-existant n'était donc pas à jeter, juste mal positionné dans la
  hiérarchie d'écrans — code réutilisé presque intégralement (`FeedDetailPagerView`).
- **Bannières décoratives du Home (carrousel Créateurs, promo pièces gratuites) volontairement PAS
  reproduites** dans la reconstruction de la grille — visibles sur les captures Android fournies,
  mais hors du périmètre strict du problème rapporté ("données absentes"/"pas en grille de 2"), pas
  un oubli. `CreatorOfWeekView.swift`/`EarnCoinsView.swift` existent déjà comme écrans séparés,
  pourraient alimenter une version compacte de ces bannières dans une passe dédiée.
- **`AuthSessionPersistence.saveSession` séparé de `persist`** plutôt que de faire attendre tout
  `persist` (Core Data + jeton push) avant de naviguer — seule la ligne qui affecte réellement le
  premier rendu de Profile/Feed (`UserSession.shared.myId`) est rendue bloquante ; le reste continue
  en tâche de fond sans retarder la navigation.

## 10. PROCHAINE TÂCHE EXACTE

**Instruction explicite et répétée de l'utilisateur ce tour (8ᵉ, 2026-08-16) : NE PAS s'arrêter, NE
PAS demander/attendre de test Appetize — un seul test global prévu APRÈS ce cycle complet, quota
conservé.** Cette règle reste valable pour la prochaine session tant que l'utilisateur ne dit pas
explicitement le contraire.

**État réel après ce tour** — voir `MIGRATION_PROGRESS.md` (entrée "SESSION DU 2026-08-16, 8ᵉ tour")
pour le détail complet par fonctionnalité. Résumé :
- **Animems (GAP-006)** : timeline/keyframes/lecture/masques maintenant CÂBLÉS (le moteur était déjà
  porté, seul l'écran ne les utilisait pas) — PARTIAL→COMPLETE pour ces sous-fonctionnalités
  précises, PLUS la sauvegarde image statique (`hasAnimation`/`exportStaticImage`, commit `70692d5`)
  ajoutée en fin de tour. Restent MISSING, non explorés cette passe : modèles de mouvement
  (local/upload communautaire), export GIF.
- **Galerie** : PARTIAL→PARTIAL (amélioré) — recadrage forme-libre/suppression fond/retournement/
  peinture/texte/miniature-durée vidéo réelle/légende limitée/partage AJOUTÉS, PLUS `MediaTrim`
  (recadrage temporel vidéo, `MediaTrimView.swift`, commit `ef3a34b`) ajouté en fin de tour. Reste
  MISSING : stickers/emoji.
- **Chat (GAP-003)** : COMPLETE quasi-intégral confirmé par 2 audits dédiés + lecture directe des
  éléments "non vérifiés" signalés (`ChatBubbleRow`, état vide roster — tous deux déjà présents).
  Téléchargement pièces jointes reçues implémenté. Seul "gap" (`pushNotification`) est un faux
  positif : code mort côté Android lui-même, confirmé par grep exhaustif.
- **WebRTC/CallKit (GAP-005)** : COMPLETE quasi-intégral confirmé par audit dédié (10 fichiers
  Android relus en entier). 2 vrais bugs trouvés ET corrigés : configuration audio session absente
  (HIGH PRIORITY — pouvait empêcher l'audio de fonctionner sur un vrai appareil) et permission micro
  jamais vérifiée avant un appel.
- **Feed/Ads** : native ads câblées dans le pager plein écran (pas la grille — vérifié contre
  `ViewPagerAdapter.java`).
- **Search** : navigation hashtag/publication, bouton Suivre, états erreur/vide AJOUTÉS.
- **Profile** : COMPLETE quasi-intégral confirmé par audit dédié, seul écart déjà documenté
  (catégorie en lecture seule).

**Tâche exacte pour la suite** (dans l'ordre, sans s'arrêter entre chaque point, sauf blocage réel) :
1. **GAP-006 Animems — modèles de mouvement / export GIF** — seuls morceaux du périmètre Android
   encore non explorés pour Animems (la sauvegarde image statique a été ajoutée en fin de tour 8,
   commit `70692d5`). Lire `AnimemesCompound.java` sections `saveAsMotionTemplate`/
   `saveAndUploadTemplate`/`MotionTemplateManager` (citées dans l'audit du tour 8, pas encore lues
   en détail) avant d'implémenter quoi que ce soit.
2. **Galerie — stickers/emoji** — seul morceau MediaEditor encore MISSING (`MediaTrim` a été ajouté
   en fin de tour 8, commit `ef3a34b`, nouveau `MediaTrimView.swift`).
3. **Audit "Autres modules"** encore non couverts explicitement par un audit dédié ce tour :
   authentification/onboarding (stables depuis des sessions antérieures, pas revérifiés), paiements/
   monétisation (`Wallet/*`, AdMob rewarded déjà câblé au module 15/16 — pas re-audité), deep links,
   Firebase/analytics (pas re-audité), notifications push (confirmé COMPLETE en passant par l'audit
   Chat, pas un audit dédié).
4. **Demander le retour Codemagic manuel** — toujours en attente depuis GAP-004 (`e4b1832`), jamais
   rapporté pour AUCUN commit à ce jour, y compris ceux de ce tour.
5. Continuer d'appliquer la stratégie double-CI (section 0) pour chaque nouveau commit important —
   **attention à la lenteur/instabilité du téléchargement de log `xcodebuild` via l'API GitHub
   Actions pour ce projet précis** (voir section 0, point 7 : `curl` timeouts fréquents sur les logs
   complets ~25-27k lignes, toujours relancer en arrière-plan avec `--max-time 590`, jamais en
   commande synchrone bloquante).
6. Le test Appetize global reste À VENIR, sur décision de l'utilisateur — ne pas le demander
   proactivement, ne pas s'arrêter en l'attendant.

## 11. HANDOFF — DERNIÈRE SESSION

**Session :** Claude Code (Sonnet 5), continuation autonome sans mémoire de session précédente,
contexte reconstruit depuis Git + documentation existante. 8ᵉ tour, 2026-08-16.
**Date :** 2026-08-16
**Dernière tâche terminée :** Cycle complet de continuation demandé explicitement par l'utilisateur
("CONTINUE LA MIGRATION... NE T'ARRÊTE PAS AVANT D'AVOIR TRAITÉ TOUT CE QUI EST RÉALISABLE") couvrant
Animems (priorité principale), Galerie, Chat, WebRTC, Feed, Profile, Search, et un audit transversal.
Voir section 10 ci-dessus pour le détail COMPLETE/PARTIAL/MISSING par fonctionnalité, et
`MIGRATION_PROGRESS.md` (entrée 8ᵉ tour) pour le récit complet.
**Travail effectué (tour 8), dans l'ordre chronologique réel :**
- Repris exactement où le tour 7 s'était arrêté : fix du geste Animems cassé (`AnimemesEditorView`
  référençait une méthode `moveObject` déjà supprimée de `AnimemesEditorState` — corrigé en premier,
  avant tout nouveau travail), gestes translation/rotation/échelle réels câblés via
  `AnimemesGestureController` (déjà porté, jamais utilisé), fix bug sélection (le calque sélectionné
  restait bloqué après le premier toucher).
- Fix bug WebRTC réel trouvé en fin de tour précédent : `makingOffer` jamais réinitialisé après
  échec `setRemoteDescription` (`RTConnection2.onSetFailure` non reproduit).
- Batch de 5 audits dédiés en parallèle (Socket.IO Chat, MediaEditor Galerie, WebRTC/CallKit complet,
  Profile complet, Search complet) — 2 premières tentatives ont échoué avec une erreur API
  transitoire, relancées avec succès.
- Galerie : freeform crop + suppression arrière-plan (composants déjà portés, jamais câblés) +
  flip + peinture/texte (nouveau `PhotoToolsView.swift`) + miniature/durée vidéo réelles + limite
  légende + partage natif.
- Native ads câblées dans le pager Feed (pas la grille — vérifié contre le code Android réel avant
  de choisir l'emplacement).
- Search : navigation hashtag/publication + bouton Suivre + états erreur/vide.
- WebRTC : 2 corrections réelles trouvées par l'audit (config audio session + permission micro).
- **Animems, le morceau principal** : lecture complète de `AnimemesCompound.java` (3947 lignes) +
  `TimelineView.java` (1320 lignes) a révélé que le moteur (timeline/keyframes/masques) était déjà
  porté à ~95% lors d'une session antérieure mais jamais câblé à l'éditeur. Câblage complet :
  `TimelineView.swift` (nouveau, rendu `Canvas` + geste unique multi-mode), enregistrement de
  keyframes explicite (bouton ◆), lecture/pause réelle (`AnimationEngine`/`CADisplayLink`), panneau
  + geste de masque.
- **4 tentatives de build CI pour le seul lot Animems** avant succès — voir section 0 pour le détail
  exact de chaque échec/diagnostic. Aucune ne pouvait être anticipée sans environnement macOS ; toutes
  diagnostiquées à partir du VRAI log `xcodebuild`, jamais devinées.
- Après le lot principal (build vert), deux compléments ajoutés et validés séparément : sauvegarde
  image statique Animems (`hasAnimation`/`exportStaticImage`, commit `70692d5`, SUCCESS) et
  recadrage temporel vidéo Galerie (`MediaTrimView.swift` nouveau, commit `ef3a34b`, SUCCESS).
- Documentation (ce fichier + `MIGRATION_PROGRESS.md` + `MIGRATION_AUDIT.md`) mise à jour en fin de
  tour avec les deux compléments inclus.
**Travail actuellement en cours :** Aucun code en cours — dernier commit (`ef3a34b`) confirmé
SUCCESS. Mise à jour de documentation en cours de finalisation, reste à committer avec ce fichier.
**PROCHAINE TÂCHE EXACTE :** Voir section 10 ci-dessus — modèles de mouvement/export GIF (Animems),
stickers (Galerie), audit des modules non encore couverts (paiements/deep links/Firebase-analytics).
**Fichiers modifiés :** Voir `MIGRATION_PROGRESS.md` (entrée 8ᵉ tour) pour la liste complète —
volume trop important pour être dupliqué ici sans risque de désynchronisation. Tout le code
applicatif de ce tour est commité et poussé (8 commits, `d19e372`…`e4b347a`) ; seule la documentation
de ce tour reste à committer.
**Fichiers à surveiller :** aucun changement externe détecté ce tour (contrairement au tour 7 où un
worktree Android parallèle était en cours) — à revérifier via `git status`/`git log` en début de
prochaine session, ne jamais supposer.
**Bugs connus :** Aucun bug de compilation à ce jour (dernier run SUCCESS). Deux VRAIS bugs
fonctionnels trouvés ET corrigés ce tour (glare WebRTC `makingOffer`, config audio session absente).
Un potentiel troisième sujet non résolu : la lenteur/l'instabilité du téléchargement des logs
`xcodebuild` complets via l'API GitHub Actions pour ce projet (jamais un problème de fond côté code,
juste un frein opérationnel à connaître pour la prochaine session — voir section 10, point 5).
**Tests effectués :** Compilation CI réelle réussie pour tout le lot du tour (GitHub Actions,
`e4b347a`, SUCCESS confirmé via l'API, pas seulement supposé). **AUCUN test fonctionnel réel
(Appetize)** — conforme à la consigne explicite et répétée de l'utilisateur ce tour.
**Résultats :** Animems/Galerie/Chat/WebRTC/Feed/Profile/Search tous avancés d'un cran réel (voir
section 10 pour le détail COMPLETE/PARTIAL/MISSING). Niveau "compile réellement" atteint pour tout
le lot (GitHub Actions SUCCESS). Codemagic toujours jamais rapporté. Test fonctionnel réel toujours
non fait — reste le seul niveau de validation manquant, sur décision explicite de l'utilisateur de
le reporter à la fin d'un cycle plus complet.
**Décisions techniques :** Voir section 9 (décisions antérieures, toujours valables) +
`MIGRATION_PROGRESS.md` entrée 8ᵉ tour pour les décisions de ce tour (piste-par-calque simplifiée
pour la timeline, pas de re-bake keyframes pour l'aperçu live vs export, gestes fusionnés en un seul
jeu plutôt que deux graphes typés différemment, etc. — chacune documentée avec sa justification dans
le code source directement, pas seulement ici).
**Points importants pour la prochaine session :**
- Ne PAS refaire les audits déjà faits ce tour (Socket.IO Chat, MediaEditor Galerie, WebRTC/CallKit,
  Profile, Search) — tous documentés en détail dans `MIGRATION_PROGRESS.md`, resultats fiables.
- Ne PAS supposer qu'un geste/timeline/masque Animems fonctionne VISUELLEMENT correctement — seule
  la compilation est confirmée, comme toujours dans cette mission tant qu'Appetize n'a pas tourné.
- **Si un nouveau lot de Swift touche des `Gesture`/`SimultaneousGesture`/`AnyGesture` composés en
  plusieurs variantes choisies dynamiquement, éviter d'emblée le pattern "deux `some Gesture`
  différentes + ternaire + `AnyGesture`"** — préférer un seul jeu de gestes avec bascule d'état À
  L'EXÉCUTION dans les handlers (voir `AnimemesEditorView.swift`, section geste, et son commentaire
  de tête qui documente l'historique complet de cet écueil). Coût réel ce tour : 4 builds CI, ~1h de
  cycles diagnostic/fix sans environnement macOS local pour vérifier.
- Ne JAMAIS déclencher Codemagic soi-même sans credential réel — l'utilisateur le fait manuellement.
- Tout le code est commité/poussé ; seule la documentation de ce tour reste à committer.
**Instructions pour la prochaine session :**
1. Lire ce fichier EN PREMIER, section 0 (CI) et 10 (prochaine tâche) en priorité absolue.
2. Vérifier qu'il correspond toujours au code réel (`git log`, `git status`) — une autre session a
   pu intervenir/pousser depuis.
3. Continuer directement les points listés en section 10 SANS demander confirmation ni test Appetize,
   sauf si l'utilisateur donne une instruction contraire explicite dans le nouveau message reçu.
4. Mettre à jour ce fichier (sections 0 et 11 au minimum) à la fin de la session, quel que soit le
   résultat.
