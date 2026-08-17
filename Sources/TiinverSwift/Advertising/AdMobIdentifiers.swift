import Foundation

/// Port des identifiants d'unité publicitaire AdMob — recopiés directement depuis
/// `res/values/strings.xml` (valeurs `translatable="false"`, donc identiques quelle que soit la
/// langue) et `TIINVER_IOS_PORT_ANALYSIS.md` §5 (IDs bannière, codés en dur dans les layouts XML
/// Android, pas dans `strings.xml`). App ID vérifié dans `AndroidManifest.xml:419`.
///
/// **Même compte AdMob que l'Android** (confirmé, pas une supposition — un compte AdMob héberge
/// les unités des deux plateformes d'une même app) : ces identifiants NUMÉRIQUES sont réutilisables
/// tels quels, SEUL le préfixe `ca-app-pub-2461482190230201` reste inchangé entre les deux OS.
enum AdMobIdentifiers {
    static let applicationID = "ca-app-pub-2461482190230201~9045103625"

    /// Port de `activity_conversion.xml`/`activity_earn_coin.xml`/`activity_retrait.xml`/
    /// `activity_transfert_coins.xml`/`wallet_header_item.xml` (module 15, Wallet) —
    /// même ID bannière recopié dans TOUS ces layouts (analyse §5.1). **Aussi réutilisé par
    /// `feed_header_layout.xml`'s `<AdView>`** (en-tête du fil d'accueil, `ActivityAdapter.
    /// HeaderViewHolder.adView`, trouvé le 2026-08-17 en portant `FeedView.homeHeader`) — même ID
    /// numérique, pas un troisième identifiant distinct.
    static let bannerWallet = "ca-app-pub-2461482190230201/5840810574"
    /// Port de `activity_monegtization.xml`/`activity_referral.xml`, seul écran à utiliser un
    /// second ID bannière distinct (`ads_layout.xml`, analyse §5.1) — PAS unifié avec
    /// `bannerWallet`, fidèle à la distinction réelle des deux IDs Android.
    static let bannerSecondary = "ca-app-pub-2461482190230201/4225372854"

    /// Port de `R.string.MyAdMobId` — utilisé pour les native ads (`AdLoader`), PAS pour une
    /// bannière malgré le nom générique (vérifié à l'usage réel dans `ReferralActivity.
    /// nativeAds`/`EarnCoinsActivity.nativeAds`).
    static let nativeAd = "ca-app-pub-2461482190230201/8041328930"

    /// Port de `R.string.MyAdMobRewardedId` — `EarnCoinsActivity` (module 15).
    static let rewarded = "ca-app-pub-2461482190230201/8526593058"
    /// Port de `R.string.MyAdMobRewardedIdOnFeed` — mini-jeu `FeedFragment`/`MainFragment`
    /// (module 6, Feed vidéo, DÉJÀ FERMÉ — voir avertissement dans le tableau détaillé : ce point
    /// d'intégration N'A PAS été rétro-ajouté au module 6, câblage différé).
    static let rewardedOnFeed = "ca-app-pub-2461482190230201/2662741569"
    /// Port de `R.string.MyAdMobInterstitielsRewardeadsId` — `WithdrawActivity`/
    /// `TransfertCoinsActivity`/`ConversionActivity` (module 15).
    static let rewardedInterstitial = "ca-app-pub-2461482190230201/4493540390"

    /// Port de `R.string.TestAdMobId` — ID de test Google standard (`ca-app-pub-3940256099942544/…`
    /// sur iOS, PAS le même numéro que l'ID de test Android, confirmé par la documentation publique
    /// des identifiants de test Google, distincts par plateforme) : utilisé en `DEBUG` pour ne
    /// jamais servir de vraies annonces pendant le développement.
    static let testBanner = "ca-app-pub-3940256099942544/2435281174"
    static let testRewarded = "ca-app-pub-3940256099942544/1712485313"
    static let testRewardedInterstitial = "ca-app-pub-3940256099942544/6978759866"
    static let testNative = "ca-app-pub-3940256099942544/3986624511"

    static func resolvedBanner(_ real: String) -> String {
        #if DEBUG
            return testBanner
        #else
            return real
        #endif
    }
    static func resolvedRewarded(_ real: String) -> String {
        #if DEBUG
            return testRewarded
        #else
            return real
        #endif
    }
    static func resolvedRewardedInterstitial(_ real: String) -> String {
        #if DEBUG
            return testRewardedInterstitial
        #else
            return real
        #endif
    }
    static func resolvedNative(_ real: String) -> String {
        #if DEBUG
            return testNative
        #else
            return real
        #endif
    }
}
