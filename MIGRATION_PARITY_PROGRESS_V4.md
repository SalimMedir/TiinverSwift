# MIGRATION PARITY PROGRESS V4

Journal de correction du cycle d'audit V4 (`MIGRATION_PARITY_AUDIT_V4.md`).

**État actuel (2026-08-24) : Phase A (Audit) TERMINÉE. Phase B EN COURS — backlog P0 épuisé
(P0-1..P0-4 clos). Liste P1 : V4-F-020, V4-F-032, V4-F-033, V4-F-042, V4-F-038, V4-F-017, V4-F-046,
V4-F-048, V4-F-049, V4-F-050, V4-F-001, V4-F-002, V4-F-029, V4-F-030, V4-F-056, V4-F-064,
V4-F-059, V4-F-068, V4-F-073, V4-F-021 clos. Prochain : V4-F-027.**

`MIGRATION_PARITY_AUDIT_V4.md` est maintenant complet : 75 findings (V4-F-001 à V4-F-075), produits
par 16 agents de recherche indépendants (lecture directe du code Android/iOS, sans lecture des
audits V1/V2/V3 par les agents eux-mêmes, pour maximiser les chances de trouver ce que ces cycles
ont manqué). **AUCUN code source n'a été modifié pour produire cet audit** — conformément à la
consigne explicite de l'utilisateur pour la Phase A. Aucun finding n'a encore été corrigé.

Répartition : 3 P0, 25 P1, 32 P2, 15 P3. Voir `MIGRATION_PARITY_AUDIT_V4.md` §0 pour la ventilation
complète par statut, et la fin du rapport livré à l'utilisateur pour l'ordre recommandé de Phase B.

Ce fichier sera alimenté lot par lot, dans le même format que `MIGRATION_PARITY_PROGRESS_V3.md`,
uniquement lorsque l'utilisateur aura explicitement demandé le démarrage de la Phase B V4 (voir
consigne du prompt d'audit : "Une fois l'audit V4 terminé, arrête-toi... Je déciderai ensuite quand
commencer la Phase B").

Pour chaque lot futur, le format attendu est :

```
## <date> — Phase B V4 — Lot N : <ID> (<titre court>)

**Commit** : `<sha>` — CI **<résultat>**.

**Cause exacte** : ...

**Fichiers modifiés** : ...

**Flux frère vérifié** : ...

**Résultat CI** : ...

**Statut honnête après correction** : ...
```

Aucun finding ne doit être marqué corrigé dans ce fichier tant que le code correspondant n'a pas
été réellement modifié, committé, poussé, et vérifié en CI verte — même règle que V3.

---

## 2026-08-23 — Phase B V4 — Lot P0-1 : V4-F-065 + V4-F-066 (Wallet — crédit de récompense envoie le
solde total au lieu du delta, argent réel)

**Statut avant** : V4-F-065 = ouvert (P0, découvert Phase A) ; V4-F-066 = ouvert (P2, découvert Phase A).

### Vérification Android (obligatoire avant toute modification Swift)

Fichiers relus en entier : `wallet/WithdrawActivity.java` (lignes 98,116,541-563),
`wallet/TransfertCoinsActivity.java` (lignes 68,79,303-322), `wallet/ConversionActivity.java`
(lignes 60,73,228-248), `wallet/WalletRepository.java` (lignes 301-328).

**Comportement Android exact** (identique dans les 3 Activities) :
```java
private void addCoins(float coins) {
    coinCount += coins;                                    // crédit local INCONDITIONNEL (affichage)
    Settings.setFloatPreference(this, infoContract.COINS_AMOUNT, coinCount);
    walletViewModel.updateToServer(this, coinCount, coins); // coinCount=solde total (repli local
}                                                            // SEULEMENT), coins=CE gain (envoyé réseau)

// WalletRepository.java
public void updateToServer(Context context, float totalAmoun, float currenGainCoins){
    float currentAmouont = pendingCoinCount + currenGainCoins;   // DELTA réellement envoyé au réseau
    map.put("coins", String.valueOf(currentAmouont));            // → POST rewardedCoins
    td.Post(map, "rewardedCoins", new Callback() {
        onResonse: cv.put("coinsAmount", totalAmoun); PENDING_COINS_AMOUNT = 0;   // solde LOCAL only
        onError:   pendingCoinCount += currenGainCoins; persist PENDING_COINS_AMOUNT;
    });
}
```
**Endpoint** : `POST rewardedCoins`. **Paramètres** : `{id, coins, type}` — `coins` = `pendingCoinCount
+ currenGainCoins` (delta), **jamais** le solde total. **Réponse serveur** : gérée par `onResonse`/
`onError` du callback `td.Post` (pas de corps de réponse inspecté au-delà du succès/échec) ; sur
succès, remise à zéro du montant en attente local ; sur échec, accumulation locale pour retry au
prochain crédit.

### Comparaison avec iOS (avant correctif)

`Wallet/WithdrawView.swift:131-137`, `TransferCoinsView.swift:97-104`, `ConversionView.swift:58-65` —
les 3 fonctions `showRewardedInterstitialAfterSuccess()` faisaient :
```swift
UserSession.shared.coinsAmount += reward
try? await WalletRepository.shared.creditReward(userId: userId, totalAmount: UserSession.shared.coinsAmount, type: "coins")
```
`creditReward(totalAmount:)` mappe directement son paramètre sur le champ réseau `"coins"`
(`WalletRepository.swift:93-96`) — donc le SOLDE TOTAL du compte (après crédit local) était envoyé
comme delta. `try?` avalait aussi toute erreur, sans aucune logique `pendingCoinsAmount` (contrairement
à `EarnCoinsView.swift`, seul des 4 sites déjà corrigé lors du cycle V3, V3-F-092).

### Divergence réelle identifiée

Un seul et même bug (V4-F-065 = valeur incorrecte envoyée ; V4-F-066 = absence de retry sur échec)
provenant du fait que la fonction Android de référence `updateToServer` combine ATOMIQUEMENT les deux
comportements — les corriger séparément aurait signifié implémenter la moitié de la logique Android
maintenant et l'autre moitié plus tard, ce qui ne correspond à aucune structure réelle du code source.
Les deux ont donc été corrigés dans le même lot, sur les 3 mêmes fichiers/fonctions.

### Correctif appliqué

Dans les 3 fonctions `showRewardedInterstitialAfterSuccess()` :
```swift
UserSession.shared.coinsAmount += reward
let amountToReport = Double(UserSession.shared.pendingCoinsAmount) + reward
do {
    try await WalletRepository.shared.creditReward(userId: userId, totalAmount: amountToReport, type: "coins")
    UserSession.shared.pendingCoinsAmount = 0
} catch {
    UserSession.shared.pendingCoinsAmount += Int(reward)
}
```
Reproduit exactement le motif déjà établi et validé dans `EarnCoinsView.onRewardEarned` (branche
`coins`, V3-F-092) — pas une nouvelle invention, une application du même correctif déjà en production
ailleurs dans ce fichier.

### Flux frères vérifiés (aucun autre écran wallet avec le même mauvais calcul)

`grep -rn "creditReward" Sources/TiinverSwift` → exactement 5 sites : les 2 dans `EarnCoinsView.swift`
(déjà corrects, gems+coins), et les 3 corrigés ici. `grep -rn "RewardedInterstitial|rewardedCoins|
onUserEarnedReward"` → confirme aucun autre fichier wallet/monétisation n'utilise ce motif de crédit.
Aucun autre site à corriger.

**Fichiers modifiés** : `Sources/TiinverSwift/Wallet/WithdrawView.swift`,
`Sources/TiinverSwift/Wallet/TransferCoinsView.swift`, `Sources/TiinverSwift/Wallet/ConversionView.swift`.

**Commit** : `393b485`.

**Résultat CI** : run `32663823532` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée), PUIS seulement
(pas `COMPLETE_PARITY_VALIDATED` même après CI verte — test réel requis) : regarder la pub
rewarded-interstitial après un retrait/transfert/conversion réussi sur un compte réel, confirmer via
un outil d'inspection réseau que le champ `"coins"` envoyé à `rewardedCoins` correspond bien au gain
de LA publicité (pas au solde total affiché), et confirmer que le solde serveur (rechargé depuis
`getuserbyid`) augmente du montant attendu et non d'un montant absurdement plus élevé.

---

## 2026-08-23 — Phase B V4 — Lot P0-2 : V4-F-040 (Calls — push VoIP pendant un appel en cours saute
le report CallKit obligatoire)

**Statut avant** : ouvert (P0, découvert Phase A).

### Vérification (obligatoire avant toute modification Swift)

Ce finding n'a PAS d'équivalent Android — PushKit/CallKit sont des obligations de plateforme propres
à iOS (Android n'a aucun contrat système équivalent pour les push d'appel entrant). La référence de
correction est donc double : (1) le contrat Apple lui-même (chaque push VoIP DOIT provoquer un
`CXProvider.reportNewIncomingCall`, sous peine de révocation du droit de recevoir des push VoIP après
manquements répétés), et (2) le motif DÉJÀ appliqué et validé dans la branche sœur de la même
fonction (`voIPPushManager(_:didReceiveIncomingCallPayload:completion:)`, branche "payload malformé",
`CallCoordinator.swift:464-483`, corrigée lors du cycle V3, V3-F-031) : reporter un appel générique
puis le terminer immédiatement (`reason: .failed`) plutôt que de ne jamais reporter.

Relu en entier `CallCoordinator.swift` (le fichier complet) pour tracer les DEUX chemins réels qui
atteignent la garde `guard state == .idle else { ... }` (ligne 199) :
- **Chemin (a)** : `ChatRepository.swift:249`, `Task { await CallCoordinator.shared.
  handleIncomingCall(profile:chatType:) }` — appel entrant déclenché par socket normal (app déjà
  active), `onReported` non fourni = `nil`. AUCUNE obligation PushKit sur ce chemin.
- **Chemin (b)** : `CallCoordinator.swift:501` (à l'intérieur de `voIPPushManager(_:
  didReceiveIncomingCallPayload:completion:)`), `onReported: completion` — le callback PushKit du
  système, avec obligation de report AVANT de l'appeler, quel que soit l'état de l'app.

**Comportement Android le plus proche à ne PAS reproduire par erreur** : `ChatRepository.
lunchcall` (Android) ne fait RIEN si `CallService.isOnCall` est déjà vrai — confirmé qu'un second
appel entrant pendant un appel en cours est un no-op silencieux côté Android aussi. Ce comportement
est correct et fidèle pour le CHEMIN (a) — ne pas y ajouter de report CallKit inventerait un
comportement absent d'Android. Seul le CHEMIN (b), propre à la plateforme iOS, nécessite le correctif.

### Divergence iOS (avant correctif)

`guard state == .idle else { onReported?(); return }` — pour les DEUX chemins, `onReported?()` était
appelé (ou rien, si nil) SANS jamais appeler `callKit.reportIncomingCall`. Pour le chemin (b), cela
viole le contrat PushKit exactement de la même façon que le bug déjà corrigé sur la branche "payload
malformé" de la fonction voisine — mais ce point de défaillance précis n'avait jamais été traité.

### Correctif appliqué

```swift
guard state == .idle else {
    guard let onReported else { return }              // chemin (a) : no-op fidèle à Android, inchangé
    let uuid = UUID()                                  // chemin (b) : obligation PushKit
    try? await callKit.reportIncomingCall(uuid: uuid, callerName: profile.nikname ?? profile.username ?? "Appel entrant")
    onReported()
    callKit.reportCallEnded(uuid: uuid, reason: .failed)
    return
}
```
Le chemin (a) reste un no-op silencieux (comportement Android fidèlement reproduit, inchangé). Le
chemin (b) reproduit exactement le motif déjà validé de la branche "payload malformé" voisine.

### Flux frères vérifiés

`grep -n "handleIncomingCall("` sur tout le projet → exactement 2 sites d'appel réels de
`CallCoordinator.handleIncomingCall` (`ChatRepository.swift:249` et `CallCoordinator.swift:501`),
tous deux tracés et couverts explicitement ci-dessus. Aucun autre site n'atteint cette garde.

**Fichiers modifiés** : `Sources/TiinverSwift/Calls/CallCoordinator.swift`.

**Commit** : `14e5ee1`.

**Résultat CI** : run `32664500075` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée), PUIS seulement (pas
`COMPLETE_PARITY_VALIDATED` même après CI verte — test réel quasi impossible à déclencher de façon
fiable sans un second appareil ET un backend VoIP fonctionnel pour produire ce scénario précis :
recevoir un vrai push VoIP pendant qu'un appel est déjà en cours. Le contrat serveur VoIP reste de
toute façon non défini — voir V3-F-031/PROGRESS_V3.md. Risque documenté, corrigé par construction,
non observable en pratique tant que le backend VoIP n'existe pas).

## 2026-08-23 — Phase B V4 — Lot P0-3 : V4-F-007 (Viewer plein écran — actions supprimer/signaler/
bloquer/commenter/télécharger mortes)

**Commit** : `d9bb80e` — CI **run 32665481871, conclusion: success**.

### Vérification Android (avant tout changement)

Quatre menus "..." Android lus intégralement et comparés :

- `uploadPerfilPhoto/ProfileFeedFragment.java:682-849` (Profile) — 6 items (`delete_content`,
  `copy_link`, `unfollow`, `block_content`, `report_content`, `download`), `hide[]` masque tout sauf
  `delete_content` pour ses propres posts. `download` RÉELLEMENT câblé :
  `addingDownloadingFileToQueue` → `checkBestQualityAndDownload` (sonde 720p/480p/360p via
  `VideoPlaybackCoordinator.urlExists`, HEAD + `Referer: https://tiinver.com`, repli sur
  `cdn_content_url` brut) → `downloadFile` (`DownloadManager`, `Referer: https://tiinver.com`,
  `.mp4`/`.webp`).
