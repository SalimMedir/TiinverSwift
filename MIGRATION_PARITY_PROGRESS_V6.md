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
