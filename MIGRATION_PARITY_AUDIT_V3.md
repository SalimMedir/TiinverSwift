# MIGRATION_PARITY_AUDIT_V3.md — Audit complet de parité Android → iOS, V3 (plus strict)

**PHASE A — AUDIT UNIQUEMENT. Aucun fichier de code n'a été modifié pour produire ce document.**
Ne remplace pas `MIGRATION_PARITY_AUDIT_V2.md`/`MIGRATION_PARITY_PROGRESS_V2.md` ni
`ANIMEMS_PARITY_AUDIT_V1.md`/`ANIMEMS_PARITY_PROGRESS_V1.md` — ceux-ci restent lisibles comme
historique. V3 est un audit indépendant, plus sceptique, couvrant l'application entière.

Date : 2026-08-19. Android (`C:\Users\helen\AndroidStudioProjects\tiinver`) = source de vérité
absolue.

---

## 1. Objectif et méthodologie

Le projet iOS compile et se lance sur Appetize — **cela ne prouve rien au-delà de
`BUILD_VALIDATED`**. Des audits précédents (V2, Animems V1) ont déjà trouvé des bugs sévères
malgré des CI vertes ; la méthodologie a parfois surévalué la parité en confondant "du code Swift
existe" avec "la fonctionnalité marche". Cette passe applique une grille de lecture délibérément
plus sceptique, en 6 niveaux obligatoires pour chaque fonctionnalité :

1. **Android** — la fonctionnalité existe-t-elle réellement ? Comment ? Quels fichiers ?
2. **iOS code** — un équivalent existe-t-il ?
3. **Connectivité** — ce code est-il réellement appelé depuis une UI ou un flux actif (pas supposé) ?
4. **Flux** — UI → Action → State/ViewModel → Repository/Service → Network/Socket/Bunny/Firebase → Response/Event → State → UI, tracé bout en bout.
5. **Données** — paramètres/IDs/URLs/JSON/types concordent-ils réellement ?
6. **Rendu/comportement** — le résultat est-il réellement affichable/utilisable ?

Si un maillon manque, la fonctionnalité n'est PAS `COMPLETE`.

**Méthode d'exécution** : 9 agents de recherche en parallèle (Search+nav, Chat/Socket/WebRTC,
Feed/Grid/Media, Bunny/Upload/Publish, Galerie/Éditeur, Auth/Profil/Groupes,
Notifications/DeepLinks/Paiements/Boost, Views/code-orphelin/silent-bugs, cartographie Android
exhaustive), chacun avec instruction explicite de citer `fichier:ligne` et de ne jamais conclure
`COMPLETE` sans preuve des 6 niveaux. **Toute conclusion HIGH confidence contradictoire ou à fort
enjeu a été re-vérifiée personnellement contre le code source** avant intégration — deux cas
documentés en détail ci-dessous (§3) où cette vérification a tranché un désaccord ou confirmé une
affirmation extrême.

---

## 2. Avertissement — BUILD SUCCESS ≠ fonctionnalité validée

Aucun `COMPLETE_PARITY_VALIDATED` n'est utilisé dans ce document — aucun test réel device/Appetize
n'a eu lieu pendant cette passe (audit statique uniquement, conforme à la consigne). Le statut le
plus élevé atteignable ici est `COMPLETE_PARITY_CANDIDATE` : chaîne de code complète et cohérente,
non testée réellement.

**Taxonomie utilisée (obligatoire, aucune exception)** : `MISSING`, `FUNCTIONALLY_FAILED`,
`PARTIAL`, `CODE_PRESENT_UNVERIFIED`, `COMPLETE_PARITY_CANDIDATE`, `BUILD_VALIDATED`,
`COMPLETE_PARITY_VALIDATED` (non utilisé ici), `ANDROID_ONLY`, `IOS_INTENTIONAL_DIFFERENCE`,
`DEAD_CODE`.

---

## 3. Résultats de tests réels déjà connus + 2 vérifications personnelles décisives

Fonctionnalités déjà rapportées comme non-fonctionnelles ou suspectes par des tests réels
précédents (Search, Chat/Socket.IO, Feed Grid/Fullscreen media) : traitées ci-dessous comme P0,
jamais requalifiées `COMPLETE` sur la seule base du code.

**Vérification personnelle #1 — priorité d'URL média (Feed)** : l'agent Feed a affirmé qu'Android
préfère `cdn_content_url` à `object_url` via `MediaObject.getObject_url()`, contredisant un
commentaire de code iOS daté du 2026-08-17 qui affirme l'inverse ("cause racine réelle, retest
utilisateur"). **Vérifié personnellement** par lecture directe de `MediaObject.java:352-357`
(l'ancienne version simple est commentée juste au-dessus de la version réelle, preuve d'un
changement de comportement délibéré côté Android) et des deux call sites réels
(`VideoPlaybackCoordinator.java:144,153` et `BubbleStatusPhoto.java:142,158,164`, qui appellent
tous `current.getObject_url()`, PAS le champ brut) : **l'agent avait raison, le commentaire iOS
est basé sur une confusion entre le NOM de la méthode Java et le CHAMP JSON qu'elle retourne**. Voir
V3-F-009.

**Vérification personnelle #2 — connexion Socket.IO jamais établie (Chat)** : l'agent Chat a
affirmé, par grep exhaustif, qu'aucun site d'appel n'existe pour `TiinverSocket.connect(apiKey:)`
dans tout le projet. **Vérifié personnellement** par un second grep indépendant
(`\.connect\(apiKey|TiinverSocket\.shared\.connect|func connect\(apiKey`) : confirmé, la SEULE
occurrence est la déclaration de la méthode elle-même (`TiinverSocket.swift:33`). Voir V3-F-016.

---

## 4. Cartographie Android exhaustive (condensée)

Établie par un agent d'exploration dédié — 63 Activities déclarées au Manifest, ~30 Fragments
instanciés, ~60 endpoints REST + Socket.IO, ~20 Repository/Manager/Service.

### 4.1 Activities Android sans appelant trouvé (candidats DEAD_CODE, à ne PAS porter)
`RechargeCoinsActvity`, `Activity/ui/Suggerencia`, `setting/Settings` (rôle de préférences natif,
remplacé par `SettingsActivity`), `exchange/ExChangeActivity`, `setting/MediaType`,
`Activity/ui/FullscreenActivity`.

