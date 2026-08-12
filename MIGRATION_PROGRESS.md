# Suivi de migration Tiinver Android → iOS Swift

Dernière mise à jour : 2026-08-12 12:00
Statut global : **CHECKPOINT 2 VALIDÉ (2026-08-11)** — build Codemagic réussi, aucune erreur de
compilation restante sur les modules 1-8 (5 itérations de correction au total : `FirebaseCore`/
`CoreDataFetchable` pour le Checkpoint 1, puis `MaskPreviewEditorPanelState`/
`AnimemesGestureController` (`CGFloat`/`Int`)/`LayerRenderer` (`Float`/`CGFloat`) pour ce
Checkpoint 2 — voir "Erreurs rencontrées et résolues" pour le détail de chacune). MODULE 7
(Caméra) FERMÉ (2026-08-10). MODULE 8 (Moteur Animems) FERMÉ (2026-08-11). MODULE 9 (Éditeur photo
simple) FERMÉ (2026-08-11). MODULE 10 (Trim/Timeline/Waveform) FERMÉ (2026-08-11) — géométrie de
trim portée en entier, export vidéo différé (décision AVFoundation). **MODULE 11 (Messagerie/Chat
UI) FERMÉ (2026-08-12), avec réserves honnêtes** — 32 398 lignes, le plus gros module du projet.
Couche protocole/persistance/routage (Socket.IO, `ChatManager`/`ChatRepository`/`RosterManager`/
`MessageLib`/`MessagePacket`) ENTIÈREMENT portée et vérifiée (4 bugs trouvés et corrigés au total).
Couche UI (`MessageListAdapter.java` + 9 `ViewHolder`, `ChatFragmentTest.java`, 4433 lignes)
également portée (bulles SwiftUI par type de message, `ChatViewModel`/`ChatView` — pagination,
temps réel, envoi, citation, sélection/suppression). Réserves documentées : transfert réel upload/
download, sélecteurs GIF/cadeau, zoom média, Message Graphic (module 14), paiement d'abonnement
(module 15), écran de liste des conversations (hors périmètre explicite) — voir tableau détaillé et
journal 2026-08-12. **MODULE 12 (Appels WebRTC/CallKit) FERMÉ (2026-08-12), avec réserves honnêtes**
— même session : moteur WebRTC (`RTConnection2.java`, 801 lignes), orchestration
(`CallService`/`CallViewModel`/`CallActivity`/`IncomingCallActivity`, 2071 lignes cumulées) tous lus
en entier, `CXProvider`/`PKPushRegistry`/API WebRTC iOS vérifiées contre la documentation Apple
réelle et les headers Objective-C du framework (pas devinées) — développement largement NEUF
(CallKit/PushKit sans équivalent Android). Bouton d'appel + présentation `CallView` câblés dans
`ChatView` (module 11), flux déclenchable de bout en bout. **2026-08-12 (suite)** : enregistrement
du jeton VoIP câblé (`Calls/VoIPTokenRegistrar.swift`, `POST user/voip-token`) — implémentation
CLIENT complète, spécification serveur détaillée dans la nouvelle section "Backend à implémenter —
PushKit/VoIP" (backend PHP séparé, PAS modifié). **MODULES 13 (Shareboard) ET 14 (Message Graphic)
FERMÉS (2026-08-12), même session** — confirmé que les deux partagent LITTÉRALEMENT le même moteur
de rendu (`PBSView.java`, 1411 lignes — pas `PBSCompound.java` comme d'abord supposé, corrigé après
lecture complète) et la même connexion WebRTC que les appels (`RTConnection2` réutilisé en instance
propre, pas le singleton Android). 1 bug data-channel réel trouvé et corrigé dans
`Calls/WebRTCConnection.swift` (delegate jamais assigné, dormant depuis le module 12) avant d'écrire
le code Shareboard. 7 fichiers Swift neufs dans `Sources/TiinverSwift/Shareboard/`. Voir tableau
détaillé et journal 2026-08-12 pour le détail complet, les portées réduites documentées (pinch/
rotate/suppression non live-synced, décoratif différé) et le gap restant (rejoindre un Shareboard en
tant qu'invité). Voir tableau détaillé et journal 2026-08-12.
**MODULES 15 (Wallet), 16 (AdMob), 17 (Profil/Réglages) ET 18 (Divers) FERMÉS (2026-08-12), même
session.** Les 18 modules de l'ordre de portage sont désormais tous `[x]`. Découverte majeure module
15 : le mécanisme d'achat de pièces réellement actif côté Android (mobile money/crypto hors
application + ID de transaction manuel) est un vrai risque de conformité App Store 3.1.1/3.1.5,
remplacé par StoreKit 2 sur instruction explicite — voir "⚠️ AUDIT CONFORMITÉ APP STORE". Module 18
fermé avec des réserves explicites (couverture fonctionnelle priorisée sur l'exhaustivité de lecture
d'un sous-module à ~54 fichiers). Voir "RÉSERVES AVANT CHECKPOINT 3" dans "Prochaine action à faire"
pour le détail complet.
Statut Checkpoint 3 : **NE PEUT PAS être validé depuis cet environnement** (aucun accès macOS/Xcode
sur toute la durée de ce portage, du premier au dernier module) — le code est écrit pour les 18
modules mais AUCUNE compilation réelle n'a eu lieu depuis le Checkpoint 2 (modules 9-18 inclus).
Prochaine étape obligatoire : compilation Xcode réelle dès qu'un accès macOS existe.

## ⚠️ Contrainte d'environnement (lire avant toute reprise de session)

Cette migration est conduite depuis une machine **Windows**, sans accès à macOS/Xcode.
Conséquences directes sur la méthodologie :
- Tout le code Swift écrit ici est relu attentivement mais **jamais compilé** dans cet
  environnement (`xcodebuild` n'existe pas sur Windows). Le statut `ÉCRIT (NON COMPILÉ)`
  dans le tableau ci-dessous signifie : code porté fidèlement depuis la source Android,
  cohérent à la lecture, mais dont la compilation réelle n'a pas pu être vérifiée.
- Dès qu'un accès macOS est disponible : lancer `xcodegen generate` puis un build complet
  (voir `docs/BUILD_INSTRUCTIONS.md`) AVANT de continuer le portage, pour rattraper toutes
  les erreurs de compilation accumulées d'un coup plutôt qu'une par une sans outil.
- Le projet Xcode n'existe pas en tant que `.xcodeproj` (impossible à produire sans Xcode) ;
  il est décrit en texte via `project.yml` (format XcodeGen), qui génère le `.xcodeproj` à
  l'ouverture sur macOS. Voir `docs/BUILD_INSTRUCTIONS.md`.
- Ne jamais interpréter l'absence d'erreur signalée comme une preuve de compilation réussie
  dans ce contexte — seule une exécution réelle de `xcodebuild` sur macOS fait foi.

## Règle de compilation par checkpoint

La migration est découpée en 3 checkpoints de compilation obligatoires, basés sur les modules
de l'ordre de portage (section "Ordre de portage" ci-dessous) :

- **Checkpoint 1** : après la fin complète des modules 1 à 6 (Infrastructure réseau/auth → Feed vidéo) —
  **[x] VALIDÉ le 2026-08-10** (build Codemagic #6a7a2aabd5ae67eb2a755de2 réussi, aucune erreur —
  voir "CHECKPOINT 1 ATTEINT" plus bas pour le détail complet).
- **Checkpoint 2** : initialement prévu après la fin complète des modules 7 à 12 — **[x] VALIDÉ
  le 2026-08-11, mais sur un périmètre RÉDUIT aux modules 7+8 uniquement** (build Codemagic
  réussi après 5 itérations de correction — voir "Erreurs rencontrées et résolues" et
  "CHECKPOINT 2 ATTEINT ET VALIDÉ" plus bas pour le détail). Décision explicite de l'utilisateur :
  valider le checkpoint à ce stade plutôt que d'attendre la fin du module 12, pour rattraper les
  erreurs de compilation du plus gros module du projet (module 8, Animems) sans les laisser
  s'accumuler avec 4 modules supplémentaires. Conséquence directe : les modules 9 à 12 seront
  portés SANS compilation intermédiaire, jusqu'au Checkpoint 3.
- **Checkpoint 3** : après la fin complète des modules 9 à 18 (Éditeur photo → Divers) —
  **prochain arrêt obligatoire, pas encore atteint.** Portée élargie par rapport au découpage
  initial (13-18) du fait de la validation anticipée du Checkpoint 2 ci-dessus — reste le
  dernier arrêt de compilation avant la fin de projet.

Comportement attendu à chaque checkpoint :

1. NE PAS commencer le module suivant tant que le checkpoint n'est pas validé.
2. Marquer clairement dans ce fichier : "CHECKPOINT [1/2/3] ATTEINT — build requis avant de
   continuer", avec la date.
3. S'arrêter et attendre une compilation réelle sur macOS (via l'utilisateur, Codemagic, ou
   GitHub Actions — hors de cet environnement Windows). Documenter explicitement : "En attente
   de build macOS pour Checkpoint [N] — ne pas reprendre le portage avant confirmation de build
   réussi ou liste d'erreurs à corriger."
4. Si l'utilisateur revient avec une liste d'erreurs de compilation : les corriger TOUTES avant
   de considérer le checkpoint comme validé et de passer au module suivant. Documenter chaque
   correction dans la section "Erreurs rencontrées et résolues".
5. Si l'utilisateur revient avec "build réussi, aucune erreur" : marquer le checkpoint comme
   VALIDÉ dans ce fichier, avec la date, puis reprendre normalement l'ordre de portage à partir
   du module suivant.
6. IMPORTANT : entre deux checkpoints, le travail continue en autonomie complète sur les modules
   comme avant (pas de pause intermédiaire, pas de demande de confirmation) — seule l'arrivée au
   module marquant la fin du checkpoint courant déclenche l'arrêt (voir liste ci-dessus : le
   découpage n'est plus strictement 6/12/18 depuis la validation anticipée du Checkpoint 2, qui a
   avancé la frontière du Checkpoint 3 à "après le module 18" en couvrant les modules 9-18 d'un
   seul bloc).

Cette règle remplace/précise le point 5 de "Prochaine action à faire" plus bas (qui évoquait un
point de contrôle "dès qu'un accès macOS devient possible" de façon plus ponctuelle) : désormais
les points de contrôle sont fixés d'avance (initialement 6/12/18, révisé en 6/8/18 après la
validation anticipée du Checkpoint 2 ci-dessus), pas laissés à l'appréciation
au fil de l'eau.

## Références

- Analyse de faisabilité complète : `C:\Users\helen\AndroidStudioProjects\tiinver\TIINVER_IOS_PORT_ANALYSIS.md`
- Clarification périmètre Animems + librairies : `C:\Users\helen\AndroidStudioProjects\tiinver\TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`
- Ces deux fichiers font autorité sur : fichiers actifs vs morts, découpage par module,
  librairies iOS recommandées, comportements réseau non négociables. Toujours s'y référer
  avant de porter un fichier dont le statut (actif/mort) n'est pas évident.

## Ordre de portage (ne pas dévier sans raison documentée)

1. [x] Infrastructure réseau + auth (URLSession/Alamofire, Socket.IO-Client-Swift, Keychain) — écrit, non compilé (voir contrainte d'environnement)
2. [x] Stockage local (Core Data/SwiftData) — écrit, non compilé (voir contrainte d'environnement)
3. [x] Auth / Onboarding — écrit, non compilé (tous les écrans atteignables portés — voir décision "MyCodeConfirmFragment mort")
4. [x] Notifications push — écrit, non compilé (fichiers de synchro en arrière-plan lus et confirmés hors-sujet, voir décisions)
5. [x] UI Shell / navigation — écrit, non compilé (écrans notifications/profil réels ; onglets Chat/Créateurs restent des placeholders, hors périmètre modules 1-6)
6. [x] Feed vidéo (AVPlayer + cache/preload) — écrit, non compilé — PARTIEL ASSUMÉ (lecteur/cache/préchargement par fenêtre faits ; interactions like/commentaire/partage explicitement différées, `ActivityAdapter.java` 956 lignes confirmé hors périmètre du Checkpoint 1, voir décision)
7. [x] Caméra + pipeline filtres GPU (MetalPetal) — écrit, non compilé — FERMÉ (2026-08-10) : capture
   `AVCaptureSession`, pipeline de filtres MetalPetal (22 filtres actifs portés), enregistrement
   `AVAssetWriter` (relu en entier, 2 lacunes corrigées), bouton de capture reconstitué PUIS
   vérifié contre `CircleCaptureButton.java` (seuil 1s corrigé), sélecteur galerie réel
   (`PHPickerViewController`), branchement navigation réel retrouvé et câblé (`FeedView.swift`
   FAB → `CameraActivity`, pas une position `HomeActivity` supposée). PARTIEL ASSUMÉ comme les
   modules précédents : écrans consommateurs post-capture (édition photo/trim vidéo/Animems)
   laissés en closures TODO, ces modules n'existent pas encore — voir tableau détaillé.
8. [x] Moteur Animems — cœur éditeur (Core Graphics, PAS Metal — voir décision d'architecture) —
   écrit, non compilé — **FERMÉ (2026-08-11)**. Note honnête sur la nature de ce "fermé", comme
   pour les modules 1-7 : chemin bout-en-bout RÉEL existe (modèle → gestes → rendu → export →
   fusion GIF) pour les types BITMAP/SHAPE_RECT/SHAPE_CIRCLE/SHAPE_LINE/TEXT/STICKER — la majorité
   observable de ce qu'un utilisateur crée avec l'éditeur. PARTIEL ASSUMÉ, comme les modules
   précédents : PATH/LINE/CLIP/ERASE non branchés au geste tactile (conçu mais pas relié aux 4
   types dessin-libre) ; SwiftUI de rendu/interaction des ~14 vues custom d'édition PAS construite
   (seule leur logique d'état/géométrie/math est portée — `TimelineViewModel`,
   `LayerEditorPanelState`, etc. — la construction visuelle proprement dite nécessite un
   simulateur pour être vérifiée, comme documenté pour chaque fichier concerné) ; 6 sous-systèmes
   secondaires découverts en finissant la lecture d'`AnimemesCompound.java` (Motion Templates,
   persistance disque du recompose, tutoriel, génération procédurale de mouvement, génération IA,
   suppression d'arrière-plan ML Kit) explicitement NON lus ni portés — voir tableau détaillé et
   journal pour la liste complète et la justification de chaque report. Catégorie A du rapport
   `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` (≈24 942 lignes Android, 10-13,5 semaines-ingénieur
   estimées) — le portage réalisé ici couvre le CŒUR fonctionnel, pas l'exhaustivité du rapport.
9. [x] Éditeur photo simple (Vision framework pour suppression d'arrière-plan) — écrit, non
   compilé — PARTIEL ASSUMÉ (2026-08-11) : décisions d'architecture actées et vérifiées
   (`TOCropViewController` remplace le recadreur Android vendorisé ~5000 lignes,
   `VNGeneratePersonSegmentationRequest` remplace ML Kit `SubjectSegmenter`), infrastructure de
   recadrage/rotation/suppression d'arrière-plan écrite et fonctionnellement complète. PAS PORTÉ,
   décision honnête : l'écran d'édition principal (stickers/texte/peinture par-dessus la photo,
   `ImageEditorCompound.java`/`ImageViewCanvas.java`, ~3169 lignes) — chevauchement CONFIRMÉ avec
   le modèle déjà porté au module 8 (`AnimationObjectData`/`AnimationComposer`/`LayerRenderer`/
   `PaintCaptureController`/`ProTextEditorState`), mais nécessite le même traitement méthodique
   multi-passage que `MemesView2.java`/`AnimemesCompound.java` en leur temps — reporté à une passe
   dédiée plutôt que rushé pour tenir le rythme des modules 10-12, voir tableau détaillé.
10. [x] Trim / Timeline / Waveform — écrit, non compilé — PARTIEL ASSUMÉ (2026-08-11) : géométrie
    de la fenêtre de trim portée en entier (`ProTimelineViewModel.swift`, port direct de
    `ProTimelineView.java`, 763 lignes lues intégralement) + état rotation/flip/ratio
    (`VideoTrimState.swift`). **Découverte de portée** : `WaveformSeekBar.java` (cité comme risque
    élevé dans le rapport de faisabilité aux côtés du trimmer) appartient en réalité au module 11
    (Messagerie) — confirmé par grep, ses seuls consommateurs sont `BubbleMessageAudioCompound.java`/
    `MessageAudioViewHolder.java` (bulles de messages vocaux), pas le trimmer vidéo. PAS PORTÉ,
    décision d'architecture (comme MetalPetal/Vision/TOCropViewController) : l'export vidéo
    lui-même (`AVAssetExportSession`/`AVMutableVideoComposition` natifs, remplaçant le pipeline
    `VideoTransformer`/`Utils/media/**` Android — dont le cluster "v2" est confirmé MORT/non
    branché prod par `TIINVER_IOS_PORT_ANALYSIS.md` §2.2) et l'extraction de vignettes
    (`AVAssetImageGenerator` natif remplaçant `VideoFrameExtractorCodecAsync.java`, 355 lignes) —
    non écrits cette passe, voir tableau détaillé pour la justification complète et les fichiers
    Android restants (`CropOverlayView.java` du recadrage vidéo, `VideoTrimmerView.java` au-delà de
    l'état déjà porté).
11. [x] Messagerie / Chat UI — FERMÉ (2026-08-12), avec réserves honnêtes détaillées ci-dessous et
    dans le tableau. 32 398 lignes au total (le plus gros module du projet). **Couche protocole/
    persistance/routage ENTIÈREMENT portée et vérifiée** (`ChatManager.java`/`ChatRepository.java`/
    `MessageLib.java`/`MessagePacket.java`/`RosterManager.java`/`ConversationIdGenerator.java`/
    `Profile.java`/`ChatModel`+3 modèles annexes — 4 bugs trouvés et corrigés, 2 côté Android
    reproduits fidèlement une fois compris, 2 dans ce portage même). **Couche UI portée** :
    `MessageListAdapter.java` (1353 lignes) + ses 9 `ViewHolder` (1328 lignes) → bulles SwiftUI par
    type de message (texte/audio/photo/gif/sticker/vidéo/cadeau/appel manqué/messages système/
    séparateur de date) ; `ChatFragmentTest.java` (3080 lignes) → `ChatViewModel`/`ChatView`
    (pagination, envoi/réception temps réel, citation, sélection/suppression, frappe). **Réserves
    documentées, PAS des oublis silencieux** : transfert réel upload/download (`UploadFileOrDataService.
    java`/`DownloadReceiver.java` pas lus, endpoints inconnus), sélecteurs GIF/cadeau réels
    (`StickerPickerDialog.java`/`GiftGalleryView.java` pas lus), zoom média plein écran
    (`ImageExpanderAnim` pas lu), rendu Message Graphic (module 14 par conception), paiement
    d'abonnement groupe (module 15 Wallet), écran de liste des conversations (fichier séparé, hors
    périmètre explicite de cette passe — `RosterModel` accepté en entrée, prêt à être branché).
12. [x] Appels WebRTC + CallKit — FERMÉ (2026-08-12), avec réserves honnêtes. `RTConnection2.java` (801
    lignes), `CallService.java` (835), `CallViewModel.java` (110), `CallActivity.java` (592),
    `IncomingCallActivity.java` (534) tous lus en entier — `RTConnection.java`/`RTConnection3.java`/
    `CallService2.java` confirmés morts par grep, pas lus. Moteur WebRTC (`WebRTCConnection.swift`),
    signalisation socket (`ChatRepository.swift` étendu), CallKit (`CallKitManager.swift`), PushKit
    (`VoIPPushManager.swift`), orchestration (`CallCoordinator.swift`) et écran post-décroché
    (`CallView.swift`) écrits et vérifiés contre les API Apple/WebRTC réelles (pas devinées — voir
    tableau détaillé et journal 2026-08-12). **Développement largement NEUF** (CallKit/PushKit
    n'ont aucun équivalent Android), pas un simple portage — risque "Élevé" du rapport de
    faisabilité confirmé justifié. Bouton d'appel + présentation `CallView` câblés dans `ChatView`
    (module 11). **2026-08-12 (suite)** : enregistrement du jeton VoIP câblé côté client
    (`VoIPTokenRegistrar.swift`, `POST user/voip-token`) — spécification serveur complète (endpoint,
    payload, prérequis APNs VoIP) dans la nouvelle section "Backend à implémenter — PushKit/VoIP" ;
    implémentation serveur elle-même hors périmètre (backend PHP séparé). Réserve restante :
    vérification de compilation réelle toujours impossible (pas d'accès macOS).
13. [x] Shareboard (PBS) — FERMÉ (2026-08-12). Lecture complète cette session :
    `GraphicMessageCodec.java` (266)/`CompactTouchEvent.java`/`CompactEditorData.java` (codec),
    `PBSCompound.java` (899 — PAS le moteur de rendu comme supposé à la découverte initiale, voir
    correction ci-dessous), `PBSView.java` (1411, LE vrai moteur `onDraw`/`onTouch`),
    `MotionEventData.java`/`EditorData.java`/`Page.java` (modèles), `FragmentPbs.java` (810, entier
    cette fois), `BannerModel.java`/`AudioData.java` (structure). **Correction de la découverte du
    18-08-12 (même session, avant lecture complète)** : `FragmentPbs.webrtc =
    RTConnection2.getInstance(requireActivity())` réutilise en réalité le MÊME SINGLETON que
    `CallService` (module 12), PAS une instance séparée — l'hypothèse "canal WebRTC dédié
    indépendant" de la découverte initiale était fausse, corrigée en lisant `FragmentPbs.java` en
    entier. `PBSCompound` est la barre d'outils/le contrôleur (`FrameLayout` + `onClick`), PAS le
    moteur de rendu — c'est `PBSView` (`onDraw`/`onTouch`, 1411 lignes) qu'il délègue et qui fait le
    vrai travail. Voir le journal détaillé et "Backend/architecture — Shareboard/Message Graphic"
    plus bas pour l'ensemble des décisions de portage, écarts documentés et bug corrigé dans
    `WebRTCConnection.swift` (canal de données jamais câblé jusqu'ici, dormant au module 12).
14. [x] Message Graphic — FERMÉ (2026-08-12), dans la MÊME passe que le module 13 : confirmé que
    les deux partagent LITTÉRALEMENT le même moteur (`PBSCompound`/`PBSView`, voir
    `FragmentMessageGraphic.java`, 295 lignes lues en entier) — la découverte initiale ("13 et 14
    plus imbriqués que prévu") était juste sur ce point précis, même si le détail du couplage
    (canal WebRTC séparé) était erroné. Voir journal.
15. [x] Wallet / Paiements — FERMÉ (2026-08-12), avec une **découverte de conformité majeure qui
    corrige la prémisse du rapport de faisabilité initial** — voir "⚠️ AUDIT CONFORMITÉ APP STORE —
    Wallet/Paiements" juste en dessous, À LIRE avant toute soumission. `BuyCoinsActivity.java`
    (le fichier que l'analyse §3.8 identifiait comme "le seul utilisant BillingClient, à porter
    vers StoreKit 2") est en réalité DU CODE MORT (absent d'`AndroidManifest.xml`, entièrement
    commenté dans le fichier lui-même) — le vrai flux d'achat live est un mécanisme mobile money/
    crypto avec ID de transaction saisi à la main, remplacé ici par StoreKit 2 sur instruction
    explicite (PAS un portage 1:1). Retrait/transfert/conversion/parrainage/récompense pub PORTÉS
    FIDÈLEMENT depuis `WithdrawActivity`/`TransfertCoinsActivity`/`ConversionActivity`/
    `ReferralActivity`/`EarnCoinsActivity` (tous lus en entier).
16. [x] AdMob — FERMÉ (2026-08-12). Inventaire complet repris de TIINVER_IOS_PORT_ANALYSIS.md §5
    (déjà cartographié avant cette session) : bannière (11 écrans), rewarded (`EarnCoinsActivity` +
    mini-jeu feed module 6, PAS rétro-câblé), rewarded interstitiel (Withdraw/Transfert/Conversion,
    motif identique dans les 3, déjà lus en entier au module 15), native (feed, pas câblé — module 6
    déjà fermé). **Interstitiel classique confirmé mort** (incertitude §5.2 levée par grep exhaustif
    des 3 fichiers wallet). API Google Mobile Ads SDK iOS (`BannerView`/`RewardedAd`/
    `RewardedInterstitialAd`/`NativeAd`/`AdLoader`, nomenclature MODERNE sans préfixe `GAD*`)
    vérifiée contre l'exemple officiel Google **SwiftUI** (`googleads/googleads-mobile-ios-examples`,
    `Swift/advanced/SwiftUIDemo/`) avant écriture — IDs de test recopiés et confirmés verbatim
    contre le code source réel, pas devinés.
17. [x] Profil / Réglages — FERMÉ (2026-08-12), avec réserves honnêtes. `UserProfile.java` (1198),
    `AddPerfilFoto.java` (1164, sections upload photo NON portées), `EditProfile.java` (190, entier),
    `EditPersonalInformation.java` (235, entier), `ProfileRepository.java` (entier),
    `SettingsActivity.java` (193, entier) + 6 des 8 fragments de réglages LUS EN ENTIER
    (`SettingPrivacityFragment`/`SettingChatFragment`/`SettingNotificationFragment`/
    `SettingAccountFragment`/`SettingAdvertisementFragment`, `SettingStorageFragment` partiel).
    **Découvertes de code mort en cascade, dans le même esprit que les modules précédents** :
    `SettingPrivacityFragment` — 5 des 6 réglages de confidentialité (dernière connexion/photo/
    appels/groupes/statut) sont ENTIÈREMENT commentés dans le source, seul le bouton "compte privé"
    est réel ; `SettingChatFragment` (menu "Chat") ne contient en réalité QUE le thème clair/sombre
    de l'app, aucun réglage de chat. `UserProfile.java` (profil d'autrui) et `AddPerfilFoto.java`
    (son propre profil) consolidés en UN SEUL `ProfileView` paramétré, pas deux écrans séparés
    (simplification délibérée documentée dans `ProfileViewModel.swift`). **PAS porté, gaps
    honnêtes** : upload de photo de profil (transfert multipart, même gap que le module 11) ;
    `FollowList` (liste abonnés/abonnements) ; `HashtagProfile.java` (964 lignes, PAS lu — grille de
    posts par hashtag, endpoint identifié mais écran non construit) ; `CategoryActivity`
    (sélection de catégorie de profil) ; détail granulaire de `SettingStorageFragment`
    (sélection multiple par type de média, 292 lignes, lu partiellement) ; contenu réel de
    `SettingHelpFragment`/`SettingAboutFragment` (pas lus, écrans informatifs statiques posés en
    stub). Voir tableau détaillé pour le détail complet fichier par fichier.
18. [x] Divers — FERMÉ (2026-08-12) AVEC RÉSERVES IMPORTANTES ET EXPLICITES. Sous-module ~54 fichiers
    Android au total (`Recherche` 11, `contacts` 14, `Following` 3, `comments` 12, `certification`
    10, `report` 3, `StatisticsActivity` 1) — **portée volontairement priorisée sur les fonctions
    directement rattachées à des écrans déjà fermés (Profil, module 17) plutôt qu'une lecture
    exhaustive des 54 fichiers**, compte tenu du volume cumulé des modules 15-18 traités dans cette
    même session. RÉELLEMENT portés, avec lecture complète des fichiers réseau/modèle déterminants :
    Recherche universelle (`RechercheTiinver.java`, réseau lu en entier — **`RechercheTiinver2.java`,
    681 lignes, CONFIRMÉ MORT par grep, même méthode que les autres clusters "v2"**), Follow (liste
    abonnés/abonnements, entier), Report (signalement, entier), Comments (lecture/publication/
    réponse, entier — envoi de "commentaire cadeau" payant NON porté), Certification (CONSULTATION
    du statut seulement — soumission avec upload de justificatif PAS portée, même gap que les
    transferts de fichiers des modules 11/17). **PAS portés du tout, repérés seulement** : Contacts
    (`ConnectedUsersRepository`/`ContactManager` — en réalité un sélecteur de MEMBRES DE GROUPE pour
    la messagerie, pas une fonctionnalité "Divers" autonome, endpoint `connectedusers/{userId}`
    identifié) ; Statistiques créateur (`StatisticsActivity.java`, AUCUN appel réseau trouvé —
    vraisemblablement une agrégation locale sur les posts de l'utilisateur, pas lu en détail) ;
    "boost interne" (`advertising/`, 9 fichiers/2026 lignes, PAS repéré du tout cette session — sans
    rapport avec AdMob, système de promotion de contenu payé en pièces, confirmé par l'analyse de
    faisabilité §3.8 mais jamais lu ici). Voir tableau détaillé pour le détail fichier par fichier.

## ⚠️ AUDIT CONFORMITÉ APP STORE — Wallet/Paiements (module 15, à lire avant soumission)

**Ceci corrige et précise TIINVER_IOS_PORT_ANALYSIS.md §3.8/§6/§7.1 point 3, écrits AVANT la
lecture complète du code réel de ce module.** Le rapport de faisabilité initial identifiait
`BuyCoinsActivity.java` comme le point d'intégration Google Play Billing à porter vers StoreKit 2,
et signalait un risque de conformité 3.1.5 générique sur retrait/transfert. Après lecture complète
de `wallet/` (29 fichiers) cette session, le tableau réel est différent et PLUS sérieux sur un
point précis :

**1. Le fichier visé par l'analyse initiale est du code mort.** `BuyCoinsActivity.java` (Google
Play Billing réel) est entièrement commenté (`/* ... */` sur tout le fichier) ET absent
d'`AndroidManifest.xml` — confirmé par les deux méthodes de vérification déjà utilisées pour tout
code suspect dans ce portage (lecture directe + grep manifeste). Il n'a jamais été
compilable/atteignable dans l'app en production.

**2. Le flux d'achat RÉELLEMENT actif contourne toute passerelle de paiement contrôlée par une
plateforme.** `WalletActivity` → `SelectAmountActivity` (choix d'un palier de pièces) →
`PurchaseActivity` : l'utilisateur choisit un opérateur mobile money (Orange Money/Airtel Money,
zone CEMAC) ou crypto (adresse USDC), un NUMÉRO/UNE ADRESSE fixe s'affiche à l'écran, l'utilisateur
effectue le paiement LUI-MÊME en dehors de l'app (application mobile money tierce ou portefeuille
crypto), puis SAISIT À LA MAIN l'identifiant de transaction reçu comme preuve — soumis au backend
(`purchaserequests`/`crypto/check-transaction`) pour vérification et crédit différé. C'est le
définition même d'un contournement d'achat intégré pour un bien numérique (pièces virtuelles) —
guideline App Store **3.1.1** ("In-App Purchase"), pas seulement 3.1.5. Un second chemin
(`CheckoutActivity`/`CheckoutViewModel`/`PaymentsUtil`/`Constants`, déclarés dans le manifeste donc
techniquement atteignables) s'est avéré être du code d'exemple Google Pay non terminé et jamais
relié au crédit de pièces (`handlePaymentSuccess` affiche un Toast et ouvre un écran de succès vide,
sans jamais appeler `WalletRepository`) — également PAS porté, ni comme référence de conformité ni
comme fonctionnalité.

**3. Le retrait ET le transfert restent, eux, un vrai risque 3.1.5 (cash-out) indépendamment du
mode d'acquisition des pièces.** `WithdrawActivity`/`TransfertCoinsActivity` permettent de convertir
le solde de pièces en argent réel (mobile money) ou crypto, avec un seuil minimum et des frais en %
paramétrés à distance (Firebase Remote Config). Ce mécanisme est PORTÉ FIDÈLEMENT dans ce portage
sur instruction explicite de l'utilisateur ("porte fidèlement... documente pour qu'elle soit facile
à auditer"), PAS parce qu'il a été jugé conforme.

**Ce qui a été fait dans ce portage, concrètement (voir `Sources/TiinverSwift/Wallet/` en entier,
7 fichiers) :**
- **Achat de pièces = StoreKit 2, PAS un portage du flux mobile money/crypto manuel**
  (`CoinStoreManager.swift`/`BuyCoinsView.swift`) — 5 paliers consommables
  (`com.tiinver.ios.coins.{250,500,1250,2500,5000}`, à créer dans App Store Connect), `Product.
  purchase()`/`VerificationResult`/`Transaction.updates` vérifiés contre le code source réel de
  `RevenueCat/purchases-ios` (bibliothèque de paiement tierce en production, Apple ne rendant pas
  son contenu JS exploitable — même contrainte que CallKit/PushKit au module 12). **Nécessite un
  NOUVEAU point serveur** (`POST storekit/verify-purchase`, PAS `purchaserequests` qui attend un
  payload mobile money/crypto incompatible) — endpoint appelé côté client, implémentation serveur
  PAS faite (backend PHP séparé, hors périmètre), même motif que la section PushKit/VoIP du module
  12 : `userId`/`quantity`/`productId`/`transactionId`/`originalTransactionId` transmis, le serveur
  doit vérifier la transaction auprès d'Apple (App Store Server API) avant de créditer.
- **Retrait/transfert/conversion/parrainage/récompense pub = portés fidèlement**
  (`WithdrawView.swift`/`TransferCoinsView.swift`/`ConversionView.swift`/`ReferralView.swift`/
  `EarnCoinsView.swift`, `WalletRepository.swift` pour les endpoints REST inchangés :
  `withdrawalrequests`/`crypto/withdraw`/`transfert`/`convert`/`referral/total`/`rewardedCoins`).

**Recommandation, reprise du rapport initial (§7.1 point 3), maintenant plus précise** : revue
juridique/produit AVANT soumission App Store sur DEUX points distincts — (a) l'achat via StoreKit 2
est conforme par construction sur le principe (bien numérique via IAP), mais le pipeline de
vérification serveur doit être fait correctement (ne pas créditer avant vérification Apple
authentique, sous peine de fraude) ; (b) le retrait/transfert de pièces en argent réel est un
mécanisme de cash-out — Apple accepte ce type de fonctionnalité dans certains cas (ex. apps de
paiement/marketplace établies) mais l'examine au cas par cas et peut exiger des justificatifs
(licences, KYC) non couverts par ce portage technique. **Ne pas soumettre ce module à l'App Store
sans cette revue**, indépendamment du fait que le code soit prêt.

## Détail par module

| Module | Fichier Android source | Fichier Swift créé | Statut | Notes/décisions prises |
|---|---|---|---|---|
| Projet | — | `project.yml` (XcodeGen), `Resources/Info.plist` (généré par XcodeGen), `Resources/Assets.xcassets` | ÉCRIT (NON COMPILÉ) | Pas d'Xcode sur Windows → projet décrit en XcodeGen plutôt qu'un `.xcodeproj` binaire. Voir `docs/BUILD_INSTRUCTIONS.md`. |
| Projet — CI | — | `codemagic.yaml`, `.github/workflows/ios-build.yml`, `.gitignore` (réécrit) | ÉCRIT (NON TESTÉ EN CI) | Deux pipelines équivalents (build simulateur `CODE_SIGNING_ALLOWED=NO`, aucune signature/publication) pour valider le Checkpoint 1 sans machine macOS locale — `.github/workflows/ios-build.yml` en déclenchement `workflow_dispatch` MANUEL uniquement. `.gitignore` : bug d'encodage UTF-16 trouvé et corrigé (voir journal/"Erreurs rencontrées et résolues") — ses règles n'étaient jamais appliquées par git avant correction. |
| Réseau | `Http/TransportData.java`, `Http/MySingleton.java` | `Networking/APIClient.swift` | ÉCRIT (NON COMPILÉ) | Alamofire. Headers répliqués à l'identique (Authorization=apiKey brut, pas de Bearer). Timeout 20s, aucun retry, redirections HTTP désactivées (`Redirector.doNotFollow`) — reproduit `MySingleton.OkHttpStack`/`DefaultRetryPolicy(20000,0,1f)`. Corps JSON envoyé même sur GET (reproduit `JsonObjectRequest`). `volleyDelete` omet l'en-tête Accept à l'identique (bug/choix Android reproduit tel quel, voir TransportData.java:1090). |
| Réseau | `Http/CustomTrust.java` | — | NON PORTÉ (décision) | Confirmé mort : zéro `new CustomTrust(` dans tout le dépôt, et son propre loader de certificats (`trustedCertificatesInputStream()`) retourne `null` — non fonctionnel même s'il était instancié. Pas de pinning SSL réel à répliquer. |
| Réseau | `Http/TenorApiClient.java` | — | DIFFÉRÉ | Client GIF (Tenor) — logiquement rattaché au module 11 (Messagerie/Stickers), pas à l'infra réseau de base. Sera porté avec le picker GIF, pas ici. |
| Réseau — enveloppe | (logique dispersée dans `TransportData.java`, ex. `response.getString("error")`) | `Networking/JSONValue.swift` | ÉCRIT (NON COMPILÉ) | Wrapper JSON dynamique type `org.json.JSONObject`, plutôt qu'un `Codable` strict — le backend n'a pas d'enveloppe homogène (parfois "data" = chaîne JSON à re-parser, parfois tableau direct sous une clé nommée par endpoint). `isBackendSuccess` compare `error` à la CHAINE `"false"`, jamais un booléen. |
| Réseau — erreurs | — | `Networking/APIError.swift` | ÉCRIT (NON COMPILÉ) | Type d'erreur Swift générique (transport/serveur/décodage), pas de contrepartie Android directe. |
| Réseau — config | `back_sync/infoContract.java` (SERVER, VPS_SERVER, SERVERIO_URL, CDN_*) | `Networking/APIEnvironment.swift` | ÉCRIT (NON COMPILÉ) | URLs de prod recopiées à l'identique. |
| Sécurité | `SharedPreferences("tiinver_1995")` clé `apiKey` | `Security/KeychainStore.swift` | ÉCRIT (NON COMPILÉ) | Migration SharedPreferences → Keychain pour la donnée sensible, recommandation explicite du rapport §6.2. `kSecAttrAccessibleAfterFirstUnlock`. |
| Sécurité | `SharedPreferences("tiinver_1995")` clés `myId`/`profile`/`username` | `Security/UserSession.swift` | ÉCRIT (NON COMPILÉ) | Reste en `UserDefaults` (non sensible), apiKey délégué à `KeychainStore`. |
| Temps réel | `messagerie/socketio/SocketInit.java` | `Realtime/TiinverSocket.swift` | ÉCRIT (NON COMPILÉ) — ⚠️ point à vérifier | Socket.IO-Client-Swift. Options de reconnection/timeout/secure/websocket-only répliquées à l'identique. **Incertitude documentée** : le mécanisme exact pour reproduire `auth: {"token": apiKey}` du handshake (lu côté serveur via `socket.handshake.auth.token`) n'a pas pu être vérifié contre la doc/API réelle de la lib sans Xcode — `.connectParams` utilisé comme meilleur candidat actuel, à confirmer au premier build réel (voir commentaire en tête du fichier et `docs/BUILD_INSTRUCTIONS.md`). |
| Temps réel | (noms d'événements dispersés : `CallService.java`, `SocketInit.java`, back-end) | `Realtime/SocketEvent.swift` | ÉCRIT (NON COMPILÉ) | Liste exhaustive des noms d'événements du rapport §6.3 point 5, y compris les émissions texte brut `"add user"`/`"offline status"`. |
| App shell | `SplashActivity.java` → `MainActivity` → `HomeActivity` (chaîne de démarrage réelle) | `App/TiinverApp.swift`, `App/AppDelegate.swift`, `App/RootPlaceholderView.swift` | ÉCRIT (NON COMPILÉ) — PLACEHOLDER | Point d'entrée SwiftUI minimal pour que la cible ait un `@main` valide pendant le portage des fondations. Sera remplacé par la vraie coquille de navigation au module 5 (UI Shell), pas avant — ne pas construire l'auth/onboarding réels tant que le module 3 n'est pas atteint dans l'ordre de portage. |
| Modèles | `models/user/User.java` (519 lignes) | `Models/User.swift` | ÉCRIT (NON COMPILÉ) | Tous champs optionnels (le backend ne renvoie jamais l'objet complet selon l'endpoint). `apikey` (minuscule, legacy) conservé distinct de `apiKey`. `getLastname()` (retourne `" "` si null/"null") reproduit en `displayLastname` (nom différent car `lastname` doit rester un stored property `Codable` propre — pas de conflit de nom avec une computed property côté Android puisque Java autorise `lastname` + `getLastname()` mais Swift non). |
| Modèles | `models/user/BlockLib.java` | `Models/BlockLib.swift` | ÉCRIT (NON COMPILÉ) | Trivial. |
| Réseau — auth | `Authentification/AutentificationWenack.java` (en-têtes spécifiques : pas d'Accept, pas d'Authorization) | `Networking/APIClient.swift` (+ `authHeaders()`/`postAuth(_:endpoint:)`) | ÉCRIT (NON COMPILÉ) | Ajouté en complément du client générique — le flux login/register/forgotpassword utilise un jeu d'en-têtes différent de celui de `TransportData.java`, reproduit fidèlement plutôt qu'unifié. |
| Réseau — auth | `Authentification/AuthRepository.java` + `AutentificationWenack.java` (LoginProcess/InscriptionProcess/registerWithProvider/mdpOublierProcess) | `Networking/Endpoints/AuthEndpoints.swift` | ÉCRIT (NON COMPILÉ) | Endpoints réseau purs (login, loginWithGoogle, register, registerWithProvider, passwordForgotten) — **aucun écran SwiftUI encore construit**, conformément à l'ordre de portage (Auth/Onboarding = étape 3, pas encore atteinte). Reproduit fidèlement la sémantique `error` à 3 valeurs (`"false"`/`"true"`/`"mailExist"`) et le déversement du message dans `User.etat`. La liste de blocage locale (`Settings.setBooleanPreference(username_blocked+"_blocked", true)`) est réimplémentée en UserDefaults directement dans ce fichier plutôt que dans un module `Settings` dédié — à réévaluer si le futur module "Réglages" (étape 17) a besoin d'un accès centralisé à cette liste. |
| Stockage local | `Authentification/MainActivity.java` (vérifié) | — | VÉRIFIÉ, RIEN À PORTER | Confirmé : uniquement navigation Fragments + init SDK tiers (AdMob/Facebook), aucun appel réseau supplémentaire à cataloguer avant login. |
| Stockage local | `Dbase.java` (SQLiteOpenHelper, `onCreate()` — schéma version 26) + `back_sync/StubProvider.java` (ContentProvider, mapping URI→table) | `Storage/TiinverModel.xcdatamodeld/**/contents` (14 entités Core Data) | ÉCRIT (NON COMPILÉ) | Schéma repris depuis `Dbase.onCreate()` UNIQUEMENT (pas les 26 migrations `onUpgrade`) — vérifié que `onCreate()` reflète déjà l'état "installation neuve" pour toutes les tables (les `ALTER TABLE` d'upgrade sont tous gardés par `checkColumnExists` et deviennent des no-op sur une base fraîche). Cohérent avec TIINVER_IOS_PORT_ANALYSIS.md §6.3 point 6 ("nouvelle app native, pas de migration de données requise"). 14 tables → 14 entités (`wk_setting` exclue, jamais exposée via les URI du ContentProvider — table de bookkeeping interne sans équivalent fonctionnel). Voir journal de décisions pour les renommages de colonnes (localId, camelCase, `description`→`messageDescription`/`rosterDescription`). |
| Stockage local | (idem, infrastructure) | `Storage/CoreDataStack.swift` | ÉCRIT (NON COMPILÉ) | `NSPersistentContainer` simple, un seul store nommé "TiinverModel". Explicitement documenté comme NE DEVANT PAS être fusionné avec le futur store Room `com.tiinver.db.AppDatabase.java` (historique de vues + chat IA Gemini, confirmé actif et séparé — TIINVER_IOS_PORT_ANALYSIS.md §2.2), qui sera modélisé plus tard comme une deuxième pile Core Data indépendante. |
| Stockage local — repository | `back_sync/StubProvider.java` (dispatch générique `insert`/`update`/`delete`/`query` par nom de table, `UriMatcher`) | `Storage/CoreDataFetchable.swift`, `Storage/CoreDataRepository.swift` | ÉCRIT (NON COMPILÉ) | Repository CRUD **générique** (`CoreDataRepository<Entity: CoreDataFetchable>`) plutôt qu'un type par entité (14x) — vérifié que `StubProvider` lui-même ne fait qu'un dispatch générique `db.insert/update/delete/query(table, ...)` par nom de table pour toutes les entités sauf `wk_roster` (voir ligne suivante). `CoreDataFetchable` déclare la conformance à `Entity.fetchRequest()` pour les 14 entités `TiinverModel` + les 2 entités `TiinverAnalyticsModel`, en s'appuyant sur le `codeGenerationType="class"` déjà choisi dans les `.xcdatamodel`. |
| Stockage local — repository | `back_sync/StubProvider.java` (cas spéciaux `ROSTER_ALL` : jointure SQL brute `wk_roster LEFT JOIN wk_messages ON conversationId` ; `UNREAD_MESSAGE_COUNT` : `UPDATE ... SET unreadCount = unreadCount + 1`) | `Storage/RosterRepository.swift` | ÉCRIT (NON COMPILÉ) | Seules exceptions au dispatch générique de `StubProvider` → repository dédié. La jointure SQL brute est reproduite par deux fetch Core Data + assemblage en mémoire (pas d'équivalent direct à une jointure SQL dans Core Data) ; fidèle au résultat observable, pas à l'implémentation SQL. `incrementUnreadCount` retourne toujours `1`, à l'identique du `rowsUpdated = 1;` codé en dur dans l'original (bug/choix Android reproduit tel quel). |
| Stockage local | `db/ViewEvent.java`, `db/entity/AiConversationEntity.java` (Room, base `tiinver_db`, `com.tiinver.db.AppDatabase.java`, version 3) | `Storage/TiinverAnalyticsModel.xcdatamodeld` (2 entités : `ViewEventEntity`, `AiConversationEntity`), `Storage/AnalyticsCoreDataStack.swift` | ÉCRIT (NON COMPILÉ) | Deuxième pile Core Data indépendante, comme annoncé dans la décision du module 2 précédente — NE PAS fusionner avec `TiinverModel`/`CoreDataStack`. `CoreDataRepository<Entity>` rendu réutilisable pour les deux stores via un protocole `CoreDataContextProviding` (`newBackgroundContext()`), implémenté par `CoreDataStack` et `AnalyticsCoreDataStack`, plutôt que dupliquer le générique. Contrainte d'unicité Room `@Index(value={"userId","activityId"}, unique=true)` sur `view_events` NON reproduite comme contrainte Core Data native (nécessiterait une politique de fusion dédiée) — déjà appliquée au niveau applicatif dans `ViewEventRepository.record()` via un `findExisting` avant insertion, à l'identique de la logique de `ViewTracker.record()` côté Android (qui ne s'appuie pas non plus sur le `OnConflictStrategy.IGNORE` de Room pour ce cas : il vérifie `findExisting` lui-même avant de choisir insert vs update). |
| Stockage local | `db/ViewEventDao.java`, `Utils/ViewTracker.java` (partie stockage local uniquement) | `Storage/ViewEventRepository.swift` | ÉCRIT (NON COMPILÉ) | Reproduit `findExisting`/`record` (cumul watchtime, max de `scrollPosition`/`exitPoint`, somme de `replayCount`)/`getPending`/`deleteById`/`deleteOlderThan`/`count`. La synchronisation réseau périodique/immédiate (`WorkManager`/`ViewSyncWorker.java`, équivalent `BGTaskScheduler`) est DIFFÉRÉE au module 18 (Divers/stats) — ce n'est pas une brique de stockage, mais un sujet de tâches d'arrière-plan à part entière. |
| Stockage local | `db/dao/AiConversationDao.java` | `Storage/AiConversationRepository.swift` | ÉCRIT (NON COMPILÉ) | Reproduit `insert`/`getConversation`/`deleteExpired`/`clearConversation`. Écran consommateur (`TiinverGeminiAIChat.java`, chat IA Gemini) pas encore lu ni porté — non numéroté explicitement dans l'ordre de portage à 18 modules, à rattacher au moment venu (probablement proche du module 11 Messagerie, à confirmer en le lisant). |
| Auth / Onboarding | `Authentification/AuthViewModel.java`, `login/SigninViewModel.java`, `register/SignupViewModel.java`, `passwordrecovery/PWRViewModel.java` (4 classes strictement identiques) | `Authentication/AuthViewModel.swift` | ÉCRIT (NON COMPILÉ) | Un seul `ObservableObject` remplace les 4 `AndroidViewModel` quasi-dupliqués — vérifié ligne à ligne que les 4 classes Java sont du code identique (même 5 méthodes, même délégation à `AuthRepository`), la duplication Android n'ayant qu'une justification de cycle de vie (un ViewModel par Fragment), sans équivalent nécessaire en SwiftUI. `@Published var user` remplace le `LiveData<User>` observé par chaque Fragment. |
| Auth / Onboarding | `Authentification/login/LoginFragment.java` + `Authentification/view/LoginCompound.java` | `Authentication/LoginView.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL | Écran de connexion (bascule email/téléphone, mot de passe, gestion des 5 valeurs de `User.etat` : `Login Successful`/`Email not verified`/`Invalid credential`/`User not exist`/`NoConnect`). Trois éléments de `LoginFragment` explicitement PAS portés à ce stade (voir commentaire en tête du fichier) : (1) connexion Google/Firebase — aucun SDK Firebase/GoogleSignIn dans `project.yml`, `TODO` explicite laissé dans le code ; (2) navigation réelle — remplacée par des closures (`onForgotPassword`/`onRegister`/`onEmailNotVerified`) en attendant le module 5 (UI Shell), même approche que `App/RootPlaceholderView.swift` (module 1) ; (3) `MyFirebaseInstanceIdService.requestNewFCMToken` — `TODO` renvoyé au module 4 (Notifications push). `AccountManager`/`ContentResolver` d'Android (plomberie de comptes système, sans équivalent iOS) remplacés par écriture directe `UserSession`/`KeychainStore`/`AccountEntity` (déjà écrits, modules 1-2). Le layout XML `login_layout.xml` n'étant pas fourni (seul le `.java` a été lu), la bascule email/téléphone est reconstituée comme un `Picker` segmenté sur la base du comportement observable (`usingEmail`/`container_mail`/`container_phone`), pas de l'agencement visuel exact d'origine. |
| Auth / Onboarding | `Authentification/register/SignupFragment.java` + `view/RegisterCompound.java` | `Authentication/RegisterView.swift` | ÉCRIT (NON COMPILÉ) | `Authentification/register/Inscrire.java`/`register/phoneNumber.java` NON portés — confirmés morts par grep (zéro instanciation). Regex email/téléphone recopiées à l'identique. Bannière AdMob et log Facebook Ads (module 16, SDK Facebook non câblé) explicitement différés. |
| Auth / Onboarding | `Authentification/passwordrecovery/RecoverPassword.java` | `Authentication/ForgotPasswordRequestView.swift` | ÉCRIT (NON COMPILÉ) | **Bug Android reproduit fidèlement, documenté** : le bouton d'envoi vérifie TOUJOURS `!mail.isEmpty()` (champ email) même en mode téléphone, où ce champ est vide — la récupération par téléphone est donc silencieusement bloquée côté Android aussi. Pas "corrigé". |
| Auth / Onboarding | `Authentification/passwordrecovery/mdpOublier.java` | `Authentication/NewPasswordView.swift` | ÉCRIT (NON COMPILÉ) | Dernière étape du flux mot de passe oublié (voir décision de flux ci-dessous, `AuthCoordinatorView.swift`). Envoi de l'email de confirmation post-changement via `VerificationEndpoints.sendMail` (nouveau, endpoint générique "mail"). |
| Auth / Onboarding | `Authentification/EmailVerificatiionCode.java` | `Authentication/EmailVerificationView.swift`, `Networking/Endpoints/VerificationEndpoints.swift` (`sendOtp`/`verifyEmail`) | ÉCRIT (NON COMPILÉ) | Écran à double usage confirmé en lisant le code (pas deviné) : après inscription (`action=="signin"` → connexion automatique) ET avant réinitialisation de mot de passe (`action=="forgotpassword"` → route vers `NewPasswordView`). `code`/`static_code` (générateur pseudo-aléatoire LOCAL jamais utilisé nulle part dans le fichier Android) confirmés morts — la vérification réelle passe entièrement par le serveur (`verifyemail`), non reproduits. `verifyUserByPhone()` = no-op côté Android (vérification téléphonique jamais implémentée serveur), reproduit comme no-op ici aussi. |
| Auth / Onboarding | `Authentification/MyCodeConfirmFragment.java` | — | NON PORTÉ (décision) | **Confirmé mort PAR ANALYSE DE FLUX, pas juste par grep** : la classe est bien instanciée dans le switch de `MainActivity.onArticleSelected` (position 5), mais AUCUN écran du flux d'authentification n'appelle jamais `onArticleSelected(5, ...)` sur `MainActivity` — les seuls appels `onArticleSelected(5, ...)` trouvés dans le dépôt ciblent le `FragmentConnectionListener` de `HomeActivity` (caméra/messagerie, sémantique de position totalement différente pour le même entier). Position auth 5 = inaccessible en pratique. |
| Auth / Onboarding | `Authentification/onboarding/OnboardingFragment.java` + `ViewPagerAdapter.java` | `Authentication/OnboardingView.swift` | ÉCRIT (NON COMPILÉ) | 5 pages (mêmes titres/thèmes que l'original : publication, chat, groupes lucratifs, messages programmés, monétisation). Images (`a1`-`a5`) et textes exacts (`R.string.*`, `strings.xml` jamais lu) remplacés par des `SF Symbols`/texte français provisoire dérivé du NOM des clés de ressource — à corriger avec les vraies chaînes localisées quand ce sujet sera traité. |
| Auth / Onboarding | `Authentification/withprovider/SignUpWithGoogle.java` | `Authentication/SignUpWithGoogleView.swift`, `Authentication/GoogleSignInCoordinator.swift` | ÉCRIT (NON COMPILÉ) — IDENTIFIANTS CONFIRMÉS (2026-08-10) | `withprovider/SignupWithProviderViewModel.java` (4ᵉ doublon strict d'`AuthViewModel`, déjà consolidé) et `Authentification/ContinueWithGoogleRepository.java` (confirmé mort par grep) NON portés séparément. `GoogleSignInCoordinator` factorise le flux Google partagé par CE fichier ET `LoginFragment.java`. **Identifiants OAuth mis à jour depuis leur source définitive** : `clientID` (iOS) vient maintenant de `Resources/GoogleService-Info.plist` (fichier réel fourni par l'utilisateur, `CLIENT_ID`/`BUNDLE_ID=com.tiinver.ios` confirmés) — corrige la valeur précédente déduite indirectement de `google-services.json` Android (associée au mauvais bundle id `com.tiinver.tiinverProject`). `serverClientID` (web, `client_type: 3`) toujours repris de `google-services.json` Android — absent des `GoogleService-Info.plist` iOS par nature, réutilisation justifiée par recoupement (même `PROJECT_ID`/`GCM_SENDER_ID` dans les deux fichiers, client identique répété sous les deux apps Android du projet = client partagé au niveau projet, pas lié à un bundle précis). `GIDConfiguration` câble maintenant `serverClientID` (oubli corrigé — la variable existait mais n'était pas utilisée). |
| Auth / Onboarding | `Authentification/PoliticaDemand.java` | `Authentication/PoliticaDemandView.swift` | ÉCRIT (NON COMPILÉ) | `WebAppInterface`/`JavascriptInterface` de l'original confirmé mort (jamais attaché à une `WebView`), non porté. Liens politique de confidentialité/CGU ouverts dans une `WKWebView` en feuille modale (équivalent simplifié de l'Activity `MyWebView.java` dédiée, pas lue en détail — usage trivial constaté par son seul appelant). |
| Auth / Onboarding | (factorisation, pas de fichier Android 1:1 — code dupliqué dans `LoginFragment.CreateSyncAccount` ET `EmailVerificatiionCode.CreateSyncAccount` ET `SignUpWithGoogle.CreateSyncAccount`) | `Authentication/AuthSessionPersistence.swift` | ÉCRIT (NON COMPILÉ) | Les 3 fichiers Android ont une copie quasi identique de la logique de persistance post-connexion — factorisée en un seul type plutôt que dupliquée dans les 3 vues SwiftUI correspondantes. Inclut maintenant l'appel à `PushTokenRegistrar.pushTokenToServer()` (équivalent `MyFirebaseInstanceIdService.requestNewFCMToken`), possible depuis que Firebase est câblé (Priorité 0). |
| Auth / Onboarding | `Utils/StringManager.java` (partiel — `getUserame` uniquement) | `Utils/StringManager.swift` | ÉCRIT (NON COMPILÉ) | Seule méthode utilisée par les fichiers déjà portés (`RegisterView`/connexion Google) ; le reste de `StringManager.java` non lu, non porté par anticipation. |
| Notifications push | `models/notification/NotiDatabase.java` (Room, base `tiinver_notifications.db`, version 2, table `wk_notifications`) + `NotiEntity.java`/`NotiDao.java` | `Storage/TiinverNotificationsModel.xcdatamodeld`, `Storage/NotiCoreDataStack.swift`, `Storage/NotiRepository.swift` | ÉCRIT (NON COMPILÉ) | **Découverte en lisant le module 4** : TROISIÈME store local indépendant, confirmé actif et distinct à la fois de `wk_noti` (StubProvider, déjà porté en `NotificationEntity`/module 2) et de `AppDatabase`/`tiinver_db` (module 2). `wk_noti` = cache reçu en temps réel par socket (écrit directement par `TransportData.java` sur `infoContract.NOTI_URI`) ; `wk_notifications` = centre de notifications paginé, alimenté par l'endpoint REST `notification2/{userId}` (`NotificationRepository.java`). Vérifié par grep que les deux sont référencés par des appelants distincts avec des schémas différents avant de créer un troisième `.xcdatamodeld` — même niveau de rigueur que pour `AppDatabase` au module 2. `NotiRepository.insertAll` reproduit `OnConflictStrategy.REPLACE` sur la clé primaire SERVEUR (`id`), pas sur `NSManagedObjectID`/`localId` — upsert explicite par recherche préalable, Core Data n'ayant pas d'équivalent déclaratif à `@PrimaryKey` + conflict strategy. |
| Notifications push | `back_sync/MyFirebaseInstanceIdService.java` (`sendRegistrationToServer`/`requestNewFCMToken`) | `Notifications/PushTokenRegistrar.swift`, `App/AppDelegate.swift` (`MessagingDelegate`) | ÉCRIT (NON COMPILÉ) — RÉVISÉ | **Décision Priorité 0 tranchée par investigation, plus une hypothèse** : bascule vers **Firebase Cloud Messaging** (`FirebaseMessaging`), pas APNs brut. Preuves trouvées : `app/build.gradle` déclare réellement `firebase-messaging:25.0.1` + `firebase-auth` + plugin `google-services` ; `MyFirebaseInstanceIdService.requestNewFCMToken` appelle explicitement `FirebaseMessaging.getInstance().getToken()` ; `app/google-services.json` existe avec un projet Firebase RÉELLEMENT provisionné (`project_id: com-tiinver`) qui déclare DÉJÀ une app iOS (`bundle_id: com.tiinver.tiinverProject`) ; `TIINVER_IOS_PORT_ANALYSIS.md` liste explicitement "Firebase iOS SDK" pour les notifications. Toutes ces preuves citées dans le journal ci-dessous. `project.yml` déclarait déjà les packages `Firebase`/`GoogleSignIn` depuis le module 1 (jamais câblés jusqu'ici) — ajout de `FirebaseCore`/`FirebaseAuth`. `PRODUCT_BUNDLE_IDENTIFIER` aligné sur `com.tiinver.tiinverProject` (l'app iOS déjà déclarée dans Firebase) plutôt que l'identifiant `com.tiinver.app` choisi au module 1 sans cette information. |
| Notifications push | `setting/FirebaseConfigManager.java` + `res/xml/remote_config_defaults.xml` | `Settings/FirebaseConfigManager.swift` (`TiinverFirebaseConfigManager`), `Resources/RemoteConfigDefaults.plist` | ÉCRIT (NON COMPILÉ) | Portage direct SDK iOS officiel (comme annoncé dans TIINVER_IOS_PORT_ANALYSIS.md). Toutes les méthodes portées sauf `adsRewardedReward()`/`adsOnFeedReward()` (dépendent de `TiinverConfig.ISO`/`CountryManager`, module 16 AdMob/pays, pas encore atteint). `remote_config_defaults.xml` lu en entier (2026-08-10) et converti fidèlement en plist (39 clés, aucune valeur ajoutée). **Recoupement notable trouvé en le lisant** : `app_expire_month = 13` (config réelle, pas une faute de frappe supposée) — combiné à `expireMonth - 1` côté Android (Calendar 0-indexé) donne le mois 12, qui déborde en janvier de l'année suivante par le comportement permissif de `GregorianCalendar` ; côté Swift, `app_expire_month = 13` passé SANS le `-1` (décision déjà prise, `DateComponents` 1-indexé) déborde de la même façon vers janvier de l'année suivante — même date réelle obtenue par les deux implémentations malgré les indexations différentes, confirmant a posteriori que la décision de ne pas soustraire 1 était correcte pour ce cas précis. |
| UI Shell / navigation | `UpdateApp.java` + gate de `SplashActivity.navigateAfterConfig` | `App/UpdateAppView.swift`, `Navigation/RootRouterView.swift` (`checkForceUpdate`) | ÉCRIT (NON COMPILÉ) | **Piège de portage identifié et évité** : `MyTimeManager.getTimeInMillis(expireDay, expireMonth - 1, expireYear)` soustrait 1 au mois car `java.util.Calendar` est 0-indexé — `DateComponents`/`Calendar` de Foundation sont 1-indexés, donc PAS de `-1` dans la version Swift malgré la ressemblance de signature. **Simplification documentée** : compare `TiinverFirebaseConfigManager.versionCode` directement à `CFBundleVersion` plutôt que via la couche de cache `infoContract.REMOTE_VERSION_KEY` de l'original (écriture de cette clé non localisée dans le code lu à ce stade). Lien App Store dans `UpdateAppView.swift` est un placeholder (`id0000000000`) — app iOS pas encore publiée, aucun identifiant réel à ce stade. |
| Notifications push | `back_sync/NotificationUtils.java` (`displayNoMessageNotification`, `displayNotificationOrPushMessage`) | `Notifications/LocalNotificationBuilder.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL | Contenu de notification (`UNMutableNotificationContent`) pour les cas "activité" (like/comment/share/follow/transfert/post/missedvoicecall) et "message de chat" (texte/graphic/gif/gift/sticker/photo/audio/doc/video/shareboard/missedvoicecall). PAS portés (voir commentaire en tête du fichier, raisons documentées) : `showIncomingCallNotification`/`showOngoingNotification` (VoIP/CallKit → module 12), `showUploadFileNotification` (progression d'envoi → module 11), `displaySuggestNotification` (réengagement, textes `R.array` localisés non lus → différé). Textes en dur en français faute de catalogue de chaînes localisées porté (pas encore un module de l'ordre de portage), chaque chaîne commentée avec sa clé `R.string.*` d'origine pour traçabilité. |
| Notifications push | `NotificationHelper.java` (racine `com.tiinver`) | — | NON PORTÉ (décision) | Confirmé mort : zéro `new NotificationHelper(` dans tout le dépôt. Générique et jamais utilisé, catégorie `CATEGORY_CALL` codée en dur même hors contexte d'appel — brouillon abandonné au profit de `NotificationUtils.java` (déjà porté partiellement en `LocalNotificationBuilder.swift`). |
| UI Shell / navigation | `manager/SessionManager.java` (`getUser`/`saveUser`, découvert en lisant le module 5) | `Security/UserSession.swift` (étendu) | ÉCRIT (NON COMPILÉ) — CORRECTIF | **Lacune trouvée dans le code du module 1** : `UserSession.swift` ne persistait que `apiKey`/`myId`/`profile`/`username`, alors que `SessionManager.java` (jamais lu en détail avant ce module) persiste aussi `nikname`/`firstname`/`lastname`/`referralCode` et les utilise pour reconstruire un `User` complet au démarrage (`getUser`). Champs ajoutés + `cachedUser()`/`save(_:)` ajoutés (ports directs de `getUser`/`saveUser`). `LoginView.persistSession` mis à jour pour utiliser `save(_:)` au lieu d'assigner les champs un par un (qui oubliait firstname/lastname/nikname/referralCode). |
| UI Shell / navigation | `Authentification/MainActivity.java implements FragmentConnectionListener` (`onArticleSelected`, switch à 9 cas) | `Navigation/AuthCoordinatorView.swift` | ÉCRIT (NON COMPILÉ) | **Révisé, complet** : les 8 positions atteignables ont maintenant un écran réel (position 5/`MyCodeConfirmFragment` exclue — confirmée inaccessible, voir tableau module 3). Flux mot de passe oublié entièrement reconstitué : ce qui était noté comme un possible bug ("mdpOublier inaccessible depuis Login") est en fait le flux normal Login→8 (RecoverPassword, saisie)→7 (EmailVerification, code)→6 (mdpOublier, nouveau mot de passe)→4 — la dénomination française prête à confusion (mdpOublier = dernière étape) mais le comportement est cohérent. `popToLogin()` vide la pile jusqu'à Login plutôt que d'empiler un nouveau Login par-dessus, pour approximer la déduplication par tag de `FragmentManager.findFragmentByTag` (sans équivalent direct dans `NavigationStack`). |
| UI Shell / navigation | `Activity/ui/HomeActivity.java` + `view/navigation/NavigationCompound.java` + `Activity/adapter/MyPagerAdapter.java` | `Navigation/HomeShellView.swift`, `Navigation/DeepLinkCenter.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL | `TabView` à 3 onglets (Accueil=`MainFragment`/module 6 **ÉCRIT**, Chat=`Roster`/module 11 placeholder, Créateurs=`CreatorFragment`/module non identifié placeholder). Badge chat = somme `wk_roster.unreadCount` (`RosterRepository`) ; badge notifications = `NotiRepository.countUnread()`, maintenant aussi synchronisé sur `UNUserNotificationCenter.setBadgeCount` (icône d'app). `DeepLinkCenter` (nouveau) reproduit le routage par destination de `NotificationUtils.show()`/`activityMap` : `AppDelegate.userNotificationCenter(_:didReceive:...)` publie une destination, `HomeShellView` l'observe pour ouvrir le bon `sheet` — écrans notifications/profil eux-mêmes toujours des placeholders (`ShowNoti`/`AddPerfilFoto` pas encore lus, voir "Prochaine action"). PAS porté : les 3 `scheduleDynamicWorker` (WorkManager, contenu suggéré/boost — différé au module 18 comme `ViewSyncWorker`, module 2). |
| UI Shell / navigation | `SplashActivity.navigateAfterConfig` (décision login/home ET gate de mise à jour forcée) | `Navigation/RootRouterView.swift` | ÉCRIT (NON COMPILÉ) | Décision `goToLogin()`/`goToHome(user)` sur la seule présence d'une session locale (`SessionManager.getUser(context) != null`, pas de revalidation réseau) — reproduit via `UserSession.shared.cachedUser()`. Gate de mise à jour forcée ajouté (voir ligne `UpdateApp.java` ci-dessus). Remplace `App/RootPlaceholderView.swift` (module 1, SUPPRIMÉ) comme point d'entrée de `TiinverApp.swift`. |
| Feed vidéo | `Utils/CacheProvider.java` (`SimpleCache` ExoPlayer + `LeastRecentlyUsedCacheEvictor`) | `Media/VideoCacheManager.swift` | ÉCRIT (NON COMPILÉ) | AVFoundation n'a pas d'équivalent direct à `SimpleCache` (cache disque intégré, éviction LRU automatique) — reproduit par un cache disque manuel (`Caches/media/`, taille plafonnée à `min(espace libre/3, 1 Go)` comme l'original, éviction par date de modification la plus ancienne). Comportement observable reproduit, mécanisme interne nécessairement différent (documenté en tête du fichier). |
| Feed vidéo | `Activity/service/ExoPlayerManager.java` (1 lecteur partagé, préchargement, fallback MP4 sur erreur) | `Media/VideoPlayerManager.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL | `AVPlayer` unique réutilisé entre cellules (comme l'original), branche "même URL → seek(0)" reproduite, fallback vers `currentFallbackUrl` sur échec de lecture reproduit. PAS porté : `DefaultPreloadManager`/déduplication `mediaSourceCache` (spécifiques à Media3, sans équivalent AVFoundation) — remplacés par un warm-up `AVURLAsset.loadValuesAsynchronously` + `NSCache`, intention identique (préparer les vidéos suivantes), mécanisme natif différent. Gestion spécifique HLS vs MP4 (`HlsMediaSource` vs `ProgressiveMediaSource` selon `.m3u8`) non distinguée : `AVPlayer` gère nativement les deux formats via la même API, donc pas de branchement nécessaire côté iOS — CE N'EST PAS un oubli, mais une simplification légitime par différence de plateforme. |
| Feed vidéo | `Http/TransportData.addActivities` (cache local `wk_activities`, endpoint `feedtimeline/{userId}/{limit}/{offset}`) + `models/activity/activityLib.java` | `Feed/FeedActivity.swift`, `Feed/FeedRepository.swift` | ÉCRIT (NON COMPILÉ) | Noms de champs JSON vérifiés directement dans `activityLib.java` (correspondance nom de champ Java ↔ clé JSON, pas de `@SerializedName`) plutôt que devinés depuis `ActivityEntity` (Core Data, module 2) qui a des noms renommés. Politique de cache local reproduite FIDÈLEMENT malgré son caractère peu optimal : au-delà de 10 lignes en cache, TOUTES sont supprimées avant réinsertion du nouveau lot (pas d'éviction sélective par id — cette logique existe en commentaire dans le fichier source Android mais n'est jamais activée) — pas "corrigé" silencieusement. |
| Feed vidéo | `Activity/ui/MainFragment.java` (1966 lignes — hors de portée d'un portage intégral à ce stade) | `Feed/FeedViewModel.swift`, `Feed/FeedView.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL | Seule la boucle "charger une page / afficher plein écran / lecture vidéo" est portée. PAS portés (fichier bien trop volumineux pour un portage intégral en une passe, à traiter module par module ultérieurement) : like/commentaire/partage inline, double-tap, mode édition/upload, pagination fine avec états de chargement par item. Défilement vertical plein écran reproduit via un contournement `TabView` pivoté (page tournée -90°/conteneur +90°, technique standard faute d'API de pagination verticale native sur la cible iOS 16) — **NON VÉRIFIÉ VISUELLEMENT**, aucun accès à un simulateur/Xcode ; à confirmer au premier build réel, avec repli documenté vers `ScrollView`+`.scrollTargetBehavior(.paging)` (iOS 17+) si le rendu est insatisfaisant — décision de relever la cible de déploiement à prendre avec l'utilisateur, pas unilatéralement. |
| Réseau — enveloppe | (aucun équivalent Android — bug de portage iOS interne) | `Networking/JSONValue.swift` (`rawData`) | ÉCRIT (NON COMPILÉ) — CORRECTIF | **Bug trouvé avant compilation** : `AuthEndpoints.decodeUser` (module 1) référence `meta.rawData` depuis le début, mais cette propriété n'existait pas dans `JSONValue` — n'aurait pas compilé au premier build réel. Trouvé en essayant de réutiliser le même mécanisme pour `FeedRepository.fetchTimeline` (module 6). Ajouté maintenant (ré-encodage via `JSONSerialization.data(withJSONObject:)`) plutôt que découvert plus tard sans contexte pour le corriger. |
| Notifications push | `NotiLikecmt/NotificationRepository.java` (`fetchNotifications`/`parseNotificationsOptimized`/`triggerSystemNotifications`/`markAllRead`/`deleteAll`) | `Notifications/NotificationCenterViewModel.swift` | ÉCRIT (NON COMPILÉ) | Endpoint `notification2/{userId}` — **convention "error" CONFIRMÉE différente** des autres endpoints déjà portés : ici un booléen JSON réel (`object.getBoolean("error")`), pas la chaîne `"false"`/`"true"` habituelle. Ajouté `JSONValue.bool(_:)` dédié plutôt que de forcer `isBackendSuccess` sur ce cas, pour ne pas uniformiser silencieusement deux conventions distinctes du même backend. `retriaveData(...)` (pagination générique réutilisée ailleurs pour les suggestions d'amis) volontairement PAS porté ici : ce n'est pas un sujet "notifications push", à rattacher au module qui le consomme réellement (pas encore identifié). |
| Notifications push | `back_sync/MyBackgroundTask.java`, `Http/transportDataBackground.java`, `Activity/service/ActivityService.java`, `service/TiinverSyncWorker.java` | `App/AppDelegate.swift` (`didReceiveRemoteNotification`) | LU, PARTIELLEMENT PORTÉ | Les 4 fichiers repérés au grep initial du module 4 lus en entier — confirmé que SEULE une sous-partie de `TiinverSyncWorker.visiteServeur` (via `MyBackgroundTask.notifyUser(id)` → `NotificationRepository.fetchNotifications`) concerne vraiment les notifications push ; déjà couverte par `NotificationCenterViewModel` (module 4). Le reste de `TiinverSyncWorker` (sync messages privés/groupe via `ChatRepository`) appartient au module 11 (Messagerie), PAS porté ici. `transportDataBackground.java` = logout/suppression de compte (module 17, PAS module 4). `ActivityService.java` = service d'upload de média en premier plan avec clé API Bunny CDN en dur dans le source Android (module 6/7, upload de contenu — PAS porté, secret tiers non recopié dans ce portage). `AppDelegate.didReceiveRemoteNotification` déclenche maintenant réellement `NotificationCenterViewModel.fetchNotifications` (auparavant un `TODO` vide). |
| Notifications push | (aucun fichier Android 1:1 — équivalent du badge d'icône, absent côté Android qui ne badge que la barre in-app `NavigationCompound`) | `Navigation/HomeShellView.swift` (`UNUserNotificationCenter.setBadgeCount`) | ÉCRIT (NON COMPILÉ) | Badge de l'icône d'app iOS synchronisé sur `NotificationCenterViewModel.unreadCount`, en plus du badge in-app déjà câblé (module 5). Ajout logique côté iOS (convention plateforme standard), pas un port direct d'un mécanisme Android équivalent — aucun n'existe. |
| UI Shell / navigation | `NotiLikecmt/ShowNoti.java` | `Notifications/NotificationsListView.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL | Remplace le placeholder `sheet` "Notifications". PAS porté, volontairement : l'injection de suggestions de follow dans la même liste (`retriaveData`/`SearchModel`, déjà exclue du module 4 pour la même raison — ce n'est pas une notification) et la pagination infinie au scroll (`NotificationCenterViewModel.fetchNotifications` n'a pas de paramètre `offset`). Affiche donc uniquement les vraies notifications. |
| UI Shell / navigation | `uploadPerfilPhoto/AddPerfilFoto.java` (1164 lignes) | `Profile/ProfileView.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL ASSUMÉ | **Portée volontairement réduite, décision explicite** : ce fichier Android est en réalité l'écran "Profil / Réglages" complet (photo, grille de publications, followers/following, portefeuille, monétisation, édition) — c'est-à-dire le MODULE 17 de l'ordre de portage, pas un sujet du module 5 (UI Shell). Affiche seulement les informations déjà disponibles localement (`UserSession`/`AccountEntity`). Grille de publications (`ProfileAdapter2`), upload de photo, portefeuille (`WalletActivity`, module 15), monétisation et édition (`EditProfile.java`, pas lu) tous différés au module 17. Compteurs followers/following NON câblés : `AccountEntity` ne les stocke pas et l'endpoint profil correspondant n'a pas été identifié. |
| UI Shell / navigation | `BaseActivity.java` | — | VÉRIFIÉ, RIEN À PORTER | Confirmé purement visuel (thème + insets edge-to-edge) — SwiftUI gère nativement les zones sûres et le mode sombre, aucun équivalent nécessaire. |
| Feed vidéo | `Activity/service/PreloadScheduler.java`, `LoadControlUtils.java`, `Preloader.java`, `MyTargetPreloadStatusControl.java`, `Utils/CacheCompat.java` | `Media/VideoPlayerManager.swift` (`preload`, `preferredForwardBufferDuration`), `Feed/FeedView.swift` (`preloadAround`) | LU, PARTIELLEMENT PORTÉ | Les 5 fichiers référencés par `ExoPlayerManager.java` mais pas encore lus individuellement (voir "Prochaine action" précédente) — maintenant lus en entier. Portée : fenêtre de préchargement `currentIndex ± 2` (`PreloadScheduler`, filtrant les posts non-vidéo comme l'original) ; `AVPlayerItem.preferredForwardBufferDuration` en meilleur équivalent de `LoadControlUtils.createFastStartLoadControl`. PAS porté, confirmé sans équivalent AVFoundation atteignable : les états de préchargement étagés de `MyTargetPreloadStatusControl`/`DefaultPreloadManager` (architecture interne Media3) et le polling de buffer de `Preloader.checkBuffered` (`getBufferedPosition()` jusqu'à 4s) — `CacheCompat` (ratio de cache partiel) déjà couvert par l'équivalent binaire `VideoCacheManager.isCached`, suffisant pour l'usage actuel. |
| Feed vidéo | `Activity/adapter/ActivityAdapter.java` (956 lignes) | — | LU (PARTIELLEMENT), PAS PORTÉ | Confirme la décision déjà prise de différer like/commentaire/partage/double-tap : c'est le fichier qui contient cette logique, et sa taille (956 lignes, view-holder binding + gestionnaires de clic denses) confirme que ce n'est pas un ajout rapide. `ActivityDiffCallback.java` (RecyclerView `DiffUtil`) non porté — `List`/`ForEach` SwiftUI diffe automatiquement, aucun équivalent nécessaire. `BiographyAdapter.java`/`StatisticsAdapter.java` repérés mais pas lus — probablement module 17 (profil), pas module 6. |
| Caméra | `editor/filter/FilterType.java` | `Camera/LensFacing.swift`, `Camera/CameraFilterType.swift` | ÉCRIT (NON COMPILÉ) | **Découverte importante en lisant le fichier réel** : sur les 43 valeurs de l'enum `FilterType`, seules 23 sont réellement atteignables dans `createGlFilter()` — les 20 restantes sont à l'intérieur d'un bloc de commentaire Java `/* ... */` (lignes ~158-219), donc retombent systématiquement sur `default: return new GlMonochromeFilter();`. Reproduit à l'identique (pas "corrigé") : `CameraFilterType.makeFilter()` retourne `TiinverMonochromeFilter` pour ces 20 cas. |
| Caméra | `engine/.../gpuv/egl/filter/Gl*.java` (22 sous-classes `GlFilter` réellement utilisées + `BeautyFilter.java`) | `Camera/Filters/TiinverCameraShaders.metal`, `Camera/Filters/TiinverCameraFilters.swift` | ÉCRIT (NON COMPILÉ) | Réécriture manuelle GLSL→MSL des 22 filtres actifs (Brightness, Contrast, Saturation, GrayScale, Sepia, Vignette, Gamma, Monochrome, Opacity, Posterize, RGB, Hue, Exposure, Luminance, Haze, HighlightShadow, Pixelation, BulgeDistortion, Sharpen, Tone, Vibrance, BeautyFilter), aucun convertisseur automatique disponible — confirmé impossible dans `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.2. Architecture : sous-classes `MTIUnaryImageRenderingFilter` (MetalPetal, recommandation actée du même rapport §2.1/§3.1) — pattern vérifié directement dans les en-têtes RÉELS du SDK MetalPetal 1.10.0 téléchargés depuis GitHub avant d'écrire ce fichier (`MTIColorMatrixFilter.h/.m`, `MTIBulgeDistortionFilter.h/.m`, `MTIUnaryImageRenderingFilter.h/.m`), pas deviné par analogie. Valeurs par défaut de chaque filtre reprises EXACTEMENT de `FilterType.createGlFilter` (ex. `contrast=2.5`, `sharpness=4`, `vibrance=3`, `gamma=2`), y compris les cas où Android n'appelle aucun setter et laisse la valeur par défaut interne de la classe `Gl*Filter` (ex. `saturation=1.0` = no-op, `opacity=1.0` = no-op, `pixel=1.0` = quasi no-op) — ce sont des filtres "no-op" côté Android RÉEL, pas des oublis de portage. **Bug d'unité Android reproduit tel quel dans `GlHueFilter`/`tiinverHue`** : le commentaire Java suggère une plage 0-360° pour `hue`, mais le shader ajoute `hueAdjust` directement à une valeur d'angle en RADIANS sans conversion — documenté en commentaire, pas corrigé. `GlSharpenFilter`/`GlThreex3TextureSamplingFilter` (`GlToneFilter`)/`BeautyFilter` calculaient les offsets de texels voisins dans le VERTEX shader Android (varyings) ; recalculés directement dans le FRAGMENT shader ici — équivalence mathématique exacte sur un quad plein écran (offset additif constant, commute avec l'interpolation bilinéaire), documentée comme telle, pas une approximation. |
| Caméra | `editor/camera/BaseCameraFragment.java` (711 lignes), `engine/.../gpuv/camerarecorder/GPUCameraRecorder.java`, `CameraHandler.java`, `GPUCameraRecorderBuilder.java` | `Camera/CameraCaptureController.swift` | ÉCRIT (NON COMPILÉ) | `Camera2`+`EGL`/`GLES20` (session caméra bas niveau, thread `CameraThread` dédié) → `AVCaptureSession` natif (pas de thread dédié à gérer à la main, `AVCaptureSession` le fait déjà en interne) — risque jugé "Faible-Moyen" dans `TIINVER_IOS_PORT_ANALYSIS.md` §3.3, confirmé à la lecture : portage direct sans architecture de repli nécessaire. Gestion des permissions caméra/micro ajoutée explicitement (`AVCaptureDevice.requestAccess`) — Android le fait aussi explicitement (`onRequestPermissionsResult`), pas un ajout arbitraire côté iOS. |
| Caméra | `MediaVideoEncoder.java`, `MediaAudioEncoder.java`, `MediaMuxerCaptureWrapper.java`, `EncodeRenderHandler.java` | `Camera/CameraRecordingWriter.swift`, `Camera/CameraRecorder.swift` | ÉCRIT (NON COMPILÉ) — RELU EN ENTIER (2026-08-10) | `MediaCodec` H.264/AAC séparés + `MediaMuxer` → `AVAssetWriter` (mux+encode unifié, "plus simple côté iOS" — décision déjà actée dans `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.1). Constantes d'encodage reprises à l'identique : vidéo H.264 30fps bitRate=BPP(0.25)×30×largeur×hauteur, audio AAC-LC 44100Hz mono 64kbps. **Relecture intégrale (pas seulement les constantes) des 3 fichiers, 2 lacunes trouvées et corrigées** : (1) `KEY_I_FRAME_INTERVAL=3` (keyframe/3s) manquait — ajouté via `AVVideoMaxKeyFrameIntervalDurationKey`. (2) `MediaMuxerCaptureWrapper.preventAudioPresentationTimeUs` (garde de monotonicité des horodatages audio) non reproduite — ajoutée (`lastAudioPresentationTime`) par prudence, bien que le mécanisme source du problème (PTS calculé manuellement par `MediaAudioEncoder.getPTSUs()` sur un thread `AudioRecord` séparé) n'ait pas d'équivalent direct côté iOS (`CMSampleBuffer` horodaté par l'horloge matérielle via `AVCaptureAudioDataOutput`, normalement déjà monotone). La synchronisation à deux compteurs `encoderCount`/`startedCount` de `MediaMuxerCaptureWrapper.start()`/`stop()` CONFIRMÉE sans équivalent nécessaire : elle résout un problème spécifique à l'API bas niveau `MediaCodec`/`MediaMuxer` (le `MediaFormat` de chaque piste n'est connu qu'après un callback asynchrone `INFO_OUTPUT_FORMAT_CHANGED`), alors que `AVAssetWriterInput` reçoit ses `outputSettings` de façon synchrone dès sa construction — absence de portage documentée, pas un oubli. `CameraRecorder.swift` unifie le rendu aperçu ET export en un seul passage MetalPetal par frame — contrairement à Android qui maintient deux pipelines GL séparés (`GlPreviewRenderer` aperçu / `EncodeRenderHandler` export) devant rester synchronisés à la main ; élimine par construction ce risque de divergence. |
| Caméra | `SampleCameraGLView.java` | `Camera/CameraPreviewView.swift` | ÉCRIT (NON COMPILÉ) | `GLSurfaceView` custom + `GlPreviewRenderer` → `MTIImageView` (vue prête à l'emploi du SDK MetalPetal, PAS un pipeline `MTKView`/cache de texture Metal écrit à la main) — API réelle vérifiée dans `Frameworks/MetalPetal/UI/MTIImageView.h` du SDK 1.10.0 avant d'écrire ce fichier. |
| Caméra | `editor/CircleCaptureButton.java` (lu en entier, 520 lignes) | `Camera/CameraView.swift` (`captureGesture`) | ÉCRIT (NON COMPILÉ) — CORRECTIF (2026-08-10) | **Corrige le premier jet** (qui reconstituait le comportement sans avoir lu ce fichier) : le vrai seuil tap/appui-long est de **1000 ms exactement** (`mHandler.postDelayed(action, 1000)`), pas une estimation. `.onLongPressGesture(minimumDuration:pressing:)` utilisé au premier jet était en réalité INCORRECT dans son principe même : son paramètre `pressing` se déclenche IMMÉDIATEMENT au toucher (pas après `minimumDuration`), ce qui aurait démarré un enregistrement dès le premier contact. Remplacé par `DragGesture(minimumDistance: 0)` + un `DispatchWorkItem` programmé à 1 s et annulé au relâchement anticipé — équivalent direct de `postDelayed`/`removeCallbacks`. **Confirmé par analyse de flux, non porté à raison** : `MINIMUM_VIDEO_DURATION_MILLIS`/`actionListener.onDurationTooShortError`/`onEndRecord` — `actionListener` n'est jamais assigné (toujours `null`) ET `onLongPressEnd()` remet `isRecording=false` AVANT le test `else if (isRecording)` qui aurait appelé `onEndRecord()` — ce test est donc TOUJOURS faux à cet endroit précis, rendant toute cette branche morte des deux côtés (ni crash `NullPointerException`, ni effet observable). Rien à porter, confirmé plutôt que supposé. |
| Caméra | `editor/CameraActivity.java` (lu en entier) + `Activity/ui/MainFragment.java` (`R.id.fab`/`requestPermission()`) | `Feed/FeedView.swift` (`cameraFAB`, `.fullScreenCover`) | ÉCRIT (NON COMPILÉ) — CORRECTIF (2026-08-10) | **Point d'entrée réel du module 7, retrouvé par grep de `CameraActivity.class` dans tout le dépôt (7 lanceurs)** : `CameraActivity` est une **Activity Android à part entière** (implémente elle-même `FragmentConnectionListener`, switch à 13 cas routant vers `BaseCameraFragment`/`MemesFragment`/`MediaEditor`/`CropFragment`/`MediaTrim`/`MediasDisplay`/`Gallery`/`PublishFragment`), PAS une position `HomeActivity.onArticleSelected` comme le supposait une note du premier jet. Le lanceur pertinent pour ce portage est `MainFragment.java:777` (`R.id.fab`, déjà porté en `FeedView.swift`/module 6) → `requestPermission()` (vérifie `Manifest.permission.CAMERA`, demande si besoin) → `startActivity(CameraActivity.class)`. Câblé en conséquence : un FAB (`cameraFAB`) ajouté à `FeedView.swift`, vérification `AVCaptureDevice.authorizationStatus`/`requestAccess` AVANT présentation (même intention que `requestPermission()`), `.fullScreenCover` comme équivalent le plus proche de `startActivity` (nouvel écran plein écran). Les 6 AUTRES lanceurs de `CameraActivity` (`FeedFragment`, `TiinverGeminiAIChat`, `ShareActivity`, `ReferralActivity`, `MonetizationActivity`) appartiennent à des modules pas encore portés — non câblés, à rattacher au moment venu. Sous-flux de `CameraActivity` correspondant à la capture (cases 0/2/5/7/8/10 du switch : `BaseCameraFragment`→`MediaEditor`(photo)/`MemesFragment`(Animems)/`MediasDisplay`(vidéo)/`Gallery`/`MediaTrim`(galerie vidéo)) reproduits comme des TODO explicites en closures (`onPhotoCaptured`/`onVideoRecorded`/`onImagePickedFromGallery`/`onVideoPickedFromGallery`/`onOpenAnimems` referment simplement l'écran caméra) — ces écrans consommateurs (modules 8/9/10, Divers) n'existent pas encore. |
| Caméra | `BaseCameraFragment.pickImageOrVideo`/`pickMedia` (branche Android R+ de `doSelection(layoutPosition==0)`) | `Camera/GalleryPickerView.swift` | ÉCRIT (NON COMPILÉ) | `ActivityResultContracts.PickVisualMedia` (filtre `ImageAndVideo`, sélection unique — aucun `setMaxItems` appelé) → `PHPickerViewController` (`UIViewControllerRepresentable`), PAS `PhotosPicker` SwiftUI (disponible dès iOS 16, vérifié, mais écarté : l'accès à un vrai fichier local pour une vidéo est plus direct via `NSItemProvider.loadFileRepresentation` que via `Transferable`, qui exigerait un type `Movie` custom sans bénéfice ici). Routage post-sélection (image → `onImagePickedFromGallery` ↔ `onArticleSelected(2,...)`→`MediaEditor` ; vidéo → `onVideoPickedFromGallery` ↔ `onArticleSelected(10,...)`→`MediaTrim`) reproduit à l'identique, écrans consommateurs pas encore portés (closures TODO, voir ligne `CameraActivity` ci-dessus). Branche Android < R (`requestStoragePermission()` + fragment `Gallery` interne) SANS équivalent nécessaire : `PHPickerViewController` ne demande aucune permission bibliothèque (design privacy-first Apple), simplification légitime par différence de plateforme, pas un oubli. |
| Caméra | `editor/camera/BaseCameraFragment.java` (portion UI/écran) | `Camera/CameraView.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL ASSUMÉ, module 7 refermé (voir décision de clôture ci-dessous) | Capture photo/vidéo avec filtre en direct (seuil 1s vérifié, voir ligne `CircleCaptureButton.java`), bascule caméra, mise au point tactile, flash, carrousel de filtres au swipe (43 valeurs, dont 20 "mortes" affichant Monochrome — bug reproduit, voir tableau filtres), sélecteur galerie réel (voir ligne `GalleryPickerView.swift`), branchement navigation réel (voir ligne `CameraActivity.java`/`FeedView.swift`). Restent des TODO explicites, PAS des oublis silencieux (les écrans consommateurs n'existent pas encore) : édition photo post-capture (module 9), affichage/trim vidéo post-capture (module non identifié), ouverture Animems (module 8, commence juste après ce tableau). |
| Animems — éditeur | `engine/keyframe/Keyframe.java` | `Animems/Keyframe.swift` | ÉCRIT (NON COMPILÉ) | Port direct — `struct` Swift (valeur) plutôt que classe (référence) comme l'original Java : rien dans le code lu jusqu'ici ne dépend d'une identité de référence persistante hors de `KeyframeTrack` (mutation toujours via recherche par `id`/`timestampNs`), un `struct` est donc fidèle au comportement observable et plus idiomatique. Représentation `[Float]` brute conservée telle quelle (pas de `enum` de propriété typé "plus propre") : le contrat avec `KeyframeTrack`/le futur `AnimationObjectData` dépend de cette forme exacte (`color`=4 éléments ARGB Android-style bits 24/16/8/0, PAS le format `UIColor`). |
| Animems — éditeur | `engine/keyframe/KeyframeTrack.java` | `Animems/KeyframeTrack.swift` | ÉCRIT (NON COMPILÉ) | Port direct, y compris les constantes `PROP_*` (noms de propriété EXACTS, réutilisés tels quels par le futur port d'`AnimationObjectData` — pas de renommage) et les couleurs `MARKER_COLOR_*` (ARGB packé 32 bits, pas converti en `Color` SwiftUI ici — l'écran de timeline qui les consommera n'existe pas encore). Formules d'easing (`t*t`, `t*(2-t)`, formule cubique de `EASE_IN_OUT`) et `lerp` (s'arrête à `min(a.count, b.count)` comme l'original) reproduites à l'identique, aucune simplification. |
| Animems — éditeur | `engine/android/memes/MemesView2.java` (grep ciblé, PAS lu en entier — juste les usages de `PorterDuff.Mode`) | `Animems/Transform.swift` (commentaire d'architecture) | DÉCISION D'ARCHITECTURE | **Décision structurante pour tout le module 8** : grep de `PorterDuff.Mode` dans `MemesView2.java` (1978 lignes) confirme que la compositing des calques n'utilise QUE 3 modes de fusion — `DST_IN` (masquage), `SRC_ATOP` via `PorterDuffColorFilter` (teinte), `CLEAR` (reset) — tous portables 1:1 en `CGBlendMode` (`.destinationIn`/`.sourceAtop`/`.clear`). **Conclusion : Core Graphics (`CGContext`) suffit pour la compositing des calques, aperçu ET export**, PAS besoin d'un pipeline Metal/MetalPetal pour cette partie — plus direct que la recommandation `AVVideoCompositing`+MetalPetal du rapport `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.1 (qui supposait Metal nécessaire ; MetalPetal reste pertinent ailleurs — filtres caméra module 7 — mais pas prouvé indispensable ici). Conséquence directe : `Transform.glMatrix`/`AnimationEngine.androidToGL_Matrix2` (conversion Android `Matrix`→OpenGL 4×4) NE SONT PAS portés, décision assumée et documentée, pas un oubli — voir ces deux fichiers. À reconsidérer SEULEMENT si l'export choisit finalement un pipeline Metal pour d'autres raisons (performance, effets GPU) — pas exclu, juste pas prouvé nécessaire à ce stade. |
| Animems — éditeur | `core/Transform.java` | `Animems/Transform.swift` | ÉCRIT (NON COMPILÉ) | `matrixValues: [Float]` (9 éléments, ordre `Matrix.getValues()` Android) conservé comme représentation brute — cohérent avec `Keyframe`/`KeyframeTrack` (`PROP_MATRIX`). `cgAffineTransform` (calculé) + `matrixValues(from:)` (sens inverse) ajoutés pour le pont vers Core Graphics — mapping d'ordre de champs vérifié explicitement (Android `[a,c,tx,b,d,ty,…]` vs `CGAffineTransform(a,b,c,d,tx,ty)`, PAS le même ordre malgré la ressemblance). `glMatrix` NON porté (voir décision d'architecture ci-dessus). Clamps `opacity∈[0,1]`/`cornerRadius≥0` reproduits via propriétés calculées avec stockage privé. |
| Animems — éditeur | `core/AnimationObjectData.java` (618 lignes, lu en entier) | `Animems/AnimationObjectData.swift` | ÉCRIT (NON COMPILÉ) | Port quasi complet de l'objet "calque" central : propriétés de masque (clamps identiques), `maskTransforms`, système de keyframes complet (tous les `add*Keyframe`/`getInterpolated*`, y compris masque et transform décomposé), `bakeKeyframesToTransforms`, bitmaps/textures avec horodatages (`CGImage` + `[Int64]`, unité "ns" déduite du nom de paramètre Android `getCurrentBitmapForTime(long ns)` — pas documentée explicitement dans le Java d'origine, signalé comme déduction), accumulateurs de vitesse de défilement par-objet, `duplicate`/`duplicate2` (copie profonde vs copie légère partageant transforms/bitmaps — reproduit tel quel, PAS harmonisé). `final class` (référence) plutôt que `struct`, contrairement à `Keyframe` : cet objet est muté en place par de nombreux appelants qui s'attendent à voir la même instance partagée dans `AnimationComposer.layers`, fidèle à la sémantique de référence Java. **Bug de nommage trouvé et corrigé avant tout build** (relecture propre) : une méthode `track(_:)` (accesseur de piste de keyframes) entrait en collision avec le champ existant `track: Int` (index de calque Android) — Swift ne peut pas résoudre `obj.track(x)` entre une propriété stockée et une méthode de même nom. Renommée `keyframeTrack(_:)`. |
| Animems — éditeur | `core/AnimationComposer.java` | `Animems/AnimationComposer.swift` | ÉCRIT (NON COMPILÉ) | Port direct. **Incohérence trouvée dans le commentaire Android lui-même, signalée** : le commentaire dit "on utilise la valeur brute 0xFF1A1A1A (noir foncé)" mais le champ réel vaut `0xFF0062A4` (bleu) — reproduit la VALEUR RÉELLE du champ, pas celle citée dans le commentaire obsolète. |
| Animems — éditeur | `core/AnimationUtils.java` | `Animems/AnimationUtils.swift` | ÉCRIT (NON COMPILÉ) | Port direct des 3 fonctions pures (`isAnimation`/`isAutoCreatableTrack`/`updateMaskLabel`) et de la conversion RGB→HSV→RGB de `makeMessengerLikeBackground`, formule par formule. Conversion finale vers octets `UInt32` sécurisée par un clamp AVANT conversion (pas après, comme un premier réflexe aurait pu le faire) : `UInt32(valeurNégative)` provoque un CRASH en Swift (contrairement à un `int` Java hors-borne, qui "wrap" silencieusement) — bug potentiel évité par construction, pas rencontré puis corrigé. |
| Animems — éditeur | `engine/mask/MaskType.java` | `Animems/MaskType.swift` | ÉCRIT (NON COMPILÉ) | Port direct, 7 cas. |
| Animems — éditeur | `engine/android/mask/MaskFactory.java` (230 lignes, lu en entier) | `Animems/MaskFactory.swift` | ÉCRIT (NON COMPILÉ) | **Piège de portage identifié et évité** : `android.graphics.Canvas` a son origine en haut-à-gauche (Y vers le bas) ; un `CGContext` bitmap créé manuellement (`CGContext(data:...)`) a son origine en BAS-à-gauche par défaut (Y vers le haut, convention PDF de Core Graphics — PAS celle de `UIView.draw`, qui inverse déjà). Sans un flip explicite (`translateBy`+`scaleBy(y:-1)`, ajouté une seule fois après la création du contexte), tout le tracé aurait été vertical-miroir par rapport à Android. Tous les tracés de formes (cercle/carré/rectangle/miroir/cœur/étoile, `CGMutablePath`) portés tels quels une fois ce flip en place, sans reconversion de coordonnées ligne à ligne. Flou de bord (`BlurMaskFilter` Android, algorithme Skia propriétaire) reproduit via `CIGaussianBlur` (Core Image) — bord adouci similaire, PAS un flou bit-identique, documenté comme approximation comportementale (même principe que `VideoCacheManager` module 6). Inversion alpha (`invertAlpha`) portée par manipulation directe du buffer de pixels RGBA pour un contrôle exact, plutôt que via un filtre Core Image générique. |
| Animems — éditeur | `core/BitmapCacheManager.java` | `Animems/BitmapCacheManager.swift` | ÉCRIT (NON COMPILÉ) | Cache feather/mask reproduit à l'identique (mêmes seuils `CACHE_DELTA_THRESHOLD`/0.01). `System.identityHashCode(src)` → `ObjectIdentifier(source)` (`CGImage` est un type `CF`, référence stable). `applyFeather` : même approximation `CIGaussianBlur` documentée que `MaskFactory` (Android floute uniquement le masque alpha du `Paint`, `CIGaussianBlur` floute RGB+alpha ensemble — effet de bord adouci proche, pas pixel-exact). |
| Animems — éditeur | `core/AnimationEngine.java` (398 lignes, lu en entier) | `Animems/AnimationEngine.swift` | ÉCRIT (NON COMPILÉ) | Table de frames (`transformationArray`, quel `Transform` local afficher par calque/frame) reproduite à l'identique. Lecture (`play`/`pause`/`stop`) : `android.animation.TimeAnimator` → `CADisplayLink` (via un `NSObject` proxy privé, `CADisplayLink` n'ayant pas d'initialiseur à fermeture native) — `deltaTime` Android reconstitué depuis les horodatages `CADisplayLink` successifs. `bakeTransformKeyframesToGL`/`androidToGL_Matrix2`/`smoothObjectTransforms` portés SANS leur étape de conversion GL finale (voir décision d'architecture Core Graphics ci-dessus) — renommé `bakeMatrixKeyframesToTransforms` pour refléter ce périmètre réduit assumé. Algorithme de lissage Chaikin (`chaikin`, moyenne 1-2-1 glissante) porté à l'identique. |
| Animems — éditeur | `model/TimelineItem.java` | `Animems/TimelineItem.swift` | ÉCRIT (NON COMPILÉ) | Port direct, `struct` (la méthode `copy()` Android n'a plus d'objet — copie-à-l'assignation déjà le comportement par défaut d'un `struct`). |
| Animems — éditeur | `model/StickerData.java`, `model/PlaylistEntry.java`, `model/DrawPathFrameData.java` | `Animems/StickerData.swift`, `Animems/PlaylistEntry.swift`, `Animems/DrawPathFrameData.swift` | ÉCRIT (NON COMPILÉ) | Ports triviaux. `DrawPathFrameData` : `recycle()` Android non porté (ARC gère la libération mémoire de `CGImage`, `nil` suffit). |
| Animems — éditeur | `model/SerializableAnimationObject.java` | `Animems/SerializableAnimationObject.swift` | ÉCRIT (NON COMPILÉ) | Sérialisation base64 PNG confirmée en lisant `Utils/BitmapUtils.bitmapToBase64`/`base64ToBitmap` (`Bitmap.CompressFormat.PNG`, qualité 100, PAS JPEG — vérifié, pas supposé) → `UIImage(cgImage:).pngData()`. **`AnimationObjectData.Type` (11 cas) revérifié directement contre sa déclaration réelle** (`core/AnimationObjectData.java:21-23`) pour que `ObjectType: String` (Swift) porte des `rawValue` IDENTIQUES aux noms Android (`Type.name()`/`Type.valueOf()`) — nécessaire pour un round-trip de sérialisation correct, pas pour l'usage interne seul (où le nom exact n'aurait pas eu d'importance). Champs mask/keyframes/shape NON repris : confirmé que la classe Android elle-même ne les sérialise pas (périmètre réel de la classe, pas une lacune de portage). |
| Animems — éditeur | `AnimemesCompound.testTimeLine().resampleTransforms`/`resampleMaskTransforms` (méthodes privées imbriquées, lues en lisant `AnimemesCompound.java` par tranches) | `Animems/AnimationObjectData.swift` (`resampleTransforms`/`resampleMaskTransforms`) | ÉCRIT (NON COMPILÉ) | Remontées de méthodes privées d'un listener UI vers des méthodes de l'objet lui-même (aucune dépendance sur `TimelineView`/`MemesView2` dans leur corps, vérifié) — ré-échantillonnage linéaire d'un tableau de `Transform` vers un nombre de frames cible (redimensionnement d'un bloc de timeline en mode capture automatique). **Écart de représentation signalé, pas masqué** : la boucle Android cherche en scannant à rebours la dernière `Transform` dont `matrix` n'est PAS `null` (repli) — `Transform.matrixValues` (Swift) ne peut représenter cet état "sans matrice" (toujours 9 valeurs, identité par défaut) ; dans tous les chemins de construction lus jusqu'ici cette situation ne semble jamais survenir en pratique, mais `MemesView2.java` (capture tactile, pas lu en entier) pourrait révéler un chemin où elle se produit — repli simplifié sur la dernière entrée du tableau, à corriger si besoin. `glMatrix`/`androidToGL_Matrix2` non recalculés (décision d'architecture Core Graphics déjà actée). |
| Animems — éditeur | `AnimemesCompound.fitBitmapIntoSize` | `Animems/BitmapGeometry.swift` | ÉCRIT (NON COMPILÉ) | Fonction pure autonome (aucune dépendance `View`/`Context`), portée telle quelle — redimensionnement "aspect fit" centré dans un canevas transparent. |
| Animems — éditeur | `engine/android/memes/MemesView2.java` — `onDraw`/`drawBitmapLastTransform`/`drawObjectFrame` (lus en détail, ~350 lignes ciblées sur le rendu BITMAP/SHAPE, sur 1978 lignes au total) | `Animems/LayerRenderer.swift` | ÉCRIT (NON COMPILÉ) | **Cœur du rendu des calques BITMAP/SHAPE_RECT/SHAPE_CIRCLE/SHAPE_LINE, la pièce la plus déterminante du module 8 pour qu'un aperçu réel soit un jour possible.** Deux méthodes Android quasi-identiques (aperçu statique avec cache vs lecture/scrubbing sans cache) factorisées en un `composite(...)` interne commun — **UNE vraie différence de comportement entre les deux préservée explicitement** (repli de rayon de bulle à 10 si `cornerRadius<=0` pour l'aperçu statique SEULEMENT, pas pour la lecture) après qu'un premier jet l'ait accidentellement effacée en factorisant trop vite — corrigé avant tout build par relecture. Teinte `PorterDuffColorFilter(color, SRC_ATOP)` reproduite via `beginTransparencyLayer`+remplissage `.sourceAtop` (isolation du bitmap comme "destination" pour l'opération atop, équivalent exact) ; masque `DST_IN` via `.destinationIn`. **Risque de double-application d'opacité identifié et neutralisé par construction** (pas rencontré puis corrigé, anticipé) : `context.setAlpha` s'applique à la fermeture de CHAQUE couche de transparence imbriquée traversée — sans précaution, l'opacité du calque aurait pu s'appliquer deux fois (une fois pour la couche de teinte imbriquée, une fois pour la couche de masque extérieure) ; neutralisé en réinitialisant l'alpha à 1 juste après l'ouverture de la couche extérieure. **Non vérifié visuellement** (aucun accès à un simulateur), signalé comme les autres zones à risque de ce portage. `TEXT`/`STICKER` portés dans une passe suivante (voir lignes `TextLayoutEngine.swift`/`drawShap` ci-dessous). `PATH`/`LINE`/`CLIP`/`ERASE` NON portés, décision motivée (voir ligne suivante). `recomposeObjects`/`computeRecomposeBounds` (fusion en séquence GIF) PAS encore lus ni portés. |
| Animems — éditeur | `MemesView2.drawPath`/`drawLine`/`clipPath`/`erase` (lus) | — | NON PORTÉ (décision) | Confirmé, PAS un oubli de lecture : ce sont les rendus du GESTE DE DESSIN LIBRE EN COURS (champs classe `path`/`inicialX/Y`/`finalX/Y`, un seul geste actif, pas liés à un `AnimationObjectData` précis) — pas des calques avec état persistant comme les autres types. `clipPath` a un corps VIDE côté Android (`{}`), confirmé mort. Porter le rendu du geste avant que la capture tactile elle-même soit conçue serait prématuré — reporté après la conception des gestes (pas encore abordée). |
| Animems — éditeur | `Utils/TextLayoutEngine.java` (lu en entier) | `Animems/TextLayoutEngine.swift` | ÉCRIT (NON COMPILÉ) | Moteur de découpage de texte en lignes, 100% pur côté Android ("compatible KMP à terme" — commentaire du fichier source). Port fidèle EN UNITÉS UTF-16 (`[UInt16]`), PAS `String.Index` Swift : l'algorithme Java indexe caractère par caractère (`charAt`/`substring`/`indexOf`/`lastIndexOf`), et un `String.Index` Swift (délimité par grapheme cluster) romprait cette correspondance terme à terme — un texte avec emoji serait démembré à la MÊME limite qu'en Java (paire de substituts UTF-16 coupée), comportement identique, pas une régression. Sentinelle `-1` (pas `Int?`) conservée pour `indexOf`/`lastIndexOf` : le code Java compare directement `blank > start` avec `-1` dans son arithmétique, un `Optional` aurait exigé une reformulation avec risque de dévier subtilement. |
| Animems — éditeur | `android/renderer/TextRect.java` (lu en entier) | `Animems/TextRect.swift` | ÉCRIT (NON COMPILÉ) | Rendu du texte découpé par `TextLayoutEngine` dans un `CGContext`. **Approximation documentée, pas pixel-exacte** : métriques via `UIFont.ascender`/`.descender`/`.leading` (police système iOS) plutôt que `Paint.FontMetricsInt` (police système Android) — aucune tentative de faire correspondre visuellement les deux systèmes de polices, seul le comportement (retour à la ligne, troncature "...") est reproduit. **Piège de signe évité** : `UIFont.descender` est NÉGATIF (sous la baseline) alors qu'Android `metrics.descent` est POSITIF pour la même grandeur physique — `-font.descender` restaure la convention positive attendue. Ancrage à la BASELINE (comme `Canvas.drawText`) reproduit en compensant `NSString.draw(at:)` (qui ancre au coin haut-gauche par défaut) de `-font.ascender`. |
| Animems — éditeur | `MemesView2.writeText` (TEXT) | `Animems/LayerRenderer.swift` (`drawText`) | ÉCRIT (NON COMPILÉ) | `outerPadding`/`bubblePadding` Android (`round(16*dp)`/`round(8*dp)`, mise à l'échelle densité manuelle) simplifiés en constantes fixes `16`/`8` POINTS — un point iOS étant déjà indépendant de la densité, simplification légitime par différence de plateforme. **Effet de bord "baking" reproduit** : si le calque n'a pas encore de bitmap figée, une bitmap bulle+texte est générée et stockée — pas consommée par le rendu live (qui redessine toujours via `TextRect`), mais par de futurs consommateurs (export, `recomposeObjects`) qui attendent un bitmap classique. **Curiosité Android reproduite telle quelle, signalée, pas corrigée** : `bmpH = h + bound.height()` additionne `textHeight` deux fois (`bound.height` le contient déjà) — bitmap "figée" plus haute que nécessaire, comportement observable préservé sans le "corriger" silencieusement. |
| Animems — éditeur | `MemesView2.drawShap` (STICKER) | `Animems/LayerRenderer.swift` (`drawSticker`) | ÉCRIT (NON COMPILÉ) | Le plus simple des types de calque : ni teinte, ni masque, ni feather, ni bulle — juste le bitmap courant dessiné à la position du calque avec sa matrice. `canvas.setMatrix()` Android (remplace tout le CTM) traité comme équivalent à `concatenate` ici, sur la même hypothèse de CTM de base identité déjà posée pour les autres méthodes de rendu de ce fichier. |
| Animems — éditeur | `android/codec/MP4Encoder.java` + `Encoder.java` (structure complète lue — constantes, `onAddFrame`, init GL, chaîne d'appel réelle confirmée dans `AnimemesCompound.createVideosFromBitmap` — MAIS PAS le détail des ~1400 lignes GLSL/`MediaCodec` bas niveau, décision motivée dans le fichier Swift) | `Animems/AnimemesExporter.swift` | ÉCRIT (NON COMPILÉ) | **Export MP4 via `AVAssetWriter`, réutilisant `AnimationEngine`+`LayerRenderer` déjà portés** — exactement le chemin de rendu partagé aperçu/export rendu possible par la décision d'architecture Core Graphics. Chemin RÉEL confirmé par lecture (pas supposé) : `onSurfaceStartEncode()`→`addFrame(composer)`→`startFrameEncoding()`→`onAddFrame`, PAS les autres modes de l'`Encoder` de base (`onEncodeMp4FomBitmap`/bitmap queue, byte queue) — confirmés non exercés par ce flux, non portés. Boucle de frames (`totalFramesMinus1`/bouclage `MODE_LOOP` si l'audio dépasse la durée de l'animation) reproduite fidèlement depuis `onAddFrame`. **Simplification légitime par capacité de plateforme, documentée en tête de fichier, pas une lacune** : les ~250 lignes de `transcodeToM4A`/normalisation audio manuelle (BUG 1/2/3 documentés dans les commentaires Android, sample rate HE-AAC réel vs déclaré...) n'ont pas de contrepartie nécessaire — `AVAssetReader`/`AVAssetWriterInput` gèrent nativement la plupart des formats audio courants sans transcodage manuel préalable. **Bug trouvé et corrigé avant tout build** : le compteur de frame `f` était initialement local à la closure passée à `requestMediaDataWhenReady` — puisque cette closure est RAPPELÉE par `AVAssetWriterInput` à chaque fois qu'il redevient prêt (pas un seul appel), `f` aurait été réinitialisé à 0 à chaque reprise au lieu de continuer où l'écriture s'était arrêtée. Corrigé en déclarant `f` dans la portée englobante (capturé par référence par la closure). **TODO explicite non porté à ce stade** : flou d'arrière-plan (`blurEnabled`), effet `FRAGMENT_EFFECT`, vidéo "outro" (`OUTRO_DURATION_SEC`) — confirmés non branchés dans le flux réellement exercé par `AnimemesCompound.java`, pas des oublis. Valeurs de retour `Bool` de `append`/`startWriting` non vérifiées dans ce premier passage (gestion d'erreur incomplète, signalée explicitement plutôt que masquée). |
| Animems — éditeur | `MemesView2.java` — geste tactile (lu en entier : `GestureListener`/`ScaleListener`/`onTouchEvent`/`touchDown`/`touchMove`/`touchUp`/`translation`/`rotate`/`scale`/`safePostScale`/`isPointInsideObject`/`bringLayerToFront`) | `Animems/AnimemesGestureController.swift` | ÉCRIT (NON COMPILÉ) | **Logique de transformation (mathématiques) séparée délibérément du câblage de gestes SwiftUI** (`DragGesture`/`MagnificationGesture`/`RotationGesture`, pas encore écrit) — la logique de matrice est vérifiable ligne à ligne contre l'original, le câblage de gestes multi-touch simultanés ne peut pas être vérifié sans simulateur ; séparer évite qu'une incertitude d'assemblage ne contamine des maths déjà fiables. **Deux bugs sérieux trouvés et corrigés AVANT tout build** : (1) `CGAffineTransform.inverted()` n'est PAS optionnelle contrairement à `Matrix.invert()` Android (retourne la transformation inchangée sur une matrice non inversible plutôt qu'un signal d'échec) — code initial utilisait `if let` sur un type non-Optional, ne pouvait pas compiler. (2) **Piège d'ordre de composition** : `postTranslate`/`postRotate`/`postScale` Android appliquent la nouvelle opération APRÈS la matrice existante (repère de destination) ; `CGAffineTransform.translatedBy`/`.rotated(by:)`/`.scaledBy` de Core Graphics ont la sémantique INVERSE (équivalent `pre*`, pas `post*`) — un premier jet aurait donc transformé les calques dans le mauvais repère dès qu'un calque est pivoté/mis à l'échelle. Corrigé en construisant chaque composante "post" comme une transformation autonome puis `tfm.concatenating(composantePost)`. Différence de sémantique Android (gestes incrémentaux)/SwiftUI (`MagnificationGesture`/`RotationGesture` cumulatifs depuis le début du geste) documentée explicitement pour la future vue de câblage. Mode d'édition de masque (`handleMaskEditTouch`/`maskApplyDrag`/`cummulateMaskTransform`) lu mais PAS encore porté — différé, la logique de masque de base (`AnimationObjectData.maskOffsetX` etc.) existe déjà, seul le geste dédié manque. |
| Animems — éditeur | `MemesView2.recomposeObjects`/`computeRecomposeBounds` (lus au passage précédent) + `AnimemesCompound.getRecomposeCandidates`/`computeDefaultTotalFrames`/`performRecompose` (lus cette passe, ~3438-3573) | `Animems/AnimemesRecompose.swift` | ÉCRIT (NON COMPILÉ) | Fusion de plusieurs calques sélectionnés en une séquence de bitmaps (façon GIF), réutilisant `LayerRenderer.drawObjectFrame` (conçu dès `AnimemesExporter` pour cette réutilisation). Porte la logique PURE (candidats, bornes, rendu, construction du calque résultat) — PAS la partie orchestration UI de `performRecompose` : `AnimemesRecomposeNameSheet` (dialogue de nommage) et `RecomposeManager.save` (persistance disque PNG) restent non lus/non portés (système séparé de la fusion elle-même), de même que le lien avec `TimelineView` pour l'icône de groupe "▼"/le filtrage par groupe (`enterGroupView`/`exitGroupView`/`applyDefaultTimelineFilter`/`syncVisibilityIcon`, lus mais non portés — dépendent de `TimelineView`, dont seule la logique d'état est portée, voir ligne `TimelineViewModel.swift`). |
| Animems — éditeur | `android/views/AnimemesCompound.java` — fin de la lecture intégrale (lignes ~2645-3931, dernière tranche de ~1300 lignes) : dialogues de sauvegarde, tutoriel `TapTargetSequence`, "Animate"/`MotionGenerator`, IA (`AIObjectGenerationDelegate`), suppression d'arrière-plan (`RemoveBackground`/ML Kit), vue groupe recompose | — | LU EN ENTIER (3931/3931 lignes), NON PORTÉ (décision documentée) | **6 sous-systèmes secondaires découverts, aucun lu en détail au-delà de leur point d'appel dans `AnimemesCompound`** — tous confirmés distincts du cœur modèle→gestes→rendu→export déjà fermé, tous nécessitant leur propre passage de lecture dédié : (1) **Motion Templates** (`MotionTemplate`/`MotionTemplateManager`/`MotionTrack`) — bibliothèque de mouvements réutilisables, classes jamais ouvertes. (2) **Persistance disque du recompose** (`RecomposeManager`/`RecomposeTemplate`, `AnimemesRecomposeNameSheet`) — sauvegarde des séquences fusionnées en PNG sur disque, distincte de la fusion en mémoire (`AnimemesRecompose.swift`, déjà portée). (3) **Tutoriel/onboarding** (`TapTargetSequence`/`TapTarget`, bibliothèque tierce Android) — purement cosmétique, sans logique de données, PAS un candidat de portage (SwiftUI a ses propres mécanismes d'overlay/coach-mark). (4) **Génération procédurale de mouvement** (`MotionGenerator.generateMouthTalkCycle`, bouton "Animate") — classe jamais ouverte. (5) **Génération d'objet par IA** (`AIObjectGenerationDelegate`, `startAIGeneration`/`replaceObjectWithAIResult`) — dépend d'un service IA externe non identifié ; `replaceObjectWithAIResult` (mutation de données pure, remplacement de bitmap + recentrage) serait portable isolément mais n'a aucune utilité sans le service qui l'appelle. (6) **Suppression d'arrière-plan** (`RemoveBackground.removeBackgroundWithMLKit`/`removeBackgroundAdvanced`) — ML Kit Android n'a pas d'équivalent iOS direct ; l'équivalent naturel serait `VNGeneratePersonSegmentationRequest`/`VNGenerateForegroundInstanceMaskRequest` (Vision framework, iOS 15+), mais ceci nécessite sa propre étude, pas une substitution mécanique. Ces 6 points représentent un périmètre PLUS LARGE que ce que l'estimation initiale du module 8 laissait supposer — communiqués explicitement ici plutôt que silencieusement absorbés dans la clôture du module. |
| Animems — éditeur | `android/utils/ShapeFactory.java` (lu en entier) | `Animems/ShapeFactory.swift` | ÉCRIT (NON COMPILÉ) | Rasterisation Core Graphics des 3 formes (rectangle/cercle/ligne) en `CGImage`, port complet y compris le contour "assombri" (`darkenColor`, HSV `V -= 0.25`) et la règle Android "l'alpha du `Paint.setColor` est TOUJOURS remplacé par `setAlpha` séparé" (reproduite via `argbColor(_:alpha:)`, qui ignore délibérément l'octet alpha packé de la couleur d'entrée). `rerender(_:canvasW:canvasH:)` relit les propriétés `shape*` déjà présentes sur `AnimationObjectData` (ajoutées lors d'un passage antérieur, confirmées correspondre exactement aux accesseurs Android utilisés ici). |
| Animems — éditeur | `android/views/BezierEditorView.java` (lu en entier) | `Animems/BezierEditorView.swift` | ÉCRIT (NON COMPILÉ) | Éditeur de courbe de Bézier cubique normalisée (easing personnalisé) — fichier auto-contenu (aucune dépendance timeline/moteur), donc porté EN ENTIER modèle+rendu+gestes (contrairement aux autres vues custom de ce lot, dont seule la logique d'état est portée) : `BezierControlPoints.interpolation(at:)` reproduit la résolution de Newton-Raphson à l'identique (8 itérations, tolérance `1e-6`), `BezierEditorView` (SwiftUI `Canvas`+`DragGesture`) reproduit `onDraw`/`onTouchEvent`. Non vérifié visuellement (pas de simulateur), comme le reste de ce portage. |
| Animems — éditeur | `android/Paint/PaintPreviewEditorPanel.java` (lu en entier) | `Animems/PaintCapture.swift` | ÉCRIT (NON COMPILÉ) | Dessin au doigt capturé comme séquence de frames bitmap (calque animé façon GIF) — fichier auto-contenu, porté EN ENTIER comme `BezierEditorView`. `PaintCaptureController` reproduit le lissage quadratique (`quadTo(lastPoint, milieu)` → `CGMutablePath.addQuadCurve(to:control:)`) et la capture d'une frame toutes les 6 itérations de mouvement (`CAN_DRAW`) + une frame finale systématique au relâchement. Palette/sliders/boutons (pure disposition Android sans logique) laissés à l'appelant SwiftUI — seule la surface de dessin (`PaintDrawingCanvas`) est fournie. |
| Animems — éditeur | `android/views/LayerEditorPanel.java` (lu en entier) | `Animems/LayerEditorPanelState.swift` | ÉCRIT (NON COMPILÉ) | Logique d'état SEULE (pas la construction `LinearLayout`/`SeekBar` Android, non portable 1:1) : `bindToLayer` (dérivation des valeurs initiales — priorité dernière `Transform`, repli forme/masque selon un ordre de priorité qui DIFFÈRE entre `opacity` (jamais de repli masque) et `feather` (repli masque seulement si `Transform.feather == 0`), reproduit à l'identique) et `refreshCornerRowVisibility` (règle de visibilité par type). Vue SwiftUI différée : dépend de la sélection courante dans la timeline, pas encore construite. |
| Animems — éditeur | `android/mask/MaskPreviewEditorPanel.java` (lu en entier) | `Animems/MaskPreviewEditorPanelState.swift`, `MaskType.displayName` (ajouté) | ÉCRIT (NON COMPILÉ) | Logique d'état seule (même raison que `LayerEditorPanelState`). **`buildFinalBitmapStatic`/`applyOpacity` (Android) délibérément NON portés — confirmés OBSOLÈTES par l'architecture Swift, pas juste différés** : ces méthodes ré-écrivaient manuellement le canal alpha du bitmap de masque pour appliquer l'opacité AVANT compositing (contournement Android) ; `LayerRenderer.composite` applique déjà l'opacité une seule fois via `context.setAlpha` au moment du dessin du calque masqué — les reporter aurait appliqué l'opacité EN DOUBLE. |
| Animems — éditeur | `android/views/ShapePreviewEditorPanel.java` (lu en entier) | `Animems/ShapePreviewEditorPanelState.swift` | ÉCRIT (NON COMPILÉ) | Logique d'état seule : `makeDefault(shapeType:canvasW:canvasH:)` (dimensionnement par défaut selon le type, port d'`init`) et `rowVisibility(for:)` (règles de visibilité des contrôles arrondi/épaisseur/contour selon le type). Palette (18 couleurs) reprise telle quelle. |
| Animems — éditeur | `android/views/MovementControllerHandlerView.java` + `listener/MovementControllerHandlerListener.java` (lus en entier) | `Animems/MovementControllerState.swift` | ÉCRIT (NON COMPILÉ) | **Découverte importante** : ce panneau de bascules (zoom/rotation/skew/top/bottom/left/right/ancrage) + slider d'angle NE GATE PAS le geste tactile libre déjà porté dans `AnimemesGestureController.swift` — c'est un mode de transformation PRÉCIS par curseur, entièrement SÉPARÉ et ADDITIF (`anchorPoint == true` → pilote `applySeekBarTransformOnAnchor`/`anchorTouchExecute` dans `MemesView2.java`, ni l'un ni l'autre lus). Seul l'état des bascules est porté ; la logique de transformation par curseur elle-même reste un sous-système ENTIER non exploré — voir "Points à vérifier en priorité" ci-dessous. |
| Animems — éditeur | `android/views/CanvasZoomController.java` (lu en entier) | `Animems/CanvasZoomController.swift` | ÉCRIT (NON COMPILÉ) | Zoom du canvas d'édition (boutons +/−/fit), DISTINCT du zoom de la timeline (`TimelineViewModel.applyPinchZoom`). Fichier auto-contenu, porté EN ENTIER (modèle `CanvasZoomState` + rendu SwiftUI `CanvasZoomControls`) comme `BezierEditorView`/`PaintPreviewEditorPanel` — `computeMinZoom` (zoom minimum garantissant que la vue cible tient dans son parent) reproduit à l'identique. |
| Animems — éditeur | `android/views/ProTextEditorView.java` (lu en entier, 923 lignes) | `Animems/ProTextEditorState.swift` | ÉCRIT (NON COMPILÉ) — PORTÉE RÉDUITE, JUSTIFIÉE | **~850 des 923 lignes confirmées être de la construction de vue Android pure** (`LinearLayout`/`RecyclerView`/`ColorAdapter`/`FontAdapter`/`ColorDot` programmatiques), sans logique réutilisable au-delà de l'état (`textColor`/`bgColor`/`textSizeSp`/`font`/`alignment`/`bgEnabled`/`cornerDp`), de la palette (16 couleurs) et de `darkenFor` (NON reporté séparément : formule HSV identique à `ShapeFactory.darken`, juste des constantes différentes — dupliquer aurait été une simple divergence de constantes). Mapping police Android (`Typeface.SANS_SERIF/SERIF/MONOSPACE`) → SF Pro/SF Pro Serif/SF Mono via `ProTextFont.font(size:)`, à confirmer visuellement (pas d'équivalence 1:1 garantie). Champ de texte réel (`TextField`/`TextEditor` SwiftUI) et rendu bitmap final (`renderBitmap`, snapshot natif) différés — nécessitent un simulateur pour être ajustés visuellement. |
| Animems — éditeur | `android/memes/FrameAdapter.java` (lu en entier, 355 lignes) | `Animems/FrameListState.swift` | ÉCRIT (NON COMPILÉ) — PORTÉE TRÈS RÉDUITE, DÉCOUVERTE IMPORTANTE | **Ce fichier ne fait PAS partie du système `AnimationEngine`/keyframes déjà porté** — c'est le pilote d'une bande de vignettes pour un sous-système SÉPARÉ de capture "image par image" façon flipbook (`mView.newFrame()`/`deleteFrame()`/`FrameConnectionListener`, AUCUNE de ces méthodes `MemesView2` lues), dépendant de classes entièrement non lues : `FrameData`, `Frame` (modèle JSON Gson distinct de `SerializableAnimationObject`), `SerializableManager` (persistance disque), `ImageViewRound`/`ButtonAddFrame` (2 vues custom SUPPLÉMENTAIRES non comptées dans la liste initiale des ~10-14), et une classe `MemesView` (sans le `2`) au code probablement mort (`TestViewHolder`, type `3` jamais atteint en pratique). Seule la logique de gestion de LISTE (`add`/`addWidthLimit`/`addHead`/`removeView`, y compris la particularité de nommage trompeur `addHead` qui ajoute en fin de liste, reproduite telle quelle) est portée, indépendante du type d'élément. Sous-système entier à explorer dans une passe dédiée future — voir "Points à vérifier en priorité". |
| Animems — éditeur | `android/mask/MaskAddPanel.java`, `android/views/ShapeAddPanel.java` (lus en entier) | — | LU, NON PORTÉ (décision) | Pickers bottom-sheet purs (grille d'icônes tapables), aucune logique au-delà de l'énumération déjà couverte par `MaskType`/`AnimationObjectData.ObjectType` existants — construction `LinearLayout`/`HorizontalScrollView` non portable 1:1, sans contenu algorithmique à extraire. À reconstruire directement en SwiftUI (`Picker`/grille de boutons) au moment de la construction de l'écran d'édition, pas avant. |
| Animems — éditeur | `engine/mask/MaskEditController.java` (lu en entier, 18 lignes) | `Animems/MaskEditController.swift` | ÉCRIT (NON COMPILÉ) | Protocoles de callback purs (`OnMaskGestureListener`/`OnMaskEditModeListener`) — port direct en protocoles Swift. Aucune implémentation concrète encore écrite : dépend du mode d'édition de masque par geste (`handleMaskEditTouch` etc.), lu mais non porté dans `AnimemesGestureController.swift`. |
| Animems — éditeur | `android/views/TimelineView.java` (lu en entier, 1320 lignes — la plus volumineuse des vues custom restantes) | `Animems/TimelineViewModel.swift` | ÉCRIT (NON COMPILÉ) | **Logique pure séparée du rendu**, même principe que `AnimemesGestureController.swift` : coordonnées (`xAtFrame`/`frameAtX`/`playheadX`, avec le playhead toujours centré et le contenu qui défile — modèle "CapCut"), zoom pincé avec ancrage au point focal (`applyPinchZoom`), pan, drag/redimensionnement d'un item AVEC anti-chevauchement (`resolveOverlap`/`resolveOverlapResizeLeft`/`resolveOverlapResizeRight`, portés à l'identique y compris le garde-fou de boucle et l'extension automatique de `totalFrames`), hit-test (items + marqueurs de keyframe). PAS porté, délibérément : rendu `onDraw`/`drawRuler`/`drawPlayhead`/`drawKeyframeMarkers` (deviendra un `Canvas` SwiftUI), physique de fling `OverScroller`/`VelocityTracker` (aucun équivalent direct — SwiftUI fournit sa propre vélocité de geste, la ballistique reste à concevoir visuellement), planification d'appui long `Handler`/`Runnable` (remplacée trivialement par `.onLongPressGesture`), sérialisation JSON manuelle `toJson`/`fromJson` (redondante avec un futur `Codable` direct sur `TimelineItem`, déjà un type Swift natif). `selected` (référence Java vive) adapté en `selectedId: String?` + recherche par id dans `items` (`TimelineItem` étant un `struct` Swift, pas une classe — différence de représentation déjà actée pour ce type, pas nouvelle ici). |
| Éditeur photo | `android/croper/CropImageView.java` (2136), `CropOverlayView.java` (1039), `CropWindowHandler.java` (371, lu en entier), `CropWindowMoveHandler.java` (764), `CropImageOptions.java` (463), `BitmapUtils.java` (877), `CropImage.java` (998, hors `toOvalBitmap`) | — | REMPLACÉ (décision d'architecture, PAS un port) | **Bibliothèque tierce vendorisée identifiée** (pas du code métier Tiinver) : `CropWindowHandler.java` porte encore l'en-tête de licence caractéristique + une citation de Sun Tzu — signature de la librairie "Android-Image-Cropper" (ArthurHub/CanHub), intégrée en source dans le dépôt plutôt qu'en dépendance. Remplacée par **`TOCropViewController`** (SPM, `github.com/TimOliver/TOCropViewController`, tag `3.2.0`) — vérifié avant choix (pas deviné) : `pushed_at` très récent (2026-07-28), 4947 ⭐, non archivé (`GET /repos/.../TOCropViewController` réel), `Package.swift` réel au tag `3.2.0` confirmé (`platforms: [.iOS(.v12)]`, compatible `deploymentTarget.iOS = "16.0"`), API Swift (`CropViewController.swift`) lue directement dans le dépôt réel avant d'écrire le wrapper (`init(croppingStyle:image:)`, `onDidCropToRect`/`onDidCropToCircleImage`/`onDidFinishCancelled`, `TOCropViewCroppingStyle.default`/`.circular` vérifiés dans `TOCropViewConstants.h` réel). Géométrie de poignées tactiles (`CropWindowHandler.getRectanglePressedMoveType`/`getOvalPressedMoveType`, zones de détection par coin/bord/centre) NON portée : entièrement prise en charge par la librairie. |
| Éditeur photo | `android/views/CroperView.java` (435, lu en entier) | `PhotoEditor/PhotoCropView.swift`, `PhotoEditor/PhotoEditorState.swift` | ÉCRIT (NON COMPILÉ) | Wrapper `UIViewControllerRepresentable` autour de `TOCropViewController` + état d'orchestration (mode RECT/FREEFORM, suppression d'arrière-plan à deux niveaux — voir ligne `RemoveBackground.swift`). **Confirmé mort par grep, NON porté** : `CroperView.removeBackground(src, bgColor, tolerance)` (méthode statique de tolérance de couleur unique, "Tolerance-based quick eraser (original, preserved as static util)" selon son propre commentaire) — zéro appelant dans tout le dépôt. **Point à vérifier** : `handleFlip`/`CropImageView.setFlippedHorizontally` n'a pas d'équivalent direct exposé par `TOCropViewController` (pas de flip horizontal en cours d'édition dans son API publique) — nécessiterait de pré-retourner l'image AVANT présentation du contrôleur de recadrage si ce comportement doit être reproduit à l'identique, non résolu ici. Animations de pression de bouton/overlay de progression Android non reprises (présentation SwiftUI standard). |
| Éditeur photo | `android/croper/FreeformCropView.java` (126, lu en entier) | `PhotoEditor/FreeformCropView.swift` | ÉCRIT (NON COMPILÉ) | Auto-contenu (aucune dépendance sur le reste du recadreur), porté EN ENTIER modèle+rendu+gestes comme `BezierEditorView`/`PaintPreviewEditorPanel` du module 8 — seul mode de recadrage NON couvert par `TOCropViewController` (tracé au doigt fermé comme masque, pas rect/ovale). Piège de repère Y déjà rencontré (`MaskFactory`/`PaintCapture`/`AnimemesRecompose`) évité dès l'écriture : flip explicite appliqué au contexte bitmap manuel avant le clip par le tracé mis à l'échelle. |
| Éditeur photo | `Utils/RemoveBackground.java` (176, lu en entier — catégorie "A+G" du rapport, PARTAGÉ avec le module 8 : `AnimemesCompound.java` section "REMOVE BACKGROUND", jamais lue en détail à l'époque, s'avère être le MÊME fichier) | `PhotoEditor/RemoveBackground.swift` | ÉCRIT (NON COMPILÉ) | **Décision d'architecture vérifiée contre la documentation Apple réelle (WebSearch + `curl` sur les headers/`Package.swift` réels, pas devinée)** : `removeBackgroundWithMLKit` (Android, `SubjectSegmenter` ML Kit — sujet GÉNÉRAL) remplacé par `VNGeneratePersonSegmentationRequest` (Vision, iOS 15+, compatible `deploymentTarget.iOS=16.0`) — PAS `VNGenerateForegroundInstanceMaskRequest` (équivalent plus proche de "sujet général", mais confirmé iOS 17+ UNIQUEMENT et confirmé NE FONCTIONNE PAS en simulateur ; relever la cible de déploiement pour cette seule fonctionnalité dépasse ce portage, décision produit non prise unilatéralement — voir tête de fichier). **Écart fonctionnel réel documenté, pas masqué** : la personne uniquement est segmentée, pas un objet/animal général comme `SubjectSegmenter` le permettait. Masque : polarité blanc=sujet/noir=fond vérifiée par recherche (pas supposée) avant d'écrire le blend `CIBlendWithMask`. `removeBackgroundAdvanced`/`applyEdgeRefinement` (repli géométrique par échantillonnage de bordure + rampe alpha + érosion 1-passe) portés fidèlement, constantes Android identiques (`TOLERANCE=55`, `SOFT_BAND=25`, `BORDER∈[2,20]`). **Bug de pré-multiplication évité par construction** (pas rencontré puis corrigé, anticipé pendant l'écriture) : un premier jet relisait la sortie de l'étape de masquage via un `CGContext` (nécessairement pré-multiplié) avant l'affinement des bords, ce qui aurait corrompu les octets RVB des pixels de bordure fraîchement semi-transparents — corrigé en gardant les deux passes sur le MÊME buffer `[UInt8]` en mémoire, sans aller-retour `CGImage` intermédiaire, et en construisant l'image finale directement via `CGDataProvider`/`CGImage(bitmapInfo: .last)` (straight alpha, PAS `CGContext.makeImage()` qui aurait forcé une pré-multiplication du résultat). `android/croper/BackgroungRemover.java` (578 lignes, pipeline `Canny`/`ConnectedComponenteLabeling`/`Dilation` maison) **confirmé mort par grep** (zéro instanciation) — PAS le même chemin que `RemoveBackground.java`, non porté. |
| Éditeur photo | `android/croper/imageprocessing/**` (9 fichiers : `Canny.java`, `Convolution.java`, `GrapCut.java`, `ConnectedComponenteLabeling.java`, `Dilation.java`, `Segmentation.java`, `MyImage.java`, `Edgedetection.java`, `GaussianSmooth.java` — 2513 lignes) | — | REMPLACÉ (décision d'architecture, PAS un port) | Pipeline de vision par ordinateur MAISON (détection de contours Canny, convolution, GrabCut, étiquetage de composantes connexes) — recommandation explicite du rapport `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.3 de le remplacer par le framework Vision natif plutôt que de le porter ligne à ligne (gain de temps ET de risque : code Apple maintenu vs. algorithmes de vision par ordinateur maison de style 2013-2015). Uniquement consommé par `BackgroungRemover.java`, lui-même confirmé mort (voir ligne précédente) — ce pipeline n'était donc même plus atteignable en pratique côté Android, pas seulement candidat au remplacement. |
| Éditeur photo | `android/croper/CropImage.java` (`toOvalBitmap` uniquement, ligne 100-122) | `PhotoEditor/PhotoCropUtils.swift` | ÉCRIT (NON COMPILÉ) | Seule fonction statique de `CropImage.java` réellement consommée (`CroperView.onCropImageComplete`) — le reste du fichier (998 lignes, orchestration `CropImageActivity`/intents Android) est couvert par `TOCropViewController`. |
| Éditeur photo | `android/views/ImageEditorCompound.java` (1132 lignes, lu PARTIELLEMENT — `init()`/constructeurs/`setImageUri`/`fitBitmapToView`, ~280 des 1132 lignes) | — | LU PARTIELLEMENT, PAS PORTÉ (décision) | **Écran principal de l'éditeur photo simple** : toolbar stickers/texte/peinture/emoji par-dessus l'image recadrée, réutilisant le MÊME modèle `AnimationComposer`/`AnimationObjectData`/`Transform` que `AnimemesCompound.java` (module 8, déjà entièrement porté) plutôt qu'un système séparé — confirmé en lisant les imports (`core.AnimationComposer`, `core.AnimationObjectData`, `core.Transform`, `Paint.PaintListAdapter`, `android.memes.FrameAdapter`, `android.taptargetview.TapTargetView`). Chevauchement réel et significatif avec l'infrastructure déjà portée (`AnimationObjectData.swift`, `LayerRenderer.swift`, `PaintCapture.swift`, `FrameListState.swift`), mais nécessite une lecture complète et méthodique du reste du fichier (~850 lignes non lues : `onClick`, gestion undo, sauvegarde) avant portage — différé à une passe dédiée plutôt que rushé, pour ne pas répéter l'erreur évitée au module 8 (facturation prématurée d'une architecture sans avoir lu les vues consommatrices). |
| Éditeur photo | `android/memes/ImageViewCanvas.java` (2037 lignes, PAS lu — seuls les imports vérifiés) | — | PAS LU, PAS PORTÉ (décision) | Canevas de rendu de l'éditeur photo simple, catégorie G du rapport (reclassée depuis A — confirmé n'être importé QUE par `ImageEditorCompound.java`, jamais par `AnimemesCompound`/`MemesView2`). Imports vérifiés (`AnimationComposer`/`AnimationObjectData`/`Transform`/`TextRect`/`BezierEditorView` — les 4 premiers déjà portés au module 8) confirmant qu'il s'agit structurellement d'un cousin à FRAME UNIQUE de `MemesView2.java` (pas de timeline/keyframes/lecture, juste des calques statiques superposés sur une photo) — gère aussi `AnimationObjectData.Type.PATH` (dessin libre), ce qui rouvre potentiellement la question du rendu PATH/LINE différé au module 8 (`AnimemesGestureController.swift` existe maintenant, contrairement à l'époque de cette décision). Lecture complète différée à la même passe dédiée que `ImageEditorCompound.java` ci-dessus — les deux fichiers se pilotent mutuellement, les porter séparément serait artificiel. |
| Éditeur photo | `app/src/main/java/com/tiinver/editor/media/MediaEditor.java` (lu en entier, 210 lignes — hors `engine/`, dans le module `app`) | — | LU, PAS PORTÉ (décision) | Fragment Android mince : délègue la quasi-totalité du travail à `ImageEditorCompound` (sticker emoji, fermeture, callback de résultat via `Bundle`/`FileReadyToUseListener`). Point d'entrée réel confirmé de `MediaEditor` : `CameraActivity` (module 7, déjà câblé avec des closures TODO pour ce cas) et 3 autres appelants (`ChatFragmentTest`, `AddPerfilFoto`, `CertificationRequestActivity` — modules 11/17, pas encore atteints). Portage d'un écran SwiftUI équivalent différé jusqu'à ce que `ImageEditorCompound`/`ImageViewCanvas` soient portés (ligne précédente). |
| Trim / Timeline / Waveform | `editor/view/ProTimelineView.java` (763 lignes, lu en entier) | `Media/ProTimelineViewModel.swift` | ÉCRIT (NON COMPILÉ) | **Logique pure séparée du rendu**, même principe que `TimelineViewModel.swift` (module 8) : deux espaces indépendants reproduits à l'identique (espace écran en pixels pour la fenêtre de sélection/playhead, espace temps en millisecondes pour la bande de vignettes qui défile) — conversions `msToX`/`pxToMs`/`msUnderPx`, `recalcWindow`/`initSelectionPx`/`clampSelectionPx`/`syncTimestamps`, `updatePlayhead` (avec bouclage de sélection), gestion tactile complète (`pickMode`/`touchDown`/`touchMove`/`touchUp`, 4 modes : `dragLeft`/`dragRight`/`dragRegion`/`scroll`). PAS porté, délibérément : `onDraw`/`drawFrames`/`drawWaveform`/`drawHandle`/`drawPlayhead`/`drawTicks`/`drawTimecodes`/`drawProgressBar` (deviendront un `Canvas` SwiftUI). |
| Trim / Timeline / Waveform | `view/trimmer/VideoTrimmerView.java` (1138 lignes, lu PARTIELLEMENT — imports, champs, constructeurs, `setBtnCropRatioVisibility`, ~140 lignes sur 1138) | `Media/VideoTrimState.swift` | LU PARTIELLEMENT, ÉTAT SEUL PORTÉ | État de rotation cyclique (0→90→180→270→0)/flip horizontal/ratio de recadrage — logique triviale mais réelle. **Reste du fichier (~1000 lignes) PAS lu** : câblage `ExoPlayer`, extraction de vignettes, export — voir décision d'architecture ci-dessous. |
| Trim / Timeline / Waveform | `editor/MediaTrim.java` (374 lignes, lu en entier) | — | LU, PAS PORTÉ (décision) | Fragment Android mince, délègue à `VideoTrimmerView` (comme `MediaEditor`→`ImageEditorCompound` au module 9) — même famille de point d'entrée. **Code mort confirmé dans le fichier lui-même** : tout le bloc `startTrim`/`rangeBarView`/`VideoTimelineViewDeprecate` est explicitement commenté (`/* ... */`) dans le source actif — `next.setOnClickListener` et la logique de déclenchement de trim manuel ne s'exécutent jamais, le flux réel passe entièrement par `VideoTrimmerView.Callback`. Portage d'un écran SwiftUI équivalent différé (dépend de `VideoTrimmerView`/l'export AVFoundation, pas encore écrits). |
| Trim / Timeline / Waveform | `Utils/media/VideoTransformer(2)`, `SmartTrimmer`, `FastTrimmer`, `SimpleTrimmer`, `view/trimmer/v2/**` (`PassthroughTrimmer`, `VideoTrimmerViewV2`, `TrimSessionPreparer`, `ProTimelineViewV2`) | — | CONFIRMÉ MORT (décision) | **Confirmé par `TIINVER_IOS_PORT_ANALYSIS.md` §2.2, pas re-vérifié indépendamment mais la preuve citée est vérifiable** : ce cluster "v2", supposé initialement être le système "moderne" actif, n'est en réalité consommé que par `TrimBenchActivity` (debug), lui-même NON déclaré dans `AndroidManifest.xml` — inatteignable en prod. Message de commit `c5c2c3d` : "WIP: passthrough trimmer + tuning VideoTransformer (non branché prod)". Le vrai trimmer actif est l'ancien `VideoTrimmerView`/`MediaTrim`, déjà traité aux lignes précédentes. |
| Trim / Timeline / Waveform | `view/seekbar/WaveformSeekBar.java` (739 lignes) | — | RECLASSÉ (découverte), PAS LU EN DÉTAIL | **Cité comme risque élevé du module 10 par le rapport de faisabilité, mais confirmé par grep appartenir au module 11 (Messagerie)** : ses seuls consommateurs sont `messagerie/layout/BubbleMessageAudioCompound.java` et `messagerie/ui/viewholders/MessageAudioViewHolder.java` (bulles de messages vocaux dans le chat), zéro référence depuis `VideoTrimmerView.java`/`MediaTrim.java`/`ProTimelineView.java`. Ne rend d'ailleurs QUE un `int[]`/`Waveform` déjà calculé (pas d'extraction PCM) — signature probable d'une bibliothèque tierce vendorisée (style "massoudss/waveformSeekBar"), à revérifier au moment du module 11. `ProTimelineView.setWaveform(float[])` existe mais AUCUN appelant trouvé dans `VideoTrimmerView.java`/`MediaTrim.java` — possiblement un chemin non branché côté trim vidéo, signalé sans investigation supplémentaire, faute de temps. |
| Trim / Timeline / Waveform | `Utils/media/VideoFrameExtractorCodecAsync.java` (355 lignes), `android/views/CropOverlayView.java` (398 lignes, package `views` — distinct de `android/croper/CropOverlayView.java`) | — | PAS LU, DÉCISION D'ARCHITECTURE | Extraction de vignettes → équivalent natif direct `AVAssetImageGenerator`, pas de portage ligne à ligne justifié (même raisonnement que les décodeurs MediaCodec des modules 7/8). Recadrage vidéo pendant le trim (rectangle de recadrage avec ratio contraint, DISTINCT de `TOCropViewController` qui ne gère que des IMAGES statiques) — non lu, nécessitera son propre petit modèle de géométrie (probablement proche de `CropWindowHandler` déjà remplacé côté photo) au moment de l'export AVFoundation. |
| Messagerie / Chat UI | `view/seekbar/WaveformSeekBar.java` (739 lignes, lu ~250/739 — constructeurs, `calculateWaveDimensions`, `calculateDiscretePosition`, `blendWaveforms`, `calculateWaveCornerRadius`) | `Media/WaveformSeekBar.swift` | ÉCRIT (NON COMPILÉ) — PARTIEL | Bibliothèque tierce vendorisée confirmée (recherche : structure identique à `massoudss/waveformSeekBar`, package Maven `com.github.massoudss`) — portée directement (algorithme compact, ~150 lignes utiles) plutôt que remplacée par une dépendance SPM, contrairement à `TOCropViewController`. Algorithme de disposition des barres (largeur/espacement, gestion du bord distinct de l'inter-barre) et `calculateDiscretePosition`/`blendWaveforms` portés fidèlement. **PAS lu/porté** : `onDraw` réel (couleurs/anim exactes — reconstruit par déduction raisonnable, pas vérifié pixel-exact), `WaveCornerType.EXACTLY` (simplifié), le minuteur d'animation `ANIM_DURATION=200ms` (laissé à `.animation(_:value:)` SwiftUI plutôt que reproduit manuellement). L'extraction PCM réelle (comment le `int[] waves` initial est calculé) n'est PAS dans ce fichier — reste à trouver en lisant `BubbleMessageAudioCompound.java`, pas fait cette passe. |
| Messagerie / Chat UI | `messagerie/repository/ChatRepository.java` (classe interne `ROOM`, lignes 107-144) | `Realtime/SocketEvent.swift` | CORRECTIF — bug réel corrigé | **Bug trouvé et corrigé (2026-08-11)** : la version du module 1 utilisait les noms des CONSTANTES Java (`"CALL"`, `"NEW_MESSAGE"`…, tirés du résumé du rapport de faisabilité) au lieu des vraies valeurs de chaîne émises sur le socket (`"call"`, `"new message"`, `"delivred"` — faute d'orthographe RÉELLE côté Android, préservée à l'identique). Avec les anciennes valeurs, AUCUN événement chat/appel n'aurait jamais été reconnu par le serveur — bug silencieux (compile, ne fonctionne jamais). ~35 constantes recopiées directement depuis `ROOM`. |
| Messagerie / Chat UI | `messagerie/ChatType.java` | `Models/ChatType.swift` | ÉCRIT (NON COMPILÉ) | `enum { group, chat }` + `wireValue` ("chatgroup"/"chat"). |
| Messagerie / Chat UI | `messagerie/ui/ConversationIdGenerator.java` (34 lignes, lu en entier) | `Models/ConversationIdGenerator.swift` | ÉCRIT (NON COMPILÉ) | Id de conversation déterministe : tri alphabétique des participants + jointure `_`, pour que les deux parties calculent le même id sans dépendre de qui est `from`/`to`. Variante groupe à 3 clés (`currentUser`/`remoteUser`/`"chatgroup"`) vérifiée triée aussi — confirmé contre la vraie signature `generateGroupConversationId(String,String,String)`. |
| Messagerie / Chat UI | `models/chat/MessageLib.java` (929 lignes, champs lus en entier) | `Models/MessageLib.swift` | ÉCRIT (NON COMPILÉ) | Portée réduite délibérément : ~25 champs UI-only RecyclerView (`isSelectedItem`/`viewType`/`title`/`subTitle`…) exclus, confirmés jamais lus du JSON ni écrits en base. ~48 champs retenus par TRIPLE recoupement (patrons `MessagePacket`, `ContentValues` de `ChatManager`, schéma Core Data `MessageEntity`) — dont `lucrative`/`price`/`belongsToCurrentUser`, ajoutés après coup en lisant `RosterManager.java` (absents des deux autres sources, présents uniquement dans le mapping roster). |
| Messagerie / Chat UI | `models/chat/MessagePacket.java` (1016 lignes, lu en entier) | `Models/MessagePacket.swift` | ÉCRIT (NON COMPILÉ) | **Découverte de protocole majeure** : l'enveloppe réellement émise (`getPacketJson`) contient un champ `"packet"` dont la valeur est elle-même un DOCUMENT JSON sous forme de STRING (double encodage), construit côté Android par 20 méthodes `get*Pattern()` quasi identiques selon `(chat\|groupe) × (texte\|graphique\|audio\|vidéo\|photo/gif/sticker) × (cité ou non)` — consolidées ici en une seule fonction paramétrée (`buildPacketString`), vérifiée champ par champ contre les 20 originales. **`image_byte` : bug de guillemets évité** — la concaténation Android insère `Arrays.toString(image_byte)` SANS guillemets autour (littéral JSON tableau/`null`, pas une chaîne) ; reproduit via `[Int]`/`NSNull` dans le dictionnaire plutôt qu'une `String`, pour que `JSONSerialization` produise le même littéral. Document interne construit via `JSONSerialization` (échappement JSON correct) plutôt que par concaténation naïve comme l'original (qui casserait sur un `"` dans le message) — amélioration documentée, protocole toujours interopérable (le `"packet"` est relayé de façon opaque par le serveur). Quatre initialiseurs de construction ajoutés, vérifiés champ par champ contre leurs 4 méthodes Android respectives (`ChatManager.sendPrivateMessage`/`sendGroupMessage`/`deletePrivateMessage`/`deleteGroupMessage`) — **asymétries réelles reproduites, pas unifiées** : `sender` = `mlib.sender` pour l'envoi privé mais = `myId` courant pour la suppression privée ; `profile` = `mlib.profile` pour l'envoi groupe mais = `Settings.PROFILE` courant pour la suppression groupe ; `giftId`/`thumbnailUrl` absents des variantes suppression. |
| Messagerie / Chat UI | `engine/model/Profile.java` (213 lignes, lu en entier) | `Models/ChatProfile.swift` | ÉCRIT (NON COMPILÉ) | Nommé `ChatProfile` (pas `Profile`) pour ne pas entrer en collision avec un futur concept "profil utilisateur" du module 17 — DTO de signalisation d'appel/PBS, pas un profil complet. |
| Messagerie / Chat UI | `messagerie/model/ChatModel.java`+`PresenceModel.java`+`TypingModel.java`+`MessageStatusModel.java` (87+22+22+31 lignes) + `models/chat/call/CallModel.java` (44 lignes), tous lus en entier | `Models/ChatEvent.swift` | ÉCRIT (NON COMPILÉ) | Consolidés en 2 `enum` Swift à valeurs associées (`ChatEvent`/`CallEvent`) plutôt qu'un type "tag entier + N champs nullable" — rend les combinaisons invalides irreprésentables, contrairement à l'original. |
| Messagerie / Chat UI | `roster/RosterManager.java` (234 lignes, lu en entier) | `Storage/RosterRepository.swift` (étendu) | ÉCRIT (NON COMPILÉ) | `updateRoster(MessageLib/Profile, isFromServer)`, `updateRosterWithLastMessageAfterDeletion`. **Asymétrie Android reproduite** : `lucrative`/`price` écrits UNIQUEMENT sur la branche UPDATE de `ContentValues` (absents de la branche INSERT, vérifié ligne par ligne) — une nouvelle conversation garde donc la valeur par défaut (0). `RosterManager.create(Context,Cursor,String)` PAS porté : son seul effet utile (`updateRoster`) est en commentaire dans le source Android lui-même (code mort confirmé, zéro appelant ailleurs dans le projet). |
| Messagerie / Chat UI | `messagerie/ui/ChatManager.java` (1508 lignes, lu en quasi-totalité — sections call/PBS `lunchcall`/`showIncomingCallNotification`/`addPbsNotification*` différées au module 12/13) | `Storage/MessageRepository.swift` | ÉCRIT (NON COMPILÉ) | Couche persistance `wk_messages` (`MessageEntity`). **Découverte majeure** : `GroupMessageEntity`/`wk_gp_messages` (module 2) est une table MORTE — confirmé par grep exhaustif sur tout `com.tiinver`, `Dbase.java` la crée et `StubProvider` sait la manipuler mais AUCUNE constante d'URI ni appelant n'écrit jamais dedans ; `addGroupMessage` (ligne 1190, lu en entier) écrit en réalité dans `infoContract.MSG_URI`, LA MÊME table `wk_messages` que les messages privés (différenciés par `type`) — `addGroupMessage` ci-contre cible donc `MessageEntity`, pas `GroupMessageEntity`. **Bug Android confirmé par analyse de flot de contrôle, délibérément PAS reproduit comme "atteignable"** : dans `addMessage` (ligne 1089), la branche `else if (!isMessageExist(messageId) && verb.equals("deletemessage"))` (lignes 1160-1170) est du CODE MORT — atteinte uniquement quand `isMessageExist==true` (négation du premier `if`), la sous-condition `!isMessageExist(...)` y vaut donc toujours faux. La suppression réelle transite par un chemin séparé (listeners socket `ON_DELETE_*_MESSAGE`, déjà câblés dans `ChatRepository.swift`). `thumbnailUri` (colonne) sourcée différemment selon l'appelant, vérifié champ par champ : `message.thumbnailUri` pour `insertFileMessage`, `message.thumbnailUrl` (wire `thumbnail_url`) pour `addMessage`/`addGroupMessage` — PAS unifié. `insertTextMessageFromServer` porté séparément (`object`/`verb` figés à `"text"`/`"post"` côté Android, `username` sourcé de `from` pas `username` — vraie divergence avec `insertTextMessage`). Branches `verb=="deleteMember"/"addMember"` d'`addGroupMessage` (gestion de membres de groupe) et notification push locale (branche `verb=="post"`) délibérément PAS portées — hors périmètre persistance, modules Groupes/Notifications. |
| Messagerie / Chat UI | `messagerie/repository/ChatRepository.java` (1124 lignes, lu en entier) | `Realtime/ChatRepository.swift` | ÉCRIT (NON COMPILÉ) | Hub de routage socket central, singleton `@MainActor` (2 `PassthroughSubject` remplaçant les 4 `MutableLiveData` Android, dont 2 confirmées toujours identiques donc fusionnées). **2 bugs trouvés et corrigés dans CE portage (pas dans l'original)** : (1) `updateGroupMessage` émettait `packetForGroupJSON()` alors que le vrai `ChatRepository.updateGroupMessage` (ligne 959) émet `getPacketJson()` — l'enveloppe CHAT PRIVÉ, PAS l'enveloppe groupe, contrairement à `sendGroupMessage`/`sendScheduledGroupMessage` (eux corrects) — incohérence réelle du côté Android, reproduite telle quelle après correction (pas "corrigée" côté protocole, juste alignée sur ce que le vrai code émet) ; (2) `deletePrivateMessage` émettait sur `SocketEvent.deletePrivateMessage` ("delete private message") au lieu de `SocketEvent.onDeletePrivateMessage` ("on delete private message", la vraie constante `ROOM.ON_DELETE_PRIVATE_MESSAGE` utilisée ligne 962). **Listener manquant ajouté** : `offlineStatus` ("offline status") a un DOUBLE rôle côté Android — émis par le client à la connexion (déjà porté) ET écouté pour un lot de statuts de livraison accumulés hors-ligne (`ChatManager.updateMessageStatus`, absent d'une première version de ce fichier). `deleteMessage(messageId:data:chatType:)` ajouté (2ᵉ chemin de suppression Android, distinct de `deletePrivateMessage` : émet `data` brut pour un chat privé, sinon appelle `onDeleteMessage` — requête REST `GET deletemessage/{id}` via `APIClient.shared.get`, PAS un événement socket). `handleNewMessage` groupe maintenant câblé sur `MessageRepository.addGroupMessage` (l'ancienne lacune documentée sur `wk_gp_messages` n'existe plus, voir ligne `ChatManager.java` ci-dessus). |
| Messagerie / Chat UI | `messagerie/ui/adapter/MessageListAdapter.java` (1353 lignes, lu en entier) + 9 `ViewHolder` (`TextViewHolder`/`MessageAudioViewHolder`/`MessagePhotoViewHolder`/`MessageVideoViewHolder`/`MessageStickerViewHolder`/`MessageGifViewHolder`/`MessageGiftViewHolder`/`GraphicMessageViewHolder`/`MissedViewHolder`, 152+228+175+177+177+181+97+152+40 lignes, tous lus en entier) + `models/chat/MessageType.java`/interfaces `MessageActionListener`/`QuoteClickListener`/`MessageViewItemClikedListener`/`LoadMoreDataListener`/`layout/ResultData.java` | `Messagerie/ChatBubbleViews.swift`, `Messagerie/ChatListItem.swift`, `Messagerie/ChatDateFormatting.swift`, `Models/GiftCatalog.swift`, `Models/RosterModel.swift` | ÉCRIT (NON COMPILÉ) | Android distingue CHAQUE type de message en 2 `viewType` RecyclerView (pair/impair) uniquement pour le pattern ViewHolder/recyclage — la seule vraie différence est `isBelongsToCurrentUser` (alignement + effets de bord upload/download) : consolidé en UNE vue SwiftUI par type d'objet, pas de doublement. **Découverte vérifiée** : la forme d'onde des bulles audio (`MessageAudioViewHolder.createWaveform()`) est un tableau ALÉATOIRE (`new Random()`), PAS une extraction PCM réelle — reproduit fidèlement (`AudioBubbleBody.randomWaveform()`), pas "amélioré" en vraie analyse audio. `MessagePhotoViewHolder`/`MessageGifViewHolder`/`MessageStickerViewHolder` confirmées byte-pour-byte IDENTIQUES côté Android (seule la fonction de chargement `glid`/`glidGif` diffère) — consolidées en une seule `MediaImageBubbleBody`. `GiftBadgeView`/`GiftCatalogHelper` (catalogue emoji/prix/nom, 12 cadeaux) portés intégralement et vérifiés. `GraphicMessageViewHolder` (rendu de chemin dessiné `EditorData`) volontairement PAS rendu — appartient au module 14 "Message Graphic" (payload `mgGraphic` déjà identifié comme JSON pré-sérialisé non décodé, module 11 protocole) — placeholder honnête. `Subscribe`/`RenewSubscription` (bandeau paiement groupe) modélisés en `ChatListItem` mais jamais peuplés (dépend du module 15 Wallet, `checksubscription`/`group/subscribe` non appelés). `TiinverAI` (bulle chat IA Gemini, VIT dans ce même adaptateur côté Android) PAS porté — écran séparé `TiinverGeminiAIChat.java`, hors périmètre chat classique. `getInformation`/`getInformation126` (2 formats de texte système selon `versionCode <> 126`) consolidés au seul format moderne (champs structurés), l'ancien format à base de regex sur des messages historiques rares non reproduit. |
| Messagerie / Chat UI | `messagerie/ui/ChatFragmentTest.java` (3080 lignes, lu en entier) | `Messagerie/ChatViewModel.swift`, `Messagerie/ChatView.swift`, `Storage/MessageRepository.swift` (`page`, ajouté) | ÉCRIT (NON COMPILÉ) | Chrome Android non pertinent PAS porté (mode immersif système, `CursorLoader`/`ItemTouchHelper`/`ServiceConnection`/`DownloadManager` — remplacés par `List` SwiftUI + `async`/`URLSession`). Logique métier réelle portée : pagination (`CursorLoader` `conversationId=? ORDER BY stamp DESC LIMIT 100 OFFSET n` → `MessageRepository.page`, `CoreDataRepository.query` étendu avec `offset`), routage temps réel (observer `chatViewModel.getIncomingMessage()` → `ChatRepository.chatEvents`, déjà câblé module 11 protocole), envoi (`sendMessageText`/`sendMessageGift`/`prepareFileMessage`/`prepareGifMessage`, écho optimiste + persistance locale + émission différée à l'affichage réel de la bulle), cycle upload/download/accusé de lecture déclenché À L'AFFICHAGE (pas au clic, fidèle à `onBindViewHolder`), citation (`showQuotedMessage`), sélection/suppression (`deleteMessageForme`/`deleteMessageForEveryOne`/`removeMessageAndUpdateSeparators`, ce dernier AMÉLIORÉ — voir `ChatListItem.swift`). **Frappe sortante reconstruite plutôt que reproduite** : le corps réel de `onTyping(boolean)` qui émettrait sur le socket est ENTIÈREMENT COMMENTÉ dans le source Android lu (lignes 830-836) — seul le ré-armement de `Handler` est actif, sans émission associée ; une émission fonctionnelle a été écrite via `ChatRepository.emitTyping`/`emitStopTyping` (vérifiés module 11 protocole) plutôt qu'un no-op fidèle. **PAS porté, gaps documentés (pas devinés)** : transfert réel upload/download (`UploadFileOrDataService.java`/`DownloadReceiver.java` PAS lus cette passe — endpoint/format multipart inconnus, `requestUpload`/`requestDownload` sont des points d'ancrage vides) ; zoom plein écran média (`ImageExpanderAnim` pas lu) ; sélecteurs GIF/cadeau réels (`StickerPickerDialog.java`/`GiftGalleryView.java` pas lus, `GiftPickerPlaceholder` minimal câblé sur le catalogue déjà vérifié) ; enregistrement audio (CONFIRMÉ code mort côté Android lui-même — tout le `touchListener` d'enregistrement est commenté dans le source) ; écran de liste des conversations (`RosterModel` fourni en entrée, fichier source séparé PAS lu, hors périmètre explicite de cette passe) ; sons d'envoi/réception (`AppSounds`, pas branché). |
| Appels WebRTC/CallKit | `messagerie/webrtc/RTConnection2.java` (801 lignes, lu en entier) | `Calls/WebRTCConnection.swift`, `Models/WebrtcData.swift`, `Models/TurnCredentials.swift` | ÉCRIT (NON COMPILÉ) | Moteur WebRTC AUDIO SEUL (aucune trace de `VideoTrack`/`VideoCapturer`, `isVideoEnabled` toujours `false` chez les deux appelants réels — confirmé, pas une réduction de portée de ce portage). **`RTConnection.java`/`RTConnection3.java` (775/790 lignes) CONFIRMÉS MORTS** par grep exhaustif (même méthode que le cluster "v2" du module 10) — seul `RTConnection2` est instancié hors de son propre fichier. Bibliothèque `stasel/WebRTC` (SPM, déjà déclarée dans `project.yml` depuis un module antérieur) vérifiée avant usage : API Swift confirmée par lecture directe du dépôt de démo officiel `stasel/WebRTC-iOS` (`WebRTCClient.swift`) ET des headers Objective-C réels (`RTCConfiguration.h`/`RTCPeerConnection.h`/`RTCPeerConnectionFactory.h`/`RTCAudioSession.h`) — **1 divergence trouvée et corrigée pendant l'écriture** : `addIceCandidate:` n'a PAS de variante à bloc de complétion contrairement à `offer`/`answer`/`setLocalDescription`/`setRemoteDescription` (une première ébauche en supposait une, corrigée après vérification du header). Asymétrie négociateur/poli de `CallService.configForOutgoingCall`/`configForIncomingCall` préservée à l'identique (l'appelant N'EST PAS l'initiateur de l'offre — contre-intuitif, vérifié). `preferCodec`/`movePayloadTypesToFront`/`findMediaDescriptionLine` (manipulation SDP texte pure, préférence codec Opus) portés fidèlement, indépendants de l'API WebRTC. |
| Appels WebRTC/CallKit | `messagerie/repository/ChatRepository.java` (signalisation d'appel, lignes 974-988 + `calling`/`notifyMissedCall`/`buildCallMessageLib`, lues au module 11 mais câblées ici) | `Realtime/ChatRepository.swift` (étendu) | ÉCRIT (NON COMPILÉ) | `onCall`/`onCallBusy`/`onRinging`/`onCallEnd`/`accepCall`/`emitWebrtcMessage` (motif commun : suffixe `PrivateAction` pour un chat 1:1, aucun pour un groupe, vérifié identique sur les 5 — SAUF `onCallBusy`, toujours suffixé, pas de variante groupe côté Android). `calling`/`notifyMissedCall` envoient un message `"voicecall"`/`"missedvoicecall"` normal via le canal de chat existant (PAS un événement dédié) — **asymétrie réelle vérifiée** : `calling` utilise `sendMessage`/`sendGroupMessage`, `notifyMissedCall` utilise `updateMessage`/`updateGroupMessage` (pas les mêmes méthodes). **Découverte** : `ChatRepository.onCall`/`CallViewModel.onCall` (émission `ROOM.CALL`) confirmés JAMAIS appelés par le client Android réel (grep exhaustif de `CallService.java`) — code mort côté Android lui-même, écouteur de réception conservé par fidélité (module 11) mais l'émission n'est déclenchée nulle part dans ce portage non plus, cohérent. Le déclenchement réel d'un appel entrant EN PREMIÈRE LIGNE (`lunchcall`, appelé directement, PAS via événement) a été corrigé dans `ChatRepository.handleNewMessage` (module 11, `object=="voicecall"`) : la branche `!isOnCall` appelle maintenant `CallCoordinator.shared.handleIncomingCall` directement au lieu de publier un `.onCall` générique — une première ébauche (avant que ce module existe) traitait les deux branches identiquement, corrigé une fois `CallCoordinator` disponible. |
| Appels WebRTC/CallKit | AUCUN équivalent Android — développement NOUVEAU | `Calls/CallKitManager.swift` | ÉCRIT (NON COMPILÉ) | `CXProvider`/`CXProviderConfiguration`/`CXCallController`/`CXCallUpdate`/`CXHandle`/`CXStartCallAction`/`CXAnswerCallAction`/`CXEndCallAction`/`CXSetMutedCallAction`/`CXCallEndedReason` — API vérifiée via `developer.apple.com/documentation/callkit` (fetch direct, a fonctionné pour `CXProvider`) et recoupée avec les bindings Xamarin officiels (`xamarin/apple-api-docs`, mêmes signatures en C#, utilisés quand la page Apple ne rendait pas son contenu JS). `CXProviderConfiguration(localizedName:)` signalé DÉPRÉCIÉ depuis iOS 14 dans la documentation croisée mais reste l'initialiseur RÉELLEMENT documenté et utilisé dans toutes les sources consultées (dont le guide d'intégration VideoSDK et le binding Xamarin, qui n'en proposent pas d'autre) — utilisé tel quel, à revoir sur un vrai Xcode si un avertissement apparaît (aucun accès macOS pour vérifier). CallKit remplace la majeure partie de la "plomberie" Android de `CallActivity`/`IncomingCallActivity` (capteur de proximité, wake lock, notification à actions `IncomingCall`/`CallLauncherService`) — gérée nativement par le système, non reproduite. |
| Appels WebRTC/CallKit | AUCUN équivalent Android — développement NOUVEAU, contrainte Apple stricte | `Calls/VoIPPushManager.swift`, `Calls/VoIPTokenRegistrar.swift` | ÉCRIT (NON COMPILÉ) | `PKPushRegistry`/`PKPushRegistryDelegate` — API vérifiée via les bindings Xamarin officiels (`PKPushRegistry.xml`/`IPKPushRegistryDelegate.xml`/`PKPushType.xml`, confirmant `.voIP`), recoupée par recherche croisée sur l'exigence Apple ("must call provider.reportNewIncomingCall … synchronously", "mere seconds to respond", désactivation du jeton par le système en cas de non-conformité répétée). Nécessaire car Android laisse FCM réveiller le processus normalement pour tout type de notification (pas de mécanisme "appel" séparé) — **iOS interdit structurellement cette approche** pour un appel entrant app tuée. **2026-08-12 : enregistrement du jeton câblé** (`VoIPTokenRegistrar.register`, `POST user/voip-token`, jeton hex-encodé) — endpoint DÉDIÉ choisi plutôt que de réutiliser le motif générique `user`/`column` déjà utilisé par le jeton FCM (`PushTokenRegistrar.swift`), sur demande explicite ; **implémentation SERVEUR PAS faite** (backend PHP séparé) — spécification complète (chemin, payload, prérequis APNs VoIP/topic `.voip`) dans la nouvelle section "Backend à implémenter — PushKit/VoIP". **Bug de séquencement trouvé et corrigé** : une première version attendait la préparation WebRTC complète (`fetchTurnAndStart`, appel réseau TURN) avant d'appeler `completion()` dans `didReceiveIncomingPushWith` — retardait inutilement le rappel PushKit au-delà de ce qu'exige Apple ; corrigé via le paramètre `onReported` de `CallCoordinator.handleIncomingCall`, appelé dès que `CXProvider.reportNewIncomingCall` a rendu la main. |
| Appels WebRTC/CallKit | `messagerie/service/CallService.java` (835 lignes, lu en entier) + `messagerie/ui/call/CallViewModel.java` (110, entier) + `messagerie/ui/call/CallActivity.java` (592, entier) + `messagerie/ui/call/IncomingCallActivity.java` (534, entier) | `Calls/CallCoordinator.swift`, `Calls/CallView.swift` | ÉCRIT (NON COMPILÉ) | UN SEUL coordinateur `@MainActor` remplace Service+ViewModel Android (la séparation Android répondait à un besoin de cycle de vie propre à Android — Service survivant à l'Activity — sans équivalent iOS direct). Flux couverts : appel sortant (`startOutgoingCall`→`CXStartCallAction`→`performStartCall`→TURN+WebRTC+`calling()`), appel entrant socket (`handleIncomingCall`, déclenché directement par `ChatRepository`), appel entrant app tuée (`VoIPPushManagerDelegate`→même méthode), acceptation (`performAnswerCall`→`accepCall`), fin d'appel locale/distante (`performEndCall`/`endCallFromRemote`, avec détection d'appel manqué fidèle à `CallActivity.isCalleMissedCall`), relais de signalisation WebRTC (`WebRTCConnectionDelegate`↔`emitWebrtcMessage`/`onMessage`), activation audio (`didActivate`/`didDeactivate`→`RTCAudioSession`). `CallView.swift` couvre l'écran POST-décroché uniquement (minuteur/muet/haut-parleur/raccrocher) — l'écran de sonnerie/réponse lui-même est l'écran système CallKit natif, aucune vue SwiftUI équivalente à `activity_receive_call.xml` n'est nécessaire. **PAS porté, gaps honnêtement documentés** : capteur de proximité/wake lock (remplacés par la gestion native CallKit, pas une omission) ; boucle de re-notification `outgoingCallRepeatRunnable` (ping `/push` toutes les 5s tant que `!isRinging`, redondant avec PushKit côté iOS — pas branché) ; `RTConnection.java`/`RTConnection3.java`/`CallService2.java` confirmés morts, pas lus. `CallView` EST présentée en `.fullScreenCover` depuis `ChatView.swift` (module 11) dès que `CallCoordinator.state != .idle`, avec un bouton d'appel dans la barre d'outils construisant un `ChatProfile` minimal depuis `RosterModel` (champs alignés sur ceux que `lunchcall` utilise réellement — `messageId`/`username`/`nikname`/`chatType` — le vrai point d'entrée bouton d'appel Android n'a PAS été localisé dans les 3080 lignes lues de `ChatFragmentTest.java`, probablement dans un layout XML non fourni, reconstruit plutôt que deviné à l'identique). |
| Appels WebRTC/CallKit | `messagerie/webrtc/RTConnection2.java` (canal de données, `RTCDataChannel`) | `Calls/WebRTCConnection.swift` (corrigé) | CORRECTIF — bug réel corrigé | **Bug trouvé et corrigé (2026-08-12, en préparation du module 13)** : `start(withDataChannel:)` créait le `RTCDataChannel` local mais n'assignait JAMAIS `.delegate`, et `peerConnection(_:didOpen:)` (canal ouvert par le pair distant) ne stockait ni ne déléguait non plus — AUCUN message reçu sur le canal de données n'aurait jamais déclenché de callback, dans un sens comme dans l'autre. Dormant tant que seuls les appels (module 12, qui n'envoient rien sur ce canal) l'utilisaient ; bloquant pour le Shareboard, qui EN A besoin dans les deux sens. Vérifié contre le vrai `WebRTCClient.swift` de référence (`stasel/WebRTC-iOS`, méthode `createDataChannel()`/`peerConnection(_:didOpen:)`) avant correction — signatures `RTCDataChannelDelegate` (`dataChannelDidChangeState`/`dataChannel(_:didReceiveMessageWith:)`) confirmées par la même source, PAS devinées. Nouvelle méthode `WebRTCConnectionDelegate.webRTCConnection(_:didReceiveData:)` (implémentation par défaut vide via extension de protocole, pour ne rien casser côté `CallCoordinator`). |
| Shareboard (module 13) / Message Graphic (module 14) | `com.animems.engine.android.codec.graphic.GraphicMessageCodec.java` (266, entier) + `CompactTouchEvent.java`/`CompactEditorData.java` (formats fil) | `Shareboard/GraphicMessageCodec.swift`, `Shareboard/PBSWireModels.swift` | ÉCRIT (NON COMPILÉ) | Codec de compression PARTAGÉ par les deux modules (confirmé : `FragmentPbs`/`FragmentMessageGraphic` l'utilisent tous les deux). Noms de clés JSON reproduits À L'IDENTIQUE (`id`/`a`/`n`/`x0`/`y0`/`x1`/`y1`/`s`/`c`/`t`/`sw`/`sh` pour le tactile, `id`/`tp`/`ac`/`tc`/`cc`/`tx`/`tw`/`th`/`l`/`t`/`px`/`py`/`bw`/`bh`/`bb` pour l'éditeur) — un pair Android encore en circulation doit pouvoir désérialiser ce que ce client émet. `bb` (bitmap) encodé en Base64 (comportement par défaut de Gson pour `byte[]`, pas une supposition). Format "legacy" `MotionEventData[]` d'Android (compatibilité descendante avec d'anciens messages) délibérément PAS repris — aucune donnée existante sous cette forme ne peut exister côté iOS, ce client ne l'a jamais émise. |
| Shareboard (module 13) / Message Graphic (module 14) | `com.animems.engine.android.pbs.PBSView.java` (1411 lignes, entier) + `com.animems.engine.model.pbs.EditorData.java`/`MotionEventData.java` (599+110) + `com.animems.engine.android.memes.Page.java` (27) | `Shareboard/PBSCanvasEngine.swift`, `Shareboard/PBSWireModels.swift` | ÉCRIT (NON COMPILÉ) | **Découverte majeure corrigeant la piste initiale** : `PBSCompound.java` (899 lignes) N'EST PAS le moteur de rendu comme supposé après une première lecture partielle — c'est la barre d'outils/le contrôleur (`FrameLayout`+`onClick`), qui délègue tout le dessin/tactile RÉEL à `PBSView` (`onDraw`/`onTouch`, 1411 lignes, jamais comptée dans l'estimation initiale de portée). Moteur d'état SwiftUI DÉCOUPLÉ de son rendu (contrairement à l'original qui mélange état+`onDraw`+`onTouch` dans une seule `View`), PARTAGÉ à l'identique par le Shareboard temps réel ET Message Graphic (lecture seule) — confirmé, pas une simplification arbitraire : les deux Fragment Android instancient littéralement `PBSCompound`/`PBSView`. `EditorData`/`MotionEventData` consolidés en DEUX structs Swift (`PBSEditorData` réutilisé pour objets placés ET traits de dessin, exactement comme Android réutilise `EditorData` pour `page.page`/`page.paintList`) — ~15 champs de rendu/animation avancés Android (`cachedText`/`seekMatrix`/`initialSkewX`/`midPointX`/`degre`…) NON repris, vérifiés un par un comme jamais lus par le codec ni la boucle de rendu normale, remplacés par les gestes natifs SwiftUI. **Portée réduite documentée** : le pinch/rotate/drag d'un objet placé n'est PAS resynchronisé EN DIRECT pendant le geste (republié en entier une fois terminé, via le canal `onSendPBStreamData` existant) — Android le fait via le même canal que le dessin avec un unique `Path` partagé (donc UN SEUL geste distant à la fois de toute façon, limitation réelle reproduite pour le dessin). Suppression d'objet PAS synchronisée (Android non plus, vérifié : `executeDeleterObjeect` n'appelle jamais `pbStreamActionListener`). |
| Shareboard (module 13) / Message Graphic (module 14) | `com.animems.engine.android.pbs.PBSView.java` (rendu `onDraw`/gestes `touchListener`) | `Shareboard/PBSCanvasView.swift` | ÉCRIT (NON COMPILÉ) | Rendu réécrit en SwiftUI natif plutôt que traduit ligne à ligne : traits libres dans un `Canvas` (chemins vectoriels), objets placés (texte/image/sticker) en VRAIES vues SwiftUI empilées au-dessus (`Text`/`Image` + `DragGesture`/`MagnificationGesture`/`RotationGesture` natifs composés via `SimultaneousGesture`), plutôt que hit-testés manuellement dans une boucle `onDraw` comme l'original (`getMidPoint`/`getDegre`/`getDistance`, trigonométrie manuelle, non reproduite). **Non porté, délibérément différé, documenté** : icône "Tiinver" embossée (`EmbossMaskFilter`/`BlurMaskFilter`), carrousel de bannières publicitaires (`BannerAdapter`/`ViewPager2`), tutoriel `TapTargetView` — purement décoratifs/publicitaires, sans impact sur la fonction collaborative principale. |
| Shareboard (module 13) | `messagerie/ui/FragmentPbs.java` (810 lignes, entier) + `messagerie/model/PBSViewModel.java`/`PBSModel.java` (58+22, entier) | `Shareboard/PBSViewModel.swift`, `Shareboard/ShareboardView.swift` | ÉCRIT (NON COMPILÉ) | UN SEUL coordinateur `@MainActor` (même choix que `CallCoordinator`, module 12). **Écart délibéré vis-à-vis d'Android, documenté en tête de fichier** : `FragmentPbs.webrtc = RTConnection2.getInstance(requireActivity())` réutilise le MÊME SINGLETON que `CallService` (empêchant structurellement un appel ET un Shareboard simultanés côté Android) — ici, `PBSViewModel` possède sa PROPRE instance de `WebRTCConnection` (classe non-singleton), car aucun point d'entrée UI n'ouvre le Shareboard pendant un appel actif (`CallCoordinator.state` contrôle seul `CallView`) : la mutuelle exclusion d'Android n'était pas un comportement observable à préserver. Asymétrie initiateur/poli de `configForOutgoingCall`/`configForIncomingCall` préservée à l'identique (même motif contre-intuitif que les appels). TURN via le MÊME endpoint `call/turn-credentials` que les appels (`TurnCredentialsFetcher` partagé côté Android, pas une supposition). Signalisation socket ajoutée à `ChatRepository.swift` (listeners `nextPage`/`beforePage`/`joinRoom`/`leaveRoom`/`onTouchListener`/`onReceiveData`/`onStartPrivatePBS`/`onJoinPrivatePBS`, jusqu'ici manquants — seul `webrtcMessage`, partagé avec les appels, était câblé). `PBSEvent` (module 11) existait déjà mais rien ne l'alimentait. **PAS porté** : `addPbsNotification` (message système local "shareboard" inséré en base au démarrage du salon, `ChatManager.addPbsNotification*`) — décoratif, sans impact sur la synchronisation, différé faute de temps. |
| Message Graphic (module 14) | `messagerie/ui/FragmentMessageGraphic.java` (295 lignes, entier) | `Shareboard/MessageGraphicComposeView.swift` | ÉCRIT (NON COMPILÉ) | Capture LOCALE pure (aucun réseau, contrairement au Shareboard), réutilisant le même `PBSCanvasEngine`/`PBSCanvasView`, envoyée en UN SEUL message `"graphic"` à la fin (`GraphicMessageCodec.encodeTouchBatch`). **Bug Android trouvé, délibérément PAS reproduit littéralement, documenté** : `FragmentMessageGraphic.onSendPBStreamData` (objets placés — image/texte/sticker) construit un `JSONObject` local puis ne fait RIEN d'autre — seul `onSendPBSTouchSreamListner` (dessin) alimente réellement le lot envoyé ; un objet placé pendant la composition DISPARAÎT donc silencieusement du message final côté Android. Plutôt que de reproduire cette UX confuse, l'écran de composition n'expose délibérément QUE l'outil dessin (pas de boutons image/texte/sticker) — décision explicite, pas un oubli. `pbs_compound.setDataCompress(2)` (cadence DIFFÉRENTE du Shareboard temps réel, qui utilise 3) reproduite. |
| Message Graphic (module 14) | `messagerie/ui/viewholders/GraphicMessageViewHolder.java` (152, lu au module 11) | `Messagerie/ChatBubbleViews.swift` (`GraphicPlaceholderBubbleBody`, remplacé) | ÉCRIT (NON COMPILÉ) | Ancien placeholder honnête (module 11) remplacé par un rendu réel : décode `message.message` (déjà substitué depuis `MgGraphic` par `ChatViewModel.onIncoming`/`MessageRepository`, module 11 protocole) via `PBSCanvasEngine.loadRecordedBatch`, rejoué dans LE MÊME moteur `PBSCanvasView` en `isInteractive: false`. `ChatViewModel.sendGraphic(payload:)` ajouté (symétrique de `sendText`/`sendMedia`, `object="graphic"`) — point d'entrée bouton non identifié côté Android (comme le bouton d'appel, module 11/12), câblé directement depuis `ChatView` sur `MessageGraphicComposeView`. |
| Wallet / Paiements (module 15) | `wallet/BuyCoinsActivity.java` (188, CONFIRMÉ MORT), `wallet/CheckoutActivity.java`+`CheckoutViewModel.java`+`utils/PaymentsUtil.java`+`Constants.java`+`CheckoutSuccessActivity.java` (Google Pay, exemple Google non terminé jamais relié au crédit de pièces) | — | CONFIRMÉ MORT/NON FONCTIONNEL, PAS PORTÉ | Voir section "⚠️ AUDIT CONFORMITÉ APP STORE" ci-dessus pour l'analyse complète. `BuyCoinsActivity` absent d'`AndroidManifest.xml` + entièrement commenté dans le fichier source. Le reste (`CheckoutActivity`/`PaymentsUtil`/`Constants`) EST déclaré dans le manifeste (techniquement atteignable) mais est du code d'exemple Google Pay copié-collé jamais fini (`gatewayMerchantId: "example"`, prix `"50.2"` codé en dur, `handlePaymentSuccess` ne crédite jamais de pièces). `PeerToPeerActivity` (déclarée, atteignable) est un stub vide (inflate seul, aucune logique). |
| Wallet / Paiements (module 15) | AUCUN équivalent Android — remplace le flux d'achat réel (`SelectAmountActivity`→`PurchaseActivity`, mobile money/crypto + ID de transaction manuel) sur instruction explicite | `Wallet/CoinStoreManager.swift`, `Wallet/BuyCoinsView.swift`, `Wallet/WalletModels.swift` (`CoinTier`) | ÉCRIT (NON COMPILÉ) | API StoreKit 2 (`Product.products(for:)`/`.purchase()`/`Product.PurchaseResult`/`VerificationResult`/`Transaction.updates`/`.finish()`) vérifiée contre le code source réel de `RevenueCat/purchases-ios` (`StoreKit2TransactionListener.swift`) avant écriture, Apple ne rendant pas son contenu JS exploitable (même contrainte que CallKit/PushKit, module 12). 5 paliers consommables reprenant les quantités Android (250/500/1250/2500/5000), IDs `com.tiinver.ios.coins.<quantité>` À CRÉER dans App Store Connect (pas encore fait, hors périmètre code). Rapporte au backend via un endpoint NEUF (`POST storekit/verify-purchase`, PAS `purchaserequests`) — implémentation SERVEUR PAS faite, voir section "Backend à implémenter" ci-dessous à étendre. |
| Wallet / Paiements (module 15) | `wallet/WalletRepository.java` (364, entier, SAUF `submitPurchasseRequest`/`submitPurchasseByCrypto` délibérément omises) | `Wallet/WalletRepository.swift` | ÉCRIT (NON COMPILÉ) | Endpoints REST reproduits à l'identique (`transactions/{id}/{limit}/{offset}`, `withdrawalrequests`, `crypto/withdraw` via `postToVPS` — serveur distinct confirmé —, `convert`, `rewardedCoins`, `referral/total/{id}`, `transfert` — faute d'orthographe française RÉELLE côté serveur, préservée —, `isPhoneOrEmailExiste`, `getuserbyid/{id}`, `push`). `refreshBalance` reproduit fidèlement l'enrobage artificiel `"["+userData+"]"` d'Android (un objet unique redésérialisé comme tableau à un élément). |
| Wallet / Paiements (module 15) | `wallet/WithdrawActivity.java` (566, entier), `TransfertCoinsActivity.java` (331, entier), `ConversionActivity.java` (251, entier), `ReferralActivity.java` (511, entier — génération de "carte" QR décorative NON reprise), `EarnCoinsActivity.java` (400, entier), `WalletActivity.java`+`WalletViewModel.java` (229+55, entiers), `models/wallet/*.java` (Transaction/Operator/Prix/Wallet, tous lus en entier) | `Wallet/WalletView.swift`, `Wallet/WithdrawView.swift`, `Wallet/TransferCoinsView.swift`, `Wallet/ConversionView.swift`, `Wallet/ReferralView.swift`, `Wallet/EarnCoinsView.swift`, `Wallet/WalletViewModel.swift`, `Wallet/WalletModels.swift` | ÉCRIT (NON COMPILÉ) | Formulaires/calculs de frais/seuils portés fidèlement (voir audit conformité ci-dessus). QR code du parrainage : `CIFilter.qrCodeGenerator()` (Core Image natif) remplace ZXing — API système, pas de dépendance tierce à vérifier, contrairement à l'original. Pub rewarded (`RewardedAd`/`RewardedInterstitialAd`) volontairement PAS câblée dans `EarnCoinsView`/`WithdrawView`/`TransfertCoinsActivity`-équivalent — protocole `AdRewardProvider` posé comme point d'ancrage exact pour le module 16 (AdMob), avec une implémentation `PlaceholderAdRewardProvider` qui ne rapporte jamais de récompense (pas un faux crédit silencieux). Minuteur décoratif de 10s avant bouton "voir la pub" (`EarnCoinsActivity.createTimer`) non repris. `MonetizationActivity` (menu hub redirigeant vers caméra/contacts/parrainage/IA, aucune logique wallet propre) PAS porté comme écran dédié — remplacé par la navigation SwiftUI native vers les écrans concernés, chacun déjà/à porter séparément. **Point d'entrée UI de `WalletView` PAS câblé** : Android lance `WalletActivity` depuis `uploadPerfilPhoto/AddPerfilFoto.java` (module 17, pas encore atteint à l'écriture de cette ligne) — à faire au moment de porter ce module. |
| Wallet / Paiements (module 15) | `TiinverConfig.java` (89, entier), `CountryManager.java` (48, entier), `setting/FirebaseConfigManager.java` (déjà porté module antérieur sous `Settings/FirebaseConfigManager.swift`, RAS pour les clés wallet — toutes déjà présentes) | `Wallet/TiinverConfig.swift` | ÉCRIT (NON COMPILÉ) | Détection de pays SIMPLIFIÉE : Android essaie `TelephonyManager.getSimCountryIso()`/`getNetworkCountryIso()` avant `Locale.getDefault().getCountry()` — `CoreTelephony`/`CTCarrier` (équivalent iOS) est restreint par Apple depuis iOS 16 pour confidentialité (fait public documenté, pas une supposition), donc porter ce repli produirait du code mort qui semble fonctionner mais ne renvoie jamais de vraie valeur ; utilise directement `Locale.current.region`, qui était de toute façon le dernier recours réel d'Android. Liste de pays CEMAC recopiée depuis `TiinverConfig.java` (6 pays + indicatifs E.164 réels, faits publics) plutôt que l'asset `countries.json` non lu (fichier de ressource, pas de code). `TiinverConfig.configure()` câblé dans `AppDelegate.swift`. |
| Sécurité / Session | `back_sync.infoContract.COINS_AMOUNT`/`GEMS_AMOUNT`/`PENDING_COINS_AMOUNT`/`PENDING_GEMS_AMOUNT` (`SharedPreferences`, lus dans quasiment tous les fichiers `wallet/` module 15) | `Security/UserSession.swift` (étendu) | ÉCRIT (NON COMPILÉ) | Cache local rapide du solde (pièces/gemmes) + compteurs de récompense en attente, lu par TOUS les écrans wallet avant tout appel réseau, mis à jour de façon optimiste après achat/retrait/transfert/conversion/récompense — même motif que `PENDING_COINS_AMOUNT` d'Android (repli en cas d'échec réseau, réessayé au prochain gain). |
| AdMob (module 16) | `AndroidManifest.xml:419` (App ID) + `res/values/strings.xml` (7 IDs d'unité, `MyAdMobId`/`MyAdMobRewardedId`/`MyAdMobRewardedIdOnFeed`/`MyAdMobInterstitielsRewardeadsId`/`MyAdMobInterstitielsadsId`/`MyAdMobOpenadsId`/`TestAdMobId`, tous lus en entier) + TIINVER_IOS_PORT_ANALYSIS.md §5.1 (2 IDs bannière codés en dur dans les layouts XML) | `Advertising/AdMobIdentifiers.swift` | ÉCRIT (NON COMPILÉ) | Tous les identifiants recopiés depuis les vraies sources (pas devinés) — même compte AdMob que l'Android, confirmé. IDs de test iOS de Google (`ca-app-pub-3940256099942544/…`, distincts des IDs de test Android) vérifiés verbatim contre le code source de l'exemple officiel `googleads/googleads-mobile-ios-examples` avant d'être recopiés ici. `MyAdMobOpenadsId`/`MyAdMobInterstitielsadsId` (App Open ads / interstitiel classique) confirmés SANS appelant réel dans le code Android lu — pas repris. |
| AdMob (module 16) | AUCUN équivalent Android direct — SDK vérifié contre l'exemple officiel Google avant écriture | `Advertising/AdMobManager.swift` | ÉCRIT (NON COMPILÉ) | `configureAdMob()` (port de `MobileAds.initialize`, appelé dans `AppDelegate` — **écart délibéré** : le bloc Android équivalent est entièrement commenté/mort, l'initialisation explicite EST en revanche requise côté iOS, pas d'auto-init équivalente, étape documentée de façon stable par Google). `AdBannerView` (`UIViewRepresentable`), `RewardedAdManager`/`RewardedInterstitialAdManager` (conformes à `AdRewardProvider`, protocole posé au module 15 dans `Wallet/EarnCoinsView.swift` comme point d'ancrage exact — câblés maintenant dans `EarnCoinsView`/`WithdrawView`/`TransferCoinsView`/`ConversionView`, portant fidèlement le motif `showRewardedVideoAfter`, délai de 500ms compris), `NativeAdLoader`/`NativeAdContentView` (rendu MANUEL — pas de Google Native Templates mûr côté iOS, confirmé §5.5 — PAS câblé dans le feed, module 6 déjà fermé sans ce point d'intégration, posé comme brique réutilisable avec un TODO explicite plutôt qu'un oubli silencieux). Bannières câblées dans `WithdrawView`/`TransferCoinsView`/`ConversionView`/`EarnCoinsView` (`bannerWallet`)/`ReferralView` (`bannerSecondary`, seul écran à utiliser le second ID, fidèle à l'original). |
| AdMob (module 16) | `project.yml`/`Info.plist` — App Tracking Transparency (iOS 14.5+), SKAdNetwork, App ID | `project.yml` (étendu) | ÉCRIT (NON COMPILÉ) | `GADApplicationIdentifier` (requis, sans quoi `MobileAds.shared.start` échoue silencieusement — comportement documenté du SDK), `NSUserTrackingUsageDescription` (AUCUN équivalent Android, prompt système ATT sans lequel le SDK sert des annonces non personnalisées par défaut), `SKAdNetworkIdentifier` de Google/AdMob (`cstr6suwn9.skadnetwork`, stable et documenté publiquement) — **liste PARTIELLE délibérément** : la liste complète (~50+ entrées) n'est nécessaire QUE si des réseaux de médiation (Meta/Unity/Pangle, comme côté Android) sont un jour activés côté console AdMob iOS ; non ajoutée sans confirmation que la médiation sera réellement activée, pour ne pas fabriquer une liste non vérifiée. Le prompt `ATTrackingManager.requestTrackingAuthorization` lui-même N'EST PAS déclenché par ce portage (aucun point d'entrée identifié côté Android à reproduire, cette permission n'existe pas sur cette plateforme) — le SDK fonctionnera en mode non personnalisé par défaut tant que ce prompt n'est pas ajouté, différé à une passe UX dédiée. |
| Profil / Réglages (module 17) | `uploadPerfilPhoto/ProfileRepository.java` (entier) + endpoints épars de `UserProfile.java`/`AddPerfilFoto.java`/`SettingAccountFragment.java` (`follow`/`block`/`user`/`logout`/`deleteaccount`, tous vérifiés dans `TransportData.java`) | `Profile/ProfileRepository.swift` | ÉCRIT (NON COMPILÉ) | `fetchProfile`/`fetchUserPosts` (endpoint À 4 segments `feedtimeline/{actor}/{userId}/{limit}/{offset}`, DIFFÉRENT du `fetchTimeline` à 3 segments du module 6/`FeedRepository.swift` — feed personnalisé vs posts d'un profil précis) réutilisent `FeedActivity` (module 6) plutôt qu'un modèle dupliqué. `toggleBlock` reproduit fidèlement la bascule serveur (réponse `"USER BLOCKED"`/`"USER UNBLOCKED"`, pas un paramètre `blocked` envoyé par le client). `uploadProfilePicture` volontairement NON implémenté (`throw`, pas un faux succès silencieux) — transfert multipart pas encore porté, même gap que le module 11. |
| Profil / Réglages (module 17) | `UserProfile.java` (1198, sections chrome immersif Android ignorées) + `AddPerfilFoto.java` (1164, sections upload NON portées) | `Profile/ProfileView.swift`, `Profile/ProfileViewModel.swift` | ÉCRIT (NON COMPILÉ) | UN SEUL écran paramétré (`isCurrentUser`) remplace les deux Activity Android — voir avertissement de tête de fichier. Grille de posts paginée (`LazyVGrid` 3 colonnes), en-tête (avatar/nom/certifié/avertissement/stats abonnés-abonnements/bio/lien), actions conditionnelles (Modifier+Portefeuille pour soi, Suivre+Message+Bloquer/Signaler pour autrui). `messageTarget` reproduit `openConversation` champ par champ (`RosterModel`), visible UNIQUEMENT si `type=="public"` (fidèle à `message.setVisibility` conditionnel). Bouton Portefeuille câblé sur `WalletView` (module 15) — point d'entrée réel confirmé (`AddPerfilFoto.java` lance `WalletActivity` depuis `container_wallet`). `HomeShellView.swift` (module 1) avait déjà un appel `ProfileView()` sans argument anticipant ce module — résolu par un init de commodité `ProfileView()` = profil courant, plutôt que de casser ce point d'entrée préexistant. **PAS porté** : `FollowList` (abonnés/abonnements), zoom plein écran avatar/posts (`zoomImage`/`ViewPager2`), `Report` (signalement, bouton présent mais vide — module 18). |
| Profil / Réglages (module 17) | `EditProfile.java` (190, entier), `EditPersonalInformation.java` (235, entier) | `Profile/EditProfileView.swift`, `Profile/EditPersonalInformationView.swift` | ÉCRIT (NON COMPILÉ) | **Asymétrie réelle préservée** : colonne locale Core Data `work`/`school` vs colonne REST `work_At`/`school_At` (vérifié ligne par ligne dans `EditPersonalInformation.UpdateProfileData`, PAS unifiée). Catégorie de profil (`CategoryActivity`) affichée en lecture seule, modification différée (écran séparé non lu). Un champ n'est envoyé au serveur QUE s'il n'est pas vide (fidèle : on ne peut pas effacer un champ existant depuis ces écrans côté Android non plus). |
| Profil / Réglages (module 17) | `setting/SettingsActivity.java` (193, entier) + `SettingAccountFragment.java`/`SettingAdvertisementFragment.java`/`SettingNotificationFragment.java`/`SettingChatFragment.java`/`SettingPrivacityFragment.java` (tous lus en entier) + `SettingStorageFragment.java` (lu partiellement) | `Settings/SettingsView.swift`, `Settings/SettingSubViews.swift` | ÉCRIT (NON COMPILÉ) | **Découvertes de code mort en cascade** (même méthodologie que les modules précédents — vérifié en lisant le corps réel des fichiers, pas deviné depuis leur nom) : `SettingPrivacityFragment` — 5 des 6 réglages de confidentialité granulaires (dernière connexion/photo/appels/groupes/statut) ENTIÈREMENT commentés dans le source (`onCreateView`, ~50 lignes mortes), seul "compte privé" (`account_type_switch`, `POST user` colonne `type`) est réel ; `SettingChatFragment` (menu "Chat") ne contient QUE le thème clair/sombre de l'app entière, aucun réglage de discussion — nom de classe trompeur, vérifié plutôt que supposé. Notifications (3 bascules chat/groupe/page) et Stockage (3 bascules mobile/wifi/itinérance) confirmés RÉELLEMENT câblés mais PUREMENT LOCAUX (`SharedPreferences`, aucune synchronisation serveur) — portés en `@AppStorage`. **PAS porté** : détail granulaire du stockage par type de média (sélection multiple, 292 lignes lues partiellement) ; contenu réel Aide/À propos (fragments non lus, stubs informatifs posés). |
| Divers (module 18) | `Recherche/ui/RechercheTiinver.java` (754, réseau lu en entier) — **`RechercheTiinver2.java` (681, CONFIRMÉ MORT par grep, seul `RechercheTiinver.class` instancié ailleurs)** ; `Recherche/SearchRepository.java` (fichier réel VIDE, 4 lignes) | `Discover/SearchModels.swift`, `Discover/SearchRepository.swift`, `Discover/SearchView.swift` | ÉCRIT (NON COMPILÉ) | Recherche universelle 4 onglets (tout/publications/comptes/hashtags) + suggestions + historique local (`RecentSearchManager.java`, 69, entier, réécrit en `[String]`/`UserDefaults` direct plutôt que le hack de concaténation `"|||"` d'Android). **Convention "error" DIFFÉRENTE ici** : vrai booléen JSON sur cet endpoint, pas la chaîne `"false"` habituelle du reste du backend — vérifié, pas supposé uniforme. `SearchPostResult` dédié plutôt que réutiliser `FeedActivity` (module 6) : `actor` arrive en entier ici contre chaîne côté `feedtimeline`, vraie divergence entre endpoints. |
| Divers (module 18) | `Following/FollowList.java` (166, entier) + `FollowRepository.java` (56, entier) | `Discover/FollowListView.swift` | ÉCRIT (NON COMPILÉ) | Endpoint unique `{type}/{userId}/{followerId}/{limit}/{offset}` où `type` ∈ `{"followers","following"}` sert de segment d'URL brut (pas un paramètre nommé, vérifié). Câblé depuis `ProfileView` (module 17, stats abonnés/abonnements désormais cliquables). |
| Divers (module 18) | `report/Report.java` (172, entier) + `models/report/ReportData.java` (95, entier) | `Discover/ReportView.swift` | ÉCRIT (NON COMPILÉ) | `POST report`, `{userId, username, message, target_id, report_type}`. **Motifs de signalement PAS vérifiés contre `R.array.report_setting_array`** (ressource non lue) — liste reconstruite par analogie avec des motifs standards, à valider avant production. Câblé depuis le menu "Signaler" de `ProfileView` (module 17, précédemment un bouton vide). |
| Divers (module 18) | `comments/controller/CommentRepository.java` (282, entier) + `models/activity/comments/CommentModel.java` (champs lus en entier, `extends User` côté Android) | `Discover/CommentModels.swift`, `Discover/CommentRepository.swift`, `Discover/CommentsView.swift` | ÉCRIT (NON COMPILÉ) | `GET comment/{activityId}/{limit}/{offset}` (premier niveau), `POST comment` (`parentId` pour une réponse). **Chemin d'URL exact préservé** pour les réponses : `"/comment/replay/"+...` — le `/` de tête fait partie de la chaîne concaténée côté Android (vérifié ligne par ligne), pas corrigé. Commentaires "cadeau" (payants en pièces, `giftEmoji`/`giftPrice`) affichés en LECTURE SEULE — l'envoi (`comment/add`, débit de pièces, `GiftAdapter.java` non lu) N'EST PAS construit. |
| Divers (module 18) | `models/certification/Certification.java` (104, entier) + endpoints de `ui/certification/CertificationRepository.java` (366 lignes au total, SEULS les endpoints grep'és, PAS le corps lu en entier) | `Discover/CertificationModels.swift`, `Discover/CertificationView.swift` | ÉCRIT (NON COMPILÉ) | `GET certification/{userId}` (consultation du statut) SEUL porté. `POST certification/request` (nouvelle demande, upload multipart d'un justificatif) PAS porté — même gap que les transferts de fichiers non résolus des modules 11/17 (`UploadFileOrDataService.java` toujours pas lu à ce stade du portage). |
| Divers (module 18) | `contacts/repository/ConnectedUsersRepository.java` (109, entier) | — | REPÉRÉ, PAS PORTÉ | **Découverte** : malgré son emplacement dans le paquet `contacts`, ce fichier est en réalité un sélecteur de MEMBRES DE GROUPE pour la messagerie (`GroupModel`, endpoint `connectedusers/{userId}`) — PAS une fonctionnalité "Divers" de suggestions d'amis autonome comme son nom le suggérait. Rattaché plus logiquement à la création de groupe de discussion (module 11, pas encore construite), différé. |
| Divers (module 18) | `Activity/ui/StatisticsActivity.java` (228 lignes) | — | REPÉRÉ, PAS LU EN DÉTAIL | Aucun appel réseau trouvé dans le fichier (grep exhaustif) — vraisemblablement un tableau de bord d'agrégation LOCALE sur les publications de l'utilisateur courant, pas un endpoint REST dédié. Contenu réel non lu, différé faute de temps dans cette session déjà très chargée (modules 15-18 cumulés). |
| Divers (module 18) | `advertising/` (9 fichiers, ~2026 lignes — système de "boost" interne, promotion de contenu payée en pièces, SANS RAPPORT avec AdMob module 16, confirmé par TIINVER_IOS_PORT_ANALYSIS.md §3.8) | — | PAS REPÉRÉ CETTE SESSION | Aucun fichier de ce paquet ouvert cette session — seule son existence et sa distinction avec AdMob sont connues via le rapport de faisabilité, pas par lecture directe. À traiter dans une passe dédiée future. |

## Décisions autonomes prises (journal)

- 2026-08-10 : Vérification de `Authentification/MainActivity.java` (point 1 de la précédente
  "prochaine action") — confirmé qu'aucun endpoint REST supplémentaire n'est appelé avant
  login/register/forgotpassword. `MainActivity.onCreate` ne fait que de la navigation par
  Fragments + init SDK tiers (AdMob `MobileAds.initialize`, Facebook SDK) qui relèvent des
  modules 16 (AdMob) et Auth/providers, pas de l'infra réseau. Le module 1 réseau/auth est donc
  considéré comme couvrant tous les endpoints pertinents identifiés à ce stade ; passage au
  module 2 (Stockage local).

- 2026-08-10 : Projet créé via `project.yml` (XcodeGen) plutôt qu'un `.xcodeproj` généré par Xcode, car Xcode est indisponible sur cette machine Windows. Raison : XcodeGen permet de décrire un projet Xcode complet en texte, éditable et versionnable depuis n'importe quel OS, et génère le `.xcodeproj` réel à la première ouverture sur macOS (`xcodegen generate`). Alternative rejetée : écrire un `.xcodeproj` à la main (format XML/pbxproj fragile, non recommandé même avec Xcode disponible).
- 2026-08-10 : Couche réseau construite autour d'un type `JSONValue` maison (proche de `org.json.JSONObject`) plutôt que des modèles `Codable` stricts par endpoint. Raison : le contrat backend n'est pas un contrat propre — `TransportData.java` traite chaque endpoint différemment (parfois "data" est une chaîne JSON ré-encodée, parfois le payload est directement sous une clé nommée par endpoint). Imposer une enveloppe `Codable` unique maintenant serait une invention non fondée sur le code source, contraire à la consigne de fidélité au comportement observé. Les modèles `Codable` spécifiques par endpoint seront ajoutés au fur et à mesure du portage des modules qui les consomment.
- 2026-08-10 : `Http/CustomTrust.java` non porté — confirmé mort (zéro instanciation dans tout le dépôt) et non fonctionnel de toute façon (son loader de certificats retourne `null`).
- 2026-08-10 : `Http/TenorApiClient.java` différé au module Messagerie (11) plutôt que porté avec l'infra réseau — c'est un client GIF spécifique à une fonctionnalité, pas une brique d'infrastructure transverse.
- 2026-08-10 : Auth du handshake Socket.IO implémentée via `.connectParams(["token": apiKey])` faute de certitude sur l'API exacte de `Socket.IO-Client-Swift` 16.x pour reproduire le champ `auth` du protocole Socket.IO v4. Décision prise sous incertitude assumée (documentée dans le fichier et ci-dessus) — À VÉRIFIER en priorité absolue au premier build réel sur macOS, avant de considérer le module Réseau comme fiable pour le chat/les appels.
- 2026-08-10 : Schéma Core Data dérivé exclusivement de `Dbase.onCreate()` (schéma version 26), sans reconstituer les 26 migrations `onUpgrade` intermédiaires. Raison : nouvelle app native, aucune base Android existante à migrer (TIINVER_IOS_PORT_ANALYSIS.md §6.3 point 6) — seul l'état final du schéma compte. Vérifié explicitement, table par table, que `onCreate()` contient déjà toutes les colonnes que les migrations auraient ajoutées (les `ALTER TABLE` sont gardés par `checkColumnExists`, donc no-op sur une installation neuve).
- 2026-08-10 : Colonne `_id` (PK auto-incrémentée SQLite) renommée `localId` dans toutes les entités Core Data. Raison : un attribut préfixé `_` est déconseillé par convention Swift/Core Data, et Core Data gère de toute façon sa propre identité (`NSManagedObjectID`) indépendamment de cette colonne applicative.
- 2026-08-10 : Toutes les colonnes `snake_case`/`object_url`-style renommées en camelCase (`objectUrl`, `cdnThumbnailUrl`, `deliverTime`, `imageByte`, `videoDuration`, etc.) dans le schéma Core Data — convention Swift standard. Ce n'est PAS une violation de la règle "ne pas modifier les contrats non négociables" (TIINVER_IOS_PORT_ANALYSIS.md §6.3) : cette règle protège le contrat RÉSEAU (JSON reçu du serveur), pas le schéma de stockage LOCAL, qui est une reconstruction interne à l'app iOS sans contrepartie serveur. La correspondance colonne SQLite ↔ clé JSON backend ↔ attribut Core Data devra être documentée explicitement dans la future couche repository/DAO (pas encore écrite) pour éviter toute confusion pendant le portage des modules qui consomment ces données (messagerie, feed, etc.).
- 2026-08-10 : Attribut `description` de `wk_messages`/`wk_roster` renommé `messageDescription`/`rosterDescription`. Raison : **contrainte technique réelle**, pas une préférence — `NSManagedObject` hérite de `NSObject.description: String` (non optionnel), donc un attribut Core Data généré nommé `description` entrerait en conflit de signature avec la propriété héritée (`String?` généré vs `String` attendu par `CustomStringConvertible`). Renommage obligatoire, pas cosmétique.
- 2026-08-10 : Table `wk_users` (nom Android trompeur : ce n'est PAS le profil utilisateur global, c'est le cache local des membres de groupe alimenté par `TransportData.getGroupMemebers()`/`updateMember()`) portée sous le nom d'entité `GroupMemberEntity` plutôt que `UserEntity`, pour éviter la confusion avec `AccountEntity` (= `wenack_account`, le vrai profil du compte connecté). Documenté en commentaire directement dans le fichier `.xcdatamodel` en plus d'ici.
- 2026-08-10 : Colonne `pageId` de `wk_contact` typée `String` dans Core Data alors qu'elle est déclarée SANS type SQL dans `Dbase.java:37` (`"pageId,"` — omission/bug confirmé dans le code source Android, SQLite retombe sur une affinité dynamique). Choix par défaut documenté plutôt que deviné comme `Integer` sans preuve — à corriger si un usage concret dans le code Android (pas encore lu à ce stade du portage) révèle le type réellement stocké en pratique.
- 2026-08-10 : `wk_setting` (bookkeeping interne `old_version`/`new_version`) non porté en entité Core Data — confirmé qu'aucune URI de `StubProvider.java` ne l'expose (absent de tous les `uriMatcher.addURI`), donc aucune fonctionnalité utilisateur n'en dépend.
- 2026-08-10 : Versions des packages SPM dans `project.yml` (Alamofire 5.9+, Socket.IO-Client-Swift 16.1+, MetalPetal 1.10+, Gifu 3.4+, etc.) fixées à des versions plausibles à la date du rapport de faisabilité (référencé comme "août 2026" dans `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`) sans pouvoir vérifier la disponibilité réelle sans accès réseau vers GitHub/SPM depuis cet environnement de build. À ajuster à la première résolution de dépendances sur macOS si une version n'existe pas.
- 2026-08-10 : Règle de compilation par checkpoint ajoutée à la demande explicite de l'utilisateur (section en tête de fichier) — 3 arrêts obligatoires fixés d'avance sur les modules 6/12/18, remplaçant l'approche "au fil de l'eau" précédente (dernier point de la section "Prochaine action" de la version antérieure du fichier).
- 2026-08-10 : Couche repository/DAO du module 2 construite comme un type **générique unique** `CoreDataRepository<Entity: CoreDataFetchable>` plutôt qu'un repository par entité (14 types quasi identiques). Raison : lecture de `back_sync/StubProvider.java` (`query`/`insert`/`delete`/`update`) confirmant que ce `ContentProvider` ne fait lui-même qu'un dispatch générique `db.<opération>(nomDeTable, ...)` par `UriMatcher`, sans logique métier propre à chaque table — à deux exceptions près (`ROSTER_ALL` et `UNREAD_MESSAGE_COUNT`, toutes deux sur `wk_roster`), sorties dans `RosterRepository.swift` dédié. Décision prise après avoir écrit concrètement le cas générique ET le cas particulier, conformément à la réserve posée précédemment ("à évaluer une fois 2-3 repositories concrets écrits plutôt que de deviner l'abstraction à l'avance").
- 2026-08-10 : `CoreDataRepository<Entity>` paramétré par un protocole `CoreDataContextProviding` (`newBackgroundContext()`) plutôt que directement par `CoreDataStack`, pour être réutilisable tel quel avec `AnalyticsCoreDataStack` (deuxième store, voir ci-dessous) sans dupliquer le générique.
- 2026-08-10 : Lecture de `com.tiinver.db.AppDatabase.java` + `db/ViewEvent(Dao).java` + `db/entity/AiConversationEntity.java` + `db/dao/AiConversationDao.java` (Room, base `tiinver_db`, version 3) — confirmé actif et utilisé par `Utils/ViewTracker.java` (tracking watchtime pour Vertex AI) et `service/worker/ViewSyncWorker.java` (sync serveur via `WorkManager`). Porté en un DEUXIÈME `.xcdatamodeld` (`TiinverAnalyticsModel`) + `AnalyticsCoreDataStack.swift` indépendant, comme annoncé. La contrainte d'unicité Room `@Index(unique=true)` sur `(userId, activityId)` de `view_events` n'est PAS reproduite comme contrainte Core Data native (complexité de politique de fusion non justifiée) : elle est déjà appliquée au niveau applicatif par un `findExisting` avant écriture dans `ViewEventRepository.record()`, à l'identique de ce que fait `ViewTracker.record()` côté Android (qui ne s'appuie pas non plus sur `OnConflictStrategy.IGNORE` pour ce chemin).
- 2026-08-10 : La synchronisation réseau du tracking de vues (`WorkManager`/`ViewSyncWorker.java`, périodique 15 min + immédiate au-delà de 5 vues en attente) est DIFFÉRÉE au module 18 (Divers/stats) plutôt que portée avec le module 2. Raison : ce n'est pas une brique de stockage local mais un sujet de tâches d'arrière-plan à part entière (équivalent iOS : `BGTaskScheduler`/`BGAppRefreshTask`), cohérent avec le fait que le rapport de faisabilité classe "stats" dans le module 18. Seule la couche de lecture/écriture locale (`ViewEventRepository.swift`) est portée ici.
- 2026-08-10 : Écran consommateur de `AiConversationDao` (`ai/TiinverGeminiAIChat.java`, chat IA Gemini) repéré mais PAS ENCORE LU ni porté — n'apparaît dans aucun des 18 modules de l'ordre de portage sous ce nom explicite. Seule la couche de stockage (`AiConversationRepository.swift`) est portée avec le module 2 (elle appartenait de toute façon à `AppDatabase.java`, lu en bloc) ; le rattachement du module fonctionnel (probablement proche de la Messagerie, module 11) sera décidé en lisant `TiinverGeminiAIChat.java` le moment venu.
- 2026-08-10 : Module 3 (Auth/Onboarding) démarré. Inventaire fait : ~20 fichiers Java sous `Authentification/**` (login, register, onboarding, password recovery, provider Google/Firebase, vérification email, saisie téléphone, compounds de vue). Seuls `AuthViewModel.java`+3 doublons et `LoginFragment.java`+`LoginCompound.java` ont été lus et portés à ce stade (voir tableau ci-dessus) — le reste (`SignupFragment.java`, `onboarding/**`, `passwordrecovery/**`, `withprovider/**`, `MyCodeConfirmFragment.java`, `EmailVerificatiionCode.java`, `register/phoneNumber.java`, `register/Inscrire.java`, `PoliticaDemand.java`, `view/RegisterCompound.java`) reste À LIRE ET À PORTER avant de considérer le module 3 terminé.
- 2026-08-10 : Connexion Google/Firebase (`CredentialManager`, `GoogleIdTokenCredential`, `FirebaseAuth`) NON câblée dans `LoginView.swift` — `project.yml` ne déclare aucun package Firebase/GoogleSignIn (absent du choix de librairies fait au module 1). `TODO` explicite laissé dans le code plutôt qu'une intégration inventée sans confirmation du SDK exact à utiliser côté iOS (Firebase iOS SDK + GoogleSignIn-iOS très probables, mais pas encore une décision actée dans `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md`) — à trancher explicitement avant la fin du module 3, pas à deviner en écrivant `LoginView.swift`.
- 2026-08-10 : Flag `USING_EMAIL` (`Settings.setBooleanPreference`, `setting/Settings.java`) écrit directement en `UserDefaults` dans `LoginView.swift` plutôt que par un port anticipé de tout `Settings.java` (module 17, pas encore atteint) — un seul flag booléen ne justifie pas d'anticiper un module entier de 15 modules d'écart dans l'ordre de portage.
- 2026-08-10 : **Déviation explicite de l'ordre de portage, à la demande directe de l'utilisateur** ("continuer avec le 4/5/6") : le module 3 (Auth/Onboarding) est mis en pause EN COURS (Login fait ; Register/mot de passe oublié/vérification email/onboarding/Google restent À FAIRE, voir décision du 2026-08-10 ci-dessus) et le travail reprend sur les modules 4, 5 puis 6. Documenté ici conformément à la règle "ne pas dévier sans raison documentée" de l'en-tête "Ordre de portage". Conséquence pour le Checkpoint 1 : il ne pourra être marqué ATTEINT tant que le module 3 n'aura pas été refermé, même si 4/5/6 sont achevés avant — les modules 1 à 6 doivent être complets, pas seulement 1-2 et 4-6.
- 2026-08-10 : Module 4 (Notifications push) — **découverte d'un TROISIÈME store local Android indépendant** en lisant `NotiLikecmt/NotificationRepository.java` : `models/notification/NotiDatabase.java` (Room, `tiinver_notifications.db`, table `wk_notifications`), confirmé actif ET distinct de `wk_noti` (StubProvider, module 2) par grep des appelants et comparaison des schémas (champs `cdnContentId`/`payloadType`/`verified`/`isRead` absents de `wk_noti`). Porté comme troisième `.xcdatamodeld`/pile Core Data indépendante (`TiinverNotificationsModel`/`NotiCoreDataStack`), même traitement que la découverte d'`AppDatabase` au module 2 — `CoreDataRepository<Entity>` et `CoreDataContextProviding` réutilisés tels quels, aucune duplication de générique nécessaire pour la troisième fois.
- 2026-08-10 : Enregistrement du jeton push (`MyFirebaseInstanceIdService.java`) porté via APNs natif (`UIApplication.registerForRemoteNotifications`) plutôt que Firebase Cloud Messaging, faute de décision actée sur le SDK Firebase — même blocage que la connexion Google du module 3. Le code est isolé dans un point de bascule unique (`PushTokenRegistrar.handleDeviceToken`) documenté comme hypothèse à vérifier, pas une invention silencieuse : si le backend envoie ses pushs via l'API Firebase, un jeton APNs brut ne suffira pas tel quel.
- 2026-08-10 : `back_sync/NotificationUtils.java` porté PARTIELLEMENT (contenu de notification "activité" + "message de chat" seulement). Explicitement exclus avec justification : notifications d'appel entrant/en cours (VoIP/CallKit → module 12, pas "notifications push" génériques), notification de progression d'upload (→ module 11 Messagerie), notification de réengagement `displaySuggestNotification` (textes localisés `R.array` jamais lus, différé plutôt qu'inventé).
- 2026-08-10 : `NotificationHelper.java` (racine `com.tiinver`) non porté — confirmé mort par grep (`new NotificationHelper(` : zéro résultat dans tout le dépôt). Générique et jamais instancié, catégorie `CATEGORY_CALL` codée en dur même pour un usage générique — vraisemblablement un brouillon abandonné au profit de `NotificationUtils.java` (bien plus complet et effectivement utilisé, déjà porté partiellement en `LocalNotificationBuilder.swift`).
- 2026-08-10 : Découverte que l'endpoint `notification2/{userId}` utilise "error" comme un booléen JSON réel (`object.getBoolean("error")`), contrairement à la convention chaîne `"false"`/`"true"` déjà documentée pour les endpoints du module 1 (`isBackendSuccess`). Ajout d'une méthode dédiée `JSONValue.bool(_:)` plutôt que de forcer ce cas dans `isBackendSuccess` — le backend a manifestement plusieurs conventions "error" selon l'endpoint, à vérifier au cas par cas plutôt qu'à supposer uniforme.
- 2026-08-10 : Module 5 (UI Shell/navigation) — **correctif rétroactif sur le module 1** : en lisant `SplashActivity.java`/`manager/SessionManager.java` pour la première fois (nécessaire pour porter la décision login/home), découverte que `SessionManager` persiste `nikname`/`firstname`/`lastname`/`referralCode` en plus des 4 champs déjà couverts par `Security/UserSession.swift`. Ce fichier datait du module 1, écrit avant la lecture de `SessionManager.java` (pas nécessaire à ce stade-là). Étendu avec les 4 champs manquants + `cachedUser()`/`save(_:)` (ports directs de `getUser`/`saveUser`) plutôt que de laisser `RootRouterView.swift` reconstruire un `User` vide en cas de session locale sans objet `User` déjà en mémoire — aurait produit un profil visiblement incomplet après un redémarrage de l'app, pas juste un détail cosmétique.
- 2026-08-10 : Ordre de navigation Android reproduit tel quel dans `AuthCoordinatorView.swift` malgré son incohérence apparente (lien "inscrire" → SignUpWithGoogle plutôt que le formulaire d'inscription classique ; lien "mot de passe oublié" → RecoverPassword plutôt que mdpOublier) — confirmé en lisant `MainActivity.onArticleSelected` en regard de `LoginFragment.java`, pas une erreur de lecture. Pas corrigé unilatéralement : si ce n'est pas le comportement voulu, c'est à l'utilisateur de le signaler pour un vrai bug Android à ne PAS reproduire, pas à cette migration de le deviner.
- 2026-08-10 : Gate de mise à jour forcée (`SplashActivity`/`FirebaseConfigManager`/`UpdateApp`, Firebase Remote Config) NON porté dans `RootRouterView.swift` — même blocage SDK Firebase que les modules 3/4 (voir décisions précédentes), et `UpdateApp.java`/`FirebaseConfigManager.java` pas encore lus. Seule la décision login/home est portée à ce stade.
- 2026-08-10 : Les 3 `HomeActivity.scheduleDynamicWorker` (WorkManager périodique : `suggest-content`, `get-suggest-content`, `my-boost-deliver`) NON portés dans `HomeShellView.swift` — différés au module 18 (Divers), même traitement que `ViewSyncWorker` au module 2 : tâches d'arrière-plan de contenu suggéré/boost, pas des briques de coquille de navigation.
- 2026-08-10 : Module 6 (Feed vidéo) — `Activity/ui/MainFragment.java` fait 1966 lignes ; décision de ne PAS tenter un portage intégral en une passe (risque élevé d'erreurs non détectables sans compilation sur un fichier de cette taille). Seule la boucle centrale "charger une page depuis `feedtimeline`/mettre en cache/afficher plein écran/lire la vidéo active" est portée (`FeedViewModel`/`FeedView`). Interactions (like/commentaire/partage/double-tap), mode édition/upload, et pagination fine sont explicitement laissés pour plus tard, module par module, plutôt que devinés en bloc.
- 2026-08-10 : `ExoPlayerManager.java`/`CacheProvider.java` portés en s'appuyant sur les primitives natives iOS les plus proches (`AVPlayer` unique partagé, cache disque manuel avec éviction LRU) plutôt qu'une tentative de réplication littérale de l'architecture Media3 (`DefaultPreloadManager`, `SimpleCache`, `CacheDataSource`) qui n'a pas d'équivalent AVFoundation — même intention fonctionnelle (un seul lecteur réutilisé, préchargement des vidéos suivantes, cache disque plafonné avec éviction), mécanismes internes nécessairement différents par plateforme. Distinction HLS/MP4 de l'original (deux fabriques de `MediaSource` différentes) non reproduite : `AVPlayer` gère nativement les deux formats via une seule API, donc ce n'est pas un oubli mais une simplification légitime.
- 2026-08-10 : Défilement vertical plein écran du flux vidéo implémenté via un `TabView` pivoté (contournement standard, pas d'API de pagination verticale native sur iOS 16) — **hypothèse non vérifiable sans Xcode**, documentée comme telle dans `FeedView.swift`. Alternative de repli identifiée (`ScrollView`+`.scrollTargetBehavior(.paging)`, iOS 17+) mais PAS appliquée par défaut : relèverait la cible de déploiement du projet (`project.yml`, actuellement iOS 16), décision qui revient à l'utilisateur, pas à prendre unilatéralement pour un simple détail de défilement.
- 2026-08-10 : **Bug de portage trouvé avant toute compilation** : `Networking/JSONValue.swift` ne définissait pas `rawData`, alors que `AuthEndpoints.decodeUser` (écrit au module 1) le référence depuis le début (`meta.rawData`). Trouvé en voulant réutiliser le même mécanisme pour décoder les éléments du tableau "activities" en `FeedActivity` (module 6). Corrigé en ajoutant la propriété manquante plutôt que de contourner le problème dans `FeedRepository` uniquement — le module 1 en aurait eu besoin de toute façon au premier build réel. Aucune autre référence à une propriété/méthode manquante détectée en écrivant les modules 2 à 6, mais cet incident renforce la valeur de la règle de checkpoint : ce genre d'erreur reste indétectable sans compilation réelle.
- 2026-08-10 : **Priorité 0 — Blocage Firebase/FCM tranché par investigation directe du code source Android** (demande explicite de l'utilisateur : trancher, pas demander). SUPERSÈDE les décisions du 2026-08-10 notées plus haut sur `PushTokenRegistrar.swift` (APNs par défaut) et sur le gate de mise à jour forcée (non porté faute de décision). Preuves rassemblées, dans l'ordre demandé :
  1. `app/build.gradle` : `implementation 'com.google.firebase:firebase-messaging:25.0.1'` (ligne 153), `implementation("com.google.firebase:firebase-auth")` (ligne 142), `apply plugin: 'com.google.gms.google-services'` (ligne 217) — dépendances RÉELLES et actives, pas du code mort.
  2. `back_sync/MyFirebaseInstanceIdService.java` lu en entier : `requestNewFCMToken()` appelle explicitement `FirebaseMessaging.getInstance().getToken()`, PAS un jeton APNs traduit manuellement — la colonne backend `fcmId` reçoit donc un jeton FCM, pas un jeton APNs brut.
  3. `app/google-services.json` EXISTE, avec un projet Firebase réellement provisionné (`project_id: "com-tiinver"`, `project_number: "837038293145"`, vraies clés API/OAuth) — ET ce fichier déclare DÉJÀ une app iOS dans Firebase (`services.appinvite_service.other_platform_oauth_client[].ios_info.bundle_id = "com.tiinver.tiinverProject"`, client OAuth `client_type: 2` dédié), preuve qu'une app iOS a été anticipée/provisionnée avant ce portage — pas une simple possibilité théorique.
  4. Aucune mention d'APNs direct ou de provider de push alternatif trouvée dans le code ou `TIINVER_IOS_PORT_ANALYSIS.md` — ce dernier liste au contraire explicitement "Notifications push (Firebase iOS SDK/APNs, deep links)" comme ligne du plan de portage, et recommande le SDK iOS officiel pour Firebase Remote Config (même famille de service).
  **Conclusion : Firebase Cloud Messaging + Firebase Auth CONFIRMÉS, pas une hypothèse.** Actions : `PushTokenRegistrar.swift` réécrit pour `FirebaseMessaging` (voir tableau) ; `App/AppDelegate.swift` réécrit (`FirebaseApp.configure()`, `MessagingDelegate`, `GIDSignIn` URL handling) ; `project.yml` : ajout de `FirebaseCore`/`FirebaseAuth` (les packages `Firebase`/`GoogleSignIn` existaient déjà depuis le module 1, jamais câblés) ; `PRODUCT_BUNDLE_IDENTIFIER` changé de `com.tiinver.app` à `com.tiinver.tiinverProject` pour réutiliser l'app iOS déjà déclarée dans Firebase plutôt que d'exiger l'enregistrement d'une seconde app — **point à confirmer explicitement avec le propriétaire du projet avant tout envoi App Store réel**, ce n'est pas une décision anodine même si elle évite du travail de configuration.
  **Point encore ouvert, honnêtement signalé** : `Resources/GoogleService-Info.plist` (secrets projet Firebase pour iOS) n'existe PAS et n'est PAS fabriqué par ce portage — à télécharger depuis la console Firebase par l'utilisateur avant le premier build réel. De même, `RemoteConfigDefaults.plist` (équivalent de `remote_config_defaults.xml`, jamais lu) doit être fourni séparément.
- 2026-08-10 : Identifiants OAuth Google (`GoogleSignInCoordinator.swift`) extraits directement de `app/google-services.json` plutôt qu'inventés : client iOS (`client_type: 2`, associé au `bundle_id: com.tiinver.tiinverProject`) pour `GIDConfiguration`, client web (`client_type: 3`, même valeur que `R.string.default_web_client_id` généré côté Android) pour `serverClientID` — reproduit la distinction `setServerClientId(getString(R.string.default_web_client_id))` de `LoginFragment.java`/`SignUpWithGoogle.java`.
- 2026-08-10 : Module 3 refermé. Récapitulatif des fichiers confirmés MORTS par grep pendant cette passe (zéro instanciation dans tout le dépôt Android) : `register/Inscrire.java`, `register/phoneNumber.java`, `Authentification/ContinueWithGoogleRepository.java`. `MyCodeConfirmFragment.java` confirmé INACCESSIBLE (pas mort au sens strict — instancié dans le switch de `MainActivity`, mais aucun appelant du flux auth n'atteint jamais la position 5 sur `MainActivity` spécifiquement) par analyse croisée des appelants de `onArticleSelected(5, ...)` dans tout le dépôt (tous ciblent `HomeActivity`, sémantique différente pour le même entier). Les 4 fichiers : NON PORTÉS, décision documentée dans le tableau module par module.
- 2026-08-10 : Logique de persistance de session post-connexion (`CreateSyncAccount`, dupliquée à l'identique dans 3 fichiers Android : `LoginFragment`, `EmailVerificatiionCode`, `SignUpWithGoogle`) factorisée en un seul type Swift (`AuthSessionPersistence.swift`) plutôt que dupliquée dans les 3 vues SwiftUI correspondantes — la duplication Android n'a aucune justification fonctionnelle (copier-coller constaté, pas une variation intentionnelle).
- 2026-08-10 : **Priorité 2 — module 4, fichiers de synchro en arrière-plan lus en entier** (`MyBackgroundTask.java`, `Http/transportDataBackground.java`, `Activity/service/ActivityService.java`, `service/TiinverSyncWorker.java`, tous repérés au grep initial du module 4 mais jamais lus jusqu'ici). Conclusion : seule une petite portion (`TiinverSyncWorker.visiteServeur` → `MyBackgroundTask.notifyUser` → `NotificationRepository.fetchNotifications`) concerne réellement les notifications push, et elle est déjà couverte par `NotificationCenterViewModel` (module 4, déjà écrit). Le reste appartient à d'autres modules : sync des messages de chat (`ChatRepository`, module 11), logout/suppression de compte (`transportDataBackground.deleteaccount`, module 17 Réglages), upload de média en premier plan avec notification de progression (`ActivityService`, module 6/7 — et qui contient une clé API Bunny CDN en dur dans le source Android, non recopiée dans ce portage par précaution). `AppDelegate.didReceiveRemoteNotification` déclenche maintenant réellement le fetch de notifications (remplace le `TODO` vide laissé précédemment).
- 2026-08-10 : Module 4 (Notifications push) refermé — la décision précédente notée comme "hypothèse APNs" est désormais révisée (voir décision Priorité 0 Firebase ci-dessus). Badge de l'icône d'app câblé (`UNUserNotificationCenter.setBadgeCount`), synchronisé sur `NotificationCenterViewModel.unreadCount` en plus du badge in-app déjà existant.
- 2026-08-10 : **Priorité 2 — module 5, `ShowNoti.java`/`AddPerfilFoto.java`/`BaseActivity.java` lus.** `BaseActivity` confirmé purement visuel, rien à porter. `ShowNoti.java` porté en `NotificationsListView.swift`, en excluant explicitement l'injection de suggestions de follow dans la liste (feature de suggestions de contacts, pas de notifications — cohérent avec l'exclusion déjà actée de `retriaveData` au module 4). `AddPerfilFoto.java` (1164 lignes) confirmé être en réalité l'écran complet "Profil/Réglages" = MODULE 17, pas un sujet du module 5 — décision de porter une version RÉDUITE mais réelle (`ProfileView.swift`, infos locales seulement) plutôt que soit (a) tenter un portage intégral hors de propos pour ce module, soit (b) laisser un simple placeholder texte comme pour les onglets Chat/Créateurs (dont le contenu, contrairement au profil, appartient à des modules pas encore commencés — le profil basique, lui, est déjà entièrement constructible avec les données du module 1-2).
- 2026-08-10 : **Priorité 2 — module 6, 5 fichiers de préchargement ExoPlayer lus en entier** (`PreloadScheduler.java`, `LoadControlUtils.java`, `Preloader.java`, `MyTargetPreloadStatusControl.java`, `Utils/CacheCompat.java`). Ajout d'un préchargement en fenêtre `currentIndex ± 2` (reproduisant `PreloadScheduler`, `windowSize` par défaut 2) dans `FeedView.preloadAround`, filtrant les posts non-vidéo comme le fait `"videos".equalsIgnoreCase(...)` côté Android. `AVPlayerItem.preferredForwardBufferDuration` ajouté comme meilleur équivalent atteignable de `LoadControlUtils.createFastStartLoadControl` (réglages fins de buffer ExoPlayer sans équivalent public AVFoundation). Confirmé SANS ÉQUIVALENT ATTEIGNABLE, donc non portés : les états de préchargement étagés `MyTargetPreloadStatusControl`/`DefaultPreloadManager` (architecture interne Media3) et le polling de buffer `Preloader.checkBuffered`. `CacheCompat` (ratio de cache partiel 0-100%) jugé superflu face à l'équivalent binaire déjà en place (`VideoCacheManager.isCached`).
- 2026-08-10 : **Priorité 2 — module 6, `Activity/adapter/ActivityAdapter.java` (956 lignes) lu partiellement** pour confirmer la portée déjà actée (like/commentaire/partage/double-tap différés) — confirmé que c'est bien le fichier contenant cette logique, et que sa taille justifie de ne pas l'inclure dans une passe déjà très chargée. `ActivityDiffCallback.java` non porté (RecyclerView `DiffUtil`, sans équivalent nécessaire — SwiftUI diffe `List`/`ForEach` automatiquement). `BiographyAdapter.java`/`StatisticsAdapter.java` repérés dans le même dossier mais pas lus, probablement module 17 (profil) vu leur nom.
- 2026-08-10 : **Priorité 3 — lecture exploratoire de `roster/ui/Roster.java` (753 lignes) et `creatorOfweek/CreatorFragment.java` (217 lignes), notes pour plus tard, PAS porté.** `Roster.java` confirmé être l'écran de liste de conversations du module 11 (Messagerie) : `CursorLoader` sur `wk_roster` (déjà modélisé en `RosterEntity`, module 2), référence `ConversationIdGenerator`/`ChatType`/`MessageLib`, ET référence `TiinverGeminiAIChat` (chat IA Gemini) — confirme l'hypothèse posée au module 2 comme quoi ce module est probablement rattaché à la Messagerie. `CreatorFragment.java` = écran de classement hebdomadaire des créateurs ("créateur de la semaine", `TrophyViewModel`/`CreatorModel`, animation confettis) — fonctionnalité autonome non nommée explicitement dans les 18 modules de l'ordre de portage, à rattacher probablement au module 18 (Divers) le moment venu, à confirmer en le lisant en entier à ce moment-là.
- 2026-08-10 : **`Resources/GoogleService-Info.plist` intégré** — l'utilisateur a fourni le fichier réel (téléchargé depuis la console Firebase, projet "com-tiinver") à `C:\Users\helen\Downloads\GoogleService-Info.plist`, copié vers `Resources/GoogleService-Info.plist`. Contenu lu et exploité, rien fabriqué : `BUNDLE_ID = "com.tiinver.ios"` CONFIRME (corrige) le bundle id utilisé jusqu'ici (`com.tiinver.tiinverProject`, qui n'était qu'une déduction indirecte depuis un identifiant d'app invite secondaire de `google-services.json` Android, pas le vrai bundle id de l'app iOS principale) — `project.yml` mis à jour. `CLIENT_ID`/`REVERSED_CLIENT_ID` (client OAuth iOS type 2) extraits et remplacent l'ancienne valeur incorrecte dans `GoogleSignInCoordinator.swift`. `ANDROID_CLIENT_ID` du plist recoupé avec succès contre `google-services.json` Android (même valeur `...ab3v5p35vnlhghf1rhq0mv30vh37nni1...`), confirmant qu'il s'agit bien du même projet Firebase que celui déjà investigué à la Priorité 0. Aucun client OAuth "web" (`client_type: 3`) présent dans le plist iOS (normal, Firebase ne l'y inclut pas) — celui de `google-services.json` Android est réutilisé pour `serverClientID`, décision déjà prise à la Priorité 0 mais maintenant confirmée : ce client web apparaît à l'identique sous les deux apps Android du même fichier (donc partagé au niveau du projet, pas lié à un bundle précis) et son numéro de projet (`GCM_SENDER_ID`/`project_number` = 837038293145) correspond exactement à celui du plist iOS. `GIDConfiguration` dans `GoogleSignInCoordinator.swift` câble maintenant réellement `serverClientID` (la variable `webClientID` existait déjà mais n'était jamais passée au constructeur — oubli corrigé au passage). Grep sur tout `Sources/` confirmant qu'aucune autre référence codée en dur à l'ancien bundle id ou à l'ancienne clé API Android ne subsiste. Nouveau point identifié, hors du périmètre code : la clé APNs doit être téléversée séparément dans la console Firebase pour que les pushs soient effectivement délivrés — pas un fichier de ce dépôt, documenté dans le résumé Checkpoint 1 pour ne pas être oublié.
- 2026-08-10 : **`Resources/RemoteConfigDefaults.plist` intégré** — `res/xml/remote_config_defaults.xml` (Android, jamais lu jusqu'ici) lu en entier et converti fidèlement en plist : 39 clés reprises telles quelles, AUCUNE valeur par défaut ajoutée ni devinée. Types choisis d'après le contenu littéral du XML (bool pour "true"/"false", integer pour les nombres entiers, real pour `0.0035`, string pour le reste) — sans incidence fonctionnelle réelle puisque Firebase Remote Config coerce de toute façon vers le type demandé par chaque getter typé (`getDouble`/`getBoolean`/`getLong`/`getString`), simple choix de lisibilité. Quelques clés présentes dans le XML mais SANS getter dédié dans `FirebaseConfigManager.java`/`TiinverFirebaseConfigManager.swift` (`new_feature_enabled`, `animemes_creation_reward`, `ads_feed_reward` sans suffixe pays) reprises quand même intégralement, fidèles à la source, sans tenter de deviner leur consommateur. **Recoupement notable** : `app_expire_month = 13` dans le XML — vérifié (pas une coïncidence ignorée) que cette valeur, combinée à la logique `expireMonth - 1` d'Android (`Calendar` 0-indexé) ET à la logique Swift sans `-1` (`DateComponents` 1-indexé, décision du module 5), produit la MÊME date réelle dans les deux implémentations par débordement de mois (les deux calendriers étant permissifs) — confirmation a posteriori que la décision de ne pas soustraire 1 en Swift était le bon choix, pas une supposition non vérifiée.
- 2026-08-10 : **CI/CD ajouté pour vérifier le Checkpoint 1 sans machine macOS locale** : `codemagic.yaml` (workflow `checkpoint-build`) et `.github/workflows/ios-build.yml` (déclenchement `workflow_dispatch` MANUEL uniquement, PAS à chaque push — décision volontaire pour ne pas consommer de minutes CI GitHub Actions sans le vouloir). Les deux pipelines font strictement la même séquence : installer XcodeGen, décoder le secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` (variable d'environnement Codemagic / secret GitHub selon la plateforme) vers `Resources/GoogleService-Info.plist`, `xcodegen generate`, résolution des dépendances SPM, `xcodebuild build` en mode simulateur avec `CODE_SIGNING_ALLOWED=NO`. AUCUNE section de signature/publication dans les deux — objectif strictement "est-ce que ça compile", pas un pipeline de release (la signature/l'archive/TestFlight viendront bien plus tard, pas avant que plusieurs checkpoints soient validés). Le choix entre les deux dépend des crédits CI disponibles côté utilisateur (Codemagic offre un quota macOS gratuit limité par mois ; GitHub Actions facture les runners macOS au-delà du quota gratuit, généralement plus cher à la minute) — aucune préférence technique imposée, les deux sont strictement équivalents fonctionnellement.
- 2026-08-10 : **Bug d'environnement trouvé et corrigé en préparant le CI : `.gitignore` était encodé en UTF-16 avec BOM** (`fffe` en tête de fichier), pas en texte brut/UTF-8 comme git l'attend pour ce fichier — conséquence concrète : les règles qu'il contenait (`Resources/GoogleService-Info.plist`, `plist_base64.txt`) n'étaient très probablement JAMAIS appliquées par git (confirmé par `git check-ignore -v`, qui ne matchait aucun des deux fichiers avant correction, alors qu'ils auraient dû l'être). Cause probable : un outil de ce système Windows écrit les fichiers texte contenant des caractères accentués en UTF-16 par défaut — reproduit en écrivant d'abord une version en français, observé le même problème, puis réécrit en anglais/ASCII pur pour contourner cette contrainte d'environnement plutôt que de la "corriger" au niveau de l'outil (hors de portée). Vérifié après coup avec `git check-ignore -v` que les deux fichiers sont maintenant bien reconnus comme ignorés.
- 2026-08-10 : **Découverte de deux fichiers non suivis par git, contenant le secret Firebase en clair (base64), dans des emplacements inattendus** : `plist_base64.txt` à la racine du dépôt, et surtout `Sources/secrete code` (nom mal orthographié, à l'intérieur de l'arborescence source) — tous deux contiennent le même contenu (`GoogleService-Info.plist` encodé en base64, encadré de marqueurs `-----BEGIN/END CERTIFICATE-----`, format caractéristique de `certutil -encode` sous Windows). Ni l'un ni l'autre n'a été créé par cette session de travail (aucune trace de leur création dans les actions effectuées ici) — probablement des artefacts laissés par une session antérieure en préparant ce même secret pour le CI. Vérifié que `Sources/secrete code` est SANS RISQUE pour la compilation : `project.yml` ne globbe que `Sources/TiinverSwift` (pas `Sources/` au complet), donc XcodeGen ne le ramassera jamais comme fichier source. Les deux fichiers sont maintenant couverts par `.gitignore` (motif `plist_base64.txt` explicite ; `Sources/secrete code` n'a PAS de motif dédié, son nom étant trop spécifique/improbable pour justifier un motif générique risquant de masquer d'autres fichiers involontairement) — **NON SUPPRIMÉS par cette session**, faute de certitude qu'ils ne sont plus nécessaires à l'utilisateur ; signalé explicitement en dehors de ce fichier pour décision.
- **2026-08-10 : CHECKPOINT 1 VALIDÉ — troisième build Codemagic réel réussi, aucune erreur.** Build `#6a7a2aabd5ae67eb2a755de2` (workflow `checkpoint-build`), toutes les étapes passées y compris "Build simulateur — vérification de compilation uniquement, sans signature" (1m 34s). Ce que ce build confirme CONCRÈTEMENT, pas par supposition : (1) résolution SPM complète et sans conflit des 9 packages de `project.yml` (Alamofire, SocketIO, MetalPetal, Gifu, GoogleMobileAds, GoogleSignIn, FBSDK, WebRTC, Firebase 11.15+) ; (2) compilation sans erreur de l'intégralité des ~50 fichiers Swift des modules 1-6, y compris les 3 stores Core Data indépendants (`TiinverModel`/`TiinverAnalyticsModel`/`TiinverNotificationsModel`) et leurs 16 entités via le protocole générique `CoreDataFetchable`/`CoreDataRepository` ; (3) aucune erreur de liaison (linkage) sur les frameworks tiers. Les deux échecs précédents (`Missing package product 'FirebaseCore'`, `protocol 'CoreDataFetchable' requirement 'fetchRequest()' cannot be satisfied by a non-final class`) sont donc CONFIRMÉS résolus par ce build, pas seulement par lecture de documentation — voir "Erreurs rencontrées et résolues", entrées mises à jour en conséquence. **Conséquence directe** : Checkpoint 1 marqué VALIDÉ dans la "Règle de compilation par checkpoint" en tête de fichier ; le portage reprend au module 7 (Caméra + pipeline filtres GPU MetalPetal), le prochain arrêt obligatoire étant le Checkpoint 2 (fin du module 12). Les points d'incertitude NON liés à la compilation (handshake Socket.IO, rendu du `TabView` pivoté du feed — voir "CHECKPOINT 1 — Résumé pour build macOS", point 2) restent ouverts : un build réussi prouve la compilation, pas le comportement à l'exécution ; ils devront être vérifiés au premier accès à un simulateur/device réel, sans bloquer la reprise du portage.
- **2026-08-10 : Module 7 (Caméra) — premier passage, PAS FERMÉ, honnêtement signalé comme tel.**
  Travail réalisé dans cette session, dans l'ordre :
  1. **Lecture des deux rapports de référence** (`TIINVER_IOS_PORT_ANALYSIS.md` §3.3/§7,
     `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.2/§3.1) — confirmé : MetalPetal en fondation du
     pipeline GPU (caméra ET futur moteur Animems, même framework, un seul apprentissage Metal
     pour l'équipe), ~40 filtres GLSL à réécrire manuellement (aucun convertisseur automatique),
     GPUImage3 déconseillé (abandon quasi confirmé, aucune release en 7 ans).
  2. **Lecture directe du code Android réel du pipeline caméra** (`BaseCameraFragment.java` 711
     lignes en entier, `GPUCameraRecorder.java`, `CameraHandler.java`, `CameraThread.java`
     — via son point d'entrée `startPreview` —, `LensFacing.java`, `GPUCameraRecorderBuilder.java`,
     `CameraRecordListener.java`, `FilterType.java`, `GlFilter.java` + les 22 sous-classes
     `Gl*Filter`/`BeautyFilter` réellement instanciées, `GlFilterGroup.java`,
     `GlThreex3TextureSamplingFilter.java`, `MediaVideoEncoder.java`/`MediaAudioEncoder.java`
     (constantes d'encodage uniquement, pas lus en entier — voir "Prochaine action à faire")).
     **Découverte majeure** : `FilterType.createGlFilter()` n'a que 23 `case` réellement compilés
     sur 43 valeurs d'enum — les 20 autres sont dans un bloc `/* ... */` commenté (code mort,
     jamais exécuté), retombant systématiquement sur `GlMonochromeFilter` par défaut. Confirme
     l'importance de lire le code source réel plutôt que de déduire le périmètre du nom de l'enum
     — un carrousel de "43 filtres" en apparence n'en propose réellement que 23 côté Android.
  3. **Vérification de l'API réelle de MetalPetal 1.10.0 AVANT d'écrire du code Swift** — leçon
     tirée directement des deux échecs de build du Checkpoint 1 (`FirebaseCore`/
     `CoreDataFetchable`) : récupéré et lu directement depuis GitHub (tag `1.10.0`, celui déclaré
     dans `project.yml`) les en-têtes réels `MTIColorMatrixFilter.h/.m`,
     `MTIUnaryImageRenderingFilter.h/.m`, `MTIBulgeDistortionFilter.h/.m`,
     `MTIRenderPipelineKernel.h`, `MTIFunctionDescriptor.h`, `MTIVector+SIMD.h`, `MTIImage.h`,
     `MTIContext.h`/`MTIContext+Rendering.h`, `MTIImageView.h`, et le fichier shader réel
     `Shaders.metal`/`MTIShaderLib.h` (structure `VertexOut`, convention `fragment float4 nom(...
     [[stage_in]], texture2d<float> [[texture(0)]], sampler [[sampler(0)]], constant T&
     [[buffer(N)]])`, exemple réel `bulgeDistortion`) — plutôt que de deviner la signature d'API
     d'un SDK tiers comme cela avait causé l'échec `Missing package product 'FirebaseCore'`.
     Confirmé au passage que le SPM package MetalPetal était déjà déclaré dans `project.yml`
     depuis le module 1 (jamais câblé jusqu'ici) et que son product name (`MetalPetal`) est
     correct pour la version 1.10.0 déclarée.
  4. **Écrit** : `Camera/LensFacing.swift`, `Camera/CameraFilterType.swift` (enum 43 valeurs +
     repli Monochrome fidèle), `Camera/Filters/TiinverCameraShaders.metal` (22 fonctions
     `fragment`, transliteration GLSL→MSL 1:1, ex. `atan(Q,I)` GLSL 2-arguments → `atan2(Q,I)`
     MSL, seule vraie différence de langage rencontrée), `Camera/Filters/TiinverCameraFilters.swift`
     (22 sous-classes `MTIUnaryImageRenderingFilter`, une par filtre — pattern obligatoire vérifié
     dans le SDK réel, pas un choix arbitraire), `Camera/CameraCaptureController.swift`
     (`AVCaptureSession`, remplace `Camera2`+`CameraThread`), `Camera/CameraRecordingWriter.swift`
     (`AVAssetWriter`, remplace `MediaCodec`+`MediaMuxer`), `Camera/CameraRecorder.swift`
     (orchestrateur équivalent `GPUCameraRecorder`, UN SEUL passage de rendu MetalPetal par frame
     partagé aperçu+export — élimine par construction le risque de divergence que l'architecture
     Android à deux pipelines GL séparés doit gérer manuellement), `Camera/CameraPreviewView.swift`
     (`MTIImageView`, pas un `MTKView` écrit à la main), `Camera/CameraView.swift` (écran SwiftUI).
  5. **Bug trouvé et corrigé avant même un premier build** (relecture propre, comme pour
     `JSONValue.rawData` au module 1) : un premier jet de `CameraView.swift` déléguait
     `CameraRecorderDelegate` à un objet `CameraRecorderCoordinator` recréé à la volée
     (`weak var delegate` sans propriétaire fort) — aurait été désalloué immédiatement après
     `.onAppear`, cassant silencieusement `didFinishRecordingAt`. Corrigé en pilotant l'écran via
     `@Published var lastRecordedURL` sur `CameraRecorder` + `.onChange` côté SwiftUI (forme à UN
     seul paramètre, la cible iOS du projet étant 16 — la forme à deux paramètres `{ old, new in }`
     exige iOS 17).
  **PAS FAIT, honnêtement signalé** (voir tableau "Détail par module" + "Prochaine action à
  faire") : `CircleCaptureButton.java` jamais lu (comportement du bouton de capture
  RECONSTITUÉ, pas vérifié) ; sélecteur galerie et item "Animems" laissés en closures vides ;
  branchement réel dans la navigation (quel écran présente `CameraView`) PAS recherché ;
  `MediaVideoEncoder`/`MediaAudioEncoder`/`MediaMuxerCaptureWrapper` lus seulement pour leurs
  constantes, pas en entier. **Module 7 reste `[ ]` non coché dans "Ordre de portage" — ne pas
  commencer le module 8 avant sa fermeture explicite.**
- **2026-08-10 : Module 7 (Caméra) — REFERMÉ.** Traitement des 6 points laissés ouverts par le
  passage précédent, dans l'ordre demandé :
  1. **`editor/CircleCaptureButton.java` lu en entier (520 lignes).** Confirme un écart réel avec
     la reconstitution précédente : seuil tap/appui-long = **1000 ms exactement**
     (`mHandler.postDelayed(action, 1000)`), pas les `0.35` s utilisés au premier jet. Plus grave :
     le mécanisme SwiftUI utilisé (`.onLongPressGesture(pressing:)`) était impropre par
     construction — son paramètre `pressing` se déclenche dès le toucher, pas après
     `minimumDuration`, donc un tap simple aurait démarré un enregistrement au lieu d'une photo.
     Remplacé par `DragGesture(minimumDistance: 0)` + `DispatchWorkItem` programmé/annulable,
     calqué directement sur `postDelayed`/`removeCallbacks`. Confirmé par analyse de flux que
     `actionListener`/`MINIMUM_VIDEO_DURATION_MILLIS` sont du code mort des deux côtés d'un même
     test (`isRecording` remis à `false` juste avant d'être testé) — rien à porter, pas une
     supposition.
  2. **Point d'entrée réel retrouvé par grep de `CameraActivity.class` (7 lanceurs dans tout le
     dépôt)** : `CameraActivity` est une Activity Android séparée (pas une position
     `HomeActivity.onArticleSelected` comme le supposait une note non vérifiée du premier jet),
     lancée depuis le FAB (`R.id.fab`) de `MainFragment.java` (déjà porté en `FeedView.swift`,
     module 6) via `requestPermission()`. Câblé : FAB ajouté à `FeedView.swift`, vérification
     `AVCaptureDevice.authorizationStatus`/`requestAccess` avant présentation, `.fullScreenCover`
     pour `CameraView`. Les 6 autres lanceurs (modules pas encore portés) non câblés.
  3. **Sélecteur galerie réel écrit** (`Camera/GalleryPickerView.swift`, `PHPickerViewController`
     via `UIViewControllerRepresentable`) après lecture de `pickImageOrVideo`/`pickMedia` —
     filtre image+vidéo, sélection unique, routage image/vidéo reproduit à l'identique vers des
     closures TODO (écrans consommateurs `MediaEditor`/`MediaTrim` pas encore portés).
  4. **"ANIMEMES" confirmé no-op assumé** — commentaire en tête de `CameraView.swift` déjà clair
     sur la raison (module 8 pas commencé à ce stade), rien à changer.
  5. **`MediaVideoEncoder.java`/`MediaAudioEncoder.java`/`MediaMuxerCaptureWrapper.java` relus en
     entier** (pas seulement leurs constantes comme au premier passage) — 2 lacunes trouvées et
     corrigées dans `CameraRecordingWriter.swift` : `KEY_I_FRAME_INTERVAL=3` manquant (ajouté via
     `AVVideoMaxKeyFrameIntervalDurationKey`), garde de monotonicité des horodatages audio
     (`preventAudioPresentationTimeUs`) non reproduite (ajoutée par prudence, `lastAudioPresentation
     Time`, bien que le mécanisme source du problème — PTS Android calculé manuellement sur un
     thread `AudioRecord` séparé — n'ait pas d'équivalent direct côté iOS). La synchronisation à
     deux compteurs `MediaMuxerCaptureWrapper.start()`/`stop()` CONFIRMÉE sans équivalent
     nécessaire (résout un problème spécifique à l'API asynchrone `MediaCodec`/`MediaMuxer`,
     absent avec `AVAssetWriterInput` qui reçoit ses réglages de façon synchrone) — dit
     explicitement dans le tableau plutôt que de ne rien noter, comme demandé.
  6. **Tableau "Détail par module" mis à jour** avec le détail de ces 5 corrections/vérifications
     (nouvelles lignes `CircleCaptureButton.java`, `CameraActivity.java`/`FeedView.swift`,
     `GalleryPickerView.swift`, lignes `CameraRecordingWriter`/`CameraView` révisées). **Module 7
     coché `[x]` dans "Ordre de portage"** — voir décision juste en dessous pour la note honnête
     sur la nature de ce "fermé" (même format que les modules précédents).

  **Enchaînement direct sur le module 8 (Moteur Animems)**, comme demandé explicitement par
  l'utilisateur — pas de pause entre les modules 7 et 12 (Checkpoint 2), voir "Règle de
  compilation par checkpoint" en tête de fichier, point 6.
- **2026-08-10 : Module 8 (Moteur Animems) démarré — PREMIER PASSAGE TRÈS PARTIEL, honnêtement
  signalé comme tel dès maintenant plutôt que de laisser croire à une progression proportionnée
  au reste du module.** Contexte de taille rappelé avant de détailler ce qui est fait :
  `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` chiffre la catégorie A (cœur éditeur) à **≈24 942 lignes
  Android** (confirmées+présumées), estimées **10-13,5 semaines-ingénieur** avec MetalPetal —
  soit, à volume comparable, l'équivalent de 3 à 4 fois le travail cumulé des modules 1 à 7. Ce
  n'est PAS un module qu'un seul passage supplémentaire, même long, peut raisonnablement fermer.
  Fait dans cette session :
  1. Relu `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.1/§3.1 (déjà lu au module 7, reconfirmé pour le
     détail catégorie A) : MetalPetal pour le rendu/masques/blending, `AVVideoCompositing`+
     `AVAssetWriter` natif pour unifier aperçu et export en un seul chemin de rendu (recommandation
     d'architecture forte du rapport — évite le piège de double synchronisation Canvas/GLSL
     qu'Android doit gérer manuellement), timeline/keyframes/modèle de données 100% custom
     (aucune librairie qualifiée trouvée).
  2. Lu en entier les fichiers du système de keyframes, la partie "100% custom" la plus
     directement portable sans dépendre d'abord d'une architecture de rendu Metal pas encore
     conçue : `engine/keyframe/Keyframe.java` (127 lignes), `engine/keyframe/KeyframeTrack.java`
     (158 lignes). Également lus pour contexte (PAS encore portés, trop couplés à
     `Bitmap`/`Matrix`/`Canvas` Android pour être portés avant d'avoir conçu le pipeline de rendu
     Metal du calque) : `core/AnimationObjectData.java` (618 lignes — l'objet "calque" complet :
     masques, tracks de keyframes par propriété, bitmaps/textures avec horodatages, propriétés de
     forme), `core/Transform.java` (110 lignes), `core/Const.java`.
  3. **Écrit** : `Animems/Keyframe.swift`, `Animems/KeyframeTrack.swift` — port direct et complet
     des deux fichiers lus, formules d'easing/lerp/couleurs reproduites à l'identique (voir
     tableau "Détail par module" pour le détail des choix `struct` vs classe et de la
     représentation `[Float]` conservée brute).
  **PAS FAIT, l'écrasante majorité du module** : `AnimationObjectData` (618 lignes, l'objet
  "calque" central — PAS encore porté) ; `AnimemesCompound.java` (3931 lignes, l'orchestrateur
  principal de l'éditeur — PAS encore lu) ; `MemesView2.java` (1978 lignes, rendu Canvas de
  l'aperçu éditable — PAS lu) ; `MP4Encoder.java` (1864 lignes, export GPU — PAS lu) ; tout le
  pipeline de rendu Metal/MetalPetal du calque (masques, blending, feather) — AUCUNE conception
  d'architecture encore faite, contrairement au module 7 où l'architecture MetalPetal avait pu
  être entièrement vérifiée avant l'écriture ; l'intégration `AVVideoCompositing`/`AVAssetWriter`
  pour l'export unifié ; toute l'UI (timeline, panneaux de masque/texte/forme, gestes tactiles).
  **Le module 8 reste `[ ]` non coché** dans "Ordre de portage" — statut "EN COURS" documenté
  explicitement, pas laissé à interprétation.
- **2026-08-10 : Module 8 (Moteur Animems) — deuxième passage, `core/` refermé.** Suite directe du
  premier passage, ordre suivi tel que proposé ("lire `AnimationEngine`/`AnimationComposer`/
  `BitmapCacheManager`/`AnimationUtils` AVANT de porter `AnimationObjectData`") :
  1. Lus en entier : `core/AnimationEngine.java` (398 lignes), `core/AnimationComposer.java`,
     `core/BitmapCacheManager.java`, `core/AnimationUtils.java`, `engine/mask/MaskType.java`,
     `engine/android/mask/MaskFactory.java` (230 lignes).
  2. **Découverte architecturale majeure, vérifiée par grep ciblé de `PorterDuff.Mode` dans
     `MemesView2.java`** (1978 lignes, PAS lu en entier — seul ce grep ciblé) : la compositing des
     calques n'utilise que 3 modes de fusion (`DST_IN`/`SRC_ATOP`/`CLEAR`), tous portables 1:1 en
     `CGBlendMode`. **Conclusion actée : Core Graphics seul suffit pour la compositing calques,
     aperçu ET export — pas besoin de Metal/MetalPetal pour cette partie**, contrairement à la
     lecture initiale de la recommandation `AVVideoCompositing`+MetalPetal du rapport
     `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §2.1. Voir le détail complet et ses implications
     (`glMatrix`/`androidToGL_Matrix2` non portés) dans le tableau "Détail par module".
  3. **Écrit** : `Animems/Transform.swift`, `Animems/AnimationObjectData.swift` (port quasi
     complet des 618 lignes), `Animems/AnimationComposer.swift`, `Animems/AnimationUtils.swift`,
     `Animems/MaskType.swift`, `Animems/MaskFactory.swift`, `Animems/BitmapCacheManager.swift`,
     `Animems/AnimationEngine.swift` — le paquet `core/` Android est maintenant refermé dans son
     ensemble (tous ses fichiers lus et portés), plus seulement le système de keyframes.
  4. **Deux bugs trouvés et corrigés avant tout build** (relecture propre des fichiers venant
     d'être écrits, même discipline qu'aux modules précédents) : (a) collision de nom
     `track(_:)`/`track: Int` dans `AnimationObjectData` (Swift ne peut pas distinguer une méthode
     et une propriété stockée de même nom si le site d'appel ressemble à un appel de fonction sur
     la propriété) — renommée `keyframeTrack(_:)` ; (b) `AnimationUtils.makeMessengerLikeBackground`
     convertissait un `Float` potentiellement hors-borne en `UInt32` sans clamp préalable — un
     `UInt32(valeurNégative)` PROVOQUE UN CRASH en Swift (contrairement à un `int` Java hors-borne,
     silencieusement "wrappé") — clamp déplacé avant la conversion.
  **PAS ENCORE FAIT** : `AnimemesCompound.java` (3931 lignes, l'orchestrateur principal — pas lu),
  `MemesView2.java` (lu seulement par grep ciblé sur `PorterDuff.Mode`, pas en entier — le rendu
  Core Graphics réel du calque, masques appliqués aux bitmaps, texte, formes, reste à porter),
  `MP4Encoder.java` (export, pas lu), `AVAssetWriter`/pipeline d'export, TOUTE l'UI (timeline,
  panneaux, gestes). Module 8 toujours `[ ]` non coché.
- **2026-08-11 : Module 8 — troisième passage : modèle de données restant porté, `AnimemesCompound.java`
  entamé (≈1300/3931 lignes lues), et surtout PÉRIMÈTRE RÉEL DU RESTE DU MODULE PRÉCISÉ par
  lecture directe (pas ré-estimé depuis le rapport de faisabilité seul).**
  1. Lus et portés en entier (petits fichiers) : `model/TimelineItem.java`, `StickerData.java`,
     `PlaylistEntry.java`, `DrawPathFrameData.java`, `SerializableAnimationObject.java` (+
     `Utils/BitmapUtils.java`, ciblé, pour confirmer le format base64 PNG). Revérifié contre la
     déclaration réelle : les 11 cas de `AnimationObjectData.Type` (`core/AnimationObjectData.java:
     21-23`) correspondaient EXACTEMENT aux 11 cas Swift déjà écrits au passage précédent
     (`ObjectType`) — confirmation a posteriori, pas une coïncidence qu'il fallait laisser non
     vérifiée.
  2. **Lu ≈1300 lignes de `AnimemesCompound.java` (sur 3931), par tranches.** Confirme que cette
     classe est un `FrameLayout` Android qui mélange ÉTROITEMENT l'état du modèle d'animation
     (`AnimationComposer`/`AnimationObjectData`) ET la construction/le câblage de dizaines de vues
     custom via `findViewById`/`new XxxPanel(...)` — PAS un contrôleur de données isolable
     mécaniquement de l'UI. `init()` (≈330 lignes) est entièrement du binding de layout XML
     (`R.layout.compound_animemes_layout`) sans logique portable. Repéré et lu en partie les
     méthodes à plus forte valeur logique : `buildMaskBitmap` (résolution du type de masque/couleur
     depuis le `label` texte du calque), `applyPropertiesToLayerForPreview`/
     `validateAndCreateKeyframe` (création de keyframes opacity/color/cornerRadius/feather/mask*
     au relâchement d'un slider d'édition), `addShapeFromData`/`addMaskFromBitmap` (création de
     calque depuis les panneaux forme/masque), `showMaskPreviewEditor` (câblage bidirectionnel
     avec `MaskEditController`/`MaskPreviewEditorPanel` pour l'édition interactive d'un masque).
  3. **Vérifié que les fichiers `.xml` de layout référencés existent bel et bien et sont lisibles**
     (`engine/src/main/res/layout/compound_animemes_layout.xml`, confirmé par recherche de
     fichier) — donc un futur portage de l'UI n'exigerait PAS d'inventer une disposition d'écran :
     la vraie disposition Android peut être lue et reproduite fidèlement, comme pour tout le reste
     de ce portage. Important à noter : ce n'est PAS parce que cette voie est ouverte que l'UI a
     été portée maintenant — seulement que rien ne bloque structurellement de le faire plus tard.
  4. **Périmètre réel du reste du module 8, maintenant précisé (pas juste le chiffrage global du
     rapport de faisabilité)** : au-delà d'`AnimemesCompound.java` lui-même, la logique repérée
     dépend d'au moins ~10 CLASSES DE VUE CUSTOM DISTINCTES, chacune avec son propre fichier
     `.java` ET son propre layout `.xml`, AUCUNE encore lue : `MaskAddPanel`,
     `MaskPreviewEditorPanel`, `MaskEditController`, `ShapeAddPanel`, `ShapePreviewEditorPanel`,
     `LayerEditorPanel`, `TimelineView`, `MovementControllerHandlerView`, `ProTextEditorView`,
     `BezierEditorView`, `CanvasZoomController`, `PaintPreviewEditorPanel`, `ShapeFactory`,
     `FrameAdapter`. Chacune est vraisemblablement un fichier de taille comparable aux vues déjà
     portées ailleurs dans ce projet (quelques centaines de lignes) — ce n'est PAS un détail
     mineur mais une composante substantielle et jusqu'ici sous-estimée du travail restant, en
     plus de `MemesView2.java` (1978 lignes, rendu) et `MP4Encoder.java` (1864 lignes, export)
     déjà identifiés. **Honnêtement signalé plutôt que rush-porté avec un niveau de vérification
     inférieur au reste de ce projet** : continuer à ce rythme (lecture intégrale avant portage,
     vérification des API tierces, documentation de chaque décision) sur un périmètre de cette
     taille dépasse largement ce qu'une seule session supplémentaire peut couvrir avec la même
     rigueur que les modules 1-7. Module 8 reste `[ ]` non coché ; modules 9-12 PAS commencés —
     aucune ligne de ce fichier ne doit laisser croire le contraire.
- **2026-08-11 : Module 8 — quatrième passage : logique réutilisable extraite d'`AnimemesCompound.java`
  (lecture poussée à ≈2600/3931 lignes) + PREMIER RENDU RÉEL ÉCRIT (`LayerRenderer.swift`), la
  pièce la plus significative du module à ce jour.**
  1. **`AnimemesCompound.java` continué de la ligne ~1300 à ~2600** : `captureTransformKeyframe`,
     `testTimeLine`/callbacks `TimelineView` (`onSelectionChanged`/`onItemChanged`/
     `onItemResizeRightEnd`/`resampleTransforms`/`resampleMaskTransforms`/`onTrackIconClicked`),
     `addToTimeline`/`duplicateTimeline`, `initView`, `onClick` (≈300 lignes, lu en entier),
     `addBitmapFromGallerie`/`onNewAddBitmap`/`fitBitmapIntoSize`/`onNewAddBitmaps`/`addBitmaps`/
     `add`/`addBitmap`, `addPictureBackground`/`onNewBackgroundPicture`/`onRepeateImage`,
     `isAnimation`/`saveBitmapDrawed`/`fromBitmapsToVideo`/`createImage`/début de
     `createVideosFromBitmap`. **Confirmé par lecture exhaustive** (pas par échantillonnage) :
     `initView`/`onClick` sont ENTIÈREMENT du câblage de widgets Android (visibilité, couleurs,
     état "selected") sans aucune logique de données extractible — rien à porter de ces deux
     méthodes tant que l'écran SwiftUI équivalent n'est pas conçu.
  2. **Deux fonctions PURES, sans dépendance sur la hiérarchie de vues, identifiées et portées** :
     `resampleTransforms`/`resampleMaskTransforms` (ré-échantillonnage linéaire d'un tableau de
     `Transform`, voir tableau) et `fitBitmapIntoSize` (redimensionnement aspect-fit, voir
     tableau) — seule logique d'`AnimemesCompound.java` jugée sûre à porter isolément à ce stade,
     le reste dépendant de classes pas encore lues (`TimelineView`, `MaskPreviewEditorPanel`,
     `ShapeFactory`, `BitmapManager`, `MP4Encoder`, `CroperView`...).
  3. **Lu en détail `engine/android/memes/MemesView2.java`** (pas en entier — ciblé sur `onDraw`/
     `drawBitmapLastTransform`/`drawObjectFrame`, ~350 des 1978 lignes, la partie directement
     nécessaire pour un premier rendu réel des types BITMAP/SHAPE) — **écrit `LayerRenderer.swift`**,
     voir détail complet dans le tableau "Détail par module". C'est la première fois depuis le
     début du module 8 qu'un vrai PIXEL sera affiché à l'écran si ce code compile et s'exécute —
     tout ce qui précédait (keyframes, moteur, modèle de données) était de la plomberie sans sortie
     visuelle.
  4. **Trois bugs trouvés et corrigés AVANT tout build** (relecture propre du fichier venant
     d'être écrit, même discipline que les passages précédents) : (a) calcul de marge de flou
     ("margin") initialement écrit comme une expression sans queue ni tête
     (`bmpToDraw.width - 0`) — corrigé en faisant réellement transiter `featherPx` (le rayon de
     flou en points) jusqu'au point de calcul, au lieu de tenter de le reconstituer depuis la
     taille de l'image déjà floutée ; (b) **une vraie différence de comportement Android entre
     `drawBitmapLastTransform` et `drawObjectFrame` (repli du rayon de bulle de fond à 10 quand
     `cornerRadius<=0`, présent dans l'un, absent dans l'autre) accidentellement EFFACÉE en
     factorisant les deux méthodes en un seul helper commun** — retrouvée en comparant à nouveau
     ligne à ligne le code Android des deux méthodes, corrigée en passant un `bubbleRadius:
     CGFloat?` calculé différemment aux deux sites d'appel plutôt qu'un seul `cornerRadius`
     partagé ; (c) risque de double-application de l'opacité d'un calque à travers deux couches de
     transparence Core Graphics imbriquées (masque + teinte) — identifié PAR ANALYSE, pas
     rencontré à l'exécution (impossible à observer sans simulateur), neutralisé par
     réinitialisation explicite de l'alpha à 1 à l'entrée de la couche imbriquée.
  **PAS ENCORE FAIT** : rendu `TEXT`/`PATH`/`LINE`/`CLIP`/`ERASE`/`STICKER` (chacun sa propre
  méthode dans `MemesView2.java`, pas lues), `recomposeObjects` (fusion GIF), le reste
  d'`AnimemesCompound.java` (~1300 lignes restantes : gestes tactiles probablement dans
  `MemesView2.java` plutôt qu'ici, fin de `createVideosFromBitmap`, dialogues de sauvegarde,
  tutoriel, recompose/groupes), `MP4Encoder.java` (export, pas lu), les ~10 vues custom
  dépendantes (aucune encore lue). Module 8 toujours `[ ]` non coché.
- **2026-08-11 : Module 8 — cinquième passage : TEXT/STICKER portés, PATH/LINE/CLIP/ERASE
  explicitement écartés (décision motivée), et l'EXPORT MP4 conçu et écrit
  (`AnimemesExporter.swift`) — module 8 a maintenant un chemin complet bout-en-bout (modèle →
  rendu → export), même si chaque maillon reste partiel sur les détails.**
  1. Lus en entier : `android/renderer/TextRect.java`, `Utils/TextLayoutEngine.java` (moteur de
     découpage de texte "100% pur, compatible KMP à terme" selon son propre commentaire — un
     candidat idéal de portage direct). Lues ciblées : `MemesView2.writeText`/`drawShap` (TEXT/
     STICKER, données par calque) — `drawPath`/`drawLine`/`clipPath`/`erase` également lues mais
     NON portées : confirmé que ce sont les rendus du GESTE DE DESSIN LIBRE EN COURS (état de
     CLASSE, pas de calque persistant), et que `clipPath` a un corps Android VIDE (`{}`,
     confirmé mort). Porter leur rendu avant que la capture tactile elle-même soit conçue serait
     prématuré — décision documentée, pas un report silencieux.
  2. **Écrit** : `Animems/TextLayoutEngine.swift` (port fidèle EN UNITÉS UTF-16, pas
     `String.Index`, pour préserver exactement la sémantique d'indexation Java y compris sur les
     emoji/caractères hors plan de base), `Animems/TextRect.swift` (rendu Core Graphics, piège de
     signe évité entre `UIFont.descender` NÉGATIF et `metrics.descent` Android POSITIF),
     `Animems/LayerRenderer.swift` étendu (`drawText`/`drawSticker`).
  3. **Un bug de mesure trouvé et corrigé avant tout build** dans `drawText` (relecture propre) :
     un premier jet mesurait la largeur du caractère `"i"` au lieu du TEXTE RÉEL du calque pour
     calculer `bubbleElementWidth` — sans rapport avec la vraie formule Android
     (`fontPaint.measureText(element.getText())`). Corrigé en ajoutant `TextRect.measureWidth(_:)`
     et en respectant l'ordre exact de l'original (mesure AVANT le retour à la ligne, PUIS
     `bubbleWidth = min(bubbleElementWidth, bubbleWidthMax)` utilisé comme largeur de wrap).
  4. **Lu `android/codec/MP4Encoder.java` (structure complète, ~450 lignes ciblées) +
     `android/codec/Encoder.java` (478 lignes, en entier)** pour identifier le chemin RÉELLEMENT
     exercé — confirmé en retournant lire la suite d'`AnimemesCompound.createVideosFromBitmap`
     (jusqu'à la ligne 2645) que le flux réel est `onSurfaceStartEncode()`→`addFrame(composer)`→
     `startFrameEncoding()`→`onAddFrame`, PAS les 3 AUTRES modes que `Encoder.java` propose
     (bitmap-par-bitmap, byte-par-byte, "outro vidéo") — ceux-ci confirmés non exercés par cette
     app à ce stade, non portés à raison. `onAddFrame` recalcule EXACTEMENT la même table de
     frames que `AnimationEngine.prepareFrame` (déjà porté au passage 2) — confirmé en comparant
     les deux algorithmes ligne à ligne, pas une supposition de similarité.
  5. **Décision motivée de NE PAS relire en détail les ~1400 lignes GLSL/`MediaCodec` restantes**
     (shaders `FRAGMENT_BASE`/`FRAGMENT_MASK_DST_IN`, init EGL/FBO, `transcodeToM4A`) — justifiée
     précisément dans `AnimemesExporter.swift` : les shaders sont une réécriture GPU du MÊME
     algorithme déjà lu et porté depuis `MemesView2.java` (leurs propres commentaires Android le
     confirment explicitement, "SYNCHRONISÉ AVEC MemesView2") ; le pipeline `MediaCodec`/EGL bas
     niveau n'a pas de primitive à répliquer face à l'API haut niveau `AVAssetWriter` ; le
     transcodage audio manuel (avec son historique de 3 bugs documentés dans les commentaires
     Android) est une capacité NATIVE d'`AVAssetReader`/`AVAssetWriterInput` côté iOS, pas un
     besoin réel à reproduire.
  6. **Écrit `Animems/AnimemesExporter.swift`** — export via `AVAssetWriter`+
     `AVAssetWriterInputPixelBufferAdaptor` (vidéo) + `AVAssetReader`+`AVAssetWriterInput` (audio,
     remux), réutilisant `AnimationEngine.prepare`/`LayerRenderer` déjà portés — le rendu aperçu
     ET export partagent maintenant RÉELLEMENT le même code, la possibilité annoncée dès la
     décision d'architecture Core Graphics du passage 2.
  7. **Un bug sérieux trouvé et corrigé avant tout build** (relecture propre, comme
     systématiquement à ce stade du portage) : le compteur de frame de la boucle d'écriture vidéo
     était initialement une variable LOCALE À LA CLOSURE passée à
     `AVAssetWriterInput.requestMediaDataWhenReady` — cette closure étant RAPPELÉE par le système
     à chaque fois que l'input redevient prêt à recevoir des données (pas un appel unique), le
     compteur aurait été réinitialisé à zéro à CHAQUE reprise, ré-écrivant les mêmes frames en
     boucle au lieu de continuer la vidéo. Corrigé en déclarant le compteur dans la portée
     englobante de la fonction (capturé par référence par la closure Swift, qui partage la même
     case mémoire entre tous ses appels) plutôt que passé en paramètre d'une sous-fonction.
  **PAS ENCORE FAIT** : `recomposeObjects`/`computeRecomposeBounds` (fusion GIF, pas lu en
  détail) ; le reste d'`AnimemesCompound.java` (~1300 lignes : dialogues de sauvegarde, tutoriel,
  recompose/groupes, IA, suppression de fond) ; les ~10 vues custom UI dépendantes (aucune lue) ;
  vérification des valeurs de retour `Bool` de `append`/`startWriting` dans l'export (gestion
  d'erreur incomplète assumée pour ce premier passage). Module 8 toujours `[ ]` non coché.
- **2026-08-11 : Module 8 — sixième et dernier passage : GESTES TACTILES conçus/portés, lecture
  intégrale d'`AnimemesCompound.java` terminée (3931/3931 lignes), `recomposeObjects` porté,
  ~14 vues custom lues et portées (logique d'état) ou documentées comme non portables tel quel —
  MODULE 8 FERMÉ.**
  1. **`Animems/AnimemesGestureController.swift`** — port de `MemesView2.java` : `GestureListener`/
     `ScaleListener`/`onTouchEvent`/`touchDown`/`touchMove`/`touchUp`/`translation`/`rotate`/
     `scale`/`safePostScale`/`isPointInsideObject`/`bringLayerToFront`/`touchPointerDown/Up` (tous
     lus en entier). Logique de transformation séparée délibérément du câblage de gestes SwiftUI
     (`DragGesture`/`MagnificationGesture`/`RotationGesture`, pas encore écrit) — voir tableau pour
     le détail complet, y compris les 2 bugs sérieux trouvés et corrigés avant tout build
     (`CGAffineTransform.inverted()` non-optionnelle ; piège d'ordre de composition
     pré/post-multiplication). Mode d'édition de masque par geste (`handleMaskEditTouch` etc.) lu
     mais non porté — différé.
  2. **Fin de lecture d'`AnimemesCompound.java`** (lignes ~2645-3931, dernière tranche de ~1300
     lignes) — dialogues de sauvegarde, tutoriel `TapTargetSequence`, section ANIMATE
     (`MotionGenerator`), section RECOMPOSE (`getRecomposeCandidates`/`computeDefaultTotalFrames`/
     `performRecompose`, confirmant le point d'entrée réel de `recomposeObjects`), section AI
     GENERATE (`AIObjectGenerationDelegate`), section REMOVE BACKGROUND (`RemoveBackground`/ML
     Kit), vue groupe recompose (`enterGroupView`/`exitGroupView`/`syncVisibilityIcon`). **6
     sous-systèmes secondaires découverts, explicitement NON lus en détail ni portés** (Motion
     Templates, persistance disque du recompose, tutoriel, génération de mouvement, génération IA,
     suppression d'arrière-plan) — voir la ligne dédiée du tableau "Détail par module" pour le
     détail complet de chacun et sa justification. Ce sont des fonctionnalités ADDITIVES posées
     sur le cœur éditeur déjà fonctionnel (modèle→gestes→rendu→export), pas des lacunes dans le
     cœur lui-même.
  3. **`Animems/AnimemesRecompose.swift`** — port de `MemesView2.recomposeObjects`/
     `computeRecomposeBounds` (lus au passage précédent) + de la portion logique pure
     (candidats/bornes/construction du calque résultat) de `AnimemesCompound.performRecompose`
     (lu cette passe). Réutilise `LayerRenderer.drawObjectFrame`, exactement la réutilisation
     anticipée lors de l'écriture d'`AnimemesExporter.swift`.
  4. **~14 vues custom lues intégralement, chacune traitée individuellement** (voir tableau pour
     le détail par fichier) : `ShapeFactory.java` (rasterisation, porté EN ENTIER) ;
     `BezierEditorView.java`/`PaintPreviewEditorPanel.java` (auto-contenus, portés EN ENTIER
     modèle+rendu+gestes SwiftUI, comme `Keyframe`/`Transform` en leur temps) ;
     `LayerEditorPanel.java`/`MaskPreviewEditorPanel.java`/`ShapePreviewEditorPanel.java`/
     `MovementControllerHandlerView.java`/`ProTextEditorView.java` (logique d'ÉTAT seule portée,
     construction de vue Android non 1:1 transposable, SwiftUI différée jusqu'à disposer d'un
     contexte de sélection de calque réel) ; `CanvasZoomController.java` (auto-contenu, porté EN
     ENTIER) ; `TimelineView.java` (1320 lignes, la plus volumineuse — logique de coordonnées/
     zoom/pan/drag/anti-chevauchement/hit-test portée intégralement dans
     `TimelineViewModel.swift`, rendu `Canvas`/gestes SwiftUI différés) ; `FrameAdapter.java`
     (**découverte** : sous-système de capture flipbook entièrement SÉPARÉ de l'`AnimationEngine`,
     dépendant de 4 classes non lues — seule la logique de gestion de liste portée) ;
     `MaskAddPanel.java`/`ShapeAddPanel.java` (pickers purs, aucun contenu portable au-delà des
     enums déjà existants, non portés) ; `MaskEditController.java` (protocoles purs, port direct).
  5. **Aucun nouveau bug de compilation anticipé trouvé cette passe** au-delà de vérifications de
     signature croisées (types/noms de propriété `AnimationObjectData` confirmés existants avant
     chaque usage dans les nouveaux fichiers, pattern déjà systématique aux passages précédents).
  **Module 8 marqué `[x]` FERMÉ** — voir "Ordre de portage" et tableau pour la note honnête sur la
  nature de cette clôture (PARTIEL ASSUMÉ, comme les modules 1-7). **ARRÊT DEMANDÉ EXPLICITEMENT
  PAR L'UTILISATEUR** : ne pas commencer le module 9 avant confirmation de build Codemagic réussi
  (couvrant modules 7+8) ou liste d'erreurs à corriger.
- **2026-08-11 : Module 9 (Éditeur photo simple) démarré après validation du Checkpoint 2 —
  décisions d'architecture actées, infrastructure de recadrage/suppression d'arrière-plan écrite,
  écran d'édition principal explicitement différé.**
  1. **Périmètre établi par lecture réelle des rapports** (`TIINVER_IOS_PORT_ANALYSIS.md`,
     `TIINVER_ANIMEMS_SCOPE_LIBRARIES.md` §1.3/§2.3/§3) — catégorie G, ≈14 117 lignes Android. Fichiers
     identifiés et localisés : `android/croper/**` (16 fichiers, recadreur), `android/croper/
     imageprocessing/**` (9 fichiers, CV maison), `ImageEditorCompound.java`/`ImageViewCanvas.java`
     (écran principal), `CroperView.java`, `Utils/RemoveBackground.java`, `MediaEditor.java`
     (point d'entrée, hors `engine/`, trouvé dans `app/src/main/java/com/tiinver/editor/media/`).
  2. **Découverte structurante en lisant `CropWindowHandler.java`** : c'est la librairie tierce
     vendorisée "Android-Image-Cropper" (signature reconnue : en-tête de licence + citation Sun
     Tzu caractéristique), pas du code métier Tiinver — décision de la remplacer par une librairie
     iOS équivalente plutôt que de porter ~5000 lignes de géométrie de poignées tactiles
     génériques, même raisonnement "buy vs build" déjà appliqué à MetalPetal (module 7/8).
     `TOCropViewController` choisi et VÉRIFIÉ avant adoption (pas deviné) : `curl` direct sur l'API
     GitHub (`pushed_at`, `stargazers_count`, `archived`) et sur le `Package.swift`/le fichier
     source Swift réels au tag figé `3.2.0` (pas la branche `main`, pour la reproductibilité du
     build) — version initialement notée `2.7.0` corrigée en `3.2.0` après vérification des tags
     réels via l'API GitHub (`git tag`/`curl .../tags`), pas laissée comme une supposition.
  3. **Vision framework vérifié avant adoption** (WebSearch, plusieurs requêtes ciblées, pas une
     seule recherche superficielle) : confirmé que `VNGenerateForegroundInstanceMaskRequest`
     (équivalent le plus proche du `SubjectSegmenter` ML Kit Android, sujet général) est iOS 17+
     UNIQUEMENT et ne fonctionne pas en simulateur — incompatible avec `deploymentTarget.iOS=16.0`
     de ce projet. `VNGeneratePersonSegmentationRequest` (iOS 15+, compatible) retenu à la place,
     avec un écart fonctionnel réel documenté (personnes uniquement, pas un sujet général) plutôt
     que masqué. Polarité du masque (blanc=sujet/noir=fond) et propriétés réelles
     (`qualityLevel`/`outputPixelFormat`/`VNPixelBufferObservation.pixelBuffer`) vérifiées par
     recherche avant d'écrire `CIBlendWithMask`, pas supposées par analogie avec ML Kit.
  4. **Écrit** : `PhotoEditor/RemoveBackground.swift` (Vision + repli géométrique fidèle à
     `removeBackgroundAdvanced`/`applyEdgeRefinement`, bug de pré-multiplication anticipé et évité
     par construction — voir tableau), `PhotoEditor/FreeformCropView.swift` (port complet, seul
     mode non couvert par `TOCropViewController`), `PhotoEditor/PhotoCropUtils.swift`
     (`toOvalBitmap`), `PhotoEditor/PhotoCropView.swift` (wrapper `UIViewControllerRepresentable`),
     `PhotoEditor/PhotoEditorState.swift` (orchestration). `project.yml` : package
     `TOCropViewController` ajouté.
  5. **Confirmés morts par grep, non portés** : `CroperView.removeBackground` (tolérance de
     couleur statique, zéro appelant) ; `android/croper/BackgroungRemover.java` (578 lignes,
     pipeline CV maison, zéro instanciation) — ce dernier étant le seul consommateur
     d'`imageprocessing/**`, ce pipeline entier n'était même plus atteignable en pratique côté
     Android, au-delà de la simple recommandation de le remplacer.
  6. **Décision honnête de portée, pas un oubli** : `ImageEditorCompound.java` (1132 lignes, lu
     seulement ~280 lignes — constructeurs/`init`/`setImageUri`) et `ImageViewCanvas.java` (2037
     lignes, PAS lu, imports seulement vérifiés) — l'écran d'édition principal — confirmés
     réutiliser le MÊME modèle `AnimationComposer`/`AnimationObjectData`/`Transform` que le module
     8 (déjà porté), mais nécessitent le même traitement multi-passage méthodique que
     `MemesView2.java`/`AnimemesCompound.java` en leur temps plutôt qu'une lecture rushée pour
     tenir le rythme des modules 10-12 demandé par l'utilisateur — reporté à une passe dédiée
     future, documenté explicitement plutôt que silencieusement absorbé dans une clôture de module
     optimiste. Module 9 marqué `[x]` avec cette réserve honnête (voir "Ordre de portage").
- **2026-08-11 : Module 10 (Trim/Timeline/Waveform) fermé — géométrie de trim portée en entier,
  export vidéo différé (décision d'architecture AVFoundation).**
  1. Périmètre établi par lecture du rapport (`TIINVER_IOS_PORT_ANALYSIS.md` §2.2/§3.7) + grep de
     vérification des fichiers actifs vs morts — confirmé que le cluster "v2" (`SimpleTrimmer`/
     `VideoTrimmerViewV2`/etc.) est MORT (non déclaré au manifest), contrairement à l'hypothèse
     initiale du rapport lui-même qui le supposait être le système "moderne" actif.
  2. **Découverte de reclassement** : `WaveformSeekBar.java` (cité comme risque élevé du module
     10 par le rapport de faisabilité) confirmé par grep appartenir au module 11 (consommateurs =
     bulles de message vocal du chat, pas le trimmer) — signalé, pas déplacé silencieusement dans
     le rapport source, juste documenté correctement ici.
  3. **Écrit** : `Media/ProTimelineViewModel.swift` (port intégral de la logique pure de
     `ProTimelineView.java`, 763 lignes lues en entier — coordonnées à deux espaces, gestion
     tactile complète des poignées/scroll/déplacement de fenêtre), `Media/VideoTrimState.swift`
     (état rotation/flip/ratio).
  4. **Décision d'architecture, pas un port** : export vidéo (trim/rotation/recadrage) via
     `AVAssetExportSession`+`AVMutableComposition`/`AVMutableVideoComposition` natifs plutôt que le
     pipeline `VideoTransformer`/MediaCodec Android — non écrit cette passe (seul l'état est
     porté), à vérifier contre la documentation Apple réelle au moment de l'écrire, comme
     TOCropViewController/Vision l'ont été au module 9. Extraction de vignettes différée de la même
     façon vers `AVAssetImageGenerator`.
  **PAS FAIT, honnêtement signalé** : `CropOverlayView.java` (398 lignes, recadrage vidéo pendant
  le trim, distinct de la version photo déjà remplacée par TOCropViewController) pas lu ;
  `VideoTrimmerView.java` lu seulement ~140/1138 lignes (câblage `ExoPlayer`/export pas encore
  lu) ; export AVFoundation lui-même pas écrit. Module 10 marqué `[x]` avec cette réserve.
- **2026-08-11 : Module 11 (Messagerie/Chat UI) — pièce tangentielle portée
  (`WaveformSeekBar.swift`), module explicitement PAS fermé, décision honnête de ne pas rusher.**
  1. Périmètre établi par lecture de `TIINVER_IOS_PORT_ANALYSIS.md` §3.5 : **32 398 lignes au
     total, le plus gros module du projet** — `ChatFragmentTest.java` (3080 lignes),
     `ChatManager.java` (1508), `adapter/MessageListAdapter.java` (1353), `FragmentPbs.java`
     (810), `call/CallActivity.java` (592), `call/IncomingCallActivity.java` (534), + 7
     `ViewHolder` par type de message (audio/GIF/vidéo/sticker/photo/graphic/texte/appel manqué).
     Comparable ou supérieur en volume au module 8 (Animems), qui a nécessité 6 passages de
     lecture/portage dédiés répartis sur plusieurs sessions avant d'être raisonnablement fermé.
  2. **`WaveformSeekBar.java` (739 lignes, lu ~250 lignes — la partie algorithmique) porté** :
     bibliothèque tierce vendorisée confirmée (`massoudss/waveformSeekBar`), algorithme de
     disposition des barres compact, portage direct plus simple qu'une nouvelle dépendance SPM
     pour ce besoin précis — voir tableau détaillé.
  3. **Décision explicite de NE PAS continuer à "fermer" le module 11 au même rythme que les
     modules 7-10** : contrairement à ces modules (chacun de taille comparable ou inférieure à ce
     qui a pu être lu/vérifié sérieusement dans le temps disponible d'une passe), le module 11
     dépasse largement ce qu'une lecture superficielle peut honnêtement couvrir — le tenter aurait
     signifié soit (a) deviner l'architecture de `ChatManager`/`MessageListAdapter` sans les avoir
     lus (violerait directement la méthodologie du projet : "lire avant de porter, ne jamais
     deviner"), soit (b) marquer le module `[x]` avec une réserve si large qu'elle serait
     trompeuse plutôt qu'honnête. **Module 11 laissé `[ ]` non coché**, contrairement aux modules
     7-10 — c'est la représentation fidèle de son état réel, pas un report silencieux.
  4. **Ce qui EST déjà en place pour ce module, sans travail supplémentaire** : l'infrastructure
     réseau temps réel (`Realtime/TiinverSocket.swift`/`SocketEvent.swift`, module 1) et le
     stockage local du roster/messages (`Storage/RosterRepository.swift`, module 2) — le rapport
     de faisabilité confirme que le contrat réseau (Socket.IO, noms d'événements `CALL`/
     `ACCEPT_CALL`/etc.) est directement réutilisable, et que le modèle de message JSON l'est
     aussi comme `Codable` Swift. Le travail réel restant est surtout la couche UI (liste de
     conversation multi-types, écran de chat, gestion d'état) — pas l'infrastructure de base.
- **2026-08-12 : Module 11 — couche protocole/persistance/routage (la "moitié backend" du module)
  ENTIÈREMENT portée et vérifiée, module TOUJOURS PAS fermé (couche UI intacte, voir ci-dessous).**
  Lecture méthodique fichier par fichier comme demandé, en commençant par `ChatManager.java` :
  `ChatManager.java` (1508 lignes, lu en quasi-totalité), `messagerie/repository/ChatRepository.java`
  (1124 lignes, lu en entier — 2 passes, une première fois pour les listeners/routage, une seconde
  pour la section "ÉMISSIONS SOCKET" lignes 955-994), `models/chat/MessageLib.java` (929),
  `models/chat/MessagePacket.java` (1016), `roster/RosterManager.java` (234, lu en entier),
  `messagerie/ui/ConversationIdGenerator.java` (34), `engine/model/Profile.java` (213),
  `ChatModel`/`PresenceModel`/`TypingModel`/`MessageStatusModel`/`CallModel` (87+22+22+31+44).
  9 fichiers Swift écrits/étendus — voir tableau détaillé pour le détail complet par fichier. Points
  saillants, tous vérifiés contre la source réelle (pas devinés) :
  1. **Bug `SocketEvent.swift` du module 1 trouvé et corrigé** : valeurs de constantes Java au lieu
     des vraies chaînes de fil (`"CALL"` au lieu de `"call"` etc.) — aurait rendu chat ET appels
     silencieusement non fonctionnels avec le vrai serveur.
  2. **Double encodage JSON découvert dans `MessagePacket`** : l'enveloppe socket contient un champ
     `"packet"` dont la valeur est elle-même un document JSON sérialisé en chaîne, construit par 20
     méthodes Android quasi identiques — consolidées en une fonction paramétrée unique, vérifiée
     champ par champ. Bug de guillemets sur `image_byte` (littéral tableau/`null` non-quoté dans la
     concaténation Android) évité en construisant un vrai `[Int]`/`NSNull` plutôt qu'une `String`.
  3. **`wk_gp_messages`/`GroupMessageEntity` (module 2) confirmée table MORTE** par grep exhaustif —
     `addGroupMessage` écrit en réalité dans `wk_messages` (même table que les messages privés,
     différenciés par `type`). Résout la lacune précédemment documentée ("groupe non persisté") :
     ce n'était pas un travail restant, c'était une hypothèse de table erronée.
  4. **Bug de code mort Android identifié par analyse de flot de contrôle** dans `addMessage` (la
     branche `deletemessage` sur message déjà existant est inatteignable, double négation
     contradictoire) — délibérément PAS reproduite comme "atteignable" dans le port Swift (une
     première ébauche l'avait fait, corrigée après relecture attentive).
  5. **2 bugs trouvés et corrigés DANS CE PORTAGE MÊME** (pas dans l'original Android) en relisant
     la section "ÉMISSIONS SOCKET" de `ChatRepository.java` ligne par ligne après une première
     ébauche : `updateGroupMessage` émettait la mauvaise enveloppe (`packetForGroupJSON` au lieu de
     `packetJSON`, l'original lui-même utilise l'enveloppe privée ici — incohérence Android
     reproduite fidèlement une fois corrigée) ; `deletePrivateMessage` émettait sur le mauvais nom
     d'événement (`"delete private message"` au lieu de `"on delete private message"`, deux
     constantes `ROOM.*` distinctes confondues).
  6. **Listener `offlineStatus` manquant ajouté** : découvert en vérifiant que TOUS les `.on(...)` de
     `registerAllListeners` avaient un équivalent Swift — cet événement a un double rôle (émis à la
     connexion ET écouté pour un lot de statuts de livraison accumulés hors-ligne), la partie
     "écoute" avait été omise dans la première ébauche de ce fichier.
  7. **Champs `lucrative`/`price`/`belongsToCurrentUser` ajoutés à `MessageLib.swift` après coup** —
     absents du premier passage triple-recoupement (ils ne recoupent QUE le mapping `RosterManager`,
     pas les 2 autres sources utilisées pour établir le périmètre initial de `MessageLib`).
  8. **Vérifié contre la source réelle Socket.IO-Client-Swift** (`SocketTypes.swift`,
     `SocketExtensions.swift`, récupérés depuis le dépôt GitHub) que `Dictionary` conforme à
     `SocketData` via une extension inconditionnelle — confirme que `socket.emit(_:[String:Any])`
     utilisé partout dans `ChatRepository.swift` est valide, pas une supposition.
  **PAS fait cette session, honnêtement** : la couche UI (`MessageListAdapter.java` + 1353 lignes +
  7 `ViewHolder` par type de message, `ChatFragmentTest.java` 3080 lignes) — repérée mais PAS lue.
  `getMessageModelFromJSONData`/`getSpecifiqueMessage`/`prepareMessage`/`prepareGroupMessage`
  (`ChatManager.java`) confirmées être des utilitaires consommés par la couche UI non encore lue
  (`prepareMessage`/`prepareGroupMessage` en particulier confirmées NON appelées par le chemin de
  réception socket réel — code mort ou chemin de secours REST, pas creusé plus loin faute de
  contexte utilisateur). Module 11 reste `[ ]` non fermé — voir "Prochaine action à faire".
- **2026-08-12 (suite, même session) : Module 11 — couche UI portée, MODULE FERMÉ.** Lecture
  méthodique de `MessageListAdapter.java` (1353 lignes, entier), ses 9 `ViewHolder` (1328 lignes au
  total, tous entiers : `TextViewHolder`/`MessageAudioViewHolder`/`MessagePhotoViewHolder`/
  `MessageVideoViewHolder`/`MessageStickerViewHolder`/`MessageGifViewHolder`/`MessageGiftViewHolder`/
  `GraphicMessageViewHolder`/`MissedViewHolder`), `models/chat/MessageType.java`, les interfaces
  `MessageActionListener`/`QuoteClickListener`/`MessageViewItemClikedListener`/
  `LoadMoreDataListener`/`layout/ResultData.java`, `view/gift/GiftBadgeView.java`+
  `models/activity/comments/GiftCatalogHelper.java` (catalogue cadeau), `models/roster/
  RosterModel.java`, `Utils/StringUtils.java` (formatage date/heure), puis `ChatFragmentTest.java`
  (3080 lignes, entier, en ~10 passages de lecture séquentiels). 7 fichiers Swift nouveaux/étendus :
  `Messagerie/ChatListItem.swift`, `Messagerie/ChatBubbleViews.swift`, `Messagerie/
  ChatDateFormatting.swift`, `Messagerie/ChatViewModel.swift`, `Messagerie/ChatView.swift`,
  `Models/GiftCatalog.swift`, `Models/RosterModel.swift` — plus `Storage/MessageRepository.swift`
  (méthode `page` ajoutée) et `Storage/CoreDataRepository.swift` (`query` étendu avec `offset`,
  nécessaire pour la pagination `LIMIT n OFFSET m`, absent des repositories précédents qui ne
  paginaient pas). Points saillants, tous vérifiés :
  1. **Consolidation délibérée du doublement de `viewType`** : Android distingue chaque type de
     message en 2 `viewType` RecyclerView (`TEXT1`/`TEXT2`, `AUDIO1`/`AUDIO2`, …) uniquement pour le
     pattern ViewHolder — vérifié que la SEULE différence réelle entre les deux est
     `isBelongsToCurrentUser` (alignement, upload vs download) — consolidé en UNE vue SwiftUI par
     type d'objet plutôt que dupliqué, cohérent avec la règle déjà appliquée à
     `MessagePacket.buildPacketString` (module 11 protocole).
  2. **Forme d'onde audio confirmée FACTICE** : `MessageAudioViewHolder.createWaveform()` génère 50
     barres ALÉATOIRES (`new Random()`), aucune extraction PCM réelle du fichier audio n'existe dans
     ce fichier — reproduit fidèlement (`AudioBubbleBody.randomWaveform()`), pas "amélioré".
  3. **`MessagePhotoViewHolder`/`MessageGifViewHolder`/`MessageStickerViewHolder` confirmées
     byte-pour-byte identiques** (`bindView` complet comparé ligne à ligne, seule la fonction de
     chargement `ChargerImages.glid`/`glidGif` diffère) — consolidées en une seule vue.
  4. **Bug de code mort Android confirmé PAR ANALYSE DE FLOT DE CONTRÔLE, corrigé dans ce portage**
     (voir aussi le bug équivalent trouvé dans `addMessage` côté protocole, même session) — pas de
     nouveau bug de ce type trouvé dans `ChatFragmentTest.java` lui-même cette fois.
  5. **Frappe sortante (`onTyping(boolean)`) confirmée INACHEVÉE côté Android** : le corps qui
     émettrait l'événement socket est ENTIÈREMENT commenté dans le source lu (lignes 830-836) — seul
     le ré-armement du `Handler` de debounce est actif. Une émission FONCTIONNELLE a été écrite
     (`ChatViewModel.onTextChanged` → `ChatRepository.emitTyping`/`emitStopTyping`, déjà vérifiés
     module 11 protocole) plutôt qu'un no-op fidèle à l'original — amélioration documentée.
  6. **Amélioration documentée de `removeMessageAndUpdateSeparators`** : l'original retrouve le
     séparateur de date à supprimer par ÉGALITÉ DE STAMP avec le message supprimé, ce qui échoue
     silencieusement (séparateur orphelin permanent) si le message supprimé n'est pas exactement
     celui qui a déclenché la création du séparateur — `ChatListItem.dateSeparator` porte un
     `dayKey` stable (année+jour) permettant de retrouver le séparateur par JOUR, corrigeant ce cas
     sans changer le comportement observable normal.
  7. **Enregistrement audio confirmé CODE MORT côté Android lui-même** : tout le corps du
     `touchListener` d'enregistrement (appui long sur le micro) est commenté dans le source lu —
     non porté, cohérent avec l'original plutôt qu'un oubli.
  **PAS porté cette session, gaps honnêtement documentés (pas devinés)** : transfert réel upload/
  download (`UploadFileOrDataService.java`/`DownloadReceiver.java` non lus — endpoints/format
  multipart inconnus, points d'ancrage vides `requestUpload`/`requestDownload` dans
  `ChatViewModel.swift`) ; sélecteurs GIF/cadeau réels (`StickerPickerDialog.java`/
  `GiftGalleryView.java` non lus, remplacés par une feuille minimale et un sélecteur de cadeau basé
  sur le catalogue déjà vérifié) ; zoom média plein écran (`ImageExpanderAnim.java` non lu) ; rendu
  Message Graphic (`GraphicMessageViewHolder`, module 14 par conception — payload `mgGraphic` déjà
  identifié comme JSON pré-sérialisé non décodé) ; bandeaux d'abonnement groupe fonctionnels
  (module 15 Wallet) ; bulle chat IA `TiinverAI` (écran séparé `TiinverGeminiAIChat.java`) ; écran de
  liste des conversations (`RosterModel` accepté en entrée par `ChatView`, fichier source séparé
  hors périmètre explicite de cette passe — "MessageListAdapter + ViewHolders + ChatFragmentTest"
  uniquement, comme demandé) ; sons d'envoi/réception/frappe (`AppSounds`, pas branché) ; caméra/
  sélecteur média réel câblé sur `ChatViewModel.sendMedia` (la méthode existe et est vérifiée, son
  déclenchement UI — `PhotosUI`/caméra — pas câblé). **Module 11 marqué `[x]` fermé** avec ces
  réserves, cohérent avec le traitement des modules 7-10 : une couverture fonctionnelle complète du
  cœur (protocole + persistance + rendu + orchestration), des extensions périphériques différées et
  documentées plutôt que devinées.
- **2026-08-12 (suite, même session) : Module 12 (Appels WebRTC/CallKit) — démarré, écrit et FERMÉ
  dans la même session, avec réserves honnêtes.** Lecture méthodique : `messagerie/webrtc/RTConnection2.java` (801 lignes,
  entier — le moteur WebRTC), `messagerie/service/CallService.java` (835, entier),
  `messagerie/ui/call/CallViewModel.java` (110, entier), `messagerie/ui/call/CallActivity.java`
  (592, entier), `messagerie/ui/call/IncomingCallActivity.java` (534, entier), plus les petits
  fichiers `WebrtcData.java`/`CallModel.java`/`SignalisationCallBack.java`/
  `WebRTCMessageListener.java`/`IncomingCall.java`/`CallLauncherService.java` (tous entiers).
  `RTConnection.java`/`RTConnection3.java` (775/790 lignes) et `CallService2.java` (785) confirmés
  MORTS par grep exhaustif (même méthode que le cluster "v2" du module 10) — ni lus ni portés.
  **Recherche API réelle AVANT écriture de code**, comme demandé explicitement pour ce module
  (CallKit/PushKit n'ont aucun équivalent Android à porter, développement largement neuf) :
  `developer.apple.com/documentation/callkit` (fetch direct, a fonctionné pour la page `CXProvider`
  mais pas pour `CXProviderConfiguration`/`CXHandle`, rendu JS non capturé par l'outil de
  récupération) — recoupé systématiquement avec les bindings Xamarin officiels
  (`xamarin/apple-api-docs`, XML statiques, signatures C# fidèles à l'API Objective-C réelle) ET
  avec le dépôt de démonstration officiel `stasel/WebRTC-iOS` (`WebRTCClient.swift`, code Swift réel
  fonctionnel) ET avec les headers Objective-C bruts du framework WebRTC
  (`RTCConfiguration.h`/`RTCPeerConnection.h`/`RTCPeerConnectionFactory.h`/`RTCAudioSession.h`,
  récupérés depuis un miroir GitHub du framework). 8 fichiers Swift nouveaux/étendus :
  `Models/WebrtcData.swift`, `Models/TurnCredentials.swift`, `Calls/WebRTCConnection.swift`,
  `Calls/CallKitManager.swift`, `Calls/VoIPPushManager.swift`, `Calls/CallCoordinator.swift`,
  `Calls/CallView.swift`, `Realtime/ChatRepository.swift` (étendu). Points saillants :
  1. **Bug trouvé et corrigé PENDANT l'écriture** (pas dans l'original, pas dans une passe de
     relecture séparée cette fois — repéré en vérifiant le header `RTCPeerConnection.h` avant de
     finaliser) : `addIceCandidate:` n'a PAS de variante à bloc de complétion contrairement à
     `offer`/`answer`/`setLocalDescription`/`setRemoteDescription` — une première ébauche
     supposait `peerConnection.add(candidate) { _ in }` par analogie avec les autres appels,
     corrigé en `peerConnection.add(candidate)` après vérification du header réel.
  2. **Asymétrie négociateur/poli WebRTC vérifiée et préservée** : `CallService.
     configForOutgoingCall`/`configForIncomingCall` montrent que l'APPELANT n'est PAS l'initiateur
     de l'offre (`isInitiator=false`, `polite=true`) — c'est le RECEVEUR qui offre
     (`isInitiator=true`, `polite=false`). Contre-intuitif, confirmé en lisant les deux méthodes
     côte à côte, pas deviné.
  3. **Bugs d'isolement d'acteur Swift trouvés et corrigés en relisant le code écrit** (avant tout
     essai de compilation, impossible dans cet environnement) : `WebRTCConnection.
     peerConnection(_:didGenerate:)` et `sendMessage(type:sdp:)` appelaient le délégué
     `@MainActor` directement depuis un contexte non isolé (callbacks WebRTC internes,
     potentiellement hors thread principal) — corrigés en les enveloppant dans
     `Task { @MainActor in … }`, cohérent avec le reste du fichier qui le faisait déjà pour les
     autres callbacks.
  4. **Découverte fonctionnelle** : `ChatRepository.onCall`/`CallViewModel.onCall` (émission
     `ROOM.CALL`) confirmés jamais appelés par le vrai `CallService.java` (grep exhaustif) — code
     mort côté Android, écouteur de réception néanmoins conservé par fidélité (le serveur pourrait
     l'émettre indépendamment).
  5. **Correction d'une lacune du module 11** : `ChatRepository.handleNewMessage` traitait les deux
     branches `!isOnCall`/`isOnCall` du message `"voicecall"` de façon identique (placeholder posé
     avant que ce module existe) — corrigé pour appeler `CallCoordinator.shared.handleIncomingCall`
     directement dans la branche `!isOnCall` (fidèle à `lunchcall(p)`, un appel direct côté Android,
     pas un événement), la branche `isOnCall` restant un événement `.onCall` (signal "occupé").
  6. **`useManualAudio`/`RTCAudioSession.audioSessionDidActivate`/`didDeactivate` câblés sur
     `CXProviderDelegate.provider(_:didActivate:)`/`didDeactivate:`** — intégration standard
     CallKit+WebRTC vérifiée via le commentaire du header réel `RTCAudioSession.h` ("current known
     use case… when CallKit activates the audio unit"), pas un pattern deviné.
  7. **`CallView` intégrée** : bouton d'appel ajouté à la barre d'outils de `ChatView.swift`
     (module 11, `ChatProfile` minimal reconstruit depuis `RosterModel`) + présentation
     `.fullScreenCover` pilotée par `CallCoordinator.state != .idle` — le flux est donc
     déclenchable de bout en bout depuis l'écran de chat, pas seulement écrit "en l'air".
  **PAS fait cette session, gaps honnêtement documentés** : envoi du jeton VoIP au backend (endpoint
  serveur non identifié, Android n'a pas d'équivalent) ; boucle de re-notification
  `outgoingCallRepeatRunnable` (ping `/push` répété) non branchée, jugée redondante avec PushKit
  sans l'avoir formellement tranché ; capteur de proximité/wake lock Android délibérément PAS reproduits (CallKit gère nativement ce
  comportement pendant un appel, pas une omission). **Module 12 marqué `[x]` fermé** avec ces
  réserves — le cœur fonctionnel (moteur WebRTC, signalisation, CallKit, PushKit, orchestration) EST
  écrit et vérifié, ET l'intégration UI (bouton d'appel, présentation de l'écran) est câblée : le
  flux est déclenchable de bout en bout depuis l'écran de chat. Aucune vérification de compilation
  réelle n'a cependant été possible (environnement Windows sans Xcode) — priorité n°1 au premier
  accès macOS, voir "Prochaine action à faire".
- **2026-08-12 (suite, même session) : jeton VoIP PushKit — enregistrement câblé côté client +
  préparation de l'intégration serveur, à la demande explicite de l'utilisateur.** Re-vérification
  de l'API PushKit (bindings Xamarin `PKPushRegistry.xml`/`IPKPushRegistryDelegate.xml`/
  `PKPushType.xml`, confirmant `.voIP`) et recherche croisée sur l'exigence Apple de signalement
  synchrone (confirmée par plusieurs sources indépendantes : "must call provider.
  reportNewIncomingCall … synchronously", "mere seconds to respond", désactivation du jeton par le
  système en cas de non-conformité répétée — pas une supposition). Nouveau fichier
  `Calls/VoIPTokenRegistrar.swift` (`POST user/voip-token`, jeton hex-encodé, motif
  `APIClient.post` déjà établi) ; `CallCoordinator.voIPPushManager(_:didUpdateToken:)` câblé dessus.
  **Bug de séquencement trouvé et corrigé en relisant le code déjà écrit** : `handleIncomingCall`
  n'exposait pas de point d'ancrage pour appeler `completion()` avant la fin de
  `fetchTurnAndStart` (appel réseau TURN) — une notification VoIP recevait donc son `completion()`
  plus tard que nécessaire par rapport à ce qu'exige Apple (signaler l'appel à CallKit, pas
  terminer toute la préparation WebRTC). Corrigé par un paramètre `onReported: (() -> Void)?`
  optionnel, appelé juste après `CXProvider.reportNewIncomingCall`, laissant le fetch TURN se
  poursuivre en arrière-plan sans retarder le rappel PushKit. Nouvelle section dédiée "Backend à
  implémenter — PushKit/VoIP" ajoutée à ce document, avec la spécification complète de l'endpoint
  d'enregistrement, du flux serveur de déclenchement (étapes 2-4), et des prérequis Apple côté
  serveur (clé .p8 ou certificat VoIP Services dédié, topic `com.tiinver.ios.voip`, en-tête
  `apns-push-type: voip`) — **aucun fichier backend PHP existant modifié**, conformément à la
  demande explicite. Alternative documentée mais non retenue : réutiliser l'endpoint générique
  `user`/`column` déjà utilisé pour le jeton FCM (`PushTokenRegistrar.swift`) plutôt qu'un endpoint
  dédié — signalée à l'équipe serveur comme option, pas imposée.
- **2026-08-12 (suite, même session) : Module 13 (Shareboard/PBS) — repéré et scruté, PAS commencé,
  découverte de séquencement importante.** `PBSModel.java` (22 lignes)/`PBSViewModel.java` (58) lus
  en entier — petits wrappers vers `ChatRepository`. `FragmentPbs.java` (810 lignes) lu
  PARTIELLEMENT (~150/810 — imports, permissions, champs) avant d'arrêter délibérément : les imports
  révèlent que Shareboard est un DESSIN/ANIMATION COLLABORATIF EN TEMPS RÉEL sur un CANAL DE DONNÉES
  WebRTC séparé de celui des appels (`FragmentPbs` instancie son propre `RTConnection2`), rendu par
  `com.animems.engine.android.views.PBSCompound` (899 lignes) et sérialisé via
  `com.animems.engine.android.codec.graphic.GraphicMessageCodec` (265 lignes) — CE codec est très
  exactement celui déjà identifié au module 11 comme le format de `MessageLib.mgGraphic`/le
  territoire du module 14 "Message Graphic" (`GraphicMessageViewHolder`, module 11, placeholder
  documenté "appartient au module 14"). **Conclusion** : les modules 13 et 14 sont un seul et même
  sous-système technique (dessin collaboratif temps réel), pas deux features indépendantes comme
  l'ordre de portage initial le laissait supposer — les traiter séparément risquerait de porter deux
  fois la même logique de codec ou de la fragmenter incohéremment. Décision : ARRÊTER la lecture ici
  plutôt que de continuer à deviner l'architecture sans avoir lu `GraphicMessageCodec.java`/
  `PBSCompound.java` (899+265=1164 lignes, la majorité de la portée réelle) — aucun code Swift écrit
  pour ce module cette session, cohérent avec la méthodologie du projet. Prochaine session dédiée :
  lire `GraphicMessageCodec.java` en premier (le format d'échange, plus petit), puis
  `PBSCompound.java` (le moteur de rendu), avant de revenir à `FragmentPbs.java` en entier.
- **2026-08-12 (suite, même session) : Modules 13 (Shareboard) et 14 (Message Graphic) FERMÉS.**
  Lecture complète comme prévu : `GraphicMessageCodec.java` (266)/`CompactTouchEvent.java`/
  `CompactEditorData.java` (codec), `PBSCompound.java` (899), `PBSView.java` (1411),
  `EditorData.java`/`MotionEventData.java`/`Page.java` (modèles), `FragmentPbs.java` (810, ENTIER
  cette fois), `FragmentMessageGraphic.java` (295, entier), `BannerModel.java`/`AudioData.java`
  (structure seulement). **Correction d'une hypothèse de la découverte précédente** : `PBSCompound`
  n'est PAS le moteur de rendu — c'est `PBSView` (1411 lignes, jamais comptée dans l'estimation de
  portée initiale) ; et `FragmentPbs.webrtc = RTConnection2.getInstance(...)` réutilise en fait le
  MÊME singleton que `CallService` (module 12), pas une connexion WebRTC séparée comme supposé avant
  lecture complète — l'hypothèse de "canal dédié indépendant" était fausse, corrigée en lisant
  `FragmentPbs.java` en entier plutôt que de la laisser non vérifiée. La conclusion structurelle de
  la découverte précédente (13 et 14 partagent un seul moteur) restait, elle, correcte.
  **Bug trouvé et corrigé AVANT d'écrire le code Shareboard** (donc dans `Calls/WebRTCConnection.swift`,
  module 12) : le canal de données WebRTC n'avait jamais son `.delegate` assigné (ni côté créateur
  local, ni côté pair distant via `peerConnection(_:didOpen:)`) — aucun message reçu n'aurait jamais
  déclenché de callback. Vérifié contre `WebRTCClient.swift` (`stasel/WebRTC-iOS`, référence déjà
  utilisée au module 12) avant correction, PAS deviné. Fichiers Swift écrits cette session :
  `Shareboard/PBSWireModels.swift`, `Shareboard/GraphicMessageCodec.swift`,
  `Shareboard/PBSCanvasEngine.swift`, `Shareboard/PBSCanvasView.swift`, `Shareboard/PBSViewModel.swift`,
  `Shareboard/ShareboardView.swift`, `Shareboard/MessageGraphicComposeView.swift` ; extensions de
  `Realtime/ChatRepository.swift` (signalisation PBS, jusqu'ici manquante malgré `PBSEvent` déjà
  défini au module 11), `Messagerie/ChatViewModel.swift` (`sendGraphic`), `Messagerie/ChatView.swift`
  (points d'entrée toolbar), `Messagerie/ChatBubbleViews.swift` (`GraphicPlaceholderBubbleBody`
  remplacé par un rendu réel). Détail des décisions/portée réduite (pinch/rotate non live-synced,
  suppression d'objet non synchronisée — fidèle à Android sur ce point précis, bannière pub/tutoriel
  non portés, `addPbsNotification` différé) dans le tableau "Détail par module" ci-dessus, section
  Shareboard/Message Graphic. **PAS vérifié par un vrai build** (aucun accès macOS) — code le plus
  volumineux écrit en une seule session de ce portage (~1000 lignes Swift), risque de compilation
  élevé signalé en priorité pour le prochain build Codemagic, au même titre que le module 12.
  **Gap fonctionnel restant, documenté plutôt que caché** : aucun point d'entrée UI n'ouvre
  `ShareboardView` en mode "invité" (`status != 1`, rejoindre un salon déjà ouvert par un pair) — le
  bandeau de message système `"shareboard"` dans `ChatView` reste un simple texte non cliquable
  (`SystemInfoRow`), il faudrait le rendre tapable et lui faire ouvrir `ShareboardView(status: 0)`
  pour fermer complètement ce flux.

## Erreurs rencontrées et résolues

- 2026-08-10 : Une commande `mkdir` initiale a été rejetée par l'environnement (prompt de permission). Résolue en relançant la même commande — aucun blocage réel, juste une confirmation d'outil à repasser.
- 2026-08-10 : `JSONValue.rawData` référencé (`AuthEndpoints.decodeUser`, module 1) mais jamais défini — trouvé en écrivant `FeedRepository.fetchTimeline` (module 6). Résolu en ajoutant la propriété manquante à `JSONValue.swift` (voir décision correspondante ci-dessus). Ce n'est pas une erreur d'outil comme la précédente : c'est un vrai bug de code qui n'aurait été détecté qu'à la compilation sans cette relecture croisée.
- 2026-08-10 : `.gitignore` était encodé en UTF-16 avec BOM plutôt qu'en texte brut — confirmé avec `git check-ignore -v` que ses règles n'étaient jamais appliquées (`Resources/GoogleService-Info.plist` et `plist_base64.txt` tous deux INTROUVABLES par git avant correction, alors qu'ils auraient dû matcher). Résolu en réécrivant le fichier en ASCII pur (le premier essai en français avec accents a reproduit le même problème d'encodage — contrainte de cet environnement Windows, pas corrigée à la source, contournée en évitant les caractères non-ASCII dans ce fichier précis). Vérifié après coup que `git check-ignore -v` reconnaît maintenant bien les deux fichiers.
- **2026-08-10 : Premier build Codemagic réel du Checkpoint 1 — ÉCHEC à l'étape de build (pas à la résolution SPM, qui a réussi).** Message d'erreur exact, apparu deux fois :
  ```
  /Users/builder/clone/TiinverSwift.xcodeproj: error: Missing package product 'FirebaseCore' (in target 'TiinverSwift' from project 'TiinverSwift')
  ```
  **Cause identifiée (vérifiée contre le vrai `Package.swift` de `firebase-ios-sdk`, pas supposée) :** `project.yml` déclarait `Firebase: from: 10.29.0` et une dépendance `product: FirebaseCore`. Or `FirebaseCore` n'est PAS exposé comme "product" SPM (`.library(name: "FirebaseCore", ...)`) dans `Package.swift` à la version 10.29.0 — c'est uniquement une target interne (`.target(name: "FirebaseCore", ...)`, ligne 202 du fichier réel à ce tag), consommée en interne par les autres SDKs (`FirebaseAuth`, `FirebaseMessaging`, etc.) mais non "publiée" comme dépendance directement adressable depuis un projet consommateur. Vérifié en récupérant et en lisant directement `https://raw.githubusercontent.com/firebase/firebase-ios-sdk/10.29.0/Package.swift` : la liste `products:` (lignes 27-144) ne contient aucune entrée `FirebaseCore`. Confirmé par ailleurs (bisection sur plusieurs tags) que ce product n'a été ajouté à `firebase-ios-sdk` qu'à partir de la branche 11.3.x (absent en 11.0.0/11.1.0, présent dès 11.3.0) — la résolution SPM avait donc réussi (le package et sa version existent bien), mais le linkage du product demandé échouait au moment du build, d'où l'erreur qui n'apparaît qu'à cette étape et pas à la résolution des dépendances.
  **Correction appliquée :** version du package `Firebase` relevée dans `project.yml` de `from: 10.29.0` à `from: 11.15.0` (version où `FirebaseCore` est confirmé exposé comme product, vérifié directement dans son `Package.swift` réel à ce tag — `.iOS(.v12)` minimum, compatible avec notre `deploymentTarget.iOS = "16.0"`). Vérifié à ce tag que TOUS les products Firebase actuellement déclarés dans `project.yml` (`FirebaseCore`, `FirebaseAuth`, `FirebaseMessaging`, `FirebaseRemoteConfig`, `FirebaseAnalytics`) existent bien sous ces noms EXACTS dans `products:` — aucun autre renommage nécessaire. Recoupé aussi avec le code Swift déjà écrit (`grep "import Firebase" sur Sources/`) : `FirebaseCore` (`AppDelegate.swift`), `FirebaseMessaging` (`AppDelegate.swift`, `PushTokenRegistrar.swift`), `FirebaseAuth` (`GoogleSignInCoordinator.swift`), `FirebaseRemoteConfig` (`FirebaseConfigManager.swift`) — les 4 imports utilisés correspondent bien à des products désormais valides à la version choisie. `FirebaseAnalytics` reste déclaré sans être importé nulle part dans le code : normal, ce product s'active par simple présence du lien (commentaire explicite en ce sens dans le `Package.swift` de Firebase), pas une anomalie.
  **✅ VÉRIFIÉE PAR BUILD RÉEL (2026-08-10, build #6a7a2aabd5ae67eb2a755de2) :** confirmée par le build Codemagic suivant, qui a franchi cette étape sans erreur (voir "CHECKPOINT 1 ATTEINT ET VALIDÉ" plus bas). N'a pas empêché un échec ultérieur distinct (`CoreDataFetchable`, entrée suivante), qui a nécessité une correction séparée.
- **2026-08-10 : Deuxième build Codemagic réel du Checkpoint 1 (après correction `FirebaseCore` ci-dessus) — ÉCHEC, nouvelle erreur, 16 occurrences dans le même fichier.** Message d'erreur exact (une ligne par entité, ex. `ActivityEntity`) :
  ```
  Sources/TiinverSwift/Storage/CoreDataFetchable.swift:13-34: error: protocol 'CoreDataFetchable' requirement 'fetchRequest()' cannot be satisfied by a non-final class ('ActivityEntity') because it uses 'Self' in a non-parameter, non-result type position
  ```
  Touchait les 16 entités déclarées dans `CoreDataFetchable.swift` (les 14 de `TiinverModel`, les 2 de `TiinverAnalyticsModel`, et `NotiEntity` de `TiinverNotificationsModel` — 17 au total en réalité, la 17ᵉ ligne de conformance n'ayant pas d'erreur listée séparément dans le message rapporté mais soumise à la même cause).
  **Cause identifiée :** le protocole déclarait `static func fetchRequest() -> NSFetchRequest<Self>`. C'est une limitation connue de Swift, pas un bug de portage lié à Android : un protocole qui utilise `Self` imbriqué dans un paramètre générique (ici `NSFetchRequest<Self>`, pas directement comme type de retour) ne peut être satisfait que par une classe `final`, car le compilateur ne peut pas garantir qu'une sous-classe potentielle non prévue respecterait la même covariance. Les classes d'entités Core Data générées par Xcode (`codeGenerationType="class"`, confirmé pour les 16 entités dans les 3 `.xcdatamodel` — voir grep `codeGenerationType` dans `Storage/*.xcdatamodeld/**/contents`) ne sont PAS marquées `final` par défaut, d'où l'échec pour chacune d'elles.
  **Option retenue : reformulation du protocole avec un `associatedtype` plutôt que rendre les entités `final` (Option B, pas Option A).** Raisons du choix, après avoir comparé les deux :
  - Rendre les entités `final` (Option A) aurait exigé de changer `codeGenerationType` de `"class"` (génération automatique par Xcode depuis le `.xcdatamodel`, décision déjà actée et documentée au module 2) vers `"category"`/manuel, et de récrire à la main 16 classes `NSManagedObject` à travers 3 `.xcdatamodeld` — surface de risque bien plus large (attributs/relations mal recopiés, un seul oubli suffit à casser une entité) pour un problème strictement local au protocole.
  - Confirmé qu'aucune entité n'a de `parentEntity` (grep sur les 3 `contents` — aucune relation d'héritage entre entités), donc aucun risque de casser une hiérarchie de classes en touchant uniquement le protocole.
  - Vérifié qu'aucun fichier hors `CoreDataRepository.swift` ne s'appuie sur le protocole `CoreDataFetchable` : `RosterRepository.swift`/`NotiRepository.swift` appellent `fetchRequest()` directement sur les classes concrètes (`RosterEntity.fetchRequest()`, `MessageEntity.fetchRequest()`, `NotiEntity.fetchRequest()`) — ces appels passent par la méthode générée par Xcode sur la classe elle-même, pas par le protocole générique, donc non affectés par ce changement (grep confirmé, voir liste complète des occurrences de `fetchRequest()` dans `Sources/`).
  Changement appliqué à `Storage/CoreDataFetchable.swift` : `associatedtype FetchResult: NSManagedObject = Self` + `static func fetchRequest() -> NSFetchRequest<FetchResult>` (au lieu de `NSFetchRequest<Self>` directement). Swift déduit `FetchResult` automatiquement pour chaque entité depuis sa méthode `fetchRequest()` déjà générée par Xcode (qui retourne toujours `NSFetchRequest<TypeConcret>`) — aucune des 16 lignes `extension XxxEntity: CoreDataFetchable {}` n'a dû être modifiée. `Storage/CoreDataRepository.swift` : ajout de la contrainte `where Entity.FetchResult == Entity` sur `CoreDataRepository<Entity: CoreDataFetchable>`, nécessaire pour que `query`/`first` continuent de retourner `[Entity]` (et pas `[Entity.FetchResult]`) sans changer aucune signature publique du repository générique — satisfaite automatiquement par toutes les entités existantes puisqu'aucune ne surcharge le `= Self` par défaut. Vérifié par grep que les 8 usages de `CoreDataRepository<...>` dans `Sources/` (`AuthSessionPersistence.swift`, `ProfileView.swift`, `FeedRepository.swift`, `AiConversationRepository.swift`, `NotiRepository.swift`, `RosterRepository.swift` ×2, `ViewEventRepository.swift`) n'ont besoin d'aucune modification — le générique reste utilisable exactement comme avant pour les 3 stores Core Data indépendants.
  **✅ VÉRIFIÉE PAR BUILD RÉEL (2026-08-10, build #6a7a2aabd5ae67eb2a755de2) :** troisième build Codemagic réussi sans aucune erreur — confirme concrètement que la reformulation `associatedtype` compile bien pour les 16 entités et que la contrainte `where Entity.FetchResult == Entity` n'a cassé aucun des 8 usages de `CoreDataRepository<...>`. Voir "CHECKPOINT 1 ATTEINT ET VALIDÉ" plus bas — **Checkpoint 1 VALIDÉ**, plus aucune erreur en attente.
- **2026-08-11 : Premier build Codemagic couvrant les modules 7+8 (post-clôture module 8) — ÉCHEC, mais PAS une erreur de compilation Swift/Metal.** Message d'erreur exact :
  ```
  error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain
  ```
  **Cause : composant Xcode manquant sur la machine de build CI, pas un problème dans le code écrit.** Depuis Xcode 16, le compilateur `metal` (nécessaire pour compiler `Camera/Filters/TiinverCameraShaders.metal`, module 7) n'est plus embarqué automatiquement dans l'installation Xcode de base — c'est un composant téléchargeable séparément (`MetalToolchain`), absent par défaut sur les images CI qui n'en ont pas explicitement besoin. Le build a échoué à l'étape de compilation du `.metal` AVANT même de tenter de compiler le reste du code Swift — **aucune information sur la validité réelle des ~22 filtres GPU du module 7 ni du reste du code (modules 1-8) n'a donc été obtenue par ce build**, ni positive ni négative.
  **Correction appliquée :** ajout d'une étape "Install Metal Toolchain" (`xcodebuild -downloadComponent MetalToolchain`) dans `codemagic.yaml` (workflow `checkpoint-build`) ET `.github/workflows/ios-build.yml`, placée après `xcodegen generate` et avant "Résoudre les dépendances Swift Package Manager"/"Build simulateur" dans les deux fichiers (le composant doit être présent avant que `xcodebuild build` tente d'invoquer `metal`).
  **PAS ENCORE VÉRIFIÉE PAR BUILD RÉEL** — nécessite un nouveau build Codemagic/GitHub Actions pour confirmer que le téléchargement du composant réussit ET que la compilation Swift/Metal proprement dite passe derrière. Les ~22 filtres GPU du module 7 (`TiinverCameraFilters.swift`/`TiinverCameraShaders.metal`) restent donc le point de risque de compilation le plus élevé non vérifié de tout le portage, exactement comme avant ce build (voir "Points à ne pas oublier" plus bas) — cette correction lève un blocage d'infrastructure CI, elle ne dit rien sur la validité du code lui-même.
- **2026-08-11 : Deuxième build Codemagic couvrant les modules 7+8 (après correction Metal Toolchain ci-dessus) — Metal Toolchain confirmé opérationnel, UNE SEULE erreur de compilation Swift réelle sur tout le reste du code testé.** Bonne nouvelle à documenter explicitement : **les ~22 shaders GPU du module 7 (`TiinverCameraShaders.metal`) ont compilé SANS ERREUR** — c'était le point de risque de compilation le plus élevé identifié dans "Points à ne pas oublier"/"Points à vérifier en priorité", maintenant levé. Message d'erreur exact de l'unique échec :
  ```
  /Users/builder/clone/Sources/TiinverSwift/Animems/MaskPreviewEditorPanelState.swift:34:22: error: value type 'MaskPreviewEditorPanelState' cannot have a stored property that recursively contains it
      private(set) var original: MaskPreviewEditorPanelState?
  ```
  **Cause :** `MaskPreviewEditorPanelState` est un `struct` (valeur) contenant une propriété stockée de son PROPRE type (`original: MaskPreviewEditorPanelState?`, snapshot pour `onCancelClicked`) — un `struct` Swift doit avoir une taille en mémoire connue et fixe à la compilation, ce qu'une propriété auto-référente rend impossible (contrairement à une classe, où seul un pointeur de taille fixe serait stocké). Cette limitation n'existe pas côté Java/Android (`original*` y sont des champs primitifs indépendants, jamais un objet `MaskPreviewEditorPanel` complet imbriqué) — le premier jet Swift avait introduit cette auto-référence en modélisant `original` comme "tout l'état" plutôt que comme les seules valeurs réellement restaurées.
  **Correction appliquée (option 1 du choix proposé, la plus fidèle au comportement Android) :** extraction d'un type `MaskPreviewEditorPanelState.Snapshot` dédié (les 8 champs comparables/restaurables — `maskType`/`inverted`/`opacity`/`feather`/`offsetX`/`offsetY`/`scale`/`mirrorGap` — SANS `original` lui-même), remplaçant `original: MaskPreviewEditorPanelState?` par `original: Snapshot?`. `cancel()` (port de `onCancelClicked`) réassigne maintenant les 8 champs individuellement depuis `original` plutôt que `self = original` — effet de bord positif : le hack de sauvegarde/restauration de `self.original` autour de l'ancien `self = original` (nécessaire uniquement à cause de l'auto-référence) disparaît, `original` n'étant plus jamais écrasé par `cancel()`. Pas d'alternative "passer en classe" retenue : rien dans `MaskPreviewEditorPanel.java` ne dépend d'une identité de référence pour ce panneau (contrairement à `AnimationObjectData`, muté en place et partagé par de nombreux appelants) — un struct reste fidèle et plus simple.
  **Vérifié par grep** qu'aucun autre fichier Swift n'utilise `MaskPreviewEditorPanelState` au-delà de références en commentaire (`ShapePreviewEditorPanelState.swift`, `MaskEditController.swift`) — aucune signature publique consommée ailleurs, correction locale au fichier uniquement.
  **✅ VÉRIFIÉE PAR BUILD RÉEL (2026-08-11) :** le build Codemagic suivant confirme que cette correction est passée — l'erreur `MaskPreviewEditorPanelState` n'apparaît plus, remplacée par une nouvelle erreur distincte (entrée suivante).
- **2026-08-11 : Troisième build Codemagic couvrant les modules 7+8 — la correction `MaskPreviewEditorPanelState` confirmée résolue, UNE NOUVELLE erreur de compilation Swift révélée.** Message d'erreur exact :
  ```
  /Users/builder/clone/Sources/TiinverSwift/Animems/AnimemesGestureController.swift:199:72: error: cannot convert value of type 'CGFloat' to expected argument type 'Int'
  /Users/builder/clone/Sources/TiinverSwift/Animems/AnimemesGestureController.swift:199:100: error: cannot convert value of type 'CGFloat' to expected argument type 'Int'
  ```
  **Cause :** dans `scale(factor:focus:objectIndex:composer:)` (port de `safePostScale`), la ligne construisait `CGRect(x: obj.offsetX, y: obj.offsetY, width: CGFloat(bmp.width), height: CGFloat(bmp.height))` — `AnimationObjectData.offsetX`/`.offsetY` sont des `Int` (fidèle à `int offsetX`/`int offsetY` côté `AnimationObjectData.java`, décision déjà actée et documentée au portage de ce fichier), mais `CGRect.init(x:y:width:height:)` n'accepte QUE des `CGFloat` pour ses 4 paramètres — il manquait un `CGFloat(...)` autour de `obj.offsetX`/`obj.offsetY`. **Note sur les colonnes rapportées par le compilateur (72/100, qui pointent vers `width:`/`height:` et non vers `x:`/`y:` où se trouve le vrai problème)** : comportement de diagnostic Swift connu — face à un unique candidat d'initialiseur avec DEUX arguments mal typés simultanément (`x`/`y`), le solveur de contraintes du compilateur peut mal attribuer l'échec de résolution aux arguments syntaxiquement voisins plutôt qu'aux véritables coupables ; vérifié en confirmant que `width`/`height` étaient déjà correctement enveloppés en `CGFloat(...)`, seuls `x`/`y` (accès direct à des `Int`) manquaient la conversion. Ce même motif `CGFloat(obj.offsetX)`/`CGFloat(obj.offsetY)` était déjà utilisé correctement dans `AnimemesRecompose.swift` (`computeBounds`, écrit à la même session) — bug local à ce seul site d'appel, pas une erreur de conception répétée.
  **Correction appliquée :** `CGRect(x: CGFloat(obj.offsetX), y: CGFloat(obj.offsetY), width: CGFloat(bmp.width), height: CGFloat(bmp.height))`. Pas de changement de type à la source (`offsetX`/`offsetY` restent `Int`, fidèles à Android) — c'est bien une coordonnée à convertir au point d'usage, pas un index/compteur mal typé en amont.
  **Vérifié par grep** qu'aucune autre occurrence de ce motif (`CGRect(x: obj.offsetX...)` ou équivalent) n'existe ailleurs dans `Animems/`, et que le reste du fichier `AnimemesGestureController.swift` n'a pas d'autre usage direct non converti de `offsetX`/`offsetY`.
  **✅ VÉRIFIÉE PAR BUILD RÉEL (2026-08-11) :** le build Codemagic suivant confirme que cette correction est passée — l'erreur `AnimemesGestureController.swift:199` n'apparaît plus, remplacée par deux nouvelles erreurs distinctes, même fichier source (entrée suivante).
- **2026-08-11 : Quatrième build Codemagic couvrant les modules 7+8 — la correction `AnimemesGestureController.swift` confirmée résolue, 2 NOUVELLES erreurs de compilation Swift révélées, même fichier, même pattern.** Messages d'erreur exacts :
  ```
  /Users/builder/clone/Sources/TiinverSwift/Animems/LayerRenderer.swift:67:43: error: binary operator '*' cannot be applied to operands of type 'Float' and 'CGFloat'
  /Users/builder/clone/Sources/TiinverSwift/Animems/LayerRenderer.swift:162:43: error: binary operator '*' cannot be applied to operands of type 'Float' and 'CGFloat'
  ```
  **Cause :** `let featherPx = feather * feather * maxFeatherPx` (dans `drawLastTransform` ligne 67 ET `drawObjectFrame` ligne 162, sites structurellement jumeaux — voir tête de fichier sur la factorisation partielle des deux méthodes). `feather` vient de `resolveVisualProperties(...)`, dont le type de retour est `(opacity: Float, color: UInt32, cornerRadius: Float, feather: Float)` — délibérément `Float` partout dans ce tuple pour rester fidèle au `float` Java d'origine (`Transform.getFeather()`/`AnimationObjectData.interpolatedFeather`, déjà `Float` côté Swift). `maxFeatherPx` est `static let maxFeatherPx: CGFloat = 250` — `CGFloat` car c'est une constante de rendu consommée uniquement par des API Core Graphics. `Float * Float` fonctionne (donne `Float`), mais `Float * CGFloat` n'a pas de surcharge d'opérateur — Swift n'effectue jamais de conversion numérique implicite entre types concrets distincts, même tous deux "à virgule flottante".
  **Vérification du pattern dominant AVANT de corriger** (comme demandé) : `grep -c ": Float"`/`": CGFloat"` sur tout `Animems/` confirme une séparation nette et déjà cohérente dans tout le module — les types de la couche modèle/moteur (`AnimationObjectData.swift`, `Transform.swift`, `Keyframe.swift`, `KeyframeTrack.swift`, `AnimationUtils.swift`, propriétés `shape*`) restent en `Float` (fidèles au `float` Android), tandis que la couche rendu/géométrie Core Graphics (`LayerRenderer.swift`, `MaskFactory.swift`, `BitmapCacheManager.swift`, `TimelineViewModel.swift`, `AnimemesGestureController.swift`, etc.) utilise `CGFloat`, converti explicitement au POINT DE CONTACT avec les API CG (`CGFloat(obj.maskFeather) * maxFeatherPx` déjà présent correctement ailleurs dans CE MÊME fichier, lignes 93-94/178, sans jamais avoir déclaré `feather`/`opacity`/`cornerRadius` en `CGFloat` à la source). Confirme que la correction doit se faire AU POINT DE CALCUL (convertir `feather`), PAS en changeant le type déclaré de `resolveVisualProperties`/`Transform.feather`/`AnimationObjectData.interpolatedFeather` — cela casserait la cohérence de tout le reste du module et la fidélité au `float` Android.
  **Correction appliquée** (identique aux 2 sites) : `let featherPx = CGFloat(feather) * CGFloat(feather) * maxFeatherPx`.
  **Relecture complète et ciblée de tout `LayerRenderer.swift` (438 lignes) pour des erreurs sœurs non encore révélées par ce build** (le compilateur peut s'arrêter avant d'atteindre tous les fichiers) : chaque usage de `opacity`/`cornerRadius`/`feather` (les 3 champs `Float` du tuple `resolveVisualProperties`) vérifié individuellement — TOUS déjà correctement enveloppés en `CGFloat(...)` avant toute arithmétique avec une valeur `CGFloat` (`CGFloat(cornerRadius)` lignes 106/111/189/194, `CGFloat(opacity)` ligne 384) ; aucune autre occurrence du motif `Float × CGFloat` trouvée dans ce fichier. `AnimationEngine.swift`/`Transform.swift`/`Keyframe.swift` non concernés par cette erreur (aucune arithmétique CG directe dans ces fichiers modèle).
  **PAS ENCORE VÉRIFIÉE PAR BUILD RÉEL** — nécessite un nouveau build pour confirmer que c'était la seule erreur restante sur l'ensemble modules 1-8.
- **2026-08-13 : Premier build Codemagic du Checkpoint 3 (couverture complète, modules 1-18) — ÉCHEC, 16 erreurs concentrées sur 2 fichiers.** Messages d'erreur exacts (11 occurrences du même type d'erreur, types distincts) :
  ```
  Sources/TiinverSwift/Advertising/AdMobManager.swift: error: cannot find type 'BannerView' in scope
  Sources/TiinverSwift/Advertising/AdMobManager.swift: error: cannot find type 'RewardedAd' in scope
  Sources/TiinverSwift/Advertising/AdMobManager.swift: error: cannot find type 'RewardedInterstitialAd' in scope
  Sources/TiinverSwift/Advertising/AdMobManager.swift: error: cannot find type 'NativeAd' in scope
  Sources/TiinverSwift/Advertising/AdMobManager.swift: error: cannot find type 'AdLoader' in scope
  Sources/TiinverSwift/Advertising/AdMobManager.swift: error: cannot find type 'NativeAdLoaderDelegate' in scope
  Sources/TiinverSwift/Shareboard/ShareboardView.swift:187: error: 'Tool' is inaccessible due to 'private' protection level
  ```
  **Erreur 1 — AdMob, cause identifiée (vérifiée, pas supposée) :** `import GoogleMobileAds` et la déclaration SPM dans `project.yml` (`package: GoogleMobileAds` / `product: GoogleMobileAds`) étaient tous les deux corrects — le nom du produit correspond exactement au `Package.swift` réel du SDK (vérifié par récupération directe de `https://raw.githubusercontent.com/googleads/swift-package-manager-google-mobile-ads/main/Package.swift`, qui confirme `.library(name: "GoogleMobileAds", ...)`). Le vrai problème était la VERSION résolue : `project.yml` déclarait `from: 11.0.0`. Or la nomenclature Swift SANS préfixe `GAD*` (`BannerView`/`RewardedAd`/`RewardedInterstitialAd`/`NativeAd`/`AdLoader`/`NativeAdLoaderDelegate`, utilisée dans tout `AdMobManager.swift` depuis le module 16) n'existe qu'à partir du SDK **12.0.0** — confirmé par les notes de version officielles Google ("Updated Swift API names to follow the naming conventions from Apple's Swift API Design Guidelines"). Avec la sémantique SPM `upToNextMajor` de `from: 11.0.0` (équivalent à `>=11.0.0 <12.0.0`), la résolution de dépendances RÉUSSIT (la branche 11.x existe bien, d'où l'absence d'erreur à l'étape de résolution) mais reste bornée à une version qui n'a jamais eu ces types sous ces noms — même famille de bug que `FirebaseCore` au Checkpoint 1 (produit/version qui se résout "avec succès" mais dont le contenu ne correspond pas à l'API attendue). Confirmé par une seconde source indépendante : le `project.pbxproj` réel de l'exemple officiel Google `googleads-mobile-ios-examples` (`Swift/advanced/SwiftUIDemo`), qui déclare explicitement `XCRemoteSwiftPackageReference` avec `requirement.kind = upToNextMajorVersion` et `minimumVersion = 13.0.0` pour ce même package — cet exemple est la référence contre laquelle l'API du module 16 avait été vérifiée à l'écriture, confirmant que la nomenclature utilisée correspond à la branche 13.x, pas 11.x.
  **Correction appliquée :** `project.yml`, package `GoogleMobileAds` : `from: 11.0.0` → `from: 13.0.0` (aligné sur la contrainte réelle de l'exemple officiel, pas deviné). Commentaire de tête `AdMobManager.swift` corrigé en conséquence (il affirmait à tort que `from: 11.0.0` était la version confirmant la nomenclature actuelle — c'était l'hypothèse non vérifiée à l'origine du bug).
  **Erreur 2 — Shareboard, cause identifiée :** `ShareboardView.swift` déclarait `private enum Tool` (type imbriqué dans `struct ShareboardView`, ligne 20), puis une `private extension ShareboardView.Tool { var androidAction: String { ... } }` à portée de fichier (ligne 187, EN DEHORS du corps lexical de `ShareboardView`). Un type imbriqué marqué `private` n'est visible que dans le corps lexical de son type englobant (et les extensions DU TYPE ENGLOBANT dans le même fichier) — pas depuis une extension du type imbriqué lui-même déclarée au niveau fichier, même dans le même fichier : `ShareboardView.Tool` n'y est simplement pas un nom accessible. Vérifié par grep (`private (enum|struct|class|typealias)` sur tout `Shareboard/`) qu'aucun autre type du module n'a le même problème — le seul autre type `private` du module (`GraphicMessageCodec.CompactEditorData`) n'est référencé que dans son propre fichier, sans extension externe.
  **Correction appliquée :** `private enum Tool` → `enum Tool` (accès `internal`, le niveau par défaut) — aucune raison d'encapsulation stricte identifiée qui justifierait `private` ici (le type n'est utilisé qu'à l'intérieur du module Shareboard de toute façon).
  **PAS ENCORE VÉRIFIÉE PAR BUILD RÉEL** — nécessite un nouveau build Codemagic pour confirmer ces deux corrections. **Checkpoint 3 NON VALIDÉ.**
- **2026-08-13 : Deuxième build Codemagic du Checkpoint 3 — ÉCHEC dès l'étape `xcodegen generate`, AVANT toute compilation Swift.** Message d'erreur exact :
  ```
  Parsing project spec failed: Decoding failed at "url": Nothing found
  ```
  **Cause : erreur de configuration `project.yml` introduite PAR LA CORRECTION PRÉCÉDENTE elle-même, pas une nouvelle erreur de code.** En insérant le commentaire explicatif autour du changement `from: 11.0.0` → `from: 13.0.0` (entrée précédente), la ligne `url: https://github.com/googleads/swift-package-manager-google-mobile-ads.git` de l'entrée `GoogleMobileAds` a été omise par erreur lors de la réécriture du bloc — l'entrée ne contenait plus que le commentaire puis `from: 13.0.0`, sans aucune clé `url:`. XcodeGen exige un `url:` pour chaque déclaration de package SPM ; son absence produit cette erreur de décodage AVANT même la génération du projet Xcode (donc avant toute tentative de compilation), ce qui explique pourquoi l'échec survient à une étape plus précoce que les précédents.
  **Vérification effectuée avant correction (comme demandé) :** relecture de la section `packages:` entière (les 8 entrées) — seule `GoogleMobileAds` avait perdu son `url:`, les 7 autres entrées étaient intactes. Validation YAML complète du fichier faite avec un parseur réel (`js-yaml` via Node, installé temporairement dans le répertoire scratchpad puis supprimé après usage — aucun outil YAML natif disponible dans cet environnement Windows) : `PARSE OK`, confirmé que les 8 packages ont bien un champ `url` non vide après correction, et que les 15 dépendances de la cible `TiinverSwift` sont toujours présentes — aucune autre casse structurelle ailleurs dans le fichier.
  **Correction appliquée :** réinsertion de la ligne `url: https://github.com/googleads/swift-package-manager-google-mobile-ads.git` juste après `GoogleMobileAds:`, avant le bloc de commentaire, en conservant `from: 13.0.0`.
  **PAS ENCORE VÉRIFIÉE PAR BUILD RÉEL** — nécessite un nouveau build Codemagic. **Checkpoint 3 toujours NON VALIDÉ.**
- **2026-08-13 : Troisième build Codemagic du Checkpoint 3 — les 2 corrections précédentes (AdMob API/version, `Tool` privé, `url:` manquant) confirmées résolues (n'apparaissent plus), UNE NOUVELLE erreur de conformité de protocole révélée.** Message d'erreur exact :
  ```
  Advertising/AdMobManager.swift:155:1: error: type 'NativeAdLoader' does not conform to protocol 'AdLoaderDelegate'
  note: protocol requires function 'adLoader(_:didFailToReceiveAdWithError:)' with type '(AdLoader, any Error) -> Void'
  ```
  **Cause :** `extension NativeAdLoader: NativeAdLoaderDelegate` n'implémentait que le callback de succès (`adLoader(_:didReceive:)`), pas le callback d'échec requis par le protocole `AdLoaderDelegate` du SDK — omission au moment de l'écriture du module 16, jamais révélée avant un vrai build puisqu'aucune compilation locale n'est possible dans cet environnement.
  **Vérification du comportement Android AVANT d'écrire un comportement (comme demandé), pas deviné :** lecture complète de `Activity/service/NativeAdsManager.java` (233 lignes, source réelle du dépôt Android `C:\Users\helen\AndroidStudioProjects\tiinver`, jamais lue en détail au module 16 initial — voir avertissement déjà présent en tête de `AdMobManager.swift`). `AdListener.onAdFailedToLoad(LoadAdError error)` (lignes 136-149) journalise l'erreur (`Log.e(TAG, "Ad failed: code=...")`) puis distingue `ERROR_CODE_NO_FILL` (backoff dédié `registerNoFill()`, pas une panne) des autres erreurs (`retryCount++`), le tout au service d'un pool de 8 annonces préchargées avec cooldown. **Cette logique de pool/retry/NO_FILL n'a pas d'équivalent dans le portage Swift**, déjà documenté comme hors périmètre en tête de fichier (`NativeAdLoader` charge UNE annonce à la fois, pas un pool) — rien à porter au-delà du journal d'erreur lui-même sans réintroduire une portée déjà explicitement exclue.
  **Correction appliquée :** ajout de `nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) { print("❌ NativeAdLoader (AdMob) échec de chargement :", error) }` — `nonisolated` par cohérence avec le callback de succès voisin dans la même extension (déjà `nonisolated`, nécessaire car le protocole `AdLoaderDelegate` n'est pas isolé à un acteur et peut être appelé par le SDK depuis un thread quelconque).
  **Avertissement Swift 6 strict concurrency signalé dans le même log, traité en même temps (rapide) :** `Realtime/ChatRepository.swift:18` (`static let shared = ChatRepository()`, classe `@MainActor`) référencé en valeur par défaut de paramètre `chatRepository: ChatRepository = .shared` dans `ChatViewModel.init` (`Messagerie/ChatViewModel.swift:49`) — une expression de valeur par défaut de paramètre n'hérite pas garantiment de l'isolation d'acteur de la fonction dans ce mode de vérification, contrairement au corps de la fonction lui-même, d'où l'avertissement ("deviendra une erreur en Swift 6 strict concurrency mode"). **Corrigé** : paramètre changé en `chatRepository: ChatRepository? = nil`, résolution `chatRepository ?? .shared` déplacée dans le corps de l'init (isolé `@MainActor` par la classe englobante `ChatViewModel`, donc l'accès à `.shared` y est sans ambiguïté d'isolation). Vérifié par grep qu'un seul site d'appel existe (`ChatView.swift:18`, `ChatViewModel(target: target)`, sans argument `chatRepository` explicite) — non affecté par l'élargissement du type de paramètre en optionnel.
  **PAS ENCORE VÉRIFIÉE PAR BUILD RÉEL** — nécessite un nouveau build Codemagic. **Checkpoint 3 toujours NON VALIDÉ.**
- **2026-08-13 : Quatrième build Codemagic du Checkpoint 3 — AdMob (protocole) et Shareboard confirmés résolus, UNE SEULE erreur de compilation restante.** Message d'erreur exact :
  ```
  Sources/TiinverSwift/PhotoEditor/RemoveBackground.swift:154:16: error: cannot call value of non-function type 'CGImage'
  ```
  **Cause : collision de portée entre un paramètre et une méthode statique de même nom, pas un problème lié à Vision/`VNGeneratePersonSegmentationRequest` (fonction différente, plus haut dans le fichier, non affectée).** `removeBackgroundAdvanced(_ image: CGImage)` (ligne 88) déclare son paramètre `image: CGImage` ; à la ligne 154, l'appel `image(fromRGBAPixels: pixels, width: w, height: h)` était censé invoquer la méthode statique privée `image(fromRGBAPixels:width:height:)` (ligne 184, reconstruction du `CGImage` final straight-alpha) — mais dans la portée de `removeBackgroundAdvanced`, le nom `image` résout d'abord vers le PARAMÈTRE local (de type `CGImage`, pas une fonction), masquant la méthode statique de même nom. D'où "cannot call value of non-function type 'CGImage'" : Swift tentait littéralement d'appeler la valeur `CGImage` du paramètre comme si c'était une fonction.
  **Correction appliquée :** `Self.image(fromRGBAPixels: pixels, width: w, height: h)` — le préfixe `Self.` force la résolution vers le membre statique du type `RemoveBackground`, en contournant le masquage par le paramètre local. Aucun changement de nom nécessaire (le paramètre `image` reste `image`, fidèle à l'original `bitmap`/`image` Android) — correction locale au seul site d'appel concerné. Vérifié qu'aucune autre collision du même type n'existe dans le fichier : `removeBackgroundWithVision` (l'autre fonction publique) n'appelle jamais `image(...)` en interne, et `pixelData(of image: CGImage)` (ligne 166, même nom de paramètre) n'appelle pas non plus la méthode `image(...)`.
  **PAS ENCORE VÉRIFIÉE PAR BUILD RÉEL** — nécessite un nouveau build Codemagic pour confirmer qu'il s'agissait bien de la dernière erreur. **Checkpoint 3 toujours NON VALIDÉ.**

## Points bloquants actuels

Statut global = **CHECKPOINT 2 VALIDÉ, MODULE 9 EN COURS** (voir sections dédiées plus bas) :

- **Plus de blocage de compilation pour les modules 1-8** : le 4ᵉ build Codemagic réel du
  2026-08-11 a confirmé que l'intégralité du code Swift écrit pour les modules 1 à 8 compile sans
  erreur (après 5 itérations de correction au total — voir "Erreurs rencontrées et résolues" et
  "CHECKPOINT 2 ATTEINT ET VALIDÉ" ci-dessous pour le détail). La contrainte d'environnement (pas
  d'Xcode/macOS sur cette machine Windows, voir section dédiée en tête de fichier) reste vraie pour
  le code écrit à PARTIR de maintenant (module 9 et suivants) : chaque nouveau fichier Swift reste
  `ÉCRIT (NON COMPILÉ)` jusqu'au prochain build réel — seul le Checkpoint 3 (fin du module 18,
  portée élargie depuis la validation anticipée du Checkpoint 2 — voir "Règle de compilation par
  checkpoint") confirmera leur compilation.
- Les points d'incertitude non liés à la compilation (handshake Socket.IO via `.connectParams`,
  rendu visuel du `TabView` pivoté du feed, câblage de gestes SwiftUI du module 8 jamais vu rendu)
  restent NON VÉRIFIÉS — un build réussi ne prouve que la compilation, pas le comportement à
  l'exécution. Voir "Points à vérifier en priorité au prochain build — Module 8" ; à garder en tête
  mais ne bloquent pas le démarrage du module 9.

## Backend à implémenter — PushKit/VoIP (module 12, spécification pour l'équipe serveur PHP/Slim)

Cette section documente ce que le backend Tiinver (PHP/Slim, projet séparé, PAS modifié par ce
portage) doit implémenter pour que les appels fonctionnent quand le destinataire a l'app iOS tuée
ou verrouillée. Écrite le 2026-08-12, à la demande explicite de l'utilisateur, pour transmission à
l'équipe serveur — le code Swift ci-contre appelle déjà le point 1 (l'enregistrement du jeton), les
points 2-4 (déclenchement/relais/envoi APNs) restent entièrement à faire côté serveur.

**Pourquoi ce mécanisme existe (contexte, PAS présent côté Android)** : Android laisse FCM réveiller
le processus normalement pour recevoir un appel entrant (pas de mécanisme dédié séparé). iOS
l'interdit structurellement pour un appel : une app tuée/suspendue ne reçoit pas de notification
silencieuse fiable ni à temps. PushKit (notifications VoIP) est le SEUL mécanisme Apple garantissant
un réveil immédiat et prioritaire, avec une contrepartie stricte imposée par Apple (voir "Prérequis
Apple" plus bas).

### 1. Enregistrement du jeton VoIP — endpoint à créer, appelé par l'app iOS

- **Méthode/chemin** : `POST user/voip-token` (préfixé par la base REST existante,
  `infoContract.SERVER`/`APIEnvironment.restBaseURL` côté client — même serveur que tous les autres
  endpoints `user`/`deletemessage`/etc.)
- **En-têtes** : identiques à tout autre appel `APIClient.post` déjà en place — `Authorization:
  <apiKey brut, sans préfixe Bearer>`, `Content-Type: application/json; charset=utf-8`, `Accept:
  application/json` (voir `Networking/APIClient.swift`, contraintes non négociables déjà
  documentées).
- **Corps JSON** :
  ```json
  { "userId": "<id utilisateur>", "voipToken": "<jeton hex, 64 caractères minuscules>" }
  ```
  Le jeton est encodé en hexadécimal (PAS en Base64) — convention APNs/VoIP standard, voir
  `Calls/VoIPTokenRegistrar.swift`.
- **Enveloppe de réponse attendue** : même convention que le reste du backend (`"error":"false"` en
  succès, `"error":"true"`+`"message"` en échec — voir `JSONValue.isBackendSuccess`).
- **Action serveur attendue** : stocker `voipToken` associé à `userId` (nouvelle colonne, ex.
  `voip_token`, distincte de la colonne `fcmId` déjà utilisée pour les notifications push
  classiques) — voir aussi "Alternative" ci-dessous.
- **Fréquence d'appel côté client** : à CHAQUE fois que `PKPushRegistry` délivre un jeton
  (inscription initiale ET rotations — PushKit peut redonner un jeton différent plus souvent
  qu'APNs classique) — le serveur doit donc traiter cet appel comme un upsert (remplacer la valeur
  précédente), pas comme un ajout.
- **Alternative envisageable, PAS celle choisie ici** : le jeton FCM utilise en réalité un endpoint
  GÉNÉRIQUE `user` existant côté Android (`{"id":userId,"column":"fcmId","value":token}`, voir
  `Notifications/PushTokenRegistrar.swift`) plutôt qu'un endpoint dédié. Un endpoint dédié
  `user/voip-token` a été choisi ici sur demande explicite (plus lisible pour un flux entièrement
  nouveau, sans précédent Android à respecter) — le backend PEUT choisir de router cet appel vers la
  même logique générique `column="voipToken"` en interne si c'est plus simple à intégrer, tant que
  le CONTRAT (chemin, méthode, corps JSON ci-dessus) reste inchangé côté client.

### 2-4. Déclenchement d'un appel entrant app tuée — flux serveur à implémenter

1. **userA appelle userB** : l'app iOS de userA envoie déjà la signalisation d'appel normale sur le
   canal Socket.IO existant (`ChatRepository.calling`/`ROOM.CALL`+suffixes, voir tableau détaillé
   module 12 — CE point est déjà porté côté client, rien à changer ici).
2. **Le serveur reçoit cette signalisation** (comme aujourd'hui pour la signalisation de chat/appel
   classique) ET, EN PLUS, doit maintenant : chercher si userB a un `voipToken` enregistré (table
   utilisateurs, colonne ajoutée au point 1).
3. **Si un `voipToken` existe pour userB** : le serveur envoie une notification **PushKit** (PAS
   une notification Firebase/APNs classique — différence importante, voir "Prérequis Apple"
   ci-dessous) vers ce jeton, via APNs en mode VoIP. Payload recommandé (correspond à ce que
   `CallCoordinator.voIPPushManager(_:didReceiveIncomingCallPayload:)` décode côté client — voir
   `Models/ChatProfile.swift` pour le schéma complet) :
   ```json
   {
     "messageId": "<id du message voicecall>",
     "username": "<username de userA, l'appelant>",
     "nikname": "<nikname de userA>",
     "chatType": "chat",
     "to": "<username de userB>",
     "receiver": "<userId de userB>"
   }
   ```
   **Ce schéma de payload n'a PAS été confirmé par le serveur** (aucune implémentation Android
   équivalente à recouper) — c'est une PROPOSITION cohérente avec `ChatProfile`/le message
   `"voicecall"` normal, à valider/ajuster avec l'équipe serveur avant implémentation finale plutôt
   que supposé figé.
4. **iOS réveille l'app de userB via PushKit**, qui déclenche CallKit pour afficher l'écran d'appel
   natif (déjà porté côté client, `VoIPPushManager`/`CallKitManager`/`CallCoordinator`, voir tableau
   détaillé module 12) — même app fermée/verrouillée.
5. **Une fois l'appel accepté**, la connexion WebRTC (déjà portée, `RTConnection2`→
   `WebRTCConnection.swift`) démarre normalement entre userA et userB, par le canal de signalisation
   Socket.IO existant — aucun changement serveur supplémentaire nécessaire à ce stade.

### Prérequis Apple côté serveur (à générer dans le compte Apple Developer)

- **PAS le même certificat que les notifications push classiques.** Deux options, au choix de
  l'équipe serveur/DevOps :
  - **Clé d'authentification APNs (.p8)** — recommandée par Apple, une seule clé peut couvrir
    plusieurs apps/types de push (y compris VoIP) si le serveur l'utilise avec le bon `topic` par
    requête. Generée dans **Apple Developer → Certificates, Identifiers & Profiles → Keys**.
  - **Certificat APNs VoIP Services dédié (.p12/.pem)** — généré dans **Apple Developer →
    Certificates, Identifiers & Profiles → Certificates → Apple Push Notification service SSL
    (Sandbox & Production)**, en cochant explicitement le service **"VoIP Services Certificate"**
    pour l'identifiant d'app `com.tiinver.ios` — PAS le certificat "Apple Push Notification
    service" standard déjà utilisé pour Firebase/notifications classiques.
- **Topic APNs** : `com.tiinver.ios.voip` (suffixe `.voip` sur le bundle id, obligatoire pour un
  push PushKit — un push envoyé avec le topic de base `com.tiinver.ios` vers un jeton PushKit sera
  rejeté par APNs).
- **En-tête APNs requis** : `apns-push-type: voip` (obligatoire depuis iOS 13 — sans cet en-tête,
  APNs peut rejeter la requête ou le comportement de réveil peut être dégradé).
- **Priorité APNs recommandée** : `apns-priority: 10` (immédiat — un push VoIP DOIT arriver sans
  délai, la contrainte Apple côté app impose de répondre "en quelques secondes" après réception,
  voir avertissement `VoIPPushManager.swift`/`CallCoordinator.swift`).
- **Capacité app côté client (déjà en place, rien à faire)** : `UIBackgroundModes` contient déjà
  `voip` dans `project.yml` (ajouté dès un module antérieur) — nécessaire pour que PushKit puisse
  réveiller l'app.
- **Contrainte stricte de comportement app CONFIRMÉE par recherche croisée (pas une supposition)** :
  toute notification VoIP reçue DOIT déclencher `CXProvider.reportNewIncomingCall` de façon
  synchrone dans le rappel PushKit, sous peine de résiliation de l'app par iOS ET, en cas de
  non-conformité répétée, de désactivation du jeton VoIP par le système lui-même (télémétrie
  surveillée par Apple) — déjà respecté côté client (voir `CallCoordinator.
  voIPPushManager(_:didReceiveIncomingCallPayload:completion:)`, `completion()` appelé dès que
  CallKit a été notifié, pas après la préparation WebRTC complète).

## Backend à implémenter — Vérification StoreKit 2 (module 15, Wallet — spécification pour l'équipe serveur PHP/Slim)

Voir la section "⚠️ AUDIT CONFORMITÉ APP STORE — Wallet/Paiements" plus haut pour le contexte complet
(pourquoi ce nouveau point serveur remplace `purchaserequests`/`crypto/check-transaction` pour
l'achat de pièces, PAS pour le retrait/transfert qui restent inchangés).

### Endpoint appelé par l'app iOS

`POST storekit/verify-purchase`, appelé depuis `CoinStoreManager.creditAndReport` juste après
qu'une transaction StoreKit 2 a été validée CÔTÉ CLIENT (`VerificationResult.verified`) — **cette
vérification client N'EST PAS suffisante pour créditer des pièces en toute sécurité** (un appareil
compromis pourrait forger une transaction locale), le serveur DOIT revérifier auprès d'Apple avant
crédit définitif.

**Payload envoyé** (`application/x-www-form-urlencoded`, mêmes conventions que tous les autres
appels `APIClient.shared.post`) :
```
userId: <UserSession.shared.myId>
quantity: <nombre de pièces attendu pour ce palier — 250/500/1250/2500/5000>
productId: <identifiant du Product StoreKit, ex. "com.tiinver.ios.coins.500">
transactionId: <Transaction.id StoreKit 2, identifiant unique de CETTE transaction>
originalTransactionId: <Transaction.originalID — identique à transactionId pour un consommable>
```

### Flux serveur nécessaire

1. Recevoir la requête, retrouver l'utilisateur par `userId`.
2. **Vérifier authentiquement la transaction auprès d'Apple** — via l'**App Store Server API**
   (`GET /inApps/v1/transactions/{transactionId}`, authentifiée par une clé JWT signée avec une clé
   privée `.p8` générée dans App Store Connect, PAS le jeton `apiKey` Tiinver habituel) : confirmer
   que `productId`/`quantity` correspondent, que la transaction n'a pas déjà été traitée (table de
   déduplication par `transactionId`, un rejeu ne doit PAS créditer deux fois), et que le statut de
   transaction est valide (pas remboursée/révoquée — champ `revocationDate` de la réponse Apple).
3. Si valide et non déjà traitée : créditer `quantity` pièces au solde de l'utilisateur (même
   mécanisme que `rewardedCoins`/`purchaserequests` existants — mise à jour de la colonne `coins`),
   enregistrer la transaction comme traitée.
4. Répondre au client (même convention `{"error": "false"/"<message>"}` que le reste du backend).

### Prérequis Apple côté serveur

- **Clé App Store Server API (.p8)** — générée dans **App Store Connect → Utilisateurs et accès →
  Clés → App Store Server API** (PAS la même clé que celle utilisée pour l'API App Store Connect
  classique de gestion des builds, bien que le mécanisme de génération soit similaire). Nécessaire
  pour authentifier les appels serveur→Apple de l'étape 2.
- **Les 5 `Product` consommables doivent être créés dans App Store Connect** (`com.tiinver.ios.
  coins.250`/`500`/`1250`/`2500`/`5000`, type "Achat intégré consommable") avant que
  `CoinStoreManager.loadProducts()` puisse retourner quoi que ce soit côté client — sans ça,
  `BuyCoinsView` affichera une liste vide indéfiniment (pas une erreur silencieuse à chercher côté
  code, un prérequis de configuration App Store Connect).
- **Ce schéma n'a PAS été validé avec l'équipe serveur** (aucune implémentation Android équivalente
  à recouper, StoreKit 2 n'a pas d'équivalent direct dans le code Android existant) — proposition
  cohérente avec les conventions REST déjà observées ailleurs dans ce backend, à ajuster avec
  l'équipe serveur avant implémentation finale.

## CHECKPOINT 2 ATTEINT ET VALIDÉ (2026-08-11)

Les modules 7 et 8 de l'ordre de portage sont marqués `[x]` ci-dessus (Checkpoint 2 validé sur ce
périmètre réduit, pas 7-12 — voir "Règle de compilation par checkpoint" pour la décision et sa
justification). Conformément à la même règle :

**✅ CHECKPOINT 2 VALIDÉ (2026-08-11) — build Codemagic réussi, aucune erreur.** 5 itérations de
correction ont été nécessaires sur 4 builds successifs avant d'atteindre ce résultat (voir "Erreurs
rencontrées et résolues" pour le détail complet de chacune) :
1. Infrastructure CI — Metal Toolchain manquant sur la machine de build (`xcodebuild
   -downloadComponent MetalToolchain` ajouté à `codemagic.yaml`/`ios-build.yml`), PAS une erreur de
   code.
2. `Animems/MaskPreviewEditorPanelState.swift` — `struct` contenant une propriété stockée de son
   propre type (auto-référence interdite pour un type valeur), corrigé en extrayant un
   `Snapshot` dédié.
3. `Animems/AnimemesGestureController.swift:199` — conversion `Int`→`CGFloat` manquante sur les
   arguments `x`/`y` d'un `CGRect` (`obj.offsetX`/`obj.offsetY` sont des `Int`, fidèles à Android).
4. `Animems/LayerRenderer.swift:67`/`:162` — multiplication `Float`×`CGFloat` invalide
   (`featherPx`), corrigée par conversion explicite au point de calcul, cohérente avec le pattern
   `Float` (modèle)/`CGFloat` (rendu) déjà établi dans tout le module Animems.
Confirme concrètement : les ~22 shaders GPU du module 7 (`TiinverCameraShaders.metal`) compilent
SANS ERREUR (risque le plus élevé identifié avant ce build, maintenant levé) ; l'intégralité du
code Swift des modules 1 à 8 compile sans erreur, y compris le chemin bout-en-bout du module 8
(modèle → gestes → rendu → export → fusion GIF) et la logique d'état des ~14 vues custom d'édition.

Note honnête sur la nature de cette validation, comme pour le Checkpoint 1 : "compile sans erreur"
ne veut pas dire "vérifié à l'exécution" — aucun accès à un simulateur/device réel n'a permis de
vérifier le comportement visuel/interactif de quoi que ce soit (filtres caméra, gestes tactiles
Animems, rendu des calques, export vidéo). Voir "Points à vérifier en priorité au prochain build —
Module 8" pour la liste des points de risque comportementaux (pas de compilation) qui restent à
vérifier dès qu'un accès à un simulateur/device sera possible — indépendant de la suite du
portage, qui continue maintenant sur les modules 9-18.

## CHECKPOINT 1 ATTEINT ET VALIDÉ (2026-08-10)

Les modules 1 à 6 de l'ordre de portage sont tous marqués `[x]` ci-dessus. Conformément à la
"Règle de compilation par checkpoint" en tête de fichier :

**✅ CHECKPOINT 1 VALIDÉ (2026-08-10) — build Codemagic réussi, aucune erreur.** Build
`#6a7a2aabd5ae67eb2a755de2` (workflow `checkpoint-build`, `codemagic.yaml`), toutes les étapes
passées y compris "Build simulateur — vérification de compilation uniquement, sans signature"
(1m 34s). Confirme concrètement (pas une supposition) : résolution SPM complète des 9 packages
déclarés dans `project.yml` (dont `firebase-ios-sdk` 11.15+, corrigé au 1er échec — voir
"Erreurs rencontrées et résolues") ; compilation sans erreur de TOUS les fichiers Swift des
modules 1 à 6 (~50 fichiers, y compris les 3 stores Core Data indépendants et leurs 16 entités
via `CoreDataFetchable`/`CoreDataRepository`, corrigé au 2ᵉ échec — voir même section) ; aucune
erreur de liaison (linkage) sur les frameworks/packages tiers (Alamofire, Socket.IO-Client-Swift,
MetalPetal, Gifu, GoogleMobileAds, GoogleSignIn, FBSDK, WebRTC, Firebase). Les deux corrections
appliquées suite aux deux premiers échecs de build (`Missing package product 'FirebaseCore'` et
`protocol 'CoreDataFetchable' requirement 'fetchRequest()' cannot be satisfied by a non-final
class`, voir "Erreurs rencontrées et résolues" ci-dessous) sont donc désormais **VÉRIFIÉES PAR
BUILD RÉEL**, plus seulement formulées par lecture de documentation/règles du langage.
Le module 7 (Caméra) est donc démarré à partir de cette confirmation explicite.

Note honnête sur la nature de ce "complet" : les modules 4/5/6 contiennent des portées
volontairement réduites documentées et justifiées au cas par cas (`ProfileView.swift` partiel,
interactions like/commentaire/partage du module 6 différées, suggestions de follow exclues de
`NotificationsListView.swift`, etc.) — "complet" signifie ici "tous les écrans/flux atteignables
depuis l'app ont un équivalent réel fonctionnel, pas de placeholder texte", PAS "portage 1:1
exhaustif de chaque ligne des fichiers Android sources". Chaque réduction de portée est tracée
dans le tableau "Détail par module" et le journal de décisions, avec sa justification.

### Checkpoint 1 — Résumé pour build macOS

**0. Comment lancer le build sans machine macOS locale** : deux pipelines CI équivalents sont
maintenant configurés, compilation uniquement (pas de signature/publication) — `codemagic.yaml`
(workflow `checkpoint-build`) et `.github/workflows/ios-build.yml` (`workflow_dispatch` MANUEL).
Les deux nécessitent le secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` (contenu de
`Resources/GoogleService-Info.plist` encodé en base64) configuré côté plateforme choisie avant le
premier lancement — voir les commentaires en tête de chaque fichier pour la marche à suivre
exacte. Choix entre les deux : selon les crédits CI disponibles côté utilisateur, aucune
préférence technique.

**1. Fichiers à fournir AVANT de lancer `xcodegen generate` (secrets, pas fabriqués par ce portage) :**
- ~~`Resources/GoogleService-Info.plist`~~ **FOURNI ET INTÉGRÉ (2026-08-10)** — l'utilisateur a
  téléchargé le fichier réel depuis la console Firebase ; copié dans `Resources/`. A permis de
  CONFIRMER (pas supposer) le vrai bundle id iOS : `com.tiinver.ios` (clé `BUNDLE_ID`), corrigeant
  `com.tiinver.tiinverProject` utilisé précédemment par déduction indirecte — voir `project.yml`
  et la décision correspondante du journal. Les identifiants OAuth de
  `GoogleSignInCoordinator.swift` ont été mis à jour en conséquence (voir tableau).
- ~~`RemoteConfigDefaults.plist`~~ **FOURNI ET INTÉGRÉ (2026-08-10)** — `res/xml/remote_config_defaults.xml`
  lu en entier et converti fidèlement (39 clés, aucune valeur ajoutée), référencé par
  `Settings/FirebaseConfigManager.swift` (`remoteConfig.setDefaults(fromPlist:
  "RemoteConfigDefaults")`). Voir décision correspondante du journal.
- **Nouveau point identifié en intégrant `GoogleService-Info.plist`, PAS un fichier de ce dépôt** :
  la clé APNs (Apple Push Notifications, `.p8` ou certificat) doit être téléversée dans la
  console Firebase (Project Settings → Cloud Messaging → Apple app configuration) pour que
  Firebase Cloud Messaging puisse effectivement relayer les pushs vers les appareils iOS — sans
  cette clé côté console Firebase (pas côté code), `Messaging.messaging().token` peut réussir
  localement mais aucune notification ne sera jamais réellement délivrée. À vérifier par
  l'utilisateur dans la console Firebase, hors du périmètre de ce portage de code.

**2. Décisions sous incertitude à vérifier EN PREMIER (recherche par "HYPOTHÈSE"/"⚠️" dans le
tableau "Détail par module") :**
- `Realtime/TiinverSocket.swift` — handshake Socket.IO (`auth: {"token": apiKey}` via
  `.connectParams`) : mécanisme jamais confirmé contre l'API réelle de `Socket.IO-Client-Swift`.
  Point critique pour tout le chat/les appels temps réel.
- `Notifications/PushTokenRegistrar.swift` — `Messaging.messaging().token(completion:)` : signature
  exacte de l'API `FirebaseMessaging` pas vérifiée contre la documentation/le SDK réel résolu par
  SPM.
- ~~`PRODUCT_BUNDLE_IDENTIFIER` — changé de `com.tiinver.app` à `com.tiinver.tiinverProject`~~
  **RÉSOLU (2026-08-10)** : `com.tiinver.ios` CONFIRMÉ par `Resources/GoogleService-Info.plist`
  (clé `BUNDLE_ID`), plus une hypothèse à valider — `project.yml` mis à jour.
- `Feed/FeedView.swift` — défilement vertical par `TabView` pivoté (rotation -90°/+90°) : technique
  standard mais jamais vue rendue, aucun accès à un simulateur. Repli documenté vers
  `ScrollView`+`.scrollTargetBehavior(.paging)` si le rendu est mauvais (nécessite iOS 17+, décision
  utilisateur).
- ~~`GoogleSignInCoordinator.swift` — identifiants OAuth extraits de `google-services.json`~~
  **PARTIELLEMENT RÉSOLU (2026-08-10)** : `clientID` (iOS) CONFIRMÉ par
  `Resources/GoogleService-Info.plist`. `serverClientID` (web) reste réutilisé depuis
  `google-services.json` Android par recoupement de projet (justifié, pas une simple
  supposition — voir tableau/journal), mais jamais testé dans un flux `GIDSignIn` réel — à
  vérifier au premier essai de connexion Google sur l'app iOS compilée.

**3. Versions de packages SPM non vérifiées** (`project.yml`, choisies à la date du rapport de
faisabilité sans accès réseau pour vérifier leur existence réelle) : `Alamofire` 5.9+,
`Socket.IO-Client-Swift` 16.1+, `MetalPetal` 1.10+, `Gifu` 3.4+, `GoogleMobileAds` 11.0+,
`GoogleSignIn-iOS` 7.1+, `facebook-ios-sdk` 17.0+, `WebRTC` (stasel/WebRTC) 125.0+ — la résolution
de dépendances SPM au premier `xcodegen generate` + ouverture Xcode est le premier signal si une
version n'existe pas/plus. `firebase-ios-sdk` relevé à 11.15+ (voir "Erreurs rencontrées et
résolues" — `10.29+` causait `Missing package product 'FirebaseCore'` au build, cette fois
vérifié contre le `Package.swift` réel du SDK, pas juste une supposition de version disponible).

**4. Erreurs de compilation déjà connues et corrigées PENDANT le portage** (pour référence, éviter
de les re-signaler comme nouvelles — les 3 sont désormais VÉRIFIÉES PAR BUILD RÉEL, voir
"CHECKPOINT 1 ATTEINT ET VALIDÉ" plus haut) : `JSONValue.rawData` manquant (corrigé, voir
journal). `Missing package product 'FirebaseCore'` au premier build Codemagic (corrigé en
relevant `firebase-ios-sdk` à 11.15+, voir "Erreurs rencontrées et résolues"). `protocol
'CoreDataFetchable' requirement 'fetchRequest()' cannot be satisfied by a non-final class` (16
entités) au deuxième build Codemagic (corrigé en remplaçant `Self` par un `associatedtype
FetchResult` dans `CoreDataFetchable.swift` + contrainte `where Entity.FetchResult == Entity` sur
`CoreDataRepository`, voir "Erreurs rencontrées et résolues"). Le troisième build Codemagic
(#6a7a2aabd5ae67eb2a755de2, 2026-08-10) a confirmé les deux corrections et n'a révélé aucune
nouvelle erreur.

**5. Ce qui N'A PAS besoin d'être vérifié en priorité** (portées réduites déjà assumées et
documentées, pas des bugs à chercher) : absence d'interactions like/commentaire/partage sur le
feed (module 6, différé) ; `ProfileView.swift`/onglets Chat et Créateurs de `HomeShellView.swift`
volontairement incomplets (modules 11/17/18) ; textes d'onboarding et de notifications en français
provisoire (vraies chaînes localisées jamais lues) ; `UpdateAppView.swift` avec un lien App Store
placeholder (app pas publiée).

## Points à vérifier en priorité au prochain build — Module 8

Le prochain build Codemagic couvre les modules 7+8 ensemble. Par ordre de risque décroissant :

1. **`LayerRenderer.swift`/`AnimemesExporter.swift`** — déjà identifiés comme zone à haut risque
   avant cette session, TOUJOURS le point le plus critique : logique Core Graphics dense (couches
   de transparence imbriquées, blend modes `.destinationIn`/`.sourceAtop`/`.clear`),
   `AVAssetWriter` asynchrone avec un bug de capture de closure déjà trouvé et corrigé une fois
   (voir journal), jamais vue rendue ni exécutée. Gestion d'erreur incomplète assumée dans
   `AnimemesExporter` (valeurs de retour `Bool` de `append`/`startWriting` non vérifiées).
2. **`AnimemesGestureController.swift`** — logique de transformation vérifiée ligne à ligne contre
   l'original (2 bugs déjà trouvés/corrigés : `CGAffineTransform.inverted()` non-optionnelle,
   ordre de composition pré/post-multiplication), mais AUCUN câblage `DragGesture`/
   `MagnificationGesture`/`RotationGesture` SwiftUI n'existe encore — les maths sont fiables, leur
   assemblage en gestes multi-touch réels est entièrement non vérifié. Sémantique Android
   incrémentale vs SwiftUI cumulative (documentée en tête de fichier) à traiter explicitement au
   moment du câblage, pas une simple substitution 1:1 d'API.
3. **`TimelineViewModel.swift`** (nouveau, cette session — 1320 lignes source, le plus gros fichier
   individuel porté ce passage) — coordonnées/zoom/pan/drag/anti-chevauchement vérifiés
   formule par formule contre l'original, mais entièrement NON EXÉCUTÉS (pas de `Canvas` SwiftUI
   ni de gestes câblés dessus). Le point le plus fragile : `contentHalfWidth`/`contentQuarterWidth`
   (nommage Android trompeur conservé tel quel — c'est bien un QUART de la largeur scrollable qui
   sert de référence de centrage, pas une moitié malgré le nom) — si le playhead ne semble pas
   centré au premier rendu réel, vérifier CE calcul en premier avant de soupçonner autre chose.
4. **`AnimemesRecompose.swift`** (nouveau) — réutilise `LayerRenderer.drawObjectFrame` avec un
   contexte bitmap créé manuellement (flip Y appliqué, même motif que `MaskFactory`/
   `AnimemesExporter`) — si la fusion GIF produit un résultat inversé verticalement, ce flip est
   le premier suspect.
5. **`PaintCapture.swift`/`BezierEditorView.swift`/`CanvasZoomController.swift`** (nouveaux, auto-
   contenus, portés avec rendu+gestes SwiftUI complets) — jamais vus rendus. `PaintCaptureController`
   en particulier : le flip Y du contexte de dessin manuel (ajouté explicitement, voir commentaire
   dans le fichier) est nécessaire pour que les coordonnées tactiles dessinent au bon endroit — à
   vérifier en premier si le dessin au doigt apparaît décalé/inversé.
6. **Sous-systèmes découverts mais non explorés** (à garder en tête pour le planning, pas des bugs
   de compilation à chercher) : Motion Templates, persistance disque du recompose, tutoriel,
   génération de mouvement, génération IA, suppression d'arrière-plan ML Kit, ET le sous-système
   flipbook de `FrameAdapter.java` (`FrameData`/`Frame`/`SerializableManager`/`ImageViewRound`/
   `ButtonAddFrame`/ancien `MemesView`) ET le mode de transformation par curseur de
   `MovementControllerHandlerView` (`applySeekBarTransformOnAnchor`/`anchorTouchExecute`, non lus)
   — 8 sous-systèmes au total nécessitant chacun leur propre passage de lecture avant portage,
   listés en détail dans le tableau "Détail par module" et le journal.
7. **Ce qui n'a PAS besoin d'être vérifié en priorité** (portées réduites déjà assumées et
   documentées) : absence de PATH/LINE/CLIP/ERASE (liés au mode dessin-libre, pas encore branché
   au geste tactile) ; SwiftUI des panneaux d'édition à état seul porté (`LayerEditorPanelState`,
   `MaskPreviewEditorPanelState`, `ShapePreviewEditorPanelState`, `ProTextEditorState`) — leur
   construction visuelle n'existe pas encore, ce n'est pas un bug à chercher au build mais un
   travail futur déjà planifié.

## Prochaine action à faire

**CHECKPOINT 2 VALIDÉ (2026-08-11). Modules 7, 8, 9, 10, 11, 12 FERMÉS.** Module 12 (Appels WebRTC/
CallKit) fermé le 2026-08-12, dans la même session que la fermeture du module 11 : moteur WebRTC
(`RTConnection2.java`, 801 lignes),
orchestration (`CallService`/`CallViewModel`/`CallActivity`/`IncomingCallActivity`, 2071 lignes
cumulées) tous lus en entier, `RTConnection.java`/`RTConnection3.java`/`CallService2.java`
confirmés morts par grep (pas lus). CallKit/PushKit/WebRTC iOS vérifiés contre la documentation
Apple réelle, les bindings Xamarin officiels (recours quand la doc Apple ne rendait pas son contenu
JS) et les headers Objective-C bruts du framework WebRTC AVANT d'écrire le moindre code, comme
demandé explicitement pour ce module — 1 divergence d'API trouvée et corrigée pendant l'écriture
(`addIceCandidate:` sans variante à bloc de complétion), plusieurs bugs d'isolement d'acteur Swift
trouvés et corrigés en relisant le code (délégué `@MainActor` appelé depuis un contexte non isolé).
8 fichiers Swift nouveaux/étendus, plus le bouton d'appel + présentation `CallView` câblés dans
`ChatView.swift` (module 11) dans la même session, une fois le cœur du module 12 écrit — le flux
est donc déclenchable de bout en bout depuis l'écran de chat. Voir le tableau détaillé et l'entrée
de journal 2026-08-12 pour le détail complet.

**Réserves du module 12, fermé mais pas sans caveat** : (1) aucune compilation réelle n'a été
possible (environnement Windows sans Xcode, comme pour tout ce portage) — le cœur WebRTC/CallKit
est le code le plus complexe et le plus à risque écrit jusqu'ici, une vérification de compilation
réelle est prioritaire dès qu'un accès macOS existe ; (2) l'enregistrement du jeton VoIP CÔTÉ
CLIENT est câblé (2026-08-12, `VoIPTokenRegistrar.swift`), mais l'implémentation SERVEUR (stockage
du jeton, déclenchement du push VoIP via APNs) reste entièrement à faire — voir la section dédiée
"Backend à implémenter — PushKit/VoIP" pour la spécification complète à donner à l'équipe PHP ;
tant qu'elle n'est pas faite, le réveil "app tuée" n'est pas fonctionnel de bout en bout malgré le
code client prêt des deux côtés (émission ET réception) ; (3) `outgoingCallRepeatRunnable` (boucle
de re-notification) non branché.

**CHECKPOINT 2 toujours valide. Modules 13 (Shareboard) et 14 (Message Graphic) FERMÉS le
2026-08-12**, dans la continuité directe de la session qui a fermé le module 12 — voir l'entrée de
journal dédiée et le tableau "Détail par module", section Shareboard/Message Graphic, pour le détail
complet (7 fichiers Swift nouveaux dans `Shareboard/`, extensions de `ChatRepository`/`ChatViewModel`/
`ChatView`/`ChatBubbleViews`, 1 bug data-channel corrigé dans `WebRTCConnection.swift` avant d'écrire
le code Shareboard). **Réserves, non sans caveat** : (1) aucune compilation réelle possible (comme
tout ce portage) — c'est le plus gros volume de code Swift écrit en une seule session
(~1000 lignes), priorité de vérification au même niveau que le module 12 dès qu'un accès macOS
existe ; (2) portée délibérément réduite sur le pinch/rotate/suppression d'objet en direct (non
live-synced sur le fil, voir tableau) et sur le décoratif (bannières pub, tutoriel) — documenté, pas
un oubli ; (3) gap fonctionnel : pas de point d'entrée UI pour REJOINDRE un Shareboard déjà ouvert
par un pair (`status != 1`), seulement pour en démarrer un — voir dernier paragraphe du journal
2026-08-12 pour le détail exact du correctif à apporter (rendre `SystemInfoRow` "shareboard"
cliquable dans `ChatView`).

**MODULES 15 (Wallet), 16 (AdMob), 17 (Profil/Réglages) ET 18 (Divers) FERMÉS le 2026-08-12, même
session que 13/14, dans la continuité directe.** Les 18 modules de l'ordre de portage sont
désormais tous `[x]` — voir cependant "RÉSERVES AVANT CHECKPOINT 3" juste en dessous : plusieurs
fermetures portent des réserves explicites et documentées, notamment le module 18 qui priorise la
couverture fonctionnelle sur l'exhaustivité de lecture (Contacts/Statistiques/boost interne repérés
mais pas construits). Points marquants de cette portion de session :
- **Module 15 (Wallet)** : découverte que le fichier visé par l'analyse de faisabilité initiale
  pour l'achat de pièces (`BuyCoinsActivity.java`, Play Billing) est du CODE MORT — le vrai flux
  actif est un paiement mobile money/crypto HORS APPLICATION avec ID de transaction saisi à la
  main, un vrai risque de conformité App Store 3.1.1/3.1.5 plus sérieux que prévu. Remplacé par
  StoreKit 2 pour l'achat (sur instruction explicite), retrait/transfert/conversion/parrainage
  portés fidèlement. Voir "⚠️ AUDIT CONFORMITÉ APP STORE — Wallet/Paiements" et "Backend à
  implémenter — Vérification StoreKit 2", **À LIRE avant toute soumission**.
- **Module 16 (AdMob)** : SDK Google Mobile Ads iOS (nomenclature moderne sans préfixe `GAD*`)
  vérifié contre l'exemple officiel SwiftUI de Google avant écriture. Interstitiel classique
  confirmé mort (incertitude du rapport de faisabilité levée par grep).
- **Module 17 (Profil/Réglages)** : découvertes de code mort en cascade côté réglages (5/6 réglages
  de confidentialité granulaires commentés, "réglages de chat" qui ne sont en réalité qu'un thème
  clair/sombre) — même méthodologie de vérification que partout ailleurs dans ce portage.
- **Module 18 (Divers)** : le plus grand écart entre périmètre théorique (~54 fichiers Android) et
  couverture réelle de cette session — recherche/follow/signalement/commentaires/certification
  (consultation) portés avec lecture complète des fichiers réseau déterminants ; contacts (en
  réalité un sélecteur de membres de groupe, pas une fonctionnalité autonome), statistiques
  créateur et "boost interne" (système de promotion payante, sans rapport avec AdMob) repérés mais
  PAS construits — à reprendre dans une passe dédiée.

**RÉSERVES AVANT CHECKPOINT 3** (aucune n'est bloquante pour la fermeture des modules, toutes sont
documentées à l'endroit précis concerné, mais doivent être lues avant de considérer le portage
"terminé" au sens produit) :
1. **Aucune compilation réelle n'a été possible sur l'ensemble du projet** (environnement Windows
   sans Xcode, du premier au dernier module) — le Checkpoint 3 tel que défini en tête de fichier
   ("build final couvrant tout le projet") NE PEUT PAS être exécuté depuis cet environnement ;
   il nécessite un accès macOS/Xcode réel, la première étape concrète de toute suite à ce portage.
2. Zones à plus haut risque de compilation/exécution, par ordre de priorité de vérification
   recommandé : (a) module 12 (Appels WebRTC/CallKit) et module 13 (Shareboard, qui en dépend) —
   code le plus complexe du portage ; (b) module 15 (StoreKit 2 — nécessite des `Product`
   consommables créés dans App Store Connect, sans quoi `BuyCoinsView` reste vide indéfiniment,
   pas une erreur de code) ; (c) module 16 (AdMob — nécessite le SDK réellement lié et les
   entrées Info.plist prises en compte par Xcode) ; (d) modules 8-10 (Animems/Caméra/Trim,
   compilent déjà sans erreur au Checkpoint 2 mais jamais exécutés à l'écran).
3. Transferts de fichiers non résolus, RÉCURRENTS à travers plusieurs modules (upload photo de
   profil module 17, documents de certification module 18, pièces jointes chat module 11) —
   tous pointent vers le même gap non résolu : `UploadFileOrDataService.java`/
   `HttpFileUploader.java` (Android) jamais lus en détail dans ce portage. Une lecture dédiée de
   ces deux fichiers débloquerait plusieurs gaps d'un coup plutôt qu'un par un.
4. Backend à transmettre à l'équipe serveur PHP/Slim, DEUX sections indépendantes déjà rédigées :
   "Backend à implémenter — PushKit/VoIP" (module 12) et "Backend à implémenter — Vérification
   StoreKit 2" (module 15).

**PREMIER BUILD CODEMAGIC RÉEL DU CHECKPOINT 3 (2026-08-13) — ÉCHEC, 2 CORRECTIONS APPLIQUÉES,
CHECKPOINT 3 TOUJOURS NON VALIDÉ.** 16 erreurs, concentrées sur 2 fichiers seulement (voir détail
complet dans "Erreurs rencontrées et résolues") : (1) 11 erreurs "cannot find type in scope" dans
`Advertising/AdMobManager.swift` (`BannerView`/`RewardedAd`/`RewardedInterstitialAd`/`NativeAd`/
`AdLoader`/`NativeAdLoaderDelegate`) — cause réelle : `project.yml` épinglait `GoogleMobileAds` à
`from: 11.0.0`, alors que la nomenclature Swift sans préfixe `GAD*` utilisée dans ce fichier n'existe
qu'à partir du SDK 12.0.0 (confirmé par les notes de version Google ET le `project.pbxproj` réel de
l'exemple officiel, qui épingle `13.0.0`) — corrigé à `from: 13.0.0`. (2) 1 erreur `'Tool' is
inaccessible due to 'private' protection level` dans `Shareboard/ShareboardView.swift:187` — un
`enum` imbriqué `private` référencé depuis une extension à portée fichier ; corrigé en `internal`
(retrait de `private`). **Un nouveau build Codemagic est nécessaire pour confirmer ces deux
corrections — ne pas considérer le Checkpoint 3 comme atteint tant qu'il n'a pas eu lieu.**

**Méthodologie à conserver pour la suite** (inchangée depuis le début du projet) : lire le code
source Android réel avant de porter (jamais deviner depuis un nom de classe/méthode) ; vérifier
toute API tierce/framework Apple contre sa documentation ou ses headers réels avant de l'utiliser ;
documenter chaque décision, simplification et bug trouvé ; ne jamais marquer un module `[x]` sans
une note honnête sur ce qui est réellement porté vs différé — et, comme démontré cette session,
préférer laisser un module `[ ]` non coché plutôt que de compromettre cette règle pour tenir un
rythme.

**Points à ne pas oublier, indépendants du reste** :
- Les ~22 filtres GPU du module 7 et le chemin bout-en-bout du module 8 (Animems) compilent tous
  les deux SANS ERREUR (Checkpoint 2 validé) mais restent NON VÉRIFIÉS À L'EXÉCUTION (aucun accès
  simulateur/device) — voir "Points à vérifier en priorité au prochain build — Module 8" pour le
  détail par ordre de risque ; à garder en tête pour un futur accès à un simulateur, indépendant
  de la suite du portage.
- Le flou "feather" (`MaskFactory`/`BitmapCacheManager`/`LayerRenderer`, module 8) utilise
  `CIGaussianBlur` en approximation documentée d'un `BlurMaskFilter` Android — à comparer
  visuellement au premier rendu réel, écart possible mais non bloquant par nature.
- Handshake Socket.IO via `.connectParams`, rendu du `TabView` pivoté pour le scroll plein écran
  du feed (Checkpoint 1) : toujours NON VÉRIFIÉS VISUELLEMENT, sans rapport avec les modules
  suivants, à vérifier au premier accès à un simulateur/device réel.
- `PhotoCropView.swift` (module 9) : pas d'équivalent direct pour `handleFlip` dans l'API publique
  de `TOCropViewController` — point ouvert, voir tableau détaillé module 9.
- `project.yml` : package `TOCropViewController` ajouté (module 9), pas encore résolu par un build
  réel — même statut `ÉCRIT (NON COMPILÉ)` que le reste du code depuis le Checkpoint 2.
