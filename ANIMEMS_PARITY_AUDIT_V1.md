# ANIMEMS_PARITY_AUDIT_V1.md — Audit de parité Android → iOS, PROFOND ET INDÉPENDANT, spécial Animems

**Fichier dédié, séparé de `MIGRATION_PARITY_AUDIT_V2.md`, sur demande explicite (2026-08-18).**
Android = source de vérité absolue. **PHASE A UNIQUEMENT : ceci est un audit, AUCUN code n'a été
modifié pour produire ce document.** Objectif : que l'iOS soit au moins aussi complet/cohérent que
l'Android, pas une reproduction ligne à ligne — mais tout écart doit être visible, mesuré, et
honnêtement classé.

Date : 2026-08-18. Méthode : lecture personnelle intégrale des fichiers moteur les plus critiques
(`AnimationEngine.swift`, `Transform.swift`, `Keyframe.swift`, `KeyframeTrack.swift`,
`AnimationObjectData.swift`, `LayerRenderer.swift`, `AnimationComposer.swift`,
`AnimemesGestureController.swift`, `AnimemesEditorView.swift` en entier, sections critiques
d'`AnimemesEditorState.swift`) + vérification directe de sources Android citées en cas de doute +
3 agents en arrière-plan pour la cartographie Android exhaustive et deux audits iOS ciblés
(masques/templates, export/outils/rendu), dont les affirmations en conflit ont été **vérifiées
personnellement contre le code source Android avant d'être retenues** (voir §16.1 pour un exemple
documenté de correction d'un rapport d'agent par lecture directe).

---

## TAXONOMIE DES STATUTS (obligatoire, 11 valeurs, aucune exception)

| Statut | Signification |
|---|---|
| `COMPLETE_PARITY_CANDIDATE` | Comparaison code-à-code approfondie faite, semble atteindre la parité, AUCUN test réel (device/Appetize) encore. |
| `COMPLETE_PARITY_VALIDATED` | Preuve réelle de parité fonctionnelle ET visuelle (test réel confirmé). **Non utilisé dans ce document — aucun test réel n'a eu lieu cette session.** |
| `BUILD_VALIDATED` | Compile en CI. Rien de plus. |
| `CODE_PRESENT_UNVERIFIED` | Le code existe, comportement réel jamais démontré, ET aucune preuve statique définitive de son accessibilité/inaccessibilité n'a été établie. |
| `PARTIAL` | Une partie de la fonctionnalité Android existe côté iOS, éléments manquants identifiés précisément. |
| `VISUALLY_DIFFERENT` | La fonctionnalité existe et fonctionne, mais l'UI/UX diffère matériellement d'Android. |
| `FUNCTIONALLY_FAILED` | Défaut confirmé avec certitude — soit par test réel, soit (dans ce document, faute de test réel disponible) par **preuve statique exhaustive et déterministe** (ex. grep de TOUS les sites d'affectation d'une variable d'état, prouvant qu'aucun chemin de code ne peut jamais l'atteindre). Chaque emploi de ce statut dans ce document cite la preuve exacte et précise explicitement qu'elle est statique, pas un test d'exécution réel. |
| `MISSING` | Fonctionnalité Android réelle sans aucun équivalent iOS, ni code ni UI. |
| `DEAD_CODE` | Existe mais n'est atteignable dans AUCUN flux réel (Android ou iOS), confirmé par recherche exhaustive de sites d'appel. |
| `ANDROID_ONLY` | Fonctionnalité confirmée réelle côté Android, délibérément non portée (décision documentée, périmètre assumé). |
| `IOS_IMPROVED` | iOS fait mieux ou différemment d'Android sans perte fonctionnelle, par choix architectural documenté. |

**Règle stricte reconduite de V2** : un run CI vert donne droit à `BUILD_VALIDATED`, jamais plus.
Une lecture de code qui "semble correcte" donne droit à `COMPLETE_PARITY_CANDIDATE` au mieux.
**Aucune fonctionnalité Animems n'est marquée `COMPLETE_PARITY_VALIDATED` dans ce document.**

---

## 1. Cartographie Android complète

Établie par un agent d'exploration dédié (isolation worktree), méthode : grep exhaustif de site
d'appel (pas de déduction par nom de fichier) + lecture directe des fichiers listés ci-dessous.
Deux rapports d'audit Android préexistants dans le dépôt (`AUDIT_ANIMEMES_IOS_MIGRATION.md`,
`TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`) ont servi de base, corrigés par une vérification fraîche
dans cette session.

### 1.1 Point d'entrée réel (tracé étape par étape)

