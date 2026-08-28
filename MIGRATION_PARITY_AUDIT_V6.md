# MIGRATION PARITY AUDIT V6

Audit indépendant Android → iOS du portage Tiinver, ciblé sur 5 domaines prioritaires
(**Animems editor / export / publish**, **ChatGroup**, **Search**, **Promotion**, **Video
Statistics**) + un balayage transversal. Phase AUDIT SEULE — **aucune modification de code**.
7 agents de recherche indépendants (5 domaines + pipeline Animems scindé en 2 + 1 balayage
transversal), chacun lisant Android en premier comme référence comportementale réelle
(code atteignable uniquement, jamais mort/commenté), sans reproduire aveuglément un bug Android
identifié comme tel (`IOS_INTENTIONAL_DIFFERENCE`).

Construit sur `MIGRATION_PARITY_AUDIT_V5.md` (99 findings, V5-F-001 à V5-F-099) — méthodologie
identique, IDs V6-F-001 à V6-F-026, **jamais de réutilisation des IDs V5**. Chaque agent a reçu
la liste des findings V5 déjà couverts dans son domaine pour éviter toute duplication ; les
domaines Promotion et Video Statistics n'avaient AUCUNE couverture V5 (confirmé par grep
exhaustif de `MIGRATION_PARITY_AUDIT_V5.md` — aucune section "Statistique"/"Boost"/"Promotion").

## 0. Sommaire

**26 findings** (V6-F-001 à V6-F-026).

### Répartition par priorité
- **P0** : 0
- **P1** : 5
- **P2** : 13
- **P3** : 8

### Répartition par domaine
- **Animems (editor/playback)** : 6 (V6-F-001 à 006)
- **Animems Export** : 3 (V6-F-007 à 009)
- **ChatGroup** : 2 (V6-F-010, 011)
- **Search** : 3 (V6-F-012 à 014)
- **Promotion** : 4 (V6-F-015 à 018)
- **Video Statistics** : 5 (V6-F-019 à 023)
- **Transversal (Other)** : 3 (V6-F-024 à 026)

