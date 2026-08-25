# MIGRATION PARITY PROGRESS V5

Journal de correction du cycle d'audit V5 (`MIGRATION_PARITY_AUDIT_V5.md`).

**État actuel (2026-08-24) : Phase A (Audit) TERMINÉE. Phase A.2 (contre-audit ciblé) TERMINÉE.
Phase B (correction) DÉMARRÉE — backlog P0 EN COURS (2/7 clos : V5-F-094, V5-F-018). Ordre imposé
par l'utilisateur : V5-F-094 en premier (priorité absolue explicite), puis les 6 autres P0 dans
l'ordre du document (V5-F-018 ✓, V5-F-031, V5-F-032, V5-F-042, V5-F-045, V5-F-064), puis
automatiquement les 40 P1, 31 P2, 21 P3.**

`MIGRATION_PARITY_AUDIT_V5.md` contient **99 findings** (V5-F-001 à V5-F-099) au total :

- **Phase A** (69 findings, V5-F-001 à V5-F-069) : produits par 23 agents de recherche
  indépendants (répartis sur autant de domaines fonctionnels) + 1 agent critique de complétude qui
  a passé en revue les 23 rapports pour repérer les zones sous-creusées et les patterns de bug
  systématiquement sous-cherchés (voir §3 de l'audit). Aucun agent n'a lu les audits V1/V2/V3/V4
  avant de produire ses findings.
- **Phase A.2** (30 nouveaux findings, V5-F-070 à V5-F-099, voir section "PHASE A.2" en fin
  d'audit) : contre-audit ciblé demandé explicitement par l'utilisateur pour vérifier les 8 zones
  signalées comme sous-creusées par l'agent critique de la Phase A (Socket.IO, Chat, pipeline
  média BunnyCDN — décomposé en 5 sous-domaines vérifiés séparément [avatar/photo-vidéo Feed/
  chat/Animems], Photo Editor, Animems Canvas) + 3 patterns transversaux (double action/
  idempotence, mémoire/concurrence, lifecycle). 12 agents indépendants, chacun recevant la liste
  des findings V5 déjà connus dans son périmètre pour éviter les doublons. **12 findings de la
  Phase A ont été reconfirmés indépendamment** (§A.2.2 de l'audit) — non recréés.

**AUCUN code source n'a été modifié pour produire cet audit, dans aucune des deux phases** —
conformément à la consigne explicite de l'utilisateur. Aucun finding n'a encore été corrigé.

Répartition finale (Phase A + A.2) : 7 P0, 40 P1, 31 P2, 21 P3. Voir `MIGRATION_PARITY_AUDIT_V5.md`
§0 pour la ventilation complète par statut suggéré, §1 pour le TOP 20 de la Phase A (le contre-audit
n'a pas été re-classé dans ce TOP 20), §2 pour le détail domaine par domaine de la Phase A, et la
section "PHASE A.2" en fin de document pour le détail complet du contre-audit (findings, findings
reconfirmés, couverture par domaine).

**Découverte la plus critique du contre-audit** : V5-F-094 (P0, `FUNCTIONALLY_FAILED`) — l'export
vidéo MP4 d'Animems (fonctionnalité de sortie principale du module) est totalement non fonctionnel
pour tout contenu animé : `AnimemesExporter` est capturé en `[weak self]` sur l'unique point
d'entrée de son pipeline d'écriture asynchrone, mais rien ne retient l'instance en vie pendant
cette durée (variable locale, pas de propriété stockée côté `AnimemesEditorState`) — l'objet est
désalloué par ARC avant que la closure GCD ne s'exécute, donc `self` vaut `nil` à chaque
invocation, aucune frame n'est écrite, `completion`/`isExporting` ne se déclenchent jamais :
l'export reste bloqué indéfiniment sans aucune erreur visible.

## 2026-08-24 — Phase B V5 — Lot P0-1 : V5-F-094 (BUILD_VALIDATED)

### Vérification

**Android** : `AnimemesCompound.java:259` (`MP4Encoder encoder;`, champ de la vue) et `:3317`
(`encoder = new MP4Encoder();`) — l'encodeur est un champ PERSISTANT de la vue, retenu pour toute
la durée de l'encodage tant que la vue existe, utilisé aux lignes 2624-2654
(`createVideosFromBitmap`).

**iOS avant correctif** : `AnimemesEditorState.export(canvasSize:completion:)` créait `exporter`
comme variable purement LOCALE. `AnimemesExporter.export(to:completion:)` enregistre son pipeline
vidéo via `videoInput.requestMediaDataWhenReady(on:using:)` (callback ASYNCHRONE rappelé plus tard
sur `videoQueue`) puis retourne immédiatement — `AnimemesEditorState.export(...)` retourne lui
aussi aussitôt après. Plus rien ne retenait alors `exporter` : ARC le désallouait avant le premier
rappel du callback, dont la capture `[weak self]` retrouvait systématiquement `self == nil` —
aucune frame jamais écrite, `completion` jamais invoquée, `isExporting` bloqué à `true`
indéfiniment, aucune erreur visible. Confirmé par lecture complète des 2 fichiers (227 lignes
d'`AnimemesExporter.swift` + le site d'appel).

### Correctif appliqué

Nouvelle propriété stockée forte `AnimemesEditorState.activeExporter: AnimemesExporter?`,
assignée juste avant `exporter.export(to:completion:)`, remise à `nil` dans la completion (succès
ET échec) — fidèle au champ persistant `encoder` d'Android. Diff strictement additif (1 propriété
+ 2 lignes), aucune ligne de logique de rendu/écriture/audio touchée. `exportStaticImage` (chemin
synchrone séparé pour l'export d'image statique) intégralement inchangé.

### Garanties vérifiées (demandées explicitement par l'utilisateur)

- Export image inchangé — `exportStaticImage` non touché.
- Export MP4 fonctionnel — le pipeline complet peut désormais s'exécuter jusqu'au bout, `self`
  restant valide tout du long.
- Toutes les frames écrites — la boucle `while videoInput.isReadyForMoreMediaData` n'est plus
  interrompue prématurément.
- Completion toujours appelée — les 3 points de sortie du pipeline atteignent désormais
  réellement la completion d'`AnimemesEditorState`.
- `isExporting` toujours réinitialisé — `self.isExporting = false` s'exécute dans tous les cas.
- Erreur correctement propagée — la branche `.failure` continue de positionner `exportError`.
- Aucune régression du pipeline existant — diff strictement additif.

### Flux frères vérifiés

Un seul site de construction d'`AnimemesExporter` et 2 sites d'appel de `export(canvasSize:)` dans
tout le projet (les 2 boutons "Exporter la vidéo" d'`AnimemesEditorView.swift`), tous deux passent
par la même fonction corrigée.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/AnimemesEditorState.swift`.

**Résultat CI** : commit `f5b7fbd`, push confirmé (`a85063a..f5b7fbd main -> main`), run
`32888135380` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis (aucun accès Xcode/simulateur/device) : ajouter un
calque animé, taper "Exporter la vidéo", confirmer qu'un MP4 valide est produit (frames + son si
piste audio ajoutée), que le spinner disparaît à la fin, et qu'un export raté affiche `exportError`
plutôt que de rester bloqué indéfiniment.

## 2026-08-24 — Phase B V5 — Lot P0-2 : V5-F-018 (BUILD_VALIDATED)

### Vérification

**Android — approfondie au-delà de la citation de l'audit** : `mLayoutManager.setStackFromEnd(true)`
positionne implicitement en bas au chargement initial (`ChatFragmentTest.java:539`).
`addMessage`/`onOldMessage`→`addOldMessage` (message envoyé localement OU reçu en direct par
socket — `:2678-2717,2001-2065`, PAS des noms trompeurs : `addOldMessage` gère en réalité les
messages socket "en retard", pas la pagination REST) appellent explicitement
`smoothScrollToPosition(getItemCount()-1)`. **Point clé vérifié personnellement, absent de la
citation d'audit initiale** : `displayMoreMessageOnScroll` (`:1645-1758`, le VRAI gestionnaire de
pagination, déclenché par `onScrolled`/`!canScrollVertically(-1)`) N'APPELLE PAS ce scroll — il
insère les anciens messages en tête (`messages.add(0, mlib)`) et laisse le `LinearLayoutManager`
préserver nativement la position de lecture pendant un prépend. La RECOMMANDATION de l'audit
restait incertaine sur ce point ; la vérification personnelle confirme qu'un scroll inconditionnel
sur CHAQUE ajout (y compris pagination) aurait été infidèle à Android.

**iOS avant correctif** : `ChatView.messageList` était un `List` SwiftUI classique sans
`ScrollViewReader` ni aucun mécanisme de scroll. La conversation s'ouvrait sur les messages les
PLUS ANCIENS de la page chargée. Pire : le premier item (le plus ancien) déclenchait immédiatement
son `.onAppear` → `loadMore()`, qui préfixait une page supplémentaire dont le nouveau premier
élément redevenait visible en haut, redéclenchant `loadMore()` en cascade — chargement de tout
l'historique de la conversation avant toute interaction utilisateur.

### Correctif appliqué

`messageList` entourée d'un `ScrollViewReader`, scroll vers `viewModel.items.last?.id` dans
`.onChange(of:)`. Ce signal ne se déclenche JAMAIS pendant `loadMore()` (insère exclusivement à
l'index 0 — le dernier élément ne change donc jamais), mais se déclenche pour le chargement initial
(`items` vide → peuplé) et tout ajout en fin de liste (`onIncoming`/`appendOptimistic`) —
reproduisant exactement la distinction Android vérifiée ci-dessus, sans flag/garde supplémentaire
côté ViewModel.

**Effet de bord positif confirmé** : résout AUSSI la cascade de pagination — une fois la vue
effectivement scrollée en bas au chargement, le premier item n'est plus dans le viewport visible,
donc son `.onAppear` ne se déclenche plus immédiatement à l'ouverture.

### Flux frères vérifiés

`grep "List {"` dans `Sources/TiinverSwift/Messagerie` → `ChatSearchView`/`GroupDetailView`/
`PrivateMessageSettingView`/`RosterListView` — aucun n'est un historique de messages avec
équivalent de `stackFromEnd` côté Android, pas de site frère à corriger.

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/ChatView.swift`.

**Résultat CI** : commit `5964e87`, push confirmé (`61d96f6..5964e87 main -> main`), run
`32889479501` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : ouvrir une conversation avec plus d'une page
d'historique, confirmer l'affichage immédiat des messages les plus récents sans scroll manuel ;
confirmer via l'inspecteur réseau qu'aucune requête de pagination en cascade ne se déclenche avant
toute interaction ; remonter manuellement l'historique et confirmer que la position de lecture est
préservée pendant le chargement d'anciens messages ; envoyer/recevoir un message en direct et
confirmer le scroll automatique vers le bas.

Ce fichier sera alimenté lot par lot, dans le même format que `MIGRATION_PARITY_PROGRESS_V4.md`.

Pour chaque lot futur, le format attendu est :

```
## <date> — Phase B V5 — Lot N : <ID> (<titre court>)

**Commit** : `<sha>` — CI **<résultat>**.

**Cause exacte** : ...

**Fichiers modifiés** : ...

**Flux frère vérifié** : ...

**Statut honnête** : `BUILD_VALIDATED` (CI verte) — PAS `COMPLETE_PARITY_VALIDATED` (device-test
requis, indisponible dans cet environnement) sauf indication contraire explicite de l'utilisateur.
```

Règles strictes héritées du cycle V4, à respecter identiquement pour V5 :
- Ne pas corriger un finding uniquement parce qu'il est marqué. Vérifier d'abord qu'il s'agit
  réellement d'une différence Android/iOS (Android source de vérité, mais jamais de code mort).
- Si le finding est déjà corrigé par un autre commit (dont un correctif V4), marquer
  doublon/résolu, ne pas modifier le code inutilement.
- Si le problème dépend du backend, d'Apple Developer, d'un serveur ou d'un test physique
  impossible à réaliser actuellement, marquer `BLOQUÉ` avec la raison précise.
- Ne jamais transformer `BUILD_VALIDATED` en `COMPLETE_PARITY_VALIDATED` sans test réel confirmé.