### 4.2 Classes Activity absentes du Manifest (inatteignables par construction)
`SplashActivity2`, `DebutWenack2`, `FacebookActivity` (racine `com.tiinver`, distinct du SDK),
`Recherche/ui/RechercheTiinver2`, `ai/TiinverAIChat` (remplacé par `TiinverGeminiAIChat`, actif),
`animation.java`, `view/trimmer/v2/debug/TrimBenchActivity`.

### 4.3 Fragments jamais instanciés
`manager/FragmentGrid`, `uploadPerfilPhoto/FragmentProfile`, `wallet/UseBankCardFragment`
(fonctionnalité "carte bancaire" commencée puis abandonnée), `ui/certification/CertificationRequestFragment`.

### 4.4 Découvertes hors des catégories connues (importantes)
- **Sélection de catégorie de contenu OBLIGATOIRE avant publication** (`CategoryActivity`,
  garde-fou dans `PublishFragment.java:274-283`) — non couverte par aucune catégorie d'audit
  connue, directement liée à V3-F-024 (Bunny/publication).
- **Sélecteur GIF/sticker via Tenor + Giphy** (APIs tierces directes, pas le backend Tiinver) —
  `ui/sticker/StickerRepository.java`, `Http/TenorApiClient.java`. Distinct du système de stickers
  Animems.
- **Architecture `AccountManager`/`ContentProvider` legacy** (`back_sync/AuthenticatorService`,
  `back_sync/StubProvider`, authority `com.tiinver.provider`) — synchronisation SQLite/Cursor
  historique, `SyncService` associé commenté (désactivé) dans le Manifest. Probablement obsolète,
  à confirmer avant tout effort de portage.
- Configuration multi-région (`api.tiinver.cu`/`.global`/`.africa`) dans `TiinverConfig.java`.
- Secrets en clair dans `back_sync/infoContract.java` (mots de passe keystore, token TURN, clé
  wallet crypto commentée, token GitHub) — signalé pour information, hors périmètre fonctionnel.

---

## 5. Cartographie iOS (résumé)

`Sources/TiinverSwift/` — modules principaux : `Feed/`, `Discover/` (Search), `Messagerie/`
(Chat+Groups), `Calls/` (WebRTC), `Profile/`, `Authentication/`+`Security/` (Session), `PhotoEditor/`
(Galerie), `Animems/` (33 fichiers, audité séparément), `Wallet/`, `Boost/`, `Notifications/`,
`Navigation/` (DeepLinks+routing), `Advertising/`, `Creators/`, `Storage/` (Core Data + analytics).
Réseau centralisé via `APIClient.swift`, socket via `TiinverSocket.swift`+`ChatRepository.swift`.

---

## 6. Tableau de parité complet (98 constats)

Légende ID : préfixe de domaine conservé pour traçabilité directe avec les rapports d'agents
sous-jacents. Colonnes : ID · Domaine · Statut · Priorité · Écart (résumé) · Confiance.

### Search (V3-F-001 à 008)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-001 (SEARCH-01) | Recherche universelle réseau/decode | COMPLETE_PARITY_CANDIDATE | P1 | Aucun | HIGH |
| V3-F-002 (SEARCH-02) | Décodage résidu strict | PARTIAL | P2 | `try?` avale une erreur réelle de décodage en "0 résultat" au lieu d'"erreur" | MEDIUM |
| V3-F-003 (SEARCH-03) | Tap résultat utilisateur | IOS_INTENTIONAL_DIFFERENCE | P2 | Zone tapable élargie (amélioration) | HIGH |
| V3-F-004 (SEARCH-04) | Tap résultat publication → plein écran | **BUILD_VALIDATED** (corrigé `77b1fc8`, Phase B lot P1, CI verte — refetch via `getactivity/{token}`, repli sur les données obsolètes seulement si le réseau échoue ; test réel requis) | P1 | Pas de refetch avant affichage (Android en fait un) — état like/compteurs possiblement obsolète | MEDIUM |
| V3-F-005 (SEARCH-05) | Tap hashtag → fil | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |
| V3-F-006 (SEARCH-06) | Recherche groupe — texte placeholder | BUILD_VALIDATED (corrigé `38d5e99`, Phase B lot P1 — vraie traduction française vérifiée dans `values-fr/strings.xml`, CI verte — test réel requis) | **P1** | Chaîne littérale anglaise `"tab here for group info"` affichée à l'utilisateur pour tout résultat groupe serveur | HIGH |
| V3-F-007 (SEARCH-07) | Tap `#hashtag`/`@mention` dans une légende | **MISSING** | **P1** | Fonctionnalité entière absente (pas de `MentionTextView` équivalent) | HIGH |
| V3-F-008 (SEARCH-08) | États loading/empty/erreur | COMPLETE_PARITY_CANDIDATE | P2 | Lié à V3-F-002 | HIGH |

### Feed / Grid / Fullscreen / Media (V3-F-009 à 015)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-009 (FEED-01) | **Priorité URL média photo+vidéo inversée** | **BUILD_VALIDATED** (corrigé `afc44bf`, Phase B Lot 2, CI verte — test réel requis) | **P0** | iOS lit toujours `object_url` brut, jamais `cdn_content_url` — Android priorise `cdn_content_url` via `getObject_url()`. Vérifié personnellement, voir §3 | HIGH |
| V3-F-010 (FEED-02) | Cache disque vidéo cassé (headers manquants) | **BUILD_VALIDATED** (corrigé `3854676`, Phase B lot P1, CI verte — bascule vers `URLSession`+`URLRequest` avec les mêmes en-têtes que la lecture réelle — test réel requis) | P1 | `VideoCacheManager.precache` utilise `Data(contentsOf:)` sans header `Referer` → 403 probable → cache jamais rempli | HIGH |
| V3-F-011 (FEED-03) | Décodage tableau entier fragile (suggestions) | PARTIAL | P2 | `SuggestionsRepository` n'a pas le motif per-item déjà appliqué ailleurs | MEDIUM |
| V3-F-012 (FEED-04) | Cache HTTP désactivé pour toutes les images | PARTIAL | P2 | `.reloadIgnoringLocalCacheData` trop large (correctif défensif historique jamais restreint) | MEDIUM |
| V3-F-013 (FEED-05) | Décodage per-item flux principal | COMPLETE_PARITY_CANDIDATE | P2 | Positif — motif correct | HIGH |
| V3-F-014 (FEED-06) | Fréquence pubs natives plein écran | COMPLETE_PARITY_CANDIDATE | P2 | Positif — constante et logique identiques | HIGH |
| V3-F-015 (FEED-07) | Seuil de pagination fixe vs dynamique | IOS_INTENTIONAL_DIFFERENCE | P2 | Assumé, sans impact | HIGH |

