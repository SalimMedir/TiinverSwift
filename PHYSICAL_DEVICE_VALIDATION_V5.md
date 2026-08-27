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

**Statut : DIAGNOSTIC_EN_COURS (diagnostic temporaire déployé, CI_PENDING)**

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

**Cause racine** : NON IDENTIFIÉE avec certitude par lecture de code seule (pas d'environnement
macOS/simulateur/débogueur disponible sur cette machine pour observer `AsyncImagePhase` en
temps réel). Deux hypothèses restent ouvertes, non tranchées :
1. `post.thumbnailURL` retourne `nil` pour ces posts précis (branche `else` jamais visible
   auparavant faute d'instrumentation).
2. `CDNAsyncImage.load()` échoue silencieusement (réseau ou décodage) — `phase == .failure`
   jamais affiché auparavant (la fermeture `content` originale ignorait ce cas, `EmptyView()`
   implicite).

**Correctif appliqué (diagnostic, PAS le correctif final)** : `FeedGridCell` affiche désormais
visiblement soit le message d'erreur réel de `AsyncImagePhase.failure` (fond rouge), soit les
valeurs brutes `object`/`isVideo`/`cdn_content_id`/`object_url` quand `thumbnailURL` est `nil`
(fond orange) — permet de trancher entre les 2 hypothèses ci-dessus sur la PROCHAINE capture
d'écran réelle, plutôt que de deviner un correctif.

**Fichier(s) modifié(s)** : `Sources/TiinverSwift/Feed/FeedView.swift` (`FeedGridCell.body`).

**Commit** : (à renseigner après commit)
**CI run** : (à renseigner après déclenchement)
**Résultat** : en attente
**Prochaine étape** : une fois la CI verte, demander à l'utilisateur de rouvrir l'onglet Accueil
sur l'appareil physique et de fournir une nouvelle capture — le texte de diagnostic affiché sur
chaque vignette cassée donnera la cause racine exacte, permettant alors le vrai correctif ciblé.

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
