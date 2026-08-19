# ANIMEMS_PARITY_PROGRESS_V1.md — Journal de progression, spécial Animems

Compagnon de `ANIMEMS_PARITY_AUDIT_V1.md`. Ce fichier journalise l'avancement de PHASE B
(correction par lots) au fur et à mesure — PAS pendant PHASE A (audit), qui ne modifie aucun code.

Format par entrée : date, lot traité, item(s) de `ANIMEMS_PARITY_AUDIT_V1.md` couverts, fichiers
modifiés, commit, statut CI, statut de parité mis à jour.

---

## 2026-08-18 — PHASE A terminée, PHASE B pas encore commencée

`ANIMEMS_PARITY_AUDIT_V1.md` créé et commité (`8f972c3`). Aucune correction de code effectuée dans
cette passe — audit uniquement.

---

## 2026-08-19 — PHASE B : feu vert reçu, 11 lots exécutés

Ordre suivi : P0 d'abord (Lot 1-2), puis P1/P2 par ordre de dépendance/risque croissant (Lot 3-11),
conformément à la méthode imposée (tracer Android → tracer iOS → corriger → commit → CI → mettre à
jour ces deux fichiers → lot suivant). **Les 11 lots sont tous `BUILD_VALIDATED` (CI verte
confirmée)** — voir tableau récapitulatif en fin de fichier.

### Lot 1 — P0 : playback recompute, export font, commentaire obsolète

**Items couverts** : F-05, F-13, F-23 (voir `ANIMEMS_PARITY_AUDIT_V1.md` §4)

