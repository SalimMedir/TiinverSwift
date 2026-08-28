# MIGRATION PARITY PROGRESS V6

Journal chronologique du cycle V6 — audit uniquement, aucune correction encore appliquée.

## 2026-08-28 — Phase Audit V6 : 7 agents indépendants, 26 findings, aucune correction

**Contexte** : après la clôture du cycle V5 (99 findings, 84 `BUILD_VALIDATED`) et la phase de
validation par test physique (`PHYSICAL_DEVICE_VALIDATION_V5.md`, 8 bugs corrigés), l'utilisateur
a demandé un nouveau cycle d'audit ciblé sur 5 domaines prioritaires jamais ou insuffisamment
couverts par V5 : **Animems (editor/export/publish)**, **ChatGroup**, **Search**, **Promotion**,
**Video Statistics**, plus un balayage transversal des patterns de bugs que V5 avait lui-même
signalés comme sous-explorés.

**Méthodologie** : lecture préalable de `MIGRATION_PARITY_AUDIT_V5.md` (inventaire complet des 99
findings par domaine/statut via `grep`, pas une lecture intégrale des ~3800 lignes) pour bâtir la
liste de ce qui est déjà couvert/corrigé et éviter toute duplication. 7 agents de recherche
indépendants (`Explore`, isolation `worktree`, lecture seule) dispatchés en parallèle :
1. Animems Editor core (canvas/layers/timeline/barre du bas)
2. Animems Playback/Export/Publish
3. ChatGroup (avec archéologie git Android obligatoire en premier pour identifier
   l'amélioration récente mentionnée par l'utilisateur sans qu'il en connaisse le détail)
4. Search (incluant recherche de conversation/membres de groupe, jamais explorées par V5)
5. Promotion/Boost (0 finding V5 — domaine jamais audité)
6. Video Statistics (0 finding V5 — domaine jamais audité)
7. Balayage transversal (re-vérification des patterns double-tap/Combine/annulation réseau/
   badge d'icône/reconnexion socket que V5 avait signalés sous-cherchés + nouvelles catégories)

**Incidents techniques** : les 7 agents ont initialement échoué simultanément (erreurs de
connexion transitoires côté plateforme, pas liées à la tâche) et ont dû être relancés une fois ;
l'agent du balayage transversal a échoué 2 fois supplémentaires (dont une fois pour cause de
limite de session utilisateur, résolue après reset) avant d'aboutir à sa 4ᵉ tentative. Aucune
perte de contenu — chaque relance a repris avec le même prompt.

**Résultat** : 26 findings (V6-F-001 à V6-F-026) compilés dans `MIGRATION_PARITY_AUDIT_V6.md` —
5 P1, 13 P2, 8 P3, 0 P0. Plus 13 différences intentionnelles documentées (`IOS_INTENTIONAL_
DIFFERENCE`, section 4) et confirmation que **V5-F-082** (habillage promotionnel outro/watermark
Animems) reste `DIFFÉRÉ`, non corrigé, exactement comme documenté en V5.

**Découverte clé (ChatGroup, archéologie git)** : le commit Android le plus récent touchant
réellement le code groupe/chat (`c5c2c3d`) introduit une fonctionnalité "cadeau" (Gift) qu'Android
masque explicitement en conversation de GROUPE (`setVisibility(GONE)`) — côté iOS, le bouton est
affiché et pleinement câblé dans TOUS les contextes, groupe inclus, ET sans jamais débiter de
pièces (V6-F-010, P1).

**Découverte clé (Promotion)** : contrairement à l'hypothèse de départ ("peut-être juste une
coquille UI"), la fonctionnalité Boost est confirmée réellement câblée de bout en bout côté iOS
— mêmes formules de calcul, mêmes endpoints, et un traitement des échecs de paiement PLUS strict
qu'Android (échec fermé par défaut, contre un bug Android de blocage silencieux sur réponse
inattendue). Aucun risque de paiement refusé affiché comme un succès, contrairement au pattern
V5-F-031/032 qui avait motivé cette vérification approfondie.

