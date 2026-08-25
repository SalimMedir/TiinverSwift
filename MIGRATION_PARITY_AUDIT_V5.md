# MIGRATION PARITY AUDIT V5

Audit indépendant Android → iOS du portage Tiinver, Phase A (recherche uniquement,
**aucune modification de code Swift pendant cette phase**). Réalisé par 24 agents de
recherche indépendants répartis sur 23 domaines fonctionnels + 1 agent critique de
complétude, sans lecture des audits V1/V2/V3/V4 par les agents eux-mêmes, pour maximiser
les chances de trouver ce que ces cycles antérieurs ont manqué. Android reste la référence
fonctionnelle : seuls les comportements Android réellement atteignables (pas de code mort,
commenté, ou jamais invoqué) ont été considérés comme faisant foi.

## 0. Sommaire

**69 findings** (V5-F-001 à V5-F-069), répartis sur 23 domaines.

### Répartition par priorité

- **P0** : 6
- **P1** : 29
- **P2** : 22
- **P3** : 12

### Répartition par statut suggéré

- **MISSING** : 20
- **FUNCTIONALLY_FAILED** : 22
- **PARTIAL** : 15
- **VISUALLY_DIFFERENT** : 10
- **CODE_PRESENT_UNVERIFIED** : 2

Aucun finding de ce cycle n'a encore de statut `BUILD_VALIDATED` ou
`COMPLETE_PARITY_VALIDATED` — la Phase A est un audit pur, aucun code n'a été modifié.

---

## 1. TOP 20 — Problèmes les plus critiques

Classement par sévérité réelle (risque financier, perte de données, blocage de flux
cœur de produit), pas seulement par la priorité suggérée par l'agent qui l'a trouvé.

1. **V5-F-045** [P0] Envoi d'un commentaire/réponse — mauvais nom de paramètre JSON envoyé au serveur
2. **V5-F-032** [P0] Rejet applicatif du serveur (retrait/transfert/conversion) affiché comme un succès à l'utilisateur
3. **V5-F-031** [P0] Échec applicatif de rewardedCoins traité comme un succès → perte définitive et silencieuse du gain en attente
4. **V5-F-068** [P1] Double-tap sur le bouton d'abonnement/renouvellement de groupe payant → double débit local de pièces et double requête réseau
5. **V5-F-064** [P0] Déconnexion et suppression de compte purgent les données locales même si l'appel réseau échoue
6. **V5-F-005** [P1] Échec réseau du logout/de la suppression de compte avalé silencieusement (try?) : purge locale totale exécutée même si le serveur n'a jamais confirmé
7. **V5-F-018** [P0] Positionnement initial et auto-scroll vers le bas de la liste de messages
8. **V5-F-042** [P0] Le verrouillage d'une piste (icône cadenas) ne bloque pas le glisser/redimensionnement du bloc dans la timeline iOS
9. **V5-F-016** [P1] Vérification de l'état d'abonnement d'un groupe payant appelle un endpoint différent de celui d'Android — le blocage du composeur pour abonnement expiré/restreint ne se déclenche jamais
10. **V5-F-007** [P1] Signalement depuis le plein écran Home envoie un signalement générique sur l'UTILISATEUR au lieu de cibler le POST précis (target_id/report_type manquants)
11. **V5-F-058** [P1] Vidéo entière chargée en RAM avant écriture sur disque (téléchargement Profil + pré-cache du Feed)
12. **V5-F-009** [P1] Rafraîchissement (pull-to-refresh) concurrent à une pagination infinie en cours produit un flux figé sur d'anciennes données (page N au lieu de la page 1) puis des doublons à la pagination suivante
13. **V5-F-013** [P1] La grille de posts d'un profil reste vide après avoir débloqué l'utilisateur
14. **V5-F-063** [P1] Erreur de chargement de l'historique des transactions jamais affichée, aucun mécanisme de reprise
15. **V5-F-033** [P1] Enregistrement et envoi de messages vocaux (voice messages) dans le chat
16. **V5-F-067** [P1] Rafraîchissements concurrents de fetchNotifications() sans verrou global → notifications système dupliquées
17. **V5-F-062** [P1] État d'erreur du centre de notifications rendu inatteignable par l'ordre des conditions
18. **V5-F-023** [P1] Centre de notifications iOS : aucun moyen d'ouvrir la publication concernée pour une notification sans vignette (like/commentaire sur un post texte)
19. **V5-F-057** [P1] CADisplayLink de l'éditeur Animems jamais invalidé si l'écran est quitté pendant la lecture
20. **V5-F-060** [P1] Synchronisation périodique WorkManager (vues/watchtime + suggestions de contenu + livraison de boost) : aucun équivalent iOS enregistré

---

## 2. Domaines couverts et périmètre non exploré

Pour chaque domaine audité : ce qui a été comparé, ce qui n'a PAS été exploré en
profondeur (limite honnête, pas un angle mort caché), et le nombre de findings produits.

### Architecture / Navigation / Lifecycle