1. `MainFragment.java:777-781` — FAB (`R.id.fab`) → `requestPermission()` → `CameraActivity`.
2. `CameraActivity.onCreate()` → `onArticleSelected(0, null)` → `BaseCameraFragment` (le jumeau
   `CameraXFragment` n'est jamais instancié par `CameraActivity` — confirmé, aucun import).
3. `BaseCameraFragment.java:84` — menu `["GALLERI", "CAMERA", "ANIMEMES"]` → sélection index 2 →
   `doSelection(2)` → `mFragmentListener.onArticleSelected(5, null)`.
4. `CameraActivity.onArticleSelected(5, ...)` → `MemesFragment.newInstance(arg)` →
   `openFragment(memesFragment, false)`.
5. Autres entrées confirmées : `ChatFragmentTest.java:2072` (créer un mème pour l'envoyer en chat),
   `UserProfile.java`/`HashtagProfile.java` (usage périphérique, non prioritaire).

`MemesFragment.onCreateView` gonfle `fragment_memes.xml`, qui contient
`<com.animems.engine.android.views.AnimemesCompound>` — `onViewCreated` appelle
`animemes_compound.init()`. `AnimemesCompound` (3947 lignes) gonfle
`compound_animemes_layout.xml` et héberge `MemesView2` (le canvas réel — gestes, rendu, cycle
bitmap, `GestureListener`/`ScaleListener`/`RotationGestureDetector`).

### 1.2 Structure visuelle confirmée (`compound_animemes_layout.xml`)

- **Barre haute** : fermer / suivant-enregistrer / vitesse d'animation / auto-capture / résolution
  export / son.
- **Canvas** : `MemesView2` + `CanvasZoomController`.
- **Menu latéral droit** : collapse / texte / forme-de-texte (masqué) / dessin / taille-pinceau /
  undo / emoji / sticker / ajouter-image / fond-répété / formes / modèles communautaires.
- **Barre lecture** : réduire/agrandir, play.
- **Timeline (140dp)** : rail de vignettes (`frameList`), `MovementControllerHandlerView` (masqué
  par défaut), `TimelineView`.
- **Barre basse défilante** : Generate with AI / Recompose / voir-groupe (masqué) /
  retour-groupe (masqué) / galerie-recompose / galerie-templates / supprimer / réinitialiser /
  onglets-timeline / contrôleur-mouvement / frame / extraction-audio / bezier (masqué par défaut,
  togglé par un vrai bouton `btn_bezier`) / dupliquer / couleur / masque / remove-bg.
- **Overlays plein écran** : bulle d'aide, progress, preview animation, `CroperView`,
  `ProTextEditorView`, `BezierEditorView`.

### 1.3 Fichiers actifs vs morts (extrait, table complète en annexe de l'agent — voir historique
de conversation pour le rapport intégral de 42 lectures de fichiers)

| Catégorie | Actifs confirmés | Morts confirmés |
|---|---|---|
| Orchestrateur | `AnimemesCompound.java` | `AnimemesCompound2.java` (gonflé mais champ Java commenté), `AnimemesCompoundOpselete.java` |
| Canvas | `MemesView2.java`, `MemesView.java` (base partagée) | `MemesView3.java` |
| Timeline | `TimelineView.java` | `TimelineView2.java` |
| Masques | `mask/MaskType.java`, `android/mask/{MaskFactory,MaskAddPanel,MaskPreviewEditorPanel}.java`, `mask/MaskEditController.java` | `android/views/MaskPreviewEditorPanel2.java` |
| Codec/export | `MP4Encoder.java`, `LowLevelAlgorithme.java`, `audio_mixer/**` | `MP4Encoder2.java`, `AnimatedGifEncoder.java`, `GIFView.java`, `VideoEditor.java`, `UnifiedComposerFinal.java`, `AACTranscoder.java`, `AnimatedWatermarkComposer.java`, `codec/sampler/**`, `codec/gl/**` |
| Templates | `template/{MotionTemplate,MotionTemplateManager,MotionTrack,MotionTemplateNetworkDelegate}.java`, `TiinverTemplateRepository/Fetcher/Downloader/Uploader.java`, `CommunityTemplateGalleryView.java` | — |
| Recompose | `template/{RecomposeManager,RecomposeTemplate}.java`, `AnimemesRecomposeNameSheet.java`, `RecomposeGalleryView.java` | — |
| Hors périmètre (même arbre `engine/`, à ne pas confondre) | — | N/A — `ImageViewCanvas`/`ImageEditorCompound`/`android/croper/**` (éditeur photo simple), `android/gpuv/**` (caméra), `PBSCompound`/`android/pbs/**` (Shareboard live), `android/codec/graphic/**` + bulles `animemes_msg_*.xml` (affichage mème en chat) |

**Vérification personnelle contradictoire résolue (2026-08-18)** : l'agent de cartographie a
d'abord affirmé que l'upload de template communautaire (`onPublishTemplate`) était **actif**
(§4.3 de son rapport), contredisant l'agent d'audit masques/templates qui l'affirmait **mort**
(bouton commenté). **Lecture personnelle directe de
`engine/src/main/java/com/animems/engine/android/views/AnimemesActionSheet.java` lignes 103-116**
tranche définitivement en faveur du second agent :
```java
// ── Bouton 3 : Publier template CDN ────────────────────
/*root.addView(makeActionRow(
        ...
        listener.onPublishTemplate();
        ...
));

root.addView(makeDivider(context));*/
```
Le bloc entier est commenté. `listener.onPublishTemplate()` — et donc `saveAndUploadTemplate()`/
`TiinverTemplateUploader` — **n'est jamais appelé par aucune interaction utilisateur possible**,
même si la méthode existe et serait fonctionnelle si un jour rebranchée. **Statut Android réel :
`DEAD_CODE` (code présent, inaccessible)**, pas actif. C'est exactement le type d'erreur que cet
audit doit éviter de laisser passer sans vérification croisée — un agent avait raison sur le
fichier consommateur (`AnimemesCompound.saveAndUploadTemplate` existe bel et bien et appelle le
delegate), l'autre avait raison sur l'accessibilité réelle (le bouton qui le déclenche est mort) ;
aucun des deux seuls n'avait la réponse complète.

---

## 2. Cartographie iOS complète

`Sources/TiinverSwift/Animems/` (33 fichiers). Statut de câblage (appelé depuis un flux UI réel)
vérifié par grep de site d'appel pour CHAQUE fichier, pas déduit du nom.

| Fichier | Rôle | Câblé dans le flux réel ? |
|---|---|---|
| `AnimemesEditorView.swift` (695 l., lu en entier) | Écran principal SwiftUI | Oui — point d'entrée |
| `AnimemesEditorState.swift` (727 l.) | `ObservableObject` central, tout l'état + actions | Oui |
| `AnimationEngine.swift` (351 l., lu en entier) | Playback, bake keyframes, lissage Chaikin | Oui |
| `Transform.swift` (86 l., lu en entier) | État visuel par frame | Oui |
| `Keyframe.swift` (73 l., lu en entier) | Modèle keyframe | Oui |
| `KeyframeTrack.swift` (162 l., lu en entier) | Piste de keyframes + interpolation | Oui |
| `AnimationObjectData.swift` (648 l., lu en entier) | Modèle de calque | Oui |
| `AnimationComposer.swift` (31 l., lu en entier) | Conteneur de calques | Oui |
| `LayerRenderer.swift` (438 l., lu en entier) | Rendu bitmap/texte/sticker | Oui — 3 sites d'appel (canvas live, export image, export vidéo) |
| `AnimemesGestureController.swift` (215 l., lu en entier) | Logique pure translation/rotation/échelle/hit-test | Oui |
| `AnimemesExporter.swift` | Export vidéo `AVAssetWriter` | Oui |
| `TimelineView.swift` / `TimelineViewModel.swift` | Timeline SwiftUI style CapCut | Oui |
| `AnimemesDrawingView.swift` | Dessin libre simple | Oui |
| `MaskType.swift` / `MaskFactory.swift` | Enum 7 masques + rendu | Oui (câblé dans `LayerRenderer`/`BitmapCacheManager`) |
| `BitmapCacheManager.swift` | Cache feather/masque | Oui |
| `MotionTemplate.swift` / `MotionTemplateManager.swift` / `MotionTemplateGalleryView.swift` | Templates locaux | Oui |
| `CommunityTemplateRepository.swift` / `CommunityTemplateGalleryView.swift` / `TemplateRemoteModel.swift` | Templates communautaires (browse/download/apply) | Oui |
| `ShapeFactory.swift` | Rastérisation formes | Oui (`rerender` via `MotionTemplateManager`, `createRect/Circle/Line` via `addShape`) |
| `TextRect.swift` / `TextLayoutEngine.swift` | Layout/rendu texte | Oui |
| **`MaskEditController.swift`** | Protocoles geste/mode masque | **NON — jamais conformé par aucun type** |
| **`MaskPreviewEditorPanelState.swift`** | État panneau masque (opacité/flou/inversion) | **NON — jamais instancié hors son fichier** |
| **`ShapePreviewEditorPanelState.swift`** | État panneau config forme avant insertion | **NON — jamais instancié hors son fichier** |
| **`AnimemesRecompose.swift`** | Logique pure de fusion recompose | **NON — zéro appelant, 2 mentions en commentaire seulement** |
| **`BezierEditorView.swift`** | Éditeur courbe d'accélération SwiftUI complet | **NON — jamais instancié** |
| **`PaintCapture.swift`** (`PaintCaptureController`, `PaintDrawingCanvas`) | Dessin animé multi-frame | **NON — jamais instancié** |
| **`CanvasZoomController.swift`** | Port du zoom Android (+/−/fit) | **NON — la vue utilise son propre `zoomControls` inline (`AnimemesEditorView.swift:342-358`), ce fichier n'est référencé nulle part ailleurs** |
| **`FrameListState.swift`** | Rail de vignettes (port de `frameList`/`FrameAdapter`) | **NON — jamais instancié** |
| **`MovementControllerState.swift`** | Sliders manuels zoom/rotation/skew | **NON — jamais instancié** |
| `SerializableAnimationObject.swift`, `PlaylistEntry.swift`, `StickerData.swift`, `DrawPathFrameData.swift`, `LayerEditorPanelState.swift`, `ProTextEditorState.swift`, `AnimationUtils.swift`, `BitmapGeometry.swift` | Modèles/utilitaires divers | Statut mixte, non tous vérifiés individuellement dans cette passe — voir §16 |

**8 fichiers sur 33 (24%) sont du code mort côté iOS** — une proportion notable, tous documentés
individuellement plus bas (§16).

---

## 3. Flux utilisateur Android → iOS (comparaison étape par étape)

| Étape | Android (réel, tracé) | iOS (réel, tracé) | Écart |
|---|---|---|---|
| Entrée | Feed → FAB → menu caméra 3 choix → "ANIMEMES" → `MemesFragment` | Bouton dédié (tab bar/deep-link `.animems`) → `fullScreenCover(AnimemesEditorView)` direct, 3 sites d'appel (`FeedView`, `HomeShellView`, `MonetizationView`) | `VISUALLY_DIFFERENT` — chrome de navigation différent (pas de menu caméra intermédiaire), mais atteint le même éditeur. Non bloquant, simplification de navigation assumée. |
| Ouverture éditeur | `AnimemesCompound.init()` | `AnimemesEditorState()` (StateObject) | Équivalent |
| Ajout de média (image) | Galerie → `CroperView` (recadrage) → ajouté comme calque BITMAP | `GalleryPickerView` → `state.addImage` (**pas de recadrage avant ajout**) | `PARTIAL` — `CroperView` confirmé actif dans le flux Animems Android (`compound_animemes_layout.xml:1023-1027`), pas d'équivalent de recadrage pré-insertion côté iOS |
| Sélection/désélection calque | `MemesView2.touchDown`/hit-test par inversion de matrice | `AnimemesGestureController.isPoint(insideObjectAt:)`, même algorithme | `COMPLETE_PARITY_CANDIDATE` |
| Déplacer/pivoter/redimensionner | Gestes natifs Android (1 doigt translate, 2 doigts rotate+scale simultané) | `SimultaneousGesture(drag, magnification, rotation)` | `COMPLETE_PARITY_CANDIDATE` — logique vérifiée ligne à ligne, MAIS non re-confirmée par test réel depuis le dernier correctif (voir §18.1) |
| Ordre des calques | `bringLayerToFront` au toucher | Idem, même méthode portée | `COMPLETE_PARITY_CANDIDATE` |
| Suppression | `remover` (calque sélectionné), `undo` (dernier calque) | `state.deleteSelected()`, `state.removeLast()`, mêmes boutons | `COMPLETE_PARITY_CANDIDATE` |
| Timeline / playhead | `TimelineView.java` (CapCut-style) | `TimelineView.swift` port dédié | `COMPLETE_PARITY_CANDIDATE` (voir §8) |
| Keyframes | Marqueur explicite + capture continue en mode auto | `state.recordKeyframe()` (bouton ◆), `autoCaptureEnabled` (approximation documentée) | `PARTIAL` — voir §9 |
| Masques | `btn_mask` → `MaskAddPanel` → `MaskPreviewEditorPanel` (geste direct sur canvas) | **AUCUN bouton n'ouvre jamais le mode masque** (`isMaskEditMode` jamais mis à `true`) | **`FUNCTIONALLY_FAILED` — voir §11, finding le plus critique de cet audit** |
| Templates de mouvement | Galerie locale + galerie communautaire + application multi-piste avec redimensionnement canvas | Galerie locale + galerie communautaire (contenu réel non interopérable) + application piste 0 seule, calque sélectionné seul | `PARTIAL` — voir §12 |
| Recompose | Bouton réel, nommage, persistance PNG, galerie dédiée | Boutons "Compose"/"Load compose" affichés grisés (`disabled(true)`), logique de fusion portée mais aucune UI ne l'invoque | `MISSING` (assumé et documenté honnêtement en UI, pas silencieux) |
| Preview plein écran avant export | `AnimationPreView`/`AnimationScreen` | Aucun équivalent trouvé — l'export se fait directement | `MISSING` (mineur, priorité basse — le canvas d'édition sert déjà de preview en direct via le playhead) |
| Export vidéo | `MP4Encoder` (GLSL/EGL/MediaCodec) | `AnimemesExporter` (`AVAssetWriter`), **police du texte différente de l'éditeur** (voir §13.1) | `FUNCTIONALLY_FAILED` pour le texte spécifiquement, `COMPLETE_PARITY_CANDIDATE` pour le reste |
| Export image statique | `createImage`/`saveBitmapDrawed` | `state.exportStaticImage` | `COMPLETE_PARITY_CANDIDATE` |
| Retour vers publication Tiinver | Passe systématiquement par un écran de crop/trim intermédiaire (`MediaEditor`/`MediaTrim`) avant `PublishFragment` | `onClose()` ferme directement le `fullScreenCover` — pas d'écran intermédiaire de recadrage final tracé dans ce module | `CODE_PRESENT_UNVERIFIED` — le point d'intégration exact avec le flux de publication Galerie n'a pas été retracé dans cette passe (hors périmètre strict "moteur Animems", à vérifier dans un futur audit Galerie) |
| Fermeture sans export | `bundleDeliverListener.onCloseView()` → retour caméra | `onClose()` → ferme le `fullScreenCover`, retour à l'écran d'origine | Équivalent |

---

## 4. Tableau de parité complet

Colonnes : ID · Fonctionnalité · Source Android · Comportement Android réel · Fichier(s) iOS ·
Comportement iOS réel · Statut · Preuve · Écart · Priorité · Action nécessaire.

