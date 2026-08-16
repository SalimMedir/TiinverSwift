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

**Mise à jour 2026-08-15 (2ᵉ passe, GAP-004 clos)** : le tableau ci-dessous n'a PAS été recompté
intégralement après cette passe (upload photo profil + certification + pièces jointes chat, tous
passés à DONE, plus GAP-000/GAP-008 identifiés) — le recompte exact des 38 lignes + section 2
nécessiterait de rouvrir chaque ligne, hors budget de cette session ciblée sur GAP-004. Au minimum
3 lignes sont connues DÉSORMAIS DONE alors que ce tableau les compte encore ailleurs (MISSING/
PARTIAL) : voir section 2 (M11/M17/M18) et section 6, déjà mises à jour individuellement. Traiter
les pourcentages ci-dessous comme approximatifs/datés du 2026-08-13, pas comme une vérité actuelle.

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
| M01 | Démarrage | Init Firebase/AdMob/config app | `App.java onCreate()` | `App/AppDelegate.swift` | DONE [VÉRIFIÉ CETTE SESSION — voir GAP-000, clos] | P0 |
| M01 | Démarrage | Sync watch-time (temps de visionnage) | `Utils/ViewTracker.java`+`ViewSyncWorker.java` | `Storage/ViewEventRepository.swift` (jamais appelé) | MISSING [VÉRIFIÉ CETTE SESSION — voir GAP-008] | P2 |
| M02 | Session | Persistance session locale | `SessionManager`/`SharedPreferences` | `Security/UserSession.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P0 |
| M03 | Réseau | Client REST générique | `Http/TransportData.java` | `Networking/APIClient.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P0 |
| M05 | Navigation | Routage racine (login/mise à jour/accueil) | `SplashActivity.navigateAfterConfig` | `Navigation/RootRouterView.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P0 |
| M05 | Navigation | Barre de navigation principale (5 items) | `NavigationCompound.java` + `navigation_layout.xml` | `Navigation/HomeShellView.swift` | DONE [VÉRIFIÉ CETTE SESSION — commit `46ccd3d`] | P0 |
| M06 | Feed | Chargement/affichage flux vidéo | `MainFragment.java` | `Feed/FeedView.swift`+`FeedViewModel.swift` | DONE [VÉRIFIÉ CETTE SESSION — commit `b47e50c`/`6c672ab`] | P0 |
| M06 | Feed | Like/commentaire/partage/suppression | `MainFragment.java`/`ActivityAdapter.java` | — | MISSING | P1 |
| M06 | Feed | Interactions temps réel sur le feed | — | — | NEEDS_VALIDATION [SYNTHÈSE] | P2 |
| M11 | Chat | Liste des conversations | `roster/ui/Roster.java` | `Messagerie/RosterListView.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P0 |
| M11 | Chat | Conversation individuelle (envoi/réception) | `ChatFragmentTest.java` | `Messagerie/ChatView.swift`+`ChatViewModel.swift` | NEEDS_VALIDATION [SYNTHÈSE — voir GAP-003] | P1 |
| M11 | Chat | Upload pièces jointes (BunnyCDN) | `UploadFileOrDataService.java` | `Messagerie/ChatMediaUploadService.swift` | DONE [VÉRIFIÉ CETTE SESSION — voir GAP-004, clos 2026-08-15] | P1 |
| M11 | Chat | Download pièces jointes reçues | `DownloadReceiver.java` | `ChatViewModel.requestDownload` (`TODO`, non implémenté) | MISSING — hors périmètre GAP-004 (upload seulement), gap distinct | P1 |
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
| M17 | Profil | Upload photo de profil | `AddPerfilFoto.java` | `Profile/ProfileRepository.swift`+`ProfileView.swift` (`PhotosPicker`) | DONE [VÉRIFIÉ CETTE SESSION — voir GAP-004, 2026-08-15] | P1 |
| M17 | Réglages | Compte/Confidentialité/Notifications/Stockage/Apparence/Pub/Aide/À propos | 8 fragments `Setting*Fragment.java` | `Settings/*.swift` | PARTIAL [SYNTHÈSE — plusieurs fragments Android eux-mêmes partiellement morts, déjà documenté] | P2 |
| M18 | Recherche | Recherche universelle | `RechercheTiinver.java` | `Discover/SearchView.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P2 |
| M18 | Divers | Follow/Signalement/Commentaires | `Following`/`report`/`comments` | `Discover/FollowListView.swift`/`ReportView.swift`/`CommentsView.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P2 |
| M18 | Divers | Certification (soumission) | `CertificationRequestActivity.java` | `Discover/CertificationView.swift`+`CertificationRepository.submit` | DONE [VÉRIFIÉ CETTE SESSION — voir GAP-004, clos 2026-08-15] | P2 |
| M18 | Divers | Contacts (sélecteur de membres groupe) | `ConnectedUsersRepository.java` | — | MISSING | P2 |
| M18 | Divers | Statistiques créateur | `StatisticsActivity.java` | — | MISSING | P3 |
| M18 | Divers | Boost interne (promotion payante) | `advertising/` (9 fichiers) | — | MISSING (jamais même repéré en détail) | P3 |
| Créateurs | Classement | Classement hebdomadaire + carte star | `creatorOfweek/CreatorFragment.java` | `Creators/CreatorOfWeekView.swift` | DONE [VÉRIFIÉ CETTE SESSION] | P1 |
| Créateurs | Classement | Confettis/animation badge/bannière pub | `CreatorFragment.java` | — | MISSING (décoratif, documenté) | P3 |
| Notif | Notifications | Centre de notifications (liste) | `ShowNoti.java` | `Notifications/NotificationsListView.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P1 |
| Notif | Notifications | Push FCM + notifications locales | `MyFirebaseInstanceIdService.java` | `Notifications/PushTokenRegistrar.swift`/`LocalNotificationBuilder.swift` | NEEDS_VALIDATION [SYNTHÈSE] | P0 |

---

## 3. GAP REGISTER

### GAP-000 — Démarrage : conformité de l'audit sur ce point précis (CLOS cette session, 2026-08-15)

**Domaine :** Architecture/Démarrage
**Fonctionnalité :** Initialisation SDK au lancement
**Priorité :** P0
**Statut actuel :** DONE [VÉRIFIÉ CETTE SESSION — `App.java` (le vrai `onCreate()` @Override, PAS
`onCreate2()` qui est du code mort jamais appelé, confirmé par grep) relu en entier ET comparé
ligne par ligne à `AppDelegate.swift`]

#### Android — référence réelle
`app/src/main/java/com/tiinver/App.java`, méthode `onCreate()` (l.264-332) : `TiinverConfig.init`,
création de 3 canaux de notification, `FirebaseApp.initializeApp`, `EmojiCompat`/`EmojiManager`
(police emoji Google de remplacement), `FirebaseConfigManager.fetchAndActivate` (+ mise à jour
synchrone immédiate des valeurs d'expiration AVANT le fetch réseau), `FacebookSdk.sdkInitialize` +
`AppEventsLogger.activateApp`, `MobileAds.initialize` (délai 3s), `initWebRct()` (WebRTC), et
`ViewTracker.startPeriodicSync` (`Utils/ViewTracker.java` — sync périodique WorkManager/15min des
événements de visionnage vers le serveur).

#### iOS — état actuel
`Sources/TiinverSwift/App/AppDelegate.swift` relu en entier. Correspondances confirmées :
`FirebaseApp.configure()`, `TiinverConfig.configure()`, `configureAdMob()`,
`UNUserNotificationCenter`/`Messaging.messaging().delegate`, `CallCoordinator.shared.start()`
(équivalent iOS-only de `initWebRct()`, nécessaire pour PushKit).

#### Différence exacte
1. **`EmojiCompat`/`EmojiManager`** — absent côté iOS. **IOS_INTENTIONAL_DIFFERENCE, pas un gap** :
   ce mécanisme Android remplace la police emoji système (souvent obsolète/incohérente selon le
   fabricant) par une police Google téléchargée ; iOS a un rendu emoji couleur natif et à jour dans
   toutes les polices système, ce contournement n'a pas de raison d'être porté.
2. **`FacebookSdk.sdkInitialize`/`AppEventsLogger.activateApp`** — **MISSING, nouveau constat de
   cette session**, absent de tout le projet iOS (aucune dépendance Facebook dans `project.yml`,
   aucun appel d'init). Vérifié que ce n'est PAS du Facebook Login (aucun `LoginManager`/
   `LoginButton`/`FacebookCallback`/`GraphRequest` trouvé dans tout `com.tiinver` par grep) — usage
   Android limité à l'activation de l'événement standard "app ouverte" (Meta App Events,
   analytics/attribution publicitaire uniquement). Aucun impact fonctionnel utilisateur ; impact
   potentiel sur le reporting d'attribution publicitaire côté Meta. Priorité P3, non bloquant.
3. **`ViewTracker.startPeriodicSync`** — **MISSING, constat le plus significatif de cette session**.
   Le stockage local existe bien côté iOS (`Storage/ViewEventRepository.swift`, `ViewEventEntity`
   Core Data, logique de cumul watchtime/scrollPosition/replayCount/exitPoint fidèle à
   `ViewTracker.record()`), MAIS **`ViewEventRepository` n'est appelé nulle part ailleurs dans tout
   le projet** (confirmé par grep sur l'ensemble de `Sources/` — seule sa propre définition et un
   commentaire dans `HomeShellView.swift` la mentionnent). Deux problèmes empilés, pas un seul :
   (a) rien n'enregistre localement le temps de visionnage depuis `FeedView`/le lecteur vidéo (le
   commentaire d'en-tête de `ViewEventRepository.swift` le confirme explicitement : "la partie
   écriture locale seulement" existe, mais rien ne l'appelle) ; (b) aucune synchronisation
   périodique vers le serveur n'existe (`BGTaskScheduler`, équivalent iOS de `WorkManager`, absent
   du projet — confirmé par grep). Déjà noté comme différé "au module 18" dans un commentaire de
   `HomeShellView.swift`, mais le module 18 a été fermé (2026-08-12) sans que ce point soit repris
   dans son résumé de clôture — probablement oublié plutôt que sciemment exclu. Impact produit
   potentiel : si le classement Créateurs/algorithme de recommandation dépend de ces données
   côté serveur (à confirmer côté backend), le feed iOS ne contribuerait actuellement AUCUNE donnée
   de comportement de visionnage, silencieusement.

#### Action recommandée
Point 1 : aucune, différence voulue. Point 2 : ajouter le SDK Facebook (`FacebookCore`/`FacebookLogin`
via SPM) + un appel d'activation équivalent dans `AppDelegate.swift`, P3, séparable du reste. Point 3 :
nécessite une session dédiée — (a) brancher `ViewEventRepository.record(...)` depuis le lecteur vidéo
du feed (au scroll/sortie de vidéo, à identifier précisément dans `FeedView.swift`/le player) ; (b)
implémenter un `BGTaskScheduler` périodique (~15 min, réseau requis) rejouant la logique de
`ViewSyncWorker.java` (non lu en détail dans cette session — à faire avant d'implémenter (b)). Ajouté
au registre de gaps comme GAP-008 ci-dessous pour suivi.

#### Dépendances
Firebase, AdMob, PushKit/CallKit, Core Data (`AnalyticsCoreDataStack`), `BGTaskScheduler` (à ajouter).

#### Risque de régression
LOW pour les 2 gaps trouvés (fonctionnalités actuellement inertes, rien à casser en les ajoutant).

#### Critère de validation
Point 2 : événement "app activée" visible dans Meta Events Manager après un lancement réel. Point 3 :
une ligne `ViewEventEntity` créée localement après visionnage d'une vidéo du feed, puis absente après
la fenêtre de sync suivante (confirmée reçue côté serveur).

---

### GAP-008 — Synchronisation du temps de visionnage (watch-time) jamais branchée côté iOS

**Domaine :** Feed / Analytics
**Priorité :** P2 (aucun impact visible utilisateur, impact potentiel sur classement/algorithme
côté serveur si celui-ci consomme ces données — à confirmer)
**Statut actuel :** MISSING [VÉRIFIÉ CETTE SESSION — voir détail complet dans GAP-000, point 3]

#### Action recommandée
Voir GAP-000. Lire `service/worker/ViewSyncWorker.java` (Android, jamais lu en détail) avant
d'implémenter la synchronisation périodique iOS.

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

### GAP-004 — Upload de fichiers : CLOS cette session (2026-08-15, 2ᵉ passe)

**Domaine :** Transversal (Chat/Profil/Certification)
**Priorité :** P1
**Statut actuel :** DONE [VÉRIFIÉ CETTE SESSION — les 3 usages (profil, certification, pièces
jointes chat) sont maintenant implémentés bout en bout côté code. Réserve unique : AUCUNE
compilation/exécution réelle possible depuis cet environnement (pas de macOS/Xcode ici), voir
section "Vérification statique effectuée cette session" plus bas.]

#### Android — référence réelle (méthode conservée de la 1ʳᵉ passe)
`HttpFileUploader.java`, `UploadFileOrDataService.java`, `ProfileRepository.java` (méthode
`uploadPhotoProfile`), `CertificationRepository.java` (méthode `requestOK`) — tous lus en entier.
Complété cette 2ᵉ passe par `ChatFragmentTest.java` (lignes 413-450 : `pickImageOrVideo`/`pickMedia`,
picker `ImageAndVideo` ; lignes 2417-2479 : `prepareFileMessage`, mapping exact `MessageLib` avant
upload) et `models/activity/MyMediaType.java` (4 constantes extension/MIME, lu en entier).

#### Correction majeure par rapport à l'hypothèse précédente
La session précédente supposait qu'**un seul** `MediaUploadService.swift` partagé débloquerait les 3
usages d'un coup. **C'est faux** — lecture complète confirmant **3 protocoles réellement différents**,
pas 3 appels du même service :

1. **Photo de profil** (`ProfileRepository.uploadPhotoProfile` → `HttpFileUploader` type=2) : POST
   multipart DIRECT vers le backend Tiinver, `{SERVER}user`, champs `id`/`column=profile_picture`/
   `format=json`/fichier `object_url` (nom fixe `wn_image.jpeg`). Réponse `{error, object_url}`,
   même convention que le reste de l'API (`JSONValue.isBackendSuccess`).
2. **Certification** (`CertificationRepository.requestOK`) : POST multipart DIRECT vers le backend
   Tiinver, `{SERVER}certification/request`, champs `userId`/`certificationLevel`/`format=json`/
   fichier `documentUrl`. **Même protocole que (1)** (backend Tiinver, multipart, convention `error`)
   — ces deux-là PEUVENT effectivement partager un seul point d'entrée générique.
3. **Pièces jointes chat** (`UploadFileOrDataService.java`) : **protocole entièrement différent**,
   PAS le backend Tiinver — PUT binaire direct vers **BunnyCDN storage**
   (`https://storage.bunnycdn.com/{STORAGE_ZONE}/tiinver/message/{type}/{filename}`, header
   `AccessKey` avec une clé statique codée en dur côté Android — `STORAGE_ZONE="tiinver-media"`,
   note sécurité : clé de stockage embarquée côté client, déjà le cas côté Android, pas une
   régression introduite par le portage). Vidéo = 2 PUT séparés (média + thumbnail). URL CDN
   publique résultante : `https://cdn.tiinver.com/{folder}/{filename}`. Après upload, mise à jour
   LOCALE uniquement (SQLite `ContentProvider` côté Android) — le backend Tiinver lui-même
   n'intervient pas dans cette partie, l'URL doit ensuite être transmise via Socket.IO pour que
   l'autre participant la reçoive (à vérifier dans `Realtime/ChatRepository.swift`, lié à GAP-003).
   Champs `bunnyApiKey`/`videoLibraryId` déclarés dans le fichier Android mais jamais utilisés
   (code mort confirmé, à ne PAS porter).