- `Activity/ui/MainFragment.java:1260-1367` (Feed principal) — `ids[]` NE CONTIENT PAS
  `R.id.download` ; le `else if (view.getId()==R.id.download)` existant (1361-1367) est mort
  (inatteignable) ET buggé (copie-collé qui rouvre l'écran Report au lieu de télécharger).
- `NotiLikecmt/FullScreenMedia.java:485-494` (tap depuis Notifications/Search) — 5 items, sans
  `download`.
- `uploadPerfilPhoto/HashtagProfile.java:637-646` (tap depuis résultats hashtag) — 5 items, sans
  `download`.

Conclusion Android : le menu "..." plein écran est une implémentation PROPRE à chaque fragment (pas
partagée), et `download` n'est câblé QUE dans `ProfileFeedFragment`. Un portage qui l'ajouterait aux
3 autres contextes migrerait une fonctionnalité qui n'existe nulle part ailleurs côté Android.

### Écart iOS constaté (portée RÉELLE, plus large que le texte d'audit initial)

L'audit ciblait uniquement Profile, mais `FeedDetailPagerView` (le pager plein écran, réutilisé par
6 écrans) exposait DEUX initialiseurs : `init(viewModel:...onComment:onMore:...)` — utilisé
UNIQUEMENT par `FeedView` (fil principal), avec de vraies closures — et `init(posts:...)`, dont les
paramètres `onComment`/`onMore` retombaient sur `{ _ in }` (no-op) car cet init ne les exposait même
pas. `grep -n "FeedDetailPagerView("` confirme que **5 des 6 appelants** utilisent ce second init :
`SearchView.swift:146`, `HashtagFeedView.swift:78`, `NotificationsListView.swift:53`,
`HomeShellView.swift:145`, `Profile/ProfileView.swift:65`. Sur ces 5 écrans, le bouton "..." et le
bouton commentaire du viewer plein écran étaient donc de purs éléments visuels sans effet — pas
seulement depuis Profile comme le texte d'audit le formulait. `download`, séparément, était absent
même de l'implémentation "de référence" (`FeedView.swift`) : `grep` confirme zéro occurrence de
"download"/"télécharg" dans le fichier avant ce correctif — cohérent avec le fait que ce n'est pas
un item du menu Android d'origine (`MainFragment`/`FullScreenMedia`/`HashtagProfile`).

### Correctif appliqué

1. Tout l'état d'action (`moreActionsPost`, `reportTargetPost`, `showReportReasons`,
   `blockTargetPost`, `commentsPost`, `boostTargetPost`, `statsTargetPost`) et les
   `.sheet`/`.confirmationDialog`/`.alert` associés, déplacés DE `FeedView` (où ils ne servaient que
   le pager) VERS `FeedDetailPagerView` elle-même — la vue possède déjà le `FeedViewModel` complet
   (`deleteOwnPost`, `hideOthersPost`, `unfollow`, `block`, `report`, tous déjà présents et
   fonctionnels, non modifiés ici).
2. Les paramètres `onComment`/`onMore` supprimés (plus nécessaires, l'état est interne) ; remplacés
   par deux flags : `showManagementActions: Bool = false` (Statistiques/Promouvoir — `FeedView`
   uniquement, aucun équivalent Android ailleurs) et `includesDownload: Bool = false` (`ProfileView`
   uniquement, seul menu Android où `download` est réellement câblé).
3. `FeedView.swift`'s propre grille (`FeedGridCell`/`MainFragment.OnclickMoreExpand`) **non
   touchée** — elle possédait déjà sa propre implémentation fonctionnelle, distincte côté Android
   (`MainFragment` vs les 3 fragments plein écran), donc légitimement dupliquée plutôt que
   partagée — fidèle à la structure Android réelle (4 implémentations Java indépendantes).
4. Nouveau fichier `Sources/TiinverSwift/Feed/FeedMediaDownloader.swift` — port de
   `checkBestQualityAndDownload`/`extractVideoId`/`downloadFile` : sonde HEAD 720p→480p→360p
   (`Referer: https://tiinver.com`, timeout 3s, succès uniquement sur 200 — fidèle à
   `responseCode == HTTP_OK`, pas toute la plage 2xx), repli sur `cdn_content_url` brut, téléchargement
   avec le même `Referer`, puis `PHPhotoLibrary.performChanges` (équivalent iOS le plus proche du
   `DownloadManager` public Android — pas de dossier "Downloads" partagé sur iOS). Permission ajoutée :
   `NSPhotoLibraryAddUsageDescription` (`project.yml`) — distincte de la permission lecture déjà
   présente pour la publication.

### Flux frères vérifiés

`grep -n "FeedDetailPagerView("` sur tout le projet → exactement 6 sites d'appel, tous couverts :
`FeedView.swift` (`showManagementActions: true`), `ProfileView.swift` (`includesDownload: true`),
`SearchView.swift`/`HashtagFeedView.swift`/`NotificationsListView.swift`/`HomeShellView.swift`
(défauts `false`/`false` — obtiennent automatiquement le menu à 5 items de base, fidèle à
`FullScreenMedia`/`HashtagProfile`, sans câblage supplémentaire par écran).

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedView.swift`,
`Sources/TiinverSwift/Feed/FeedMediaDownloader.swift` (nouveau),
`Sources/TiinverSwift/Profile/ProfileView.swift`, `project.yml`.

**Résultat CI** : run `32665481871` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — chacune des 5 actions (supprimer/signaler/bloquer/commenter/
télécharger) doit être vérifiée séparément sur device réel, depuis CHACUN des 6 points d'entrée
(consigne explicite de l'utilisateur : "Ne pas considérer le viewer comme corrigé simplement parce
qu'il s'affiche"). Point d'attention spécifique pour le test réel : le téléchargement nécessite une
autorisation Photos ("Ajouter uniquement") jamais demandée avant ce correctif — premier appel
déclenchera la boîte de dialogue système iOS, à valider manuellement.

## 2026-08-23 — Phase B V4 — Lot P0-4 : V4-F-008 (Profile — upload photo de profil contourne
BunnyCDN, porte un chemin Android mort)

**Commit** : `4293e06` — CI **run 32673048282, conclusion: success**.

### Vérification Android (avant tout changement)

Relecture directe (pas seulement les conclusions de l'audit Phase A, déjà double-confirmées par 2
agents indépendants à l'époque) :

- `uploadPerfilPhoto/AddPerfilFoto.java:157-173,557-558` — `uploadProfilePicture(uri)` (ligne 157)
  démarre `ProfileService` avec `ACTION_UPLOAD` et un `UploadData(token, userId, fileUri)`. Site
  d'appel réel confirmé : ligne 557, `uploadProfilePicture(uri.toString());`, TOUJOURS exécuté.
  Juste en dessous (ligne 558) : `// profileViewModel.uploadPhotoProfile(foto);` — **commenté**,
  seul site d'appel possible de la méthode `uploadPhotoProfile` côté `ProfileRepository.java`,
  confirmant que cette dernière est un chemin mort, jamais exécuté en pratique.
- `uploadPerfilPhoto/service/ProfileService.java:174-321` — flux réel :
  1. `uploadImageToBunny(data)` (274-321) : `PUT https://storage.bunnycdn.com/tiinver-media/
     tiinver/profile/photos/{token}.webp`, header `AccessKey`, octets bruts
     (`ProgressRequestBodyUri`, `application/octet-stream`).
  2. Sur succès HTTP, `cdn_content_url = cdn_url + folder + fileName` où `cdn_url =
     "https://cdn.tiinver.com/"` (ligne 60) — **URL ABSOLUE**, contrairement au chemin RELATIF que
     `FeedMediaUploader.uploadPhoto` renvoie pour les posts Feed (vérifié comme un écart réel entre
     les deux flux, pas une simplification de ce portage).
  3. `sendMetaDate(userId, cdn_content_url)` (178-244) : `POST user/avatar/add` avec `{id,
     column:"profile_picture", value:<url>, object_url:<url>}`, réponse `{"error":"false"/...}`
     (même convention que `JSONValue.isBackendSuccess`).

### Écart iOS constaté (avant correctif)

`ProfileRepository.uploadProfilePicture` (ligne 117 avant correctif) faisait un POST multipart
DIRECT vers `{SERVER}user` avec un fichier nommé `wn_image.jpeg` — reproduction fidèle de
`ProfileRepository.uploadPhotoProfile`/`HttpFileUploader` côté Android, qui est EXACTEMENT le chemin
confirmé mort ci-dessus. BunnyCDN n'était jamais sollicité pour cette fonctionnalité.

### Correctif appliqué

`ProfileRepository.uploadProfilePicture` réécrite pour reproduire le flux réel en 2 étapes :
```swift
let token = UUID().uuidString
let folder = "tiinver/profile/photos"
let filename = "\(token).webp"
// 1. PUT vers Bunny Storage
var putRequest = URLRequest(url: URL(string: "\(FeedMediaUploader.storageBaseURL)/\(FeedMediaUploader.storageZone)/\(folder)/\(filename)")!)
putRequest.httpMethod = "PUT"
putRequest.setValue(FeedMediaUploader.storageAPIKey, forHTTPHeaderField: "AccessKey")
// ... upload, vérification du statut HTTP ...

// 2. POST des métadonnées avec l'URL CDN ABSOLUE résultante
let objectURL = "\(APIEnvironment.cdnPhotoBaseURL)\(folder)/\(filename)"
let value = try await APIClient.shared.post(
    ["id": userId, "column": "profile_picture", "value": objectURL, "object_url": objectURL],
    endpoint: "user/avatar/add"
)
```
**Décision prise pendant ce lot** : les constantes de stockage BunnyCDN (`storageZone`/
`storageAPIKey`/`storageBaseURL`) sont RÉUTILISÉES depuis `FeedMediaUploader` (rendues internes,
`private` → sans modificateur) plutôt que redupliquées une 3ᵉ fois dans `ProfileRepository.swift`.
Android lui-même triple ces littéraux dans 3 fichiers source (`ActivityService.java`/
`UploadFileOrDataService.java`/`ProfileService.java`) — un portage strictement fidèle les aurait donc
aussi dupliqués une 3ᵉ fois. Écart délibéré, décidé avec l'utilisateur : éviter une occurrence
supplémentaire en clair de la clé d'accès dans le dépôt (le détecteur de secrets de la session a
bloqué le premier `git add`/`git push` contenant cette 3ᵉ copie littérale), sans aucun changement de
comportement réseau — même zone, même clé, même hôte, valeur identique à celle déjà committée dans
`FeedMediaUploader.swift`/`ChatMediaUploadService.swift`.

### Flux frères vérifiés

`grep -rn "uploadProfilePicture"` → un seul appelant réel (`ProfileViewModel.uploadProfilePicture`
→ `ProfileView.swift:85`). `CertificationRepository.submit` (`Discover/CertificationModels.swift`)
référence `ProfileRepository.uploadProfilePicture` dans un COMMENTAIRE ("même protocole que...") mais
ne l'appelle jamais — c'est un flux multipart-vers-backend SÉPARÉ et réellement correct
(`certification/request`, endpoint Android distinct, vérifié indépendamment), non affecté par ce
correctif.

**Fichiers modifiés** : `Sources/TiinverSwift/Profile/ProfileRepository.swift`,
`Sources/TiinverSwift/Feed/FeedMediaUploader.swift` (constantes de stockage rendues internes).

**Résultat CI** : run `32673048282` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — nécessite de changer l'avatar sur un compte réel et de confirmer par
inspection réseau que le PUT Bunny (statut 2xx) et le POST `user/avatar/add` (`error:"false"`)
aboutissent tous deux, et que l'avatar affiché après rechargement du profil (`getuserbyid`)
correspond bien à l'image envoyée — pas seulement que l'UI locale se met à jour immédiatement après
le retour de la fonction (optimisme local possible même si le POST de métadonnées échouait
silencieusement côté serveur, scénario non couvert par la seule CI).

---

**Backlog P0 (V4) épuisé** — les 4 lots P0 (P0-1/V4-F-065+066, P0-2/V4-F-040, P0-3/V4-F-007, P0-4/
V4-F-008) sont tous `BUILD_VALIDATED`, CI verte. Prochain : liste P1 (23 items) dans l'ordre exact
donné par l'utilisateur, en commençant par V4-F-020.

## 2026-08-23 — Phase B V4 — Lot P1-1 : V4-F-020 (Groups — mutations ignorent les rejets backend)

**Commit** : `6190dee` — CI **run 32673545395, conclusion: success**.

### Vérification Android (avant tout changement)

`Http/TransportData.java:615-681` (`Post`), lu en entier — le point d'entrée réseau commun aux 7
mutations citées par l'audit :
```java
public void onResponse(JSONObject response) {
    String error = response.getString(ERROR);
    if (callBack != null) {
        if (error.equals("false")) {
            callBack.onResonse(context, 0, response);   // action TOUJOURS 0 ici — littéral, pas un champ lu
        } else {
            String message = response.getString(MESSAGE);
            callBack.onError(message);                   // rejet backend → onError, jamais onResonse
        }
    }
}
```
Confirme que le `if (action==0)` visible dans chaque appelant (`SettingGroupMessageFragmant.java:553`,
`ChangeGroupTopicActivity.java`, `AddGroupDescriptionActivity.java`, `GroupDetailActivity.java`) est
un artefact — `action` est un littéral `0` fixé par le framework à l'intérieur de la branche succès,
JAMAIS lu depuis la réponse. Le vrai gate Android est `error.equals("false")`, exactement l'équivalent
de `JSONValue.isBackendSuccess` déjà utilisé ailleurs dans ce portage.

### Écart iOS constaté (avant correctif)

Les 7 méthodes de `GroupRepository.swift` (`updateMemberRole`, `removeMember`, `updateDescription`,
`updateName`, `leaveGroup`, `subscribeToGroup`, `renewGroupSubscription`) faisaient toutes `_ = try
await APIClient.shared.post(...)` — la réponse était systématiquement DISCARDÉE, jamais inspectée.
Contraste net avec `createGroup`/`fetchGroup` dans le MÊME fichier, qui font déjà `guard
value.isBackendSuccess else { throw ... }`.

### Correctif appliqué

Ajout du même garde aux 7 méthodes :
```swift
let value = try await APIClient.shared.post(params, endpoint: "...")
guard value.isBackendSuccess else {
    throw JSONError.typeMismatch(value.backendErrorMessage ?? "...")
}
```

### Flux frères vérifiés

