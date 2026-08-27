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

**Commit** : (à renseigner, build CI unique en fin de lot)
**CI run** : en attente (build complet groupé en fin des 8 bugs, sur demande explicite)
**Résultat** : NON confirmé visuellement (aucun accès simulateur/appareil sur cette machine) —
`CODE_COMPLETE`, nécessitera une validation physique finale groupée avec les autres bugs.

## BUG 4 — Accueil : carrousel de comptes suggérés absent

**Statut : NON DÉMARRÉ** — note : `Sources/TiinverSwift/Feed/SuggestionsCarouselView.swift` et
`SuggestionsRepository.swift` existent déjà dans le projet ; à vérifier s'ils sont simplement
non câblés dans `FeedView.homeHeader` avant de construire quoi que ce soit de nouveau.

## BUG 5 — Assistant IA : puces de suggestion absentes

**Statut : NON DÉMARRÉ**

## BUG 6 — Animems : barre d'outils du bas absente

**Statut : NON DÉMARRÉ**

## BUG 7 — Animems : hauteur de piste de la timeline ne grandit pas

**Statut : NON DÉMARRÉ**

## BUG 8 — Animems : le bouton Play n'anime pas le canvas

**Statut : NON DÉMARRÉ**
