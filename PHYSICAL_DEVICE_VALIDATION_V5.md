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

**Statut : NON DÉMARRÉ**

## BUG 3 — Plein écran : mise à l'échelle incorrecte

**Statut : NON DÉMARRÉ**

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