Les 7 sites d'appel (`GroupDetailView.swift` ×5, `ChatViewModel.resolveGroupSubscription` ×2)
enveloppaient DÉJÀ chaque appel dans un `do { try await ...; <effets locaux> } catch { errorMessage =
... }` — aucun changement nécessaire côté appelants, le `catch` existant n'avait simplement jamais
rien à attraper avant ce correctif. `grep "_ = try await APIClient" GroupRepository.swift` → 0
occurrence restante après correctif (toutes les mutations du fichier vérifient désormais leur
réponse).

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/GroupRepository.swift`.

**Résultat CI** : run `32673545395` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — nécessite de provoquer un rejet backend réel (ex. retirer un membre
déjà retiré, renommer un groupe sans les droits requis) et de confirmer que le message d'erreur
s'affiche SANS que l'effet local (membre disparu, nom mis à jour, écran fermé) ne soit appliqué.

## 2026-08-23 — Phase B V4 — Lot P1-2 : V4-F-032 (Feed — supprimer son propre post le retire même si
le serveur rejette)

**Commit** : `f503a72` — CI **run 32674024379, conclusion: success**.

### Vérification Android (avant tout changement)

`Activity/adapter/ActivityAdapter.java:847-867` (`deleteMyPost`), lu en entier — même contrat
`TransportData.Post` déjà vérifié pour V4-F-020 (`Http/TransportData.java:615-681`) :
```java
td.Post(map, "deleteactivity", new Callback() {
    public void onResonse(Context context, int action, JSONObject object) {
        Toast.makeText(context, ...effectuer..., Toast.LENGTH_LONG).show();
        deletePostById(mediaObject.getId());   // retrait LOCAL — uniquement ici, succès confirmé
    }
    public void onError(String message) {
        Toast.makeText(context, ...errorLoad..., Toast.LENGTH_LONG).show();  // PAS de retrait local
    }
});
```

### Écart iOS constaté (avant correctif)

`FeedViewModel.deleteOwnPost` (lignes 144-148 avant correctif) :
```swift
try? await repository.deleteActivity(id: post.id, actorId: myId)
posts.removeAll { $0.id == post.id }
```
`FeedRepository.deleteActivity` (`FeedRepository.swift:243-246`) vérifiait DÉJÀ correctement
`value.isBackendSuccess` et levait une erreur sur rejet — le `try?` de l'appelant avalait cette
levée, puis `posts.removeAll` s'exécutait INCONDITIONNELLEMENT, qu'il y ait eu succès ou non.

### Correctif appliqué

```swift
do {
    try await repository.deleteActivity(id: post.id, actorId: myId)
    posts.removeAll { $0.id == post.id }
} catch {
    deleteError = "Échec de la suppression du post."
}
```
Nouvelle propriété `@Published var deleteError: String?` (équivalent du `Toast` d'erreur Android),
affichée via une alerte dans les 2 vues qui déclenchent `deleteOwnPost`.

### Flux frères vérifiés

`grep -n "deleteOwnPost"` → exactement 2 sites d'appel réels (`FeedView.swift` — menu "..." de la
grille — et `FeedDetailPagerView` — menu "..." du plein écran, voir V4-F-007/Lot P0-3). Alerte
`deleteError` ajoutée aux DEUX vues. `hideOthersPost` (branche non-propriétaire du même bouton, pas
d'appel serveur côté Android — juste un masquage local persisté) et `block` (même pattern `try?` +
retrait inconditionnel, MAIS finding séparé V4-F-033, prochain de la liste) délibérément NON touchés
dans ce lot — scope strictement limité à `deleteOwnPost`.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedViewModel.swift`,
`Sources/TiinverSwift/Feed/FeedView.swift`.

**Résultat CI** : run `32674024379` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — nécessite de provoquer un rejet serveur réel sur une suppression de
post propre (ex. token expiré, id déjà supprimé) et de confirmer que le post reste visible avec
l'alerte affichée, plutôt que de disparaître puis réapparaître au rechargement suivant.

## 2026-08-23 — Phase B V4 — Lot P1-3 : V4-F-033 (Feed — bloquer un utilisateur retire son post
même en cas d'échec ou de bascule inverse)

**Commit** : `8d6ebae` — CI **run 32674513016, conclusion: success**.

### Vérification Android (avant tout changement)

`Activity/ui/MainFragment.java:1704-1758` (`block`), lu en entier :
```java
td.Post(map, "block", new Callback() {
    public void onResonse(Context context, int action, JSONObject object) {
        String response = object.getString("message");
        if (response.equals(USER_BLOCKED)) {
            collapseAll();
            mAdapter.deletePost(mediaObject.getActor());   // retrait local — UNIQUEMENT ici
            ...
        } else if (response.equals(USER_UNBLOCKED)) {
            ...                                             // PAS de retrait local — bascule inverse
        }
    }
    public void onError(String message) {
        Toast.makeText(...errorLoad..., Toast.LENGTH_LONG).show();  // PAS de retrait local non plus
    }
});
```
`infoContract.java:101,103` confirme `USER_BLOCKED="USER BLOCKED"` / `USER_UNBLOCKED="USER UNBLOCKED"`
— exactement la comparaison déjà faite côté iOS dans `ProfileRepository.toggleBlock`
(`(try? value.string("message")) == "USER BLOCKED"`).

### Écart iOS constaté (avant correctif)

`FeedViewModel.block` (lignes 216-222 avant correctif) :
```swift
_ = try? await profileRepository.toggleBlock(...)
posts.removeAll { $0.id == post.id }
```
`toggleBlock` retournait DÉJÀ le bon `Bool`, mais le résultat était discardé et le retrait local
s'exécutait dans TOUS les cas — succès de blocage, bascule vers déblocage, ou échec réseau/backend.

### Correctif appliqué

```swift
guard let blocked = try? await profileRepository.toggleBlock(...), blocked else { return }
posts.removeAll { $0.id == post.id }
```

**Décision de scope prise pendant ce lot** : PAS d'UI d'erreur ajoutée ici, contrairement à
V4-F-032. `toggleBlock` ne vérifie pas `isBackendSuccess` (retourne `false` aussi bien pour un
déblocage légitime que pour un rejet backend) — les distinguer aurait nécessité de modifier
`toggleBlock` elle-même, qui est aussi utilisée par `ProfileViewModel.toggleBlock` (bouton bloquer de
l'écran Profil, comportement différent et déjà correct — bascule un état `Bool` local, pas de retrait
de liste). Modifier son contrat aurait dépassé le périmètre de ce finding précis et risqué d'affecter
un appelant non concerné. Le comportement correct pour V4-F-033 (ne pas retirer le post) est de toute
façon identique que la cause soit "juste débloqué" ou "rejet backend" — aucune perte de fidélité.

### Flux frères vérifiés

`grep -n "viewModel.block("` → exactement 2 sites d'appel (`FeedView.swift` — menu "..." de la
grille et du plein écran, tous deux derrière la même alerte de confirmation `blockTargetPost`),
aucun ne dépend de la valeur de retour de `block()` — aucun changement nécessaire côté appelants.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedViewModel.swift`.

**Résultat CI** : run `32674513016` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — nécessite de bloquer réellement un utilisateur depuis le Feed et de
confirmer le retrait du post, puis de débloquer et de confirmer qu'aucun post ne disparaît par erreur.

## 2026-08-23 — Phase B V4 — Lot P1-4 : V4-F-042 (WebRTC-Calls — notification d'appel manqué
déclenchée du mauvais côté)

**Commit** : `9de2d73` — CI **run 32674952912, conclusion: success**.

### Vérification Android (avant tout changement)

`messagerie/ui/call/CallActivity.java`, lu en entier :
- Ligne 85 : `private boolean isCalleMissedCall = true;` (valeur par défaut).
- Ligne 476 (`callEnd`, événement socket reçu quand l'AUTRE partie termine l'appel) : `isCalleMissedCall
  = false;`.
- Ligne 506 (`onAccepCall`, appel décroché) : `isCalleMissedCall = false;`.
- Lignes 509-525 (`endCall`, déclenché quand CE device raccroche) : `if (isCalleMissedCall) {
  callService.notifyMissedCall(...); }`.

Donc `notifyMissedCall` ne se déclenche QUE si `endCall()` est atteint alors que
`isCalleMissedCall` est encore à sa valeur par défaut `true` — c'est-à-dire ni décroché, ni terminé
par l'autre partie. Question clé : QUI atteint `endCall()` dans ce scénario ? Vérifié dans
`CallService.java:571-612` : `CallActivity` (la classe qui possède TOUT ce mécanisme) n'est lancée
QUE dans la branche `if (callType == CallModel.OUTGOINGCALL)` (ligne 571-578) — le côté `INCOMINGCALL`
(lignes 591-612) route TOUJOURS vers `IncomingCallActivity`, une classe SÉPARÉE qui n'appelle JAMAIS
`notifyMissedCall`. Conclusion sans ambiguïté : le message "appel manqué" n'est enregistré QUE côté
APPELANT, quand il raccroche lui-même un appel sortant jamais décroché.

### Écart iOS constaté (avant correctif)

`CallCoordinator.swift` (`performEndCall`, avant correctif) :
```swift
if !isOutgoingCall, !wasAnswered {
    chatRepository.notifyMissedCall(...)
}
```
Condition EXACTEMENT inversée : se déclenchait côté CALLEE (`!isOutgoingCall`) raccrochant un appel
entrant non décroché — le scénario qu'Android NE gère JAMAIS de ce côté — et jamais côté appelant
(le seul scénario réel Android).

### Correctif appliqué

```swift
if isOutgoingCall, !wasAnswered {
    chatRepository.notifyMissedCall(...)
}
```
Simple inversion de la garde, comme recommandé par l'audit — aucune logique supplémentaire requise.

### Flux frères vérifiés

`grep -n "notifyMissedCall"` → une seule occurrence d'appel dans tout le projet (celle corrigée
ici) ; `ChatRepository.notifyMissedCall` (le wrapper réseau) est un simple point d'entrée, pas de
logique de condition dupliquée ailleurs. `endCallFromRemote` (le chemin "l'autre partie a raccroché
en premier", équivalent iOS de `callEnd()` reçu du socket côté Android) ne déclenche PAS
`notifyMissedCall` — fidèle à Android, où ce même chemin (`callEnd()`) se contente de mettre
`isCalleMissedCall = false` sans notifier.

**Fichiers modifiés** : `Sources/TiinverSwift/Calls/CallCoordinator.swift`.

**Résultat CI** : run `32674952912` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — nécessite un test réel : passer un appel sortant non répondu et
raccrocher soi-même (confirmer le message "appel manqué" apparaît), puis recevoir un appel entrant et
le refuser sans décrocher (confirmer qu'AUCUN message "appel manqué" n'apparaît côté callee) —
idéalement avec un pair Android réel des deux côtés pour vérifier l'absence de doublon en
interopérabilité.

## 2026-08-23 — Phase B V4 — Lot P1-5 : V4-F-038 (Chat-Socket — message live perdu s'il arrive
pendant le chargement initial de l'historique, race condition)

**Commit** : `d093438` — CI **run 32675426271, conclusion: success**.

### Vérification Android (avant tout changement)

`messagerie/ui/ChatFragmentTest.java:220` : `private final LinkedList<MessageLib> messages = new
LinkedList<>();` — UNE SEULE instance de liste pour toute la durée de vie de l'écran, `final` (jamais
réassignée). Confirmé par grep (`LinkedList<MessageLib>` apparaît uniquement en déclaration de champ
et en paramètre de méthode utilitaire, jamais en `new LinkedList<>()` de remplacement en cours de
vie) : chargement initial ET réception socket AJOUTENT toujours à cette même liste, aucun des deux
ne la remplace jamais entièrement.

### Écart iOS constaté (avant correctif)

`ChatViewModel.loadInitial()` (avant correctif) :
```swift
let page = try? await messages.page(...)
var built: [ChatListItem] = []
for mlib in page ?? [] { appendWithDateSeparator(mlib, into: &built) }
items = built   // ← remplacement INCONDITIONNEL
```
`onIncoming` (câblé via `subscribeToRealtimeEvents` dès `init`, donc actif AVANT même que
`loadInitial()` ne soit appelée par `.task` côté `ChatView`) ajoute directement à `items` — capable
de s'exécuter PENDANT le `await messages.page(...)` ci-dessus (Combine → `Task { @MainActor in await
self.handle(event) }`, un nouveau `Task` indépendant, pas sérialisé avec `loadInitial()`). Si ça
arrive dans cette fenêtre, `items = built` écrase ensuite silencieusement l'ajout.

### Correctif appliqué

```swift
let page = (try? await messages.page(...)) ?? []
let fetchedIds = Set(page.compactMap(\.messageId))
let liveArrived = items.compactMap { item -> MessageLib? in
    guard case .message(let mlib) = item, let id = mlib.messageId, !fetchedIds.contains(id) else { return nil }
    return mlib
}
let merged = (page + liveArrived).sorted { (Double($0.stamp ?? "") ?? 0) < (Double($1.stamp ?? "") ?? 0) }
var built: [ChatListItem] = []
for mlib in merged { appendWithDateSeparator(mlib, into: &built) }
items = built
```
`items` (post-`await`) est inspecté pour tout `.message` absent de la page fraîche — ces messages
sont réinjectés dans le tri chronologique avant reconstruction des séparateurs de date.

### Flux frères vérifiés

`loadMore()` (pagination, `ChatViewModel.swift:167-178`) n'a PAS ce problème — elle fait
`items.insert(contentsOf: prepended, at: 0)` (insertion, jamais de remplacement de `items`), donc
aucune correction nécessaire là. `.task { await viewModel.loadInitial() }` (`ChatView.swift:64`) est
le seul site d'appel de `loadInitial()` — s'exécute une fois par apparition d'écran, confirmant que
`items` ne peut contenir QUE des messages arrivés via `onIncoming` pendant CETTE fenêtre précise au
moment de la fusion (pas de données périmées d'une session précédente à risque de pollution).

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/ChatViewModel.swift`.

**Résultat CI** : run `32675426271` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — scénario de course difficile à déclencher de façon fiable sans
outillage (nécessite un message reçu depuis un pair dans une fenêtre de quelques dizaines de
millisecondes) ; test réel suggéré : ralentir artificiellement `messages.page` en debug pour élargir
la fenêtre, envoyer un message depuis un second appareil pendant ce délai, confirmer qu'il reste
visible sans fermer/rouvrir la conversation.