### Statut d'un finding V5 toujours ouvert (rappel, pas un nouvel ID)
**V5-F-082** (habillage promotionnel outro + watermark animé à l'export/partage Animems) —
vérifié par l'agent Export/Publish comme **toujours `DIFFÉRÉ`**, non corrigé, exactement comme
documenté dans `MIGRATION_PARITY_AUDIT_V5.md` (aucun code modifié depuis). Rapporté ici pour
exactitude, ne compte pas dans les 26 findings V6.

---

## 1. TOP 10 — Problèmes les plus critiques

1. **V6-F-024** [P1] Bouton "Publier" (post ET export Animems, `PublishComposeView.swift`) : la
   garde anti-double-soumission (`isPublishing`) est posée APRÈS un appel réseau
   (`fetchProfile` pour résoudre la catégorie), pas avant — fenêtre de double-tap réelle pouvant
   créer 2 publications côté serveur pour un seul tap.
2. **V6-F-006** [P1] Les keyframes matricielles (position/rotation/scale) sur un calque
   TEXTE ou STICKER sont enregistrables mais ne sont JAMAIS lues au rendu — ni en aperçu, ni à
   l'export — silencieusement, sans erreur.
3. **V6-F-010** [P1] Le bouton d'envoi de cadeau ("Gift") est affiché et pleinement câblé dans
   les conversations de GROUPE côté iOS, alors qu'Android le masque explicitement dans ce
   contexte — ET la version iOS n'appelle jamais l'endpoint de débit de pièces, contrairement à
   Android.
4. **V6-F-019** [P1] Le pipeline de suivi du temps de visionnage (watch time/replay/exit
   point), qui alimente les métriques mêmes affichées par l'écran Statistiques, est
   entièrement absent côté iOS — toute activité de visionnage sur iOS n'est jamais remontée au
   serveur.
5. **V6-F-001** [P1] Le défilement VERTICAL de la timeline Animems est totalement mort côté
   iOS (propriété jamais modifiée par aucun geste) — dès qu'une composition a plus de calques
   que la hauteur visible (cas courant depuis le correctif V5 du nombre de pistes), les pistes
   hors écran sont définitivement inaccessibles.
6. **V6-F-002** [P2] Le panneau "Contrôle" (ajustement précis par curseurs — zoom/rotation
   /inclinaison/point d'ancrage) est entièrement absent côté iOS, alors que le bouton
   correspondant existe côté Android et est pleinement fonctionnel.
7. **V6-F-020** [P2] La métrique "taux de vue à 3 secondes" est absente de l'écran
   Statistiques iOS (le champ est décodé mais jamais affiché).
8. **V6-F-021** [P2] Un échec réseau au chargement des Statistiques affiche un écran
   totalement vide côté iOS (aucune section), contre un affichage "--" complet + une
   nouvelle tentative automatique côté Android.
9. **V6-F-007** [P2] Aucune garde de ré-entrance sur `AnimemesEditorState.export()` — un
   second appel concurrent (double-tap rapide) écraserait silencieusement l'exporteur en cours,
   dont la fermeture est capturée faiblement (`self` faible), abandonnant le premier export sans
   jamais appeler sa complétion.
10. **V6-F-012** [P2] Course de réponses obsolètes dans la recherche universelle — un ancien
    résultat plus lent qu'une frappe plus récente peut écraser l'affichage courant. **Défaut
    partagé identique sur les DEUX plateformes** (ni régression ni amélioration iOS), documenté
    car explicitement demandé par la mission.

---

## 2. Domaines couverts

### Animems — Editor core (Canvas/Layers/Timeline/Toolbar)
**Couvert** : création de projet (comparaison partielle, voir non-exploré), structure de
timeline (scroll horizontal/vertical, pinch-zoom, drag/resize anti-chevauchement, sélection,
keyframes), calques (verrouillage/visibilité/duplication/suppression/réinitialisation), les 13
boutons de la barre du bas un par un (chaîne UI→action→état→résultat, pas seulement présence de
l'icône). **Findings** : 5 (V6-F-001 à 005).
**Non exploré en profondeur** : dimensions/orientation/FPS initiaux du canevas (voir V6-F-A
ci-dessous, signalé comme différence possiblement intentionnelle non confirmée) ; rotation/
opacité/z-order fin pour les types vidéo/audio spécifiquement ; édition photo/texte au-delà
d'une re-vérification de non-régression des correctifs V5.

### Animems — Playback / Export / Publish
**Couvert** : chaîne complète Play→timer→currentTime→keyframes→interpolation→renderer→canvas
(comparée ligne à ligne côté moteur d'interpolation) ; pipeline d'export Canvas→AVAssetWriter→
MP4 (frames, FPS, résolution, codec, audio, complétion, mémoire, arrière-plan) ; flux de
publication (titre, hashtags, métadonnées, progression d'upload, continuité arrière-plan,
double-soumission). **Findings** : 3 nouveaux (V6-F-006 à 009 — 006 en Playback, 007-009 en
Export) + re-confirmation que V5-F-082 (outro/watermark) reste non corrigé.
**Non exploré** : rendu MP4 binaire réel (lecture dans un lecteur tiers, synchronisation A/V en
pratique) — nécessite un run réel, hors de portée statique.

### ChatGroup
**Couvert** : archéologie git Android ciblée (commit le plus récent touchant réellement le
code groupe/chat identifié et lu en entier) ; messages/temps réel/pagination/media/
notifications pour le contexte GROUPE spécifiquement. **Findings** : 2 (V6-F-010, 011).
**Non exploré** : re-vérification indépendante complète de `SocketInit.java` actuel (le
budget de cette passe a été consommé par l'archéologie git requise en premier) ; courses de
duplication/perte de message pendant une reconnexion (déjà couvert par le balayage
transversal, résultat : symétrique, pas un défaut iOS).

### Search
**Couvert** : recherche universelle (course de réponses obsolètes, encodage, soumission
explicite, historique récent) ; recherche de conversation/chat et de membres de groupe
(domaines explicitement NON explorés par V5). **Findings** : 3 (V6-F-012 à 014) + 5
`IOS_INTENTIONAL_DIFFERENCE` documentées (bugs Android non reproduits, ou améliorations iOS).
**Non exploré** : rien de significatif signalé comme manqué par l'agent.

### Promotion / Boost
**Couvert** : domaine à 0 finding V5 (jamais audité). Chaîne complète UI→éligibilité→
configuration→paiement→confirmation→tableau de bord→annulation→notifications, vérifiée
champ par champ contre `CreateBoostFragment.java`/`BoostDashboardFragment.java`. **Verdict
explicite demandé** : la fonctionnalité EST réellement câblée de bout en bout côté iOS (pas
une coquille UI), avec un traitement des échecs de paiement plus strict qu'Android (échec
fermé, pas de risque de succès silencieux sur un paiement refusé). **Findings** : 4
(V6-F-015 à 018) + 4 `IOS_INTENTIONAL_DIFFERENCE`.

### Video Statistics
**Couvert** : domaine à 0 finding V5 (jamais audité). Chaîne complète API→JSON→modèle→
repository→state→UI pour chaque métrique ; comparaison champ par champ des 14 champs du
modèle. **Findings** : 5 (V6-F-019 à 023) + 2 `IOS_INTENTIONAL_DIFFERENCE` (bugs Android non
reproduits, en faveur d'iOS).
**Non exploré** : magnitude réelle du sous-comptage causé par V6-F-019 (nécessite des données
réelles cross-plateforme).

### Transversal (patterns sous-cherchés par V5 + nouvelles catégories)
**Couvert** : re-vérification indépendante des patterns que V5 avait lui-même signalés comme
sous-explorés (double-tap sur boutons monétaires/irréversibles, rétention mémoire Combine,
annulation réseau à la navigation, badge icône app vs badge in-app, fenêtre de
duplication/perte de message à la reconnexion socket) + balayage neuf (navigation, états de
chargement, pagination, exécution en arrière-plan, accessibilité). **Findings** : 3
(V6-F-024 à 026). La plupart des patterns re-vérifiés se sont avérés **déjà corrects** (Like/
Follow/Send/Buy-coins/Boost tous protégés ; 0 fuite mémoire Combine trouvée sur les 3 sites
`.sink` du projet ; reconnexion socket symétrique, pas un défaut iOS) — évidence négative
précieuse, documentée dans le détail des findings.
**Non exploré** : sweep exhaustif de tous les sites `Task {` du projet pour l'annulation à la
navigation (V5 avait déjà signalé cette limite, non résolue ici) ; accessibilité au-delà d'une
reconfirmation qu'elle reste un point aveugle total (0 `accessibilityLabel` dans tout le
projet).

---

## 3. Findings détaillés

```
ID : V6-F-001
PRIORITÉ : P1
DOMAINE : Animems — Timeline (défilement vertical)
FEATURE : Le défilement vertical de la timeline (pour révéler les pistes hors du cadre visible) ne fonctionne jamais côté iOS
ANDROID SOURCE : TimelineView.java:104 (champ `scrollTracksPx`), :938-951 (`onMove`, branche `Mode.PAN` : un geste de pan sur une zone vide de la timeline défile verticalement si `|dy| > |dx|`, horizontalement sinon) ; `maxScrollTracksPx` calculé à partir de `trackCount * (trackHeight+gap) - visibleHeight` (:501).
ANDROID BEHAVIOR : Un balayage vertical sur une zone vide de la timeline révèle les pistes situées sous le pli, dès que le nombre de pistes dépasse ce qui tient à l'écran.
IOS FILES : TimelineViewModel.swift:40 (`scrollTracksPx: CGFloat = 0`) ; TimelineView.swift:263-276 (case `.pan`).
IOS BEHAVIOR : `scrollTracksPx` est LU par tout le code de hit-testing/dessin (icônes, rectangles d'item, marqueurs de keyframe) mais n'est JAMAIS ASSIGNÉ par aucun geste — `TimelineView.swift`'s case `.pan` ne lit que `value.translation.width`, jamais `.height`, et `TimelineViewModel.pan(...)` n'a qu'une formule horizontale. Aucune branche dx-vs-dy équivalente à Android.
CAUSE : Le mécanisme de défilement vertical (propriété + tout le hit-testing qui la consulte) a été porté, mais AUCUN geste ne le déclenche — la seule branche de pan portée est horizontale.
IMPACT : Dès qu'une composition a plus de calques que la hauteur visible de la timeline (cas courant depuis que `trackCount == layers.count`, ex. fond + texte + 2-3 stickers), les pistes au-delà du pli sont dessinées hors écran et DÉFINITIVEMENT inaccessibles : icônes verrou/visibilité, drag/resize par poignée, tap sur diamant de keyframe — tout est inatteignable pour ces calques. La sélection tactile directe sur le canevas reste un palliatif partiel pour les actions dépendant de la sélection (barre du bas), mais pas pour les interactions propres à la timeline.
REPRODUCTIBILITÉ : Certaine par lecture de code (la propriété n'est provablement jamais mutée par aucun geste).
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter la branche verticale manquante dans `TimelineView.swift`'s case `.pan`/`TimelineViewModel.pan(...)`, en miroir de la logique dx-vs-dy d'Android.
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V6-F-002
PRIORITÉ : P2
DOMAINE : Animems — Barre du bas (panneau "Contrôle")
FEATURE : Le panneau de curseurs "Contrôle" (zoom/rotation/inclinaison/haut/bas/gauche/droite/point d'ancrage) est totalement absent côté iOS
ANDROID SOURCE : compound_animemes_layout.xml:737-761 (`controller_c`/`controlle_movement`, icône `gamepad_24px`, libellé `@string/control`) ; handler AnimemesCompound.java:1857-1873 — bascule `movement_controller_view` et révèle `btn_keyframe`, masque `frameList`/`timelineView`.
ANDROID BEHAVIOR : Bouton réel de la barre du bas ouvrant un panneau de curseurs pour un ajustement précis/incrémental (alternative au geste tactile direct), avec capture explicite de keyframe via ◆ dans ce mode.
IOS FILES : MovementControllerState.swift (fichier entier).
IOS BEHAVIOR : Le fichier définit la structure/état mais n'est JAMAIS instancié ni référencé nulle part dans `AnimemesEditorView.swift`/`AnimemesEditorState.swift` (grep confirmé, zéro site d'appel en dehors de la déclaration elle-même). Aucun bouton, aucun panneau — fonctionnalité totalement invisible, pas seulement inerte.
CAUSE : État porté mais jamais câblé à une UI.
IMPACT : Perte du flux d'ajustement précis par curseurs. Le geste tactile direct (déjà porté) reste un palliatif partiel.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Construire le panneau de curseurs manquant et le câbler au bouton "Contrôle" de la barre du bas, en réutilisant `MovementControllerState` déjà porté.
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V6-F-003
PRIORITÉ : P2
DOMAINE : Animems — Barre du bas ("Extraire")
FEATURE : Extraction de la piste audio d'une vidéo importée, pour l'utiliser comme musique de fond — fonctionnalité entièrement absente côté iOS
ANDROID SOURCE : compound_animemes_layout.xml:790-813 (`extract_c`/`extract`) ; handler AnimemesCompound.java:2027-2028 → `onExtracSonFromVideo()` (MemesFragment.java:376-378) → sélecteur vidéo système → `audioToExtractUri(data)` (AnimemesCompound.java:2165-2182) → dialogue `ExtracAudioFromVideo` (extraction/découpe) → définie comme musique de fond de la composition.
ANDROID BEHAVIOR : Bouton réel, chaîne complète et atteignable.
IOS FILES : aucun — grep de `audioToExtract`/`extractAudio`/`ExtracAudio` dans `Sources/TiinverSwift/Animems/` retourne zéro fichier.
IOS BEHAVIOR : Absence totale — pas seulement un bouton non câblé, aucune trace de logique d'extraction nulle part.
CAUSE : Fonctionnalité jamais portée.
IMPACT : Impossible de réutiliser la bande sonore d'une vidéo comme musique de fond directement depuis l'éditeur.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Porter la chaîne sélection vidéo → extraction audio (AVAssetExportSession) → définition comme piste audio de fond.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Nouveau bouton "extraire" (barre du bas) → sélecteur vidéo dédié (`GalleryPickerView`, nouveau filtre `.videos` optionnel) → `AnimemesEditorState.extractAudioAsBackgroundMusic(from:)` (`AVAssetExportSession`, préréglage `AppleM4A`, même pattern `withCheckedContinuation` que `MediaTrimView`) → `audioURL` défini sur succès (même point d'entrée que "Ajouter un son"). Portée réduite documentée : le dialogue de découpe temporelle Android (`ExtracAudioFromVideo`) n'est pas porté — la piste audio COMPLÈTE est extraite, aucune UI de recadrage temporel Animems n'existant côté iOS pour l'instant (même limitation déjà assumée pour l'import vidéo en calque, V5-F-034) ; couvre le cas d'usage principal sans le raffinement de découpe.
```

```
ID : V6-F-004
PRIORITÉ : P2
DOMAINE : Animems — Barre du bas ("Réinitialiser")
FEATURE : "Réinitialiser" ne réinitialise pas réellement la position/rotation/échelle du calque sélectionné, contrairement à Android
ANDROID SOURCE : AnimemesCompound.java:2151-2158 (`item.endFrame = 1` + `mView.resetItemById(item.id)`) → MemesView2.java:516-533 — remplace `transforms` par UN SEUL nouveau `Transform` enveloppant une `Matrix()` IDENTITÉ (position/échelle/rotation/inclinaison remises à l'origine non transformée) et vide `maskTransforms`.
ANDROID BEHAVIOR : Le calque saute visiblement à sa position/échelle/rotation par défaut, et son clip timeline se réduit à un stub (~2 frames).
IOS FILES : AnimemesEditorState.swift:781-788 (`resetSelected()`).
IOS BEHAVIOR : `if let last = obj.transforms.last { obj.transforms = [last] }` — CONSERVE la pose actuelle/dernière (ne réinitialise PAS à l'identité) + `clearAllKeyframes()` ; ne touche ni `endFrame` ni la largeur du clip timeline.
CAUSE : Le correctif iOS ne fait que retirer l'animation keyframe, sans reproduire le retour à la pose d'origine.
IMPACT : Un utilisateur s'attendant au comportement Android ("retour au point de départ") obtient un résultat différent et plus limité (seule l'animation est retirée, pas la pose).
REPRODUCTIBILITÉ : Certaine par lecture de code, sans ambiguïté des deux côtés.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Faire pointer `resetSelected()` vers une transformation identité (position/échelle/rotation d'origine du calque), pas la dernière pose, et réduire `durationFrames`/`endFrame` en cohérence avec Android.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. `resetSelected()` remplace désormais `transforms` par un `Transform()` identité neuf (miroir exact de `new Transform()` + `Matrix()` identité côté Android), réduit `endFrame` à `startFrame` (stub d'une frame — PAS le littéral `1` d'Android, une valeur ABSOLUE invalide pour un calque dont `startFrame > 1` ; `obj.startFrame` produit le même effet de stub sans ce risque), et appelle `clearMaskTransforms()` en plus de `clearAllKeyframes()` (manquant jusqu'ici, port de `objectData.clearMaskTransforms()`).
```

```
ID : V6-F-005
PRIORITÉ : P3
DOMAINE : Animems — Barre du bas ("Cadre")
FEATURE : Le panneau "Cadre" (liste de frames façon stop-motion, héritée) est totalement absent côté iOS
ANDROID SOURCE : compound_animemes_layout.xml:763-788 (`stack_c`/`stack`) ; handler AnimemesCompound.java:1887-1895 bascule `frameList` — un système "legacy" distinct du système principal de keyframes/composer (`FrameAdapter`, `frames: List<AnimationComposer>`).
ANDROID BEHAVIOR : Bouton réel, ouvre un panneau de capture image-par-image façon flipbook.
IOS FILES : FrameListState.swift (fichier entier) — jamais instancié nulle part (grep confirmé).
IOS BEHAVIOR : Absent, aucun bouton.
CAUSE : Non porté. iOS a de toute façon déjà divergé volontairement vers un modèle différent (`autoCaptureEnabled`, keyframe automatique en fin de glisser, `AnimemesEditorState.swift:70-77`), documenté comme choix délibéré.
IMPACT : Mineur — chemin "legacy" côté Android, potentiellement moins pertinent à reproduire fidèlement vu la divergence déjà assumée du modèle de capture.
REPRODUCTIBILITÉ : Certaine (absence) ; pertinence du portage à juger au cas par cas.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Décision produit à prendre avant correction — porter fidèlement, ou documenter comme `IOS_INTENTIONAL_DIFFERENCE` étant donné la divergence déjà assumée du modèle de capture.
STATUT : IOS_INTENTIONAL_DIFFERENCE — décidé 2026-08-28, aucun changement de code. Panneau "Cadre" un système "legacy" côté Android lui-même (chemin distinct du composer/keyframes principal) ; iOS a déjà une divergence délibérée et documentée (`autoCaptureEnabled`, keyframe automatique en fin de glisser) couvrant le même besoin (capture image-par-image façon flipbook) par un mécanisme différent et déjà choisi. Construire un second panneau dupliquant un chemin legacy déjà superseded côté Android n'apporterait rien — cohérent avec la règle explicite de ne jamais reproduire un mécanisme uniquement pour la parité quand iOS a déjà une solution équivalente ou meilleure.
```

```
ID : V6-F-006
PRIORITÉ : P1
DOMAINE : Animems — Playback/Export (rendu des keyframes matricielles Texte/Sticker)
FEATURE : Une keyframe de transformation (position/rotation/échelle) enregistrée sur un calque TEXTE ou STICKER n'est JAMAIS lue au rendu, ni en aperçu ni à l'export
ANDROID SOURCE : `MP4Encoder.renderSceneIntoFbo` (MP4Encoder.java:347-485) — boucle de rendu par frame UNIFORME, sans distinction de type de calque, lecture de `obj.getTransforms().get(local)` pour CHAQUE calque. `AnimemesCompound.applyInterpolation()` (bake des keyframes `PROP_MATRIX` dans `obj.transforms`, AnimationEngine.java:250-303) est appelé à ~15 sites de mutation dans AnimemesCompound.java (lignes 832, 1276, 1340, 1387, 1446, 1477, 1679, 2912, 2936, 3441, 3559, 3640, 3664, 3840, 3940) — chaque édition structurelle re-bake `obj.transforms` pour TOUS les calques, texte/sticker inclus.
ANDROID BEHAVIOR : L'aperçu EN COURS D'ÉDITION n'anime pas non plus le texte/sticker (Android utilise aussi `getTransforms().get(count-1)` — dernière transform — pendant l'édition, `MemesView2.writeText`/`drawShap`) — mais l'EXPORT final, via la boucle uniforme + le bake pervasif, anime probablement bel et bien ces calques dans le MP4 produit.
IOS FILES : LayerRenderer.swift:219-267 (`drawText`), :288-296 (`drawSticker`), comparer à `drawObjectFrame` (:122-199, utilisé pour bitmap/formes, qui LIT bien les keyframes matricielles via `interpolatedMatrixValues(at:)`). Chemin de bake `AnimationEngine.applyInterpolation(composer:)` jamais appelé nulle part dans l'app (grep exhaustif : seule sa déclaration + 3 commentaires notant la non-implémentation délibérée pour bitmap/forme, où le rendu direct des keyframes en direct contourne le bake).
IOS BEHAVIOR : `drawText`/`drawSticker` utilisent `obj.transforms.last` sans condition, ne consultent JAMAIS `interpolatedMatrixValues`/`hasTransformKeyframes`. `AnimemesEditorState.recordKeyframe()`/`dragEnded()` n'ont AUCUN filtre par type d'objet — l'utilisateur PEUT sélectionner un texte/sticker, le transformer, enregistrer une keyframe matricielle, qui est stockée silencieusement mais jamais consultée par les 2 seules fonctions de rendu pour ce type. Contrairement à Android, il n'existe côté iOS AUCUN chemin (ni direct, ni bake) capable de faire bouger un calque texte/sticker.
CAUSE : `LayerRenderer.drawText`/`drawSticker` n'ont jamais été mis à jour pour consulter les keyframes matricielles comme `drawObjectFrame` le fait déjà pour bitmap/formes ; et le pipeline de bake (`applyInterpolation`) qui aurait pu compenser côté export n'a jamais été câblé non plus.
IMPACT : Un utilisateur animant une légende texte ou un sticker (flux plausible et courant — ex. une étiquette "appuyez ici" animée) voit son animation ne rien faire du tout, silencieusement, en aperçu ET dans la vidéo exportée — sans erreur, sans indice visuel.
REPRODUCTIBILITÉ : Certaine par lecture de code pour la moitié "iOS ne rend jamais" ; probable (non prouvée par exécution) pour la moitié "Android rend bien à l'export" — NEEDS_PHYSICAL_VALIDATION sur un vrai build Android pour confirmer visuellement le mouvement dans le MP4 exporté.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Faire consulter à `drawText`/`drawSticker` les keyframes matricielles comme `drawObjectFrame` le fait déjà (lecture directe en direct, cohérent avec le reste du moteur — pas besoin de câbler le bake mort `applyInterpolation` pour ces deux types).
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28 (commit 96527fe). `drawText`/`drawSticker` acceptent désormais un `currentNs: Int64?` optionnel et reproduisent exactement le repli `hasTransformKeyframes`/`interpolatedMatrixValues` de `drawObjectFrame`. Câblé dans la boucle de rendu canevas EN DIRECT (`AnimemesEditorView.canvasArea`, `currentNs: ns` = playhead courant) ET dans la boucle d'export MP4 (`AnimemesExporter.render(frame:into:)`, `currentNs` = timestamp de la frame réellement encodée) — donc corrigé en aperçu ET à l'export, comme demandé. Les deux sites d'aplatissement statique (`exportStaticImage`, `repeatBackgroundImage`) omettent délibérément `currentNs` (défaut `nil`) pour conserver leur comportement "dernière transform" existant, cohérent avec leurs appels `drawLastTransform(..., isSliderPreview: true)` voisins.
```

```
ID : V6-F-007
PRIORITÉ : P2
DOMAINE : Animems — Export (ré-entrance)
FEATURE : Aucune garde de ré-entrance sur `AnimemesEditorState.export()` — un second appel concurrent écrase silencieusement l'export en cours
ANDROID SOURCE : AnimemesCompound.java:2583 — garde booléenne synchrone explicite `isStartedCodec` (posée avant toute création d'un nouveau `MP4Encoder`, vérifiée avant `createVideosFromBitmap()`).
ANDROID BEHAVIOR : Un second déclenchement pendant un export en cours est un no-op garanti.
IOS FILES : AnimemesEditorState.swift:1086-1118 (`export(canvasSize:completion:)`) ; AnimemesExporter.swift:176-177 (capture faible de `self` dans les fermetures internes).
IOS BEHAVIOR : Seule garde présente : `guard !composer.layers.isEmpty`. Le bouton devient un `ProgressView` une fois `isExporting == true`, mais c'est une CONSÉQUENCE de l'état, pas une garde À L'INTÉRIEUR de `export()` elle-même. Un second appel (double-tap rapide avant re-rendu, ou tout futur site d'appel) créerait un second `AnimemesExporter`, écraserait `activeExporter` — le premier exporteur serait alors silencieusement désalloué (capture faible), sa complétion jamais appelée, son fichier temporaire orphelin.
CAUSE : Garde de ré-entrance jamais portée dans `export()` lui-même.
IMPACT : Fenêtre de double-tap réelle bien que probablement étroite ; travail perdu, fichier orphelin, complétion jamais appelée pour le premier export.
REPRODUCTIBILITÉ : Certaine par lecture de code que la garde manque ; NEEDS_PHYSICAL_VALIDATION pour confirmer la fenêtre réellement déclenchable via double-tap rapide sur l'appareil.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter `guard !isExporting else { return }` en tête de `export(canvasSize:completion:)`, miroir exact de la garde `isStartedCodec` d'Android.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. `guard !isExporting else { return }` ajouté en toute première ligne de `export(canvasSize:completion:)`, avant même le guard `composer.layers.isEmpty` existant — miroir exact de la garde `isStartedCodec` d'Android. `isExporting` était déjà remis à `false` de façon fiable en cas de succès ET d'échec (`self.isExporting = false` dans le callback de `exporter.export`), donc un nouvel essai après un échec fonctionne normalement sans modification supplémentaire.
```

```
ID : V6-F-008
PRIORITÉ : P3
DOMAINE : Animems — Export (robustesse)
FEATURE : La valeur de retour de `pixelBufferAdaptor.append` n'est jamais vérifiée — une frame perdue silencieusement ne fait pas échouer l'export
ANDROID SOURCE : N/A — mécanisme de défaillance différent côté Android (`drainEncoderBudget`/`EGLExt.eglPresentationTimeANDROID`), pas une comparaison stricte de parité, mais un vrai défaut de robustesse identifié indépendamment.
IOS FILES : AnimemesExporter.swift:219-223 — commentaire de l'auteur du portage reconnaissant lui-même la limitation.
IOS BEHAVIOR : `append` peut retourner `false` en cas d'échec, jamais vérifié — une frame silencieusement absente du fichier de sortie ne déclenche aucune erreur d'export.
CAUSE : Limitation connue, auto-documentée, non corrigée.
IMPACT : Risque de vidéo exportée avec des frames manquantes sans qu'aucune erreur ne soit remontée à l'utilisateur.
REPRODUCTIBILITÉ : Certaine par lecture de code que la vérification manque ; fréquence réelle en pratique non mesurable statiquement.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Vérifier la valeur de retour de `append` et faire échouer explicitement l'export (avec message clair) en cas de frame refusée.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Valeur de retour de `append` désormais vérifiée ; sur `false`, l'export s'arrête proprement (`videoInput.markAsFinished()`, `writer.cancelWriting()`) et échoue explicitement via `completion(.failure(.writingFailed(writer.error)))` au lieu de continuer silencieusement avec une frame manquante.
```

```
ID : V6-F-009
PRIORITÉ : P3
DOMAINE : Animems — Playback/Export (dette de code mort)
FEATURE : Le pipeline de "bake" des keyframes (`AnimationEngine.applyInterpolation`/`AnimationObjectData.bakeKeyframesToTransforms`) est entièrement porté et correct isolément, mais jamais invoqué nulle part dans l'app
ANDROID SOURCE : `AnimemesCompound.applyInterpolation()` — appelé à ~15 sites de mutation réels dans AnimemesCompound.java (voir V6-F-006).
IOS FILES : AnimationEngine.swift (`applyInterpolation`/`applyInterpolation2`), AnimationObjectData.swift (`bakeKeyframesToTransforms`/`bakeMatrixKeyframesToTransforms`).
IOS BEHAVIOR : Fonctions correctement portées mais jamais appelées (grep exhaustif confirmé — seuls des commentaires y font référence, notant explicitement l'omission délibérée pour les calques bitmap/forme, dont le rendu direct des keyframes en direct contourne le besoin de bake).
CAUSE : Racine directe de V6-F-006 pour texte/sticker ; sans impact pour bitmap/forme (rendu direct fonctionnel).
IMPACT : Piège latent pour une future modification qui supposerait ce code actif ; ~50 lignes de code mort à surveiller.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : CODE_PRESENT_UNVERIFIED
RECOMMANDATION : Soit câbler `applyInterpolation` pour texte/sticker (résout aussi V6-F-006), soit retirer le code mort si le rendu direct est retenu comme approche définitive pour tous les types.
STATUT : DIFFÉRÉ — 2026-08-28. V6-F-006 corrigé via la voie "lecture directe" (option B de la recommandation), pas via le bake — confirmant `applyInterpolation`/`bakeKeyframesToTransforms` comme définitivement inutilisés pour TOUS les types de calque (bitmap/forme ET texte/sticker désormais). Le code reste mort mais n'est plus un piège actif pour une future modification puisque le rendu direct est maintenant l'approche uniforme documentée. Retrait des ~50 lignes laissé hors scope de ce cycle V6 (nettoyage pur, aucun risque fonctionnel, pas de raison technique bloquante — reporté à une passe de nettoyage dédiée).
```

```
ID : V6-F-010
PRIORITÉ : P1
DOMAINE : ChatGroup — Cadeaux ("Gift") en conversation de groupe
FEATURE : Le bouton d'envoi de cadeau est affiché et pleinement câblé dans les conversations de GROUPE côté iOS ; Android le masque explicitement dans ce contexte. De plus, iOS n'appelle jamais l'endpoint de débit de pièces pour un cadeau, contrairement à Android
ANDROID SOURCE : ChatFragmentTest.java:1420-1443 (`init()`), ligne 1436 précisément : `messageEventLayout.gift.setVisibility(GONE)` dans la branche groupe (`else`) — confirmé atteignable, appelé à chaque ouverture d'écran chat/groupe. Commit Android récent `c5c2c3d` (identifié par archéologie git) introduisant cette fonctionnalité "Gift" ; le tap réel débite les pièces via `POST message/gift` (`ChatRepository.java`/`ChatViewModel.sendGift`).
ANDROID BEHAVIOR : Le bouton cadeau n'apparaît JAMAIS dans une conversation de groupe — seulement en 1:1. Quand utilisé (1:1), débit réel de pièces côté serveur avant envoi du message.
IOS FILES : ChatView.swift:314-368 (`inputBar`, bouton ligne 338 + feuille lignes 363-368) ; ChatViewModel.swift:420-425 (`sendGift(giftId:)`), :417-419 (commentaire de l'auteur confirmant l'absence du débit), :564-594 (`send(_:)` → `chatRepository.sendGroupMessage(mlib)` si `mlib.type == .group`).
IOS BEHAVIOR : Le bouton cadeau est rendu SANS AUCUNE condition liée au type de conversation — visible et fonctionnel en groupe comme en 1:1. `sendGift` construit un vrai message "gift" sortant et l'émet réellement sur le socket vers le groupe — pas une simple maquette UI. Aucun appel de débit de pièces n'existe nulle part dans `sendGift`.
CAUSE : Le bouton a été porté sans filtre de type de conversation ; le flux de paiement/débit associé n'a jamais été porté du tout (auto-documenté).
IMPACT : Des membres de groupe peuvent envoyer des messages "cadeau" qu'Android interdit explicitement dans ce contexte, ET ce message est envoyé sans AUCUN paiement réel — un défaut d'intégrité économique atteignable spécifiquement dans un contexte (groupe) qu'Android bloque par design.
REPRODUCTIBILITÉ : Certaine par lecture de code (les deux lacunes — filtre UI manquant et appel de débit manquant — lues directement, pas déduites).
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : (1) Masquer le bouton cadeau dans `ChatView` quand `target` est un groupe, miroir du `setVisibility(GONE)` Android. (2) Câbler le débit de pièces réel (`POST message/gift` ou équivalent) dans `sendGift` avant l'envoi du message, quel que soit le contexte.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. (1) Bouton cadeau masqué dans `ChatView.inputBar` quand `viewModel.target.isGroup`, miroir de `setVisibility(GONE)`. (2) `WalletRepository.sendGift(sender:receiver:price:messageId:)` ajouté (`POST message/gift`, mêmes champs qu'Android) et réellement appelé depuis `ChatViewModel.sendGift(giftId:)` ; solde local décrémenté SEULEMENT après confirmation serveur (jamais optimiste, financier). DEUXIÈME barrière ajoutée dans `sendGift` lui-même (`guard !target.isGroup`, pas seulement le bouton masqué) pour couvrir un futur appelant qui contournerait l'UI — répond explicitement à l'exigence de l'audit "vérifier qu'il est impossible de déclencher Gift indirectement en groupe". Vérification de solde AVANT envoi ajoutée aussi (`price <= coinsAmount`), miroir de `btnSendGift.setEnabled(canAfford)` bien que le panneau `GiftPickerPlaceholder` reste un placeholder minimal par ailleurs (catalogue réel, mise en page complète non portée — gap pré-existant, hors scope V6-F-010).
```

```
ID : V6-F-011
PRIORITÉ : P3
DOMAINE : ChatGroup / Chat — Retour sonore envoi/réception
FEATURE : Le retour sonore (chime) à l'envoi/réception d'un message, présent côté Android (groupe ET 1:1), n'a aucune implémentation de lecture côté iOS malgré le plomberie de configuration portée
ANDROID SOURCE : ChatFragmentTest.java:192 (lecture du flag remote-config `allow_chat_send_receive_sound`), :1932-1956 (`onNewMessage`, `playSoundReceive()` atteignable pour 1:1 ET groupe), :2697-2721 (`addMessage`, `playSoundSend()` pour tout message sortant, groupe et 1:1 partagés), :3277-3297 (délégation à `Utils/app_sound/AppSounds.java`, tonalités synthétisées, sans asset audio). Commit Android identifié par archéologie git (`5e67efb`, "version 4.0.1").
ANDROID BEHAVIOR : Chime synthétisé bref à l'envoi et à la réception d'un message, sous réserve du flag remote-config, en groupe comme en 1:1.
IOS FILES : Settings/FirebaseConfigManager.swift:52 (`allowChatSendReceiveSound`).
IOS BEHAVIOR : La propriété de flag existe mais n'est référencée NULLE PART ailleurs (grep confirmé) ; aucun appel `AVAudioPlayer`/`AudioServicesPlaySystemSound`/toute lecture sonore n'existe dans `Sources/TiinverSwift/Messagerie/` (grep ciblé, zéro résultat).
CAUSE : Seule la plomberie du flag de configuration a été portée ; l'implémentation de lecture n'a jamais suivi.
IMPACT : Absence d'un indice UX/retour sonore mineur mais réel, sur les deux contextes (groupe et 1:1).
REPRODUCTIBILITÉ : Certaine par lecture de code (absence confirmée).
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Implémenter la lecture (tonalités synthétisées via `AVAudioPlayer` ou équivalent) à l'envoi/réception, gatée par `allowChatSendReceiveSound`.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Nouveau `ChatSoundPlayer.swift` : port fidèle de `AppSounds.playSend`/`playReceive` (mêmes fréquences/durées/enveloppes exponentielles, synthèse PCM Float via `AVAudioEngine`/`AVAudioPlayerNode` au lieu du PCM16/`AudioTrack` Android — formule d'amplitude identique, seule la représentation bas niveau diffère, sans perte perceptible). Gatée en interne par `allowChatSendReceiveSound`. Câblée dans `ChatViewModel.appendOptimistic` (son d'envoi, tout message sortant local — texte/média/cadeau/rejoindre-groupe, miroir de `addMessage`'s `isBelongsToCurrentUser()`) et `ChatViewModel.onIncoming` (son de réception, gaté `!belongsToCurrentUser`, miroir exact de `onNewMessage`'s garde). `AppSounds.playTyping()` non porté — confirmé sans aucun appelant dans `ChatFragmentTest.java`, code mort côté Android lui-même.
```

```
ID : V6-F-012
PRIORITÉ : P2
DOMAINE : Search — Recherche universelle (course de réponses obsolètes)
FEATURE : Aucune protection contre une réponse réseau obsolète qui écraserait un résultat plus récent, sur les DEUX plateformes — défaut PARTAGÉ, pas une régression iOS
ANDROID SOURCE : RechercheTiinver.java:389-410 (le debounce n'annule que le `Runnable` en attente, jamais la requête réseau déjà en vol) ; `parseAndDisplay` (:461-573) réaffiche inconditionnellement sur toute réponse arrivant, sans vérifier qu'elle correspond à la requête/l'onglet actuellement affiché.
ANDROID BEHAVIOR : Une frappe "abc" puis "abcde" peut, sous conditions réseau défavorables, laisser les résultats de "abc" affichés pendant que le champ montre "abcde".
IOS FILES : SearchView.swift:140-151 (annulation du debounce uniquement), :356-385 (`runSearch(full:)`, tâche réseau distincte et non annulée).
IOS BEHAVIOR : Identique — `.onChange(of: query)` annule seulement la tâche de debounce (le sommeil), pas la tâche réseau elle-même ; le résultat de cette dernière est appliqué sans condition, sans comparaison avec la requête/l'onglet actifs au moment de la réponse. Même lacune au changement d'onglet.
CAUSE : Architecture identique des deux côtés — aucun jeton de génération/séquence, aucune annulation de requête en vol.
IMPACT : Affichage transitoirement incohérent avec ce que l'utilisateur a réellement tapé, sous timing réseau défavorable — même risque sur les deux plateformes.
REPRODUCTIBILITÉ : Certaine par lecture de code qu'aucune garde n'existe ; l'observation réelle du scintillement nécessite un test avec latence réseau artificielle (NEEDS_PHYSICAL_VALIDATION).
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter un jeton de génération (incrémenté à chaque nouvelle recherche, comparé à la réception de la réponse avant application) côté iOS — corrige le défaut partagé sans attendre qu'Android soit lui-même corrigé.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Décision explicitement demandée par la mission (défaut partagé, ne pas corriger automatiquement) : jugé nécessaire ET sûr — le correctif (jeton `searchGeneration`) ne fait QUE supprimer une course, ne change AUCUN comportement observable quand le réseau se comporte normalement, et ne dépend d'aucun changement côté Android. `searchGeneration` ajouté à `SearchView`, incrémenté dans `runSearch`/`suggest`, comparé avant toute application de résultat/erreur ET avant la remise à `false` de `isLoading` (pour éviter qu'une réponse obsolète n'efface l'indicateur de chargement d'une requête plus récente encore en vol).
```

```
ID : V6-F-013
PRIORITÉ : P3
DOMAINE : Search — Soumission explicite
FEATURE : Aucun gestionnaire `.onSubmit` sur le champ de recherche iOS — la validation clavier/bouton "Rechercher" ne court-circuite jamais le debounce, contrairement à Android
ANDROID SOURCE : RechercheTiinver.java:203-216 (`onQueryTextSubmit`) — appel immédiat de `searchFull`, sans attendre les 300ms de debounce.
ANDROID BEHAVIOR : Valider explicitement lance la recherche sans délai perçu.
IOS FILES : SearchView.swift:139 (`.searchable`) — aucun `.onSubmit(of: .search)` trouvé dans le fichier.
IOS BEHAVIOR : La validation explicite n'a aucun effet distinct de la frappe normale — toujours gatée par le debounce de 300ms.
CAUSE : Modificateur `.onSubmit` jamais ajouté.
IMPACT : ~300ms de latence perçue supplémentaire lors d'une validation explicite ; mineur.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter `.onSubmit(of: .search) { Task { await runSearch(full: true) } }` (ou équivalent), en annulant d'abord le debounce en attente.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. `.onSubmit(of: .search) { searchTask?.cancel(); runSearch(full: true) }` ajouté, exactement la recommandation.
```

```
ID : V6-F-014
PRIORITÉ : P2
DOMAINE : Search — Recherche de conversation (chat)
FEATURE : L'écran de recherche de conversation iOS affiche une liste vide tant qu'aucun texte n'est tapé ; Android affiche la liste COMPLÈTE des conversations dès l'ouverture (mode navigation)
ANDROID SOURCE : RechercheTiinver.java:130-197 (`RetrieveContacts(null)` à `onCreate`), :584-685 — quand `str == null || str.equals("")`, CHAQUE conversation locale est ajoutée sans condition (mode navigation, pas un état vide) ; même comportement en effaçant le champ de recherche.
ANDROID BEHAVIOR : L'écran "rechercher une conversation" s'ouvre en montrant la liste complète des conversations, permettant de parcourir/scanner par mémoire visuelle en plus de la recherche par mot-clé.
IOS FILES : ChatSearchView.swift:29-43 (`localMatches`) — `guard !q.isEmpty else { return [] }` ; RosterListView.swift:110-112 (confirme que les données du roster nécessaires pour reproduire ce mode navigation SONT déjà disponibles — `RosterListViewModel` déjà peuplé — mais inutilisées pour le cas requête-vide).
IOS BEHAVIOR : Liste toujours vide tant qu'aucun texte n'est saisi.
CAUSE : `localMatches` retourne systématiquement `[]` pour une requête vide, au lieu de retourner toutes les lignes du roster déjà chargé.
IMPACT : Perte d'un cas d'usage secondaire réel (parcourir ses conversations depuis cet écran sans taper de mot-clé) — pas seulement cosmétique.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Faire retourner à `localMatches` toutes les lignes du `RosterListViewModel` déjà chargé quand `q.isEmpty`, au lieu de `[]`.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. `localMatches` retourne désormais `rosterViewModel.rows` (déjà chargé, aucun appel réseau supplémentaire) quand la requête est vide, exactement la recommandation.
```

```
ID : V6-F-015
PRIORITÉ : P2
DOMAINE : Promotion — Tableau de bord (vignette des posts vidéo boostés)
FEATURE : La vignette de liste d'un boost VIDÉO utilise le mauvais champ CDN côté iOS, potentiellement affichée cassée
ANDROID SOURCE : MyBoostAdapter.java:189-228 (`onBindView`) — branche explicitement sur `object.equals("videos")`, charge alors `cdn_thumbnail_url` (repli sur `objectUrl` seulement si `cdn_content_id` est nul/`"NULL"`) ; pour un objet non-vidéo, charge `objectUrl` directement.
ANDROID BEHAVIOR : Une vignette IMAGE réelle s'affiche pour un boost vidéo.
IOS FILES : BoostDashboardView.swift:77-81 (`boostRow`).
IOS BEHAVIOR : Utilise uniquement `boost.resolvedObjectUrl` (équivalent de `getObjectUrl()`), qui pour une vidéo avec `cdn_content_id` valide résout vers `cdn_content_url` (une URL/manifest vidéo brute), pas une vraie vignette image.
CAUSE : `resolvedObjectUrl` réutilise la logique de priorité de lecture vidéo (conçue pour un autre usage), pas la logique de sélection de vignette d'Android spécifique à cet écran.
IMPACT : Pour les boosts VIDÉO spécifiquement, la vignette du tableau de bord peut échouer à s'afficher ou s'afficher incorrectement (chargeur d'image tentant de charger une URL vidéo).
REPRODUCTIBILITÉ : Certaine par lecture de code que la logique diverge ; le symptôme visuel exact dépend du comportement de `CDNAsyncImage` face à une URL non-image — NEEDS_PHYSICAL_VALIDATION pour confirmer le rendu réel.
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Dans `boostRow`, répliquer la logique Android : pour un boost vidéo, préférer `cdn_thumbnail_url` (repli sur `object_url` si `cdn_content_id` invalide) plutôt que `resolvedObjectUrl`.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Nouvelle propriété `AdsData.resolvedThumbnailUrl` (miroir exact de `MyBoostAdapter.onBindView`, distincte de `resolvedObjectUrl` qui reste utilisée là où elle l'était déjà pour la LECTURE vidéo). `boostRow` utilise désormais `resolvedThumbnailUrl`.
```

```
ID : V6-F-016
PRIORITÉ : P2
DOMAINE : Promotion — Paiement (solde local après achat en gemmes)
FEATURE : Après un boost payé en GEMMES, le solde de PIÈCES mis en cache localement est décrémenté à tort — bug PARTAGÉ, présent identiquement sur les deux plateformes
ANDROID SOURCE : CreateBoostFragment.java:208-215 — écrit inconditionnellement dans `COINS_AMOUNT`, même quand `usingCoins == false` (paiement réel en gemmes via `boost/create2`).
ANDROID BEHAVIOR : Le solde de pièces mis en cache localement diminue même pour un achat payé en gemmes.
IOS FILES : CreateBoostView.swift:230-234 — reproduit fidèlement (avec un commentaire explicite signalant qu'il s'agit d'un bug Android probable, reproduit tel quel, non corrigé).
IOS BEHAVIOR : Identique à Android.
CAUSE : Ni Android ni iOS ne re-synchronisent le vrai solde serveur après achat — écriture locale optimiste inconditionnelle des deux côtés.
IMPACT : Affichage temporairement faux du solde de pièces (fantôme) après un achat en gemmes, jusqu'à la prochaine synchronisation réelle — sur les deux plateformes, pas une régression iOS.
REPRODUCTIBILITÉ : Certaine par lecture de code, des deux côtés.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Conditionner l'écriture locale à `usingCoins`/`useGems`, ou re-synchroniser le vrai solde serveur après un achat réussi — correctif applicable indépendamment côté iOS sans attendre Android.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Décision explicite demandée par la mission pour les opérations financières (sécurité/idempotence prioritaires sur la simple parité visuelle) : écriture locale désormais conditionnée à `useGems` (`gemsAmount` si payé en gemmes, `coinsAmount` sinon), au lieu d'écrire inconditionnellement dans `coinsAmount`. Correctif autonome, ne dépend d'aucun changement Android.
```

```
ID : V6-F-017
PRIORITÉ : P2
DOMAINE : Promotion — Tâche périodique de livraison
FEATURE : L'appel quotidien `GET boost/deliver/{userId}` (WorkManager côté Android) n'a aucun équivalent côté iOS
ANDROID SOURCE : HomeActivity.java:375 (`scheduleDynamicWorker(..., "my-boost-deliver", 1, ...)`) → MyWorker.java:111-128 (`myBoostDeliver()`, appel quotidien). Note : le corps du callback `onResonse` est lui-même VIDE côté Android (aucune notification client déclenchée par ce code précis) — seul `onError` fait quelque chose (et via une clé de préférence erronée, bug distinct).
ANDROID BEHAVIOR : Un `GET` quotidien réel est envoyé au serveur, même si son callback client ne produit aucun effet visible.
IOS FILES : aucun — grep confirmé, `boost/deliver` n'apparaît nulle part dans `Sources/`. Absence documentée comme différée délibérément dans `HomeShellView.swift:38-41` ("module 18").
IOS BEHAVIOR : Aucun appel équivalent n'est jamais émis.
CAUSE : Report délibéré et documenté (BGTaskScheduler non encore mis en place, V5-F-060 déjà connu).
IMPACT : Incertain mais plausible — si le serveur utilise l'ACTE MÊME de cet appel `GET` comme déclencheur pour faire progresser la livraison du boost côté serveur, les boosts iOS pourraient ne jamais recevoir ce signal quotidien. Non confirmable statiquement.
REPRODUCTIBILITÉ : Certaine par lecture de code pour l'absence côté iOS et l'inertie du callback côté Android ; NEEDS_PHYSICAL_VALIDATION pour l'impact serveur réel.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : À traiter dans le cadre du même chantier BGTaskScheduler que V5-F-060 (report déjà décidé) — signaler la dépendance potentielle sur ce endpoint spécifique lors de ce chantier.
STATUT : DIFFÉRÉ — confirmé 2026-08-28, aucun changement de code. Raison technique réelle : dépend de l'infrastructure `BGTaskScheduler` (chantier V5-F-060 déjà décidé, hors périmètre d'un correctif ponctuel) ; regroupé avec ce chantier plutôt que traité isolément ici.
```

```
ID : V6-F-018
PRIORITÉ : P3
DOMAINE : Promotion — Tableau de bord (résilience réseau)
FEATURE : Absence de nouvelle tentative automatique après un échec de chargement du tableau de bord Boost, contrairement à Android
ANDROID SOURCE : BoostDashboardFragment.java:208-234 (`attemptReconnect`/`attemptReconnectOverview`) — nouvelle tentative automatique après 5 secondes en cas d'erreur.
ANDROID BEHAVIOR : Le tableau de bord se rétablit tout seul après un échec réseau transitoire.
IOS FILES : BoostDashboardView.swift:91-99.
IOS BEHAVIOR : Erreur avalée via `try?`, aucune tentative automatique — seul le tirer-pour-rafraîchir manuel permet de relancer.
CAUSE : Mécanisme de nouvelle tentative jamais porté.
IMPACT : Résilience UX moindre, pas un défaut de données (pull-to-refresh reste un palliatif raisonnable).
REPRODUCTIBILITÉ : Certaine par lecture de code (absence confirmée).
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter une nouvelle tentative automatique après un court délai en cas d'échec, miroir du comportement Android.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Port de `attemptReconnect`/`attemptReconnectOverview` (délai 5s, tentative UNIQUE), mais avec DEUX flags indépendants (`didRetryOverview`/`didRetryBoosts`) plutôt que le booléen `attemptReconnect` PARTAGÉ côté Android entre les deux mécanismes — un défaut d'implémentation manifeste chez Android (la première erreur, quelle que soit sa source, consomme la seule tentative disponible pour LES DEUX chargements) non reproduit ici, `IOS_INTENTIONAL_DIFFERENCE` : chaque chargement se rétablit indépendamment. Les deux flags sont réinitialisés par le tirer-pour-rafraîchir manuel (nouveau budget de tentative complet à chaque intention explicite de l'utilisateur).
```

```
ID : V6-F-019
PRIORITÉ : P1
DOMAINE : Video Statistics — Pipeline de suivi du temps de visionnage
FEATURE : Le pipeline client de suivi (temps de visionnage cumulé, point de sortie, profondeur de scroll, nombre de replays), qui alimente les métriques mêmes affichées par l'écran Statistiques, est entièrement absent côté iOS
ANDROID SOURCE : Utils/WatchTimeTracker.java (suivi par session de lecture) → Utils/ViewTracker.java:33-98 (`record()`, persistance/cumul Room, synchronisation au-delà de `SYNC_THRESHOLD=5`) → service/worker/ViewSyncWorker.java:23-121 (WorkManager, périodique 15min + immédiat, `POST addview` avec `userId, activityId, watchtime, scrollPosition, replayCount, exitPoint`). Câblé dans le cycle de vie de lecture, FeedFragment.java:158,665,1430-1441,1587.
ANDROID BEHAVIOR : Chaque impression de visionnage (vidéo OU photo) accumule watch time/point de sortie/replay/scroll localement et synchronise périodiquement vers `addview`, alimentant vraisemblablement `total_watch_time`/`avg_watch_time`/`completion_rate`/`view_rate_3sec` retournés par `activity/statistics/{id}/{userId}`.
IOS FILES : Storage/ViewEventRepository.swift (accumulation locale CoreData SEULEMENT — commentaire d'en-tête propre confirmant le report explicite du volet serveur, "module 18, pas ici").
IOS BEHAVIOR : `ViewEventRepository.record(...)` n'est appelé NULLE PART ailleurs que sa propre déclaration (grep confirmé) — aucun site d'appel côté lecteur vidéo, aucun port de `WatchTimeTracker`. La chaîne `"addview"` n'apparaît NULLE PART dans `Sources/` — le endpoint de synchronisation n'est pas implémenté. `Storage/LocalDataPurger.swift:19` documente explicitement ces lignes comme "non purgées, délibérément" (module différé).
CAUSE : Report délibéré et documenté du "module 18" — mais son impact sur l'écran Statistiques lui-même n'avait apparemment jamais été tracé jusqu'ici.
IMPACT : Toute activité de visionnage sur iOS (de N'IMPORTE QUEL contenu, pas seulement les auto-visionnages) n'est JAMAIS remontée au serveur. Les métriques `total_watch_time`/`avg_watch_time`/`completion_rate`/`view_rate_3sec` des créateurs sont systématiquement sous-comptées/faussées pour toute part d'audience venant d'iOS, invisiblement (l'écran Statistiques "a l'air" correct, il lit juste un jeu de données incomplet). Effet secondaire : le stockage CoreData local grandit sans limite sur les appareils iOS (jamais purgé, jamais synchronisé).
REPRODUCTIBILITÉ : Certaine par lecture de code pour "jamais appelé/synchronisé" ; magnitude réelle du sous-comptage NEEDS_PHYSICAL_VALIDATION (compte réel avec audience mixte Android/iOS).
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Prioriser ce chantier différé au-dessus des autres report du "module 18" étant donné son impact direct et invisible sur des métriques business-critiques pour les créateurs.
STATUT : NON CORRIGÉ (audit uniquement, report déjà assumé mais impact précis nouvellement documenté)
```

```
ID : V6-F-020
PRIORITÉ : P2
DOMAINE : Video Statistics — Métrique "taux de vue à 3 secondes"
FEATURE : La carte "taux de vue à 3 secondes" est absente de l'écran Statistiques iOS
ANDROID SOURCE : activity_statistics.xml:277-293 (carte dédiée, libellé `@string/_3sec_view_rate`) ; StatisticsActivity.java:97,142.
ANDROID BEHAVIOR : Carte affichée (note : le binding Android lui-même contient un bug indépendant — ligne 142 affiche `getViews()` au lieu de `getView_rate_3sec()`, donc cette carte n'affiche jamais de vraie donnée de taux de vue à 3s même côté Android — mais la carte EXISTE visuellement).
IOS FILES : StatisticsView.swift ; le champ est décodé (BoostModels.swift:79) mais jamais lu ailleurs (grep confirmé, un seul résultat : la déclaration).
IOS BEHAVIOR : Aucune ligne/carte pour cette métrique.
CAUSE : Omission lors du portage — pas une reproduction délibérée du bug de binding Android (qui, lui, affiche AU MOINS quelque chose, même incorrect).
IMPACT : Les créateurs voient un bloc de métrique en moins que sur Android ; si le bug de binding Android est un jour corrigé côté serveur/client, iOS ne l'affichera toujours pas puisque rien n'est câblé.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter la ligne manquante dans `StatisticsView.swift`, lisant `stats.view_rate_3sec` (pas `views`, contrairement au bug Android).
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Ligne "Taux de vue à 3s" ajoutée, lisant `stats.view_rate_3sec` — PAS le bug de binding Android (`views`).
```

```
ID : V6-F-021
PRIORITÉ : P2
DOMAINE : Video Statistics — Gestion d'erreur au chargement
FEATURE : Un échec réseau au chargement des Statistiques affiche un écran totalement vide côté iOS (aucune section, aucune tentative automatique), contre un affichage "--" complet + une tentative automatique côté Android
ANDROID SOURCE : StatisticsActivity.java:127-131 (nouvelle tentative automatique UNE FOIS, garde `attemps`) ; en cas d'échec persistant, chaque champ garde son placeholder XML par défaut `"--"` (aucun bandeau/toast d'erreur n'est jamais affiché, `Result.getErrorMessage()` capturé mais jamais lu).
ANDROID BEHAVIOR : Écran toujours visuellement complet, avec des "--" à la place des valeurs en cas d'échec persistant.
IOS FILES : StatisticsView.swift:114-118 (`load()`).
IOS BEHAVIOR : `stats = try? await AdsRepository.shared.fetchStatistics(...)` avale toute erreur, sans tentative automatique ; comme `stats` reste `nil`, la `List` entière ne rend AUCUNE section — écran vide sans aucune explication.
CAUSE : Motif "échec silencieux via `try?`" déjà identifié à de nombreuses reprises ailleurs par V5, retrouvé ici dans un domaine jamais audité auparavant.
IMPACT : Pire expérience qu'Android en cas d'échec réseau — écran vide sans indication, plutôt qu'un scaffold complet avec placeholders.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ajouter une nouvelle tentative automatique (miroir d'Android) et afficher un scaffold complet avec placeholders "--" en cas d'échec persistant, au lieu d'une liste vide.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. `load()` : une nouvelle tentative immédiate sur échec (port de la garde `attemps`, pas de délai comme Android), puis `stats = StatisticModel()` (scaffold complet, tous les replis `?? 0`/`?? ""` déjà en place) si l'échec persiste — au lieu d'un écran totalement vide.
```

```
ID : V6-F-022
PRIORITÉ : P3
DOMAINE : Video Statistics — Cadence de rafraîchissement
FEATURE : L'écran Statistiques iOS ne se rafraîchit pas automatiquement en réapparaissant, contrairement à Android
ANDROID SOURCE : StatisticsActivity.java:214-218 — recharge à CHAQUE `onResume`.
ANDROID BEHAVIOR : Revenir sur cet écran depuis n'importe où re-déclenche toujours un chargement frais.
IOS FILES : StatisticsView.swift:79-80 (`.task`/`.refreshable`).
IOS BEHAVIOR : Chargement unique via `.task`, plus tirer-pour-rafraîchir manuel ; pas de re-chargement automatique à la réapparition si l'instance de vue SwiftUI persiste.
CAUSE : `.task` ne se redéclenche pas sur simple réapparition (contrairement à `onResume` Android).
IMPACT : Données potentiellement obsolètes si l'utilisateur revient sur cet écran sans le fermer complètement ; mineur, pull-to-refresh reste disponible.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter un rechargement sur `.onAppear` (avec une garde anti-doublon si `.task` a déjà chargé), miroir du comportement `onResume` Android.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. `.onAppear { if hasLoadedOnce { Task { await load() } } }` ajouté, exactement la recommandation.
```

```
ID : V6-F-023
PRIORITÉ : P3
DOMAINE : Video Statistics — Rendu cosmétique (dictionnaire présent-mais-vide)
FEATURE : Un dictionnaire de distribution (genre/âge) présent mais vide (`{}`) s'affiche en texte blanc côté Android, en "--" côté iOS
ANDROID SOURCE : StatisticsActivity.java:152-159 — variables pré-initialisées à `""`, jamais réassignées si la boucle ne s'exécute pas.
ANDROID BEHAVIOR : Texte vide (pas de "--").
IOS FILES : StatisticsView.swift:98-112 (`lastMatchingBucket`).
IOS BEHAVIOR : Retombe explicitement sur "--" pour un dictionnaire vide/nul.
CAUSE : Divergence cosmétique de valeur de repli.
IMPACT : Différence visuelle mineure, cas limite rare (post tout neuf sans donnée d'audience encore).
REPRODUCTIBILITÉ : Certaine par lecture de code des deux comportements ; la fréquence réelle en pratique (le backend envoie-t-il vraiment `{}` ?) NEEDS_PHYSICAL_VALIDATION.
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Faible priorité — aligner sur "--" ou texte vide selon préférence produit, cohérence pas exactitude fonctionnelle en jeu.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Repli aligné sur le texte vide Android (`gender["M"] ?? ""` au lieu de `?? "--"`) UNIQUEMENT pour le cas "dictionnaire nul/vide" — le `"--"` par bucket non gagnant D'UN DICTIONNAIRE NON VIDE (bug de la boucle Android lui-même, distinct, toujours reproduit fidèlement) est inchangé.
```

```
ID : V6-F-024
PRIORITÉ : P1
DOMAINE : Transversal — Publication (post ET export Animems, double-soumission)
FEATURE : Le bouton "Publier" a une fenêtre de double-tap réelle : la garde anti-double-soumission est posée APRÈS un appel réseau, pas avant
ANDROID SOURCE : PublishFragment.java:274-283 (`post.setOnClickListener` → `getCurrentCategory()` → `proceedToPublish()`) ; `getCurrentCategory()` (:350-362) est une lecture LOCALE SYNCHRONE (`ContentResolver.query()`), aucun appel réseau — fenêtre de double-tap quasi nulle avant que le bouton ne se désactive.
ANDROID BEHAVIOR : Le bouton devient effectivement non-cliquable quasi instantanément après le premier tap.
IOS FILES : PublishComposeView.swift:314-351, précisément lignes 335-347.
IOS BEHAVIOR :
```swift
if resolvedCategory == nil {
    if let profile = try? await ProfileRepository.shared.fetchProfile(userId: actorId, viewerId: actorId), ... {
        resolvedCategory = category
    } else { showCategoryPicker = true; return }
}
isPublishing = true   // posé APRÈS l'attente réseau ci-dessus
```
`resolvedCategory` (ligne 68) n'est jamais préchargé ailleurs dans la vue (grep confirmé, seuls 2 sites d'assignation : lignes 240 et 339) — donc CHAQUE tap sur "Publier" déclenche un aller-retour réseau réel (`fetchProfile`) AVANT que `isPublishing` ne devienne vrai. Le bouton ne devient un `ProgressView` (non cliquable) qu'une fois `isPublishing` vrai — il reste donc pleinement tapable pendant toute la durée de cet appel réseau. Aucun `guard !isPublishing else { return }` en tête de `publish()`.
CAUSE : La garde a été placée après l'appel réseau au lieu d'avant, et `resolvedCategory` n'est jamais pré-résolu en amont (ex. à l'apparition de l'écran) pour éviter ce chemin réseau au moment du tap.
IMPACT : Un double-tap normal (ou simplement la latence réseau) peut démarrer `publish()` deux fois en parallèle — les deux passent les gardes, les deux appellent `FeedRepository().publish(...)` — risque de deux publications `activity/add` pour un seul geste utilisateur. Même mécanisme partagé par le flux de publication Animems (qui réutilise `PublishComposeView`).
REPRODUCTIBILITÉ : Certaine par lecture de code pour la course logique (attente avant pose du drapeau, aucune garde) ; le taux réel de publications dupliquées en pratique NEEDS_PHYSICAL_VALIDATION (latence réseau réaliste sur appareil).
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ajouter `guard !isPublishing else { return }` en TOUTE PREMIÈRE ligne de `publish()`, avant même la résolution de catégorie ; envisager de pré-résoudre `resolvedCategory` à l'apparition de l'écran plutôt qu'au moment du tap.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. `guard !isPublishing else { return }` posé en toute première ligne de `publish()`, ET `isPublishing = true` (+ `defer { isPublishing = false }`) déplacé au même endroit — AVANT la résolution de catégorie async (`fetchProfile`), pas seulement le guard seul, sinon deux appels concurrents auraient tous deux pu passer le guard avant que l'un d'eux ne pose le drapeau. Protège atomiquement le flux post ET le flux export Animems (qui réutilise `PublishComposeView`), conforme au test mental demandé (tap → réseau lent → second tap → une seule publication). Pré-résolution de `resolvedCategory` à l'apparition de l'écran non implémentée (optimisation secondaire de la recommandation, pas nécessaire une fois la garde atomique en place).
```

```
ID : V6-F-025
PRIORITÉ : P2
DOMAINE : Transversal — Badge d'icône système (fonctionnalité ajoutée par iOS, incomplète)
FEATURE : Le badge d'icône de l'app sur l'écran d'accueil ne reflète JAMAIS le nombre de messages non lus, seulement les notifications non lues
ANDROID SOURCE : aucun — Android n'a pas d'équivalent de badge d'icône d'app pour cette fonctionnalité (confirmé par le commentaire du code iOS lui-même) ; seul le badge de navigation in-app existe côté Android (déjà couvert par V5).
IOS FILES : Navigation/HomeShellView.swift — ligne 53 (`chatUnreadCount`, alimenté lignes 284-288 depuis `wk_roster`/CoreData, ne pilote QUE le badge de l'onglet Chat, ligne 79) ; ligne 95 (badge onglet Notifications) ; lignes 196-201 (SEUL site d'appel de `UNUserNotificationCenter.current().setBadgeCount(count)` dans tout le fichier, câblé via `.onChange(of: notificationsViewModel.unreadCount)` UNIQUEMENT).
IOS BEHAVIOR : Le badge système de l'icône de l'app ne suit QUE le compteur de notifications non lues — jamais mis à jour depuis `chatUnreadCount`. Aucun `.onChange(of: chatUnreadCount)` (ni total combiné) n'existe nulle part (grep confirmé, `setBadgeCount` apparaît exactement une fois).
CAUSE : Fonctionnalité ajoutée uniquement côté iOS (sans équivalent Android à porter), mais implémentée de façon incomplète — le chat n'a jamais été inclus dans le calcul.
IMPACT : Un utilisateur avec des messages non lus mais zéro notification non lue ne voit AUCUN badge sur l'icône de l'app/le sélecteur d'apps, alors que l'onglet Chat in-app affiche pourtant un badge non nul. Les 2 badges in-app et le badge système ne coïncident jamais dans ce cas.
REPRODUCTIBILITÉ : Certaine par lecture de code.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Combiner `chatUnreadCount` + `notificationsViewModel.unreadCount` (ou les deux séparément en cascade) dans le calcul passé à `setBadgeCount`, avec un `.onChange` couvrant les deux sources.
STATUT : BUILD_VALIDATED — CI run 33156167515 SUCCESS (2026-08-28, https://github.com/SalimMedir/TiinverSwift/actions/runs/33156167515). Corrigé 2026-08-28. Nouveau `updateSystemBadge()` combinant les deux sources, appelé par `.onChange(of: notificationsViewModel.unreadCount)` (existant, réutilisé) ET un nouveau `.onChange(of: chatUnreadCount)`.
```

```
ID : V6-F-026
PRIORITÉ : P2
DOMAINE : Transversal — Téléchargement de vidéo du fil (habillage promotionnel)
FEATURE : Les vidéos du fil téléchargées perdent leur habillage promotionnel (watermark animé + outro) côté iOS, contrairement à Android
ANDROID SOURCE : service/broadcast/DownloadReceiver.java:44-91 — sur `ACTION_DOWNLOAD_COMPLETE`, si `origin=="feed" && object.equals("videos")`, planifie `ExportWorker` via WorkManager (:72-82) ; service/worker/ExportWorker.java:41-46,61-256 — exécute `AnimatedWatermarkComposer` (watermark animé par keyframes, lignes 252-256) + pipeline `OutroConfig`/`MP4Encoder` AVANT l'écriture finale dans la galerie via `MediaStore`.
ANDROID BEHAVIOR : Chaque vidéo du fil téléchargée est post-traitée avec l'habillage de marque de l'app (watermark + outro) avant d'atterrir dans la galerie.
IOS FILES : Feed/FeedMediaDownloader.swift:42-69.
IOS BEHAVIOR : Télécharge le fichier brut via `URLSession.shared.download(for:)` et l'enregistre directement dans `PHPhotoLibrary` (`PHAssetChangeRequest.creationRequestForAssetFromVideo`) — aucune étape de watermark/outro/ré-encodage n'existe nulle part dans cette fonction ni ses sites d'appel (lecture intégrale confirmée).
CAUSE : Fonctionnalité de post-traitement jamais portée — même famille de lacune que V5-F-082 (habillage à l'export/partage Animems, toujours différé), mais sur un chemin de code totalement distinct (téléchargement de vidéo du FIL, pas export Animems).
IMPACT : Les vidéos sauvegardées depuis iOS puis repartagées ailleurs (WhatsApp, etc.) ne portent aucune attribution/marque de l'app, contrairement à Android — un vrai écart de parité produit/marketing, pas seulement une nuance d'infrastructure d'arrière-plan.
REPRODUCTIBILITÉ : Certaine par lecture de code (fonctionnalité totalement absente, pas seulement dégradée).
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Porter le pipeline de post-traitement watermark/outro pour les téléchargements de vidéo du fil, potentiellement en réutilisant l'infrastructure déjà scaffoldée pour V5-F-082 (`OutroConfig`/`AnimatedWatermarkComposer` déjà documentés côté iOS pour l'export Animems).
STATUT : DIFFÉRÉ — confirmé 2026-08-28, aucun changement de code. Raison technique réelle : même famille de lacune que V5-F-082 (toujours `DIFFÉRÉ`), nécessite la MÊME infrastructure substantielle de post-traitement vidéo (composition watermark animé par keyframes + pipeline outro + ré-encodage MP4) qui n'a été construite sur AUCUN des deux chemins de code iOS pour l'instant. Construire ce pipeline seulement pour le téléchargement de vidéo du fil, dans cette session, sans validation physique de la vidéo résultante (encodage, lisibilité/timing du watermark, orientation) serait un risque disproportionné pour une fonctionnalité de marque/marketing — regroupé avec V5-F-082 comme un futur chantier dédié de post-traitement vidéo plutôt que traité isolément ici.
```

---

## 4. Différences Android/iOS intentionnelles (`IOS_INTENTIONAL_DIFFERENCE`)

Bugs Android confirmés non reproduits côté iOS (à NE PAS "corriger" pour forcer la parité), ou
améliorations iOS documentées sans équivalent Android à comparer :

1. **Search** — Android construit ses URLs de requête sans encodage pourcentage (`RechercheTiinver.java:417,440`) ; iOS encode correctement. Un query avec espace/accent/`&` peut casser côté Android, pas côté iOS. Bug Android, ne pas reproduire.
2. **Search** — Android peut sauvegarder un historique de recherche à 1 caractère qui n'a jamais réellement cherché (`onQueryTextSubmit` sauvegarde avant que `searchFull`'s garde `length<2` ne no-op). iOS ne peut pas atteindre ce chemin (garde `count>=2` avant toute action, sauvegarde incluse).
3. **Search** — `RecentSearchManager.clearAll()` existe côté Android mais est du code mort (jamais câblé à aucune UI) ; iOS câble explicitement "Tout effacer" à une action équivalente. Amélioration iOS, pas une lacune à retirer.
4. **Search** — Le flag `searchOnLocal` d'Android (recherche de conversation) ne reflète que la DERNIÈRE ligne de curseur examinée, jamais réinitialisé entre appels — comportement de repli serveur incohérent + appels serveur superflus. iOS recalcule intégralement à chaque accès, structurellement immunisé.
5. **Search** — La recherche de membres de groupe Android (`FilterGroupMemberList.filterMember`) interroge sans filtre de `groupId` — fuite possible de membres d'un AUTRE groupe dans les résultats. iOS scope toujours via l'endpoint réseau `membership/{groupId}`, immunisé par construction.
6. **Promotion** — iOS désactive le bouton de soumission sous le budget minimum (5) au lieu de laisser Android faire un tap sans effet silencieux. Amélioration UX, pas une régression.
7. **Promotion** — Le curseur de durée iOS impose `1...30`, empêchant `duration=0` (possible côté Android via son seekbar non validé, impact serveur réel inconnu). Prévention côté iOS d'une faille de validation Android.
8. **Promotion** — Sur une réponse de paiement rejetée/inattendue, Android reste bloqué silencieusement sans jamais notifier l'utilisateur (aucun ERROR ni SUCCESS n'est jamais posté) ; iOS échoue de façon fermée (`isBackendSuccess` par défaut à `false`) et affiche une vraie erreur. Aucune preuve d'un paiement refusé affiché comme un succès côté iOS — le défaut est dans l'autre sens côté Android (silence, pas fausse réussite).
9. **Promotion** — iOS masque le bouton "Annuler" une fois un boost déjà annulé ; Android le laisse toujours visible (permettant un re-tap sans effet). Amélioration UX mineure.
10. **Video Statistics** — Android accumule des lignes pays/ville en double à chaque `onResume` répété (jamais vidées) ; iOS reconstruit toujours depuis les données fraîchement décodées, immunisé par le modèle déclaratif SwiftUI.
11. **Video Statistics** — Les cartes `Map<String,Integer>` d'Android peuvent être `null` si la clé JSON est absente, provoquant un risque de `NullPointerException` non gardé ; iOS utilise des `[String:Int]?` avec garde systématique, structurellement immunisé.
12. **Animems** — La garde `AnimationEngine.tick()` sur les transforms d'un calque arbitraire (déjà retirée côté iOS lors du cycle V5) est confirmée être un effet de bord incident côté Android, pas un choix délibéré — retrait confirmé correct, pas à réintroduire.
13. **Animems** — Le "Play" en direct d'Android masque entièrement texte/sticker/tracé/ligne/clip/gomme pendant la lecture (ils réapparaissent à l'arrêt) ; iOS les garde visibles (figés) pendant toute la lecture. Comportement Android sans commentaire explicatif, ressemble à un oubli plutôt qu'un choix délibéré — non signalé comme lacune iOS à corriger, documenté pour éviter une confusion future.
14. **Animems** (décidé pendant la correction, 2026-08-28, V6-F-005) — le panneau "Cadre" (flipbook stop-motion legacy) n'est pas porté ; iOS couvre le même besoin via `autoCaptureEnabled` (déjà choisi, mécanisme différent). Construire un second chemin dupliquant un système legacy déjà superseded côté Android lui-même n'apporterait rien.
15. **Promotion** (décidé pendant la correction, 2026-08-28, V6-F-018) — le nouvel auto-retry du tableau de bord Boost utilise DEUX flags indépendants (overview/liste), pas le booléen `attemptReconnect` PARTAGÉ côté Android entre les deux mécanismes de retry — un défaut d'implémentation manifeste chez Android (la première erreur consomme la seule tentative disponible pour LES DEUX chargements), non reproduit.

---

## 5. Domaines non explorés / limites honnêtes de ce cycle

- Rendu MP4 binaire réel (lecture tierce, synchronisation A/V en pratique) — nécessite un run réel.
- Re-vérification indépendante complète de `SocketInit.java` Android actuel pour ChatGroup — budget consommé par l'archéologie git requise en premier.
- Balayage exhaustif de TOUS les sites `Task {` du projet pour l'annulation réseau à la navigation — V5 avait déjà signalé cette limite, non résolue ici (seulement 4 écrans échantillonnés).
- Accessibilité — reconfirmée comme point aveugle total (0 `accessibilityLabel` dans tout le projet), non traitée au-delà de cette reconfirmation.
- Magnitude réelle du sous-comptage causé par V6-F-019 — nécessite des données réelles cross-plateforme sur un compte réel.
- Dimensions/orientation/FPS initiaux précis du canevas Animems à la création (V6-F-A) — possible différence intentionnelle non confirmée, nécessiterait une lecture plus profonde du moteur de bake.