### Bunny CDN / Upload / Publish (V3-F-016 renumbered — voir Chat pour 016 réel; Bunny ci-dessous)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-017 (BUNNY-01) | Métadonnées `activity/add` incomplètes | **BUILD_VALIDATED (partiel, portée documentée)** — corrigé `4ee582e`, Phase B lot P1, CI verte : `category` (best-effort)/`width`/`height`/`video_duration` (vidéos) maintenant envoyés, `metadata`/`template_id`/`consentAi` envoyés avec des valeurs par défaut fidèles. **NE reproduit PAS** le blocage de publication sans catégorie (nécessite V3-F-058, écran distinct non construit) — gap documenté, pas fermé silencieusement ; test réel requis | P1 | `category`/`metadata`/`template_id`/`consentAi`/`width`/`height`/`video_duration` jamais envoyés, contrairement à un commentaire iOS qui affirme (à tort) que "ce n'est pas envoyé par Android non plus" — catégorie confirmée OBLIGATOIRE côté Android | HIGH |
| V3-F-018 (BUNNY-02) | Publication photo — chaîne cœur Bunny Storage | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |
| V3-F-019 (BUNNY-03) | Progression upload + mémoire | PARTIAL | P2 | Pas de % réel, vidéo chargée entière en RAM avant envoi (Android streame par blocs de 8192o) | MEDIUM |
| V3-F-020 (BUNNY-04) | Publication vidéo — chaîne cœur Bunny Stream | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |
| V3-F-021 (BUNNY-05) | En-tête `Accept` manquant sur PUT vidéo | PARTIAL | P2 | Écart HTTP certain, impact incertain | LOW |
| V3-F-022 (BUNNY-06) | **Animems export → publication : rupture totale** | **BUILD_VALIDATED** (corrigé `5164acf`, Phase B Lot 3, CI verte — test réel requis) | **P0** | Android : export Animems rejoint le pipeline `PublishFragment`/`activity/add` standard. iOS : `exportedURL` alimente UNIQUEMENT un `ShareLink` système — aucun chemin vers `PublishComposeView`/`FeedRepository.publish`. **Confirmé indépendamment par vérification personnelle** (voir §3 de l'historique de session, `AnimemesEditorView.swift:211-220`) | HIGH |

### Chat / Socket.IO / WebRTC (V3-F-016, V3-F-023 à 031)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-016 (CHAT-01) | **Socket jamais connecté** | **BUILD_VALIDATED** (corrigé `57fd300`, Phase B Lot 1, CI verte — test réel requis) | **P0** | `TiinverSocket.connect(apiKey:)` n'a AUCUN site d'appel dans tout le projet — vérifié 2× indépendamment (agent + moi-même, voir §3). Racine probable de la quasi-totalité des échecs réels de chat déjà rapportés | HIGH |
| V3-F-023 (CHAT-02) | Architecture socket figée (`let`) | BUILD_VALIDATED (corrigé `57fd300`, `socket` devenu `var`, reset via `attachToCurrentSocket()` — test réel requis) | P0 | Même après correction de V3-F-016, tout ordre d'init défavorable fige `socket=nil` à vie pour le process | HIGH |
| V3-F-024 (CHAT-03) | Transport du token d'auth socket différent | BUILD_VALIDATED (corrigé `136388b`, Phase B Lot 8 — preuve vérifiée : `.connectParams` remplacé par `connect(withPayload:)`, le vrai équivalent de `IO.Options.auth` dans cette bibliothèque, confirmé via sa documentation officielle 16.1.1 ; test réel requis) | P0 | `connectParams` (query) au lieu d'`auth` (bibliothèque Swift ne l'expose pas) — impact dépend du serveur | HIGH (élevé de MEDIUM après vérification directe de la doc officielle de la bibliothèque, voir Progress_V3) |
| V3-F-025 (CHAT-04) | Mapping des noms d'événements | CODE_PRESENT_UNVERIFIED | P1 | Fidèle à la lecture statique, mais invérifiable tant que V3-F-016 n'est pas résolu | MEDIUM |
| V3-F-026 (WEBRTC-01) | `makingOffer` jamais reseté sur échec de `createOffer` (bug frère) | BUILD_VALIDATED (corrigé `136388b`, Phase B Lot 8 — en réalité la branche succès, pas échec, qui ne remettait jamais `makingOffer=false` ; test réel requis) | P1 (traité en P0-8 car dépendant du lot socket) | Le correctif symétrique existe dans `process()` mais pas dans `createOffer()` — même classe de bug déjà "corrigée" ailleurs | HIGH |
| V3-F-027 (CHAT-05) | Envoi de message neutralisé par V3-F-016 | CODE_PRESENT_UNVERIFIED | P2 | Écho optimiste local masque le fait que rien ne part réellement | HIGH |
| V3-F-028 (CHAT-06) | Groupes — endpoints REST | CODE_PRESENT_UNVERIFIED | P2 | Noms d'endpoint corrects, payloads non vérifiés en détail | MEDIUM |
| V3-F-029 (CHAT-07) | Indicateur de frappe sortant | IOS_INTENTIONAL_DIFFERENCE | P2 | Android : code mort (commenté). iOS : fonctionnel — amélioration assumée | HIGH |
| V3-F-030 (CHAT-08) | Payload suppression groupe malformé | COMPLETE_PARITY_CANDIDATE (bug partagé) | P2 | Bug Android reproduit fidèlement, pas une régression iOS | MEDIUM |
| V3-F-031 (CHAT-09) | Réveil app tuée (VoIP push) | CODE_PRESENT_UNVERIFIED | P2 | Contrat serveur non confirmé | LOW-MEDIUM |

### Galerie / Éditeur photo / Éditeur vidéo (V3-F-032 à 046)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-032 (GALERIE-01) | **Vidéo — crop/rotation/miroir absents** | **BUILD_VALIDATED** (corrigé `f519361`, Phase B Lot 5, CI verte — test réel requis, voir §3/Progress pour la contradiction VideoTransformer résolue) | **P0** | Aucun bouton, aucun code — capacité 100% absente côté iOS, présente et câblée jusqu'à l'export réel côté Android | HIGH |
| V3-F-033 (GALERIE-02) | Vidéo — peinture/texte/stickers | COMPLETE_PARITY_CANDIDATE | — | Absence symétrique confirmée (pas un écart) | HIGH |
| V3-F-034 (GALERIE-03) | Flux de choix du mode de recadrage | PARTIAL | P1 | Android permet de changer de mode en cours ; iOS impose un choix figé irréversible | MEDIUM |
| V3-F-035 (GALERIE-04) | Recadrage ovale — contrainte 1:1 possible | PARTIAL | P1 | `TOCropViewController.circular` pourrait forcer un cercle vs ellipse libre Android | MEDIUM |
| V3-F-036 (GALERIE-05) | Géométrie de recadrage — composant tiers non vérifié | CODE_PRESENT_UNVERIFIED | P1 | Remplacement délibéré du moteur maison Android (~5000 lignes) par une bibliothèque tierce, comportement aux limites non garanti identique | MEDIUM |
| V3-F-037 (GALERIE-06) | Recadrage forme libre | COMPLETE_PARITY_CANDIDATE | P2 | Port très fidèle, y compris un défaut visuel partagé | HIGH |
| V3-F-038 (GALERIE-07) | Suppression d'arrière-plan — qualité sujet non-humain | PARTIAL | P1 | Vision (iOS) = personnes uniquement ; ML Kit (Android) = sujet général. Repli géométrique identique des deux côtés | HIGH |
| V3-F-039 (GALERIE-08) | Aplatissement (bake) — risque de distorsion de ratio | IOS_INTENTIONAL_DIFFERENCE (risque réel) | P1 | `flatten()` applique un facteur d'échelle unique malgré un `aspectRatio(.fit)` non uniforme — pourrait réintroduire des marges après annotation | MEDIUM |
| V3-F-040 (GALERIE-09) | Stickers/emoji — pas de repositionnement post-placement | IOS_INTENTIONAL_DIFFERENCE | P2 | Android permettrait le glisser-déposer après placement (non confirmé en détail) | MEDIUM |
| V3-F-041 (GALERIE-10) | Limite légende 80 caractères | COMPLETE_PARITY_CANDIDATE | P2 | Vérifié exact, écart mineur de comptage Unicode possible | HIGH |
| V3-F-042 (GALERIE-11) | Trim vidéo — précision du point de coupe | PARTIAL | P1 | `AVAssetExportPresetPassthrough` cale sur le keyframe précédent (pas de ré-encodage) vs MediaCodec Android, frame-exact | MEDIUM |
| V3-F-043 (GALERIE-12) | Sélection média + permissions | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |
| V3-F-044 (GALERIE-13) | Miniature + durée vidéo | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | MEDIUM |
| V3-F-045 (GALERIE-14) | Catégorie/consentement IA — omission vérifiée fidèle | COMPLETE_PARITY_CANDIDATE | — | Vérifié indépendamment dans `HttpFileUploader.java` : ces champs Android ne sont PAS envoyés au réseau non plus malgré leur présence en UI — omission iOS correcte, pas un gap | HIGH |
| V3-F-046 (GALERIE-15) | Publication — cohérence façade avec pipeline Bunny | CODE_PRESENT_UNVERIFIED | P1 | Cohérence structurelle observée, non testée en intégration croisée | MEDIUM |

### Auth / Session (V3-F-047 à 055)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-047 (AUTH-01) | Login — parsing `error` booléen | COMPLETE_PARITY_CANDIDATE | P1 | Correctif déjà appliqué, tient | HIGH |
| V3-F-048 (AUTH-02) | Login — race condition navigation | COMPLETE_PARITY_CANDIDATE | P1 | Correctif déjà appliqué (persistance synchrone), tient | HIGH |
| V3-F-049 (AUTH-03) | Persistance de session — jeu de champs | COMPLETE_PARITY_CANDIDATE | P1 | Identique, `apiKey` mieux protégé (Keychain) | HIGH |
| V3-F-050 (AUTH-04) | Restauration de session au relancement | COMPLETE_PARITY_CANDIDATE | P1 | Identique | HIGH |
| V3-F-051 (AUTH-05) | **Déconnexion ne réinitialise jamais la racine de navigation** | **BUILD_VALIDATED** (corrigé `57fd300`, Phase B Lot 1, CI verte — test réel requis) | **P0** | `RootRouterView.authenticatedUser` n'est jamais remis à `nil` au logout — utilisateur bloqué sur un Home mort tant que l'app n'est pas tuée et relancée | HIGH |
| V3-F-052 (AUTH-06) | Bug "stale userId" Profil | COMPLETE_PARITY_CANDIDATE | P1 | Correctif déjà appliqué, tient | HIGH |
| V3-F-053 (AUTH-07) | Autres sites de la classe "stale userId" | COMPLETE_PARITY_CANDIDATE | P2 | Aucun autre site trouvé (revue statique) | MEDIUM |
| V3-F-054 (AUTH-08) | Gestion 401/session expirée | COMPLETE_PARITY_CANDIDATE (parité d'absence) | P2 | Ni Android ni iOS ne gèrent ce cas — pas une régression | HIGH |
| V3-F-055 (AUTH-09) | Google Sign-In | CODE_PRESENT_UNVERIFIED | P2 | Chaîne complète mais jamais testée réellement | MEDIUM |

### Profile (V3-F-056 à 063)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-056 (PROFILE-01) | Profil propre — fusion 2 écrans Android en 1 | COMPLETE_PARITY_CANDIDATE | P1 | Simplification assumée et vérifiée équivalente | HIGH |
| V3-F-057 (PROFILE-02) | Bug "envoi inconditionnel" birthday/gender | COMPLETE_PARITY_CANDIDATE | P1 | Correctif déjà appliqué, tient | HIGH |
| V3-F-058 (PROFILE-03) | **Édition de catégorie de compte** | **MISSING** | **P1** | Aucun écran, ni même affichage lecture seule, malgré le champ modèle déjà décodé | HIGH |
| V3-F-059 (PROFILE-04) | Points d'entrée vers profil d'autrui | COMPLETE_PARITY_CANDIDATE | P1 | 9 catégories Android, toutes couvertes côté iOS | HIGH |
| V3-F-060 (PROFILE-05) | Follow/unfollow — répartition asymétrique | COMPLETE_PARITY_CANDIDATE | P2 | Fidèle à Android (follow en Profil, unfollow en Feed uniquement) | HIGH |
| V3-F-061 (PROFILE-06) | Menu bloquer/signaler | COMPLETE_PARITY_CANDIDATE | P1 | Aucun | HIGH |
| V3-F-062 (PROFILE-07) | Grille → plein écran | COMPLETE_PARITY_CANDIDATE | P1 | Correctif déjà appliqué, tient | HIGH |
| V3-F-063 (PROFILE-08) | Lien de bio interne non routé | PARTIAL | P2 | Toujours ouvert en Safari, jamais via `DeepLinkRouter` | MEDIUM |

### Groups (V3-F-064 à 071)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-064 (GROUPS-01) | Création de groupe — flux 3 écrans | COMPLETE_PARITY_CANDIDATE | P1 | Code cohérent mais **jamais re-testé en réel** malgré un historique de régressions répétées | MEDIUM |
| V3-F-065 (GROUPS-02) | Liste de contacts vidée silencieusement | COMPLETE_PARITY_CANDIDATE | P1 | Correctif per-item déjà appliqué, tient | HIGH |
| V3-F-066 (GROUPS-03) | Rejoindre/quitter | COMPLETE_PARITY_CANDIDATE | P1 | Aucun | HIGH |
| V3-F-067 (GROUPS-04) | Membres + actions admin | COMPLETE_PARITY_CANDIDATE | P1 | Aucun | HIGH |
| V3-F-068 (GROUPS-05) | Renommage + description | COMPLETE_PARITY_CANDIDATE | P2 | Correctif déjà appliqué | HIGH |
| V3-F-069 (GROUPS-06) | Groupes payants — catalogue de prix erroné | **CORRIGÉ EN COMPLETE_PARITY_CANDIDATE** (contradiction résolue, `e330e6c` — voir Progress_V3 : les 5 valeurs 250/500/1250/2500/5000 ne sont que des libellés d'affichage `Group.java`, le prix RÉELLEMENT soumis vient de `getPrice(position)` et ne peut jamais être autre chose que 100/200/400/500 pour un spinner à 5 éléments ; iOS envoyait déjà ces 4 valeurs, seuls 3 choix morts (700/800/1000) ont été retirés) | **P1** | 7 paliers iOS (`[100,200,400,500,700,800,1000]`) ne correspondent à AUCUNE des 5 vraies valeurs Android (`250/500/1250/2500/5000`) — **prémisse invalidée, voir statut** | HIGH |
| V3-F-070 (GROUPS-07) | **Abonnement/renouvellement groupe payant — bouton inerte** | **BUILD_VALIDATED** (corrigé `e330e6c`, Phase B lot P1, CI verte — test réel requis ; gap réel plus sévère que décrit, voir Progress_V3 : la bannière ne s'affichait JAMAIS, pas seulement le bouton) | **P1** | Closure vide `{}`, justifiée par un commentaire périmé ("attend le module Wallet" — qui existe désormais intégralement) | HIGH |
| V3-F-071 (GROUPS-08) | Affichage nom/icône groupe en chat | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |

### Notifications / Deep Links / Payments / Boost (V3-F-072 à 090)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-072 (NOTIF-01) | Enregistrement token push | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |
| V3-F-073 (NOTIF-02) | Événements socket `pushNotification*` | DEAD_CODE (2 côtés) | P2 | Reproduction fidèle de code mort Android ; commentaire iOS à corriger (trompeur) | HIGH |
| V3-F-074 (NOTIF-03) | Notifications "activité" (like/comment/follow) | COMPLETE_PARITY_CANDIDATE | P1 | Aucun | HIGH |
| V3-F-075 (NOTIF-04) | **Aucune notification pour un nouveau message de chat en arrière-plan** | **BUILD_VALIDATED** (corrigé `6f5f0ca`, Phase B Lot 4, CI verte — test réel requis) | **P0** | `LocalNotificationBuilder.chatMessageNotificationContent` existe, jamais appelé depuis `ChatRepository.handleNewMessage` | HIGH |
| V3-F-076 (NOTIF-05) | Réveil app tuée (contrainte plateforme) | IOS_INTENTIONAL_DIFFERENCE | P1 | Limitation Apple réelle, dépend du format serveur (hors périmètre client) | MEDIUM |
| V3-F-077 (NOTIF-06) | Navigation au tap notification | PARTIAL | P2 | Bloqué en aval par V3-F-075 pour les messages | HIGH |
| V3-F-078 (DEEPLINK-01) | **Universal Links `https://tiinver.com/...` non fonctionnels** | **PARTIAL** | **P1** | Aucun AASA hébergé, aucun droit Associated Domains — code de routage prêt mais jamais atteint | HIGH |
| V3-F-079 (DEEPLINK-02) | Lien de parrainage `myapp://parrainage` | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |
| V3-F-080 (DEEPLINK-03) | Chemins de contenu (user/post/group/etc.) | COMPLETE_PARITY_CANDIDATE | P2 | Chaîne complète, bloquée en pratique par V3-F-078 pour les liens externes | HIGH |
| V3-F-081 (DEEPLINK-04) | Chemin `update/` (mise à jour forcée) | PARTIAL | P2 | `appStoreId=nil`, attendu avant publication réelle | HIGH |
| V3-F-082 (PAY-01) | Référence Android — mobile money/crypto hors app | ANDROID_ONLY | — | Justifié (conformité App Store) | HIGH |
| V3-F-083 (PAY-02) | Substitution StoreKit 2 | IOS_INTENTIONAL_DIFFERENCE | P1 | Justifiée (règle 3.1.1/3.1.5 App Store) | HIGH |
| V3-F-084 (PAY-03) | **Achat StoreKit non persisté serveur** | **FUNCTIONALLY_FAILED** (mitigé côté client par `9c5dd02`, Phase B Lot 6, CI verte — endpoint backend `storekit/verify-purchase` toujours INEXISTANT, voir Progress_V3 pour le détail exact du travail serveur requis ; statut délibérément PAS remonté à BUILD_VALIDATED car la parité fonctionnelle réelle — crédit durable côté serveur — reste absente) | **P0** | `storekit/verify-purchase` n'existe pas côté backend, documenté dans le code lui-même — argent réel dépensé, crédit perdu à la prochaine resynchronisation | HIGH |
| V3-F-085 (PAY-04) | Retrait/conversion/transfert/parrainage | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |
| V3-F-086 (BOOST-01) | Création de campagne — champs/endpoint | COMPLETE_PARITY_CANDIDATE | P2 | Aucun — vérifié indépendamment, pas un mock | HIGH |
| V3-F-087 (BOOST-02) | Calculs budget/durée/estimation | COMPLETE_PARITY_CANDIDATE | P2 | Aucun | HIGH |
| V3-F-088 (BOOST-03) | Tableau de bord — données réelles | COMPLETE_PARITY_CANDIDATE | P1 | Réserve mineure sur la forme JSON de `boost/overviews`, non confirmée | MEDIUM |
| V3-F-089 (BOOST-04/05/06) | Détail/annulation, update générique, pubs natives Feed | COMPLETE_PARITY_CANDIDATE / CODE_PRESENT_UNVERIFIED | P2 | `boost/update` probablement mort des 2 côtés ; reste vérifié fidèle | HIGH/LOW |

### Views/UI, bugs silencieux, code mort (V3-F-090 à 098)
| ID | Domaine | Statut | Prio | Écart | Confiance |
|---|---|---|---|---|---|
| V3-F-090 (SILENT-01) | **Décodage messages chat entrants fragile** | **BUILD_VALIDATED** (corrigé `57fd300`, Phase B Lot 1 — `decodeMessages` passé en `compactMap` per-item, CI verte — test réel requis) | **P0** | `ChatRepository.decodeMessages` décode le tableau ENTIER, pas per-item — un seul message malformé fait disparaître tout le lot socket entrant, sans trace | HIGH |
| V3-F-091 (SILENT-02) | Upload photo de profil — erreur avalée | **CORRIGÉ EN COMPLETE_PARITY_CANDIDATE (bug partagé)** — vérifié directement dans `AddPerfilFoto.java:655-658` : `onError(String message)` est ÉGALEMENT vide côté Android réel (aucun Toast, aucun feedback), le finding original supposait à tort qu'Android faisait mieux ; réutiliser `ProfileViewModel.errorMessage` ici aurait remplacé tout l'écran profil par un bandeau "recharger", une régression UX pire que le silence actuel — non modifié | P1 | `catch {}` vide, `errorMessage` jamais alimenté | HIGH |
| V3-F-092 (SILENT-03) | **Gains de pub récompensée perdus silencieusement** | **BUILD_VALIDATED** (corrigé `aa83ab4`, Phase B lot P1, CI verte — test réel requis ; bug plus sévère que décrit, voir Progress_V3 : le champ `"coins"` envoyé au serveur était le solde total du compte au lieu d'un delta, risque de doublement du solde à chaque pub, pas seulement une perte du solde en attente) | **P1** | `pendingCoinsAmount`/`pendingGemsAmount` écrits une fois, jamais réinjectés (Android le fait) — écrasés par le solde serveur au prochain reload | HIGH |
| V3-F-093 (SILENT-04) | Décodage tableau entier — Wallet/Discover/Créateurs | CODE_PRESENT_UNVERIFIED | P2 | Risque résiduel atténué par les décodages tolérants déjà en place | MEDIUM |
| V3-F-094 (SILENT-05) | Navigation profil "créateur de la semaine" avec id vide | CODE_PRESENT_UNVERIFIED | P2 | Pas de filet de sécurité pour `isCurrentUser==false` | MEDIUM |
| V3-F-095 (ORPHAN-01) | Analytics temps de visionnage jamais collectées | DEAD_CODE / MISSING | P2 | `ViewEventRepository` complet, zéro appelant — Android collecte activement | HIGH |
| V3-F-096 (ORPHAN-02) | Contrôles rotation/flip/ratio vidéo (état) jamais montés | BUILD_VALIDATED (corrigé `f519361`, Phase B Lot 5 — `VideoTrimState` maintenant monté dans `MediaTrimView` — test réel requis) | P1 | `VideoTrimState` écrit en prévision, jamais utilisé — recoupe directement V3-F-032 | HIGH |
| V3-F-097 | Absence confirmée hors Animems : `.id()`+geste, `AnyView`/`AnyGesture` dangereux, `@StateObject` à id vide, `opacity(0)`/`.hidden()` piégeux, `guard`→`EmptyView()` sans état d'erreur | — | — | Recherché explicitement, NON trouvé (négatif confirmé) | HIGH |
| V3-F-098 | Animems — voir section 14 | — | — | Renvoi | — |

---

## 7. P0 — bloquants (11 constats)

1. **V3-F-009** — Priorité d'URL média Feed inversée (photos ET vidéos manquantes)
2. **V3-F-022** — Animems : aucun chemin de publication réelle vers le Feed
3. **V3-F-016** — Socket.IO jamais connecté (racine probable de la quasi-totalité des échecs Chat)
4. **V3-F-023** — Architecture socket figée (`let`), piège de réintroduction même après correctif de #3
5. **V3-F-024** — Transport du token d'auth socket potentiellement incompatible serveur
6. **V3-F-051** — Déconnexion ne réinitialise jamais la racine de navigation
7. **V3-F-032** — Vidéo : recadrage/rotation/miroir totalement absents avant publication
8. **V3-F-075** — Aucune notification pour un message de chat reçu en arrière-plan
9. **V3-F-084** — Achat StoreKit 2 non persisté côté serveur (perte d'argent réel possible)
10. **V3-F-090** — Décodage des messages de chat entrants fragile (tableau entier)
11. *(V3-F-026 WEBRTC-01 classé P1 par son agent mais dépend directement de #3/#4/#5 pour être atteignable — à traiter dans le même lot)*

## 8. P1 (26 constats)

V3-F-004, V3-F-006, V3-F-007, V3-F-010, V3-F-017, V3-F-019 (P2 en pratique), V3-F-025, V3-F-026,
V3-F-034, V3-F-035, V3-F-036, V3-F-038, V3-F-039, V3-F-042, V3-F-046, V3-F-058, V3-F-064, V3-F-069,
V3-F-070, V3-F-074, V3-F-076, V3-F-078, V3-F-083, V3-F-088, V3-F-091, V3-F-092, V3-F-096.

## 9. P2 (le reste — voir tableau §6)

---

## 10. Audit Search — voir §6 tableau "Search". Détail complet des findings dans le rapport agent
source (conservé dans l'historique de session), résumé le plus sévère :
**V3-F-006/V3-F-007** — un texte de développement resté en dur visible par les utilisateurs, et
une fonctionnalité de recherche par tap-sur-hashtag entièrement absente.

## 11. Audit Chat / Socket.IO — voir §6 tableau "Chat". **Constat central** : la totalité du
périmètre chat/présence/typing/accusés/suppression/signalisation WebRTC est actuellement
inatteignable en usage réel, la connexion socket elle-même n'étant jamais établie (V3-F-016). Tout
le reste (mapping d'événements, logique ChatViewModel) est un travail par ailleurs soigné mais qui
ne s'exécute jamais tant que ce point n'est pas corrigé — risque classique de "l'UI a l'air de
marcher" (écho optimiste local qui masque l'absence d'envoi réel, V3-F-027).

## 12. Audit Feed/Grid/Fullscreen/Media — voir §6 tableau "Feed". Le finding le plus sévère
(V3-F-009) explique directement le symptôme historique "photos/vidéos manquantes" déjà rapporté
par des tests réels — confirmé être une régression d'un correctif antérieur mal ciblé (confusion
nom de méthode Java / champ JSON), pas un gap jamais traité.

## 13. Audit Bunny/Upload — voir §6 tableau "Bunny". Les deux chaînes cœur (photo/Storage,
vidéo/Stream) sont fidèles et réellement câblées. Le vrai problème est le raccordement Animems
(V3-F-022, P0) et des métadonnées de publication incomplètes (V3-F-017, catégorie obligatoire côté
Android jamais transmise côté iOS).

## 14. Audit Animems (lien vers l'audit dédié)

Le dossier interne d'Animems (moteur, canvas, gestes, timeline, keyframes, masques, templates,
recompose, export) est déjà audité et corrigé en profondeur dans
`ANIMEMS_PARITY_AUDIT_V1.md`/`ANIMEMS_PARITY_PROGRESS_V1.md` (Phase A + Phase B, 11 lots, tous
`BUILD_VALIDATED`). Cette passe V3 n'a PAS refait cet audit interne. Elle a vérifié
spécifiquement **l'intégration d'Animems avec le reste de l'application** :

- **Entrée dans Animems** : 3 sites d'appel réels (`FeedView`, `HomeShellView`, `MonetizationView`),
  `fullScreenCover` — fonctionnel.
- **Import média DANS Animems** : image — fonctionnel (`addImage`). Vidéo — **no-op confirmé**
  (`onVideoPicked: { _ in showGalleryPicker = false }`), déjà documenté comme F-45 dans le journal
  Animems Phase B, non retraité en détail ici (doublon volontaire évité).
- **Export/publication HORS d'Animems** : **V3-F-022, P0** — rupture totale, voir §13. C'est le
  finding le plus important produit par cette vérification d'intégration, non identifié comme tel
  dans l'audit Animems V1 (qui l'avait noté "non retracé" en §18.3, statut `CODE_PRESENT_UNVERIFIED`
  — **cette passe V3 le requalifie en `MISSING` confirmé**, preuve directe obtenue).
- Statut des items explicitement signalés comme non traités par Animems Phase B :
  - **F-33** (contrôleur de mouvement manuel) : toujours `MISSING`, nécessite de porter une
    nouvelle logique moteur jamais lue — confirmé inchangé.
  - **F-34/F-45** (import vidéo/audio) : toujours `MISSING`, confirmé bloqué par le no-op
    `onVideoPicked` ci-dessus.
  - **F-40** (zoom visuel réel du canvas) : toujours non résolu, risque de geste jugé trop élevé
    sans device réel — confirmé inchangé, décision toujours jugée prudente.
  - **F-17** (templates communautaires, contenu réel) : toujours `PARTIAL`, décision
    produit/backend hors portée iOS seul — confirmé inchangé.

## 15. Audit Galerie/Photo Editor/Video Editor — voir §6 tableau "Galerie". Le finding le plus
sévère (V3-F-032, P0) est une capacité entièrement absente (pas juste non câblée) : aucune vidéo
ne peut être recadrée, pivotée ou retournée avant publication sur iOS, alors que c'est câblé
jusqu'à l'export réel côté Android. Recoupe directement l'orphelin V3-F-096 (`VideoTrimState`,
écrit en prévision, jamais monté).

## 16. Audit Auth/Session — voir §6 tableau "Auth". Tous les correctifs précédemment appliqués
(parsing `error` booléen, race condition login, stale userId Profil) tiennent à la vérification.
Le nouveau finding le plus sévère (V3-F-051, P0) n'avait été identifié par aucun audit antérieur.

## 17. Audit Profile — voir §6 tableau "Profile". Correctifs antérieurs (birthday/gender,
grille→plein écran) tiennent. Nouveau gap réel : édition de catégorie de compte totalement absente
(V3-F-058).

## 18. Audit Groups — voir §6 tableau "Groups". Chaîne de création de groupe cohérente au niveau
code mais **jamais re-testée en réel** malgré un historique de régressions répétées — prudence
recommandée avant de la déclarer résolue. Deux nouveaux gaps réels : catalogue de prix de groupe
payant complètement erroné (V3-F-069) et bouton d'abonnement/renouvellement inerte avec
justification périmée (V3-F-070).

## 19. Audit WebRTC — voir V3-F-026 dans le tableau "Chat". Bug frère du correctif
"makingOffer jamais reseté" déjà appliqué côté réception (`process()`) mais pas côté émission
(`createOffer()`) — actuellement masqué par V3-F-016/023 (rien ne peut s'exécuter tant que le
socket n'est pas connecté), mais deviendra un problème réel dès que le socket sera corrigé.

## 20. Audit Firebase/Notifications — voir §6 tableau "Notifications". Enregistrement de token et
notifications "activité" fidèles. Gap réel majeur : aucune notification pour un message de chat
reçu en arrière-plan (V3-F-075, P0) alors que le code de contenu existe déjà.

## 21. Audit Payments — voir §6 tableau "Payments". La substitution StoreKit 2 est un choix produit
légitime et bien implémenté côté client — mais l'absence de l'endpoint serveur de vérification
(V3-F-084, P0) rend la fonctionnalité dangereuse en l'état : un achat réel facturé par Apple peut
perdre son crédit côté serveur.

## 22. Audit Deep Links — voir §6 tableau "DeepLinks". Le code de routage interne est prêt et
correct, mais les Universal Links `https://tiinver.com/...` ne fonctionnent pas du tout faute
d'AASA hébergé et de droit Associated Domains (V3-F-078) — impact élevé pour tout partage/marketing
utilisant ce type de lien.

## 23. Audit Boost — voir §6 tableau "Boost". **Vérification indépendante de l'auto-déclaration
"Boost construit" d'une session précédente : confirmée exacte.** Les 6 écrans sont réellement
câblés à de vrais endpoints avec des champs correspondants, non statiques/mock. L'un des rares
modules où l'auto-évaluation antérieure résiste à un audit indépendant ligne par ligne.

## 24. Audit Views/UI/accessibilité — voir §6 "Views/UI". Recherche explicite et ciblée des
patterns dangereux déjà identifiés comme récurrents dans ce projet (`.id()` sur vue à geste actif,
`AnyView`/`AnyGesture` masquant un bug, `@StateObject` à id vide/périmé, `opacity(0)`/`.hidden()`
piégeux, `guard`→`EmptyView()` sans état d'erreur visible) : **absence confirmée hors du module
Animems** (déjà traités séparément) — négatif rassurant, pas juste "non cherché".

## 25. Audit bugs silencieux — voir §6 "Views/UI"/"Silent". Le pattern `try? JSONDecoder().decode
([T].self, ...)` (décodage tableau entier, qui échoue en bloc dès qu'UN élément est malformé)
reste le bug de portage le plus récurrent de tout ce projet — déjà corrigé à plusieurs endroits
lors de sessions antérieures (Feed, Profile, Contacts, Groups), mais **toujours présent et non
corrigé sur le chemin le plus critique de tous : la réception de messages de chat en temps réel**
(V3-F-090, P0) — corrobore et aggrave directement V3-F-016/023.

## 26. Code mort / orphelin

### 26.1 Android (à NE PAS porter)
Voir §4.1/4.2 — 6 Activities déclarées sans appelant + 7 classes Activity absentes du Manifest,
4 Fragments jamais instanciés, 1 Service entièrement commenté (`MyAccessibilityService`, USSD).

### 26.2 iOS (code présent, jamais câblé)
`ViewEventRepository.swift` (V3-F-095, analytics temps de visionnage — Android l'utilise
activement, gap réel), `VideoTrimState.swift` (V3-F-096, rotation/flip/ratio vidéo — gap réel,
recoupe V3-F-032). Le module Animems a son propre inventaire détaillé dans
`ANIMEMS_PARITY_AUDIT_V1.md` §16.2 (9 fichiers orphelins) — non dupliqué ici.

## 27. Endpoints Android sans équivalent iOS confirmé

Non exhaustivement croisé endpoint-par-endpoint dans cette passe (98 findings couvrent déjà les
flux réels majeurs) — signalés comme nécessitant une vérification dédiée si un futur audit se
concentre spécifiquement sur cet angle : `activity/boots` (POST, rôle "booster une activité",
possible legacy/doublon de `boost/create`, jamais confirmé consommé côté iOS), `message/gift`
(POST, cadeau dans le chat — dépend du chat, non fonctionnel tant que V3-F-016 n'est pas résolu),
`purchaserequests`/`withdrawalrequests`/`crypto/check-transaction`/`crypto/withdraw` (flux mobile
money/crypto Android — `ANDROID_ONLY` par nécessité de conformité App Store, voir V3-F-082, pas un
gap à combler).

## 28. Fichiers iOS orphelins/non appelés (résumé)

Voir §26.2 pour le résumé complet hors Animems. Dans Animems, voir
`ANIMEMS_PARITY_AUDIT_V1.md` §16.2 (`MaskEditController.swift`, `MaskPreviewEditorPanelState.swift`
en partie, `AnimemesRecompose.swift` désormais câblé en Phase B Lot 9, etc. — statuts mis à jour
dans le §23 de ce même fichier).

## 29. Liste finale priorisée (P0 uniquement, ordre d'impact utilisateur décroissant)

1. V3-F-016/023/024 — Socket.IO jamais connecté + architecture figée + transport d'auth incertain (bloque tout le Chat + WebRTC + notifications de message)
2. V3-F-090 — Décodage messages entrants fragile (aggrave #1 dès qu'il sera résolu)
3. V3-F-075 — Aucune notification de chat en arrière-plan
4. V3-F-009 — Priorité d'URL média Feed inversée (photos/vidéos manquantes, déjà rapporté par test réel)
5. V3-F-022 — Animems : aucun chemin de publication réelle
6. V3-F-051 — Déconnexion ne réinitialise jamais la navigation racine
7. V3-F-032 — Vidéo : crop/rotation/miroir totalement absents avant publication
8. V3-F-084 — Achat StoreKit 2 non persisté côté serveur (risque financier réel)

**Aucun de ces 8 points n'a été corrigé dans cette passe — Phase A s'arrête ici.**