## 2026-08-23 — Phase B V4 — Lot P1-6 : V4-F-017 (Settings — toggle confidentialité garde le mauvais
état visuel en cas d'échec serveur)

**Commit** : `d63c2f6` — CI **run 32675965460, conclusion: success**.

### Vérification Android (avant tout changement)

`setting/SettingPrivacityFragment.java:294-328` (`swichtToPrivate`), lu en entier :
```java
td.Post(param, "user", new Callback() {
    public void onResonse(Context context, int action, JSONObject object) {
        if (action == 0) {
            Settings.setStringPreference(...);
            account_type_switch.setChecked(isChecked);   // confirme la NOUVELLE position
        }
        dialog.dismiss();
    }
    public void onError(String message) {
        account_type_switch.setChecked(!isChecked);       // revert à l'ANCIENNE position
        dialog.dismiss();
    }
});
```
Point clé vérifié séparément : le listener réseau (`swichtToPrivate`) est câblé sur
`setOnClickListener` (ligne 174-178), PAS sur `setOnCheckedChangeListener` — `setChecked()` appelé
programmatiquement (succès ou échec) NE redéclenche PAS `swichtToPrivate`. Un revert Android est donc
purement visuel, sans second appel réseau.

### Écart iOS constaté (avant correctif) — cause racine plus profonde que prévu

`SettingPrivacyView.save` faisait `try? await ProfileRepository.shared.updateProfileField(...)`,
avalant toute erreur. Mais en creusant `updateProfileField` elle-même (`ProfileRepository.swift:105-
107`), cause racine plus profonde : `_ = try await APIClient.shared.post(...)` — discardait la
réponse SANS jamais vérifier `isBackendSuccess`, donc ne pouvait JAMAIS lever pour un rejet backend
(HTTP 200, `error:"true"`), seulement pour un échec réseau. Même un `do/catch` correctement écrit
dans `SettingPrivacyView.save` n'aurait donc PAS attrapé un rejet backend avant ce correctif plus en
amont.

### Correctif appliqué

1. `ProfileRepository.updateProfileField` vérifie désormais `isBackendSuccess` et lève sinon (même
   motif que `deleteActivity`/les 7 méthodes de `GroupRepository`, V4-F-020).
2. `SettingPrivacyView.save` : `do/catch`, revert `isPrivate` sur échec.
3. Un flag `isReverting` empêche le revert de redéclencher un second appel réseau via
   `.onChange(of: isPrivate)` — SwiftUI ne distingue pas nativement "tap utilisateur" de "mutation
   programmatique" comme le fait `setOnClickListener` côté Android ; sans ce flag, revertir
   `isPrivate` aurait envoyé une requête supplémentaire non désirée (comportement qu'Android n'a
   jamais).

### Flux frères vérifiés

`grep -n "updateProfileField"` → 9 sites d'appel au total : 8 en `try?`
(`EditProfileView.swift` ×2, `EditPersonalInformationView.swift` ×7) — AUCUN changement de
comportement observable, ils ignoraient déjà toute distinction succès/échec ; `CategoryPickerView.
save` avait DÉJÀ un `do/catch` prêt pour un `throw` qui n'arrivait jamais — bénéficie du correctif
sans modification de son propre code (un rejet backend sur le changement de catégorie affiche
désormais réellement `errorText`, comme prévu par son code existant).

**Fichiers modifiés** : `Sources/TiinverSwift/Profile/ProfileRepository.swift`,
`Sources/TiinverSwift/Settings/SettingSubViews.swift`.

**Résultat CI** : run `32675965460` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — nécessite un test réel : couper le réseau (ou provoquer un rejet
backend), basculer le toggle "Compte privé", confirmer qu'il revient visuellement à son état précédent
SANS second appel réseau observable (outil d'inspection réseau), et confirmer qu'un changement réussi
persiste bien après rechargement de l'écran.

## 2026-08-23 — Phase B V4 — Lot P1-7 : V4-F-046 (Animems-ImportExport — collision PTS frame 0/frame 1
à l'export vidéo)

**Commit** : `b0b61ea` — CI **run 32676432499, conclusion: success**.

### Vérification Android (avant tout changement)

`engine/src/main/java/com/animems/engine/android/codec/MP4Encoder.java:1752-1753` :
```java
private long getPresentationTimeUsec(int frameIndex, int c) { return (((long) frameIndex * FRAME_DURATION) / FRAME_RATE) * getFrameDelay(c); }
private long getPresentationTimeUsec(int frameIndex)        { return frameIndex * FRAME_NS; }
```
La seconde surcharge (utilisée par `onAddBitmap`, ligne 1727, le chemin d'encodage par bitmap
pertinent pour Animems) : `frameIndex * FRAME_NS`, STRICTEMENT proportionnel, `frameIndex=0` →
`0`. Aucun `max(...)` ni clamp équivalent trouvé dans tout le fichier pour cette fonction.

### Écart iOS constaté (avant correctif)

`AnimemesExporter.swift:202` (avant correctif) :
```swift
let ptsNs = max(Self.frameDurationNs, Int64(f) * Self.frameDurationNs)
```
Pour `f=0` : `Int64(0) * frameDurationNs = 0`, puis `max(frameDurationNs, 0) = frameDurationNs`.
Pour `f=1` : `Int64(1) * frameDurationNs = frameDurationNs`, puis `max(frameDurationNs,
frameDurationNs) = frameDurationNs`. **Même résultat pour les deux frames** — collision confirmée
par calcul direct, pas seulement par lecture du code. `writer.startSession(atSourceTime: .zero)`
(ligne 150) fixe pourtant le début de session à t=0, jamais atteint par aucun échantillon écrit.

### Recherche de justification historique (avant suppression du `max`)

Aucun commentaire, aucune trace dans l'historique de ce fichier (`git log -p` sur les lignes
concernées, aucune mention de crash/contournement) ne justifie ce `max(...)` — absence de raison
documentée de le conserver, conformément à la demande explicite de l'utilisateur de vérifier ce point
avant suppression.

### Correctif appliqué

```swift
let ptsNs = Int64(f) * Self.frameDurationNs
```
Suppression pure et simple du `max(...)`, fidèle à `getPresentationTimeUsec(frameIndex)` côté
Android. Seul `f=0` change de valeur produite (0 au lieu de `frameDurationNs`) — `f>=1` produisait
déjà exactement la même valeur avec ou sans le `max` (`f * frameDurationNs >= frameDurationNs` est
toujours vrai pour `f>=1`), donc aucun risque de régression au-delà de la toute première frame.

### Flux frères vérifiés

`grep -n "frameDurationNs\|ptsNs" Sources/TiinverSwift/Animems/*.swift` → un seul site de calcul de
PTS dans tout le module (celui corrigé ici) ; la piste audio (`beginAudioPass`) utilise ses propres
timestamps natifs lus depuis `copyNextSampleBuffer()`, sans dépendance à ce calcul.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/AnimemesExporter.swift`.

**Résultat CI** : run `32676432499` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — nécessite un test réel : exporter une vidéo Animems, inspecter les
métadonnées de la piste vidéo résultante (ex. `ffprobe -show_frames`) pour confirmer que la 1ʳᵉ frame
est bien à pts=0 sans doublon de timestamp, et vérifier visuellement qu'aucune frame n'est perdue en
tout début de lecture.

## 2026-08-23 — Phase B V4 — Lot P1-8 : V4-F-048 (Animems-Interaction — zoom du canevas inerte
visuellement)

**Commit** : `da0e744` — CI **run 32677174090, conclusion: success**.

### Rigueur renforcée appliquée (consigne explicite de l'utilisateur pour Animems)

Chaîne complète tracée AVANT toute modification :
1. **UI Android** : `CanvasZoomController.java` — 2 boutons (+/−) + libellé + bouton "fit", `LinearLayout` autonome.
2. **Événement Android** : `setOnClickListener` → `zoom(delta)`/`reset()`.
3. **État Android** : `currentScale` (champ privé), clampé `[ZOOM_MIN dynamique, ZOOM_MAX=4.0]`.
4. **Renderer Android** : `applyZoom()` → `targetView.setPivotX/Y(centre)` + `setScaleX/Y(currentScale)`
   — transform VISUEL natif Android sur la vue `mView` (`MemesView2`) elle-même, DIRECTEMENT.
5. **Geste Android** : AUCUNE correction de coordonnées nécessaire côté Android — `View.setScaleX/Y`
   est un transform système que le dispatch tactile Android traduit automatiquement pour les gestes
   internes à la vue (comportement plateforme standard, pas de code applicatif dédié).
6. **UI/état/renderer/geste iOS AVANT correctif** : `CanvasZoomState`/`CanvasZoomControls`
   (`CanvasZoomController.swift`) — algorithme (1-3) DÉJÀ fidèlement porté (vérifié ligne par ligne
   contre Android : `updateMinZoom`≡`computeMinZoom`, `zoom(by:)`≡`zoom(delta)`, `reset()`≡`reset()`).
   Étape 4 (renderer) MANQUANTE : `currentScale` jamais appliqué au `Canvas` SwiftUI réellement rendu
   — confirmé par le commentaire de tête de `zoomControls` lui-même, laissé délibérément comme risque
   documenté par une session précédente plutôt que corrigé à l'aveugle.
7. **Export Android** : `zoomController.reset()` appelé AVANT `saveBitmapDrawed()`/
   `fromBitmapsToVideo()` (`AnimemesCompound.java:2574-2584`) — remet le zoom à 1.0 avant capture.
8. **Export iOS** : `AnimemesExporter.render(frame:into:)` — VÉRIFIÉ dessiner dans un `CVPixelBuffer`/
   `CGContext` construit INDÉPENDAMMENT du `Canvas` SwiftUI interactif (résolution/coordonnées propres
   à l'export, jamais partagées avec la vue éditée à l'écran). Aucun équivalent de l'étape 7 requis
   côté iOS — architectures différentes, pas un gap de parité.

### Pourquoi le risque documenté n'empêchait PAS une correction sûre

Le commentaire existant redoutait qu'un `.scaleEffect` sur le `Canvas` portant aussi `combinedGesture`
(glissement/pincement/rotation D'OBJETS, PAS de la vue) désynchronise les coordonnées de geste.
Analyse : `.scaleEffect` est un `GeometryEffect` SwiftUI de premier ordre — placé APRÈS `.gesture()`
dans la chaîne de modificateurs (donc englobant la vue porteuse du geste), SwiftUI continue de
convertir les coordonnées tactiles PHYSIQUES vers l'espace LOCAL non-transformé de la vue porteuse
AVANT de les reporter dans les callbacks du geste — motif standard pour du contenu zoomable qui gère
aussi ses propres gestes internes (analogue au `View.setScaleX/Y` + dispatch tactile automatique
d'Android, étape 5 ci-dessus).

### Correctif appliqué

`AnimemesEditorView.canvasArea` :
```swift
Canvas { ... }
    .frame(width: fitSize.width, height: fitSize.height)
    .background(Color(white: 0.08))
    .gesture(combinedGesture)
    .onAppear { ... }
    .onChange(of: fitSize) { ... }
    .onChange(of: state.version) { ... }
    .scaleEffect(zoomState.currentScale)   // ← ajouté, APRÈS .gesture()
```
`anchor` par défaut de `.scaleEffect` = `.center`, correspondant déjà au pivot centré qu'Android fixe
explicitement (`setPivotX/Y`). Commentaire de tête de `zoomControls` mis à jour pour refléter la
résolution (plus de mention "risque non résolu").

### Flux frères vérifiés

`zoomControls`/`rightToolbar` restent des SIBLINGS du `Canvas` dans le même `ZStack`, PAS affectés
par le `.scaleEffect` (appliqué uniquement à la sous-vue `Canvas`) — fidèle à Android où le contrôleur
de zoom et la barre d'outils sont des vues séparées dans le même `FrameLayout` parent, non affectées
par `mView.setScaleX/Y`. `AnimemesExporter` confirmé architecturalement isolé (voir étape 8 ci-dessus)
— aucun appel `reset()` équivalent à ajouter avant export.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/AnimemesEditorView.swift`.

**Résultat CI** : run `32677174090` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — le raisonnement sur le comportement de conversion de coordonnées
SwiftUI n'est PAS vérifiable empiriquement dans cet environnement (aucun accès Xcode/simulateur).
Test réel IMPÉRATIF avant de considérer ce finding réellement clos : zoomer via +/−, confirmer
l'effet visuel réel sur le canevas ; PUIS, à `currentScale != 1.0`, effectuer un glissement/
pincement/rotation sur un objet et confirmer qu'il suit le doigt SANS dérive de coordonnées — ce
second point est le risque technique précis que ce correctif ne peut pas garantir sans device réel.

## 2026-08-23 — Phase B V4 — Lot P1-9 : V4-F-049 (Animems-Interaction — marqueurs de keyframe sans
cible tactile, sélection/suppression inatteignables)

**Commit** : `fc60738` — CI **run 32677846820, conclusion: success**.

### Rigueur renforcée appliquée

Chaîne complète tracée AVANT tout câblage :
1. **Geste Android** : `TimelineView.onDown` (`TimelineView.java:826-877`) — `hitTestKeyframeMarker`
   testé EN PREMIER, avant icône/scrub/hit-test d'item. Un hit CONSOMME ENTIÈREMENT la touche
   (`return true`), sans jamais atteindre le reste de `onDown`.
2. **État Android** : `selectedKeyframe`/`selectedKeyframeLayerId`/`selectedKeyframeTrackName`
   (champs privés de `TimelineView`). Toggle : `tappedKf == selectedKeyframe` → suppression + clear ;
   sinon → (ré)sélection.
3. **Callback Android** : `AnimemesCompound.setOnKeyframeListener` — `onKeyframeSelected` NE FAIT
   RIEN (`{}` vide, sélection déjà mémorisée par `TimelineView` lui-même) ; `onKeyframeDeleteRequested`
   → `track.removeKeyframe(id)`, puis `obj.removeTrack(propertyName)` SI la piste devient vide,
   `timelineView.setLayers(...)` + `invalidate()` + `mView.postInvalidate()` (rafraîchit AUSSI le
   canevas principal).
