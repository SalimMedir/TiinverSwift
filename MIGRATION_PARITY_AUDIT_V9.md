# MIGRATION PARITY AUDIT V9 — Création/Publication + Téléchargement de médias

**Phase** : AUDIT UNIQUEMENT — aucune correction de code appliquée pendant ce cycle, conformément à
la consigne explicite. Toutes les corrections listées ci-dessous sont des recommandations pour une
Phase B ultérieure.

**Date** : 2026-09-02. **Méthodologie** : 6 agents de recherche (`general-purpose`, lecture
intégrale des fichiers, aucune modification) lancés en parallèle sur 6 tranches du périmètre, plus
2 investigations manuelles complémentaires (session principale) sur les deux points critiques
signalés par l'utilisateur en cours d'audit. Android (`C:\Users\helen\AndroidStudioProjects\tiinver`)
est la référence fonctionnelle ; iOS (`C:\Users\helen\iOSProjects\TiinverSwift`) est le portage
audité. 3 agents ont dû être relancés après des erreurs réseau infrastructurelles (perte de
connexion serveur, pas un problème de contenu) — tous ont fini par aboutir.

**Principe directeur explicite de l'utilisateur, respecté tout au long de cet audit** : privilégier
le code réel sur toute documentation/audit antérieur en cas de contradiction. Deux contradictions
réelles avec la documentation existante ont été trouvées et corrigées dans ce document (voir
§4.2 et le tableau de synthèse) — la doc iOS antérieure affirmait à tort qu'Android ne fait jamais
passer une vidéo Animems par `MediaTrim`.

**⚠️ MISE À JOUR (2026-09-02, contre-audit adversarial des 5 P1)** : les 5 findings `P1` ci-dessous
ont été soumis à une seconde passe de validation volontairement sceptique, pour distinguer les
vrais bugs des décisions produit et des différences UX acceptables — **voir §9 pour le détail complet
et §10 pour la synthèse actionnable**. Résultat : sur 5 `P1` initiaux, seul 1 reste un
`CONFIRMED BUG` net (portée revue à la baisse), 1 est reclassé `FALSE POSITIVE` (le risque
identifié est en réalité partagé à l'identique par Android — pas un écart de portage), 2 sont
`PRODUCT DECISION REQUIRED` (aucun comportement Android unique à copier, le choix appartient au
produit), et 1 reste `❓` non tranchable sans test sur device réel. **Les priorités et libellés du
§5/§6 originaux ci-dessous sont conservés tels quels pour la traçabilité historique — §9/§10 font
foi pour la décision de correction.**

---

## 1. Résumé exécutif

**Niveau global de parité** : **élevé**. Sur les ~90 comparaisons ponctuelles effectuées à travers
les deux pipelines, l'écrasante majorité (~65) sont `✅ Conforme`. Aucun défaut `P0` (bloquant)
n'a été trouvé — les deux pipelines fonctionnent bout en bout sur les deux plateformes pour le cas
nominal. Les écarts réels se concentrent sur trois zones : (1) l'absence totale, côté iOS, du
mécanisme de branding promotionnel (filigrane + outro) qu'Android applique systématiquement à la
vidéo non-premium, sur DEUX points d'entrée distincts (Partage ET **Téléchargement depuis le
Feed**, ce second point n'étant documenté nulle part avant cet audit) ; (2) l'absence de tout
retour visuel (aperçu, seek, rotation, flip en direct) pendant l'édition `MediaTrim` ; (3) l'absence
de confirmation de succès après un téléchargement réussi.

- **P0 (bloquant)** : 0
- **P1 (critique)** : 5 (dont 2 marquées `❓ à vérifier` — priorité conditionnelle à une confirmation
  device/simulateur réel, actuellement indisponible dans cet environnement)
- **P2 (important)** : 3 (dont 1 `❓`)
- **P3 (mineur)** : 18

Un fait important pour la suite : **`ProTimelineViewModel.swift` est un port fidèle et complet
d'`ProTimelineView.java` (fenêtre de zoom, bornes en ms absolues, playhead) déjà écrit dans le
dépôt iOS mais jamais câblé à aucune vue** — plusieurs écarts `MediaTrim` (§V9-F-016, V9-F-017)
seraient déjà résolus si ce code existant était simplement utilisé au lieu d'être dupliqué de façon
approximative.

---

## 2. Pipeline création/publication

```text
Galerie ──┐
Animemes ─┼──► MediaTrim (vidéo uniquement) ──► MediasDisplay ──► PublishFragment ──► Poster ──► Upload ──► Publication
Caméra ───┘        (Galerie + Animemes            (musique/          (légende,        (URL          (BunnyCDN    (POST
                     sur Android ; les 3            voix off)         catégorie,       construite    Storage/     activity/add)
                     sur iOS, cf. §4.1)                               partage)         client, pas   Video Lib)
                                                                                        d'upload
                                                                                        séparé)
```

**Verdict global : le pipeline est réellement équivalent entre Android et iOS**, avec deux nuances
notables et assumées : (a) iOS fait désormais passer les vidéos Caméra par `MediaTrim` — une
authentique divergence produit pour la Caméra (Android ne le fait jamais), mais en réalité une
**correction de fidélité** pour Animemes (Android le fait aussi, contrairement à ce que la
documentation antérieure affirmait — voir §4.1) ; (b) le filigrane/outro promotionnel du bouton
Partager (chemin non-premium Android) n'a pas d'équivalent iOS, mais ceci n'affecte JAMAIS le
chemin Publication proprement dit sur Android (vérifié par traçage direct des appelants), donc la
Publication elle-même reste pleinement équivalente.

---

## 3. Pipeline téléchargement

```text
Feed (grille Home, FeedFragment.java / FeedView.swift)
  ↓
Post média (photo ou vidéo)
  ↓
Fullscreen (FeedDetailPagerView)
  ↓
"..." → menu d'actions (Copier le lien / Ne plus suivre / Bloquer / Signaler / Télécharger)
        [PAS de "Partager" dans ce menu précis — bouton dédié séparé, hors bottom-sheet]
  ↓
Télécharger
  ↓
Photo : sonde qualité inexistante, URL directe                Vidéo : sonde 720p→480p→360p→brut
  ↓                                                              ↓
Téléchargement (Referer: https://tiinver.com, identique)
  ↓
[VIDÉO SEULEMENT, Android] ── ExportWorker (filigrane + outro si !premium) ──► fichier final réécrit
  ↓                                                                                    ↓
Enregistrement : Downloads/tiinver/ (Android, DownloadManager)      Photos (iOS, PHPhotoLibrary.addOnly)
                  OU Movies/Tiinver/Animemes/ (Android, si watermarké)
  ↓
Confirmation utilisateur : Toast "Download completed" (Android) — ABSENTE côté iOS
```

**Verdict global : le mécanisme de téléchargement lui-même (sonde qualité, Referer, permission,
sauvegarde) est fidèlement reproduit et fonctionnel des deux côtés pour le cas nominal.** Deux
écarts substantiels : l'absence totale du filigrane/outro post-téléchargement côté iOS (P1,
découverte majeure de cet audit, voir §4.2), et l'absence de toute confirmation de succès (P2).

---

## 4. Comparaison détaillée Android ↔ iOS

### 4.1 Chaîne Animemes vidéo — investigation demandée par l'utilisateur, CORRECTION d'une doc antérieure

**Chaîne Android tracée intégralement, ligne par ligne** :

1. `editor/memes/MemesFragment.java:334-338` (`bundleDeliver`) : `pos == RESULT_VIDEO` →
   `mFragmentListener.onArticleSelected(10, bundle)`.
2. `editor/CameraActivity.java:196-200` : `case 10` → ouvre un nouveau `MediaTrim` avec les
   arguments reçus (`openFragment(mediaTrim, true)`).
3. `editor/MediaTrim.java:180-206` (`Callback.onVideo`) : à la fin du trim (réel ou no-op),
   construit un `Bundle b` portant `type`, `path`, `contentType`, `style`, `template_id` (repris
   tels quels depuis les arguments d'entrée, lignes 146-152), et `detail` (avec l'URI mise à jour
   si `isTrimmed`), puis `mListener.onArticleSelected(7, b)`.
4. `editor/CameraActivity.java:180-184` : `case 7` → ouvre `MediasDisplay` avec ce bundle.
5. `editor/MediasDisplay.java:169-171` : `isAnimemes = inputOutputPath != null &&
   inputOutputPath.contains("ANIMEMES")`.

**Conclusion sans ambiguïté : Android fait bien passer une vidéo Animemes par `MediaTrim` avant
`MediasDisplay`**, exactement comme la Galerie (même `case 10`). Seule la **Caméra** saute
directement à `MediasDisplay` (`case 7` direct, confirmé indépendamment par l'agent Galerie/Caméra
via `BaseCameraFragment.java:429-442`).

**La documentation iOS antérieure** (commentaire de tête de `pendingMediasDisplayURL` dans
`FeedView.swift`, daté du 2026-09-01, et le commentaire de `AnimemesEditorView.swift` daté du
2026-09-02 qualifiant le routage Animemes→MediaTrim de « écart produit délibéré... PAS une
fidélité Android ») **est FACTUELLEMENT INEXACTE pour le cas Animemes** — c'est établi par cet
audit comme une découverte à corriger dans le code (documentation seulement, voir V9-F-015). Pour
la **Caméra**, en revanche, la documentation reste exacte : c'est une réelle divergence produit
assumée (Android ne fait jamais passer une vidéo caméra par `MediaTrim`).

**Détail supplémentaire découvert en creusant** : après un vrai trim (pas un no-op), le fichier de
sortie Android est nommé `VIDEO_<timestamp>.mp4` (`Utils.createPublicVideoFile`), **PAS**
`ANIMEMES_<timestamp>.mp4` — ce qui signifie que `isAnimemes` (détection par correspondance de
sous-chaîne sur le nom de fichier) **repasse à `false` du côté Android lui-même** dès qu'un trim
réel a eu lieu, y compris pour une vidéo réellement issue d'Animemes. Impact vérifié : `isAnimemes`
ne pilote qu'un préfixe de nom de fichier temporaire pendant la fusion musique/voix off
(`MediasDisplay.startMerge`, ligne 462) — **jamais** les métadonnées `content_type`/`style`/
`template_id` réellement envoyées au serveur, qui transitent par des champs de `Bundle` séparés et
donc insensibles à cette fragilité. Aucune action corrective nécessaire sur ce point précis (bug
Android mineur et sans conséquence, pas un écart de portage).

**iOS actuel** (`AnimemesEditorView.swift:375-411`, `FeedView.swift:251-267,301-315`) : les 3
sources (Caméra, Galerie, Animemes) passent désormais toutes par `MediaTrimView` avant
`MediasDisplayView`. Pour Animemes et Galerie, **c'est la fidélité réelle à Android** (pas une
divergence). Pour la Caméra, **c'est une divergence produit assumée** (déjà correctement demandée
explicitement par l'utilisateur dans cette même session, avant le lancement de cet audit V9).

---

### 4.2 Pipeline filigrane + outro déclenché par le téléchargement — investigation demandée par l'utilisateur

**Chaîne Android tracée intégralement, méthode par méthode** :

1. **Déclencheur** — `service/broadcast/DownloadReceiver.java:64` (`onReceive`, sur
   `DownloadManager.ACTION_DOWNLOAD_COMPLETE`) :
   ```java
   if (origin != null && origin.equals("feed") && object.equals("videos")) {
       // enfile ExportWorker
   }
   ```
   `origin`/`object` sont des préférences posées explicitement au moment du lancement du
   téléchargement (`FeedFragment.downloadFile()`). **Gate exacte et unique : uniquement les vidéos
   (`object.equals("videos")`) téléchargées depuis le Feed (`origin.equals("feed")`) — une photo ne
   déclenche JAMAIS ce mécanisme**, quelle que soit son origine (confirmé : aucun chemin
   n'enfile `ExportWorker` pour `object.equals("photos")`).
2. **Enfilement** — `WorkManager.enqueueUniqueWork("download_export_video_work",
   ExistingWorkPolicy.REPLACE, exportWork)` (lignes 72-82).
3. **Vérification premium** — `service/worker/ExportWorker.java:118`, dans `doWork()` :
   ```java
   boolean hasPremium = Settings.getBooleanPreference(getApplicationContext(), PROGRAM_PREMIUM, false);
   if (hasPremium) { /* no-op, le fichier brut téléchargé par DownloadManager reste tel quel */ }
   else { export(getApplicationContext(), username, videoUri); }
   ```
4. **Génération de l'outro** — `ExportWorker.export()`, lignes 212-227 : configure `OutroConfig cfg`
   (`durationSec=4`, `username`, `message = R.string.connect_grow_and_monetize`,
   `logoResId = R.mipmap.ic_logo`), puis `encoder.setOutroConfig(cfg);
   encoder.setOutputFilePath(outroPath); encoder.startOutreVideoEncode()` —
   `encoder` = `com.animems.engine.android.codec.MP4Encoder`. **C'est ici, précisément, que le clip
   outro de 4 secondes est encodé.**
5. **Application du filigrane + composition finale** — dans le callback
   `Encoder.EncodeFinishListener.onEncodeFinished()` (lignes 229-343) : construit un
   `OverlayView` avec le nom d'utilisateur, le rend en `Bitmap introLogo`, puis :
   ```java
   AnimatedWatermarkComposer watermark = new AnimatedWatermarkComposer();
   // 3 MotionKeyframe : t=0/2000/4000 ms — jeu de valeurs DISTINCT de celui de
   // l'export Animemes natif (ExportVideoService.java, 5 keyframes différents),
   // codé en dur séparément ici (lignes 254-256)
   watermark.setLogoBitmap(introLogo);
   watermark.setKeyframes(keys);
   UnifiedComposerFinal.compose(context, introLogo, mainPath, outroVideo, outputFinal, watermark, listener);
   ```
   **C'est ici, précisément, que le filigrane animé est composité sur la vidéo ET que l'outro est
   concaténé** — les deux dans le même appel `UnifiedComposerFinal.compose(...)`, la même classe
   utilisée pour l'export Animemes natif, mais avec sa propre configuration de keyframes.
6. **Nettoyage** — dans `onCompleted(String outputPath)` (lignes 275-309) : supprime le fichier
   brut originellement téléchargé (`mainPath`, celui produit par `DownloadManager`), le fichier
   composé intermédiaire (`f`, avant remux), et le clip outro intermédiaire (`foutroVideo`) — ne
   conserve QUE le résultat final remuxé.
7. **Fichier final réellement sauvegardé** — `remuxFastStart(f)` (lignes 347-376) écrit via
   `Utils.createPublicFileScannable()` (`engine/.../Utils/Utils.java:243-256`) dans
   **`Environment.DIRECTORY_MOVIES + "/Tiinver/Animemes"`** (répertoire PUBLIC), puis
   `MediaScannerConnection.scanFile(...)` le rend visible dans la Galerie système.

**Réponses précises aux 6 questions posées** :
- *Où le filigrane est appliqué* : dans `UnifiedComposerFinal.compose(...)`, appelé depuis
  `ExportWorker.export()`'s `onEncodeFinished` callback (étape 5 ci-dessus).
- *Où l'outro est ajoutée* : encodée séparément par `MP4Encoder.startOutreVideoEncode()` (étape 4),
  puis concaténée dans le MÊME appel `UnifiedComposerFinal.compose(...)` (étape 5).
- *Dans quels cas* : uniquement une vidéo (jamais une photo), téléchargée depuis le Feed
  spécifiquement (`origin=="feed"`), pour un utilisateur non-premium.
- *Comment Android distingue photo/vidéo* : la préférence `object` posée au lancement du
  téléchargement (`"videos"` vs `"photos"`), testée dans `DownloadReceiver.onReceive` (étape 1) —
  une photo ne fait jamais exister ce chemin de code.
- *Dépendance au statut premium* : oui, vérifiée explicitement (`PROGRAM_PREMIUM`,
  `ExportWorker.doWork()`, étape 3) — un utilisateur premium reçoit le fichier brut inchangé.
- *Fichier final réellement sauvegardé* : PAS le MP4 brut du CDN — une version reconstituée
  filigranée+outro, dans `Movies/Tiinver/Animemes/` (étape 7), le fichier brut étant activement
  effacé (étape 6). Seul un compte premium échappe à cette reconstitution.

**Pourquoi/où iOS ne reproduit pas ce comportement** : `Sources/TiinverSwift/Feed/
FeedMediaDownloader.swift` (fichier entier lu) ne contient AUCUNE trace de "watermark"/"outro"/
"premium"/"PROGRAM_PREMIUM" — grep exhaustif confirmé négatif. Aucun concept de statut premium
n'existe nulle part ailleurs dans le portage iOS non plus (déjà établi indépendamment pour le
bouton Partager de `PublishComposeView`/`AnimemesEditorView`, voir V9-F-005). Ce point précis
(déclenchement par le TÉLÉCHARGEMENT depuis le Feed, distinct du Partage) n'était **documenté
nulle part** avant cet audit — c'est une découverte, pas une décision produit déjà actée pour ce
point d'entrée spécifique.

