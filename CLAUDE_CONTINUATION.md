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
**Build :** GitHub Actions run `31908841925` (workflow `ios-build.yml`)
**Commit :** `e4b1832` ("feat(migration): complete file upload migration (GAP-004)")
**Date :** 2026-08-15 21:13-21:18 UTC
**Résultat :** `** BUILD SUCCEEDED **` (ligne littérale du log Xcode). Les 8 étapes du workflow
vertes. 0 erreur réelle. 2 warnings, tous deux dans du code PRÉ-EXISTANT de `ChatViewModel.swift`
(pas GAP-004). Vérifié explicitement (pas seulement le statut global) que les 10 fichiers GAP-004
apparaissent chacun par leur chemin complet dans les invocations réelles du compilateur — voir
`MIGRATION_AUDIT.md` section 12 pour le détail complet.
**Historique des 3 runs de cette journée** (pour ne pas confondre) :
1. `31905358058` (commit `733da28`, avant tout fix) — ÉCHEC, `-downloadComponent` invalide,
   aucune version Xcode sélectionnée.
2. `31907788616` (commit `a66c509`, fixes CI seuls) — SUCCESS, confirme le pipeline lui-même.
3. `31908841925` (commit `e4b1832`, GAP-004 inclus) — SUCCESS, confirme GAP-004 compilable.
   (Un run intermédiaire sur `e48dbed` a échoué à cause d'un bug YAML auto-introduit par le 1er
   fix — corrigé avant ce run 3, voir `MIGRATION_AUDIT.md` section 12.)

### CI VALIDATION — format demandé par l'utilisateur pour chaque commit important