4. **Rendu Android** : `drawKeyframeMarkers` (`TimelineView.java:687-708`) — losange plein
   (`kfFillPaint`, couleur par propriété) PUIS, si `kf == selectedKeyframe`, un losange CONTOUR blanc
   par-dessus (`kfSelectPaint`, `STROKE`, 2dp).
5. **État/geste/rendu iOS AVANT câblage** : `hitTestKeyframeMarker` (`TimelineViewModel.swift:333-350`)
   et `KeyframeTrack.removeKeyframe(id:)` (`KeyframeTrack.swift:70-72`) DÉJÀ portés fidèlement
   (vérifiés ligne par ligne) mais avec ZÉRO appelant — `combinedDragGesture`
   (`TimelineView.swift:149-221`) ne les référençait jamais. Aucun état de sélection de keyframe
   n'existait côté iOS.

### Correctif appliqué (4 fichiers)

1. `TimelineViewModel.swift` — nouvelle propriété `var selectedKeyframeId: String?`.
2. `AnimationObjectData.swift` — nouvelle méthode `removeKeyframe(propertyName:keyframeId:) -> Bool`
   (port de `KeyframeTrack.removeKeyframe(id)` + `if (track.isEmpty()) obj.removeTrack(...)`).
3. `AnimemesEditorState.swift` — nouvelle méthode `deleteKeyframe(layerId:propertyName:keyframeId:)`
   (port de `onKeyframeDeleteRequested`), incrémente `version` (PAS `renderVersion`) — changement
   structurel réel (les valeurs interpolées à la frame courante peuvent changer), fidèle au double
   `invalidate()`+`postInvalidate()` Android qui redessine AUSSI le canevas principal.
4. `TimelineView.swift` :
   - Nouveau cas `DragMode.keyframeTap` (port du `return true` d'`onDown` — consomme la touche
     entière, empêche tout scrub/pan/drag/resize pour le reste de ce flux tactile).
   - `hitTestKeyframeMarker` appelé EN PREMIER dans `combinedDragGesture`, avant `resolveMode` —
     toggle sélection/suppression fidèle au point 2 ci-dessus.
   - `drawKeyframeMarkers` : contour blanc (`stroke`, `.white`, largeur 2) ajouté PAR-DESSUS le
     losange plein quand `kf.id == model.selectedKeyframeId` — port de `kfSelectPaint`. Sans cet
     ajout (au-delà du strict texte de l'audit, qui ne mentionnait que hit-test+suppression),
     l'utilisateur n'aurait eu AUCUN moyen visuel de savoir quel keyframe est armé pour suppression
     au tap suivant — jugé nécessaire à la fidélité fonctionnelle réelle, pas une extension gratuite.

### Flux frères vérifiés

`grep -n "hitTestKeyframeMarker\|removeKeyframe\|selectedKeyframeId"` → exactement UN site d'appel
réel pour chacun des 2 anciens orphelins, cohérent avec les nouvelles déclarations — aucun autre
appelant à mettre à jour. `.onEnded` de `combinedDragGesture` vérifié : `.keyframeTap` ne correspond
à aucun `if case .dragItem/.resizeLeft/.resizeRight`, donc ne déclenche jamais
`applyTimelineItemsToLayers()` par erreur.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/TimelineViewModel.swift`,
`Sources/TiinverSwift/Animems/AnimationObjectData.swift`,
`Sources/TiinverSwift/Animems/AnimemesEditorState.swift`,
`Sources/TiinverSwift/Animems/TimelineView.swift`.

**Résultat CI** : run `32677846820` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : taper sur un keyframe (confirmer le contour blanc
de sélection) ; taper à nouveau DESSUS (confirmer la suppression ET que le canevas principal reflète
la valeur interpolée mise à jour) ; sélectionner un keyframe puis taper sur un AUTRE (confirmer un
simple changement de sélection, PAS de suppression accidentelle) ; vérifier qu'un glissement/
redimensionnement d'item de timeline reste inchangé (aucune régression sur les modes existants).

## 2026-08-23/24 — Phase B V4 — Lot P1-10 : V4-F-050 (Animems-UI — icônes verrou/visibilité par
calque totalement absentes, aucune protection au niveau geste)

**Commits** : `8ab3088` (correctif) + `1ff1032` (correctif CI, voir incident ci-dessous) — CI **run
32679329863, conclusion: success**.

### Rigueur renforcée appliquée — recommandation initiale de l'audit corrigée par relecture directe

`MemesView2.java`, lu en entier pour ce lot — la RECOMMANDATION de l'audit citait
`AnimemesGestureController.isPoint`/`touchDown`/`scale`/`rotate` comme sites de garde à ajouter.
Vérification directe : SEULS 3 sites réels testent `.isLocked()` dans `MemesView2.java` :
```java
// GestureListener.onScroll (translation à un doigt) — ligne 1577-1579
if (objectInAction >= 0 && !composer.getLayers().isEmpty()
        && !composer.getLayers().get(objectInAction).isLocked())
{ translation(-dx, -dy, objectInAction); invalidate(); }

// ScaleListener.onScale — ligne 1587
if (objectInAction >= 0 && !composer.getLayers().get(objectInAction).isLocked()) { ... }

// onTouchEvent, boucle de dispatch par calque — lignes 1604-1609
for (int i = 0; i < composer.getLayers().size(); i++)
    if (!composer.getLayers().get(i).isLocked()
            && composer.getLayers().get(i).getObjectType() != AnimationObjectData.Type.PATH)
        executeTouchEvent(event, i);   // rotate() est appelée DEPUIS cette méthode
```
`touchDown`/`isPointInsideObject` (`onSingleTapUp`, `onLongPress`) NE TESTENT `.isLocked()` NULLE
PART — confirmé par grep exhaustif du fichier. Un calque verrouillé reste donc TAPABLE/sélectionnable
côté Android ; seule la manipulation réelle (translation/échelle/rotation) est bloquée. La
recommandation de l'audit était donc imprécise sur ce point précis — corrigée par la vérification
directe, conformément à la méthode ("l'audit est une hypothèse à vérifier, pas une vérité").

Visibilité vérifiée séparément : `grep isVisible()/.visibility` dans `MemesView2.java` → toutes les
occurrences sont dans le code de RENDU, aucune dans le code de geste — la visibilité ne gate JAMAIS
le geste côté Android non plus (déjà correctement traité côté iOS pour le rendu,
`guard obj.visible else { continue }` dans `AnimemesEditorView.canvasArea`).

### Correctif appliqué

1. `AnimemesEditorState.toggleLocked(layerId:)`/`toggleVisible(layerId:)` (nouveau) — port de
   `onTrackIconClicked` (`AnimemesCompound.java:1645-1666`), `version += 1` (structurel, fidèle à
   `mView.prepare()+applyInterpolation()+postInvalidate()`).
2. Garde `!layers[idx].locked` ajoutée à `dragMoved`/`rotationChanged`/`scaleChanged` UNIQUEMENT
   (PAS `selectObject`, fidèle à la vérification ci-dessus).
3. `TimelineViewModel` : icônes verrou/œil lues DIRECTEMENT depuis `items`/`layers` (déjà porteurs
   de `.locked`/`.visibility`/`AnimationObjectData.locked/.visible`) plutôt que le registre
   générique `trackIcons`/`addTrackIcon` déjà présent mais orphelin — celui-ci réservé à la 3ᵉ icône
   Android (`id3`, "compose group"), fonctionnalité SÉPARÉE déjà différée ailleurs dans ce portage.
   Géométrie/hit-test port fidèle de `drawTrackIcons` (`iconSize=20dp, padding=8dp`,
   `touchPadH=4dp/V=8dp`).
4. `TimelineView` : nouveau `DragMode.iconTap` (port du `return true` d'`onDown` après un tap
   d'icône), hit-test icône inséré dans `combinedDragGesture` ENTRE le hit-test keyframe (lot
   précédent) et le repli `resolveMode` — même ordre que `onDown` Android
   (keyframe → icône → ruler/scrub → item). Icônes dessinées dans le panneau gauche du `Canvas`
   (jusqu'ici entièrement vide côté iOS).

### Incident CI (corrigé dans la foulée)

Le 1er commit (`8ab3088`) a échoué en CI : `TimelineView.swift:161:40: error: no exact matches in
call to instance method 'resolve'` — `context.resolve(Image(systemName:).foregroundColor(...))` ne
type-check pas sous le SDK Xcode 16.2 du runner (`Image.foregroundColor` n'y est pas garanti de
type `Image` pour cette surcharge de `resolve`). Corrigé (`1ff1032`) en dessinant via
`Text(Image(systemName:))` + `context.draw(_:at:)` directement — MÊME motif déjà éprouvé et
compilant dans ce fichier (`drawRuler`, labels de secondes de la règle), sans passer par
`resolve()`.

### Flux frères vérifiés

`grep -n "TrackIconKind\|iconScreenRect\|hitTestTrackIcon"` → un seul site d'appel pour chacun,
cohérent. `.onEnded` de `combinedDragGesture` vérifié : `.iconTap` ne correspond à aucun
`if case .dragItem/.resizeLeft/.resizeRight`. Registre `trackIcons`/`addTrackIcon` existant
délibérément NON touché (réservé à la fonctionnalité "compose group" séparée).

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/TimelineViewModel.swift`,
`Sources/TiinverSwift/Animems/AnimemesEditorState.swift`,
`Sources/TiinverSwift/Animems/TimelineView.swift`.

**Résultat CI** : run `32678716272` → `failure` (voir incident ci-dessus) ; run `32679329863`
(après correctif) → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée après correctif). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : taper l'icône verrou (confirmer la bascule visuelle
ET qu'un glissement/pincement/rotation du calque est ensuite BLOQUÉ), taper l'icône œil (confirmer
la bascule ET le masquage réel du rendu du calque), confirmer qu'un calque verrouillé reste
TAPABLE/sélectionnable (pas totalement exclu de l'interaction, fidèle à Android).

---

**Backlog P1 Animems (3 findings à rigueur renforcée, V4-F-046/048/049/050 — 4 lots car 046+048 sont
2 findings distincts malgré la numérotation proche) désormais ENTIÈREMENT clos**, chacun avec une
chaîne complète tracée sur les deux plateformes avant correction, conformément à la consigne
explicite de l'utilisateur pour ce domaine. Prochain : V4-F-001, retour à la liste P1 standard.

## 2026-08-24 — Phase B V4 — Lot P1-11 : V4-F-001 (Session-Auth — cold start bloqué derrière un
fetch réseau Firebase Remote Config)

**Commit** : `d7d50b0` — CI **run 32679885732, conclusion: success**.

### Vérification Android (avant tout changement)

`SplashActivity.java:80-122`, lu en entier :
```java
// ✅ 4. Naviguer IMMÉDIATEMENT avec les valeurs Firebase déjà en cache
FirebaseConfigManager config = FirebaseConfigManager.getInstance();
navigateAfterConfig(config, pf);          // SYNCHRONE, zéro I/O réseau

// ✅ 5. Fetch Firebase en arrière-plan pour la PROCHAINE ouverture
config.fetchAndActivate();                 // fire-and-forget, jamais attendu
```
`FirebaseConfigManager.getInstance()` (`setting/FirebaseConfigManager.java:37-56`) construit le
wrapper avec `remoteConfig.setDefaultsAsync(R.xml.remote_config_defaults)` — défauts APPLIQUÉS
SYNCHRONEMENT à l'init malgré le nom trompeur. `getExpireDay()`/etc. lisent donc soit ces défauts
(tout premier lancement, jamais de fetch réussi encore), soit les valeurs du DERNIER fetch réussi
(sessions suivantes) — dans les deux cas, un cache LOCAL, zéro réseau à cet instant précis.
`navigateAfterConfig` décide Home/Login/UpdateApp à partir de CE cache + `SessionManager.getUser()`
(lecture `SharedPreferences` synchrone).

### Écart iOS constaté (avant correctif)

`RootRouterView.checkForceUpdate()` (avant correctif) :
```swift
_ = await TiinverFirebaseConfigManager.shared.fetchAndActivate()   // VRAI fetch réseau, ATTENDU
let config = TiinverFirebaseConfigManager.shared
// ... lecture expireDay/expireMonth/expireYear seulement APRÈS
```
`configChecked` ne passe à `true` qu'après ce fetch — `RootRouterView.body` reste sur
`ProgressView()` (ni Home, ni Login) tant que `!configChecked`. `TiinverFirebaseConfigManager.
fetchAndActivate()` (`FirebaseConfigManager.swift:27-29`) n'a aucun timeout explicite — le SDK
Firebase peut mettre jusqu'à ~60s à échouer sur réseau dégradé/absent.

### Correctif appliqué

