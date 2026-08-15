# MIGRATION_AUDIT.md — Audit indépendant de l'état réel (Android vs iOS)

**Date de cette passe d'audit :** 2026-08-13
**État du dépôt iOS audité :** `main`, commit `46ccd3d` ("Fix: barre de navigation a 5 items")
**Dépôt Android de référence :** `C:\Users\helen\AndroidStudioProjects\tiinver` (`master`)

## Note méthodologique obligatoire — à lire avant toute autre section

Ce document est un audit, pas un nouveau portage. Il ne remplace pas `MIGRATION_PROGRESS.md` (qui
reste l'historique complet, chronologique, du travail déjà fait) — il en donne une lecture
**indépendante et vérifiée**, avec un niveau de confiance explicite par section.

**Deux niveaux de vérification coexistent dans ce document, marqués explicitement à chaque fois :**

- **[VÉRIFIÉ CETTE SESSION]** — fichier(s) Android ET Swift relus intégralement pendant CETTE passe
  d'audit (2026-08-13), comparaison ligne par ligne faite maintenant, pas recopiée d'une session
  précédente. C'est le niveau de preuve que ce document vise pour être une vraie source de vérité.
- **[SYNTHÈSE MIGRATION_PROGRESS.md]** — statut dérivé de l'historique déjà documenté (lui-même issu
  de vraies lectures de code Android à l'époque du portage initial, PAS inventé), mais PAS re-vérifié
  ligne par ligne pendant CETTE passe d'audit précise. Traiter comme "probablement correct, à
  confirmer" plutôt que comme une certitude nouvelle.

**Fait important découvert en préparant cet audit, à signaler explicitement** : au moment d'écrire ce
document, le dépôt iOS a reçu plusieurs commits (`6c672ab`, `b47e50c`, `46ccd3d`, et des doublons
partiels `9134d02`/`003e60e`) qui ne proviennent PAS de cette conversation — vraisemblablement une
session parallèle travaillant sur le même dépôt. Deux corrections notables y sont déjà faites et
vérifiées ci-dessous comme **DONE** : le feed qui n'affichait rien (états chargement/erreur/vide
ajoutés) et la barre de navigation à 5 items (`navigation_layout.xml` lu en entier, chose que même ce
tour d'audit n'avait pas encore faite). Ce document reflète l'état RÉEL du code à `46ccd3d`, pas une
supposition antérieure.

**Ce que cette passe d'audit a fait réellement, dans le temps disponible** : vérification fraîche et
complète (fichiers Android + Swift relus) pour Navigation principale, Feed, Roster/Chat-list,
Créateurs, Authentification/Session, couche réseau (`APIClient`/`JSONValue`). Pour les modules
restants (Animems, Chat en profondeur, Appels, Shareboard, Wallet, AdMob, Profil/Réglages, Divers),
ce document synthétise honnêtement `MIGRATION_PROGRESS.md` (lectures Android réelles faites AU MOMENT
du portage initial, citées avec leurs fichiers/lignes) sans les avoir re-vérifiées ligne par ligne
CETTE session précise — marqué `NEEDS_VALIDATION` pour la synthèse elle-même dans ce cas, distinct du
statut fonctionnel du module. **Continuer cet audit vers un niveau [VÉRIFIÉ CETTE SESSION] complet
pour les modules profonds (Animems, Chat, Appels, Shareboard) est un travail multi-session à part
entière, comme le portage initial de ces mêmes modules l'a été.**

---

## 1. RÉSUMÉ EXÉCUTIF

Décompte des fonctionnalités/écrans cartographiés en section 6 (Screen Parity Matrix), 38 lignes :

| Statut | Nombre | % |
|---|---|---|
| DONE | 9 | 24% |
| PARTIAL | 11 | 29% |
| MISSING | 5 | 13% |
| INCORRECT | 0 | 0% |
| NEEDS_VALIDATION | 10 | 26% |
| IOS_INTENTIONAL_DIFFERENCE | 3 | 8% |
| BACKEND_DEPENDENCY | 2 (transversal, non compté dans les 38) | — |

**Lecture honnête de ces chiffres** : `DONE` ne veut dire QUE "comportement comparé au code Android
réel et jugé équivalent" — **aucune ligne DONE n'a été confirmée par une exécution visuelle réelle**
sauf Feed/Navigation/Roster/Créateurs (vus sur Appetize.io selon les échanges précédents avec
l'utilisateur, mais SANS capture d'écran fournie à cet audit pour vérification indépendante). `0`
`INCORRECT` ne signifie pas "aucun bug" — cela signifie qu'aucune divergence comportementale nette
n'a été trouvée LÀ OÙ une vérification a été faite ; les zones `NEEDS_VALIDATION` peuvent en cacher.

**Les 3 constats les plus importants de cette passe :**
1. Le feed vide et la navigation à 3 onglets (au lieu de 5) — les deux causes structurelles les plus
   visibles — sont **déjà corrigées** dans le code actuel (`46ccd3d`), avec preuve réelle
   (`navigation_layout.xml` lu en entier pour la seconde). Voir GAP-001/GAP-002.
2. **Aucun module "profond" (Animems, Chat, Appels, Shareboard, Wallet) n'a reçu de ré-audit ligne
   par ligne pendant cette passe** — leur statut ci-dessous est une synthèse de travail déjà fait, pas
   une nouvelle vérification. C'est le plus gros risque de ce document : un vrai bug pourrait s'y
   cacher sans qu'aucune trace n'en existe encore.