**Verdict** : ⚠️ Partiellement conforme — fonctionnellement le fichier téléchargé reste utilisable
des deux côtés, mais le résultat métier diverge fortement pour un utilisateur non-premium (majorité
des utilisateurs Android réels). Voir V9-F-001.

---

### 4.3 Synthèse par domaine (issue des 6 rapports de recherche + investigations complémentaires)

| Domaine | Constat |
|---|---|
| **Galerie** | `PHPickerViewController` (iOS) ≡ `PickVisualMedia` système (Android, chemin réellement actif sur API ≥ 30) — aucune permission requise des deux côtés, sélection unique des deux côtés, gestion d'erreur iCloud/asset manquant ajoutée côté iOS sans équivalent Android nécessaire. ✅ Conforme dans l'ensemble. |
| **Caméra** | Codec/résolution/bitrate/FPS H.264+AAC recopiés à l'identique (y compris `KEY_I_FRAME_INTERVAL=3`), seuil tap/appui-long identique (1000ms), durée max identique (20s), perte de focus gérée des deux côtés. Écarts mineurs : timing permission micro (V9-F-009), flash fonctionnel iOS vs mort Android (V9-F-010, amélioration assumée). **Réserve globale** : aucune partie du pipeline caméra iOS n'a été compilée/exécutée à ce jour (contrainte Windows sans Xcode) — tous les verdicts reposent sur une relecture de code, pas un test runtime. |
| **Animemes** | Contenu produit (image JPEG q.7-0.7 vs MP4 H.264/AAC 30fps), emplacement fichier, métadonnées `content_type`/`style`/`template_id` (y compris la règle fine "jamais de template_id sur une image") : tous ✅ Conforme, vérifiés champ par champ. Chaîne de routage CORRIGÉE en doc (§4.1). Seul écart réel : filigrane/outro absent sur le bouton Partager Animemes (V9-F-005, regroupé avec Publish). |
| **MediaTrim** | Durée max (60000ms), reclamp bi-directionnel des poignées, ratios de recadrage (6 préréglages), recadrage interactif déplaçable, arrondi pair du render size, synchro audio/vidéo, blocage sur échec réel : tous ✅ Conforme. Écart majeur : **aucun retour visuel pendant l'édition** (V9-F-003, P1) — ni seek synchronisé, ni bouclage dans la sélection, ni prévisualisation de la rotation/du flip, alors qu'Android anime le lecteur en temps réel sur les 4 points. Écart informationnel : `ProTimelineViewModel.swift`, port fidèle et complet, existe mais n'est jamais câblé (V9-F-016/017). |
| **MediasDisplay** | Un seul média à la fois des deux côtés (le test "plusieurs médias" ne s'applique à AUCUNE plateforme sur cet écran précis — pas un écart iOS). Fusion audio réelle (pas un remplacement, bouclage de la piste courte) reproduite fidèlement via `AVMutableComposition`/`AVMutableAudioMix`. Écart notable : bibliothèque de sons propriétaire Android vs sélecteur système iOS (V9-F-006, P2). |
| **PublishFragment** | Miniature 110×150 (câblage vérifié à jour, pas seulement documenté), limite légende 80 caractères identique, extraction hashtags identique, gate de catégorie fonctionnellement équivalent (avec nuance de robustesse, V9-F-013), champ `consentAi` identique. Écart notable : filigrane/outro du bouton Partager absent (V9-F-005). |
| **Poster** | **Équivalence quasi littérale confirmée** : sur AUCUNE des deux plateformes le poster n'est un fichier généré/uploadé par le client — c'est une fonctionnalité serveur BunnyCDN (thumbnail auto-généré), les deux clients construisent la MÊME chaîne `{guid}/thumbnail.jpg` côté client, transmise dans le même champ `cdn_thumbnail_url` du même appel `activity/add`. ✅ Conforme, aucune correction nécessaire. |
| **Upload (média + réseau)** | Vérifié caractère pour caractère : URLs, clés `AccessKey` (2 clés BunnyCDN distinctes, jamais confondues), Content-Type (y compris l'absence délibérée sur la PUT vidéo), traitement de réponse (statut HTTP seul pour les uploads CDN). ✅ Conforme. |
| **Publication API** | `POST activity/add` comparé champ par champ (17 champs top-niveau + 14 champs `metadata` imbriqués) : ✅ Conforme quasi intégralement, y compris la logique d'omission des clés `null` (`JSONObject`). Écarts mineurs : 1 champ extra côté iOS (V9-F-023), progression photo absente (V9-F-024), origine de `width`/`height` côté Android non tracée dans le périmètre des 3 fichiers assignés (V9-F-008). **Point clé vérifié explicitement demandé par l'audit** : ni Android ni iOS ne traitent un simple 200 HTTP comme un succès — les deux vérifient un champ `error`/`isBackendSuccess` au niveau du corps de la réponse. Aucun risque de faux succès identifié. |
| **Feed → Fullscreen → "..." → Download** | Le VRAI menu "..." atteint depuis le Feed principal est celui de `FeedFragment.java` (PAS `FullScreenMedia.java`, un écran mort pour ce flux — piège documentaire identifié et résolu). Ordre du menu, gating "posts des autres uniquement", sonde de qualité vidéo (720p→480p→360p→brut), en-tête Referer, protection anti-double-tap : tous ✅ Conforme, vérifiés bit pour bit. Écarts : filigrane/outro absent (V9-F-001, P1, découverte majeure), aucun feedback de succès (V9-F-007, P2), aucun indicateur de progression (V9-F-018 bis mineur), destination finale différente par design (V9-F-025, P3 assumé). |

---

## 5. Bugs et écarts identifiés (V9-F-001 à V9-F-026)

### P1 — CRITIQUE

```
ID : V9-F-001
PRIORITÉ : P1
DOMAINE : Feed → Fullscreen → Download (vidéo)
FEATURE : Filigrane + outro promotionnel appliqué par Android au téléchargement vidéo depuis le Feed, absent côté iOS
ANDROID SOURCE : service/broadcast/DownloadReceiver.java:64-88 (déclencheur, gate object=="videos" && origin=="feed") ; service/worker/ExportWorker.java (entier — doWork:113-136 check PROGRAM_PREMIUM, export:212-346 génération outro + filigrane + composition + nettoyage + sauvegarde finale)
ANDROID BEHAVIOR : Pour un utilisateur NON premium, toute vidéo téléchargée depuis le Feed est reconstituée avec un filigrane animé "Tiinver" + un outro de marque de 4s AVANT d'être visible dans la Galerie — le fichier brut du CDN est activement supprimé. Voir §4.2 pour le détail méthode par méthode.
IOS FILES : Sources/TiinverSwift/Feed/FeedMediaDownloader.swift (fichier entier, aucune trace de watermark/outro/premium)
IOS BEHAVIOR : Le fichier CDN brut est sauvegardé tel quel dans Photos, pour TOUS les utilisateurs (équivalent du chemin premium Android, sans distinction).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Mécanisme jamais découvert/documenté pour ce point d'entrée précis avant cet audit V9 (à la différence du bouton Partager, où l'absence est déjà assumée et documentée).
IMPACT : Tous les utilisateurs iOS (premium ou non) reçoivent l'équivalent du parcours premium Android via Télécharger — perte potentielle d'un levier de marque/acquisition significatif pour l'écrasante majorité des utilisateurs (non-premium).
RECOMMANDATION : Décision produit à trancher explicitement (aligner sur Android non-premium pour tous, sur Android premium pour tous — état actuel de facto —, ou construire un système Premium iOS avant de décider) — ne pas corriger silencieusement sans arbitrage, par cohérence avec la décision déjà prise pour le bouton Partager.
```

```
ID : V9-F-002
PRIORITÉ : P1 (❓ à vérifier — nécessite un test device/simulateur réel)
DOMAINE : Feed → Fullscreen → Download (vidéo, cas de repli qualité)
FEATURE : Risque de sauvegarder une URL/manifest HLS (.m3u8) comme fichier vidéo final téléchargeable
ANDROID SOURCE : Activity/ui/FeedFragment.java:1988-2026 (checkBestQualityAndDownload, repli sur model.getCdn_content_url() si les 3 qualités 720p/480p/360p échouent) ; Activity/service/ExoPlayerManager.java:473-474 (confirme que cdn_content_url peut légitimement être un .m3u8)
ANDROID BEHAVIOR : Dans le cas de repli (rare mais réel), le DownloadManager reçoit potentiellement un manifest .m3u8 avec une extension .mp4 forcée en dur.
IOS FILES : Sources/TiinverSwift/Feed/FeedMediaDownloader.swift:80-96 (bestVideoDownloadURL/videoQualityCandidates, même triplet de qualités, même repli sur cdn_content_url brut)
IOS BEHAVIOR : Même repli, même risque théorique — PARTAGÉ avec Android, PAS une régression iOS spécifique. Reste à vérifier : le comportement exact de PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:) sur un tel fichier mal étiqueté — échec propre (alerte affichée) ou succès silencieux sans média réellement sauvegardé (aggravé par l'absence totale de confirmation de succès, V9-F-007, qui empêcherait l'utilisateur de remarquer l'échec).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui, mais uniquement dans le cas de repli (rare en usage nominal)
CAUSE : Limitation partagée des deux plateformes, pas un défaut de portage.
IMPACT : Si confirmé défaillant côté iOS, un utilisateur pourrait croire avoir téléchargé une vidéo qui n'existe en réalité pas dans sa photothèque.
RECOMMANDATION : Test manuel prioritaire sur device/simulateur réel (forcer le cas de repli, vérifier le comportement de PHPhotoLibrary). Si confirmé, ajouter une vérification explicite de l'extension/contenu avant l'appel PHPhotoLibrary.
```

```
ID : V9-F-003
PRIORITÉ : P1
DOMAINE : MediaTrim
FEATURE : Aucun retour visuel pendant l'édition (aperçu de sélection, bouclage, prévisualisation rotation/flip)
ANDROID SOURCE : view/trimmer/VideoTrimmerView.java (ticker de playhead L500-509 ; ProTimelineView.Listener.onSelectionChanged/onUserScrub → player.seekTo L514-527 ; bouclage dans la sélection, myPlayerListener L985-990 ; applyPreview() L306-338, anime le conteneur du lecteur pour rotation/flip)
ANDROID BEHAVIOR : Glisser une poignée déplace immédiatement le lecteur à ce point ; la lecture boucle dans la fenêtre sélectionnée ; pivoter/retourner anime visuellement le conteneur du lecteur avant export.
IOS FILES : Sources/TiinverSwift/Feed/MediaTrimView.swift (VideoPlayer AVKit standard, aucun appel player.seek(...) dans tout le fichier, aucun .rotationEffect/.scaleEffect conditionnel sur le lecteur — confirmé par le fichier lui-même, commentaire L516-519)
IOS BEHAVIOR : Le lecteur ne réagit jamais au glissement des poignées, ne boucle jamais dans la sélection, et n'affiche jamais l'effet de la rotation/du flip avant export.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Fonctionnalité de synchronisation lecteur↔sélection jamais portée, alors que le modèle de données (VideoTrimState) qui la piloterait existe déjà.
IMPACT : L'utilisateur ne peut vérifier ni le point de coupe ni l'effet d'une rotation/d'un flip qu'après un export potentiellement long (ré-encodage complet) — seul moyen de vérifier le résultat, contrairement à Android.
RECOMMANDATION : (1) player?.seek(to:) dans dragGesture.onChanged pour prévisualiser le point de coupe ; (2) bouclage dans [startFraction,endFraction]*duration ; (3) .rotationEffect/.scaleEffect sur le conteneur du VideoPlayer selon trimState, avec fit-to-screen équivalent pour 90°/270°.
```

```
ID : V9-F-004
PRIORITÉ : P1 (❓ à vérifier — nécessite un test device/simulateur réel)
DOMAINE : MediaTrim
FEATURE : Maths de rotation/flip jamais vérifiées visuellement en exécution
ANDROID SOURCE : Utils/media/VideoTransformer.java:225-267 (buildTexCoords, remapping direct des coordonnées de texture OpenGL, combinaison avec metaRot lu depuis MediaFormat.KEY_ROTATION)
IOS FILES : Sources/TiinverSwift/Feed/MediaTrimView.swift:509-584 (composeTransform, composition de CGAffineTransform)
IOS BEHAVIOR : Logique mathématiquement cohérente à la lecture (même cycle 4 valeurs, même principe de pivot centré, même échange de dimensions à 90/270°, même ordre flip-après-rotation), mais AUCUNE vérification visuelle n'a jamais été faite — le fichier le documente lui-même explicitement (commentaire L514-519).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence d'environnement Xcode/simulateur dans toutes les sessions de développement à ce jour (contrainte Windows).
IMPACT SI UN ÉCART ÉTAIT CONFIRMÉ : rendu visuellement incorrect à l'export (P1), en particulier pour une vidéo source déjà tournée nativement en portrait (combinaison avec preferredTransform/metaRot jamais testée).
RECOMMANDATION : Test manuel prioritaire — importer une vidéo tournée en mode portrait ET appliquer une rotation manuelle 90°/180°/270°, comparer visuellement le rendu exporté entre les deux plateformes.
```

```
ID : V9-F-005
PRIORITÉ : P1/P2 (décision produit déjà partiellement actée)
DOMAINE : Publish / Animemes — bouton Partager
FEATURE : Filigrane + outro promotionnel absent du bouton "Partager" (chemin non-premium Android)
ANDROID SOURCE : editor/PublishFragment.java:306-312,448-461 (exportingVideo, hasPremium check) ; editor/service/ExportVideoService.java (watermark+outro, même mécanisme que V9-F-001 mais déclenché par le bouton Partager de l'écran Publish, PAS par le Téléchargement Feed — 2 points d'entrée distincts vers un mécanisme similaire)
ANDROID BEHAVIOR : Pour un utilisateur non-premium, le fichier partagé en externe est filigrané+outro ; premium → fichier brut.
IOS FILES : Sources/TiinverSwift/Feed/PublishComposeView.swift:64-100 (showRealMediaShareSheet, commentaire déjà présent expliquant l'absence délibérée) ; Sources/TiinverSwift/Animems/AnimemesEditorView.swift:396 (ShareLink), AnimemesExporter.swift:37 (TODO explicite)
IOS BEHAVIOR : Fichier brut partagé pour tous les utilisateurs, dans les deux écrans (Publish ET Animemes).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence totale de système Premium côté iOS (confirmé, aucun concept câblé nulle part dans le portage), décision déjà documentée et assumée dans le code source lui-même pour CE point d'entrée précis (contrairement à V9-F-001, jamais documenté avant cet audit).
IMPACT : Perte potentielle d'un levier d'acquisition organique pour le partage externe non-premium.
RECOMMANDATION : Même décision produit que V9-F-001, à trancher ensemble puisqu'il s'agit du même mécanisme sous-jacent (AnimatedWatermarkComposer/UnifiedComposerFinal) appliqué à 3 points d'entrée Android distincts (Partage Publish, Partage Animemes, Téléchargement Feed).
```

### P2 — IMPORTANT

```
ID : V9-F-006
PRIORITÉ : P2
DOMAINE : MediasDisplay
FEATURE : Bibliothèque de sons — catalogue propriétaire Android vs bibliothèque personnelle iOS
ANDROID SOURCE : editor/MediasDisplay.java:246-256 (MusicShooserDialog, catalogue de sons "maison" intégré à l'app)
IOS FILES : Sources/TiinverSwift/Feed/MediasDisplayView.swift:152-158,206-233 (MPMediaPickerController, bibliothèque musicale personnelle iCloud/Apple Music de l'utilisateur)
IOS BEHAVIOR : Fonctionnellement équivalent (choisir un morceau à mélanger) mais catalogue totalement différent — pas de "sons tendance" fournis par l'app côté iOS.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui, mais nécessiterait un catalogue de sons propre à héberger/streamer, absent du projet iOS actuel.
CAUSE : Écart technologique assumé faute d'accès aux mêmes assets côté iOS.
IMPACT : Perte de la découvrabilité de sons "maison" — potentiellement significatif pour la viralité/l'usage type Reels/TikTok de la fonctionnalité.
RECOMMANDATION : Évaluer l'intérêt produit d'un catalogue de sons propre à l'app côté iOS (hébergement CDN + UI de sélection dédiée) — chantier distinct, non trivial.
```

```
ID : V9-F-007
PRIORITÉ : P2
DOMAINE : Feed → Fullscreen → Download
FEATURE : Aucune confirmation de succès après un téléchargement réussi
ANDROID SOURCE : service/broadcast/DownloadReceiver.java:90 (Toast.makeText(context, "Download completed", Toast.LENGTH_SHORT).show())
IOS FILES : Sources/TiinverSwift/Feed/FeedView.swift (recherche exhaustive : alerte d'ÉCHEC uniquement, L968-972 ; aucun toast/alert/haptique de SUCCÈS)
IOS BEHAVIOR : Après un téléchargement réussi, aucun retour visible à l'utilisateur.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Chemin de succès jamais complété par un feedback utilisateur.
IMPACT : Sur une vidéo volumineuse en particulier, l'utilisateur tape "Télécharger" et ne voit plus rien se passer, sans confirmation que le fichier est bien arrivé dans Photos.
RECOMMANDATION : Ajouter un état de succès (toast-équivalent léger ou a minima UINotificationFeedbackGenerator().notificationOccurred(.success)) après un téléchargement réussi.
```

```
ID : V9-F-008
PRIORITÉ : P2 (❓ à vérifier — hors périmètre des 3 fichiers assignés à l'audit Upload/API)
DOMAINE : Publication API
FEATURE : Origine réelle des valeurs width/height envoyées par Android non tracée
ANDROID SOURCE : Activity/ui/MainFragment.java:746-764 (UploadData.setWidth/setHeight jamais appelés dans ce chemin direct — les valeurs proviendraient du ContentProvider local, ActivityRepository/ActivityViewModel, fichiers hors périmètre de cet audit)
IOS FILES : Sources/TiinverSwift/Feed/PublishComposeView.swift (calcule et envoie systématiquement les dimensions réelles du média)
IOS BEHAVIOR : iOS calcule toujours les dimensions réelles ; impossible d'affirmer une parité stricte sans tracer la source Android réelle.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Non déterminé dans ce périmètre
CAUSE : Fichiers Android pertinents (ActivityRepository/ActivityViewModel) non lus dans cette passe.
IMPACT : Potentiellement aucun (iOS envoie probablement des valeurs au moins aussi correctes qu'Android) — à confirmer.
RECOMMANDATION : Chapitre d'audit dédié tracant ActivityRepository.saveFilebeforeTransfer côté Android avant de conclure.
```

### P3 — MINEUR

```
V9-F-009 [Caméra] Permission micro demandée dès l'ouverture de l'écran caméra côté iOS (CameraCaptureController.swift:72-99), alors qu'Android ne la sollicite qu'au premier appui long réel sur le bouton de capture (CircleCaptureButton.java:484-504). Impact : popup micro vue par un utilisateur iOS qui n'utilise que la photo. Correction suggérée : déplacer la demande vers startRecording plutôt que start(lensFacing:).

V9-F-010 [Caméra] Bouton flash fonctionnel côté iOS (CameraView.swift:169-176) alors qu'il est mort/masqué côté Android (visibility="gone", jamais câblé, fragment_camera_portrate.xml:94-102). Amélioration assumée, pas une régression — information seulement.

V9-F-011 [MediasDisplay] La preview vidéo boucle côté iOS (MediasDisplayView.swift:60-65) mais PAS côté Android (le code cité en preuve, MediasDisplay.java onCompletion, est du code mort — la vraie preview utilise ExoPlayer sans repeatMode). Le commentaire iOS affirmant une fidélité Android est donc inexact — à corriger (documentation seulement, comportement jugé préférable).

V9-F-012 [MediasDisplay] Boutons Android "merge" (relance manuelle de la fusion) et "voice2" (bascule visibilité bouton enregistrement) non reproduits côté iOS — les 2 chemins AUTOMATIQUES de fusion (après choix musical, après confirmation voix off) sont bien reproduits, ces boutons semblent redondants. Impact négligeable.

V9-F-013 [PublishFragment] Gate de catégorie : Android optimiste (CategoryActivity.updateProfileData écrit en local puis publie même si la synchro serveur échoue silencieusement en arrière-plan) vs iOS pessimiste (CategoryPickerView.save attend la confirmation réseau avant de débloquer la publication). iOS plus robuste, divergence assumée à documenter comme amélioration.

V9-F-014 [PublishFragment] Bannière publicitaire toujours visible côté iOS (AdBannerView, pas de garde premium) alors qu'Android la masque si hasPremium. Cohérent avec l'absence totale de système Premium côté iOS — lié à V9-F-005.

V9-F-015 [Animemes] Commentaire de documentation iOS erroné (AnimemesEditorView.swift:85-91) qualifiant le passage par MediaTrimView de "écart produit délibéré, PAS une fidélité Android" — c'est en fait la fidélité exacte au tracé Android réel pour Animemes (voir §4.1). Correction de documentation uniquement, aucun changement de comportement nécessaire.

V9-F-016 [MediaTrim] Espacement minimal entre poignées exprimé en FRACTION de durée totale côté iOS (3%, MediaTrimView.swift:91) vs valeur ABSOLUE de 1000ms côté Android (ProTimelineView.java:315-318) — sur une vidéo courte, iOS autorise une sélection plus courte qu'Android ne l'aurait permis. ProTimelineViewModel.swift (déjà écrit, fidèle à Android) résoudrait ce point s'il était câblé au lieu d'être code mort.

V9-F-017 [MediaTrim] Bandeau de trim statique (toute la durée mappée sur l'écran) côté iOS vs bandeau à fenêtre de zoom/défilement côté Android (ProTimelineView.java, fenêtre visible ≈75s max) — précision de glissement réduite pour les vidéos longues côté iOS. Même remarque que V9-F-016 sur ProTimelineViewModel.swift.

V9-F-018 [MediaTrim] 8 vignettes générées côté iOS (MediaTrimView.swift:372) vs 16-20 côté Android (2 passes, generateThumbsAsync puis MediaAssetsLoader.extractThumbnails) — bandeau moins dense, gestion mémoire équivalente (320×180, sous-échantillonnage dès le décodage des deux côtés).

V9-F-019 [MediaTrim] Grille des tiers et marques de coin en L absentes de l'overlay de recadrage iOS (CropOverlayView.java:309-337 les dessine, MediaTrimView.swift:207-211 ne dessine qu'une bordure simple) — visuel uniquement.

V9-F-020 [MediaTrim] Ré-encodage systématique côté iOS (AVMutableComposition) même pour un trim purement temporel, alors qu'Android emprunte un fast path de remux sans décodage dans ce cas (VideoTransformer.java:131, SimpleTrimmer.java) — écart ASSUMÉ et documenté (compromis précision > vitesse), reconfirmé exact par cet audit. Impact : export iOS plus lent pour un trim simple, mais résultat plus précis (frame-exact vs calé sur keyframe).

V9-F-021 [MediaTrim] Bitrate de sortie délégué au preset AVAssetExportPresetHighestQuality côté iOS, sans calcul adaptatif équivalent à Android (adaptiveBitrate(), 800kbps-4Mbps borné selon résolution) — fichiers de sortie iOS potentiellement plus lourds.

V9-F-022 [MediaTrim] Fichier de sortie partiel non supprimé explicitement en cas d'échec d'export côté iOS (MediaTrimView.swift:501-505, aucun removeItem) — Android le fait explicitement (VideoTransformer.java finally, SimpleTrimmer.java catch). Répertoire temporaryDirectory iOS auto-nettoyé par le système, donc pas de fuite permanente.

V9-F-023 [Publication API] Champ "format":"json" envoyé par iOS (FeedRepository.swift:264), absent de la liste complète des paramètres Android sendMetaDate — poids mort probable (le serveur ignore vraisemblablement les clés inconnues), à retirer ou justifier.

V9-F-024 [Upload] Aucun callback de progression pour l'upload d'une PHOTO côté iOS (FeedMediaUploader.uploadPhoto), alors qu'Android en fournit un (ProgressRequestBodyUri) même pour ce chemin court. Impact mineur (upload photo très rapide).

V9-F-025 [Download] Destination finale différente par design : Android sauvegarde dans Downloads/tiinver/videos/ (dossier système, PAS la Galerie, sauf traitement watermark qui redirige vers Movies/Tiinver/Animemes/) ; iOS sauvegarde directement et systématiquement dans Photos via PHPhotoLibrary. Divergence de plateforme raisonnable (iOS n'a pas d'équivalent direct au dossier "Téléchargements" visible utilisateur pour ce type de contenu), à documenter explicitement plutôt qu'à corriger.

V9-F-026 [Download] Commentaire de documentation obsolète : FeedView.swift affirme encore "includesDownload = true SEULEMENT depuis ProfileView", contredit par le câblage réel actuel (FeedView.swift:248, includesDownload:true est bien présent pour le Feed principal aussi). Aucun impact fonctionnel, nettoyage de documentation uniquement.
```

---

## 6. Matrice de parité complète

| Fonction | Android | iOS | Parité | Priorité | Problème |
|---|---|---|---|---|---|
| Galerie | Picker système, sélection unique, aucune permission | Idem (PHPickerViewController) | ✅ | — | — |
| Animemes (contenu produit) | JPEG q.70 / MP4 H.264+AAC 30fps | JPEG q.0.7 / MP4 H.264+AAC 30fps | ✅ | — | — |
| Animemes (routage) | MemesFragment→MediaTrim→MediasDisplay (vidéo) | Idem depuis correction §4.1 | ✅ | — | Doc antérieure erronée (V9-F-015, cosmétique) |
| Caméra (capture) | H.264/AAC, seuils identiques, 20s max | Idem | ✅ | — | Micro trop tôt (V9-F-009, P3) |
| Caméra (routage) | Directement → MediasDisplay | → MediaTrim d'abord (divergence produit assumée) | ⚠️ | P3 | Décision produit déjà actée par l'utilisateur |
| MediaTrim (fonctions cœur) | Trim/pivot/flip/crop, bornes identiques | Idem | ✅ | — | Vignettes/bandeau/bitrate mineurs (P3) |
| MediaTrim (retour visuel) | Seek/boucle/preview rotation-flip en direct | Aucun des 4 | ❌ | **P1** | V9-F-003 |
| MediasDisplay | Musique/voix off, fusion réelle, 1 média max | Idem | ✅ | — | Catalogue musical différent (V9-F-006, P2) |
| PublishFragment | Légende 80c, hashtags, gate catégorie | Idem | ✅ | — | Gate plus strict côté iOS (V9-F-013, amélioration) |
| Poster | URL construite côté client, pas d'upload séparé | Idem, valeur identique | ✅ | — | — |
| Poster upload | N/A (pas un fichier séparé) | N/A | ✅ | — | — |
| Media upload | 2 clés BunnyCDN distinctes, headers exacts | Idem, vérifié caractère pour caractère | ✅ | — | — |
| Publication API | 17 champs top-niveau + 14 metadata | Idem, champ par champ | ✅ | — | 1 champ extra iOS (V9-F-023, P3) |
| Feed | Grille 2 colonnes, menu "..." sur FeedFragment | Grille, menu identique | ✅ | — | — |
| Fullscreen | Pager plein écran | FeedDetailPagerView | ✅ | — | — |
| More ⋯ | 6 items, Télécharger en dernier | Idem | ✅ | — | — |
| Share | Bouton dédié séparé, filigrane si non-premium | Fichier brut pour tous | ⚠️ | P1/P2 | V9-F-005 |
| Download photo | URL priorisée, Referer, permission | Idem | ✅ | — | — |
| Download vidéo | Sonde qualité identique + filigrane/outro si non-premium | Sonde identique, PAS de filigrane/outro | ⚠️ | **P1** | V9-F-001 |
| Permission download | DownloadManager, pas de permission (API29+) | PHPhotoLibrary .addOnly | ✅ | — | — |
| HLS download | Repli possible vers .m3u8 (rare) | Même repli, même risque partagé | ❓ | P1 | V9-F-002, à vérifier device |
| Sauvegarde Photos/Galerie | Downloads/ (ou Movies/Tiinver/Animemes si watermarké) | Photos directement | ⚠️ | P3 | V9-F-025, divergence assumée |
| Feedback utilisateur | Toast "Download completed" | Aucun | ❌ | P2 | V9-F-007 |

Statuts : ✅ Conforme · ⚠️ Partiellement conforme · ❌ Non conforme · ❓ À vérifier

---

## 7. Plan de correction

```
P0 (0 finding — rien à traiter)
 ↓
P1 (5 findings — 2 conditionnels à un test device)
 1. V9-F-003 — MediaTrim : retour visuel pendant l'édition (le plus actionnable immédiatement, pas de décision produit requise)
 2. V9-F-001 — Download : décision produit filigrane/outro (bloque sur un arbitrage, pas un correctif pur)
 3. V9-F-005 — Share : même décision produit que V9-F-001, à trancher ensemble
 4. V9-F-004 — MediaTrim : test device rotation/flip (préalable nécessaire avant de savoir si un correctif est même requis)
 5. V9-F-002 — Download : test device cas de repli HLS (idem)
 ↓
P2 (3 findings)
 1. V9-F-007 — Download : ajouter un feedback de succès (correctif petit, immédiat)
 2. V9-F-006 — MediasDisplay : décision produit catalogue de sons (chantier séparé, non trivial)
 3. V9-F-008 — Publication API : chapitre d'audit complémentaire (ActivityRepository côté Android)
 ↓
P3 (18 findings — cosmétiques/documentation/optimisations, à traiter en lot quand le temps le permet)
```

---

## 8. Conclusion

### Question A — Le pipeline Galerie/Animemes/Caméra → MediaTrim → MediasDisplay → PublishFragment → Poster → Upload → Publication est-il réellement équivalent entre Android et iOS ?

**Oui, avec une réserve unique et bien délimitée.** Chaque étape individuelle du pipeline —
acquisition (galerie/caméra/Animemes), édition géométrique/temporelle (MediaTrim), revue
musique/voix off (MediasDisplay), composition de la publication (PublishFragment), génération du
poster, upload BunnyCDN (2 clés distinctes, 2 étapes pour la vidéo), et l'appel final `POST
activity/add` (17+14 champs vérifiés un par un) — a été comparée et confirmée fonctionnellement
équivalente, preuves à l'appui (file:line des deux côtés, valeurs littérales comparées
caractère pour caractère pour l'upload et l'API). Aucun défaut bloquant (P0) n'a été trouvé sur ce
pipeline. La réserve concerne l'écran `MediaTrim` : l'ÉDITION elle-même produit un résultat correct
des deux côtés, mais l'EXPÉRIENCE iOS pendant l'édition est dégradée (aucun retour visuel avant
export, V9-F-003) — un défaut d'UX réel, pas un défaut de résultat final. Le routage Animemes a été
CORRIGÉ dans la documentation (il était déjà correct dans le code) : Android fait bien passer une
vidéo Animemes par `MediaTrim`, contrairement à ce qu'affirmait la doc antérieure.

### Question B — Le pipeline Feed → Fullscreen → More ⋯ → Download → sauvegarde de photo/vidéo est-il réellement équivalent entre Android et iOS ?

**Le mécanisme de téléchargement lui-même est équivalent (menu, sonde qualité, permission,
sauvegarde) — mais le RÉSULTAT final pour une vidéo ne l'est pas.** L'accessibilité de l'action
(Feed → Fullscreen → "..." → Télécharger), la logique de sélection de qualité vidéo (720p→480p→
360p→brut, identique bit pour bit), l'en-tête `Referer`, la permission `PHPhotoLibrary` (add-only,
la plus restrictive et donc la plus fidèle à l'intention "juste sauvegarder", contrairement à
`DownloadManager` qui ne demande aucune permission mais aussi n'accède pas directement à la
photothèque) sont tous fidèlement reproduits et vérifiés fonctionnels. **Mais le fichier vidéo
qu'un utilisateur Android non-premium reçoit réellement dans sa Galerie n'est PAS le même contenu
que celui qu'un utilisateur iOS reçoit dans Photos** — Android le reconstitue avec un filigrane
animé et un outro promotionnel de 4 secondes avant de le rendre visible (V9-F-001, découverte
majeure de cet audit, jamais documentée avant aujourd'hui), tandis qu'iOS livre systématiquement le
fichier brut du CDN. Il manque aussi une confirmation de succès explicite côté iOS (V9-F-007). Le
mécanisme technique de téléchargement est donc équivalent ; le résultat métier final pour une
vidéo, non.

---

## 9. Contre-audit adversarial des 5 P1 (2026-09-02, seconde passe de validation)

**Objectif de cette passe** : pour chacun des 5 `P1`, déterminer — preuves Android ET iOS à
l'appui — s'il s'agit (1) d'un vrai défaut de parité, (2) d'une différence UX acceptable, (3) d'un
comportement Android relevant d'une règle produit spécifique (pas une référence à copier
aveuglément), ou (4) d'un point dont le comportement attendu reste à confirmer. Consigne explicite
respectée : ne jamais déduire que « ce que fait Android » est automatiquement « ce que doit faire
iOS » — en particulier quand le comportement Android lui-même bifurque selon des conditions
(statut premium) absentes du portage iOS.

Classification utilisée pour chaque finding : `CONFIRMED BUG` / `EXPECTED DIFFERENCE` /
`PRODUCT DECISION REQUIRED` / `FALSE POSITIVE`.

---

### 9.1 — V9-F-001 : Filigrane + outro au téléchargement vidéo

**Reconstitution complète du comportement Android, matrice à 4 cas (photo/vidéo × gratuit/premium),
pour Share ET Download** :

| Média | Statut | Action | Comportement Android EXACT | Preuve |
|---|---|---|---|---|
| Photo | Gratuit | Partager | Fichier brut, `ShareCompat.IntentBuilder` direct | `PublishFragment.java:513-526` (`sharePhoto`) — aucune lecture de `hasPremium`, aucun appel à `ExportVideoService` |
| Photo | Premium | Partager | Identique (fichier brut) | Idem — le code de `sharePhoto` ne teste JAMAIS le statut premium |
| Photo | Gratuit/Premium | Télécharger | Jamais de filigrane, quel que soit le statut | `DownloadReceiver.java:64` : `object.equals("videos")` exclut catégoriquement toute photo du déclenchement d'`ExportWorker` |
| Vidéo | Gratuit | Partager | `PublishFragment.java:448-461` : `!hasPremium` → démarre `ExportVideoService` (watermark animé + outro 4s) → `shareVideo(fichier filigrané)` |
| Vidéo | Premium | Partager | `PublishFragment.java:450` : `hasPremium` → `shareVideo(fileUri)` **direct**, fichier brut, `ExportVideoService` jamais démarré |
| Vidéo | Gratuit | Télécharger | `DownloadReceiver`→`ExportWorker.doWork()` (`ExportWorker.java:118`) : `!hasPremium` → `export()` → filigrane+outro → **fichier brut supprimé** → sauvegarde finale dans `Movies/Tiinver/Animemes/`, **scannée et visible en Galerie** (`MediaScannerConnection.scanFile`) |
| Vidéo | Premium | Télécharger | `ExportWorker.doWork()` : `hasPremium` → **no-op complet** (juste `updateProgress(100)`/`updateState("finish")`) — le fichier reste **exactement là où `DownloadManager` l'a écrit** (`Downloads/tiinver/videos/`), **PAS scanné en Galerie automatiquement** | `ExportWorker.java:118-123` |

**Découverte supplémentaire de cette passe, absente du rapport initial** : même en écartant
entièrement la question du filigrane, le statut premium change aussi la **destination finale** du
fichier sur Android — un utilisateur premium garde son fichier dans le dossier système
« Téléchargements » (jamais poussé en Galerie), un utilisateur gratuit voit son fichier (filigrané)
apparaître directement dans sa Galerie. Il n'existe donc pas UN SEUL comportement Android
« Téléchargement vidéo », mais DEUX comportements entièrement distincts (contenu ET destination),
choisis par une variable produit qu'iOS n'a pas.

**iOS actuel** : un seul comportement, pour tous : fichier brut, toujours sauvegardé directement
dans Photos (`FeedMediaDownloader.swift`, `PHAssetChangeRequest.creationRequestForAssetFromVideo`).
C'est strictement le comportement **PREMIUM** d'Android pour le contenu, mais PAS pour la
destination (Android premium ne va jamais en Galerie ; iOS y va toujours).

- **Android actuel** : bifurque en 4 comportements distincts selon (statut premium × action), voir
  matrice ci-dessus.
- **iOS actuel** : 1 seul comportement, pour tous, quel que soit le média ou l'action — équivalent
  au chemin Android « vidéo premium + partage » pour le CONTENU, mais pas à un chemin Android
  cohérent pour la DESTINATION.
- **Différence** : le résultat obtenu par un utilisateur iOS ne correspond à AUCUN des 4 chemins
  Android de façon complète (contenu + destination réunis) — il correspond à un contenu premium
  livré à une destination gratuite.
- **Impact** : perte du levier de branding/acquisition organique pour tous les utilisateurs
  gratuits (majorité), ET incohérence mineure de destination même pour un profil « premium »
  hypothétique.
- **Est-ce une vraie exigence de parité ou une décision produit à confirmer ?** **Décision produit.**
  Il n'existe pas de comportement Android unique et non-ambigu à répliquer — le choisir (gratuit
  pour tous, premium pour tous — état de facto actuel —, ou construire un vrai système Premium
  iOS avant de trancher) est un arbitrage produit, pas une correction de bug.

**Classification : `PRODUCT DECISION REQUIRED`.**

---

### 9.2 — V9-F-002 : Risque HLS (`.m3u8`) en cas de repli qualité

**Nouvelle preuve déterminante, absente du rapport initial** : `cdn_content_url` est construit de
façon **strictement identique** sur les deux plateformes pour toute vidéo publiée :

- Android : `ActivityService.java:298` — `String cdn_content_url = videoId + "/playlist.m3u8";`
- iOS : `FeedMediaUploader.swift:111-115` — `cdnContentUrl: "\(guid)/playlist.m3u8"`

Ce champ est donc **TOUJOURS** un manifest `.m3u8`, sur les deux plateformes, sans exception — ce
n'est pas une possibilité occasionnelle, c'est la valeur systématiquement stockée en base pour ce
champ précis dès la publication. Le repli `bestVideoDownloadURL`/`checkBestQualityAndDownload`
(quand les 3 sondes 720p/480p/360p échouent toutes) livre donc, dans les DEUX codebases, ce même
manifest à leur mécanisme de sauvegarde système respectif (`DownloadManager` côté Android,
`PHAssetChangeRequest.creationRequestForAssetFromVideo` côté iOS), avec extension `.mp4` forcée en
dur des deux côtés.

- **Android actuel** : repli possible vers un `.m3u8` mal étiqueté `.mp4`, remis tel quel à
  `DownloadManager` (aucune vérification de contenu, `DownloadManager` ne valide pas les octets).
- **iOS actuel** : repli identique, même construction d'URL, même absence de vérification de
  contenu avant l'appel `PHPhotoLibrary`.
- **Différence** : **aucune** — le comportement est byte-pour-byte le même sur les deux
  plateformes, preuve directe à l'appui (constructions littérales identiques citées ci-dessus).
- **Impact** : s'il existe, ce risque est un défaut produit PARTAGÉ (probablement présent sur
  Android AUSSI, un fichier `.m3u8` de quelques centaines d'octets sauvegardé comme si c'était une
  vidéo de plusieurs Mo produirait vraisemblablement un résultat tout aussi cassé/illisible sur les
  deux plateformes) — PAS un écart de portage iOS.
- **Est-ce une vraie exigence de parité ou une décision produit à confirmer ?** Ni l'un ni l'autre
  — ce n'est PAS un sujet de parité du tout, puisqu'il n'y a pas de différence entre les deux
  plateformes à corriger.

**Classification : `FALSE POSITIVE`** (en tant qu'écart de parité Android↔iOS — le comportement est
identique). Recommandation distincte, HORS périmètre de cet audit de portage : envisager un ticket
produit séparé, applicable aux DEUX plateformes, si ce cas de repli s'avère réellement atteint en
usage réel (à mesurer via les logs serveur — fréquence à laquelle les 3 qualités 720p/480p/360p
échouent simultanément).

---

### 9.3 — V9-F-003 : Absence de retour visuel pendant l'édition MediaTrim

**Question posée par l'utilisateur : est-ce que ça empêche l'utilisateur iOS d'obtenir le MÊME
RÉSULTAT que l'utilisateur Android, ou est-ce principalement une différence d'interface ?**

Comparaison précise des 10 axes demandés :

| Axe | Android | iOS | Le RÉSULTAT FINAL diffère-t-il ? |
|---|---|---|---|
| Seek pendant le drag des poignées | `onSelectionChanged`→`player.seekTo(startMs)` (retour visuel immédiat) | Aucun (`grep` négatif de `.seek(` sur tout `MediaTrimView.swift`) | Non — le seek n'affecte que l'AFFICHAGE pendant l'édition, pas les valeurs `startFraction`/`endFraction` réellement utilisées à l'export, qui sont identiques dans les deux cas |
| Synchronisation preview↔sélection | Le lecteur reflète toujours la fenêtre `[selStart,selEnd]` | Le lecteur (AVKit `VideoPlayer` standard) joue la vidéo COMPLÈTE, contrôles natifs | Non — purement une question d'AFFICHAGE ; les bornes réellement exportées ne dépendent pas de ce que le lecteur montre |
| Loop dans la sélection | `Player.STATE_ENDED`→reseek au début de la sélection, boucle infinie | Aucun bouclage, lecture complète native | Non — même raisonnement |
| Rotation (aperçu live) | Conteneur du lecteur animé en temps réel (`applyPreview`) | Aucun aperçu, mais `composeTransform` applique la MÊME rotation au moment de l'export (§4, MediaTrim, points 6-7 du rapport initial) | **Non pour le résultat, mais VOIR V9-F-004** — la fonction de transformation ELLE-MÊME reste `❓` non vérifiée indépendamment de ce point-ci |
| Flip (aperçu live) | Idem, animé en temps réel | Idem, appliqué à l'export sans aperçu | Idem — dépend de V9-F-004, pas de ce point |
| Crop | Rectangle interactif affiché ET appliqué à l'export sur les deux plateformes | Idem (`cropOverlay`, §8 du rapport initial, déjà `✅ Conforme`) | Non — le crop EST prévisualisé sur les deux plateformes (seul le point distinct concerné ici est rotation/flip, pas le crop) |
| Trim (découpe temporelle) | Bornes appliquées à l'export | Bornes appliquées à l'export, valeurs identiques que prévisualisées ou non | Non |
| Ré-encodage | Fast path conditionnel (§9 rapport initial, `V9-F-020`) | Ré-encodage systématique | Non pertinent à CE point précis (différence de vitesse/précision déjà traitée séparément) |
| Preview avant export | Riche (4 mécanismes actifs) | Aucune | **Différence d'INTERFACE confirmée, pas de résultat** |
| Résultat final exporté | Frame-exact ou calé keyframe selon le chemin | Toujours frame-exact (ré-encodage systématique) | Non — au contraire, iOS produit un résultat au moins aussi précis (voir V9-F-020, déjà noté comme un compromis assumé) |

**Conclusion factuelle** : sur les 10 axes, l'écart se limite strictement aux 4 mécanismes de
PRÉVISUALISATION eux-mêmes (seek, loop, aperçu rotation, aperçu flip) — dans TOUS les cas, la
valeur réellement appliquée à l'export (`startFraction`/`endFraction`/`rotationDegrees`/
`flippedHorizontally`/`cropCenter`) est lue depuis le MÊME état (`@State`/`VideoTrimState`) que
celui piloté par les boutons, indépendamment de ce que le lecteur affiche pendant l'édition. **Le
résultat final n'est donc PAS démontré différent par ce point précis** — c'est un déficit
d'interface/confiance pendant l'édition (l'utilisateur ne peut pas VÉRIFIER visuellement avant
d'exporter), pas un déficit de résultat.

- **Android actuel** : 4 mécanismes de synchronisation lecteur↔édition actifs et démontrés (citations
  precises dans le rapport initial, §V9-F-003).
- **iOS actuel** : aucun des 4, confirmé par recherche exhaustive négative dans le fichier entier.
- **Différence** : réelle et non ambiguë — absence totale de fonctionnalité, pas une question
  d'interprétation.
- **Impact** : dégradation de confiance/UX pendant l'édition (l'utilisateur doit exporter — un
  ré-encodage potentiellement long — pour voir le résultat d'une rotation/d'un flip/d'un point de
  coupe), MAIS le fichier produit à la fin est fonctionnellement correct (sous réserve, séparément,
  que V9-F-004 confirme la justesse des maths de rotation/flip).
- **Est-ce une vraie exigence de parité ou une décision produit à confirmer ?** Vraie exigence de
  parité UX — Android offre une fonctionnalité concrète (retour visuel immédiat) qu'iOS n'offre pas
  du tout, sans qu'aucune raison produit ne justifie cette absence (ce n'est pas un choix assumé
  documenté quelque part, contrairement à V9-F-001/V9-F-005).

**Classification : `CONFIRMED BUG`** — mais **portée corrigée par rapport au rapport initial** :
c'est un bug d'INTERFACE/interaction démontré, PAS un bug de résultat. **Recommandation de
sévérité révisée : P2** (pas P1) — aucun utilisateur n'obtient un fichier final différent de ce
qu'il obtiendrait sur Android, seulement une expérience d'édition moins rassurante. La décision
finale de priorité reste à l'utilisateur, mais la justification d'un P1 (« résultat cassé ») ne
tient pas à l'examen.

---

### 9.4 — V9-F-004 : Justesse des maths de rotation/flip, jamais vérifiée en exécution

**Tentative de vérification statique plus poussée, au-delà du rapport initial** : lecture directe de
`VideoTransformer.buildTexCoords` (`engine/.../VideoTransformer.java:662-679`) :

```java
private float[] buildTexCoords(float l, float t, float r, float b, int rotation, boolean flipH) {
    float[][] c = { {l,b}, {r,b}, {l,t}, {r,t} };
    int[] order;
    switch (((rotation % 360) + 360) % 360) {
        case  90: order = new int[]{2, 0, 3, 1}; break;
        case 180: order = new int[]{3, 2, 1, 0}; break;
        case 270: order = new int[]{1, 3, 0, 2}; break;
        default:  order = new int[]{0, 1, 2, 3}; break;
    }
    // ... permutation des coordonnées UV selon `order`, puis flip horizontal si demandé
}
```

C'est un remapping de **coordonnées de texture GPU** (convention OpenGL ES, système de sommets non
inclus dans cet extrait — le positionnement du quad lui-même, ailleurs dans le fichier, n'a pas été
relu dans cette passe) — un mécanisme **fondamentalement différent** de l'approche iOS
(composition de `CGAffineTransform` via `AVMutableVideoCompositionLayerInstruction`, un système de
coordonnées Core Graphics/AVFoundation). Établir une preuve rigoureuse d'équivalence entre les deux
exigerait : (1) de tracer aussi le positionnement des sommets (pas seulement les UV), (2) de
résoudre toute divergence de convention d'axe Y entre OpenGL (Y-up) et Core Graphics/AVFoundation
(Y-down) — un piège déjà rencontré ailleurs dans CE MÊME projet (voir les commentaires de
`LayerRenderer.swift` sur ce sujet précis pour le rendu Animems).

**Précédent direct dans ce même fichier justifiant la prudence** : ce même écran (`MediaTrim`) a
déjà fait l'objet de DEUX conclusions statiques erronées, corrigées seulement après une relecture
plus profonde (V3-F-032/V3-F-124, invalidées par V5-F-037 — voir le rapport initial, §9 du tableau
MediaTrim). Affirmer une conclusion `CONFIRMED BUG` ou `FALSE POSITIVE` ici, sans test réel, sur la
seule base d'une lecture partielle, répéterait exactement l'erreur méthodologique déjà identifiée
et corrigée dans ce projet.

- **Android actuel** : remapping de coordonnées de texture OpenGL par permutation d'indices.
- **iOS actuel** : composition de `CGAffineTransform` (translation-rotation-translation, centrée).
- **Différence** : mécanismes non directement comparables par simple lecture ; équivalence
  mathématique plausible sur la base du CYCLE de valeurs et du principe de pivot centré (déjà noté
  dans le rapport initial), mais NON prouvée avec certitude.
- **Impact si un écart réel existait** : rendu visuellement incorrect à l'export — élevé, mais
  purement hypothétique à ce stade.
- **Est-ce une vraie exigence de parité ou une décision produit à confirmer ?** Ni l'un ni l'autre —
  **c'est un point factuel binaire (juste ou faux) qui ne peut être tranché que par un test**, pas
  par un jugement de priorité produit.

**Classification : reste `❓` — non tranchable sans test device/simulateur réel.** Aucune
correction ne doit être entreprise sur la seule base de cet audit statique. Recommandation
opérationnelle précise pour lever le doute rapidement : importer une vidéo tournée nativement en
mode portrait (rotation EXIF/`preferredTransform` non-nulle), appliquer une rotation manuelle de
90°, comparer visuellement le résultat exporté aux deux mêmes opérations sur Android — un seul test
ciblé suffit à confirmer ou infirmer.

---

### 9.5 — V9-F-005 : Filigrane + outro absent du bouton Partager (Publish/Animems)

Aucun fait nouveau à établir par rapport au rapport initial — l'absence est **déjà consciemment
documentée dans le code source iOS lui-même** (`PublishComposeView.swift:64-100`, plusieurs
paragraphes de commentaire explicitant le choix et les 3 options ouvertes : filigrane pour tous
comme Android non-premium, aucun filigrane comme état actuel, ou construction d'un système Premium
avant de trancher). Il s'agit du **même mécanisme sous-jacent Android** que V9-F-001
(`AnimatedWatermarkComposer`/`UnifiedComposerFinal`), simplement déclenché depuis un point d'entrée
différent (`PublishFragment.share`/`AnimemesCompound` plutôt que `DownloadReceiver`).

- **Android actuel** : `!hasPremium` → filigrane+outro appliqué au fichier partagé (`PublishFragment.
  java:448-461`) ; `hasPremium` → fichier brut (`:450`).
- **iOS actuel** : fichier brut pour tous, sans distinction — déjà documenté comme tel dans le code.
- **Différence** : identique en nature à V9-F-001 (bifurcation Android selon un statut absent
  d'iOS), mais SANS la complication de destination (Partager livre toujours vers la feuille de
  partage système sur les deux plateformes, pas de question de dossier final).
- **Impact** : perte potentielle du même levier d'acquisition organique que V9-F-001, pour le canal
  Partage plutôt que Téléchargement.
- **Est-ce une vraie exigence de parité ou une décision produit à confirmer ?** **Décision
  produit**, pour la même raison exacte que V9-F-001 — pas de comportement Android unique à copier.

**Classification : `PRODUCT DECISION REQUIRED`** — à fusionner avec V9-F-001 dans une seule
décision produit unique (le MÊME mécanisme Android, 3 points d'entrée au total en comptant l'export
Animems déjà noté séparément dans le rapport initial), plutôt que 2 (ou 3) décisions indépendantes
qui risqueraient d'aboutir à des choix incohérents entre eux.

---

## 10. Synthèse actionnable post-validation (2026-09-02)

### 10.1 — Les 5 P1 reclassifiés

| ID | Sujet | Priorité §5 initiale | Classification post-validation | Priorité recommandée |
|---|---|---|---|---|
| V9-F-001 | Filigrane+outro au Téléchargement | P1 | `PRODUCT DECISION REQUIRED` | Reste ouvert tant que la décision n'est pas prise — pas un ticket de correction de code en l'état |
| V9-F-002 | Risque `.m3u8` en repli | P1 (❓) | `FALSE POSITIVE` (comportement identique aux deux plateformes) | Retiré du backlog de portage — éventuel ticket produit séparé, hors périmètre iOS |
| V9-F-003 | MediaTrim — absence de retour visuel | P1 | `CONFIRMED BUG` (portée : UX/interaction, pas résultat) | **P2** (révisé à la baisse — le fichier final n'est pas affecté) |
| V9-F-004 | MediaTrim — justesse rotation/flip | P1 (❓) | `❓` non tranché — nécessite un test device | Reste `❓` — un seul test ciblé (vidéo portrait + rotation 90°) suffit à trancher |
| V9-F-005 | Filigrane+outro au Partage | P1 | `PRODUCT DECISION REQUIRED` (à fusionner avec V9-F-001) | Reste ouvert, même décision que V9-F-001 |

### 10.2 — Les P2 reclassifiés

| ID | Sujet | Reclassification |
|---|---|---|
| V9-F-006 | Catalogue musical propriétaire absent | Inchangé — `PRODUCT DECISION REQUIRED` (chantier d'hébergement de contenu, pas un bug de code) |
| V9-F-007 | Aucun feedback de succès au téléchargement | Inchangé — `CONFIRMED BUG` net, sans ambiguïté, corrigible immédiatement et sans décision produit préalable |
| V9-F-008 | Origine réelle de `width`/`height` côté Android | Inchangé — reste `❓`, nécessite un chapitre d'audit dédié (fichiers Android non lus dans le périmètre assigné) |

### 10.3 — Les P3 (inchangés, listés pour mémoire)

V9-F-009 à V9-F-026 (18 findings) — aucun n'a été touché par cette passe de validation, tous
restent des écarts mineurs (cosmétiques, de documentation, ou d'optimisation) sans impact sur le
résultat final ni sur une décision produit bloquante. Voir §5 pour le détail complet.

### 10.4 — Corrections réellement nécessaires (exécutables sans attendre de décision produit)

1. **V9-F-007** (P2→ passe en tête, seule correction P1/P2 ne dépendant d'AUCUNE décision produit
   ni d'AUCUN test device) — ajouter un retour de succès explicite après un téléchargement réussi.
2. **V9-F-003** (P2 révisé) — ajouter le retour visuel `MediaTrim` (seek synchronisé, bouclage,
   aperçu rotation/flip) — ne dépend d'aucune décision produit, uniquement d'un effort
   d'implémentation SwiftUI/AVKit.
3. Le nettoyage des P3 documentaires/cosmétiques (V9-F-011, V9-F-015, V9-F-026) peut être fait à
   tout moment, sans risque, en lot.

### 10.5 — Décisions produit à prendre AVANT de coder quoi que ce soit d'autre

1. **Filigrane + outro promotionnel (V9-F-001 + V9-F-005, décision UNIQUE à prendre pour les 2)** :
   iOS doit-il (a) répliquer le comportement Android non-premium (filigrane+outro pour tous, sur
   Partage ET Téléchargement) ; (b) conserver l'état actuel (fichier brut pour tous, équivalent
   premium) en l'assumant explicitement comme choix produit documenté ; ou (c) construire d'abord
   un système Premium iOS avant de trancher lequel des deux comportements s'applique à qui ? Cette
   décision doit aussi couvrir la question de DESTINATION du fichier téléchargé (Photos direct vs
   un éventuel dossier « Téléchargements » iOS, actuellement inexistant).
2. **Catalogue de sons `MediasDisplay` (V9-F-006)** : investissement jugé nécessaire ou non pour un
   catalogue de sons propre à l'app côté iOS (vs bibliothèque personnelle de l'utilisateur, état
   actuel) ?

### 10.6 — Ordre recommandé des corrections

```
Immédiat, sans décision produit préalable :
 1. V9-F-007 — feedback de succès au téléchargement (petit correctif, gain UX net)
 2. V9-F-003 — retour visuel MediaTrim (seek/loop/aperçu rotation-flip)
 3. Lot de nettoyage documentaire P3 (V9-F-011, V9-F-015, V9-F-026)
 ↓
Test bloquant avant de savoir si une correction est même nécessaire :
 4. V9-F-004 — test manuel ciblé (vidéo portrait + rotation 90°, comparaison visuelle Android/iOS)
    → si un écart réel est confirmé, le traiter en P1 immédiatement après
 ↓
En attente d'arbitrage produit (aucun code à écrire avant la décision) :
 5. V9-F-001 + V9-F-005 — décision filigrane/outro (§10.5.1)
 6. V9-F-006 — décision catalogue de sons (§10.5.2)
 ↓
Hors périmètre de ce cycle de correction :
 - V9-F-002 — reclassé FALSE POSITIVE, retiré du backlog de portage iOS
 - V9-F-008 — nécessite un chapitre d'audit complémentaire avant toute action
 - Reste des P3 — lot à faible risque, à traiter au fil de l'eau
```

---

## 11. Corrections implémentées (Phase 1, 2026-09-02 — bugs confirmés sans ambiguïté uniquement)

**Périmètre strictement respecté** : uniquement V9-F-007 et V9-F-003 (les 2 seuls findings
`CONFIRMED BUG` sans dépendance à une décision produit ni à un test device). Aucune ligne touchée
concernant le filigrane/outro (Download ou Share), le catalogue musical, le fallback `.m3u8`, ou
les mathématiques d'export (`composeTransform`/`trim()`, `VideoTrimState.swift` — inchangés).

### 11.1 — V9-F-007 : feedback de succès au téléchargement

**Fichier modifié** : `Sources/TiinverSwift/Feed/FeedView.swift` (`struct FeedDetailPagerView`).

- Ajout de `@State private var downloadSucceeded = false`, à côté de `downloadError` (préexistant).
- Dans le bouton "Télécharger" (`.confirmationDialog("Actions", ...)`), `downloadSucceeded = true`
  ajouté juste après `try await FeedMediaDownloader.download(post)` — **pas** dans un `catch`, donc
  déclenché UNIQUEMENT si `download(post)` retourne sans erreur, ce qui n'arrive qu'après le succès
  de `PHPhotoLibrary.shared().performChanges` (le fichier est réellement présent dans Photos à ce
  point précis, pas seulement téléchargé depuis le réseau — vérifié en relisant
  `FeedMediaDownloader.swift` avant de coder, voir §11.3).
- Ajout d'un `.alert("Téléchargement réussi", isPresented: $downloadSucceeded) { Button("OK",
  role: .cancel) {} }`, juste après l'`.alert` d'échec préexistant — même style que le motif
  "toast" déjà établi dans ce projet (`templateSavedToast`/"Modèle enregistré",
  `AnimemesEditorView.swift:479-481`), repris à l'identique plutôt qu'un nouveau mécanisme inventé.

Couvre les DEUX points d'entrée (`FeedView` grille Home ET `ProfileView`), qui partagent tous deux
la même `FeedDetailPagerView` — un seul site de correction nécessaire.

### 11.2 — V9-F-003 : retour visuel pendant l'édition MediaTrim

**Fichier modifié** : `Sources/TiinverSwift/Feed/MediaTrimView.swift`. Trois ajouts ciblés,
`composeTransform`/`trim()` (les fonctions d'EXPORT) intégralement inchangées :

1. **Seek synchronisé au glissement des poignées** (`dragGesture(isStart:width:)`) — un seul appel
   `player?.seek(to: CMTime(seconds: seekFraction * duration, ...), toleranceBefore: .zero,
   toleranceAfter: .zero)` ajouté en fin de `.onChanged`, port de `onSelectionChanged`→`seekTo`
   (`VideoTrimmerView.java:514-527`). `startFraction`/`endFraction` eux-mêmes ne sont pas modifiés.
2. **Bouclage dans la sélection pendant la lecture** — nouvelle fonction privée
   `addLoopObserver()`, appelée une fois dans `load()` juste après la création du `player` :
   observateur de temps périodique (0.1s) qui reseek au début de la sélection dès que la lecture
   atteint sa fin, port de `Player.STATE_ENDED`→`seekTo(selStart)` (`VideoTrimmerView.java:
   985-990`). Capture `[weak player]` pour éviter le cycle de rétention lecteur↔observateur.
3. **Aperçu live de la rotation/miroir** — nouvelle propriété calculée `videoPreview` remplaçant le
   `VideoPlayer` figé précédent : un `GeometryReader` calcule `videoRect` (même formule
   `letterboxedRect`/`currentPreviewAspect` qu'utilisait déjà `cropOverlay`, pour rester aligné),
   pré-dimensionne le `VideoPlayer` en ÉCHANGEANT largeur/hauteur pour une rotation 90°/270° (le
   fit-to-screen nécessaire, une rotation ne changeant pas la taille de mise en page d'une vue),
   puis applique `.rotationEffect(.degrees(trimState.rotationDegrees))` et
   `.scaleEffect(x: trimState.flippedHorizontally ? -1 : 1, y: 1)` — port de `applyPreview()`
   (`VideoTrimmerView.java:306-338`). Lit `trimState` tel quel, ne le modifie pas.

**Ce qui n'a PAS été touché, vérifié explicitement** : `composeTransform` (la fonction qui calcule
la transformation RÉELLEMENT appliquée à l'export), `trim()` (l'export lui-même),
`VideoTrimState.swift` (le modèle d'état) — les 3 recherchés dans le diff final, absents.

### 11.3 — Méthode suivie pour chaque correction

Pour les deux corrections : (1) relecture de la fiche V9-F-00x/§9 du contre-audit ; (2) relecture
directe du fichier Android cité (`DownloadReceiver.java` pour V9-F-007 ; `VideoTrimmerView.java`
pour V9-F-003) ; (3) relecture directe du fichier iOS actuel AVANT toute modification
(`FeedMediaDownloader.swift` entier, `MediaTrimView.swift` entier) pour confirmer avec certitude le
point exact où l'opération réussit réellement (pas seulement démarre) ; (4) changement minimal,
sans toucher aux fonctions d'export/upload/watermark ; (5) relecture du diff final pour confirmer
l'absence de tout effet de bord.

### 11.4 — Test manuel à préparer pour V9-F-004 (rotation/flip) — NON exécuté, device indisponible

Aucune modification des mathématiques de rotation/flip n'a été faite, conformément à la consigne.
Protocole exact préparé pour trancher `V9-F-004` dès qu'un device/simulateur est disponible :

1. **Matériel de test** : 3 clips vidéo courts (5-10s) sources, un par orientation de capture native
   — (a) tournée en paysage (`preferredTransform` proche de l'identité), (b) tournée en portrait
   (rotation native 90°), (c) tournée en portrait inversé (rotation native 270°). Une source par cas
   suffit : le point sensible est la COMBINAISON `preferredTransform` source × `rotationDegrees`
   utilisateur, pas chaque cas isolément.
2. **Pour chaque clip, sur Android ET iOS** : importer dans `MediaTrim`/`MediaTrimView`, exporter 5
   fois — sans rotation (0°), puis avec 1/2/3/4 appuis sur "Pivoter" (90°/180°/270°/retour à 0°) —
   et une 6ᵉ fois avec le miroir horizontal activé seul (0° + flip), en conservant les fichiers
   exportés (pas seulement l'aperçu, qui n'existait pas côté iOS avant cette phase).
3. **Comparaison** : ouvrir les 6 fichiers exportés (Android et iOS, soit 12 fichiers par clip
   source) dans un lecteur neutre (QuickTime/VLC), à l'écran, côte à côte. Vérifier pour chaque
   paire Android/iOS au même réglage : (a) même orientation visuelle finale (un repère fixe dans le
   cadre — horizon, texte, visage — doit apparaître dans la MÊME orientation) ; (b) même sens du
   miroir (gauche/droite effectivement inversé, pas haut/bas) ; (c) dimensions de sortie
   cohérentes (largeur/hauteur échangées à 90°/270°, pas de bandes noires inattendues) ; (d) le
   flip appliqué APRÈS rotation donne le même résultat composé des deux côtés (tester spécifiquement
   90°+flip, le cas combiné le plus susceptible de révéler un écart d'ordre des opérations).
4. **Verdict** : si les 6×N paires sont visuellement identiques (aux différences de compression/
   codec près, pas d'orientation), `V9-F-004` passe à `FALSE POSITIVE` (le rapport initial l'avait
   correctement laissé `❓`, pas classé bug). Si UNE seule paire diverge, documenter précisément
   laquelle (quel réglage, quelle divergence observée) et reclasser en `CONFIRMED BUG` avec la
   preuve visuelle avant toute correction du code de `composeTransform`.

Ce protocole n'a pas pu être exécuté dans cet environnement (pas de simulateur/device — contrainte
déjà documentée dans `MIGRATION_PROGRESS.md`).

---

## 12 — Phase 2 Validation (2026-09-02, relecture intégrale, pas seulement le diff)

**Méthode** : relecture complète de `MediaTrimView.swift` (683 lignes) et des sites d'appel de
`FeedMediaDownloader.download` dans `FeedView.swift`, sans se limiter au diff Phase 1. Aucune
modification de code effectuée durant cette passe. Légende des verdicts :
`VALIDÉ PAR INSPECTION` (cohérent par lecture/raisonnement du code, non exécuté) ·
`NON TESTÉ SUR DEVICE` (comportement plausible mais dépendant d'une exécution réelle) ·
`NON COMPILÉ` · `À VALIDER SUR DEVICE`.

### ⚠️ Problème trouvé dans les modifications Phase 1 (signalé, PAS corrigé)

**Fichier** : `Sources/TiinverSwift/Feed/MediaTrimView.swift`, fonction `addLoopObserver()`.
**Problème** : le token retourné par `player.addPeriodicTimeObserver(forInterval:queue:using:)`
n'est ni stocké ni retiré via `removeTimeObserver(_:)` — aucun `.onDisappear` ne nettoie
l'observateur explicitement.
**Impact** : par lecture du code, AUCUN cycle de rétention n'est démontrable — `[weak player]`
dans la fermeture empêche que l'observateur retienne `AVPlayer` en retour, et `player` (`@State`)
n'est retenu fortement que par le `@State` de la vue et par `VideoPlayer`/AVKit pendant l'affichage
de l'écran ; sa désallocation à la fermeture de `MediaTrimView` devrait normalement arrêter
l'observateur. **Mais ceci n'est PAS garanti par une preuve statique** — c'est un écart par rapport
à la pratique explicitement recommandée par la documentation Apple (« appelez `removeTimeObserver`
quand vous n'avez plus besoin de l'observateur, par exemple en désallouant un objet qui les
utilise »), et seul un test Instruments réel (Allocations/Leaks, avec ouverture puis fermeture
répétées de `MediaTrim`) peut confirmer avec certitude l'absence de fuite.
**Correction recommandée** (NON appliquée dans cette passe) : stocker le token
(`@State private var loopObserverToken: Any?`) et le retirer explicitement via
`.onDisappear { if let token = loopObserverToken { player?.removeTimeObserver(token) } }`.

### 12.1 — Download success

**Chaîne exacte vérifiée** (`FeedView.swift:941-951` + `FeedMediaDownloader.swift:42-69`, relecture
intégrale des deux fichiers) :

```text
Tap "Télécharger"
 → guard queuedDownloadPostIds.insert(post.id).inserted (anti double-tap, inchangé)
 → Task { do { try await FeedMediaDownloader.download(post) ... } }
 → download(post) : permission .addOnly → résolution URL → download(for:) réseau (200-299)
   → move vers fichier temp → try await PHPhotoLibrary.shared().performChanges { creationRequest... }
 → SI performChanges réussit : download(post) retourne SANS throw
 → downloadSucceeded = true (ligne suivante, AUCUN await intermédiaire)
 → .alert("Téléchargement réussi", isPresented: $downloadSucceeded)
```

**Chemins d'échec vérifiés** :
- Permission refusée : `guard status == .authorized || status == .limited else { throw
  DownloadError.photoLibraryDenied }` — lève AVANT toute activité réseau/fichier → `catch` →
  `downloadError = ...` → `downloadSucceeded` JAMAIS atteint (la ligne qui le positionne est
  textuellement APRÈS le `try await` qui a levé).
- Échec réseau/décodage : `guard ... (200..<300).contains(...) else { throw .networkFailure }` —
  même raisonnement, `catch` intercepte avant `downloadSucceeded = true`.
- Échec `performChanges` (fichier invalide, permission révoquée entre-temps, etc.) : `try await`
  propage l'erreur de `PHPhotoLibrary` telle quelle → même `catch`.

**Isolation MainActor** : `downloadSucceeded = true` s'exécute dans le même `Task {}` créé depuis
la fermeture du bouton (contexte `View`, implicitement `@MainActor` par le protocole `View` lui-même)
— après un `await` sur une fonction non isolée à un acteur spécifique, l'exécution reprend sur
l'acteur D'ORIGINE du `Task` (MainActor), exactement le même raisonnement qui s'applique déjà,
sans qu'il ait jamais été mis en cause, au `downloadError = error.localizedDescription` préexistant
juste à côté.

**Résultat : VALIDÉ PAR INSPECTION.** La chaîne demandée par l'utilisateur correspond exactement au
code : le succès n'est signalé qu'après la sauvegarde RÉELLE dans Photos, jamais au lancement ni à
la seule fin du téléchargement réseau. Les deux chemins d'échec (réseau, permission refusée)
n'atteignent jamais `downloadSucceeded = true`, vérifié par le flux de contrôle `do/catch` lui-même
(pas une supposition). **NON TESTÉ SUR DEVICE** (aucune exécution réelle de `PHPhotoLibrary`/appel
réseau effectuée dans cette session).

### 12.2 — MediaTrim seek

- **Position curseur = position export, vérifié avec le code exact** : `dragGesture` calcule
  `seekFraction * duration` où `seekFraction = isStart ? startFraction : endFraction` — CES DEUX
  variables `@State` (`startFraction`/`endFraction`) sont LITTÉRALEMENT les mêmes lues par `trim()`
  pour construire `timeRange` (`CMTime(seconds: startFraction * duration, ...)`/`CMTime(seconds:
  endFraction * duration, ...)`, lignes 505-506, INCHANGÉES par Phase 1). Aucune variable
  intermédiaire, aucune divergence possible entre ce que montre le seek et ce qu'utilisera
  l'export.
- **Boucle de seek excessive / concurrence entre seeks** : `AVPlayer.seek(to:toleranceBefore:
  toleranceAfter:)` (la variante SANS gestionnaire d'achèvement, celle utilisée ici) annule/
  remplace nativement tout seek précédent encore en attente sur le même lecteur dès qu'un nouveau
  est demandé — comportement documenté d'AVFoundation, pas une supposition. Un glissement rapide
  générant de nombreux évènements `.onChanged` par seconde ne crée donc PAS de file d'attente de
  seeks empilés.
- **Saccades potentielles** : `toleranceBefore: .zero, toleranceAfter: .zero` force un seek
  frame-exact (plus coûteux qu'un seek tolérant, qui pourrait s'accrocher à la trame décodable la
  plus proche). Choix délibéré pour prévisualiser le point de coupe EXACT plutôt qu'une
  approximation — risque de saccade visuelle sur un glissement très rapide, plausible mais non
  mesuré.
- **Conflit avec la lecture automatique** : AUCUN autoplay n'existe dans ce fichier — confirmé par
  recherche exhaustive, zéro appel `.play()` dans tout `MediaTrimView.swift`. La lecture ne démarre
  que si l'utilisateur appuie sur le bouton lecture natif d'AVKit (`VideoPlayer`) — donc "conflit
  avec l'autoplay" est sans objet, rien n'autoplaye.
- **Conflit avec le loop observer** : les deux mécanismes appellent uniquement `.seek(...)` sur le
  même `AVPlayer` — même en cas de chevauchement temporel (fenêtre de 0.1s), le dernier appel
  l'emporte nativement (même raisonnement que ci-dessus), sans état corrompu ni crash possible.

**Résultat : VALIDÉ PAR INSPECTION** pour l'équivalence curseur=export (preuve par lecture directe
du code de `trim()`) et l'absence de conflit structurel. **NON TESTÉ SUR DEVICE** pour la fluidité
réelle (saccades) du seek frame-exact pendant un glissement rapide — à surveiller en priorité lors
du premier test device.

### 12.3 — MediaTrim loop

- **Boucle uniquement entre startFraction et endFraction** : `if time.seconds >= endFraction *
  duration { player.seek(to: CMTime(seconds: startFraction * duration, ...)) }` — ne boucle QUE
  cette fenêtre, jamais 0→duration entière (sauf cas par défaut `startFraction=0, endFraction=1`
  avant toute sélection, où la fenêtre EST la vidéo entière — comportement attendu, pas un bug).
- **Durée correcte** : `duration` est la même variable `@State` chargée une seule fois dans
  `load()`, jamais réassignée ailleurs — source unique, cohérente avec `dragGesture`/`trim()`.
- **start < end garanti ?** Logique de clamp PRÉ-EXISTANTE (V4-F-059, non modifiée par Phase 1) :
  `startFraction` est borné à `endFraction - minHandleSpacing` (ou 0 si ce plancher devient
  négatif), `endFraction` symétriquement borné à `startFraction + minHandleSpacing`. Dans le cas
  limite pathologique (sélection proche de 0 largeur), le clamp peut produire un écart INFÉRIEUR à
  `minHandleSpacing` mais **jamais `start ≥ end`** dans les chemins de code lus — le bouclage ne
  peut donc pas tourner sur une fenêtre inversée ou nulle.
- **start ≈ end** : produit un cycle de lecture très rapide (jouer une fraction de seconde, boucler,
  répéter) — visuellement un scintillement, pas un crash ni un état incohérent. Cas limite hérité
  du réglage `minHandleSpacing` déjà identifié séparément dans le rapport (V9-F-016, non traité par
  cette phase).
- **Déplacement des poignées pendant la lecture** : l'observateur lit `startFraction`/`endFraction`
  À CHAQUE déclenchement (toutes les 0.1s) directement depuis le `@State` partagé — un ajustement
  de poignée en cours de lecture est pris en compte au tick suivant, pas de valeur figée/périmée.
- **Vidéo en pause** : le comportement documenté d'`addPeriodicTimeObserver` est de ne PAS
  redéclencher le bloc périodiquement quand `rate == 0` (lecture à l'arrêt) — donc si l'utilisateur
  positionne manuellement la lecture au-delà de `endFraction` via les contrôles natifs PUIS mets en
  pause exactement là, le rebouclage ne se déclenche qu'à la reprise de la lecture. Comportement
  raisonnable (le bouclage ne s'applique qu'À LA LECTURE, pas comme une barrière dure au scrub
  manuel), pas un bug.
- **Limite exacte** : condition `>=` (pas `>`), donc une correspondance EXACTE déclenche bien le
  rebouclage — pas de trou d'1 tick.
- **Accumulation d'observers / intervalle 0.1s** : un SEUL observateur est jamais enregistré
  (`addLoopObserver()` appelé une seule fois depuis `load()`, lui-même appelé une seule fois par
  `.task {}` — garantie SwiftUI standard, pas de ré-exécution du closure `.task` à chaque
  recomputation de `body`). 10 déclenchements/seconde sur la file principale est un rythme léger et
  courant pour ce type d'UI (barres de progression), sans risque de surcharge CPU/batterie notable.
  **Voir toutefois le problème signalé en tête de §12 concernant le nettoyage explicite de cet
  observateur.**

**Résultat : VALIDÉ PAR INSPECTION** pour la portée du bouclage, la cohérence des valeurs, et
l'absence d'accumulation d'observateurs. **NON TESTÉ SUR DEVICE** pour le rendu réel (fluidité du
rebouclage, absence de flash/saut visuel au point de coupure).

### 12.4 — Rotation preview

Comparaison Android `applyPreview()` (`VideoTrimmerView.java:306-338`, cité dans l'historique
d'audit de ce fichier, non relu ligne à ligne dans CETTE passe) vs iOS `videoPreview` :

- **0°** : `isSideways = false` → `preRotationSize = videoRect.size` (inchangé) →
  `.rotationEffect(.degrees(0))` (no-op). Cohérent, aucune surprise.
- **90°/270°** : `isSideways = true` → `preRotationSize` = dimensions de `videoRect` ÉCHANGÉES.
  Vérification algébrique effectuée dans cette passe (pas seulement visuelle) : `currentPreviewAspect`
  vaut `1/base` pour ces deux angles (`base` = aspect natif pré-rotation) ; `videoRect` est donc
  ajusté à cet aspect inversé ; `preRotationSize` (= `videoRect` avec largeur/hauteur ré-échangées)
  retrouve un aspect ÉGAL à `base` — c'est-à-dire EXACTEMENT l'aspect natif de la vidéo (non
  pivotée) que `VideoPlayer` doit recevoir pour s'ajuster sans bande interne parasite. Après
  rotation de 90°/270°, l'empreinte visuelle (bounding box) redevient celle de `videoRect` — la
  vidéo pivotée tient exactement dans le cadre prévu, sans dépassement ni recadrage involontaire.
  Cohérence mathématique confirmée par le calcul, pas seulement par lecture superficielle.
- **180°** : `isSideways = false` (180 n'est pas dans `{90,270}`) — pas d'échange de dimensions
  (correct, une rotation de 180° NE change PAS la boîte englobante). `.rotationEffect(.degrees(180))`
  retourne le contenu dans le MÊME cadre. Cohérent.

**Distinction explicite Preview vs Export, respectée** : cette vérification porte UNIQUEMENT sur la
cohérence géométrique interne de l'aperçu SwiftUI (`.rotationEffect`/`CGSize`/`GeometryReader`).
Elle NE PERMET AUCUNE conclusion sur la justesse de `composeTransform` (remapping de coordonnées de
texture OpenGL côté Android vs composition de `CGAffineTransform` côté export iOS) — ce dernier
reste strictement `❓ À VALIDER SUR DEVICE`, sujet exclusif de V9-F-004, non rouvert ni influencé
par cette validation de la preview.

**Résultat : VALIDÉ PAR INSPECTION** (cohérence algébrique interne de l'aperçu, aux 4 angles).
**NON TESTÉ SUR DEVICE** pour la fidélité visuelle réelle par rapport à Android, ET séparément,
**❓ NON COMPILÉ / À VALIDER SUR DEVICE** pour `composeTransform` (export), sans lien de dépendance
avec ce résultat de preview.

### 12.5 — Flip preview

**Constat préalable, vérifié directement dans `VideoTrimState.swift`** : `flippedVertically`
**N'EXISTE PAS** dans ce projet, ni côté modèle d'état iOS, ni comme contrôle Android — confirmé par
lecture intégrale du fichier (`struct VideoTrimState`, seule propriété de miroir :
`flippedHorizontally`) et cohérent avec l'historique d'audit déjà consigné dans l'en-tête de
`MediaTrimView.swift` (`btnFlip` documenté comme "miroir horizontal" uniquement, jamais un miroir
vertical, sur les 3 cycles d'audit antérieurs ayant lu `VideoTrimmerView.java` en entier). **Les
combinaisons "flip vertical" et "horizontal + vertical" demandées par l'utilisateur sont donc SANS
OBJET — pas un manque côté iOS, une fonctionnalité qui n'existe pas non plus côté Android sur cet
écran.** Seuls "aucun flip" et "flip horizontal" sont des cas réels à vérifier.

- **Aucun flip** : `.scaleEffect(x: 1, y: 1)` — no-op, image inchangée.
- **Flip horizontal** : `.scaleEffect(x: -1, y: 1)` — miroir sur l'axe X, appliqué APRÈS
  `.rotationEffect` dans la chaîne de modificateurs SwiftUI.
- **Ordre flip/rotation cohérent avec l'export, vérifié algébriquement** : dans `composeTransform`,
  `transform.concatenating(pivotRotation).concatenating(pivotFlip)` — la convention de composition
  `CGAffineTransform.concatenating` applique la transformation de GAUCHE en premier (rotation),
  celle de DROITE ensuite (flip), donc rotation PUIS flip dans l'espace déjà pivoté. Côté preview,
  la chaîne de modificateurs SwiftUI `.rotationEffect(...).scaleEffect(...)` applique elle aussi la
  rotation en premier (modificateur le plus interne) et le flip en second (modificateur englobant,
  opérant sur le résultat déjà pivoté) — MÊME ordre de composition des deux côtés. Vérifié pour le
  cas combiné 90°+flip explicitement (le cas le plus susceptible de révéler un écart d'ordre).
- **Le flip ne détruit pas le cadrage** : `.scaleEffect` ne modifie PAS la taille de mise en page
  rapportée par une vue (seule une transformation VISUELLE, centrée) — le `.frame(width:height:)`
  déjà appliqué et le `.position(...)` qui suit restent valides après le flip, aucun recalcul de
  taille nécessaire ni observé.

**Résultat : VALIDÉ PAR INSPECTION** pour l'ordre de composition (cohérence structurelle preview/
export) et l'absence d'impact sur le cadrage. **NON APPLICABLE** pour le flip vertical (n'existe
sur aucune des deux plateformes). **NON TESTÉ SUR DEVICE** pour le rendu visuel réel du miroir
combiné à une rotation.

### 12.6 — Fit-to-screen

- **Aspect ratio vidéo vs conteneur** : `videoRect = letterboxedRect(in: geo.size, aspect:
  currentPreviewAspect)` — fonction PRÉEXISTANTE (V5-F-038, non modifiée), déjà validée pour
  `cropOverlay` avant cette phase, réutilisée telle quelle pour `videoPreview` — pas de nouvelle
  logique de letterboxing inventée, réutilisation d'un calcul déjà en production.
- **`.fit` vs `.fill`** : `VideoPlayer` (AVKit) utilise son mode par défaut `.resizeAspect`
  (ajustement proportionnel, PAS de remplissage/recadrage) — aucun mode `.resizeAspectFill`
  explicitement configuré nulle part dans le fichier. Cohérent avec l'intention "aperçu fidèle",
  pas un recadrage forcé.
- **Crop involontaire** : aucun `.clipped()`/`.aspectRatio(contentMode: .fill)` appliqué au
  `VideoPlayer` lui-même dans `videoPreview` — le SEUL rectangle de recadrage visible reste
  `cropOverlay`, un calque de sélection UTILISATEUR distinct et inchangé, pas un effet de bord de
  ce correctif.
- **Bandes noires** : `Color.black` en fond du `ZStack` fournit le letterboxing hors de `videoRect`
  — cohérent avec le traitement standard d'un aperçu vidéo letterboxé.
- **Rotation 90°/270° / flip / combinaison** : couverts en détail en §12.4/§12.5 ci-dessus.

**Résultat : VALIDÉ PAR INSPECTION.** **NON TESTÉ SUR DEVICE** pour le rendu pixel réel.

### 12.7 — Isolation preview/export

**Confirmation demandée par l'utilisateur, avec le code exact.** `videoPreview` (la nouvelle
propriété calculée) ne LIT que `player`, `trimState`, `orientedVideoAspect`, et (indirectement, via
`Self.letterboxedRect`) la taille du conteneur SwiftUI — elle n'ÉCRIT jamais dans `startFraction`,
`endFraction`, `rotationDegrees`, `flippedHorizontally`, ni aucun état lu par `trim()`/
`composeTransform`. Les seules ÉCRITURES ajoutées par Phase 1 sont : (a) `player?.seek(...)` dans
`dragGesture` — mute la POSITION DE LECTURE de l'`AVPlayer`, une propriété runtime de l'objet
`AVPlayer` lui-même, complètement disjointe de tout `@State` lu par l'export ; (b)
`player.seek(...)` dans `addLoopObserver` — même nature, même absence de lien avec l'export.

`trim()` et `composeTransform` (lignes 480-652, INTÉGRALEMENT relues dans cette passe, zéro octet
modifié par Phase 1 — confirmé par comparaison caractère pour caractère avec la version
pré-Phase 1 déjà vérifiée) lisent `startFraction`, `endFraction`, `trimState`, et
`sourceURL`/`asset` — TOUJOURS le fichier source ORIGINAL (`AVURLAsset(url: sourceURL)`, ligne 503,
jamais une référence dérivée de l'aperçu). Aucun chemin de données n'existe entre les calculs
géométriques locaux de `videoPreview` (`videoRect`, `preRotationSize`, tous des `let` locaux à la
`View`, jamais stockés dans `@State`) et l'export.

**Résultat : VALIDÉ PAR INSPECTION, confirmé par relecture caractère pour caractère de `trim()`/
`composeTransform` (inchangés) et par l'absence de toute écriture croisée entre `videoPreview` et
l'état lu par l'export.**

### 12.8 — Compilation

**Compilation non exécutée — environnement Windows sans Xcode.** Aucun mécanisme CI accessible
sans commit/push n'est disponible dans cette session (le seul pipeline CI de ce dépôt,
`ios-build.yml` sur GitHub Actions, se déclenche sur push — explicitement exclu par la consigne de
cette phase). Aucun environnement macOS local n'est présent. La validation ci-dessus est
STATIQUE UNIQUEMENT (relecture, cohérence structurelle, raisonnement algébrique) — elle NE
CONSTITUE PAS une preuve de compilation et ne doit pas être interprétée comme telle. Aucune ligne
de code n'a été modifiée dans le seul but de prévenir une erreur hypothétique de compilation.

### 12.9 — Tests device restant à effectuer

1. Nettoyage de l'observateur de bouclage (§ problème signalé en tête de §12) — test Instruments
   Allocations/Leaks, ouvrir/fermer `MediaTrim` plusieurs fois de suite.
2. Fluidité du seek frame-exact pendant un glissement rapide des poignées (§12.2) — saccades
   possibles, tolérance zéro délibérément choisie.
3. Rendu réel du rebouclage dans la sélection (§12.3) — absence de flash/saut visuel perceptible.
4. Fidélité visuelle de la rotation/du miroir en aperçu par rapport au rendu Android réel (§12.4/
   §12.5) — comparaison écran à écran, pas seulement la cohérence algébrique déjà vérifiée.
5. Le protocole complet rotation/flip à l'EXPORT (§11.4, `composeTransform`/`V9-F-004`) — distinct
   des points 4 ci-dessus, jamais exécuté, reste la question ouverte la plus importante du dossier
   MediaTrim.
6. Chaîne `Download → succès` en conditions réelles (réseau, `PHPhotoLibrary` réel) — §12.1 n'a été
   validée que par lecture du flux de contrôle, jamais exécutée.

---

## 13 — Correction lifecycle MediaTrim observer (2026-09-02)

**Problème** : `addLoopObserver()` appelait `player.addPeriodicTimeObserver(...)` sans jamais
conserver le token retourné ni appeler `removeTimeObserver(_:)` — identifié en §12, non corrigé à
l'époque (signalé, puis arrêt demandé).

**Cause** : oubli lors de l'ajout initial de l'observateur en Phase 1 — le token retourné par
`addPeriodicTimeObserver` était jeté (résultat de l'appel jamais assigné), rendant tout retrait
explicite impossible.

**Correction appliquée** : trois changements, strictement scopés au cycle de vie de cet unique
observateur, aucune autre fonctionnalité touchée :
1. Nouvel état `@State private var loopObserverToken: Any?`.
2. `addLoopObserver()` stocke désormais le token (`loopObserverToken = player.
   addPeriodicTimeObserver(...)`) au lieu de l'ignorer. La fonction ne retire plus rien
   elle-même — elle suppose que l'appelant a déjà nettoyé l'éventuel ancien token (voir point 3).
3. `load()` retire l'observateur de l'ANCIEN `player` **avant** de le remplacer
   (`if let token = loopObserverToken { player?.removeTimeObserver(token); loopObserverToken =
   nil }`, placé juste avant `player = AVPlayer(url: sourceURL)`) — respecte l'ordre exact demandé
   (ancien observer → removeTimeObserver → nouveau player → addPeriodicTimeObserver → stocker
   nouveau token), correct que `load()` soit appelée une ou plusieurs fois. Un `.onDisappear` sur
   le `NavigationStack` (dans `body`) retire l'observateur restant à la fermeture de l'écran
   (annulation, validation réussie, ou tout autre chemin de sortie), avec la même garde
   token-non-nil et la même remise à `nil` après retrait pour éviter un double retrait.

**Vérification des 14 exigences de la demande** :
1. Un seul observer actif par player — ✅ un seul site d'ajout (`addLoopObserver`), toujours
   précédé d'un retrait si un token préexistait.
2. Token conservé — ✅ `loopObserverToken`.
3. Retiré quand `MediaTrim` n'en a plus besoin — ✅ `.onDisappear`.
4. Ancien retiré avant nouveau si `load()` rappelée — ✅ ordre explicite dans `load()`, avant
   `player = AVPlayer(...)`.
5. Aucun retrait avec token invalide — ✅ le retrait dans `load()` cible encore l'ANCIEN `player`
   (pas réassigné avant ce retrait) ; le retrait dans `.onDisappear` cible le seul `player` qui ait
   jamais existé pour cette vue (jamais réassigné après `load()`) ; `loopObserverToken = nil` après
   chaque retrait empêche toute double tentative sur le même token.
6. Aucun crash si `player == nil` — ✅ `player?.removeTimeObserver(token)`, chaînage optionnel.
7. Aucun retain cycle inutile — ✅ `[weak player]` conservé dans la fermeture de l'observateur
   (inchangé).
8. Comportement du loop `[startFraction, endFraction]` strictement identique — ✅ le corps de la
   fermeture de l'observateur (la logique de bouclage elle-même) n'a pas été modifié, seul son
   point d'ATTACHEMENT/retrait a changé.
9. Intervalle 0.1s inchangé — ✅.
10-14. Seek, `videoPreview`, `composeTransform`, `trim()`, pipeline d'export — ✅ aucun touché,
   confirmé par `grep` ciblé sur le diff final (aucune occurrence dans les fonctions concernées
   au-delà des commentaires déjà présents).

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/MediaTrimView.swift` uniquement (+39 lignes par
rapport à l'état post-Phase 1 : 1 nouvel état, 1 `.onDisappear`, le retrait dans `load()`, le
stockage du token dans `addLoopObserver()`, commentaires).

**Validation effectuée** : relecture intégrale du fichier après modification ; confirmé par `grep`
qu'un seul `addPeriodicTimeObserver` réel existe dans le fichier (ligne 459) et exactement deux
`removeTimeObserver` réels (`.onDisappear` ligne 176, `load()` ligne 417) ; confirmé qu'aucun autre
`addPeriodicTimeObserver` non géré n'existe ; confirmé par recherche exhaustive l'absence de tout
terme lié au filigrane/outro/premium/musique/`.m3u8` dans le diff ; confirmé par diff ciblé que
`trim()`/`composeTransform`/le mécanisme de seek/`videoPreview` (au-delà des commentaires) sont
inchangés par cette correction précise.

**Compilation** : **Compilation non exécutée — environnement Windows sans Xcode.** Aucun mécanisme
CI accessible sans commit/push dans cette session ; aucun environnement macOS local disponible.

---

## 14 — CI GitHub / Build iOS (2026-09-02)

### 14.1 — Workflow GitHub Actions identifié

**Un seul fichier** dans `.github/workflows/` (confirmé par `git log --all --diff-filter=A` sur ce
chemin — jamais eu de second fichier, ni ajouté ni supprimé) :

| Aspect | Valeur |
|---|---|
| Fichier | `.github/workflows/ios-build.yml` |
| Nom | `iOS build (compilation seule — Checkpoint)` |
| Déclenchement | `workflow_dispatch: {}` **UNIQUEMENT** — aucun `push`, aucun `pull_request` |
| Machine | `macos-14` (runner GitHub hébergé) |
| Version Xcode | **Non fixée** — sélectionne dynamiquement la plus récente installée sur le runner (`ls -d /Applications/Xcode_*.app \| sort -V \| tail -1`, puis `xcode-select -s`) |
| Méthode de build | `xcodebuild build` (compilation directe, PAS `archive`) |
| Scheme | `TiinverSwift` |
| Projet | `TiinverSwift.xcodeproj` — généré à chaque run via `xcodegen generate` depuis `project.yml` (non committé tel quel) |
| Configuration | Non spécifiée explicitement (`xcodebuild build` sans `-configuration` → Debug par défaut) |
| Destination | `generic/platform=iOS Simulator` |
| Signing | **Désactivé explicitement** (`CODE_SIGNING_ALLOWED=NO`) — aucun certificat, aucun profil de provisionnement utilisé par ce workflow |
| Secrets | `GOOGLE_SERVICE_INFO_PLIST_BASE64` (Firebase, requis — le run échoue immédiatement si absent) |
| Services externes | XcodeGen (Homebrew), Firebase (fichier décodé depuis le secret) |

**Objectif du workflow, tel que documenté dans son propre en-tête** : valider uniquement que le
code Swift écrit sur cette machine Windows (jamais compilé localement) compile réellement — pas un
pipeline de déploiement.

**Second mécanisme CI existant, DISTINCT, non GitHub Actions** : `codemagic.yaml` (racine du dépôt,
1045 lignes) — un service tiers, Codemagic, avec 4 workflows nommés : `checkpoint-build`
(équivalent fonctionnel de `ios-build.yml`), `visual-smoke-test`, `browserstack-ipa-build`, et
`ios-testflight` (signature + publication App Store Connect réelles). **Ce sont ces 2 derniers noms
qui apparaissent dans l'historique `git log` évoqué par l'utilisateur** — ce ne sont PAS des
workflows GitHub Actions distincts (aucun fichier `.yml` correspondant n'a jamais existé sous
`.github/workflows/`, confirmé), mais des sections nommées à l'intérieur de ce fichier Codemagic
unique. Cette section §14 se concentre sur `ios-build.yml` (GitHub Actions) conformément à la
demande ; `codemagic.yaml` n'a pas été audité en détail (hors périmètre demandé).

### 14.2 — Derniers runs GitHub Actions (`ios-build.yml`)

Consultés via l'API GitHub (`GET /repos/SalimMedir/TiinverSwift/actions/workflows/ios-build.yml/runs`) :

| Run ID | Commit | Statut | Résultat | Déclenché | Terminé | Durée |
|---|---|---|---|---|---|---|
| **33629326816** | `9e9b96e` | completed | **success** | 2026-09-02 12:19:57 UTC | 12:28:25 UTC | ~8 min 28s |
| 33613778839 | `834d88b` | completed | success | 2026-09-02 09:22:47 UTC | — | — |
| 33569407291 | `e0b26bd` | completed | success | 2026-09-01 23:05:38 UTC | — | — |

Les 3 derniers runs consultés sont tous `success`, tous déclenchés via l'événement
`workflow_dispatch` (confirmé champ `"event"` de l'API — pas de push/PR déclencheur, cohérent avec
la configuration `on:` du fichier). **Aucune erreur** à signaler sur ces runs. Version Xcode
précise non extraite des logs dans cette passe (tentative de téléchargement des logs bruts trop
lente/hors budget de cette vérification — sans conséquence : le workflow sélectionne toujours la
plus récente disponible sur le runner, une valeur qui varie avec l'image GitHub Actions plutôt
qu'un numéro figé à comparer).

### 14.3 — Déclenchement manuel possible sans push

**OUI** — `workflow_dispatch: {}` est le SEUL déclencheur configuré, donc CHAQUE run de ce workflow
a toujours été manuel par nature (jamais de build automatique sur push). Le déclenchement se fait
via l'API GitHub (`POST /repos/{owner}/{repo}/actions/workflows/ios-build.yml/dispatches` avec
`{"ref":"main"}`) — mécanisme utilisé identiquement pour les 3 runs listés ci-dessus, et pour
chaque validation CI de toute cette session (V5-F-072 à la dernière en date, `9e9b96e`).

**Point déterminant, PAS ambigu** : `workflow_dispatch` construit TOUJOURS à partir de la référence
Git indiquée (`ref: "main"`, c'est-à-dire l'état de la branche `main` **sur GitHub**, `origin/main`)
— **jamais** depuis l'arborescence de travail locale. Déclencher ce workflow maintenant
reconstruirait donc exactement le même commit `9e9b96e` déjà validé (run 33629326816 ci-dessus),
**sans tester une seule ligne des corrections Phase 1/Phase 2/§13** — ce serait une confirmation
redondante d'un état déjà connu, pas une validation nouvelle. **Ce déclenchement n'a donc PAS été
effectué dans cette passe** : il n'apporterait aucune information supplémentaire tant que les
modifications actuelles ne sont pas poussées sur GitHub (voir §14.4/§14.6), et la consigne de cette
tâche demande explicitement de ne rien pousser sans autorisation.

### 14.4 — État du commit actuel

```
git status --short
 M Sources/TiinverSwift/Feed/FeedView.swift
 M Sources/TiinverSwift/Feed/MediaTrimView.swift
?? MIGRATION_PARITY_AUDIT_V9.md

git rev-parse HEAD
9e9b96e389a29a0de1134d4173773c930e5e736b

git rev-parse origin/main
9e9b96e389a29a0de1134d4173773c930e5e736b

HEAD == origin/main : OUI, identiques.

git diff --stat
 Sources/TiinverSwift/Feed/FeedView.swift      |  19 +++-
 Sources/TiinverSwift/Feed/MediaTrimView.swift | 119 ++++++++++++++++++++++++--
 2 files changed, 131 insertions(+), 7 deletions(-)
```

**⚠️ Confirmation explicite demandée par l'utilisateur** : les modifications Phase 1, Phase 2 (aucune
modification de code, validation uniquement) et §13 (correction du cycle de vie de l'observateur)
sont actuellement **UNIQUEMENT dans l'arborescence de travail locale (working tree), NON commitées,
NON présentes sur GitHub**. Le dernier build GitHub réussi (run 33629326816, commit `9e9b96e`) **NE
VALIDE PAS** ces modifications — il valide l'état du dépôt tel qu'il était AVANT que la moindre
ligne de la Phase 1 ne soit écrite. **Aucun build GitHub n'a, à ce jour, jamais compilé le code
contenant le feedback de succès du téléchargement, l'aperçu vidéo live de MediaTrim, ou la
correction du cycle de vie de l'observateur.**

### 14.5 — Version iOS

| Clé | Valeur | Source |
|---|---|---|
| `MARKETING_VERSION` (→ `CFBundleShortVersionString`) | `"1.0.0"` | `project.yml:422`, `settings: base:` |
| `CURRENT_PROJECT_VERSION` (→ `CFBundleVersion`) | `"1000"` | `project.yml:421`, `settings: base:` |

**Ces deux valeurs sont explicitement documentées dans `project.yml` lui-même comme TEMPORAIRES**
(commentaire ligne 418-420 : *"TEMPORAIRE : "1000"/"1.0.0" à remettre à une valeur réelle
cohérente avant soumission App Store"*) — pas des valeurs de production réelles, un stub de
développement en attendant une décision de versioning explicite.

**Dernier build utilisé sur App Store Connect** : **information NON accessible depuis cet
environnement** — aucun identifiant/token App Store Connect n'est configuré dans cette session (à
la différence du token GitHub, disponible via `git credential fill`). Je ne peux ni confirmer ni
infirmer si le build `1000` a déjà été soumis, ni quel serait le prochain numéro valide côté Apple.
Ne pas supposer une valeur ici.

**Progression Apple** : Apple exige un `CFBundleVersion` strictement croissant pour chaque nouvel
upload d'une même `CFBundleShortVersionString` vers App Store Connect. Puisque `CURRENT_PROJECT_VERSION`
est une chaîne LITTÉRALE FIXE (`"1000"`) dans `project.yml` — **aucun mécanisme d'auto-incrément
par build n'existe dans ce projet** (confirmé par lecture de `project.yml` et de `ios-build.yml` :
aucune substitution dynamique de cette valeur nulle part) — tout upload RÉEL vers App Store Connect
(via `codemagic.yaml`'s `ios-testflight`, hors périmètre GitHub Actions de cette section) devrait
soit incrémenter manuellement cette valeur avant publication, soit s'appuyer sur un mécanisme
d'auto-incrément propre à Codemagic non vérifié ici. **Aucune version n'a été modifiée dans cette
passe**, conformément à la consigne.

### 14.6 — Pourquoi les sessions précédentes ont pu obtenir un build GitHub, et pourquoi pas celle-ci

**Chaîne exacte** :

```text
Working tree actuel (Phase 1 + Phase 2 + §13, 131 lignes non commitées)
        ↓  ❌ PAS de commit créé (consigne explicite : "aucun commit")
commit local = 9e9b96e (inchangé depuis avant Phase 1)
        ↓  ❌ PAS de push effectué (consigne explicite : "aucun push")
commit GitHub actuel (origin/main) = 9e9b96e (identique au commit local — confirmé §14.4)
        ↓  workflow_dispatch({"ref":"main"}) construit TOUJOURS depuis origin/main
workflow GitHub Actions (ios-build.yml)
        ↓
build obtenu = validation du commit 9e9b96e UNIQUEMENT (run 33629326816, déjà connu, déjà success)
```

**Ce n'est ni un oubli ni une limitation technique** : dans TOUTES les sessions précédentes de ce
cycle (V5-F-072 à `9e9b96e` inclus), la séquence suivie était systématiquement `commit → push →
workflow_dispatch → poll jusqu'à complétion` — exactement le mécanisme décrit en §14.3, utilisé
avec succès à répétition tout au long de cette même conversation. **La seule différence pour
Phase 1/Phase 2/§13 est une instruction explicite et répétée de l'utilisateur : "aucun commit,
aucun push"**, respectée à la lettre à chaque étape. Le mécanisme de CI n'a pas changé, n'a pas
cessé de fonctionner, et n'a rien de différent d'une session à l'autre — il n'a simplement pas été
INVOQUÉ, par choix, parce que son invocation aurait nécessité l'étape (commit+push) explicitement
exclue.

**Ce qu'il faut faire pour reproduire la procédure et obtenir un vrai build CI des modifications
actuelles** :
1. Committer les 2 fichiers modifiés (`FeedView.swift`, `MediaTrimView.swift`) — et, si souhaité,
   `MIGRATION_PARITY_AUDIT_V9.md`.
2. Pousser ce commit vers `origin/main`.
3. Déclencher `workflow_dispatch` sur `ios-build.yml` (même mécanisme qu'en §14.3).
4. Attendre la complétion (`status: completed`) et lire `conclusion` (`success`/`failure`).

**Aucune de ces 4 étapes n'a été effectuée dans cette session** — conformément à la consigne
explicite de ne rien commiter ni pousser sans autorisation. J'attends cette autorisation avant
d'entreprendre l'étape 1.