#### iOS — état actuel (les 3 usages fermés)
- **Photo de profil** — `APIClient.uploadMultipart(...)` (méthode générique, `Networking/
  APIClient.swift`) + `ProfileRepository.uploadProfilePicture` (POST réel vers `user`) +
  `ProfileViewModel.uploadProfilePicture` + `ProfileView` (avatar tapable via `PhotosPicker` natif
  quand `isCurrentUser`). Écart assumé : pas de recadrage avant envoi (Android : `CroperView`),
  l'avatar est de toute façon affiché en cercle recadré côté client.
- **Certification (soumission)** — `CertificationRepository.submit(userId:documentData:)` (même
  `uploadMultipart`, endpoint `certification/request`, champs `userId`/`certificationLevel="basic"`
  [seul palier réellement envoyé par Android, `btnSubmitCertification` — reproduit à l'identique,
  PAS une sélection de palier absente]/`format`/`documentUrl`) + `CertificationView` (section
  "Nouvelle demande" ajoutée : prix via `TiinverFirebaseConfigManager.certificationPrice`,
  `PhotosPicker`, statut rechargé après succès). `CertificationPlanFragment.tarification()`
  (re-fetch réseau redondant avec Remote Config) délibérément PAS porté, hors périmètre strict de
  ce GAP (transfert de fichier).