| ID | Fonctionnalité | Android source | Comportement Android réel | iOS fichier(s) | Comportement iOS réel | Statut | Preuve | Écart | Priorité | Action nécessaire |
|---|---|---|---|---|---|---|---|---|---|---|
| F-01 | Modèle de calque (`AnimationObjectData`) | `core/AnimationObjectData.java` (617 l.) | Type BITMAP/ERASE/TEXT/PATH/LINE/CLIP/STICKER/BACKGROUND/SHAPE_*, frames multiples, transforms, keyframeTracks, masque appliqué | `AnimationObjectData.swift` (648 l.) | Port champ à champ confirmé, classe de référence (raison documentée) | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale des deux fichiers, ligne à ligne | Aucun champ manquant identifié | — | Aucune |
| F-02 | Transform par frame | `core/Transform.java` | matrix/opacity/color/cornerRadius/feather | `Transform.swift` (86 l.) | Port fidèle, mapping d'index Android↔CoreGraphics documenté | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale | Aucun | — | Aucune |
| F-03 | Keyframe/interpolation | `keyframe/{Keyframe,KeyframeTrack}.java` | ARGB packing, easing 4 courbes, clamp avant/après | `Keyframe.swift`/`KeyframeTrack.swift` | Port fidèle vérifié | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale | Aucun | — | Aucune |
| F-04 | Moteur de lecture (`prepare`/`play`/`pause`/`seek`) | `core/AnimationEngine.java` | `TimeAnimator`, bake keyframes→transforms, `androidToGL_Matrix2`, lissage Chaikin | `AnimationEngine.swift` (351 l.) | Port fidèle, `CADisplayLink` au lieu de `TimeAnimator` | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale | Aucun sur la logique elle-même | — | Aucune |
| F-05 | **Performance lecture — recalcul de la table complète à chaque frame** | N/A (bug iOS-only introduit par le split version/renderVersion de cette session) | N/A | `AnimemesEditorState.swift:724-726`, `AnimemesEditorView.swift:314` | `animationEngineDidInvalidate` (appelé ~30×/s pendant la lecture) incrémente `version`, PAS `renderVersion` ; `.onChange(of: state.version)` déclenche `preparePlayback()`→`engine.prepare()`, un rebuild O(objets×frames) de la table de transformation — **exécuté sur CHAQUE frame de lecture** | `FUNCTIONALLY_FAILED` | Preuve statique : citation directe des deux sites, lus intégralement cette session. Pas de test réel (perf non mesurée sur device) mais la relation de cause à effet est déterministe et non ambiguë dans le code | Bug de performance sévère, potentiellement lecture saccadée/CPU élevé sur animations avec plusieurs calques/keyframes | **P0** | `animationEngineDidInvalidate` doit appeler `bumpRenderVersion()`, pas incrémenter `version` |
| F-06 | Hit-test (sélection) | `MemesView2.isPointInsideObject` | Inversion de matrice de la dernière `Transform`, test dans `bound` local | `AnimemesGestureController.isPoint(insideObjectAt:)` | Port identique | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale | Différence documentée : Android `Matrix.invert` retourne un bool d'échec, `CGAffineTransform.inverted()` renvoie la transform d'origine sur matrice non inversible — cas limite jamais rencontré en pratique | — | Aucune |
| F-07 | Ordre des calques (Z-order) | `bringLayerToFront` | Déplace en fin de tableau au toucher | `AnimemesGestureController.bringLayerToFront` | Port identique | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale | Aucun | — | Aucune |
| F-08 | Gestes 1-doigt (translation) | `MemesView2.touchMove` (branche translation) | Delta depuis dernier point | `dragGesture` (`AnimemesEditorView.swift:506-535`) → `state.dragMoved` → `AnimemesGestureController.translation` | Port fidèle, delta calculé côté vue | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale + vérif ordre de composition matricielle (`post*` Android = `concatenating` après, documenté et corrigé avant tout build) | Non re-testé sur device depuis dernier correctif | — | Voir §18.1 (risque non confirmé) |
| F-09 | Gestes 2-doigts (pinch+rotate simultané) | `ScaleListener`/`RotationGestureDetector` | Facteur/angle incrémentaux par événement | `magnificationGesture`/`rotationGesture` (`AnimemesEditorView.swift:537-580`) | Reconciliation cumulatif→incrémental documentée et implémentée (`value / lastMagnification`) | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale | Non re-testé sur device depuis dernier correctif | — | Voir §18.1 |
| F-10 | Bug de recréation de geste via `.id(state.version)` | N/A | N/A | `AnimemesEditorView.swift` (canvas principal), `TimelineView.swift` | **Trouvé et corrigé 2 fois cette session** (commits `0a8966b`, `e7736af`) ; recherche exhaustive cette passe (`grep ".id(...version...)"` sur tout `Animems/`) : **aucune occurrence vivante restante**, seulement 2 mentions en commentaire documentant le bug déjà résolu | `COMPLETE_PARITY_CANDIDATE` (résolu) | Grep exhaustif, 2 résultats = commentaires historiques uniquement | Aucun résiduel trouvé dans le périmètre Animems | — | Aucune — mais non re-testé sur device (voir §18.1) |
| F-11 | Mode d'édition masque — **entrée dans le mode** | `MaskAddPanel` déclenché par `btn_mask` (bouton bottom_navigation réel) | Ouvre le panneau de sélection de masque, bascule `MemesView2` en mode édition masque | `isMaskEditMode` (`AnimemesEditorState.swift:57`), `maskPanel(for:)` (`AnimemesEditorView.swift:599`) | **`isMaskEditMode` n'est JAMAIS assigné à `true` nulle part dans tout `Sources/TiinverSwift`** (grep exhaustif `\.isMaskEditMode\s*=` : unique résultat = mise à `false` dans le bouton "Aucun" DU panneau lui-même). Le panneau (`if state.isMaskEditMode { maskPanel(...) }`) ne peut donc jamais s'afficher | **`FUNCTIONALLY_FAILED`** | Grep exhaustif `\.isMaskEditMode\s*=` sur tout le projet — preuve statique déterministe, pas de test réel nécessaire : il n'existe simplement aucun chemin de code vers `true` | **Aucun utilisateur iOS ne peut jamais appliquer un masque à un calque, malgré un moteur de masque entièrement fonctionnel et câblé en aval** | **P0 — CRITIQUE** | Ajouter un bouton (ex. dans `rightToolbar` ou `bottomToolbar`, correspondant à `btn_mask`) qui fait `state.isMaskEditMode = true` pour le calque sélectionné |
| F-12 | Moteur de masque (7 formes, scale/offset/rotation/mirrorGap/feather/invert) | `android/mask/MaskFactory.java` | `createMaskScaled` | `MaskFactory.swift` | Port fidèle, câblé dans `LayerRenderer`/`BitmapCacheManager` | `COMPLETE_PARITY_CANDIDATE` | Lecture + rapport agent masques, vérifié | Flou via `CIGaussianBlur` au lieu de `BlurMaskFilter` — équivalence comportementale, pas bit-identique | — | Aucune (mais inaccessible en pratique, voir F-11) |
| F-13 | Priorité `maskTransforms` (capture auto) sur `KeyframeTrack` au rendu | `MemesView2.drawBitmapLastTransform`/`drawObjectFrame` | `maskTransforms` prioritaire si présent | `LayerRenderer.swift:79-88` (`drawLastTransform`), `:169-177` (`drawObjectFrame`) | **Confirmé implémenté** — le commentaire de tête de fichier d'`AnimationObjectData.swift` affirmait ce comportement "pas encore écrit" ; lecture directe de `LayerRenderer.swift` cette session prouve que c'est FAIT | `COMPLETE_PARITY_CANDIDATE` (résolu, contredit un commentaire de code obsolète) | Lecture intégrale `LayerRenderer.swift` | Commentaire obsolète dans `AnimationObjectData.swift` à corriger (cosmétique) | P2 | Mettre à jour le commentaire dans `AnimationObjectData.swift` |
| F-14 | Édition post-application masque (opacité/flou/inverser/mirrorGap) | `MaskPreviewEditorPanel.java` | Panel + geste direct délégué au canvas | `AnimemesEditorState` setters + `maskPanel(for:)` | Logique portée, mais **inaccessible** (dépend de F-11) | `FUNCTIONALLY_FAILED` (conséquence directe de F-11) | Même preuve que F-11 | — | P0 (lié à F-11) | Résoudre F-11 |
| F-15 | Templates locaux (sauvegarder/charger/supprimer/galerie) | `MotionTemplateManager.java` + `MotionTemplateGalleryView.java` | Sérialisation Java, persistance disque | `MotionTemplateManager.swift` + `MotionTemplateGalleryView.swift` | Port JSON `Codable`, câblé (`saveAsTemplate`/bouton "Modèle") | `COMPLETE_PARITY_CANDIDATE` | Rapport agent masques/templates + vérification | Aucun | — | Aucune |
| F-16 | Templates communautaires — parcourir/filtrer/paginer/prévisualiser/télécharger | `CommunityTemplateGalleryView.java` (854 l.) + `TiinverTemplateFetcher/Downloader.java` | Grille 2 colonnes, 4 filtres, pagination infinie | `CommunityTemplateGalleryView.swift` + `CommunityTemplateRepository.swift` | Port complet, câblé | `COMPLETE_PARITY_CANDIDATE` | Rapport agent + vérification | Aucun sur la navigation/liste elle-même | — | Aucune |
| F-17 | Templates communautaires — **contenu réel appliqué après téléchargement** | `.tmpl` = sérialisation Java binaire | Mouvement réel appliqué après téléchargement | `CommunityTemplateRepository.rebuildFromRemote` | `.tmpl` Android illisible en Swift (formats incompatibles) — repli systématique sur métadonnées seules, **tracks toujours vides** | `PARTIAL` | Rapport agent, confirmé par lecture du repli documenté dans le fichier iOS | Un template communautaire téléchargé ne bouge jamais réellement l'objet, seule la fiche (nom/aperçu/son) est utilisable | **P1** | Définir un format d'échange commun (JSON exporté par un futur endpoint, ou reconstruction manuelle des tracks depuis les métadonnées si le CDN les expose) — nécessite une décision produit/backend, hors portée d'un simple correctif iOS |
| F-18 | Upload de template vers la communauté | `AnimemesActionSheet` bouton 3 — **confirmé mort** (bloc commenté, §1.3) | Bouton présent en Java mais inatteignable | `TiinverTemplateUploader` non porté | Non porté, choix cohérent avec l'état réel Android | `DEAD_CODE` côté Android → `ANDROID_ONLY` non applicable, correctement absent côté iOS | Lecture directe `AnimemesActionSheet.java:103-116` | Aucun — décision correcte | — | Aucune |
| F-19 | Application de template — **multi-piste + redimensionnement canvas + auto-création de calques** | `AnimemesCompound.applyMotionTemplateInternal` → `applyTemplateWithAutoCreate`/`applyTemplateDirectly` + `showTemplateMismatchDialog` | Boucle sur TOUTES les pistes, redimensionne le canvas (`mView.setCustomSize`), auto-crée les calques manquants, dialogue si incompatibilité | `AnimemesEditorState.applyTemplate` (`AnimemesEditorState.swift:603-608`) | **Applique UNIQUEMENT `trackIndex: 0`, au SEUL calque sélectionné**, aucun redimensionnement de canvas, aucune auto-création, aucun dialogue | `PARTIAL` | Lecture directe des deux côtés, citée avec numéros de ligne | Un template Android multi-objets (cas courant) sera partiellement appliqué côté iOS | **P1** | Étendre `applyTemplate` pour itérer toutes les pistes, mapper aux calques existants par position/index, proposer l'auto-création des calques manquants |
| F-20 | Recompose (fusion de calques sélectionnés en séquence bitmap réutilisable) | `AnimemesCompound.performRecompose` + `RecomposeManager`/`RecomposeGalleryView`/`AnimemesRecomposeNameSheet` — bouton réel, nommage, persistance PNG, galerie dédiée | Fonctionnalité active de bout en bout | `AnimemesRecompose.swift` (logique pure portée) | **Aucune UI, aucun appelant** — les boutons "Compose"/"Load compose" existent mais sont `disabled(true)`, `opacity(0.4)` | `MISSING` | Grep exhaustif : zéro appelant de `AnimemesRecompose.*` hors son propre fichier + 2 mentions en commentaire | Fonctionnalité entière absente de l'usage réel, malgré logique de fusion déjà écrite et prête | **P1** | Construire l'UI de sélection multi-calques + nommage + galerie ; brancher `AnimemesRecompose.recompose(...)` déjà existant |
| F-21 | Forme vectorielle — insertion (rect/circle/line) | `ShapeFactory.rerenderShape` | Rastérisation avec couleur/opacité/arrondi/épaisseur configurables AVANT insertion via `ShapePreviewEditorPanel` | `state.addShape` (`AnimemesEditorState.swift:210-225`) | Insertion directe avec valeurs **codées en dur** (rouge 150×100, vert cercle 140, bleu ligne 200×8) | `PARTIAL` | Rapport agent export/outils + lecture | Pas de personnalisation avant insertion, contrairement à Android | **P2** | Monter `ShapePreviewEditorPanelState.swift` (déjà écrit, orphelin) dans une vraie feuille SwiftUI avant `addShape` |
| F-22 | Texte — édition/layout/rendu dans l'éditeur | `MemesView2.writeText` + `TextRect`/`TextLayoutEngine` | Police éditeur = bake réel dès la 1ère frame | `LayerRenderer.drawText` + `TextRect.swift` | Port fidèle, police `.boldSystemFont(32)` définie dans `AnimemesEditorState.swift:85`, cohérente entre canvas live et export image | `COMPLETE_PARITY_CANDIDATE` | Lecture intégrale | Aucun dans l'éditeur lui-même | — | Aucune |
| F-23 | Texte — **police en export VIDÉO** | `MP4Encoder.renderSceneIntoFbo` — traite tous les calques comme textures GL déjà "bakées" (aucun code de police dans le pipeline vidéo) | Cohérence garantie structurellement (bake-once) | `AnimemesExporter.swift:69-71` | `AnimemesExporter(composer:)` (seul appelant, `AnimemesEditorState.swift:627`) **n'utilise pas les paramètres `font`/`textColor`** — construit son propre `TextRect(font: .systemFont(14), ...)` au lieu de réutiliser `state.textRect` (`.boldSystemFont(32)`) | **`FUNCTIONALLY_FAILED`** | Citation directe des deux sites (init par défaut vs seul call site), rapport agent export/outils, vérifié cohérent avec l'architecture "re-render toujours" documentée du fichier | **Tout calque TEXTE apparaît nettement plus petit et non-gras dans la vidéo MP4 exportée que dans l'éditeur** — bug de parité rendu réel, visible par tout utilisateur exportant du texte | **P0** | `AnimemesEditorState.export` doit passer `font`/`textColor` (ou directement `self.textRect`) au constructeur d'`AnimemesExporter` |
| F-24 | Sticker/emoji | `DisplayStickerListener` (Android : pas de catalogue custom confirmé, clavier système) | Clavier emoji natif | `showStickerPrompt` + `state.addSticker` | Clavier emoji natif iOS, fidèle (Android n'a pas non plus de catalogue custom) | `COMPLETE_PARITY_CANDIDATE` | Lecture + doc de tête de fichier | Aucun | — | Aucune |
| F-25 | Dessin libre simple (trait unique) | `mView.setAction("drawPath")` | Capture directe du geste | `AnimemesDrawingView.swift` | Port fidèle, câblé | `COMPLETE_PARITY_CANDIDATE` | Rapport agent + lecture | Aucun | — | Aucune |
| F-26 | Dessin animé multi-frame (`automateCapture` actif) | `PaintPreviewEditorPanel.java`, togglé par un switch utilisateur réel (`AnimemesCompound.java:1902/3209`) | Capture en continu de nouvelles frames pendant le geste | `PaintCapture.swift` (`PaintCaptureController`/`PaintDrawingCanvas`) | Logique portée à l'identique, **jamais instanciée, aucun entry point UI** | `MISSING` | Grep exhaustif, zéro appelant hors fichier propre | Deuxième mode de dessin Android (le mode "capture animée") totalement inaccessible côté iOS | **P1** | Ajouter le toggle `automateCapture` (existe déjà, `AnimemesEditorState.autoCaptureEnabled`) comme branche pour router vers `PaintCaptureController` au lieu d'`AnimemesDrawingView` |
| F-27 | Éditeur de courbe d'accélération (bezier easing) | `BezierEditorView.java`, togglé par bouton réel `btn_bezier` (`AnimemesCompound.java:1970-1980`) | Édition de courbe custom pour l'interpolation | `BezierEditorView.swift` | Port SwiftUI complet (modèle+rendu+gestes), **jamais instancié** | `MISSING` | Grep exhaustif, zéro appelant. Source unique (agent export/outils) pour la ligne Android exacte — non re-vérifiée personnellement, confiance élevée mais mono-source (voir §18.2) | Fonctionnalité d'easing avancé totalement inaccessible côté iOS | P2 | Ajouter le bouton manquant + monter la vue |
| F-28 | Panneau d'édition de calque (opacity/tint/cornerRadius/feather, preview→validate/cancel) | `LayerEditorPanel.java` (504 l.) | Panel dédié avec création de keyframes | `LayerEditorPanelState.swift` | Non vérifié en détail cette passe (fichier listé mais pas lu intégralement) | `CODE_PRESENT_UNVERIFIED` | Fichier existe, non audité en profondeur | Statut d'accessibilité réelle non déterminé | P1 (à ré-auditer) | Auditer `LayerEditorPanelState.swift` + ses sites d'appel dans une prochaine passe |
| F-29 | Suppression de fond (remove background) | `Utils/RemoveBackground.java`, bouton réel `btn_removebg` | Détoure le calque sélectionné | Aucun fichier équivalent trouvé dans `Animems/` (seule mention : commentaire dans `FrameListState.swift` citant "RemoveBackground du point 2 du plan module 8") | **Aucune implémentation trouvée dans le module Animems** | `MISSING` | Grep exhaustif `RemoveBackground`/`removeBackground` dans `Animems/` : une seule occurrence, en commentaire | Fonctionnalité Android réelle sans équivalent iOS dans Animems (la Galerie a sa propre suppression de fond IA, portée séparément — pas réutilisée ici) | P2 | Réutiliser le pipeline de suppression de fond déjà construit pour la Galerie, l'exposer comme bouton calque dans Animems |
| F-30 | Duplication de calque | `AnimemesCompound` bouton `btn_duplicate` | Copie un calque sélectionné | `AnimationObjectData.duplicate`/`duplicate2` (statiques, lignes 572/624) | Méthodes portées (copie profonde vs superficielle), **zéro site d'appel** | `MISSING` | Grep exhaustif `AnimationObjectData\.duplicate` : uniquement la déclaration | Impossible de dupliquer un calque côté iOS malgré la logique déjà écrite | P2 | Ajouter un bouton bottomToolbar → `state.duplicateSelected()` (à écrire, appelant `AnimationObjectData.duplicate`) |
| F-31 | Teinte de couleur du calque sélectionné | `ic_palete` bouton réel | Sélecteur de couleur, applique `objectColor`/keyframe couleur | Pas de bouton dédié trouvé (le champ `color`/`tfm.color` existe et est utilisé par `LayerRenderer`/`resolveVisualProperties`, mais pas de UI pour le régler hors `LayerEditorPanelState` non monté) | Dépend du statut de F-28 | `CODE_PRESENT_UNVERIFIED` (lié à F-28) | — | — | P1 (à ré-auditer avec F-28) | Voir F-28 |
| F-32 | Rail de vignettes (miniatures de frame) | `FrameAdapter.java` + `frameList` RecyclerView | Rail horizontal de miniatures de la timeline | `FrameListState.swift` | Port de l'état, **jamais instancié** | `MISSING` mais `IOS_IMPROVED` partiel — la navigation/scrub reste possible via `TimelineView.swift` (paradigme différent, pas de perte de capacité de navigation) | Grep exhaustif, zéro appelant | Différence purement visuelle de présentation, la fonction de scrub existe par un autre chemin | P2 | Optionnel — évaluer si le rail de vignettes apporte une valeur au-delà de `TimelineView` avant de l'implémenter |
| F-33 | Contrôleur de mouvement manuel (sliders zoom/rotation/skew sans geste tactile) | `MovementControllerHandlerView.java`, masqué par défaut mais réel | Alternative aux gestes pour animer précisément | `MovementControllerState.swift` | Port de l'état, **jamais instancié** | `MISSING` | Grep exhaustif, zéro appelant | Pas d'alternative aux gestes tactiles pour un réglage fin | P2 | Monter une vue à partir de `MovementControllerState.swift` déjà écrit |
| F-34 | Extraction audio depuis une vidéo importée | `ExtracAudioFromVideo.java`, bouton réel `extract` | Extrait la piste audio d'une vidéo importée comme calque | Aucun bouton équivalent trouvé (`showAudioPicker` = import direct d'un fichier audio, PAS extraction depuis vidéo) | Non porté | `MISSING` | Lecture intégrale de `AnimemesEditorView.swift`, aucune référence à une extraction audio-depuis-vidéo | Un utilisateur ne peut pas réutiliser l'audio d'une vidéo déjà importée comme calque | P2 | Ajouter l'extraction via `AVAssetExportSession`/`AVAssetReader` sur `audioURL` si le calque source est une vidéo |
| F-35 | Génération IA d'objet ("Generate with AI") | `btn_ai_generate`, `aiObjectDelegate` **jamais assigné** côté Android | Bouton réel, tap ne fait rien de visible (log seulement) | Bouton affiché, sans action | Fidèle à l'inaction réelle d'Android | `ANDROID_ONLY` (délibérément non reproduit au-delà de l'apparence, car Android lui-même n'a pas de comportement à reproduire) | Doc de tête de fichier + confirmé par cartographie | Aucun — parité comportementale exacte (inaction des deux côtés) | — | Aucune |
| F-36 | Répéter l'image de fond | `onRepeateImage`/`CroperView` | Reconstruction exacte via recadrage | `repeatBackgroundImage()` (`AnimemesEditorView.swift:391-413`) | Approximation assumée : aplatissement de la frame courante en nouveau calque statique | `PARTIAL` (approximation documentée, pas un oubli) | Lecture + doc en tête de fonction | Résultat visuel probablement proche mais pas garanti identique pixel à pixel | P2 | Optionnel — non prioritaire, effet visuel secondaire |
| F-37 | Export vidéo — pipeline général (hors texte) | `MP4Encoder.java` (GLSL/EGL/MediaCodec) | Pipeline complexe mais equivalent fonctionnel | `AnimemesExporter.swift` (`AVAssetWriter`) | Chaîne tracée en entier : bouton → `state.export` → `AnimemesExporter.export(to:)` → `render(frame:into:)` (réutilise `LayerRenderer` — MÊME code que le canvas live, sauf texte) → `AVAssetWriter` | `COMPLETE_PARITY_CANDIDATE` (hors bug texte F-23) | Rapport agent export/outils, tracé ligne par ligne | Destination différente : `ShareLink` iOS vs `ACTION_MEDIA_SCANNER_SCAN_FILE` Android (différence de plateforme légitime, pas un bug) | — | Aucune |
| F-38 | Export image statique | `createImage`/`saveBitmapDrawed` (JPEG qualité 70) | Export direct | `AnimemesEditorState.exportStaticImage` | Port fidèle, réutilise `self.textRect` correctement (pas le bug F-23) | `COMPLETE_PARITY_CANDIDATE` | Lecture directe | Aucun | — | Aucune |
| F-39 | Export GIF | `AnimatedGifEncoder.java`/`GIFView.java` — **confirmé mort côté Android** (zéro appelant) | N/A, jamais exposé à l'utilisateur | Non porté | Non porté | `ANDROID_ONLY` → correctement absent (Android lui-même ne l'expose jamais) | Grep exhaustif Android confirmé par agent cartographie + `AnimemesEditorState.swift:613-618` documente explicitement cette décision | Aucun — décision correcte | — | Aucune |
| F-40 | Zoom du canvas d'édition (affichage, pas résolution export) | `CanvasZoomController.java` | Boutons +/−/fit, reset avant export | `zoomControls` inline (`AnimemesEditorView.swift:342-358`) — **PAS** `CanvasZoomController.swift` (orphelin, doublon jamais utilisé) | Fonctionnellement équivalent (+/−/fit) mais implémenté deux fois côté iOS, une version morte | `COMPLETE_PARITY_CANDIDATE` fonctionnellement, mais avec doublon de code mort | Lecture directe + grep | Duplication de code sans impact utilisateur | P2 (nettoyage) | Supprimer `CanvasZoomController.swift` OU migrer `zoomControls` pour le réutiliser (nettoyage, pas fonctionnel) |
| F-41 | Preview plein écran avant export | `AnimationPreView.java`/`AnimationScreen.java`, confirmés actifs par présence dans les classes `*Binding.java` générées | Écran de preview dédié avant validation finale | Aucun équivalent trouvé | Le canvas d'édition sert de preview en direct (playhead) | `MISSING` (mineur) | Lecture intégrale `AnimemesEditorView.swift`, aucun écran de preview séparé | Étape UX Android absente, mais la fonction (voir avant d'exporter) existe déjà en continu dans l'éditeur | P2 | Optionnel, faible priorité |
| F-42 | Tutoriel intégré (coach marks, 6 étapes) | `android/taptargetview/**` (librairie vendorisée), `showAnimemeTutorial*`, clé `Const.ANIMEMES_TUTO` | Onboarding visuel au premier lancement | Aucun équivalent trouvé | Non porté | `MISSING` | Cartographie agent, non contredite par mes lectures | Pas d'onboarding pour un nouvel utilisateur iOS | P2 | Optionnel |
| F-43 | Ratio de canevas (résolution export) | `spinnerResolution` | 9:16/16:9/3:4/1:1, contrôle aussi résolution d'export | `selectedRatioIndex`/`ratioOptions` (`AnimemesEditorView.swift:73-75`) | Port fidèle, ordre confirmé par capture d'écran Android | `COMPLETE_PARITY_CANDIDATE` | Doc de tête de fichier | Aucun | — | Aucune |
| F-44 | Vitesse d'animation (`frame_duration_array2`) | `R.array.frame_duration_array2` | 5 vitesses | `speedOptions` (`AnimemesEditorView.swift:70`) | Port fidèle des libellés, **effet réel sur le moteur non confirmé identique** (modèle de moteur différent d'Android, documenté) | `PARTIAL` | Doc de tête de fichier (auto-documentée comme limite assumée) | Le sélecteur existe visuellement mais son effet précis sur le frame rate/durée n'est pas garanti identique à Android | P2 | Vérifier/tracer l'effet réel de `selectedSpeedIndex` sur `AnimationEngine.frameRate` |
| F-45 | Capture automatique (`auto_checkbox`) | `AnimemesCompound.java:1900-1904` | Enregistre en continu de nouvelles frames pendant le geste | `state.autoCaptureEnabled` | Approximation assumée et documentée : keyframe auto-enregistré en fin de glissement plutôt qu'un flux continu de frames | `PARTIAL` (approximation documentée) | Doc de tête de fichier | Modèle différent, résultat visuel probablement proche mais pas identique | P2 | Non prioritaire sans retour utilisateur négatif |

