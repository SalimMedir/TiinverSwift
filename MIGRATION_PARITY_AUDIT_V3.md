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
| V3-F-017 (BUNNY-01) | Métadonnées `activity/add` incomplètes | **BUILD_VALIDATED** — corrigé `4ee582e` (métadonnées) + `5ebf13a` (blocage forcé + sélecteur, V3-F-058) : `category`/`width`/`height`/`video_duration`/`metadata`/`template_id`/`consentAi` maintenant envoyés, ET le blocage de publication sans catégorie est maintenant reproduit (`PublishComposeView` ouvre `CategoryPickerView` avant de publier) — portée désormais complète, test réel requis | P1 | `category`/`metadata`/`template_id`/`consentAi`/`width`/`height`/`video_duration` jamais envoyés, contrairement à un commentaire iOS qui affirme (à tort) que "ce n'est pas envoyé par Android non plus" — catégorie confirmée OBLIGATOIRE côté Android | HIGH |
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
| V3-F-058 (PROFILE-03) | **Édition de catégorie de compte** | **BUILD_VALIDATED** (corrigé `5ebf13a`, Phase B lot P1, CI verte — `CategoryPickerView.swift` créé, 37 vraies catégories `CategoryActivity.java`, entrée libre dans Réglages Compte + blocage forcé avant publication (voir V3-F-017) ; test réel requis) | **P1** | Aucun écran, ni même affichage lecture seule, malgré le champ modèle déjà décodé | HIGH |
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

---

## 30. CYCLE COMPLÉMENTAIRE (2026-08-20) — audit approfondi 7 domaines