```swift
private func checkForceUpdate() async {
    let config = TiinverFirebaseConfigManager.shared   // lecture cache locale, ZÉRO réseau
    // ... expireDay/expireMonth/expireYear, forceUpdateRequired, configChecked = true (inchangé)

    // Port de config.fetchAndActivate() (sans listener, après navigation) — arrière-plan.
    Task { _ = await config.fetchAndActivate() }
}
```
`RemoteConfig.setDefaults(fromPlist: "RemoteConfigDefaults")` (`FirebaseConfigManager.swift:24`,
appelé à l'`init`) est le même mécanisme synchrone qu'Android — la lecture de `expireDay`/etc. reste
donc correcte et instantanée dès le tout premier lancement, sans dépendre d'un fetch préalable.

### Flux frères vérifiés

`grep -n "fetchAndActivate"` → un seul site d'appel réel dans tout le projet (`RootRouterView.
checkForceUpdate`, celui corrigé) ; les 4 autres usages de `TiinverFirebaseConfigManager.shared`
(`EarnCoinsView`/`WithdrawView`/`WalletViewModel`/`CertificationView`) ne lisent que des propriétés
déjà-en-cache (`coinsValue`, `certificationPrice`, etc.), aucun fetch bloquant ailleurs à corriger.

**Fichiers modifiés** : `Sources/TiinverSwift/Navigation/RootRouterView.swift`.

**Résultat CI** : run `32679885732` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : lancer l'app avec une session locale déjà valide
puis couper le réseau (ou simuler une latence extrême), confirmer l'arrivée quasi-instantanée sur
Home au lieu d'un spinner prolongé ; confirmer aussi qu'un rejet de mise à jour forcée (`expiryDate`
dépassée en cache) continue de s'afficher correctement dans ce même scénario réseau dégradé.

## 2026-08-24 — Phase B V4 — Lot P1-12 : V4-F-002 (Navigation-DeepLinks — lien profond résolu avant
le montage de HomeShellView est silencieusement perdu)

**Commit** : `97f87fd` — CI **run 32680432322, conclusion: success**.

### Vérification Android (avant tout changement)

`partage/ShareActivity.java:140-291` : résout la destination (user/post/groupe/paramètres/animems/
parrainage) puis appelle `startActivity(intent)` DIRECTEMENT — aucune dépendance à ce qu'une autre
`Activity` soit déjà à l'écran et à l'écoute d'un état partagé. Le lancement de l'écran cible EST
l'action elle-même, pas une notification qu'un autre composant doit capter.

### Écart iOS constaté (avant correctif)

`DeepLinkCenter.route(_:)` (`DeepLinkCenter.swift:44-46`) se contente de `pending = destination`
(`@Published`). Le SEUL consommateur, `HomeShellView.onChange(of: deepLinks.pending)`
(`HomeShellView.swift:190-205` avant correctif), ne réagit QUE sur une transition nil→valeur
survenant APRÈS que ce modificateur soit déjà attaché à la hiérarchie de vues — jamais pour une
valeur déjà présente au moment de l'attachement. Si un lien est résolu (`AppDelegate`/
`DeepLinkRouter`) PENDANT le cold start ou l'écran de login (`RootRouterView` affiche encore
`ProgressView()`/`AuthCoordinatorView`, `HomeShellView` pas encore monté), `pending` est déjà
non-`nil` au moment où `HomeShellView` apparaît enfin — `.onChange` ne se déclenche jamais pour cette
valeur, `consume()` n'est jamais appelé, le lien est perdu sans erreur ni indication.

### Correctif appliqué

Extrait la table de dispatch (`switch destination { ... }`) du corps de `.onChange` vers une méthode
partagée `handleDeepLink(_:)`, appelée :
1. Par le `.onChange(of: deepLinks.pending)` existant, inchangé dans son déclenchement.
2. PAR le `.task` déjà présent dans `HomeShellView` (rafraîchissement notifications/badge chat) —
   ajout d'une consommation de `deepLinks.pending` AU MONTAGE, fidèle au lancement direct
   `startActivity` d'Android qui ne dépend d'aucun état de montage préalable.

`DeepLinkCenter.consume()`'s `defer { pending = nil }` (déjà existant, non modifié) rend les deux
points d'appel sûrs par construction : si le `.task` consomme déjà la valeur au montage, le
`.onChange` suivant ne trouvera plus rien à consommer (`pending == nil`), sans double traitement.

### Flux frères vérifiés

`grep -n "DeepLinkCenter"` → `AppDelegate.swift`/`DeepLinkRouter.swift` sont des PRODUCTEURS
(`route(...)`/`showError()`) ; `HomeShellView.swift` est le SEUL consommateur (`@StateObject`,
`.pending`, `.consume()`) dans tout le projet — aucun autre site à corriger.

**Fichiers modifiés** : `Sources/TiinverSwift/Navigation/HomeShellView.swift`.

**Résultat CI** : run `32680432322` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — scénario de test réel difficile à provoquer de façon fiable (nécessite
de recevoir un vrai lien profond — notification push ou URL `tiinver://`/`https://tiinver.com/...` —
PENDANT la fenêtre précise du cold start/écran de login, avant authentification, sur un device réel)
; suggéré : déclencher un lien profond juste après le lancement de l'app sur un compte non connecté,
se connecter, confirmer que le lien est bien honoré une fois `HomeShellView` monté plutôt que
silencieusement ignoré.

## 2026-08-24 — Phase B V4 — Lot P1-13 : V4-F-029 (Feed — publication n'envoie jamais le
consentement IA ni les métadonnées enrichies, divergence légale/conformité réelle)

**Commit** : `ec7dd68` — CI **run 32681106944, conclusion: success**.

### Contexte : gap déjà documenté explicitement par un cycle précédent

`FeedRepository.swift`, commentaire de tête de `publish` (cycle V3, V3-F-017, 2026-08-19) :
"`metadata`/`template_id` envoyés vides, `consentAi` envoyé à `"0"`... aucun bascule de consentement
IA n'existe dans `PublishComposeView` actuellement — gap distinct, non construit ici." Ce lot COMBLE
ce gap déjà identifié, retrouvé indépendamment par l'audit V4 (signal de fiabilité fort — 2 cycles
d'audit indépendants arrivent à la même conclusion).

### Vérification Android (avant tout changement)

`editor/PublishFragment.java:544-639` (`getMetadata`/`getImageMetadata`/`getVideoMetadata`, lu en
entier) + `models/MediaMetaData.java` (entier) :
```java
meta.setLanguage(language);           // Locale.getDefault().getLanguage()
meta.setLocale(locale.toString());    // Locale.getDefault().toString()
meta.setCountry(country);             // Locale.getDefault().getCountry()
meta.setWidth(width); meta.setHeight(height);
meta.setConsentAi(consentAi);         // acceptAi.isChecked() — CheckBox RÉELLE, R.id.acceptAi
meta.setLicense(consentAi ? "ai_training_non_exclusive" : "no_ai");
// PHOTO uniquement : meta.setFormat(mimeType)
// VIDÉO uniquement : meta.setFps(...), meta.setDuration(KEY_DURATION/1_000_000f — SECONDES),
//                     meta.setHasAudio(...)
```
`style`/`content_type`/`bitRate` : déclarés dans `MediaMetaData.java` mais AUCUN `setStyle`/
`setContent_type`/`setBitRate` trouvé nulle part dans `PublishFragment.java` (grep exhaustif) —
restent `null`/`0` dans CHAQUE publication Android réelle. `acceptAi` (`fragment_publish.xml:86-92`)
confirmée réelle : `<CheckBox android:text="@string/allow_my_content_for_ai_training" .../>`, libellé
FR exact `"Autoriser l'utilisation de mon contenu pour l'entraînement de l'IA"`.

### Écart iOS constaté (avant correctif)

`FeedRepository.publish` : `"metadata": ""`, `"consentAi": "0"` — littéraux hardcodés, jamais
calculés. `PublishComposeView` : aucun contrôle de consentement IA nulle part dans l'UI — impossible
pour un utilisateur iOS de donner OU refuser explicitement son consentement à l'entraînement IA.

### Correctif appliqué

1. `PublishComposeView` : nouveau `@State private var acceptAiConsent = false` (décoché par défaut,
   fidèle à l'état initial Android) + `Toggle("Autoriser l'utilisation de mon contenu pour
   l'entraînement de l'IA", isOn: $acceptAiConsent)` ajouté juste avant l'action de publication
   (position relative fidèle à `layout_above="@+id/share"`).
2. `PublishComposeView.publish()` (branche vidéo) : extraction `fps`/piste audio ajoutée À CÔTÉ de
   l'extraction width/height/duration déjà existante (même `AVAssetTrack` déjà chargé,
   `nominalFrameRate` = équivalent AVFoundation de `MediaFormat.KEY_FRAME_RATE`).
3. `FeedRepository.MediaMetaData` (nouveau `struct Encodable`) — noms de champs Gson EXACTS
   (`content_type` en snake_case inclus, pas de transformation de clé). Construit dans `publish`,
   sérialisé en JSON via `JSONEncoder`, injecté dans `params["metadata"]`. `consentAi` envoyé comme
   `"1"`/`"0"` selon la valeur réelle du toggle (plus jamais hardcodé).

### Flux frères vérifiés

`grep -n "FeedRepository().publish("` → exactement 2 sites d'appel dans tout le projet (branches
photo et vidéo de `PublishComposeView.publish()`), tous deux mis à jour avec `consentAi:` (et
`videoFps:`/`videoHasAudio:` pour la vidéo).

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedRepository.swift`,
`Sources/TiinverSwift/Feed/PublishComposeView.swift`.

**Résultat CI** : run `32681106944` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : publier une photo ET une vidéo, une fois avec le
toggle activé et une fois désactivé, inspecter le payload réseau `activity/add` (outil d'inspection
réseau) pour confirmer que `consentAi`/`metadata.consentAi`/`metadata.license` reflètent bien l'état
réel du toggle, et que `metadata.fps`/`.hasAudio`/`.duration` sont cohérents pour une vidéo réelle.

## 2026-08-24 — Phase B V4 — Lot P1-14 : V4-F-030 (Feed — like/partage/commentaire ne notifient
jamais l'auteur du post)

**Commit** : `b6e6807` — CI **run 32681817117, conclusion: success**.

### Vérification Android (avant tout changement) — portée réelle affinée

`Activity/ui/MainFragment.java:1140-1198,1200-1238` (lu en entier) :
```java
private void notifyUser(String id){
    TransportData data = new TransportData(requireActivity());
    HashMap<String,String> map = new HashMap<>();
    map.put("userId", id);
    data.Post(map, "push", null);   // fire-and-forget, callback null
}
```
Appelé à 3 endroits, chacun avec un placement PRÉCIS vérifié ligne par ligne :
1. **Like** (ligne 1174) : APRÈS le `if/else` de bascule like/unlike (les deux branches y mènent),
   INCONDITIONNELLEMENT, SANS attendre la réponse de `activityViewModel.reaction(map)`.
2. **Commentaire** (ligne 1190, `OnclickCommentaire`) : IMMÉDIATEMENT après
   `mySheetDialog.show(fm, "modalSheetDialog")` — donc à l'OUVERTURE du panneau, PAS à l'envoi d'un
   commentaire.
3. **Partage** (ligne 1238, `OnclickPrtg`) : DANS le callback de succès (`onResonse`,
   `error.equals("false")`), mais placé APRÈS le `if/else` SHARE/UNSHARE (pas imbriqué dedans) — se
   déclenche sur tout succès réseau, quel que soit le message retourné.

**Portée réelle affinée par rapport au texte d'audit** : `grep notifyUser` sur `ProfileFeedFragment.
java`/`HashtagProfile.java` confirme le MÊME mécanisme câblé (3 sites chacun) ; `FullScreenMedia.
java` (source de `SearchView`/`NotificationsListView`) → **0 résultat**, ce mécanisme n'y est PAS
câblé côté Android non plus.

### Correctif appliqué

1. `FeedRepository.notifyPostAuthor(userId:)` (nouveau) — `POST push {"userId": userId}`.
2. `FeedViewModel` : nouveau `private let notifiesAuthorOnInteraction: Bool` (paramètre d'`init`,
   défaut `false`), `notifyPostAuthorIfNeeded(_:)` (privé, garde le flag + fire-and-forget).
3. `toggleLike` : appel INCONDITIONNEL après le `Task { reaction(...) }`, sans l'attendre.
4. `toggleShare` : appel APRÈS le `if/else` SHARE/UNSHARE, à l'intérieur du `guard let message`
   réussi (donc sur tout succès réseau).
5. `notifyCommentOpened(_:)` (nouveau, public) — appelé par la VUE au moment où elle arme
   `commentsPost`, pas depuis `CommentsView`.
6. Câblage par écran : `FeedView` (`notifiesAuthorOnInteraction: true` à l'instanciation du
   viewModel, propage à la fois à la grille ET au pager puisqu'ils partagent la MÊME instance) ;
   `ProfileView`/`HashtagFeedView`/`HomeShellView` (`notifiesAuthor: true` sur l'init `posts:` de
   `FeedDetailPagerView`) ; `SearchView`/`NotificationsListView` laissés au défaut `false`
   (commentaire explicite ajouté, pas un oubli silencieux).

### Flux frères vérifiés

`grep -n "FeedDetailPagerView(posts:"` → 5 sites externes + 1 usage interne (`FeedView`) déjà
recensés lors du lot V4-F-007 — chacun réévalué individuellement contre sa source Android réelle
(`MainFragment`/`ProfileFeedFragment`/`HashtagProfile`/`FullScreenMedia` ×2), pas une règle générique
appliquée en bloc.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedViewModel.swift`,
`Sources/TiinverSwift/Feed/FeedRepository.swift`, `Sources/TiinverSwift/Feed/FeedView.swift`,
`Sources/TiinverSwift/Profile/ProfileView.swift`, `Sources/TiinverSwift/Discover/HashtagFeedView.swift`,
`Sources/TiinverSwift/Discover/SearchView.swift`,
`Sources/TiinverSwift/Notifications/NotificationsListView.swift`,
`Sources/TiinverSwift/Navigation/HomeShellView.swift`.

**Résultat CI** : run `32681817117` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : depuis un compte, liker/partager/ouvrir les
commentaires d'un post d'un AUTRE compte depuis Feed/Profile/Hashtag, confirmer la réception d'une
notification push sur le second appareil ; répéter depuis Search/Notifications et confirmer l'ABSENCE
de notification (fidèle à Android, pas une régression).

## 2026-08-24 — Phase B V4 — Lot P1-15 : V4-F-056 (Gallery-PhotoEditor — freeform crop ignore l'orientation EXIF)

### Vérification Android

`BitmapLoadingWorkerTask.java:66-79` (`doInBackground`) :
```java
BitmapUtils.BitmapSampled decodeResult =
    BitmapUtils.decodeSampledBitmap(mContext, mUri, mWidth, mHeight);
...
BitmapUtils.RotateBitmapResult rotateResult =
    BitmapUtils.rotateBitmapByExif(decodeResult.bitmap, mContext, mUri);
```
`rotateBitmapByExif` est appelé EN AMONT, avant tout branchement sur le sous-mode de recadrage
(rect/oval/freeform) — c'est le SEUL point de chargement du bitmap pour `CropImageView`, donc les
trois sous-modes reçoivent déjà un bitmap dont les pixels sont physiquement tournés selon l'EXIF.
Second point d'entrée confirmé, `CropImageView.java:981-994` (`setImageBitmap(bitmap, exif)`) :
même fonction `rotateBitmapByExif`, même garantie.

### État iOS avant correctif