**Couvert** : Comparaison du graphe de navigation/cycle de vie racine (AndroidManifest.xml/HomeActivity/ShareActivity/NotificationUtils/CallService côté Android vs TiinverApp/AppDelegate/RootRouterView/HomeShellView/DeepLinkRouter/DeepLinkCenter/CallCoordinator côté iOS) : démarrage à froid, liens profonds (myapp://parrainage, https://tiinver.com/..., tiinver://...), routage des notifications, barre de navigation à 5 items et ses badges, et présentation de l'écran d'appel actif.

**Non exploré** : Pas exploré en détail : back-stack et transitions fines des sous-écrans profonds (Wallet, éditeur Animems, Statistics, groupes de messagerie au-delà de leur point d'entrée), gestion de l'orientation/rotation (FullscreenActivity côté Android), restauration d'état SwiftUI après un vrai kill mémoire côté OS (nécessiterait un test sur appareil réel), et parité fine du flux CallKit après une réponse depuis l'écran verrouillé avec l'app totalement tuée (VoIPPushManager) — signalé comme piste mais non vérifié au runtime.

**Findings produits** : 3

### Session / Auth / Logout / Token

**Couvert** : Audit du flux de session/authentification iOS vs Android : login email/téléphone et Google Sign-In, persistance (Keychain/UserDefaults vs SharedPreferences), déconnexion et suppression de compte (nettoyage local, appel serveur, socket), et absence (des deux côtés) de rafraîchissement/détection d'expiration de token.

**Non exploré** : Flux complet de vérification email/OTP (EmailVerificatiionCode.java vs EmailVerificationView.swift) et de récupération de mot de passe (PWRViewModel/RecoverPassword.java vs ForgotPasswordRequestView/NewPasswordView.swift) non audités champ par champ ; back_sync/Authenticator.java et AuthenticatorService.java (AbstractAccountAuthenticator/SyncAdapter, plomberie Android sans équivalent fonctionnel direct) non lus en détail ; comparaison exhaustive de tous les champs de infoContract.java face à UserSession.swift/AccountEntity non faite au-delà du solde wallet et fcmId ; comportement multi-appareils/session concurrente non testé (aucun mécanisme de ce type trouvé sur Android, donc probablement hors périmètre) ; pas de test dynamique réel (Appetize) — analyse uniquement statique du code source.

**Findings produits** : 2

### Feed — Home / Pagination / Refresh / Grid / Fullscreen / Actions

**Couvert** : Feed Home (grille 2 colonnes + pager plein écran atteint par tap), pagination offset/limit, pull-to-refresh, et les actions like/commentaire/partage/signalement/téléchargement/suppression/blocage/ne-plus-suivre depuis les deux contextes, comparés à `MainFragment.java` (grille) et `FeedFragment.java` (plein écran Home, atteint via `HomeActivity.onArticleSelected(1,...)`) côté Android.

**Non exploré** : Je n'ai pas vérifié en détail : le mécanisme de cache vidéo hors-ligne (ExoPlayerManager/myLikePlay.jaimeCount, lecture du compteur de like en offline), les bannières AdMob/WinFreeCoinsBanner dans le header, le détail du tutoriel TapTargetView, la logique de `PreLoadingGridLayoutManager`/`GridSpacingDecoration` pixel-perfect, ni les différences de format d'image/qualité CDN entre grille et plein écran (au-delà de ce qui est déjà cité). Je n'ai pas non plus vérifié Profile/Hashtag/Search/Notifications en détail (hors périmètre Feed), bien que le finding sur `target_id`/`report_type` les affecte probablement aussi via l'implémentation iOS partagée `FeedViewModel.report()`.

**Findings produits** : 4

### Recherche globale et par catégorie

**Couvert** : Audit du flux de recherche universelle Tiinver (RechercheTiinver.java / RechercheTiinver2.java confirmé mort → SearchView.swift + SearchRepository.swift + SearchModels.swift) : debounce, seuils suggest/full, construction des paramètres q/types/limit/offset par onglet, fusion et filtrage des catégories users/hashtags/posts, historique de recherches récentes (RecentSearchManager ↔ RecentSearchStore), et navigation résultat → profil/hashtag/publication (UniversalSearchAdapter/MentionTextView ↔ SearchView/HashtagMentionText).

**Non exploré** : Recherche dans les conversations (tokenSearch=\"chat\", RetrieveContacts/getItFromServeur côté Android ↔ ChatSearchView.swift côté iOS) volontairement laissée de côté, jugée hors du périmètre \"recherche globale/par catégorie\" assigné et relevant plutôt du domaine Messagerie. FilterGroupMemberList.java (recherche de membres de groupe) et FollowList.java (recherche dans abonnés/abonnements) non audités pour la même raison. Contenu exact des layouts XML de l'écran de recherche (activity_recherche_wenack.xml) non comparé en détail visuel — l'UI iOS étant explicitement reconstruite (pas de spec XML fournie), seules les divergences fonctionnelles/de contenu ont été retenues, pas l'agencement.

**Findings produits** : 3

### Profil / Posts / Followers / Following

**Couvert** : Audit de l'écran Profil (soi-même et autrui) sur iOS — grille de posts paginée, compteurs abonnés/abonnements, liste followers/following (FollowListView), actions suivre/bloquer/signaler, et édition de profil — comparé à UserProfile.java/AddPerfilFoto.java, Following/FollowList.java, Recherche/ui/Adapter.java et Http/TransportData.java côté Android.

**Non exploré** : Le flux d'édition de profil (EditProfile.java, lecture/écriture via ContentProvider local) n'a pas été comparé en profondeur car son architecture (cursor SQLite local + sync différée) diverge trop du modèle REST iOS pour une comparaison ligne-à-ligne fiable dans le temps imparti ; le menu contextuel par POST (unfollow/block/report d'un post individuel dans la grille, OnclickMoreExpand) n'a pas été audité en détail car il relève davantage du domaine Feed/détail-post que du domaine Profil assigné. L'upload de photo de profil (BunnyCDN) n'a pas été revérifié car déjà documenté comme corrigé récemment (V4-F-008/V4-F-009).

**Findings produits** : 3

### Groupes / Groupes payants / Membres / Permissions

**Couvert** : Audit du domaine Groupes de messagerie (création, abonnement payant, gestion des membres, rôles admin/membre, actions de groupe) comparant messagerie/group/*.java + ChatFragmentTest.java + MessageListAdapter.java (Android, lus en détail) à GroupDetailView.swift/GroupRepository.swift/GroupCreationView.swift/AddGroupMemberView.swift/ChatViewModel.swift (iOS) ; gardes de permission admin, endpoints réseau (création, ajout/retrait membre, promotion/rétrogradation, changement nom/description/photo, quitter le groupe, flux d'abonnement/renouvellement) vérifiés champ par champ et endpoint par endpoint.

**Non exploré** : Pas vérifié en détail : le backend réel (impossible d'exécuter les endpoints pour confirmer le comportement exact de \"group/checksubscription\" sans le \"2\" — l'analyse s'appuie sur la lecture stricte du code source des deux côtés) ; le module Wallet/Paiements sous-jacent (débit réel côté serveur, cohérence du solde après un crash réseau juste après paiement) ; la synchronisation SQLite locale Android (MyBackgroundTask) et son équivalent absent côté iOS (délibérément simplifié en appel réseau direct, déjà documenté comme tel dans le code iOS) ; les écrans GIF/Gift picker liés aux groupes ; le comportement du bouton \"reset\" du lien d'invitation (code mort des deux côtés, non exploré en profondeur) ; les cas de concurrence multi-appareils (deux admins agissant simultanément sur le même membre).

**Findings produits** : 2

### Chat

**Couvert** : Audit du pipeline complet de l'écran de conversation (chat 1:1 et groupe) côté iOS versus Android : construction et émission des paquets réseau par type de message (texte/photo/vidéo/audio/gif/sticker/graphic/gift/document), réception et persistance des messages entrants (privés et groupe), accusés de livraison/lecture, indicateur de frappe, présence en ligne, citation, suppression locale et pour tous, pagination, et rendu des bulles par type — avec vérification de l'atteignabilité réelle du code Android comparé.

**Non exploré** : Le codec de compaction des messages Graphic (GraphicMessageCodec.swift / MessageGraphicComposeView.swift) n'a été vérifié que superficiellement (wiring d'entrée confirmé, pas le détail octet-par-octet du format compact). ChatSearchView.swift, PrivateMessageSettingView.swift et le détail complet de ChatMediaUploadService.swift (protocole d'upload BunnyCDN) n'ont pas été audités dans cette passe — le domaine assigné se concentre sur l'écran de conversation lui-même. Le module WebRTC/CallKit (démarrage réel d'un appel après le tap corrigé en Finding 2) n'a pas été vérifié au-delà du point d'entrée partagé avec le bouton de la barre d'outils. Les DAO/requêtes SQL exactes de MessageDAO.java (Android) n'ont pas été comparées champ par champ à MessageRepository.swift au-delà du tri/pagination.

**Findings produits** : 2

### Socket.IO / Temps réel — flux complet

**Couvert** : Audit complet du flux Socket.IO messagerie/appels/PBS iOS vs Android (connexion, authentification handshake, abonnement aux 27+ événements de ChatRepository.ROOM, noms et payloads exacts, réception→propagation UI via Combine, reconnexion, présence/frappe, déconnexion propre) — domaine déjà très largement corrigé par les cycles V1-V4 (fichiers TiinverSocket.swift/ChatRepository.swift/SocketEvent.swift abondamment commentés avec preuves) ; un écart réel de pagination hybride REST+local pour l'historique de GROUPE a été identifié par grep exhaustif, non couvert par les correctifs précédents.

**Non exploré** : Signalisation WebRTC (appels 1:1/CallService, CallService2 dupliqué) et flux audio-sur-socket 'onVoice' (AudioCall/CallButton) vérifiés comme du code Android mort (init() commenté, call jamais instancié) donc hors périmètre — pas auditée en profondeur côté iOS CallCoordinator/CallKitManager (probablement domaine WebRTC dédié). Pas vérifié : détail des payloads JSON de MessagePacket.getPacketJson()/getPacketForGroupJson() champ par champ (uniquement les noms d'événements et le routage), ni le comportement exact d'ordre/scroll après réception d'un lot ancien de groupe côté UI (non pertinent puisque la fonctionnalité elle-même est absente côté iOS, voir finding).

**Findings produits** : 1

### Notifications

**Couvert** : Push (FCM/APNs), notifications locales (contenu et déclenchement), centre de notifications in-app (liste, badges, tap), et routage au tap d'une notification système, comparés entre Android (back_sync/NotiLikecmt) et iOS (Notifications/, Realtime/ChatRepository.swift, App/AppDelegate.swift).

**Non exploré** : Le module VoIP/CallKit (showIncomingCallNotification/showOngoingNotification) et la notification de réengagement displaySuggestNotification sont explicitement hors périmètre notifications push génériques côté iOS (documenté dans LocalNotificationBuilder.swift) et n'ont pas été creusés en détail. Le contenu exact des chaînes localisées (strings.xml) n'a pas été vérifié caractère par caractère.

**Findings produits** : 8

### WebRTC / Appels / CallKit / PushKit

**Couvert** : Audit du domaine appels audio/vidéo WebRTC (signalisation offer/answer/ICE, CallKit/PushKit, permissions micro, transitions d'état sonnerie/connecté/terminé/manqué/occupé, mute/haut-parleur, appel entrant pendant appel en cours) via comparaison ligne à ligne de CallService.java/CallActivity.java/IncomingCallActivity.java/RTConnection2.java/ChatRepository.java (Android, RTConnection2 confirmé seul moteur vivant) contre CallCoordinator.swift/CallKitManager.swift/WebRTCConnection.swift/CallView.swift/ChatRepository.swift (iOS).

**Non exploré** : Non couverts en profondeur faute de temps : VoIPPushManager.swift/VoIPTokenRegistrar.swift (endpoint serveur non implémenté, déjà signalé comme limitation connue dans les commentaires du code), CallService2.java/RTConnection.java/RTConnection3.java (confirmés morts, non portés à dessein), comparaison fine des chaînes de ressources (strings.xml) pour les libellés d'état d'appel, comportement de la sonnerie/haut-parleur sur matériel réel (Bluetooth, casque filaire), et le bug Android lui-même (CallActivity.java mute button : l'appel réel à setMicrophoneMute est commenté sur la branche \"activer le mute\", ligne ~399) qui n'a pas été retenu comme gap iOS car iOS ne reproduit pas ce bug (comportement iOS meilleur, pas une régression).

**Findings produits** : 2

### Wallet / Pièces / Paiements / Retraits

**Couvert** : Audit du domaine Wallet (solde de pièces/gemmes, gain par pub récompensée, transfert P2P, conversion, retrait, parrainage, AdMob) — analyse ligne par ligne de WalletRepository.java/EarnCoinsActivity.java/WithdrawActivity.java/TransfertCoinsActivity.java/ConversionActivity.java/ReferralActivity.java côté Android contre leurs ports iOS, avec vérification systématique de la chaîne réseau (TransportData.Post vs APIClient) pour la sémantique delta/total et le traitement des erreurs applicatives.

**Non exploré** : MonetizationActivity/MonetizationView (écran de paramétrage, pas de logique de solde trouvée, non exploré en profondeur), les layouts XML wallet_* restants (adapters WalletAdapter/OfferAdapter côté affichage pur), Purchase/CheckoutActivity Android (flux mobile money/crypto confirmé remplacé intentionnellement par StoreKit 2 côté iOS, déjà documenté et audité aux cycles précédents — non ré-audité en détail ici), le module Engine Animems (hors périmètre Wallet), et le contenu réel du backend PHP (endpoints `rewardedCoins`/`withdrawalrequests`/`convert`/`transfert`) qui n'est pas accessible en lecture — la preuve du contrat \"error\"/\"message\" HTTP-200 repose uniquement sur `TransportData.Post`/`postToVPS` côté client, pas sur une inspection directe du serveur.

**Findings produits** : 2

### Pipeline média — sélection → BunnyCDN → backend (photo/vidéo)

**Couvert** : Pipeline média complet audité pour Feed (photo/vidéo BunnyCDN Storage + Video Library), Chat (photo/vidéo/pièces jointes BunnyCDN Storage direct), photo de profil et photo de groupe (multipart backend) — protocoles trouvés fidèlement portés et déjà très bien documentés côté iOS ; un gap fonctionnel réel et non documenté identifié sur l'enregistrement/envoi de messages vocaux en chat.

**Non exploré** : Story (aucun module Story identifié dans le temps imparti — non confirmé comme existant côté Android). Envoi de documents (\"doc\") en chat non approfondi car le bouton Android correspondant (openDoc) s'est avéré être du code mort (jamais attaché via setOnClickListener), donc hors périmètre par la règle 3. Compression/redimensionnement exact des images côté Android (Bitmap.CompressFormat, qualité) non comparé octet-près au portage iOS (jpegData compressionQuality 0.9) faute de temps — les deux nomment le fichier \".webp\" avec Content-Type application/octet-stream donc le serveur ne dépend pas du format réel, mais une comparaison fine de la qualité/taille n'a pas été faite. Retry/backoff explicite (MAX_RETRY/getBackoffDelay présents mais non appelés côté Android dans UploadFileOrDataService, donc probablement code mort également) non vérifié en détail.

**Findings produits** : 1

### Galerie (picker photo/vidéo)

**Couvert** : Sélecteur natif de photo/vidéo (PHPickerViewController iOS vs PickVisualMedia Android) : permissions, sélection unique, gestion des échecs (iCloud non téléchargé, permission révoquée, copie/lecture échouée), annulation, et — pour le point d'entrée « + » de l'éditeur Animems — l'étape d'aperçu/validation post-sélection (recadrage image, extraction de trame vidéo) qui fait partie intégrante du flux de sélection dans ce contexte précis.

**Non exploré** : Je n'ai pas vérifié en détail : (1) le comportement de PHPicker/GalleryPickerView sur iPad (présentation popover) ; (2) le cas d'un asset iCloud volumineux dont le téléchargement dépasse un délai réel (pas de timeout explicite ni côté Android ni côté iOS observé, donc probablement non pertinent) ; (3) les autres pickers Android hors périmètre direct de la « galerie native » (StickerPickerDialog/GiftGalleryView, explicitement documentés comme non portés côté iOS avec un placeholder, donc déjà signalés dans le code source lui-même, pas un gap caché) ; (4) le flux complet post-sélection dans MediaEditor/PublishFragment (aperçu de recadrage/filtre pour les publications du fil principal, hors du picker lui-même) n'a été vérifié que pour Animems, pas pour Feed/Wallet.

**Findings produits** : 2

### Photo Editor

**Couvert** : Comparaison de l'éditeur photo réellement atteignable (ImageViewCanvas/ImageEditorCompound/AnimemesCompound côté Android — MediaEditor2.java confirmé mort et exclu — vs AnimemesEditorState/AnimemesEditorView côté iOS) sur le dessin libre, le texte, la superposition de calques, l'export et surtout la sémantique exacte du bouton undo.

**Non exploré** : Comparaison fine du recadrage (CroperView.java vs FreeformCropView/PhotoCropView), de l'ordre de superposition exact des calques pendant le rendu/export (LayerRenderer.swift complet), des gestes de déplacement/rotation/scale des calques, et des filtres/ajustements image (aucune fonctionnalité de ce type trouvée dans le code Android réellement atteignable de cet éditeur — uniquement des filtres de caméra en direct, hors périmètre — donc non traité comme écart). Pas de vérification approfondie de BezierEditorView, MaskEditController, ni du module de recomposition (AnimemesRecompose).

**Findings produits** : 1

### Video Editor

**Couvert** : Écran de trim/recadrage vidéo (VideoTrimmerView.java / MediaTrim.java côté Android, MediaTrimView.swift / VideoTrimState.swift côté iOS) : précision et chemin d'export du trim temporel, interactivité et zone par défaut du recadrage spatial, et seuils de détection 'aucune modification' — aucun filtre visuel n'existe côté Android sur cet écran de trim (parité de fait), et les presets de ratio/rotation/flip/limite de durée max (60s) sont déjà correctement portés.

**Non exploré** : Codec exact produit par AVAssetExportPresetHighestQuality (H.264 vs HEVC selon device) comparé au H.264 forcé côté Android, et comportement réel de Mp4Faststart/shouldOptimizeForNetworkUse sur device — nécessiteraient un test sur appareil réel, non vérifiables statiquement avec certitude suffisante. Le module Animems (moteur d'animation séparé) et les filtres photo (editor/filter, hors flux vidéo trim) n'ont pas été explorés en détail car non rattachés à l'écran de trim vidéo réellement atteignable.

**Findings produits** : 3

### Animems — Canvas / Gestures / Interaction / Masques / Texte / Formes / Dessin

**Couvert** : Audit des gestes du canevas Animems (tap/glisser/pincer/pivoter/appui long) — sélection, déplacement, rotation, échelle, ordre d'empilement (bring-to-front), verrouillage, suppression et édition de masque — comparés ligne à ligne entre engine/android/memes/MemesView2.java (+ AnimemesCompound.java, vue réellement utilisée par MemesFragment) et AnimemesGestureController.swift/AnimemesEditorState.swift/AnimemesEditorView.swift côté iOS ; le dessin libre, l'ajout de formes/texte et l'import média n'ont été vérifiés que superficiellement (délibérément écartés, cf. ci-dessous).

**Non exploré** : Pas d'audit approfondi de : ajout/édition de texte (ProTextEditorState/TextLayoutEngine vs ProTextEditorView Android), ajout de formes (ShapeFactory/ShapeAddPanel), import de média dans le canevas (sélecteur galerie → calque), et le mode dessin libre au pinceau n'a été comparé qu'au niveau architecture générale (iOS l'implémente comme un sous-écran modal séparé qui aplati le tracé en un calque bitmap unique, une divergence de flux déjà documentée et assumée dans AnimemesDrawingView.swift plutôt que vérifiée point par point contre drawPathProcess/chaikin). Verrouillage/visibilité écarté du périmètre \"gestes canevas\" car piloté par la timeline/panneau de calques (clic), pas par un geste sur le canevas lui-même — non comparé en détail à ce titre.

**Findings produits** : 2

### Animems — Timeline / Keyframes / Moteur / Import-Export / Playback / Audio

**Couvert** : Timeline (scrub/pan/zoom pincé/sélection/redimensionnement/icônes verrou-visibilité), keyframes (ajout via bouton ◆, sélection/suppression par tap sur marqueur, interpolation/easing), moteur de lecture (AnimationEngine, table de frames, CADisplayLink) et export MP4 (AnimemesExporter vs MP4Encoder) du module Animems, comparés ligne à ligne entre AnimemesCompound.java/TimelineView.java/AnimationEngine.java (Android, classes réellement actives — TimelineView2/AnimemesCompound2 confirmées non utilisées) et TimelineView.swift/TimelineViewModel.swift/AnimationEngine.swift/AnimemesExporter.swift (iOS).

**Non exploré** : Le pipeline d'export bas niveau Android (MP4Encoder.java, shaders GLSL, MediaCodec/EGL, transcodeToM4A) n'a été comparé que via les notes déjà laissées par le port iOS existant, pas relu ligne à ligne côté Android par moi-même ; la piste audio (ajout/synchro/volume) n'a pas montré de contrôle de volume identifiable côté Android dans le temps imparti, donc non comparée en détail ; TimelineView2/AnimemesCompound2/AnimemesCompoundOpselete (classes confirmées non appelées depuis MemesFragment, donc hors périmètre par la règle anti-code-mort) n'ont pas été examinées davantage ; le baking GL matriciel (androidToGL_Matrix2) n'a pas été audité en profondeur, sa non-portée étant déjà justifiée par choix d'architecture Core Graphics documenté côté iOS ; la précision fine des arrondis dans MP4Encoder (calcul de durée audio totalFramesForAudio) n'a pas pu être comparée faute d'avoir localisé le fichier Android correspondant dans le temps imparti.

**Findings produits** : 3

### Publication de posts + Commentaires / Likes / Partage / Signalement

**Couvert** : Audit du flux complet de publication de posts (média → légende/hashtags → catégorie → publication Bunny+activity/add) et des interactions associées (likes, partage, signalement, commentaires avec réponses imbriquées et cadeaux en commentaire), en comparant le code Android réellement exécuté (ActivityService, PublishFragment, MyBottomSheetDialogFragment/CommentAdapter/CommentRepository, GiftCatalogHelper) au port Swift correspondant (FeedRepository/PublishComposeView, CommentRepository/CommentsView/CommentModels, HashtagMentionText, GiftCatalog).

**Non exploré** : None

**Findings produits** : 5

### Settings / Compte / Confidentialité + Deep Links / Universal Links

**Couvert** : Audit des écrans Settings (compte, confidentialité, notifications, stockage, à propos, aide, publicité, apparence) et du routage des liens profonds/Universal Links (schémas myapp:// et tiinver://https://tiinver.com/{user,post,group,myaccount,animemes,update,offer}), avec vérification de la persistance serveur réelle et de la visibilité des erreurs.

**Non exploré** : Le module Certification (ui/certification/*, lié depuis le menu racine des Réglages via header_verified/CertificationActivity, porté côté iOS sous Discover/CertificationView.swift) n'a pas été audité en détail — probablement hors périmètre de ce domaine (classé sous « Discover » côté iOS, pas « Settings »). SettingPrivateMessageFragmant/PrivateMessageSettingView (réglages de conversation individuelle) et SettingGroupMessageFragmant (réglages de groupe) ont été vérifiés rapidement mais pas ligne à ligne intégralement. Le contenu détaillé des dialogues MyFragmentDialog (types 0-7) n'a été vérifié qu'au niveau des cas pertinents pour Settings/deep links. La correspondance exacte des libellés FR/EN de toutes les chaînes de settings n'a pas été vérifiée exhaustivement au-delà des cas cités.

**Findings produits** : 4

### Cache / Téléchargement / Offline / Reprise

**Couvert** : Audit du cache disque/mémoire (images CDN, vidéos Feed, réponses API), du téléchargement de fichiers (média Feed, pièces jointes de chat) et du comportement hors-ligne/reprise après interruption sur iOS, comparé ligne à ligne au code Android source (ActivityRepository/MainFragment/ExoPlayerManager/DownloadManager/DownloadReceiver/ChatFragmentTest).

**Non exploré** : Upload de média (BunnyCDN, feed et chat) non couvert en profondeur côté résilience à la mise en arrière-plan (URLSession foreground vs Android Service au premier plan) — signalé en passant mais pas développé en finding faute de temps ; comportement offline détaillé des écrans Notifications/Recherche/Wallet/Contacts non audité ; migration/corruption du store Core Data (CoreDataStack.swift) non examinée en détail ; comportement du cache disque Animems (stickers/gifs, GifDiskCache/StickerCache côté Android) non comparé à un éventuel équivalent iOS.

**Findings produits** : 3

### Performance / Mémoire / Gros médias

**Couvert** : Audit des chemins de décodage d'images/vidéos (CDNAsyncImage, vignettes de trim vidéo et de pièces jointes chat), du cycle de vie des ressources actives (CADisplayLink/timers de l'éditeur Animems, observers KVO/NotificationCenter du lecteur vidéo Feed, listeners Socket.IO), et des mécanismes de téléchargement/pré-cache vidéo et de virtualisation des listes (Feed, pager plein écran).

**Non exploré** : Détail complet du module Shareboard/PBS (PBSCanvasView/PBSViewModel) et de MotionTemplateManager/CommunityTemplateGalleryView (galeries de modèles, pagination potentielle) non audités en profondeur ; Camera/Filters (traitement CoreImage sur flux caméra) et Statistics (graphiques) non couverts ; pas de vérification de la croissance mémoire de AnimationObjectData.transforms/keyframes sur des animations très longues ; pas de test dynamique réel (profiling Instruments), toutes les conclusions reposent sur lecture statique du code source des deux plateformes.

**Findings produits** : 3

### Permissions iOS + Background Tasks

**Couvert** : Audit des permissions système (caméra, micro, photos, notifications, contacts, tracking ATT) et des tâches en arrière-plan (BGTaskScheduler / équivalents WorkManager) sur iOS, avec vérification croisée de la logique Android réellement atteignable pour chaque point.

**Non exploré** : Je n'ai pas audité en détail : (1) la robustesse des uploads réseau (chat/posts) face à la mise en arrière-plan de l'app — aucun usage de URLSession background(withIdentifier:) ni de beginBackgroundTask n'a été trouvé côté iOS (Sources/TiinverSwift/Networking/APIClient.swift utilise uniquement URLSessionConfiguration.af.default), ce qui pourrait constituer un gap supplémentaire par rapport aux OneTimeWorkRequest Android (service/worker/UploadChatWork.java) mais nécessiterait une comparaison plus poussée avec le module Messagerie/Upload (hors périmètre strict de mon domaine) pour conclure formellement ; (2) le détail complet du module Animems (moteur C:\Users\helen\AndroidStudioProjects\tiinver\engine\...) côté permissions/tâches de fond n'a pas été exploré ; (3) le flux complet PushKit/VoIP (déjà fortement documenté par des corrections antérieures V3/V4 dans le code, jugé probablement déjà couvert) n'a été vérifié que superficiellement.

**Findings produits** : 2

### Erreurs réseau / backend / états loading-empty-error-success

**Couvert** : Audit de la gestion d'erreur transversale (états chargement/vide/erreur/succès et try?/catch silencieux) sur les 7 écrans assignés (Feed, Profile, Chat, Notifications, Search, Wallet, Settings), avec vérification systématique des ViewModels et vues correspondantes contre le code Android source réellement atteignable.

**Non exploré** : Écran Chat : la pagination/chargement des messages (source locale Core Data, comparable au CursorLoader local Android — pas de divergence trouvée) et le cycle upload/download média (spinner perpétuel sans erreur des deux côtés, vérifié fidèle) ont été examinés sans trouver de nouvel écart de ce domaine ; les sous-écrans de réglages liés aux groupes de discussion (GroupDetailView, PrivateMessageSettingView) et le flux d'appel (CallCoordinator) n'ont pas été audités en détail sous cet angle faute de temps. Search a été revérifié rapidement (déjà largement corrigé par les cycles V3/V4) sans nouvel écart trouvé, mais sans relecture ligne à ligne de SearchRepository.swift. Les écrans secondaires de Wallet (Retrait/Achat/Transfert/Conversion/Parrainage) n'ont été vérifiés qu'en survol (WithdrawView semble déjà correctement instrumenté).

**Findings produits** : 5

### Concurrence / Race conditions / async-await / callbacks

**Couvert** : Audit des race conditions et de la sécurité de concurrence dans ChatViewModel/ChatRepository (Messagerie), NotificationCenterViewModel (Notifications), FeedViewModel/FeedRepository (Feed), AIChatViewModel (module IA) et TimelineViewModel/AnimemesEditorState/BitmapCacheManager/AnimemesExporter (Animems), avec comparaison systématique aux gardes de concurrence Android correspondantes.

**Non exploré** : Repositories bas niveau non audités en détail pour la synchronisation Core Data (MessageRepository, RosterRepository — accès concurrents aux NSManagedObjectContext non vérifiés ligne à ligne) ; PBSViewModel/Shareboard et CallCoordinator/WebRTCConnection (module appels, concurrence WebRTC non couverte) ; ProfileViewModel et SearchView (follow/unfollow optimistes, pattern déjà documenté ailleurs comme corrigé mais pas revérifié ici) ; MotionTemplateManager (chargement/sauvegarde de templates, accès disque non audité pour la concurrence) ; comparaison approfondie du pipeline Android ActivityRepository/ActivityViewModel (AsyncTask/LiveData) pour statuer définitivement sur une éventuelle race identique côté Android autour de FeedViewModel.reset()/loadNextPage() — piste explorée mais écartée faute de preuve solide d'une différence de comportement avec Android (donc non reportée comme finding)."

**Findings produits** : 3

---

## 3. Critique de complétude (agent indépendant)

Un agent séparé, sans avoir produit lui-même de finding, a examiné les 23 rapports de
domaine pour repérer les zones sous-creusées et les patterns de bug systématiquement
sous-cherchés. À traiter comme point de départ d'un futur complément d'audit, pas comme
des findings confirmés.

### Domaines insuffisamment creusés

- Socket.IO / Temps réel — 1 seul finding malgré l'audit de 27+ événements et un flux central à toute l'app (chat, présence, appels). Le domaine invoque "déjà largement corrigé par V1-V4" pour justifier le faible score, mais aucun finding ne porte sur la reconnexion elle-même (doublons de messages après reconnexion, ré-abonnement aux rooms, fenêtre de perte d'événements pendant la coupure) alors que 'reconnexion' est explicitement listé comme couvert.
- Chat (écran de conversation) — seulement 2 findings pour le domaine fonctionnellement le plus riche de l'app (9 types de message, accusés de livraison/lecture, frappe, présence, citation, suppression, pagination, rendu par type). Le scope réellement couvert (hors les exclusions explicites: codec Graphic, ChatSearchView, upload BunnyCDN, WebRTC, DAO SQL) reste très large ; un ratio de seulement 2 findings dessus, alors que des domaines de portée comparable ou moindre (Notifications: 8, Publication+Commentaires: 5) en trouvent nettement plus, suggère une détection insuffisante plutôt qu'une réelle parité.
- Pipeline média BunnyCDN (sélection→upload→backend) — 1 seul finding (messages vocaux) pour un pipeline couvrant Feed, Chat, photo de profil et photo de groupe sur 4 types de média. Le retry/backoff, la robustesse à la mise en arrière-plan et la fidélité de compression n'ont été qu'effleurés (cf. not_reached), donc le chiffre bas pourrait refléter un manque de profondeur plutôt qu'une réelle parité totale.
- Photo Editor — 1 seul finding, alors que gestes de calque (déplacement/rotation/scale), ordre de superposition à l'export et recadrage n'ont explicitement pas été vérifiés en détail (cf. not_reached) ; une seule anomalie remontée sur un si grand nombre de sous-fonctionnalités non couvertes est suspect.
- Animems — Canvas/Gestures — 2 findings, mais le texte, les formes, l'import média et le dessin libre (des pans entiers du canevas) n'ont été vérifiés que 'superficiellement' ou pas du tout ; ces zones sont historiquement riches en bugs d'interaction (undo/z-order/hit-testing) et restent un point aveugle transversal avec le domaine Timeline (qui ne les couvre pas non plus).

### Patterns de bug systématiquement sous-cherchés

- Double-tap / soumission dupliquée sur bouton d'action : le pattern n'a été détecté qu'une seule fois (abonnement/renouvellement de groupe payant, domaine Concurrence) alors qu'il s'agit d'un bug classique à vérifier systématiquement sur TOUS les boutons d'action réseau à effet monétaire ou irréversible (Like, Suivre, Envoyer un message, Publier un post, Retrait/Transfert/Conversion Wallet) — aucun de ces autres points d'entrée n'a été explicitement testé pour ce pattern, y compris dans le domaine Wallet lui-même qui a pourtant trouvé 2 P0 sur d'autres axes.
- Cycles de rétention mémoire / fuites via closures Combine (capture forte de `self` dans `.sink`/`.assign`, souscriptions jamais annulées) — jamais mentionné comme axe d'investigation dans aucun des 23 domaines, alors que l'architecture est explicitement décrite comme fortement basée sur Combine (propagation UI Socket→Combine) ; c'est un pattern de bug très classique en portage Android(RxJava/LiveData)→iOS(Combine) qui semble totalement absent de l'audit.
- Annulation des requêtes réseau en vol lors d'une navigation hors écran (URLSession/Combine task cancellation, `Task` non annulée) — non traité comme catégorie propre ; plusieurs findings d'erreurs silencieuses pourraient masquer ce pattern sans qu'il ait été cherché en tant que tel.
- Synchronisation du badge d'icône d'application (badge système iOS) avec les badges in-app — seul le badge de l'onglet Chat a été vérifié (et trouvé buggé) ; aucune vérification de la cohérence entre `UIApplication.applicationIconBadgeNumber` et les compteurs internes (messages, notifications) n'apparaît.
- Accessibilité (VoiceOver, Dynamic Type, contraste) — absente à 100% des 23 domaines, aucune mention même en 'not_reached' ; angle mort total pour un audit de parité de cette ampleur.
- Perte/duplication de messages socket pendant une fenêtre de reconnexion (event manqué, re-livraison en double après reconnect) — le domaine Socket.IO couvre la reconnexion 'générique' mais ne rapporte aucun finding précis sur ce sous-cas pourtant classique et à fort impact (messages en double ou messages perdus).

### Notes complémentaires

Couverture globale solide (64 findings sur 23 domaines, avec de bons réflexes récurrents : erreurs réseau avalées via try?, endpoints divergents Android/iOS, état UI non rafraîchi). Les domaines à fort volume (Notifications: 8, Erreurs réseau: 5, Publication+Commentaires: 5, Feed: 4) montrent que la méthode fonctionne bien quand appliquée en profondeur — ce qui rend d'autant plus visible le contraste avec les domaines à 1-2 findings listés ci-dessus, surtout quand leur description de scope reste large. Beaucoup de sections 'not_reached' sont honnêtes et bien justifiées (code mort exclu par une règle explicite, backend inaccessible, absence de device réel) — ce n'est pas un signe de bâclage en soi, mais certains agents (Chat, Pipeline média, Photo Editor) semblent avoir arrêté la recherche dès la première anomalie trouvée plutôt que d'épuiser le scope annoncé comme couvert. Le pattern 'double-tap / duplicate submit' et les fuites mémoire Combine sont les deux angles les plus nettement sous-explorés de façon transversale (pas propres à un seul domaine).

---

## 4. Findings détaillés

```
ID : V5-F-001
PRIORITÉ : P1
DOMAINE : Architecture / navigation — appels entrants et en cours
FEATURE : Écran d'appel (CallView) accessible uniquement depuis la conversation d'origine, pas globalement
ANDROID SOURCE : AndroidManifest.xml:347-353 (CallActivity/IncomingCallActivity déclarées comme Activities EXPORTED indépendantes, IncomingCallActivity en launchMode="singleTask") ; CallService.java:571-617 (onStartCommand) — `startActivity(new Intent(this, CallActivity.class).addFlags(FLAG_ACTIVITY_NEW_TASK))` (ligne 578-585, appel sortant) et `startActivity(new Intent(this, IncomingCallActivity.class).setFlags(FLAG_ACTIVITY_NEW_TASK))` (lignes 605-617, appel entrant) — lancées depuis un Service Android, donc INCONDITIONNELLEMENT, quelle que soit l'Activity/le Fragment actuellement affiché.
ANDROID BEHAVIOR : Dès qu'un appel démarre (sortant ou entrant), Android lance CallActivity/IncomingCallActivity par-dessus N'IMPORTE QUEL écran de l'app (Feed, Wallet, Réglages, etc.) grâce à FLAG_ACTIVITY_NEW_TASK depuis le Service. L'écran d'appel personnalisé (muet/haut-parleur/raccrocher/minuteur) est donc TOUJOURS atteignable pendant tout appel, indépendamment de la conversation ouverte au moment où l'appel a démarré ou repris.
IOS FILES : Sources/TiinverSwift/Messagerie/ChatView.swift:70-72 (SEUL point d'attache : `.fullScreenCover(isPresented: Binding(get: { callCoordinator.state != .idle }, ...)) { CallView(coordinator: callCoordinator) }`) ; grep exhaustif sur `callCoordinator`/`CallCoordinator.shared`/`CallView(` dans tout `Sources/TiinverSwift` confirme SEULEMENT 3 fichiers : ChatRepository.swift (émetteur d'événements), AppDelegate.swift (aucune présentation), ChatView.swift (seule présentation UI) — ni HomeShellView.swift ni RootRouterView.swift n'observent `CallCoordinator.shared.state`.
IOS BEHAVIOR : `CallView` (les contrôles muet/haut-parleur/raccrocher propres à l'app, voir Sources/TiinverSwift/Calls/CallView.swift) n'est présenté QUE si l'instance SwiftUI `ChatView` de LA conversation concernée est actuellement montée dans la hiérarchie de vues. Si l'utilisateur est sur un autre onglet (Feed, Créateurs), sur la liste des conversations, dans le Wallet, les Réglages, ou même dans le ChatView d'UNE AUTRE conversation au moment où l'appel démarre ou reprend (ex. après avoir répondu via l'écran système CallKit depuis l'écran verrouillé), aucune vue de l'app n'observe `callCoordinator.state` : l'appel reste actif côté WebRTC/CallKit mais l'app ne présente JAMAIS ses propres contrôles muet/haut-parleur/raccrocher tant que l'utilisateur n'a pas navigué manuellement jusqu'à cette conversation précise.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage a recréé `CallCoordinator`/`CallView` comme un couple orchestrateur+vue unique (choix documenté en tête de `CallCoordinator.swift`), mais la présentation de `CallView` a été câblée comme un simple `.fullScreenCover` local à `ChatView` plutôt que d'être remontée au niveau racine de la coquille post-connexion (`HomeShellView`) ou de la racine de navigation (`RootRouterView`), qui sont les seuls points toujours montés quel que soit l'écran affiché — contrairement à Android où CallActivity/IncomingCallActivity sont des Activities système indépendantes, lancées par un Service et donc jamais dépendantes d'un Fragment particulier.
IMPACT : Pendant un appel, si l'utilisateur (ou l'app relancée en arrière-plan par CallKit après réponse depuis l'écran verrouillé) n'est pas précisément sur le ChatView de la conversation en cours d'appel, aucun contrôle muet/haut-parleur/raccrocher propre à l'app n'est disponible — seul l'écran système CallKit initial (sonnerie) a été montré, sans équivalent d'écran d'appel actif ensuite. L'utilisateur peut se retrouver bloqué en communication sans moyen visible de raccrocher depuis l'interface de l'app.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Déplacer le `.fullScreenCover(isPresented: callCoordinator.state != .idle) { CallView(...) }` de `ChatView.swift` vers `HomeShellView.swift` (ou `RootRouterView.swift`, qui reste monté même avant authentification) afin qu'il soit atteignable depuis n'importe quel écran de l'app, fidèle à l'indépendance de CallActivity/IncomingCallActivity côté Android.
```

```
ID : V5-F-002
PRIORITÉ : P2
DOMAINE : Architecture / navigation — badge de l'onglet Chat (TabView)
FEATURE : Le badge de messages non lus de l'onglet "Chat" ne se met pas à jour en temps réel à la réception d'un nouveau message
ANDROID SOURCE : roster/ui/Roster.java:722-740 (`addMessage`, appelée à chaque message socket entrant via `organizeAndDisplayMessage`) — ligne 738-739 : `if (getActivity() instanceof HomeActivity) { ((HomeActivity) getActivity()).refreshChatBadge(); }` ; Activity/ui/HomeActivity.java:385-389 (`refreshChatBadge` → `navigation.display()`) ; view/navigation/NavigationCompound.java:86-151 (`display()`, requête `ROSTER_URI`/`unreadCount`, met à jour le badge `navigation_chat` immédiatement).
ANDROID BEHAVIOR : Dès qu'un message arrive par socket PENDANT que l'app est au premier plan (quel que soit l'onglet affiché — Feed, Créateurs, etc.), `Roster.addMessage` déclenche `HomeActivity.refreshChatBadge()` qui recalcule et affiche immédiatement le nouveau total non-lu sur l'icône `navigation_chat` de la barre de navigation persistante.
IOS FILES : Sources/TiinverSwift/Navigation/HomeShellView.swift:53,79,168-182,272-276 (`chatUnreadCount`, `.badge(chatUnreadCount)` ligne 79, calculé UNIQUEMENT dans `refreshChatUnreadCount()` appelée une seule fois depuis `.task` ligne 170) ; Sources/TiinverSwift/Realtime/ChatRepository.swift:20,263,276 (`let chatEvents = PassthroughSubject<ChatEvent, Never>()`, `chatEvents.send(.message(meta))` à chaque nouveau message privé/groupe) — `HomeShellView` ne souscrit à `chatEvents` nulle part (grep confirmé).
IOS BEHAVIOR : `chatUnreadCount` (source du badge `.badge(chatUnreadCount)` de l'onglet Chat, HomeShellView.swift:79) n'est recalculé qu'une seule fois, au montage de `HomeShellView` (`.task` ligne 168-182). `ChatRepository.shared.chatEvents` publie pourtant bien un événement `.message(meta)` à chaque nouveau message reçu par socket (privé ligne 263, groupe ligne 276) — ce flux existe et est déjà utilisé ailleurs, mais rien dans `HomeShellView` ne s'y abonne pour rafraîchir le badge de l'onglet.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `refreshChatUnreadCount()` a été porté comme une lecture ponctuelle (fidèle au calcul SQL d'Android) mais sans reproduire le déclenchement `addMessage → refreshChatBadge()` côté réception socket — le `PassthroughSubject chatEvents` qui aurait permis ce câblage existe déjà (utilisé par `ChatViewModel`/`RosterListViewModel` pour d'autres besoins) mais n'a pas été relié à `HomeShellView`.
IMPACT : Un utilisateur qui reste sur l'onglet Accueil ou Créateurs pendant qu'un nouveau message arrive ne verra JAMAIS le badge de l'onglet Chat apparaître ou s'incrémenter tant qu'il n'a pas quitté puis remonté `HomeShellView` (relance de l'app) — contrairement à Android où le badge de la barre de navigation se met à jour à l'instant même de la réception, peu importe l'onglet affiché.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter dans `HomeShellView` un `.onReceive(ChatRepository.shared.chatEvents)` (filtré sur le cas `.message`) qui relance `refreshChatUnreadCount()`, à l'image de `Roster.addMessage → HomeActivity.refreshChatBadge()`.
```

```
ID : V5-F-003
PRIORITÉ : P3
DOMAINE : Architecture / navigation — liens profonds avant authentification
FEATURE : L'alerte d'échec de résolution d'un lien profond (utilisateur/post/groupe introuvable) reçue AVANT connexion s'affiche hors contexte APRÈS un login sans rapport
ANDROID SOURCE : partage/ShareActivity.java:232-260 (`connectToServeur`/`onResonse`, `onError` non montré ici mais référencé par les commentaires iOS comme `showDialog()` immédiat, affiché sur l'Activity `ShareActivity` elle-même, qui EST l'écran actif au moment de l'échec réseau — pas de report différé).
ANDROID BEHAVIOR : `ShareActivity` affiche son `AlertDialog` d'erreur immédiatement sur l'écran où l'utilisateur se trouve réellement au moment de l'échec (elle EST l'écran actif, lancée directement par l'intent-filter du lien), qu'un utilisateur soit connecté ou non.
IOS FILES : Sources/TiinverSwift/Navigation/DeepLinkCenter.swift:44,48-59 (`@Published var errorMessage`, `showError()`) ; Sources/TiinverSwift/Navigation/DeepLinkRouter.swift:95,104,118 (`routeToUser`/`routeToPost`/`routeToGroup` appellent `DeepLinkCenter.shared.showError()` sur échec réseau, DÉCLENCHABLES depuis `.onOpenURL` de RootRouterView.swift:66-68, donc AVANT authentification aussi) ; Sources/TiinverSwift/Navigation/HomeShellView.swift:214-221 (SEUL `.alert` lié à `deepLinks.errorMessage` dans tout le projet, grep confirmé — absent de RootRouterView.swift et AuthCoordinatorView).
IOS BEHAVIOR : Si un lien profond `user`/`post`/`group` échoue à se résoudre (réseau coupé, ressource introuvable) alors que l'utilisateur n'est PAS encore authentifié (`RootRouterView` affiche `AuthCoordinatorView`), `DeepLinkCenter.errorMessage` est renseigné mais aucune vue montée à cet instant ne l'observe. L'alerte ne s'affichera que plus tard, dès que `HomeShellView` sera montée — c'est-à-dire potentiellement APRÈS que l'utilisateur se soit connecté pour une raison totalement indépendante, lui présentant alors un message d'erreur ("Pas de connexion internet, réessayer plus tard") sans rapport apparent avec ce qu'il vient de faire (se connecter).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `DeepLinkCenter.pending` (destinations réussies) est correctement bufferisé et consommé au bon moment par `HomeShellView.task` (port explicite documenté V4-F-002), mais `errorMessage` — un second canal d'état du même singleton — n'a reçu qu'UN SEUL consommateur UI (`HomeShellView`), sans tenir compte du fait qu'il peut être déclenché AVANT que cette vue existe, contrairement à `pending` qui a explicitement été pensé pour ce cas.
IMPACT : Message d'erreur affiché au mauvais moment, dans un contexte sans rapport (juste après un login réussi), pouvant laisser croire à l'utilisateur que sa connexion vient d'échouer ou qu'un problème réseau affecte son compte alors que l'application fonctionne normalement à cet instant.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter le même `.alert` sur `deepLinks.errorMessage` au niveau de `RootRouterView` (ou `AuthCoordinatorView`), qui reste monté même avant authentification, à l'image du traitement déjà réservé à `pending`.
```

```
ID : V5-F-004
PRIORITÉ : P2
DOMAINE : Session / Déconnexion / Nettoyage local
FEATURE : Nettoyage incomplet du cache local (solde wallet, fcmId, préférences) à la déconnexion / suppression de compte
ANDROID SOURCE : manager/SessionManager.java:59-66 (clear() : `context.getSharedPreferences(PREFFERENCE_NAME, MODE_PRIVATE).edit().clear().apply()` — vide la TOTALITÉ du fichier SharedPreferences "tiinver_1995") ; back_sync/infoContract.java:106-109,134 (COINS_AMOUNT/GEMS_AMOUNT/PENDING_COINS_AMOUNT/PENDING_GEMS_AMOUNT, PREFFERENCE_NAME="tiinver_1995") ; setting/Settings.java:290-341 (TOUTES les méthodes setStringPreference/setBooleanPreference/setIntegerPreference/setFloatPreference/getXPreference utilisent ce même fichier PREFFERENCE_NAME — vérifié pour chaque helper) ; Http/transportDataBackground.java:147-181 (deleteaccount() appelle SessionManager.clear(context) après les suppressions ContentResolver).
ANDROID BEHAVIOR : Le logout ET la suppression de compte (même méthode partagée `deleteaccount()`) vident intégralement le SEUL fichier SharedPreferences de l'app — pas seulement l'identité de session (id/apiKey/username) mais aussi le solde wallet en cache (coinsAmount/gemsAmount/pendingCoinsAmount/pendingGemsAmount), le fcmId poussé au serveur, le flag USING_EMAIL, les bascules de notifications/stockage, le thème, etc. Un nouvel utilisateur qui se connecte sur le même appareil ne peut voir AUCUNE donnée résiduelle de l'utilisateur précédent dans ces préférences.
IOS FILES : Security/UserSession.swift:150-159 (clear() ne supprime que myId/profile/username/nikname/firstname/lastname/referralCode + apiKey Keychain) ; Wallet/WalletViewModel.swift:17-18 (coinsAmount/gemsAmount lus directement depuis UserSession.shared, sans appel réseau) ; Profile/ProfileViewModel.swift:113,116 (seul point qui réécrit coinsAmount/gemsAmount, après un fetch profil) ; Notifications/PushTokenRegistrar.swift:36,42 (fcmId persistant dans UserDefaults, jamais effacé) ; Storage/LocalDataPurger.swift:1-50 (purge Core Data — messages/roster/notifications/activités — mais ne mentionne ni ne touche `coinsAmount`/`gemsAmount`/`pendingCoinsAmount`/`pendingGemsAmount`/`fcmId`) ; Settings/SettingSubViews.swift:35-61 (logout()/deleteAccount() n'appellent que LocalDataPurger.purgeAll() + UserSession.shared.clear(), aucun de ces deux ne touche le solde wallet ni fcmId).
IOS BEHAVIOR : Après déconnexion ou suppression de compte, `UserSession.shared.coinsAmount`/`gemsAmount`/`pendingCoinsAmount`/`pendingGemsAmount` ainsi que la clé UserDefaults `fcmId` restent en mémoire persistée, non réinitialisés — `WalletViewModel.coinsAmount`/`gemsAmount` (Wallet/WalletViewModel.swift:17-18) continuent de lire ces valeurs résiduelles tant qu'aucun fetch profil (ProfileViewModel.swift:113,116) ne les écrase.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `UserSession.clear()` a été porté comme une purge ciblée des seuls champs d'identité de session (myId/profile/username/...), pas comme l'équivalent fidèle de `SharedPreferences.edit().clear()` qui vide TOUT le magasin de préférences côté Android — divergence de granularité non documentée (le commentaire de tête de `LocalDataPurger.swift` documente explicitement une lacune similaire pour les caches Core Data mais ne couvre pas les champs UserDefaults wallet/fcmId/préférences).
IMPACT : Sur un appareil partagé (device de test/famille) : après déconnexion d'un utilisateur A et connexion d'un utilisateur B, l'écran Wallet (`WalletView`/`WalletViewModel.coinsAmount`) peut afficher le solde en pièces/gemmes de l'utilisateur A jusqu'à ce que `ProfileViewModel` rafraîchisse le profil de B — fenêtre où une information financière erronée est montrée. Le `fcmId` de l'utilisateur précédent reste aussi en cache (pourrait être repoussé par erreur avant qu'un nouveau token ne soit obtenu).
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Étendre `UserSession.clear()` (ou `LocalDataPurger.purgeAll()`) pour réinitialiser aussi coinsAmount/gemsAmount/pendingCoinsAmount/pendingGemsAmount à 0 et supprimer la clé `fcmId` de UserDefaults, pour refléter fidèlement le `.edit().clear()` global d'Android sur le même fichier de préférences.
```

```
ID : V5-F-005
PRIORITÉ : P1
DOMAINE : Session / Déconnexion / Gestion d'erreur réseau
FEATURE : Échec réseau du logout/de la suppression de compte avalé silencieusement (try?) : purge locale totale exécutée même si le serveur n'a jamais confirmé
ANDROID SOURCE : Http/transportDataBackground.java:90-116 (le `Response.Listener` déclenche `deleteaccount()` — purge locale complète + navigation SplashActivity — UNIQUEMENT dans `onResponse` (succès HTTP) pour method="logout"/"deleteaccount" ; le `Response.ErrorListener` (`onErrorResponse`, appelé sur toute erreur réseau/HTTP) pour ces deux mêmes cas ne fait QUE `dialog.dismiss()` — aucune purge, aucune navigation, la session locale reste intacte).
ANDROID BEHAVIOR : Si la requête serveur `logout`/`deleteaccount` échoue (pas de réseau, timeout, erreur serveur), Android n'efface RIEN localement : ni SharedPreferences, ni AccountManager, ni les tables ContentResolver (messages/roster/notifications/...), et ne navigue pas vers l'écran de connexion — l'utilisateur reste connecté et peut réessayer.
IOS FILES : Settings/SettingSubViews.swift:35-51 (logout()) et :53-61 (deleteAccount()) ; Networking/APIClient.swift:128,188 (`.validate(statusCode: 200..<300)` → `APIError.transport` sur échec réseau/HTTP non-2xx).
IOS BEHAVIOR : `try? await ProfileRepository.shared.logout(userId:)` / `try? await ProfileRepository.shared.deleteAccount(userId:)` avalent silencieusement toute erreur (réseau, timeout, statut HTTP non-2xx confirmé levé par APIClient.swift), PUIS le code poursuit INCONDITIONNELLEMENT : `await LocalDataPurger.purgeAll()` (purge Core Data messages/roster/notifications/activités) + `UserSession.shared.clear()` + `NotificationCenter.default.post(name: .userDidLogout, ...)` s'exécutent même si l'appel serveur a échoué, sans afficher la moindre erreur à l'utilisateur.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage a remplacé le couple onResponse/onErrorListener d'Android par un simple `try?` qui traite "erreur réseau" et "succès" de façon identique (poursuite du flux), au lieu de conditionner la purge locale au succès de l'appel serveur comme le fait `transportDataBackground.onResponse` vs `onErrorResponse`.
IMPACT : Pour `deleteAccount()` en particulier : si la requête `deleteaccount` échoue (réseau instable, timeout 20s de l'APIClient), le compte N'EST PAS supprimé côté serveur (toutes les données y restent), mais côté iOS TOUT le cache local est quand même détruit : messages, roster, notifications, fil d'activités (Core Data) ET la session (apiKey Keychain, identifiants UserDefaults) — l'utilisateur est éjecté vers l'écran de connexion en croyant son compte supprimé, sans aucun message d'erreur (aucun texte d'erreur affiché dans `SettingAccountView`), alors que son compte existe toujours intact côté serveur et que son cache local vient d'être perdu pour rien. Pour `logout()`, impact moindre mais même divergence : une déconnexion échouée côté serveur reste malgré tout une déconnexion locale complète côté iOS, contrairement à Android qui ne change rien tant que le serveur n'a pas confirmé.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ne déclencher `LocalDataPurger.purgeAll()` + `UserSession.shared.clear()` + `.userDidLogout` que si `ProfileRepository.shared.logout/deleteAccount` a RÉELLEMENT réussi (remplacer `try?` par un `do/catch` qui affiche une erreur à l'utilisateur et n'exécute PAS la purge en cas d'échec), à l'identique du branchement onResponse/onErrorListener d'Android.
```

```
ID : V5-F-006
PRIORITÉ : P1
DOMAINE : Feed / Plein écran Home / Menu "..." 
FEATURE : Téléchargement de média absent du menu "..." du plein écran Home (présent et câblé côté Android)
ANDROID SOURCE : Activity/ui/FeedFragment.java:1246-1247 (tableau `ids`/`idContentHide` incluant `R.id.download`), 1360-1365 (branche `R.id.download` → `addingDownloadingFileToQueue`+`checkBestQualityAndDownload`), 1943-2004 (implémentation réelle du téléchargement, `DownloadManager`). `FeedFragment.java` est bien la classe du pager plein écran atteint depuis la grille Home (`HomeActivity.java:787-796`, `onArticleSelected(1,...)` → `FeedFragment.newInstance(...)`, elle-même déclenchée par `MainFragment.OnAdapterItemClicked` ligne 1108-1124).
ANDROID BEHAVIOR : Sur CHAQUE post d'autrui (masqué seulement sur ses propres posts via `idContentHide`), le menu "..." du plein écran Home affiche un item "Télécharger" réellement câblé : il télécharge la meilleure qualité vidéo disponible (sonde 720p→480p→360p) ou la photo, via `DownloadManager`, dans le dossier public de l'appareil.
IOS FILES : Sources/TiinverSwift/Feed/FeedView.swift:132-140 (le `.fullScreenCover` qui présente `FeedDetailPagerView` depuis la grille Home appelle l'initialiseur SANS `includesDownload: true`, donc `includesDownload` reste à sa valeur par défaut `false`) ; FeedView.swift:604-637 (le bloc `confirmationDialog` de `FeedDetailPagerView` ne montre le bouton "Télécharger" QUE `if includesDownload`) ; le commentaire de tête de `FeedMediaDownloader.swift:4-10` affirme explicitement que Profile est "le SEUL contexte Android où Télécharger est réellement câblé", en ne vérifiant que `MainFragment`/`FullScreenMedia`/`HashtagProfile` — sans jamais mentionner `FeedFragment.java`, qui est pourtant la classe réelle du plein écran Home.
IOS BEHAVIOR : Depuis l'écran d'accueil (grille → tap → plein écran), le menu "..." ne propose JAMAIS "Télécharger", quel que soit le post (propre ou d'autrui) — l'item est simplement absent du menu, pas désactivé.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `FeedDetailPagerView` est réutilisé par 6 écrans iOS différents avec un seul paramètre `includesDownload` global ; celui-ci n'est mis à `true` que par `ProfileView`, sur la base d'une analyse Android incomplète qui a vérifié 3 fichiers Android (grille Home, notifications/recherche, hashtag) mais a omis de vérifier `FeedFragment.java` — la classe qui gère RÉELLEMENT le plein écran atteint depuis la grille Home.
IMPACT : Un utilisateur qui ouvre n'importe quel post d'un autre utilisateur en plein écran depuis le fil d'accueil (le point d'entrée le plus fréquent de l'app) ne peut jamais télécharger ce média, alors qu'Android le permet systématiquement à cet endroit précis.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Passer `includesDownload: true` à l'appel de `FeedDetailPagerView` dans `FeedView.swift:136-139` (le `.fullScreenCover` du fil Home), au même titre que `ProfileView`.
```

```
ID : V5-F-007
PRIORITÉ : P1
DOMAINE : Feed / Plein écran Home / Signalement
FEATURE : Signalement depuis le plein écran Home envoie un signalement générique sur l'UTILISATEUR au lieu de cibler le POST précis (target_id/report_type manquants)
ANDROID SOURCE : Activity/ui/FeedFragment.java:1351-1359 (branche `report_content` : `r.putExtra("target_id", String.valueOf(mediaObjects.getId())); r.putExtra("report_type","content");` en plus de userId/username/nikname) ; report/Report.java:70-71 et 149-150 (`target_id`/`report_type` lus depuis l'Intent puis envoyés dans le `map` POST vers l'endpoint `report`).
ANDROID BEHAVIOR : Depuis le plein écran Home, un signalement envoie au backend `target_id=<id du post>` et `report_type="content"`, en plus de `userId`/`username`/`message` — le signalement cible précisément la publication consultée.
IOS FILES : Sources/TiinverSwift/Feed/FeedViewModel.swift:282-285 (`report(_:reason:)`, appelé identiquement par la grille ET par `FeedDetailPagerView`, n'utilise jamais `post.id`) ; Sources/TiinverSwift/Feed/FeedRepository.swift:328-332 (`reportUser` envoie TOUJOURS `target_id: ""`, `report_type: ""`, codé en dur, quel que soit l'appelant).
IOS BEHAVIOR : Un signalement envoyé depuis le plein écran Home (comme depuis la grille) envoie systématiquement `target_id` et `report_type` vides — le backend ne peut pas distinguer un signalement de post d'un signalement d'utilisateur générique, ni savoir quel post est visé.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le commentaire de `FeedRepository.swift:322-327` justifie les champs vides en ne citant QUE `MainFragment.OnclickMoreExpand` (la grille) comme référence Android pour CE point d'entrée précis — mais `FeedViewModel.report()` est aussi appelé depuis `FeedDetailPagerView` (plein écran), dont l'équivalent Android réel (`FeedFragment.java`) remplit bien ces deux champs. La même fonction/implémentation sert les deux contextes côté iOS alors qu'Android a deux comportements distincts selon la classe (grille vs plein écran).
IMPACT : Les signalements de contenu envoyés depuis le plein écran Home (et vraisemblablement aussi Profile/Hashtag, qui appellent la même fonction) arrivent au back-office de modération sans indication du post concerné ni du type de signalement, dégradant la capacité de modération par rapport à Android.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Faire passer `post.id` et un `report_type` ("content" en plein écran) à `FeedRepository.reportUser`/`FeedViewModel.report`, en distinguant le contexte grille (vide, fidèle à `MainFragment`) du contexte plein écran (rempli, fidèle à `FeedFragment.java`/`ProfileFeedFragment.java`/`HashtagProfile.java`).
```

```
ID : V5-F-008
PRIORITÉ : P2
DOMAINE : Feed / Grille Home / Publicités natives
FEATURE : Publicités natives absentes de la grille Home (présentes tous les 7 posts côté Android, cellule pleine largeur)
ANDROID SOURCE : Activity/adapter/ActivityAdapter.java:158-161 (`isAdPosition`, `position % ADS_ON_FEED_POST == 0`), :184-193 (`getItemViewType` → `TYPE_ITEM_ADS`), :201-212 (`AdsViewHolder`/`CustomAdsSmallView`) ; Activity/service/NativeAdsManager.java:19 (`ADS_ON_FEED_POST = 7`) ; Activity/ui/MainFragment.java:709-723 (le `SpanSizeLookup` de la grille attribue un span=2, c'est-à-dire une ligne pleine largeur, aux positions `TYPE_ITEM_ADS`).
ANDROID BEHAVIOR : Dans la grille 2 colonnes de l'accueil, une publicité native (`CustomAdsSmallView`) s'insère automatiquement tous les 7 posts, occupant une ligne entière (span=2) au milieu du flux de vignettes.
IOS FILES : Sources/TiinverSwift/Feed/FeedView.swift:96-117 (le `LazyVGrid` du fil Home itère uniquement sur `viewModel.posts` avec `FeedGridCell`, aucune insertion de cellule publicitaire) — comparer avec FeedView.swift:524-548 où `FeedAdCell`/`isAdPosition` existe mais UNIQUEMENT dans `FeedDetailPagerView` (le plein écran), pas dans la grille.
IOS BEHAVIOR : La grille Home n'affiche jamais de publicité native, quel que soit le nombre de posts chargés — seul le plein écran (après un tap) en montre.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage de `isAdPosition`/`NativeAdLoader` (`FeedAdCell`) n'a été fait que pour le pager plein écran (`ViewPagerAdapter` Android), sans équivalent pour `ActivityAdapter` (la grille), qui a pourtant sa propre logique d'insertion publicitaire indépendante côté Android.
IMPACT : Perte d'inventaire publicitaire sur l'écran le plus consulté de l'app (impact revenu), et différence visuelle constatable par l'utilisateur (grille Android interrompue par des blocs pub que la grille iOS n'a jamais).
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter une cellule publicitaire pleine largeur tous les 7 éléments dans le `LazyVGrid` de `FeedView.swift`, réutilisant `FeedAdCell`/`NativeAdLoader` déjà existants pour le plein écran.
```

```
ID : V5-F-009
PRIORITÉ : P1
DOMAINE : Feed / Pagination & pull-to-refresh
FEATURE : Rafraîchissement (pull-to-refresh) concurrent à une pagination infinie en cours produit un flux figé sur d'anciennes données (page N au lieu de la page 1) puis des doublons à la pagination suivante
ANDROID SOURCE : Activity/ui/MainFragment.java:481-489 (`loadResetData`, appelée par `HomeActivity.java:182` au nouveau tap sur l'onglet Accueil) — ne vérifie AUCUN flag `loading`/`isLoadingMore` avant de relancer `executeBackTask()` : le rafraîchissement est TOUJOURS déclenché, même si une pagination (`loadMoreData`, ligne 505-517) est en cours.
ANDROID BEHAVIOR : Un nouveau chargement (page 1, OFFSET=0) est systématiquement émis dès la demande de rafraîchissement, sans jamais être bloqué par un chargement de pagination en cours — l'ordre d'arrivée des réponses réseau peut encore créer un mélange, mais le rafraîchissement lui-même n'est jamais silencieusement annulé.
IOS FILES : Sources/TiinverSwift/Feed/FeedViewModel.swift:65-66 (`func loadNextPage() { guard !isLoading else { return } ... }`) et :126-130 (`func reset() { posts = []; offset = 0; await loadNextPage() }`) — `reset()` réutilise la MÊME fonction `loadNextPage()`, protégée par le MÊME verrou `isLoading`, que la pagination infinie déclenchée par `FeedView.swift:109-115` (`onAppear`, seuil `count-2`).
IOS BEHAVIOR : Scénario reproductible : l'utilisateur atteint le seuil de pagination (déclenche `loadNextPage()` avec l'offset courant, ex. 10, `isLoading=true`, requête réseau en vol) PUIS tire pour rafraîchir avant que cette requête ne réponde. `reset()` vide `posts` et remet `offset=0` immédiatement, puis appelle `loadNextPage()` qui retourne aussitôt sans rien faire à cause du `guard !isLoading` (toujours vrai, verrouillé par l'appel précédent). Quand la requête de pagination initiale répond enfin (données de l'ancienne page, offset 10-19), elle est ajoutée au tableau `posts` fraîchement vidé et `offset` est recalculé à partir de 0 — l'utilisateur voit alors la page 2 affichée comme si c'était un flux "rafraîchi", et la pagination suivante re-télécharge exactement les mêmes éléments (doublons), la vraie page 1 n'étant jamais récupérée.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `reset()` et `loadNextPage()` partagent le même verrou `isLoading` avec sémantique "annuler silencieusement si déjà en cours" plutôt qu'une annulation explicite de la requête en vol ou une invalidation par génération/jeton, ce qui permet à une réponse de pagination obsolète de s'appliquer à l'état fraîchement réinitialisé sans jamais relancer le vrai fetch de la page 1.
IMPACT : Après un tirage pour rafraîchir pendant un défilement rapide vers le bas (scénario d'usage courant), l'utilisateur voit un contenu incohérent (ancienne page affichée comme "actualisée") puis des publications en double lors du défilement suivant, sans aucune erreur visible — bug silencieux de cohérence des données.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Découpler le verrou de `reset()` de celui de `loadNextPage()` (ex. incrémenter un jeton de génération à chaque `reset()` et ignorer toute réponse de pagination dont le jeton est périmé), ou annuler explicitement la tâche de pagination en vol avant de lancer le rafraîchissement.
```

```
ID : V5-F-010
PRIORITÉ : P1
DOMAINE : Recherche — rendu des vignettes de résultats "Publications"
FEATURE : Sélection de l'image de vignette pour un résultat de recherche de type post
ANDROID SOURCE : Recherche/ui/UniversalSearchAdapter.java, classe PostViewHolder, méthode bind() lignes 268-290 (en particulier 270-282)
ANDROID BEHAVIOR : PostViewHolder.bind() applique un fallback simple à DEUX étages, sans branche vidéo/photo ni référence à cdn_content_id ni à object_url : `String thumbUrl = item.getThumbnail()` (= champ JSON `cdn_thumbnail_url`) → si non vide, l'utiliser ; sinon `item.getContentUrl()` (= champ JSON `cdn_content_url`) → si non vide, l'utiliser ; sinon fond gris uni. Le champ `object_url` (pourtant stocké dans SearchResultModel via setObjectUrl à RechercheTiinver.java:546) n'est JAMAIS lu par ce ViewHolder — confirmé par lecture complète de bind().
IOS FILES : Discover/SearchModels.swift, struct SearchPostResult, propriété calculée thumbnailURL lignes 114-125 ; consommée dans Discover/SearchView.swift, postGridCell() ligne 264 (`if let thumb = post.thumbnailURL`)
IOS BEHAVIOR : thumbnailURL réimplémente l'algorithme de priorité CDN utilisé ailleurs pour FeedActivity (celui du fil principal) : détermine `isVideo` via `object`, calcule `hasContentId` (cdn_content_id non nil/non "NULL"/non vide), puis : si vidéo → `hasContentId ? cdn_thumbnail_url : object_url` ; si photo → `hasContentId ? (cdn_content_url ?? object_url) : object_url`. Résultat : dès que `cdn_content_id` est absent/NULL/vide (cas explicitement anticipé par le commentaire du fichier comme fréquent, par analogie avec FeedActivity), la vignette bascule sur `object_url` au lieu de `cdn_thumbnail_url`/`cdn_content_url`, MÊME si `cdn_thumbnail_url` est renseigné et non vide.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Réutilisation par erreur de la logique CDN générique `FeedActivity`/`effectiveObjectURLString` (conçue pour un endpoint différent où `object_url` est la source de vérité) au lieu de porter fidèlement la logique RÉELLE et beaucoup plus simple de `UniversalSearchAdapter.PostViewHolder.bind()`, propre à l'endpoint `content/search`.
IMPACT : Pour tout post retourné par la recherche universelle (onglet "Tous" ou "Publications", requête ≥2 caractères) dont `cdn_content_id` est absent/NULL/vide mais dont `cdn_thumbnail_url` (ou `cdn_content_url` pour une photo) est bien renseigné, Android affiche la vignette correcte alors qu'iOS l'ignore et retombe sur `object_url` — pouvant afficher une image différente, une image obsolète, ou une case vide (placeholder gris) si `object_url` est lui-même absent. Grille de résultats "Publications" potentiellement dégradée de façon reproductible pour une partie significative des posts.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Remplacer `SearchPostResult.thumbnailURL` par le fallback fidèle à Android : `cdn_thumbnail_url` non vide → l'utiliser ; sinon `cdn_content_url` non vide → l'utiliser ; sinon nil (placeholder gris) — sans dépendre de `object_url` ni de `cdn_content_id` ni du type vidéo/photo, exactement comme UniversalSearchAdapter.java:270-282.
```

```
ID : V5-F-011
PRIORITÉ : P3
DOMAINE : Recherche — filtrage des catégories de résultats par onglet
FEATURE : Filtrage applicatif des catégories affichées (comptes/hashtags/publications) selon l'onglet actif
ANDROID SOURCE : Recherche/ui/RechercheTiinver.java, méthode parseAndDisplay(), lignes 461-573 — gardes explicites : `showUsers` (ligne 473), `showHashtags` (ligne 505), `showPosts` (ligne 528), chacune conditionnée par le paramètre `tab` REÇU EN ARGUMENT (capturé au moment de l'appel réseau), en plus (et indépendamment) de la présence de la clé JSON correspondante (`results.has("users")` etc.)
ANDROID BEHAVIOR : Même si la réponse JSON contient une clé "users"/"hashtags"/"posts" non vide, Android ne l'affiche QUE si l'onglet associé à cette requête l'autorise (ex. onglet "posts" → `showUsers=false`/`showHashtags=false` inconditionnellement, quel que soit le contenu de `results`).
IOS FILES : Discover/SearchRepository.swift, decodeResults() lignes 54-62 (ne reçoit et n'applique aucun filtre par `tab`, seulement par `isFull` pour les posts) ; Discover/SearchView.swift, corps de vue lignes 62-106 (chaque section conditionnée UNIQUEMENT par `!results.x.isEmpty`, sans référence à `tab`)
IOS BEHAVIOR : iOS affiche toute catégorie non vide présente dans `SearchResults` décodé, sans jamais vérifier qu'elle correspond à l'onglet actuellement sélectionné — la seule protection est le paramètre réseau `types=` envoyé dans l'URL de la requête (SearchRepository.swift:28).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Port incomplet de parseAndDisplay() : seule la garde `isFull` (posts) a été reportée (via V3-F-106), pas la garde par `tab` appliquée à `showUsers`/`showHashtags`/`showPosts`.
IMPACT : Si le backend ne respecte pas strictement `types=` (renvoie malgré tout une catégorie non demandée) ou si une réponse réseau en vol arrive après un changement d'onglet, Android supprime la catégorie hors-scope de l'onglet demandé au moment de la requête tandis qu'iOS l'affiche quand même — un onglet "Publications" pourrait ponctuellement afficher une section "Comptes"/"Hashtags" côté iOS sans équivalent Android. Impact dépendant du respect effectif de `types=` par le backend, non vérifiable depuis le code client seul — sévérité tenue basse en conséquence.
SUGGESTED_STATUS : CODE_PRESENT_UNVERIFIED
RECOMMANDATION : Ajouter dans decodeResults()/SearchView un filtrage explicite par `tab` (n'afficher "users" que si tab∈{all,users}, "hashtags" que si tab∈{all,hashtags}, "posts" que si isFull && tab∈{all,posts}), fidèle à parseAndDisplay().
```

```
ID : V5-F-012
PRIORITÉ : P3
DOMAINE : Recherche — debounce et changement d'onglet
FEATURE : Annulation du debounce de saisie lors d'un changement d'onglet
ANDROID SOURCE : Recherche/ui/RechercheTiinver.java, selectTab() lignes 341-350 — appelle `cancelDebounce()` avant de relancer explicitement la recherche pour le nouvel onglet
ANDROID BEHAVIOR : Un changement d'onglet ANNULE tout debounce de frappe en attente (`debounceHandler.removeCallbacks`), empêchant qu'une recherche programmée par la frappe précédente ne se déclenche redondamment après le changement d'onglet.
IOS FILES : Discover/SearchView.swift, `.onChange(of: tab) { _ in runSearch(full: true) }` ligne 46 — ne touche pas à `searchTask` (le Task de debounce créé dans `.onChange(of: query)`, lignes 133-144)
IOS BEHAVIOR : Le Task de debounce en attente (créé par la dernière frappe, `searchTask`) n'est PAS annulé lors d'un changement d'onglet ; il reste actif et se déclenche ~300 ms plus tard, appelant `runSearch(full: true)` une seconde fois avec les valeurs courantes de `query`/`tab` (lues au moment de l'exécution, donc déjà à jour) — appel réseau strictement redondant.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `runSearch(full:)` appelé directement depuis `.onChange(of: tab)` sans annuler `searchTask` au préalable (contrairement à `cancelDebounce()` côté Android).
IMPACT : Pas d'affichage erroné observé (les deux appels utilisent les mêmes paramètres à jour), mais requête réseau dupliquée à chaque changement d'onglet effectué pendant qu'un debounce de frappe est encore en vol (fenêtre de ~300 ms après la dernière frappe) — gaspillage réseau reproductible, sévérité mineure.
SUGGESTED_STATUS : CODE_PRESENT_UNVERIFIED
RECOMMANDATION : Appeler `searchTask?.cancel()` au début du handler `.onChange(of: tab)`, avant `runSearch(full: true)`, pour reproduire fidèlement `cancelDebounce()`.
```

```
ID : V5-F-013
PRIORITÉ : P1
DOMAINE : Profil
FEATURE : La grille de posts d'un profil reste vide après avoir débloqué l'utilisateur
ANDROID SOURCE : app/src/main/java/com/tiinver/uploadPerfilPhoto/UserProfile.java:1094-1145 (méthode block(), branche USER_UNBLOCKED ligne 1118-1124, appelle loadInitialData() ligne 1123) ; loadInitialData()/executeTask() lignes 687-690 et 723-727 (executeTask() gardé par `if (!isBlocked)`, donc redevient actif dès que isBlocked passe à false)
ANDROID BEHAVIOR : Quand le serveur répond "USER UNBLOCKED", Android met isBlocked=false PUIS appelle explicitement loadInitialData() → executeTask() → profileViewModel.executeBackTask(...), ce qui relance la requête de la première page de médias du profil et republie la grille immédiatement, sans que l'utilisateur ait besoin de quitter/revenir sur l'écran.
IOS FILES : Sources/TiinverSwift/Profile/ProfileViewModel.swift:144-163 (loadMorePosts(), garde `guard !isLoadingPosts, !reachedEnd, !isBlocked, ...`) et :204-212 (toggleBlock())
IOS BEHAVIOR : toggleBlock() met à jour isBlocked (true→false lors d'un déblocage) mais n'appelle QUE `if blocked { posts = [] }` — rien n'est fait quand blocked==false. Comme `posts` a été vidé au moment du blocage et qu'aucun élément n'est présent pour déclencher le `.onAppear` qui relance loadMorePosts(), la grille reste vide indéfiniment après un déblocage réussi, jusqu'à ce que l'utilisateur quitte complètement l'écran et y revienne (nouvelle instance de ProfileViewModel).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Port incomplet de UserProfile.java:1123 (`loadInitialData()`) — seul le cas "bloquer" (vider `posts`) a été porté dans `toggleBlock()`, pas le cas symétrique "débloquer" (recharger `posts`).
IMPACT : Un utilisateur qui débloque quelqu'un depuis son profil voit un écran vide (aucun post) alors que le blocage est bien levé côté serveur — donne l'impression que le profil n'a aucune publication ou que le déblocage a échoué, contrairement à Android qui republie la grille instantanément.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Dans `toggleBlock()`, ajouter un `else` (ou appel systématique) qui relance `await loadInitialPosts()` quand `blocked == false`, symétriquement au `if blocked { posts = [] }` existant.
```

```
ID : V5-F-014
PRIORITÉ : P2
DOMAINE : Profil
FEATURE : Aucune notification push envoyée à l'utilisateur suivi, ni depuis le bouton "Suivre" du profil, ni depuis la liste abonnés/abonnements
ANDROID SOURCE : app/src/main/java/com/tiinver/uploadPerfilPhoto/UserProfile.java:494-523 (bouton butSeguir, `OnFollowingSuccess` ligne 501-504 appelle `TransportData.notifyUser(v.getContext(), String.valueOf(metas.getId()))` ligne 503) ; app/src/main/java/com/tiinver/Recherche/ui/Adapter.java:135-164 (bouton labelSuivre partagé par FollowList.java — confirmé par `import com.tiinver.Recherche.ui.Adapter` dans FollowList.java — `OnFollowingSuccess` ligne 142-148 appelle `TransportData.notifyUser(...)` ligne 146) ; TransportData.java:122-127 (`notifyUser` = `POST push {"userId": id}`)
ANDROID BEHAVIOR : À CHAQUE follow réussi (que ce soit depuis le bouton "Suivre" du profil d'autrui, ou depuis une ligne de la liste abonnés/abonnements), Android déclenche un `POST push {userId: <id suivi>}` en plus du `POST follow`, ce qui déclenche côté serveur l'envoi d'une notification push à l'utilisateur qui vient d'être suivi.
IOS FILES : Sources/TiinverSwift/Profile/ProfileViewModel.swift:176-184 (follow()) et Sources/TiinverSwift/Discover/FollowListView.swift:76-84 (toggleFollow())
IOS BEHAVIOR : Les deux fonctions appellent uniquement `ProfileRepository.shared.follow(userId:followerId:)` (POST follow) et ne font ensuite aucun appel équivalent à `push`. Le mécanisme existe pourtant déjà côté iOS et est utilisé ailleurs : `FeedRepository.notifyPostAuthor(userId:)` (Sources/TiinverSwift/Feed/FeedRepository.swift:311-313) porte exactement ce même endpoint `push` et est déjà appelé pour les likes/commentaires/partages (V4-F-030), mais jamais après un follow réussi.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Port partiel du callback `OnFollowingSuccess` : seule la mise à jour du libellé du bouton ("Suivre"→"Abonné") a été portée, l'appel `TransportData.notifyUser` qui l'accompagne systématiquement côté Android n'a pas été porté, dans aucun des deux points d'entrée follow (profil, liste abonnés/abonnements).
IMPACT : Un utilisateur suivi via iOS ne reçoit jamais la notification push "quelqu'un vous suit" que ses abonnés Android reçoivent, ce qui réduit silencieusement l'engagement/la découverte pour tout compte suivi majoritairement depuis l'app iOS.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Après le succès de `repository.follow(...)` dans `ProfileViewModel.follow()` et dans `FollowListView.toggleFollow()`, appeler `try? await FeedRepository.shared.notifyPostAuthor(userId: <id de l'utilisateur suivi>)`, fidèle au fire-and-forget sans callback d'Android (`data.Post(map,"push",null)`).
```

```
ID : V5-F-015
PRIORITÉ : P3
DOMAINE : Profil
FEATURE : Aucun retour visuel en cas d'échec réseau lors d'un bloquer/débloquer
ANDROID SOURCE : app/src/main/java/com/tiinver/uploadPerfilPhoto/UserProfile.java:1133-1137 (`onError` du POST "block" : `Toast.makeText(..., getString(R.string.errorLoad), Toast.LENGTH_LONG).show()`)
ANDROID BEHAVIOR : Si la requête POST "block" échoue (réseau ou erreur serveur), Android affiche un Toast explicite ("errorLoad") informant l'utilisateur que l'action a échoué ; `isBlocked` n'est jamais modifié dans ce cas, l'état affiché reste cohérent avec l'échec.
IOS FILES : Sources/TiinverSwift/Profile/ProfileViewModel.swift:204-212 (toggleBlock())
IOS BEHAVIOR : `let blocked = (try? await repository.toggleBlock(...)) ?? isBlocked` avale silencieusement toute erreur réseau/backend (aucun `errorMessage`, aucune alerte, aucun log utilisateur) : en cas d'échec, `blocked` retombe simplement sur la valeur actuelle de `isBlocked`, donc rien ne change visuellement et l'utilisateur n'a aucune indication que son action "Bloquer"/"Débloquer" n'a pas abouti.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Pattern `try? ... ?? valeurActuelle` qui transforme toute erreur en no-op silencieux, sans jamais renseigner `errorMessage` (pourtant déjà présent et affiché ailleurs sur cet écran pour `loadProfile()`).
IMPACT : Un utilisateur qui tente de bloquer quelqu'un lors d'une coupure réseau croit l'avoir fait (aucune erreur affichée) alors que rien ne s'est produit côté serveur — il peut continuer à croire, à tort, que le blocage est actif.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Remplacer le `try?` par un `do/catch` qui, en cas d'échec, renseigne `errorMessage` (ou un état d'erreur dédié) affiché à l'écran, cohérent avec le motif déjà utilisé pour `loadProfile()` dans ce même fichier.
```

```
ID : V5-F-016
PRIORITÉ : P1
DOMAINE : Messagerie — Groupes payants (abonnement)
FEATURE : Vérification de l'état d'abonnement d'un groupe payant appelle un endpoint différent de celui d'Android — le blocage du composeur pour abonnement expiré/restreint ne se déclenche jamais
ANDROID SOURCE : app/src/main/java/com/tiinver/messagerie/ui/ChatFragmentTest.java:727-728 (checkSubcribtion) — `String url=infoContract.SERVER+"group/checksubscription2"+"/"+userId+"/"+groupId;` — endpoint avec le suffixe "2". Appelé depuis onViewCreated ligne 628 dès qu'un groupe est ouvert par un membre existant (`if (userData.isGroupMember())`).
ANDROID BEHAVIOR : Pour tout membre d'un groupe (payant ou non), Android appelle `group/checksubscription2/{userId}/{groupId}` à l'ouverture de la conversation. Si la réponse contient `error:"true"` avec `message` égal à `subscription expires.` (SUBCRIPTION_EXPIRE, infoContract.java:49) ou `Restricted access.` (RESTRICTED_ACCESS, infoContract.java:50), la barre de saisie est masquée (`block_layout.setVisibility(VISIBLE)`) et une bannière "renouveler"/"s'abonner" est insérée dans la liste de messages, empêchant l'envoi tant que l'abonnement n'est pas régularisé.
IOS FILES : Sources/TiinverSwift/Messagerie/GroupRepository.swift:345-354 (checkSubscription) ; Sources/TiinverSwift/Messagerie/ChatViewModel.swift:126-150 (checkGroupSubscription, appelé ligne 98 dans loadInitial()) ; Sources/TiinverSwift/Messagerie/ChatView.swift:51-59 (isComposerBlocked masque la barre de saisie).
IOS BEHAVIOR : `GroupRepository.checkSubscription` appelle `APIClient.shared.get("group/checksubscription/\(userId)/\(groupId)")` — SANS le suffixe "2" présent côté Android. La fonction utilise `try? await ... else { return .active }` (ligne 346-347) : tout échec réseau (404, erreur de route, etc.) fait silencieusement retourner `.active`. Résultat : `checkGroupSubscription()` ne passe jamais dans les branches `.expired`/`.restricted` (lignes 140-149), `isComposerBlocked` reste `false`, et le composeur de message N'EST JAMAIS bloqué pour un membre dont l'abonnement payant a expiré ou dont l'accès est restreint — contrairement à Android qui bloque réellement l'envoi dans ce cas.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Faute de frappe/oubli lors du portage : l'endpoint Android exact `group/checksubscription2` (avec le chiffre "2", vérifié par grep exhaustif — aucune autre occurrence dans tout le code Android) a été porté sans son suffixe numérique en `group/checksubscription`. Combiné au `try?` qui avale silencieusement l'échec réseau résultant et retombe sur l'état "actif" par défaut, le bug est invisible en usage normal (aucun crash, aucune erreur affichée).
IMPACT : Un membre d'un groupe payant dont l'abonnement a expiré (ou dont l'accès est marqué restreint côté serveur) peut continuer à lire ET à envoyer des messages sans limite sur iOS, alors qu'Android bloque explicitement la composition tant que l'utilisateur n'a pas renouvelé/payé — perte de la mécanique de monétisation pour les créateurs de groupes payants, et incohérence de comportement entre plateformes pour la même fonctionnalité payante.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Corriger l'endpoint dans GroupRepository.swift:346 en `"group/checksubscription2/\(userId)/\(groupId)"` pour retrouver le comportement exact d'Android. Envisager également de ne PAS retomber silencieusement sur `.active` en cas d'échec réseau franc (ex. distinguer un 404/erreur de route d'un simple timeout), afin qu'une régression future de ce type soit détectable plutôt que masquée.
```

```
ID : V5-F-017
PRIORITÉ : P3
DOMAINE : Messagerie — Groupes payants (information visible à tous les membres)
FEATURE : Le panneau d'information "Contenu restreint / accessible uniquement aux abonnés / prix d'abonnement" affiché dans l'écran de détail d'un groupe payant est totalement absent côté iOS
ANDROID SOURCE : app/src/main/java/com/tiinver/messagerie/group/SettingGroupMessageFragmant.java:183,190-196 (`container_static_info`, `subscrition_price_info`) ; layout app/src/main/res/layout/setting_group_message_fragment.xml:150-177 (`container_static_info`, visibility par défaut "gone", rendu visible par code) ; chaînes app/src/main/res/values-fr/strings.xml:472-475 (`Restricted_content`="🔒 Contenu restreint", `only_subscribers`="Ce groupe est accessible uniquement aux abonnés.", `subscription`="Abonnement :", `coins_per_month`="jetons/mois").
ANDROID BEHAVIOR : Dans l'écran de gestion du groupe (SettingGroupMessageFragmant, accessible à TOUT membre, pas seulement l'admin — ce bloc est en dehors de toute garde IAM_ADMIN), si `lucrative==1`, un panneau est affiché avec le cadenas "Contenu restreint", le texte "Ce groupe est accessible uniquement aux abonnés." et le prix formaté "Abonnement : {price} jetons/mois".
IOS FILES : Sources/TiinverSwift/Messagerie/GroupDetailView.swift (fichier entier, aucune référence à lucrative/price) ; les données sont pourtant disponibles via Sources/TiinverSwift/Models/RosterModel.swift:47-48 (`price`/`lucrative`) et sont bien peuplées côté serveur (Sources/TiinverSwift/Messagerie/GroupRepository.swift:62-63,103-104 `GroupInfo.rosterModel`), mais ChatView.swift:107-111 n'en transmet ni `price` ni `lucrative` à `GroupDetailView.init`.
IOS BEHAVIOR : L'écran "Infos du groupe" (GroupDetailView) ne comporte aucun panneau équivalent : aucun membre, qu'il soit admin ou non, ne voit d'indication que le groupe est payant, ni son prix, dans cet écran. La seule surface où le prix apparaît côté iOS est la bannière d'abonnement dans le fil de discussion lui-même (ChatView.swift:170,174), pas dans l'écran de détail du groupe.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Lors du portage de SettingGroupMessageFragmant.java (documenté comme lu "en entier" dans l'en-tête de GroupDetailView.swift), le bloc `container_static_info` n'a pas été repris — GroupDetailView.init() ne reçoit même pas les paramètres `price`/`lucrative` du RosterModel source alors que ceux-ci existent déjà dans le modèle.
IMPACT : Un utilisateur consultant les informations d'un groupe payant sur iOS (via l'écran dédié, pas seulement au moment de devoir payer) n'a aucun moyen d'y voir le prix de l'abonnement ou la mention "contenu restreint" — perte d'information mineure mais réelle par rapport à Android, potentiellement gênante pour un membre qui veut vérifier le tarif avant renouvellement sans revenir au fil de discussion.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter `price`/`lucrative` aux paramètres de `GroupDetailView.init`, les transmettre depuis `ChatView.swift:107-111` (`viewModel.target.price`/`.lucrative`), et rendre un panneau équivalent (cadenas + "Ce groupe est accessible uniquement aux abonnés." + prix) en tête de liste, visible à tout membre quand `lucrative==1`, à l'identique d'Android.
```

```
ID : V5-F-018
PRIORITÉ : P0
DOMAINE : Écran de conversation — liste de messages / défilement
FEATURE : Positionnement initial et auto-scroll vers le bas de la liste de messages
ANDROID SOURCE : messagerie/ui/ChatFragmentTest.java:536 (mLayoutManager.setStackFromEnd(true)) ; lignes 2678-2717 (addMessage(MessageLib) — appelé pour CHAQUE message reçu en direct (lignes 1928/1932) ET pour chaque message envoyé localement (lignes 2390, 2442, 2541, 2606) — termine systématiquement par mRecycleView.smoothScrollToPosition(mAdapter.getItemCount()-1)) ; lignes 2718-2756 (addOldMessage, même appel de scroll lors du chargement d'anciens messages).
ANDROID BEHAVIOR : Le RecyclerView est configuré en stackFromEnd=true (ancré en bas dès le premier layout, donc affiche les messages les PLUS RÉCENTS à l'ouverture d'une conversation) et re-scrolle explicitement vers la dernière position à chaque message ajouté (envoyé ou reçu), garantissant que le dernier message est toujours visible sans action de l'utilisateur.
IOS FILES : Messagerie/ChatView.swift:140-157 (var messageList — un simple SwiftUI List(ForEach(viewModel.items)) sans ScrollViewReader ni scrollTo) ; Messagerie/ChatViewModel.swift (loadInitial(), loadMore(), onIncoming(_:), appendOptimistic(_:) — aucun de ces points n'émet de signal de scroll, aucun état 'scroll to id' n'existe dans la classe).
IOS BEHAVIOR : La liste est un SwiftUI List classique, positionné par défaut en haut (premier élément = message le plus ANCIEN de la page chargée, car `items` est trié par ordre croissant de stamp — voir ChatViewModel.swift:93-96). Aucun mécanisme (ScrollViewReader/scrollTo, .onChange sur items, ancre) ne ramène la vue vers le bas ni à l'ouverture, ni après l'envoi d'un message, ni après réception d'un message en direct.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence totale de gestion de position de défilement côté SwiftUI : aucun ScrollViewReader n'a été ajouté lors du portage de ChatFragmentTest/MessageListAdapter, alors que l'équivalent Android (stackFromEnd + smoothScrollToPosition systématique) est une fonctionnalité centrale de l'écran de chat, pas un détail cosmétique.
IMPACT : Dès qu'une conversation contient plus de messages que ce qui tient à l'écran (cas normal après quelques échanges), l'utilisateur qui ouvre le chat voit les messages les plus ANCIENS de la page chargée au lieu des plus récents, et doit défiler manuellement vers le bas pour retrouver la conversation en cours. Pire : comme le tout premier item de la page (le plus ancien) est visible dès l'ouverture, son .onAppear (ChatView.swift:146-152, condition `item.id == viewModel.items.first?.id`) déclenche IMMÉDIATEMENT `loadMore()` — qui préfixe une page supplémentaire de 100 messages plus anciens, dont le nouveau premier élément redevient à son tour visible en haut, redéclenchant loadMore() en cascade. Résultat observable : à l'ouverture de toute conversation dépassant une page d'historique, l'app charge en boucle TOUT l'historique de la conversation au lieu de la page initiale de 100 messages, avant même toute interaction de l'utilisateur — surconsommation de données/CPU et lenteur d'ouverture, en plus du problème d'affichage. De plus, l'envoi d'un nouveau message (optimiste) ou la réception d'un message en direct n'amène pas non plus la vue vers le bas — le message part/arrive bien mais peut rester invisible hors du viewport actuel.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Entourer `messageList` d'un `ScrollViewReader`, scroller vers le dernier `id` de `viewModel.items` (1) juste après `loadInitial()` dans `.task`, (2) dans un `.onChange(of: viewModel.items.last?.id)` limité aux ajouts en fin de liste (nouveaux messages envoyés/reçus, pas aux préfixes de pagination), avec une garde équivalente à `belongsToCurrentUser` ou 'déjà proche du bas' si on veut respecter le confort de lecture d'un utilisateur remonté dans l'historique — mais à minima reproduire le comportement Android qui scrolle inconditionnellement, pour ne pas régresser silencieusement.
```

```
ID : V5-F-019
PRIORITÉ : P1
DOMAINE : Écran de conversation — bulle d'appel manqué
FEATURE : Rappel depuis la bulle d'appel manqué/vocal dans la conversation
ANDROID SOURCE : messagerie/ui/viewholders/MissedViewHolder.java:15-39 (onClick → construit ResultData avec object=ResultData.CALL, transmis à MessageViewItemClikedListener) ; messagerie/ui/ChatFragmentTest.java:561-563 (le listener détecte ResultData.CALL et appelle mListener.onArticleSelected(8,null)) ; messagerie/ui/ActivityMsg.java:516-518 (case 8: startCall(); — même méthode que le bouton d'appel de la barre d'outils, R.id.call, ligne 535-537).
ANDROID BEHAVIOR : Un tap sur une bulle de message 'appel manqué' (missedvoicecall) ou 'appel vocal' (voicecall) dans la conversation déclenche exactement la même action que le bouton d'appel de la barre d'outils (startCall()) : un appel sortant est immédiatement relancé vers le correspondant de la conversation.
IOS FILES : Messagerie/ChatView.swift:190-191 (`MissedCallBubbleRow(message: mlib, text: systemInfoText(for: mlib)) { }` — dernier paramètre `onTap`, fermeture vide).
IOS BEHAVIOR : `MissedCallBubbleRow` (ChatBubbleViews.swift:306-322) est un `Button` fonctionnel, câblé côté vue, mais avec un closure `onTap` totalement vide (`{ }`) au site d'appel dans ChatView.swift — le tap sur la bulle ne produit aucun effet observable, alors que le fichier lui-même possède déjà tout le nécessaire pour lancer un appel (`outgoingCallProfile` et `callCoordinator.startOutgoingCall(...)`, utilisés juste à côté pour le bouton de la barre d'outils, ChatView.swift:356-359).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Point d'entrée UI non câblé lors du portage : `MissedCallBubbleRow` a été créé et intégré dans `messageRow(_:)` mais son action de tap n'a jamais été reliée à `callCoordinator.startOutgoingCall`, alors que cette même action est déjà implémentée et fonctionnelle ailleurs dans le même fichier pour le bouton d'appel de la barre d'outils.
IMPACT : Un utilisateur qui tape sur une notification d'appel manqué dans la conversation (le geste naturel pour rappeler quelqu'un) n'obtient aucune réaction sur iOS, alors que c'est le comportement attendu et fonctionnel sur Android — perte d'une fonctionnalité de rappel rapide, régression silencieuse d'UX.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Remplacer la fermeture vide par `{ callCoordinator.startOutgoingCall(profile: outgoingCallProfile, chatType: viewModel.target.type) }` au site d'appel de `MissedCallBubbleRow` dans `ChatView.swift:190-191`, en respectant la même garde `callCoordinator.state != .idle` déjà utilisée pour le bouton de la barre d'outils afin d'éviter un double-appel concurrent.
```

```
ID : V5-F-020
PRIORITÉ : P1
DOMAINE : Socket.IO — historique de groupe (fusion REST + cache local)
FEATURE : Pagination groupe : repli REST serveur quand le cache local est épuisé (loadMoreFromServeur)
ANDROID SOURCE : ChatFragmentTest.java:985-995 (loadMoreFromServeur(), déclenché uniquement si userData.getType().equals(GROUP)) ; ChatFragmentTest.java:1415-1430 (onLoadFinished : si le CursorLoader local retourne 0 ligne pendant un 'load more', hasLocalData=false puis appel de loadMoreFromServeur()) ; ChatFragmentTest.java:203/1731 (lastDate = stamp du plus ancien message déjà chargé) ; messagerie/model/ChatViewModel.java:128-130 (délègue à chatRepository.loadMoreFromServeur) ; messagerie/repository/ChatRepository.java:1129-1177 (GET '/group/'+groupId+'/messages?lastDate='+lastDate+'&limit='+limit via TransportData, puis en cas de succès getChatManager().prepareOldGroupMessage(object,false)) ; messagerie/ui/ChatManager.java:1090-1155 (prepareOldGroupMessage : parse le tableau JSON 'data', persiste chaque message via addGroupMessage(meta,true/false), ET propage à l'UI via ChatRepository.sendLiveData(chatModel) avec ChatModel.OLDMESSAGE — donc bien un flux atteignable et propagé, pas juste stocké).
ANDROID BEHAVIOR : Quand l'utilisateur scrolle vers le haut d'une conversation de GROUPE et que le cache local (ContentProvider infoContract.MSG_URI) est épuisé (0 ligne retournée), Android bascule automatiquement sur un appel REST serveur paginé par date ('lastDate') pour continuer à charger l'historique plus ancien, l'insère en local ET met à jour la liste affichée en direct. Ce comportement est réel et atteignable (pas de code mort : tous les maillons de la chaîne s'appellent réellement les uns les autres, vérifié méthode par méthode).
IOS FILES : Sources/TiinverSwift/Messagerie/ChatViewModel.swift, fonction loadMore() (ligne ~184-195) : 'let page = try? await messages.page(conversationId:..., limit: pageSize, offset: offset, currentUsername:...); guard let page, !page.isEmpty else { return }' — puis rien d'autre.
IOS BEHAVIOR : loadMore() interroge UNIQUEMENT le cache Core Data local (MessageRepository.page). Si la page retournée est vide, la fonction retourne immédiatement sans effectuer aucun appel réseau de repli — grep exhaustif sur tout Sources/TiinverSwift/ pour 'group/*/messages', 'loadMoreFromServeur' et 'lastDate' ne retourne AUCUN résultat : cette fonctionnalité n'a aucune trace de portage, même partielle.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Fonctionnalité absente du portage : MessageRepository.page(...) ne fait que paginer localement, et aucune méthode équivalente à ChatRepository.loadMoreFromServeur (endpoint REST '/group/{id}/messages') n'existe dans GroupRepository.swift ni ailleurs dans le projet iOS.
IMPACT : Pour une conversation de groupe dont l'historique complet n'est pas (ou plus) intégralement présent dans le cache Core Data local (réinstallation de l'app, utilisateur ayant rejoint le groupe avant que cet appareil n'ait synchronisé l'ancien historique, cache purgé, etc.), le scroll vers le haut s'arrête silencieusement dès que le cache local est épuisé côté iOS, alors qu'Android continue de charger l'historique plus ancien depuis le serveur. L'utilisateur iOS perçoit la conversation comme tronquée sans indication ni possibilité de voir la suite de l'historique, contrairement à Android.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Porter ChatRepository.loadMoreFromServeur (Android) : dans ChatViewModel.loadMore(), quand la page locale Core Data est vide ET que la conversation est un groupe, appeler GET 'group/{groupId}/messages?lastDate={dateDuPlusAncienMessageChargé}&limit={pageSize}' via APIClient, décoder le tableau 'data' (avec le même motif de décodage tolérant par item déjà utilisé dans ChatRepository.decodeMessages, pas un décodage strict du tableau entier), persister chaque message via MessageRepository.addGroupMessage, puis insérer les résultats en tête de 'items' comme le fait déjà loadMore() pour la page locale.
```

```
ID : V5-F-021
PRIORITÉ : P1
DOMAINE : Notifications
FEATURE : Tap sur une notification locale iOS route toujours vers le centre de notifications, y compris pour les messages de chat
ANDROID SOURCE : back_sync/NotificationUtils.java:290-338 (displayNoMessageNotification) et :103-153 (displayNotificationOrPushMessage) : les deux construisent la destination via `String destination = "MainActivity";` (ligne 302 et 114) puis `show()` (ligne 342) fait `new Intent(mContext, activityMap.get(destination))` où `activityMap.put("MainActivity", SplashActivity.class)` (NotificationUtils.java:94) — donc le tap ouvre l'écran d'accueil générique (Splash/Home), jamais un écran de liste de notifications dédié.
ANDROID BEHAVIOR : Tap sur N'IMPORTE QUELLE notification système (activité comme like/comment/follow OU message de chat) ouvre SplashActivity/HomeActivity (écran d'accueil générique), pas un centre de notifications.
IOS FILES : App/AppDelegate.swift:153-163 (userNotificationCenter(_:didReceive:)) ; Navigation/HomeShellView.swift:281-286 (handleDeepLink, case .notifications: showNotifications = true) ; Realtime/ChatRepository.swift:317-341 (chatMessageNotificationContent utilisé pour les messages de chat, sans categoryIdentifier distinct)
IOS BEHAVIOR : `didReceive response` appelle systématiquement `DeepLinkCenter.shared.route(.notifications)` quel que soit le type de notification tapée (y compris les notifications de MESSAGE DE CHAT construites par `LocalNotificationBuilder.chatMessageNotificationContent`/ChatRepository.swift:341, qui n'ont pas de categoryIdentifier distinct), ce qui ouvre la sheet `NotificationsListView` — un écran qui ne contient AUCUNE trace des messages de chat (seulement les entités `NotiEntity` issues de `notification2/{userId}`).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le commentaire de justification dans AppDelegate.swift (lignes 148-151) affirme que ce comportement est "comme le fait activityMap.get('MainActivity') par défaut côté Android" — mais `activityMap.get("MainActivity")` mappe vers SplashActivity (écran d'accueil), pas vers un centre de notifications. La confusion entre "écran d'accueil par défaut" et "centre de notifications" a fait dériver l'implémentation iOS.
IMPACT : Un utilisateur qui reçoit une notification de nouveau message de chat et tape dessus se retrouve projeté dans une liste de likes/commentaires/follows sans aucun rapport avec le message reçu, au lieu d'atterrir sur l'écran d'accueil (comportement Android, déjà imparfait mais au moins neutre).
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Router vers l'accueil (TabView, onglet 0) par défaut pour les notifications de type chat/inconnues, et réserver `.notifications` (ouverture de la sheet) aux seules notifications d'activité (like/comment/follow/etc.), en s'appuyant sur `categoryIdentifier` pour distinguer les deux familles au moment de la construction du contenu.
```

```
ID : V5-F-022
PRIORITÉ : P1
DOMAINE : Notifications
FEATURE : Bouton "Suivre en Retour" du centre de notifications appelle un endpoint backend différent d'Android
ANDROID SOURCE : NotiLikecmt/AdapterNoti.java:420-441 (FollowVH.bind, `td.Post(map, "followback", ...)`) — SEUL appelant de l'endpoint `followback` dans tout le code Android. À comparer avec Http/TransportData.java:1428-1430 (`Following()` → `volleyPost(..., "follow")`), utilisé lui par NotiLikecmt/AdapterNoti.java:511 dans SuggestionVH (la ligne "suggestions de comptes", pas la ligne "follow-back").
ANDROID BEHAVIOR : Le bouton de follow-back affiché sur une notification `verb=="follow"` (dans le centre de notifications) poste sur l'endpoint `followback`, distinct de l'endpoint générique `follow` utilisé partout ailleurs (profil, suggestions).
IOS FILES : Notifications/NotificationsListView.swift:135-146 (bouton "Suivre en Retour", appelle `ProfileRepository.shared.follow(...)`) ; Profile/ProfileRepository.swift:88-90 (`func follow` poste sur endpoint "follow")
IOS BEHAVIOR : Le même bouton "Suivre en Retour" côté iOS réutilise `ProfileRepository.follow()`, qui poste sur l'endpoint générique `follow` — jamais `followback`.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage a réutilisé le repository de follow générique déjà existant (module Profil) au lieu de reproduire l'appel réseau spécifique du `FollowVH` Android, qui cible délibérément un endpoint backend différent pour ce cas précis.
IMPACT : Si le backend traite `followback` différemment de `follow` (ex. suppression d'une entrée "vous devriez suivre en retour" côté serveur, notification spécifique à l'autre utilisateur, comptabilisation différente), l'action de follow-back depuis le centre de notifications iOS peut réussir en apparence côté client (follow effectif) tout en laissant un état serveur incohérent avec ce qu'Android produit pour la même action utilisateur.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ajouter une méthode dédiée (ex. `ProfileRepository.followBack`) postant sur l'endpoint `followback` avec les mêmes paramètres `{userId, followId}`, et l'utiliser spécifiquement depuis `NotificationsListView`'s bouton "Suivre en Retour", en laissant `follow()` pour les autres points d'entrée (profil, suggestions).
```

```
ID : V5-F-023
PRIORITÉ : P1
DOMAINE : Notifications
FEATURE : Centre de notifications iOS : aucun moyen d'ouvrir la publication concernée pour une notification sans vignette (like/commentaire sur un post texte)
ANDROID SOURCE : NotiLikecmt/AdapterNoti.java:612-625 (bindBodyClick, attaché au conteneur `body` = titre/texte) et :586-600 (bindAvatarClick, attaché SEULEMENT à `contentAvatar`) — deux zones tapables DISTINCTES avec deux destinations différentes (`body`→FullScreenMedia si `activityId>0`, `contentAvatar`→UserProfile), indépendamment de la présence d'une vignette (bindThumb, :564-584, peut masquer complètement le conteneur photo sans désactiver le clic sur `body`).
ANDROID BEHAVIOR : Sur un like/commentaire concernant un post texte (sans photo/vidéo, donc sans vignette affichée), l'utilisateur peut quand même taper sur le TEXTE de la ligne de notification pour ouvrir le post visé (FullScreenMedia), tant que `activityId>0`.
IOS FILES : Notifications/NotificationsListView.swift:108-124 (NavigationLink unique enveloppant avatar+nom+bodyText → ProfileView) et :152-160 (Button distinct, uniquement si `thumbnailURL != nil`, → onOpenPost)
IOS BEHAVIOR : Le bloc avatar+nom+texte est un SEUL `NavigationLink` qui va toujours vers `ProfileView` (jamais vers le post). Le seul moyen d'atteindre le post est le bouton vignette séparé, qui n'existe QUE si `thumbnailURL` est non-nil (dérivé de `cdnThumbnailUrl`/`cdnContentUrl`/`objectUrl`) — absent pour un post texte.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage a fusionné les deux zones tapables Android (avatar→profil, corps→post) en une seule (avatar+texte→profil), et n'a conservé l'accès au post que via la vignette, qui n'est pas toujours présente.
IMPACT : Pour toute notification like/commentaire sur une publication sans image/vidéo (texte, sondage, etc.), l'utilisateur iOS ne peut PAS accéder au post concerné depuis le centre de notifications — alors qu'Android le permet en tapant le texte de la ligne.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Séparer la zone tapable en deux comme Android : un tap sur l'avatar seul ouvre le profil, un tap sur le bloc nom/texte ouvre le post (reconstructedPost) quand `noti.activityId > 0`, indépendamment de la présence d'une vignette.
```

```
ID : V5-F-024
PRIORITÉ : P2
DOMAINE : Notifications
FEATURE : Notification de type cadeau (comment payload_type==gift) affiche un identifiant brut au lieu de l'emoji + nom du cadeau, dans le centre de notifications in-app
ANDROID SOURCE : NotiLikecmt/AdapterNoti.java:219-224 (getItemViewType route payload_type=="gift" vers TYPE_GIFT) et :361-392 (GiftVH.bind, résout `e.commentText` via `GiftCatalogHelper.getEmojiForStringId` + lookup de ressource, affiche "{nom} vous a envoyé un cadeau {emoji} {nomCadeau}")
ANDROID BEHAVIOR : Une notification de commentaire dont `payload_type=="gift"` est affichée avec une ligne dédiée (TYPE_GIFT) montrant l'emoji et le nom lisible du cadeau, jamais l'identifiant interne brut.
IOS FILES : Notifications/NotificationsListView.swift:91-100 (`bodyText`, switch sur `noti.verb` uniquement — case "comment" ne teste jamais `noti.payloadType`)
IOS BEHAVIOR : Pour la même notification, `bodyText` retombe sur le cas générique "comment" : `noti.commentText` est affiché tel quel entre guillemets français ("a commenté : « gift_xxx »"), montrant l'identifiant interne du cadeau au lieu de l'emoji/nom — alors que la notification PUSH système équivalente (`LocalNotificationBuilder.activityNotificationContent`, Notifications/LocalNotificationBuilder.swift:45-60) gère déjà correctement ce même cas via `GiftCatalog`.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le switch de `NotificationRow.bodyText` (liste in-app) ne reprend que le mapping par `verb`, sans reproduire la vérification `payloadType=="gift"` déjà faite (et documentée comme portée) dans `LocalNotificationBuilder` du même module.
IMPACT : Chaque notification de cadeau reçu en commentaire affiche un texte incompréhensible pour l'utilisateur dans le centre de notifications (ex. « gift_rose_23 » au lieu de « 🌹 Rose »), alors que la notification push correspondante affiche le bon texte.
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Réutiliser `LocalNotificationBuilder`'s logique de résolution gift (ou `GiftCatalog` directement) dans `NotificationRow.bodyText` quand `noti.verb == "comment" && noti.payloadType == "gift"`.
```

```
ID : V5-F-025
PRIORITÉ : P2
DOMAINE : Notifications
FEATURE : Notification de transfert de coins (verb==transfert) n'affiche pas le montant transféré dans le centre de notifications in-app
ANDROID SOURCE : NotiLikecmt/AdapterNoti.java:530-540 (TransferVH.bind : `String.format("%s %s %s << %s >>", fullName, transferred_you, e.commentText, coins)` — `e.commentText` porte le MONTANT, documenté explicitement dans models/notification/NotiEntity.java:26 : `commentText; // texte | "gift_diamond_name" | montant`)
ANDROID BEHAVIOR : La ligne de notification affiche le montant exact transféré, ex. "Jean vous a transféré 50 « pièces »".
IOS FILES : Notifications/NotificationsListView.swift:96 (`case "transfert": return "vous a transféré des coins"`)
IOS BEHAVIOR : Le texte est générique et n'inclut jamais le montant (`noti.commentText` n'est pas lu dans ce cas), contrairement à la notification PUSH système équivalente (LocalNotificationBuilder.swift:63-64, `payload.object`) qui, elle, inclut au moins une valeur (bien que tirée d'un champ différent, `object` plutôt que `commentText`, cf. incohérence déjà présente côté Android entre push et liste).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le switch de `bodyText` n'a pas repris le champ `commentText` pour le cas "transfert", perdant l'information de montant présente dans `NotiEntity`.
IMPACT : L'utilisateur ne voit jamais combien de coins lui ont été transférés en consultant le centre de notifications, seulement qu'un transfert a eu lieu.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Utiliser `noti.commentText` (le montant) dans le texte affiché pour `verb=="transfert"`, à l'identique d'Android (TransferVH).
```

```
ID : V5-F-026
PRIORITÉ : P2
DOMAINE : Notifications
FEATURE : Notification locale de rappel de mise à jour (`notifyUpdate`) jamais portée côté iOS, alors que reproductible et déclenchée en pratique
ANDROID SOURCE : service/TiinverSyncWorker.java:75-88 (`visiteServeur`, condition `currentTime > lastTime - 604800` où `lastTime` dérive de `infoContract.EXPIRE_DAY/MONTH/YEAR`) ; back_sync/infoContract.java:77-79 (`EXPIRE_DAY=0, EXPIRE_MONTH=0, EXPIRE_YEAR=0`, les valeurs réelles étant commentées lignes 73-75) ; back_sync/NotificationUtils.java:516-586 (`requestUpdate`, construit et poste une notification "Mise à jour"/"update_msg")
ANDROID BEHAVIOR : `TiinverSyncWorker.visiteServeur` est exécuté à chaque réception FCM (via `MyFirebaseMessagingService.onMessageReceived`, qui enqueue TOUJOURS ce worker, back_sync/MyFirebaseMessagingService.java:103-119). Avec `EXPIRE_DAY/MONTH/YEAR` remis à 0 (valeurs réelles commentées), la condition temporelle est quasi-systématiquement vraie, donc `notifyUpdate` poste une notification système "Mise à jour" à (quasi) chaque sync déclenchée par push — un type de notification locale réellement montré à l'utilisateur Android.
IOS FILES : Notifications/LocalNotificationBuilder.swift:1-24 (en-tête de fichier énumérant explicitement ce qui est porté/non porté — `notifyUpdate`/`requestUpdate` n'y figure ni dans la liste "portés" ni dans la liste "volontairement pas portés")
IOS BEHAVIOR : Aucun code iOS ne construit ni ne présente de notification locale "Mise à jour disponible" en réponse à la synchro déclenchée par push (`AppDelegate.didReceiveRemoteNotification` n'appelle que `NotificationCenterViewModel.fetchNotifications`, jamais un équivalent de `notifyUpdate`).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage du module Notifications s'est concentré sur `displayNoMessageNotification`/`displayNotificationOrPushMessage` (documentés explicitement) et a omis `NotificationUtils.requestUpdate`/`MyFirebaseMessagingService.notifyUpdate`, jamais mentionné même dans la liste "volontairement pas porté" du fichier de portage.
IMPACT : Les utilisateurs Android reçoivent périodiquement (à chaque sync déclenchée par push, vu la mauvaise configuration des constantes EXPIRE_*) une notification système "Mise à jour" ; les utilisateurs iOS n'en voient jamais l'équivalent — divergence de contenu notifié, même si son origine côté Android tient elle-même d'une configuration probablement non-intentionnelle (constantes à 0).
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Décider explicitement (documenter) si ce comportement Android est un bug de configuration à ne pas reproduire, ou porter un équivalent minimal ; dans tous les cas, l'absence actuelle n'est pour l'instant pas documentée comme un choix délibéré dans LocalNotificationBuilder.swift.
```

```
ID : V5-F-027
PRIORITÉ : P3
DOMAINE : Notifications
FEATURE : Notifications de réponse à un commentaire ("reply"/"reply_on_my_post") non différenciées dans le centre de notifications iOS
ANDROID SOURCE : NotiLikecmt/AdapterNoti.java:219-224 (payload `type=="reply"` ou `"reply_on_my_post"` → TYPE_REPLY) et :301-327 (CommentVH.bind, switch sur `type` : "a répondu à votre commentaire « ... »" vs "a répondu à votre publication" vs générique "a commenté...")
ANDROID BEHAVIOR : Le texte affiché distingue trois cas pour une notification de type commentaire : commentaire normal, réponse à un commentaire, réponse à une publication — avec un libellé différent pour chacun.
IOS FILES : Notifications/NotificationsListView.swift:91-100 (`bodyText`, case "comment" unique, ne lit jamais `noti.type`) ; NotificationCenterViewModel.swift:79 (`row.type` bien décodé et stocké, mais jamais consulté ensuite dans l'UI de liste)
IOS BEHAVIOR : Toute notification `verb=="comment"` affiche le même texte générique "a commenté : « ... »" ou "a commenté votre publication", quel que soit `noti.type`.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le champ `type` est décodé et persisté (Core Data) mais son utilisation dans le texte de la liste n'a pas été reprise du switch Android correspondant.
IMPACT : Perte d'une nuance d'information (réponse à un commentaire vs commentaire direct vs réponse à la publication) visible côté Android, sans conséquence fonctionnelle bloquante.
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Ajouter la même distinction par `noti.type` dans `bodyText` (case "comment") qu'Android (CommentVH.bind).
```

```
ID : V5-F-028
PRIORITÉ : P3
DOMAINE : Notifications
FEATURE : Boutons d'action rapide ("Quitter"/"Répondre") des notifications système Android absents côté iOS
ANDROID SOURCE : back_sync/NotificationUtils.java:342-381 (`show()`, ajoute systématiquement deux `addAction` — R.string.quitter et R.string.repondre — sur TOUTE notification d'activité construite via `displayNoMessageNotification`/`displayNotification`)
ANDROID BEHAVIOR : Chaque notification d'activité système Android affiche deux boutons d'action dans le tiroir de notifications (bien que les deux pointent vers le même PendingIntent que le tap sur la notification elle-même — aucune action réellement distincte).
IOS FILES : Notifications/LocalNotificationBuilder.swift:36-76 (`activityNotificationContent`, ne définit jamais de `categoryIdentifier` avec des `UNNotificationAction` associées, sauf `missed_call` sans catégorie enregistrée)
IOS BEHAVIOR : Aucune notification locale iOS n'expose de bouton d'action rapide ; `UNUserNotificationCenter.current().setNotificationCategories(...)` n'est appelé nulle part dans le projet (confirmé par recherche exhaustive).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence de portage de la présentation visuelle des actions de notification (les deux boutons Android n'ayant de toute façon aucun comportement distinct du tap simple, ceci a probablement été jugé non prioritaire).
IMPACT : Différence purement visuelle dans le tiroir de notifications système ; impact fonctionnel nul puisque les deux actions Android sont déjà des no-op fonctionnels (même PendingIntent que le tap).
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Impact faible — à ne traiter qu'après les gaps fonctionnels ci-dessus ; si traité, enregistrer une `UNNotificationCategory` avec deux `UNNotificationAction` factices reproduisant le même no-op.
```

```
ID : V5-F-029
PRIORITÉ : P1
DOMAINE : Appels audio/vidéo WebRTC — signalisation / historique de conversation
FEATURE : Appel sortant vers un correspondant occupé (BUSY_CALL) : aucun message "appel manqué" enregistré côté iOS
ANDROID SOURCE : messagerie/ui/call/CallActivity.java:85 (isCalleMissedCall=true à l'init), 483-500 (callBusy: affiche "Occupé" 3s puis initEndCall(false)), 376-384 (initEndCall appelle endCall()), 509-525 (endCall(): if(isCalleMissedCall) callService.notifyMissedCall(...) — JAMAIS mis à false dans le chemin callBusy, contrairement à callEnd() ligne 476 et onAccepCall() ligne 506) ; messagerie/repository/ChatRepository.java:1045-1057 (notifyMissedCall insère un vrai message "missedvoicecall" persistant via updateMessage/sendPrivateMessage)
ANDROID BEHAVIOR : Quand l'appelant reçoit BUSY_CALL (le correspondant est déjà en communication), l'app affiche "Occupé" pendant 3s PUIS termine l'appel via endCall(). Comme isCalleMissedCall n'est réinitialisé à false QUE dans callEnd()/onAccepCall() (jamais dans callBusy()), endCall() trouve isCalleMissedCall toujours à true et appelle callService.notifyMissedCall(...), qui insère un message "missedvoicecall" persistant dans la conversation (visible dans l'historique de chat).
IOS FILES : Calls/CallCoordinator.swift:111-112 (case .busyCall: endCallFromRemote(reason: .unanswered)) ; 326-330 (endCallFromRemote: callKit.reportCallEnded + teardown(), aucun appel à chatRepository.notifyMissedCall) ; 403-413 (performEndCall: SEUL point d'appel de notifyMissedCall, uniquement sur raccroché LOCAL d'un appel sortant non répondu, jamais sur réception .busyCall)
IOS BEHAVIOR : À la réception de .busyCall, CallCoordinator appelle endCallFromRemote(reason: .unanswered) qui se contente de callKit.reportCallEnded(...) puis teardown() — aucune de ces deux fonctions n'appelle jamais chatRepository.notifyMissedCall. L'appel se termine sans laisser de trace dans la conversation.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le port de la fin d'appel a été factorisé en un point de sortie unique (teardown()/endCallFromRemote()) qui ne reproduit pas la logique "isCalleMissedCall reste true seulement si callBusy" d'Android — endCallFromRemote() ne déclenche jamais notifyMissedCall, quel que soit le CXCallEndedReason (y compris .unanswered pour le cas occupé).
IMPACT : Quand l'appelant iOS appelle quelqu'un déjà en communication, l'appel se termine silencieusement (CallKit affiche juste la fin d'appel) sans laisser AUCUNE trace dans la conversation — alors qu'Android insère un message "appel manqué" persistant et visible dans l'historique de chat. L'utilisateur iOS n'a donc aucune preuve dans le fil de discussion qu'il a tenté d'appeler.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Dans CallCoordinator.handle(.busyCall), avant d'appeler endCallFromRemote(reason: .unanswered), appeler chatRepository.notifyMissedCall(profile:chatType:object:"missedvoicecall":messageId:) comme le fait déjà performEndCall pour le raccroché local non répondu — reproduire fidèlement la condition Android "isCalleMissedCall encore true à ce moment" (c'est-à-dire : appel sortant, jamais accepté ni terminé par le correspondant, terminé par occupation).
```

```
ID : V5-F-030
PRIORITÉ : P2
DOMAINE : Appels audio/vidéo WebRTC — signalisation de l'appel entrant (événement socket brut)
FEATURE : Événement socket ROOM.CALL ("call") reçu alors qu'aucun appel n'est en cours : n'établit jamais d'appel entrant côté iOS
ANDROID SOURCE : messagerie/repository/ChatRepository.java:452-469 (Emitter.Listener onCall, enregistré sur ROOM.CALL ligne 247): if (!CallService.isOnCall) { lunchcall(gson.fromJson(args[0].toString(), Profile.class)); } else { ...CallModel.ONCALL... } — lunchcall() (ligne 436-446) démarre réellement CallService avec CallModel.INCOMINGCALL, ce qui affiche IncomingCallActivity et la notification d'appel entrant
ANDROID BEHAVIOR : Si le serveur émet l'événement socket brut ROOM.CALL alors que le client Android n'est PAS déjà en communication, le client lance immédiatement CallService en mode INCOMINGCALL — sonnerie, notification, IncomingCallActivity affichée, exactement comme pour un message "voicecall" classique.
IOS FILES : Realtime/ChatRepository.swift:142 (socket.on(SocketEvent.call) { ... handleIncomingCall(data) }), 388-398 (private func handleIncomingCall(_ data:): les deux branches if !Self.isOnCall / else exécutent EXACTEMENT le même code — callEvents.send(.onCall(data:)) — aucune branche n'appelle CallCoordinator.handleIncomingCall) ; Calls/CallCoordinator.swift:90-102 (case .onCall: guard ... callUUID != nil ... else { return } — si callUUID est nil, c'est-à-dire si aucun appel n'est déjà en cours, la fonction ne fait RIEN)
IOS BEHAVIOR : handleIncomingCall(_:) publie inconditionnellement .onCall quel que soit isOnCall. CallCoordinator.handle(.onCall) exige callUUID != nil pour agir (réponse "occupé") ; si aucun appel n'est en cours, callUUID est nil et la fonction retourne sans rien faire — aucun CXProvider.reportNewIncomingCall n'est jamais déclenché pour cet événement.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le port de ChatRepository.handleIncomingCall(_:) pour ROOM.CALL a été délibérément simplifié (voir commentaire CallCoordinator.swift:93-100) sur l'hypothèse que le client Android n'émet lui-même jamais cet événement — mais rien ne garantit que le SERVEUR ne l'émet jamais indépendamment, et le code Android réel (listener socket live, pas mort) réagit pleinement à sa réception en établissant l'appel entrant complet quand isOnCall est faux.
IMPACT : Si le serveur émet un jour ROOM.CALL (indépendamment du message "voicecall") pour notifier un appel entrant alors que l'utilisateur iOS n'est pas déjà en communication, celui-ci ne recevra AUCUNE notification CallKit, AUCUNE sonnerie — l'appel entrant est silencieusement ignoré, alors qu'Android l'établirait normalement.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Faire diverger les deux branches de ChatRepository.handleIncomingCall(_:) comme sur Android : quand !Self.isOnCall, décoder le profil et appeler CallCoordinator.shared.handleIncomingCall(profile:chatType:) (comme le fait déjà handleNewMessage pour "voicecall") au lieu de toujours publier .onCall ; conserver .onCall uniquement pour la branche isOnCall==true (détection d'occupation).
```

```
ID : V5-F-031
PRIORITÉ : P0
DOMAINE : Wallet — crédit récompense pub (rewardedCoins)
FEATURE : Échec applicatif de rewardedCoins traité comme un succès → perte définitive et silencieuse du gain en attente
ANDROID SOURCE : wallet/WalletRepository.java:301-328 (updateToServer) et wallet/EarnCoinsActivity.java:342-399 (updateToServer/updateGemsToServer) ; Http/TransportData.java:615-641 (méthode Post: `error=response.getString(ERROR)`, si différent de "false" alors `callBack.onError(message)` est appelé AVANT tout crédit local)
ANDROID BEHAVIOR : Le champ "coins" envoyé à l'endpoint `rewardedCoins` est un DELTA (`pendingCoinCount + currenGainCoins`). Si le serveur répond avec un corps applicatif d'erreur (`error` ≠ "false", HTTP 200 quand même — c'est le contrat vérifié dans `TransportData.Post`), Android appelle `callBack.onError(message)` et NON `onResonse` : `pendingCoinCount` N'EST JAMAIS remis à 0, il est même incrémenté du gain courant (`pendingCoinCount+=currenGainCoins`) pour être réessayé au prochain crédit — le gain n'est donc jamais perdu tant qu'un crédit finit par réussir.
IOS FILES : Sources/TiinverSwift/Wallet/WalletRepository.swift:93-96 (creditReward) ; Sources/TiinverSwift/Networking/APIClient.swift:166-202 (request: seule `.validate(statusCode: 200..<300)` est vérifiée, le champ JSON "error" n'est JAMAIS inspecté) ; appelants : Sources/TiinverSwift/Wallet/EarnCoinsView.swift:76-99 (onRewardEarned), WithdrawView.swift:173-185, TransferCoinsView.swift:103-115, ConversionView.swift:64-76 (showRewardedInterstitialAfterSuccess, motif identique dans les 4 fichiers)
IOS BEHAVIOR : `WalletRepository.creditReward` fait `_ = try await APIClient.shared.post(params, endpoint: "rewardedCoins")` sans jamais vérifier `value.isBackendSuccess` (contrairement à la quasi-totalité des autres repositories du projet — `FeedRepository`, `GroupRepository`, `CertificationModels`, etc. — qui font tous `guard value.isBackendSuccess else { throw ... }` après un POST/GET). Tant que le serveur répond avec un code HTTP 2xx, l'appel ne lève JAMAIS d'exception, MÊME si le corps JSON contient `{"error":"true","message":"..."}`. Le code appelant exécute alors inconditionnellement `UserSession.shared.pendingCoinsAmount = 0` (ou `pendingGemsAmount = 0`) dans la branche `do`, alors que le serveur a en réalité REJETÉ le crédit. Le gain optimiste déjà ajouté à `coinsAmount`/`gemsAmount` (ligne précédente, avant même l'appel réseau) reste affiché à l'utilisateur, mais le serveur ne l'a jamais enregistré, et comme `pendingCoinsAmount` vient d'être remis à 0, il n'y a plus JAMAIS de nouvelle tentative — le solde affiché diverge silencieusement et définitivement du solde serveur réel.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `APIClient.request()` ne lit que le status code HTTP et jamais le champ applicatif "error" du corps JSON (confirmé en lisant `APIClient.swift` en entier — `JSONValue.isBackendSuccess`/`errorFieldNormalized` existent et sont utilisés ailleurs dans le projet, par ex. `WalletRepository.referralTotal`/`refreshBalance` juste en dessous dans le même fichier, mais PAS dans `creditReward`). Le pattern `guard value.isBackendSuccess else { throw ... }` documenté et appliqué systématiquement ailleurs (Feed, Groupes, Certification, Boost, Profil) est absent spécifiquement sur cet appel Wallet.
IMPACT : Un rejet serveur du crédit de récompense pub (fraude anti-abus, limite quotidienne, session expirée, etc.) — un scénario réel puisque c'est exactement pour cela que le mécanisme `pendingCoinCount`/retry existe côté Android — se traduit sur iOS par : (1) un solde local `coinsAmount`/`gemsAmount` gonflé qui ne correspond plus au solde serveur, (2) aucune tentative de nouvelle synchronisation car `pendingCoinsAmount` est remis à 0 à tort, (3) aucun message d'erreur affiché à l'utilisateur — la récompense est perdue en silence côté serveur tout en restant visible côté client.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Dans `WalletRepository.creditReward`, vérifier `response.isBackendSuccess` après le POST et lever une erreur (`throw JSONError.typeMismatch(response.backendErrorMessage ?? "rewardedCoins")`) si `error` ≠ "false", exactement comme le fait `TransportData.Post` côté Android avant d'invoquer `onError`. Cela restaure la sémantique retry de `pendingCoinsAmount`/`pendingGemsAmount` dans les 4 appelants (`EarnCoinsView`, `WithdrawView`, `TransferCoinsView`, `ConversionView`) qui l'attendent déjà correctement via leur bloc `catch`.
```

```
ID : V5-F-032
PRIORITÉ : P0
DOMAINE : Wallet — retrait / transfert / conversion
FEATURE : Rejet applicatif du serveur (retrait/transfert/conversion) affiché comme un succès à l'utilisateur
ANDROID SOURCE : wallet/WithdrawActivity.java:151-157 (le message d'erreur `WITHDRAWAL_THRESHOLD_EXCEEDED` est explicitement testé et mappé sur un libellé dédié `R.string.withdrawal_threshold_exceeded`, preuve que ce chemin d'erreur applicatif HTTP-200 est réellement emprunté en production) ; wallet/WalletRepository.java:130-243 (submitWithdrawalRequest/convert/submitWithdrawalByCrypto — chacun via `td.Post`/`td.postToVPS` → callback `onError(message)` déclenché par le champ JSON "error") ; wallet/TransfertCoinsActivity.java:128-150 (transfert → callback onError distinct de onResonse) ; Http/TransportData.java:615-641
ANDROID BEHAVIOR : Pour ces 4 flux (retrait mobile money, retrait crypto, conversion, transfert P2P), Android n'affiche le message de succès (et ne lance la pub "rewarded interstitial" post-succès) QUE dans la branche `onResonse`/`Result.SUCCESS`, atteinte uniquement quand le corps JSON contient `error=="false"`. Toute réponse HTTP 200 avec `error` différent de "false" (ex. seuil de retrait dépassé côté serveur) déclenche `onError(message)` → `Result.ERROR` → un message d'erreur dédié est affiché, le bouton reste actif pour réessayer, ET (pour le transfert) le solde local n'est PAS déduit.
IOS FILES : Sources/TiinverSwift/Wallet/WalletRepository.swift:52-62 (submitWithdrawalRequest), 66-76 (submitWithdrawalByCrypto), 80-86 (convert), 117-120 (transferCoins) ; Sources/TiinverSwift/Wallet/WithdrawView.swift:139-153 (submit), Sources/TiinverSwift/Wallet/TransferCoinsView.swift:83-93 (transfer), Sources/TiinverSwift/Wallet/ConversionView.swift:47-55 (convert)
IOS BEHAVIOR : Les 4 méthodes de `WalletRepository` (`submitWithdrawalRequest`, `submitWithdrawalByCrypto`, `convert`, `transferCoins`) exécutent `_ = try await APIClient.shared.post(...)` puis retournent SANS jamais vérifier `isBackendSuccess`. Tant que la requête HTTP réussit (2xx), la fonction ne lève jamais, donc les vues appelantes (`WithdrawView.submit`, `TransferCoinsView.transfer`, `ConversionView.convert`) entrent systématiquement dans leur branche `do` de succès : `didSubmit = true` (alerte "Retrait envoyé"), `UserSession.shared.coinsAmount -= amount` (déduction locale du transfert), `resultMessage = "Envoyé avec succès"` — MÊME si le serveur a répondu `{"error":"true","message":"WITHDRAWAL_THRESHOLD_EXCEEDED"}` (ou tout autre rejet applicatif). Le bloc `catch` (seul endroit où une erreur serait affichée) n'est jamais atteint pour ce type de rejet.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Même cause racine que le finding précédent : `APIClient.post`/`request` ne valide que le status code HTTP, jamais le champ "error" du corps JSON, et ces 4 méthodes de `WalletRepository` n'ajoutent pas le contrôle `isBackendSuccess` que d'autres repositories du même fichier (referralTotal, refreshBalance) et du reste du projet appliquent systématiquement.
IMPACT : Pour le retrait : l'utilisateur voit "Retrait envoyé" alors que sa demande a été rejetée par le serveur (ex. seuil dépassé) — aucune indication qu'il doit corriger le montant, aucune trace dans son historique d'un retrait réellement traité. Pour le transfert P2P : le solde local `coinsAmount` est décrémenté et un message "Vous avez transféré X pièces à Y" s'affiche alors qu'AUCUNE pièce n'a quitté le compte côté serveur — l'utilisateur voit son solde baisser pour rien, un vrai bug de perte de solde perçue. Pour la conversion : "Envoyé avec succès" s'affiche alors qu'aucune gemme n'a été créditée.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ajouter `guard response.isBackendSuccess else { throw JSONError.typeMismatch(response.backendErrorMessage ?? endpoint) }` dans `submitWithdrawalRequest`, `submitWithdrawalByCrypto`, `convert` et `transferCoins` de `WalletRepository.swift`, au même endroit où `referralTotal`/`refreshBalance` le font déjà dans ce même fichier. Envisager aussi de propager `backendErrorMessage` jusqu'à l'UI pour reproduire le mapping spécifique `WITHDRAWAL_THRESHOLD_EXCEEDED` → libellé dédié (`WithdrawActivity.java:152-153`).
```

```
ID : V5-F-033
PRIORITÉ : P1
DOMAINE : Pipeline média — Chat (messages vocaux)
FEATURE : Enregistrement et envoi de messages vocaux (voice messages) dans le chat
ANDROID SOURCE : messagerie/layout/MessageEventLayout.java:238-301 (recordListener.onFinish→startRecording/endRecord→listener.onVoiceMessage), messagerie/ui/ChatFragmentTest.java:823-826 (onVoiceMessage→sendAudioMessage) et :1355-1358 (sendAudioMessage→prepareFileMessage(detail,"audio",null)) qui insère le message (isFileUploaded=0) puis déclenche l'upload via messagerie/service/UploadFileOrDataService.java:153-176 (prapare→uploadMediaToBunny, branche non-vidéo) — PUT direct BunnyCDN storage, même protocole que photo/vidéo de chat.
ANDROID BEHAVIOR : Un bouton micro dans la barre de composition (RecordButton/RecordView) permet d'enregistrer un message vocal (appui maintenu) ; à la fin de l'enregistrement, le fichier audio local (.3gp) est envoyé comme message "audio" et uploadé vers BunnyCDN (storage.bunnycdn.com/tiinver-media/tiinver/message/audio/…) exactement comme un attachement photo/vidéo. Chemin confirmé RÉELLEMENT câblé (recordListener assigné dans MessageEventLayout, pas de code mort/commenté sur ce chemin, contrairement à l'ancien View.OnTouchListener obsolète des lignes 1234-1309 qui, lui, est entièrement commenté).
IOS FILES : Sources/TiinverSwift/Messagerie/ChatView.swift:270-317 (barre de composition : boutons paperclip/gif/gift/graphic, AUCUN bouton micro/enregistrement) ; Sources/TiinverSwift/Messagerie/ChatViewModel.swift:354-427 (sendMedia/attachMedia ne gèrent que photo/vidéo via GalleryPickerView) ; recherche projet entier `AVAudioRecorder`/équivalent = 0 résultat.
IOS BEHAVIOR : Aucun bouton ni geste ne permet d'enregistrer et d'envoyer un message vocal. `ChatMediaUploadService` (le service d'upload BunnyCDN direct, Sources/TiinverSwift/Messagerie/ChatMediaUploadService.swift) sait techniquement uploader un objet "audio" (MessageMediaKind.audio existe), et la lecture d'un message audio REÇU fonctionne (ChatBubbleViews.swift:73, AudioBubbleBody) — mais rien côté UI n'appelle jamais `sendMedia(object: "audio", …)` : la fonctionnalité d'ENVOI est totalement absente, pas seulement désactivée.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage de la barre de composition du chat n'a jamais implémenté l'enregistrement audio (AVAudioRecorder + geste d'appui maintenu + UI équivalente à RecordView) alors que le protocole d'upload backend correspondant existe déjà côté iOS et est prêt à l'emploi (MessageMediaKind.audio, mimeType/extension corrects, .3gp/.3gpp). Aucun commentaire dans le code iOS ne signale ce gap (contrairement au GIF/sticker picker, explicitement marqué "à porter" en commentaire dans ChatView.swift:290-296) — c'est une omission non documentée.
IMPACT : Fonctionnalité de messagerie de base (message vocal), très utilisée sur mobile, totalement indisponible côté iOS : un utilisateur ne peut jamais envoyer de message vocal à un contact ou un groupe, alors qu'il peut en recevoir et les lire. Asymétrie fonctionnelle complète entre les deux plateformes sur ce type de message.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter un bouton micro dans la barre de composition (ChatView.swift, à côté du bouton paperclip), avec AVAudioRecorder pour capturer un fichier audio temporaire (appui maintenu, relâchement = fin d'enregistrement, glissement pour annuler comme Android RecordView), puis appeler `viewModel.sendMedia(object: "audio", localFileURI: …, duration: …)` — le reste du pipeline (upload BunnyCDN, persistance, envoi socket) est déjà fonctionnel côté iOS et n'a pas besoin d'être modifié.
```

```
ID : V5-F-034
PRIORITÉ : P1
DOMAINE : Galerie
FEATURE : Sélection d'une VIDÉO depuis la galerie dans l'éditeur Animems (bouton « + », ic_add) — silencieusement ignorée côté iOS
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/views/AnimemesCompound.java:2108-2113 (clic R.id.ic_add → addBitmapFromGallerie()) et :2251-2253 (addBitmapFromGallerie() → animemesListener.onOpenGalleryImageOnly()) ; app/src/main/java/com/tiinver/editor/memes/MemesFragment.java:386-388 (onOpenGalleryImageOnly() → pickOnlyImage()), :551-559 (pickOnlyImage() lance pickMediaOnlyImage avec filtre PickVisualMedia.ImageAndVideo), :561-587 (callback : si isVideo, videotrimmer.setVideoUri(uri) + setVisibility(VISIBLE)), :233-267 (videotrimmer.setVideoTrimmerListener → onBitmaps(bitmaps) → animemes_compound.addBitmaps(bitmaps, 33) puis fermeture du trimmer)
ANDROID BEHAVIOR : En tapant sur le bouton « + » (ic_add) de la barre d'outils Animems puis en choisissant une VIDÉO dans le sélecteur système, Android ouvre un vrai écran de recadrage temporel (VideoTrimmerView, avec ratio de crop visible), et à la validation extrait une séquence de bitmaps depuis la vidéo trimée pour les ajouter comme calque animé sur le canevas (animemes_compound.addBitmaps(bitmaps, 33)). C'est un chemin réellement atteignable (bouton câblé, listener non nul, VideoTrimmerView instancié depuis le layout à la ligne 233) et fonctionnellement significatif.
IOS FILES : Sources/TiinverSwift/Animems/AnimemesEditorView.swift:167-178 (sheet du GalleryPickerView) et ligne 175 précisément ; bouton d'appel ligne 599 (Button { showGalleryPicker = true } label: { Image(systemName: "plus") } // ic_add)
IOS BEHAVIOR : onVideoPicked: { _ in showGalleryPicker = false } — la vidéo sélectionnée est totalement jetée : aucun trimmer, aucune extraction de trame, aucun calque ajouté au canevas. La feuille de sélection se ferme simplement, sans aucun message d'erreur ni indication à l'utilisateur que son choix n'a eu aucun effet.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le port de GalleryPickerView pour ce point d'entrée précis n'implémente que la branche image (state.addImage, ligne 171-173) ; la branche vidéo n'a jamais été câblée vers un équivalent du trim + extraction de trames (aucune fonction addBitmaps/extractFrames équivalente n'existe dans AnimemesEditorState.swift malgré la présence de addCapturedPaintFrames, mécanisme structurellement proche déjà utilisé pour un autre bouton).
IMPACT : Un utilisateur qui tente d'ajouter une vidéo comme calque animé depuis la galerie dans l'éditeur Animems n'obtient RIEN : pas d'erreur, pas de calque, juste la fermeture silencieuse du sélecteur — fonctionnalité entièrement manquante et échec totalement silencieux, exactement le pattern à signaler selon la consigne d'audit.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Porter la branche vidéo : ouvrir une UI de recadrage temporel (réutiliser MediaTrimView existant côté iOS ou équivalent), puis extraire une séquence de frames via AVAssetImageGenerator et les ajouter au canevas via une nouvelle méthode AnimemesEditorState.addVideoFrames(...) analogue à addCapturedPaintFrames. À défaut, au minimum afficher un message d'erreur explicite plutôt que fermer silencieusement la feuille.
```

```
ID : V5-F-035
PRIORITÉ : P2
DOMAINE : Galerie
FEATURE : Sélection d'une IMAGE depuis la galerie dans l'éditeur Animems (bouton « + ») — étape de recadrage/aperçu manquante avant ajout au canevas
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/views/AnimemesCompound.java:2441-2469 (méthode add(MediaDataDetail result) : instancie un CroperView, croperView.setImageUri(...), setOnBitmapCroperListerner — l'image n'est ajoutée au calque (onNewAddBitmap) qu'APRÈS validation du recadrage par l'utilisateur, onClose() permettant d'annuler sans rien ajouter) ; app/src/main/java/com/tiinver/editor/memes/MemesFragment.java:573-584 (branche image de pickMediaOnlyImage → clearResidualOverlays() puis animemes_compound.add(data))
ANDROID BEHAVIOR : Après sélection d'une image dans la galerie via le bouton « + », Android affiche un écran interactif de recadrage (CroperView/CropImageView, module com.animems.engine.android.croper) permettant à l'utilisateur d'ajuster/recadrer l'image et de VALIDER ou d'ANNULER (onClose() referme sans rien ajouter au canevas) avant qu'elle ne devienne un calque bitmap sur le canevas.
IOS FILES : Sources/TiinverSwift/Animems/AnimemesEditorView.swift:169-173 (onImagePicked: { url in ... state.addImage(image, canvasSize: canvasSize) }) ; Sources/TiinverSwift/Animems/AnimemesEditorState.swift:223-236 (func addImage)
IOS BEHAVIOR : L'image sélectionnée est immédiatement redimensionnée (Self.downscale(image, maxDimension: 220)) et ajoutée comme calque au canevas sans AUCUNE étape de recadrage ni de confirmation/annulation intermédiaire — l'utilisateur ne peut ni ajuster le cadrage ni annuler après avoir vu l'aperçu.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le port n'a pas reproduit CroperView/CropImageView (module de recadrage dédié, engine/src/main/java/com/animems/engine/android/croper/), et a remplacé l'étape par un ajout direct avec redimensionnement automatique.
IMPACT : Perte fonctionnelle réelle (pas de recadrage possible avant ajout) et différence de flux UX : sur Android l'utilisateur voit un aperçu interactif et peut annuler à cette étape précise (le calque n'existe pas encore) ; sur iOS l'image est ajoutée au canevas de façon irréversible dès la sélection, sans étape d'aperçu/validation dédiée — correspond directement au point « aperçu avant validation » du domaine audité.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter une étape de recadrage/aperçu (SwiftUI crop interactif, ou a minima un aperçu avec boutons Valider/Annuler) entre onImagePicked et state.addImage, pour retrouver la possibilité d'ajuster ou d'annuler avant que l'image ne devienne un calque permanent.
```

```
ID : V5-F-036
PRIORITÉ : P1
DOMAINE : Éditeur photo — undo (dessin libre vs superposition de calques)
FEATURE : Le bouton "undo" retire le mauvais type de calque (et est visible en dehors du mode dessin)
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/memes/ImageViewCanvas.java:317-326 (deletePrecedenteDraw, opère sur composer.getPaintLayers()) + core/AnimationComposer.java:10,46-47 (paintLayers est une ArrayList SÉPARÉE de layers) ; câblage bouton : engine/.../android/views/ImageEditorCompound.java:353,458-460 et engine/.../android/views/AnimemesCompound.java:341,460,1939 (mView.deletePrecedenteDraw()) — visibilité du bouton limitée au mode peinture : ImageEditorCompound.java:565 (Visibility.show(btn_undo) dans le handler ic_paint) / :590 (Visibility.gone(btn_undo) à la désélection) / :761 (Visibility.gone(btn_undo) dans initView()) ; même pattern AnimemesCompound.java:2085/2099/1809. Les traits de dessin libre sont ajoutés séparément via initPathDraw()/composer.addPaintLayer() (ImageViewCanvas.java:1795-1798,1022-1024), jamais dans composer.getLayers() (qui contient bitmaps/texte/stickers, ajoutés via addData()/composer.addLayer(), ImageViewCanvas.java:1017-1020).
ANDROID BEHAVIOR : Sur Android, "undo" ne retire QUE le dernier trait de dessin libre (paintLayers), jamais une image/un sticker/un texte. Le bouton n'est même visible qu'en mode pinceau actif (masqué le reste du temps). Si l'utilisateur ajoute sticker → dessine un trait → ajoute un 2e sticker, un appui sur undo (visible seulement en mode pinceau, donc juste après le trait) retire le trait et laisse les deux stickers intacts. En dehors du mode pinceau, il n'y a même pas de bouton undo permettant de supprimer un calque par erreur.
IOS FILES : Sources/TiinverSwift/Animems/AnimationComposer.swift:8-31 (paintLayers porté fidèlement mais addPaintLayer()/paintLayers ne sont appelés/lus NULLE PART ailleurs dans tout le module Animems — vérifié par recherche exhaustive) ; Sources/TiinverSwift/Animems/AnimemesEditorState.swift:648-655 (removeLast(), commentaire de tête revendiquant à tort la fidélité : "fidèle à ce bouton précis côté Android") + :724-735 (addFreehandDrawing, ajoute le trait terminé comme calque .bitmap ORDINAIRE via composer.addLayer(), PAS composer.addPaintLayer()) ; câblage bouton toujours visible : Sources/TiinverSwift/Animems/AnimemesEditorView.swift:906-980 (bottomToolbar, barre horizontale permanente, aucune condition de mode) et ligne 979-980 (bottomButton("undo") { state.removeLast() }.disabled(state.layers.isEmpty)).
IOS BEHAVIOR : removeLast() fait composer.setLayers(Array(composer.layers.dropLast())) : il retire le DERNIER calque ajouté toutes catégories confondues (trait, image, sticker OU texte), et le bouton undo est toujours visible/actif dès qu'il y a au moins un calque, peu importe l'outil actif. Reprenant l'exemple ci-dessus (sticker → trait → sticker), un appui sur undo sur iOS retire le 2e STICKER (pas le trait) ; il faut un second appui pour retirer le trait — résultat inverse de celui d'Android. Si l'utilisateur n'a fait qu'ajouter des stickers/texte/images sans jamais dessiner, undo sur Android ne fait RIEN (paintLayers vide, garde à la ligne 318 de ImageViewCanvas.java) alors que sur iOS il supprime silencieusement le dernier élément placé par l'utilisateur.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le conteneur paintLayers a été porté fidèlement dans AnimationComposer.swift mais n'a jamais été relié : ni le point d'ajout des traits (addFreehandDrawing utilise addLayer au lieu de addPaintLayer), ni le bouton undo (removeLast() lit composer.layers.dropLast() au lieu de composer.paintLayers.dropLast()/composer.setPaintLayers). Le commentaire de tête de removeLast() (ligne 648-649) affirme à tort que ce port est fidèle au bouton Android précis, ce qui indique qu'un cycle d'audit antérieur a validé cette fonction sans vérifier la séparation paintLayers/layers côté Android.
IMPACT : Perte de données silencieuse et surprenante lors de toute session d'édition mélangeant dessin libre et calques (photo de profil, message de discussion, demande de certification, création Animems complète) : l'utilisateur qui pense annuler un trait de pinceau supprime en réalité son dernier sticker/texte/image sans confirmation ni moyen de distinguer les deux cas ; à l'inverse, si aucun trait n'a été dessiné, le bouton reste actif sur iOS et supprime un calque là où Android n'aurait rien fait (bouton même invisible).
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Faire écrire addFreehandDrawing() dans composer.addPaintLayer() (pas addLayer), et faire opérer removeLast() sur composer.paintLayers (composer.setPaintLayers(Array(composer.paintLayers.dropLast()))) avec garde si vide — comme deletePrecedenteDraw() côté Android ; et ne montrer/activer le bouton undo que lorsque l'outil pinceau est actif (miroir de Visibility.show/gone(btn_undo) dans les handlers ic_paint d'AnimemesCompound.java et ImageEditorCompound.java), au lieu de .disabled(state.layers.isEmpty) dans la barre du bas toujours visible.
```

```
ID : V5-F-037
PRIORITÉ : P1
DOMAINE : Éditeur vidéo — export/précision du trim
FEATURE : Chemin d'export : remux rapide Android (SimpleTrimmer) jamais reproduit côté iOS
ANDROID SOURCE : engine/src/main/java/com/animems/engine/Utils/media/VideoTransformer.java:122-157 (process(), calcul de needsTransform et branchement fast/slow path) ; engine/src/main/java/com/animems/engine/Utils/media/SimpleTrimmer.java:26-66 (javadoc) et :107-127 (correctTimeToSyncSample, correctedStart partagé vidéo+audio) ; app/src/main/java/com/tiinver/view/trimmer/VideoTrimmerView.java:670-700 (startTrimWithCrop() → VideoTransformer.process(params, callback), méthode réellement appelée depuis next.setOnClickListener, :232-257)
ANDROID BEHAVIOR : needsTransform = (cropNorm != null) || (rotation != 0) || flipH — cette condition NE tient PAS compte de startMs/endMs. Donc pour l'immense majorité des trims utilisateur (coupe temporelle seule, sans rotation/flip/ratio), VideoTransformer.process() emprunte le FAST PATH : SimpleTrimmer.trim() remuxe sans ré-encoder (aucune perte, <1s), en calant le point de départ sur la keyframe vidéo précédente la plus proche (potentiellement décalé de tout un intervalle GOP, PAS frame-exact — documenté explicitement dans SimpleTrimmer.java) et en appliquant ce MÊME point corrigé à la piste audio (ligne 124 : « correctedStart est LE MEME pour toutes les pistes — c'est le design voulu »). Le SLOW PATH (ré-encodage OpenGL frame-exact H.264, VideoTransformer.run()) n'est utilisé QUE si rotation≠0, flipH ou un crop est actif.
IOS FILES : Sources/TiinverSwift/Feed/MediaTrimView.swift:279-361 (trim())
IOS BEHAVIOR : iOS ré-encode SYSTÉMATIQUEMENT via AVMutableComposition/AVMutableVideoComposition dès qu'un trim temporel OU une transformation géométrique est actif — aucun chemin remux/passthrough n'existe. Le commentaire de tête du fichier (lignes 11-33) affirme explicitement avoir vérifié qu'Android « ne fait JAMAIS » de remux/copie pour un trim temporel seul et avoir supprimé un chemin passthrough antérieur pour cette raison (citant une correction V3-F-124) — affirmation contredite par la lecture directe de VideoTransformer.java : le fast path (SimpleTrimmer) EXISTE bel et bien et est le chemin RÉELLEMENT emprunté par le cas le plus fréquent (trim seul, sans rotation/flip/ratio).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Erreur d'analyse d'un cycle d'audit précédent : la lecture s'est arrêtée à VideoTrimmerView.java (qui se contente d'appeler VideoTransformer.process) sans descendre dans VideoTransformer.java pour voir le branchement fast/slow path interne, ni dans SimpleTrimmer.java pour voir le remux keyframe-snappé qu'il effectue réellement.
IMPACT : Deux divergences opposées coexistent : (1) iOS est désormais bien plus lent/coûteux (décodage+ré-encodage complet, risque de perte de qualité par génération) pour le cas le plus courant (trim seul) là où Android termine en <1s par un remux sans perte de qualité ; (2) le résultat n'est PAS non plus identique en précision : Android cale le début sur la keyframe précédente (écart possible jusqu'à ~1-2s selon le GOP, et l'audio est forcé au même point corrigé que la vidéo, donc potentiellement décalé du timestamp demandé par l'utilisateur), alors qu'iOS produit toujours une coupe frame-exacte au timestamp exact demandé. La même action utilisateur produit donc un fichier sensiblement différent (durée, cadrage temporel, temps d'export) selon la plateforme, sans qu'aucune des deux ne soit une reproduction fidèle de l'autre malgré l'intention affichée dans les commentaires de code.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Réintroduire côté iOS un chemin rapide pour le cas 'trim temporel seul, sans transformation géométrique', fidèle au comportement RÉEL d'Android (remux + calage sur la keyframe précédente identique pour vidéo et audio, pas une simple passe AVAssetExportPresetPassthrough sans calage). Si le choix de garder un ré-encodage frame-exact systématique est assumé comme une amélioration délibérée, corriger la documentation en tête de VideoTrimState.swift/MediaTrimView.swift qui affirme à tort qu'il s'agit d'une 'fidélité' à Android.
```

```
ID : V5-F-038
PRIORITÉ : P2
DOMAINE : Éditeur vidéo — recadrage spatial (ratio)
FEATURE : Recadrage vidéo : repositionnement interactif du cadre et zone par défaut
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/views/CropOverlayView.java:243-266 (resetCropRect — cadre centré à 90% seulement de la zone maximale possible pour le ratio choisi) et :341-389 (onTouchEvent/moveCropRect — glisser tactile pour repositionner le cadre, clampé dans videoRect) ; app/src/main/java/com/tiinver/view/trimmer/VideoTrimmerView.java:122-137 (setBtnCropRatioVisibility, monte CropOverlayView sur l'écran de trim réellement affiché) et :670-690 (startTrimWithCrop, cropOverlayView.getCropNormRelativeToVideo() envoyé tel quel à VideoTransformer)
ANDROID BEHAVIOR : Après sélection d'un ratio, le cadre de recadrage est centré PAR DÉFAUT à seulement 90% de la zone maximale possible pour ce ratio (resetCropRect : maxW/maxH = 90% de videoRect), ET l'utilisateur peut le FAIRE GLISSER (onTouchEvent → moveCropRect) n'importe où à l'intérieur des limites de l'image vidéo avant de valider — il choisit donc réellement quelle portion du cadre est conservée, la position finale envoyée à VideoTransformer étant celle choisie par l'utilisateur, pas un centre automatique.
IOS FILES : Sources/TiinverSwift/Feed/MediaTrimView.swift:364-436 (composeTransform, étape 4 lignes 414-434)
IOS BEHAVIOR : Le recadrage est calculé automatiquement comme le rectangle centré MAXIMAL (100% de la dimension contraignante, pas de marge de 90%) qui respecte le ratio choisi — aucune gesture ni état de position n'existe dans tout le fichier : l'utilisateur ne peut ni voir ni déplacer une zone de recadrage à l'écran, seulement choisir le ratio dans un menu (lignes 102-112).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le commentaire de composeTransform (lignes 366-369) indique lui-même que la géométrie a été 'reconstruite via l'API native ... non lue ligne à ligne' plutôt que portée depuis CropOverlayView.java, dont l'interactivité tactile n'a donc jamais été reprise.
IMPACT : Pour toute vidéo où le sujet n'est pas déjà centré (cas fréquent après un changement de ratio, ex. paysage → 9:16), les utilisateurs Android peuvent recadrer manuellement pour garder le sujet dans le cadre ; les utilisateurs iOS obtiennent TOUJOURS un recadrage strictement centré sans aucun moyen de le corriger — perte de fonctionnalité, et pixels finaux différents même sans aucune interaction de l'utilisateur (90% vs 100% de la zone disponible).
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter une DragGesture sur l'aperçu vidéo pendant que le menu de ratio est actif, pour permettre de repositionner un cadre de recadrage réellement affiché à l'écran, clampé dans les limites du renderSize (équivalent de moveCropRect), et reproduire la marge par défaut de 90% avant tout glissement de l'utilisateur.
```

```
ID : V5-F-039
PRIORITÉ : P2
DOMAINE : Éditeur vidéo — précision du trim (seuil de détection 'aucune modification')
FEATURE : Seuil de tolérance pour détecter qu'aucun trim temporel n'a été effectué
ANDROID SOURCE : app/src/main/java/com/tiinver/view/trimmer/VideoTrimmerView.java:232-257 (next.setOnClickListener), précisément ligne 238 : boolean noTrim = selStart <= 100 && selEnd >= duration - 100;
ANDROID BEHAVIOR : Le seuil de tolérance pour considérer qu'aucun trim temporel n'a été effectué est un seuil ABSOLU fixe de 100 ms de chaque côté de la sélection, indépendant de la durée totale de la vidéo source.
IOS FILES : Sources/TiinverSwift/Feed/MediaTrimView.swift:279-287 (trim(), garde de sortie anticipée)
IOS BEHAVIOR : Le seuil équivalent est exprimé en FRACTION de la durée totale de la vidéo (startFraction > 0.001 || endFraction < 0.999, soit 0.1% de la durée totale) plutôt qu'en millisecondes absolues.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le seuil a été porté en cohérence avec le reste du fichier qui manipule startFraction/endFraction (fractions [0,1]) plutôt que d'être reconverti en un seuil absolu équivalent au comportement Android en millisecondes.
IMPACT : Pour toute vidéo source de plus de 100 secondes (0.001 × durée > 0.1 s), iOS traite comme 'sans modification' — et republie donc le fichier ORIGINAL non trimmé — un trim qu'Android aurait bien exécuté. Exemple concret : sur une vidéo source de 10 minutes (600 s), iOS ignore silencieusement jusqu'à 0.6 s coupés à chaque extrémité (0.001×600=0.6s, très supérieur au seuil Android de 0.1s), alors qu'Android aurait déjà déclenché startTrimWithCrop() dès 100 ms de différence. À l'inverse, pour une vidéo source de moins de 100 s, le seuil iOS est plus strict qu'Android (peut déclencher un ré-encodage pour une différence sub-100ms qu'Android aurait ignorée).
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Remplacer les seuils fractionnaires (0.001) par un seuil absolu en secondes équivalent aux 100 ms d'Android, calculé sur (startFraction * duration) et ((1 - endFraction) * duration) plutôt que sur les fractions brutes indépendamment de la durée totale.
```

```
ID : V5-F-040
PRIORITÉ : P2
DOMAINE : Animems — interactions canvas
FEATURE : Suppression d'un objet en le glissant sur l'icône corbeille (drag-to-delete)
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/memes/MemesView2.java:1355-1362 (drawDeleterIcon, zone de dépôt), :1737-1743+1749-1763 (executeTouchEvent → touchUp puis executeDeleterObjeect sur ACTION_UP), :1765-1769 (executeDeleterObjeect), :589-597 (deleteObjectDrawed) ; onFingerMoving mis à jour dans executeTouchEvent (ACTION_MOVE, ligne 1761) et consommé par drawDeleterIcon
ANDROID BEHAVIOR : Pendant qu'un objet est en cours de déplacement (onFingerMoving=true, mode non-auto), une icône corbeille apparaît en haut-centre du canevas (drawDeleterIcon, zone ~[largeur/2, 10]→[largeur/2+70, 80]). Si l'utilisateur relâche le doigt (ACTION_UP) alors que le point de contact est dans cette zone ET que l'objet relâché est bien celui en cours d'action (i == objectInAction), l'objet est supprimé (deleteObjectDrawed : visible=false, endFrame défini). C'est un second moyen de suppression, purement gestuel, indépendant du bouton de suppression de la timeline (`deleteObjectById`, lui bien porté côté iOS).
IOS FILES : Sources/TiinverSwift/Animems/AnimemesEditorView.swift (dragGesture, lignes 731-761 ; combinedGesture, lignes 727-729) ; Sources/TiinverSwift/Animems/AnimemesEditorState.swift (dragMoved lignes 340-360, dragEnded lignes 362-367, deleteSelected lignes 660-675) ; Sources/TiinverSwift/Animems/LayerRenderer.swift (aucune icône de dépôt) — recherche exhaustive de "mDeleteBound"/"deleteIcon"/"trash" dans Sources/TiinverSwift : aucune occurrence hors du module Shareboard (PBSCanvasView, fonctionnalité distincte)
IOS BEHAVIOR : `dragGesture.onChanged`/`dragEnded()` ne testent jamais de zone de dépôt : glisser un objet n'importe où sur le canevas, y compris en haut-centre, ne fait que le déplacer. Aucune icône de corbeille n'apparaît jamais pendant un glissement (`renderVersion` incrémenté par `dragMoved`, mais rien n'affiche d'icône de suppression). La suppression n'est possible que via le bouton "supprimer" de la barre d'outils du bas (`state.deleteSelected()`, AnimemesEditorView.swift:974).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le geste de glisser-déposer-pour-supprimer n'a jamais été porté lors de la migration de `MemesView2.onTouchEvent`/`executeDeleterObjeect` : `AnimemesGestureController`/`AnimemesEditorState` ne portent que translation/rotation/échelle/sélection/bring-to-front, sans zone de dépôt ni affichage d'icône corbeille pendant le glissement.
IMPACT : Perte d'un raccourci de suppression rapide et intuitif (pattern courant des éditeurs de stickers/mèmes façon Stories) : sur iOS, la suppression d'un calque exige systématiquement un aller-retour vers la barre d'outils du bas au lieu d'un simple glisser-déposer en haut de l'écran pendant la manipulation. Fonctionnalité non bloquante (le bouton "supprimer" reste disponible) mais un geste réel et atteignable d'Android est totalement absent côté iOS.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter dans `dragGesture`/`AnimemesEditorState` (mode normal, hors édition de masque) : afficher une icône de corbeille dans `AnimemesEditorView` pendant que `state.selectedId != nil` et qu'un glissement est en cours, tester à `dragEnded()` si `value.location` (dernière position connue) tombe dans cette zone de dépôt, et appeler `state.deleteSelected()` (ou une variante "soft delete" fidèle à `deleteObjectDrawed` si la distinction visible=false/endFrame vs suppression complète du tableau est jugée importante à préserver).
```

```
ID : V5-F-041
PRIORITÉ : P3
DOMAINE : Animems — interactions canvas
FEATURE : Bornes de clamp du décalage et de l'échelle du masque (glisser/pincer en mode édition de masque) deux fois plus larges côté iOS
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/memes/MemesView2.java:402-404 (clamp `maskEditScale` à [0.1, 3.0]) et :454-460 (`maskApplyDrag`, clamp `maskEditOffsetX/Y` à [-1, 1])
ANDROID BEHAVIOR : En mode édition de masque, le décalage du masque (`maskEditOffsetX`/`Y`, glissement à un ou deux doigts) est strictement borné à [-1, 1] (fraction de la largeur/hauteur de la vue) et l'échelle du masque (`maskEditScale`, pincement à deux doigts) est strictement bornée à [0.1, 3.0] — au-delà, la valeur est plafonnée (`Math.max`/`Math.min`), le geste ne produit plus aucun effet supplémentaire une fois la borne atteinte.
IOS FILES : Sources/TiinverSwift/Animems/AnimationObjectData.swift:45-60 (`maskOffsetX`/`maskOffsetY` clampés à [-2, 2] ; `maskScale` clampé à [0.1, 5]) ; Sources/TiinverSwift/Animems/AnimemesEditorState.swift:544-559 (`maskOffsetChanged`/`maskScaleChanged`, aucun clamp local, s'appuient sur les setters ci-dessus)
IOS BEHAVIOR : Le même geste (glisser/pincer en mode masque) autorise un décalage jusqu'à ±2 (le double d'Android) et une échelle jusqu'à 5.0 (67% de plus que le maximum Android de 3.0) avant d'être plafonné.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Lors du portage de `maskApplyDrag`/du clamp de `maskEditScale` dans les accesseurs de `AnimationObjectData`, les bornes numériques choisies ([-2,2] et [0.1,5]) ne reprennent pas les constantes exactes d'Android ([-1,1] et [0.1,3.0]) — divergence numérique, pas une différence de logique de geste.
IMPACT : Pour une même amplitude de glissement/pincement du doigt, un masque peut être positionné/mis à l'échelle bien plus loin sur iOS qu'Android ne le permettrait avant de saturer — résultat visuel final différent pour un geste identique dans les zones proches ou au-delà des bornes Android, notamment perceptible en fin de course du geste (impression de "plus de marge" côté iOS).
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Aligner les bornes de `AnimationObjectData.maskOffsetX`/`maskOffsetY` sur [-1, 1] et `maskScale` sur [0.1, 3.0] pour reproduire fidèlement `maskApplyDrag`/le clamp de `maskEditScale` de `MemesView2.java`.
```

```
ID : V5-F-042
PRIORITÉ : P0
DOMAINE : Animems - Timeline
FEATURE : Le verrouillage d'une piste (icône cadenas) ne bloque pas le glisser/redimensionnement du bloc dans la timeline iOS
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/views/TimelineView.java:898-910 (onDown, branche `if (!hit.locked) { ... } else { mode = Mode.NONE; }`) ; TimelineView.java:922-1008 (onMove, aucune mutation possible quand mode==NONE)
ANDROID BEHAVIOR : Dans `onDown`, dès qu'un item timeline est touché, si `hit.locked` est vrai, `mode` est forcé à `Mode.NONE` : aucune des branches DRAG/RESIZE_LEFT/RESIZE_RIGHT de `onMove` n'est jamais atteinte pour cet item, donc `startFrame`/`endFrame`/`track` ne peuvent pas être modifiés tant que le calque est verrouillé (seule la sélection reste possible). Ce verrou est piloté par l'icône cadenas de la piste, ajoutée/gérée via `addTrackIcon`/`onTrackIconClicked` (`AnimemesCompound.java`) qui bascule `obj.locked` puis relit ce booléen à chaque frame dessinée par `TimelineView`.
IOS FILES : Sources/TiinverSwift/Animems/TimelineView.swift:314-330 (`resolveMode`) ; TimelineViewModel.swift:258-292 (`dragItem`/`resizeLeft`/`resizeRight`) ; AnimemesEditorState.swift:190-198 (`applyTimelineItemsToLayers`)
IOS BEHAVIOR : `resolveMode(at:model:)` détermine le `DragMode` uniquement à partir du hit-test de poignée (gauche/droite) ou du corps du bloc, SANS jamais lire `item.locked` (le champ existe pourtant sur `TimelineItem`, `TimelineItem.swift:17`, et est bien synchronisé depuis `obj.locked` par `syncTimeline()`, `AnimemesEditorState.swift:178`). `dragItem`/`resizeLeft`/`resizeRight` dans `TimelineViewModel` n'ont eux non plus aucun garde sur `.locked`. Au relâchement du geste, `applyTimelineItemsToLayers()` écrit sans condition `item.startFrame`/`item.endFrame` dans l'`AnimationObjectData` réel et relance `engine.prepare()` — la mutation atteint donc le moteur de lecture, pas seulement l'affichage.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage de la state-machine tactile de `TimelineView.java` (bien documenté et fidèle par ailleurs, y compris pour le fling ou les icônes verrou/visibilité elles-mêmes) a omis la condition `if (!hit.locked)` qui encadre le choix du mode dans `onDown` — la synchronisation `item.locked ← obj.locked` existe, mais rien ne la consulte au moment de décider si le geste peut modifier le bloc.
IMPACT : Verrouiller un calque via l'icône cadenas de la timeline (fonctionnalité elle-même correctement portée, `V4-F-050`) donne une fausse sécurité côté iOS : l'utilisateur peut toujours glisser le bloc, redimensionner son début/sa fin, et ces changements sont appliqués à l'`AnimationObjectData` réel puis au moteur — contrairement à Android où le verrou bloque strictement toute manipulation temporelle du bloc.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Dans `TimelineView.resolveMode(at:model:)`, retourner `.pan(scrollFramesAtDown:)` (comme pour un tap dans le vide) au lieu de `.dragItem`/`.resizeLeft`/`.resizeRight` quand `item.locked == true`, tout en laissant `model.selectedId = item.id` pour préserver la sélection — miroir exact de `mode = Mode.NONE` côté Android qui laisse `selected = hit` mais bloque toute mutation dans `onMove`.
```

```
ID : V5-F-043
PRIORITÉ : P1
DOMAINE : Animems - Keyframes
FEATURE : Le bouton ◆ (keyframe) capture toujours un keyframe matriciel côté iOS, alors qu'en mode timeline par défaut Android il ouvre le panneau de propriétés sans créer aucun keyframe
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/views/AnimemesCompound.java:859-871 (`onKeyframeButtonClicked`, branche `if (controller_mode_activate) captureTransformKeyframe(); else showPanelEditor(sel);`) ; lignes 1321-1348 (`captureTransformKeyframe`) ; lignes 873-901 (`showPanelEditor`) ; lignes 1857-1877 (`controller_mode_activate` piloté par le bouton séparé `R.id.controlle_movement`, `false` par défaut et remis à `false` par `R.id.timelineTabs`) ; lignes 420-436 et 1390 (`btn_keyframe` masqué par défaut, rendu VISIBLE dès qu'un item timeline est sélectionné dans `onSelectionChanged` — donc atteignable en mode timeline normal, PAS seulement en mode « controller »)
ANDROID BEHAVIOR : Le bouton diamant `btn_keyframe` est visible dès qu'un calque est sélectionné dans la timeline classique (mode par défaut de l'éditeur, `controller_mode_activate == false`). Dans cet état, le taper appelle `showPanelEditor(sel)` : ouverture du `LayerEditorPanel` (sliders opacité/couleur/rayon de coin, etc.), SANS créer le moindre keyframe. `captureTransformKeyframe()` (qui, elle, enregistre un keyframe matriciel à la frame courante du playhead à partir de la matrice courante de l'objet) n'est appelée QUE lorsque le mode « controller de mouvement » (`R.id.controlle_movement`, un panneau de curseurs séparé, zoom/rotation/skew/ancrage) a été explicitement activé par un autre bouton.
IOS FILES : Sources/TiinverSwift/Animems/AnimemesEditorView.swift:662-665 (bouton ◆ dans `playbackBar`) ; AnimemesEditorState.swift:823-833 (`recordKeyframe`) ; MovementControllerState.swift:1-48 (mode « controller » entièrement non branché — aucun appelant `MovementControllerState(...)` dans tout le projet)
IOS BEHAVIOR : Le bouton ◆ de `playbackBar` (visible dès que `state.selectedId != nil`, soit l'équivalent exact du mode timeline par défaut d'Android) appelle inconditionnellement `state.recordKeyframe()`, qui ajoute/écrase un keyframe matriciel (`obj.addMatrixKeyframe`) à la frame du playhead courant à partir de `obj.transforms.last`. Il n'existe côté iOS aucune branche équivalente à `controller_mode_activate` : `MovementControllerState` (le modèle du mode « controller » Android) est un type Swift complet mais jamais instancié nulle part dans le projet — le mode qui, côté Android, est la SEULE condition sous laquelle ◆ enregistre un keyframe, n'existe tout simplement pas côté iOS.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le commentaire de `recordKeyframe()` (`AnimemesEditorState.swift:816-822`) cite bien avoir audité `AnimemesCompound.java:859-871,1321-1348`, mais retient seulement la branche `captureTransformKeyframe` sans reproduire la condition `controller_mode_activate` qui l'encadre côté Android ; le bouton ◆ iOS a donc été câblé sur le comportement du mode secondaire (non porté par ailleurs) plutôt que sur le comportement par défaut du même bouton visuel.
IMPACT : Dans le flux d'édition normal (timeline visible, pas de mode « controller » — flux qui est d'ailleurs le SEUL possible côté iOS puisque ce mode n'existe pas), taper ◆ sur iOS insère silencieusement un keyframe de position/rotation/échelle/inclinaison à la frame courante à chaque appui — un effet de bord réel sur la timeline — alors qu'un utilisateur venant d'Android s'attend à ce que ce bouton, dans ce contexte, ouvre juste un panneau de réglages sans rien modifier. Des taps répétés/exploratoires créent ou écrasent des keyframes matriciels non voulus (silencieusement, `KeyframeTrack.addKeyframe` remplaçant en place tout keyframe déjà présent au même timestamp).
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Faire pointer le bouton ◆ vers l'ouverture du panneau de propriétés (déjà porté ailleurs sous le bouton « propriétés », `AnimemesEditorView.swift:944-949`) par défaut, et réserver `recordKeyframe()`/l'icône diamant « active » au futur mode « controller » de mouvement s'il est un jour porté — ou, a minima, documenter explicitement ce choix de design comme une divergence assumée plutôt que comme un port direct du bouton Android.
```

```
ID : V5-F-044
PRIORITÉ : P3
DOMAINE : Animems - Timeline (zoom pincé)
FEATURE : Le pincement-zoom de la timeline se recentre toujours sur le centre de l'écran au lieu de rester ancré sous les doigts de l'utilisateur
ANDROID SOURCE : engine/src/main/java/com/animems/engine/android/views/TimelineView.java:258-295 (`buildScaleDetector`, `onScaleBegin`/`onScale` utilisent `d.getFocusX()`, la position réelle du point focal du pincement rapportée par `ScaleGestureDetector`)
ANDROID BEHAVIOR : `pivotFrame` est capturé à la frame sous le point focal RÉEL du pincement (`frameAtX((int) d.getFocusX())`), puis `onScale` recalcule `scrollFrames` pour que ce point focal reste exactement sous les doigts pendant tout le geste — comportement standard CapCut/Premiere : où qu'on pince sur la timeline, le contenu sous les doigts ne bouge pas.
IOS FILES : Sources/TiinverSwift/Animems/TimelineView.swift:302-312 (`magnificationGesture`)
IOS BEHAVIOR : `magnificationGesture` appelle systématiquement `model.pivotFrame(atFocusX: model.viewportWidth / 2)` puis `applyPinchZoom(..., focusX: model.viewportWidth / 2)` — le point d'ancrage du zoom est TOUJOURS le centre horizontal de la vue, jamais la position réelle du pincement (limitation native de `MagnificationGesture` SwiftUI, qui ne fournit aucune localisation).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `MagnificationGesture` de SwiftUI ne transmet pas la position du geste (contrairement à `ScaleGestureDetector` Android) ; le portage a comblé ce manque par une valeur fixe (centre de l'écran) sans note documentant cette approximation comme une divergence de comportement connue.
IMPACT : Pincer-zoomer près du bord gauche ou droit de la timeline sur iOS fait sauter visuellement le contenu (recentrage brusque sur le milieu de l'écran) au lieu de rester stable sous les doigts comme sur Android — gênant surtout à fort zoom sur une longue timeline.
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Remplacer `MagnificationGesture` par un `UIPinchGestureRecognizer` enveloppé dans un `UIViewRepresentable` pour récupérer `location(in:)`, permettant de reproduire fidèlement l'ancrage sous le point focal réel ; à défaut, documenter explicitement l'approximation comme limitation SwiftUI assumée.
```

```
ID : V5-F-045
PRIORITÉ : P0
DOMAINE : Commentaires
FEATURE : Envoi d'un commentaire/réponse — mauvais nom de paramètre JSON envoyé au serveur
ANDROID SOURCE : comments/ui/MyBottomSheetDialogFragment.java:496-502, comments/controller/CommentRepository.java:95-96, Http/TransportData.java:615-680
ANDROID BEHAVIOR : Le corps JSON réellement envoyé à POST comment contient la clé "comment" (jamais "commentText") pour le texte du commentaire, ainsi que "activityId", "userId", et "parentId" (uniquement pour une réponse). Le nom "commentText" n'est qu'un nom de champ Java interne (CommentModel.commentText) — preuve qu'il ne correspond pas à la clé réseau de cet endpoint : NotificationRepository.java:176 lit lui une clé serveur "comment_text" en snake_case sur un endpoint DIFFÉRENT.
IOS FILES : Discover/CommentRepository.swift:53-57 (func post(activityId:text:parentId:) — var params = ["activityId": ..., "commentText": text, "userId": ...]) ; Networking/APIClient.swift:67-69,166+ (post(_:endpoint:) envoie le dictionnaire params directement comme corps JSON, sans renommage de clé).
IOS BEHAVIOR : CommentsView.send() (Discover/CommentsView.swift:101-111) appelle CommentRepository.shared.post(...), qui envoie un corps JSON avec la clé "commentText" au lieu de "comment" attendue par le backend. Flux atteignable de bout en bout : bouton "Envoyer" câblé → send() → post() → APIClient.post → endpoint comment.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Confusion entre le nom du champ interne Java commentText (jamais sérialisé tel quel vers cet endpoint) et le vrai nom du paramètre réseau comment, construit explicitement par map.put("comment", ...) côté Android.
IMPACT : Tout commentaire ou toute réponse postée depuis l'app iOS envoie le texte sous une clé que le backend n'attend probablement pas pour cet endpoint — risque réel que le commentaire arrive vide/absent côté serveur, ce qui casserait silencieusement TOUTE publication de commentaire/réponse depuis iOS, alors que l'UI affiche un succès (seul isBackendSuccess est vérifié, pas le contenu retourné).
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Renommer la clé envoyée dans CommentRepository.post de "commentText" à "comment", fidèle à MyBottomSheetDialogFragment.java:498.
```

```
ID : V5-F-046
PRIORITÉ : P1
DOMAINE : Commentaires — réponses imbriquées
FEATURE : Affichage des réponses imbriquées (threading) — jamais chargé ni affiché
ANDROID SOURCE : comments/ui/CommentAdapter.java:211-233 (bouton "Afficher N commentaires" visible si elts.getRepliesCount() > 0, tap → listener.getReplay(elts, callback) → replayCommentAdapter.submitList(...)) ; comments/ui/MyBottomSheetDialogFragment.java:516-520 (getReplay → commentViewModel.getReplay(data.getId(), LIMIT, OFFSET)) ; comments/controller/CommentRepository.java:177-229 (getReplay/prepareReplayeData, endpoint /comment/replay/{activityId}/{limit}/{offset}).
ANDROID BEHAVIOR : Chaque commentaire de premier niveau ayant des réponses affiche un bouton "Afficher N commentaires" ; le tap déclenche un appel réseau réel qui récupère et affiche les réponses imbriquées sous le commentaire parent via un adapter dédié (ReplayCommentAdapter).
IOS FILES : Discover/CommentRepository.swift:16-24 (func replies(commentId:limit:offset:) — port fonctionnel correct de getReplay) ; Discover/CommentsView.swift (fichier entier, 112 lignes) ; Discover/CommentModels.swift:17,50 (repliesCount décodé).
IOS BEHAVIOR : CommentRepository.replies(commentId:limit:offset:) existe et compile, mais n'a AUCUN appelant dans tout le projet iOS (grep "\.replies(commentId" sur Sources/TiinverSwift = 0 résultat). CommentsView ne récupère ni n'affiche jamais aucune réponse : pas de bouton "voir les réponses", pas d'indentation, pas d'appel à replies(...). Le champ décodé repliesCount n'est lu nulle part dans l'UI. Le bouton "Répondre" (ligne 84) permet bien d'ENVOYER un commentaire avec parentId, mais aucune réponse — ni la sienne, ni celle d'un autre utilisateur — n'est jamais visible dans l'app.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : CommentRepository.replies a été porté (fonction isolée) mais jamais câblé dans CommentsView — code mort côté fonction réseau, fonctionnalité UI simplement absente.
IMPACT : Le threading des commentaires, explicitement demandé par le brief d'audit ("réponses imbriquées ... fonctionnent des deux côtés"), est totalement non fonctionnel côté lecture sur iOS : un utilisateur ne voit jamais aucune réponse existante à un commentaire.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter dans CommentsView un affichage "Afficher N réponses" conditionné à comment.repliesCount ?? 0 > 0, appelant CommentRepository.shared.replies(commentId:...) et rendant les résultats imbriqués sous le commentaire parent, fidèle à CommentAdapter/ReplayCommentAdapter.
```

```
ID : V5-F-047
PRIORITÉ : P1
DOMAINE : Commentaires — cadeaux
FEATURE : Affichage d'un commentaire-cadeau reçu — rendu cassé (ID technique brut au lieu du badge emoji)
ANDROID SOURCE : models/activity/comments/CommentModel.java:300-330 (commentaire explicite : "Les champs existants suffisent : comments → stocke gift_thumb_name, object → stocke gift" ; resolveGift(Context) résout LOCALEMENT emoji/nom/prix depuis commentText via GiftCatalogHelper, ne lit JAMAIS getGiftEmoji()/getGiftName()/getGiftPrice() pour l'affichage) ; comments/ui/CommentAdapter.java:197-198,276-281 (bindGiftView appelle elts.resolveGift(context), pas les getters directs) ; models/activity/comments/GiftCatalogHelper.java (catalogue statique complet emoji/prix/nom localisé).
ANDROID BEHAVIOR : Le serveur n'envoie, pour un commentaire-cadeau, que object="gift" et comments="gift_thumb_name" (l'identifiant technique du cadeau) — aucune preuve que le backend envoie des champs séparés giftEmoji/giftName/giftPrice/hasGift. Android résout entièrement l'affichage (emoji, nom localisé, prix) CÔTÉ CLIENT via GiftCatalogHelper, à partir de ces deux seuls champs.
IOS FILES : Discover/CommentModels.swift:26-33 (giftEmoji/giftName/giftPrice/hasGift décodés directement depuis des clés JSON supposées du serveur, AUCUN champ object décodé) ; Discover/CommentsView.swift:79-82 (if comment.hasGift == true, let emoji = comment.giftEmoji { Label(...) } sinon Text(comment.commentText ?? "") brut) ; Models/GiftCatalog.swift:3-8 (commentaire de tête du fichier lui-même : "CommentModel.resolveGift (commentaires, module 18, pas encore atteint)").
IOS BEHAVIOR : Comment ne décode aucun champ object, et s'appuie entièrement sur des clés hasGift/giftEmoji/giftName/giftPrice qu'Android ne prouve nulle part être envoyées par le serveur pour cet endpoint (preuve inverse : Android calcule tout en local exprès). GiftCatalog.swift — le catalogue Swift déjà porté et fonctionnel pour le chat — documente lui-même explicitement que son intégration au module Commentaires n'a "pas encore" été faite. Résultat probable : un commentaire-cadeau reçu s'affiche comme texte brut "gift_thumb_name" (l'ID technique non résolu) au lieu d'un badge "👍 ... 5".
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le port iOS suppose que le serveur envoie des champs de cadeau pré-résolus, alors qu'Android démontre que la résolution est intégralement client-side via un catalogue statique jamais branché côté iOS pour ce module.
IMPACT : Tout commentaire-cadeau visible dans le flux (envoyé par un utilisateur Android) s'affiche de façon cassée/illisible pour l'utilisateur iOS, au lieu du badge emoji + nom localisé attendu — fonctionnalité explicitement dans le périmètre de cet audit ("cadeaux en commentaire").
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Ajouter un champ object à Comment, détecter object == "gift", et résoudre l'affichage via GiftCatalog.resolve(comment.commentText) (déjà porté et disponible) plutôt que de dépendre de champs serveur non confirmés.
```

```
ID : V5-F-048
PRIORITÉ : P2
DOMAINE : Commentaires — cadeaux
FEATURE : Envoi d'un cadeau en commentaire — fonctionnalité entièrement absente côté iOS
ANDROID SOURCE : comments/ui/MyBottomSheetDialogFragment.java:94-131 (panneau cadeau complet : grille GiftAdapter, solde de pièces, bouton recharge), 315-380 (sélection/envoi), 450-503 (onPost branche object="gift" → commentViewModel.debitCoins → POST comment/add avec senderId/receiverId/amount), 525-565 (sendGiftComment) ; comments/controller/CommentRepository.java:240-281 (debitCoins).
ANDROID BEHAVIOR : Un bouton cadeau (btn_gift, visible seulement si FirebaseConfigManager.allowGiftCommenter()) ouvre un panneau de sélection de cadeau (grille 4 colonnes, 12 cadeaux, prix en pièces) ; l'envoi débite le solde de pièces de l'utilisateur ET poste le commentaire-cadeau en une seule opération réseau (comment/add), avec ajout optimiste immédiat et remboursement du solde local en cas d'échec.
IOS FILES : Discover/CommentsView.swift (fichier entier — aucun bouton cadeau, aucun panneau, aucune grille) ; Discover/CommentRepository.swift (aucune fonction debitCoins/comment/add) ; Discover/CommentModels.swift:26-29 (commentaire du code lui-même : "Envoi PAS porté cette session").
IOS BEHAVIOR : Aucun élément d'interface (bouton, panneau, grille de cadeaux) n'existe pour envoyer un cadeau en commentaire ; CommentRepository ne possède aucune méthode équivalente à debitCoins/comment/add. Un utilisateur iOS ne peut donc jamais envoyer de cadeau en commentaire.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Non — voir CAUSE pour contexte
CAUSE : Fonctionnalité jamais portée — explicitement reconnu par le commentaire du code source iOS lui-même ("Envoi PAS porté cette session").
IMPACT : Asymétrie fonctionnelle complète sur une fonctionnalité économique (monétisation par pièces) explicitement dans le périmètre du domaine audité ("cadeaux en commentaire") — les utilisateurs iOS ne peuvent pas participer à cette interaction sociale/monétaire du tout.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Porter le panneau de sélection de cadeau et l'appel comment/add (débit + commentaire), en réutilisant GiftCatalog déjà disponible côté iOS pour le catalogue statique (emoji/prix/nom).
```

```
ID : V5-F-049
PRIORITÉ : P2
DOMAINE : Publication — hashtags
FEATURE : Extraction des hashtags à la publication — la ponctuation finale reste collée au hashtag envoyé au serveur
ANDROID SOURCE : editor/PublishFragment.java:528-534 (extractHashtags — Pattern.compile("#(\\w+)"), matcher.find() global sur tout le texte, \\w+ s'arrête à toute ponctuation non-alphanumérique).
ANDROID BEHAVIOR : Pour une légende telle que "Beau coucher de soleil #sunset, ici", le regex extrait le hashtag "sunset" (SANS la virgule finale), et détecte aussi un hashtag collé à un mot sans espace précédent (ex. "jour#tag").
IOS FILES : Feed/PublishComposeView.swift:315 (let hashtags = caption.split(separator: " ").filter { $0.hasPrefix("#") }.map { String($0.dropFirst()) }).
IOS BEHAVIOR : Pour la même légende "Beau coucher de soleil #sunset, ici", le découpage par espace produit le token "#sunset," (virgule incluse), puis dropFirst() produit "sunset," — la virgule finale reste incluse dans le hashtag envoyé au champ hashtags de activity/add (FeedRepository.swift:255,270). De plus, un hashtag collé à un mot sans espace précédent ("jour#tag") n'est jamais détecté.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le port remplace le parsing par regex Android (#(\w+), qui borne proprement le hashtag à ses caractères alphanumériques) par un simple split-par-espace + dropFirst(), qui ne retire pas la ponctuation de fin de token.
IMPACT : Un hashtag publié depuis iOS avec une ponctuation immédiatement après (virgule, point, point d'exclamation — cas très courant en usage réel) est enregistré côté serveur avec cette ponctuation collée (ex. "sunset," au lieu de "sunset"), cassant potentiellement l'association avec le flux #sunset (HashtagFeedView) et la recherche par hashtag pour CE post précis, sans qu'aucune erreur ne soit visible à l'utilisateur.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Réutiliser la même regex #([\wÀ-ɏ]+) déjà portée dans HashtagMentionText.swift:38 pour extraire les hashtags au moment de la publication, au lieu du split par espace.
```

```
ID : V5-F-050
PRIORITÉ : P1
DOMAINE : Deep links — visibilité des erreurs
FEATURE : Alerte d'échec de résolution d'un lien profond invisible avant authentification
ANDROID SOURCE : partage/ShareActivity.java:264-268 (onError → showDialog(), lignes 366-376) — le dialogue d'erreur (R.string.errorLoad) est affiché par ShareActivity elle-même, INDÉPENDAMMENT de tout état de connexion : ShareActivity n'a aucune logique de redirection vers un écran de login avant de traiter le lien.
ANDROID BEHAVIOR : Un lien https://tiinver.com/user/{x}, /post/{x} ou /group/{x} qui échoue à se résoudre (utilisateur/post/groupe introuvable, coupure réseau) affiche TOUJOURS un dialogue d'erreur visible (R.string.errorLoad), que l'utilisateur soit connecté ou non — le dialogue est monté sur ShareActivity, l'Activity qui reçoit directement l'intent VIEW.
IOS FILES : Navigation/DeepLinkRouter.swift:93-121 (routeToUser/routeToPost/routeToGroup, appellent DeepLinkCenter.shared.showError() sur échec) ; Navigation/DeepLinkCenter.swift:44 (@Published var errorMessage) ; Navigation/HomeShellView.swift:214-221 (seul et unique consommateur de deepLinks.errorMessage via .alert) ; Navigation/RootRouterView.swift:31-57 (AuthCoordinatorView affiché tant qu'aucune session, .onOpenURL monté ligne 66-68 sur RootRouterView lui-même, PAS sur HomeShellView).
IOS BEHAVIOR : `DeepLinkCenter.errorMessage` n'est lu et affiché en `.alert` que dans `HomeShellView` (ligne 216-220). `.onOpenURL` est volontairement monté sur `RootRouterView` (commentaire ligne 61-65 du fichier) précisément pour capter un lien reçu AVANT authentification (cas parrainage notamment) — mais `RootRouterView`/`AuthCoordinatorView` n'ont AUCUN modificateur `.alert` consommant `errorMessage`. Un lien user/post/group qui échoue à se résoudre alors que l'utilisateur n'est PAS encore connecté (AuchCoordinatorView affiché) déclenche bien `showError()`, mais rien ne s'affiche à l'écran au moment du tap — la valeur reste dans `errorMessage` et ne sera consommée (affichée hors contexte, après coup) que si/quand l'utilisateur se connecte ensuite et que `HomeShellView` se monte. De plus, `routeToGroup` (ligne 115-122) retourne SILENCIEUSEMENT sans même appeler `showError()` si `UserSession.shared.myId` est nil (non connecté) — alors qu'Android appelle le réseau dans tous les cas et affiche `errorLoad` en cas d'échec serveur.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : L'alerte d'erreur des liens profonds n'est câblée que sur `HomeShellView`, alors que le point d'entrée `.onOpenURL` a été délibérément placé plus haut (`RootRouterView`) pour couvrir le cas pré-authentification — les deux décisions de design ne sont pas cohérentes entre elles.
IMPACT : Un utilisateur qui ouvre un lien partagé (tiinver://user/xxx, tiinver://post/xxx, tiinver://group/xxx) via un lien invalide ou une coupure réseau AVANT de s'être connecté ne voit RIEN se passer — pas de message, pas de redirection — l'app semble ignorer le lien. Pour les liens de groupe spécifiquement, aucune erreur n'est même levée en interne (retour silencieux avant tout appel réseau).
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Monter un `.alert` consommant `DeepLinkCenter.shared.errorMessage` également sur `RootRouterView`/`AuthCoordinatorView` (pas seulement `HomeShellView`), et faire appeler `DeepLinkCenter.shared.showError()` par `routeToGroup` aussi dans le cas `myId == nil`, fidèle au comportement Android qui affiche toujours `errorLoad` sur échec, connecté ou non.
```

```
ID : V5-F-051
PRIORITÉ : P2
DOMAINE : Settings — menu racine
FEATURE : Entrée « Mise à jour » du menu Réglages absente côté iOS
ANDROID SOURCE : setting/adapter/Adapter.java:171-176 (header_updateapp.setOnClickListener → mListener.onAppUpdate()) ; setting/BlankFragment.java:219-223 (onAppUpdate() → startActivity(Intent(UpdateApp.class))) ; UpdateApp.java:13-35 (bouton qui ouvre infoContract.PLAYSTORE_LINK = https://play.google.com/store/apps/details?id=com.tiinver) ; layout res/layout/item_headers_of_settings.xml:250-269 (texte affiché : "updates to a new version", toujours visible, non conditionné).
ANDROID BEHAVIOR : L'écran racine des Réglages (BlankFragment, atteint via case 0 de SettingsActivity, premier écran affiché à l'ouverture des Réglages) affiche TOUJOURS une entrée de menu dédiée (icône mobile_check_24px, libellé "updates to a new version") qui ouvre une Activity avec un bouton menant vers la fiche Play Store de l'app.
IOS FILES : Settings/SettingsView.swift:18-46 (liste complète du menu racine des Réglages) ; App/UpdateAppView.swift ; Navigation/RootRouterView.swift:34 (seul appelant de UpdateAppView, uniquement dans le cas `forceUpdateRequired`).
IOS BEHAVIOR : `SettingsView` ne contient aucune entrée « Mise à jour »/« Vérifier les mises à jour ». `UpdateAppView` (le port de `UpdateApp.java`) existe bien côté iOS, mais son SEUL point d'entrée dans toute la base est le blocage forcé de `RootRouterView` (grep exhaustif de `UpdateAppView(` = 1 seul appelant) — un utilisateur qui n'est PAS bloqué par le gate de mise à jour forcée n'a AUCUN moyen d'ouvrir manuellement la fiche App Store depuis les Réglages.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Portage incomplet du menu racine des Réglages — l'entrée `header_updateapp` n'a jamais été reproduite dans `SettingsView.swift`, alors que les 9 autres entrées du même RecyclerView (`header_account`, `header_verified`, `header_chat`, `header_notification`, `header_privacity`, `header_storage`, `header_help`, `header_about`, `header_publicite`) le sont toutes.
IMPACT : Fonctionnalité utilisateur manquante : impossible de vérifier/ouvrir manuellement la fiche App Store depuis les Réglages iOS, contrairement à Android où ce raccourci est toujours visible dans le menu racine.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter une entrée « Mise à jour » dans `SettingsView.swift` qui réutilise `UpdateAppView` (ou directement `UIApplication.shared.open` vers la fiche App Store une fois `appStoreId` renseigné — actuellement `nil` dans `DeepLinkRouter.swift:77`, autre gap déjà documenté par le portage lui-même).
```

```
ID : V5-F-052
PRIORITÉ : P3
DOMAINE : Settings — accès depuis un autre écran (parrainage/publicité)
FEATURE : Bouton « Activer la visualisation des publicités maintenant » de l'écran Parrainage absent côté iOS, sans raccourci vers Réglages > Publicité
ANDROID SOURCE : wallet/ReferralActivity.java:160-165 (btn_activate_ads.setOnClickListener → Intent(SettingsActivity) + BY_URL=true + INDEX=11) ; res/layout/activity_referral.xml:72-83 (bouton toujours visible, texte @string/activate_ad_viewing_now) ; res/values-fr/strings.xml:645 ("Activer la visualisation des publicités maintenant").
ANDROID BEHAVIOR : L'écran Parrainage (ReferralActivity, section « gagnez des pièces en regardant des publicités ») affiche un bouton permanent qui saute DIRECTEMENT vers l'écran Réglages > Publicité (SettingAdvertisementFragment, index 11), permettant à l'utilisateur d'activer les publicités personnalisées sans quitter le flux de gain de pièces.
IOS FILES : Wallet/ReferralView.swift:12-55 (écran complet, aucune mention de ce bouton ni de navigation vers SettingAdvertisementView).
IOS BEHAVIOR : `ReferralView` reproduit le bandeau publicitaire (`AdBannerView`), le texte descriptif et le bouton « Regarder une vidéo », mais n'a aucun bouton équivalent à `btn_activate_ads` — aucun raccourci vers `SettingAdvertisementView` n'existe sur cet écran.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Portage incomplet de `ReferralActivity.java` — le commentaire de tête du fichier iOS documente explicitement d'autres simplifications délibérées (carte QR dessinée à la main, carrousel de pubs natives) mais ne mentionne pas `btn_activate_ads`, qui a simplement été omis sans être documenté comme gap connu.
IMPACT : Perte d'un raccourci UX réel : sur Android, un utilisateur qui n'a pas encore autorisé les publicités personnalisées peut le faire en un tap depuis l'écran Parrainage ; sur iOS il doit naviguer manuellement jusqu'à Réglages > Publicité.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter un bouton « Activer la visualisation des publicités maintenant » dans `ReferralView.swift` qui navigue vers `SettingAdvertisementView` (ou présente `SettingsView(startAtAccount: false)` positionné sur cet écran, à l'image du mécanisme déjà utilisé pour `.settingsAccount`).
```

```
ID : V5-F-053
PRIORITÉ : P3
DOMAINE : Settings — Stockage et données
FEATURE : Sélection granulaire par type de média (photos/vidéos/documents) par condition réseau, absente côté iOS
ANDROID SOURCE : setting/SettingStorageFragment.java:113-151 (containerMobileData/containerWifiData/containerRoaming, onClick → showNoticeDialog3, dialogue multi-sélection R.array.list_of_media_Entires) et lignes 215-282 (onDialogPositiveClick, persistance dans storageDataListChoosed/storageWifiListChoosed/storageRoamingListChoosed via SharedPreferences).
ANDROID BEHAVIOR : L'écran Stockage et données affiche, sous chacun des 3 interrupteurs (données mobiles/Wi-Fi/itinérance), une ligne cliquable supplémentaire (sous-titre listant les types de médias choisis, ex. "Photos,Vidéos") qui ouvre un dialogue à sélection multiple pour choisir PAR CONDITION RÉSEAU quels types de médias sont téléchargés automatiquement.
IOS FILES : Settings/SettingSubViews.swift:87-102 (SettingStorageView) — le commentaire de tête du bloc (lignes 82-85) documente lui-même explicitement ce gap : "le détail granulaire par type de média — storageDataListChoosed etc., une sélection multiple — PAS reproduit cette session".
IOS BEHAVIOR : `SettingStorageView` ne contient que les 3 interrupteurs maîtres (mobileData/wifi/roaming) sans les 3 lignes de sélection par type de média ni les dialogues associés — fonctionnalité entièrement absente, pas seulement simplifiée.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Portage partiel documenté par le code source iOS lui-même (faute de temps, selon le commentaire) plutôt qu'un choix produit délibéré.
IMPACT : Perte de contrôle utilisateur fin : impossible sur iOS de restreindre le téléchargement automatique par type de média (ex. autoriser les photos mais pas les vidéos en itinérance) alors que c'est possible sur Android.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter les 3 lignes de sélection multiple par type de média sous chaque interrupteur, avec persistance locale des 3 listes équivalentes à storageDataListChoosed/storageWifiListChoosed/storageRoamingListChoosed.
```

```
ID : V5-F-054
PRIORITÉ : P2
DOMAINE : Cache / téléchargement / hors-ligne
FEATURE : Feed principal (Home) : échec de pagination totalement silencieux, aucun message ni bouton Réessayer
ANDROID SOURCE : Activity/ui/MainFragment.java:792-808 (OnScrollListener → loadMoreData() si scroll proche de la fin), :397-407 (onError() → mAdapter.setLoadingStatus(2)) ; Activity/adapter/ActivityAdapter.java:259-291 (FooterViewHolder.bindView, case 2 = icône erreur + texte + bouton buttonReesayer VISIBLE)
ANDROID BEHAVIOR : Quand le scroll approche de la fin de la liste ET que le réseau est déjà connu comme coupé (networkInfo.isConnected()==false), Android n'émet même pas la requête. Mais dès qu'une requête de pagination EST tentée et échoue réellement (timeout, 5xx, coupure pendant le transfert), MainFragment.onError() bascule le footer de l'adapter en loadingStatus=2 : un footer visible apparaît en bas de la liste avec une icône d'erreur, un texte, et un bouton « Réessayer » cliquable (ActivityAdapter.java:274-281). L'utilisateur voit donc toujours une indication claire quand une tentative de page suivante échoue.
IOS FILES : Feed/FeedView.swift:85-121 (body — LazyVGrid sans aucun footer de pagination), :109-115 (déclenchement loadNextPage() au scroll, index == posts.count-2), :281-311 (emptyOrStatusState, qui affiche errorMessage+bouton Réessayer mais N'EST rendu QUE si viewModel.posts.isEmpty, ligne 87) ; Feed/FeedViewModel.swift:65-122 (loadNextPage(), catch final ligne 116-121 qui écrit errorMessage sans vérification préalable de connectivité)
IOS BEHAVIOR : FeedViewModel.loadNextPage() tente TOUJOURS la requête réseau (aucune vérification de connectivité côté client) et, en cas d'échec, écrit bien viewModel.errorMessage — mais FeedView.swift ne lit errorMessage QUE dans emptyOrStatusState, elle-même conditionnée à `viewModel.posts.isEmpty` (ligne 87). Dès que la liste contient déjà des posts (cas normal d'une pagination en cours de scroll), la branche `else` (ligne 93-121) est utilisée à la place : aucun footer, aucun spinner, aucun message, aucun bouton de reprise. Le flux s'arrête simplement de grandir, sans que l'utilisateur puisse distinguer « fin réelle du flux » de « échec réseau pendant le scroll » — alors que ProfileView.swift:443-457 (postsGridFooter, viewModel.postsLoadError) implémente correctement ce même motif d'erreur/retry pour la grille du Profil, prouvant que le pattern est connu et déjà construit ailleurs dans ce même portage, juste absent du Feed principal.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : FeedView.swift n'affiche la vue d'état (chargement/erreur/vide) que dans la branche `posts.isEmpty`, sans équivalent de footer d'état pour la branche `else` où la pagination se produit réellement en pratique — contrairement à ProfileView.swift qui possède ce footer dédié.
IMPACT : Sur l'écran d'accueil (le plus consulté de l'app), un utilisateur qui perd la connexion ou rencontre une erreur serveur pendant le scroll voit son flux s'arrêter de grandir sans aucune explication ni moyen de relancer manuellement le chargement — expérience « écran figé » sans message clair, exactement le pattern que ce domaine d'audit cible explicitement, alors qu'Android affiche toujours un état visible (icône + texte + bouton) pour ce cas précis.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter à FeedView.swift un footer de pagination (readable via une nouvelle propriété booléenne type `postsLoadError`, sur le même modèle que ProfileViewModel.postsLoadError/ProfileView.postsGridFooter) affichant une icône d'erreur, un texte, et un bouton Réessayer quand `loadNextPage()` échoue alors que `posts` n'est pas vide.
```

```
ID : V5-F-055
PRIORITÉ : P2
DOMAINE : Cache / téléchargement / hors-ligne
FEATURE : Précache vidéo Feed : téléchargement du fichier ENTIER au lieu d'un préfixe plafonné à 2 Mo, et file d'attente strictement séquentielle (1 thread) au lieu de 2 threads parallèles
ANDROID SOURCE : Activity/service/ExoPlayerManager.java:87 (precacheExecutor = Executors.newFixedThreadPool(2)), :408-424 (cacheVideos/submitPrecache), :437-461 (preCachePrefix(url, 2_000_000L) — DataSpec.setLength(2_000_000L) plafonne explicitement le téléchargement à 2 Mo)
ANDROID BEHAVIOR : Pour chaque vidéo dans la fenêtre de préchargement (position courante + décalage), Android télécharge UNIQUEMENT les 2 premiers Mo du fichier (`preCachePrefix(url, 2_000_000L)`, `DataSpec.Builder().setLength(bytes)`) — juste assez pour un démarrage instantané de lecture, jamais le fichier complet. Ces téléchargements s'exécutent sur un pool de 2 threads (`Executors.newFixedThreadPool(2)`), donc 2 précaches peuvent progresser en parallèle sans se bloquer mutuellement.
IOS FILES : Media/VideoCacheManager.swift:18 (queue = DispatchQueue sérielle unique, qos:.utility), :53-71 (precache(_:) — URLSession.shared.dataTask SANS aucune restriction de longueur/plage, écrit l'intégralité de `data` reçue sur disque) ; Media/VideoPlayerManager.swift:117-123 (preload(_:), appelé pour une fenêtre courant±2, voir commentaire ligne 106-116 référençant FeedView.preloadAround)
IOS BEHAVIOR : VideoCacheManager.precache() télécharge la vidéo INTÉGRALE (aucun en-tête Range, aucune limite de taille) pour chaque vidéo de la fenêtre de préchargement (±2 autour de la position courante, appelé par VideoPlayerManager.preload), et écrit l'intégralité des octets reçus sur disque via `try? data.write(to:)` uniquement si la requête complète a réussi (200..<300). Ces appels s'exécutent sur UNE SEULE queue sérielle dédiée (`DispatchQueue(label: "com.tiinver.videocache")`), donc un seul précache à la fois — chacun bloquant sur un `semaphore.wait()` jusqu'à la fin (succès, échec OU timeout 60s par défaut) avant que le suivant ne démarre.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le port de `preCachePrefix` n'a pas reproduit le plafond de longueur `2_000_000L` d'Android (aucune notion de Range/longueur limitée dans l'implémentation Swift), et la queue dédiée créée pour ce cache est sérielle au lieu de reproduire le pool à 2 threads d'Android.
IMPACT : Pour chaque vidéo du feed approchant de la position de lecture courante, l'app iOS télécharge silencieusement le fichier vidéo ENTIER (potentiellement plusieurs dizaines de Mo) au lieu d'un préfixe de 2 Mo — surconsommation de données cellulaires nettement supérieure à Android, et exposition beaucoup plus grande à une interruption réseau en cours de téléchargement (un fichier volumineux a statistiquement bien plus de chances d'être coupé qu'un préfixe de 2 Mo, et le résultat partiel est alors intégralement jeté silencieusement — `try?`/vérification de statut 2xx, aucun octet écrit, tentative perdue). De plus, la sérialisation stricte (1 thread vs 2 côté Android) signifie qu'un seul téléchargement lent ou bloqué sur une connexion dégradée retarde la mise en cache de TOUTES les vidéos suivantes de la fenêtre, alors qu'Android peut continuer avec son second thread.
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Limiter precache() à un préfixe de taille comparable (ex. 2 Mo) via un en-tête `Range: bytes=0-1999999` sur la requête, et paralléliser la queue de précache (ex. DispatchQueue concurrente avec une limite de 2 opérations simultanées) pour se rapprocher du comportement/volume de données observable d'Android.
```

```
ID : V5-F-056
PRIORITÉ : P3
DOMAINE : Cache / téléchargement / hors-ligne
FEATURE : Téléchargement de pièce jointe de chat (photo/vidéo/audio/sticker/gif) : pas de reprise réelle après interruption (perte réseau pendant l'affichage, app tuée)
ANDROID SOURCE : messagerie/ui/ChatFragmentTest.java:3152-3176 (downloadFile — délègue à android.app.DownloadManager.enqueue), service/broadcast/DownloadReceiver.java:43-99 (ACTION_DOWNLOAD_COMPLETE, mise à jour de MSG_URI même si l'app a été relancée entre-temps)
ANDROID BEHAVIOR : Le téléchargement d'une pièce jointe de chat est délégué au service système `android.app.DownloadManager` (`downloadManager.enqueue(request)`), qui persiste la tâche HORS du processus de l'app : le téléchargement continue même si l'app est tuée, reprend automatiquement après une coupure réseau ou un redémarrage de l'appareil (garantie native de ce composant OS), et poste un broadcast `ACTION_DOWNLOAD_COMPLETE` capté par `DownloadReceiver` qui met à jour la base locale (`MSG_URI`) dès que le téléchargement aboutit — y compris si l'app a été relancée entre-temps (l'identifiant `downloadId` et les métadonnées associées sont retrouvés via `Settings`/SharedPreferences persistantes).
IOS FILES : Messagerie/ChatViewModel.swift:559-601 (requestDownload — Task + URLSession.shared.download(from:)), :479-496 (handleAppear, seul déclencheur/re-déclencheur), Messagerie/ChatView.swift:195 (onAppearEffects → viewModel.handleAppear, point d'entrée UI réel confirmé)
IOS BEHAVIOR : requestDownload() lance un `Task` in-process qui appelle `URLSession.shared.download(from:)` (session par défaut, pas une session `background`). Si l'app est tuée pendant le téléchargement, ou si le Task échoue (coupure réseau), le `catch` ne fait RIEN d'autre que laisser `isFileDownloaded == 0` — sans persister d'état intermédiaire ni programmer de nouvel essai automatique. Le seul mécanisme de reprise est un nouveau `handleAppear(of:)`, câblé sur `.onAppear` de la bulle de message (ChatView.swift:195) : cela ne se redéclenche PAS tant que la ligne reste visible à l'écran sans en sortir/rentrer — si l'utilisateur garde la conversation ouverte pendant que le réseau revient, le téléchargement resté en échec n'est JAMAIS relancé automatiquement tant que la bulle ne quitte pas puis ne revient pas dans la zone visible (scroll, changement d'écran, relance de l'app).
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le portage utilise un `URLSession.download(from:)` lié au cycle de vie du process/de la vue plutôt qu'un mécanisme persistant équivalent au DownloadManager système d'Android — écart d'architecture documenté en partie dans le commentaire de tête ("pas de service WorkManager/notification système équivalents") mais ce commentaire ne couvre explicitement que l'absence de notification de progression, pas la garantie de reprise/persistance à travers un kill d'app ou une coupure réseau survenant PENDANT que la bulle reste visible.
IMPACT : Un utilisateur qui ouvre une conversation contenant une photo/vidéo non encore téléchargée alors que le réseau est instable peut voir le téléchargement échouer silencieusement et rester bloqué indéfiniment tant qu'il ne quitte pas puis ne revient pas sur ce message précis (scroll, navigation) — contrairement à Android où le téléchargement, une fois lancé, se termine de façon fiable indépendamment de l'état de l'app ou de la vue, y compris après un kill complet de l'app.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Envisager une URLSession de configuration `background` pour les téléchargements de pièces jointes de chat (comme pour tout téléchargement iOS destiné à survivre à la mise en arrière-plan/au kill de l'app), et/ou déclencher un nouvel essai automatique sur le retour de NetworkMonitor.shared à `.satisfied` pour les messages dont isFileDownloaded reste à 0, sans attendre un ré-appairage visuel de la bulle.
```

```
ID : V5-F-057
PRIORITÉ : P1
DOMAINE : Performance et mémoire — éditeur Animems (lecture/aperçu)
FEATURE : CADisplayLink de l'éditeur Animems jamais invalidé si l'écran est quitté pendant la lecture
ANDROID SOURCE : app/src/main/java/com/tiinver/editor/memes/MemesFragment.java:144-176 (onPause/onStop/onDestroyView appellent tous animemes_compound.pause() + animemes_compound.stopView(), et onDestroyView appelle en plus animemes_compound.onDestroy())
ANDROID BEHAVIOR : Dès que le Fragment perd le focus (bouton retour, mise en arrière-plan de l'app, changement d'onglet, destruction de la vue), Android arrête explicitement la lecture ET la vue d'animation (mView.stopView() côté MemesView2/AnimemesCompound) — le rendu par frame ne peut jamais continuer à tourner après la sortie de l'écran.
IOS FILES : Sources/TiinverSwift/Animems/AnimemesEditorState.swift:29,780-802 (engine, togglePlayback, scrub) ; Sources/TiinverSwift/Animems/AnimationEngine.swift:170-189 (startPlayback/stopDisplayLink) ; Sources/TiinverSwift/Animems/AnimemesEditorView.swift:38-41 (@StateObject private var state = AnimemesEditorState())
IOS BEHAVIOR : AnimemesEditorState est un @StateObject sans aucun deinit, et AnimemesEditorView.swift ne contient aucun .onDisappear. Le CADisplayLink (AnimationEngine.displayLink, ajouté à .main avec forMode:.common) n'est arrêté (stopDisplayLink()/invalidate()) QUE lors d'un second tap explicite sur le bouton lecture (togglePlayback) ou d'un scrub manuel (scrub(toFrame:)). Si l'utilisateur lance la lecture puis quitte l'écran (bouton retour de FeedView/HomeShellView/MonetizationView, ou l'app passe en arrière-plan) pendant que isPlaying==true, rien n'appelle engine.pause()/stop().
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : DisplayLinkProxy.onTick capture `self` (AnimationEngine) en [weak self] (AnimationEngine.swift:175), ce qui évite un crash après désallocation de AnimemesEditorState — mais RunLoop.main retient fortement le CADisplayLink lui-même (et son target DisplayLinkProxy) indépendamment de l'AnimationEngine qui l'a créé. Sans deinit/onDisappear appelant engine.stop(), le CADisplayLink continue de déclencher son callback à chaque rafraîchissement d'écran (jusqu'à 60-120 Hz) POUR TOUJOURS après la sortie de l'écran (le self?.tick(...) devient un no-op silencieux une fois AnimationEngine désalloué, mais l'objet CADisplayLink lui-même n'est jamais invalidé ni libéré).
IMPACT : Fuite de timer classique : chaque session « lecture puis sortie sans re-taper pause » laisse un CADisplayLink actif indéfiniment dans le run loop principal, consommant CPU/batterie en continu sur TOUT le reste de la session app (tous les écrans suivants), jusqu'au kill de l'app. Répété plusieurs fois (l'utilisateur rentre/sort de l'éditeur plusieurs fois en jouant à chaque fois), plusieurs CADisplayLink orphelins s'accumulent simultanément — croissance non bornée du nombre de timers actifs vs le comportement Android qui les arrête systématiquement au niveau du lifecycle.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ajouter .onDisappear { state.engine.stop() } (ou pause()) sur la vue racine d'AnimemesEditorView, et/ou un deinit dans AnimemesEditorState qui invalide explicitement engine.displayLink, pour reproduire fidèlement onPause/onStop/onDestroyView de MemesFragment.java.
```

```
ID : V5-F-058
PRIORITÉ : P1
DOMAINE : Performance et mémoire — téléchargement et pré-cache vidéo (listes/feed)
FEATURE : Vidéo entière chargée en RAM avant écriture sur disque (téléchargement Profil + pré-cache du Feed)
ANDROID SOURCE : app/src/main/java/com/tiinver/Activity/service/CacheWorker.java:66-69,231-234 (CacheDataSource.Factory + CacheWriter(dataSource, dataSpec, buffer, ...) — écrit en flux, par blocs bornés, directement dans SimpleCache sur disque) ; téléchargement utilisateur via android.app.DownloadManager (streaming disque système, jamais chargé en tas Java)
ANDROID BEHAVIOR : Le pré-cache vidéo ExoPlayer (CacheWriter/SimpleCache, CacheWorker.java) et le téléchargement utilisateur (DownloadManager) écrivent tous deux la vidéo progressivement sur disque via un buffer de taille bornée, sans jamais retenir le fichier complet en mémoire Java, quelle que soit sa durée/poids.
IOS FILES : Sources/TiinverSwift/Feed/FeedMediaDownloader.swift:36-45 (download, via URLSession.shared.data(for:)) ; Sources/TiinverSwift/Media/VideoCacheManager.swift:53-71 (precache, via URLSession.shared.dataTask + data.write(to:))
IOS BEHAVIOR : FeedMediaDownloader.download utilise `try await URLSession.shared.data(for: request)` : la totalité du fichier vidéo est chargée en mémoire comme un objet `Data` unique avant `data.write(to: tmpURL)`. VideoCacheManager.precache (appelé automatiquement en arrière-plan par VideoPlayerManager.preload pour chaque vidéo de la fenêtre currentIndex±2 pendant le défilement du Feed, cf. commentaire ligne 106-116 de VideoPlayerManager.swift) fait de même via `URLSession.shared.dataTask` : le callback reçoit `data` déjà entièrement bufférisé en mémoire avant `data.write(to:)`.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `URLSession.shared.data(for:)`/`dataTask` (API haut niveau) chargent systématiquement tout le corps de la réponse HTTP en RAM comme `Data`, contrairement à `URLSession.shared.download(for:)` (téléchargement en flux direct vers un fichier temporaire) qui aurait été l'équivalent réel du streaming disque Android.
IMPACT : Pour une vidéo longue/haute qualité (le pré-cache cible spécifiquement les URLs 720p, voir commentaire ligne 44-52 de VideoCacheManager.swift), ce chargement en mémoire peut atteindre plusieurs centaines de Mo d'un coup — pendant un simple défilement du Feed (precache silencieux, sans action utilisateur visible), cumulé avec la vidéo en cours de lecture et d'éventuels autres médias déjà en mémoire, ce qui augmente significativement le risque de jetsam/crash mémoire sur les appareils à RAM limitée, un scénario d'usage normal (scroll du Feed) et non un cas limite.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Remplacer `URLSession.shared.data(for:)`/`dataTask` par `URLSession.shared.download(for:)` (ou une URLSessionDownloadTask) dans FeedMediaDownloader.download et VideoCacheManager.precache, qui écrit directement sur disque par blocs sans charger le fichier complet en RAM, fidèle au streaming disque de DownloadManager/CacheWriter côté Android.
```

```
ID : V5-F-059
PRIORITÉ : P2
DOMAINE : Performance et mémoire — génération de vignettes vidéo (trim + pièces jointes chat)
FEATURE : Vignettes vidéo générées à la résolution native complète au lieu d'une taille réduite
ANDROID SOURCE : app/src/main/java/com/tiinver/view/trimmer/VideoTrimmerView.java:1019-1032 (generateThumbsAsync : r.getFrameAtTime(...) PUIS Bitmap.createScaledBitmap(bmp, 320, 180, true) immédiat, avec bmp.recycle() du plein format)
ANDROID BEHAVIOR : Android décode chaque frame plein format via MediaMetadataRetriever.getFrameAtTime, la réduit IMMÉDIATEMENT à 320×180 avec Bitmap.createScaledBitmap, puis recycle explicitement le bitmap plein format — seule la petite vignette 320×180 est conservée en mémoire, jamais le plein format simultanément pour plusieurs frames.
IOS FILES : Sources/TiinverSwift/Feed/MediaTrimView.swift:235-247 (generateThumbnails — 8 appels à generator.image(at:) sans maximumSize, accumulés dans `images` avant assignation à `thumbnails`) ; Sources/TiinverSwift/Messagerie/ChatViewModel.swift:416-426 (generateThumbnail — generator.copyCGImage(at: .zero,...) sans maximumSize)
IOS BEHAVIOR : AVAssetImageGenerator est instancié sans définir `generator.maximumSize` dans les deux sites — par défaut, ImageIO décode et retourne chaque frame à la résolution NATIVE complète de la piste vidéo (ex. 4K/1080p), qui n'est ensuite affichée qu'en bandeau de vignettes miniatures (MediaTrimView.swift:148-150, largeur ≈ largeur écran/8) ou en miniature de bulle de chat.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence de `generator.maximumSize = CGSize(width: 320, height: 180)` (ou équivalent) avant l'appel à `image(at:)`/`copyCGImage(at:actualTime:)` — ImageIO décode donc chaque frame à pleine résolution source avant tout redimensionnement (qui n'a d'ailleurs jamais lieu explicitement côté iOS, contrairement à `createScaledBitmap` côté Android).
IMPACT : Pour une vidéo source à haute résolution, MediaTrimView.generateThumbnails maintient simultanément jusqu'à 8 UIImage plein format dans le tableau `images` avant assignation — pic mémoire transitoire important (potentiellement plusieurs dizaines à centaines de Mo selon la résolution source) pour un résultat final affiché en vignettes de quelques dizaines de points ; ChatViewModel.generateThumbnail décode une frame plein format juste pour produire un JPEG de vignette de chat.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Définir generator.maximumSize à une taille cible réduite (ex. CGSize(width: 320, height: 180)) avant chaque appel image(at:)/copyCGImage(at:actualTime:) dans MediaTrimView.generateThumbnails et ChatViewModel.generateThumbnail, pour que ImageIO sous-échantillonne dès la génération de la frame plutôt que de décoder puis jeter le plein format.
```

```
ID : V5-F-060
PRIORITÉ : P1
DOMAINE : Tâches en arrière-plan (BGTaskScheduler)
FEATURE : Synchronisation périodique WorkManager (vues/watchtime + suggestions de contenu + livraison de boost) : aucun équivalent iOS enregistré
ANDROID SOURCE : Utils/ViewTracker.java:100-113 (startPeriodicSync, PeriodicWorkRequest 15min sur ViewSyncWorker) appelé depuis App.java:259,329 ; Activity/ui/HomeActivity.java:365,373-375 + 752-782 (scheduleDynamicWorker → 3 PeriodicWorkRequest sur MyWorker, 1-2 jours : "suggest-content", "get-suggest-content", "my-boost-deliver") ; service/worker/ViewSyncWorker.java (doWork) ; service/MyWorker.java (doWork, appelle NotificationUtils.displaySuggestNotification et /boost/deliver/{userId})
ANDROID BEHAVIOR : Au démarrage de l'app (App.java) et à chaque création de HomeActivity pour un utilisateur connecté, 4 tâches WorkManager périodiques sont enregistrées et persistent au-delà du cycle de vie du process (survivent au kill de l'app, retry avec backoff exponentiel, contrainte réseau) : synchronisation du temps de visionnage/analytics (toutes les 15 min), suggestion de contenu pour ré-engagement (déclenche une notification locale via NotificationUtils.displaySuggestNotification), et livraison quotidienne des "boosts" (promotion payante de publications, module advertising/).
IOS FILES : Sources/TiinverSwift/Storage/ViewEventRepository.swift (commentaire ligne 3-6 admet explicitement l'absence : "la synchronisation périodique/immédiate vers le serveur ... est un sujet à part entière (équivalent BackgroundTasks/BGTaskScheduler) ... différé") ; Sources/TiinverSwift/Navigation/HomeShellView.swift ligne 39-41 (même aveu pour les 3 scheduleDynamicWorker) ; project.yml (aucune clé BGTaskSchedulerPermittedIdentifiers)
IOS BEHAVIOR : Aucune tâche périodique en arrière-plan n'existe côté iOS : `grep -r BGTaskScheduler` sur tout `Sources/TiinverSwift/` ne renvoie aucun résultat, `BGTaskSchedulerPermittedIdentifiers` est absent d'Info.plist/project.yml, et `ViewEventRepository` (le seul morceau écrit, stockage local uniquement) n'est instancié NULLE PART dans le code (`grep -rn "ViewEventRepository("` ne renvoie rien) — même le suivi local du temps de visionnage est mort. Les endpoints `activity/suggest-content` et `boost/deliver` n'apparaissent dans AUCUN fichier Swift (`grep -rln "suggest-content\|boost/deliver"` vide) : ni en tâche de fond, ni même en appel synchrone au premier plan.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Fonctionnalité explicitement reportée ("module 18, pas encore atteint" selon les commentaires du code) mais aucune infrastructure de remplacement (BGAppRefreshTask/BGProcessingTask) n'a été mise en place, et même le stockage local préparatoire n'est jamais sollicité par un point d'entrée réel.
IMPACT : Sur iOS : (1) aucune notification de ré-engagement basée sur le contenu suggéré (perte d'un levier de rétention actif sur Android) ; (2) les posts "boostés" (promotion payante, argent réel dépensé par l'utilisateur) ne sont jamais livrés/activés automatiquement en tâche de fond — sur Android ce mécanisme tourne même app fermée ; (3) aucune donnée de temps de visionnage n'est jamais envoyée au serveur, cassant potentiellement tout algorithme de recommandation côté backend qui en dépendrait.
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Enregistrer un identifiant BGAppRefreshTask (ou BGProcessingTask pour la synchro de vues nécessitant plus de temps) dans BGTaskSchedulerPermittedIdentifiers, l'enregistrer via BGTaskScheduler.shared.register(forTaskWithIdentifier:) dans AppDelegate, planifier une soumission après chaque connexion (miroir de HomeActivity.allPermisson()/scheduleDynamicWorker) et à la fermeture de l'app, et enfin câbler ViewEventRepository.record(...) depuis les écrans de lecture du Feed (FeedView) pour que le stockage local cesse d'être mort.
```

```
ID : V5-F-061
PRIORITÉ : P2
DOMAINE : Permissions système iOS (notifications)
FEATURE : La demande d'autorisation de notifications se déclenche avant tout affichage d'écran, à chaque lancement à froid, pour tous les utilisateurs — au lieu d'être liée à l'onboarding comme sur Android
ANDROID SOURCE : Authentification/onboarding/OnboardingFragment.java:127-135 (onViewCreated, APRÈS que le layout ait été affiché : la demande POST_NOTIFICATIONS n'intervient qu'une fois la vue ViewPager/onboarding déjà rendue, uniquement pour les utilisateurs non connectés passant par MainActivity) ; SplashActivity.java:220-247 (les utilisateurs déjà connectés sont routés directement vers HomeActivity, JAMAIS vers MainActivity/OnboardingFragment) ; Activity/ui/HomeActivity.java:571-577 (second point de demande, mais dans viewPager.post(...), donc après affichage du contenu, et no-op si déjà déterminé via checkSelfPermission)
ANDROID BEHAVIOR : Le premier (et généralement seul) moment où l'utilisateur voit le dialogue système d'autorisation de notifications est APRÈS qu'au moins un écran de l'app (le premier slide de l'onboarding, ou le Home déjà affiché) soit visible à l'écran — jamais avant que l'app n'ait rendu quoi que ce soit.
IOS FILES : Sources/TiinverSwift/App/AppDelegate.swift:49-56 (application(_:didFinishLaunchingWithOptions:))
IOS BEHAVIOR : `UNUserNotificationCenter.current().requestAuthorization(...)` est appelé de façon inconditionnelle et synchrone dans `didFinishLaunchingWithOptions`, donc AVANT que la fenêtre/le premier écran (splash, onboarding OU home) n'ait été rendu à l'écran — et ce à CHAQUE lancement à froid de l'app, pour tout utilisateur (connecté ou non), pas seulement lors du tout premier lancement.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Le point d'accroche choisi pour porter la demande de permission est le point d'entrée process-level `didFinishLaunchingWithOptions`, sans distinguer premier lancement vs relance, ni attendre qu'un écran de contenu (onboarding ou home) soit affiché comme le fait systématiquement Android.
IMPACT : Pour un tout nouvel utilisateur, la toute première chose que l'app affiche est potentiellement une boîte de dialogue système opaque demandant l'autorisation de notifications, sans aucun contexte (pas de splash, pas d'onboarding, pas d'explication) — Android ne montre jamais ce dialogue avant qu'au moins un écran de l'app soit visible. Cela réduit le taux d'acceptation (bonne pratique Apple documentée : contextualiser la demande) et diffère du comportement Android réel.
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Déplacer l'appel à `requestAuthorization` hors de `didFinishLaunchingWithOptions`, vers un point après le premier rendu d'écran (ex. `.onAppear` de l'écran d'onboarding ou de Home, à l'image d'Android), pour ne plus interrompre le lancement du process avant tout affichage.
```

```
ID : V5-F-062
PRIORITÉ : P1
DOMAINE : Gestion d'erreur transversale — Notifications
FEATURE : État d'erreur du centre de notifications rendu inatteignable par l'ordre des conditions
ANDROID SOURCE : app/src/main/java/com/tiinver/NotiLikecmt/ShowNoti.java:107-142 (setupObservers — Observer 1 « Room LiveData » lignes 110-122, Observer 2 « état réseau » lignes 125-142)
ANDROID BEHAVIOR : Android distingue explicitement 3 états visuels indépendants : `progressBar` (chargement), `messageEmpty` (liste vide + réseau terminé, `notifNetworkDone && itemCount==0`), et `messageError` (résultat réseau `MyResult.ERROR`, affiché uniquement si `itemCount==0`). `messageError` est rendu `VISIBLE` par l'observateur 2 dès que le type réseau est `ERROR`, indépendamment de l'observateur 1.
IOS FILES : Sources/TiinverSwift/Notifications/NotificationsListView.swift:27-35
IOS BEHAVIOR : La vue teste dans cet ordre : `if isLoading && notifications.isEmpty { spinner } else if notifications.isEmpty { Text("Aucune notification") } else if let error = errorMessage, notifications.isEmpty { Text(error) } else { List }`. La 2ᵉ branche (vide) est un sur-ensemble strict de la condition de garde de la 3ᵉ branche (erreur) — les deux exigent `notifications.isEmpty`, et la vide est testée AVANT. Dès que `isLoading` repasse à `false` (le `defer` de `fetchNotifications` s'exécute toujours), la branche « Aucune notification » capte systématiquement le cas, y compris quand `errorMessage` est non-nil. La 3ᵉ branche (`Text(error)` rouge) est donc du code strictement mort, jamais atteignable.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Erreur d'ordonnancement des conditions `if/else if` : la garde de la branche « vide » (`notifications.isEmpty`) est un sur-ensemble de celle de la branche « erreur » (`errorMessage != nil && notifications.isEmpty`), et elle est placée avant. `NotificationCenterViewModel.fetchNotifications` (lignes 21-52) peuple bien `errorMessage` correctement en cas d'échec réseau/session — le bug est uniquement dans l'ordre d'affichage de `NotificationsListView`.
IMPACT : Au premier lancement de l'écran Notifications sans réseau (ou session expirée), l'utilisateur voit toujours « Aucune notification » — un message neutre qui laisse croire qu'il n'a simplement aucune notification — au lieu du vrai message d'erreur (`error.localizedDescription`) qu'Android affiche distinctement via `messageError`. Aucun moyen de distinguer un compte réellement sans notification d'un échec réseau, contrairement à Android.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Inverser l'ordre des deux branches (tester `errorMessage != nil` avant `notifications.isEmpty`), ou fusionner en un seul bloc qui priorise explicitement l'erreur sur le vide, comme le fait `FeedView.emptyOrStatusState`/`ProfileView.header` (déjà corrects) pour le même pattern.
```

```
ID : V5-F-063
PRIORITÉ : P1
DOMAINE : Gestion d'erreur transversale — Wallet
FEATURE : Erreur de chargement de l'historique des transactions jamais affichée, aucun mécanisme de reprise
ANDROID SOURCE : app/src/main/java/com/tiinver/wallet/WalletActivity.java:124-186 (observer `getLiveData()`, branche `Result.ERROR` ligne 128-129 → `attemptReconnect()` ligne 178-186, relance automatique `executeBackTask()` toutes les 5s via `Handler.postDelayed`)
ANDROID BEHAVIOR : Sur échec réseau du chargement de l'historique (`Result.ERROR`), Android ne montre pas de message d'erreur visible mais relance AUTOMATIQUEMENT la même requête (`executeBackTask()`) après un délai de 5 secondes, indéfiniment, jusqu'à succès — l'écran finit toujours par se remplir dès que le réseau revient, sans action de l'utilisateur.
IOS FILES : Sources/TiinverSwift/Wallet/WalletViewModel.swift:37-52 (loadMore, `errorMessage = error.localizedDescription` ligne 50) ; Sources/TiinverSwift/Wallet/WalletView.swift:1-83 (aucune lecture de `viewModel.errorMessage`, pas de `.refreshable`)
IOS BEHAVIOR : `WalletViewModel.errorMessage` est bien peuplé en cas d'échec (`catch { errorMessage = error.localizedDescription }`), mais `WalletView.swift` ne le lit NULLE PART (grep confirmé sur tout le fichier) : aucun `Text(viewModel.errorMessage)`, aucune alerte. De plus, si l'échec survient au chargement INITIAL (`loadInitial()`, `transactions` reste vide), aucune cellule n'existe pour déclencher le `.onAppear` qui relance `loadMore()` au scroll, et il n'y a pas de `.refreshable` sur la `List` : l'écran reste vide et figé en permanence, sans texte d'erreur, sans bouton réessayer, sans reprise automatique — contrairement à Android qui retente seul toutes les 5s.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `errorMessage` publié côté ViewModel mais jamais consommé côté vue (variable écrite, jamais lue) ; absence du mécanisme `attemptReconnect` porté depuis Android.
IMPACT : Un utilisateur ouvrant Portefeuille avec un réseau instable au moment précis du chargement voit un écran d'historique vide en permanence (solde/gemmes toujours visibles car lus depuis le cache local `UserSession`, mais aucune transaction, aucune explication, aucun moyen de relancer sans quitter/rouvrir l'écran), alors qu'Android se rétablirait automatiquement dans les secondes suivantes.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Afficher `viewModel.errorMessage` (bandeau + bouton « Réessayer », même motif que `FeedView`/`ProfileView`) et/ou ajouter `.refreshable { await viewModel.loadInitial() }`, voire reproduire la reprise automatique à 5s d'Android.
```

```
ID : V5-F-064
PRIORITÉ : P0
DOMAINE : Gestion d'erreur transversale — Settings (Compte)
FEATURE : Déconnexion et suppression de compte purgent les données locales même si l'appel réseau échoue
ANDROID SOURCE : app/src/main/java/com/tiinver/setting/SettingAccountFragment.java:183-206 (logout()/deleteAccount(), déclenchent transportDataBackground avec method="logout"/"deleteaccount") ; app/src/main/java/com/tiinver/Http/transportDataBackground.java:90-96 (onResponse → deleteaccount() = purge locale UNIQUEMENT en cas de succès réseau) et :110-116 (onErrorResponse pour "logout"/"deleteaccount" → dialog.dismiss() seul, PAS de purge, PAS de déconnexion locale)
ANDROID BEHAVIOR : La purge des préférences locales (profil/id/username) et le retour à l'écran de connexion ne surviennent QUE dans `onResponse` (succès réseau confirmé du endpoint `logout`/`deleteaccount`). Sur `onErrorResponse` (échec réseau), Android se contente de fermer la boîte de dialogue de progression — la session et les données locales restent intactes, l'utilisateur reste connecté et peut réessayer.
IOS FILES : Sources/TiinverSwift/Settings/SettingSubViews.swift:35-51 (logout()), :53-61 (deleteAccount())
IOS BEHAVIOR : `try? await ProfileRepository.shared.logout(userId:)` (et l'équivalent `deleteAccount`) avale silencieusement toute erreur réseau — le code continue INCONDITIONNELLEMENT vers `LocalDataPurger.purgeAll()`, `UserSession.shared.clear()`, puis poste `.userDidLogout`, que l'appel serveur ait réussi ou non.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `try?` sur l'appel réseau sans vérifier son succès avant d'exécuter les effets de bord destructeurs (purge Core Data complète + effacement de session), contrairement à Android qui conditionne strictement la purge locale à la confirmation serveur.
IMPACT : Pour « Se déconnecter » : une simple coupure réseau au moment du tap déconnecte quand même l'utilisateur localement et purge tout son cache (messages/roster/notifications, voir `LocalDataPurger`), sans que le serveur en soit informé — désynchronisation silencieuse. Plus grave pour « Supprimer le compte » : si l'appel `deleteaccount` échoue côté serveur (le compte N'EST PAS réellement supprimé), l'utilisateur est quand même éjecté vers l'écran de connexion avec tout son cache local effacé, sans AUCUN message d'erreur — il croit son compte supprimé alors qu'il existe toujours côté serveur, avec risque de confusion majeure (tentative de reconnexion sur un compte qu'il pense supprimé, ou inversement absence de retry alors que la suppression n'a jamais eu lieu).
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Remplacer `try?` par `do/catch` : n'exécuter `LocalDataPurger.purgeAll()`/`UserSession.shared.clear()`/`.userDidLogout` que dans la branche succès, et afficher une erreur explicite (garder l'utilisateur connecté) dans la branche catch, fidèle à `onErrorResponse` d'Android.
```

```
ID : V5-F-065
PRIORITÉ : P2
DOMAINE : Gestion d'erreur transversale — Feed / Profile (blocage)
FEATURE : Échec de blocage/déblocage d'un utilisateur sans aucun retour visuel
ANDROID SOURCE : app/src/main/java/com/tiinver/Activity/ui/MainFragment.java:1747-1751 (block(), onError → Toast R.string.errorLoad) ; app/src/main/java/com/tiinver/uploadPerfilPhoto/UserProfile.java:1133-1137 (block(), onError → même Toast)
ANDROID BEHAVIOR : Les deux points d'entrée Android du blocage (menu « … » du fil, et bouton bloquer du profil) affichent un `Toast` explicite avec le texte `R.string.errorLoad` (« pas de connexion internet, réessayer plus tard », values-fr/strings.xml:4) en cas d'échec réseau de l'appel `block`.
IOS FILES : Sources/TiinverSwift/Feed/FeedViewModel.swift:270-278 (block(_:)) ; Sources/TiinverSwift/Profile/ProfileViewModel.swift:204-212 (toggleBlock())
IOS BEHAVIOR : `FeedViewModel.block` : `guard let blocked = try? await profileRepository.toggleBlock(...), blocked else { return }` — sur échec réseau, la fonction retourne silencieusement, sans aucun état d'erreur publié ni consommé par `FeedView`/`FeedDetailPagerView` (aucune propriété `blockError` n'existe). `ProfileViewModel.toggleBlock` : `let blocked = (try? await repository.toggleBlock(...)) ?? isBlocked` — retombe silencieusement sur l'état précédent, sans erreur affichée par `ProfileView` non plus.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : `try?` sur l'appel réseau de blocage sans branche d'erreur exposée à la vue, alors que d'autres actions du même écran (suppression de post, follow) ont déjà reçu ce traitement lors d'audits précédents (V3-F-107, V4-F-032, V4-F-033) mais pas le blocage lui-même.
IMPACT : Un utilisateur qui tente de bloquer/débloquer quelqu'un avec une coupure réseau momentanée ne voit RIEN se passer (pas de Toast, pas d'alerte, pas de changement d'état) — contrairement à Android qui informe explicitement de l'échec, laissant l'utilisateur sans indication s'il doit réessayer ou si l'action a simplement été ignorée.
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter une propriété d'erreur publiée (ex. `blockError: String?`) sur les deux ViewModels, alimentée dans la branche `catch`, et une alerte dans `FeedView`/`FeedDetailPagerView`/`ProfileView` reprenant le texte `errorLoad` (« pas de connexion internet, réessayer plus tard »), même motif que `deleteError` déjà câblé pour la suppression de post.
```

```
ID : V5-F-066
PRIORITÉ : P2
DOMAINE : Gestion d'erreur transversale — Commentaires (Feed)
FEATURE : Un commentaire dont l'envoi échoue disparaît entièrement sans trace ni indication
ANDROID SOURCE : app/src/main/java/com/tiinver/comments/ui/MyBottomSheetDialogFragment.java:388-436 (SentCmtToServer — ajout OPTIMISTE immédiat à l'adapter, ligne 432, AVANT le réseau) et :209-215 (observer postLiveData, branche ERROR ligne 210-211 — masque juste le spinner, ne retire PAS le commentaire de la liste)
ANDROID BEHAVIOR : Android ajoute le commentaire à la liste visible IMMÉDIATEMENT (avant même l'appel réseau), avec `status=0`. Sur échec réseau (`Result.ERROR`), le commentaire reste affiché dans la liste (jamais retiré), simplement sans passer à `status=1` — l'utilisateur voit toujours son commentaire à l'écran après l'envoi, même en cas d'échec silencieux côté Android.
IOS FILES : Sources/TiinverSwift/Discover/CommentsView.swift:101-111 (send())
IOS BEHAVIOR : `send()` vide `inputText` immédiatement (ligne 104), appelle `try? await CommentRepository.shared.post(...)` (ligne 107, erreur avalée), PUIS recharge inconditionnellement `comments = []` suivi de `loadMore()` depuis le serveur (lignes 108-110) — sans ajout optimiste local préalable. Si l'envoi échoue, le commentaire tapé par l'utilisateur n'apparaît JAMAIS dans la liste (le serveur ne l'a pas persisté) et le champ de saisie est déjà vidé : le texte est perdu intégralement, sans le moindre indice visuel qu'un problème est survenu.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence totale d'ajout optimiste côté iOS (contrairement à Android) combinée à l'avalement silencieux (`try?`) de l'échec réseau du POST — la recharge systématique depuis le serveur après coup masque complètement l'échec.
IMPACT : Sur une coupure réseau momentanée, l'utilisateur tape un commentaire, appuie sur Envoyer, voit le champ se vider — et le commentaire ne réapparaît JAMAIS, sans aucun message d'erreur ni possibilité de retenter avec le texte déjà saisi (à retaper entièrement). C'est une perte de données silencieuse plus sévère que le comportement Android correspondant (qui, bien qu'imparfait — pas de Toast d'erreur pour un commentaire texte non-cadeau —, laisse au moins le commentaire visible à l'écran).
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ajouter le commentaire de façon optimiste à `comments` AVANT l'appel réseau (comme Android), remplacer `try?` par `do/catch`, et sur échec soit retirer l'entrée optimiste avec un message d'erreur explicite, soit la laisser visible avec un indicateur d'échec — dans tous les cas, ne plus vider silencieusement `inputText` sans confirmation de succès.
```

```
ID : V5-F-067
PRIORITÉ : P1
DOMAINE : Notifications — concurrence transversale
FEATURE : Rafraîchissements concurrents de fetchNotifications() sans verrou global → notifications système dupliquées
ANDROID SOURCE : back_sync/MyFirebaseMessagingService.java:109-119 (onMessageReceived → WorkManager.enqueueUniqueWork("FCM_SYNC_WORK", ExistingWorkPolicy.KEEP, syncWork)) ; NotiLikecmt/NotificationRepository.java:89-120 (fetchNotifications, appelé par TiinverSyncWorker.visiteServeur, un seul exécutant garanti par la clé unique WorkManager)
ANDROID BEHAVIOR : Chaque notification FCM entrante enfile un OneTimeWorkRequest sous la clé unique "FCM_SYNC_WORK" avec la politique ExistingWorkPolicy.KEEP : si un travail de synchro est déjà en file/en cours, le nouveau est ignoré. `NotificationRepository.fetchNotifications` (donc `triggerSystemNotifications`, qui affiche les notifications système) ne peut donc jamais s'exécuter deux fois en parallèle, même si plusieurs push FCM arrivent en rafale.
IOS FILES : Sources/TiinverSwift/App/AppDelegate.swift:120-134 (didReceiveRemoteNotification, instancie un `NotificationCenterViewModel()` FRAIS à chaque appel puis appelle fetchNotifications) ; Sources/TiinverSwift/Notifications/NotificationCenterViewModel.swift:21-52 (fetchNotifications, aucun garde `isLoading`/`guard !isLoading` avant de lancer le fetch) et :96-115 (triggerSystemNotifications, lit `row.isRead == 0` sans jamais l'écrire à 1 dans ce chemin) ; Sources/TiinverSwift/Notifications/LocalNotificationBuilder.swift:128-129 (present(_:identifier:) — identifiant par défaut = UUID().uuidString ALÉATOIRE à chaque appel, donc aucune déduplication système possible) ; Sources/TiinverSwift/Notifications/NotificationsListView.swift:43-46 (.task appelle aussi fetchNotifications sur SA PROPRE instance @StateObject, indépendante de celle d'AppDelegate)
IOS BEHAVIOR : Chaque push distant reçu crée une NOUVELLE instance de `NotificationCenterViewModel` (donc un `isLoading` toujours à `false` au départ, sans mémoire des appels précédents) et lance `fetchNotifications`. Si l'écran Notifications est ouvert (sa propre instance lance déjà un fetch via `.task`) ou si plusieurs push arrivent en rafale, plusieurs exécutions de `fetchNotifications`/`triggerSystemNotifications` tournent en parallèle sans aucune synchronisation. Comme `upsert` ne touche jamais `isRead`, chaque exécution concurrente relit `isRead == 0` pour les mêmes lignes AVANT qu'aucune ne l'ait marquée lue, et appelle `LocalNotificationBuilder.present` avec un identifiant UUID distinct à chaque fois — donc AUCUNE déduplication système : la même notification serveur déclenche plusieurs bannières locales identiques affichées à l'utilisateur.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence de verrou/guard de type "single-flight" côté iOS : contrairement à Android qui sérialise via `WorkManager.enqueueUniqueWork(..., KEEP, ...)`, rien n'empêche deux exécutions concurrentes de `fetchNotifications` (deux push rapprochés, ou un push pendant que `NotificationsListView` a déjà son propre fetch en vol) — de plus, `AppDelegate` recrée une instance différente du ViewModel à chaque appel, rendant même un simple flag `isLoading` sur l'instance inefficace comme protection.
IMPACT : L'utilisateur reçoit des notifications système dupliquées (2 bannières identiques pour le même like/commentaire/follow) lors de rafales de push — bug visible et dérangeant, sans perte de données mais avec une expérience utilisateur clairement dégradée par rapport à Android.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ajouter une sérialisation globale (ex. un `Task` unique partagé/`actor` avec déduplication par identifiant, ou un flag statique partagé entre toutes les instances) autour de `fetchNotifications`, et/ou faire écrire `triggerSystemNotifications` un marqueur "déjà notifié" avant de présenter, pour empêcher deux exécutions concurrentes de notifier la même entrée.
```

```
ID : V5-F-068
PRIORITÉ : P1
DOMAINE : Messagerie — concurrence transversale
FEATURE : Double-tap sur le bouton d'abonnement/renouvellement de groupe payant → double débit local de pièces et double requête réseau
ANDROID SOURCE : messagerie/ui/adapter/MessageListAdapter.java:322-365 (Subscribe.bind, subscribe.setOnClickListener → td.Post(..., "group/subscribe", Callback) ; onLoading() ligne 361-364 exécute `subscribe.setVisibility(GONE); progress.setVisibility(VISIBLE)` de façon synchrone avant l'appel réseau) et :420+ (RenewSubscription, même motif)
ANDROID BEHAVIOR : Dès le clic, `onLoading()` masque immédiatement le bouton `subscribe` et affiche une barre de progression — le bouton n'est donc plus dans la hiérarchie de vue cliquable pendant toute la durée de l'appel réseau, ce qui empêche mécaniquement un second appui de déclencher un second débit tant que le premier n'est pas résolu (`onResonse`/`onError` le remet visible).
IOS FILES : Sources/TiinverSwift/Messagerie/ChatBubbleViews.swift:369-385 (SubscriptionBannerRow — Button toujours actif, aucun état `isLoading`/`disabled`) ; Sources/TiinverSwift/Messagerie/ChatViewModel.swift:158-179 (resolveGroupSubscription — vérifie `UserSession.shared.coinsAmount > Double(price)` PUIS lance un `Task` réseau, sans aucun flag "requête déjà en cours pour cet item" ; ligne 173 `UserSession.shared.coinsAmount -= Double(price)` exécuté APRÈS chaque appel réseau réussi, sans idempotence)
IOS BEHAVIOR : `SubscriptionBannerRow` reste un bouton actif pendant toute la durée de `resolveGroupSubscription` (pas de ProgressView de remplacement contrairement au bouton d'export/suppression de fond d'Animems qui, eux, désactivent bien le bouton). Un double-tap rapide sur "S'abonner"/"Renouveler l'abonnement" avant que la bannière ne soit retirée de `items` (retrait seulement après la fin du premier `Task`, ligne 171) déclenche DEUX `Task` concurrents : les deux lisent `UserSession.shared.coinsAmount` (encore non décrémenté par le premier) et passent la garde, envoient chacun leur `POST group/subscribe` (ou `renewsubscription`), puis chacun décrémente `UserSession.shared.coinsAmount -= Double(price)` — un lire-puis-écrire non atomique sur le compteur de pièces qui aboutit à un double débit local pour un seul abonnement voulu par l'utilisateur.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence de protection contre le double-tap côté iOS (ni désactivation visuelle du bouton, ni verrou logique par `itemId`/`groupId` dans `resolveGroupSubscription`), alors qu'Android neutralise physiquement le bouton dès le premier clic via `onLoading()`.
IMPACT : Perte financière locale pour l'utilisateur (solde de pièces débité deux fois pour un seul abonnement, potentiellement deux requêtes serveur `group/subscribe`/`group/renewsubscription` distinctes) sur un double-tap ordinaire — scénario UI courant et facilement déclenché par accident.
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Désactiver visuellement le bouton (ou le remplacer par un indicateur de chargement) dès le premier tap, ET ajouter un verrou logique (ex. Set<String> des `itemId` en cours de traitement) dans `resolveGroupSubscription` pour ignorer tout appel concurrent sur le même item, comme le fait implicitement Android en masquant le bouton.
```

```
ID : V5-F-069
PRIORITÉ : P2
DOMAINE : Messagerie — concurrence transversale
FEATURE : Réapparition d'une bulle média pendant un upload/download en vol → nouvel envoi/téléchargement concurrent du même fichier, sans déduplication
ANDROID SOURCE : messagerie/ui/ChatFragmentTest.java:2937-2963 (onUpload/onDowload → addingUploadingFileToQueue/addingDownloadingFileToQueue, gardées par `uniqueUploadSet.add(msg)`/`uniqueDowloadSet.add(msg)` — n'enfilent dans `uploadFileQueue`/`downloadFileQueue` QUE si le message n'y est pas déjà présent, empêchant toute mise en file redondante du même message tant qu'il n'en est pas retiré)
ANDROID BEHAVIOR : `MessageActionListener.onUpload`/`onDowload` (rappelés à chaque (re)liaison de vue `onBindViewHolder`, l'équivalent Android d'un `onAppear` répété au scroll) passent systématiquement par `uniqueUploadSet`/`uniqueDowloadSet` avant d'enfiler le message — un même `MessageLib` déjà en file (upload/téléchargement en cours) ne peut pas être réenfilé et redéclencher un second envoi concurrent tant qu'il n'a pas été traité.
IOS FILES : Sources/TiinverSwift/Messagerie/ChatViewModel.swift:479-496 (handleAppear, appelé depuis Sources/TiinverSwift/Messagerie/ChatView.swift:195 via `onAppearEffects`, câblé sur `.onAppear` de ChatBubbleViews.swift:62 — SwiftUI `List` réexécute `.onAppear` à chaque fois qu'une ligne redevient visible au scroll) ; ChatViewModel.swift:531-557 (requestUpload) et :567-601 (requestDownload) — aucun état "upload/download en cours pour ce messageId" tracké nulle part dans la classe
IOS BEHAVIOR : `handleAppear` relance inconditionnellement `requestUpload`/`requestDownload` (nouveau `Task`) à CHAQUE `.onAppear` tant que `mlib.isFileUploaded`/`isFileDownloaded` reste à 0 côté modèle — valeur qui ne passe à 1 qu'à la fin du `Task` en cours. Si la bulle défile hors écran puis revient (scénario ordinaire dans une longue conversation, pendant l'upload d'une vidéo qui peut prendre plusieurs secondes), un second `Task` d'upload/téléchargement démarre en parallèle du premier pour le MÊME message : deux appels `ChatMediaUploadService.shared.upload(...)` (ou deux `URLSession.download(from:)`) concurrents sur le même fichier, deux écritures concurrentes de `updateFileUploaded`/`updateFileDownloaded` en Core Data, et potentiellement deux émissions socket `self.send(updated)` du même message.
LOGIQUE CONFIRMÉE ATTEIGNABLE : Oui
CAUSE : Absence, côté iOS, de l'équivalent du `uniqueUploadSet`/`uniqueDowloadSet` Android — aucun mécanisme ne marque un `messageId` comme "déjà en cours de traitement" pour empêcher une seconde tentative concurrente déclenchée par une réapparition de la vue.
IMPACT : Upload/téléchargement CDN dupliqué (bande passante et stockage gaspillés), écritures Core Data concurrentes non ordonnées sur le même enregistrement, et risque de double émission socket du même message vers le pair (mitigé côté réception par la dé-duplication par `messageId`, mais pas côté émetteur/CDN).
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter un `Set<String>` (ou dictionnaire d'état) de messageId actuellement en upload/téléchargement dans `ChatViewModel`, consulté et alimenté par `requestUpload`/`requestDownload` avant de lancer un nouveau `Task`, reproduisant la garde `uniqueUploadSet`/`uniqueDowloadSet` d'Android.
```