**Commit :** `e4b1832`
**GitHub Actions :** Build ID `31908841925` — Result **SUCCESS**
**Codemagic :** Build ID — (aucun, déclenchement manuel par l'utilisateur, en attente de retour)
**Double validation :** NO (GitHub seul pour l'instant)
**Erreurs GitHub :** 0
**Erreurs Codemagic :** N/A (pas encore lancé)
**Prochaine tâche :** voir section 10.

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
Non commité : CLAUDE_CONTINUATION.md (ce fichier — sera commité en fin de session, doc pure)
```

## 7. TESTS EFFECTUÉS

- **Vérification statique** (lecture manuelle) avant push : cohérence des types Swift, signatures
  d'appel, disponibilité API vs `deploymentTarget: 16.0`. Erreurs trouvées et corrigées AVANT de
  pousser (voir section 2, point 5).
- **Comparaison Android ↔ iOS** : chaque endpoint/champ/header vérifié contre le fichier Android
  source correspondant, lu en entier (pas deviné).
- **Compilation CI RÉELLE, GitHub Actions** : run `31908841925`, commit `e4b1832`, **SUCCESS**
  confirmé (`** BUILD SUCCEEDED **` dans le log brut), 10/10 fichiers GAP-004 confirmés présents
  dans les invocations de compilation par leur chemin complet. Voir section 0/0bis pour le détail.

## 8. TESTS IMPOSSIBLES/PAS ENCORE EFFECTUÉS

- **Compilation Codemagic** — en attente d'un déclenchement manuel par l'utilisateur sur le commit
  `e4b1832` (aucun credential Codemagic disponible dans cet environnement, voir section 0).
- Exécution sur simulateur/device — jamais depuis cet environnement Windows (pas de Xcode local).
- Test réseau réel (les 3 uploads de GAP-004 n'ont jamais touché un vrai serveur/CDN, seulement
  compilé).
- Test visuel (Appetize.io) des écrans modifiés (`ProfileView`, `CertificationView`, `ChatView`).
- Téléchargement des pièces jointes chat (fonctionnalité non implémentée, gap distinct de GAP-004).
→ **Rappel permanent de l'utilisateur, à ne jamais oublier** : "compile réellement" (atteint pour
GitHub Actions) ≠ "double validation CI" (Codemagic manquant) ≠ "fonctionnellement validé" (aucun
test réel, aucune des 3 fonctionnalités GAP-004 n'a jamais touché un serveur ou été vue à l'écran).

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

## 10. PROCHAINE TÂCHE EXACTE

**Ne PAS commencer GAP-003 — instruction explicite de l'utilisateur, toujours valable.** GAP-004
compile réellement (GitHub Actions), mais la "double validation CI" (règle permanente du projet à
partir de maintenant) n'est PAS encore atteinte pour le commit `e4b1832` — il manque Codemagic.

**Tâche exacte** :
1. **Attendre le retour de l'utilisateur sur son build Codemagic manuel** (commit `e4b1832`, même
   commit que GitHub Actions). Documenter son résultat dans la table CI VALIDATION (section 0) et
   dans `MIGRATION_AUDIT.md` section 12 dès qu'il est communiqué.
2. Si Codemagic échoue : appliquer la règle de diagnostic explicite de l'utilisateur — déterminer
   si c'est spécifique à Codemagic (corriger `codemagic.yaml` uniquement) ou un problème commun
   (Swift/dépendance/config projet, auquel cas GitHub Actions aurait dû aussi échouer — à
   réexaminer). Ne PAS dupliquer aveuglément un correctif GitHub-specific vers Codemagic sans
   preuve qu'il en a besoin.
3. Si Codemagic réussit aussi : double validation CI atteinte pour `e4b1832` — GAP-004 est alors au
   niveau maximal atteignable sans test réel (compilation confirmée 2×, toujours PAS "fonctionnel").
4. **Seulement après double validation** (ou décision explicite de l'utilisateur de continuer sans
   attendre Codemagic) : passer à GAP-003 (audit profond du Chat — Socket.IO événement par
   événement, messages texte/audio/photo/vidéo/fichier/statuts/pagination/cache/notifications,
   appels/WebRTC/CallKit, comportement offline/online — périmètre donné explicitement par
   l'utilisateur, voir son message dédié).

**Stratégie double-CI permanente à appliquer pour TOUTE la suite de la migration** (pas seulement
GAP-004) : pour chaque gros GAP, même séquence — implémentation Swift → commit → push → GitHub
Actions (moi) + Codemagic (utilisateur, manuel) sur le MÊME commit → analyse → correction ciblée
(le bon fichier CI selon la cause) → répéter jusqu'à double SUCCESS → GAP suivant.

## 11. HANDOFF — DERNIÈRE SESSION

**Session :** Claude Code (Sonnet 5), reprise sans mémoire, contexte reconstruit depuis Git +
documentation existante. 5ᵉ tour de cette même journée (2026-08-15).
**Date :** 2026-08-15
**Dernière tâche terminée :** GAP-004 (upload de fichiers) implémenté ET compilé réellement avec
preuve CI (GitHub Actions, run `31908841925`, commit `e4b1832`). Pipeline CI lui-même réparé (2
bugs trouvés et corrigés : sélection Xcode absente, puis bug YAML auto-introduit par le 1er fix).
Remote Git sécurisé (token retiré de l'URL, Git Credential Manager utilisé pour toute la suite).
Stratégie double-CI (GitHub Actions + Codemagic) adoptée comme règle permanente du projet.
**Travail effectué :** Sécurisation du remote + vérification qu'aucun fichier ne contient le token.
2 itérations de correctifs CI (commits `8aeb5a6`, `e48dbed`, `a66c509`) jusqu'à un run CI-only vert
(`31907788616`). Commit + push du code applicatif GAP-004 (`e4b1832`, après vérification explicite
qu'aucun secret n'était présent dans le diff). Build CI déclenché et suivi jusqu'au résultat réel :
SUCCESS, vérifié explicitement fichier par fichier (pas seulement le statut global).
**Travail actuellement en cours :** Aucun code en cours — en attente du retour utilisateur sur le
build Codemagic manuel (commit `e4b1832`).
**PROCHAINE TÂCHE EXACTE :** Voir section 10 ci-dessus.
**Fichiers modifiés :** Voir section 6 ci-dessus — TOUT est commité et poussé sauf ce fichier
(`CLAUDE_CONTINUATION.md`, doc pure, sera commité en fin de session).
**Fichiers à surveiller :** `.claude/worktrees/fix-splash-stuck` apparaît modifié dans le `git
status` du dépôt ANDROID (pas iOS) — une AUTRE session travaille en parallèle sur ce worktree
Android. Ne PAS y toucher, ne pas supposer son contenu.
**Bugs connus :** Voir section 5 (GAPs restants) + section 4 (download pièces jointes chat, pas
implémenté). Le token GitHub qui était dans l'URL du remote a été exposé une fois en clair dans
cette conversation avant sécurisation — **rotation recommandée, à confirmer avec l'utilisateur si
elle a été faite.**
**Tests effectués :** Voir section 7 — 1 compilation CI réelle réussie (GitHub Actions). AUCUN test
fonctionnel réel (section 8).
**Résultats :** GAP-004 compile réellement (niveau 1/3 : COMPILÉE). Pas encore DOUBLE VALIDATION CI
(niveau 2/3, Codemagic manquant). Pas encore FONCTIONNELLEMENT VALIDÉE (niveau 3/3, aucun test réel).
**Décisions techniques :** Voir section 9 + section 0/12 (stratégie double-CI, pourquoi
`codemagic.yaml` n'a pas été touché sans preuve qu'il soit cassé).
**Points importants :**
- Ne PAS refaire l'audit global — `MIGRATION_AUDIT.md`/`MIGRATION_PROGRESS.md` sont à jour et
  fiables.
- Ne PAS supposer qu'une fonctionnalité "DONE" a été testée fonctionnellement — voir section 0bis/8,
  seule la COMPILATION est confirmée pour GAP-004, jamais l'exécution réelle.
- Ne JAMAIS déclencher Codemagic soi-même sans credential réel — l'utilisateur le fait manuellement
  par choix explicite, ne pas prétendre l'avoir fait ou vérifié.
- Ne PAS dupliquer un correctif GitHub Actions vers `codemagic.yaml` sans preuve que Codemagic en a
  besoin (règle explicite de l'utilisateur).
- Tout est commité/poussé sauf ce fichier de continuité.
**Instructions pour la prochaine session :**
1. Lire ce fichier EN PREMIER, section 0/0bis en priorité absolue.
2. Vérifier qu'il correspond toujours au code réel (`git log`, `git status`) — une autre session a
   pu intervenir/pousser depuis.
3. Si l'utilisateur ne précise pas de priorité, demander le résultat de son build Codemagic manuel
   sur le commit `e4b1832` (section 10) — c'est la seule chose qui manque à la double validation CI,
   et l'utilisateur a explicitement interdit GAP-003 tant qu'elle n'est pas discutée/atteinte.
4. Mettre à jour ce fichier (sections 0, 0bis et 11) à la fin de la session, quel que soit le
   résultat.
