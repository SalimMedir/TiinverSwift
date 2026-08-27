# PHYSICAL_DEVICE_VALIDATION_V5.md

Suivi des bugs trouvés par **test réel sur appareil physique** (2026-08-27), distincts des
findings `MIGRATION_PARITY_AUDIT_V5.md` (audit de code statique). Ne PAS fusionner avec V5 :
périmètre différent (preuve = capture d'écran réelle, pas lecture de code seule), voir
`CLAUDE_CONTINUATION.md` pour le contexte complet de la bascule de phase.

Règle absolue de cette phase : **NE SUPPOSE PAS**. Android = référence comportementale, code =
source de vérité. Cycle par bug : capture → code iOS → code Android → comparaison → cause racine
→ correctif minimal → diff vérifié → commit → push → déclenchement CI → attente résultat réel →
sur ÉCHEC, corriger/commit/push/re-déclencher → validé UNIQUEMENT après un run CI VERT réel.
Jamais plusieurs correctifs non validés empilés.

## Statut global (2026-08-27) — les 8 bugs

Les 8 bugs sont tous `CODE_COMPLETE` + `BUILD_VALIDATED` par le run CI groupé final
[33062002222](https://github.com/SalimMedir/TiinverSwift/actions/runs/33062002222) (SUCCESS).
Aucun n'est encore `COMPLETE_PARITY_VALIDATED` — cela nécessite un vrai test sur appareil
physique, qui n'a pas eu lieu depuis ces correctifs (aucun simulateur/appareil disponible dans
cet environnement de développement).

| Bug | Statut | Commit(s) |
|---|---|---|
| 1 — Grille Home vignettes invisibles | BUILD_VALIDATED | `eaecb9c` |
| 2/3 — Plein écran boutons absents + mauvaise échelle | BUILD_VALIDATED | `0225267` |
| 4 — Carrousel suggestions absent | DÉJÀ_CORRECT (aucun code changé) | — |
| 5 — Puces IA manquantes | BUILD_VALIDATED | `f42453b` |
| 6/7 — Barre du bas absente + timeline hauteur fixe | BUILD_VALIDATED | `a5723c4` |
| 8 — Play n'anime pas | BUILD_VALIDATED | `e13ea4f` |

## Inventaire des captures (12 fichiers, dossier fourni par l'utilisateur)

Dossier : `C:\Users\helen\OneDrive\Pictures\photo\Product hunt\ios-example\`

| Fichier | Plateforme | Bug(s) documenté(s) |
|---|---|---|
| `home-feed-grid.png` | iOS | BUG 1 (vignettes grille Home invisibles) |
| `android-home.png` | Android | Référence BUG 1 (vignettes OK) + BUG 4 (carrousel suggestions) |
| `fullscreen-feed.png` | iOS | BUG 2 (boutons d'action absents) |
| `fullscreen-feed2.png` | iOS | BUG 2 (confirmation) + BUG 3 (image en petit rectangle centré, marges noires/beiges) |
| `android-feed-fullscreen.png` | Android | Référence BUG 2/3 (cœur/commentaire/partage/"...", avatar/nom/date/"S'abonner") |
| `ai screen.png` | iOS | BUG 5 (assistant IA sans puces de suggestion) |
| `android-Ai-page.png` | Android | Référence BUG 5 ("Questions fréquentes" + "Générer une image", 9 puces) |
| `android-animemes.jpg` | Android | Référence BUG 6/7 (barre du bas complète, pistes qui grandissent avec les calques) |
| `android-animemes.png` | Android | Référence BUG 6 (état vide : Generate with AI/Compose/Load compose/Modèle/supprimer/réinitialiser/chronologie) |
| `animemes-menu en bas abscent.png` | iOS | BUG 6 (barre du bas quasi entièrement absente, overlay debug visible) |
| `animemes-timeline.track-ne-grandi-pas-comme-sur-android.png` | iOS | BUG 7 (hauteur de piste fixe, 1 calque) |
| `animemes.click.play-pas de animation.png` | iOS | BUG 7 (confirmation, 2 calques, même hauteur fixe) + BUG 8 (Play appuyé, canvas figé) |

## BUG 1 — Grille Home : vignettes invisibles

**Statut : CODE_COMPLETE, CI_VALIDATED — en attente de confirmation visuelle sur appareil
physique (PAS encore `COMPLETE_PARITY_VALIDATED`)**

**Problème observé** (`home-feed-grid.png`) : la grille 2 colonnes de l'accueil affiche
correctement le nom d'utilisateur et les compteurs like/commentaire/partage de chaque post, mais
la zone vignette (photo ou 1ʳᵉ image vidéo) reste un dégradé plat gris clair → gris foncé — aucun
contenu photo/vidéo visible, y compris dans la moitié haute de la cellule où le `LinearGradient`
de légende est `.clear` (donc l'image, si chargée, y serait visible sans obstruction). Confirmé
sur un post SANS icône "play" (donc probablement une photo) ET sur un post AVEC icône "play"
(vidéo) — le bug touche les deux types de contenu, pas seulement les vidéos.

**Comportement Android** (`android-home.png`) : même endpoint `feedtimeline/{userId}/{limit}/
{offset}` (`ActivityRepository.java:134`, vérifié — port iOS identique, `FeedRepository.
fetchTimeline`), vignettes réelles affichées correctement (photo Tom & Jerry, image abstraite,
etc.).

**Comportement iOS** : `Sources/TiinverSwift/Feed/FeedView.swift`, `FeedGridCell` — vignette
chargée via `CDNAsyncImage(url: post.thumbnailURL, ...)`, jamais rendue.

**Investigation menée (aucune cause de code trouvée)** :
- Endpoint : `feedtimeline/{userId}/{limit}/{offset}` (3 segments) — vérifié IDENTIQUE à
  `ActivityRepository.java:134` (Android, Home). L'endpoint Profil (`feedtimeline/{actor}/
  {viewerId}/{limit}/{offset}`, 4 segments) est un endpoint RÉELLEMENT différent
  (`uploadPerfilPhoto/ProfileRepository.java:153`), pas une erreur de portage.
- Modèle : `FeedActivity` (`Feed/FeedActivity.swift`) partagé à 100% entre Home et Profil, même
  `init(from decoder:)`, mêmes clés JSON (`object_url`/`cdn_content_id`/`cdn_content_url`/
  `cdn_thumbnail_url`). `thumbnailURL` (computed) identique dans les deux contextes.
- Rendu : `CDNAsyncImage` (`Media/CDNAsyncImage.swift`) — même en-tête `Referer` CDN déjà
  validé app-entière (2026-08-17). `FeedGridCell` utilise la variante `(AsyncImagePhase) ->
  Content` (pattern standard, valide).
- Dimensionnement : `ZStack` de `FeedGridCell` porte `.aspectRatio(0.8, contentMode: .fill)
  .clipped()` (ligne 567-568) — mécanisme standard SwiftUI (LazyVGrid propose une largeur fixe,
  hauteur `nil`, l'aspectRatio calcule la hauteur manquante) : la capture confirme d'ailleurs que
  la cellule a bien la bonne taille (dégradé visible sur toute la hauteur attendue), donc ce
  N'EST PAS un problème de taille/aspect ratio.
- Comparaison avec `ProfileView.postCell` (grille Profil, qui fonctionne côté utilisateur) :
  même `CDNAsyncImage`, même modèle, aucune différence structurelle trouvée qui expliquerait un
  échec systématique côté Home uniquement.

**Diagnostic temporaire (commit `9c3194d`, CI [33054200758](https://github.com/SalimMedir/TiinverSwift/actions/runs/33054200758) SUCCESS)** — retiré au commit suivant, remplacé par la
cause racine réelle ci-dessous, fournie par l'utilisateur à partir du JSON réel de l'API (pas du
diagnostic sur écran, qui n'a pas eu besoin d'être observé).

**Cause racine confirmée (2026-08-27)** : `FeedActivity.thumbnailURL` (`Feed/FeedActivity.swift:
104-118`) — propriété **partagée à 100 % entre Home et Profil** (même modèle, même code, aucune
divergence Home-vs-Profil au niveau du code lui-même). Pour une activité PHOTO
(`!isVideo`), l'ancienne branche déléguait à `effectiveObjectURLString` (port de
`getObject_url()`, conçue pour la PRIORITÉ de lecture vidéo, réutilisée à tort ici) :
```swift
hasContentId ? (cdn_content_url ?? object_url) : object_url
```
— qui IGNORE `cdn_content_url` (la vraie image) dès que `cdn_content_id` est absent/`"NULL"`/vide
sur l'activité, retombant alors sur `object_url` brut. JSON réel confirmé par l'utilisateur :
pour `object == "photos"`, `cdn_content_url` contient TOUJOURS l'image réelle (que
`cdn_content_id` soit renseigné ou non), alors que `cdn_thumbnail_url` peut valoir un simple hôte
nu `"https://cdn.tiinver.com/"` (jamais une vraie vignette) — et n'était déjà, vérification
faite, JAMAIS lu pour une photo (contrairement à l'hypothèse initiale). Le vrai défaut est le
GATE sur `cdn_content_id`, pas une confusion `cdn_thumbnail_url`/`cdn_content_url`. Cette logique
étant partagée, l'asymétrie Home-cassé/Profil-fonctionnel s'explique par une différence de
FORME DE DONNÉES entre les 2 endpoints backend réels (`feedtimeline/{userId}/{limit}/{offset}`
générique pour Home vs `feedtimeline/{actor}/{viewerId}/{limit}/{offset}` personnalisé pour
Profil), pas par un chemin de code différent.

**Correctif appliqué** : la branche photo utilise désormais `cdn_content_url` directement, sans
condition sur `cdn_content_id`, avec repli sur `object_url` uniquement si `cdn_content_url` est
absent/vide. Branche vidéo (`cdn_thumbnail_url` prioritaire), `effectiveObjectURLString`/
`playbackURL` (lecture plein écran) et téléchargement (`FeedMediaDownloader`) intacts, non
modifiés.

**Fichier(s) modifié(s)** : `Sources/TiinverSwift/Feed/FeedActivity.swift` (`thumbnailURL`,
branche photo). `FeedView.swift` restauré à l'identique d'avant le diagnostic temporaire.

**Commit** : `eaecb9c`
**CI run** : [33055972824](https://github.com/SalimMedir/TiinverSwift/actions/runs/33055972824) — SUCCESS (2026-08-27)
**Résultat** : build vert confirmé. `CODE_COMPLETE`, PAS encore `COMPLETE_PARITY_VALIDATED` —
nécessite une nouvelle capture d'écran réelle de la grille Home pour confirmer visuellement que
les vignettes s'affichent désormais (aucun accès simulateur/débogueur sur cette machine pour le
vérifier autrement).

**RETEST RÉEL (2026-08-27, après-midi) — PROBLÈME TOUJOURS PRÉSENT** : nouvelle capture
(`home-grid-feed-minuature-affiche-pas-les-media.png`) confirme que la grille Home affiche
toujours 4 posts (`Tiinver`/`RodrigueZibi`/`Bale`/`Bale`, AUCUN sans icône "play" visible → posts
PHOTO) avec vignette toujours vide, malgré le correctif ci-dessus déjà vert en CI. Capture de
référence fournie en parallèle (`feed-profile-working-good.png`, profil `@IssaMahamat`) montre un
grille Profil fonctionnelle — mais avec des posts qui ont TOUS une icône "play" (donc des VIDÉOS,
pas des photos) : ne prouve PAS que les photos fonctionnent côté Profil non plus, seulement que
les vidéos fonctionnent des deux côtés. La logique de sélection d'URL (`thumbnailURL`) a été
revérifiée ligne par ligne et respecte maintenant exactement la règle demandée — un 2ᵉ correctif
de LOGIQUE n'aurait rien à corriger de plus à ce niveau. Nouvelle hypothèse, non encore
confirmée : les champs `cdn_content_url`/`object_url`/`cdn_content_id` pourraient être ABSENTS ou
VIDES dans la réponse JSON RÉELLE de CET endpoint précis (`feedtimeline/{userId}/{limit}/
{offset}`, générique) — indifférent à la logique de sélection côté client, quelle qu'elle soit.

**Diagnostic ajouté (PAS un correctif)** : `FeedViewModel.fetchPage()` imprime désormais, pour
chaque page reçue (6 premiers items), une ligne `THUMBNAIL DEBUG: id=... object=... isVideo=...
cdn_content_id=... cdn_content_url=... cdn_thumbnail_url=... object_url=...
resolvedThumbnailURL=...` — consultable directement dans la console Xcode (build Debug lancé
depuis Xcode) SANS nécessiter de nouvelle capture d'écran. Permettra de confirmer/infirmer
l'hypothèse ci-dessus au prochain lancement de l'app.

**Fichier(s) modifié(s) (ce tour)** : `Sources/TiinverSwift/Feed/FeedViewModel.swift`
(`fetchPage()`, diagnostic console uniquement, aucune logique changée).

**Commit** : `f00c857`
**CI run** : [33064960546](https://github.com/SalimMedir/TiinverSwift/actions/runs/33064960546) — SUCCESS (2026-08-27)
**Statut** : `BLOQUÉ_EN_INVESTIGATION` — cause exacte non confirmable sans lire la console Xcode
réelle de l'utilisateur (ou une nouvelle capture s'il n'a pas accès à la console). PAS un
correctif à ce tour, juste l'instrumentation pour trancher entre logique-encore-fausse (peu
probable, revérifiée) et données-absentes-côté-serveur-pour-cet-endpoint (hypothèse actuelle).

**Vérification externe réelle (2026-08-27, `curl` direct sur le CDN, en dehors de l'app)** —
l'utilisateur a fourni le JSON réel des 2 endpoints (Home ET Profil, via Postman). Le JSON Home
contient bel et bien un `cdn_content_url` complet et valide pour chaque photo (ex. `Bale`,
id=13199 : `https://cdn.tiinver.com/tiinver/photos/NDg0NjUxNzIx.webp`). Testé directement :
```
curl (sans Referer)                              → HTTP 403 Forbidden
curl -H "Referer: https://tiinver.com" (identique à CDNAsyncImage) → HTTP 200, image/webp, 44809 octets
```
Même résultat sur un avatar de profil (même domaine `cdn.tiinver.com`). En-têtes `Cache-Control`
vérifiés en plus : le 403 est explicitement `no-cache, no-store, max-age=0` (ne peut PAS rester
bloqué en cache local), le 200 est `public, max-age=2592000` (mis en cache légitimement après
succès). **Conclusion** : serveur CDN, en-tête `Referer`, et logique de sélection d'URL
(`thumbnailURL`) sont TOUS LES TROIS vérifiés corrects, en dehors de toute exécution de l'app —
le code sur `main` devrait charger cette image sans problème. Aucune preuve que l'app exécutée
par l'utilisateur reflète bien ce code (build non à jour non exclu).

**Diagnostic renforcé (toujours PAS un correctif)** : le print console seul supposait un accès à
Xcode non confirmé par l'utilisateur. Remplacé/complété par un bandeau AFFICHÉ DIRECTEMENT À
L'ÉCRAN (`FeedView.thumbnailDiagnosticsBanner`, fond rouge, au-dessus de la grille Home), listant
pour chaque post : `object`/`cdn_content_url`/`object_url`/URL résolue — visible sans Xcode, sans
nouvelle capture d'écran nécessaire pour le lire (il suffit de rouvrir l'onglet Accueil).

