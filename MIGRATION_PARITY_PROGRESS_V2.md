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
**Run CI :** en cours de vérification (dispatché après ce commit)
**Statut AVANT (audit V2) :** `COMPLETE_PARITY_CANDIDATE` (cœur), gap silencieux non détecté
**Statut APRÈS :** `BUILD_VALIDATED` à confirmer par CI — commit `da89974` — test fonctionnel réel
toujours requis
**Preuve du changement de statut :** `ProfileRepository.fetchUserPosts`/`fetchHashtagPosts`
utilisaient `try? JSONDecoder().decode([FeedActivity].self, ...) ?? []` — un seul post au format
inattendu aurait vidé silencieusement toute la grille Profile. Remplacé par un décodage per-item +
diagnostic console (même motif que `FeedRepository.fetchTimeline`). Endpoint grille re-vérifié
contre `ProfileRepository.java:153` (identique). Chaîne Grid→tap→Fullscreen vérifiée intacte.

### 2026-08-17 — Chat/Messaging (P0-4) — Décodage per-item pour contacts + membres de groupe
**Commit(s) :** (à committer avec ce lot)
**Run CI :** à dispatcher après commit
**Statut AVANT (audit V2) :** `COMPLETE_PARITY_CANDIDATE` (création de groupe 3 écrans), historique
`FUNCTIONALLY_FAILED` déjà corrigé une fois pour la cause précise `userId` numérique
**Statut APRÈS :** `BUILD_VALIDATED` à confirmer par CI — test fonctionnel réel toujours requis
**Preuve du changement de statut :** Re-vérifié la chaîne FAB→`ContactPickerView`→`GroupCreationView`
intacte (aucune régression). Trouvé et corrigé un point de fragilité résiduel : `ContactsRepository.
connectedUsers` et `GroupRepository.fetchMembers` décodaient encore le tableau ENTIER via `try?`,
laissant la possibilité qu'UN SEUL contact/membre non conforme revienne à faire disparaître toute la
liste silencieusement — exactement la classe de bug déjà identifiée comme suspecte dans un commentaire
de code préexistant pour P0-F, mais dont seule la cause ponctuelle (pas le point de fragilité
structurel) avait été corrigée. Remplacé par le même motif per-item + diagnostic que Feed/Profile.