- **Pièces jointes chat** — nouveau fichier `Messagerie/ChatMediaUploadService.swift` (PUT direct
  BunnyCDN, `AccessKey` statique, PAS `APIClient`) + `MessageRepository.updateFileUploaded(...)`
  (nouvelle méthode Core Data) + `ChatViewModel.requestUpload` (point d'ancrage déjà documenté par
  la 1ʳᵉ passe, maintenant implémenté) + `ChatViewModel.attachMedia/attachImage/attachVideo` (calcul
  largeur/hauteur/durée + génération de miniature vidéo via `AVAssetImageGenerator`) +
  `ChatView` (bouton trombone → `GalleryPickerView`, réutilisé tel quel, module 7). **2 bugs
  "double slash" trouvés dans `UploadFileOrDataService.java` en le relisant précisément pour cette
  implémentation** (URL de PUT ET/OU URL CDN finale, incohérents entre la branche vidéo et la
  branche générique — voir commentaire de tête de `ChatMediaUploadService.swift`) — NON reproduits,
  corrigés uniformément (accidentels, pas un protocole voulu, contrairement à `MyMediaType.IMAGE`
  qui déclare `.webp`/`image/jpeg` de façon cohérente PARTOUT et EST donc reproduit tel quel).
  **Écart assumé** : miniature vidéo générée réellement côté iOS (`AVAssetImageGenerator`) —
  `saveThumbnailToCache` (Android, `prepareFileMessage` ligne 2425) est du code COMMENTÉ/mort, alors
  que `UploadFileOrDataService.uploadMediaAndThumbnail` utilise `thumbnailUri` SANS garde de
  nullité : sans génération réelle, ce chemin serait cassé même côté Android. **Emplacement précis
  du bouton d'attache non identifié** dans les 3080 lignes lues de `ChatFragmentTest.java` (pas dans
  ce fichier, probablement `chat_salon.xml` non fourni) — branché sur une icône trombone par
  cohérence avec les autres points d'entrée déjà non localisés précisément dans ce module (bouton
  d'appel, Shareboard, voir `ChatView.swift`).