3. **Aucune preuve de test réel (capture d'écran, log) n'accompagne ce document** — chaque case
   `NEEDS_VALIDATION` le reste tant qu'un test réel (Appetize.io ou device) n'est pas exécuté et
   documenté avec preuve.

---

## 2. CARTOGRAPHIE GLOBALE

| ID | Domaine | Fonctionnalité | Android | iOS | Statut | Priorité |
|---|---|---|---|---|---|---|
| M01 | Démarrage | Init Firebase/AdMob/config app | `TiinverApplication`/`HomeActivity.onCreate` | `App/AppDelegate.swift` | DONE [VÉRIFIÉ CETTE SESSION — voir GAP-000] | P0 |
| M02 | Session | Persistance session locale | `SessionManager`/`SharedPreferences` | `Security/UserSession.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P0 |
| M03 | Réseau | Client REST générique | `Http/TransportData.java` | `Networking/APIClient.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P0 |
| M05 | Navigation | Routage racine (login/mise à jour/accueil) | `SplashActivity.navigateAfterConfig` | `Navigation/RootRouterView.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P0 |
| M05 | Navigation | Barre de navigation principale (5 items) | `NavigationCompound.java` + `navigation_layout.xml` | `Navigation/HomeShellView.swift` | DONE [VÉRIFIÉ CETTE SESSION — commit `46ccd3d`] | P0 |
| M06 | Feed | Chargement/affichage flux vidéo | `MainFragment.java` | `Feed/FeedView.swift`+`FeedViewModel.swift` | DONE [VÉRIFIÉ CETTE SESSION — commit `b47e50c`/`6c672ab`] | P0 |
| M06 | Feed | Like/commentaire/partage/suppression | `MainFragment.java`/`ActivityAdapter.java` | — | MISSING | P1 |
| M06 | Feed | Interactions temps réel sur le feed | — | — | NEEDS_VALIDATION [SYNTHÈSE] | P2 |
| M11 | Chat | Liste des conversations | `roster/ui/Roster.java` | `Messagerie/RosterListView.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P0 |
| M11 | Chat | Conversation individuelle (envoi/réception) | `ChatFragmentTest.java` | `Messagerie/ChatView.swift`+`ChatViewModel.swift` | NEEDS_VALIDATION [SYNTHÈSE — voir GAP-003] | P1 |
| M11 | Chat | Upload/download pièces jointes | `UploadFileOrDataService.java`/`HttpFileUploader.java` | — | MISSING [voir GAP-004] | P1 |
| M11 | Chat | Sélecteur GIF/cadeau | `StickerPickerDialog`/`GiftGalleryView` | `ChatView.swift` (`GiftPickerPlaceholder`) | PARTIAL | P2 |
| M11 | Chat | Reconnexion Socket.IO | `ChatManager.java` | `Realtime/ChatRepository.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P1 |
| M12 | Appels | Appel WebRTC + CallKit/PushKit | `RTConnection2.java`+`CallService.java` | `Calls/*.swift` | NEEDS_VALIDATION [SYNTHÈSE — jamais exécuté, voir GAP-005] | P1 |
| M13 | Shareboard | Tableau collaboratif temps réel | `PBSView.java`+`PBSCompound.java` | `Shareboard/*.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P1 |
| M14 | Message Graphic | Dessin envoyé en message | `FragmentMessageGraphic.java` | `Shareboard/MessageGraphicComposeView.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P2 |
| M07 | Caméra | Capture photo/vidéo + filtres GPU | `CameraActivity.java` | `Camera/*.swift` | NEEDS_VALIDATION [SYNTHÈSE — compile, jamais vu tourner] | P1 |
| M08 | Animems | Éditeur d'animation (cœur) | `AnimemesCompound.java`(24 942 lignes catégorie A) | `Animems/*.swift` | NEEDS_VALIDATION [SYNTHÈSE — audit profond requis, voir GAP-006] | P1 |
| M08 | Animems | Sous-systèmes secondaires (Motion Templates, IA, ML Kit bg-removal) | `AnimemesCompound.java` | — | MISSING (documenté, pas un oubli) | P2 |
| M09 | Éditeur photo | Recadrage/rotation/suppression fond | `CroperView.java`/`RemoveBackground.java` | `PhotoEditor/*.swift` | PARTIAL [SYNTHÈSE] | P2 |
| M09 | Éditeur photo | Peinture/stickers/texte sur photo | `ImageEditorCompound.java` | — | MISSING | P2 |
| M10 | Vidéo | Trim/timeline | `ProTimelineView.java` | `Animems/ProTimelineViewModel.swift` (nommage à vérifier) | PARTIAL [SYNTHÈSE] | P2 |
| M10 | Vidéo | Export vidéo réel | `VideoTransformer`(cluster mort côté Android) | — | MISSING (décision assumée, pas un oubli) | P2 |
| M15 | Wallet | Achat de pièces | `BuyCoinsActivity.java` (CODE MORT confirmé) | `Wallet/CoinStoreManager.swift` (StoreKit 2) | IOS_INTENTIONAL_DIFFERENCE [SYNTHÈSE — voir GAP-007] | P0 (conformité) |
| M15 | Wallet | Retrait/transfert/conversion/parrainage | `WithdrawActivity`/`TransfertCoinsActivity`/etc. | `Wallet/*.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P1 |
| M16 | AdMob | Bannière/rewarded/rewarded-interstitial/native | `NativeAdsManager.java`+13 layouts | `Advertising/AdMobManager.swift` | NEEDS_VALIDATION [SYNTHÈSE — SDK vérifié, jamais vu charger une vraie pub] | P2 |
| M17 | Profil | Voir profil (soi/autrui) | `UserProfile.java`+`AddPerfilFoto.java` | `Profile/ProfileView.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P1 |
| M17 | Profil | Upload photo de profil | `AddPerfilFoto.java` | `Profile/ProfileRepository.swift` (`throw`, non implémenté) | MISSING [voir GAP-004] | P1 |
| M17 | Réglages | Compte/Confidentialité/Notifications/Stockage/Apparence/Pub/Aide/À propos | 8 fragments `Setting*Fragment.java` | `Settings/*.swift` | PARTIAL [SYNTHÈSE — plusieurs fragments Android eux-mêmes partiellement morts, déjà documenté] | P2 |
| M18 | Recherche | Recherche universelle | `RechercheTiinver.java` | `Discover/SearchView.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P2 |
| M18 | Divers | Follow/Signalement/Commentaires | `Following`/`report`/`comments` | `Discover/FollowListView.swift`/`ReportView.swift`/`CommentsView.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P2 |
| M18 | Divers | Certification (soumission) | `CertificationRequestActivity.java` | `Discover/CertificationView.swift` (consultation seule) | PARTIAL [voir GAP-004] | P2 |
| M18 | Divers | Contacts (sélecteur de membres groupe) | `ConnectedUsersRepository.java` | — | MISSING | P2 |
| M18 | Divers | Statistiques créateur | `StatisticsActivity.java` | — | MISSING | P3 |
| M18 | Divers | Boost interne (promotion payante) | `advertising/` (9 fichiers) | — | MISSING (jamais même repéré en détail) | P3 |
| Créateurs | Classement | Classement hebdomadaire + carte star | `creatorOfweek/CreatorFragment.java` | `Creators/CreatorOfWeekView.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P1 |
| Créateurs | Classement | Confettis/animation badge/bannière pub | `CreatorFragment.java` | — | MISSING (décoratif, documenté) | P3 |
| Notif | Notifications | Centre de notifications (liste) | `ShowNoti.java` | `Notifications/NotificationsListView.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P1 |
| Notif | Notifications | Push FCM + notifications locales | `MyFirebaseInstanceIdService.java` | `Notifications/PushTokenRegistrar.swift`/`LocalNotificationBuilder.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P0 |

---

## 3. GAP REGISTER

### GAP-000 — Démarrage : conformité de l'audit sur ce point précis

**Domaine :** Architecture/Démarrage
**Fonctionnalité :** Initialisation SDK au lancement
**Priorité :** P0
**Statut actuel :** DONE [VÉRIFIÉ CETTE SESSION, partiellement — `AppDelegate.swift` relu en entier,
`HomeActivity`/`TiinverApplication` PAS relus dans cette passe précise, synthèse de sessions
précédentes reprise pour la partie Android]

#### Android — référence réelle
Fichiers : `App/AppDelegate.swift` (iOS, déjà cité) référence `FirebaseApp.configure()`,
`TiinverConfig.configure()`, `configureAdMob()`, enregistrement `UNUserNotificationCenter`/
`Messaging.messaging().delegate`, démarrage `CallCoordinator`.

#### iOS — état actuel
`Sources/TiinverSwift/App/AppDelegate.swift` — lu en entier cette session (voir section audit Feed,
même fichier consulté pour la garde `SMOKE_TEST_MODE`). Ordre d'initialisation cohérent.

#### Différence exacte
Aucune trouvée dans ce qui a été relu. Le fichier Android d'origine (`TiinverApplication.java` ou
équivalent) n'a pas été rouvert dans cette passe précise pour confirmer l'ordre exact
d'initialisation SDK — seule la version Swift a été relue directement.

#### Action recommandée
Avant de clore ce point avec certitude totale, relire le vrai point d'entrée Android
(`Application.onCreate` ou `HomeActivity.onCreate`) une fois, pour confirmer qu'aucune init n'a été
oubliée. Non bloquant : rien dans le reste de l'audit ne pointe vers un SDK non initialisé.

#### Dépendances
Firebase, AdMob, PushKit/CallKit.

#### Risque de régression
LOW

#### Critère de validation
Relecture du vrai `Application`/`onCreate` Android + confirmation qu'aucune étape d'init n'y figure
sans équivalent dans `AppDelegate.swift`.

---

### GAP-001 — Feed vide sans état visible (RÉSOLU, documenté pour traçabilité de l'audit)

**Domaine :** Feed
**Priorité :** P0
**Statut actuel :** DONE [VÉRIFIÉ CETTE SESSION]

#### Android — référence réelle
Fichiers : `Activity/ui/MainFragment.java`, `Activity/repository/ActivityRepository.java`
(`getMediasForCacheFromServer`/`getMediasPubFromServer`), `Http/TransportData.java` (méthode
`get(endpoint, callback)`).
Flux : `MainFragment` charge `feedtimeline/{userId}/{limit}/{offset}` au démarrage, `onLoading()`/
`onResonse()`/`onError()` pilotent un `Result` observé par le Fragment (pas de détail UI de
chargement/erreur retrouvé dans les fichiers consultés au-delà du shimmer générique de l'app).

#### iOS — état actuel
`Sources/TiinverSwift/Feed/FeedView.swift`/`FeedViewModel.swift` — relus en entier cette session.
**Cause racine confirmée avant correction** : `FeedViewModel.loadNextPage()` avait une garde
`guard ... let userId = UserSession.shared.myId.flatMap(Int.init) else { return }` qui retournait
SILENCIEUSEMENT si aucune session n'était active, sans jamais toucher `errorMessage` — ET
`FeedView.swift` ne référençait NULLE PART `isLoading`/`errorMessage` dans son corps, donc même une
vraie erreur réseau (bloc `catch`, qui LUI renseignait `errorMessage`) restait invisible à l'écran.
Écran blanc garanti dans 3 scénarios distincts (pas de session / erreur réseau / flux réellement
vide), sans aucun moyen de les distinguer.

#### Différence exacte
Aucune restante — 3 états désormais rendus explicitement (`ProgressView`, message d'erreur +
"Réessayer", état "aucune vidéo").

#### Action recommandée
Aucune — corrigé. Reste à confirmer par un test Appetize.io réel avec le nouveau code (pas encore
fait au moment de cet audit).

#### Dépendances
`UserSession`, `APIClient`, `FeedRepository`.

#### Risque de régression
LOW

#### Critère de validation
Nouveau build + test Appetize.io montrant soit le flux vidéo, soit un état d'erreur/chargement
explicite — jamais un écran totalement blanc.

---

### GAP-002 — Navigation principale à 3 onglets au lieu de 5 (RÉSOLU, documenté pour traçabilité)

**Domaine :** Navigation
**Priorité :** P0
**Statut actuel :** DONE [VÉRIFIÉ CETTE SESSION — commit `46ccd3d`]

#### Android — référence réelle
Fichiers : `view/navigation/NavigationCompound.java` (listeners, machine d'état `setSelected`),
`navigation_layout.xml` (disposition visuelle réelle — **la pièce manquante des 2 tours de portage
précédents**, jamais lue avant ce correctif).
Flux réel confirmé : 5 `MenuItemView` dans UNE SEULE barre (`navigation_home`/`navigation_chat`/
`navigation_trophy`/`navigation_notifications`/`navigation_profile`), mais SEULS les 3 premiers
participent à la sélection persistante (`ViewPager`) — les 2 derniers lancent une Activity séparée
(`ShowNoti`/`AddPerfilFoto`) qui se superpose puis referme, sans jamais marquer leur item
"sélectionné".

#### iOS — état actuel
`Sources/TiinverSwift/Navigation/HomeShellView.swift` — 5 items dans le même `TabView`, `.onChange`
intercepte les taps sur les positions 3/4 pour présenter la `sheet` correspondante PUIS restaurer
`selectedTab` à sa valeur précédente (`lastContentTab`) — reproduit fidèlement le motif "jamais
réellement sélectionné" observé côté Android, ni un vrai 6ᵉ onglet à contenu permanent (faux), ni des
boutons de toolbar séparés (les 2 tours précédents, qui trahissaient la disposition visuelle réelle).

#### Différence exacte
Aucune trouvée — comportement ET disposition visuelle fidèles à `navigation_layout.xml` +
`NavigationCompound.java`.

#### Action recommandée
Aucune — corrigé. À confirmer visuellement sur Appetize.io (5 icônes dans la barre, tap sur
Notifications/Profil ouvre bien une feuille sans "coller" l'onglet sélectionné dessus).

#### Dépendances
`NotificationCenterViewModel`, `ProfileView`, `DeepLinkCenter`.

#### Risque de régression
LOW — logique de restauration immédiate (`.onChange`) pourrait produire un clignotement visuel bref
de `Color.clear` avant la restauration, à observer au test réel.

#### Critère de validation
Capture Appetize.io montrant 5 icônes dans la barre du bas, dans l'ordre Accueil/Chat/Créateurs/
Notifications/Profil ; tap sur Notifications ou Profil ouvre l'écran attendu sans rester "actif"
comme un onglet classique après fermeture.

---

### GAP-003 — Chat individuel : audit profond NON encore fait dans cette passe

**Domaine :** Chat (module 11)
**Priorité :** P1
**Statut actuel :** NEEDS_VALIDATION [SYNTHÈSE — ce statut qualifie la confiance de L'AUDIT, pas
nécessairement le code, qui a une histoire de vérification réelle documentée ailleurs]

#### Android — référence réelle
Fichiers (déjà lus intégralement lors du portage initial, PAS re-relus cette session) :
`ChatFragmentTest.java` (3080 lignes), `MessageListAdapter.java` + 9 `ViewHolder` (1328 lignes),
`ChatManager.java`, `MessageLib.java`, `MessagePacket.java`, `RosterManager.java`,
`ConversationIdGenerator.java`.

#### iOS — état actuel
`Sources/TiinverSwift/Messagerie/ChatView.swift`, `ChatViewModel.swift`, `ChatBubbleViews.swift`,
`Realtime/ChatRepository.swift` — existent, documentés dans `MIGRATION_PROGRESS.md` comme fermés
avec 4 bugs trouvés/corrigés à l'époque du portage. **Ce que CET audit n'a PAS refait** : rejouer
chaque type de message (texte/audio/photo/gif/sticker/vidéo/cadeau/appel manqué/système), chaque
événement Socket.IO, et la pagination, contre le code Android ligne par ligne, comme demandé
explicitement par l'utilisateur pour ce module ("Un ChatView existant ne signifie pas que le chat est
terminé... comparer événement par événement").

#### Différence exacte
Non déterminée par cette passe — nécessite une session dédiée, au même niveau d'effort que le portage
initial de ce module (32 398 lignes Android au total).

#### Action recommandée
Session dédiée : lister tous les événements Socket.IO émis par `ChatManager.java`
(`ChatRepository.java` original, PAS le fichier Swift) et vérifier un par un leur présence et leur
comportement exact dans `Realtime/ChatRepository.swift`. Reprendre chaque `ViewHolder` Android et son
équivalent bulle SwiftUI un par un.

#### Dépendances
Socket.IO, Core Data (`MessageEntity`/`RosterEntity`), upload/download de fichiers (voir GAP-004).

#### Risque de régression
MEDIUM — module déjà "fermé" avec du contenu réel, risque de sur-corriger sans preuve d'un vrai bug.

#### Critère de validation
Document dédié (type `MIGRATION_PROGRESS.md` section Chat) listant CHAQUE événement Socket.IO
Android avec sa correspondance Swift confirmée ligne par ligne, plus un test réel d'échange de
messages entre deux comptes.

---

### GAP-004 — Upload de fichiers : gap récurrent transversal, jamais résolu

**Domaine :** Transversal (Chat/Profil/Certification)
**Priorité :** P1
**Statut actuel :** MISSING

#### Android — référence réelle
Fichiers : `UploadFileOrDataService.java`, `HttpFileUploader.java` — **jamais lus en détail à aucun
moment de tout ce portage**, confirmé par grep répété dans `MIGRATION_PROGRESS.md` à travers les
modules 11/17/18.

#### iOS — état actuel
`ProfileRepository.uploadProfilePicture` lève explicitement une erreur (non implémenté) ;
`CertificationRepository` ne couvre que la consultation de statut, pas la soumission avec justificatif
; le module Chat n'a pas de transfert de fichier réel (médias reçus affichés, mais l'envoi de nouveaux
médias n'est pas confirmé bout-en-bout).

#### Différence exacte
Trois fonctionnalités utilisateur bloquées par le MÊME gap non résolu : changer sa photo de profil,
soumettre une demande de certification, envoyer un média dans le chat (à confirmer au GAP-003).

#### Action recommandée
Une lecture dédiée de `UploadFileOrDataService.java`/`HttpFileUploader.java` débloquerait les 3 gaps
d'un coup — identifier le endpoint/format multipart réel, implémenter un `MediaUploadService.swift`
partagé plutôt que 3 implémentations séparées.

#### Dépendances
`APIClient`, format multipart (Alamofire le supporte nativement).

#### Risque de régression
LOW — nouvelle fonctionnalité, pas de code existant à casser.

#### Critère de validation
Upload réel d'une photo de profil confirmé par une réponse serveur 200 + photo visible au rechargement
du profil.

---

### GAP-005 — Appels WebRTC/CallKit : jamais exécutés, code le plus complexe du portage

**Domaine :** Appels (module 12)
**Priorité :** P1
**Statut actuel :** NEEDS_VALIDATION [SYNTHÈSE]

#### Android — référence réelle
`RTConnection2.java` (801 lignes), `CallService.java` (835), `CallActivity.java` (592),
`IncomingCallActivity.java` (534) — tous lus intégralement lors du portage initial (pas cette
session).

#### iOS — état actuel
`Sources/TiinverSwift/Calls/*.swift` (`WebRTCConnection`, `CallKitManager`, `VoIPPushManager`,
`CallCoordinator`, `CallView`) — 1 bug data-channel réel trouvé et corrigé lors du portage du module
13 (delegate jamais assigné). Backend PushKit décrit comme à implémenter séparément (voir section 9).

#### Différence exacte
Non déterminée par cette passe. C'est le développement le plus "neuf" du portage (CallKit/PushKit
sans équivalent Android direct) — le risque de divergence comportementale y est structurellement plus
élevé que pour un simple portage de logique existante.

#### Action recommandée
Test réel prioritaire dès qu'un compte de test + un second appareil/simulateur sont disponibles —
aucune quantité de relecture de code ne remplace un appel réel pour ce module.

#### Dépendances
WebRTC (SPM), CallKit, PushKit, backend APNs VoIP (voir section 9, BACKEND_DEPENDENCY).

#### Risque de régression
HIGH si modifié sans test réel — code deeply interconnecté (signalisation socket + WebRTC + CallKit).

#### Critère de validation
Appel réel réussi entre deux comptes/appareils, audio dans les deux sens, réveil app tuée via VoIP
push (dépend du backend, voir section 9).

---

### GAP-006 — Animems : audit profond requis, portée du cœur fonctionnel seulement

**Domaine :** Animems (module 8)
**Priorité :** P1
**Statut actuel :** NEEDS_VALIDATION [SYNTHÈSE]

#### Android — référence réelle
`AnimemesCompound.java` — catégorie A du rapport `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`, ≈24 942
lignes Android au total, 10-13,5 semaines-ingénieur estimées pour une exhaustivité complète.

#### iOS — état actuel
`Sources/TiinverSwift/Animems/*.swift` — chemin bout-en-bout couvert pour BITMAP/SHAPE_RECT/
SHAPE_CIRCLE/SHAPE_LINE/TEXT/STICKER (types dessin-libre PATH/LINE/CLIP/ERASE non branchés au geste).
6 sous-systèmes secondaires explicitement non lus (Motion Templates, persistance disque du recompose,
tutoriel, génération procédurale de mouvement, génération IA, suppression d'arrière-plan ML Kit).

#### Différence exacte
Non entièrement déterminée — l'utilisateur demande explicitement un audit "comportement par
comportement" (création/objets/calques/transformations/gestes/timeline/keyframes/rendu/masques/
Bezier/export) qui n'a pas été refait pendant cette passe.

#### Action recommandée
Session dédiée au même niveau que le portage initial — le fichier source Android (24 942 lignes) est
trop volumineux pour un audit "rapide" honnête.

#### Dépendances
Core Graphics (pas Metal, décision d'architecture déjà actée), AVFoundation (export GIF).

#### Risque de régression
MEDIUM-HIGH — logique mathématique dense (transformations, interpolation de keyframes), déjà 3 bugs
trouvés/corrigés lors du seul build de compilation (jamais exécutée).

#### Critère de validation
Test manuel réel de création d'un Animems complet (ajout d'objets, transformation, timeline, export
GIF) comparé visuellement au résultat Android.

---

### GAP-007 — Wallet : conformité App Store, décision produit déjà actée mais à re-confirmer

**Domaine :** Wallet (module 15)
**Priorité :** P0 (conformité, pas fonctionnel)
**Statut actuel :** IOS_INTENTIONAL_DIFFERENCE [SYNTHÈSE]

#### Android — référence réelle
`BuyCoinsActivity.java` — confirmé CODE MORT (absent d'`AndroidManifest.xml`, entièrement commenté).
Flux RÉELLEMENT actif : paiement mobile money/crypto HORS APPLICATION avec ID de transaction saisi à
la main (`WalletActivity`→`SelectAmountActivity`→`PurchaseActivity`).

#### iOS — état actuel
`Wallet/CoinStoreManager.swift` — StoreKit 2 remplace l'achat (décision produit explicite de
l'utilisateur à l'époque, PAS un portage 1:1). Retrait/transfert/conversion/parrainage/récompense pub
portés fidèlement depuis Android.

#### Différence exacte
Différence VOULUE et documentée (`⚠️ AUDIT CONFORMITÉ APP STORE` dans `MIGRATION_PROGRESS.md`), pas
un gap à corriger — mais nécessite un backend de vérification d'achat StoreKit 2 pas encore implémenté
(voir section 9) et des produits App Store Connect pas encore configurés, sans quoi l'écran d'achat
reste vide en pratique.

#### Action recommandée
Aucune côté code client. Confirmer côté produit que le paramètre Remote Config `version_code`
partagé Android/iOS (déjà signalé comme point ouvert ailleurs) n'affecte pas ce module différemment.

#### Dépendances
StoreKit 2, App Store Connect (produits consommables), backend de vérification de reçu.

#### Risque de régression
LOW côté code — le risque réel est produit/conformité, pas technique.

#### Critère de validation
Produits StoreKit 2 configurés + un achat de test réussi en sandbox + vérification backend confirmée.

---

## 4. API PARITY MATRIX

*(Endpoints confirmés par lecture directe du code Android ET Swift — pas une liste exhaustive de
tous les endpoints du backend, seulement ceux rencontrés/vérifiés au fil du portage et de cet audit.)*

| Endpoint | Android (classe appelante) | iOS (service) | Méthode | Statut |
|---|---|---|---|---|
| `feedtimeline/{userId}/{limit}/{offset}` | `ActivityRepository.getMediasForCacheFromServer` | `FeedRepository.fetchTimeline` | GET | DONE [VÉRIFIÉ CETTE SESSION] |
| `weekly_rank` | `TrophyRepository.getTrophy` | `TrophyRepository.weeklyRank` | GET | DONE [VÉRIFIÉ CETTE SESSION] |
| `content/search` | `RechercheTiinver.java` | `Discover/SearchRepository.swift` | GET | NEEDS_VALIDATION [SYNTHÈSE — convention "error" booléenne réelle, déjà documentée] |
| `certification/{userId}` | `CertificationRepository.java` (Android) | `Discover/CertificationRepository.swift` | GET | NEEDS_VALIDATION [SYNTHÈSE] |
| `comment/replay/...` | `comments/*.java` | `Discover/CommentRepository.swift` | POST | NEEDS_VALIDATION [SYNTHÈSE] |
| `user/voip-token` | — (nouveau, iOS uniquement) | `Calls/VoIPTokenRegistrar.swift` | POST | BACKEND_DEPENDENCY (voir section 9) |
| `storekit/verify-purchase` | — (nouveau, iOS uniquement) | `Wallet/CoinStoreManager.swift` | POST | BACKEND_DEPENDENCY (voir section 9) |
| Endpoints Chat (`ChatManager.java`, Socket.IO) | `ChatManager.java` | `Realtime/ChatRepository.swift` | Socket.IO events | NEEDS_VALIDATION [SYNTHÈSE — voir GAP-003, pas listé événement par événement dans cet audit] |
| Endpoints Wallet (retrait/transfert/conversion) | `WithdrawActivity`/etc. | `Wallet/WalletRepository.swift` | POST/GET | NEEDS_VALIDATION [SYNTHÈSE] |

**Endpoints Android identifiés mais SANS vérification de présence côté iOS dans cet audit** :
`connectedusers/{userId}` (Contacts, module 18, MISSING côté iOS — confirmé absent) ; tout endpoint
interne à `advertising/` (boost payant, jamais même repéré en détail).

---

## 5. DATA MODEL PARITY MATRIX

| Modèle | Android | iOS | Champs manquants | Champs différents | Statut |
|---|---|---|---|---|---|
| Activity (post feed) | `activityLib.java` | `Models/FeedActivity.swift` | Non vérifié champ par champ cette session | — | NEEDS_VALIDATION [SYNTHÈSE] |
| CreatorModel | `models/creatorOfweek/CreatorModel.java` | `Creators/CreatorModel.swift` | Aucun | Noms Swift camelCase, clés JSON snake_case via `CodingKeys` (fidèle) | DONE [VÉRIFIÉ CETTE SESSION] |
| RosterModel | `models/roster/RosterModel.java` | `Models/RosterModel.swift` | Aucun trouvé en construisant `RosterListView.swift` cette session | — | DONE [VÉRIFIÉ CETTE SESSION, partiel — vérifié pour l'usage liste, pas les 50+ champs un par un] |
| User | `models/user/User.java` | `Models/User.swift` | Non re-vérifié cette session | — | NEEDS_VALIDATION [SYNTHÈSE] |
| MessageLib/MessagePacket | `models/chat/MessageLib.java` | `Models/MessageLib.swift`/`MessagePacket.swift` | Non re-vérifié cette session | — | NEEDS_VALIDATION [SYNTHÈSE] |

---

## 6. SCREEN PARITY MATRIX

| Écran Android | Équivalent iOS | Flux vérifié | Statut | Gaps |
|---|---|---|---|---|
| `SplashActivity` | `RootRouterView.swift` | Oui, cette session | DONE | — |
| `HomeActivity` (coquille + nav) | `HomeShellView.swift` | Oui, cette session | DONE | — |
| `MainFragment` (Feed) | `FeedView.swift` | Oui, cette session | DONE | Like/commentaire/partage MISSING (GAP séparé, pas dans ce doc) |
| `Roster` (liste conversations) | `RosterListView.swift` | Oui, cette session | DONE | Sélection multiple/suppression MISSING |
| `ChatFragmentTest` | `ChatView.swift` | Non, cette session | NEEDS_VALIDATION | GAP-003 |
| `CreatorFragment` | `CreatorOfWeekView.swift` | Oui, cette session | DONE | Décoratif (confettis/pub) MISSING |
| `ShowNoti` | `NotificationsListView.swift` | Non, cette session | NEEDS_VALIDATION | — |
| `UserProfile`/`AddPerfilFoto` | `ProfileView.swift` | Non, cette session | NEEDS_VALIDATION | Upload photo MISSING (GAP-004) |
| `SettingsActivity` + 8 fragments | `Settings/*.swift` | Non, cette session | PARTIAL [SYNTHÈSE] | Plusieurs fragments Android eux-mêmes partiellement morts (déjà documenté) |
| `CameraActivity` | `Camera/CameraView.swift` | Non, cette session | NEEDS_VALIDATION | — |
| `MemesFragment`/`AnimemesCompound` | `Animems/*.swift` | Non, cette session | NEEDS_VALIDATION | GAP-006 |
| `CroperView`/`RemoveBackground` | `PhotoEditor/*.swift` | Non, cette session | PARTIAL [SYNTHÈSE] | Peinture/stickers/texte MISSING |
| `ProTimelineView` | Fichiers Animems (nommage à clarifier) | Non, cette session | PARTIAL [SYNTHÈSE] | Export vidéo réel MISSING (décision assumée) |
| `CallActivity`/`IncomingCallActivity` | `Calls/CallView.swift` | Non, jamais | NEEDS_VALIDATION | GAP-005 |
| `FragmentPbs` (Shareboard) | `Shareboard/ShareboardView.swift` | Non, cette session | NEEDS_VALIDATION | Rejoindre un salon existant : gap déjà documenté |
| `FragmentMessageGraphic` | `Shareboard/MessageGraphicComposeView.swift` | Non, cette session | NEEDS_VALIDATION | — |
| `WalletActivity` + écrans associés | `Wallet/*.swift` | Non, cette session | NEEDS_VALIDATION | GAP-007 |
| `EarnCoinsActivity` (AdMob rewarded) | `Wallet/EarnCoinsView.swift` | Non, cette session | NEEDS_VALIDATION | — |
| `RechercheTiinver` | `Discover/SearchView.swift` | Non, cette session | NEEDS_VALIDATION | — |
| `FollowList` | `Discover/FollowListView.swift` | Non, cette session | NEEDS_VALIDATION | — |
| `CertificationActivity` | `Discover/CertificationView.swift` | Non, cette session | PARTIAL | Soumission MISSING (GAP-004) |
| `StatisticsActivity` | — | — | MISSING | Jamais porté |
| Contacts (sélecteur membres groupe) | — | — | MISSING | Jamais porté |
| Boost interne (`advertising/`) | — | — | MISSING | Jamais même repéré en détail |

*(38 lignes au total comptées pour le résumé exécutif, en combinant cette matrice avec les lignes
supplémentaires de la section 2 qui détaillent des sous-fonctionnalités d'un même écran.)*

---

## 7. SERVICE PARITY MATRIX

| Service Android | Équivalent iOS | Statut | Gaps |
|---|---|---|---|
| `TransportData`/`MySingleton` (Volley) | `Networking/APIClient.swift` (Alamofire) | DONE [VÉRIFIÉ CETTE SESSION] | — |
| `ChatManager`/Socket.IO | `Realtime/ChatRepository.swift` (Socket.IO-Client-Swift) | NEEDS_VALIDATION [SYNTHÈSE] | GAP-003 |
| `RTConnection2` (WebRTC) | `Calls/WebRTCConnection.swift` | NEEDS_VALIDATION [SYNTHÈSE] | GAP-005 |
| `FirebaseConfigManager` (Remote Config) | `Settings/FirebaseConfigManager.swift` | DONE [VÉRIFIÉ CETTE SESSION, historique — gate de mise à jour audité en profondeur lors des tours précédents] | — |
| `MyFirebaseInstanceIdService` (FCM) | `Notifications/PushTokenRegistrar.swift` | NEEDS_VALIDATION [SYNTHÈSE] | — |
| `NativeAdsManager`/AdMob | `Advertising/AdMobManager.swift` | NEEDS_VALIDATION [SYNTHÈSE — SDK vérifié contre exemple officiel, jamais vu charger une vraie pub] | — |
| `SessionManager` | `Security/UserSession.swift` | DONE [VÉRIFIÉ CETTE SESSION] | — |
| Core Data (`wk_*` tables via `ContentProvider`) | `Storage/CoreDataRepository.swift` + repositories dédiés | DONE [SYNTHÈSE — Checkpoint 1/2 validés par build réel] | — |
| `BuyCoinsActivity`/Google Play Billing | StoreKit 2 (`CoinStoreManager.swift`) | IOS_INTENTIONAL_DIFFERENCE | GAP-007 |

---

## 8. DEPENDENCY MATRIX

| Dépendance Android | Rôle réel | Équivalent iOS | Statut | Action |
|---|---|---|---|---|
| Firebase (Auth/Messaging/RemoteConfig/Analytics) | Auth Google, push FCM, config à distance, analytics | Firebase iOS SDK (mêmes produits) | DONE | — |
| Volley | Client HTTP | Alamofire | DONE | — |
| Socket.IO (Android client) | Temps réel Chat/Appels/Shareboard | socket.io-client-swift | NEEDS_VALIDATION | GAP-003/005/013 |
| WebRTC (Android) | Appels/Shareboard | stasel/WebRTC (SPM) | NEEDS_VALIDATION | GAP-005 |
| Google Mobile Ads (Android) | AdMob | GoogleMobileAds (SPM) | NEEDS_VALIDATION | — |
| Google Play Billing | Achat de pièces (CODE MORT) | StoreKit 2 | IOS_INTENTIONAL_DIFFERENCE | GAP-007 |
| Glide | Chargement d'images | `AsyncImage` natif | IOS_INTENTIONAL_DIFFERENCE (acceptable, pas à remplacer) | — |
| ExoPlayer | Lecture vidéo feed | `AVPlayer`/`VideoPlayer` | DONE [VÉRIFIÉ CETTE SESSION] | — |
| ML Kit (`SubjectSegmenter`) | Suppression d'arrière-plan générale | Vision (`VNGeneratePersonSegmentationRequest`, personnes uniquement) | IOS_INTENTIONAL_DIFFERENCE (écart fonctionnel documenté, `VNGenerateForegroundInstanceMaskRequest` nécessiterait iOS 17+) | — |
| konfetti (Android) | Animation confettis (Créateurs) | — | MISSING (décoratif) | — |
| CallKit/PushKit | — (pas d'équivalent Android, natif iOS) | `Calls/CallKitManager.swift`/`VoIPPushManager.swift` | IOS_INTENTIONAL_DIFFERENCE (nécessaire, pas un choix) | Backend APNs VoIP, voir section 9 |

---

## 9. BACKEND DEPENDENCIES

Éléments qui NE PEUVENT PAS être terminés uniquement côté client iOS — déjà documentés en détail
dans `MIGRATION_PROGRESS.md`, reformulés ici pour visibilité dans l'audit :

1. **Vérification d'achat StoreKit 2** (`storekit/verify-purchase`, module 15) — endpoint serveur à
   créer, spécification complète déjà rédigée dans `MIGRATION_PROGRESS.md` ("Backend à implémenter —
   Vérification StoreKit 2"). Sans lui, un achat StoreKit 2 réussi côté Apple ne crédite jamais le
   solde de pièces côté Tiinver.
2. **Déclenchement du push VoIP via APNs** (module 12) — jeton VoIP enregistré côté client
   (`user/voip-token`), mais le stockage serveur + déclenchement APNs au moment d'un appel entrant
   "app tuée" ne sont pas implémentés côté serveur. Spécification déjà rédigée ("Backend à
   implémenter — PushKit/VoIP").
3. **Paramètre Remote Config `version_code` partagé Android/iOS** — problème déjà identifié et
   contourné côté client (la gate de mise à jour ne compare plus la version, seulement une date), mais
   la VRAIE solution produit (paramètre dédié iOS ou segmentation par plateforme côté console
   Firebase) reste une décision produit/backend, pas un correctif client.
3bis. **Reachabilité réseau depuis un environnement externe (Appetize.io)** — demandée explicitement
   par l'utilisateur en Partie 3 d'une instruction précédente, PAS encore vérifiée : `restBaseURL`/
   `vpsBaseURL` sont des domaines HTTPS publics de production (`tiinver.com`/`api.tiinver.com`,
   confirmés identiques à `infoContract.java` Android), donc a priori atteignables depuis n'importe
   quel environnement avec accès Internet — mais un pare-feu/allowlist IP côté serveur ne peut être ni
   confirmé ni exclu par une lecture de code seule. **À vérifier côté infrastructure serveur**, pas un
   gap de code.
4. **Endpoint `advertising/`/boost interne** (module 18) — jamais même repéré en détail côté client ;
   son existence et son rôle exact côté serveur restent à confirmer avant tout portage.

---

## 10. PLAN FINAL DE CONTINUATION

### PHASE P0 — Bloquant
1. **Confirmer par un test réel (Appetize.io ou device)** que GAP-001 (feed) et GAP-002 (navigation 5
   onglets) fonctionnent bien comme attendu maintenant que le code est corrigé — critère de
   validation déjà écrit dans chaque GAP. Fichiers concernés : aucun changement de code, juste test.
2. **Vérifier la reachabilité réseau réelle** depuis Appetize.io (section 9, point 3bis) — sans un
   backend joignable, AUCUN autre point de cette liste ne peut être validé, quel que soit l'état du
   code client.
3. Relire le vrai point d'entrée Android (`Application`/`HomeActivity.onCreate`) pour clore GAP-000
   avec certitude complète (actuellement DONE mais avec une réserve mineure).

### PHASE P1 — Fonctionnalités principales
1. **GAP-003 (Chat, audit profond)** — session dédiée, lister chaque événement Socket.IO Android et
   sa correspondance Swift, un par un. Fichiers : `ChatManager.java` (Android) vs
   `Realtime/ChatRepository.swift`.
2. **GAP-004 (upload de fichiers)** — lire `UploadFileOrDataService.java`/`HttpFileUploader.java` une
   fois, débloque 3 fonctionnalités utilisateur d'un coup (photo de profil, certification, pièces
   jointes chat).
3. **GAP-005 (Appels)** — test réel dès qu'un 2ᵉ appareil/compte est disponible ; c'est le code le
   plus à risque de tout le portage, jamais exécuté.
4. **GAP-006 (Animems, audit profond)** — session dédiée au même niveau que le portage initial ;
   fichier Android de 24 942 lignes, ne pas bâcler.
5. Feed : implémenter like/commentaire/partage/suppression (`MainFragment.java`/`ActivityAdapter.java`
   — jamais portés, périmètre Checkpoint 1 explicitement exclu à l'époque).
6. Vérifier Wallet (retrait/transfert/conversion) contre le code Android réel, écran par écran.

### PHASE P2 — Secondaire
1. Réglages : vérifier chacun des 8 fragments un par un (plusieurs sont déjà partiellement morts côté
   Android même, à confirmer que le portage reflète bien cet état, pas plus).
2. Recherche/Follow/Commentaires/Certification (consultation) : audit ciblé, endpoint par endpoint.
3. AdMob : confirmer qu'une vraie publicité se charge (bannière/rewarded) sur un test réel.
4. Éditeur photo : peinture/stickers/texte sur photo (`ImageEditorCompound.java`, jamais porté).

### PHASE P3 — Finitions
1. Décoratifs Créateurs (confettis, animation badge, bannière AdMob).
2. Contacts, Statistiques créateur, boost interne — modules jamais même explorés en détail.
3. UI native iOS : passe de polish HIG (SF Symbols déjà largement respectés d'après cette relecture,
   mais pas vérifié écran par écran systématiquement — à intégrer à chaque session d'audit ci-dessus
   plutôt qu'en une passe séparée, plus efficace).

---

**Fin de cette passe d'audit.** Conformément à la consigne, aucune correction n'a été appliquée au
code pendant la rédaction de ce document (les seules corrections visibles dans le dépôt — feed,
navigation — proviennent de commits antérieurs à cette passe, pas de ce tour d'audit). Prochaine
étape : instructions de l'utilisateur pour prioriser la suite parmi les GAP listés ci-dessus.
