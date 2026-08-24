# MIGRATION PARITY AUDIT V4

**Cycle indépendant** — ne remplace ni n'écrase `MIGRATION_PARITY_AUDIT_V1.md`/`V2`/`V3`. Numérotation
de findings propre (`V4-F-xxx`), sans réutiliser les IDs V1/V2/V3. Objectif explicite de ce cycle :
trouver ce qui a échappé aux audits précédents, pas re-vérifier ce qu'ils ont déjà couvert.

**Phase actuelle : AUDIT UNIQUEMENT (Phase A). Aucun code n'a été modifié pour produire ce document.**
Aucune Phase B n'a été lancée. Voir `MIGRATION_PARITY_PROGRESS_V4.md`.

**Méthode** : 16 agents de recherche indépendants (lecture directe du code Android
`C:\Users\helen\AndroidStudioProjects\tiinver\` et iOS `C:\Users\helen\iOSProjects\TiinverSwift\`,
AUCUNE lecture des audits V1/V2/V3 ni du contenu de ce cycle par les agents entre eux), un par
domaine, avec pour consigne explicite de tracer la chaîne complète UI→ViewModel→Repository→réseau/
socket→parsing→state→rendu, de vérifier l'accessibilité RÉELLE (pas seulement la présence de code),
et de ne jamais porter du code Android mort/inutilisé/expérimental. Deux domaines (le bug de paiement
photo de profil, le gap "signaler un groupe", l'absence d'Extension de partage iOS, et l'écart
d'analytics de visionnage) ont été **découverts indépendamment par deux agents distincts** — fusionnés
ci-dessous en un seul finding avec double preuve, un signal de fiabilité fort.

**Classification utilisée** (exclusive par finding) : MISSING · PARTIAL · FUNCTIONALLY_FAILED ·
VISUALLY_DIFFERENT · CODE_PRESENT_UNVERIFIED · BUILD_VALIDATED · COMPLETE_PARITY_CANDIDATE ·
IOS_INTENTIONAL_DIFFERENCE · ANDROID_DEAD_CODE · DUPLICATE · BACKEND_BLOCKED · DEVICE_TEST_REQUIRED.

**Rappel obligatoire** : "le code compile"/"la classe existe"/"CI verte" ne sont PAS des preuves de
parité fonctionnelle. Aucun finding ci-dessous n'a été testé sur device réel — tout est basé sur
lecture de code des deux côtés, avec citations fichier:ligne vérifiées.

---

## 0. Statistiques

- **Total findings** : 75 (V4-F-001 à V4-F-075), plus 2 confirmations "code mort Android, aucune
  action requise" (non comptées comme gaps) et 1 note architecturale informative (Animems GL/Metal).
- **MISSING** : 19
- **PARTIAL** : 25
- **FUNCTIONALLY_FAILED** : 19
- **VISUALLY_DIFFERENT** : 7
- **CODE_PRESENT_UNVERIFIED** : 1
- **IOS_INTENTIONAL_DIFFERENCE** : 3
- **DEVICE_TEST_REQUIRED** : 1
- **BUILD_VALIDATED** : 0 (aucun code modifié ce cycle — Phase A uniquement)
- **COMPLETE_PARITY_CANDIDATE** : 0
- **ANDROID_DEAD_CODE** (findings formels) : 0 (2 confirmations informelles, voir §9)
- **P0** : 3 — **P1** : 25 — **P2** : 32 — **P3** : 15

---

## 1. Session / Authentification

```
ID : V4-F-001
PRIORITÉ : P1
DOMAINE : Session-Auth
FEATURE : Cold start bloqué derrière un fetch réseau Firebase Remote Config, contrairement à Android
ANDROID SOURCE : SplashActivity.java:80-91,98-122 ; setting/FirebaseConfigManager.java:37-56,145-154
IOS FILES : Navigation/RootRouterView.swift:31-60,111-148 ; Settings/FirebaseConfigManager.swift:27-29
ANDROID BEHAVIOR : `navigateAfterConfig` décide Home/Login de façon SYNCHRONE à partir du cache Remote
Config local (zéro I/O réseau) ET de `SessionManager.getUser()` (lecture SharedPreferences
synchrone) ; `fetchAndActivate()` n'est appelé qu'APRÈS la navigation, pour la PROCHAINE ouverture.
IOS BEHAVIOR : `RootRouterView` affiche un `ProgressView()` tant que `!configChecked` ; `configChecked`
n'est mis à `true` qu'APRÈS un `await fetchAndActivate()` réel (réseau), sans timeout ni repli sur
cache. Sur réseau lent/absent, l'écran racine (Home ET Login) reste bloqué jusqu'à ~60s (timeout SDK).
DIFFÉRENCE : Android ne bloque jamais la décision Home/Login sur un appel réseau ; iOS bloque
l'écran racine entier derrière un fetch Remote Config attendu.
IMPACT : Un utilisateur déjà connecté avec une session locale valide reste sur un spinner vide
jusqu'à 60s sur réseau dégradé/absent, alors qu'Android atteindrait Home instantanément.
PREUVE : `RootRouterView.swift:35` ; `checkForceUpdate()` (lignes 111-148) attend `fetchAndActivate()`
avant de lever `configChecked` ; `FirebaseConfigManager.swift:27-29` sans paramètre timeout.
RECOMMANDATION : Découpler la lecture Remote Config (cache local, synchrone) de la décision Home/
Login ; lancer `fetchAndActivate()` en arrière-plan pour la prochaine ouverture, comme Android.
STATUT : BUILD_VALIDATED (2026-08-24, commit d7d50b0, CI run 32679885732 succès). Reconfirmé côté
Android (`SplashActivity.java:80-122`, entier) : `getExpireDay()`/etc. lisent le cache LOCAL du SDK
Remote Config (défauts XML au 1er lancement via `setDefaultsAsync`, appliqués SYNCHRONEMENT malgré
le nom, ou valeurs du dernier fetch réussi), ZÉRO I/O réseau. `config.fetchAndActivate()` appelé
SEULEMENT après la navigation, jamais attendu. Corrigé : `checkForceUpdate()` ne fait plus `_ = await
...fetchAndActivate()` avant de lire `expireDay`/`expireMonth`/`expireYear` — `RemoteConfig.
setDefaults(fromPlist:)` (iOS) est le même mécanisme synchrone qu'Android, la lecture cache
fonctionne identiquement sans attendre un fetch. `fetchAndActivate()` désormais lancé dans un `Task`
en arrière-plan APRÈS `configChecked = true`, fidèle à `config.fetchAndActivate()` (sans listener)
d'Android. `grep fetchAndActivate` → un seul site d'appel dans tout le projet, celui corrigé — aucun
autre gap. DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED (couper le réseau au lancement avec
une session locale valide déjà présente, confirmer l'arrivée quasi-instantanée sur Home au lieu d'un
spinner jusqu'à 60s).
```

```
ID : V4-F-002
PRIORITÉ : P1
DOMAINE : Navigation-DeepLinks
FEATURE : Deep link résolu avant le montage de HomeShellView est silencieusement perdu
ANDROID SOURCE : partage/ShareActivity.java:140-291
IOS FILES : Navigation/DeepLinkCenter.swift:44-51 ; Navigation/HomeShellView.swift:52,190-205
ANDROID BEHAVIOR : `ShareActivity` résout puis lance directement l'écran cible (`startActivity`),
sans dépendre qu'une autre Activity soit déjà à l'écran et à l'écoute.
IOS BEHAVIOR : `DeepLinkRouter` résout de façon asynchrone puis appelle `DeepLinkCenter.shared.
route(...)`, qui met juste à jour `@Published var pending`. Le SEUL consommateur est `HomeShellView.
onChange(of: deepLinks.pending)` — qui ne se déclenche QUE sur une transition nil→valeur pendant que
la vue est déjà montée, jamais pour une valeur déjà présente à l'attachement du modificateur.
DIFFÉRENCE : Si `pending` est déjà positionné AVANT le montage de `HomeShellView` (cold start, écran
de login, fenêtre de blocage V4-F-001), `.onChange` ne se déclenche jamais et `consume()` n'est
jamais appelé — le deep link est perdu silencieusement, sans erreur, sans indication.
IMPACT : Tout deep link tapé pendant le cold start ou avant authentification a une chance réelle et
reproductible d'être avalé silencieusement.
PREUVE : `HomeShellView.swift:190-191`, seul site de consommation dans tout le projet (grep confirmé) ;
aucun `.onAppear`/`.task` de repli pour drainer une valeur déjà en attente.
RECOMMANDATION : Ajouter un `.task`/`.onAppear` dans `HomeShellView` qui appelle `deepLinks.consume()`
dès le premier rendu, en plus du `.onChange` existant.
STATUT : BUILD_VALIDATED (2026-08-24, commit 97f87fd, CI run 32680432322 succès). Reconfirmé :
`HomeShellView` reste le SEUL consommateur de `DeepLinkCenter.shared.pending` dans tout le projet
(`grep DeepLinkCenter` — plusieurs PRODUCTEURs dans `AppDelegate`/`DeepLinkRouter`, un seul
consommateur). Corrigé exactement comme recommandé : la table de dispatch de destinations extraite
en `handleDeepLink(_:)` partagée, appelée à la fois par le `.onChange` existant (inchangé) ET par le
`.task` déjà présent (ajout d'une consommation au montage). `DeepLinkCenter.consume()`'s `defer {
pending = nil }` rend les deux appels sûrs (le second, si atteint, est un no-op sur `pending == nil`).
DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED (taper un lien profond [notification push ou URL
`tiinver://`/`https://tiinver.com/...`] PENDANT le cold start ou l'écran de login, avant toute
authentification, puis confirmer qu'il est bien consommé une fois `HomeShellView` monté après
connexion — scénario impossible à reproduire de façon fiable sans device réel et un lien réellement
reçu pendant cette fenêtre précise).
```

```
ID : V4-F-003
PRIORITÉ : P1
DOMAINE : Navigation-DeepLinks
FEATURE : Aucun vrai Universal Link (Associated Domains) — les liens `https://tiinver.com/...` réels
ne peuvent pas ouvrir l'app depuis l'extérieur
ANDROID SOURCE : AndroidManifest.xml:206-243 (`autoVerify="true"`, host `tiinver.com`)
IOS FILES : project.yml:206-223 (schémas `myapp`/`tiinver` uniquement) ; aucun fichier `.entitlements`
ANDROID BEHAVIOR : App Link vérifié — tout lien `https://tiinver.com/user|post|group|...` tapé
depuis SMS/WhatsApp/email/navigateur ouvre directement Tiinver.
IOS BEHAVIOR : Seuls les schémas privés `myapp://`/`tiinver://` sont déclarés ; aucune entitlement
Associated Domains n'existe. `DeepLinkRouter.handle` accepte techniquement `https`/`http`, mais rien
côté OS ne route un vrai lien `https://tiinver.com/...` vers l'app sans AASA hébergé.
DIFFÉRENCE : La surface de partage de contenu réelle d'Android (`https://tiinver.com/...`, générée
partout par le backend/l'app) est pratiquement inatteignable sur iOS.
IMPACT : Tout lien de partage généré côté Android/backend échouera à ouvrir l'app iOS — ouvrira
Safari à la place.
PREUVE : `project.yml:219-223` ; aucune entitlement `applinks:` trouvée ; `DeepLinkRouter.swift:4-9`
documente déjà cette limitation comme connue.
RECOMMANDATION : Nécessite un travail hors dépôt (héberger `apple-app-site-association`) + ajout de
l'entitlement Associated Domains — décision produit/serveur, le code de routage est prêt.

STATUT : BLOQUÉ — hors dépôt, AUCUNE action de code possible dans cet environnement (2026-08-24).
Finding confirmé réel (pas une hypothèse) : `project.yml:206-223` ne déclare que les schémas privés
`myapp`/`tiinver` ; `grep applinks:` dans tout le dépôt → 0 résultat ; aucun fichier
`.entitlements` n'existe. `DeepLinkRouter.swift:4-9` documente déjà cette limitation comme connue.
**Ce finding est en réalité une REDÉCOUVERTE indépendante de `V3-F-078` (DEEPLINK-01,
`MIGRATION_PARITY_AUDIT_V3.md`)** — même cause racine identifiée par le cycle V3, déjà documentée
`BLOCKED` à l'époque, jamais corrigée depuis car la correction elle-même nécessite, dans cet ordre :
1. Ajouter l'entitlement `com.apple.developer.associated-domains` (`applinks:tiinver.com`) au
   projet — SANS EFFET tant que (2) n'est pas fait, et RISQUE RÉEL de faire ÉCHOUER la
   signature/CI si la capability "Associated Domains" n'est pas d'abord activée pour cet App ID
   dans le portail développeur Apple (le profil de provisioning rejette un entitlement non couvert
   par la capability correspondante — erreur de signature, pas un avertissement silencieux).
2. Activer la capability "Associated Domains" pour l'App ID `com.tiinver...` dans le portail
   développeur Apple — décision de compte développeur, hors accès de cet environnement.
3. Héberger un fichier `apple-app-site-association` (AASA) signé/servi correctement (Content-Type
   `application/json`, SANS extension de fichier, HTTPS valide) à
   `https://tiinver.com/.well-known/apple-app-site-association` — décision serveur/infra, hors
   dépôt iOS, hors accès de cet environnement.
Ajouter l'entitlement SEUL (étape 1 sans 2 et 3) créerait un risque réel de casser la CI actuelle
(verte sur tous les lots précédents) pour un gain fonctionnel NUL tant que les étapes serveur ne
sont pas faites — contraire à la consigne de ne jamais introduire de régression. Conformément à la
règle de Phase B ("si un finding s'avère... nécessiter une action hors du périmètre atteignable,
ne pas modifier le code — documenter pourquoi"), AUCUN code n'a été modifié pour ce finding. Le
code de routage lui-même (`DeepLinkRouter`/`DeepLinkCenter`) est déjà prêt et fonctionnel pour les
schémas privés `myapp://`/`tiinver://`, confirmé par les lots V4-F-002 (Phase B P1, ce même cycle)
qui l'ont déjà exercé et corrigé pour son propre gap (consommation au montage). Aucun commit de
code, aucune CI dispatchée pour ce finding (rien à builder). DEVICE_TEST_REQUIRED sans objet — ce
finding restera `BLOQUÉ` jusqu'à ce que l'utilisateur/l'équipe serveur réalise les 3 étapes
ci-dessus hors de ce dépôt et de cette session.
```

```
ID : V4-F-004
PRIORITÉ : P2
DOMAINE : Navigation-DeepLinks / Social
FEATURE : Aucune Extension de partage iOS — impossible de partager une image DEPUIS une autre app
VERS Tiinver (doublon confirmé, trouvé indépendamment par 2 agents)
ANDROID SOURCE : AndroidManifest.xml:209-233 (intent-filters SEND/SEND_MULTIPLE) ; partage/
ShareActivity.java:74-121,336-357 ; view/SendToFragment.java
IOS FILES : AUCUN — aucun target Share Extension, aucun `.appex`/`NSExtension` dans tout le projet
ANDROID BEHAVIOR : Tiinver est une cible de partage système — une image partagée depuis Photos/une
autre app arrive dans `ShareActivity`, qui affiche `SendToFragment` (liste de conversations, multi-
sélection) pour la transférer directement dans un chat/groupe Tiinver.
IOS BEHAVIOR : Capacité entièrement absente — pas de target Xcode, pas de code.
DIFFÉRENCE : Un module Xcode entier (Share Extension), pas seulement du code Swift manquant.
IMPACT : Les utilisateurs iOS ne peuvent pas partager une photo depuis une autre app directement
dans une conversation Tiinver.
PREUVE : `AndroidManifest.xml:210-233` ; recherche exhaustive iOS = zéro résultat pour extension/
appex/ShareExtension. Note : le `text/plain`/`SEND_MULTIPLE` d'Android sont eux-mêmes des no-op/
stubs non fonctionnels — seul le cas image simple est un vrai gap à porter.
RECOMMANDATION : Scoper un target Share Extension dédié réutilisant le picker de conversation déjà
existant (`ContactPickerView` mode browse).

STATUT : BLOQUÉ (2026-08-24, Phase B P2, Lot P2-1) — pas une simple modification de code, un module
Xcode entier (target App Extension). Vérifié avant de conclure : la session (`UserSession`) est
stockée via `KeychainStore` (`Sources/TiinverSwift/Security/KeychainStore.swift`), SANS groupe
d'accès Keychain partagé (`kSecAttrAccessGroup`) déclaré nulle part dans le projet — un target
d'extension NE PEUT PAS lire cette session sans (1) ajouter l'entitlement "App Groups"/groupe de
trousseau partagé aux DEUX targets (app + extension), ce qui (2) nécessite d'activer la capability
correspondante pour l'App ID dans le portail développeur Apple AVANT que l'entitlement n'ait un
effet — exactement la même dépendance externe et le même risque de casser la signature/CI que
`V4-F-003` (Associated Domains), hors accès de cet environnement. Scaffolder le target seul (sans
partage de session fonctionnel) produirait une extension qui ne peut identifier aucun utilisateur —
un travail non minimal, non testable sans device/compte développeur, pour un résultat non
fonctionnel en l'état. Conformément à la règle de Phase B ("ne pas modifier le code si l'action
dépend du backend/Apple Developer/serveur/test physique impossible"), aucun code n'a été modifié.
Aucun commit, aucune CI dispatchée. Ce finding nécessite une décision produit (vaut-il le coût d'un
target dédié + partage de session ?) et l'accès au compte développeur Apple du projet.
```

```
ID : V4-F-005
PRIORITÉ : P3
DOMAINE : Navigation-DeepLinks
FEATURE : Segment de chemin deep link non reconnu → no-op silencieux au lieu d'un repli vers Home
ANDROID SOURCE : partage/ShareActivity.java:166-217 (`default:` → lance `SplashActivity`)
IOS FILES : Navigation/DeepLinkRouter.swift:55-85 (`default: break`)
DIFFÉRENCE : Android atterrit toujours sur un écran utilisable ; iOS ne fait rien d'observable.
IMPACT : Mineur, cas de bord seulement.
PREUVE : `ShareActivity.java:207-210` vs `DeepLinkRouter.swift:83-84`.
RECOMMANDATION : Ajouter un repli vers Home dans le `default` de `handleContentLink`.
```

```
ID : V4-F-006
PRIORITÉ : P2
DOMAINE : Navigation-DeepLinks
FEATURE : Route deep link `update` — no-op auto-documenté (appStoreId non renseigné)
ANDROID SOURCE : partage/ShareActivity.java:193-199
IOS FILES : Navigation/DeepLinkRouter.swift:69-80 (`let appStoreId: String? = nil`)
DIFFÉRENCE : Android ouvre un écran de mise à jour forcée réel ; iOS ne fait rien tant que l'app
n'est pas publiée (déjà documenté dans le code comme un placeholder connu).
IMPACT : Faible aujourd'hui (lien rarement tapé, gate de force-update séparée existe déjà).
PREUVE : `DeepLinkRouter.swift:77`.
RECOMMANDATION : Renseigner l'App Store ID réel avant publication — pas d'investigation
supplémentaire nécessaire.

STATUT : DIFFÉRÉ, sans objet actuellement (2026-08-24, Phase B P2, Lot P2-1) — vérifié :
`DeepLinkRouter.swift` déclare bien `let appStoreId: String? = nil` avec un commentaire de tête
documentant explicitement ce placeholder connu. Pas un bug de code à corriger : l'app n'étant pas
encore publiée sur l'App Store, AUCUN App Store ID réel n'existe à renseigner — toute tentative de
"corriger" ce finding maintenant introduirait soit une valeur fictive (pire que `nil`, un lien mort
silencieux au lieu d'un `nil` explicite et déjà documenté), soit nécessiterait d'attendre une
publication qui n'a pas eu lieu. La RECOMMANDATION de l'audit lui-même le confirme ("pas
d'investigation supplémentaire nécessaire"). Le code de routage (`DeepLinkRouter.handleContentLink`,
route `update`) est déjà prêt à fonctionner dès que cette valeur sera renseignée avant la
publication réelle — aucune modification de code faite ici, aucun commit, aucune CI.
```

---

## 2. Profile

```
ID : V4-F-007
PRIORITÉ : P0
DOMAINE : Profile
FEATURE : Le viewer plein écran ouvert DEPUIS Profile a des boutons supprimer/signaler/bloquer/
commenter/télécharger totalement morts
ANDROID SOURCE : uploadPerfilPhoto/ProfileFeedFragment.java:597-756 ; uploadPerfilPhoto/AddPerfilFoto
.java:491-503 ; uploadPerfilPhoto/UserProfile.java:1180-1197
IOS FILES : Feed/FeedView.swift:415-465,428-429,692-694 ; Profile/ProfileView.swift:64-66
ANDROID BEHAVIOR : Le "…" du viewer plein écran ouvre un menu complet (supprimer son post/copier le
lien/ne plus suivre/bloquer/signaler/télécharger) ; le bouton commentaire ouvre les commentaires —
fonctionnel, identique au fil principal.
IOS BEHAVIOR : `ProfileView` ouvre `FeedDetailPagerView` via l'initialiseur SANS closures `onComment`/
`onMore` — ces deux paramètres retombent silencieusement sur `{ _ in }` (no-op). Like/partage/suivre/
ouvrir-profil-auteur fonctionnent (appellent directement `viewModel`), mais "…" et commentaire ne font
RIEN quand on y accède depuis Profile — alors que le MÊME pager fonctionne parfaitement depuis le Feed
principal.
DIFFÉRENCE : Comportement du viewer entièrement dépendant du point d'entrée, alors que c'est le même
composant.
IMPACT : Impossible de supprimer son propre post, signaler/bloquer un utilisateur, télécharger un
média, copier un lien ou ouvrir les commentaires en parcourant via Profile — seul moyen de contourner :
retrouver le même post dans le Feed principal.
PREUVE : `FeedView.swift:428-429` déclare les closures par défaut à `{ _ in }` ; l'init utilisé par
`ProfileView` (lignes 449-456) ne les définit jamais.
RECOMMANDATION : Donner à `ProfileView` sa propre présentation `FeedViewModel` (ou câbler les vraies
closures) pour un comportement identique quel que soit le point d'entrée.
STATUT : BUILD_VALIDATED (2026-08-23, Lot P0-3, commit d9bb80e, CI run 32665481871 succès). Portée
RÉELLE plus large que le texte d'audit ci-dessus : le même bug (`onComment`/`onMore` no-op) touchait
EN RÉALITÉ 5 des 6 appelants de `FeedDetailPagerView` (`SearchView`, `HashtagFeedView`,
`NotificationsListView`, `HomeShellView`, `ProfileView` — tous via l'init `posts:` sans closures),
pas seulement Profile. État/dialogues (`moreActionsPost`, `reportTargetPost`, `blockTargetPost`,
`commentsPost`, `boostTargetPost`, `statsTargetPost`) déplacés DANS `FeedDetailPagerView` elle-même
(plus de closures remontées à l'appelant) — les 6 écrans en bénéficient désormais uniformément.
`showManagementActions: true` réservé à `FeedView` (Statistiques/Promouvoir, sans équivalent
Android dans les 3 autres menus "..." vérifiés). Téléchargement (`FeedMediaDownloader.swift`, port
de `checkBestQualityAndDownload`/`downloadFile`) confirmé RÉEL uniquement dans
`ProfileFeedFragment` par lecture croisée de `MainFragment`/`FullScreenMedia`/`HashtagProfile` (`ids`
n'y liste jamais `R.id.download`, ou pointe vers un handler mort) — gated `includesDownload: true`
sur le seul appel `ProfileView`. DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED (5 actions +
téléchargement à vérifier séparément sur device réel, cf. méthode Phase B).
```

```
ID : V4-F-008
PRIORITÉ : P0
DOMAINE : Profile / BunnyCDN-Media
FEATURE : L'upload de photo de profil utilise le mauvais protocole backend — contourne complètement
BunnyCDN (doublon confirmé, trouvé indépendamment par 2 agents)
ANDROID SOURCE : uploadPerfilPhoto/AddPerfilFoto.java:153-196,558 (chemin réel, l'alternative est
COMMENTÉE) ; uploadPerfilPhoto/service/ProfileService.java:174-321 (`uploadImageToBunny`+
`sendMetaDate`, RÉEL) ; uploadPerfilPhoto/ProfileRepository.java:107 (`uploadPhotoProfile`, MORT —
son seul site d'appel est commenté à `AddPerfilFoto.java:558`)
IOS FILES : Profile/ProfileRepository.swift:109-130 ; câblé depuis ProfileViewModel.swift:166-175 et
ProfileView.swift:83
ANDROID BEHAVIOR : Le VRAI flux (bouton "changer l'avatar" réel) : (1) `PUT storage.bunnycdn.com/
tiinver-media/tiinver/profile/photos/{token}.webp` (header `AccessKey`, octets bruts) ; (2)
`POST user/avatar/add` avec `{id, column:"profile_picture", value:<url_bunny>, object_url:<url_bunny>}`.
IOS BEHAVIOR : `ProfileRepository.uploadProfilePicture` fait un POST multipart directement vers
`{SERVER}user` — c'est le PORT DU CODE MORT ANDROID (`uploadPhotoProfile`, jamais appelé en réalité),
pas du flux réellement câblé.
DIFFÉRENCE : Endpoint et protocole entièrement différents de ce que le trafic Android réel envoie
jamais. N'utilise jamais BunnyCDN pour cette fonctionnalité.
IMPACT : Le changement de photo de profil sur iOS risque fortement d'échouer ou de se comporter de
façon imprévisible en production — le endpoint `user` n'a probablement jamais été construit/testé
pour ce format multipart.
PREUVE : `AddPerfilFoto.java:558` — `// profileViewModel.uploadPhotoProfile(foto);` (commenté) ; le
chemin réel démarre `ProfileService` à la ligne 157.
RECOMMANDATION : Réécrire `uploadProfilePicture` pour PUT vers Bunny Storage puis POST `user/
avatar/add` avec l'URL CDN résultante, en reprenant le motif déjà établi dans `FeedMediaUploader.swift`.
STATUT : BUILD_VALIDATED (2026-08-23, Lot P0-4, commit 4293e06, CI run 32673048282 succès).
Reconfirmé par relecture directe d'`AddPerfilFoto.java` (pas seulement les conclusions Phase A) :
`uploadPhotoProfile` est bien mort (ligne 558 commentée), le flux réel (`uploadProfilePicture`,
ligne 557 → `ProfileService`) fait exactement PUT Bunny Storage puis POST `user/avatar/add` comme
décrit ci-dessus. `ProfileRepository.uploadProfilePicture` réécrit en conséquence : PUT `tiinver-
media/tiinver/profile/photos/{token}.webp` (AccessKey), puis POST `user/avatar/add` avec l'URL CDN
ABSOLUE résultante (`cdn.tiinver.com/...`, PAS un chemin relatif comme le flux Feed — vérifié comme
une différence RÉELLE entre les deux flux BunnyCDN, pas une simplification de ce portage). Constantes
de stockage RÉUTILISÉES depuis `FeedMediaUploader` (rendues internes) plutôt que redupliquées une 3ᵉ
fois — écart délibéré par rapport à la triplication Android, pour éviter une occurrence
supplémentaire en clair de la clé d'accès dans le dépôt, sans changement de comportement réseau.
`CertificationRepository.submit` (endpoint `certification/request`) vérifié comme un flux SÉPARÉ,
non affecté par ce correctif malgré une référence en commentaire. DEVICE_TEST_REQUIRED pour
COMPLETE_PARITY_VALIDATED (changer l'avatar sur un compte réel, confirmer via inspection réseau que
le PUT Bunny et le POST `user/avatar/add` aboutissent, et que l'avatar affiché après rechargement du
profil correspond bien à l'image envoyée).
```

```
ID : V4-F-009
PRIORITÉ : P2
DOMAINE : Profile
FEATURE : Échec d'upload de photo de profil totalement silencieux (`catch {}` vide)
ANDROID SOURCE : uploadPerfilPhoto/AddPerfilFoto.java:258-289 ; adapter/ProfileAdapter2.java:272-285
IOS FILES : Profile/ProfileViewModel.swift:170-178
DIFFÉRENCE : Android bascule l'avatar vers une icône d'erreur visible ; iOS n'affiche rien.
IMPACT : L'utilisateur ne sait pas si son upload a échoué.
PREUVE : `catch {}` sans état d'erreur ni indicateur.
RECOMMANDATION : Ajouter un état d'erreur dédié (ex. `photoUploadError`) affiché près de l'avatar.

STATUT : BUILD_VALIDATED (2026-08-24, Phase B P2, Lot P2-1) — Vérifié contre `AddPerfilFoto.java:
258-289` (`Result.ERROR` → `mAdapter.setProfilePictureStateLoading(3)`) et `ProfileAdapter2.java:
281-285` (`error.setVisibility(VISIBLE)`, icône d'erreur dédiée superposée à l'avatar, distincte de
l'icône de succès et du spinner de chargement). Confirmé côté iOS : `ProfileViewModel.
uploadProfilePicture` avait un `catch {}` strictement vide. Correctif : nouveau `@Published var
photoUploadFailed`, mis à `true` dans le `catch`/à `false` au démarrage d'un nouvel essai ; rendu
en overlay (icône `exclamationmark.circle.fill`, coin HAUT-droit pour ne pas chevaucher le bouton
caméra existant en bas-droit) dans `ProfileView.avatar`. Commit `ac3ce38`, push confirmé
(`1b06e18..ac3ce38 main -> main`), CI run `32709964672` conclusion `success`.
DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED (couper le réseau pendant un changement
d'avatar, confirmer l'icône d'erreur visible).
```

```
ID : V4-F-010
PRIORITÉ : P2
DOMAINE : Profile
FEATURE : Grille de posts du profil sans état loading/vide
ANDROID SOURCE : adapter/ProfileAdapter2.java:169-208 (shimmer + repli avec bouton réessayer)
IOS FILES : Profile/ProfileView.swift:41-63 ; ProfileViewModel.swift:14 (`isLoadingPosts` non lu)
DIFFÉRENCE : `isLoadingPosts` publié mais jamais référencé dans la vue (grep confirmé) ; aucun état
vide pour un profil sans post.
IMPACT : Espace blanc inexpliqué pour un profil vide ; aucun feedback pendant la pagination.
RECOMMANDATION : Ajouter un `ProgressView` en pied de grille + un état vide explicite.

STATUT : BUILD_VALIDATED (2026-08-24, Phase B P2, Lot P2-1) — Vérifié contre `ProfileAdapter2.
FooterViewHolder.bindView(type)` (`ProfileAdapter2.java:186-208`, entier) : pied de grille paginée
à 3 états réels — shimmer (chargement, type 0), rien (succès, type 1), icône+texte+bouton
"Réessayer" (échec, type 2). Recherche explicite d'un état "vide" dédié dans
`ProfileAdapter2`/`UserProfile.java`/`AddPerfilFoto.java` (`grep emptyView\|no_data\|Aucune`) →
AUCUN résultat pertinent — Android n'a PAS de vue "aucune publication" explicite, seule la partie
loading/erreur ci-dessus a un équivalent Android réel. Confirmé côté iOS : `isLoadingPosts` publié
mais lu par AUCUNE vue (grep confirmé) ; `loadMorePosts()` avalait l'échec via `print(...)` seul.
Correctif : nouveau `@Published var postsLoadError` ; `postsGridFooter` (nouveau) rend
`ProgressView`/erreur+retry/texte "Aucune publication" selon l'état — CE DERNIER état est un ajout
de confort UX documenté comme NON issu d'Android (pas de parité fabriquée), les 2 premiers sont un
port fidèle du footer Android. Commit `ac3ce38`, push confirmé (`1b06e18..ac3ce38 main -> main`),
CI run `32709964672` conclusion `success`. DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED
(couper le réseau pendant le scroll, confirmer l'erreur+retry ; profil sans post, confirmer le
texte vide).
```

```
ID : V4-F-011
PRIORITÉ : P2
DOMAINE : Profile
FEATURE : L'écran Modifier le profil ne charge/affiche jamais la bio ou le lien existants
ANDROID SOURCE : uploadPerfilPhoto/EditProfile.java:86-142 (affiche au moins en `hint`)
IOS FILES : Profile/EditProfileView.swift:1-81 (seul `loadCategory()` précharge quelque chose)
DIFFÉRENCE : `biography`/`link` ne sont jamais assignés depuis un profil chargé — champs vides à
l'ouverture, sans même un placeholder informatif.
IMPACT : Impossible de voir sa bio/son lien actuels sans quitter cet écran.
RECOMMANDATION : Précharger `biography`/`link` dans `.task`, comme pour `loadCategory()`.

STATUT : BUILD_VALIDATED (2026-08-24, Phase B P2, Lot P2-1) — Vérifié contre `EditProfile.onResume`
(`EditProfile.java:86-128`, entier) : `bioInput.setHint(biography)`/`linkView.setHint(link)` — les
valeurs existantes sont affichées EN PLACEHOLDER (hint), PAS pré-remplies dans le champ éditable
(`setText` jamais appelé pour ces 2 champs, contrairement à `category`, dont le hint SEUL est
également utilisé). Confirmé côté iOS : `biography`/`link` jamais assignés depuis un profil
chargé — champs vides sans même un placeholder informatif. Correctif : `loadCategory()` étendue
(fetch déjà en place, juste 2 champs supplémentaires lus) pour peupler `existingBiography`/
`existingLink`, utilisés comme PLACEHOLDER du `TextField` (pas pré-saisis dans `$biography`/`$link`)
— reproduit fidèlement le hint Android, préserve intact le comportement de `save()` ("un champ
non-vide seulement est envoyé", déjà correct). Commit `ac3ce38`, push confirmé
(`1b06e18..ac3ce38 main -> main`), CI run `32709964672` conclusion `success`.
DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED (ouvrir "Modifier le profil" avec une bio/un
lien déjà enregistrés, confirmer leur affichage en placeholder grisé).
```

```
ID : V4-F-012
PRIORITÉ : P2
DOMAINE : Profile / Settings
FEATURE : Écran résumé lecture-seule "Informations personnelles" (téléphone/email) entièrement
absent (doublon confirmé, trouvé indépendamment par 2 agents — Profile et Settings)
ANDROID SOURCE : setting/FragmentProfile.java:1-247 ; setting/SettingAccountFragment.java:102
IOS FILES : Settings/SettingsView.swift:22 (lien direct vers le formulaire d'édition) ; AUCUN écran
résumé lecture-seule
ANDROID BEHAVIOR : Depuis Réglages → Compte, un écran intermédiaire affiche nickname/localisation/
travail/qualification/école/username/genre/date de naissance/**téléphone**/**email** en lecture
seule, avec un bouton "Modifier" séparé vers le vrai formulaire d'édition.
IOS BEHAVIOR : Accès direct au formulaire d'édition — qui ne contient PAS les champs téléphone/email
non plus (fidèle à Android sur ce point précis). Aucun écran de l'app n'affiche donc le téléphone/
email de l'utilisateur nulle part.
DIFFÉRENCE : L'unique endroit où voir son propre téléphone/email enregistré est entièrement absent.
IMPACT : Un utilisateur ne peut voir son téléphone/email enregistré nulle part dans l'app.
RECOMMANDATION : Ajouter un écran résumé lecture-seule (au moins téléphone/email) accessible depuis
Réglages → Compte, avant/à côté du formulaire d'édition.

STATUT : BUILD_VALIDATED (2026-08-24, Phase B P2, Lot P2-2) — Vérifié contre `setting/
FragmentProfile.java` (247, entier) : écran lecture seule affichant nickname/localisation/travail/
qualification/école/username/genre/date de naissance/téléphone/email. Chaîne de navigation réelle
tracée par lecture croisée : `SettingAccountFragment.java:97-105` (`pref_personnel_info` →
`onFragmentInteraction(9)`) → `SettingsActivity.java:164-172` (case 9 → `FragmentProfile`) →
`FragmentProfile.java:73-80` (bouton `editbtn` → `onFragmentInteraction(10)`) →
`SettingsActivity.java:173-181` (case 10 → `EditPersonalInformation`, déjà porté). `grep
onFragmentInteraction\(10\)` dans tout le code Android → UN SEUL appelant (ce bouton précis) —
confirmé qu'Android n'offre AUCUN accès direct au formulaire d'édition, contrairement à ce que
faisait `SettingsView.swift` avant ce correctif. Correctif : nouvelle
`PersonalInformationSummaryView` (port fidèle de `FragmentProfile`, 10 champs + bouton "Modifier"
→ `EditPersonalInformationView` déjà existant) ; câblée dans `SettingAccountView` ("Compte",
nouvelle entrée, fidèle à `pref_personnel_info`) ; le raccourci racine préexistant de
`SettingsView` (qui allait DIRECTEMENT au formulaire d'édition, une déviation réelle vs Android)
redirigé vers ce résumé au lieu d'être supprimé — préserve la commodité d'accès rapide tout en
imposant le même passage par la vue lecture seule qu'Android. Commit `4cc0ba2`, push confirmé
(`15ffbd1..4cc0ba2 main -> main`), CI run `32711209239` conclusion `success`.
DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED (ouvrir Réglages → Compte → Informations
personnelles ET Réglages → Informations personnelles [raccourci], confirmer que les 10 champs
s'affichent avec les vraies valeurs du compte, notamment téléphone/email).
```

```
ID : V4-F-013
PRIORITÉ : P3
DOMAINE : Profile
FEATURE : Bannière de statut de compte et badge programme premium décodés mais jamais affichés
ANDROID SOURCE : adapter/ProfileAdapter2.java:257-303
IOS FILES : Models/User.swift:53-55,138-143 (décodés) ; Profile/ProfileView.swift:100-157 (jamais lus)
IMPACT : Un utilisateur restreint/banni/averti n'a aucune indication in-app ; badge premium jamais visible.
RECOMMANDATION : Rendre `profile?.userStatus`/`hasProgram`/`programs` dans le header.
```

```
ID : V4-F-014
PRIORITÉ : P2
DOMAINE : Profile
FEATURE : Les posts d'un profil sont récupérés même si l'utilisateur visionné est bloqué
ANDROID SOURCE : uploadPerfilPhoto/UserProfile.java:723-727 (`if (!isBlocked) { ... }`)
IOS FILES : Profile/ProfileViewModel.swift:118-142 (aucune garde `isBlocked`)
IMPACT : Écart mineur de confidentialité/cohérence — requête réseau émise malgré le blocage.
RECOMMANDATION : Ajouter `guard !isBlocked else { return }` avant `loadInitialPosts`/`loadMorePosts`.
```

```
ID : V4-F-015
PRIORITÉ : P3
DOMAINE : Profile
FEATURE : Aucune action "Partager le profil"
ANDROID SOURCE : uploadPerfilPhoto/AddPerfilFoto.java:396-419
IOS FILES : Profile/ProfileView.swift:335-351 (toolbar own-profile = seulement réglages)
RECOMMANDATION : Ajouter un `ShareLink` vers `https://tiinver.com/user/{username}`.
```

```
ID : V4-F-016
PRIORITÉ : P3
DOMAINE : Profile
FEATURE : L'upload d'avatar saute l'étape de recadrage présente sur Android
ANDROID SOURCE : uploadPerfilPhoto/AddPerfilFoto.java:421-490 (CropFragment/MediaEditor)
IOS FILES : Profile/ProfileView.swift:77-86 (PhotosPicker → upload direct, aucun recadrage)
SUGGESTED_STATUS : IOS_INTENTIONAL_DIFFERENCE (acceptable si le recadrage circulaire côté serveur
suffit — à confirmer produit)
RECOMMANDATION : Accepter tel quel, ou ajouter une étape de recadrage si jugé nécessaire.
```

---

## 3. Settings

```
ID : V4-F-017
PRIORITÉ : P1
DOMAINE : Settings
FEATURE : Le toggle de confidentialité (compte privé) garde silencieusement le mauvais état visuel
en cas d'échec de sauvegarde serveur
ANDROID SOURCE : setting/SettingPrivacityFragment.java:294-328 (`swichtToPrivate`, revert explicite
sur `onError` : `account_type_switch.setChecked(!isChecked)`)
IOS FILES : Settings/SettingSubViews.swift:107-137 (`SettingPrivacyView.save`, `try?` avale l'erreur)
DIFFÉRENCE : Android reflète l'échec en remettant le switch à son vrai état serveur ; iOS laisse le
toggle sur la nouvelle position jamais persistée, sans aucune indication.
IMPACT : L'utilisateur croit avoir changé sa confidentialité alors que le serveur n'a jamais reçu le
changement — état trompeur jusqu'au rechargement de l'écran.
RECOMMANDATION : `do/catch` explicite ; sur échec, revert `isPrivate` + message d'erreur, comme Android.
STATUT : BUILD_VALIDATED (2026-08-23, commit d63c2f6, CI run 32675965460 succès). Cause racine réelle
plus profonde que le seul `try?` de `save` : `ProfileRepository.updateProfileField` (méthode PARTAGÉE,
9 appelants) discardait la réponse sans jamais vérifier `isBackendSuccess` — ne pouvait donc JAMAIS
lever sur un rejet backend (HTTP 200, `error:"true"`), seulement sur échec réseau. Corrigée pour lever
correctement (aucun changement observable pour les 8 appelants `try?` déjà indifférents au résultat ;
`CategoryPickerView.save`, qui avait DÉJÀ un `do/catch` prêt, bénéficie du correctif au passage).
`SettingPrivacyView.save` fait maintenant `do/catch` + revert de `isPrivate` sur échec, fidèle à
`account_type_switch.setChecked(!isChecked)`. Écart iOS/Android identifié et géré : `setChecked`
Android ne redéclenche PAS le listener de clic, mais `.onChange(of: isPrivate)` SwiftUI redéclenche
TOUJOURS — un flag `isReverting` évite qu'un revert visuel envoie un second appel réseau non désiré
(divergence Android absente, comportement observable final identique). DEVICE_TEST_REQUIRED pour
COMPLETE_PARITY_VALIDATED (couper le réseau ou simuler un rejet serveur, basculer le toggle, confirmer
qu'il revient à son état précédent SANS second appel réseau visible dans un outil d'inspection).
```

```
ID : V4-F-018
PRIORITÉ : P3
DOMAINE : Settings
FEATURE : Écran Stockage — sélection média par type de connexion (photos/vidéos/fichiers) absente
ANDROID SOURCE : setting/SettingStorageFragment.java:113-151,215-227,255-282
IOS FILES : Settings/SettingSubViews.swift:81-96 (seulement 3 switches maître, déjà documenté comme
port incomplet dans le fichier lui-même)
IMPACT : Faible — confirmé que ces préférences granulaires ne sont lues nulle part côté Android non
plus (grep : zéro consommateur hors leur propre écran), donc écart visuel/de complétude seulement,
pas fonctionnel.
RECOMMANDATION : Priorité basse — ajouter les 3 lignes + dialogue multi-sélection pour la complétude
visuelle uniquement si jugé utile.
```

---

## 4. Groups

```
ID : V4-F-019
PRIORITÉ : P1
DOMAINE : Groups
FEATURE : Action "Envoyer un message" absente de la gestion des membres de groupe
ANDROID SOURCE : messagerie/group/SettingGroupMessageFragmant.java:417-478 ; Adapter.java:119-144
(`sendMessage`, ouvre un chat 1:1 avec le membre) ; res/values/strings.xml:443-455
IOS FILES : Messagerie/GroupDetailView.swift:176-182,205-211
ANDROID BEHAVIOR : Taper un membre propose TOUJOURS "Message" (+ promouvoir/rétrograder + retirer si
admin). Un non-admin a exactement 1 option : Message.
IOS BEHAVIOR : Le dialogue de confirmation n'offre que 2 actions (rôle admin, retirer) — aucune option
"Message". Pour un non-admin, `guard isCurrentUserAdmin ... else { return }` rend le tap totalement
mort (aucun dialogue, aucun feedback).
IMPACT : Impossible de démarrer une conversation privée avec un membre du groupe depuis cette liste ;
les non-admins n'ont aucune interaction du tout sur les lignes de membres.
RECOMMANDATION : Ajouter "Message" au dialogue admin ; donner aux non-admins un moyen (à option
unique) d'ouvrir un chat 1:1 avec le membre tapé.

STATUT : BUILD_VALIDATED (2026-08-24) — Vérifié contre `SettingGroupMessageFragmant.java:162-172`
(`onItemClick` : `if (IAM_ADMIN) showMemberDialog(...) else showMemberIsNotAdminDialog(...)`),
`:417-447` (les 2 fonctions, entières) et `strings.xml:443-455` (3 tableaux :
`action_on_members_group`/`action_on_members_group_admin` = [Message, rôle, Retirer] — "Message"
TOUJOURS EN PREMIER ; `action_on_members_group_no_admin` = [Message] seul) ; ET `Adapter.
java:119-144` (`sendMessage(pos)`, construit un `RosterModel` `type=CHAT` avec
`nikname`/`username`/`userId`/`profile`/`from`/`to`). Confirmé côté iOS que le dialogue admin
n'avait que 2 actions (rôle/retirer, "Message" absent) et qu'un non-admin tapant un membre ne
déclenchait STRICTEMENT rien (`guard isCurrentUserAdmin ... else { return }`). Correctif : "Message"
ajouté EN PREMIER dans le dialogue admin existant ; nouveau dialogue à 1 action pour un non-admin
tapant un AUTRE membre (`messageOnlyTarget`) ; nouvelle `chatTarget(for:)` (port fidèle de
`Adapter.sendMessage`) + `.navigationDestination(isPresented:)` vers `ChatView`, même motif déjà
établi par `ProfileView.messageTarget`/`NewMessageView.rosterTarget` (pas une 3ᵉ implémentation
divergente). Le garde-fou `member.userId != currentUserId` (empêcher de se cibler soi-même) est
préservé pour les DEUX rôles — comportement pré-existant côté iOS, non demandé par ce finding, non
modifié. Flux frères vérifiés : `grep memberActionTarget\|showMemberDialog\|GroupMember\b` → une
seule vue concernée, `GroupDetailView.swift`. Commit `bda7955`, push confirmé
(`39be9b9..bda7955 main -> main`), CI run `32686822701` conclusion `success`.
DEVICE_TEST_REQUIRED pour passer en COMPLETE_PARITY_VALIDATED (aucun accès Xcode/simulateur dans
cet environnement — test réel requis : en tant qu'admin, taper un membre → confirmer "Message" en
tête du dialogue, taper "Message" → conversation 1:1 ouverte ; en tant que non-admin, taper un
membre → confirmer le dialogue à 1 action, taper "Message" → même résultat).
```

```
ID : V4-F-020
PRIORITÉ : P1
DOMAINE : Groups
FEATURE : Les mutations de gestion de groupe ignorent les réponses d'erreur backend
ANDROID SOURCE : messagerie/group/SettingGroupMessageFragmant.java:542-620 ; ChangeGroupTopicActivity
.java:101-166 ; AddGroupDescriptionActivity.java:105-168 ; GroupDetailActivity.java:271-336 (toutes
gated par `if (action==0)`)
IOS FILES : Messagerie/GroupRepository.swift:229-323 (`updateMemberRole`, `removeMember`,
`updateDescription`, `updateName`, `leaveGroup`, `subscribeToGroup`, `renewGroupSubscription`)
ANDROID BEHAVIOR : Chaque opération n'applique ses effets locaux QUE si `action==0` (succès) ; un
rejet backend laisse l'UI/état inchangés.
IOS BEHAVIOR : Les 7 méthodes font `_ = try await APIClient.shared.post(...)` SANS jamais vérifier
`value.isBackendSuccess`/`backendErrorMessage` — contrairement à `createGroup`/`fetchGroup` DANS LE
MÊME FICHIER, qui font bien ce contrôle.
DIFFÉRENCE : Un rejet métier backend (HTTP 200, `error:"true"`) est traité comme un succès pour ces
7 opérations.
IMPACT : `GroupDetailView` (remove/toggleAdmin/submitDescription/submitName/leaveGroup) applique les
effets locaux (membre disparaît, nom/description mis à jour, écran fermé) même si le serveur a
rejeté l'opération — désynchronisation client/serveur silencieuse.
RECOMMANDATION : Ajouter `guard value.isBackendSuccess else { throw ... }` aux 7 méthodes, comme déjà
fait pour `createGroup`/`fetchGroup` dans le même fichier.
STATUT : BUILD_VALIDATED (2026-08-23, commit 6190dee, CI run 32673545395 succès). Vérification
Android approfondie : `TransportData.Post` (`Http/TransportData.java:615-681`, lu en entier) confirme
que le callback `onResonse` (qui applique les effets locaux) n'est appelé QUE si
`response.getString("error").equals("false")`, sinon `onError` est appelé à la place — le `action==0`
visible dans chaque appelant est donc TOUJOURS vrai quand `onResonse` est atteint (`action` y est un
littéral `0` fixé par le framework, pas un champ de la réponse), le vrai gate étant `error=="false"`,
exactement `JSONValue.isBackendSuccess`. Les 7 appelants iOS (`GroupDetailView.swift`,
`ChatViewModel.resolveGroupSubscription`) enveloppaient déjà chaque appel dans un `do/catch`
appliquant les effets locaux seulement après le `try await` — il ne manquait que le `throw` côté
`GroupRepository` pour que ce `catch` existant se déclenche réellement. Correctif : `guard
value.isBackendSuccess else { throw ... }` ajouté aux 7 méthodes (`grep "_ = try await APIClient"` →
0 occurrence restante dans le fichier après correctif). Aucun changement côté appelants nécessaire.
DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED (provoquer un rejet backend réel — ex. retirer un
membre déjà retiré, renommer un groupe avec des droits insuffisants — et confirmer que le message
d'erreur s'affiche sans appliquer l'effet local).
```

```
ID : V4-F-021
PRIORITÉ : P1
DOMAINE : Groups / Social
FEATURE : Les motifs de signalement affichés depuis Profile ne correspondent pas à la vraie liste Android
ANDROID SOURCE : res/values/strings.xml:516-525 (`report_setting_array`, 8 items) ; Feed/FeedView
.swift:250-253 (contient DÉJÀ la bonne liste, utilisée pour un AUTRE flux de signalement)
IOS FILES : Discover/ReportView.swift:19 (liste de 6 items inventée, différente)
DIFFÉRENCE : `ReportView` (seul point d'entrée réel, depuis Profile) utilise "Spam"/"Autre" — absents
d'Android — et omet Nudité/Vente non autorisée/Discours de haine/Moins de 13 ans. La BONNE liste à
8 items existe déjà ailleurs dans le même projet iOS (`FeedView.swift`) mais n'a jamais été réutilisée
ici.
IMPACT : Les catégories envoyées au backend pour un signalement de profil ne correspondent pas à la
taxonomie de modération attendue.
RECOMMANDATION : Remplacer la liste de `ReportView.swift` par celle déjà correcte de
`FeedView.swift:250-253` (idéalement factoriser en une seule constante partagée).

STATUT : BUILD_VALIDATED (2026-08-24) — Vérifié contre `strings.xml:516-525`
(`report_setting_array`, 8 items : Nudity/Violence/Harassment/False Information/
Unauthorised_sales/Hate speech/Terrorisme/Under 13 years old) et `report/Report.java:67`
(`getResources().getStringArray(R.array.report_setting_array)`, UNE SEULE liste, réutilisée
identiquement pour les signalements "user" ET "group" — pas de liste séparée par type). Confirmé
côté iOS que `ReportView.reasons` (6 items : "Spam"/"Contenu inapproprié"/"Harcèlement"/
"Usurpation d'identité"/"Fausses informations"/"Autre") ne correspondait à AUCUN sous-ensemble de
la vraie liste — et que la bonne liste à 8 items existait déjà, mot pour mot, dans
`FeedView.swift` (`feedReportReasons`, `private`, utilisée par le menu "..." du Feed — un flux de
signalement Android SÉPARÉ mais utilisant la MÊME ressource). Correctif : `feedReportReasons`
rendue interne (retrait de `private`) et RÉUTILISÉE telle quelle dans `ReportView` (suppression de
la liste dupliquée divergente), même motif de partage de constante que `UploadProgressDelegate`
(V4-F-064). Pas de branchement `reportType`-spécifique ajouté — confirmé par lecture directe de
`Report.java` que la même ressource sert aux deux types. Commit `4ff545b`, push confirmé
(`c3812dd..4ff545b main -> main`), CI run `32685665777` conclusion `success`.
DEVICE_TEST_REQUIRED pour passer en COMPLETE_PARITY_VALIDATED (aucun accès Xcode/simulateur dans
cet environnement — test réel requis : signaler un profil ET un groupe, confirmer que les 8 motifs
affichés correspondent exactement à `report_setting_array`, et que le `message` envoyé au backend
reflète le motif choisi).
```

```
ID : V4-F-022
PRIORITÉ : P2
DOMAINE : Groups / Social
FEATURE : Action "Signaler le groupe" entièrement absente (doublon confirmé, trouvé indépendamment
par 2 agents)
ANDROID SOURCE : messagerie/group/GroupDetailActivity.java:204-215 ; res/menu/menu_group.xml:12-15
IOS FILES : Messagerie/GroupDetailView.swift — aucune référence à `ReportView`/signalement
ANDROID BEHAVIOR : Le menu d'un groupe (accessible à tout membre) propose "Signaler", qui lance
`Report` avec `type="group"`.
IOS BEHAVIOR : `ReportView.swift` supporte déjà `reportType: "group"` en interne (composant générique
prêt) mais n'est JAMAIS instancié depuis `GroupDetailView` — gap de câblage pur, pas de composant à
construire.
RECOMMANDATION : Ajouter une action "Signaler le groupe" dans `GroupDetailView` qui présente
`ReportView(targetId: groupId, username: groupName, reportType: "group")`.
```

```
ID : V4-F-023
PRIORITÉ : P3
DOMAINE : Groups
FEATURE : `ReportView` ne reproduit pas la convention `userId="0"` d'Android pour un signalement de
groupe
ANDROID SOURCE : report/Report.java:77-78,138-150 (`userId="0"` hardcodé pour `type=="group"`)
IOS FILES : Discover/ReportView.swift:42-48 (`userId: targetId` inconditionnel)
SUGGESTED_STATUS : CODE_PRESENT_UNVERIFIED — pertinent seulement une fois V4-F-022 câblé.
RECOMMANDATION : Spécialiser `submit()` pour envoyer `"userId":"0"` quand `reportType=="group"`.
```

```
ID : V4-F-024
PRIORITÉ : P3
DOMAINE : Groups / Social
FEATURE : Le dialogue de confirmation de signalement n'affiche pas le motif choisi
ANDROID SOURCE : report/Report.java:117-124 (titre + corps rappelant le motif)
IOS FILES : Discover/ReportView.swift:27-34 (titre seul, pas de `message:`)
RECOMMANDATION : Ajouter un `message:` au `confirmationDialog` rappelant le motif sélectionné.
```

```
ID : V4-F-025
PRIORITÉ : P2
DOMAINE : Groups
FEATURE : Changement de photo/avatar de groupe non porté
ANDROID SOURCE : messagerie/group/SettingGroupMessageFragmant.java:197-247,628-738 (galerie → crop
→ upload multipart `updategroup` type=4 → message système "groupPictureChanged")
IOS FILES : Messagerie/GroupDetailView.swift (photo affichée en lecture seule, aucun geste ni état
d'édition ; gap déjà documenté dans le fichier lui-même)
IMPACT : Aucun admin ne peut changer la photo d'un groupe depuis iOS.
RECOMMANDATION : Ajouter picker+recadrage (gated admin) + `GroupRepository.updatePhoto(...)`
(multipart `updategroup` type=4), en réutilisant l'infrastructure d'upload de photo de profil.
```

```
ID : V4-F-026
PRIORITÉ : P3
DOMAINE : Groups
FEATURE : Écran de lien d'invitation réduit à un simple déclencheur de share-sheet
ANDROID SOURCE : messagerie/group/InviteLinkActivity.java:49-103 (affichage persistant du lien +
bouton Copier fonctionnel ; NOTE : "Share"/"Reset" sont eux-mêmes du code mort/no-op côté Android)
IOS FILES : Messagerie/GroupDetailView.swift:105,169-171,316-322 (share-sheet système direct)
IMPACT : Faible — impact limité car les boutons Android correspondants sont déjà en grande partie
non fonctionnels ; la share-sheet iOS est arguablement plus fonctionnelle dans l'ensemble.
RECOMMANDATION : Priorité basse — optionnel, afficher le lien en texte + bouton Copier dédié avant
la share-sheet pour une parité visuelle plus proche.
```

---

## 5. Social / Follow / Créateurs

```
ID : V4-F-027
PRIORITÉ : P1
DOMAINE : Following
FEATURE : La liste abonnés/abonnements n'a aucun bouton suivre/ne plus suivre par ligne
ANDROID SOURCE : Recherche/ui/Adapter.java:85-164 (`labelSuivre`, câblé)
IOS FILES : Discover/FollowListView.swift:26-44 (avatar+nom seulement, `NavigationLink` vers le
profil ; `SearchUserResult.isFollowed` déjà utilisé ailleurs dans l'app mais jamais lu ici)
IMPACT : Taps supplémentaires requis pour suivre quelqu'un trouvé dans une liste abonnés/abonnements ;
écart de parité y compris vis-à-vis des propres écrans Recherche/Suggestions d'iOS, qui ont déjà ce
motif exact.
RECOMMANDATION : Ajouter un bouton suivre/ne plus suivre par ligne, en réutilisant le motif déjà
implémenté dans `SearchView.swift`/`SuggestionsCarouselView.swift`.

STATUT : BUILD_VALIDATED (2026-08-24) — Vérifié contre `Recherche/ui/Adapter.java:85-164`
(`labelSuivre`/`lL.setOnClickListener`, entier) ET `Following/FollowList.java:24,43,60`
(`import com.tiinver.Recherche.ui.Adapter` ; `Adapter mAdapter` ; `new Adapter(...)`) : l'écran
abonnés/abonnements RÉUTILISE littéralement le même adaptateur/bouton que Recherche, pas une
implémentation séparée — confirmant que le bouton suivre est un élément structurel de la ligne
partagé entre les deux écrans, pas une fonctionnalité Recherche-only. Confirmé côté iOS que
`FollowListView` n'avait qu'un `NavigationLink` avatar+nom, `SearchUserResult.isFollowed` jamais lu.
Correctif : bouton `followButton`/`toggleFollow` ajouté, réutilisant EXACTEMENT le motif déjà
présent et déjà corrigé dans `SearchView.swift` (V3-F-107 : optimiste + rollback sur échec réseau,
suivre uniquement — pas de bascule "ne plus suivre" depuis cette liste, fidèle à la limitation
réelle de `ProfileRepository.follow`/`Adapter.java` lui-même, qui n'a pas de bouton "ne plus
suivre" inline sur cette ligne). Pas de nouvelle logique réseau — `ProfileRepository.follow` déjà
existant, simplement câblé ici. Commit `a2725a9`, push confirmé (`dfb70b3..a2725a9 main -> main`),
CI run `32686191058` conclusion `success`. DEVICE_TEST_REQUIRED pour passer en
COMPLETE_PARITY_VALIDATED (aucun accès Xcode/simulateur dans cet environnement — test réel requis :
depuis la liste abonnés/abonnements d'un autre compte, suivre un utilisateur non encore suivi,
confirmer le changement d'état visuel ET la persistance après réouverture de l'écran).
```

```
ID : V4-F-028
PRIORITÉ : P2
DOMAINE : Creators
FEATURE : Le classement "Créateur de la semaine" ne se rafraîchit jamais après le premier chargement
ANDROID SOURCE : creatorOfweek/CreatorFragment.java:160-164 (`onResume` → refetch à chaque visite)
IOS FILES : Creators/CreatorOfWeekView.swift:52 (`.task` unique) ; Navigation/HomeShellView.swift:70-98
(onglet persistant dans le `TabView`, `.task` ne se redéclenche jamais)
IMPACT : Classement obsolète pour toute la session après un premier chargement, sans moyen de forcer
un rafraîchissement hors échec.
RECOMMANDATION : Ajouter `.refreshable` et/ou redéclencher au retour sur l'onglet.
```

---

## 6. Feed

```
ID : V4-F-029
PRIORITÉ : P1
DOMAINE : Feed
FEATURE : La publication n'envoie jamais le consentement IA ni les métadonnées enrichies au backend
ANDROID SOURCE : Activity/service/ActivityService.java:182-201 ; editor/PublishFragment.java:274-283,
367-390,544-643 (case à cocher `acceptAi` réel, JSON `metadata` construit avec langue/locale/pays/
dimensions/fps/durée/licence)
IOS FILES : Feed/FeedRepository.swift:187-209 (`"metadata": ""`, `"consentAi": "0"` hardcodés) ;
Feed/PublishComposeView.swift (aucun contrôle de consentement IA dans l'UI)
IMPACT : Divergence légale/conformité réelle, pas seulement de qualité de données — les utilisateurs
iOS ne peuvent jamais donner (ni refuser explicitement) leur consentement à l'entraînement IA.
RECOMMANDATION : Ajouter un toggle de consentement IA à l'écran de légende + construire un vrai JSON
de métadonnées dans `FeedRepository.publish`.
STATUT : BUILD_VALIDATED (2026-08-24, commit ec7dd68, CI run 32681106944 succès). Confirmé : ce gap
était déjà explicitement documenté (pas silencieusement) par le cycle V3 (V3-F-017) comme non
construit dans ce lot-là — retrouvé indépendamment par l'audit V4, signal de fiabilité fort. Vérifié
`PublishFragment.java:544-639` (`getImageMetadata`/`getVideoMetadata`) + `models/MediaMetaData.java`
en entier : `style`/`content_type`/`bitRate` sont déclarés côté Android mais JAMAIS assignés dans
`PublishFragment.java` (confirmé par grep exhaustif) — restent `null`/`0` dans CHAQUE publication
Android réelle, reproduits fidèlement tels quels plutôt qu'inventés. `format` n'est fixé QUE pour une
photo côté Android (`getVideoMetadata` n'appelle jamais `setFormat`) — même asymétrie reproduite.
Corrigé : `Toggle` de consentement IA ajouté à `PublishComposeView` (libellé exact
`@string/allow_my_content_for_ai_training`, décoché par défaut), `fps`/piste audio extraits en plus
de width/height/duration déjà présents pour la vidéo, `MediaMetaData` (struct Swift, champs Gson
EXACTS) sérialisée en JSON dans `metadata`, `consentAi` envoyé fidèlement. `grep publish(` → 2 seuls
sites d'appel dans tout le projet (photo/vidéo), tous deux corrigés. DEVICE_TEST_REQUIRED pour
COMPLETE_PARITY_VALIDATED (publier avec le toggle activé ET désactivé, inspecter le payload réseau
`activity/add` pour confirmer `consentAi`/`metadata` corrects dans les deux cas).
```

```
ID : V4-F-030
PRIORITÉ : P1
DOMAINE : Feed
FEATURE : Like/partage/commentaire ne déclenchent jamais l'appel push vers l'auteur du post
ANDROID SOURCE : Activity/ui/MainFragment.java:1150-1174,1190,1238 (`notifyUser` → `POST push`
séparé de l'appel `reaction`/`comment` lui-même)
IOS FILES : Feed/FeedViewModel.swift:113-140 (`toggleLike`/`toggleShare` — aucun appel équivalent
nulle part)
IMPACT : Les auteurs de post ne sont jamais notifiés d'un like/partage (ni de l'ouverture des
commentaires) venant d'iOS.
RECOMMANDATION : Ajouter un appel `POST push {"userId": <auteur>}` dans `toggleLike`, `toggleShare`,
et à l'ouverture des commentaires.
STATUT : BUILD_VALIDATED (2026-08-24, commit b6e6807, CI run 32681817117 succès). Portée RÉELLE plus
précise que le texte d'audit : vérifié que `notifyUser` est câblé dans `MainFragment` (Feed),
`ProfileFeedFragment` (Profile) ET `HashtagProfile` (hashtag), mais CONFIRMÉ ABSENT de
`FullScreenMedia` (source Android de `SearchView`/`NotificationsListView`, `grep notifyUser` = 0
résultat) — donc PAS câblé partout uniformément côté Android non plus. Placement exact vérifié ligne
par ligne : like → inconditionnel après like ET unlike (hors du if/else, sans attendre la réponse
réseau) ; partage → uniquement sur succès réseau du `reaction`, hors du if/else SHARE/UNSHARE (donc
même sur un message inattendu) ; commentaire → à l'OUVERTURE du panneau, pas à l'envoi d'un
commentaire. Corrigé fidèlement : `FeedRepository.notifyPostAuthor(userId:)` (nouveau), flag
`notifiesAuthorOnInteraction` sur `FeedViewModel` (positionné à l'init, chaque écran possédant déjà
son propre `FeedViewModel` jetable) — `true` pour `FeedView`/`ProfileView`/`HashtagFeedView`/le
pager deep-link de `HomeShellView` (confirmé router par `ShareActivity.getActivities` →
`SplashActivity` → contexte `MainFragment` normal), `false` par défaut (documenté explicitement, pas
un oubli) pour `SearchView`/`NotificationsListView`. DEVICE_TEST_REQUIRED pour
COMPLETE_PARITY_VALIDATED (liker/partager/ouvrir les commentaires depuis Feed/Profile/Hashtag avec un
2ᵉ compte comme auteur, confirmer la réception d'une notification push ; confirmer l'ABSENCE de
notification depuis Search/Notifications, fidèle à Android).
```

```
ID : V4-F-031
PRIORITÉ : P2
DOMAINE : Feed / Performance
FEATURE : Analytics de temps de visionnage par post construites mais jamais câblées (= V3-F-095,
déjà connu/différé ; confirmé indépendamment ici par 2 agents)
ANDROID SOURCE : Activity/ui/FeedFragment.java:1417-1441 (`WatchTimeTracker`→`ViewTracker.record`)
IOS FILES : Storage/ViewEventRepository.swift (port complet et correct, ZÉRO site d'appel confirmé
par grep exhaustif)
IMPACT : Aucune donnée de watch-time/scroll/replay/exit-point n'est jamais collectée côté iOS —
impact potentiel sur le classement/les revenus créateur si le backend en dépend.
RECOMMANDATION : Déjà planifié comme "module 18" — porter le cycle de vie `WatchTimeTracker` dans
`FeedDetailPagerView`/`FeedDetailCell` + un `BGTaskScheduler` de synchronisation périodique.
```

```
ID : V4-F-032
PRIORITÉ : P1
DOMAINE : Feed
FEATURE : Supprimer son propre post le retire du fil même si l'appel serveur échoue
ANDROID SOURCE : Activity/adapter/ActivityAdapter.java:847-867 (retrait UNIQUEMENT dans `onResonse`
succès)
IOS FILES : Feed/FeedViewModel.swift:144-148 (`try?` avale l'erreur, `posts.removeAll` inconditionnel)
IMPACT : Un échec de suppression (réseau, rejet serveur) fait disparaître le post de l'UI comme s'il
avait réussi, sans erreur visible ; il réapparaît au prochain rechargement — même classe de bug déjà
corrigée une fois dans ce fichier (`followFromDetail`) mais manquée ici.
RECOMMANDATION : Ne retirer le post qu'après un `deleteActivity` réussi (sans `try?`) ; afficher une
erreur sinon.
STATUT : BUILD_VALIDATED (2026-08-23, commit f503a72, CI run 32674024379 succès). Reconfirmé par
relecture directe d'`ActivityAdapter.deleteMyPost` : `deletePostById` (retrait local) n'est appelé QUE
dans `onResonse`, jamais dans `onError` (simple Toast) — même contrat `TransportData.Post` que
V4-F-020 (`error=="false"` ⇔ `onResonse`). `deleteActivity` (`FeedRepository.swift`) vérifiait déjà
`isBackendSuccess` et levait correctement ; le seul bug était le `try?` de `deleteOwnPost` qui avalait
cette levée. Corrigé : retrait local conditionné au succès réel (`do/catch`), nouvelle propriété
`@Published var deleteError: String?` (équivalent du Toast Android) affichée via une alerte dans les
2 vues qui déclenchent cette action (`FeedView` grille, `FeedDetailPagerView` plein écran — les 2
seuls sites d'appel, confirmés par `grep deleteOwnPost`). DEVICE_TEST_REQUIRED pour
COMPLETE_PARITY_VALIDATED (provoquer un rejet serveur réel sur une suppression et confirmer que le
post reste visible avec l'alerte affichée, plutôt que de disparaître puis réapparaître).
```

```
ID : V4-F-033
PRIORITÉ : P1
DOMAINE : Feed
FEATURE : Bloquer un utilisateur depuis le Feed retire son post même en cas d'échec ou de bascule
inverse (déblocage)
ANDROID SOURCE : Activity/ui/MainFragment.java:1704-1745 (retrait UNIQUEMENT si `message==USER_BLOCKED`)
IOS FILES : Feed/FeedViewModel.swift:198-204 (`_ = try?`, retrait inconditionnel)
IMPACT : Même classe de bug que V4-F-032 — un blocage échoué ou une bascule vers "débloqué" fait
disparaître le post silencieusement, sans distinction possible pour l'utilisateur.
RECOMMANDATION : Utiliser le `Bool` déjà retourné par `toggleBlock` (et propager l'erreur) pour ne
retirer le post que sur un vrai succès de blocage.
STATUT : BUILD_VALIDATED (2026-08-23, commit 8d6ebae, CI run 32674513016 succès). Reconfirmé par
relecture directe de `MainFragment.block()` (lignes 1704-1758, entier) : `mAdapter.deletePost` n'est
appelé QUE dans la branche `response.equals(USER_BLOCKED)`, ni sur `USER_UNBLOCKED` (bascule inverse)
ni sur `onError` (Toast seul). `ProfileRepository.toggleBlock` retournait déjà le `Bool` fidèle
(`message == "USER BLOCKED"`) mais `FeedViewModel.block` le discardait (`_ = try?`) et retirait le
post inconditionnellement. Corrigé : retrait local conditionné à `blocked == true`. Aucune UI
d'erreur ajoutée ici (contrairement à V4-F-032) — `toggleBlock` retourne le même `false` pour un
déblocage légitime ET un rejet backend (elle ne vérifie pas `isBackendSuccess`), les distinguer
sortirait du périmètre de ce lot ; le comportement correct (ne pas retirer le post) est identique
dans les deux cas, donc aucune régression fonctionnelle. DEVICE_TEST_REQUIRED pour
COMPLETE_PARITY_VALIDATED (bloquer réellement un utilisateur depuis le Feed et confirmer le retrait
du post ; débloquer et confirmer qu'aucun post ne disparaît).
```

```
ID : V4-F-034
PRIORITÉ : P3
DOMAINE : Feed
FEATURE : Le pager plein écran lie chaque cellule vidéo au même `AVPlayer` partagé, sans exclusivité
ANDROID SOURCE : Activity/service/ExoPlayerManager.java:198-330 (détache explicitement le player de
la vue précédente avant de l'attacher à la nouvelle)
IOS FILES : Feed/FeedView.swift:586-599 (`VideoPlayer(player: VideoPlayerManager.shared.player)`
inconditionnel pour chaque cellule vidéo, y compris les voisines potentiellement gardées vivantes
par `TabView(.page)`)
IMPACT : Risque de "bleed" visuel (la vidéo en cours de lecture apparaît brièvement sur la page
voisine pendant un swipe) — non confirmable sans test réel.
SUGGESTED_STATUS : DEVICE_TEST_REQUIRED
RECOMMANDATION : Tester sur device un swipe entre 2 posts vidéo consécutifs ; si confirmé, gater le
binding `VideoPlayer(player:)` lui-même (pas seulement la lecture) sur `isActive`.
```

---

## 7. Recherche

```
ID : V4-F-035
PRIORITÉ : P2
DOMAINE : Search
FEATURE : L'historique de recherche perd le contexte d'onglet (pas de préfixe #/@ à la sauvegarde)
ANDROID SOURCE : Recherche/ui/RechercheTiinver.java:210,324-328,433-447 (`buildDisplayEntry`,
préfixe selon l'onglet actif à CHAQUE site de sauvegarde)
IOS FILES : Discover/SearchView.swift:322-336 (`runSearch`, sauvegarde toujours la query brute)
IMPACT : Retaper une entrée d'historique sauvegardée sous l'onglet Hashtags/Utilisateurs restaure
l'onglet "Tous" au lieu du bon onglet — résultats potentiellement différents de ce qui a été sauvegardé.
RECOMMANDATION : Ajouter un équivalent de `buildDisplayEntry` préfixant selon l'onglet actif avant
`RecentSearchStore.save`.
```

```
ID : V4-F-036
PRIORITÉ : P3
DOMAINE : Search
FEATURE : Un échec réseau sur le chemin "suggestion" affiche le mauvais message/la mauvaise sévérité
ANDROID SOURCE : RechercheTiinver.java:412-430 (`showEmpty("Aucun résultat")`, neutre)
IOS FILES : Discover/SearchView.swift:288-296 (`errorText = "Erreur de chargement."`, rouge)
IMPACT : Un simple hoquet réseau sur une query de 1 caractère affiche une bannière rouge alarmante
au lieu du message neutre "Aucun résultat" qu'Android affiche pour ce même cas.
RECOMMANDATION : Dans `suggest(_:)`, ne pas positionner `errorText` en cas d'échec.
```

```
ID : V4-F-037
PRIORITÉ : P3
DOMAINE : Search
FEATURE : `error:true` explicite du backend fusionné avec le message "aucun résultat pour {query}"
ANDROID SOURCE : RechercheTiinver.java:461-467 (message différent, sans nom de query) vs :567
IOS FILES : Discover/SearchRepository.swift:54-62 ; SearchView.swift:120-126
IMPACT : Différence de texte cosmétique uniquement, aucune perte fonctionnelle.
RECOMMANDATION : Priorité basse — optionnel, threader un flag distinct si jugé utile.
```

---

## 8. Chat / Socket.IO

```
ID : V4-F-038
PRIORITÉ : P1
DOMAINE : Chat-Socket
FEATURE : Un message arrivé en direct est perdu s'il arrive pendant le chargement initial de
l'historique (race condition)
ANDROID SOURCE : messagerie/ui/ChatFragmentTest.java:217,649,949,1381-1521 (append+dédup dans UNE
liste partagée, jamais de remplacement complet)
IOS FILES : Messagerie/ChatViewModel.swift:73-84 (`loadInitial()` remplace `items` inconditionnellement
après un `await`, écrasant tout ce qu'`onIncoming` aurait ajouté pendant ce même `await`)
IMPACT : Un message reçu par socket dans la brève fenêtre entre l'ouverture d'une conversation et la
fin du chargement de son historique disparaît visuellement (bien que persisté en Core Data) jusqu'à
fermeture/réouverture de la conversation.
RECOMMANDATION : Faire de `loadInitial()` une fusion (dédup-append) plutôt qu'un remplacement complet
de `items`.
STATUT : BUILD_VALIDATED (2026-08-23, commit d093438, CI run 32675426271 succès). Reconfirmé côté
Android : `messages` (`ChatFragmentTest.java:220`) est un `LinkedList<MessageLib>` UNIQUE, jamais
réassigné en bloc. Corrigé : `loadInitial()` fusionne désormais la page fraîchement chargée avec tout
message encore présent dans `items` après l'`await` (donc arrivé via `onIncoming` pendant la fenêtre
de course) et absent de cette page, trie l'ensemble par `stamp`, puis reconstruit les séparateurs de
date sur la liste fusionnée — remplace le remplacement inconditionnel par une fusion dédup, fidèle au
principe append-only Android. DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED (scénario difficile
à provoquer de façon fiable sans outillage — envoyer un message depuis un second appareil/pair dans la
fenêtre très brève entre l'ouverture d'une conversation et la fin de `messages.page(...)` ; ralentir
artificiellement `messages.page` en debug pour élargir la fenêtre et confirmer que le message envoyé
pendant ce délai reste visible sans fermer/rouvrir la conversation).
```

```
ID : V4-F-039
PRIORITÉ : P2
DOMAINE : Chat-Socket / Groups
FEATURE : Les messages système "deleteMember"/"addMember" ne mettent jamais à jour l'état
d'appartenance local ni ne quittent la room socket
ANDROID SOURCE : messagerie/ui/ChatManager.java:1190-1282,1263-1281 (retire la ligne membre locale,
bascule un flag d'appartenance, ÉMET `leaveRoom` si l'utilisateur courant est retiré)
IOS FILES : Storage/MessageRepository.swift:128-173 (`addGroupMessage` — gap AUTO-DOCUMENTÉ dans le
code lui-même comme non traité)
IMPACT : Un utilisateur retiré d'un groupe voit le bon message système, mais l'app ne signale jamais
au serveur avoir quitté la room, et aucun état local d'appartenance n'est mis à jour.
RECOMMANDATION : Ajouter la gestion des verbes `deleteMember`/`addMember` avec mise à jour d'état
local + `leaveRoom` émis quand l'utilisateur courant est retiré.
```

---

## 9. WebRTC / Appels

```
ID : V4-F-040
STATUT : **BUILD_VALIDATED (corrigé `14e5ee1`, Phase B Lot P0-2, CI verte confirmée run
`32664500075` — voir PROGRESS_V4.md ; test réel quasi impossible sans backend VoIP fonctionnel, voir
détail)** — statut avant : ouvert (audit Phase A)
PRIORITÉ : P0
DOMAINE : WebRTC-Calls
FEATURE : Un push VoIP reçu alors qu'un appel est déjà en cours saute le report CallKit obligatoire
ANDROID SOURCE : Aucun équivalent (obligation spécifique à PushKit/CallKit iOS)
IOS FILES : Calls/CallCoordinator.swift:198-202 (`guard state == .idle else { onReported?(); return }`,
AUCUN appel à `reportIncomingCall` dans cette branche) ; :464-487 (site d'appel du delegate VoIP)
DIFFÉRENCE : La branche "payload malformé" de cette MÊME fonction reporte bien un appel générique
avant de terminer (déjà corrigé lors d'un cycle antérieur) — mais la branche "déjà occupé", atteinte
par le même chemin, n'a AUCUNE gestion équivalente.
IMPACT : Violations répétées de l'obligation PushKit ("chaque push VoIP DOIT provoquer un report")
peuvent entraîner la révocation par iOS du droit de l'app à recevoir des push VoIP — casserait
silencieusement et durablement le réveil pour appel entrant en arrière-plan/app tuée.
PREUVE : `CallCoordinator.swift:198-202` sans appel `callKit.reportIncomingCall`, contrairement à la
branche payload malformé (lignes 476-482) qui le fait.
RECOMMANDATION : Reporter un appel générique puis le terminer immédiatement (même motif que la branche
payload malformé) quand `state != .idle` sur le chemin push VoIP, avant `onReported()`.
```

```
ID : V4-F-041
PRIORITÉ : P2
DOMAINE : WebRTC-Calls
FEATURE : L'accusé "sonnerie" (ringing) n'est jamais renvoyé à l'appelant
ANDROID SOURCE : messagerie/service/CallService.java:591-623,663-674 (`onRinging()` appelé
inconditionnellement dès le début du traitement d'un appel entrant, émet `ROOM.RINGING`)
IOS FILES : Realtime/ChatRepository.swift:456 (`onRinging` défini, ZÉRO site d'appel confirmé par
grep) ; Calls/CallCoordinator.swift:198-228 (`handleIncomingCall`, aucun appel équivalent)
IMPACT : Un appelant Android vers un callee iOS ne voit jamais son état basculer vers "Sonnerie…" et
son re-déclenchement de push toutes les 5s ne s'arrête jamais tant que l'appel n'est pas répondu/
terminé.
RECOMMANDATION : Appeler `chatRepository.onRinging(...)` depuis `handleIncomingCall`, juste après un
`reportIncomingCall` réussi.
```

```
ID : V4-F-042
PRIORITÉ : P1
DOMAINE : WebRTC-Calls
FEATURE : La notification d'appel manqué se déclenche du mauvais côté de l'appel (logique inversée)
ANDROID SOURCE : messagerie/ui/call/CallActivity.java:85,467-480,503-507,509-525 (enregistré
UNIQUEMENT côté APPELANT, quand un appel sortant non répondu se termine)
IOS FILES : Calls/CallCoordinator.swift:347-357 (`performEndCall`, condition `if !isOutgoingCall,
!wasAnswered` — déclenché côté CALLEE, jamais côté appelant)
DIFFÉRENCE : La condition est inversée par rapport à Android.
IMPACT : Un utilisateur iOS qui passe un appel non répondu et raccroche n'obtient AUCUN message
"appel manqué" (le scénario exact qu'Android gère) ; inversement, iOS enregistre un message manqué
côté callee qu'Android ne génère jamais lui-même de ce côté — risque de doublon/incohérence en
interopérabilité avec un appelant Android.
RECOMMANDATION : Inverser la garde (`isOutgoingCall && !wasAnswered`) pour matcher le comportement
Android, et réévaluer si le déclenchement côté callee doit être retiré.
STATUT : BUILD_VALIDATED (2026-08-23, commit 9de2d73, CI run 32674952912 succès). Reconfirmé par
relecture directe de `CallActivity.java` (entier) + `CallService.java:571-612` : `CallActivity` (qui
possède `isCalleMissedCall`/`notifyMissedCall`) n'est lancée QUE pour `callType ==
CallModel.OUTGOINGCALL` — le côté entrant route TOUJOURS vers `IncomingCallActivity`, classe séparée
qui n'appelle jamais `notifyMissedCall`. `isCalleMissedCall` (init `true`) n'est remis à `false` que
sur acceptation ou `callEnd()` reçu du socket (l'autre partie a terminé l'appel) ; `endCall()`
déclenche `notifyMissedCall` UNIQUEMENT si encore `true` — donc UNIQUEMENT côté appelant, sur un
appel sortant jamais décroché ni terminé par l'autre partie. Correctif : garde simplement inversée
(`if isOutgoingCall, !wasAnswered`), retrait du déclenchement côté callee comme suggéré par la
recommandation — pas de logique supplémentaire nécessaire, la seule instance de `notifyMissedCall`
dans tout le projet (`grep`) est celle corrigée ici. DEVICE_TEST_REQUIRED pour
COMPLETE_PARITY_VALIDATED (passer un appel sortant non répondu et raccrocher — confirmer le message
"appel manqué" ; recevoir un appel entrant et le refuser — confirmer l'ABSENCE de ce message côté
callee, avec un pair Android réel des deux côtés si possible pour vérifier l'interopérabilité).
```

```
ID : V4-F-043
PRIORITÉ : P2
DOMAINE : WebRTC-Calls
FEATURE : Un échec de report CallKit est silencieusement avalé, WebRTC démarre quand même
ANDROID SOURCE : Aucun équivalent
IOS FILES : Calls/CallCoordinator.swift:216-227 (`try? await callKit.reportIncomingCall(...)`, puis
poursuite inconditionnelle vers `fetchTurnAndStart`)
IMPACT : Dans le cas (rare mais réel) où CallKit rejette le report (Ne pas déranger, liste de blocage,
etc.), l'app consomme quand même des ressources réseau/audio pour un appel que l'utilisateur ne peut
ni voir ni décrocher.
RECOMMANDATION : `do/catch` réel ; sur échec, `teardown()` immédiat au lieu de poursuivre.
```

```
ID : V4-F-044
PRIORITÉ : P3
DOMAINE : WebRTC-Calls
FEATURE : Aucune tonalité de retour d'appel (ringback) pendant que le téléphone du callee sonne
ANDROID SOURCE : messagerie/service/CallService.java:790-802 (`playOutgoingSound`)
IOS FILES : Aucun (grep `AVAudioPlayer|ringback|SystemSoundID` sur `Calls/` = zéro résultat)
IMPACT : Mineur — actuellement inatteignable en pratique de toute façon (V4-F-041 non corrigé).
RECOMMANDATION : Ajouter une tonalité en boucle une fois V4-F-041 corrigé.
```

```
ID : V4-F-045
PRIORITÉ : P3
DOMAINE : WebRTC-Calls
FEATURE : Fin d'appel "occupé" immédiate côté iOS vs délai de grâce de 3s côté Android
ANDROID SOURCE : messagerie/ui/call/CallActivity.java:483-500 (affiche "occupé" 3s avant de fermer)
IOS FILES : Calls/CallCoordinator.swift:111-112 (fermeture immédiate)
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Optionnel — ajouter un état "occupé" transitoire de ~3s si la parité visuelle exacte
est désirée.
```

---

## 10. Animems — Engine / Runtime / Import-Export

**Note de portée** : le moteur Android vit dans un module SÉPARÉ, `com.animems.engine.*`
(`engine/src/main/java/com/animems/engine/`), distinct du reste de l'app sous `com.tiinver`. Le
cœur du moteur (matrices de transformation, interpolation de keyframes, lissage Chaikin, boucle de
lecture, ordre de composition Canvas) a été vérifié ligne par ligne et est un port EXCEPTIONNELLEMENT
fidèle — aucune divergence trouvée à ce niveau. Deux bugs concrets ont été trouvés dans la couche
import/export.

```
ID : V4-F-046
PRIORITÉ : P1
DOMAINE : Animems-ImportExport
FEATURE : Collision de timestamp (PTS) entre la frame 0 et la frame 1 de la vidéo exportée
ANDROID SOURCE : engine/.../codec/MP4Encoder.java:1727,1753 (`frameIndex * FRAME_NS`, strictement
croissant depuis 0)
IOS FILES : Animems/AnimemesExporter.swift:202 (`ptsNs = max(frameDurationNs, f * frameDurationNs)`)
DIFFÉRENCE : Pour `f=0` ET `f=1`, la formule iOS donne EXACTEMENT la même valeur
(`frameDurationNs`) — deux échantillons vidéo au même timestamp, et aucun échantillon écrit à pts=0
alors que `startSession(atSourceTime: .zero)` fixe le début de session à t=0.
IMPACT : La vidéo exportée perd/corrompt probablement sa toute première frame (timestamps dupliqués
généralement fusionnés/indéfinis par `AVAssetWriter`), ou laisse un trou de ~33ms non défini en
début de lecture — défaut visible absent côté Android, avec un risque de désynchronisation audio/
vidéo d'une frame si une piste audio est attachée.
PREUVE : Substitution directe — `f=0` et `f=1` produisent la même constante.
RECOMMANDATION : Retirer le `max(...)` — le PTS doit être simplement `Int64(f) * frameDurationNs`,
comme Android. Vérifier d'abord qu'aucune raison historique (ex. un crash passé) ne justifiait ce
garde-fou avant de le retirer.
STATUT : BUILD_VALIDATED (2026-08-23, commit b0b61ea, CI run 32676432499 succès). Aucune raison
historique trouvée justifiant le `max(...)` (aucun commentaire, aucune trace dans l'historique local
du fichier) — retiré tel que recommandé. Reconfirmé côté Android : `MP4Encoder.java:1753`
(`getPresentationTimeUsec(frameIndex) { return frameIndex * FRAME_NS; }`) sans clamp équivalent.
Seul `f=0` change de valeur (0 au lieu de `frameDurationNs`) ; `f>=1` calculait déjà la même valeur
avec ou sans le `max`, aucun risque de régression sur les frames suivantes. Aucun autre site de calcul
de PTS trouvé dans le module Animems (`grep frameDurationNs`/`ptsNs`). DEVICE_TEST_REQUIRED pour
COMPLETE_PARITY_VALIDATED (exporter une vidéo réelle, inspecter les métadonnées de la piste vidéo
[ex. `ffprobe`] pour confirmer la 1ʳᵉ frame à pts=0 et l'absence de doublon de timestamp ; vérifier
visuellement qu'aucune frame n'est perdue en tout début de lecture).
```

```
ID : V4-F-047
PRIORITÉ : P2
DOMAINE : Animems-ImportExport
FEATURE : La mise à l'échelle de translation d'un template de mouvement diverge de la formule
(buggée) d'Android lors d'un changement de taille de canevas
ANDROID SOURCE : engine/.../template/MotionTemplateManager.java:98,225-241 — formule quadratique en
`targetCanvasWidth` : `valeur_normalisée × targetCanvasWidth × (targetCanvasWidth/templateCanvasWidth)`
IOS FILES : Animems/MotionTemplateManager.swift:143,156-158 — formule linéaire correcte :
`valeur_normalisée × targetCanvasWidth` (le facteur `scaleX` d'Android n'a pas été repris)
DIFFÉRENCE : Identique quand les tailles de canevas correspondent (cas courant). Pour un template
appliqué à un canevas de taille DIFFÉRENTE de celle où il a été capturé, Android mal-positionne
l'objet de façon quadratique (souvent hors-écran) ; iOS le positionne correctement/linéairement —
un écart visuel réel dans un sens ou dans l'autre selon quelle version est jugée "correcte".
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Décision Phase B explicite requise — répliquer le bug Android pour une parité octet-
à-octet, ou documenter formellement la correction iOS comme `IOS_INTENTIONAL_DIFFERENCE` (le code
actuel n'a aucun commentaire expliquant cet écart, il se lit comme un oubli plutôt qu'une décision).
```

*(Note architecturale informative, pas un bug)* : le moteur iOS est entièrement Core Graphics (pas de
pipeline GL/Metal), une décision vérifiée et justifiée — `MemesView2.java` n'utilise que des modes
`PorterDuff` directement exprimables en `CGBlendMode`. Pertinent seulement si une fonctionnalité pas
encore portée (flou d'arrière-plan, compositing d'outro vidéo) exige un jour un vrai pipeline GPU.

---

## 11. Animems — UI / Interaction

```
ID : V4-F-048
PRIORITÉ : P1
DOMAINE : Animems-Interaction
FEATURE : Les contrôles de zoom du canevas mettent à jour le libellé mais ne zooment jamais
visuellement le canevas
ANDROID SOURCE : engine/.../views/CanvasZoomController.java:94-117 (`setScaleX/setScaleY` réels sur
la vue)
IOS FILES : Animems/CanvasZoomController.swift:33-40 (mutation de `currentScale` seule) ; Animems/
AnimemesEditorView.swift:434-489,521-527 (aucun `.scaleEffect` ni transform reliant `currentScale`
au `Canvas` réellement rendu)
IMPACT : Impossible de zoomer pour affiner un petit objet ou dézoomer pour voir du contenu hors-
canevas ; les boutons semblent fonctionner (le libellé "1.25×" change) mais n'ont aucun effet visuel
— se lit comme cassé/non réactif.
PREUVE : Le commentaire de tête de `zoomControls` documente déjà ce risque comme non résolu ("Le
zoom ne zoome toujours pas visuellement le canevas après ce lot").
RECOMMANDATION : Envelopper le `Canvas` de rendu dans un conteneur zoom/pan appliquant réellement
`currentScale`, en corrigeant explicitement l'espace de coordonnées des gestes en conséquence.
STATUT : BUILD_VALIDATED (2026-08-23, commit da0e744, CI run 32677174090 succès). Chaîne complète
tracée avant correction (UI boutons → `CanvasZoomState` → rendu `Canvas` → `combinedGesture` →
`AnimemesExporter`), conformément à la consigne explicite de rigueur de l'utilisateur pour Animems.
`CanvasZoomState` (algorithme `computeMinZoom`/`zoom(delta)`/`reset`) déjà fidèle avant ce lot — seul
le RENDU manquait. Corrigé SANS la correction de coordonnées de geste que redoutait le commentaire
existant : `.scaleEffect(zoomState.currentScale)` appliqué APRÈS `.gesture(combinedGesture)` dans la
chaîne de modificateurs — `.scaleEffect` étant un `GeometryEffect` SwiftUI de premier ordre, les
coordonnées tactiles continuent d'être rapportées dans l'espace local NON transformé du `Canvas`,
donc `AnimemesEditorState.dragMoved`/`selectObject`/etc. n'ont nécessité AUCUNE modification. Vérifié
en plus (au-delà du strict périmètre du finding) : `AnimemesExporter.render(frame:into:)` dessine
dans un `CVPixelBuffer`/`CGContext` totalement indépendant du pipeline `Canvas`/`.scaleEffect`
interactif — confirmant qu'iOS n'a PAS besoin de l'équivalent des 2 appels `zoomController.reset()`
qu'Android fait avant encodage (architectures différentes ici, pas un gap). Raisonnement sur le
comportement SwiftUI documenté mais NON vérifiable empiriquement dans cet environnement (pas de
Xcode/simulateur) — DEVICE_TEST_REQUIRED IMPÉRATIF pour COMPLETE_PARITY_VALIDATED : zoomer via +/−,
confirmer l'effet visuel réel, ET vérifier qu'un geste de glissement/pincement/rotation sur un objet
à `currentScale != 1.0` reste cohérent avec le doigt (aucune dérive de coordonnées) — ce SECOND point
est le risque technique réel que ce correctif ne peut pas garantir sans test sur device.
```

```
ID : V4-F-049
PRIORITÉ : P1
DOMAINE : Animems-Interaction
FEATURE : Les marqueurs de keyframe sur la timeline n'ont aucune cible tactile — sélection/suppression
inatteignables
ANDROID SOURCE : engine/.../views/TimelineView.java:168-170,833-850,1054-1078 ; AnimemesCompound.java
:1356-1372 (1er tap = sélection, 2e tap sur le MÊME keyframe = suppression)
IOS FILES : Animems/TimelineViewModel.swift:333-350 (`hitTestKeyframeMarker`, PORTÉ, zéro appelant) ;
Animems/KeyframeTrack.swift:70-72 (`removeKeyframe(id:)`, PORTÉ, zéro appelant) ; Animems/TimelineView
.swift:149-221 (`combinedDragGesture` ne référence jamais `hitTestKeyframeMarker`)
DIFFÉRENCE : Logique de hit-test ET de suppression fidèlement portée, mais jamais câblée au
gestionnaire de gestes — motif classique "logique portée, jamais invoquée".
IMPACT : Aucun moyen de supprimer un keyframe précis par erreur — seul recours : "réinitialiser"
TOUTE l'animation du calque, une sur-correction destructrice qu'Android n'impose pas.
RECOMMANDATION : Appeler `model.hitTestKeyframeMarker` avant le repli vers `resolveMode` dans
`combinedDragGesture` ; un second tap sur le même keyframe appelle `KeyframeTrack.removeKeyframe`.
STATUT : BUILD_VALIDATED (2026-08-23, commit fc60738, CI run 32677846820 succès). Chaîne complète
tracée avant câblage (UI/geste Android → état Android → UI/geste Swift → état Swift → rendu),
conformément à la rigueur renforcée demandée pour Animems. `hitTestKeyframeMarker` appelé en PREMIER
dans `combinedDragGesture`, avant `resolveMode` — fidèle à `onDown` qui teste le hit keyframe avant
tout repli icône/scrub/item et consomme ENTIÈREMENT la touche en cas de succès (nouveau cas
`DragMode.keyframeTap` reproduisant ce `return true`). 1er tap = sélection (`selectedKeyframeId`,
nouveau sur `TimelineViewModel`) ; 2e tap sur le MÊME keyframe = suppression
(`AnimemesEditorState.deleteKeyframe`, nouveau, port de `onKeyframeDeleteRequested`) via
`AnimationObjectData.removeKeyframe` (nouveau, port de `KeyframeTrack.removeKeyframe` +
`obj.removeTrack` si la piste devient vide). Détail supplémentaire porté au-delà du strict texte de
l'audit : le contour blanc de sélection (`kfSelectPaint`, `TimelineView.java:704`) ajouté à
`drawKeyframeMarkers`, sans quoi l'utilisateur n'aurait aucun moyen visuel de savoir quel keyframe
est armé pour suppression au prochain tap. DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED :
tap sur un keyframe (confirmer le contour blanc), tap à nouveau dessus (confirmer la suppression ET
que le canevas principal reflète la valeur interpolée mise à jour), tap sur un AUTRE keyframe après
sélection (confirmer un simple changement de sélection, PAS de suppression).
```

```
ID : V4-F-050
PRIORITÉ : P1
DOMAINE : Animems-UI
FEATURE : Icônes verrou/visibilité par calque totalement absentes, aucune protection au niveau geste
ANDROID SOURCE : engine/.../views/AnimemesCompound.java:1639-1681 (icônes verrou+œil par ligne de
timeline) ; MemesView2.java:1577-1608 (les gestes tap/scroll/scale IGNORENT explicitement un calque
verrouillé)
IOS FILES : AUCUNE UI (TimelineView.drawItem ne dessine que le clip/label/poignées) ; `obj.locked`
n'est JAMAIS basculé par une action utilisateur (lu seulement par l'import/export de template) ;
`AnimemesGestureController` ne teste JAMAIS `.locked`
DIFFÉRENCE : Toute une catégorie d'interaction (protéger/masquer un calque) absente à la fois comme
affordance UI ET comme application au niveau des gestes.
IMPACT : Aucun moyen de protéger un calque terminé contre un glissement accidentel pendant qu'on
travaille sur d'autres, ni de masquer temporairement un calque.
RECOMMANDATION : Ajouter les icônes verrou/visibilité par ligne de `TimelineView`, câblées à de
nouvelles méthodes `toggleLocked(id:)`/`toggleVisible(id:)`, et ajouter une garde `obj.locked` en
sortie précoce dans `AnimemesGestureController.isPoint`/`touchDown`/`scale`/`rotate`.
STATUT : BUILD_VALIDATED (2026-08-23/24, commits 8ab3088 + 1ff1032 [correctif CI], CI run 32679329863
succès). Chaîne complète tracée sur les DEUX architectures Android AVANT câblage — la recommandation
initiale de l'audit était imprécise (citait `touchDown`/`isPoint` comme sites de garde) : relecture
directe de `MemesView2.java` confirme QUE 3 sites réels vérifient `.isLocked()`
(`onScroll`/`onScale`/la boucle `onTouchEvent` dont `executeTouchEvent`→`rotate` dépend), AUCUN dans
`touchDown`/`isPointInsideObject` — un calque verrouillé reste donc SÉLECTIONNABLE côté Android,
seule la manipulation réelle est bloquée. Reproduit fidèlement : garde `!layers[idx].locked` ajoutée
à `dragMoved`/`rotationChanged`/`scaleChanged` (PAS `selectObject`). Icônes verrou/œil dessinées dans
le panneau gauche de `TimelineView` (jusqu'ici vide), lues directement depuis
`AnimationObjectData.locked/.visible` (chemin plus simple que le registre générique
`trackIcons`/`addTrackIcon` déjà présent mais orphelin, réservé à la 3ᵉ icône Android "compose
group", fonctionnalité séparée déjà différée ailleurs). `toggleLocked`/`toggleVisible` (nouveau)
bascule `version`, fidèle à `mView.prepare()+applyInterpolation()+postInvalidate()` Android après
CHAQUE clic d'icône. **Incident CI** : 1er commit (8ab3088) a échoué en CI
(`Image.foregroundColor`/`resolve` ambigu sous Xcode 16.2) — corrigé en 2ᵉ commit (1ff1032) en
dessinant via `Text(Image(systemName:))` (motif déjà éprouvé dans ce fichier, `drawRuler`) plutôt
que `context.resolve(Image(...))`. DEVICE_TEST_REQUIRED pour COMPLETE_PARITY_VALIDATED : taper
l'icône verrou (confirmer bascule visuelle + qu'un glissement/pincement/rotation du calque est
ensuite BLOQUÉ), taper l'icône œil (confirmer bascule + masquage réel du rendu), confirmer qu'un
calque verrouillé reste TAPABLE/sélectionnable (pas totalement exclu de l'interaction).
```

```
ID : V4-F-051
PRIORITÉ : P2
DOMAINE : Animems-Interaction
FEATURE : Faire défiler (pan) la timeline ne resynchronise jamais le moteur de lecture — Play peut
reprendre depuis une frame obsolète
ANDROID SOURCE : engine/.../views/TimelineView.java:938-954 ; AnimemesCompound.java:1417-1426
(PAN ET scrub appellent tous deux `mView.seek(frame)`)
IOS FILES : Animems/TimelineView.swift:163-190 (seul `.scrub` appelle `state.scrub(toFrame:)` ; le
cas `.pan` met à jour uniquement `TimelineViewModel.playheadFrame`, jamais `engine.totalFrame`)
IMPACT : Après un pan pour revoir une section, l'aperçu canevas montre la bonne frame, mais `Play`
peut visiblement sauter en arrière vers une frame différente de celle affichée à l'écran.
RECOMMANDATION : Appeler `state.scrub(toFrame: model.playheadFrame)` dans le cas `.pan` également.
```

```
ID : V4-F-052
PRIORITÉ : P2
DOMAINE : Animems-Interaction
FEATURE : Aucun appui long pour ramener un calque au premier plan
ANDROID SOURCE : engine/.../memes/MemesView2.java:1571-1574,1613-1616 (appui long sur le canevas →
calque le plus haut sous le doigt → premier plan)
IOS FILES : Animems/AnimemesGestureController.swift:74-82 (`bringLayerToFront`, PORTÉ, zéro appelant) ;
aucun `LongPressGesture` nulle part dans `AnimemesEditorView.swift` (930 lignes, lecture complète)
IMPACT : Aucun moyen direct de faire remonter un calque enfoui sous d'autres par manipulation directe.
RECOMMANDATION : Ajouter un `LongPressGesture` (avec vérification sur device, historique de
régressions de composition de gestes documenté dans ce fichier) résolvant le calque le plus haut et
appelant `bringLayerToFront`, déjà prêt.
```

```
ID : V4-F-053
PRIORITÉ : P3
DOMAINE : Animems-Interaction
FEATURE : Taper une zone vide de la timeline ne désélectionne pas le calque courant
ANDROID SOURCE : engine/.../views/TimelineView.java:879-887 ; AnimemesCompound.java:1406-1414
(sélection explicitement mise à `null`, cascade sur le panneau/boutons dépendants)
IOS FILES : Animems/TimelineView.swift:149-161 (`.pan` → `break` explicite, ne touche jamais
`state.selectedId`)
IMPACT : Mineur — incohérence entre canevas (qui gère bien la désélection sur tap vide) et timeline
(qui ne le fait pas) au sein du même écran.
RECOMMANDATION : `state.selectedId = nil` dans le repli `.pan` sans item touché.
```

```
ID : V4-F-054
PRIORITÉ : P3
DOMAINE : Animems-Interaction
FEATURE : L'appui long pour ouvrir le panneau de propriétés est remplacé par un bouton de barre
d'outils dédié (substitution délibérée et documentée)
ANDROID SOURCE : engine/.../views/TimelineView.java:912-914 ; AnimemesCompound.java:1634-1637
IOS FILES : Animems/AnimemesEditorState.swift:387-407 (justification en commentaire) ; AnimemesEditorView
.swift:873-883 (bouton "propriétés")
SUGGESTED_STATUS : IOS_INTENTIONAL_DIFFERENCE
IMPACT : Faible — résultat final équivalent, geste déclencheur différent (bouton visible vs appui
long non indiqué).
RECOMMANDATION : Aucune action requise — substitution déjà raisonnée compte tenu de l'historique de
fragilité de composition de gestes documenté dans ce même fichier.
```

```
ID : V4-F-055
PRIORITÉ : P3
DOMAINE : Animems-UI
FEATURE : HUD de diagnostic de gestes en permanence à l'écran dans l'UI de production
ANDROID SOURCE : Aucun équivalent
IOS FILES : Animems/AnimemesEditorView.swift:124-127,385-402 (`gestureDiagnosticsHUD`, PAS de garde
`#if DEBUG`, propre commentaire de tête le qualifiant lui-même de "TEMPORAIRE, à retirer")
IMPACT : Bande de texte de debug (IDs internes, trace de gestes) visible par TOUS les utilisateurs
en TOUTE configuration de build, occupant de l'espace vertical au-dessus du canevas.
RECOMMANDATION : Gater `gestureDiagnosticsHUD` derrière `#if DEBUG` maintenant que le pipeline de
gestes a été éprouvé sur plusieurs cycles de correction.
```

---

## 12. Galerie / Éditeur photo

```
ID : V4-F-056
PRIORITÉ : P1
DOMAINE : Gallery-PhotoEditor
FEATURE : Le recadrage libre (freeform) ignore l'orientation EXIF — photos portrait rendues de côté/
en miroir
ANDROID SOURCE : engine/.../croper/BitmapLoadingWorkerTask.java:76 ; CropImageView.java:981-994 —
`rotateBitmapByExif` appliqué en amont pour TOUS les sous-modes de recadrage (rect/oval/freeform)
IOS FILES : Feed/PublishComposeView.swift:111-125 ; PhotoEditor/FreeformCropView.swift:11-38 —
`image.cgImage` brut passé directement, dessiné via `Image(decorative:)` qui IGNORE
`imageOrientation` entièrement
DIFFÉRENCE : Le mode rect/oval est correct (passe par `TOCropViewController`, orientation préservée) ;
SEUL le mode freeform opère sur le buffer brut non-tourné.
IMPACT : Pour toute photo à orientation EXIF non-`.up` (cas courant pour une photo portrait), choisir
"Freeform" à la publication affiche l'image de côté ou en miroir pendant le tracé, ET compose le
résultat final contre ce buffer mal orienté.
RECOMMANDATION : Normaliser l'orientation vers `.up` avant de construire le `cgImage` passé à
`FreeformCropStepView` (ex. via un passage `UIGraphicsImageRenderer` respectant `imageOrientation`).

STATUT : BUILD_VALIDATED (2026-08-24) — Vérifié contre `BitmapLoadingWorkerTask.java:76`
(`rotateBitmapByExif` appliqué en amont, avant tout branchement rect/oval/freeform) et
`CropImageView.java:981-994` (même fonction, second point d'entrée). Confirmé côté iOS que
`PublishComposeView.swift`'s `.freeformCropping` passait `image.cgImage` brut à
`FreeformCropStepView`, dessiné via `Image(decorative:)` (`FreeformCropView.swift:18`) — cette API
ignore `imageOrientation`, contrairement au mode rect/oval (`TOCropViewController`, déjà correct).
Correctif : nouvelle méthode privée `UIImage.normalizedToUpOrientation()` (redessine via
`UIGraphicsImageRenderer`/`draw(in:)`, qui respecte `imageOrientation`) appliquée avant extraction
du `cgImage` ; le résultat découpé (`FreeformCropView.croppedImage`) est reconstruit avec
`orientation: .up` (pas `image.imageOrientation`, qui aurait doublé la rotation puisque la source
est déjà normalisée). Flux frère vérifié : `PhotoCropView.swift:54` (mode oval) opère sur
`croppedImage.cgImage` — mais APRÈS le passage par `TOCropViewController`, dont la sortie a déjà
ses pixels physiquement tournés (orientation `.up` de fait) ; pas affecté. `PhotoToolsView.swift`
(flip/removeBackground) propage `imageOrientation` d'un bout à l'autre, affiché via `Image(uiImage:)`
(pas `decorative:`) ; pas affecté. Les usages `Image(decorative:)` dans le module Animems
(`PaintCapture.swift`, `ShapePreviewEditorPanelView.swift`) opèrent sur des calques/stickers
générés en interne, jamais sur une photo EXIF importée — hors périmètre de ce finding. Commit code
`29385f5`, push confirmé (`c1cb713..29385f5 main -> main`), CI run `32682553930` conclusion
`success`. DEVICE_TEST_REQUIRED pour passer en COMPLETE_PARITY_VALIDATED (aucun accès
Xcode/simulateur dans cet environnement — le raisonnement sur `UIGraphicsImageRenderer` respectant
`imageOrientation` est standard-documenté mais non vérifié visuellement sur une vraie photo
portrait EXIF).
```

```
ID : V4-F-057
PRIORITÉ : P2
DOMAINE : Gallery-PhotoEditor
FEATURE : Sémantique d'annuler/supprimer un objet divergente d'Android — mauvaise priorité
chronologique
ANDROID SOURCE : engine/.../views/ImageEditorCompound.java:458-460,565-566,590-591 ; ImageViewCanvas
.java:317-326,854-862,1712-1721 — "annuler" ne concerne QUE le dernier trait de peinture ; texte/
stickers sont individuellement sélectionnables et supprimables via une icône dédiée, indépendamment
de l'ordre chronologique
IOS FILES : PhotoEditor/PhotoToolsView.swift:139-141,171-177 — un seul bouton "annuler" global
retirant toujours le dernier TEXTE en premier, puis seulement le dernier TRAIT une fois `texts` vide
— pas un vrai suivi chronologique
DIFFÉRENCE : Android permet de retirer précisément un objet ancien ou récent (texte/sticker/image),
tandis que son bouton "annuler" propre ne touche que la peinture. iOS fusionne tout en un "annuler"
global prouvablement incorrect pour des éditions entrelacées (ex. trait→texte→trait retire le texte
au lieu du trait réellement le plus récent).
RECOMMANDATION : Suivre une pile chronologique unique (enum trait/texte) et dépiler la vraie dernière
entrée ; évaluer si la suppression individuelle par tap vaut la peine d'être portée.
```

```
ID : V4-F-058
PRIORITÉ : P2
DOMAINE : Gallery-PhotoEditor
FEATURE : Le picker de galerie avale silencieusement les échecs de chargement — feuille bloquée
ANDROID SOURCE : editor/camera/BaseCameraFragment.java:218-227 (le picker système ne peut pas
atterrir sur un état "sélectionné mais échoué")
IOS FILES : Camera/GalleryPickerView.swift:55-76 — `loadFileRepresentation` : `{ url, _ in guard let
url else { return } ... }` ignore l'erreur, ni `onImagePicked`/`onVideoPicked` ni `onCancel` ne se
déclenchent sur échec
IMPACT : Sur un échec réel (asset iCloud non téléchargé, permission révoquée en cours de sélection,
erreur I/O transitoire), l'utilisateur reste bloqué derrière/sur la feuille de sélection, sans
message d'erreur, sans fermeture automatique.
RECOMMANDATION : Appeler `onCancel()` (avec éventuellement l'erreur affichée) quand `url == nil`,
comme le fait déjà le garde `results.first == nil` juste au-dessus.
```

---

## 13. Éditeur vidéo

```
ID : V4-F-059
PRIORITÉ : P1
DOMAINE : VideoEditor
FEATURE : La sélection de trim n'a aucun plafond continu de durée maximale — l'utilisateur peut
glisser au-delà de la limite de 60s
ANDROID SOURCE : editor/view/ProTimelineView.java:685-713 (`selMaxWidthPx`, appliqué à CHAQUE
déplacement de poignée, tout au long de l'édition) ; MediaTrim.java:175 (`setTrimeLimitMax(60000)`)
IOS FILES : Feed/MediaTrimView.swift:188-204 (`dragGesture` — seule une borne MINIMALE
`minHandleSpacing` est appliquée ; le chargement initial cadre la sélection par défaut à ≤60s, mais
rien n'empêche de l'étendre ensuite par glissement)
IMPACT : Un utilisateur peut publier un segment vidéo dépassant la limite prévue de 60s sur iOS, ce
qu'Android empêche structurellement à tout moment.
RECOMMANDATION : Ajouter un plafond de largeur maximale (60s, dérivé de `duration`) aux deux branches
de `dragGesture` dans `MediaTrimView.swift`.

STATUT : BUILD_VALIDATED (2026-08-24) — Vérifié contre `ProTimelineView.java:685-713`
(`handleMove`, cas `DRAG_LEFT_PX`/`DRAG_RIGHT_PX`) : `selMaxWidthPx` (dérivé de
`setTrimeLimitMax(60000)`, `MediaTrim.java:175`, ligne 316 `selMaxWidthPx = maxTrimMs /
viewWindowMs * w`) est reclampé à CHAQUE déplacement de poignée, dans les DEUX directions — si la
nouvelle largeur dépasserait la limite, la poignée en cours de déplacement est ramenée à la largeur
maximale (`newLeft = selRightPx - selMaxWidthPx` / `newRight = selLeftPx + selMaxWidthPx`), pas un
blocage dur du geste. Confirmé côté iOS que `MediaTrimView.dragGesture` (lignes 188-204) n'appliquait
qu'une borne MINIMALE (`minHandleSpacing`) — le cadrage initial (`load()`) limite bien la sélection
par défaut à `maxDurationSeconds` si la vidéo dépasse 60s, mais rien n'empêchait ensuite de
l'ÉTENDRE par glissement. Correctif : nouveau clamp `maxWidthFraction = min(1, maxDurationSeconds /
duration)` appliqué APRÈS le clamp minimal existant dans les deux branches (`isStart`/`!isStart`),
reproduisant fidèlement le comportement "recale la poignée en cours, ne bloque pas le geste"
d'Android. Flux frères vérifiés : `grep minHandleSpacing`/`dragGesture(isStart:` dans tout le projet
→ un seul site, `MediaTrimView.swift` — aucun autre écran ne reproduit ce motif de poignées de trim.
Commit `0e7f651`, push confirmé (`5088cb0..0e7f651 main -> main`), CI run `32683632141` conclusion
`success`. DEVICE_TEST_REQUIRED pour passer en COMPLETE_PARITY_VALIDATED (aucun accès
Xcode/simulateur dans cet environnement — test réel requis : charger une vidéo >60s, tenter
d'étendre la sélection au-delà de 60s en glissant chaque poignée, confirmer le plafond réel).
```

```
ID : V4-F-060
PRIORITÉ : P2
DOMAINE : VideoEditor
FEATURE : Flux complet "partager en externe avec outro promotionnel + filigrane animé" absent
ANDROID SOURCE : editor/PublishFragment.java:306-312,448-461,499-511 ; editor/service/
ExportVideoService.java (entier, composition d'outro + filigrane animé keyframé pour les utilisateurs
non-premium, partage direct du fichier vers n'importe quelle app externe, indépendamment de la
publication sur le fil Tiinver)
IOS FILES : AUCUN — `PublishComposeView.swift` n'a qu'une action "Publier", et son share-sheet ne
partage qu'un texte de légende APRÈS publication, jamais le fichier vidéo lui-même
IMPACT : Les utilisateurs non-premium iOS perdent le mécanisme de croissance de marque intégré à
Android (outro+filigrane) ; TOUS les utilisateurs iOS perdent la capacité de partager le fichier
vidéo édité vers une autre app sans d'abord le publier sur Tiinver.
RECOMMANDATION : Décider si c'est une simplification produit intentionnelle (documenter comme telle)
ou implémenter un flux équivalent si le mécanisme de croissance reste désiré.
```

```
ID : V4-F-061
PRIORITÉ : P2
DOMAINE : VideoEditor
FEATURE : La vidéo exportée/rognée n'est pas optimisée "fast-start" (atome moov non relocalisé)
ANDROID SOURCE : view/trimmer/VideoTrimmerView.java:710-729 (`Mp4Faststart.process(...)` après
chaque ré-encodage, avec repli sur le fichier non-optimisé en cas d'échec de cette passe elle-même)
IOS FILES : Feed/MediaTrimView.swift:319-335 (`trim()` — aucune étape équivalente ; `AVAssetExportSession`
écrit directement, `shouldOptimizeForNetworkUse` n'est PAS positionné)
IMPACT : Latence de démarrage/seek potentiellement plus élevée pour la lecture progressive des vidéos
uploadées depuis iOS (pertinent puisque certains chemins de lecture Bunny utilisent un MP4 direct en
repli, pas seulement HLS).
RECOMMANDATION : Ajouter une passe de relocalisation d'atome moov après `AVAssetExportSession`, ou au
minimum positionner `shouldOptimizeForNetworkUse = true`.
```

```
ID : V4-F-062
PRIORITÉ : P3
DOMAINE : VideoEditor
FEATURE : Preset de ratio de recadrage "3:4" manquant
ANDROID SOURCE : view/trimmer/VideoTrimmerView.java:265-288 (6 ratios : Libre/16:9/9:16/1:1/4:3/3:4)
IOS FILES : Media/VideoTrimState.swift:52-57 (seulement 5 : manque 3:4)
RECOMMANDATION : Ajouter `("3:4", .ratio(w: 3, h: 4))` aux presets.
```

```
ID : V4-F-063
PRIORITÉ : P3
DOMAINE : VideoEditor
FEATURE : Le recadrage vidéo est toujours centré automatiquement — pas de repositionnement interactif
ANDROID SOURCE : engine/.../views/CropOverlayView.java:341-389 (boîte de recadrage glissable,
position ajustable dans les limites de la vidéo)
IOS FILES : Feed/MediaTrimView.swift:388-409 (`composeTransform`, rectangle de recadrage toujours
calculé centré, aucune UI/geste de repositionnement)
SUGGESTED_STATUS : VISUALLY_DIFFERENT
IMPACT : Perte de contrôle du cadrage pour un sujet non centré — aucun moyen d'ajuster.
RECOMMANDATION : Optionnel — ajouter un geste de glissement sur une boîte de recadrage si la parité
exacte est désirée ; sinon documenter comme simplification intentionnelle.
```

---

## 14. BunnyCDN / Media

```
ID : V4-F-064
PRIORITÉ : P1
DOMAINE : BunnyCDN-Media
FEATURE : L'upload de pièce jointe de chat charge le fichier entier en RAM au lieu de le streamer
depuis le disque
ANDROID SOURCE : messagerie/service/UploadFileOrDataService.java:242-267,269-301
(`ProgressRequestBodyUri`, streaming par blocs de 8Ko pour TOUTE pièce jointe y compris vidéo, avec
progression réelle)
IOS FILES : Messagerie/ChatMediaUploadService.swift:59-73 (`put(localFile:...)` — `Data(contentsOf:)`
charge tout le fichier avant l'envoi, aucun délégué de progression)
DIFFÉRENCE : Exactement l'anti-pattern à risque OOM déjà corrigé pour l'upload vidéo du Feed principal
(`FeedMediaUploader.uploadVideo`, qui streame déjà correctement) — jamais appliqué au chemin Chat.
IMPACT : Envoyer une vidéo volumineuse (ou même une photo/document conséquent) en pièce jointe de
chat peut faire un pic mémoire significatif, avec risque de terminaison OOM sur appareil à mémoire
limitée ; aucune barre de progression pour les pièces jointes chat.
RECOMMANDATION : Passer `put(localFile:...)` à `URLSession.shared.upload(for:fromFile:delegate:)`, en
réutilisant `UploadProgressDelegate` déjà implémenté dans `FeedMediaUploader.swift`.

STATUT : BUILD_VALIDATED (2026-08-24) — Vérifié contre `UploadFileOrDataService.java:242-267`
(`uploadToBunny`, seul chemin réseau pour LES 4 types de pièce jointe — photo/vidéo/audio/doc,
`MyMediaType.fromKey(data.getObject())` sans branchement type-spécifique avant l'appel) et
`ProgressRequestBodyUri.java` (entier) : `writeTo` lit par blocs de 8192 octets depuis un
`InputStream` ouvert sur l'`Uri` du fichier, jamais de chargement intégral, avec calcul de
progression réel (`uploaded*100/contentLength`) à chaque bloc. Confirmé côté iOS que
`ChatMediaUploadService.put` faisait `try Data(contentsOf: localFile)` avant
`URLSession.shared.upload(for:from:)` — chargement intégral en mémoire, même anti-pattern déjà
identifié et corrigé pour `FeedMediaUploader.uploadVideo` (V3-F-019/BUNNY-03). Correctif : `put`
utilise maintenant `URLSession.shared.upload(for:fromFile:delegate:)`, streaming natif depuis le
disque sans jamais matérialiser le fichier entier en `Data` ; `UploadProgressDelegate`
(`FeedMediaUploader.swift`) rendue interne (pas `private`) et réutilisée telle quelle plutôt que
dupliquée, même motif de partage que les constantes BunnyCDN (V4-F-008) ; nouveau paramètre
`progress` optionnel propagé de `upload(...)` à `put(...)`, défaut `nil` (aucun appelant existant
ne branche encore de barre de progression — `ChatBubbleViews.swift` affiche déjà un `ProgressView()`
indéterminé tant que `isFileUploaded != 1`, fidèle à Android qui route sa propre progression vers
une notification système de service au premier plan, hors périmètre UI de ce finding, dont les
`IOS FILES` cités se limitent à `ChatMediaUploadService.swift`). Flux frères vérifiés : `grep
Data(contentsOf:` dans tout le projet → tous les autres usages chargent une image locale déjà en
cache pour l'affichage UI (pas un upload réseau) ; `grep URLSession.shared.upload(for:` → les 2
usages restants sur `from:` (Data en mémoire, `FeedMediaUploader.uploadPhoto`/
`ProfileRepository.uploadProfilePicture`) uploadent des PHOTOS compressées (webp), chemin non
streamé côté Android non plus (`uploadImageToBunny`, PAS `ProgressRequestBodyUri`) — pas affectés,
aucun changement nécessaire. Commit `1090279`, push confirmé (`ff1c20e..1090279 main -> main`), CI
run `32683050887` conclusion `success`. DEVICE_TEST_REQUIRED pour passer en
COMPLETE_PARITY_VALIDATED (aucun accès Xcode/simulateur dans cet environnement — test réel requis :
envoyer une pièce jointe volumineuse en chat, confirmer l'absence de pic mémoire significatif
[Instruments/Memory Graph] et la réussite de l'upload).
```

---

## 15. Wallet / Monétisation

```
ID : V4-F-065
STATUT : **BUILD_VALIDATED (corrigé `393b485`, Phase B Lot P0-1, CI verte confirmée run
`32663823532` — voir PROGRESS_V4.md ; test réel requis avant COMPLETE_PARITY_VALIDATED)** — statut
avant : ouvert (audit Phase A)
PRIORITÉ : P0
DOMAINE : Wallet-Monetization
FEATURE : Le crédit de récompense post-retrait/transfert/conversion envoie le SOLDE TOTAL au lieu du
delta de récompense — bug de corruption de solde argent réel
ANDROID SOURCE : wallet/WithdrawActivity.java:558-563 ; TransfertCoinsActivity.java:317-324 ;
ConversionActivity.java:243-250 ; WalletRepository.java:301-306 — `coins = pendingCoinCount +
currenGainCoins` (delta uniquement)
IOS FILES : Wallet/WithdrawView.swift:131-137 ; TransferCoinsView.swift:97-104 ; ConversionView.swift
:58-65 — `creditReward(totalAmount: UserSession.shared.coinsAmount)`, le SOLDE ENTIER envoyé comme
si c'était le delta
DIFFÉRENCE : Même classe de bug déjà trouvée et corrigée dans `EarnCoinsView.swift` (cycle antérieur,
V3-F-092) — mais jamais corrigée dans ces 3 écrans frères qui partagent pourtant le même motif
`AdRewardProvider`/`creditReward`.
IMPACT : Chaque fois qu'un utilisateur regarde la pub post-retrait/transfert/conversion, le serveur
ajoute TOUT le solde actuel de l'utilisateur par-dessus son solde serveur existant — doublement
(voire pire en cas de répétition) du solde réel, retirable, de l'utilisateur.
PREUVE : `WalletRepository.swift:93-96` mappe `totalAmount` directement en `"coins"` envoyé au
serveur ; les 3 vues passent le solde total, pas la récompense seule.
RECOMMANDATION : Corriger les 3 écrans pour n'envoyer que le delta de récompense (+tout montant en
attente, motif `pendingCoinsAmount` déjà implémenté dans `EarnCoinsView.swift`).
```

```
ID : V4-F-066
STATUT : **BUILD_VALIDATED (corrigé `393b485`, résolu comme effet de bord nécessaire du Lot
P0-1/V4-F-065 — même 3 fichiers, même fonction Android de référence `updateToServer` qui combine les
deux comportements en une seule unité — CI verte confirmée run `32663823532`)** — statut avant : ouvert
PRIORITÉ : P2
DOMAINE : Wallet-Monetization
FEATURE : Les échecs de rapport de crédit de récompense sont silencieusement avalés, sans retry de
montant en attente
ANDROID SOURCE : wallet/WalletRepository.java:307-320 (`onError` persiste le montant manqué dans
`PENDING_COINS_AMOUNT` pour resynchronisation ultérieure)
IOS FILES : Wallet/WithdrawView.swift:136 ; TransferCoinsView.swift:103 ; ConversionView.swift:64 —
`try?` nu, aucune logique `pendingCoinsAmount` (contrairement à `EarnCoinsView.swift`, qui l'a)
IMPACT : Sur un échec réseau pendant le crédit de récompense, le solde local reste gonflé
indéfiniment sans que le serveur ne le reçoive jamais — divergence permanente et silencieuse.
RECOMMANDATION : Appliquer le même motif de retry `pendingCoinsAmount` que `EarnCoinsView.swift` à
ces 3 sites — idéalement dans le même correctif que V4-F-065.
```

```
ID : V4-F-067
PRIORITÉ : P2
DOMAINE : Wallet-Monetization
FEATURE : `ReferralView` utilise le mauvais identifiant de bannière AdMob
ANDROID SOURCE : res/layout/activity_referral.xml:19-25 — même bannière que TOUS les autres écrans
Wallet (`5840810574`)
IOS FILES : Wallet/ReferralView.swift:20 — utilise `AdMobIdentifiers.bannerSecondary` (`4225372854`)
au lieu de `bannerWallet`
DIFFÉRENCE : `4225372854` est en réalité orphelin côté Android (layout jamais inclus/inflé) — ses
seuls usages Android réels sont un identifiant totalement différent, câblé en dur dans le module
Authentification, sans rapport avec Wallet.
IMPACT : Attribution erronée des impressions/revenus publicitaires de cet emplacement dans le
reporting AdMob, potentiellement un eCPM/fill inadapté (identifiant tuné pour un autre contexte).
RECOMMANDATION : Changer `ReferralView.swift:20` pour utiliser `AdMobIdentifiers.bannerWallet`.
```

```
ID : V4-F-068
PRIORITÉ : P1
DOMAINE : Wallet-Monetization
FEATURE : `WithdrawView` ne rafraîchit jamais le solde depuis le serveur avant d'autoriser une
demande de retrait
ANDROID SOURCE : wallet/WithdrawActivity.java:221,415-448 (`getRealAmount()` appelé inconditionnellement
avant que le formulaire ne devienne interactif)
IOS FILES : Wallet/WalletRepository.swift:133-140 (`refreshBalance`, ZÉRO appelant confirmé par grep
projet entier) ; Wallet/WithdrawView.swift:8-9,29 (utilise uniquement le solde en cache local)
IMPACT : Le solde affiché/utilisé pour le retrait peut être obsolète (dérive multi-session, ou
conséquence directe du bug V4-F-065) ; ce solde client potentiellement obsolète est envoyé au
serveur dans le payload de la demande de retrait elle-même — un montant d'argent réel.
RECOMMANDATION : Câbler `refreshBalance(userId:)` dans le `.task`/`.onAppear` de `WithdrawView` avant
que le formulaire ne devienne interactif, comme `getRealAmount()` côté Android.

STATUT : BUILD_VALIDATED (2026-08-24) — Vérifié contre `WithdrawActivity.java:221`
(`getRealAmount()` appelé INCONDITIONNELLEMENT dans `onCreate`, avant même que `submitButton` ne
soit câblé) et `:415-448` (`getRealAmount`, entier) : le champ d'instance `currentBalance` (initialisé
depuis l'écran précédent) est écrasé par la réponse `getuserbyid/{myId}` — et c'est CE MÊME champ
qui sert ensuite à la fois à la validation (`requestedAmount < currentBalance`, ligne 249) ET à la
valeur envoyée telle quelle au serveur dans le payload (`submitWithdrawalRequest(myId,
currentBalance, ...)`, ligne 272). Confirmé côté iOS que `WalletRepository.refreshBalance(userId:)`
existait déjà (port fidèle de `getRealAmount`) mais avait ZÉRO appelant (`grep refreshBalance` = 1
seul résultat, sa propre définition) — `WithdrawView` utilisait uniquement `coinsAmount`, le
paramètre statique reçu à l'instanciation (`WalletView.swift:29`,
`WithdrawView(coinsAmount: viewModel.coinsAmount)`, le cache local `WalletViewModel`/
`UserSession.shared.coinsAmount`), jamais rafraîchi. Correctif : nouveau `@State private var
currentBalance: Double` initialisé depuis `coinsAmount` (via un `init` explicite désormais requis),
rafraîchi par un `.task { await refreshBalance() }` NON BLOQUANT (fidèle au caractère
fire-and-forget de l'appel Android) ; tous les usages internes à `submit()` (validation solde
insuffisant + `currentBalance:` envoyé aux 2 méthodes de soumission crypto/mobile money) et
l'affichage ("Solde disponible") basculés de `coinsAmount` vers `currentBalance`. Flux frères
vérifiés PAR LECTURE DIRECTE du code Android : `grep getRealAmount\|getuserbyid` dans
`TransfertCoinsActivity.java` ET `ConversionActivity.java` → 0 résultat dans les deux — Android
lui-même NE rafraîchit PAS le solde serveur pour Transfert/Conversion (seul Retrait, l'écran de
cash-out réel visé par la guideline App Store 3.1.5, le fait) — `TransferCoinsView`/`ConversionView`
(qui lisent `UserSession.shared.coinsAmount` en direct) laissés INCHANGÉS, fidèles à leur source
Android respective, pas un oubli. Commit `4e6c2f1`, push confirmé (`5a9904e..4e6c2f1 main -> main`),
CI run `32684195949` conclusion `success`. DEVICE_TEST_REQUIRED pour passer en
COMPLETE_PARITY_VALIDATED (aucun accès Xcode/simulateur dans cet environnement — test réel requis :
modifier le solde serveur depuis un AUTRE appareil/session pendant que l'écran Retrait est ouvert
sur le premier, confirmer que le solde affiché ET utilisé pour la validation/soumission se met à
jour, sans bloquer visuellement le formulaire pendant le rafraîchissement).
```

---

## 16. Notifications / Firebase

```
ID : V4-F-069
PRIORITÉ : P2
DOMAINE : Notifications-Firebase
FEATURE : La notification "nouvelle publication" affiche l'URL de photo de profil au lieu du
pseudonyme
ANDROID SOURCE : back_sync/NotificationUtils.java:325-327 (`myNikname` = `infoContract.NIKNAME`,
texte)
IOS FILES : Notifications/NotificationCenterViewModel.swift:96-104 (`myNikname: UserSession.shared.
profile` — mauvaise propriété, c'est le champ PHOTO DE PROFIL, pas le pseudonyme)
IMPACT : Chaque notification d'activité "nouvelle publication" affiche un nom garbled ou vide (ex.
une URL d'image) au lieu d'un pseudonyme lisible.
RECOMMANDATION : Changer `myNikname: UserSession.shared.profile` en `UserSession.shared.nikname`
(propriété correcte déjà présente dans le même fichier `UserSession.swift`).
```

```
ID : V4-F-070
PRIORITÉ : P2
DOMAINE : Notifications-Firebase
FEATURE : Notification push de ré-engagement "contenu suggéré" jamais portée
ANDROID SOURCE : back_sync/NotificationUtils.java:154-220 ; service/MyWorker.java:78-110 ; Activity/
ui/HomeActivity.java:373-375,752-784 (job `WorkManager` périodique réel, tous les 2 jours)
IOS FILES : AUCUN — déjà documenté comme délibérément différé dans `HomeShellView.swift:37-41`
("module 18")
IMPACT : Les utilisateurs iOS inactifs ne reçoivent aucune notification de ré-engagement qu'Android
envoie — écart pertinent pour la rétention.
RECOMMANDATION : Différé, déjà planifié — ajouter un `BGTaskScheduler` périodique + porter la
sélection de message par moment de la journée quand ce module sera traité.
```

```
ID : V4-F-071
PRIORITÉ : P3
DOMAINE : Notifications-Firebase
FEATURE : Emoji/nom du cadeau non résolus dans les corps de notification liées aux cadeaux
ANDROID SOURCE : back_sync/NotificationUtils.java:123-129,311-319 (`GiftCatalogHelper`, emoji + nom
localisé inclus)
IOS FILES : Notifications/LocalNotificationBuilder.swift:46-47,86-87 — texte générique statique,
sans emoji ni nom (gap auto-documenté dans le code : "catalogue de cadeaux pas encore porté")
IMPACT : Identité du cadeau envoyé illisible depuis la seule notification.
RECOMMANDATION : Porter un équivalent `GiftCatalogHelper` (résolution emoji+nom par id) et le câbler
dans les deux branches concernées.
```

```
ID : V4-F-072
PRIORITÉ : P3
DOMAINE : Notifications-Firebase
FEATURE : Des notifications système du centre de notifications peuvent être perdues après la purge
locale
ANDROID SOURCE : NotiLikecmt/NotificationRepository.java:106-113 (déclenche les notifications depuis
la liste EN MÉMOIRE juste parsée, indépendamment de ce que la purge supprime ensuite en base)
IOS FILES : Notifications/NotificationCenterViewModel.swift:35-38,86-105 — re-requête Core Data PAR
ID après que `pruneOld(keeping: 30)` a déjà tourné ; un id purgé est silencieusement ignoré
IMPACT : Un utilisateur avec plus de 30 notifications non lues d'un coup (ex. après une longue
absence) peut silencieusement manquer les notifications système pour les plus anciennes éléments
purgés, alors qu'Android les déclencherait toutes.
RECOMMANDATION : Construire le contenu de notification directement depuis les résultats venant d'être
parsés/upsertés, avant la purge, plutôt que de re-requêter après.
```

---

## 17. Performance / Mémoire

```
ID : V4-F-073
PRIORITÉ : P1
DOMAINE : Performance-Memory
FEATURE : `CDNAsyncImage` décode chaque image CDN à pleine résolution, sans sous-échantillonnage
ANDROID SOURCE : ChargerImages.java:92-134,201-292,325-552 — CHAQUE chargeur Glide utilise
`.override(largeur,hauteur)`, décodage sous-échantillonné dès la source
IOS FILES : Media/CDNAsyncImage.swift:54-82 — `UIImage(data: data)` sur les octets bruts
téléchargés, aucune option `ImageIO`/`CGImageSource` de miniature, aucun paramètre de taille cible,
sur les 18 sites d'appel confirmés (Feed/Profile/Chat/Notifications/Recherche/Commentaires)
IMPACT : Mémoire/CPU pic élevés sur tout écran affichant plusieurs images à la fois (Feed, grilles,
listes de commentaires/notifications) — un avatar affiché à 32×32pt décode quand même à sa résolution
CDN complète, contrairement à Android où chaque site demande une cible de décodage réduite.
RECOMMANDATION : Ajouter un paramètre `targetSize` à `CDNAsyncImage`, décoder via
`CGImageSourceCreateThumbnailAtIndex` dimensionné à la taille d'affichage réelle sur chacun des 18
sites d'appel, à l'image des valeurs `.override()` par contexte d'Android.

STATUT : BUILD_VALIDATED (2026-08-24) — Vérifié contre `ChargerImages.java` : chaque chargeur Glide
(`displayThumbail`/`displayThumbailFromServeur` à `.override(200)`, `glid` à `.override(400)`,
surtout `glidLoadImageRequireAuth(mContext, url, view, width, height)` — le chargeur AVEC le header
`Referer` réel, donc l'équivalent Android direct de `CDNAsyncImage`, qui prend `width`/`height` en
PARAMÈTRES fournis par CHAQUE appelant, pas une valeur fixe globale) décode systématiquement
sous-échantillonné dès la source. `grep CDNAsyncImage(` recompté au moment de ce lot : **25
occurrences dans 16 fichiers** (le texte d'audit en citait 18 — le nombre a crû avec les lots
V4-F-007/V4-F-030 de ce même cycle qui ont étendu `FeedDetailPagerView`/ajouté des call sites entre
la Phase A et ce lot ; toutes les 25 occurrences ACTUELLES ont été traitées, pas seulement les 18
d'origine). Correctif : nouveau paramètre `targetSize: CGSize?` (points, `nil` par défaut) sur les
2 signatures d'init de `CDNAsyncImage` ; `load()` décode via `CGImageSourceCreateThumbnailAtIndex`
(`kCGImageSourceCreateThumbnailFromImageAlways`/`kCGImageSourceThumbnailMaxPixelSize` dérivé de
`targetSize` × `displayScale`/`kCGImageSourceCreateThumbnailWithTransform`/
`kCGImageSourceShouldCacheImmediately`) quand fourni, repli sur l'ancien `UIImage(data:)` pleine
résolution sinon (comportement inchangé pour tout appel non encore migré). Les 25 sites migrés,
chacun avec la taille réelle de son `.frame(width:height:)` voisin (avatars 32/36/40/44/50/56/64/72
selon l'écran, `.frame(maxWidth:220,maxHeight:220)` des bulles média chat) ou, pour les grilles sans
`.frame` fixe sur `CDNAsyncImage` elle-même, la largeur de colonne réelle dérivée du nombre de
colonnes déclaré (`FeedGridCell` partagée Feed/Hashtag = 2 colonnes ; grilles Profile/Search post =
3 colonnes) ; les 2 arrière-plans plein écran (viewer fullscreen Feed, sans borne plus petite
disponible) bornés à `UIScreen.main.bounds.size` — toujours un gain mémoire réel vs. la résolution
CDN source, généralement bien supérieure à l'écran. Commit `63039ff`, push confirmé
(`cf542ca..63039ff main -> main`), CI run `32685087464` conclusion `success`.
DEVICE_TEST_REQUIRED pour passer en COMPLETE_PARITY_VALIDATED (aucun accès Xcode/simulateur dans
cet environnement — test réel IMPÉRATIF, changement le plus risqué visuellement de tout ce cycle
P1 : confirmer sur chacun des 16 écrans touchés que les images restent nettes à leur taille
d'affichage [pas de flou perceptible dû à un `targetSize` trop petit], et profiler Feed/grilles à
défilement rapide via Instruments/Memory Graph pour confirmer la baisse de pic mémoire attendue).
```

```
ID : V4-F-074
PRIORITÉ : P2
DOMAINE : Performance-Memory
FEATURE : Des closures `Task` de `ChatViewModel` capturent `self` fortement à travers des allers-
retours réseau
ANDROID SOURCE : N/A (spécifique au comptage de références Swift/ARC)
IOS FILES : Messagerie/ChatViewModel.swift:144-161,514-539,549-582 (`resolveGroupSubscription`,
`requestUpload`, `requestDownload` — sans `[weak self]`, contrairement à `subscribeToRealtimeEvents`
dans le même fichier qui utilise déjà l'idiome correct)
IMPACT : Désallocation retardée de `ChatViewModel` si l'utilisateur quitte l'écran pendant qu'un
upload/download/abonnement est en vol, et risque de mutation d'état `@Published` sur un view model
dont la vue n'existe plus.
RECOMMANDATION : Ajouter `[weak self]` (avec `guard` de sortie précoce) aux 3 closures `Task`
identifiées, cohérent avec le motif déjà établi ailleurs dans le même fichier.
```

```
ID : V4-F-075
PRIORITÉ : P3
DOMAINE : Performance-Memory
FEATURE : Croissance non bornée de `ChatViewModel.items` et `PaintCaptureController.frames`
ANDROID SOURCE : Même caractéristique confirmée côté Android pour les deux (pas de plafond/éviction
non plus)
IOS FILES : Messagerie/ChatViewModel.swift:167-178,249-265 ; Animems/PaintCapture.swift:25,80-83,
134-137
SUGGESTED_STATUS : IOS_INTENTIONAL_DIFFERENCE (fidèle à une caractéristique déjà présente côté
Android, pas une régression iOS)
IMPACT : Croissance mémoire graduelle possible dans une session de chat très longue ou une séance de
dessin élaborée — informatif, aucune parité à corriger.
RECOMMANDATION : Optionnel — les deux plateformes pourraient bénéficier indépendamment d'un plafond,
hors périmètre de la parité de portage.
```

---

## 18. Confirmations "code mort Android, aucune action requise" (non comptées comme findings)

- **`uploadPerfilPhoto/FragmentProfile.java`** et **`uploadPerfilPhoto/adapter/ProfileAdapter.java`**
  (à distinguer de `setting.FragmentProfile`, RÉEL — voir V4-F-012) : confirmés inatteignables par
  grep exhaustif des sites d'appel (commentés) / classe entière encapsulée dans un commentaire bloc.
  Aucun port requis.
- **`partage/PartageWenack.java`** : déclaré au manifeste mais jamais lancé par aucun `Intent` dans
  tout le code Android (grep exhaustif). Aucun port requis.

---

## 19. Sections déjà vérifiées comme correctes/déjà résolues par le cycle V3, revérifiées ici sans
divergence trouvée (positif, mentionné pour traçabilité)

Session socket (auth/reconnexion/32 événements), envoi/réception de message, accusés de réception,
motif de décodage per-item, `FeedMediaUploader`/en-têtes Bunny, cache HTTP image, cache vidéo, crop
mode-switch, background removal (limitation iOS 16 acceptée), Boost (création→dashboard→détail→
annulation), core moteur Animems (transformations/keyframes/rendu). Aucune régression trouvée sur ces
points par les agents V4 malgré une recherche indépendante et approfondie.