`PublishComposeView.swift` (`.freeformCropping` case) :
```swift
if case .photo(let image) = media, let cgImage = image.cgImage {
    FreeformCropStepView(sourceImage: cgImage, path: $freeformPath, ...)
}
```
`image.cgImage` extrait le buffer de pixels BRUT, sans tenir compte de `image.imageOrientation`.
`FreeformCropView.body` (`FreeformCropView.swift:18`) dessine ce buffer via
`context.draw(Image(decorative: sourceImage, scale: 1), in: ...)` — `Image(decorative:)` est
documenté par Apple comme ignorant les métadonnées d'orientation (contrairement à
`Image(uiImage:)`, qui les respecte). Pour une photo prise en mode portrait (EXIF
`.rightMirrored`/`.right`/etc., cas quasi-systématique caméra iPhone), le buffer brut est en
réalité stocké en paysage — la photo apparaît donc de côté ou en miroir pendant le tracé du masque,
ET le résultat composé (`FreeformCropView.croppedImage`, qui opère sur ce même buffer non tourné)
hérite du même défaut.

Le mode rect/oval (`.cropping`, même fichier) passe par `TOCropViewController`
(`PhotoCropView.swift`), une bibliothèque tierce qui respecte nativement `imageOrientation` — seul
le mode freeform était affecté, confirmant exactement la `DIFFÉRENCE` du finding d'audit.

### Correctif appliqué

Nouvelle méthode privée `UIImage.normalizedToUpOrientation()` (`PublishComposeView.swift`, scope
`private extension`, utilisée au seul site concerné) :
```swift
func normalizedToUpOrientation() -> UIImage {
    guard imageOrientation != .up else { return self }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = scale
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        draw(in: CGRect(origin: .zero, size: size))
    }
}
```
`draw(in:)` respecte `imageOrientation` (contrairement à un accès direct à `.cgImage`), donc le
bitmap redessiné a des pixels déjà dans le bon sens — équivalent fonctionnel de
`rotateBitmapByExif`. Appliquée avant l'extraction du `cgImage` passé à `FreeformCropStepView`.
Le résultat découpé (`onValidate`) est reconstruit avec `orientation: .up` (et non
`image.imageOrientation`, comme avant le correctif) puisque la source est désormais déjà
normalisée — réappliquer l'orientation d'origine aurait doublé la rotation.

### Flux frères vérifiés

- `PhotoCropView.swift:54` (mode oval, `croppedImage.cgImage`) : opère sur la SORTIE de
  `TOCropViewController`, dont les pixels sont déjà physiquement tournés (orientation `.up` de
  fait, bibliothèque tierce qui gère l'EXIF en interne) — pas affecté, aucun changement nécessaire.
- `PhotoToolsView.swift` (`flipHorizontal`/`removeBackground`) : propage
  `displayedImage.imageOrientation` d'un bout à l'autre et affiche via `Image(uiImage:)` (pas
  `Image(decorative:)`) — pas affecté.
- `Image(decorative:)` dans le module Animems (`PaintCapture.swift:162`,
  `ShapePreviewEditorPanelView.swift:25`) : opère sur des calques/aperçus de formes générés en
  interne par l'éditeur (jamais une photo EXIF importée par l'utilisateur) — hors périmètre de ce
  finding, `DOMAINE: Gallery-PhotoEditor` uniquement.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/PublishComposeView.swift`.

**Résultat CI** : commit `29385f5`, push confirmé (`c1cb713..29385f5 main -> main`), run
`32682553930` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : publier depuis une photo portrait prise à la
caméra (EXIF non-`.up`), choisir "Freeform", confirmer que le tracé et le rendu final apparaissent
dans le bon sens (pas de côté/en miroir) ; répéter avec une photo paysage et une photo déjà `.up`
pour confirmer l'absence de régression sur les cas déjà corrects.

## 2026-08-24 — Phase B V4 — Lot P1-16 : V4-F-064 (BunnyCDN-Media — upload de pièce jointe chat charge tout le fichier en RAM)

### Vérification Android

`UploadFileOrDataService.java:242-267` (`uploadToBunny`) :
```java
private boolean uploadToBunny(Uri fileUri, String remotePath, String mimeType) throws IOException {
    OkHttpClient client = new OkHttpClient();
    ProgressRequestBodyUri body = new ProgressRequestBodyUri(
        this, fileUri, MediaType.parse(mimeType), progress -> updateView(progress));
    Request request = new Request.Builder()
        .url(remotePath).put(body).addHeader("AccessKey", STORAGE_API_KEY).build();
    try (Response response = client.newCall(request).execute()) {
        return response.isSuccessful();
    }
}
```
`uploadMediaAndThumbnail` (lignes 269-301) est le SEUL appelant, et il dispatch `MyMediaType.
fromKey(data.getObject())` SANS branchement type-spécifique avant l'appel — donc les 4 types de
pièce jointe (photo/vidéo/audio/doc) partagent tous ce même chemin `uploadToBunny`/
`ProgressRequestBodyUri`. `ProgressRequestBodyUri.writeTo` (entier, lu) :
```java
byte[] buffer = new byte[8192];
long uploaded = 0;
try (InputStream in = contentResolver.openInputStream(fileUri)) {
    int read;
    while ((read = in.read(buffer)) != -1) {
        sink.write(buffer, 0, read);
        uploaded += read;
        if (callback != null && contentLength > 0) {
            callback.onProgress((int) ((uploaded * 100) / contentLength));
        }
    }
}
```
Streaming par blocs de 8Ko depuis un `InputStream` ouvert sur l'`Uri` du fichier — jamais de
chargement intégral en mémoire, quelle que soit la taille du fichier, avec progression réelle
calculée à chaque bloc.

### État iOS avant correctif

`ChatMediaUploadService.put` :
```swift
let fileData = try Data(contentsOf: localFile)
let (_, response) = try await URLSession.shared.upload(for: request, from: fileData)
```
`Data(contentsOf:)` charge le fichier ENTIER en mémoire avant même de commencer l'envoi réseau —
pour une vidéo volumineuse en pièce jointe chat, risque réel de pic mémoire significatif et de
terminaison OOM sur un appareil à mémoire limitée. Exactement le même anti-pattern déjà identifié
et corrigé pour l'upload vidéo du Feed principal (`FeedMediaUploader.uploadVideo`, V3-F-019/
BUNNY-03), jamais appliqué au chemin Chat séparé.

### Correctif appliqué

1. `ChatMediaUploadService.put` : remplace `Data(contentsOf:)` +
   `URLSession.shared.upload(for:from:)` par `URLSession.shared.upload(for:fromFile:delegate:)` —
   streaming natif depuis le disque, jamais de matérialisation intégrale en `Data`.
2. `UploadProgressDelegate` (`FeedMediaUploader.swift`) rendue interne (retrait de `private`) et
   réutilisée TELLE QUELLE, plutôt que dupliquée dans `ChatMediaUploadService` — même motif de
   partage déjà appliqué aux constantes de stockage BunnyCDN entre `FeedMediaUploader` et
   `ProfileRepository` (V4-F-008).
3. Nouveau paramètre `progress: (@Sendable (Double) -> Void)? = nil` propagé de `upload(...)` à
   `put(...)`, défaut `nil` — capacité de progression désormais disponible, non branchée à une UI
   dans ce lot : `ChatBubbleViews.swift` affiche déjà un `ProgressView()` indéterminé tant que
   `isFileUploaded != 1` (fidèle à l'écran chat Android, qui n'affiche PAS de barre de pourcentage
   inline — Android route sa progression vers une notification système de service au premier plan,
   fonctionnalité séparée hors périmètre des `IOS FILES` cités par ce finding).

### Flux frères vérifiés

`grep "Data(contentsOf:"` dans tout le projet → tous les autres usages chargent une image locale
déjà en cache pour l'affichage UI (aperçus Animems/Wallet/Feed/Chat), aucun n'est un upload réseau.
`grep "URLSession.shared.upload(for:"` → 2 usages restants sur `from:` (Data en mémoire) :
`FeedMediaUploader.uploadPhoto` et `ProfileRepository.uploadProfilePicture`, tous deux des photos
compressées (webp) — vérifié que le chemin Android correspondant (`uploadImageToBunny`) N'utilise
PAS non plus `ProgressRequestBodyUri` pour les photos (seul `uploadToBunny`, chemin Chat, et
`uploadFileToBunny`, vidéo Feed, streament) — pas affectés, aucun changement nécessaire.

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/ChatMediaUploadService.swift`,
`Sources/TiinverSwift/Feed/FeedMediaUploader.swift`.

**Résultat CI** : commit `1090279`, push confirmé (`ff1c20e..1090279 main -> main`), run
`32683050887` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : envoyer une pièce jointe volumineuse (vidéo) en
chat, confirmer via Instruments/Memory Graph l'absence de pic mémoire correspondant à la taille du
fichier, et la réussite de l'upload (bulle passe à `isFileUploaded == 1`).

## 2026-08-24 — Phase B V4 — Lot P1-17 : V4-F-059 (VideoEditor — sélection de trim sans plafond continu de durée maximale)

### Vérification Android

`ProTimelineView.java:685-713` (`handleMove`, cas `DRAG_LEFT_PX`/`DRAG_RIGHT_PX`) :
```java
case DRAG_LEFT_PX: {
    float newLeft = downSelLeftPx + (x - downX);
    newLeft = Math.max(MARGIN_PX, newLeft);
    newLeft = Math.min(selRightPx - selMinWidthPx, newLeft);
    if (selRightPx - newLeft > selMaxWidthPx)
        newLeft = selRightPx - selMaxWidthPx;
    selLeftPx = newLeft;
    ...
}
case DRAG_RIGHT_PX: {
    float newRight = downSelRightPx + (x - downX);
    newRight = Math.min(w - MARGIN_PX, newRight);
    newRight = Math.max(selLeftPx + selMinWidthPx, newRight);
    if (newRight - selLeftPx > selMaxWidthPx)
        newRight = selLeftPx + selMaxWidthPx;
    selRightPx = newRight;
    ...
}
```
`selMaxWidthPx` (ligne 316, `selMaxWidthPx = (float) maxTrimMs / viewWindowMs * w`) dérive de
`maxTrimMs`, lui-même alimenté par `videotrimmer.setTrimeLimitMax(60000)` (`MediaTrim.java:175`) —
soit 60 secondes. Les DEUX branches de `handleMove` reclampent `selMaxWidthPx` À CHAQUE appel
(donc à chaque pixel de déplacement du doigt, pas seulement au moment du cadrage initial) : si le
nouveau bord dépasserait la largeur maximale, c'est CE bord précis (celui en cours de glissement)
qui est ramené en arrière pour maintenir exactement `selMaxWidthPx` — le geste n'est jamais bloqué
dur, juste recadré en continu.

### État iOS avant correctif

`MediaTrimView.dragGesture` (lignes 188-204) :
```swift
if isStart {
    let maxAllowed = endFraction - Self.minHandleSpacing
    startFraction = min(max(0, startFractionAtDragBegin + delta), max(0, maxAllowed))
} else {
    let minAllowed = startFraction + Self.minHandleSpacing
    endFraction = max(min(1, endFractionAtDragBegin + delta), min(1, minAllowed))
}
```
Seule une borne MINIMALE (`minHandleSpacing`, écart minimal entre les 2 poignées) est appliquée.
`load()` cadre bien la sélection par défaut à `maxDurationSeconds` (60s) si la vidéo source est plus
longue (`endFraction = maxDurationSeconds / seconds`) — mais ce cadrage n'a lieu QU'UNE FOIS, au
chargement. Rien dans `dragGesture` n'empêchait ensuite d'étendre la sélection en glissant une
poignée vers l'extérieur, bien au-delà de 60s.

### Correctif appliqué

Ajout d'un clamp de largeur maximale dans `dragGesture`, appliqué APRÈS le clamp minimal existant
(même ordre qu'Android — largeur min d'abord, puis largeur max) :
```swift
let maxWidthFraction = duration > 0 ? min(1, Self.maxDurationSeconds / duration) : 1
if isStart {
    ... // clamp minimal existant, inchangé
    if endFraction - startFraction > maxWidthFraction {
        startFraction = endFraction - maxWidthFraction
    }
} else {
    ... // clamp minimal existant, inchangé
    if endFraction - startFraction > maxWidthFraction {
        endFraction = startFraction + maxWidthFraction
    }
}
```
Reproduit fidèlement le comportement Android : c'est la poignée EN COURS de déplacement qui est
recadrée à la largeur maximale, pas un blocage dur du geste (le doigt peut continuer à glisser sans
que la vue "saute" ou refuse le geste). Appliqué en continu à chaque callback `onChanged`, comme
`handleMove` côté Android — pas seulement au chargement initial.

### Flux frères vérifiés

