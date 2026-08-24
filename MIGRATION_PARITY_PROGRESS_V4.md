# MIGRATION PARITY PROGRESS V4

Journal de correction du cycle d'audit V4 (`MIGRATION_PARITY_AUDIT_V4.md`).

**État actuel (2026-08-23) : Phase A (Audit) TERMINÉE. Phase B EN COURS — backlog P0 épuisé
(P0-1..P0-4 clos). Liste P1 : V4-F-020, V4-F-032, V4-F-033, V4-F-042, V4-F-038, V4-F-017, V4-F-046,
V4-F-048 clos. Prochain : V4-F-049 (Animems keyframe delete — même rigueur requise).**

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
