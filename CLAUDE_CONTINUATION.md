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
Codemagic en attente d'un déclenchement manuel par l'utilisateur)
**Build :** GitHub Actions run `31911325017` (workflow `ios-build.yml`)
**Commit :** `3f5f880` ("fix(migration): resolve Appetize functional parity issues (P0:
Home/Profile/Search)")
**Date :** 2026-08-15 22:08-22:13 UTC
**Résultat :** `** BUILD SUCCEEDED **`. Les 6 fichiers modifiés confirmés compilés (chemin complet
dans le log). 0 erreur réelle. 1 warning, PRÉ-EXISTANT (`AuthSessionPersistence.swift:31`, `try?`
non utilisé sur le bloc Core Data — sans rapport avec cette session).
**Historique complet des runs de cette journée** (pour ne pas confondre) :
1. `31905358058` (commit `733da28`) — ÉCHEC, `-downloadComponent` invalide, Xcode non sélectionné.
2. `31907788616` (commit `a66c509`, fixes CI seuls) — SUCCESS.
3. `31908841925` (commit `e4b1832`, GAP-004) — SUCCESS.
4. `31911325017` (commit `3f5f880`, corrections P0 Appetize Home/Profile/Search) — **SUCCESS,
   dernier run connu**.

### CI VALIDATION — format demandé par l'utilisateur pour chaque commit important

**Commit :** `3f5f880`
**GitHub Actions :** Build ID `31911325017` — Result **SUCCESS**
**Codemagic :** Build ID — (aucun, déclenchement manuel par l'utilisateur, en attente de retour —
toujours vrai pour CE commit ET pour `e4b1832`, aucun build Codemagic n'a encore été rapporté)
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
  initial) ; GAP-005 (Appels WebRTC/CallKit, jamais exécutés) ; GAP-006 (Animems, audit profond,
  24 942 lignes Android) ; download pièces jointes chat (voir section 4 ci-dessus) ; Feed
  like/commentaire/partage (jamais portés, périmètre Checkpoint 1 exclu à l'époque).
- **P2** — GAP-008 (sync watch-time, voir section 2) ; Réglages (8 fragments à vérifier un par un) ;
  Recherche/Follow/Commentaires (audit ciblé) ; AdMob (jamais vu charger une vraie pub).
- **P3** — SDK Facebook (App Events) ; décoratifs Créateurs ; Contacts/Statistiques/boost interne
  (jamais explorés en détail).

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

**Ne PAS commencer GAP-003 — instruction explicite de l'utilisateur, toujours valable, réaffirmée
pour la mission Appetize.** 3 corrections P0 (Home/Profile/Search) compilent réellement (GitHub
Actions, run `31911325017`) mais N'ONT PAS ENCORE été retestées sur Appetize, et 3 problèmes
(Chat/Galerie/Animems) restent non traités (fonctionnalités jamais construites, pas des bugs).

**Tâche exacte** :
1. **Demander à l'utilisateur de retester Home/Profile/Search sur Appetize** avec le commit
   `3f5f880` (ou plus récent) — c'est la seule façon de confirmer que les 3 corrections
   fonctionnent réellement, pas seulement qu'elles compilent. Documenter le résultat (PASS/FAIL par
   écran) dans `MIGRATION_AUDIT.md`, section "APPETIZE FUNCTIONAL TEST — 2026-08-15", en remplaçant
   les 3 mentions "NON TESTÉ" par le résultat réel.
2. **Décider avec l'utilisateur comment aborder Chat/Galerie/Animems** — ces 3 ne sont PAS des
   corrections ponctuelles (voir `MIGRATION_AUDIT.md`, même section, entrées P0-4/5/6) :
   - Chat : construire un sélecteur de contacts + un écran de création de groupe (port de
     `Contact.java`/`ChooseFragment.java`/`Group.java`).
   - Galerie : construire un vrai flux `MediaEditor`/publication (aucun flux de publication de post
     ne semble exister côté iOS pour la caméra à ce stade — à confirmer avant de commencer).
   - Animems : assembler un écran d'éditeur complet à partir du moteur déjà porté (GAP-006, déjà
     estimé à plusieurs semaines dans `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`).
   Proposer de les traiter comme 3 chantiers séparés (pas une seule session), en commençant par
   celui que l'utilisateur juge prioritaire.
3. **Demander le retour Codemagic manuel** — toujours en attente depuis GAP-004 (`e4b1832`),
   jamais rapporté ; s'applique maintenant aussi à `3f5f880`.
4. Continuer d'appliquer la stratégie double-CI (section 0) pour chaque nouveau commit important.

## 11. HANDOFF — DERNIÈRE SESSION