`grep "minHandleSpacing\|dragGesture(isStart:"` dans tout le projet → un seul site,
`MediaTrimView.swift` — aucun autre écran (Animems, Stories, autre) ne reproduit ce motif de
poignées de trim avec bornes min/max.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/MediaTrimView.swift`.

**Résultat CI** : commit `0e7f651`, push confirmé (`5088cb0..0e7f651 main -> main`), run
`32683632141` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : charger une vidéo de plus de 60s, glisser chaque
poignée (gauche puis droite) pour tenter d'étendre la sélection au-delà de 60s, confirmer que la
largeur reste plafonnée en continu (pas seulement au chargement initial).

## 2026-08-24 — Phase B V4 — Lot P1-18 : V4-F-068 (Wallet-Monetization — WithdrawView ne rafraîchit jamais le solde serveur avant un retrait)

### Vérification Android

`WithdrawActivity.java:221` (`onCreate`) :
```java
getRealAmount();
setupSpinners();
submitButton.setOnClickListener(v -> { ... });
```
`getRealAmount()` est appelé INCONDITIONNELLEMENT, avant même que `submitButton` ne soit câblé.
`getRealAmount()` (lignes 415-448, entier) :
```java
public void getRealAmount(){
    TransportData data = new TransportData(this);
    data.get("getuserbyid/" + myId, new Callback() {
        public void onResonse(Context context, int action, JSONObject object) {
            ...
            if (error.equals("false")) {
                String users = "[" + object.getString("userData") + "]";
                User[] metas = gson.fromJson(users, User[].class);
                for (User meta : metas) {
                    currentBalance = meta.getCoinsAmount();
                    ...
                    availablePieces.setText(...);
                }
            }
        }
    });
}
```
`currentBalance` est un CHAMP D'INSTANCE (pas une variable locale) — écrasé par la réponse serveur,
puis réutilisé PLUS LOIN dans le même fichier, à la fois pour la validation (ligne 249,
`if (requestedAmount < currentBalance)`) ET comme valeur envoyée telle quelle au serveur dans le
payload de la demande de retrait (ligne 272,
`submitWithdrawalRequest(myId, currentBalance, requestedAmount, calculatedMoney, ...)`). Appel
asynchrone fire-and-forget — ne bloque pas l'interactivité du formulaire, mais garantit que
`currentBalance` reflète le solde serveur dès que la requête revient (quasi immédiatement après
l'ouverture de l'écran).

### État iOS avant correctif

`WalletRepository.refreshBalance(userId:)` (port fidèle de `getRealAmount`) existait déjà mais
`grep refreshBalance` dans tout le projet ne remontait QUE sa propre définition — zéro appelant.
`WithdrawView(coinsAmount: viewModel.coinsAmount)` (`WalletView.swift:29`) recevait le solde en
cache local (`WalletViewModel`/`UserSession.shared.coinsAmount`) à l'instanciation, et l'utilisait
tel quel partout dans `submit()` (validation solde insuffisant, valeur `currentBalance:` envoyée
aux 2 méthodes de soumission) — jamais rafraîchi depuis le serveur, potentiellement obsolète (dérive
multi-session, ou conséquence directe du bug V4-F-065 déjà corrigé dans ce cycle).

### Correctif appliqué

1. Nouveau `@State private var currentBalance: Double`, initialisé depuis `coinsAmount` via un
   `init(coinsAmount:)` explicite (désormais requis, `@State` ne peut pas être alimenté par l'init
   memberwise implicite).
2. `.task { await refreshBalance() }` ajouté au montage de la vue — NON BLOQUANT pour le formulaire
   (le geste peut être rempli/soumis pendant que la requête est en vol), fidèle au caractère
   fire-and-forget de `getRealAmount()`.
3. `refreshBalance()` (nouvelle méthode privée) appelle `WalletRepository.shared.refreshBalance
   (userId:)` et met à jour `currentBalance` sur succès ; conserve la valeur précédente sur échec
   (`try?`), fidèle au callback `onError` Android qui ne fait rien.
4. TOUS les usages internes basculés de `coinsAmount` vers `currentBalance` : affichage ("Solde
   disponible"), validation (`requestedAmount < currentBalance`), et paramètre `currentBalance:`
   envoyé aux 2 méthodes de soumission (`submitWithdrawalRequest`/`submitWithdrawalByCrypto`).

### Flux frères vérifiés

Vérification PAR LECTURE DIRECTE du code Android (pas une supposition) : `grep
"getRealAmount\|getuserbyid"` dans `TransfertCoinsActivity.java` ET `ConversionActivity.java` → 0
résultat dans LES DEUX fichiers — Android lui-même ne rafraîchit PAS le solde serveur pour les écrans
Transfert/Conversion, seul Retrait (le cash-out réel, zone d'audit conformité App Store 3.1.5
explicitement signalée en tête de `WithdrawActivity.java`) le fait. `TransferCoinsView.swift`/
`ConversionView.swift` (qui lisent `UserSession.shared.coinsAmount` directement) laissés
INCHANGÉS — fidèles à leur source Android respective, PAS un oubli.

**Fichiers modifiés** : `Sources/TiinverSwift/Wallet/WithdrawView.swift`.

**Résultat CI** : commit `4e6c2f1`, push confirmé (`5a9904e..4e6c2f1 main -> main`), run
`32684195949` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : modifier le solde serveur depuis un autre
appareil/session pendant que l'écran Retrait est ouvert, confirmer que le solde affiché ET utilisé
pour la validation/soumission se met à jour sans bloquer visuellement le formulaire.

## 2026-08-24 — Phase B V4 — Lot P1-19 : V4-F-073 (Performance-Memory — CDNAsyncImage décode chaque image CDN à pleine résolution)

### Vérification Android

`ChargerImages.java` (lu en entier) — CHAQUE chargeur Glide sous-échantillonne dès la source :
```java
public static void displayThumbail(Context context, String uri, ImageView imageView){
    RequestOptions requestOptions = new RequestOptions();
    requestOptions.frame(10000);
    requestOptions.override(200);
    ...
}
public static void glid(Context mContext, String model, ImageView view){
    Glide.with(mContext).asBitmap().load(model).fitCenter().override(400).into(view);
}
public static void glidLoadImageRequireAuth(Context mContext, GlideUrl model, ImageView view, int width, int height){
    Glide.with(mContext).asBitmap().load(model)
        .encodeFormat(Bitmap.CompressFormat.WEBP).encodeQuality(100)
        .override(width, height).fitCenter().into(view);
}
```
`glidLoadImageRequireAuth` (avec `LazyHeaders`/`Referer`, donc l'équivalent Android DIRECT de
`CDNAsyncImage`, seul chargeur avec le même header) prend `width`/`height` en PARAMÈTRES — chaque
site d'appel Android fournit sa propre taille d'affichage réelle, pas une constante globale. Les
autres chargeurs (`displayThumbail`/`glid`) utilisent des constantes fixes (200/400px) pour des
usages plus génériques.

### État iOS avant correctif

`CDNAsyncImage.load()` : `UIImage(data: data)` sur les octets bruts téléchargés, sans AUCUNE option
`ImageIO`/`CGImageSource` de miniature — chaque image, quelle que soit sa taille d'affichage finale
(un avatar à 32×32pt inclus), décodait à sa résolution CDN complète. `grep CDNAsyncImage(`
recompté au moment de ce lot : **25 occurrences dans 16 fichiers** (le texte d'audit en citait 18 —
écart expliqué par la croissance du projet entre la Phase A de l'audit et ce lot, notamment les
lots V4-F-007/V4-F-030 de ce même cycle qui ont étendu `FeedDetailPagerView` et ajouté des
call sites) — les 25 occurrences ACTUELLES ont toutes été traitées, pas seulement les 18 d'origine.

### Correctif appliqué

1. `CDNAsyncImage` : nouveau paramètre `targetSize: CGSize?` (points, `nil` par défaut) sur les 2
   signatures d'`init` ; nouvelle méthode statique `decode(_:targetSize:scale:)` qui utilise
   `CGImageSourceCreateThumbnailAtIndex` (`kCGImageSourceCreateThumbnailFromImageAlways` — force le
   sous-échantillonnage même si l'image contient déjà une miniature embarquée EXIF potentiellement
   trop petite/grande — `kCGImageSourceThumbnailMaxPixelSize` dérivé de `max(targetSize.width,
   targetSize.height) * displayScale`, `ImageIO` respecte le ratio d'origine —
   `kCGImageSourceCreateThumbnailWithTransform` applique l'orientation EXIF —
   `kCGImageSourceShouldCacheImmediately` décode immédiatement plutôt que paresseusement) quand
   `targetSize` est fourni ; repli sur l'ancien `UIImage(data:)` pleine résolution sinon
   (comportement STRICTEMENT inchangé pour tout appel qui ne passerait pas encore `targetSize`).
2. Les 25 sites d'appel migrés, chacun avec la taille réelle de son contexte d'affichage :
   - Avatars à taille fixe (`.frame(width:height:)` voisin) : 32pt (`CommentsView`,
     `GroupCreationView`), 36pt (`GroupDetailView` membre, `FeedView` fullscreen overlay), 40pt
     (`SearchView` compte), 44pt (`NotificationsListView` ×2, `FollowListView`, `ChatSearchView`,
     `ContactPickerView` ×2, `BoostDashboardView`, `CreatorOfWeekView` rang), 50pt
     (`RosterListView`), 56pt (`GroupDetailView` groupe), 64pt (`SuggestionsCarouselView`), 72pt
     (`CreatorOfWeekView` star), 84pt (`ProfileView` avatar), 160pt (`BoostDetailView`, borné par
     `.frame(height: 160)`).
   - Bulles média chat (`ChatBubbleViews`, photo + vidéo) : 220pt, fidèle à leur
     `.frame(maxWidth: 220, maxHeight: 220)` commun.
   - Grilles sans `.frame` fixe sur `CDNAsyncImage` elle-même — taille de colonne dérivée du nombre
     de colonnes RÉELLEMENT déclaré dans chaque grille : `FeedGridCell` (2 colonnes, partagée par
     `FeedView`/`HashtagFeedView` — corrigée une seule fois, couvre les deux écrans),
     `ProfileView.postCell`/`SearchView.postGridCell` (3 colonnes chacune) →
     `UIScreen.main.bounds.width / N`.
   - 2 arrière-plans plein écran (`FeedView`, viewer fullscreen — pas de borne plus petite
     disponible pour une image affichée en plein écran) → `UIScreen.main.bounds.size` — toujours un
     gain mémoire réel vs. la résolution CDN source, généralement bien supérieure à l'écran.

### Flux frères vérifiés

`grep "AsyncImage("` (SwiftUI natif, pas `CDNAsyncImage`) → un seul autre site, `AIChatView.swift`
— images générées par l'IA, hors CDN Tiinver, contexte totalement différent (pas de header
`Referer`, pas le même backend) — hors périmètre de ce finding, non touché.

**Fichiers modifiés** : `Sources/TiinverSwift/Media/CDNAsyncImage.swift` (mécanisme) +
`Sources/TiinverSwift/Boost/BoostDashboardView.swift`, `BoostDetailView.swift`,
`Sources/TiinverSwift/Creators/CreatorOfWeekView.swift`,
`Sources/TiinverSwift/Discover/CommentsView.swift`, `FollowListView.swift`, `SearchView.swift`,
`Sources/TiinverSwift/Feed/FeedView.swift`, `SuggestionsCarouselView.swift`,
`Sources/TiinverSwift/Messagerie/ChatBubbleViews.swift`, `ChatSearchView.swift`,
`ContactPickerView.swift`, `GroupCreationView.swift`, `GroupDetailView.swift`,
`RosterListView.swift`, `Sources/TiinverSwift/Notifications/NotificationsListView.swift`,
`Sources/TiinverSwift/Profile/ProfileView.swift` (16 fichiers d'appel + 1 fichier de mécanisme).

**Résultat CI** : commit `63039ff`, push confirmé (`cf542ca..63039ff main -> main`), run
`32685087464` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel IMPÉRATIF, changement le plus risqué visuellement de tout
ce cycle P1 (17 fichiers, 25 sites d'appel) : confirmer sur chacun des 16 écrans touchés que les
images restent nettes à leur taille d'affichage (pas de flou perceptible dû à un `targetSize` trop
petit ni de recadrage inattendu), et profiler Feed/grilles à défilement rapide via
Instruments/Memory Graph pour confirmer la baisse de pic mémoire attendue.

## 2026-08-24 — Phase B V4 — Lot P1-20 : V4-F-021 (Groups / Social — motifs de signalement affichés depuis Profile ne correspondent pas à la vraie liste Android)

### Vérification Android

`strings.xml:516-525` (`report_setting_array`, entier) :
```xml
<string-array name="report_setting_array">
    <item>Nudity</item>
    <item>Violence</item>
    <item>Harassment</item>
    <item>False Information</item>
    <item>Unauthorised_sales</item>
    <item>Hate speech</item>
    <item>Terrorisme</item>
    <item>Under 13 years old</item>
</string-array>
```
`report/Report.java:67` : `list = getResources().getStringArray(R.array.report_setting_array);` —
UNE SEULE liste, utilisée identiquement quel que soit le type de cible signalée (utilisateur ou
groupe, `Report.java` gère les deux avec la même Activity et la même ressource).

### État iOS avant correctif

`ReportView.reasons` : `["Spam", "Contenu inapproprié", "Harcèlement", "Usurpation d'identité",
"Fausses informations", "Autre"]` — liste RECONSTRUITE (le commentaire de tête l'admettait
explicitement : "PAS lus... à faire valider/ajuster"), ne correspondant à AUCUN sous-ensemble de la
vraie liste Android : "Spam"/"Autre" n'existent pas côté Android, et Nudité/Vente non
autorisée/Discours de haine/Moins de 13 ans manquaient entièrement. `ReportView` est le SEUL point
d'entrée réel du signalement depuis Profile (`grep ReportView(` confirmé). Or la BONNE liste à 8
items existait déjà, mot pour mot, ailleurs dans le MÊME projet iOS :
`FeedView.swift:24-27` (`feedReportReasons`, `private`) :
```swift
private let feedReportReasons = [
    "Nudité", "Violence", "Harcèlement", "Fausse information",
    "Vente non autorisée", "Discours de haine", "Terrorisme", "Moins de 13 ans",
]
```
Déjà utilisée par le menu "..." du Feed (un flux de signalement Android SÉPARÉ —
`MainFragment.OnclickMoreExpand`/`ProfileFeedFragment`+`FullScreenMedia`+
`HashtagProfile.OnclickMoreExpand` — mais qui lit la MÊME ressource `report_setting_array`) —
jamais réutilisée pour `ReportView`.

### Correctif appliqué

1. `feedReportReasons` (`FeedView.swift`) rendue interne (retrait de `private`) — même motif de
   partage de constante que `UploadProgressDelegate` (V4-F-064) plutôt que dupliquer une 2ᵉ liste.
2. `ReportView.reasons` (la liste divergente) supprimée ; `List(reasons, id: \.self)` remplacé par
   `List(feedReportReasons, id: \.self)`.
3. Aucun branchement `reportType`-spécifique ajouté — confirmé par lecture directe de `Report.java`
   que la même ressource Android sert aux deux types ("user" et "group").

### Flux frères vérifiés

`grep "report_setting_array\|Contenu inapproprié\|Fausses informations"` dans tout le projet iOS →
plus aucune liste divergente après le correctif (les seules occurrences restantes sont les
commentaires documentant ce correctif lui-même).

**Fichiers modifiés** : `Sources/TiinverSwift/Discover/ReportView.swift`,
`Sources/TiinverSwift/Feed/FeedView.swift`.

**Résultat CI** : commit `4ff545b`, push confirmé (`c3812dd..4ff545b main -> main`), run
`32685665777` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : signaler un profil ET un groupe depuis
`ReportView`, confirmer que les 8 motifs affichés correspondent exactement à
`report_setting_array`, et que le `message` envoyé au backend (`POST report`) reflète le motif
choisi.