#### Vérification statique effectuée cette session (AUCUN accès Xcode/build/device)
Relecture manuelle des fichiers modifiés/créés pour : cohérence des types (`String`/`Int`/`Int64`
Core Data), signatures d'appel (`APIClient.uploadMultipart`, `MultipartFormData.append`,
`Session.upload(multipartFormData:to:headers:)`, `URLSession.upload(for:from:)`, `AVAsset.load(_:)`
async), disponibilité API vs `deploymentTarget: 16.0` (`project.yml`) — **1 erreur trouvée et
corrigée avant de continuer** : `.onChange(of:) { oldValue, newValue in }` (forme iOS 17+) utilisée
par erreur dans `ProfileView.swift`, corrigée en `{ newValue in }` (seule forme disponible en 16.0,
confirmée par grep sur tout `Sources/` — 10+ usages existants, tous dans cette forme). **1 bug
trouvé et corrigé** : `FirebaseConfigManager.shared` (n'existe pas) au lieu de
`TiinverFirebaseConfigManager.shared` dans `CertificationView.swift`, corrigé après grep de
vérification. Aucune garantie de compilation réelle — la seule vérification qui fasse foi est un
build CI (`ios-build.yml`/`codemagic.yaml`) ou un accès Xcode direct, ni l'un ni l'autre disponibles
depuis cet environnement Windows.

#### Action recommandée
Aucune côté transfert de fichier — GAP-004 clos. Reste, HORS PÉRIMÈTRE de ce GAP mais découvert en
le fermant : confirmer comment un message chat avec pièce jointe atteint réellement l'autre
participant une fois uploadé (le `send(mlib)` explicite ajouté dans `requestUpload` émet bien via
`ChatRepository.sendPrivateMessage`/`sendGroupMessage`, MAIS ce chemin socket n'a pas été re-vérifié
événement par événement dans cette session — lié à GAP-003, qui reste une session à part entière).

#### Dépendances
`APIClient` (fait), Alamofire (déjà utilisé), `AVFoundation` (miniature vidéo, déjà lié au projet
pour d'autres modules), BunnyCDN (`URLSession` natif, pas de SDK).

#### Risque de régression
LOW — 3 fonctionnalités précédemment inertes/manquantes, rien d'existant cassé en les complétant.

#### Critère de validation
Build CI réel + test manuel : (1) upload réel d'une photo de profil, réponse 200 + photo visible au
rechargement ; (2) soumission de certification, statut passe à "pending" après envoi ; (3) envoi
d'une photo/vidéo en chat, bulle affiche la miniature locale puis bascule sur l'icône "prêt" une
fois l'upload terminé, ET l'autre participant reçoit bien le message (test à 2 comptes).

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
| `CertificationActivity` | `Discover/CertificationView.swift` | Oui, cette session (2026-08-15) | DONE | Soumission implémentée (GAP-004 clos) ; `tarification()` (re-fetch prix redondant) non porté, mineur |
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

---

## 11. PREMIER BUILD CI RÉEL POST-GAP-004 (2026-08-15) — BUILD NON VALIDÉ

**Contexte** : sur instruction explicite de l'utilisateur, déclenchement d'un vrai build CI
(`.github/workflows/ios-build.yml`, GitHub Actions) via l'API GitHub REST (`workflow_dispatch`),
pour vérifier que tout le code écrit depuis le 2026-08-13 (y compris GAP-004, cette session) compile
réellement. **AUCUN commit/push effectué à ce stade** — l'utilisateur a explicitement choisi
l'option "ne rien pousser, juste diagnostiquer" quand la question s'est posée (le fix ci-dessous
nécessite un push pour être re-testé).

### Run #1 — RÉSULTAT RÉEL (pas une estimation)

- **Run ID** : `31905358058`
- **Commit testé** : `733da28fc414dc059474c9be4e973280ae8bb153` (dernier commit sur `main` au
  moment du déclenchement — **PAS** le code GAP-004 de cette session, resté non commité, voir
  avertissement ci-dessous)
- **Déclenché** : 2026-08-15 19:57:16 UTC, via API REST avec le token présent dans `git remote -v`
- **Runner** : `macos-14-arm64`, image `20260629.0180.1`, macOS `14.8.7`
- **Conclusion** : **FAILURE**, échec après seulement ~36 secondes (bien avant toute compilation
  Swift réelle)
- **Étape en échec** : `Install Metal Toolchain` (`xcodebuild -downloadComponent MetalToolchain`)
- **Erreur exacte** (log brut) : `xcodebuild: error: invalid option '-downloadComponent'`
- **Étapes JAMAIS ATTEINTES** (marquées `skipped`) : `Résoudre les dépendances Swift Package
  Manager`, `Build simulateur — vérification de compilation uniquement, sans signature` — **donc
  AUCUNE vérification de dépendances SPM ni de compilation Swift n'a eu lieu dans ce run**, contrai-
  rement à ce qu'on pourrait déduire d'un "build lancé".

### Analyse groupée par cause (méthode demandée par l'utilisateur)

1. **Erreurs de configuration CI/runner** — 1 trouvée : `-downloadComponent` n'existe pas sur la
   version d'Xcode sélectionnée par défaut sur ce runner. Cause réelle : le workflow ne sélectionne
   JAMAIS explicitement de version Xcode (`xcode-select`/`DEVELOPER_DIR`) alors que le runner
   `macos-14-arm64` héberge plusieurs Xcode installés côte à côte — le symlink par défaut pointait
   vers une version trop ancienne pour ce flag (introduit avec la séparation du toolchain Metal en
   composant téléchargeable, Xcode 16+).
2. **Erreurs de dépendances SPM** — NON ÉVALUABLE, étape jamais atteinte.
3. **Erreurs Swift** — NON ÉVALUABLE, étape jamais atteinte. **En particulier, aucun des fichiers
   Swift de GAP-004 (cette session) n'a été testé par ce run**, puisqu'ils ne sont même pas encore
   commités.
4. **Erreurs Firebase/GoogleMobileAds/signature/ressources** — NON ÉVALUABLES, étapes jamais
   atteintes.

### Correction appliquée (écrite, PAS testée — nécessite un push pour l'être)

`.github/workflows/ios-build.yml` — nouvelle étape avant `Install Metal Toolchain` : sélectionne
explicitement la version Xcode la plus récente disponible sur le runner
(`ls -d /Applications/Xcode_*.app | sort -V | tail -1` + `sudo xcode-select -s`), plutôt qu'un
numéro de version codé en dur (pour ne pas se recasser à la prochaine image de runner GitHub, mise à
jour régulièrement). Log ajouté (`xcodebuild -version`) pour documenter la version réellement
sélectionnée au prochain run.

### État réel au moment de l'écriture initiale de cette section — À NE PAS CONFONDRE AVEC UN SUCCÈS

**BUILD NON VALIDÉ** (à ce stade). Ni le code actuel de `main` (commit `733da28`), ni a fortiori le
code GAP-004 de cette session (non commité), n'ont été confirmés compilables par un build CI réel.
Le fix ci-dessus est une hypothèse raisonnable (cause d'erreur claire, correction directe) mais
**NON CONFIRMÉE** — seul un nouveau run CI après push pourrait le confirmer.

**Suite (même session, tours suivants) — voir section 12 ci-dessous pour l'état final.**

---

## 12. GAP-004 — VALIDATION CI RÉELLE (2026-08-15, tours suivants) + STRATÉGIE DOUBLE-CI

### Correctifs CI supplémentaires (2 itérations avant d'atteindre un run propre)

1. **`-downloadComponent` absent de TOUTES les versions Xcode du runner** (15.0 à 16.2 inclus,
   confirmé par la liste d'options réelle retournée par `xcodebuild` en erreur — le fix de
   sélection de version (ci-dessus) fonctionnait bien, Xcode 16.2 était correctement sélectionné,
   mais le flag lui-même n'existe simplement sur aucune version disponible ici). Rendu non
   bloquant (`|| echo ...`) plutôt que supprimé — reste tenté en best-effort, laisse une vraie
   erreur de toolchain Metal manquant (si elle survient plus loin dans le build) se manifester
   d'elle-même plutôt que de la deviner.
2. **Bug YAML auto-introduit par le fix précédent** — `run: xcodebuild ... || echo "AVERTISSEMENT :
   ..."` sur une seule ligne (scalaire YAML non bloqué) contenait une séquence ` : ` qui a cassé le
   parsing du workflow (confirmé par 2 symptômes indépendants : le `name:` du workflow retombé sur
   son chemin de fichier côté API GitHub, et `workflow_dispatch` refusant le déclenchement avec
   "Workflow does not have 'workflow_dispatch' trigger" malgré le trigger bien présent dans le
   fichier). Corrigé en bloc `run: |`, **validé localement avec PyYAML avant de pousser** cette
   fois — leçon retenue : toujours valider la syntaxe YAML d'un correctif CI avant de le pousser,
   pas seulement sa logique.

### Run de référence — commit CI-only (avant GAP-004)

- **Run `31907788616`**, commit `a66c509` (fixes CI seuls, PAS encore GAP-004) — **SUCCESS**, les 8
  étapes vertes, `** BUILD SUCCEEDED **` confirmé dans le log brut. Première preuve que le pipeline
  lui-même fonctionne de bout en bout.

### Run de référence — commit GAP-004 (upload de fichiers)

- **Run `31908841925`**, commit `e4b1832` ("feat(migration): complete file upload migration
  (GAP-004)") — **SUCCESS**, `** BUILD SUCCEEDED **` confirmé. **Vérification explicite demandée par
  l'utilisateur, pas seulement le statut global** : les 10 fichiers GAP-004
  (`APIClient.swift`/`ProfileRepository.swift`/`ProfileViewModel.swift`/`ProfileView.swift`/
  `CertificationModels.swift`/`CertificationView.swift`/`ChatMediaUploadService.swift`/
  `ChatViewModel.swift`/`ChatView.swift`/`MessageRepository.swift`) apparaissent chacun par leur
  chemin complet dans les invocations réelles du compilateur (log brut, pas une déduction). 0 erreur
  réelle (3 occurrences du mot "error:" dans le log : 1 message toléré du contournement Metal
  Toolchain, 2 signatures Objective-C légitimes contenant "error:" comme nom de paramètre — aucune
  ne bloque le build). **2 warnings au total, tous les deux dans du code PRÉ-EXISTANT de
  `ChatViewModel.swift`** (`markConversationRead`/`deleteSelectedForEveryone`, présents avant cette
  session) — **zéro warning dans le code effectivement écrit pour GAP-004**.

### Codemagic — stratégie double-CI adoptée à partir de maintenant

Sur décision explicite de l'utilisateur, **les deux CI (GitHub Actions + Codemagic) font
désormais partie du workflow permanent** du projet, testant systématiquement le MÊME commit.
**Contrainte technique actuelle** : aucun credential Codemagic n'est disponible dans cet
environnement (contrairement à GitHub, où Git Credential Manager fournissait déjà un token
utilisable) — **l'utilisateur déclenche Codemagic manuellement** depuis son dashboard
(codemagic.io) sur le même commit que celui validé côté GitHub Actions, et communique le résultat
pour documentation. `codemagic.yaml` **n'a PAS été modifié cette session** — aucune preuve qu'il
soit cassé (il utilise `xcode: latest`, potentiellement une version plus récente que le plafond
16.2 du runner GitHub, qui pourrait très bien supporter `-downloadComponent` nativement) ; règle
explicite de l'utilisateur : ne pas dupliquer un correctif GitHub-specific vers Codemagic sans
preuve qu'il en a besoin.

| Commit    | GitHub Actions          | Codemagic                          |
|-----------|--------------------------|-------------------------------------|
| `a66c509` | SUCCESS (`31907788616`) | Non déclenché (CI-only, pas de nouvelle feature) |
| `e4b1832` | SUCCESS (`31908841925`) | **EN ATTENTE** — à déclencher manuellement par l'utilisateur |

### Ce que ce résultat NE dit PAS (rappel explicite de l'utilisateur, à ne jamais oublier)

**"Le code GAP-004 compile réellement dans l'environnement iOS CI (GitHub Actions)."** C'est tout ce
qui est confirmé. PAS confirmé : fonctionnement réel de l'upload (aucun appel n'a jamais touché un
vrai serveur/CDN), sélection photo sur simulateur/device, réception du message chat par l'autre
participant, téléchargement des pièces jointes (non implémenté, gap distinct). Double validation CI
(GitHub + Codemagic tous les deux SUCCESS) : PAS encore atteinte pour `e4b1832`, en attente du build
Codemagic manuel.

---

## APPETIZE FUNCTIONAL TEST — 2026-08-15

**Contexte** : premier test réel de l'app sur Appetize.io (device réel, pas une lecture de code).
Confirme la mise en garde répétée tout au long de ce document : `CODE PORTÉ` ≠ `CODE COMPILÉ` ≠
`FONCTIONNALITÉ RÉELLEMENT VALIDÉE`. 6 problèmes fonctionnels identifiés par l'utilisateur avec
captures d'écran Android de référence à l'appui. Diagnostic fait par comparaison directe du code
Android réel et du code Swift réel (6 investigations menées en parallèle, PAS de supposition).

### P0-1 — HOME : contenu absent

**Problème observé** : le feed n'affiche aucune donnée, ni en grille ni en liste.
**Cause réelle** : **double cause**, pas une seule. (1) Erreur d'architecture — `FeedView.swift`
avait été construit comme un pager plein écran façon Reels/TikTok (`TabView` pivoté, un item à la
fois), une hypothèse du portage initial explicitement documentée comme "non vérifiée visuellement"
et jamais recroisée avec le vrai code Android. `MainFragment.java:707`
(`PreLoadingGridLayoutManager(..., 2, VERTICAL, false)`) montre qu'Android affiche en réalité une
vraie **grille 2 colonnes** (`RecyclerView`/`GridLayoutManager`), confirmée par capture d'écran
utilisateur. (2) Race condition de session (voir P0-2) pouvant aussi empêcher tout chargement au
tout premier lancement après connexion.
**Fichiers Android comparés** : `Activity/ui/MainFragment.java` (lignes 707-730, 1108-1123 —
`OnAdapterItemClicked`), `Activity/adapter/ActivityAdapter.java` (types de vue
`TYPE_HEADER`/`TYPE_ITEM`/`TYPE_ITEM_ADS`, `ViewHolder.video`/`photo`, lignes 386-502).
**Fichiers iOS modifiés** : `Sources/TiinverSwift/Feed/FeedView.swift` (réécriture complète) —
`FeedGridCell` (nouvelle cellule de grille, port de `ViewHolder.video`/`photo`) devient l'écran
principal ; l'ancien pager plein écran devient `FeedDetailPagerView`, un écran de DÉTAIL ouvert au
tap sur une cellule (port fidèle de `OnAdapterItemClicked` → `onArticleSelected(1, arg)`,
positionné sur l'item tapé). `FeedViewModel.swift` non modifié (couche données déjà correcte,
confirmée fidèle à `ActivityRepository.java` par comparaison directe).
**Correction** : grille 2 colonnes (`LazyVGrid`) avec vignette/nom/compteurs like+commentaire en
surimpression (fidèle à `ViewHolder.onBindView`), tap → détail plein écran avec bouton retour.
Bannières décoratives (carrousel Créateurs, promo pièces gratuites) volontairement PAS reproduites
dans cette passe — hors périmètre du problème "données absentes", pas un oubli.
**GitHub Actions** : SUCCESS (run `31911325017`, commit `3f5f880`).
**Codemagic** : en attente (déclenchement manuel utilisateur).
**Test Appetize après correction** : NON TESTÉ (à refaire par l'utilisateur).

### P0-2 — PROFILE : aucune donnée affichée

**Problème observé** : écran Profil vide, sans erreur visible.
**Cause réelle** : race condition confirmée dans les 3 flux de connexion. `Task { await
AuthSessionPersistence.persist(user) }` était lancé SANS être attendu, puis `onLoginSuccess(user)`
naviguait immédiatement — `UserSession.shared.myId` pouvait donc être encore `nil` au moment où
`HomeShellView` présentait `ProfileView()`. Aggravant : `ProfileView.init()` fige
`UserSession.shared.myId ?? ""` dans un `let` AU MOMENT DE LA CONSTRUCTION — si `myId` était nil à
cet instant, l'écran restait bloqué avec `userId == ""` en permanence, même si la session se
complétait une fraction de seconde plus tard. `ProfileViewModel.loadProfile()` a ensuite un `guard
let viewerId = UserSession.shared.myId else { return }` qui sort SANS toucher `isLoadingProfile`,
donc ni le spinner ni les données ne s'affichent jamais — écran vide sans aucun indice.
**Fichiers Android comparés** : `uploadPerfilPhoto/UserProfile.java` (endpoint `getuserbyid`),
confirmé fidèlement porté côté endpoint/JSON (PAS la cause).
**Fichiers iOS modifiés** : `Sources/TiinverSwift/Authentication/AuthSessionPersistence.swift`
(nouvelle fonction synchrone `saveSession(_:)`), `LoginView.swift`, `SignUpWithGoogleView.swift`,
`EmailVerificationView.swift` (appel de `saveSession` AVANT la navigation dans les 3 flux).
**Correction** : `UserSession.save(user)` (déjà synchrone, pas de `await` interne) appelé
directement avant `onLoginSuccess`/`onRegistered`, éliminant la fenêtre de race. Le reste de
`persist` (Core Data, jeton push) reste asynchrone sans bloquer la navigation.
**GitHub Actions** : SUCCESS (run `31911325017`, commit `3f5f880`).
**Codemagic** : en attente.
**Test Appetize après correction** : NON TESTÉ.

### P0-3 — SEARCH : résultats non visibles

**Problème observé** : la recherche ne montre aucun résultat.
**Cause réelle** : `SearchResults` (tableaux `users`/`hashtags`/`posts`, non-optionnels avec valeur
par défaut `[]`) échouait silencieusement au décodage : Swift ne respecte PAS une valeur par défaut
sur un type non-optionnel si la clé JSON est absente. Or `RechercheTiinver.java`
(`parseAndDisplay`, lignes 474/506/529) garde chaque catégorie avec `results.has("users")`/
`has("hashtags")`/`has("posts")` — preuve que le serveur OMET la clé entière d'une catégorie non
demandée (onglet "Publications" → réponse `{"posts":[...]}` SEULEMENT). `JSONDecoder` levait donc
`keyNotFound`, avalé par le `try?` de `SearchRepository.decodeResults`, qui retombait sur
`SearchResults()` vide — MÊME quand le serveur renvoyait de vrais résultats dans la catégorie
demandée.
**Fichiers Android comparés** : `Recherche/ui/RechercheTiinver.java` (`parseAndDisplay`, lignes
460-530).
**Fichiers iOS modifiés** : `Sources/TiinverSwift/Discover/SearchModels.swift` — `init(from:)`
custom sur `SearchResults` (`decodeIfPresent(...) ?? []` par catégorie, fidèle au `.has(...)`
Android).
**GitHub Actions** : SUCCESS (run `31911325017`, commit `3f5f880`).
**Codemagic** : en attente.
**Test Appetize après correction** : NON TESTÉ.

### P0-4 — CHAT : bouton créer un groupe absent

**Problème observé** : aucun point d'entrée pour créer un groupe dans la liste des conversations.
**Cause réelle** : **fonctionnalité jamais construite**, pas un bug — décision de portée déjà
documentée dans `RosterListView.swift` avant ce test ("module Contacts jamais construit, voir
module 18"). Android : FAB `GoToContact` (`Roster.java:84,133-144`) → `Contact.java` (hôte 3
fragments : `ContactsFragment` liste de contacts → `ChooseFragment` sélection multiple → `Group`
fragment nom/confidentialité/type lucratif → `POST group` + `POST membership` par membre →
navigation vers le chat du groupe). AUCUN équivalent iOS n'existe (ni sélecteur de membres, ni écran
de création, ni FAB).
**Fichiers Android référence** : `roster/ui/Roster.java`, `contacts/Contact.java`,
`contacts/ChooseFragment.java`, `contacts/Group.java`.
**Statut** : NON CORRIGÉ cette session — nécessite de construire 2-3 écrans iOS entièrement
nouveaux (sélecteur de contacts, création de groupe), effort de l'ordre d'une session dédiée,
pas une correction ponctuelle. Voir `CLAUDE_CONTINUATION.md` pour la décision de priorisation.
**Test Appetize après correction** : NON TESTÉ (rien à tester, pas encore construit).

### P0-5 — GALERIE : sélection photo sans action

**Problème observé** : sélectionner une photo dans la galerie ne fait rien, pas de bouton "Choisir".
**Cause réelle** : le sélecteur lui-même fonctionne correctement des deux côtés (Android : tap direct
sur une vignette confirme la sélection, `GridViewManager.java:275-280`, pas de bouton séparé — iOS :
`PHPickerViewController` a la même sémantique native, confirmée correcte). Le vrai problème : la
sélection depuis l'écran Caméra mène vers un écran `MediaEditor` qui **n'a jamais été construit**
côté iOS (`FeedView.swift`, `onImagePickedFromGallery`/`onVideoPickedFromGallery` étaient des
fermetures vides ne faisant que refermer la caméra sans aucun retour visuel). Le sélecteur de pièce
jointe du Chat (`ChatView.swift`, ajouté lors de GAP-004), lui, fonctionne déjà correctement — pas
concerné par ce problème.
**Fichiers Android référence** : `engine/.../manager/GridViewManager.java`,
`CustomGalleryView.java`.
**Statut** : NON CORRIGÉ cette session — nécessite de construire un véritable écran
`MediaEditor`/flux de publication (recadrage, légende, publication réelle vers le serveur), qui ne
semble pas exister du tout côté iOS actuellement pour la caméra. Effort substantiel, pas une
correction ponctuelle.
**Test Appetize après correction** : NON TESTÉ.

### P0-6 — ANIMEMES : bouton non fonctionnel

**Problème observé** : le bouton Animems ne fait rien.
**Cause réelle** : `CameraView.swift`'s `onOpenAnimems` est une fermeture vide (`{}`), ET aucun écran
composite `AnimemesEditorView` n'existe côté iOS — le dossier `Animems/` (33 fichiers) ne contient
que les pièces du MOTEUR (`AnimationEngine.swift`, `LayerRenderer.swift`, etc.), jamais assemblées
en un écran affichable, contrairement à `AnimemesCompound`/`fragment_memes.xml` côté Android.
**Fichiers Android référence** : `Activity/ui/CameraActivity.java` (case 5),
`memes/MemesFragment.java`, `com.animems.engine.android.views.AnimemesCompound`.
**Statut** : NON CORRIGÉ cette session — assembler un écran d'éditeur complet à partir du moteur
existant est un effort déjà estimé à plusieurs semaines-ingénieur dans `TIINVER_ANIMEMS_SCOPE_
LIBRARIES.md` (GAP-006). Pas une correction ponctuelle.
**Test Appetize après correction** : NON TESTÉ.

---

## APPETIZE FUNCTIONAL TEST — 2026-08-15 (suite) — P0-4/5/6 CONSTRUITS

Sur instruction explicite de l'utilisateur ("continue sans attendre de test Appetize
intermédiaire — un seul test global à la fin, quota Appetize limité"), les 3 fonctionnalités P0-4/
5/6 (identifiées ci-dessus comme "jamais construites", pas de simples bugs) ont été **construites
dans la même session**, pas seulement documentées comme manquantes.

### P0-4 — CHAT : création de groupe — CONSTRUIT

Port complet de `contacts/ContactsFragment.java`/`ChooseFragment.java`/`Group.java` (lus en entier
via investigation dédiée) :
- **Nouveaux fichiers** : `Messagerie/GroupModels.swift`, `Messagerie/ContactsRepository.swift`
  (`GET connectedusers/{userId}`), `Messagerie/GroupRepository.swift` (`POST group` + `POST
  membership` en boucle), `Messagerie/ContactPickerView.swift` (sélection multiple),
  `Messagerie/GroupCreationView.swift` (nom/privé-public/lucratif+prix/lien d'invitation local).
- **Modifié** : `Messagerie/RosterListView.swift` (bouton d'entrée, port du FAB `GoToContact`
  déplacé en barre du haut — convention iOS, pas de FAB flottant natif).
- Champs `POST group` fidèles à l'original **y compris la faute de frappe réelle du serveur**
  (`type: "pivate"`, pas "private") — reproduite, pas "corrigée".
- Après création : message système local + `RosterModel` construit → navigation directe vers
  `ChatView` (réutilise `MessageRepository.insertTextMessage`, qui met déjà à jour `wk_roster` —
  même chemin que les messages normaux, pas dupliqué).
- **GitHub Actions** : SUCCESS (run `31912698274`, commit `f2460f2`), les 6 fichiers confirmés
  compilés, 0 erreur, 0 warning.

### P0-5 — GALERIE : MediaEditor + publication — CONSTRUIT (périmètre réduit assumé)

Port de `editor/media/MediaEditor.java`/`ImageEditorCompound.java` (crop) + `PublishFragment.java`
(légende/hashtags), investigation dédiée ayant confirmé l'endpoint réel de publication
(`activity/add`, identique au chemin `HttpFileUploader.uploadRequestBody` type=0).
- **Nouveau fichier** : `Feed/PublishComposeView.swift` (recadrage via `PhotoCropView` déjà
  existant, réutilisé tel quel + légende/hashtags).
- **Modifiés** : `Feed/FeedRepository.swift` (+ `publish(...)`, réutilise `APIClient.
  uploadMultipart` de GAP-004), `Feed/FeedView.swift` (les 4 fermetures vides caméra/galerie
  remplacées par un vrai flux vers `PublishComposeView`).
- **Périmètre volontairement réduit** : peinture/texte/stickers du calque photo d'Android
  (`ImageEditorCompound`) PAS repris — confirmés secondaires par l'investigation (le flux principal
  est crop→légende→publication). Catégorie/consentement IA de l'écran Android PAS repris non plus
  — confirmés NE PAS être envoyés au serveur par le code Android réel malgré leur présence dans
  l'UI (`uploadRequestBody` ne les inclut pas), donc hors du comportement observable à reproduire.
  `MediaTrim` (recadrage temporel vidéo) non repris — vidéo publiée telle quelle.
- **GitHub Actions** : SUCCESS (même run), 3 fichiers confirmés compilés, 0 erreur, 0 warning.

### P0-6 — ANIMEMS : écran éditeur — CONSTRUIT (périmètre minimal assumé, PAS la parité complète)

Assemblage d'un écran RÉEL autour du moteur déjà porté (`AnimationComposer`/`AnimationObjectData`/
`LayerRenderer`/`ShapeFactory`/`AnimemesExporter`/`TextRect`) — chaque signature vérifiée
directement dans le code source avant intégration, aucune modification du moteur lui-même.
- **Nouveaux fichiers** : `Animems/AnimemesEditorView.swift` (canevas `Canvas`+`CGContext` via
  `GraphicsContext.withCGContext`, barre d'outils, geste de déplacement), `Animems/
  AnimemesEditorState.swift` (état, ajout photo/texte/forme, export).
- **Périmètre MINIMAL assumé et documenté en tête de fichier** : ajout photo/texte/forme (rectangle/
  cercle/ligne), déplacement au doigt (**translation seule** — pas de rotation/échelle combinées
  comme `AnimemesGestureController` le permettrait en entier), export MP4 **statique 3 secondes**
  (`holdLast`, pas de vraie animation image par image ni de timeline détaillée). PAS la parité
  complète avec `AnimemesCompound.java` (24 942 lignes, déjà estimée à plusieurs semaines-ingénieur
  dans `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`, GAP-006) — un sous-ensemble réellement fonctionnel,
  pas une façade.
- **Câblage** : `CameraView.onOpenAnimems` (fermeture vide auparavant) présente maintenant cet
  écran via `FeedView` (`fullScreenCover`).
- **GitHub Actions** : SUCCESS (même run), 2 fichiers confirmés compilés, 0 erreur, 0 warning —
  résultat notable vu la complexité (rendu `CGContext` bas niveau, `AVAssetWriter`), vérifié
  explicitement plutôt que supposé sûr par analogie avec les autres fichiers.

### Codemagic

Toujours en attente d'un déclenchement manuel par l'utilisateur — aucun résultat Codemagic
rapporté à ce jour pour aucun commit de cette journée (`e4b1832`, `3f5f880`, `f2460f2`).

### Revue transversale (TODO/stubs/placeholders)

Recherche effectuée sur tout `Sources/` — gaps trouvés déjà connus et documentés (pas de nouvelle
découverte majeure) : sélecteur GIF/stickers du chat (`ChatView.swift`, placeholder texte),
téléchargement des pièces jointes chat reçues (`ChatViewModel.requestDownload`, distinct de
GAP-004 qui ne couvrait que l'upload), TODOs de migration Core Data (routine, sans impact
fonctionnel). Rien nécessitant une action dans cette passe.

---

## SESSION DU 2026-08-16 — STATUT PAR FONCTIONNALITÉ (8ᵉ tour, continuation autonome sans
Appetize, instruction explicite de l'utilisateur). Commit final validé : `e4b347a` (GitHub Actions
SUCCESS). Détail chronologique complet dans `MIGRATION_PROGRESS.md`.

| Fonctionnalité | Statut | Détail |
|---|---|---|
| Animems — translation/rotation/échelle | COMPLETE | `AnimemesGestureController` câblé réellement (était déjà porté, jamais utilisé côté UI avant ce tour) |
| Animems — timeline (règle/playhead/blocs par calque) | COMPLETE | Nouveau `TimelineView.swift` au-dessus de `TimelineViewModel` (435 lignes, déjà porté, jamais utilisé) |
| Animems — keyframes explicites (bouton ◆) | COMPLETE | Modèle "marqueur explicite" confirmé par lecture d'Android, PAS un enregistrement continu |
| Animems — lecture/pause réelle | COMPLETE | `AnimationEngine`/`CADisplayLink` (déjà porté, jamais branché) |
| Animems — masques (type/inversion/flou/écart/geste offset-scale-rotation) | COMPLETE | `MaskFactory`/`MaskType`/champs `AnimationObjectData` déjà portés et déjà rendus par `LayerRenderer`, seul le câblage UI manquait |
| Animems — ordre des calques (z-order) | N/A | Confirmé : n'existe PAS côté Android non plus (ordre = ordre d'ajout) |
| Animems — sauvegarde image statique / modèles de mouvement / export GIF | MISSING | Non explorés ce tour — voir `AnimemesCompound.java` `showSaveDialog`/`saveAsMotionTemplate`/`MotionTemplateManager` |
| Galerie — recadrage forme libre / suppression arrière-plan | COMPLETE | Composants déjà portés (`FreeformCropView`/`RemoveBackground`), jamais câblés avant ce tour |
| Galerie — retournement horizontal, peinture, texte | COMPLETE | Nouveau `PhotoToolsView.swift` |
| Galerie — miniature/durée vidéo réelles | COMPLETE | `AVAssetImageGenerator`, remplace l'icône statique |
| Galerie — légende (limite 80), partage natif | COMPLETE | — |
| Galerie — stickers/emoji, `MediaTrim` (recadrage temporel vidéo) | MISSING | Non explorés ce tour |
| Chat — Socket.IO (tous événements) | COMPLETE | Audit dédié événement-par-événement, portage confirmé "unusuellement complet" |
| Chat — pagination/suppression/accusés lecture/reconnexion/présence | COMPLETE | Audit fonctionnel transversal dédié |
| Chat — téléchargement pièces jointes reçues | COMPLETE | `DownloadReceiver.java` lu en entier, GET non authentifié confirmé fidèle |
| Chat — `ChatBubbleRow` (avatar/timestamp/coche), état vide roster | COMPLETE | Signalés "non vérifiés" par l'audit, confirmés déjà présents après relecture directe |
| Chat — `pushNotification`/`pushNotification_by_id` | N/A (faux positif) | `notificateUser`/`notificateUserById` : zéro appelant dans TOUT le dépôt Android, code mort côté Android lui-même |
| WebRTC — signalisation/glare/ICE restart/mute/CallKit | COMPLETE | Audit dédié, 10 fichiers Android relus en entier |
| WebRTC — configuration `AVAudioSession`/`RTCAudioSession` | COMPLETE (corrigé ce tour) | HIGH PRIORITY — absente nulle part avant ce tour, pouvait empêcher l'audio réel sur device malgré compilation/exécution logique correctes |
| WebRTC — permission micro avant appel | COMPLETE (corrigé ce tour) | `Utils/PermissionRequest.java` jamais porté avant ce tour |
| Feed — native ads dans le pager plein écran | COMPLETE | Câblées dans `FeedDetailPagerView` (PAS la grille — vérifié contre `ViewPagerAdapter.java`/`NativeAdsManager.java`) |
| Profile | COMPLETE (quasi-intégral) | Audit dédié ; seul écart déjà documenté (édition catégorie lecture seule) |
| Search — navigation hashtag/publication, bouton Suivre, états erreur/vide | COMPLETE | Nouveau `HashtagFeedView.swift`, mapping `SearchPostResult → FeedActivity` |
| Paiements/monétisation, deep links, Firebase/analytics | UNVERIFIED | Pas d'audit dédié ce tour |

### Build CI — 4 tentatives sur le seul lot Animems timeline/masques

Voir `CLAUDE_CONTINUATION.md` section 0 pour le détail complet run-par-run. Résumé : 3 échecs
successifs (`3f1c22d`, `b90ae3d`, `fd92885`, `0fa0de8` — mauvais usage d'un singleton `private
init`, puis deux vagues d'échecs de type-checking `AnyGesture`/`some Gesture` sur le geste de
masque), chacun diagnostiqué à partir du VRAI log `xcodebuild` téléchargé via l'API GitHub Actions
(jamais deviné, pas d'environnement macOS local). Résolu en restructurant le geste (un seul jeu de
gestes, bascule d'état à l'exécution plutôt que deux graphes de gestes typés différemment) plutôt
que de continuer à patcher l'érasure de type à l'aveugle. **Run final SUCCESS : `31923679579`,
commit `e4b347a`.**

### Codemagic

Toujours en attente d'un déclenchement manuel par l'utilisateur — aucun résultat Codemagic
rapporté à ce jour pour AUCUN commit, y compris ceux de ce tour.
