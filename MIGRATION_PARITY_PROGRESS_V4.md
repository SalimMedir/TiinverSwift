# MIGRATION PARITY PROGRESS V4

Journal de correction du cycle d'audit V4 (`MIGRATION_PARITY_AUDIT_V4.md`).

**État actuel (2026-08-23) : Phase A (Audit) TERMINÉE, Phase B PAS démarrée.**

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

**Commit** : *(à renseigner après ce commit)*.

**Résultat CI** : à déclencher.

**Statut honnête après correction** : `BUILD_VALIDATED` jusqu'à confirmation CI, PUIS seulement
(pas `COMPLETE_PARITY_VALIDATED` même après CI verte — test réel requis) : regarder la pub
rewarded-interstitial après un retrait/transfert/conversion réussi sur un compte réel, confirmer via
un outil d'inspection réseau que le champ `"coins"` envoyé à `rewardedCoins` correspond bien au gain
de LA publicité (pas au solde total affiché), et confirmer que le solde serveur (rechargé depuis
`getuserbyid`) augmente du montant attendu et non d'un montant absurdement plus élevé.