**Session :** Claude Code (Sonnet 5), reprise sans mémoire, contexte reconstruit depuis Git +
documentation existante. 6ᵉ tour de cette même journée (2026-08-15) — premier test fonctionnel réel
de l'app (Appetize.io, device réel) fourni par l'utilisateur avec captures Android de référence.
**Date :** 2026-08-15
**Dernière tâche terminée :** Diagnostic des 6 problèmes rapportés (6 investigations Android↔iOS en
parallèle) + correction et validation CI de 3 d'entre eux (Home, Profile, Search) — commit `3f5f880`,
GitHub Actions SUCCESS (run `31911325017`).
**Travail effectué :**
- Home : cause racine confirmée = erreur d'architecture (pager plein écran au lieu d'une grille 2
  colonnes) + race condition possible. `FeedView.swift` réécrit : grille 2 colonnes comme écran
  principal, l'ancien pager devient l'écran de détail (tap sur une cellule), fidèle à
  `MainFragment.OnAdapterItemClicked`.
- Profile : race condition confirmée et corrigée (session non attendue avant navigation dans les 3
  flux de connexion) — `AuthSessionPersistence.saveSession` (nouvelle fonction synchrone).
- Search : bug de décodage JSON confirmé et corrigé (clés de catégorie absentes du JSON faisaient
  échouer silencieusement tout le décodage) — `init(from:)` custom sur `SearchResults`.
- Chat/Galerie/Animems : diagnostiqués (causes réelles identifiées avec citations de code précises)
  mais PAS corrigés — ce sont des fonctionnalités jamais construites, pas des bugs, effort d'une
  toute autre ampleur.
**Travail actuellement en cours :** Aucun code en cours. Documentation de cette passe terminée dans
`MIGRATION_AUDIT.md`/`MIGRATION_PROGRESS.md`/ce fichier, reste à committer.
**PROCHAINE TÂCHE EXACTE :** Voir section 10 ci-dessus.
**Fichiers modifiés :** Voir section 6 ci-dessus. Code applicatif (commit `3f5f880`) déjà poussé ;
mises à jour de documentation de cette section restent à committer avec ce fichier.
**Fichiers à surveiller :** `.claude/worktrees/fix-splash-stuck` apparaît modifié dans le `git
status` du dépôt ANDROID (pas iOS) — une AUTRE session travaille en parallèle sur ce worktree
Android. Ne PAS y toucher, ne pas supposer son contenu.
**Bugs connus :** Voir `MIGRATION_AUDIT.md`, section "APPETIZE FUNCTIONAL TEST", entrées P0-4/5/6
(Chat/Galerie/Animems, non corrigés). Le token GitHub qui était dans l'URL du remote a été exposé
une fois en clair dans cette conversation avant sécurisation — **rotation recommandée, à confirmer
avec l'utilisateur si elle a été faite.**
**Tests effectués :** Voir section 7 — compilation CI réelle réussie (GitHub Actions, `3f5f880`).
Test Appetize réel EFFECTUÉ par l'utilisateur AVANT ces corrections (c'est ce qui a motivé ce tour) ;
PAS ENCORE REFAIT après ces corrections.
**Résultats :** Home/Profile/Search compilent réellement (niveau 1/3). PAS encore retestés sur
Appetize après correction (niveau 3/3 non atteint). Chat/Galerie/Animems : diagnostiqués seulement,
niveau 0/3.
**Décisions techniques :** Voir section 9 (nouvelles entrées Feed/AuthSessionPersistence de ce tour).
**Points importants :**
- Ne PAS refaire l'audit global — `MIGRATION_AUDIT.md`/`MIGRATION_PROGRESS.md` sont à jour et
  fiables.
- Ne PAS supposer que Home/Profile/Search fonctionnent réellement — seule la compilation est
  confirmée, pas le comportement sur device, règle absolue rappelée explicitement par l'utilisateur
  pour toute cette mission.
- Ne PAS commencer Chat/Galerie/Animems sans clarifier avec l'utilisateur l'ampleur réelle du
  travail (nouveaux écrans complets, pas des corrections) — voir section 10, point 2.
- Ne JAMAIS déclencher Codemagic soi-même sans credential réel — l'utilisateur le fait manuellement.
- Tout le code est commité/poussé ; seule la documentation de ce tour reste à committer.
**Instructions pour la prochaine session :**
1. Lire ce fichier EN PREMIER, section 0/0bis en priorité absolue.
2. Vérifier qu'il correspond toujours au code réel (`git log`, `git status`) — une autre session a
   pu intervenir/pousser depuis.
3. Si l'utilisateur ne précise pas de priorité, demander (a) le résultat du retest Appetize des
   corrections Home/Profile/Search (commit `3f5f880`) et (b) le résultat de son build Codemagic
   manuel (section 10) — l'utilisateur a explicitement interdit GAP-003 tant que ces points ne sont
   pas clarifiés.
4. Mettre à jour ce fichier (sections 0, 0bis et 11) à la fin de la session, quel que soit le
   résultat.