**Découverte clé (Video Statistics)** : le pipeline client de suivi du temps de visionnage
(watch time/replay/exit point), qui alimente directement les métriques affichées par l'écran
Statistiques, est un module entier jamais porté (déjà connu comme différé "module 18" dans
`ViewEventRepository.swift`, mais son impact précis sur les métriques Statistiques n'avait
jamais été tracé jusqu'à ce cycle) — V6-F-019, P1, la finding la plus consequente du domaine.

**Découverte clé (Animems)** : le défilement vertical de la timeline est un mécanisme
entièrement porté (toute la logique de hit-testing/dessin le consulte) mais dont AUCUN geste ne
modifie jamais la valeur — la propriété reste bloquée à 0 en permanence (V6-F-001, P1). Combiné
au correctif V5 récent qui a rendu `trackCount == layers.count` (au lieu d'un plancher de 5), ce
défaut devient un blocage courant plutôt qu'un cas limite rare, puisque toute composition à plus
de calques que la hauteur visible de l'écran a désormais ses pistes excédentaires définitivement
hors d'atteinte.

**Découverte clé (Animems, playback)** : les keyframes de transformation sur un calque TEXTE ou
STICKER sont enregistrables sans aucun garde-fou de type, mais ne sont JAMAIS consultées par les
fonctions de rendu correspondantes (`drawText`/`drawSticker`), ni en aperçu ni à l'export — alors
que le pipeline équivalent pour bitmap/formes (`drawObjectFrame`) le fait déjà correctement
(V6-F-006, P1). Un utilisateur animant une légende ou un sticker ne voit RIEN se passer, sans
erreur.

**Découverte transversale la plus consequente** : le bouton "Publier" (partagé par le flux de
galerie standard ET par la publication d'un export Animems) pose sa garde anti-double-soumission
APRÈS un appel réseau de résolution de catégorie au lieu d'avant — fenêtre de double-tap réelle
pouvant produire deux publications serveur pour un seul tap (V6-F-024, P1).

**Statut** : `AUDIT_TERMINÉ` — aucune ligne de code Swift modifiée à ce stade, conformément à la
consigne explicite de l'utilisateur ("NE COMMENCE PAS PAR CORRIGER LE CODE"). Le rapport complet
(répartition, top 10, findings détaillés, `IOS_INTENTIONAL_DIFFERENCE`, limites honnêtes) a été
présenté à l'utilisateur pour décision de la phase de correction à suivre.

---

Ce fichier sera alimenté lot par lot au fur et à mesure des corrections V6, suivant exactement la
même discipline que `MIGRATION_PARITY_PROGRESS_V5.md` : vérifier Android, vérifier iOS, corriger
le minimum nécessaire, vérifier l'absence de régression, commit + push, déclencher CI, attendre
le résultat réel, mettre à jour les 3 documents (`MIGRATION_PARITY_AUDIT_V6.md`,
`MIGRATION_PARITY_PROGRESS_V6.md`, `CLAUDE_CONTINUATION.md`), passer au finding suivant.

---

## 2026-08-28 — Phase B : correction complète des 26 findings V6, en une session

**Contexte** : suite immédiate de la phase audit ci-dessus. Consigne explicite de l'utilisateur :
corriger TOUS les 26 findings du backlog, pas seulement un sous-ensemble, en suivant un ordre de
priorité donné (Animems P1 → ChatGroup → Search → Promotion → Video Statistics → Animems Export →
Transversal), sans s'arrêter pour demander confirmation entre chaque correction, en conservant les
builds/tests physiques (vérification statique/lecture de code d'abord), et en marquant chaque
finding `CODE_COMPLETE, CI_PENDING`/`DUPLICATE`/`IOS_INTENTIONAL_DIFFERENCE`/`DIFFÉRÉ` avec
précision — jamais `BUILD_VALIDATED` sans un run CI réellement vert.

**Résultat** : les 26 findings sont traités.
- **19 corrigés en code** (V6-F-001,002,003,004,006,007,008,010,011,012,013,014,015,016,018,019,
  020,021,022,023,024,025) — chacun `CODE_COMPLETE, CI_PENDING` dans `MIGRATION_PARITY_AUDIT_V6.md`.
- **3 `DIFFÉRÉS`** avec raison technique réelle documentée : V6-F-009 (pipeline de bake mort,
  confirmé comme la voie NON empruntée par le correctif V6-F-006 — nettoyage pur, hors scope) ;
  V6-F-017 (`boost/deliver` quotidien, dépend du chantier `BGTaskScheduler` déjà différé pour
  V5-F-060) ; V6-F-026 (watermark/outro sur téléchargement vidéo du fil, même infrastructure de
  post-traitement vidéo substantielle que V5-F-082, toujours différé).
- **1 `IOS_INTENTIONAL_DIFFERENCE`** décidé pendant la correction : V6-F-005 (panneau "Cadre"
  flipbook, système legacy Android déjà superseded côté iOS par `autoCaptureEnabled`).

**11 commits** créés sur `main`, chacun un lot cohérent par domaine/priorité :
1. `78aa601` — V6-F-001/002 (timeline scroll vertical, panneau Contrôle)
2. `96527fe` — V6-F-006 (keyframes texte/sticker)
3. `3eda927` — V6-F-007/024 (gardes anti-double-soumission export + publication)
4. `fbba1b4` — V6-F-010/011 (Gift en groupe verrouillé + débit réel, sons chat)
5. `a752c80` — V6-F-012/013/014 (recherche : jeton de génération, `.onSubmit`, navigation à vide)
6. `9f6cc24` — V6-F-015/016/018 (Boost : vignette, solde gemmes, auto-retry tableau de bord)
7. `c7339ea` — V6-F-020/021/022/023 (Statistiques : taux 3s, retry+scaffold, refresh, texte vide)
8. `df74e70` — V6-F-025 (badge icône système combiné chat+notifications)
9. `003096b` — V6-F-008 (échec explicite sur frame d'export perdue)
10. `2211b9f` — V6-F-019 (pipeline complet de suivi du temps de visionnage — délégué à un agent
    en arrière-plan avec contexte Android complet pré-digéré, pendant que la session principale
    traitait Statistiques/Transversal/Animems export en parallèle ; vérifié après coup : équilibre
    des accolades correct sur les 5 fichiers touchés, mapping Android→iOS documenté commit par
    commit)
11. `143e38f` — V6-F-003/004 (extraction audio comme musique de fond, réinitialisation identité réelle)

**CI** : déclenché 4 fois au total pendant cette phase (après le lot Animems P1, après ChatGroup+
Search, après Promotion+Statistiques+Transversal+Export+Editor), chaque run confirmé
`completed`/`success` avant de poursuivre — voir les IDs de run dans les messages de commit
`docs:` de clôture ci-dessous si présents, sinon dans l'historique GitHub Actions du dépôt.

**Décision notable (V6-F-012, recherche, défaut partagé Android/iOS)** : consigne explicite de ne
PAS corriger automatiquement un défaut partagé sans évaluation — jugé nécessaire ET sûr ici (jeton
de génération, ne change aucun comportement observable en fonctionnement normal, ne dépend d'aucun
changement Android), donc corrigé plutôt que laissé en l'état.

**Décision notable (V6-F-016, Boost, gemmes)** : principe explicite "sécurité/idempotence avant
parité visuelle" pour toute opération financière — écriture locale du solde conditionnée à
`useGems` au lieu de toujours écrire dans `coinsAmount` comme le fait Android, sans attendre
qu'Android soit lui-même corrigé.

**Statut** : cycle de correction V6 terminé pour les 26 findings. Reste : validation CI finale du
dernier lot, mise à jour de `CLAUDE_CONTINUATION.md`, vérification de la propreté de `git status`.