**Phase A uniquement — aucun code modifié pour produire cette section.** Suite directe du cycle V3
existant (§1-29 ci-dessus), PAS un nouveau cycle indépendant — continue la numérotation à partir de
V3-F-099. Méthode : 7 agents de recherche en parallèle (Recherche approfondi, Chat/Socket/WebRTC
approfondi, régression Animems post-Phase B, Galerie/Photo/Video Editor, Settings/Permissions/
Notifications/DeepLinks, Monétisation/Groupes/Authentification, balayage transversal code-mort),
chacun avec la méthodologie 5 dimensions (VIEW/LOGIC/NETWORK-MEDIA/RUNTIME WIRING) et le format de
finding strict imposé. Renumérotation appliquée ici pour éliminer les collisions d'ID entre agents
(chacun avait reçu l'instruction de démarrer à V3-F-099 indépendamment) — la correspondance
locale→globale n'est pas conservée, seule la numérotation finale ci-dessous fait foi.

**Constat le plus sévère de tout ce cycle complémentaire** : V3-F-110 (WebRTC — `isOnCall` jamais
mis à `true`, toute la signalisation d'appel entrant est routée vers Shareboard au lieu de l'appel
réel) — un appel WebRTC réel ne peut vraisemblablement JAMAIS établir de flux audio dans l'état
actuel du code, plus sévère que tout ce qui a été corrigé en Phase B sur ce domaine.

### 30.1 Recherche — audit très approfondi

```
ID : V3-F-099
PRIORITÉ : P1
DOMAINE : Recherche
FEATURE : Tap #hashtag/@mention dans une légende de post → recherche universelle
ANDROID SOURCE OF TRUTH : view/textview/MentionTextView.java:184-196 (TokenClickableSpan.onClick), Activity/ui/viewHolder/VideoViewHolder.java:636, view/CustomCardView.java:142, Recherche/ui/RechercheTiinver.java:156-181
IOS FILES : Feed/FeedView.swift (aucun équivalent), Discover/SearchView.swift
VIEW PARITY : Android rend les légendes cliquables dans TOUS les posts (vidéo ET photo). iOS affiche la légende en `Text(message)` brut, sans span/geste cliquable.
LOGIC PARITY : Android extrait le token, lance la recherche avec onglet+query présélectionnés. Aucune logique équivalente côté iOS.
NETWORK/MEDIA PARITY : N/A (jamais atteint côté iOS).
RUNTIME CHAIN : USER ACTION (tap #hashtag) → Android : ClickableSpan → recherche pré-remplie. iOS : rupture au premier maillon, `Text` statique sans geste.
STATUT : **BUILD_VALIDATED** (corrigé `349b606`, Phase B, CI confirmée verte — mais `AttributedString.link`/`.environment(\.openURL)` jamais exercé sur device/simulateur, test réel indispensable avant COMPLETE_PARITY_VALIDATED, cf. `HashtagMentionText.swift`)
PREUVE : `MentionTextView.java:98,188-196` ; `VideoViewHolder.java:636` ; `CustomCardView.java:142` ; `Feed/FeedView.swift:595-596` (`Text(message)` sans modificateur de geste). (Avant correctif.)
CAUSE : Fonctionnalité jamais portée (grep exhaustif `MentionTextView`/`onHashtagTap`/`clickableSpan` : zéro résultat).
RISQUE : Perte d'un point d'entrée réel et fréquent vers la recherche.
RECOMMANDATION : Construire un `AttributedString`/`Text` avec détection `#\w+`/`@[\w.-]+`, ouvrant `SearchView` pré-rempli. **Appliqué le 2026-08-20** : nouveau `HashtagMentionText.swift` (regex fidèles à `HASHTAG_PATTERN`/`MENTION_PATTERN`, `AttributedString.link` + `.environment(\.openURL)` pour le tap par sous-plage) câblé dans `FeedDetailCell` (seul endroit Android où la légende est cliquable, confirmé par grep : `VideoViewHolder.java:636`/`CustomCardView.java:142` sont les 2 SEULS appelants de `setSpannableText`). `SearchView` accepte désormais `initialQuery`/`initialTab` et lance la recherche immédiatement (port d'`autoQuery`/`autoTab`, `RechercheTiinver.java:156-181`). `FeedDetailCell`/`FeedDetailPagerView` étant le viewer plein écran PARTAGÉ par les 6 points d'entrée de l'app (fil principal, recherche, hashtag, notifications, profil, liens profonds), le correctif se propage automatiquement à tous sans modification supplémentaire.
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-100
PRIORITÉ : P2
DOMAINE : Recherche
FEATURE : Présentation des résultats "Publications" (grille vs liste)
ANDROID SOURCE OF TRUTH : Recherche/ui/RechercheTiinver.java:143-153 (GridLayoutManager 3 colonnes) ; UniversalSearchAdapter.java:103-106,255-314
IOS FILES : Discover/SearchView.swift:67-73,171-182
VIEW PARITY : Android insère les résultats posts comme tuiles carrées dans une grille 3 colonnes entrelacée. iOS les affiche en liste verticale de lignes.
STATUT : PARTIAL
PREUVE : `RechercheTiinver.java:144-151` vs `SearchView.swift:171-182` (`postRow`, `HStack`).
CAUSE : Reconstruction UI native sans layout XML Android, jamais comparée en détail au visuel réel des résultats posts.
RISQUE : Incohérence visuelle notable, aucune perte de donnée.
RECOMMANDATION : Reproduire la grille 3 colonnes (`LazyVGrid`) pour les résultats posts.
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-101
PRIORITÉ : P2
DOMAINE : Recherche
FEATURE : Métadonnées hashtag (nb publications/vues) décodées mais jamais affichées
ANDROID SOURCE OF TRUTH : UniversalSearchAdapter.java:320-349 ; HashtagProfile.java:282-284,343-347
IOS FILES : Discover/SearchView.swift:58-65, Discover/HashtagFeedView.swift, Discover/SearchModels.swift:46-52
LOGIC PARITY : `SearchHashtagResult.post_count`/`total_views` décodés côté modèle mais jamais lus par aucune vue.
STATUT : PARTIAL
PREUVE : `SearchModels.swift:46-52` déclare les champs ; `SearchView.swift:58-65`/`HashtagFeedView.swift:8-16` ne les utilisent jamais.
CAUSE : Champs modélisés lors du portage réseau, oubliés lors de la construction de la vue.
RISQUE : Perte d'information utile visible sur Android à deux endroits.
RECOMMANDATION : Afficher `post_count`/`total_views` sur la ligne résultat ET en header du fil hashtag.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-102
PRIORITÉ : P1
DOMAINE : Recherche
FEATURE : Pagination du fil hashtag absente au-delà de 30 posts
ANDROID SOURCE OF TRUTH : HashtagProfile.java:100-102,435-465 (LIMIT=10, scroll infini) ; ProfileRepository.java:226-232,242
IOS FILES : Discover/HashtagFeedView.swift:11-19,57-66 ; Profile/ProfileRepository.swift:58-62
LOGIC PARITY : Endpoint/paramètres identiques pour le PREMIER appel ; aucun second appel n'est jamais émis côté iOS (pas d'état offset, pas de déclencheur de scroll).
RUNTIME CHAIN : USER ACTION (scroll jusqu'en bas) → Android : nouvel appel réseau. iOS : rupture, rien ne se passe au-delà des 30 premiers posts.
STATUT : **BUILD_VALIDATED** (corrigé `596105f`, Phase B, CI confirmée verte — test réel requis avant COMPLETE_PARITY_VALIDATED)
PREUVE : `HashtagFeedView.swift:61` : `fetchHashtagPosts(tag:limit:30,offset:0)` appelé une seule fois. (Avant correctif.)
CAUSE : Pagination jamais implémentée lors du portage.
RISQUE : Régression fonctionnelle réelle pour tout hashtag &gt;30 publications (cas courant).
RECOMMANDATION : Ajouter état `offset`/`hasMore`, déclencher via `.onAppear` sur les dernières cellules. **Appliqué le 2026-08-20** (`HashtagFeedView.swift`) : état `offset`/`reachedEnd`/`isLoadingMore` ajouté, `loadMore()` déclenché sur `.onAppear` de la dernière cellule (même motif que `ProfileView`/`loadMorePosts`). Au passage, `limit` corrigé de `30` à `10` : vérification directe d'`HashtagProfile.java:101` (`LIMIT=10`) a montré que la valeur réelle Android ne correspondait PAS à ce qu'affirmait ce finding ("paramètres du premier appel déjà identiques").
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-103
PRIORITÉ : P1
DOMAINE : Recherche
FEATURE : Tap sur une recherche récente hashtag/mention donne 0 résultat (reproductible à 100%)
ANDROID SOURCE OF TRUTH : Recherche/ui/RechercheTiinver.java:252-279 (strip du préfixe, dérivation d'onglet, query sans préfixe)
IOS FILES : Discover/SearchView.swift:26-38,194-209
LOGIC PARITY : Android reconnaît `#`/`@`, dérive l'onglet, relance avec la query DÉPOUILLÉE. iOS conserve le préfixe brut dans `query` et n'ajuste jamais l'onglet — le backend reçoit littéralement `%23android` au lieu de `android`.
RUNTIME CHAIN : USER ACTION (tap entrée récente "#android") → iOS : query="#android" inchangée → recherche → probablement 0 résultat.
STATUT : **BUILD_VALIDATED** (corrigé `c9dd8b1`, Phase B, CI confirmée verte — test réel requis avant COMPLETE_PARITY_VALIDATED)
PREUVE : `SearchView.swift:29` : `Button(entry) { query = entry; runSearch(full: true) }` sans traitement de préfixe, vs `RechercheTiinver.java:256-265,271-272`. (Avant correctif.)
CAUSE : Format de stockage de l'historique fidèle à Android, mais logique de RÉ-INTERPRÉTATION du préfixe au tap jamais portée.
RISQUE : Bug visible et reproductible à 100% dans une zone déjà signalée prioritaire par des tests réels antérieurs.
RECOMMANDATION : Reproduire le parsing Android (détecter préfixe → dériver tab → query nettoyée). **Appliqué le 2026-08-20** (`SearchView.swift`, `selectRecent(_:)`) : préfixe `#`→onglet Hashtags, `@`→onglet Utilisateurs, sinon Tous ; query réseau toujours dépouillée du préfixe.
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-104
PRIORITÉ : P2
DOMAINE : Recherche
FEATURE : Sauvegarde dans l'historique local même en cas d'échec réseau
ANDROID SOURCE OF TRUTH : Recherche/ui/RechercheTiinver.java:440-458 (save UNIQUEMENT dans onResonse)
IOS FILES : Discover/SearchView.swift:194-209
LOGIC PARITY : `RecentSearchStore.save(query)` placé après le bloc `do/catch`, donc exécuté même dans la branche catch.
STATUT : PARTIAL
PREUVE : `SearchView.swift:199-207` (save hors du bloc `do`, sans `return`/`guard`).
CAUSE : Positionnement du `save()` après le do/catch au lieu de dans le do.
RISQUE : Pollution de l'historique avec des recherches jamais réellement abouties.
RECOMMANDATION : Déplacer `save()` à l'intérieur du bloc `do`.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-105
PRIORITÉ : P2
DOMAINE : Recherche
FEATURE : Écran figé sans feedback pour une query d'exactement 1 caractère en échec
ANDROID SOURCE OF TRUTH : Recherche/ui/RechercheTiinver.java:412-431,567 (showEmpty inconditionnel)
IOS FILES : Discover/SearchView.swift:74-86,92-102,184-192
LOGIC PARITY : Le bloc d'affichage erreur/vide est protégé par `query.count &gt;= 2`, mais `suggest()` (seule fonction alimentant `errorText` pour une query courte) n'est déclenchée QUE pour `query.count == 1` — les deux conditions ne se recoupent jamais.
STATUT : PARTIAL
PREUVE : `SearchView.swift:79` (`query.count &gt;= 2`) vs `:97-98` (suggest à `count &gt;= 1`, exclusivement `==1` en pratique).
CAUSE : Seuil réseau Android copié par erreur sur le seuil d'affichage.
RISQUE : Écran semble cassé/gelé pour une query de 1 caractère en échec.
RECOMMANDATION : Étendre la condition d'affichage à `query.count &gt;= 1`.
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-106
PRIORITÉ : P3
DOMAINE : Recherche
FEATURE : Filtrage "posts" absent du chemin suggestion (garde `isFull` Android non reproduite)
ANDROID SOURCE OF TRUTH : Recherche/ui/RechercheTiinver.java:421,461,528 (`isFull=false` garantit l'absence de section Publications en suggestion)
IOS FILES : Discover/SearchRepository.swift:16-20, Discover/SearchView.swift:67-73,184-192
STATUT : CODE_PRESENT_UNVERIFIED
PREUVE : Aucune garde équivalente à `isFull` dans `SearchView.suggest`/`SearchRepository.suggest`.
CAUSE : Simplification du portage — une seule fonction `decodeResults` partagée entre les deux endpoints.
RISQUE : Incertain — dépend d'un comportement serveur non observable par lecture de code.
RECOMMANDATION : Capturer une réponse réelle de `content/search/suggest` pour trancher.
TEST RÉEL NÉCESSAIRE : oui (inspection réseau).
```

```
ID : V3-F-107
PRIORITÉ : P1
DOMAINE : Recherche
FEATURE : Bouton "Suivre" inline sur résultat utilisateur — état FAUX permanent après échec réseau
ANDROID SOURCE OF TRUTH : UniversalSearchAdapter.java:226-247 (`onFollowingError` ne confirme jamais faussement un succès)
IOS FILES : Discover/SearchView.swift:145-169
LOGIC PARITY : `toggleFollow` met `isFollowed=true` IMMÉDIATEMENT, puis `try? await ...follow(...)` — en cas d'échec, l'erreur est avalée, AUCUN rollback.
RUNTIME CHAIN : USER ACTION (tap Suivre) → state=true → réseau échoue → try? avale → RENDU : "Abonné" affiché en permanence, désactivé, aucun moyen de réessayer.
STATUT : **BUILD_VALIDATED** (corrigé `c08ce4c`, Phase B, CI confirmée verte — test réel requis avant COMPLETE_PARITY_VALIDATED)
PREUVE : `SearchView.swift:163-169` (mise à jour d'état avant `try?`, aucun `catch`, aucune réaffectation en échec). (Avant correctif.)
CAUSE : Pattern `try?` combiné à une mise à jour optimiste jamais annulée en cas d'échec.
RISQUE : Faux positif visible et persistant — l'utilisateur croit avoir suivi quelqu'un alors que non.
RECOMMANDATION : `do/catch` explicite, rollback `isFollowed=false` + état d'erreur visible en cas d'échec. **Appliqué le 2026-08-20** : rollback `isFollowed=false` sur échec dans `SearchView.toggleFollow`. En vérifiant TOUS les appelants de `ProfileRepository.follow` (étape obligatoire de la méthode), 3 AUTRES sites exhibant EXACTEMENT le même bug (mise à jour optimiste + `try?` sans rollback) ont été trouvés et corrigés dans le même lot : `ProfileViewModel.follow()` (bouton principal du profil), `FeedViewModel.followFromDetail()` (bouton follow du visualiseur plein écran), `SuggestionsCarouselView.follow()` (carrousel de suggestions), `NotificationsListView` (bouton "Suivre en Retour"). Un 5e site (`FeedViewModel.unfollow()`) a été vérifié et laissé inchangé : il ne pose aucune mise à jour optimiste, donc n'exhibe pas ce bug précis (hors périmètre de ce finding).
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-108
PRIORITÉ : P2
DOMAINE : Recherche
FEATURE : Recherche de conversations locales — filtrage sur le texte du dernier message absent
ANDROID SOURCE OF TRUTH : Recherche/ui/RechercheTiinver.java:663-674 (filtre sur titre/message/sous-titre)
IOS FILES : Messagerie/ChatSearchView.swift:29-38, Messagerie/RosterListView.swift:195-203,246
LOGIC PARITY : iOS ne filtre que sur `title`/`subtitle` — `subtitle` n'est JAMAIS le texte du dernier message (nom d'utilisateur ou chaîne statique groupe), alors que la donnée existe (`pair.lastMessage?.message`) mais n'est jamais exposée au filtre.
STATUT : PARTIAL
PREUVE : `RechercheTiinver.java:666-668` (3 champs) vs `ChatSearchView.swift:35-37` (2 champs, ni l'un ni l'autre = texte du message).
CAUSE : `Row` n'expose pas le dernier message comme champ filtrable.
RISQUE : Recherche de conversation par mot-clé de message échoue silencieusement sur iOS.
RECOMMANDATION : Ajouter un champ `lastMessage: String` à `Row`, l'inclure dans le filtre.
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-109
PRIORITÉ : P3
DOMAINE : Recherche
FEATURE : Décision locale/repli-serveur (recherche de conversations) — iOS plus correct qu'Android
ANDROID SOURCE OF TRUTH : Recherche/ui/RechercheTiinver.java:584-685 (bug réel : `searchOnLocal` réaffecté sans OR logique à chaque itération de boucle)
IOS FILES : Messagerie/ChatSearchView.swift:29-38,106-123
STATUT : IOS_IMPROVED
PREUVE : `RechercheTiinver.java:670-673` (réaffectation sans accumulation) vs `ChatSearchView.swift:109` (`localMatches.isEmpty`, logique correcte et déterministe).
CAUSE : Bug Android préexistant non reproduit intentionnellement.
RISQUE : Faible impact direct, mais RISQUE DE FAUX CONSTAT lors de tests comparatifs manuels (un testeur pourrait signaler à tort une régression iOS).
RECOMMANDATION : Ne pas "corriger" iOS pour reproduire le bug Android ; documenter pour l'équipe QA.
TEST RÉEL NÉCESSAIRE : oui, pour documentation QA seulement.
```

### 30.2 Chat / Socket.IO / WebRTC — audit très approfondi

```
ID : V3-F-110
PRIORITÉ : P0 — LE FINDING LE PLUS SÉVÈRE DE CE CYCLE COMPLÉMENTAIRE
DOMAINE : Chat/Socket/WebRTC
FEATURE : Signalisation WebRTC entrante (offre/réponse/ICE) jamais routée vers l'appel réel
ANDROID SOURCE OF TRUTH : messagerie/service/CallService.java:113,561,641 (isOnCall vit tout le cycle d'appel) ; messagerie/repository/ChatRepository.java (~ligne 284, teste CallService.isOnCall)
IOS FILES : Realtime/ChatRepository.swift:27 (`static var isOnCall`), :368-376 (`handleUnifiedWebrtcMessage`) ; Calls/CallCoordinator.swift:81 (souscrit uniquement à `callEvents`)
VIEW PARITY : Sans objet directement (bug de routage interne).
LOGIC PARITY : `ChatRepository.isOnCall` est le port explicite de `CallService.isOnCall` (commenté comme tel dans le code) — mais grep exhaustif confirme AUCUNE affectation `= true` nulle part dans le projet, seule affectation = `false` à la déclaration.
NETWORK/MEDIA PARITY : L'événement socket `webrtcMessage` arrive bien au client (nom d'événement correct) mais `handleUnifiedWebrtcMessage` route `if Self.isOnCall { callEvents... } else { chatEvents.pbs... }` — `isOnCall` étant toujours `false`, 100% des messages webrtcMessage entrants partent vers le flux Shareboard, jamais vers `CallCoordinator`.
RUNTIME CHAIN : USER ACTION (répondre/passer un appel) → offre locale envoyée (non affectée) → pair distant répond via socket `webrtcMessage` → `handleUnifiedWebrtcMessage` reçoit → RUPTURE : routé vers `chatEvents.pbs`, jamais vers `callEvents` → `CallCoordinator` ne reçoit jamais l'événement → `RTCPeerConnection.setRemoteDescription`/`addIceCandidate` jamais invoqués pour le pair → connexion audio ne peut jamais s'établir.
STATUT : **BUILD_VALIDATED** (corrigé `2a779f6`, Phase B, CI verte — test réel d'appel requis avant COMPLETE_PARITY_VALIDATED)
PREUVE : `ChatRepository.swift:27` (grep `isOnCall\s*=` = 1 seul résultat, la déclaration) ; `:368-376` (routage) ; `CallCoordinator.swift:81` (jamais abonné à `chatEvents`) ; côté Android `CallService.java:113,561,641` (3 sites vivants, absents côté iOS).
CAUSE : Le module CallCoordinator/CallKit a été écrit APRÈS ChatRepository (commentaire du code le dit lui-même) mais le raccordement final (faire vivre `isOnCall` depuis CallCoordinator) n'a jamais été fait.
RISQUE : Un appel WebRTC réel ne peut vraisemblablement JAMAIS établir de flux audio dans l'état actuel — plus sévère que V3-F-026 (`makingOffer`, déjà corrigé), qui ne bloquait que la RENÉGOCIATION, pas la connexion INITIALE.
RECOMMANDATION : Faire vivre `ChatRepository.isOnCall = true/false` depuis `CallCoordinator` aux mêmes points qu'Android (début/fin d'appel), ou remplacer le booléen statique par une lecture directe de `CallCoordinator.shared.state != .idle`.
TEST RÉEL NÉCESSAIRE : oui, impératif et prioritaire — passer un appel réel entre 2 comptes et confirmer qu'un flux audio bidirectionnel s'établit (pas seulement que CallKit s'affiche).
```

```
ID : V3-F-111
PRIORITÉ : P0 (vérification, résultat positif)
DOMAINE : Chat/Socket
FEATURE : Cycle de vie socket (connect/reset/disconnect) et persistance du token sur reconnexion auto
ANDROID SOURCE OF TRUTH : App.java:88-171
IOS FILES : Realtime/TiinverSocket.swift, Realtime/ChatRepository.swift, Navigation/RootRouterView.swift
LOGIC PARITY : Relu intégralement — `ensureSocket`/`connect`/`reset`/`disconnect` fidèles à `getSocket`/`connectSocket`/`resetSocket`/`disconnectSocket`. `attachToCurrentSocket()` a un unique site d'appel réel (`RootRouterView.swift:53`, après login réussi) — confirmé PRÉSENT.
NETWORK/MEDIA PARITY : Vérifié indépendamment contre la source de `socket.io-client-swift` : `connect(withPayload:)` fait `connectPayload = payload` (propriété STOCKÉE sur l'instance), donc les reconnexions automatiques du moteur (`.reconnects(true)`) réutilisent bien le token — le risque initialement soupçonné (perte d'auth sur reconnexion auto) est INFONDÉ pour ce chemin.
STATUT : BUILD_VALIDATED (confirmé cohérent à la relecture, aucune régression, un point d'incertitude du journal levé positivement)
PREUVE : `TiinverSocket.swift:82-91` ; `ChatRepository.swift:48-53,62-67` ; `RootRouterView.swift:45-53`.
CAUSE : Sans objet (vérification positive).
RISQUE : Aucun nouveau. Le test serveur réel (association de session) reste entier.
RECOMMANDATION : Documenter dans le code que `connectPayload` persiste bien across-reconnect.
TEST RÉEL NÉCESSAIRE : oui — connexion réelle + coupure/reprise réseau, confirmer l'identification serveur après reconnexion auto.
```

```
ID : V3-F-112
PRIORITÉ : P1 (vérification, résultat positif — mais effet bloqué par V3-F-110)
DOMAINE : WebRTC
FEATURE : `makingOffer` correctement remis à `false` sur succès de `createOffer()`
ANDROID SOURCE OF TRUTH : messagerie/webrtc/RTConnection2.java
IOS FILES : Calls/WebRTCConnection.swift:191-205
LOGIC PARITY : Confirmé présent — `createOffer()` remet `makingOffer=false` dans les DEUX branches (succès ligne 203, échec ligne 195-198), symétrique à `iceRestart()`.
STATUT : BUILD_VALIDATED (fix confirmé correct) — mais inatteignable en pratique tant que V3-F-110 n'est pas corrigé (aucun message entrant réel n'est jamais traité par `process()`)
PREUVE : `WebRTCConnection.swift:191-205`.
RISQUE : Nul isolément.
RECOMMANDATION : Traiter V3-F-110 en priorité pour que ce correctif devienne effectif.
TEST RÉEL NÉCESSAIRE : oui, mais seulement après correction de V3-F-110.
```

```
ID : V3-F-113
PRIORITÉ : P1
DOMAINE : Socket
FEATURE : Aucune surveillance réseau côté client — pas de reconnexion forcée après coupure réelle
ANDROID SOURCE OF TRUTH : Activity/ui/HomeActivity.java:430-464,482-497 (`networkStateReceiver` → `resetSocket()+connectSocket()` à CHAQUE transition réseau)
IOS FILES : Realtime/TiinverSocket.swift, Realtime/ChatRepository.swift, Navigation/RootRouterView.swift
LOGIC PARITY : Grep exhaustif (`NWPathMonitor`/`Reachability`) = zéro résultat sur tout le projet. Seul `attachToCurrentSocket()` existe, appelé UNIQUEMENT au login (jamais réexécuté ensuite). Le seul mécanisme résiduel (`attemptReconnect`) ne couvre que `"io server disconnect"`, pas une coupure réseau côté client — équivalent au VRAI `ChatRepository.attemptReconnect()` Android, mais PAS à `HomeActivity.onNetworkChange` (mécanisme séparé, absent côté iOS).
RUNTIME CHAIN : Perte réseau réelle → iOS : rien n'observe activement, seul le backoff interne du moteur Socket.IO agit (hors contrôle applicatif) → Android : détection explicite + reset forcé immédiat.
STATUT : **CODE_PRESENT_UNVERIFIED** (corrigé, Phase B — CI pas encore confirmée verte)
PREUVE : `HomeActivity.java:482-497` ; absence confirmée côté iOS (grep 0 résultat) ; `RootRouterView.swift:53` (seul site d'appel). (Avant correctif.)
CAUSE : Le portage a traité `onNetworkChange` uniquement comme "premier reset après login", sans reproduire le déclencheur RÉSEAU qui l'active à chaque changement de connectivité côté Android.
RISQUE : Chat/appels potentiellement non fonctionnels plus longtemps qu'Android après une coupure réseau (mode avion, changement WiFi/4G, tunnel).
RECOMMANDATION : Ajouter un `NWPathMonitor` appelant `attachToCurrentSocket()` sur chaque transition vers `.satisfied`. **Appliqué le 2026-08-20** : nouveau `NetworkMonitor.swift` (singleton `NWPathMonitor`, recréé à chaque `start()` — `cancel()` invalide définitivement une instance), démarré/arrêté sur `.active`/`.background` dans `RootRouterView` (port d'`onStart`/`onStop`, pas `onResume`/`onPause`). Déclenche `ChatRepository.attachToCurrentSocket()` UNIQUEMENT sur une transition RÉELLE non-satisfait→satisfait (pas à chaque broadcast comme Android, plus bruyant — différence assumée et documentée dans le fichier, pour éviter des resets redondants sans manquer le scénario réel décrit par ce finding) et uniquement si une session existe déjà.
TEST RÉEL NÉCESSAIRE : oui — mode avion 30s+, rétablir, mesurer le délai de reprise vs Android.
```

```
ID : V3-F-114
PRIORITÉ : P1
DOMAINE : Chat
FEATURE : Indicateur de présence (en ligne) — requête jamais émise à l'ouverture d'un chat privé
ANDROID SOURCE OF TRUTH : messagerie/ui/ChatFragmentTest.java:699-703 (`chatViewModel.presence(userData.getTo())` à l'ouverture) ; ChatRepository.java:993
IOS FILES : Messagerie/ChatViewModel.swift (aucun appel), Realtime/ChatRepository.swift:432 (`emitPresence` déclarée), Messagerie/ChatView.swift:130 (badge affiché)
LOGIC PARITY : `emitPresence(username:)` existe et émet correctement, mais grep exhaustif confirme ZÉRO site d'appel en dehors de sa propre déclaration. `ChatViewModel.loadInitial()` ne l'appelle jamais.
NETWORK/MEDIA PARITY : La RÉCEPTION fonctionne (listener câblé, met à jour `isPeerOnline`) — seule l'ÉMISSION de la requête initiale manque.
RUNTIME CHAIN : USER ACTION (ouvrir chat 1:1) → RUPTURE : aucun appel à `emitPresence` → `isPeerOnline` reste `false` indéfiniment sauf changement d'état du pair PENDANT que l'écran est déjà ouvert.
STATUT : **CODE_PRESENT_UNVERIFIED** (corrigé, Phase B — CI pas encore confirmée verte)
PREUVE : `ChatRepository.swift:432` (jamais appelée) ; `ChatFragmentTest.java:701` (site d'appel Android). (Avant correctif.)
CAUSE : Angle mort entre deux modules écrits à des passes différentes (protocole d'émission vs déclenchement dans le flux d'ouverture).
RISQUE : Badge "en ligne" fonctionnellement mort en usage normal — fausse impression que le contact n'est "jamais en ligne".
RECOMMANDATION : Ajouter `chatRepository.emitPresence(username: target.to)` dans `loadInitial()`, gardé par `!target.isGroup`. **Appliqué le 2026-08-20** exactement comme recommandé (`ChatViewModel.swift`, nouvelle `emitPresenceIfPrivateChat()` appelée en fin de `loadInitial()`). `loadInitial()` a un seul site d'appel dans tout le projet (`ChatView.swift:64`, `.task`) — aucun flux frère à corriger.
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-115
PRIORITÉ : P2
DOMAINE : Chat/Socket
FEATURE : Canal "update message"/"update group message" jamais écouté (missed-call + suppression groupe "pour tous") — bug PARTAGÉ, pas une régression iOS
ANDROID SOURCE OF TRUTH : messagerie/repository/ChatRepository.java:130-131,958-959 (émission SEULEMENT, confirmé par grep exhaustif — aucun listener non plus côté Android)
IOS FILES : Realtime/ChatRepository.swift:382,392,568-579
LOGIC PARITY : Bug partagé fidèlement reproduit — ni Android ni iOS n'écoutent ces 2 canaux, utilisés en émission seulement.
STATUT : CODE_PRESENT_UNVERIFIED (dépend du comportement SERVEUR, non tranchable côté client)
PREUVE : `ChatRepository.swift:568-579` (émission) vs absence d'écoute des deux côtés (grep indépendant confirmé).
CAUSE : Lacune protocole pré-existante côté Android, reproduite fidèlement.
RISQUE : Si le serveur ne relaie pas : suppression groupe "pour tous" ou notification appel manqué pourrait ne jamais atteindre le destinataire en temps réel.
RECOMMANDATION : Test serveur dédié requis avant toute action côté client.
TEST RÉEL NÉCESSAIRE : oui, impératif pour lever l'ambiguïté.
```

```
ID : V3-F-116
PRIORITÉ : P2
DOMAINE : Chat
FEATURE : Suppression de message privé "pour tous" reçue — pas de mise à jour UI en direct si conversation déjà ouverte
ANDROID SOURCE OF TRUTH : messagerie/repository/ChatRepository.java:127-129,962 (`ON_DELETE_PRIVATE_MESSAGE`, écouté ET émis sur le même canal)
IOS FILES : Realtime/ChatRepository.swift:315-320,400,90,104-106
LOGIC PARITY : Contrairement à V3-F-115 (groupe), la suppression privée est bien écoutée ET émise sur le même canal, propagation confirmée. Mais `handleDeleteMessage` persiste en Core Data SANS émettre d'événement Combine — si la conversation est déjà ouverte, aucun rafraîchissement UI.
STATUT : PARTIAL
PREUVE : `ChatRepository.swift:315-320` (aucun `chatEvents.send` après persistance) vs `handleNewMessage` (envoie bien `chatEvents.send`).
CAUSE : Angle mort — persistance faite, notification Combine oubliée.
RISQUE : Message supprimé "pour tous" reste visible à l'écran jusqu'à fermeture/réouverture, si le destinataire a la conversation déjà ouverte.
RECOMMANDATION : Ajouter `chatEvents.send(.messageDeleted(id:))` (nouveau cas), consommé par `ChatViewModel.handle(_:)`.
TEST RÉEL NÉCESSAIRE : oui — 2 appareils, conversation déjà ouverte des deux côtés, supprimer "pour tous" et observer.
```

```
ID : V3-F-117
PRIORITÉ : P2
DOMAINE : WebRTC/VoIP
FEATURE : Push VoIP à payload malformé — violation potentielle du contrat CallKit obligatoire
ANDROID SOURCE OF TRUTH : Sans équivalent direct (PushKit = fonctionnalité 100% iOS)
IOS FILES : Calls/CallCoordinator.swift:442-452
LOGIC PARITY : Si le décodage du payload échoue, `completion()` est appelé SANS jamais appeler `reportIncomingCall` — viole la règle Apple documentée dans le fichier lui-même (toute notification VoIP DOIT déclencher `reportNewIncomingCall` de façon synchrone).
STATUT : PARTIAL
PREUVE : `CallCoordinator.swift:443-448`.
CAUSE : Défense contre décodage invalide qui viole une règle plus stricte documentée juste au-dessus dans le même fichier.
RISQUE : Faible probabilité (contrat serveur VoIP inexistant, V3-F-031) mais sévérité élevée si déclenché — iOS peut révoquer le droit de recevoir des push VoIP après manquements répétés.
RECOMMANDATION : En cas d'échec de décodage, reporter quand même un appel générique puis le terminer immédiatement, plutôt que de ne jamais reporter.
TEST RÉEL NÉCESSAIRE : non-bloquant tant que le backend VoIP n'existe pas — à re-tester dès son implémentation.
```

```
ID : V3-F-118
PRIORITÉ : P2
DOMAINE : Chat
FEATURE : Mapping des 30 noms d'événements socket — vérification exhaustive positive
ANDROID SOURCE OF TRUTH : messagerie/repository/ChatRepository.java:107-144 (classe `ROOM`)
IOS FILES : Realtime/SocketEvent.swift
LOGIC PARITY : Les 30 constantes vérifiées champ par champ, y compris les 2 pièges les plus probables (`onPbsTouchListener`, `onData`) et la faute d'orthographe volontairement reproduite (`"delivred"`) — toutes exactes.
STATUT : COMPLETE_PARITY_CANDIDATE (upgrade depuis CODE_PRESENT_UNVERIFIED — le blocage V3-F-016 est levé, vérification manuelle confirme l'exactitude)
PREUVE : `SocketEvent.swift:20-78` vs `ChatRepository.java:107-144`.
RISQUE : Aucun.
RECOMMANDATION : Aucune.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-119
PRIORITÉ : P2
DOMAINE : Chat
FEATURE : Accusés de réception (read receipts) — chaîne complète bind→emit→listener→UI, vérification positive
ANDROID SOURCE OF TRUTH : messagerie/ui/adapter/MessageListAdapter.java:739-742,1203-1210 ; messagerie/repository/ChatRepository.java:731-756
IOS FILES : Messagerie/ChatViewModel.swift:432-449,464-473 ; Messagerie/ChatView.swift:195 ; Realtime/ChatRepository.swift:322-339,427
LOGIC PARITY : `handleAppear`→`markAsRead`→`sendMessageState`→émission "displayed" ; réception `handleResponse` (switch 4 cas identique) → persistance + `chatEvents.messageStatus` → mise à jour bulle. Chaîne complète confirmée sans rupture.
STATUT : COMPLETE_PARITY_CANDIDATE
PREUVE : Citations ci-dessus, comparaison champ par champ concordante.
RISQUE : Dépend de V3-F-110/V3-F-113 pour la fiabilité globale du canal, mais la logique de CE flux est fidèle.
RECOMMANDATION : Aucune action de code ; confirmer par test réel.
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-120
PRIORITÉ : P3
DOMAINE : Chat
FEATURE : Absence de resynchronisation REST de l'historique — parité d'absence confirmée
ANDROID SOURCE OF TRUTH : Recherche exhaustive : aucun endpoint HTTP "récupérer historique conversation" trouvé
IOS FILES : Storage/MessageRepository.swift:300-306 (page = requête Core Data pure)
STATUT : COMPLETE_PARITY_CANDIDATE (parité d'absence, fidèle à Android)
CAUSE : Limitation produit pré-existante côté Android, pas un gap de portage.
RISQUE : Réinstallation/changement d'appareil/purge locale fait perdre TOUT l'historique — symétrique aux deux plateformes.
RECOMMANDATION : Aucune action de portage ; signalable au propriétaire produit comme limitation partagée si non désirée.
TEST RÉEL NÉCESSAIRE : non pour la parité.
```

```
ID : V3-F-121
PRIORITÉ : P2
DOMAINE : Chat
FEATURE : Pièces jointes chat (upload/download photo+vidéo) — chaîne complète, vérification positive
ANDROID SOURCE OF TRUTH : messagerie/ui/adapter/MessageListAdapter.java (dispatch par `isFileUploaded==0`/`isFileDownloaded==0`)
IOS FILES : Messagerie/ChatViewModel.swift:484-552, Messagerie/ChatBubbleViews.swift:74-246
LOGIC PARITY : `handleAppear` déclenche `requestUpload`/`requestDownload` au même point que `onBindViewHolder`. Upload via Bunny direct (conforme GAP-004), envoi socket explicite après upload (palliatif documenté pour l'absence de re-bind SwiftUI). Download sans en-tête d'auth, cohérent avec Android (CDN public une fois uploadé).
STATUT : CODE_PRESENT_UNVERIFIED (chaîne cohérente au niveau code, jamais exercée sur device/simulateur)
PREUVE : Citations ci-dessus.
RISQUE : Modéré — pas de compteur de tentatives, retry sur prochain `.onAppear`/scroll (comportement partagé avec Android, pas une régression).
RECOMMANDATION : Surveiller en test réel l'absence de boucle infinie sur échec permanent.
TEST RÉEL NÉCESSAIRE : oui.
```

### 30.3 Animems — régression post-Phase B (PAS un nouvel audit, voir ANIMEMS_PARITY_AUDIT_V1.md)

**Aucune régression trouvée** sur les 11 lots de Phase B Animems — vérifié lot par lot par relecture
du code actuel + `git log` (un seul commit Animems postérieur à `b090153`, `5164acf`, ajout pur isolé
au bloc sheet d'export, aucune suppression/déplacement des lots précédents). F-33 (contrôleur
mouvement), F-34/F-45 (import vidéo/audio), F-40 (zoom visuel), F-17 (contenu templates communautaires)
confirmés inchangés dans l'état exact où Phase B les a laissés.

```
ID : V3-F-122
PRIORITÉ : P2 (documentation — comportement CORRECT, pas un défaut)
DOMAINE : Animems / Feed
FEATURE : Blocage de publication par catégorie de compte (V3-F-058) s'applique aussi au flux Animems→Publier — fidèle à Android, pas une régression
ANDROID SOURCE OF TRUTH : PublishFragment.java:274-283 (classe UNIQUE et partagée, sans branche par origine) ; MemesFragment.java:327-351,410-433 (route vers le même pipeline que caméra/galerie)
IOS FILES : Animems/AnimemesEditorView.swift (appelant), Feed/PublishComposeView.swift (gate interne), Feed/FeedRepository.swift (paramètre `category:`)
LOGIC PARITY : Signature `PublishComposeView.init(media:onPublished:onCancel:)` inchangée depuis `5164acf` — le gate catégorie (commit `5ebf13a`, postérieur) est entièrement interne à `publish()`, aucun paramètre supplémentaire requis côté appelant Animems.
RUNTIME CHAIN : Vérifiée non cassée — chaîne complète Animems→export→publish→gate catégorie intacte.
STATUT : BUILD_VALIDATED (aucun test réel — ce parcours précis n'a jamais été exercé depuis Animems sur device/Appetize)
PREUVE : `PublishFragment.java:274-283` cité ci-dessus ; `PublishComposeView.swift:210-220` ; `git log -- AnimemesEditorView.swift` ne montre aucun commit après `5164acf`.
CAUSE : Réutilisation intentionnelle et documentée de `PublishComposeView` pour Animems (choix de parité fonctionnelle, assumé dans le commit `5164acf`).
RISQUE : Aucun risque de régression identifié — risque résiduel classique : jamais testé en réel, donc l'UX exacte (l'utilisateur Animems comprend-il pourquoi on lui demande une catégorie après avoir exporté un mème ?) n'est pas confirmée empiriquement.
RECOMMANDATION : Aucune action corrective — documenter ce couplage dans `ANIMEMS_PARITY_AUDIT_V1.md` (§3/§18.3, désormais résolu). Prioriser un test réel du parcours complet avant annonce de parité validée.
TEST RÉEL NÉCESSAIRE : oui.
```

### 30.4 Galerie / Photo Editor / Video Editor

```
ID : V3-F-123
PRIORITÉ : P0
DOMAINE : Video Editor
FEATURE : Trim vidéo — échec d'export SILENCIEUX, publication du fichier ORIGINAL non modifié en repli
ANDROID SOURCE OF TRUTH : VideoTrimmerView.java:670-758 (Toast d'erreur explicite, `callback.onVideo()` JAMAIS appelé en cas d'échec) ; MediaTrim.java:178-227 (`onError` → arrêt, aucun callback de succès)
IOS FILES : Feed/MediaTrimView.swift:220-309 (`trim()`)
LOGIC PARITY : Android bloque l'utilisateur sur l'écran de trim en cas d'échec (Toast + pas de callback succès). iOS a 7 points de sortie anticipée (échec export, échec chargement piste, échec composeTransform, échec piste composite, statut != completed sur les 2 chemins) qui appellent TOUS `onTrimmed(sourceURL)` — publient le fichier ORIGINAL BRUT (non coupé, non recadré, potentiellement &gt;60s) comme si le trim avait réussi. Seul indice : un `print()` invisible en production.
RUNTIME CHAIN : `trim()` échoue → `onTrimmed(sourceURL)` → `PublishComposeView.publish()` → `FeedRepository.publish` → Bunny → `activity/add`. Chaîne tracée en entier, confirmée.
STATUT : **BUILD_VALIDATED** (corrigé `0ee101b`, Phase B, CI verte — test réel de trim/crop en échec requis avant COMPLETE_PARITY_VALIDATED)
PREUVE : `MediaTrimView.swift:303-308` — `if exportSession.status == .completed { onTrimmed(outputURL) } else { print(...); onTrimmed(sourceURL) }`, contrat `onTrimmed: (URL) -&gt; Void` sans variante d'échec. (Avant correctif.)
CAUSE : Le contrat de callback ne permet structurellement pas de distinguer succès et échec — chaque garde a été ajoutée en "meilleur effort" plutôt que remontée en erreur.
RISQUE : L'utilisateur qui coupe explicitement une vidéo de 3 minutes à 15 secondes (ou pivote/recadre) peut publier silencieusement l'intégralité non coupée — régression de confidentialité/contenu potentiellement grave.
RECOMMANDATION : Changer la signature en `(Result&lt;URL, Error&gt;) -&gt; Void`, ne JAMAIS retomber sur `sourceURL` sans consentement explicite — fidèle au comportement Android réel (blocage, pas de publication de repli). **Appliqué le 2026-08-20** (`MediaTrimView.swift`) : chaque garde d'échec (création `AVAssetExportSession`, chargement de piste, `composeTransform`, création de piste composite, `status != .completed` sur les 2 chemins export) affiche désormais une alerte `"Échec du recadrage"` et `return`, SANS appeler `onTrimmed` — fidèle au blocage Android réel. Seul le cas légitime `noTrim && noTransform` continue d'appeler `onTrimmed(sourceURL)` (fast-path Android réel, pas un échec). `AVAssetExportSession` confirmé unique dans tout le projet (aucun flux frère à corriger).
TEST RÉEL NÉCESSAIRE : oui — forcer un échec d'export et vérifier qu'aucune vidéo non coupée ne part au serveur.
```

```
ID : V3-F-124
PRIORITÉ : P1
DOMAINE : Video Editor
FEATURE : Justification architecturale du correctif P0-6 invalidée — V3-F-042 sous-estimé (portée élargie)
ANDROID SOURCE OF TRUTH : VideoTrimmerView.java:232-257 (`next.setOnClickListener`, condition réelle) ; :670-758 (`startTrimWithCrop`, SEUL chemin atteignable) ; :807-870 (`startTrimWithCrop2`, confirmé 0 appelant par grep exhaustif)
IOS FILES : Media/VideoTrimState.swift (commentaire de tête), Feed/MediaTrimView.swift:5-28,220-255
LOGIC PARITY : Le commentaire ajouté au Lot 5 (P0-6) affirme une "architecture à deux chemins" Android où `startTrimWithCrop2()` serait un "repli RAPIDE sans transformation... pas un vestige mort". Vérifié par grep : `startTrimWithCrop2` a ZÉRO appelant — c'est du code mort, l'inverse de ce qu'affirme le commentaire. De plus, même actif, il construit lui aussi `VideoTransformer.Params` et appelle `.process()` — il ne "saute" jamais la transformation. Le VRAI mécanisme : `next.setOnClickListener` ne fait AUCUN export quand `noTrim &amp;&amp; noTransform` (aucune modification), et appelle TOUJOURS `startTrimWithCrop()` (re-encodage frame-exact) sinon — MÊME pour un trim purement temporel sans recadrage. **Aucun chemin Android ne fait un simple remux/copie pour un trim temporel seul** — contrairement à iOS qui utilise `AVAssetExportPresetPassthrough` (imprécis, calé keyframe) dès que `needsTransform` est faux, c'est-à-dire pour LA MAJORITÉ des trims réels.
STATUT : **BUILD_VALIDATED** (corrigé `cd316df`, Phase B, CI confirmée verte — test réel de comparaison frame-exacte requis avant COMPLETE_PARITY_VALIDATED)
PREUVE : `grep -rn "startTrimWithCrop2" app/src/main/java/` → 1 seul résultat (la définition). Condition réelle : `if (noTrim &amp;&amp; noTransform) { callback.onVideo(null,false); } else { startTrimWithCrop(); }` (VideoTrimmerView.java:235-252). (Avant correctif : `MediaTrimView.swift` utilisait `AVAssetExportPresetPassthrough` dès que `!needsTransform`.)
CAUSE : Le correctif Lot 5 a construit sa justification sur une méthode Android jamais exécutée en production, sans vérifier son nombre d'appelants.
RISQUE : Pour la majorité des trims (coupe simple sans recadrage), iOS produit un point de coupe imprécis (potentiellement plusieurs secondes de décalage selon le GOP) alors qu'Android produit systématiquement une coupe frame-exacte — écart de qualité perceptible, pas un cas limite rare.
RECOMMANDATION : Soit toujours ré-encoder même sans transformation géométrique (fidèle à Android, coût CPU accru), soit documenter explicitement cet écart et corriger le commentaire erroné de `VideoTrimState.swift`/`MediaTrimView.swift`. **Appliqué le 2026-08-20** (`MediaTrimView.swift`) : le chemin `presetPassthrough` a été supprimé — `trim()` ré-encode désormais systématiquement (`AVMutableComposition`/`AVMutableVideoComposition`) dès que la garde de no-op légitime (`noTrim && noTransform`) n'est pas satisfaite, avec une transformation identité quand `trimState == VideoTrimState()`. Commentaires de tête corrigés (l'ancienne justification "architecture à deux chemins" était fausse, `startTrimWithCrop2()` est du code mort côté Android).
TEST RÉEL NÉCESSAIRE : oui — comparer le point de coupe exact (frame par frame) entre export Android et iOS pour un trim sans recadrage.
```

```
ID : V3-F-125
PRIORITÉ : P1
DOMAINE : Photo Editor
FEATURE : Recadrage ovale — Android est une ellipse libre, iOS force un cercle 1:1 (V3-F-035 requalifié de "risque" à "confirmé")
ANDROID SOURCE OF TRUTH : editor/croper/CropFragment.java:59 (setAspectRatio(1,1) SANS setFixedAspectRatio) ; CropImageViewOptions.java:32 (fixAspectRatio=false par défaut) ; fragment_crop_oval.xml/fragment_crop_rect.xml (aucun `app:cropFixAspectRatio`)
IOS FILES : PhotoEditor/PhotoCropView.swift:36-37 (`CropViewCroppingStyle.circular`)
LOGIC PARITY : `setFixedAspectRatio(true)` n'est JAMAIS appelé dans `CropFragment.java` (grep exhaustif) — le recadrage ovale Android est donc une ELLIPSE LIBRE (n'importe quel ratio). `.circular` (TOCropViewController) verrouille la zone à un carré 1:1, produisant TOUJOURS un cercle parfait.
RUNTIME CHAIN : Le résultat cerclé part réellement en publication (`croppedImage` → JPEG → Bunny).
STATUT : **BUILD_VALIDATED** (corrigé `5eb3358`, Phase B, CI confirmée verte `e869825` — test visuel réel requis avant COMPLETE_PARITY_VALIDATED)
PREUVE : `CropImageViewOptions.java:32` (pas d'initialiseur = false) ; aucun `setFixedAspectRatio(true)` trouvé ; aucun `app:cropFixAspectRatio` dans les 2 layouts XML. (Avant correctif : `PhotoCropView.swift:36` utilisait `.circular`.)
CAUSE : Remplacement du moteur maison Android par TOCropViewController (décision assumée), mais le style `.circular` ne couvre pas le mode "ellipse libre" réel d'Android.
RISQUE : Perte silencieuse de fonctionnalité pour les portraits larges non carrés (le bouton "fonctionne" mais produit un résultat visuellement différent).
RECOMMANDATION : Utiliser `.default` avec masque de rendu ovale appliqué après coup (comme `FreeformCropView`), ou documenter explicitement comme IOS_INTENTIONAL_DIFFERENCE assumée. **Appliqué le 2026-08-20** (`PhotoCropView.swift`) : le mode "Ovale" utilise désormais `.default` (zone de recadrage rectangulaire libre, même ratio libre qu'Android) puis applique `PhotoCropUtils.toOvalImage` (port direct de `CropImage.toOvalBitmap`, déjà écrit lors d'un correctif antérieur mais jamais câblé — confirmé zéro appelant avant ce correctif) sur le rectangle recadré. `.circular` confirmé, par grep, sans autre usage dans tout le projet.
TEST RÉEL NÉCESSAIRE : oui — recadrer une photo en "Ovale" avec un ratio non carré sur les 2 plateformes et comparer.
```

```
ID : V3-F-126
PRIORITÉ : P1 (reconfirmation de V3-F-039, toujours présent, inchangé)
DOMAINE : Photo Editor
FEATURE : Aplatissement (flatten) peinture/texte/stickers — distorsion de ratio toujours présente
ANDROID SOURCE OF TRUTH : Voir V3-F-039
IOS FILES : PhotoEditor/PhotoToolsView.swift:227-249 (`flatten()`)
LOGIC PARITY : `renderer.scale` dérive uniquement du ratio de LARGEUR (`canvasSize`=taille écran vs taille photo). Si le ratio de l'écran diffère du ratio de la photo source (cas courant), le rendu final aura les dimensions du RATIO ÉCRAN, pas du ratio photo — les bandes de lettrboxing (transparentes/blanches dans le composé, contrairement au fond noir explicite de l'écran d'édition) sont gravées définitivement dans l'image publiée dès qu'un trait/texte a été ajouté.
STATUT : PARTIAL (confirmation — fichier inchangé depuis sa création)
PREUVE : `renderer.scale = max(displayedImage.size.width / canvasSize.width, 1) * displayedImage.scale` (une seule composante, ligne 247) ; vue composée sans fond noir explicite (ligne 244) contrairement à l'écran d'édition (ligne 47).
CAUSE : `ImageRenderer.scale` scalaire unique suppose implicitement le même ratio pour `canvasSize` et `displayedImage`.
RISQUE : Toute publication avec peinture/texte/sticker sur une photo de ratio ≠ écran introduit bandes de bord non désirées et distorsion des dimensions publiées.
RECOMMANDATION : Rendre le composé à la résolution EXACTE de `displayedImage`, convertir les positions du repère `canvasSize` vers le repère réel de l'image affichée.
TEST RÉEL NÉCESSAIRE : oui — publier une photo 1:1 ou 4:3 avec un trait de peinture sur un écran ~9:19.5, comparer dimensions/contenu du JPEG uploadé.
```

```
ID : V3-F-127
PRIORITÉ : P3
DOMAINE : Galerie
FEATURE : Commentaire obsolète — FeedRepository.swift affirme à tort que le blocage catégorie n'est pas reproduit
IOS FILES : Feed/FeedRepository.swift:133-137 (commentaire), Feed/PublishComposeView.swift:207-220 (code réel, correct)
STATUT : COMPLETE_PARITY_CANDIDATE (le code est correct — seul le commentaire ment)
PREUVE : Commentaire du commit `4ee582e` jamais mis à jour après l'ajout du blocage réel par `5ebf13a` (même journée).
CAUSE : Mise à jour de commentaire oubliée après un correctif touchant un fichier voisin.
RISQUE : Faible — un futur audit basé sur ce commentaire seul re-signalerait à tort BUNNY-01/V3-F-058.
RECOMMANDATION : Mettre à jour le commentaire pour renvoyer vers `PublishComposeView.publish()`/`CategoryPickerView.swift`.
TEST RÉEL NÉCESSAIRE : non.
```

### 30.5 Settings / Permissions / Notifications / DeepLinks

```
ID : V3-F-128
PRIORITÉ : P1
DOMAINE : Settings
FEATURE : Bouton "Catégorie du compte" mal placé — devrait être dans Modifier le profil, pas Réglages > Compte
ANDROID SOURCE OF TRUTH : uploadPerfilPhoto/EditProfile.java:72-73 (lance CategoryActivity DEPUIS l'écran d'édition de profil) ; setting/SettingAccountFragment.java (207 lignes, entier — AUCUN champ catégorie)
IOS FILES : Settings/SettingSubViews.swift:9-56 (SettingAccountView), Profile/EditProfileView.swift:1-5
LOGIC PARITY : Le vrai gap (bouton manquant dans `EditProfileView`) reste documenté MAIS non comblé (commentaire propre du fichier : "Catégorie NON portée cette session"), tandis qu'un doublon fonctionnel a été ajouté au mauvais endroit (Réglages > Compte).
STATUT : **CODE_PRESENT_UNVERIFIED** (corrigé, Phase B — CI pas encore confirmée verte)
PREUVE : `SettingSubViews.swift:9-13` ("aucun équivalent Android direct identifié... placé ici par analogie") ; `EditProfileView.swift:3-5` ("Catégorie NON portée cette session"). (Avant correctif.)
CAUSE : Deux sessions de portage différentes ont traité le même gap sans se recouper.
RISQUE : Navigation divergente de l'attente Android ; risque de double-maintenance si le vrai gap est comblé plus tard sans retirer le doublon.
RECOMMANDATION : Déplacer (ou dupliquer en le documentant explicitement) le point d'entrée vers `EditProfileView.swift`. **Appliqué le 2026-08-20** : déplacé (pas dupliqué) — retiré de `SettingAccountView` (`Settings/SettingSubViews.swift`), ajouté à `EditProfileView.swift` avec le même `CategoryPickerView`/`ProfileRepository.fetchProfile`, fidèle à `categoryView.setOnClickListener` (`EditProfile.java:68-75`).
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-129
PRIORITÉ : P1
DOMAINE : Settings
FEATURE : Liens légaux (CGU/confidentialité) pointent vers la racine du site, pas les pages réelles
ANDROID SOURCE OF TRUTH : setting/SettingAboutFragment.java:93-108 (`privacy`→`/privacy_policy.html`, `terms`→`/terms_conditions.html`, ouverts en WebView interne)
IOS FILES : Settings/SettingSubViews.swift:220-229 (SettingAboutView)
LOGIC PARITY : Les DEUX libellés pointent vers `https://tiinver.com` (racine), pas les pages légales réelles ; ouverture via Safari externe au lieu d'une WebView interne.
STATUT : **CODE_PRESENT_UNVERIFIED** (corrigé, Phase B — CI pas encore confirmée verte)
PREUVE : `SettingSubViews.swift:224-225` — deux `Link` vers la même URL racine. (Avant correctif.)
CAUSE : `SettingAboutFragment.java` jamais lu en détail au moment du portage (commentaire du fichier iOS obsolète maintenant contredit).
RISQUE : Problème potentiel de conformité (RGPD/App Store review) — un lien "Politique de confidentialité" doit mener au texte légal réel.
RECOMMANDATION : Remplacer par les URLs exactes. **Appliqué le 2026-08-20** : URLs réelles (`/privacy_policy.html`, `/terms_conditions.html`, confirmées dans `SettingAboutFragment.java:93-108` ET déjà correctes dans `PoliticaDemandView.swift`), ouvertes en `InAppWebView` (port de `MyWebView.java`, réutilisé — promu `internal` — plutôt que dupliqué) au lieu d'un `Link` Safari externe.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-130
PRIORITÉ : P2
DOMAINE : Settings
FEATURE : FAQ localisée (fr/en) et contact support absents côté iOS
ANDROID SOURCE OF TRUTH : setting/SettingHelpFragment.java:88-119 (FAQ selon `Locale.getDefault()` ; bouton support avec handler VIDE côté Android aussi)
IOS FILES : Settings/SettingSubViews.swift:211-218 (SettingHelpView)
LOGIC PARITY : iOS n'a qu'un lien générique vers la racine du site, aucune FAQ localisée, aucun affichage de l'adresse support.
STATUT : PARTIAL
CAUSE : Fragment jamais lu en détail malgré sa présence dans la cartographie V2.
RISQUE : Faible (le lien support est déjà mort côté Android) mais UX dégradée pour utilisateurs francophones.
RECOMMANDATION : Porter le lien FAQ avec sélection de langue ; le bouton support n'a pas à devenir fonctionnel (fidèle à Android, mort des deux côtés).
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-131
PRIORITÉ : P0
DOMAINE : Settings
FEATURE : Toggle thème clair/sombre — ne change RIEN visuellement sur iOS
ANDROID SOURCE OF TRUTH : Utils/ThemeUtils.java:31-38 (`AppCompatDelegate.setDefaultNightMode`, changement visuel immédiat app-wide) ; SettingChatFragment.java:136-147
IOS FILES : Settings/SettingSubViews.swift:178-191 (SettingAppearanceView), App/TiinverApp.swift (aucun `.preferredColorScheme`)
LOGIC PARITY : `@AppStorage("theme")` écrit dans UserDefaults mais grep exhaustif confirme AUCUNE vue ne le lit pour appliquer `.preferredColorScheme` — seule occurrence = la déclaration elle-même.
RUNTIME CHAIN : USER ACTION (changer le Picker) → STATE écrit → RESULT : jamais consommé → RENDU : rien ne change.
STATUT : **BUILD_VALIDATED** (corrigé `11f118a`, Phase B, CI verte — test visuel réel requis)
PREUVE : `grep -rn "@AppStorage(\"theme\")|\"theme\"" Sources` → 1 seul résultat ; `TiinverApp.swift` (12 lignes) sans `preferredColorScheme`.
CAUSE : Picker de thème porté comme simple state UI sans câbler l'application réelle du colorScheme.
RISQUE : Régression flagrante et facilement testable — le mode sombre fonctionne réellement sur Android, pas du tout sur iOS.
RECOMMANDATION : Appliquer `.preferredColorScheme(theme == "Dark" ? .dark : .light)` au niveau de `WindowGroup`/`RootRouterView`.
TEST RÉEL NÉCESSAIRE : oui — vérifier visuellement que le toggle change l'app.
```

```
ID : V3-F-132
PRIORITÉ : P3
DOMAINE : Settings
FEATURE : Préférences notifications/stockage — persistées mais jamais lues, parité RÉELLE (dead-code partagé, pas une régression)
ANDROID SOURCE OF TRUTH : `notificateChats/Groups/Pages` déclarés (SettingsActivity.java:43-45) mais JAMAIS relus dans MyFirebaseMessagingService.java (grep confirmé côté Android aussi)
IOS FILES : Settings/SettingSubViews.swift:96-131
STATUT : COMPLETE_PARITY_VALIDATED (parité d'absence confirmée des deux côtés)
CAUSE : Sans objet — parité réelle par absence symétrique.
RISQUE : Aucun.
RECOMMANDATION : Aucune action.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-133
PRIORITÉ : P2
DOMAINE : Settings
FEATURE : `AUTHORIZED_ADS` (pub personnalisée) — persisté mais jamais consulté par AdMobManager, contrairement à Android
ANDROID SOURCE OF TRUTH : `infoContract.AUTHORIZED_ADS` lu réellement dans `FeedFragment.java:1804`/`MainFragment.java:1839` (gate réel avant injection de pub)
IOS FILES : Settings/SettingSubViews.swift:195-204, Advertising/AdMobManager.swift
LOGIC PARITY : Grep exhaustif : `AUTHORIZED_ADS` apparaît UNIQUEMENT dans sa propre déclaration/toggle, jamais dans `AdMobManager.swift`.
STATUT : PARTIAL
CAUSE : Toggle porté comme UI pure sans câblage vers le SDK AdMob iOS.
RISQUE : Faible/moyen — cosmétique, l'utilisateur croit contrôler la personnalisation pub sans effet réel.
RECOMMANDATION : Câbler `AUTHORIZED_ADS` dans `AdMobManager.swift` avant chargement d'une requête pub (mode "non personnalisé" si `false`).
TEST RÉEL NÉCESSAIRE : non pour le constat, oui pour valider le fix.
```

```
ID : V3-F-134
PRIORITÉ : P0
DOMAINE : Permissions
FEATURE : Aucun repli utilisateur (alerte + redirection Réglages) en cas de refus de permission caméra/micro/photos
ANDROID SOURCE OF TRUTH : editor/camera/CameraXFragment.java:534-550,596-619 (dialogue `ErrorDialog` visible + rationale)
IOS FILES : Camera/CameraCaptureController.swift:19,58, Camera/CameraView.swift, Camera/CameraRecorder.swift
RUNTIME CHAIN : USER ACTION (refuse permission) → `permissionDenied` émis → RÉSULTAT : grep exhaustif (`.alert`, `UIAlertController`, `openSettingsURLString`) = ZÉRO occurrence liée dans tout le module Camera, ET `openSettingsURLString` = ZÉRO occurrence sur TOUT le projet.
STATUT : **BUILD_VALIDATED** (corrigé `83e9dee`, Phase B, CI verte — test réel requis : refuser la permission, ouvrir Réglages, accorder, revenir)
PREUVE : `CameraCaptureController.swift:19,58` (erreur définie et émise, jamais consommée avec UI) ; `grep -rln "openSettingsURLString" Sources` → 0 résultat.
CAUSE : Le chemin d'erreur existe au niveau modèle mais aucune vue n'y souscrit ; aucune primitive de redirection Réglages n'a jamais été implémentée.
RISQUE : Un utilisateur qui refuse la permission caméra/micro se retrouve devant un écran silencieusement cassé, sans explication ni chemin de récupération — pire que le comportement Android.
RECOMMANDATION : Ajouter `.alert` sur `permissionDenied` avec bouton "Ouvrir Réglages" (`UIApplication.open(openSettingsURLString)`) ; re-vérifier sur `scenePhase == .active` pour relancer automatiquement après retour des Réglages.
TEST RÉEL NÉCESSAIRE : oui — device réel, refuser la permission puis revenir depuis Réglages.
```

```
ID : V3-F-135
PRIORITÉ : P2
DOMAINE : Permissions
FEATURE : Comparaison Info.plist vs AndroidManifest — parité réelle confirmée par absence symétrique (localisation)
ANDROID SOURCE OF TRUTH : AndroidManifest.xml:44-45 (permissions localisation déclarées mais JAMAIS consommées par le code applicatif — probablement héritées d'un SDK tiers)
IOS FILES : project.yml:179-182 (NSCamera/NSMicrophone/NSPhotoLibrary/NSContacts présents et cohérents ; pas de NSLocationWhenInUseUsageDescription)
STATUT : COMPLETE_PARITY_VALIDATED (parité réelle par absence des deux côtés)
CAUSE : Sans objet.
RISQUE : Si une fonctionnalité géo est ajoutée plus tard côté iOS SANS ajouter la clé, crash immédiat garanti (contrairement à Android qui logue juste un refus).
RECOMMANDATION : Documenter comme dette à combler SI une fonctionnalité géo est ajoutée.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-136
PRIORITÉ : P3 (requalifié — voir CAUSE, prémisse du finding original invalidée par vérification directe)
DOMAINE : Notifications
FEATURE : Tap sur notification — contradiction résolue : Android n'ouvre JAMAIS une destination spécifique non plus
ANDROID SOURCE OF TRUTH : back_sync/NotificationUtils.java:104-114,151 (`displayNotificationOrPushMessage`, chat), :251-262 (`displayNotification`, profil), :290-337 (`displayNoMessageNotification`, like/comment/follow/post/missedcall), :342-346 (`show()`, seul point qui construit réellement l'Intent affiché)
IOS FILES : App/AppDelegate.swift:153-162
LOGIC PARITY : **Le finding original (P0, MISSING) reposait sur une prémisse fausse, invalidée par lecture directe avant tout correctif** — exactement le type de vérification que cette session impose avant tout code. `displayNotificationOrPushMessage` CONSTRUIT bien un `Intent(mContext, ActivityMsg.class)` riche (avec `MessageLib` en extra) à la ligne 104, MAIS cette variable `intent` n'est **jamais utilisée** : la ligne 151 appelle `show(icon, destination, message, action, title)` où `destination` est une chaîne LITTÉRALE `"MainActivity"` (ligne 114), jamais `intent` lui-même. `show()` (ligne 346) reconstruit son PROPRE `Intent` à partir de `activityMap.get(destination)` — donc `activityMap.get("MainActivity")` → `SplashActivity.class`, SANS AUCUN extra. Même constat pour `displayNotification` (profil, ligne 261 : `destination = "MainActivity"` codé en dur) et `displayNoMessageNotification` (like/comment/follow/post/missedvoicecall, ligne 302 : `String destination = "MainActivity";`, avec la ligne 301 juste au-dessus **explicitement commentée** : `// String destination = notificationVO.getActionDestination();` — preuve d'un mécanisme de routage dynamique qui existait autrefois et a été désactivé). `NotificationVO.getActionDestination()`/`.setActionDestination()` confirmés par grep exhaustif comme n'étant appelés NULLE PART ailleurs dans tout le projet Android, code mort.
RUNTIME CHAIN : **Sur Android, TAPER N'IMPORTE QUELLE notification Tiinver (message privé, message groupe, like, commentaire, follow, nouveau post, appel manqué) ouvre `SplashActivity` — l'écran de lancement générique, avec ZÉRO extra/contexte transmis.** `SplashActivity` fait ensuite son routage normal (session→Home ou Login), pas un routage spécifique à la notification. Ce n'est ni un bug de portage iOS, ni une fonctionnalité Android à reproduire fidèlement dans le sens où le finding original l'imaginait — c'est le comportement RÉEL, déjà `SplashActivity`≈`RootRouterView.swift` déjà porté et audité en V2.
STATUT : COMPLETE_PARITY_CANDIDATE (voire IOS_IMPROVED sur le plan pratique — voir RISQUE)
PREUVE : `NotificationUtils.java:114,151,261,302,337,346` (5 citations directes, dont un commentaire explicitement désactivé prouvant l'intention originale) ; `grep -rn "getActionDestination|setActionDestination"` sur tout `app/src/main/java` = uniquement la déclaration du getter/setter, zéro appelant.
CAUSE : Le finding original (produit par un agent d'audit) a lu la CONSTRUCTION des `Intent` riches (`ActivityMsg`/`HomeActivity`/`ShowNoti`) sans vérifier qu'ils sont ensuite réellement UTILISÉS par `show()` — ils ne le sont pas, `show()` reconstruit systématiquement un `Intent` bare vers `SplashActivity`. Erreur de lecture corrigée par vérification personnelle avant tout code, conformément à la règle anti-erreurs de cette session.
RISQUE : Aucun côté iOS — le comportement actuel (`DeepLinkCenter.shared.route(.notifications)`, ouvrant le centre de notifications où l'utilisateur peut ensuite taper l'item précis) est FONCTIONNELLEMENT AU MOINS ÉQUIVALENT à Android (qui ouvre un écran encore plus générique, sans même la liste des notifications pré-filtrée). Il est même arguable qu'iOS soit meilleur : Android perd toute trace du contexte de la notification tapée, iOS la conserve au moins dans le centre de notifications.
RECOMMANDATION : **Aucun correctif de code** — implémenter le routage contextuel imaginé par le finding original ferait diverger iOS d'Android dans le sens "iOS fait mieux", ce qui est une décision produit (UX à améliorer sur les DEUX plateformes potentiellement) et non un gap de parité à combler silencieusement. Si un vrai routage contextuel est souhaité, c'est une amélioration produit à discuter explicitement (et à appliquer aux deux plateformes, Android ayant lui-même régressé sur ce point vu le commentaire désactivé), pas une correction de parité.
TEST RÉEL NÉCESSAIRE : non pour la parité (établie par lecture de code déterministe des deux côtés) ; utile seulement si une décision produit d'amélioration UX est prise séparément.
```

```
ID : V3-F-137
PRIORITÉ : P1
DOMAINE : DeepLinks
FEATURE : Deep link "myaccount" — ouvre le menu Réglages générique au lieu du sous-écran "Compte"
ANDROID SOURCE OF TRUTH : partage/ShareActivity.java:179-185 (`case "myaccount"` → `SettingsActivity` INDEX=7, sous-écran exact SettingAccountFragment)
IOS FILES : Navigation/DeepLinkRouter.swift:65-66, Navigation/HomeShellView.swift:148-150
LOGIC PARITY : `DeepLinkDestination.settings` n'a pas été granularisé pour porter une sous-destination.
STATUT : PARTIAL
RISQUE : Moyen — l'utilisateur doit taper une fois de plus après ouverture du lien.
RECOMMANDATION : Étendre `DeepLinkDestination.settings` en `.settingsAccount`, router directement.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-138
PRIORITÉ : P2
DOMAINE : DeepLinks
FEATURE : Échec silencieux des deep links user/post/group en cas d'erreur réseau
ANDROID SOURCE OF TRUTH : partage/ShareActivity.java:264-268 (`onError` → dialogue visible)
IOS FILES : Navigation/DeepLinkRouter.swift:89-109
LOGIC PARITY : `guard let ... = try? await ... else { return }` — aucun chemin d'erreur visible.
STATUT : PARTIAL
RISQUE : Faible/moyen — un lien mort/expiré ouvre l'app sans aucune indication d'échec.
RECOMMANDATION : Ajouter un état d'erreur visible (toast/alert) sur échec de résolution.
TEST RÉEL NÉCESSAIRE : non.
```

### 30.6 Monétisation / Groupes / Authentification

```
ID : V3-F-139
PRIORITÉ : P2
DOMAINE : Monétisation
FEATURE : AdMob (bannière/rewarded/rewarded-interstitial/native) — câblage complet confirmé
ANDROID SOURCE OF TRUTH : Activity/service/NativeAdsManager.java ; FeedFragment.java:1758-1903 ; wallet/*Activity.java
IOS FILES : Advertising/AdMobManager.swift, AdMobIdentifiers.swift, Feed/FeedView.swift, Wallet/*.swift
STATUT : COMPLETE_PARITY_CANDIDATE
PREUVE : Tous les sites d'instanciation (`RewardedAdManager`/`RewardedInterstitialAdManager`/`NativeAdLoader`/`AdBannerView`) résolus et confirmés, même modulo (`adsOnFeedPost=7`) que `ADS_ON_FEED_POST`.
RISQUE : Aucun nouveau — le rendu natif reste un portage partiel assumé déjà connu (une annonce à la fois, pas de pool retry).
RECOMMANDATION : Aucune action.
TEST RÉEL NÉCESSAIRE : oui (chargement effectif AdMob sur device).
```

```
ID : V3-F-140
PRIORITÉ : P0 (reconfirmation, inchangé)
DOMAINE : Monétisation
FEATURE : Achat de pièces StoreKit 2 — vérification serveur toujours absente
IOS FILES : Wallet/CoinStoreManager.swift:60-170
LOGIC PARITY : Code relu, conforme à la description P0-7 : `transaction.finish()` seulement si confirmation serveur ; sinon redélivrance via `Transaction.updates`. Crédit local optimiste avant confirmation dans les 2 chemins.
STATUT : FUNCTIONALLY_FAILED (inchangé — l'endpoint backend `storekit/verify-purchase` n'existe toujours pas)
RISQUE : Argent réel dépensé peut rester non crédité durablement si le prochain lancement ne se produit pas avant resynchronisation du profil.
RECOMMANDATION : Implémenter l'endpoint serveur avant mise en production.
TEST RÉEL NÉCESSAIRE : oui (sandbox StoreKit + backend réel).
```

```
ID : V3-F-141
PRIORITÉ : P3
DOMAINE : Monétisation
FEATURE : Boost/campagnes — aucune régression après modifications de session
STATUT : COMPLETE_PARITY_CANDIDATE (confirmé, module isolé, aucun couplage avec CoinStoreManager/GroupRepository)
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-142
PRIORITÉ : P1
DOMAINE : Groupes
FEATURE : Groupes payants — chaîne complète abonnement/renouvellement (V3-F-070) tracée bout en bout, aucun maillon manquant
ANDROID SOURCE OF TRUTH : ChatFragmentTest.java:618-629,707-749,3023-3057 ; MessageListAdapter.java:247-412 ; infoContract.java:49-50
IOS FILES : Messagerie/ChatViewModel.swift:82,97-149 ; Messagerie/ChatListItem.swift:37-46 ; Messagerie/GroupRepository.swift:291-323 ; Messagerie/ChatView.swift:48,171,175
STATUT : COMPLETE_PARITY_CANDIDATE (upgrade depuis BUILD_VALIDATED)
PREUVE : Chaîne complète vérifiée — payload identique, comparaison de solde stricte `&gt;` reproduite, messages système corrects.
RECOMMANDATION : Test réel avec un groupe payant réel (non-membre/expiré/restreint).
TEST RÉEL NÉCESSAIRE : oui.
```

```
ID : V3-F-143
PRIORITÉ : P1
DOMAINE : Authentification
FEATURE : Routeur d'authentification — 9 positions Android vérifiées champ par champ
ANDROID SOURCE OF TRUTH : Authentification/MainActivity.java (switch 0-8)
IOS FILES : Navigation/AuthCoordinatorView.swift
LOGIC PARITY : Les 9 positions correspondent exactement, y compris position 5 (`MyCodeConfirmFragment`) confirmée morte dans le contexte Auth des deux côtés.
STATUT : COMPLETE_PARITY_CANDIDATE (pas VALIDATED — aucun test réel device n'a eu lieu, corrigé par rapport à la conclusion initiale de l'agent)
TEST RÉEL NÉCESSAIRE : non (structure de navigation, faible risque runtime) — mais statut plafonné par la règle stricte de la taxonomie.
```

```
ID : V3-F-144
PRIORITÉ : P2
DOMAINE : Authentification
FEATURE : Inscription email/téléphone — champs/validation/erreurs fidèles
ANDROID SOURCE OF TRUTH : Authentification/register/SignupFragment.java (source active — Inscrire.java mort, phoneNumber.java sans appelant)
IOS FILES : Authentication/RegisterView.swift
STATUT : COMPLETE_PARITY_CANDIDATE
TEST RÉEL NÉCESSAIRE : oui (léger).
```

```
ID : V3-F-145
PRIORITÉ : P2
DOMAINE : Authentification
FEATURE : Connexion/Inscription via Google (Firebase)
IOS FILES : Authentication/GoogleSignInCoordinator.swift
LOGIC PARITY : `providerId` = `FirebaseUser.uid` (équivalent exact de `profile.getUid()`), coordinateur factorisé (Android duplique dans 2 fichiers) sans impact fonctionnel.
STATUT : COMPLETE_PARITY_CANDIDATE
TEST RÉEL NÉCESSAIRE : oui (OAuth réel).
```

```
ID : V3-F-146
PRIORITÉ : P2
DOMAINE : Authentification
FEATURE : Vérification de code (email) — double usage inscription/mot de passe oublié
IOS FILES : Authentication/EmailVerificationView.swift
STATUT : COMPLETE_PARITY_CANDIDATE
TEST RÉEL NÉCESSAIRE : oui (léger).
```

```
ID : V3-F-147
PRIORITÉ : P3
DOMAINE : Authentification
FEATURE : Mot de passe oublié — email de confirmation en clair (bug PARTAGÉ, pas une régression iOS)
ANDROID SOURCE OF TRUTH : Authentification/passwordrecovery/mdpOublier.java:151-170 (endpoint "mail", nouveau mot de passe en TEXTE CLAIR)
IOS FILES : Authentication/NewPasswordView.swift:66-82
STATUT : COMPLETE_PARITY_CANDIDATE (parité comportementale, défaut préexistant côté Android)
RISQUE : Faible risque de sécurité PARTAGÉ, pas introduit par le portage.
RECOMMANDATION : Décision produit hors périmètre parité — arrêter d'envoyer le mot de passe en clair, des DEUX côtés.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-148
PRIORITÉ : P2
DOMAINE : Authentification
FEATURE : Récupération par téléphone silencieusement bloquée (bug PARTAGÉ, reproduit fidèlement)
ANDROID SOURCE OF TRUTH : Authentification/passwordrecovery/RecoverPassword.java:79-93 (`clicOub` vérifie toujours `!mail.isEmpty()`, même en mode téléphone)
IOS FILES : Authentication/ForgotPasswordRequestView.swift:32-44
STATUT : COMPLETE_PARITY_CANDIDATE (bug partagé, PAS une régression iOS)
RECOMMANDATION : Signaler au propriétaire produit pour correction synchronisée Android+iOS.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-149
PRIORITÉ : P1
DOMAINE : Authentification
FEATURE : Restauration de session au relancement
ANDROID SOURCE OF TRUTH : SplashActivity.java:98-122
IOS FILES : Navigation/RootRouterView.swift
STATUT : IOS_IMPROVED (session) / DIVERGENCE PRODUIT VOLONTAIRE DOCUMENTÉE (comparaison de version retirée, déjà actée le 2026-08-13)
RISQUE : Faible, documenté et intentionnel.
TEST RÉEL NÉCESSAIRE : non.
```

```
ID : V3-F-150
PRIORITÉ : P3
DOMAINE : Authentification
FEATURE : Attribution de parrainage à l'installation (Install Referrer) — capacité plateforme absente
ANDROID SOURCE OF TRUTH : SplashActivity.java:175-216 (Play Install Referrer API)
IOS FILES : Navigation/DeepLinkRouter.swift, Navigation/RootRouterView.swift:65-67
STATUT : ANDROID_ONLY (capacité plateforme, pas un oubli de portage)
RISQUE : Parrainages via lien Play Store cliqué avant installation non trackables côté iOS de la même façon.
RECOMMANDATION : Évaluer un SDK d'attribution tiers si stratégique, sinon documenter comme limitation acceptée.
TEST RÉEL NÉCESSAIRE : non.
```

### 30.7 Balayage transversal (code mort / stubs, hors Animems)

Décompte honnête : 289 sites `try?` (0 retenu — motif décodage-tolérant déjà établi), 53 clauses
`catch` non vides (0 retenu — gestion correcte ou politique de retry documentée), 22 fichiers
`TODO`/`stub` (0 retenu — usages légitimes déjà trackés ailleurs), 3 `fatalError` (boilerplate
CoreDataStack standard, non retenus), 74 vues SwiftUI vérifiées (0 orpheline hors Animems), ~75
classes/services vérifiés (1 orpheline confirmée).

```
ID : V3-F-151
PRIORITÉ : P2
DOMAINE : Transversal
FEATURE : Upload photo de profil — échec réseau totalement silencieux (`catch {}` littéralement vide)
IOS FILES : Profile/ProfileViewModel.swift:157-165
RUNTIME CHAIN : `ProfileView.swift:77-85` (sélection photo réelle via PhotosPicker) → `uploadProfilePicture` → `catch {}` vide, contrairement aux 53 autres clauses catch du projet (toutes avec message utilisateur ou diagnostic).
STATUT : FUNCTIONALLY_FAILED (partiel — dégrade l'UX sans casser le succès)
PREUVE : Ligne 164, corps vide, comparé à `loadProfile()` (ligne 105-108, même fichier, qui alimente `errorMessage`+`print()` pour un cas comparable).
CAUSE : Oubli lors du portage.
RISQUE : En cas d'échec réseau pendant l'upload, l'utilisateur voit le spinner disparaître sans indication — peut croire l'opération réussie.
RECOMMANDATION : Ajouter `errorMessage` + `print()` diagnostic, à l'identique du motif de `loadProfile()`.
TEST RÉEL NÉCESSAIRE : oui (simuler coupure réseau pendant l'upload).
```

```
ID : V3-F-152
PRIORITÉ : P3
DOMAINE : Transversal
FEATURE : `ProTimelineViewModel.swift` — logique de trim "pro" complète (293 lignes) jamais instanciée
ANDROID SOURCE OF TRUTH : editor/view/ProTimelineView.java (763 lignes)
IOS FILES : Media/ProTimelineViewModel.swift
RUNTIME CHAIN : `grep -rn "ProTimelineViewModel("` = zéro site d'appel. `MediaTrimView.swift` (l'écran réellement monté) utilise sa propre géométrie simplifiée à la place.
STATUT : DEAD_CODE (déjà partiellement tracké dans `MIGRATION_AUDIT.md:115`/`MIGRATION_PROGRESS.md`, jamais consolidé dans V3)
CAUSE : Logique pure écrite en avance du rendu Canvas SwiftUI, jamais terminée — `MediaTrimView.swift` livré avec une géométrie plus simple à la place.
RISQUE : Faible — 293 lignes maintenues sans bénéfice, risque de confusion pour un futur contributeur.
RECOMMANDATION : Supprimer le fichier, ou documenter explicitement comme vestige volontairement laissé de côté.
TEST RÉEL NÉCESSAIRE : non.
```

### 30.8 Décompte des statuts — cycle complémentaire (54 nouveaux findings, V3-F-099 à V3-F-152)

- `MISSING` : 2 (V3-F-099 hashtag/mention tap, +1 déjà cité) — **V3-F-136 retiré de ce décompte, voir requalification ci-dessous**
- `FUNCTIONALLY_FAILED` : 8 (V3-F-103, V3-F-107, V3-F-110, V3-F-123, V3-F-131, V3-F-134, V3-F-140 [reconfirmation], V3-F-151)
- `PARTIAL` : 20
- `CODE_PRESENT_UNVERIFIED` : 4
- `COMPLETE_PARITY_CANDIDATE` : 17 (V3-F-136 y entre après requalification)
- `COMPLETE_PARITY_VALIDATED` : 2 (V3-F-132, V3-F-135 — parité par absence symétrique, pas des fonctionnalités testées sur device)
- `BUILD_VALIDATED` : 2 (V3-F-111, V3-F-122)
- `IOS_IMPROVED` : 2 (V3-F-109, V3-F-149)
- `ANDROID_ONLY` : 1 (V3-F-150)
- `DEAD_CODE` : 1 (V3-F-152)

**MISE À JOUR 2026-08-20 (Phase B, avant tout code)** — V3-F-136 a été **requalifié de P0/MISSING à
P3/COMPLETE_PARITY_CANDIDATE** après vérification personnelle directe du code Android AVANT
d'écrire le moindre correctif (règle anti-erreurs) : la prémisse du finding original était fausse.
`show()` (`NotificationUtils.java:346`) reconstruit TOUJOURS un `Intent` bare vers `SplashActivity`
(`activityMap.get("MainActivity")`), quel que soit le type de notification — les `Intent` riches
construits par `displayNotificationOrPushMessage`/`displayNotification`/`displayNoMessageNotification`
sont des variables locales JAMAIS utilisées. Preuve supplémentaire : `displayNoMessageNotification`
contient une ligne commentée (`// String destination = notificationVO.getActionDestination();`)
prouvant qu'un routage dynamique existait autrefois et a été désactivé côté ANDROID lui-même ;
`getActionDestination()`/`setActionDestination()` confirmés morts par grep exhaustif (zéro appelant
dans tout le projet Android). Le comportement iOS actuel (ouvrir le centre de notifications) est
donc déjà à parité, voire meilleur qu'Android (qui perd tout contexte au tap). Voir le finding
complet ci-dessus pour le détail — **aucun code n'a été modifié pour ce point**, correction
purement documentaire.

**Nouveaux P0 (4 restants après requalification de V3-F-136, tous non identifiés par les cycles précédents) — LOT TERMINÉ le 2026-08-20 (Phase B), 4/4 corrigés côté code, CI verte sur les 4** :
1. **V3-F-110** — WebRTC : `isOnCall` jamais mis à `true`, signalisation d'appel entrant jamais routée vers l'appel réel. **Le plus sévère.** ✅ **CORRIGÉ le 2026-08-20** (commit `2a779f6`, Phase B) — `BUILD_VALIDATED`.
2. **V3-F-131** — Réglages : toggle thème clair/sombre sans aucun effet visuel. ✅ **CORRIGÉ le 2026-08-20** (commit `11f118a`, Phase B) — `BUILD_VALIDATED`.
3. **V3-F-134** — Permissions : aucun repli utilisateur (alerte/redirection Réglages) en cas de refus caméra/micro/photos. ✅ **CORRIGÉ le 2026-08-20** (commit `83e9dee`, Phase B) — `BUILD_VALIDATED`.
4. **V3-F-123** — Vidéo : tout échec d'export republie silencieusement le fichier ORIGINAL non modifié. ✅ **CORRIGÉ le 2026-08-20** (commit `0ee101b`, Phase B) — `BUILD_VALIDATED`.

Les 4 corrections sont `BUILD_VALIDATED` (CI verte, comportement code re-tracé et vérifié ligne à ligne contre l'Android source of truth) mais PAS `COMPLETE_PARITY_VALIDATED` — aucun test réel sur device/simulateur n'a été effectué (rappel : COMPILER N'EST PAS ÉQUIVALENT À FONCTIONNER).

**P0 reconfirmés (inchangés, déjà connus, bloqués backend)** : V3-F-140/V3-F-084 (StoreKit) — aucune correction client possible sans le endpoint backend `storekit/verify-purchase` (voir doc en tête de `CoinStoreManager.swift`, déjà écrite lors du travail P0-7 antérieur à cette session Phase B). Reste `FUNCTIONALLY_FAILED` pour la vraie parité tant que ce endpoint n'existe pas côté serveur — **BLOCKED BY BACKEND**.

**P1 majeurs nouveaux — TOUS CORRIGÉS le 2026-08-20 (Phase B), CI verte confirmée sur chacun, tous `BUILD_VALIDATED`** : V3-F-124 (`cd316df`), V3-F-125 (`5eb3358`/`e869825`), V3-F-103 (`c9dd8b1`), V3-F-107 (`c08ce4c`), V3-F-099 (`349b606` — mais `AttributedString.link`/`openURL` jamais exercé sur device, test réel prioritaire). Restants dans le backlog P1 : V3-F-102 (pagination hashtag absente au-delà de 30), V3-F-113 (pas de surveillance réseau pour la reconnexion socket), V3-F-114 (présence jamais émise), V3-F-128/129 (Réglages : bouton catégorie mal placé, liens légaux faux).

**2 découvertes notables où iOS est confirmé PLUS correct qu'Android** (à ne pas "corriger" — signaler à l'équipe QA pour éviter un faux rapport de régression) : V3-F-109 (recherche de conversation locale), V3-F-149 (restauration de session, déjà connu).

**Aucun de ces 8 points n'a été corrigé dans cette passe — Phase A s'arrête ici.**