**Android retracé** : `AnimationEngine.tick()` (appelle `didPlayFrame` PUIS
`animationEngineDidInvalidate` à chaque frame) ; aucune contrepartie Android pour F-23 (bug
iOS-only, architecture "re-render toujours" vs "bake-once" d'Android)

**iOS avant correction** : `AnimemesEditorState.swift` — les 3 callbacks du delegate de lecture
bumpaient `version` (rebuild complet `engine.prepare()` via `.onChange(of: state.version)`) au lieu
de `renderVersion`, sur CHAQUE frame de lecture. `AnimemesExporter` construisait son propre
`TextRect(.systemFont(14))` jamais écrasé par son seul appelant, au lieu de la police réelle de
l'éditeur (`.boldSystemFont(32)`).

**Changement appliqué** : `AnimemesEditorState.swift` (delegate → `bumpRenderVersion()`, nouvelles
constantes `textFont`/`textColor` partagées), `AnimationObjectData.swift` (commentaire
`maskTransforms` corrigé)

**Commit** : `71375ff`

**CI** : [run 32201713716](https://github.com/SalimMedir/TiinverSwift/actions/runs/32201713716) —
`success`

**Statut de parité mis à jour** : F-05 `FUNCTIONALLY_FAILED` → `COMPLETE_PARITY_CANDIDATE` ; F-23
`FUNCTIONALLY_FAILED` → `COMPLETE_PARITY_CANDIDATE` ; F-13 commentaire corrigé

**Notes** : aucun test réel de performance sur device — la relation de cause à effet dans le code
est déterministe, mais l'amélioration effective de fluidité n'est pas mesurée.

---

### Lot 2 — P0 : point d'entrée du mode masque

**Items couverts** : F-11, F-14

**Android retracé** : `AnimemesCompound.java:1986` (`btn_mask` → `showMaskAddPanel()`) →
`onMaskPicked` → `showMaskPreviewEditor` (applique le type, démarre `mView.startMaskEditMode`,
câble `MaskGestureListener`) ; `AnimemesCompound.java:1143-1148` (guard `obj == null`) ;
`onRemoveMask()`/`onDismiss()` distincts (`AnimemesCompound.java:1044-1071`,
`MaskPreviewEditorPanel.java:199/352`)

**iOS avant correction** : `isMaskEditMode` jamais assigné à `true` nulle part (confirmé par grep
exhaustif sur tout le projet) — moteur de masque entièrement câblé mais inaccessible

**Changement appliqué** : bouton "masque" dans `bottomToolbar` (`disabled(selectedId == nil)`) →
`isMaskEditMode = true` ; bouton "✓" ajouté dans `maskPanel(for:)` pour sortir SANS effacer le
masque (distinct de "Aucun") ; `deleteSelected()` réinitialise aussi `isMaskEditMode`

**Fichiers modifiés** : `AnimemesEditorView.swift`, `AnimemesEditorState.swift`

**Commit** : `4f7d78e`

**CI** : [run 32201920028](https://github.com/SalimMedir/TiinverSwift/actions/runs/32201920028) —
`success`

**Statut de parité mis à jour** : F-11/F-14 `FUNCTIONALLY_FAILED` → `COMPLETE_PARITY_CANDIDATE`

**Notes** : gestes de mask-edit (drag/pinch/rotate → offset/scale/rotation du masque) non re-testés
sur device depuis leur écriture initiale — risque non confirmé, voir §18.1 de l'audit.

---

### Lot 3 — P1 : panneau d'édition de calque (opacité/teinte/arrondi/flou)

**Items couverts** : F-28, F-31

**Android retracé** : `showPanelEditor` a 3 sites d'appel dans `AnimemesCompound.java` —
`onKeyframeButtonClicked2()` (mort, zéro appelant), la branche `else` d'`onKeyframeButtonClicked()`
(structurellement inatteignable, `btn_keyframe` n'est visible QUE quand `controller_mode_activate`
est déjà vrai), et `onTrackLongPressed(TimelineItem)` (ligne 1636, RÉEL — appui long sur une piste
timeline) ; modèle preview/validate/cancel de `MaskPreviewEditorPanel`... pardon,
`LayerEditorPanel.java` (`applyPropertiesToLayerForPreview`/`validateAndCreateKeyframe`/
`cancelLayerEditorPreview`, lignes 675-927)

**iOS avant correction** : `LayerEditorPanelState.swift` (état pur, `bound(to:)`/
`showsCornerRadius`/`palette`) jamais monté dans une vue, jamais instancié

**Changement appliqué** : `LayerEditorPanelView.swift` (nouveau, sheet SwiftUI) ; état
`snapshotLayerEditor`/`applyLayerEditorPreview`/`validateLayerEditor`/`cancelLayerEditor` dans
`AnimemesEditorState.swift` ; bouton "propriétés" dans `bottomToolbar` (substitution du déclencheur
appui-long → bouton dédié, documentée et motivée par le risque de composition de geste sur
`TimelineView.swift`, déjà cassé 2 fois cette session)

**Fichiers modifiés** : `AnimemesEditorState.swift`, `AnimemesEditorView.swift`,
`LayerEditorPanelView.swift` (nouveau)

**Commit** : `5b85e7e`

**CI** : [run 32202284433](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202284433) —
`success`

**Statut de parité mis à jour** : F-28/F-31 `CODE_PRESENT_UNVERIFIED` → `COMPLETE_PARITY_CANDIDATE`

**Notes** : `tintStrength` Android (séparé) fusionné dans l'octet alpha du `color` ARGB iOS (une
seule piste), décision motivée par l'architecture de rendu déjà en place (`LayerRenderer.drawTinted`
traite déjà l'alpha comme force de teinte).

---

### Lot 4 — P2 : duplication de calque

**Items couverts** : F-30

**Android retracé** : `AnimemesCompound.java:1959-1965` (`btn_duplicate` →
`AnimationObjectData.duplicate(data)`, PAS `duplicate2` — vérifié par lecture directe du site
d'appel) → `duplicateTimeline(dup, item)` (ajoute sans sélectionner)

**iOS avant correction** : `AnimationObjectData.duplicate(_:)` écrit, zéro site d'appel

**Changement appliqué** : `AnimemesEditorState.duplicateSelected()` + bouton "dupliquer" dans
`bottomToolbar`

**Fichiers modifiés** : `AnimemesEditorState.swift`, `AnimemesEditorView.swift`

**Commit** : `ac46dc0`

**CI** : [run 32202402631](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202402631) —
`success`

**Statut de parité mis à jour** : F-30 `MISSING` → `COMPLETE_PARITY_CANDIDATE`

**Notes** : confirmation croisée obtenue pendant ce lot que `btn_bezier` (F-27) est bien réel
(`AnimemesCompound.java:1970`), résolvant le risque mono-source §18.2 de l'audit.

---

### Lot 5 — P2 : panneau de configuration de forme avant insertion

**Items couverts** : F-21

**Android retracé** : `ShapeAddPanel` (choix type) → `ShapePreviewEditorPanel` (couleur/opacité/
arrondi/épaisseur/contour AVANT insertion) → `onConfirm(data)` → `ShapeFactory.rerenderShape`

**iOS avant correction** : `addShape` insérait directement avec des valeurs codées en dur (rouge
150×100, vert cercle 140, bleu ligne 200×8) ; `ShapePreviewEditorPanelState.swift` (`makeDefault`/
`rowVisibility`/`label`) écrit, jamais monté

**Changement appliqué** : `beginAddingShape`/`finalizeShape` dans `AnimemesEditorState.swift` ;
`ShapePreviewEditorPanelView.swift` (nouveau, aperçu live via `ShapeFactory.rerender`, palette,
sliders conditionnels selon `rowVisibility`)

**Fichiers modifiés** : `AnimemesEditorState.swift`, `AnimemesEditorView.swift`,
`ShapePreviewEditorPanelView.swift` (nouveau)

**Commit** : `6980f39`

**CI** : [run 32202564912](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202564912) —
`success`

**Statut de parité mis à jour** : F-21 `PARTIAL` → `COMPLETE_PARITY_CANDIDATE`

---

### Lot 6 — P2 : toggle éditeur bezier

**Items couverts** : F-27

**Android retracé** : `AnimemesCompound.java:1970-1980` (`btn_bezier`, réel, confirmé par 2 lectures
indépendantes) ; `BezierEditorView.java` a bien une API de sortie
(`setOnControlPointChangedListener`/`getControlPoints`) mais **jamais appelée dans
`AnimemesCompound.java`** — outil visuel sans effet sur l'animation, des deux côtés

**iOS avant correction** : `BezierEditorView.swift` (modèle+rendu+gestes complets) jamais instancié

**Changement appliqué** : bouton "bezier" toggle `showBezierEditor`, remplace la zone timeline
pendant qu'actif (comme Android), lié à un `BezierControlPoints` local jetable — délibérément PAS
relié au moteur de keyframes/easing

**Fichiers modifiés** : `AnimemesEditorView.swift`

**Commit** : `c912bdd`

**CI** : [run 32202682880](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202682880) —
`success`

**Statut de parité mis à jour** : F-27 `MISSING` → `COMPLETE_PARITY_CANDIDATE`

---

### Lot 7 — P1 : mode capture animée multi-frame

**Items couverts** : F-26

**Android retracé** : `ic_paint` branche sur `automateCapture` (`AnimemesCompound.java:2078-2095`)
— `drawPath` simple (déjà câblé) OU `PaintPreviewEditorPanel` (capture continue de frames, jamais
câblé côté iOS)

**iOS avant correction** : `PaintCaptureController`/`PaintDrawingCanvas` (`PaintCapture.swift`)
entièrement écrits, zéro appelant

**Changement appliqué** : `ic_paint` branche désormais sur `state.autoCaptureEnabled` ;
`PaintCaptureSheetView.swift` (nouveau, palette/épaisseur/vitesse) ;
`AnimemesEditorState.addCapturedPaintFrames` alimente le mécanisme de cyclage bitmap déjà existant
(`setBitmaps`/`bitmapChangeIntervalMs`/`advanceBitmapFrame`)

**Fichiers modifiés** : `AnimemesEditorState.swift`, `AnimemesEditorView.swift`,
`PaintCaptureSheetView.swift` (nouveau)

**Commit** : `72f2a0b`

**CI** : [run 32202814990](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202814990) —
`success`

**Statut de parité mis à jour** : F-26 `MISSING` → `COMPLETE_PARITY_CANDIDATE`

---

### Lot 8 — P2 : zoom du canevas (nettoyage + bug trouvé)

**Items couverts** : F-40

**Android retracé** : `CanvasZoomController.java` (`computeMinZoom`/`zoom(delta)`/`reset`)

**iOS avant correction** : `CanvasZoomState`/`CanvasZoomControls` (`CanvasZoomController.swift`)
orphelins — une version inline (`displayZoom`) faisait double emploi ET (**bug trouvé pendant ce
lot, pas dans l'audit initial**) ne zoomait RIEN visuellement, juste un label qui changeait

**Changement appliqué** : orphelin intégré (algorithme de clamp min/max dynamique plus fidèle) ;
`updateMinZoom` câblé sur `onAppear`/`onChange(of: fitSize)`

**Fichiers modifiés** : `AnimemesEditorView.swift`

**Commit** : `84339c0`

**CI** : [run 32202980938](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202980938) —
`success`

**Statut de parité mis à jour** : F-40 → `PARTIAL` (révisé — voir §23 de l'audit : l'orphelin est
éliminé et l'algorithme est correct, mais le zoom ne s'applique TOUJOURS PAS visuellement au
canevas ; appliquer `.scaleEffect` sur le `Canvas` porteur de `combinedGesture` jugé trop risqué
sans test réel après 2 bugs de geste déjà survenus cette session — documenté comme risque ouvert,
pas corrigé silencieusement à moitié)

---

### Lot 9 — P1 : Recompose

**Items couverts** : F-20

**Android retracé** : `onRecomposeClicked` → `getRecomposeCandidates()` (tous calques non
verrouillés+visibles, AUCUNE sélection manuelle) → `performRecompose` (≥2 requis) —
`AnimemesCompound.java:3464-3556`

**iOS avant correction** : `AnimemesRecompose.swift` (logique de fusion pure complète) zéro
appelant ; bouton "Compose" affiché grisé

**Changement appliqué** : `AnimemesEditorState.performRecompose()` (candidats → 
`buildComposedLayer` → ajout composer → masque les calques sources, comme
`src.setVisible(false)`) ; bouton "Compose" activé, alerte si <2 calques

**Fichiers modifiés** : `AnimemesEditorState.swift`, `AnimemesEditorView.swift`

**Commit** : `ae1d2d0`

**CI** : [run 32203115522](https://github.com/SalimMedir/TiinverSwift/actions/runs/32203115522) —
`success`

**Statut de parité mis à jour** : F-20 `MISSING` → `COMPLETE_PARITY_CANDIDATE`

**Notes** : `recomposeGroupId`/vue-groupe (`btn_view_group`/`btn_group_back`) et persistance disque
(`RecomposeManager`/"Load compose") restent délibérément non portés — périmètre déjà défini par
`AnimemesRecompose.swift` lui-même avant ce lot, pas un nouvel abandon.

---

### Lot 10 — P1 : application de template multi-piste

**Items couverts** : F-19

**Android retracé** : `applyMotionTemplateInternal`/`applyTemplateWithAutoCreate`
(`AnimemesCompound.java:2697-2784`) — boucle sur TOUTES les pistes, auto-création pour
shape/mask-render, consommation des calques existants pour bitmap/texte ; `showTemplateMismatchDialog`
— 3 boutons mais 2 appellent la même méthode avec les mêmes arguments (net : 2 comportements réels)

**iOS avant correction** : `applyTemplate` appliquait UNIQUEMENT la piste 0 au calque sélectionné

**Changement appliqué** : `applyTemplate` réécrit — boucle complète, `isAutoCreatableTrack` (port
d'`AnimationUtils.isAutoCreatableTrack`), `templateMismatch` + `confirmTemplateMismatch`/
`cancelTemplateMismatch`, alerte dans la vue

**Fichiers modifiés** : `AnimemesEditorState.swift`, `AnimemesEditorView.swift`

**Commit** : `56e0a1a`

**CI** : [run 32203269814](https://github.com/SalimMedir/TiinverSwift/actions/runs/32203269814) —
`success`

**Statut de parité mis à jour** : F-19 `PARTIAL` → `COMPLETE_PARITY_CANDIDATE`

**Notes** : redimensionnement du canvas d'édition à la taille du template (`mView.setCustomSize`)
délibérément pas porté — changerait silencieusement le ratio d'export choisi par l'utilisateur.

---

### Lot 11a — P2 : suppression de fond

**Items couverts** : F-29

**Android retracé** : `onRemoveBgClicked` (`AnimemesCompound.java:3853-3908`) — boucle sur TOUS les
bitmaps du calque (pas seulement le courant), ML Kit avec repli silencieux vers l'algorithme
géométrique, repli sur le bitmap d'origine si les deux échouent

**iOS avant correction** : aucune implémentation dans le module Animems (mais `RemoveBackground.swift`
existait déjà côté Galerie/éditeur photo — port du MÊME fichier Android partagé)

**Changement appliqué** : `AnimemesEditorState.removeBackgroundFromSelected()` (réutilise
`RemoveBackground.swift` tel quel, file d'arrière-plan) + bouton "fond" avec spinner de progression

**Fichiers modifiés** : `AnimemesEditorState.swift`, `AnimemesEditorView.swift`

**Commit** : `b090153`

**CI** : [run 32203423433](https://github.com/SalimMedir/TiinverSwift/actions/runs/32203423433) —
`success`

**Statut de parité mis à jour** : F-29 `MISSING` → `COMPLETE_PARITY_CANDIDATE`

**Notes** : deux gaps documentés mais délibérément NON traités dans ce lot (pas d'oubli silencieux) :

- **F-33 (contrôleur de mouvement manuel)** : `MovementControllerState.swift` documente lui-même
  que la logique de transformation réelle Android (`applySeekBarTransformOnAnchor`/
  `anchorTouchExecute`) n'a jamais été lue ni portée — contrairement à tous les lots précédents
  (câblage UI sur logique déjà écrite), celui-ci exigerait de PORTER une nouvelle logique moteur
  avant tout câblage UI. Nécessite son propre lot dédié.
- **F-34 (extraction audio depuis vidéo importée) — gap plus profond découvert** : traçage a révélé
  que `AnimemesEditorView.swift`'s `onVideoPicked` jette l'URL vidéo choisie et ferme juste le
  picker — **importer une vidéo comme calque est un no-op complet côté iOS aujourd'hui**, bien en
  amont de l'extraction audio elle-même. Noté comme nouveau finding F-45 dans l'audit.
- **F-32 (rail de vignettes)** : confirmé lors de l'audit Phase A comme fonctionnellement compensé
  par `TimelineView.swift` (scrub/navigation déjà possibles autrement) — aucune régression
  d'usage, laissé tel quel par choix (P2, optionnel).

---

## Récapitulatif — statut CI de tous les lots Phase B

| Lot | Commit | CI | Statut |
|---|---|---|---|
| 1 | `71375ff` | [32201713716](https://github.com/SalimMedir/TiinverSwift/actions/runs/32201713716) | ✅ success |
| 2 | `4f7d78e` | [32201920028](https://github.com/SalimMedir/TiinverSwift/actions/runs/32201920028) | ✅ success |
| 3 | `5b85e7e` | [32202284433](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202284433) | ✅ success |
| 4 | `ac46dc0` | [32202402631](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202402631) | ✅ success |
| 5 | `6980f39` | [32202564912](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202564912) | ✅ success |
| 6 | `c912bdd` | [32202682880](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202682880) | ✅ success |
| 7 | `72f2a0b` | [32202814990](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202814990) | ✅ success |
| 8 | `84339c0` | [32202980938](https://github.com/SalimMedir/TiinverSwift/actions/runs/32202980938) | ✅ success |
| 9 | `ae1d2d0` | [32203115522](https://github.com/SalimMedir/TiinverSwift/actions/runs/32203115522) | ✅ success |
| 10 | `56e0a1a` | [32203269814](https://github.com/SalimMedir/TiinverSwift/actions/runs/32203269814) | ✅ success |
| 11a | `b090153` | [32203423433](https://github.com/SalimMedir/TiinverSwift/actions/runs/32203423433) | ✅ success |

**11/11 lots BUILD_VALIDATED.** Aucun test réel device/Appetize effectué (conforme à la consigne).
Reste à traiter dans une future passe, documenté honnêtement plutôt qu'ignoré : F-33 (nouvelle
logique moteur à porter), F-34/F-45 (import vidéo, no-op fondamental), F-40 (zoom visuel du
canevas, risque de geste jugé trop élevé sans device réel), F-17 (format d'échange template
communautaire, décision produit/backend).
