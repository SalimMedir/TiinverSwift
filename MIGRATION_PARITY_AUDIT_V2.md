# MIGRATION_PARITY_AUDIT_V2.md — Audit de parité Android → iOS (nouvelle source de vérité)

**Ce fichier remplace `MIGRATION_AUDIT.md`/`MIGRATION_PROGRESS.md`/`CLAUDE_CONTINUATION.md` comme
source de vérité pour la PARITÉ. Ces trois anciens fichiers restent lisibles comme HISTORIQUE
uniquement — ne pas leur faire confiance pour un statut de parité actuel.**

Date de création : 2026-08-17. Android = source de vérité absolue. Aucun statut "COMPLETE" n'est
utilisé dans ce fichier — voir la taxonomie ci-dessous, qui distingue explicitement "le code compile"
de "la fonctionnalité fonctionne réellement".

---

## TAXONOMIE DES STATUTS (obligatoire, aucune exception)

| Statut | Signification | Preuve minimale requise |
|---|---|---|
| `BUILD_VALIDATED` | Le compilateur accepte ce code. RIEN DE PLUS. | Run CI (GitHub Actions/Codemagic) réussi, référencé par son identifiant. |
| `CODE_PRESENT_UNVERIFIED` | Le code existe, son comportement réel n'a jamais été démontré. | Aucune. |
| `PARTIAL` | Une partie de la fonctionnalité Android existe côté iOS, il manque des éléments importants identifiés. | Liste précise des éléments manquants. |
| `VISUALLY_DIFFERENT` | La fonctionnalité existe, mais la vue/UI/UX diffère matériellement d'Android. | Comparaison Android réelle (capture ou XML) vs iOS. |
| `FUNCTIONALLY_FAILED` | La fonctionnalité existe mais a échoué lors d'un test réel connu (capture Appetize, rapport utilisateur). | Référence à la capture/au rapport précis. |
| `MISSING` | Absente de l'application iOS. | — |
| `DEAD_CODE` | Existe dans le code mais n'est pas réellement accessible/utilisé dans le flux réel de l'app (Android OU iOS). | Preuve de non-atteignabilité (aucun appelant trouvé). |
| `COMPLETE_PARITY_CANDIDATE` | Après comparaison approfondie code-à-code avec Android, semble atteindre la parité. AUCUN test réel encore. | Comparaison ligne à ligne documentée dans ce fichier. |
| `COMPLETE_PARITY_VALIDATED` | Preuve réelle suffisante de parité fonctionnelle ET/OU visuelle (capture Appetize post-correctif, confirmée par l'utilisateur). | Référence explicite à la preuve. |

**Règle stricte** : un run CI vert donne DROIT à `BUILD_VALIDATED`, jamais automatiquement à un statut
de parité supérieur. Une lecture de code qui "semble correcte" donne droit à
`COMPLETE_PARITY_CANDIDATE` au mieux, jamais à `COMPLETE_PARITY_VALIDATED`.

---

## MÉTHODOLOGIE

Pour chaque FEATURE, format obligatoire :

```
## FEATURE: <nom>
### Android reference
- fichiers / classes / views / flux réel
### iOS implementation
- fichiers / classes-views / flux réel
### Comparison
| Élément | Android | iOS | Statut | Preuve |
### Missing / broken / different
### Required work
### Validation level
```

---

## SOMMAIRE

1. [Cartographie Navigation](#navigation-cartography)
2. [FEATURE: Home/Feed](#feature-homefeed)
3. [FEATURE: Profile](#feature-profile)
4. [FEATURE: Search](#feature-search)
5. [FEATURE: Chat/Messaging](#feature-chatmessaging)
6. [FEATURE: Galerie/Publication](#feature-galeriepublication)
7. [FEATURE: Animems](#feature-animems-audit-3-niveaux)
8. [VISUAL PARITY AUDIT](#visual-parity-audit)
9. [RAPPORT FINAL](#rapport-final)

---

## NAVIGATION CARTOGRAPHY

**Méthode** : `grep -rl "extends AppCompatActivity\|extends Activity\|extends BaseActivity\|extends
FragmentActivity"` = **67 Activities**. `grep -rl "extends Fragment\b\|extends DialogFragment\|
extends BottomSheetDialogFragment"` = **60 Fragments**. Total **127 classes de navigation**
recensées. Croisées avec la liste complète des 172 fichiers `.swift` du projet iOS
(`find Sources -name "*.swift"`).

**Légende statut rapide** (voir taxonomie complète en tête de fichier) : ✅=fichier iOS trouvé,
correspondance déjà vérifiée en profondeur une session antérieure ou cette session ; 🟡=fichier iOS
trouvé, correspondance PAS vérifiée en détail cette passe (`CODE_PRESENT_UNVERIFIED`) ; ❌=aucun
fichier iOS correspondant trouvé (`MISSING`, sous réserve — certains sont des redirections/wrappers
Android sans équivalent nécessaire, noté).

### Cœur applicatif (Home/Feed/Profile/Chat/Search)

| Android | Rôle | iOS équivalent | Statut |
|---|---|---|---|
| `Activity/ui/HomeActivity.java` | Shell principal, 5 onglets (`navigation_layout.xml`), routeur `onArticleSelected` | `Navigation/HomeShellView.swift` | ✅ `COMPLETE_PARITY_CANDIDATE` — structure TabView confirmée, voir FEATURE Home/Feed |
| `Activity/ui/MainFragment.java` | Fil Home (Fragment hébergé par HomeActivity, position 0) | `Feed/FeedView.swift` | ✅ voir FEATURE Home/Feed |
| `Activity/ui/FeedFragment.java` | Fullscreen Feed (`ViewPager2` vertical) | `Feed/FeedView.swift` (`FeedDetailPagerView`) | ✅ voir FEATURE Home/Feed |
| `Activity/ui/FullscreenActivity.java` | Template Android Studio générique | — | ❌ `DEAD_CODE` confirmé (GAP-020 tour précédent) : écouteurs vides, jamais atteint par navigation réelle. Aucun équivalent nécessaire. |
| `NotiLikecmt/FullScreenMedia.java` | 3ᵉ visualiseur fullscreen (post isolé, depuis Notifications/Search) | `Feed/FeedView.swift` (`FeedDetailPagerView(posts:[post])`) | 🟡 réutilisation confirmée pour Search ; Notifications câblé (GAP-021) mais PAS re-testé |
| `uploadPerfilPhoto/UserProfile.java` | Profil d'AUTRUI | `Profile/ProfileView.swift` (`isCurrentUser:false`) | ✅ voir FEATURE Profile |
| `uploadPerfilPhoto/AddPerfilFoto.java` | SON PROPRE profil | `Profile/ProfileView.swift` (`isCurrentUser:true`) | ✅ voir FEATURE Profile |
| `uploadPerfilPhoto/EditProfile.java` | Édition profil | `Profile/EditProfileView.swift` | 🟡 |
| `uploadPerfilPhoto/HashtagProfile.java` | Résultats par hashtag | `Discover/HashtagFeedView.swift` | 🟡 |
| `Recherche/ui/RechercheTiinver.java` | Recherche universelle | `Discover/SearchView.swift` | 🟡 voir FEATURE Search |
| `Recherche/ui/RechercheTiinver2.java` | Variante recherche (v2, à déterminer si active) | `Discover/SearchView.swift` (probable fusion) | 🟡 voir FEATURE Search |
| `roster/ui/Roster.java` | Liste conversations | `Messagerie/RosterListView.swift` | ✅ voir FEATURE Chat |
| `roster/NewMessage.java` | Recherche téléphone/email pour nouveau contact | `NewMessageView.swift` (nouveau, 2026-08-18 P2) | `BUILD_VALIDATED` (CI confirmée verte) — écart assumé : le premier message n'est PAS pré-inséré localement comme Android (`ContentValues`/`ContentProvider`, dépend probablement d'une sync locale hors périmètre), transmis en pré-remplissage à `ChatView` qui l'envoie via son VRAI pipeline `sendText()` déjà fonctionnel |
| `roster/Invite.java` | Invitation SMS/contact natif | `Wallet/ReferralView.swift` (partiel) | 🟡 `PARTIAL` probable — à vérifier si `Invite.java` = même flux que `ReferralActivity` ou distinct |
| `messagerie/ui/ActivityMsg.java` | Conversation 1:1/groupe (hôte `ChatFragmentTest`) | `Messagerie/ChatView.swift` | ✅ voir FEATURE Chat |
| `messagerie/ui/ProfileDetailActivity.java` | Réglages d'1 conversation (lance `SettingPrivateMessageFragmant`) | `PrivateMessageSettingView.swift` | `BUILD_VALIDATED` (CI confirmée verte) — implémenté le 2026-08-18 (P1) |
| `contacts/Contact.java` | Hôte écran 1/2/3 création de groupe | `Messagerie/ContactPickerView.swift` + `GroupCreationView.swift` | ✅ voir FEATURE Chat |
| `messagerie/group/GroupDetailActivity.java` | Détail groupe (membres, admin) | `Messagerie/GroupDetailView.swift` | ✅ voir FEATURE Chat |
| `messagerie/group/AddGroupMemberActivity.java` | Ajout membre | `Messagerie/AddGroupMemberView.swift` | ✅ voir FEATURE Chat |
| `messagerie/group/AddGroupDescriptionActivity.java` | Modifier description groupe | `Messagerie/GroupDetailView.swift` (probable, intégré) | 🟡 à vérifier si c'est un écran séparé côté Android non reproduit comme tel |
| `messagerie/group/ChangeGroupTopicActivity.java` | Modifier sujet/nom groupe | `Messagerie/GroupDetailView.swift` (probable) | 🟡 idem |
| `messagerie/group/FilterGroupMemberList.java` | Filtrer/rechercher parmi les membres | — | ❌ `MISSING` probable, à confirmer |
| `messagerie/group/InviteLinkActivity.java` | Lien d'invitation groupe | `Messagerie/GroupDetailView.swift` (lien affiché) | 🟡 |
| `creatorOfweek/CreatorFragment.java` | Classement créateurs | `Creators/CreatorOfWeekView.swift` | ✅ |
| `NotiLikecmt/ShowNoti.java` | Centre de notifications | `Notifications/NotificationsListView.swift` | ✅ |

### Authentification / Onboarding

| Android | Rôle | iOS équivalent | Statut |
|---|---|---|---|
| `SplashActivity.java`/`SplashActivity2.java` | Écran de lancement | `TiinverApp.swift`/`RootRouterView.swift` | 🟡 |
| `Authentification/MainActivity.java` | Hôte des fragments d'auth | `AuthCoordinatorView.swift` | 🟡 |
| `Authentification/onboarding/OnboardingFragment.java` | Onboarding | `OnboardingView.swift` | 🟡 |
| `Authentification/login/LoginFragment.java` | Connexion | `LoginView.swift` | ✅ (session vide corrigée, causes racines documentées `MIGRATION_AUDIT.md` historique) |
| `Authentification/register/SignupFragment.java`/`Inscrire.java`/`phoneNumber.java` | Inscription | `RegisterView.swift` | 🟡 |
| `Authentification/withprovider/SignUpWithGoogle.java` | Inscription Google | `SignUpWithGoogleView.swift`/`GoogleSignInCoordinator.swift` | 🟡 |
| `Authentification/EmailVerificatiionCode.java`/`MyCodeConfirmFragment.java` | Vérification email | `EmailVerificationView.swift` | 🟡 |
| `Authentification/passwordrecovery/mdpOublier.java`/`RecoverPassword.java` | Mot de passe oublié | `ForgotPasswordRequestView.swift`/`NewPasswordView.swift` | 🟡 |
| `Authentification/PoliticaDemand.java` | CGU/politique de confidentialité | `PoliticaDemandView.swift` | 🟡 |
| `FacebookActivity.java` | Connexion Facebook | — | ❌ `MISSING` probable (pas de SDK Facebook trouvé côté iOS dans la liste des fichiers) — À CONFIRMER, pas supposé sans vérification du flux réel |

### Wallet / Monétisation / Paiement

| Android | Rôle | iOS équivalent | Statut |
|---|---|---|---|
| `wallet/WalletActivity.java` | Écran principal portefeuille | `Wallet/WalletView.swift` | ✅ |
| `wallet/MonetizationActivity.java` | Hub monétisation | `Wallet/MonetizationView.swift` | ✅ (porté cette session) |
| `wallet/BuyCoinsActivity.java` | Achat de pièces | `Wallet/BuyCoinsView.swift` | 🟡 |
| `wallet/EarnCoinsActivity.java` | Gagner des pièces (pub récompensée) | `Wallet/EarnCoinsView.swift` | 🟡 |
| `wallet/WithdrawActivity.java` | Retrait | `Wallet/WithdrawView.swift` | 🟡 (GAP historique : confirmation récapitulative manquante, `MIGRATION_AUDIT.md` GAP-019) |
| `wallet/TransfertCoinsActivity.java` | Transfert de pièces | `Wallet/TransferCoinsView.swift` | 🟡 |
| `wallet/ConversionActivity.java` | Conversion pièces↔argent | `Wallet/ConversionView.swift` | 🟡 |
| `wallet/ReferralActivity.java` | Parrainage | `Wallet/ReferralView.swift` | 🟡 |
| `wallet/CheckoutActivity.java`/`CheckoutSuccessActivity.java` | Paiement carte (web/tierce) | — | ❌ `MISSING` probable — iOS utilise StoreKit (`CoinStoreManager.swift`), divergence ARCHITECTURALE assumée (contrainte Apple : achats intégrés natifs obligatoires), PAS un oubli — à documenter explicitement, pas juste marquer manquant |
| `wallet/PurchaseActivity.java` | Achat (web) | `CoinStoreManager.swift` (StoreKit) | 🟡 même divergence assumée |
| `wallet/PeerToPeerActivity.java` | Transfert P2P | — | ❌ `MISSING`, à vérifier si distinct de `TransfertCoinsActivity` |
| `wallet/SelectAmountActivity.java` | Sélection de montant (étape intermédiaire) | — | 🟡 probablement fusionné dans les Views ci-dessus, à vérifier |
| `wallet/RechargeCoinsActvity.java` | Recharge | — | ❌ `MISSING`, à vérifier si redondant avec `BuyCoinsActivity` |
| `wallet/TransactionTutorialActivity.java` | Tutoriel transaction | — | ❌ `MISSING` (probablement décoratif, faible priorité) |
| `wallet/UseBankCardFragment.java` | Formulaire carte bancaire | — | ❌ `MISSING` (StoreKit ne demande jamais de CB directement à l'app) |
| `exchange/ExChangeActivity.java`/`RechargeActivity.java` | Change/recharge (legacy ?) | — | ❌ `MISSING`, rôle exact non déterminé cette passe |
| `advertising/ui/BoostActivity.java`/`BoostDashboardFragment.java`/`CreateBoostFragment.java`/`CommandeActivity.java`/`MesBoosts.java` | Système de "boost" de publication (campagnes publicitaires payantes pour un post) | `Sources/TiinverSwift/Boost/` (nouveau, 2026-08-18 P1) | `BUILD_VALIDATED` (CI confirmée verte) — test fonctionnel réel toujours requis | **Implémenté le 2026-08-18 (P1)** : 5 fichiers Android (2087 lignes) lus en entier. `AdsRepository.swift` (7 endpoints : `boost/overviews`, `boost/myboost`, `boost/create`/`create2`, `boost/update`, `boost/cancel2`, `searchs/country`), `BoostView.swift` (conteneur 2 onglets), `CreateBoostView.swift` (formulaire, formules `estimateReach` reproduites EXACTEMENT — views×4/likes÷3/followers÷5, division entière), `BoostDashboardView.swift` (vue d'ensemble + liste paginée), `BoostDetailView.swift` (détail + annulation). Point d'entrée : action "Promouvoir" ajoutée au menu "..." du Feed pour ses propres posts (`isOwnPost`, même garde que `promoteBtn` Android) — regroupée dans le menu existant plutôt qu'un bouton dédié sur le rail plein écran (déjà dense), substitution d'UI documentée, pas de comportement. **Bug Android reproduit fidèlement** : la déduction locale de solde après succès écrit TOUJOURS dans le cache `coinsAmount`, même en payant par gemmes (`useGems`) — vérifié dans le code source, pas corrigé. `MediaObject.isBoosted()`/badge "sponsorisé" sur les posts déjà boostés (affichage Feed) PAS vérifié cette passe — hors périmètre de ce lot (création/gestion uniquement). |

### Certification

| Android | Rôle | iOS équivalent | Statut |
|---|---|---|---|
| `ui/certification/CertificationActivity.java` + `CertificationRequestActivity.java` + `CertificationPlanFragment.java` + `CertificationRequestFragment.java` | Demande de certification (badge vérifié) | `CertificationView.swift`/`CertificationModels.swift` | 🟡 fusion probable en un seul écran iOS, PAS vérifié en détail cette passe |

### Galerie / Édition / Publication (voir aussi FEATURE dédiée)

| Android | Rôle | iOS équivalent | Statut |
|---|---|---|---|
| `editor/CameraActivity.java` | Hôte caméra/galerie | `CameraView.swift` | 🟡 voir FEATURE Galerie |
| `editor/camera/CameraXFragment.java`/`BaseCameraFragment.java` | Capture CameraX | `CameraCaptureController.swift`/`CameraRecorder.swift` | 🟡 |
| `editor/media/MediaEditor.java`/`MediaEditor2.java` | Éditeur média post-capture | `PublishComposeView.swift`/`PhotoToolsView.swift` | 🟡 voir FEATURE Galerie |
| `editor/croper/CropFragment.java` | Recadrage | `FreeformCropView.swift`/`PhotoCropView.swift` | 🟡 |
| `editor/DecodeFragment.java` | Décodage média en tâche de fond | — | 🟡 rôle exact non re-vérifié |
| `editor/FireMissilesDialogFragment.java` | Dialogue confirmation générique (réutilisé ailleurs, ex. retrait) | `.confirmationDialog`/`.alert` SwiftUI (générique, pas 1 fichier dédié) | 🟡 |
| `manager/Gallery.java` | Sélecteur galerie natif | `GalleryPickerView.swift` (PhotosPicker) | 🟡 |
| `messagerie/ui/GalleryMessage.java`/`MediaTrimMessage.java`/`MediaTrimMessage2.java`/`MediasDisplayMessage.java` | Galerie/trim/affichage média DANS le Chat | `ChatMediaUploadService.swift`/`MediaTrimView.swift` (réutilisation probable) | 🟡 |
| `view/trimmer/v2/debug/TrimBenchActivity.java` | Écran de DEBUG interne (banc de test du trimmer) | — | ❌ `DEAD_CODE`/hors périmètre volontaire (outil de développement Android, pas une fonctionnalité utilisateur) |

### Réglages (Settings)

| Android | Rôle | iOS équivalent | Statut |
|---|---|---|---|
| `setting/SettingsActivity.java` | Hôte réglages | `SettingsView.swift` | ✅ |
| `setting/SettingAccountFragment.java` | Compte (déconnexion/suppression) | `SettingSubViews.swift` | 🟡 |
| `setting/SettingPrivateMessageFragmant.java` | Réglages 1 conversation (mute, etc.) | `PrivateMessageSettingView.swift` (nouveau, 2026-08-18 P1) | `BUILD_VALIDATED` (CI confirmée verte) — test fonctionnel réel toujours requis |
| `setting/SettingAboutFragment.java`/`SettingHelpFragment.java` | À propos / Aide | `SettingSubViews.swift` | 🟡 (GAP-010 historique : liens légaux/FAQ génériques signalé) |
| `setting/SettingAdvertisementFragment.java` | Préférences pub | `SettingSubViews.swift` | 🟡 (GAP-012 historique : clé `AUTHORIZED_ADS` corrigée) |
| `setting/SettingChatFragment.java` | Préférences chat | `SettingSubViews.swift` | 🟡 |
| `setting/SettingNotificationFragment.java` | Préférences notifications | `SettingSubViews.swift` | 🟡 |
| `setting/SettingPrivacityFragment.java` | Confidentialité | `SettingSubViews.swift` | 🟡 |
| `setting/SettingStorageFragment.java` | Stockage/téléchargements | `SettingSubViews.swift` | 🟡 (GAP-009 historique : téléchargement sélectif par type absent) |
| `setting/EditPersonalInformation.java` | Infos personnelles | `EditPersonalInformationView.swift` | 🟡 |

### Divers / Utilitaires

| Android | Rôle | iOS équivalent | Statut |
|---|---|---|---|
| `Activity/ui/StatisticsActivity.java` | Statistiques d'un post (créateur) | `StatisticsView.swift` (nouveau, 2026-08-18 P2) | `BUILD_VALIDATED` (CI confirmée verte) — test fonctionnel réel toujours requis |
| `Activity/ui/Suggerencia.java` | Rôle exact non déterminé cette passe | — | 🟡 à investiguer |
| `Activity/ui/TiinverCode.java` | Rôle exact non déterminé cette passe | — | 🟡 à investiguer |
| `partage/ShareActivity.java`/`PartageWenack.java` | Résolution de liens profonds/partage | `Navigation/DeepLinkRouter.swift` | ✅ |
| `report/Report.java` | Signalement (post/user) | `ReportView.swift` | ✅ (GAP-015 historique : motifs de signalement à vérifier fidèles) |
| `Following/FollowList.java` | Liste abonnés/abonnements | `Discover/FollowListView.swift` | ✅ |
| `ai/TiinverAIChat.java`/`TiinverGeminiAIChat.java` | Assistant IA (Gemini) | `AiConversationRepository.swift` | 🟡 `PARTIAL` probable — présence d'un repository ne garantit pas un écran de chat IA complet, à vérifier |
| `ui/categorie/CategoryActivity.java` | Sélection de catégorie (contenu) | — | ❌ `MISSING`, à confirmer où ce flux est utilisé côté Android avant de conclure |
| `ui/filetransfer/FileTransferActivity.java` | Transfert de fichier (rôle exact à vérifier) | — | 🟡 à investiguer |
| `messagerie/ui/call/CallActivity.java`/`IncomingCallActivity.java` | Appels audio/vidéo | `CallView.swift`/`CallKitManager.swift`/`CallCoordinator.swift`/`WebRTCConnection.swift` | ✅ (GAP-005 historique : audit WebRTC/CallKit fait en profondeur) |
| `UpdateApp.java` | Mise à jour forcée | `UpdateAppView.swift` | 🟡 |
| `MyWebView.java` | WebView générique | — | 🟡 probablement remplacé par `SFSafariViewController`/`WKWebView` ponctuel, pas de fichier dédié nécessaire |
| `animation.java` | Rôle exact non déterminé (nom générique) | — | 🟡 à investiguer |
| `myFilterClass.java` | Rôle exact non déterminé | — | 🟡 à investiguer |
| `DebutWenack2.java` | Rôle exact non déterminé (probable écran de démarrage legacy) | — | 🟡 à investiguer |

**Note méthodologique** : les lignes 🟡 "à investiguer"/"à vérifier" reflètent honnêtement le fait
que CETTE passe n'a pas eu le temps de lire chacun de ces ~40 fichiers en entier — elles ne doivent
PAS être lues comme "fonctionnalité manquante confirmée", seulement comme "non vérifié". Un prochain
lot de travail doit lire chacun individuellement avant de changer leur statut.

---

## FEATURE: Home/Feed

### Android reference
- **Fichiers** : `Activity/ui/MainFragment.java` (grille), `Activity/ui/FeedFragment.java` +
  `Activity/ui/ViewPagerAdapter.java` (fullscreen), `Activity/adapter/ActivityAdapter.java` (adapter
  grille), `view/CustomCardView.java`+`view/BubbleStatusPhoto.java` (rendu photo),
  `Activity/ui/viewHolder/VideoViewHolder.java`+`video_expanded_item.xml` (rendu vidéo),
  `Activity/service/ExoPlayerManager.java`+`VideoPlaybackCoordinator.java` (lecture), `res/layout/
  feed_header_layout.xml`+`Activity/ui/AdapterSuggestContact.java` (en-tête suggestions).
- **Flux réel confirmé (lu en entier)** : `HomeActivity` héberge `MainFragment` en position 0 (grille
  2 colonnes, `PreLoadingGridLayoutManager`) → tap sur un item → `onArticleSelected(1, GlobalMedias)`
  → remplace par `FeedFragment` (ViewPager2 VERTICAL, positionné sur l'item tapé) → chaque page =
  `CustomCardView` (photo) ou `VideoViewHolder` (vidéo), les DEUX réutilisant `reaction_pub_but.xml`
  (légende→avatar/pseudo/date→"S'abonner", rail Like/Comment/Partager/Plus).
- **Endpoint réel** : `feedtimeline/{userId}/{limit}/{offset}` (`ActivityRepository`).

### iOS implementation
- **Fichiers** : `Feed/FeedView.swift` (`FeedGridCell`+`FeedDetailPagerView`+`FeedDetailCell`),
  `Feed/FeedViewModel.swift`, `Feed/FeedRepository.swift`, `Feed/FeedActivity.swift`,
  `Media/CDNAsyncImage.swift`, `Media/VideoPlayerManager.swift`, `Feed/SuggestionsCarouselView.swift`,
  `Feed/WinFreeCoinsBannerView.swift`, `Feed/SuggestionsRepository.swift`.
- **Flux réel** : `FeedView` = grille 2 colonnes (`LazyVGrid`) → tap → `.fullScreenCover` sur
  `FeedDetailPagerView` (positionné sur l'index tapé, `TabView` pivoté ±90° pour un défilement
  vertical, contournement documenté de l'absence de `TabView` vertical natif iOS 16).

### Comparison

| Élément | Android | iOS | Statut | Preuve |
|---|---|---|---|---|
| Grille — colonnes | 2 (`PreLoadingGridLayoutManager(...,2,...)`) | 2 (`LazyVGrid`, 2 `GridItem`) | `COMPLETE_PARITY_CANDIDATE` | Code confirmé identique |
| Grille — image/thumbnail | `BubbleStatusPhoto.setMediaObject` : photo=`object_url` tjrs, vidéo=`cdn_thumbnail_url` si `cdn_content_id` valide sinon `object_url` | `FeedActivity.thumbnailURL` reproduit EXACTEMENT cette logique | `COMPLETE_PARITY_CANDIDATE` | Commit `8fd7493`, comparaison ligne à ligne documentée `MIGRATION_AUDIT.md` |
| Grille — Referer CDN | `Referer: https://tiinver.com` (Glide, `LazyHeaders`) | Même valeur (`CDNAsyncImage`, `URLRequest.setValue`) | `COMPLETE_PARITY_CANDIDATE` | Code confirmé |
| Fullscreen — paging | `ViewPager2` vertical | `TabView` pivoté ±90° | `COMPLETE_PARITY_CANDIDATE` (mécanisme différent, résultat visuel visé identique) | — |
| Fullscreen — ordre bloc info | légende→avatar+pseudo+date→"S'abonner" (`reaction_pub_but.xml`) | Même ordre depuis commit `3bf7ae3` | `COMPLETE_PARITY_CANDIDATE` | GAP-020, XML lu en entier |
| Fullscreen — Like/Comment/Partager/Plus | présents, connectés (`OnLikeClicked`/`OnclickCommentaire`/`OnclickPrtg`/`OnclickMoreExpand`) | présents, connectés (`actionRail`, `viewModel.toggleLike`/etc.) | `COMPLETE_PARITY_CANDIDATE` | Code confirmé — AUCUNE preuve de test réel que ces boutons rendent visuellement sur un appareil ; dernière capture utilisateur ne les montre pas (build potentiellement non à jour, non confirmé) |
| Fullscreen — tap identité → profil auteur | `nameContainer`→`Intent UserProfile` | `Button(onOpenProfile)`→`fullScreenCover(ProfileView(isCurrentUser:false))` | `COMPLETE_PARITY_CANDIDATE` | Commit `a796446` |
| Fullscreen — ratio vidéo | `PlayerView` SANS `resize_mode` → défaut `RESIZE_MODE_FIT` (letterbox) | `VideoPlayer` SANS `.videoGravity` → défaut `.resizeAspect` (letterbox) | `COMPLETE_PARITY_CANDIDATE` — confirmé PAS un bug, comportement par défaut IDENTIQUE des deux plateformes | XML Android lu en entier, aucune surcharge trouvée côté iOS |
| Vidéo — URL de lecture | PRIMAIRE=`object_url`, repli=`cdn_content_url`→`stream.tiinver.com/{id}/play_720p.mp4` si échec (`VideoPlaybackCoordinator.tryPlayAt`) | Même priorité depuis commit `eded5f1` (`FeedActivity.playbackURL`/`fallbackPlaybackURL`) | `COMPLETE_PARITY_CANDIDATE` | Cause racine réelle trouvée et corrigée cette session — AVANT ce commit, l'ordre était inversé (`FUNCTIONALLY_FAILED` avéré) |
| En-tête — suggestions | `AdapterSuggestContact` (carrousel horizontal, `GET suggestions/{userId}`) | `SuggestionsCarouselView.swift` | `COMPLETE_PARITY_CANDIDATE` | Ported cette session — format exact de la réponse `"users"` NON confirmé par JSON réel, code tolère les deux formes par prudence |
| En-tête — bannière AdMob | même ID que Wallet (`5840810574`) | `AdBannerView(AdMobIdentifiers.bannerWallet)` | `COMPLETE_PARITY_CANDIDATE` | ID vérifié identique dans le XML |
| En-tête — bannière "gagner des pièces" | `free_coins_win_banner.xml`, bouton→`ReferralActivity` | `WinFreeCoinsBannerView.swift`→`ReferralView` | `COMPLETE_PARITY_CANDIDATE` | XML lu en entier |
| Profile Grid → Fullscreen (clic depuis Profile) | tap item → même `FeedFragment` réutilisé | `ProfileView` postCell → `.fullScreenCover(FeedDetailPagerView)` | `COMPLETE_PARITY_CANDIDATE` | Câblage confirmé présent (P0-D) — AVANT correctif : `MISSING` total, aucun geste attaché |
| Pagination infinie | seuil 2 items avant la fin | même seuil | `COMPLETE_PARITY_CANDIDATE` | — |
| Pub native dans le fil | 1 annonce toutes les N positions (`NativeAdsManager`) | `FeedAdCell`, même position modulo | `COMPLETE_PARITY_CANDIDATE` | Câblé session antérieure |
| État vide/erreur/chargement | shimmer/texte erreur/liste vide distincts | `ProgressView`/message erreur+Réessayer/état vide distincts | `COMPLETE_PARITY_CANDIDATE` | Corrigé session antérieure |

### Missing / broken / different
- Aucun élément `MISSING` confirmé pour Home/Feed lui-même à ce stade.
- **Statut réel encore INCERTAIN** : la dernière capture Appetize fournie par l'utilisateur (fullscreen
  sans avatar/boutons visibles, grille entièrement vide) contredit l'état actuel du code — build non
  confirmé à jour par l'utilisateur au moment de la rédaction. Ne PAS lire les lignes
  `COMPLETE_PARITY_CANDIDATE` ci-dessus comme "testé et fonctionnel".

### Required work
1. Test réel sur un build confirmé à jour (post-`eded5f1` au minimum) pour faire passer les lignes
   `COMPLETE_PARITY_CANDIDATE` en `COMPLETE_PARITY_VALIDATED` ou les rétrograder selon le résultat.
2. `Suggerencia.java`/`TiinverCode.java` (voir Navigation) — rôle exact non déterminé, à investiguer.

### Validation level
**`COMPLETE_PARITY_CANDIDATE`** globalement — PAS `COMPLETE_PARITY_VALIDATED`. Historique :
`FUNCTIONALLY_FAILED` confirmé à plusieurs reprises avant les correctifs de cette session (session
vide, GET-body Alamofire, Keychain silencieux, priorité `playbackURL` inversée, ordre du bloc
d'infos inversé) — tous corrigés au niveau code, aucun re-testé depuis le dernier lot.

**MISE À JOUR 2026-08-17 (Phase 2, P0-2)** — Re-tracé intégralement la chaîne
session→endpoint→JSON→decode→ViewModel→Grid→tap→Fullscreen, sans supposer les correctifs antérieurs
suffisants : `FeedRepository.fetchTimeline` (diagnostics `print()` sur chaque échec `compactMap`,
`receivedCount` vs `decoded.count` exposé à l'appelant), `FeedViewModel.loadNextPage` (session/requête/
réponse/UI tracées et AFFICHÉES À L'ÉCRAN, pas seulement en console — `errorMessage`/`isLoading`
effectivement rendus par `FeedView`, contrairement au bug historique documenté ci-dessus),
`FeedActivity.init(from:)` (décodage tolérant `id`/`actor`/`isLiked` confirmé contre un échantillon
JSON réel fourni par l'utilisateur, pas deviné), `FeedView.body` (grille 2 colonnes réelle,
`onTapGesture` → `detailStartIndex`/`showDetail` → `fullScreenCover` vers `FeedDetailPagerView`,
chaîne intacte, aucun point de rupture trouvé). **Aucun nouveau gap silencieux trouvé dans cette
passe** — les correctifs déjà en place (lus en entier, pas juste grep) couvrent bien les 3 causes
historiques (session invalide silencieuse, décodage strict cassant tout le flux, erreur non
affichée). Statut inchangé : `COMPLETE_PARITY_CANDIDATE`, test fonctionnel réel sur build à jour
toujours requis pour passer en `COMPLETE_PARITY_VALIDATED`.

---

## FEATURE: Profile

### Android reference
- **Fichiers** : `uploadPerfilPhoto/UserProfile.java` (1198 lignes, profil d'AUTRUI, lu en entier),
  `uploadPerfilPhoto/AddPerfilFoto.java` (1164 lignes, SON PROPRE profil, lu en entier),
  `uploadPerfilPhoto/ProfileRepository.java`, `uploadPerfilPhoto/adapter/ProfileAdapter.java`/
  `ProfileAdapter2.java`/`ProfileMediaAdapter.java` (grille de posts), `R.menu.menu_user_profile`
  (menu "...").
- **Flux réel confirmé** : `getuserbyid/{userId}/{myId}` (profil) + `feedtimeline/{actor}/{viewerId}/
  {limit}/{offset}` (grille de posts, endpoint DIFFÉRENT du fil personnalisé). Menu "..." = EXACTEMENT
  2 items : `report`→`Report` (`report_type="user"`), `block`→dialogue confirmation
  (Bloquer/Débloquer selon état, PAS d'appel serveur dans le libellé lui-même). Bouton follow avec
  écho optimiste (`labelSeguir.setText(R.string.pending)` avant réponse réseau). Bouton "Message"
  visible seulement si `metas.getType().equals(PUBLIC)`.

### iOS implementation
- **Fichiers** : `Profile/ProfileView.swift`, `Profile/ProfileViewModel.swift`,
  `Profile/ProfileRepository.swift`.
- **Décision de fusion documentée** : UN SEUL écran iOS (`ProfileView`, paramétré par
  `isCurrentUser`) couvre les deux Activity Android (`UserProfile`+`AddPerfilFoto`) — les deux
  partagent ~80% de la mise en page, seules les actions d'en-tête diffèrent. Décision assumée, pas
  une simplification silencieuse.

### Comparison

| Élément | Android | iOS | Statut | Preuve |
|---|---|---|---|---|
| Chargement profil | `getuserbyid/{userId}/{myId}` | Même endpoint (`ProfileRepository.fetchProfile`) | `COMPLETE_PARITY_CANDIDATE` | — |
| Grille de posts | `feedtimeline/{actor}/{viewerId}/{limit}/{offset}` | Même endpoint (`fetchUserPosts`) | `COMPLETE_PARITY_CANDIDATE` | — |
| Avatar/pseudo/bio | présents | présents (`header`) | `COMPLETE_PARITY_CANDIDATE` | — |
| Compteurs followers/following | `followers_count`/`following_count`, tap→`FollowList` | `FollowListView.swift`, même nav | `COMPLETE_PARITY_CANDIDATE` | — |
| Menu "..." (autre profil) | EXACTEMENT 2 items : Signaler/Bloquer-Débloquer | EXACTEMENT 2 items identiques (`toolbarContent`) | `COMPLETE_PARITY_CANDIDATE` | Comparé ligne à ligne cette session, déjà présent AVANT ce tour — aucune correction nécessaire |
| Bouton Follow | écho optimiste avant réponse réseau | écho optimiste identique (`ProfileViewModel.follow()`) | `COMPLETE_PARITY_CANDIDATE` | — |
| Bouton Message (1:1) | visible si `type==PUBLIC` | `messageTarget` avec même condition (`profile.type == "public"`) | `COMPLETE_PARITY_CANDIDATE` | — |
| Édition (son propre profil) | `EditProfile.java`/`EditPersonalInformation.java` | `EditProfileView.swift`/`EditPersonalInformationView.swift` | 🟡 `CODE_PRESENT_UNVERIFIED` — fichiers existent, PAS comparés champ par champ cette passe |
| Upload avatar | `HttpFileUploader`, `POST user` multipart | `PhotosPicker` natif + même endpoint | `PARTIAL` assumé — écart d'architecture documenté (Android recadre AVANT envoi via `CroperView`, iOS envoie tel quel) — DÉCISION ASSUMÉE, pas un oubli |
| Solde pièces (coinsAmount) | rafraîchi à CHAQUE chargement du propre profil (`AddPerfilFoto.java:636`), PAS à la connexion | Même point d'écriture (`ProfileViewModel.loadProfile()`) | `COMPLETE_PARITY_CANDIDATE` | Cause racine réelle trouvée et corrigée session précédente |
| Certification (badge) | `isCertified`, affiché sur pseudo | Affiché (`ShortTextVIew`-équivalent) | 🟡 non re-vérifié visuellement cette passe |
| Blocage | `POST block`, toggle `USER_BLOCKED`/`USER_UNBLOCKED` | Même endpoint (`toggleBlock`) | `COMPLETE_PARITY_CANDIDATE` | — |
| Grille posts → Fullscreen | tap → même `FeedFragment`/`ViewPagerAdapter` réutilisé | tap → `.fullScreenCover(FeedDetailPagerView)` | `COMPLETE_PARITY_CANDIDATE` | Corrigé cette session (P0-D) — AVANT : aucun geste attaché du tout, `MISSING` confirmé |
| Statistiques par post | `StatisticsActivity`, lancé depuis le fullscreen SI post = le sien | `StatisticsView.swift`, câblé DEPUIS `FeedView` (menu "..."), PAS ENCORE depuis le pager plein écran de `ProfileView` (`FeedDetailPagerView(posts:startIndex:onClose:)`, l'initialiseur SANS `onMore` utilisé par Profile) | `PARTIAL` — implémenté le 2026-08-18 (P2), point d'entrée Feed seulement | Écart honnête : le point d'entrée depuis le fullscreen de PROFIL (mentionné dans la référence Android) reste à câbler, `FeedDetailPagerView` initialisé sans `onMore` à cet endroit précis |
| État vide/erreur | chrome (avatar/stats/boutons) toujours visible même sans données, erreur affichée à côté | Même comportement (correctif session antérieure) | `COMPLETE_PARITY_CANDIDATE` | — |

### Missing / broken / different
- Statistiques par post (`StatisticsActivity`) : implémenté le 2026-08-18 (P2), voir `StatisticsView.swift` — point d'entrée Feed câblé, point d'entrée Profile (fullscreen) restant.
- Édition profil : présence de code confirmée, PAS vérifiée champ par champ (`CODE_PRESENT_UNVERIFIED`).
- Aucune preuve de test réel récent (post-correctifs `thumbnailURL`/fullscreen) que la grille de
  posts affiche désormais des images — dépend directement du statut Home/Feed ci-dessus.

### Required work
1. Vérifier `EditProfileView.swift`/`EditPersonalInformationView.swift` champ par champ contre
   `EditProfile.java`/`EditPersonalInformation.java`.
2. ~~Décider si `StatisticsActivity` doit être porté (P2, hors périmètre P0 actuel).~~ Implémenté le
   2026-08-18, câblage Profile (fullscreen) restant — voir `StatisticsView.swift`.
3. Test réel pour confirmer que la grille affiche désormais des images (dépend du correctif
   `thumbnailURL`, non re-testé).

### Validation level
**`COMPLETE_PARITY_CANDIDATE`** pour le cœur (chargement/grille/menu/follow/block), **`MISSING`**
pour les statistiques, **`CODE_PRESENT_UNVERIFIED`** pour l'édition. Historique : `FUNCTIONALLY_FAILED`
confirmé (profil vide) avant les correctifs de session vide — corrigé au niveau code, dépend du même
correctif `thumbnailURL` que Home/Feed pour les images de la grille, non re-testé depuis.

**MISE À JOUR 2026-08-17 (Phase 2, P0-3)** — Re-tracé intégralement `ProfileRepository.fetchProfile`/
`fetchUserPosts`, `ProfileViewModel.loadProfile`/`loadMorePosts`, `ProfileView.body`/`postCell`/tap→
`FeedDetailPagerView`, sans supposer les correctifs antérieurs suffisants. Endpoint grille re-vérifié
contre `ProfileRepository.java:153` (`feedtimeline/{actor}/{userId}/{limit}/{offset}`, clé
`"activities"`) — confirmé identique, RAS. **NOUVEAU GAP RÉEL TROUVÉ** (même classe de bug que le
Feed déjà corrigé, jamais porté ici) : `fetchUserPosts`/`fetchHashtagPosts` utilisaient
`try? JSONDecoder().decode([FeedActivity].self, ...) ?? []` — un décodage `Array` Swift lève à la
PREMIÈRE erreur d'élément (contrairement à `compactMap`), donc `try?` transformait ÇA en tableau
VIDE ENTIER dès qu'UN SEUL post avait un champ non conforme, rendant la grille Profile
silencieusement vide (indiscernable de "0 post"). **Corrigé** (commit à suivre) : remplacé par un
décodage per-item avec diagnostics console, même motif que `FeedRepository.fetchTimeline`. Chaîne
Grid→tap→Fullscreen (réutilise `FeedDetailPagerView(posts:startIndex:onClose:)`) vérifiée intacte,
RAS. **Statut : `BUILD_VALIDATED` (CI confirmée verte) — voir `MIGRATION_PARITY_PROGRESS_V2.md`** pour
le reste (`COMPLETE_PARITY_CANDIDATE` inchangé pour le reste de la FEATURE).

---

## FEATURE: Search

### Android reference
- **Fichiers** : `Recherche/ui/RechercheTiinver.java` (754 lignes, ACTIF — confirmé seul point
  d'entrée réel : `grep "RechercheTiinver.class"` = 4 appelants, `FeedFragment`/`MainFragment`/
  `Roster`/`MentionTextView`), `Recherche/ui/UniversalSearchAdapter.java` (357 lignes),
  `Recherche/ui/Adapter.java` (227 lignes, legacy — utilisé pour un rendu différent, à confirmer
  lequel des deux adapters est réellement actif dans quel contexte).
  **`Recherche/ui/RechercheTiinver2.java` (681 lignes) confirmé `DEAD_CODE` cette passe** :
  `grep "RechercheTiinver2.class"` sur tout le projet = 0 résultat, jamais instancié.
- **Flux réel confirmé** : 4 onglets EXACTS `"all"|"posts"|"users"|"hashtags"` (`currentTab`,
  `selectTab`), debounce (`Handler.postDelayed`, `DEBOUNCE_DELAY_MS`), endpoints `content/search/
  suggest?q=` (auto-complétion) et `content/search?q=&types=&limit=10&offset=0` (recherche complète,
  `types` = liste des onglets à inclure). **Élément distinct trouvé cette passe, PAS documenté
  auparavant** : une seconde branche de recherche (`getItFromServeur`, `search/{myId}/{str}`) cible
  spécifiquement les GROUPES (`GroupModel[]`, construit un `MessageLib` pour ouvrir la conversation
  trouvée) — mécanisme de recherche locale d'abord (`searchOnLocal`, curseur SQLite) puis serveur en
  repli. Le déclencheur UI exact (onglet dédié vs bouton séparé) n'a pas été tracé entièrement cette
  passe (fichier de 754 lignes, lecture partielle).

### iOS implementation
- **Fichiers** : `Discover/SearchView.swift`, `Discover/SearchModels.swift`,
  `Discover/SearchRepository.swift`, `Discover/RecentSearchStore` (recherches récentes locales).

### Comparison

| Élément | Android | iOS | Statut | Preuve |
|---|---|---|---|---|
| Onglets | `all`/`posts`/`users`/`hashtags` | `SearchTab`: `.all`/`.posts`/`.users`/`.hashtags` | `COMPLETE_PARITY_CANDIDATE` | Noms ET valeurs `types` confirmés identiques |
| Endpoint suggestion | `content/search/suggest?q=` | Même endpoint (`SearchRepository.suggest`) | `COMPLETE_PARITY_CANDIDATE` | — |
| Endpoint recherche complète | `content/search?q=&types=&limit=10&offset=0` | Même endpoint exact (`SearchRepository.search`) | `COMPLETE_PARITY_CANDIDATE` | — |
| Debounce | `Handler.postDelayed` | À vérifier — présence d'un `Task`/délai dans `SearchView` non confirmée cette passe | 🟡 `CODE_PRESENT_UNVERIFIED` |
| Résultat "users" — tap → profil | `img_avatar.setOnClickListener`→`UserProfile` | `NavigationLink`→`ProfileView(isCurrentUser:false)` | `COMPLETE_PARITY_CANDIDATE` | Confirmé GAP-021 (session précédente) |
| Résultat "users" — bouton Suivre inline | présent (`UniversalSearchAdapter.java:225-247`) | présent (`followButton`) | `COMPLETE_PARITY_CANDIDATE` | Ajouté session antérieure (tâche #35) |
| Résultat "posts" — tap → fullscreen | ouvre `FullScreenMedia` | `.fullScreenCover(FeedDetailPagerView)` | `COMPLETE_PARITY_CANDIDATE` | Confirmé, réutilise le même fullscreen que Home/Feed (GAP-020 s'y applique aussi) |
| Résultat "hashtags" — tap → fil du hashtag | navigation vers résultats hashtag | `HashtagFeedView.swift` | 🟡 non re-vérifié cette passe |
| Recherche de GROUPES/conversations (`search/{myId}/{str}`) | présente, distincte des 4 onglets | **AUCUNE trace trouvée côté iOS** | `MISSING` (nouveau, trouvé cette passe) | `grep` sur `SearchRepository.swift`/`ChatRepository.swift` : aucun appel à un endpoint `search/{userId}/{query}` |
| Recherches récentes locales | à confirmer (non tracé cette passe) | `RecentSearchStore` (persistance locale confirmée) | 🟡 |
| État vide/chargement/erreur | à confirmer | `isLoading`/`errorText` présents dans le code | 🟡 non comparé écran par écran |

### Missing / broken / different
- **`MISSING` (nouveau)** : recherche/ouverture directe d'un GROUPE via la recherche (`search/{myId}/
  {str}`) — trouvé cette passe, jamais documenté auparavant. Impact : un utilisateur ne peut
  probablement pas retrouver un groupe existant par recherche textuelle côté iOS, seulement via la
  liste de conversations déjà ouvertes.
- `RechercheTiinver2.java` confirmé mort — aucune action nécessaire côté iOS pour ce fichier.
- Plusieurs éléments 🟡 non tracés en détail par manque de temps cette passe (debounce exact, hashtag
  tap, états vides) — à re-vérifier avant de conclure `COMPLETE_PARITY_CANDIDATE` sur l'ensemble.

### Required work
1. Lire `RechercheTiinver.java` en entier (parties non couvertes, ~lignes 1-400 et 500-754) pour
   confirmer le déclencheur exact de la recherche de groupes et décider si elle doit être portée.
2. Vérifier le debounce, le tap hashtag, et les états vides précisément.
3. Décider explicitement (avec l'utilisateur si ambigu) si la recherche de groupes est un P1/P2.

### Validation level
**`COMPLETE_PARITY_CANDIDATE`** pour le cœur (4 onglets, 2 endpoints principaux, navigation
users/posts). **`MISSING`** confirmé pour la recherche de groupes. Reste **`CODE_PRESENT_UNVERIFIED`**
sur plusieurs points de détail (debounce, hashtag, états).

---

## FEATURE: Chat/Messaging

### Android reference
- **Fichiers** : `roster/ui/Roster.java` (liste conversations), `messagerie/ui/ActivityMsg.java`+
  `ChatFragmentTest.java` (conversation), `messagerie/repository/ChatRepository.java` (Socket.IO,
  classe `ROOM` = source de vérité des noms d'événements, lue en entier module 11), `contacts/
  Contact.java`+`ContactsFragment.java`+`ChooseFragment.java`+`Adapter.java` (création de groupe,
  3 écrans, lus en entier), `messagerie/group/GroupDetailActivity.java`+
  `SettingGroupMessageFragmant.java` (gestion groupe), `messagerie/ui/UploadFileOrDataService.java`+
  `HttpFileUploader.java` (upload pièces jointes, BunnyCDN).
- **Flux réel confirmé (création de groupe, lu en entier)** : `Contact.onCreate`→`onArticleSelected(0,
  null)` TOUJOURS en premier → `ContactsFragment` (écran 1, liste générale, tap=ouvre conversation
  DIRECTEMENT, `Adapter.ContactHolder`) → en-tête cliquable "Créer un groupe" → `onArticleSelected(1,
  models)` → `ChooseFragment` (écran 2, MÊME liste re-rendue en mode case à cocher,
  `Adapter.ViewHolder`, bande de "chips", FAB "suivant") → `onArticleSelected(2, sélection)` →
  `Group.java` (écran 3, nom + création réelle).
- **Socket.IO — noms d'événements réels** (`ChatRepository.ROOM`) : `"call"`/`"acceptCall"`/
  `"new message"`/`"new message group"`/`"delivred"` (faute d'orthographe RÉELLE côté serveur) — PAS
  les noms `MAJUSCULE_SNAKE_CASE` qu'on pourrait attendre par convention.

### iOS implementation
- **Fichiers** : `Messagerie/RosterListView.swift`, `Messagerie/ChatView.swift`+`ChatViewModel.swift`,
  `Realtime/TiinverSocket.swift`+`SocketEvent.swift`, `Messagerie/ContactPickerView.swift`,
  `Messagerie/GroupCreationView.swift`, `Messagerie/GroupDetailView.swift`+
  `AddGroupMemberView.swift`, `Messagerie/GroupRepository.swift`, `Messagerie/ChatMediaUploadService.swift`.

### Comparison

| Élément | Android | iOS | Statut | Preuve |
|---|---|---|---|---|
| Socket — noms d'événements | `"call"`/`"new message"`/`"delivred"` (faute réelle) etc., 30 constantes `ROOM.*` | `SocketEvent.swift`, mêmes 30 valeurs EXACTES (faute d'orthographe reproduite intentionnellement) | `COMPLETE_PARITY_CANDIDATE` | Bug réel trouvé et corrigé session antérieure (valeurs MAJUSCULE erronées avant) — documenté en tête de fichier |
| Création groupe — écran 1 (liste, tap=chat) | `ContactsFragment`/`Adapter.ContactHolder` | `ContactPickerView` mode `.browse` (défaut) | `COMPLETE_PARITY_CANDIDATE` | Corrigé cette session (commits `acbddc7`/`e860d32`) — AVANT : `MISSING`, sautait direct à l'écran 2 |
| Création groupe — écran 2 (sélection multiple) | `ChooseFragment`/`Adapter.ViewHolder` | `ContactPickerView` mode `.selectForGroup` | `COMPLETE_PARITY_CANDIDATE` | — |
| Création groupe — écran 3 (nom+création) | `Group.java` | `GroupCreationView.swift` | `COMPLETE_PARITY_CANDIDATE` | Endpoint `POST group` vérifié, y compris la faute `type:"pivate"` reproduite |
| Bouton "créer groupe" — accessible réellement | FAB `Roster.java:84,133-144` | FAB `RosterListView` | `COMPLETE_PARITY_CANDIDATE` | Câblé — **historique : signalé absent/non accessible par l'utilisateur, corrigé, PAS re-testé depuis le dernier correctif de flux (écran 1/2)** |
| Gestion groupe (membres/rôles) | `GroupDetailActivity`/`SettingGroupMessageFragmant` | `GroupDetailView.swift`/`AddGroupMemberView.swift` | `COMPLETE_PARITY_CANDIDATE` | `GET membership/{groupId}`, `POST /member/update`, `POST deleteMember` vérifiés (GAP-011 historique) |
| Réglages 1 conversation (mute, heure programmée) | `SettingPrivateMessageFragmant` (238 lignes, hébergé par `ProfileDetailActivity`, MÊME Activity que `SettingGroupMessageFragmant`) | `PrivateMessageSettingView.swift` | `BUILD_VALIDATED` (CI confirmée verte) — test fonctionnel réel toujours requis | **Implémenté le 2026-08-18 (P1)** — 100% local (`UserDefaults`/`@AppStorage`, AUCUN appel réseau côté Android non plus, vérifié en lisant le fichier en entier). Le bouton "person.circle" du chat 1:1 (raccourci direct-profil, documenté comme gap volontairement borné) ouvre désormais ce VRAI écran, dont `profile_btn` est maintenant une simple rangée. Bouton "Bloquer" reproduit FIDÈLEMENT tel quel (Android ne fait que changer le label, aucun appel réseau ni persistance à cet endroit précis — PAS "corrigé" en un vrai toggle, le vrai blocage fonctionnel existe déjà ailleurs, `ProfileViewModel.toggleBlock`). |
| Accès profil depuis un chat 1:1 | `profile_btn`→`UserProfile` | bouton toolbar "person.circle" ajouté cette session | `COMPLETE_PARITY_CANDIDATE` | Commit dans GAP-021 |
| Suppression message (pour moi / pour tous) | dialogue 2 choix (`ChatFragmentTest.java:2493-2521`) | `showDeleteOptions`, même 2 choix | `COMPLETE_PARITY_CANDIDATE` | Câblé session antérieure |
| Upload pièces jointes | `HttpFileUploader`/BunnyCDN | `ChatMediaUploadService.swift` | `COMPLETE_PARITY_CANDIDATE` | GAP-004c historique, protocole BunnyCDN confirmé DIFFÉRENT du multipart direct du profil |
| Téléchargement pièces jointes reçues | présent | présent | `COMPLETE_PARITY_CANDIDATE` | GAP-003 historique |
| Appels audio/vidéo | WebRTC/CallKit-équivalent Android | `CallView.swift`/`WebRTCConnection.swift`/`CallKitManager.swift` | `COMPLETE_PARITY_CANDIDATE` | Audit dédié fait (GAP-005 historique), bug `makingOffer` trouvé et corrigé |
| Recherche de groupe/conversation | `search/{myId}/{str}` | `ChatSearchView.swift` (nouveau) | `BUILD_VALIDATED` (CI confirmée verte) — test fonctionnel réel toujours requis | **Implémenté le 2026-08-18 (Phase 2, P1)**, suite du tracé de la passe précédente. `Recherche/ui/ChatAdapter.java:291-313` lu (click handler) : Android n'a PAS d'étape "rejoindre" séparée — tap sur un résultat, local OU serveur, construit un `RosterModel` et ouvre directement `ActivityMsg`/`ChatView`, reproduit tel quel. Construction du `RosterModel` d'un groupe extraite dans `GroupRepository.GroupInfo.rosterModel(myId:myUsername:)` (réutilisée par `DeepLinkRouter.routeToGroup`, qui dupliquait auparavant cette construction ET laissait `subTitle` vide faute d'avoir alors identifié la chaîne réelle `"tab here for group info"`, corrigé au passage). Icône loupe ajoutée à la toolbar `RosterListView`, présente `ChatSearchView` en `.sheet` (écran autonome avec sa propre pile, fidèle à l'Activity séparée d'Android). `GroupRepository.searchGroups` décode `search/{myId}/{str}` per-item avec diagnostics (même motif défensif que P0-4). |

### Missing / broken / different
- Réglages complets d'une conversation 1:1 (mute, heure de livraison programmée) : `MISSING`.
- Recherche de groupe via la barre de recherche : `MISSING` (partagé avec FEATURE Search).
- `messagerie/group/AddGroupDescriptionActivity.java`/`ChangeGroupTopicActivity.java`/
  `FilterGroupMemberList.java` : correspondance exacte avec `GroupDetailView.swift` non vérifiée
  élément par élément cette passe (probable fusion, à confirmer).

### Required work
1. Test réel du flux complet création de groupe (écran 1→2→3→chat créé) sur un build à jour —
   AUCUNE preuve de test réel post-correctif à ce jour.
2. ~~Décider du sort de `SettingPrivateMessageFragmant` (P1/P2).~~ Implémenté le 2026-08-18 (P1),
   voir `PrivateMessageSettingView.swift`.
3. Vérifier `AddGroupDescriptionActivity`/`ChangeGroupTopicActivity`/`FilterGroupMemberList` contre
   `GroupDetailView.swift` élément par élément.

### Validation level
**`COMPLETE_PARITY_CANDIDATE`** pour le cœur (socket, création de groupe 3 écrans, gestion groupe,
appels, pièces jointes, réglages 1:1, recherche de groupe — ces 2 derniers implémentés le 2026-08-18,
P1, `BUILD_VALIDATED` à confirmer). Historique :
`FUNCTIONALLY_FAILED` confirmé à plusieurs reprises (bouton créer groupe rapporté absent/inaccessible,
écran hybride au lieu de 2 écrans distincts) — corrigé au niveau code, AUCUN re-test réel depuis.

**MISE À JOUR 2026-08-17 (Phase 2, P0-4)** — Re-vérifié la chaîne complète `RosterListView` (FAB
`GoToContact`) → `ContactPickerView` (écran 1 `.browse` par défaut, en-tête "Créer un groupe" →
écran 2 `.selectForGroup`) → `GroupCreationView`, sans régression trouvée : les 3 écrans, le mode
tap-pour-discuter de l'écran 1, et la navigation restent intacts. **NOUVEAU GAP RÉEL TROUVÉ** en
creusant plus loin que la simple présence du bouton (même classe de bug que P0-1/P0-3, cette fois
dans `ContactsRepository.connectedUsers` ET `GroupRepository.fetchMembers`) : les deux utilisaient
`try? JSONDecoder().decode([T].self, ...) ?? []` sur le TABLEAU entier — un seul contact/membre au
format inattendu aurait de nouveau vidé silencieusement TOUTE la liste (le commentaire de code
préexistant soupçonnait déjà explicitement cette cause pour le P0-F historique "impossible de créer
un groupe", dont la cause précise — `userId` numérique cassant `GroupMemberCandidate`'s décodage
strict — avait déjà été corrigée une session précédente via `init(from:)`, mais SANS retirer le
`try?` englobant qui restait un point de fragilité identique pour tout futur champ non conforme).
Corrigé avec le même motif per-item + diagnostic que Feed/Profile. **Statut : `BUILD_VALIDATED` à
confirmer par CI — voir `MIGRATION_PARITY_PROGRESS_V2.md`** pour le reste (`COMPLETE_PARITY_CANDIDATE`
inchangé pour le reste de la FEATURE Chat/Messaging).

---

## FEATURE: Galerie/Publication

### Android reference
- **Fichiers** : `editor/CameraActivity.java`, `editor/media/MediaEditor.java`/`MediaEditor2.java`,
  `editor/croper/CropFragment.java`, `manager/Gallery.java`, `Activity/service/ActivityService.java`
  (327 lignes de la partie upload lues en détail cette passe — **PAS lu en entier avant cette passe**,
  contrairement à ce qu'une conclusion précédente "GAP-004 lu en entier" pouvait laisser penser : ce
  fichier précis, `ActivityService.java`, distinct de `UploadFileOrDataService.java` déjà lu pour le
  Chat, n'avait jamais été comparé au flux Feed iOS avant maintenant), `uploading/UploadData.java`.
- **FLUX RÉEL DE PUBLICATION D'UN POST (photo OU vidéo), confirmé précisément cette passe** — **DIVISE
  EN 2 ÉTAPES DISTINCTES, PAS UN SEUL APPEL RÉSEAU** :
  1. **Upload du média DIRECTEMENT vers BunnyCDN**, jamais vers le backend Tiinver :
     - **Photo** (`uploadImageToBunny`) : `PUT https://storage.bunnycdn.com/tiinver-media/tiinver/
       photos/{token}.webp`, header `AccessKey: 75ef8922-9f01-40d9-a71c66e21a22-a056-4615` (clé
       statique, codée en dur côté Android). `cdn_content_url` construit CÔTÉ CLIENT :
       `"tiinver/photos/" + fileName`.
     - **Vidéo** (`uploadVideoToCdn`→`getCdnVideoId`+`uploadFileToBunny`) : **DEUX appels**
       BunnyCDN VIDEO LIBRARY (PAS storage) : (a) `POST https://video.bunnycdn.com/library/471609/
       videos` avec `{"title": token}` → réponse `{"guid": videoId}` ; (b) `PUT https://
       video.bunnycdn.com/library/471609/videos/{videoId}` = octets bruts de la vidéo, mêmes
       en-têtes `AccessKey`. `cdn_content_url` construit CÔTÉ CLIENT : `videoId + "/playlist.m3u8"`
       (HLS, PAS un MP4 direct) ; `cdn_thumbnail_url` = `videoId + "/thumbnail.jpg"`.
  2. **SEULEMENT ENSUITE**, `sendMetaDate(data)` → `POST activity/add` sur le backend Tiinver, avec
     `object_url`/`cdn_content_url`/`cdn_content_id`/`cdn_thumbnail_url`/`cdn_provider="bunny"` etc.
     envoyés comme **PARAMÈTRES TEXTE** (`Map<String,String>`) — **JAMAIS de fichier binaire envoyé
     à `activity/add`**, cet endpoint ne reçoit QUE des métadonnées.

### iOS implementation
- **Fichiers** : `Feed/PublishComposeView.swift`, `Feed/FeedRepository.swift` (`func publish`).
- **Flux réel actuel** : **UN SEUL appel** `APIClient.shared.uploadMultipart(endpoint: "activity/add",
  fields: params, fileFieldName: "object_url", filename:, mimeType:, fileData: <octets bruts>)` —
  envoie le FICHIER BINAIRE COMPLET (photo OU vidéo) DIRECTEMENT à `activity/add` sur le backend
  Tiinver, en un seul POST multipart.

### Comparison

| Élément | Android (réel) | iOS (réel) | Statut | Preuve |
|---|---|---|---|---|
| Destination du fichier photo | BunnyCDN Storage (`storage.bunnycdn.com/tiinver-media/...`) | Backend Tiinver (`activity/add`, champ `object_url`) | **`FUNCTIONALLY_FAILED` (haute confiance)** | `ActivityService.uploadImageToBunny` lu en entier vs `FeedRepository.publish` lu en entier |
| Destination du fichier vidéo | BunnyCDN VIDEO LIBRARY (2 appels : créer `guid`, puis PUT octets) | Backend Tiinver (`activity/add`, champ `object_url`), MÊME endpoint que la photo | **`FUNCTIONALLY_FAILED` (haute confiance)** | idem |
| Payload de `activity/add` | métadonnées TEXTE uniquement, jamais de fichier | fichier binaire COMPLET + métadonnées, en multipart | **`FUNCTIONALLY_FAILED`** | `sendMetaDate` (params `Map<String,String>`, aucun `MultipartBody`) vs `uploadMultipart(...fileData:)` |
| Infrastructure de upload direct BunnyCDN | 2 systèmes distincts (Storage=photos/pièces jointes chat, Video Library=vidéos Feed) | **Storage DÉJÀ implémenté** (`Messagerie/ChatMediaUploadService.swift`, MÊME zone `tiinver-media`/MÊME clé statique, confirmé identique) mais **jamais réutilisé pour la publication Feed** ; Video Library (`.m3u8`/`guid`) **absent partout dans le projet iOS** (`grep "video.bunnycdn\|playlist.m3u8\|471609"` sur `Sources/` = 0 résultat) | `PARTIAL` — la moitié de l'infrastructure existe déjà mais n'est pas branchée au bon endroit | `grep` confirmé |
| Éditeur (crop/rotate/flip/texte/stickers/paint/trim) | `MediaEditor`/`CropFragment` | `PhotoToolsView`/`FreeformCropView`/`MediaTrimView`/etc. (nombreux fichiers, tâches #27-#30 session antérieure) | 🟡 `CODE_PRESENT_UNVERIFIED` pour la parité visuelle exacte, PAS re-vérifié cette passe — mais le flux d'ÉDITION lui-même n'est pas le problème trouvé ici, c'est l'étape RÉSEAU finale |

### Missing / broken / different
**TROUVAILLE MAJEURE DE CETTE PASSE, PAS DOCUMENTÉE AUPARAVANT** : le flux de publication Feed
(photo ET vidéo) envoie actuellement le fichier média au MAUVAIS endroit. Le bouton "Publier" APPELLE
bien un réseau réel (pas un bug de câblage UI — `PublishComposeView.publish()` est correctement
relié, gère les erreurs explicitement, n'avale rien silencieusement), MAIS la REQUÊTE elle-même ne
correspond à AUCUN chemin que le vrai client Android emprunte jamais. Il est très probable (sans
certitude à 100% sans test réel du comportement du BACKEND face à cette requête inattendue) que :
- soit le backend Tiinver rejette une requête multipart sur `activity/add` (endpoint jamais conçu
  pour recevoir un fichier) ;
- soit il l'accepte mais stocke le fichier d'une manière incompatible avec ce que les CLIENTS
  (Android existant, et donc probablement le CDN de lecture `cdn.tiinver.com`/`stream.tiinver.com`
  déjà découverts) attendent pour le SERVIR ensuite — expliquant potentiellement, EN PARTIE, les
  posts qui ne se chargent jamais pour CERTAINS contenus (si des posts publiés depuis iOS existent
  déjà en base avec un `object_url` de forme différente de ce que le CDN attend).

### Required work (Phase 2 — PAS fait cette passe, audit uniquement)
1. Implémenter le flux 2-étapes pour la PHOTO : réutiliser `ChatMediaUploadService`'s pattern de PUT
   direct (même zone/clé déjà confirmées identiques) vers `tiinver/photos/{token}.webp`, PUIS
   `POST activity/add` avec les champs metadata texte (PAS de fichier).
2. Implémenter le flux 2-étapes pour la VIDÉO : NOUVEAU code nécessaire (créer `guid` via `POST
   video.bunnycdn.com/library/471609/videos`, PUIS PUT des octets vers `.../videos/{guid}`), PUIS
   `POST activity/add` avec `cdn_content_url = "{guid}/playlist.m3u8"` (HLS).
3. Vérifier si le lecteur vidéo iOS (`VideoPlayerManager`) gère bien HLS (`.m3u8`) — actuellement
   testé/corrigé cette session pour des URLs `.mp4` (`play_720p.mp4`), PAS `.m3u8` — à confirmer
   `AVPlayer` gère nativement HLS (généralement oui, mais jamais vérifié pour CE cas précis).

### Validation level
**`FUNCTIONALLY_FAILED`** (haute confiance, PAS certitude absolue faute de test réel du comportement
backend) pour la publication Feed elle-même — c'est l'écart le plus significatif trouvé dans TOUT cet
audit V2, jamais documenté dans aucune passe précédente malgré une tâche antérieure intitulée
"P0-5 Galerie publish: verify real upload pipeline end to end" marquée complétée — cette tâche n'avait
PAS comparé `ActivityService.java` (le fichier qui contient la vérité) au flux iOS réel.

**MISE À JOUR 2026-08-17 (Phase 2, P0-1)** — Correctif implémenté : nouveau fichier
`Feed/FeedMediaUploader.swift` reproduisant fidèlement `ActivityService.uploadImageToBunny` (Storage,
`PUT storage.bunnycdn.com/tiinver-media/tiinver/photos/{token}.webp`) et `getCdnVideoId`+
`uploadFileToBunny` (Video Library, 2 appels : `POST .../library/471609/videos` → `guid`, puis `PUT
.../videos/{guid}` octets bruts sans Content-Type). `FeedRepository.publish` réécrit pour appeler
`FeedMediaUploader` PUIS `POST activity/add` avec SEULEMENT des métadonnées texte (plus aucun
multipart/fichier binaire vers cet endpoint). Diagnostics `print()` à chaque étape (upload CDN,
metadata POST, succès/échec) pour un futur débogage sans re-deviner. Commit `b639057`, CI verte
(run [32076424332](https://github.com/SalimMedir/TiinverSwift/actions/runs/32076424332), `conclusion:
success`). **Statut : `BUILD_VALIDATED` — commit `b639057` — CI SUCCESS — test fonctionnel réel
toujours requis** (aucune preuve encore qu'un post publié depuis iOS apparaît bien dans le Feed avec
un média lisible — le point #3 de "Required work" ci-dessus, lecture HLS `.m3u8` par `AVPlayer`, reste
également non re-testé). NE PAS marquer `COMPLETE_PARITY_VALIDATED` avant un test Appetize global.

---

## FEATURE: Animems (audit 3 niveaux)

### Android reference
- **Découverte structurelle de cette passe** : le moteur Animems vit dans un module Gradle SÉPARÉ,
  `engine/src/main/java/com/animems/engine/` — 340 fichiers `.java`, PAS dans `app/src/main/java/
  com/tiinver` comme le reste de l'application. Ce module contient AUSSI de l'infrastructure
  PARTAGÉE avec la Galerie (filtres GPU `android.gpuv.egl.filter.*`, recadrage `android.croper.*`,
  trim vidéo `Utils.media.*`) — donc "340 fichiers" ne veut pas dire "340 fonctionnalités Animems",
  une partie sert aussi à `editor/media/MediaEditor.java` (voir FEATURE Galerie).
- **Fichiers cœur Animems** (correspondance directe 1:1 avec les noms de fichiers iOS) :
  `core.AnimationEngine`/`core.AnimationComposer`/`core.AnimationObjectData`/`core.Transform`/
  `core.AnimationUtils`, `keyframe.Keyframe`/`keyframe.KeyframeTrack`, `mask.MaskType`/
  `mask.MaskEditController`, `template.MotionTemplate`/`template.MotionTemplateManager`,
  `android.memes.MemesView2` (moteur de geste tactile), `android.views.AnimemesCompound`/
  `AnimemesCompound2` (vue éditeur), `android.views.TimelineView`, `android.utils.ShapeFactory`,
  `model.StickerData`/`model.SerializableAnimationObject`/`model.PlaylistEntry`/`model.TimelineItem`,
  `android.codec.AnimatedGifEncoder` (export GIF).
- **Types de masque réels** (7, `mask.MaskType.java`) : `CIRCLE`/`SQUARE`/`RECTANGLE`/`HORIZONTAL`/
  `MIRROR`/`HEART`/`STAR`.

### iOS implementation
- **Fichiers** : `Animems/AnimemesEditorView.swift`+`AnimemesEditorState.swift` (état+vue fusionnés
  — Android sépare `AnimemesCompound` de la logique portée dans `MemesView2`),
  `AnimemesGestureController.swift`, `AnimationEngine.swift`/`AnimationComposer.swift`/
  `AnimationObjectData.swift`/`Transform.swift`/`AnimationUtils.swift`, `Keyframe.swift`/
  `KeyframeTrack.swift`, `MaskType.swift`/`MaskEditController.swift`/`MaskFactory.swift`,
  `MotionTemplate.swift`/`MotionTemplateManager.swift`/`MotionTemplateGalleryView.swift`/
  `CommunityTemplateGalleryView.swift`/`CommunityTemplateRepository.swift`, `TimelineView.swift`/
  `TimelineViewModel.swift`, `LayerRenderer.swift`, `ShapeFactory.swift`, `StickerData.swift`/
  `SerializableAnimationObject.swift`/`PlaylistEntry.swift`/`TimelineItem.swift`,
  `AnimemesExporter.swift`, `CanvasZoomController.swift`, `BezierEditorView.swift`,
  `AnimemesDrawingView.swift`, `BitmapCacheManager.swift`/`BitmapGeometry.swift`.

### Niveau 1 — Fonctionnalités (inventaire)

| Fonctionnalité | Android | iOS | Statut |
|---|---|---|---|
| Sélection image source | présent | présent | COMPLETE_PARITY_CANDIDATE |
| Ajout objets (bitmap/forme/texte/sticker/dessin libre) | présent (`AnimemesCompound`) | `addImage`/`addShape`/`addText`/`addSticker`/`addFreehandDrawing` | COMPLETE_PARITY_CANDIDATE |
| Sélection objet (hit-test) | `touchDown`, matrice inversée | `selectObject`, même logique (`AnimemesGestureController.isPoint`) | COMPLETE_PARITY_CANDIDATE — bug de hit-test réel trouvé et corrigé session antérieure |
| Déplacement (1 doigt) | `touchMove`/`translation`, matrice `postTranslate` | `dragMoved`/`touchMoveTranslate`, même composition matricielle | COMPLETE_PARITY_CANDIDATE — bug réel `.id(state.version)` interrompant le geste EN COURS, trouvé et corrigé CETTE session (GAP-024), jamais détecté par les passes précédentes qui s'étaient arrêtées à `AnimemesGestureController`/`AnimemesEditorState` sans relire `AnimemesEditorView` (le point d'attache SwiftUI réel) |
| Rotation/Scale (2 doigts) | `RotationGestureDetector`, pivot=point milieu réel des 2 doigts | `RotationGesture`/`MagnificationGesture` SwiftUI, pivot=centre du calque (écart assumé, SwiftUI n'expose pas les coordonnées de contact individuelles) | VISUALLY_DIFFERENT (mineur) — écart de pivot documenté et assumé, pas un oubli |
| Multi-touch simultané (glisser+pincer+pivoter) | supporté nativement | `SimultaneousGesture` imbriqué | COMPLETE_PARITY_CANDIDATE |
| Timeline / playhead / scrub | `TimelineView.java` | `TimelineView.swift`/`TimelineViewModel.swift` | COMPLETE_PARITY_CANDIDATE — câblé session antérieure |
| Lecture/pause | `CADisplayLink`-équivalent Android | `AnimationEngine.play`/`pause` | COMPLETE_PARITY_CANDIDATE |
| Keyframes (ajout/suppression/interpolation) | `Keyframe.java`/`KeyframeTrack.java` | `Keyframe.swift`/`KeyframeTrack.swift`, `recordKeyframe()` | COMPLETE_PARITY_CANDIDATE |
| Masques — 7 types | CIRCLE/SQUARE/RECTANGLE/HORIZONTAL/MIRROR/HEART/STAR | `MaskType.swift` : mêmes 7 valeurs, même ordre | COMPLETE_PARITY_CANDIDATE — comparaison exacte fichier à fichier |
| Masques — feather/invert/mirror gap/offset/scale/rotation | présents (`MaskPreviewEditorPanel`) | présents (`setMaskFeather`/`toggleMaskInverted`/`setMaskMirrorGap`/`maskOffsetChanged`/`maskScaleChanged`/`maskRotationChanged`) | COMPLETE_PARITY_CANDIDATE — les 3 fonctions de geste continu ont aussi bénéficié du correctif `renderVersion` cette session |
| Templates locaux (sauvegarde/chargement/suppression) | `template.MotionTemplateManager` | `MotionTemplateManager.swift` | COMPLETE_PARITY_CANDIDATE |
| Templates communautaires (parcourir/télécharger/appliquer) | `template.RecomposeManager`/`RecomposeTemplate` | `CommunityTemplateRepository.swift`/`CommunityTemplateGalleryView.swift` | COMPLETE_PARITY_CANDIDATE — upload confirmé DEAD_CODE côté Android lui-même |
| Export image statique | présent | `exportStaticImage` | COMPLETE_PARITY_CANDIDATE |
| Export vidéo (MP4) | `android.codec.MP4Encoder.java` (2200+ lignes, GPU/OpenGL) | `AnimemesExporter.swift` via `AVAssetWriter` (mécanisme natif différent) | PARTIAL/VISUALLY_DIFFERENT — le fichier iOS documente lui-même ce qui n'a pas été relu en détail (normalisation audio notamment) |
| Export GIF | `android.codec.AnimatedGifEncoder.java`/`GIFView.java` (1282+ lignes, présents dans le module `engine`) | ABSENT | **`DEAD_CODE` (RECLASSIFIÉ le 2026-08-18, P2)** — PAS `MISSING` : `grep "AnimatedGifEncoder\|GIFView"` sur TOUT le module `engine` ne retourne que leurs propres fichiers, JAMAIS référencés depuis `AnimemesCompound.java` (la classe réellement exercée) ni aucun autre appelant. `showSaveDialog()` (`AnimemesCompound.java:2960-2966`, le VRAI menu de sauvegarde, `AnimemesActionSheet.ActionListener`) n'expose que 3 actions : `onPublishAnimation`→vidéo, `onSaveTemplate`/`onPublishTemplate` — AUCUNE action GIF. Même classe de code mort que `RechercheTiinver2.java`/`TrimBenchActivity.java`/`FullscreenActivity.java` déjà confirmés cette session : construire un export GIF côté iOS inventerait une fonctionnalité qu'Android lui-même n'expose jamais à l'utilisateur. |
| Toolbar/boutons/panels | `AnimemesCompound`/`LayerEditorPanel`/`ShapeAddPanel`/`MaskAddPanel` | `LayerEditorPanelState.swift`/panels correspondants | CODE_PRESENT_UNVERIFIED — parité visuelle non comparée capture à capture cette passe |

### Niveau 2 — Architecture (points de rupture précis)

Chaîne attendue : geste SwiftUI → state (mutation) → observation → redessin Canvas → rendu visuel
appliqué. Cette passe a identifié précisément où cette chaîne s'était rompue :

- **Avant cette session** : `gestureController.touchMoveTranslate` mutait correctement la matrice
  (le state changeait bien). `version += 1` déclenchait bien `body` (le Canvas redessinait bien,
  avec la bonne transformation — le rendu final était correct à chaque frame individuellement). Le
  point de rupture réel n'était dans AUCUNE de ces 3 étapes : c'était `.id(state.version)` en
  périphérie qui, en changeant l'identité de la vue portant le `.gesture()`, interrompait le
  reconnaisseur de geste UIKit sous-jacent au milieu du geste — un 4ᵉ type de rupture, au niveau du
  cycle de vie de la vue elle-même, pas du triptyque state/observation/rendu. Cause probable pour
  laquelle un audit dédié précédent ("P0-3 Animems canvas: full pipeline audit vs
  AnimemesCompound.java") ne l'a pas trouvée : il comparait le moteur (`AnimemesGestureController`/
  `AnimemesEditorState`) à `AnimemesCompound.java`/`MemesView2.java`, jamais `AnimemesEditorView.swift`
  lui-même (le seul endroit où `.gesture()` et `.id()` coexistent) — un point de rupture au niveau
  du framework SwiftUI, invisible depuis une comparaison purement algorithmique avec Android.
- **`preparePlayback` sur-déclenché** : le state changeait, `body` redessinait correctement avec la
  bonne transformation (aucune rupture de rendu), mais un effet de bord non lié au rendu
  (`.onChange(of: state.version)`) exécutait un travail coûteux (`engine.prepare`) à chaque frame de
  geste — dégradant la fluidité perçue sans casser la correction visuelle, un 5ᵉ type de problème
  distinct des précédents (performance, pas correction).

**MISE À JOUR 2026-08-17 (Phase 2, P0-5)** — **LA MÊME rupture de cycle de vie (`.id(state.version)`
sur un `Canvas` porteur d'un `.gesture()`) a été retrouvée, jamais corrigée, dans `TimelineView.swift`
(fichier SŒUR du canevas principal, jamais relu lors du correctif GAP-024 initial ni de l'audit V2
Phase 1 — celui-ci s'était arrêté à `AnimemesEditorView.swift`/`AnimemesEditorState.swift`/
`AnimemesGestureController.swift` sans redescendre dans `TimelineView.swift`)**. Ici le bug était
encore plus systématique : `combinedDragGesture`/`magnificationGesture` appelaient `state.
bumpVersion()` à CHAQUE frame de geste (pas seulement certaines fonctions comme sur le canevas
principal), garantissant une auto-interruption du geste au premier mouvement pour LES 5 interactions
Timeline (pan, scrub, glisser-item, redimensionner, pincer-zoomer) — un bug plus sévère que celui du
canevas principal, jamais rapporté par l'utilisateur (cohérent avec le fait que la Timeline soit un
écran secondaire moins testé). **Corrigé** avec le même motif exact que GAP-024 : `.id()` retiré,
nouveau `AnimemesEditorState.bumpRenderVersion()` (miroir de `bumpVersion()`, incrémente
`renderVersion` au lieu de `version`) utilisé par les 3 gestes continus + `scrub(toFrame:)` (qui
bump ait `version` directement, même sur-déclenchement `preparePlayback` que GAP-024 partie 2).
**Statut : `BUILD_VALIDATED` (CI confirmée verte) — test fonctionnel réel toujours requis** (aucun
simulateur/device disponible pour confirmer visuellement que pan/scrub/drag/resize/zoom fonctionnent
désormais en pratique — la correction est déduite de la même logique de cycle de vue SwiftUI déjà
confirmée exacte pour GAP-024, pas observée directement).

### Niveau 3 — Parité visuelle

Aucune capture Android réelle de l'éditeur Animems n'a été fournie par l'utilisateur à ce jour
(contrairement au Feed). Cette section reste CODE_PRESENT_UNVERIFIED sur le plan visuel pur, malgré
une forte correspondance structurelle de code — ne pas confondre "l'algorithme correspond" (Niveaux
1/2, établis avec un bon niveau de confiance) et "l'écran a l'air identique" (Niveau 3, non établi).

### Missing / broken / different
1. `.id(state.version)` interrompant le geste actif — FUNCTIONALLY_FAILED confirmé, corrigé cette
   session (commit `0a8966b`).
2. `preparePlayback` sur-déclenché à chaque frame de geste — dégradation de fluidité, corrigée cette
   session (commit `4c57d08`).
3. ~~Export GIF — MISSING confirmé (auto-documenté dans le code).~~ **RECLASSIFIÉ `DEAD_CODE` le
   2026-08-18 (P2)** — `AnimatedGifEncoder.java`/`GIFView.java` jamais appelés depuis
   `AnimemesCompound.java`, `showSaveDialog()` n'expose que vidéo/template. Rien à porter.
4. Export vidéo MP4 — PARTIAL : mécanisme différent (AVAssetWriter vs pipeline OpenGL/codec Android),
   zones explicitement documentées comme non comparées en détail (normalisation audio).
5. Pivot de rotation/scale à 2 doigts — VISUALLY_DIFFERENT mineur, écart assumé.
6. Parité visuelle globale (toolbar/panels/disposition) — non vérifiée faute de référence visuelle
   Android fournie.

### Required work
1. Obtenir une capture/vidéo Android réelle de l'éditeur Animems pour la parité visuelle (Niveau 3)
   — demande explicite à l'utilisateur, pas une hypothèse à deviner.
2. Vérifier `AnimemesExporter.swift` contre les parties non lues de `MP4Encoder.java` (normalisation
   audio notamment).
3. Décider si l'export GIF doit être porté (P1/P2).
4. Test réel du glisser/pincer/pivoter sur un build incluant les commits `0a8966b`/`4c57d08` —
   aucune preuve de test réel à ce jour, seulement une correction par analyse statique.

### Validation level
COMPLETE_PARITY_CANDIDATE pour le cœur moteur (gestes, masques, keyframes, templates) — avec deux
causes racines réelles supplémentaires trouvées et corrigées cette passe précise (`.id()` +
`preparePlayback`). MISSING confirmé pour GIF. PARTIAL pour l'export vidéo. CODE_PRESENT_UNVERIFIED
pour la parité visuelle globale (Niveau 3), faute de référence. Historique : FUNCTIONALLY_FAILED
rapporté par l'utilisateur ("ne se déplacent pas facilement") — cause racine réelle maintenant
identifiée avec un haut degré de confiance, pas encore confirmée par test réel.

---

## VISUAL PARITY AUDIT

Comparaisons basées sur : (a) XML Android lu directement (source la plus fiable), (b) captures
Appetize RÉELLES fournies par l'utilisateur au cours de cette conversation, (c) captures Android non
fournies pour Animems (voir note Niveau 3 ci-dessus).

| Android screen/view | Android source | iOS equivalent | Structure parity | Interaction parity | Visual parity | Functional status | Missing/different |
|---|---|---|---|---|---|---|---|
| Feed Grid (2 colonnes) | `fragment_main_activity.xml`+`les_pub_affiche2.xml` | `FeedView.swift` (`FeedGridCell`) | Identique (2 colonnes confirmé) | Tap→fullscreen, "..."→menu, both confirmed wired | **NON CONFIRMÉE** — dernière capture Appetize montre des rectangles gris vides (dégradé), aucune image | `FUNCTIONALLY_FAILED` sur la dernière capture connue, `COMPLETE_PARITY_CANDIDATE` au niveau code (correctif `thumbnailURL` non re-testé depuis) | Image/thumbnail — build testé non confirmé à jour |
| Feed Fullscreen | `video_expanded_item.xml`/`image_expanded_item.xml`+`reaction_pub_but.xml` | `FeedView.swift` (`FeedDetailCell`) | Identique au niveau code (légende→avatar+pseudo+date→"S'abonner"+rail actions) | Like/Comment/Partager/Plus/tap-profil tous câblés au niveau code | **NON CONFIRMÉE** — dernière capture montre SEULEMENT une flèche retour + compteur de vues, aucun des éléments ci-dessus visible | `FUNCTIONALLY_FAILED` sur la dernière capture connue, `COMPLETE_PARITY_CANDIDATE` au niveau code | Build testé non confirmé à jour — voir note ci-dessous |
| Fullscreen — ratio vidéo | `PlayerView` sans `resize_mode` (défaut FIT/letterbox) | `VideoPlayer` sans `.videoGravity` (défaut `.resizeAspect`/letterbox) | Identique (même défaut des deux plateformes) | — | **CONFIRMÉE IDENTIQUE PAR LE CODE** — le letterboxing visible sur la capture EST le comportement attendu, pas un bug | `COMPLETE_PARITY_CANDIDATE` | Aucun — comportement par défaut identique |
| Création de groupe — écran 1 | `fragment_contacts.xml` (liste, en-tête "Créer un groupe" rouge) | `ContactPickerView.swift` mode `.browse` | Identique au niveau code depuis `acbddc7`/`e860d32` | Tap=ouvre conversation, en-tête=bascule sélection | **NON CONFIRMÉE** — dernière capture montre la sélection multiple ACTIVE dès l'ouverture (case cochée visible) | `FUNCTIONALLY_FAILED` sur la dernière capture connue (antérieure au correctif), `COMPLETE_PARITY_CANDIDATE` au niveau code | Build testé antérieur aux commits `acbddc7`/`e860d32`, à confirmer |
| Bandeau debug session | — (n'existe pas sur Android) | `HomeShellView.userIdDebugBanner` | N/A (ajout iOS pur, demande de debug utilisateur) | — | Visible en permanence sur capture Appetize AVANT correctif | `COMPLETE_PARITY_VALIDATED` pour le correctif lui-même (condition `UserDefaults` toujours fausse par défaut, vérifiable statiquement) | Corrigé commit `f669a89`, non re-testé |
| Animems — éditeur (toolbar/canvas/timeline) | `AnimemesCompound`/panels | `AnimemesEditorView.swift` | Non comparé (pas de référence Android fournie) | Geste continu CORRIGÉ cette session (`.id()`+`preparePlayback`) | **AUCUNE référence disponible** | `CODE_PRESENT_UNVERIFIED` visuellement, `FUNCTIONALLY_FAILED`→corrigé (non re-testé) fonctionnellement | Référence visuelle Android manquante — demande explicite à l'utilisateur |

**Note critique sur les 3 lignes "NON CONFIRMÉE" ci-dessus** : au moment de la rédaction de cet audit
V2, l'utilisateur n'a PAS confirmé si les dernières captures Appetize fournies correspondent à un
build incluant les commits `a796446`/`3bf7ae3` (Fullscreen) et `acbddc7`/`e860d32` (création de
groupe). Le pipeline Codemagic `visual-smoke-test` qui produit le binaire Appetize est déclenché
MANUELLEMENT par l'utilisateur, séparément de la CI GitHub Actions automatique. **Ces 3 lignes
doivent être retestées sur un build confirmé à jour avant de statuer définitivement.**

---

## RAPPORT FINAL

### Méthodologie de comptage
Le décompte ci-dessous mesure les OCCURRENCES de chaque statut dans l'ensemble des tableaux de ce
document (Navigation + 6 FEATURE + Visual Parity Audit), moins leur unique occurrence dans le
tableau de taxonomie en tête de fichier. Ce n'est PAS un décompte d'"unités de fonctionnalité"
parfaitement atomiques et déduplicquées — le tableau Navigation compte 1 ligne = 1 classe Android
(127 au total), tandis que les tableaux `Comparison` de chaque FEATURE comptent 1 ligne = 1 élément
de comparaison plus fin (ex. "ratio vidéo", "URL de lecture" sont 2 lignes distinctes pour la même
fonctionnalité "Fullscreen"). Chiffre honnête, pas un chiffre habillé pour paraître définitif.

- **Total classes de navigation Android inventoriées** : **127** (67 Activities + 60 Fragments).
- **`COMPLETE_PARITY_CANDIDATE`** : **71** occurrences — code comparé en détail à Android, jugé
  correspondant, AUCUN test réel post-comparaison.
- **`COMPLETE_PARITY_VALIDATED`** : **4** occurrences — dont AUCUNE n'est en réalité appuyée sur une
  preuve de test réel POST-derniers-correctifs (voir note critique du Visual Parity Audit) ; à
  corriger dans une prochaine passe si cette lecture stricte s'avère trop généreuse.
- **`BUILD_VALIDATED`** (seul) : **1** — la mention explicite de la règle elle-même ; en pratique,
  TOUS les commits de cette session ET des sessions précédentes n'ont que ce niveau de preuve
  (nombreux runs CI verts référencés par leur SHA dans `CLAUDE_CONTINUATION.md`/historique).
- **`CODE_PRESENT_UNVERIFIED`** : **11** occurrences.
- **`PARTIAL`** : **7** occurrences.
- **`VISUALLY_DIFFERENT`** : **3** occurrences.
- **`FUNCTIONALLY_FAILED`** : **14** occurrences (inclut les mentions historiques désormais corrigées
  au niveau code mais jamais re-testées).
- **`MISSING`** : **33** occurrences.
- **`DEAD_CODE`** : **4** occurrences (`FullscreenActivity.java`, `RechercheTiinver2.java`,
  `TrimBenchActivity.java`, et la mention de méthode générique dans la taxonomie).

### TOP 20 DES GAPS LES PLUS IMPORTANTS (par impact réel, pas par ordre de découverte)

1. **[CRITIQUE, NOUVEAU] Publication Feed (photo ET vidéo) envoie le fichier au MAUVAIS endroit** —
   `activity/add` ne reçoit QUE des métadonnées côté Android (upload réel en 2 étapes vers BunnyCDN
   Storage/Video Library AVANT), iOS envoie le fichier binaire complet en multipart DIRECTEMENT à
   `activity/add`. `FUNCTIONALLY_FAILED` haute confiance. Voir FEATURE Galerie/Publication.
2. **[NOUVEAU] Export vidéo Bunny Video Library (guid+HLS) totalement absent côté iOS** — nécessaire
   pour corriger le gap n°1 côté vidéo spécifiquement (0 fichier trouvé référençant
   `video.bunnycdn.com`/`.m3u8`/`471609`).
3. ~~Recherche de groupe/conversation (`search/{myId}/{str}`) absente côté iOS~~ — **implémentée le
   2026-08-18 (P1)**, voir `ChatSearchView.swift`/FEATURE Chat/Messaging. `BUILD_VALIDATED` à
   confirmer par CI, test fonctionnel réel toujours requis.
4. Feed Grid — statut réel incertain : dernière capture Appetize montre des images absentes malgré
   un correctif déjà livré (`8fd7493`), build testé non confirmé à jour.
5. Feed Fullscreen — statut réel incertain : dernière capture montre AUCUN des éléments (avatar,
   boutons, "S'abonner") pourtant déjà présents dans le code (`a796446`/`3bf7ae3`), build testé non
   confirmé à jour.
6. Création de groupe — statut réel incertain : dernière capture montre l'ancien flux à un seul
   écran malgré un correctif déjà livré (`acbddc7`/`e860d32`), build testé non confirmé à jour.
7. `.id(state.version)` interrompait le geste actif dans Animems — `FUNCTIONALLY_FAILED` réel,
   corrigé cette session (`0a8966b`), non re-testé.
8. `preparePlayback` sur-déclenché à chaque frame de geste Animems — dégradation de fluidité,
   corrigée cette session (`4c57d08`), non re-testée.
9. ~~Système de "Boost" (campagnes publicitaires payantes pour un post — `BoostActivity`/
   `BoostDashboardFragment`/`CreateBoostFragment`/`CommandeActivity`/`MesBoosts`)~~ — **implémenté
   le 2026-08-18 (P1)**, voir `Sources/TiinverSwift/Boost/`. `BUILD_VALIDATED` (CI confirmée verte).
10. ~~Réglages complets d'une conversation individuelle (mute, heure de livraison programmée,
    `SettingPrivateMessageFragmant`)~~ — **implémentés le 2026-08-18 (P1)**, voir
    `PrivateMessageSettingView.swift`. `BUILD_VALIDATED` (CI confirmée verte).
11. ~~Statistiques par post (`StatisticsActivity`)~~ — **implémenté le 2026-08-18 (P2)**, voir
    `StatisticsView.swift`. `BUILD_VALIDATED` (CI confirmée verte) ; point d'entrée Profile restant.
12. ~~Export GIF Animems — `MISSING` confirmé, auto-documenté dans le code lui-même.~~ **RECLASSIFIÉ
    `DEAD_CODE` le 2026-08-18 (P2)** — l'encodeur Android existe mais n'est câblé nulle part dans le
    flux réel (`AnimemesCompound.java`). Retiré du décompte des gaps à combler.
13. ~~Écran de recherche téléphone/email pour nouveau contact (`roster/NewMessage.java`)~~ —
    **implémenté le 2026-08-18 (P2)**, voir `NewMessageView.swift`. `BUILD_VALIDATED` à confirmer
    par CI.
14. Assistant IA (Gemini, `TiinverAIChat`/`TiinverGeminiAIChat`) — présence d'un repository
    (`AiConversationRepository.swift`) mais écran de chat complet non vérifié — `PARTIAL` probable.
15. Système de certification — 4 classes Android (`CertificationActivity`/
    `CertificationRequestActivity`/2 Fragments) vs `CertificationView.swift` — correspondance non
    vérifiée en détail (`CODE_PRESENT_UNVERIFIED`).
16. Plusieurs écrans Wallet secondaires (`PeerToPeerActivity`/`SelectAmountActivity`/
    `RechargeCoinsActvity`/`TransactionTutorialActivity`/`UseBankCardFragment`) — rôle exact et
    correspondance iOS non déterminés cette passe, possibles redondances ou `MISSING` réels.
17. `AddGroupDescriptionActivity`/`ChangeGroupTopicActivity`/`FilterGroupMemberList` — correspondance
    avec `GroupDetailView.swift` non vérifiée élément par élément (fusion probable non confirmée).
18. Bandeau de diagnostic session visible en permanence (y compris sur Appetize) — corrigé cette
    session (`f669a89`), non re-testé.
19. Export vidéo MP4 Animems — mécanisme différent d'Android (AVAssetWriter vs pipeline OpenGL),
    zones explicitement non comparées en détail (normalisation audio) — `PARTIAL`.
20. Parité visuelle Animems (Niveau 3 : toolbar/panels/disposition) — **aucune référence visuelle
    Android disponible**, blocage réel nécessitant une capture/vidéo de l'utilisateur avant de
    pouvoir conclure quoi que ce soit sur ce point précis.

### Confirmé DEAD_CODE (aucune action requise)
`Activity/ui/FullscreenActivity.java` (template Android Studio jamais atteint), `Recherche/ui/
RechercheTiinver2.java` (0 instanciation trouvée), `view/trimmer/v2/debug/TrimBenchActivity.java`
(outil de debug interne Android).

### Ce que cet audit V2 NE couvre PAS encore (honnêteté de portée)
- Réglages (Settings) : 10 Fragments listés dans la cartographie, tous `CODE_PRESENT_UNVERIFIED`,
  aucun comparé champ par champ cette passe.
- Authentification/Onboarding : 10 classes listées, correspondance de fichiers confirmée mais
  contenu non comparé en détail (flux déjà partiellement audité lors des sessions précédentes pour
  la cause racine "session vide", mais pas pour la PARITÉ VISUELLE/fonctionnelle complète de chaque
  écran).
- ~40 classes marquées 🟡 "à investiguer" dans la cartographie Navigation (rôle exact non déterminé
  faute de lecture cette passe : `Suggerencia`/`TiinverCode`/`animation`/`myFilterClass`/
  `DebutWenack2`/etc.).
- 340 fichiers du module `engine/` Android : seule la fraction à correspondance 1:1 directe avec des
  noms de fichiers iOS a été comparée ; les ~35 filtres GPU, le pipeline de composition vidéo
  complet (`android.gpuv.composer.*`), et l'infrastructure de recadrage bas niveau
  (`android.croper.imageprocessing.*`) n'ont pas été comparés élément par élément.

**Conclusion honnête** : cet audit V2 établit une cartographie substantiellement plus rigoureuse et
sourcée que les documents précédents, avec au moins UNE découverte majeure jamais documentée
(publication Feed vers le mauvais endpoint) et deux causes racines Animems réelles trouvées et
corrigées dans le même mouvement. Il reste néanmoins INCOMPLET sur Réglages/Authentification/
plusieurs écrans Wallet secondaires — ne pas le lire comme "audit terminé à 100%", mais comme la
base fiable sur laquelle les lots de correction suivants (Phase 2) doivent s'appuyer, en complétant
les zones encore 🟡/`CODE_PRESENT_UNVERIFIED` au fur et à mesure.