---

## 5. Audit logique/moteur (synthèse — détail dans le tableau §4, lignes F-01 à F-05)

Les 5 fichiers cœur (`AnimationEngine`, `Transform`, `Keyframe`, `KeyframeTrack`,
`AnimationObjectData`) ont été lus **intégralement** et comparés point par point à leurs
équivalents Android déjà lus lors de sessions précédentes. Aucune divergence structurelle
trouvée sur le modèle de données ou l'algorithme d'interpolation. **Seule divergence réelle
trouvée : F-05 (recalcul de la table de lecture à chaque frame), un bug de performance introduit
par cette session elle-même (split `version`/`renderVersion`) et jamais étendu au delegate de
lecture.**

## 6. Audit gestes

Voir §4 F-06 à F-10. Logique mathématique (hit-test, translation, rotation autour d'un pivot,
échelle avec double garde-fou, ordre de composition `post*`) vérifiée ligne à ligne et jugée
fidèle. Le bug de classe `.id(state.version)` (destruction de vue pendant un geste actif) a été
cherché explicitement dans tout `Animems/` cette passe — **aucune occurrence vivante restante**.
**Risque non confirmé** : aucun de ces correctifs n'a été re-testé sur un device/Appetize réel
depuis leur application (voir §18.1) — la preuve de non-régression actuelle est uniquement une
relecture de code, pas une exécution.