**Fichier(s) modifié(s) (ce tour)** : `Sources/TiinverSwift/Feed/FeedViewModel.swift`
(`thumbnailDiagnostics` publié), `Sources/TiinverSwift/Feed/FeedView.swift`
(`thumbnailDiagnosticsBanner`).

**Commit** : `2718c89`
**CI run** : [33069822759](https://github.com/SalimMedir/TiinverSwift/actions/runs/33069822759) — SUCCESS (2026-08-27)
**Statut** : `BLOQUÉ_EN_INVESTIGATION` — en attente que l'utilisateur rouvre l'app et lise le
bandeau rouge en haut de l'Accueil, pour confirmer si l'app reçoit bien les mêmes valeurs que le
JSON vérifié manuellement, ou si le build testé est simplement en retard sur `main`.

---

## BUG 2 — Plein écran : boutons d'action absents
## BUG 3 — Plein écran : mise à l'échelle incorrecte

**Statut : CODE_COMPLETE — MÊME CAUSE RACINE, fusionnés (voir règle de fusion)**

**Découverte clé** : `FeedDetailCell` (`FeedView.swift:850-989`, la cellule du pager plein écran
partagée par Home/Profil/Recherche/Hashtag/Notifications/liens profonds — un seul composant,
`FeedDetailPagerView`) possédait DÉJÀ tout ce que Bug 2 décrivait comme absent : rail
like/commentaire/partage/"..." (`actionRail`, lignes 980-989), avatar+pseudo+date+bouton
"S'abonner" (lignes 901-966), légende cliquable. Rien n'était réellement manquant côté
fonctionnalité métier — donc PAS une implémentation à construire, mais un bug d'AFFICHAGE qui
cache une UI déjà câblée.

**Cause racine réelle** (`FeedView.swift:668-699`, `FeedDetailPagerView.body`) : le pager
vertical est simulé via le contournement standard SwiftUI "`TabView` horizontal tourné à 90°"
(`TabView` n'a pas de style de pagination vertical natif). Le pattern correct : le CONTENEUR
`TabView` reçoit un frame ÉCHANGÉ (largeur/hauteur inversées) avant sa propre rotation +90°, MAIS
chaque PAGE À L'INTÉRIEUR doit recevoir ses dimensions RÉELLES (`geo.size`, non échangées) avant
sa rotation -90° individuelle. Le code reprenait par erreur le MÊME frame échangé pour les pages
individuelles ET pour le conteneur (`.frame(width: geo.size.height, height: geo.size.width)` aux
deux endroits) — chaque page se disposait donc dans une boîte paysage (dimensions de l'écran
inversées) au lieu du vrai portrait. Conséquences directement observables : (BUG 3) l'image/vidéo
se limitait à cette boîte mal dimensionnée, rendue en petit rectangle centré avec de grandes
marges ; (BUG 2) le rail d'actions et le bloc avatar/nom, positionnés par `Spacer()`/`.padding()`
relatifs à cette même boîte erronée, se retrouvaient hors de la zone effectivement rendue à
l'écran.

**Comportement Android** (`android-feed-fullscreen.png`) : plein écran vertical réel
(`ViewPager2` natif, pas de contournement de rotation nécessaire), cœur/commentaire/partage/"..."
+ avatar/nom/date/"S'abonner" tous visibles — confirme qu'iOS DEVAIT afficher exactement ce que
`FeedDetailCell` construit déjà, une fois le frame corrigé.

**Correctif appliqué** : un seul frame corrigé, ligne 689 — `.frame(width: geo.size.height,
height: geo.size.width)` → `.frame(width: geo.size.width, height: geo.size.height)` (dimensions
réelles, non échangées) sur CHAQUE page avant sa rotation -90°. Le conteneur `TabView` externe
(ligne 697, échangé + rotation +90° + offset) reste inchangé — vérifié correct par comparaison
avec le pattern de référence de ce contournement. Recherche exhaustive (`grep rotationEffect`) :
un seul site dans tout le projet utilise ce contournement — aucun autre pager vertical à corriger
séparément.

**Fichier(s) modifié(s)** : `Sources/TiinverSwift/Feed/FeedView.swift`
(`FeedDetailPagerView.body`, une seule ligne de frame).

**Commit** : `0225267`
**CI run** : [33062002222](https://github.com/SalimMedir/TiinverSwift/actions/runs/33062002222) — SUCCESS (2026-08-27, build groupé final des 8 bugs)
**Résultat** : `BUILD_VALIDATED` (compile réellement, run CI vert confirmé). NON confirmé
visuellement (aucun accès simulateur/appareil sur cette machine) — nécessite encore une
validation physique finale groupée.

**RETEST RÉEL (2026-08-27, après-midi) — SURCORRECTION DÉTECTÉE** : nouvelles captures
(`fullscreen-is-outscreen.png`, `fullscreen-button-outscreen.png`) montrent le contenu qui remplit
maintenant correctement l'écran (fini le petit rectangle centré), MAIS le rail d'actions
(cœur/commentaire/partage/"..." — "15"/"1"/"2" visibles, coupés à droite) ET le bouton
"S'abonner" (visible tronqué "...onner" en bas) débordent maintenant SOUS le bord réel de
l'écran. Cause du 2ᵉ défaut : `.rotationEffect` ne modifie JAMAIS la taille de layout qu'une vue
remonte à son parent (seulement son rendu visuel) — le 1ᵉʳ correctif n'ajoutait qu'UN SEUL
`.frame()`, AVANT la rotation, aux dimensions réelles (nécessaire pour les bonnes proportions du
contenu), mais celui-ci, non affecté par la rotation qui suit, continuait de remonter au
`TabView` un encombrement de layout NON échangé (portrait) alors que le conteneur réserve un
encombrement ÉCHANGÉ (paysage) — d'où le débordement. Pattern complet de ce contournement : DEUX
`.frame()` par page (un avant rotation aux dimensions réelles, un second APRÈS rotation aux
dimensions échangées) — seul ce 2ᵉ frame manquait. Ajouté (`.frame(width: geo.size.height,
height: geo.size.width)` juste après `.rotationEffect(.degrees(-90))`).

**Fichier(s) modifié(s) (ce tour)** : `Sources/TiinverSwift/Feed/FeedView.swift`
(`FeedDetailPagerView.body`, ajout du frame post-rotation).

**Commit** : `f00c857`
**CI run** : [33064960546](https://github.com/SalimMedir/TiinverSwift/actions/runs/33064960546) — SUCCESS (2026-08-27)
**Résultat** : `BUILD_VALIDATED`. NON confirmé visuellement — nécessite un nouveau test physique
pour confirmer que le contenu ET le rail d'actions/bouton "S'abonner" sont maintenant
intégralement visibles à l'écran, sans petit rectangle NI débordement.

## BUG 4 — Accueil : carrousel de comptes suggérés absent

**Statut : DÉJÀ_CORRECT — aucun défaut de code trouvé, pas de modification**

`Sources/TiinverSwift/Feed/SuggestionsCarouselView.swift` + `SuggestionsRepository.swift`
existent déjà et sont ENTIÈREMENT câblés : `FeedView.homeHeader` (ligne 141) instancie
`SuggestionsCarouselView()` en tout premier élément, AVANT la bannière AdMob. Vérifié point par
point contre les 7 exigences : (1) endpoint Android `TransportData.getSuggestionsUsers` = `GET
suggestions/{userId}` (2) modèle `User` réutilisé (3-4) API/composant DÉJÀ existants ET câblés
(5) réutilise `ProfileRepository.follow`/`FeedRepository.notifyPostAuthor`, pas de logique
dupliquée (6) carrousel intégré dans `homeHeader`, au bon endroit, avant la grille (7) Follow réel
avec écho optimiste + rollback (V3-F-107) + notification (V5-F-014). Aucune donnée fictive.
Dernier commit sur ces 2 fichiers : `2026-08-26 14:28`, ANTÉRIEUR à la capture d'écran
(2026-08-27 matin) — le code testé par l'utilisateur incluait donc déjà cette fonctionnalité.

`SuggestionsCarouselView.body` (ligne 22-34) se rétracte ENTIÈREMENT (`Group` vide) si
`users.isEmpty` — comportement DÉLIBÉRÉMENT fidèle à Android (`AdapterSuggestContact`, le
conteneur XML reste visible mais la RecyclerView interne n'a simplement aucune cellule), pas un
bug. L'explication la plus probable du carrousel absent sur la capture (`home-feed-grid.png` :
la bannière AdMob apparaît en tout premier, sans aucun espace au-dessus) est que
`SuggestionsRepository.fetchSuggestions` a retourné un tableau vide pour CE compte précis au
moment du test — pas un défaut de code. Documenté ici plutôt que corrigé sans preuve
(pas de correction spéculative, conformément à la consigne).

## BUG 5 — Assistant IA : puces de suggestion absentes

**Statut : CODE_COMPLETE**

**Problème observé** (`ai screen.png`) : `AIChatView.welcomeState` (état vide, aucun message
envoyé) n'affichait QUE l'icône sparkles + le texte d'accroche — aucune puce de suggestion.

**Comportement Android** (`android-Ai-page.png`, `ai/TiinverGeminiAIChat.java:268-313`,
`setupChips()`, lu en entier) : section "Questions fréquentes" (5 puces : gain de pièces, créer
un Animeme, monétiser le compte, groupe payant, retirer les gains) + section "Générer une image"
(3 puces de prompt + "Améliorer mon image"). Textes exacts tirés de
`res/values-fr/strings.xml:871-879` (`chip_gain_coins` etc.), pas devinés.

**Cause racine** : fonctionnalité jamais portée (`welcomeState` ne contenait que l'état vide de
base) — confirmé absence totale de toute notion de "chip" dans `AIChatView.swift` avant ce
correctif.

**Correctif appliqué** : 8 puces ajoutées à `welcomeState`, texte français exact d'Android. Aucune
NOUVELLE logique métier : les puces "question" réutilisent `viewModel.sendText()` (même chemin
que taper la question et appuyer sur envoyer), les puces "image" réutilisent
`viewModel.generateImage()`, la puce "Améliorer mon image" est un second `PhotosPicker` lié au
MÊME `$pickerItem` déjà câblé dans `inputBar` (fidèle à Android : `chip_improve_image` se contente
d'ouvrir la galerie, aucun prompt n'est pré-rempli automatiquement côté Android non plus, vérifié
dans le handler réel).

**Fichier(s) modifié(s)** : `Sources/TiinverSwift/AI/AIChatView.swift` (`welcomeState` + 5
nouvelles fonctions/propriétés privées, aucun fichier de modèle/viewmodel touché).

**Commit** : `f42453b`
**CI run** : [33062002222](https://github.com/SalimMedir/TiinverSwift/actions/runs/33062002222) — SUCCESS (2026-08-27, build groupé final des 8 bugs)
**Résultat** : `BUILD_VALIDATED`. NON confirmé visuellement.

## BUG 6 — Animems : barre d'outils du bas absente
## BUG 7 — Animems : hauteur de piste de la timeline ne grandit pas

**Statut : CODE_COMPLETE — MÊME CAUSE RACINE, fusionnés (voir règle de fusion)**

**Découverte clé** : `AnimemesEditorView.bottomToolbar` (`AnimemesEditorView.swift:1079-1165`)
existait DÉJÀ, entièrement câblé, avec BEAUCOUP plus que les 8 boutons cités dans le rapport :
Generate with AI (code mort côté Android lui-même, fidèlement reproduit), Compose, Load compose
(différé, grisé), Modèle, masque, propriétés, dupliquer, bezier, fond (suppression d'arrière-
plan), supprimer, réinitialiser, chronologie, undo. Reconstruit lors d'un audit dédié antérieur
(« capture d'écran réelle 2026-08-16 », voir en-tête de fichier) — PAS une fonctionnalité à
construire. L'overlay de debug (`gestureDiagnosticsHUD`) était DÉJÀ gaté `#if DEBUG`
(`AnimemesEditorView.swift:146-153`, corrigé V4-F-055 2026-08-24) — n'apparaît QUE dans un build
Debug (Xcode "Run" direct sur l'appareil), déjà absent de tout build Release/TestFlight ;
aucune action requise pour la « production ».

**Cause racine réelle** : `AnimemesEditorState.syncTimeline()` (`AnimemesEditorState.swift:210`)
fixait `timeline.trackCount = max(5, composer.layers.count)` — un PLANCHER de 5 pistes TOUJOURS
réservé, même avec 0, 1 ou 2 calques réels. `TimelineView.body` (`TimelineView.swift:60,78`)
calcule sa hauteur comme `rulerHeight + trackCount * (trackHeight + trackGap) + 8` — donc figée à
la hauteur de 5 pistes tant que le nombre de calques restait ≤ 5 (BUG 7 : aucune croissance
visible entre 1 et 2 calques). Cette hauteur fixe (~240pt) était réservée dans le `VStack`
NON-scrollable de `AnimemesEditorView.body` (topBar → canevas → barre de lecture → timeline →
`bottomToolbar`), squeezant le canevas (confirmé par le texte de debug de la capture :
`canvasSize=202×360`, anormalement petit) ET poussant `bottomToolbar`, dernier élément du
`VStack`, hors de l'écran visible (BUG 6). `syncTimeline()` n'était de plus appelée qu'APRÈS
chaque ajout/suppression de calque, jamais à l'ouverture de l'éditeur — l'écran vide
(`calques=0`, exactement la capture `animemes-menu en bas abscent.png`) restait donc sur le
défaut de classe `TimelineViewModel.trackCount = 5` (jamais synchronisé) tant qu'aucun calque
n'avait encore été ajouté.

**Comportement Android confirmé** : `AnimemesCompound.java:1744/1781/3606` appellent TOUS
`timelineView.setTrackCount(mView.getComposer().getLayers().size())` — le nombre EXACT de
calques ; `TimelineView.setTrackCount` (`android/views/TimelineView.java:307`) ne clampe qu'à un
PLANCHER de 1 (`Math.max(1, count)`), jamais 5. Le défaut interne `private int trackCount = 5`
(`TimelineView.java:73`) existe aussi côté Android, mais UNIQUEMENT comme valeur de classe avant
tout appel réel — jamais destiné à survivre à l'écran affiché.

**Correctif appliqué** : `syncTimeline()` — `max(5, ...)` → `max(1, composer.layers.count)`
(fidèle à Android). `AnimemesEditorState.init()` appelle désormais `syncTimeline()` (au lieu de
seulement `timeline.layers = composer.layers`), pour que `trackCount` soit correct (`1`) dès
l'ouverture de l'éditeur plutôt que de dépendre du défaut de classe non synchronisé. AUCUN
nouveau bouton créé — le toolbar existant est déjà complet et déjà audité contre de vraies
captures Android.

**Fichier(s) modifié(s)** : `Sources/TiinverSwift/Animems/AnimemesEditorState.swift`
(`syncTimeline()`, `init()`).

**Commit** : `a5723c4`
**CI run** : [33062002222](https://github.com/SalimMedir/TiinverSwift/actions/runs/33062002222) — SUCCESS (2026-08-27, build groupé final des 8 bugs)
**Résultat** : `BUILD_VALIDATED`. NON confirmé visuellement. Point nécessitant une validation
physique : confirmer que `bottomToolbar` est bien visible ET que la timeline grandit visiblement
avec 2+ calques sur un appareil réel — la logique de hauteur est vérifiée algébriquement mais pas
testée à l'écran (aucun simulateur/appareil disponible dans cet environnement).

## BUG 8 — Animems : le bouton Play n'anime pas le canvas

**Statut : CODE_COMPLETE**

**Problème observé** (`animemes.click.play-pas de animation.png`) : bouton Play visible et
apparemment fonctionnel (icône), mais le canevas reste figé.

**Pipeline tracé en entier** (aucune supposition) : Play → `AnimemesEditorState.togglePlayback()`
(`:899`) → `preparePlayback()` + `engine.play(composer:layer: 0)` → `AnimationEngine.play()`
(`:158`, garde `!composer.layers.isEmpty`) → `startPlayback()` (`:178`) → crée un vrai
`CADisplayLink` (`:183-189`, pas un timer factice) → `tick(composer:layer:timestamp:)` (`:202`,
appelé ~60×/s par le displaylink) → **ICI, cause racine** : `guard !composer.layers[layer]
.transforms.isEmpty else { return }` — retour IMMÉDIAT, `totalFrame` jamais incrémenté,
`isPlaying` jamais mis à `true` (l'affectation est À L'INTÉRIEUR de la boucle jamais atteinte),
tant que `composer.layers[0].transforms` est vide. En aval (jamais atteint dans ce cas) : le reste
du pipeline (interpolation clé/image, `LayerRenderer`, invalidation `@Published`/`renderVersion`,
`Canvas` de `AnimemesEditorView.canvasArea`) est correctement câblé — vérifié en lisant le
délégué `AnimationEnginePlaybackDelegate` (`AnimemesEditorState.swift:1199-1216`) : `didPlayFrame`
met à jour `timeline.playheadFrame` + `isPlaying` + `bumpRenderVersion()`, tous `@Published`,
observés par SwiftUI. Le problème n'est PAS un timer non démarré, ni un déclenchement UI cassé,
ni un moteur non observé — c'est un retour anticipé qui empêche TOUT le reste de s'exécuter.

**Pourquoi `transforms` est vide** : `autoCaptureEnabled` (case "Capture automatique") vaut
`false` par défaut (`AnimemesEditorState.swift:78`) ; `dragEnded()` (`:437-440`) n'enregistre une
keyframe QUE si cette case est cochée. Un simple glissement au doigt (capture d'écran "DRAG at
(...) → calque #0 déplacé") ne peuple donc `transforms` d'AUCUN calque sans elle.

**Cause racine réelle et divergence Android assumée** : `layer: 0` est TOUJOURS le paramètre
utilisé côté iOS (`togglePlayback`, `:904`). Côté Android (`AnimationEngine.java:200-207`, MÊME
garde `if (tfm.isEmpty()) return;`), la valeur RÉELLE de `layer` transmise par `MemesView2.play()`
(`:1948-1951`) n'est PAS un choix délibéré de « calque principal » : `layer` est un simple champ
MUTÉ COMME EFFET DE BORD de la dernière boucle de dessin (`seekDraw`/`playPreview`,
`MemesView2.java:794/832`, `layer = i` à chaque calque bitmap/forme dessiné) — sa valeur au
moment du tap sur Play dépend donc de l'ordre/type des calques dessinés juste avant, pas d'une
intention. Bloquer l'avancement GLOBAL de `totalFrame` (qui pilote déjà TOUS les calques via
`transformationArray`, construit calque par calque dans `prepareFrame`, indépendamment de
`layer`) sur les seuls `transforms` d'UN calque arbitraire est contraire à l'intention
fonctionnelle réelle — PAS un comportement Android intentionnel à reproduire (conformément à la
consigne explicite de ne pas copier aveuglément un bug/effet de bord Android).

**Correctif appliqué** : retrait de la garde `layer < composer.layers.count` /
`!transforms.isEmpty` dans `AnimationEngine.tick()` — l'avancement de `totalFrame` ne dépend plus
que de `totalFramesMinus1` (déjà calculé sur TOUS les calques par `prepare()`), plus de la
présence de données sur un calque arbitraire. La seule garde réellement significative
(`!composer.layers.isEmpty`) reste dans `play()`, inchangée. Aucun comportement forcé/inventé —
si AUCUN calque n'a de keyframe, `totalFramesMinus1` reste à 0 et Play n'a toujours rien à animer
(comportement correct : rien à animer = rien ne bouge), mais dès qu'UN calque a des données
(quel que soit son index), Play les anime désormais réellement.

**Fichier(s) modifié(s)** : `Sources/TiinverSwift/Animems/AnimationEngine.swift` (`tick(composer:
layer:timestamp:)`).

**Commit** : `e13ea4f`
**CI run** : [33062002222](https://github.com/SalimMedir/TiinverSwift/actions/runs/33062002222) — SUCCESS (2026-08-27, build groupé final des 8 bugs)
**Résultat** : `BUILD_VALIDATED`. NON confirmé visuellement. Point nécessitant une validation
physique : confirmer qu'un calque avec des keyframes RÉELLEMENT enregistrées (case "Capture
automatique" cochée, ou keyframe posée via le bouton ◆/propriétés) s'anime bien au Play. Un
calque SANS aucune keyframe n'a, par design (Android et iOS), rien à animer — pas un bug distinct.