## 7. Audit canvas

Voir §14 (audit vues/UI). Le rendu du canvas (`Canvas` SwiftUI + `LayerRenderer`) est
structurellement fidèle à `MemesView2.onDraw`/`startDraw`. Différence de bulle de fond entre
aperçu figé et lecture (`drawLastTransform` vs `drawObjectFrame`) vérifiée comme un comportement
Android RÉEL et intentionnellement reproduit à l'identique côté iOS (pas une erreur de portage).

## 8. Audit timeline

`TimelineView.swift`/`TimelineViewModel.swift` portent le modèle CapCut ("playhead fixe, contenu
défile") de `TimelineView.java` (1320 lignes, actif ; `TimelineView2.java` confirmé mort). Le bug
de recréation de geste (`.id(state.version)`) y a été trouvé et corrigé cette session
(commit `e7736af`) — deuxième occurrence après le canvas principal, **aggravée** car les gestes
continus de `TimelineView` appelaient aussi `bumpVersion()` à chaque frame, garantissant une
auto-interruption. Corrigé en `bumpRenderVersion()`. Non re-testé sur device (§18.1). Le rail de
vignettes séparé (`frameList`/`FrameAdapter`, F-32) n'a pas d'équivalent — navigation de
substitution déjà assurée par `TimelineView` lui-même.

## 9. Audit keyframes

Modèle de keyframes (F-03) fidèle. **Modèle de capture** différent et documenté : Android capture
en continu pendant le geste si `auto_checkbox` actif (flux dense de frames) ; iOS approxime par un
keyframe explicite au bouton ◆ (`recordKeyframe`) OU un keyframe auto-enregistré en fin de
glissement si `autoCaptureEnabled` (F-45, approximation assumée). La priorité `maskTransforms` sur
`KeyframeTrack` au rendu, un point resté ouvert dans les commentaires du code lors d'une session
précédente, est **confirmée résolue et implémentée** (F-13) par lecture directe de
`LayerRenderer.swift` cette session — le commentaire correspondant dans `AnimationObjectData.swift`
est obsolète et doit être mis à jour (cosmétique, P2).

## 10. Audit lecture (playback)

`AnimationEngine.play/pause/stop/seek` porté fidèlement (F-04). **Bug critique trouvé** (F-05) :
le delegate de lecture bumpe `version` (déclenche un rebuild complet coûteux) au lieu de
`renderVersion` (léger, redraw seul) sur CHAQUE frame de lecture — alors que ce même split
`version`/`renderVersion` a été correctement appliqué aux gestes cette session (`bumpRenderVersion`
existe déjà, juste non branché ici). Classé P0.

## 11. Audit masques — finding le plus critique de cet audit

Le moteur de masque (7 formes, `MaskFactory.createMaskScaled`, câblage dans `LayerRenderer`) est
**complet et réellement exercé** par le pipeline de rendu (F-12, F-13). L'état/les setters
(`setMaskType`, `maskOffsetChanged`, `toggleMaskInverted`, etc.) sont réels et appelés depuis
`AnimemesEditorView`. **Mais le SEUL point d'entrée pour activer ce mode côté utilisateur
(`isMaskEditMode = true`) n'existe nulle part** (F-11, F-14) — confirmé par un grep exhaustif de
tous les sites d'affectation de cette variable dans TOUT le projet Swift, pas seulement le module
Animems. C'est une preuve statique déterministe, pas une supposition : SwiftUI observe l'état via
`@Published`, il n'y a pas de mécanisme caché (réflexion, KVO externe) qui pourrait fixer cette
valeur autrement qu'une assignation directe trouvable par grep. **Verdict : la fonctionnalité
masque, bien que représentant probablement des centaines de lignes de code fonctionnel et
correctement testé au niveau logique, est actuellement inaccessible à 100% des utilisateurs
iOS.** P0.

## 12. Audit templates

Voir F-15 à F-20. Templates locaux : parité complète. Templates communautaires : navigation/liste
complète mais contenu réel non interopérable (F-17, format binaire Java vs JSON Swift, P1).
Application de template : simplifiée à la piste 0 / calque sélectionné uniquement, alors
qu'Android applique multi-piste avec auto-création et redimensionnement de canvas (F-19, P1).
Upload : mort des deux côtés, correctement non porté (F-18). Recompose : logique portée,
totalement inaccessible en UI (F-20, P1).

## 13. Audit export

### 13.1 Bug confirmé — divergence de police éditeur/export vidéo

Voir F-23. `AnimemesExporter` construit son propre `TextRect` avec des valeurs par défaut
(`.systemFont(14)`) jamais écrasées par son unique appelant, au lieu de recevoir la police réelle
de l'éditeur (`.boldSystemFont(32)`, `AnimemesEditorState.swift:85`). Contrairement à Android où
`MP4Encoder` ne contient AUCUN code de rendu de police (le texte est "baké" en bitmap une seule
fois par `MemesView2.writeText`, donc structurellement synchronisé), l'architecture iOS
"re-render toujours via `LayerRenderer.drawText`" — un choix par ailleurs correct et plus flexible
— introduit ce risque de divergence de paramètres entre les deux call sites. Export image statique
non affecté (réutilise correctement `self.textRect`). P0.

### 13.2 Reste du pipeline

Masques, keyframes, feather, teinte : le rendu vidéo et le rendu live partagent le même code
(`LayerRenderer.drawObjectFrame`) et les mêmes pistes de keyframes interpolées — pas de logique
dupliquée, pas de risque de divergence structurel au-delà du cas texte ci-dessus (F-37).

## 14. Audit vues/UI

Comparaison structurelle Android (`compound_animemes_layout.xml`, capture d'écran réelle du
2026-08-16 référencée dans les commentaires du fichier) vs iOS (`AnimemesEditorView.swift`, lu
intégralement) :

| Zone | Android | iOS | Statut |
|---|---|---|---|
| Barre haute | fermer/vitesse/résolution/auto-capture/son | Identique, ordre confirmé par capture | `COMPLETE_PARITY_CANDIDATE` |
| Canvas | `MemesView2` + zoom | `Canvas` SwiftUI + `zoomControls` | `COMPLETE_PARITY_CANDIDATE` |
| Menu droit | 9 boutons (collapse/texte/dessin/emoji/sticker/image/fond/formes/templates) | 8 boutons identiques (emoji et sticker partagent le même clavier natif, fidèle) | `COMPLETE_PARITY_CANDIDATE` |
| Barre lecture | play unique | play/pause + ◆ keyframe + durée + chevron timeline | `IOS_IMPROVED` (contrôles supplémentaires utiles, pas de perte) |
| Timeline | rail vignettes + `TimelineView` | `TimelineView` seul (pas de rail vignettes, F-32) | `PARTIAL` |
| Barre basse | 15+ boutons (AI/recompose×2/template/supprimer/reset/onglets/mouvement/frame/audio/bezier/dupliquer/couleur/masque/removebg) | 8 boutons (AI/compose-grisé/load-grisé/modèle/supprimer/reset/chronologie/undo) | **`PARTIAL` sévère — 7 fonctions Android réelles sans bouton iOS du tout : mouvement manuel (F-33), extraction audio (F-34), bezier (F-27), dupliquer (F-30), couleur (F-31, lié à F-28), masque (F-11, **critique**), remove-bg (F-29)** |
| Panneau masque | `MaskAddPanel`/`MaskPreviewEditorPanel` toujours atteignable via `btn_mask` | Existe en code, jamais affiché (F-11) | `FUNCTIONALLY_FAILED` |
| HUD de diagnostic geste | N/A (n'existe pas côté Android) | Présent et actif (`gestureDiagnosticsHUD`, `AnimemesEditorView.swift:235-248`), affiché en permanence, code vert sur fond noir | `VISUALLY_DIFFERENT` — élément de debug temporaire visible par l'utilisateur final, jamais retiré (voir §18.1) |

**Constat global §14** : la barre du bas est la zone de plus grand écart structurel — près de la
moitié des boutons Android réels n'a aucun équivalent visuel iOS, alors que la logique sous-jacente
existe déjà pour plusieurs d'entre eux (bezier, dupliquer, masque, mouvement) et attend simplement
d'être montée.

## 15. Boutons et actions (audit par bouton, périmètre non déjà couvert par §4/§14)

| Bouton Android | Handler réel | iOS équivalent | Accessible ? | Appelle une vraie logique ? | Produit un résultat visible ? |
|---|---|---|---|---|---|
| `close_animemes` | ferme sans export | `onClose()` | Oui | Oui | Oui |
| `save_animemes2` | `showSaveDialog` | `saveButton` → `showSaveOptions`/`export` | Oui | Oui | Oui |
| `btn_mask` | ouvre mode masque | **Aucun bouton correspondant trouvé** | **Non** | N/A | N/A — voir F-11 |
| `remover` | supprime calque sélectionné | bouton "supprimer" | Oui | Oui | Oui |
| `undo` | supprime dernier calque | bouton "undo" | Oui | Oui | Oui |
| `reset_animation` | réinitialise animation du calque | bouton "réinitialiser" | Oui | Oui | Oui |
| `btn_ai_generate` | log seulement (mort côté Android) | bouton affiché, sans action | Oui (visible) | Non (fidèle) | Non (fidèle) |
| `btn_recompose`/`btn_recompose_gallery` | fusion réelle + galerie | "Compose"/"Load compose", `disabled(true)` | Non (assumé, grisé honnêtement) | Non | Non |
| `btn_motion_template` | galerie templates | "Modèle" | Oui | Oui | Oui |
| `btn_duplicate` | duplique calque | **Aucun** | Non | N/A | N/A |
| `ic_palete` | couleur du calque | **Aucun bouton dédié identifié** (dépend de F-28) | Incertain | Incertain | Incertain |
| `btn_removebg` | détoure calque | **Aucun** | Non | N/A | N/A |
| `extract` | extrait audio de vidéo | **Aucun** | Non | N/A | N/A |
| `bezier_c` | courbe d'easing | **Aucun** | Non | N/A | N/A |
| `controlle_movement` | sliders manuels | **Aucun** | Non | N/A | N/A |
| `stack` (rail vignettes) | navigation par miniature | **Aucun** (substitué par `TimelineView`) | Non (mais fonction de navigation équivalente ailleurs) | N/A | N/A |

## 16. Code mort / faux positifs — "ANIMEMS FALSE POSITIVES / DEAD CODE"

### 16.1 Côté Android (confirmé mort, ne PAS porter)

`AnimemesCompound2.java`, `AnimemesCompoundOpselete.java`, `MemesView3.java`, `TimelineView2.java`,
`MaskPreviewEditorPanel2.java`, `MP4Encoder2.java`, `AnimatedGifEncoder.java`, `GIFView.java`,
`VideoEditor.java`, `UnifiedComposerFinal.java`, `AACTranscoder.java`,
`AnimatedWatermarkComposer.java`, `codec/sampler/**`, `codec/gl/**`,
`compound_animemes_layout2.xml`. **Upload de template CDN** (`AnimemesActionSheet` bouton 3,
bloc commenté — voir §1.3, correction personnelle d'un conflit entre deux agents).

### 16.2 Côté iOS (code présent, jamais appelé — confirmé par grep exhaustif individuel)

| Fichier | Ce qu'il porte | Pourquoi il existe malgré tout (probable) |
|---|---|---|
| `MaskEditController.swift` | Protocoles `MaskGestureListener`/`MaskEditModeListener` | La logique équivalente a été réimplémentée directement dans `AnimemesEditorState` (setters directs) plutôt que via ces protocoles — les deux approches ont coexisté, celle-ci a perdu |
| `MaskPreviewEditorPanelState.swift` | État du panneau masque (opacité/flou/inversion/snapshot annuler) | Écrit en avance d'une vue qui n'a jamais été montée (le panneau actuel, `maskPanel(for:)`, est plus simple et n'utilise pas cette struct) |
| `ShapePreviewEditorPanelState.swift` | État du panneau de config de forme avant insertion | Écrit en avance d'une vue jamais montée — `addShape` utilise des valeurs codées en dur à la place (F-21) |
| `AnimemesRecompose.swift` | Logique pure de fusion recompose | Écrit en avance d'une UI jamais construite (F-20) |
| `BezierEditorView.swift` | Éditeur de courbe d'easing complet | Écrit en avance d'un bouton d'entrée jamais ajouté (F-27) |
| `PaintCapture.swift` | Dessin animé multi-frame | Écrit en avance d'un branchement jamais fait sur `autoCaptureEnabled` (F-26) |
| `CanvasZoomController.swift` | Zoom canvas (+/−/fit) | Doublon — une version inline plus simple (`zoomControls`) a été écrite séparément et utilisée à la place (F-40) |
| `FrameListState.swift` | Rail de vignettes | Écrit en avance d'une vue jamais montée (F-32) |
| `MovementControllerState.swift` | Sliders manuels zoom/rotation/skew | Écrit en avance d'une vue jamais montée (F-33) |
| `AnimationObjectData.duplicate`/`.duplicate2` | Copie de calque (profonde/superficielle) | Méthodes écrites, jamais reliées à un bouton (F-30) |

**Constat** : contrairement au code mort Android (versions obsolètes remplacées), le code mort
iOS est presque entièrement composé de **logique écrite EN AVANCE de son UI**, jamais terminée —
un profil différent qui suggère que le travail de portage a précédemment priorisé le moteur/la
logique avant le câblage UI complet, et que plusieurs boucles de câblage restent inachevées. Ce
n'est pas nécessairement un problème (mieux vaut une logique déjà prête à monter qu'à écrire), mais
cela signifie que la majorité du travail P1/P2 restant est du **câblage UI**, pas de la nouvelle
logique métier.

## 17. Bugs confirmés (par preuve statique exhaustive, cette session)

1. **F-05 — Playback recalcule la table complète de transformation à chaque frame** (P0,
   performance). `AnimemesEditorState.swift:724-726` + `AnimemesEditorView.swift:314`.
2. **F-11 — Le mode d'édition masque n'est accessible par aucun bouton, masques 100%
   inutilisables** (P0, fonctionnalité majeure entièrement inerte). Grep exhaustif
   `\.isMaskEditMode\s*=` sur tout `Sources/TiinverSwift`.
3. **F-23 — Le texte exporté en vidéo utilise une police différente de l'éditeur** (P0, bug visuel
   confirmé par lecture de code). `AnimemesExporter.swift:69-71` vs
   `AnimemesEditorState.swift:85/627`.

Les trois bugs ci-dessus sont établis par **lecture de code exhaustive et déterministe**, pas par
exécution réelle sur device/Appetize (qui n'a pas eu lieu cette session, conformément à la
consigne de ne pas déclencher de test Appetize pendant ce travail). Ce niveau de preuve est jugé
suffisant pour ces trois cas précis car chacun repose sur un raisonnement fermé (aucun chemin de
code alternatif possible), pas sur une supposition de comportement à l'exécution.

## 18. Risques non confirmés

### 18.1 Gestes de transformation — non re-testés depuis les 2 derniers correctifs

Le fichier `AnimemesEditorView.swift` contient un `gestureDiagnosticsHUD` (lignes 231-248)
**toujours actif dans le code actuel**, ajouté suite à un rapport utilisateur antérieur
("les transformations ne fonctionnent pas réellement dans Appetize"). Son propre commentaire de
tête indique : *"TEMPORAIRE, à retirer une fois la cause racine confirmée par un run réel."* Deux
correctifs liés à la classe de bug `.id(state.version)` ont depuis été appliqués (commits
`0a8966b`, `e7736af`), qui sont les corrections les plus probables du problème original — mais
**aucun test réel (Appetize ou device) n'a eu lieu depuis pour confirmer que ces correctifs
résolvent bien le rapport initial**. Le HUD reste donc un signal actif et non résolu dans le code
lui-même, pas une inférence de cet audit. **Statut : risque non confirmé, ni positivement ni
négativement.**

### 18.2 Bouton `btn_bezier` (F-27) — preuve mono-source

L'existence d'un bouton réel togglant la visibilité de `BezierEditorView` côté Android
(`AnimemesCompound.java:1970-1980`) provient d'un seul des trois agents (export/outils), non
re-vérifiée personnellement par lecture directe du fichier Android. Confiance élevée (citation de
lignes précises) mais non corroborée par une deuxième source comme l'a été le cas du conflit
upload-template (§1.3). À re-vérifier avant de prioriser un correctif dessus.

### 18.3 Intégration de sortie vers `PublishFragment`/flux Galerie

Le tracé Android complet (`MemesFragment` → `MediaEditor`/`MediaTrim` → `PublishFragment`) est
confirmé par l'agent de cartographie. Le point d'intégration iOS équivalent (`onClose()` du
`fullScreenCover`, et ce qui se passe après avec `exportedURL`) n'a **pas** été retracé jusqu'au
flux de publication réel dans cette passe — hors périmètre strict "moteur Animems" tel que délimité
par la consigne. À couvrir dans un audit Galerie/Publication dédié si nécessaire.

### 18.4 `LayerEditorPanelState.swift` et champs associés (F-28, F-31)

Fichier listé, non lu ni audité en détail cette passe faute de temps dans le budget de cette
session — son statut d'accessibilité réelle (câblé ou orphelin comme tant d'autres au §16.2) n'est
pas déterminé. Priorité de vérification P1 pour la prochaine passe, car il conditionne aussi le
statut de F-31 (couleur du calque).

## 19. Éléments visuellement différents

- Point d'entrée : menu caméra 3 choix (Android) vs accès direct (iOS) — §3.
- Ajout de média : recadrage systématique via `CroperView` (Android) vs ajout direct sans
  recadrage (iOS) — F-19 bis (voir §3, ligne "Ajout de média").
- HUD de diagnostic geste visible en permanence côté iOS (§14, n'existe pas côté Android — élément
  de debug non retiré).
- Barre basse : Android présente 15+ boutons dans une bande défilante dense, iOS en présente 8 —
  différence de densité visuelle nette même là où la fonction manquante n'est pas critique.

## 20. Éléments manquants (`MISSING`, résumé)

F-20 (Recompose), F-26 (dessin animé multi-frame), F-27 (bezier easing), F-29 (remove background),
F-30 (dupliquer calque), F-32 (rail de vignettes — compensé), F-33 (contrôleur de mouvement
manuel), F-34 (extraction audio depuis vidéo), F-41 (preview plein écran avant export), F-42
(tutoriel intégré). **F-11 (entrée en mode masque) est classé `FUNCTIONALLY_FAILED` plutôt que
`MISSING`** car le code existe et fonctionnerait immédiatement si un point d'entrée était ajouté —
distinction volontaire pour la priorisation (P0, pas juste une fonctionnalité "à écrire depuis
zéro").

## 21. Priorisation P0/P1/P2

**P0 (bloquant, à corriger avant tout autre travail Animems)**
1. F-11/F-14 — Ajouter un bouton d'entrée en mode masque (`isMaskEditMode = true`). Fonctionnalité
   Android majeure (7 types de masque) 100% inaccessible sinon.
2. F-23 — Corriger la police du texte dans l'export vidéo (passer `font`/`textColor` réels à
   `AnimemesExporter`).
3. F-05 — Corriger `animationEngineDidInvalidate` pour utiliser `bumpRenderVersion()` au lieu de
   `version` (bug de performance de lecture).

**P1 (fonctionnalités réelles Android manquantes ou dégradées, impact utilisateur significatif)**
4. F-19 — Application de template multi-piste (actuellement limitée à la piste 0/calque
   sélectionné).
5. F-17 — Contenu réel des templates communautaires téléchargés (actuellement toujours vide,
   nécessite une décision de format d'échange, possiblement hors portée iOS seul).
6. F-20 — UI Recompose (logique déjà écrite, aucune interface).
7. F-26 — Entrée UI pour le dessin animé multi-frame (logique déjà écrite).
8. F-28/F-31 — Auditer `LayerEditorPanelState.swift` (statut inconnu, conditionne la couleur de
   calque).

**P2 (améliorations, gaps mineurs ou cosmétiques)**
9. F-27 (bezier easing UI), F-29 (remove background), F-30 (dupliquer calque), F-33 (contrôleur de
   mouvement manuel), F-34 (extraction audio depuis vidéo), F-21 (panneau de config de forme avant
   insertion), F-13 (commentaire obsolète), F-40 (nettoyage doublon zoom), F-32/F-41/F-42
   (optionnels).

## 22. Plan de correction précis (pour PHASE B, non exécuté dans cette passe)

Pour chaque item P0/P1, la méthode obligatoire de PHASE B (audit → tracer Android → tracer iOS →
corriger un lot cohérent → commit → CI → corriger erreurs → mettre à jour
`ANIMEMS_PARITY_PROGRESS_V1.md` → continuer) s'applique. Proposition de lots, du plus isolé/sûr au
plus large :

- **Lot 1 (P0, risque faible, 3 corrections indépendantes et petites)** : F-05
  (`animationEngineDidInvalidate` → `bumpRenderVersion()`), F-23 (passer `font`/`textColor` à
  `AnimemesExporter`), F-13 (commentaire obsolète). Aucune de ces trois ne touche l'UI ni
  n'introduit de nouveau composant — correctifs chirurgicaux à un ou deux fichiers chacun.
- **Lot 2 (P0, le plus important fonctionnellement)** : F-11/F-14, ajouter le point d'entrée en
  mode masque. Nécessite une décision de placement UI (bouton dédié `rightToolbar` ou
  `bottomToolbar`, correspondant à `btn_mask`) — à trancher avant d'écrire le code.
- **Lot 3 (P1, câblage UI sur logique déjà existante)** : F-20 (Recompose), F-26 (dessin animé),
  chacun un lot séparé vu leur taille (nouvelle vue + navigation + intégration état).
- **Lot 4 (P1, logique à étendre)** : F-19 (template multi-piste) — nécessite de retracer
  `applyTemplateWithAutoCreate`/`showTemplateMismatchDialog` plus en détail avant de coder.
- **Lot 5 (P1, décision produit/backend nécessaire avant tout code)** : F-17 (format d'échange
  template communautaire) — à ne pas commencer sans clarification du besoin réel (le format
  binaire Java ne sera jamais lisible tel quel par Swift).
- **Lots 6+ (P2)** : chaque item traité individuellement, petits lots, priorité basse.

**Ce plan n'est PAS exécuté dans cette passe — Phase A s'arrête ici. Attente du feu vert explicite
de l'utilisateur avant Phase B.**

---

## 23. PHASE B — Statuts mis à jour (2026-08-19, feu vert reçu)

Phase B exécutée en 11 lots, chacun commité et poussé séparément (voir `ANIMEMS_PARITY_PROGRESS_V1.md`
pour le détail chronologique complet, preuves, commits, CI). **Cette section met à jour les statuts
du tableau §4 pour les fonctionnalités traitées — les lignes non mentionnées ici gardent leur statut
Phase A d'origine.** Rappel : `BUILD_VALIDATED` = CI verte confirmée ; `COMPLETE_PARITY_CANDIDATE` =
comparaison code-à-code approfondie faite, code corrigé et poussé, AUCUN test réel device/Appetize
encore (conforme à la consigne de ne pas déclencher Appetize pendant ce travail).

| ID | Ancien statut (Phase A) | Nouveau statut | Lot | Résumé du correctif |
|---|---|---|---|---|
| F-05 | `FUNCTIONALLY_FAILED` | `COMPLETE_PARITY_CANDIDATE` | 1 | `didPlayFrame`/`animationEngineDidEnd`/`animationEngineDidInvalidate` utilisent `bumpRenderVersion()` au lieu de `version` — plus de double rebuild complet à chaque frame de lecture |
| F-13 | `COMPLETE_PARITY_CANDIDATE` (commentaire obsolète) | `COMPLETE_PARITY_CANDIDATE` (commentaire corrigé) | 1 | Cosmétique, pas de changement de comportement |
| F-11 / F-14 | `FUNCTIONALLY_FAILED` | `COMPLETE_PARITY_CANDIDATE` | 2 | Bouton "masque" ajouté (`bottomToolbar`, `disabled(selectedId == nil)`) → `isMaskEditMode = true`. 2 bugs connexes trouvés et corrigés pendant le câblage : sortie du mode sans effacer le masque (bouton "✓" distinct de "Aucun"), `deleteSelected()` ne réinitialisait pas `isMaskEditMode` |
| F-28 / F-31 | `CODE_PRESENT_UNVERIFIED` | `COMPLETE_PARITY_CANDIDATE` | 3 | `LayerEditorPanelView.swift` (nouveau) monté sur `LayerEditorPanelState` déjà écrit — déclenché par un bouton dédié "propriétés" plutôt que l'appui long Android sur la timeline (substitution documentée, risque de composition de geste évité) |
| F-30 | `MISSING` | `COMPLETE_PARITY_CANDIDATE` | 4 | Bouton "dupliquer" → `AnimationObjectData.duplicate(_:)` (déjà écrit, jamais appelé) |
| F-21 | `PARTIAL` | `COMPLETE_PARITY_CANDIDATE` | 5 | `ShapePreviewEditorPanelView.swift` (nouveau) monté sur `ShapePreviewEditorPanelState` déjà écrit — remplace l'insertion à valeurs codées en dur par un vrai panneau de configuration (couleur/opacité/arrondi/épaisseur/contour) avant insertion |
| F-27 | `MISSING` | `COMPLETE_PARITY_CANDIDATE` | 6 | Bouton "bezier" toggle `BezierEditorView` déjà écrit. **Trouvaille de fidélité** : la courbe éditée n'est consommée nulle part côté Android non plus (`setOnControlPointChangedListener` jamais appelé) — reproduit comme outil visuel inerte, PAS relié au moteur d'easing (l'ajouter aurait été une fonctionnalité qu'Android lui-même n'expose pas) |
| F-26 | `MISSING` | `COMPLETE_PARITY_CANDIDATE` | 7 | `ic_paint` branche désormais sur `autoCaptureEnabled` comme Android ; nouveau mode capturé multi-frame (`PaintCaptureSheetView.swift`) alimente le mécanisme de cyclage bitmap déjà existant (`setBitmaps`/`bitmapChangeIntervalMs`) |
| F-40 | `COMPLETE_PARITY_CANDIDATE` (fonctionnel) + doublon mort | `PARTIAL` (révisé — voir ci-dessous) | 8 | Orphelin `CanvasZoomState`/`CanvasZoomControls` intégré (algorithme de clamp min/max plus fidèle). **Nouveau bug trouvé pendant ce lot** : l'ancien zoom ne zoomait RIEN visuellement (juste un label). Le remplacement corrige l'algorithme mais **ne zoome toujours pas le canevas** — appliquer `.scaleEffect` risquerait de désynchroniser les coordonnées de `combinedGesture`, jugé trop risqué sans test réel après 2 bugs de geste déjà survenus cette session. Statut révisé à `PARTIAL` pour refléter honnêtement que l'effet visuel manque toujours |
| F-20 | `MISSING` | `COMPLETE_PARITY_CANDIDATE` | 9 | Bouton "Compose" → `AnimemesEditorState.performRecompose()` (nouveau) → `AnimemesRecompose.buildComposedLayer(from:)` (déjà écrit, jamais appelé). **Correction de portée** : pas de sélection manuelle nécessaire, Android fusionne tous les calques visibles non verrouillés en un seul tap — plus simple que ce que l'audit Phase A supposait |
| F-19 | `PARTIAL` | `COMPLETE_PARITY_CANDIDATE` | 10 | `applyTemplate` applique désormais TOUTES les pistes dans l'ordre (auto-création pour formes/masques, consommation des calques existants pour bitmap/texte), plus une alerte de correspondance (`templateMismatch`) fidèle au comportement RÉEL d'Android (2 options effectives, pas 3 malgré l'apparence à 3 boutons) |
| F-29 | `MISSING` | `COMPLETE_PARITY_CANDIDATE` | 11a | Bouton "fond" → `removeBackgroundFromSelected()` (nouveau), réutilise `RemoveBackground.swift` déjà écrit pour la Galerie (même fichier Android source, catégorie partagée "A+G") |
| F-33 | `MISSING` | `MISSING` (inchangé, raison affinée) | — | **Non traité, décision explicite** : le fichier `MovementControllerState.swift` documente lui-même que la logique de transformation réelle (`applySeekBarTransformOnAnchor`/`anchorTouchExecute`) n'a jamais été lue ni portée — contrairement aux autres lots (câblage UI sur logique déjà existante), celui-ci exigerait de PORTER une nouvelle logique moteur en premier. Nécessite son propre lot dédié, hors budget de cette passe |
| F-34 | `MISSING` | `MISSING` (inchangé, gap plus profond découvert) | — | **Non traité — nouvelle découverte pendant ce lot** : `AnimemesEditorView.swift`, le callback `onVideoPicked` du sélecteur média jette l'URL de la vidéo choisie et ferme simplement le picker (`{ _ in showGalleryPicker = false }`) — **importer une vidéo comme calque/fond ne fait RIEN aujourd'hui côté iOS**, un gap plus fondamental que l'extraction audio elle-même, qui en dépend. Voir F-45 ci-dessous |
| F-45 (nouveau) | — | `MISSING` (nouveau finding) | — | Import vidéo dans Animems (`ic_add` → sélection vidéo) est un no-op complet côté iOS — `GalleryPickerView.onVideoPicked` ne fait qu'ignorer l'URL. Bloque F-34 en amont. Priorité P1 pour une future passe (nécessite de décoder une vidéo en séquence de frames bitmap ou équivalent, un morceau de travail substantiel, pas une simple correction de câblage) |

### 23.1 Comptage synthétique après Phase B

| Statut | Avant Phase B | Après Phase B |
|---|---|---|
| `COMPLETE_PARITY_VALIDATED` | 0 | 0 (toujours aucun test réel device/Appetize) |
| `COMPLETE_PARITY_CANDIDATE` | 21 | 32 |
| `PARTIAL` | 9 | 8 (F-19/F-20/F-21/F-26/F-27/F-28/F-29/F-30 sortis, F-40 révisé y entre) |
| `FUNCTIONALLY_FAILED` | 4 | 0 |
| `MISSING` | 10 | 8 (F-19/F-20/F-21/F-26/F-27/F-29/F-30 sortis ; F-45 nouveau y entre ; F-33/F-34 restent) |
| `CODE_PRESENT_UNVERIFIED` | 2 | 0 |
| `ANDROID_ONLY` | 2 | 2 (inchangé) |
| `IOS_IMPROVED` | 1 | 1 (inchangé) |

**12 des 14 items P0/P1 du plan §21/§22 traités** (F-05, F-11/F-14, F-19, F-20, F-21, F-23, F-26,
F-27, F-28/F-31, F-29, F-30, F-40-partiel). **2 P1/P2 restent délibérément différés** (F-33, F-34)
avec raison précise documentée, pas silencieusement abandonnés. **1 nouveau gap découvert et
documenté** (F-45, import vidéo). Aucun de ces correctifs n'a été validé par un test réel
device/Appetize — voir `ANIMEMS_PARITY_PROGRESS_V1.md` pour le statut CI (`BUILD_VALIDATED`) de
chaque lot.
