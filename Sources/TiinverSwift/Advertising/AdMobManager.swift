import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI

/// Port du module 16 (AdMob) — API Google Mobile Ads SDK iOS vérifiée AVANT écriture (pas devinée)
/// contre l'exemple officiel Google **SwiftUI** `googleads/googleads-mobile-ios-examples`
/// (`Swift/advanced/SwiftUIDemo/`, dépôt public), la même contrainte que pour CallKit/PushKit/
/// StoreKit 2 aux modules 12/15 (Apple/Google ne rendent pas leur documentation JS exploitable via
/// récupération directe) : noms de types SANS préfixe `GAD*` (`BannerView`/`RewardedAd`/
/// `RewardedInterstitialAd`/`NativeAd`/`AdLoader`/`Request`/`FullScreenContentDelegate`), API
/// moderne `async throws` pour le chargement des formats plein écran — nomenclature introduite en
/// SDK 12.0.0 ("Updated Swift API names to follow the naming conventions from Apple's Swift API
/// Design Guidelines", notes de version Google), PAS disponible en 11.x. **Bug Checkpoint 3 trouvé
/// et corrigé ici** : `project.yml` déclarait encore `from: 11.0.0` (résolution SPM bornée à la
/// branche 11.x par la sémantique `upToNextMajor`, jamais ces types) — corrigé à `from: 13.0.0`,
/// aligné sur le `minimumVersion = 13.0.0` réel du `project.pbxproj` de l'exemple officiel
/// `SwiftUIDemo`. Les anciens noms `GADRewardedAd` etc. restent valides comme alias
/// Objective-C, mais ne sont plus ce que l'exemple officiel Swift actuel utilise.
///
/// **Interstitiel classique (`InterstitialAd`, PAS `RewardedInterstitialAd`) CONFIRMÉ NON UTILISÉ**
/// — l'incertitude signalée par TIINVER_IOS_PORT_ANALYSIS.md §5.2 ("à vérifier en lecture directe
/// avant portage") est levée : grep exhaustif sur les 3 fichiers wallet qui importent
/// `InterstitialAd` (`WithdrawActivity`/`TransfertCoinsActivity`/`ConversionActivity`, tous lus en
/// entier au module 15) montre que SEUL `RewardedInterstitialAd.load(` est réellement appelé —
/// l'import `InterstitialAd` est mort dans les 3 fichiers. Aucun wrapper dédié écrit ici.
@MainActor
func configureAdMob() {
    MobileAds.shared.start(completionHandler: nil)
}

/// Port de la conformité App Tracking Transparency (AUCUN équivalent Android — Google Play n'a pas
/// cette exigence, seul l'App Store la requiert depuis iOS 14.5) — **trouvé manquant par l'audit du
/// 2026-08-16 (GAP-018)** : `NSUserTrackingUsageDescription` était déjà déclarée dans `project.yml`,
/// mais `ATTrackingManager.requestTrackingAuthorization` n'était appelé nulle part, donc le prompt
/// système n'apparaissait jamais et l'app utilisait potentiellement l'IDFA pour la publicité
/// personnalisée AdMob sans consentement recueilli — un motif de rejet direct à la revue App Store
/// (guideline 5.1.2). Appelé depuis `AppDelegate.applicationDidBecomeActive`, PAS `didFinishLaunching`
/// (la fenêtre n'est pas encore key à ce stade, le prompt système risquerait de ne pas s'afficher —
/// pratique documentée dans les guides d'intégration ATT officiels). Ne montre une UI QUE si le
/// statut est `.notDetermined` (comportement natif de l'API) — sûr à appeler plusieurs fois, mais
/// gardé par un drapeau pour n'émettre l'appel qu'une seule fois par lancement d'app.
@MainActor
private var hasRequestedTrackingAuthorization = false

@MainActor
func requestTrackingAuthorizationIfNeeded() {
    guard !hasRequestedTrackingAuthorization else { return }
    hasRequestedTrackingAuthorization = true
    ATTrackingManager.requestTrackingAuthorization { _ in }
}

@MainActor
private func topViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController
}

// MARK: - Bannière (port de `GADBannerView`/`AdView`, 11 écrans, analyse §5.1)

/// Port du motif `BannerViewContainer` de l'exemple officiel SwiftUI Google — `UIViewRepresentable`
/// autour de `BannerView`.
struct AdBannerView: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}

// MARK: - Rewarded (port de `GADRewardedAd`, `EarnCoinsActivity`, analyse §5.3)

/// Conforme à `AdRewardProvider` (module 15, `Wallet/EarnCoinsView.swift`) — point d'ancrage exact
/// posé à cette session-là, câblé ici maintenant que le SDK est vérifié/disponible.
@MainActor
final class RewardedAdManager: ObservableObject, AdRewardProvider {
    private let adUnitID: String
    private var ad: RewardedAd?

    init(adUnitID: String = AdMobIdentifiers.resolvedRewarded(AdMobIdentifiers.rewarded)) {
        self.adUnitID = adUnitID
        Task { await preload() }
    }

    private func preload() async {
        ad = try? await RewardedAd.load(with: adUnitID, request: Request())
    }

    /// Port de `loadRewardedAd`/`showRewardedVideo`/`OnUserEarnedRewardListener.
    /// onUserEarnedReward` — présente l'annonce déjà préchargée (ou tente un chargement synchrone
    /// de repli si le préchargement n'a pas encore abouti), retourne le montant de la récompense.
    func showRewardedAd() async -> Double? {
        if ad == nil { await preload() }
        guard let presentedAd = ad else { return nil }
        ad = nil
        let rewardAmount: Double = await withCheckedContinuation { continuation in
            presentedAd.present(from: topViewController()) {
                continuation.resume(returning: presentedAd.adReward.amount.doubleValue)
            }
        }
        Task { await preload() } // recharge pour la prochaine présentation
        return rewardAmount
    }
}

// MARK: - Rewarded Interstitial (port de `GADRewardedInterstitialAd`, `WithdrawActivity`/
// `TransfertCoinsActivity`/`ConversionActivity`, analyse §5.4)

/// Port de `loadRewardedInterstitialAd`/`showRewardedVideoAfter` — motif IDENTIQUE dans les 3
/// écrans wallet (copié-collé côté Android, vérifié) : affiché ~500ms après le succès d'une
/// opération (retrait/transfert/conversion), la récompense s'ajoute au solde en plus de
/// l'opération elle-même.
@MainActor
final class RewardedInterstitialAdManager: ObservableObject, AdRewardProvider {
    private let adUnitID: String
    private var ad: RewardedInterstitialAd?

    init(adUnitID: String = AdMobIdentifiers.resolvedRewardedInterstitial(AdMobIdentifiers.rewardedInterstitial)) {
        self.adUnitID = adUnitID
        Task { await preload() }
    }

    private func preload() async {
        ad = try? await RewardedInterstitialAd.load(with: adUnitID, request: Request())
    }

    func showRewardedAd() async -> Double? {
        if ad == nil { await preload() }
        guard let presentedAd = ad else { return nil }
        ad = nil
        let rewardAmount: Double = await withCheckedContinuation { continuation in
            presentedAd.present(from: topViewController()) {
                continuation.resume(returning: presentedAd.adReward.amount.doubleValue)
            }
        }
        Task { await preload() }
        return rewardAmount
    }
}

// MARK: - Native (port de `Activity/service/NativeAdsManager.java`/`ads/TemplateView.java`,
// analyse §5.5 — pool de préchargement + rendu custom, feed uniquement)

/// Port PARTIEL de `NativeAdsManager.java` (233 lignes) : charge UNE annonce native à la fois par
/// slot plutôt que le pool de 8 préchargées avec retry/cooldown NO_FILL d'Android
/// (`TemplateView`/`SmallTemplateView`, équivalent Google Native Templates non maintenu au même
/// niveau côté iOS, confirmé par l'analyse §5.5) — rendu manuel `NativeAdContentView` ci-dessous
/// plutôt qu'un composant prêt à l'emploi. **Câblé dans le feed le 2026-08-16** (`FeedDetailPagerView`
/// dans `FeedView.swift`, une instance par position d'annonce, chargée à l'apparition de la page).
@MainActor
final class NativeAdLoader: NSObject, ObservableObject {
    /// Port de `NativeAdsManager.ADS_ON_FEED_POST` — câblé dans `FeedDetailPagerView`
    /// (`FeedView.swift`, 2026-08-16) : une position d'annonce remplace le post à cette position
    /// plutôt que d'insérer une page en plus, fidèle à `ViewPagerAdapter.isAdPosition`/`getItemCount`
    /// (`list.size()+1`, PAS `+adCount`) côté Android — vérifié en lisant `ViewPagerAdapter.java` en
    /// entier.
    static let adsOnFeedPost = 7

    @Published private(set) var nativeAd: NativeAd?

    private var loader: AdLoader?
    private let adUnitID: String

    init(adUnitID: String = AdMobIdentifiers.resolvedNative(AdMobIdentifiers.nativeAd)) {
        self.adUnitID = adUnitID
    }

    func load() {
        guard loader == nil, nativeAd == nil else { return }
        let loader = AdLoader(adUnitID: adUnitID, rootViewController: topViewController(), adTypes: [.native], options: nil)
        loader.delegate = self
        self.loader = loader
        loader.load(Request())
    }
}

extension NativeAdLoader: NativeAdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in self.nativeAd = nativeAd }
    }

    /// Port du cas d'échec de `NativeAdsManager.loadOneAd`/`AdListener.onAdFailedToLoad` — SEUL le
    /// journal d'erreur (`Log.e(TAG, "Ad failed: ...")`) est repris ici, fidèlement à la portée déjà
    /// réduite documentée en tête de fichier (chargement d'UNE annonce à la fois, pas le pool de 8
    /// avec retry/cooldown NO_FILL d'Android — cette logique de pool n'a pas d'équivalent dans ce
    /// portage partiel, donc rien de plus à porter ici que le log).
    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) {
        print("❌ NativeAdLoader (AdMob) échec de chargement :", error)
    }
}

/// Port minimal de `TemplateView.java`/`SmallTemplateView.java` — rendu custom d'une native ad,
/// PAS un composant Google Native Templates (non maintenu côté iOS au même niveau, voir
/// avertissement de tête de fichier) : titre/corps/icône/bouton d'action seulement, pas le rendu
/// complet (medias/étoiles/prix) que `TemplateView` gère côté Android.
struct NativeAdContentView: View {
    let nativeAd: NativeAd

    var body: some View {
        HStack(spacing: 8) {
            if let icon = nativeAd.icon?.image {
                Image(uiImage: icon).resizable().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(nativeAd.headline ?? "").font(.subheadline).bold()
                if let body = nativeAd.body { Text(body).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if let callToAction = nativeAd.callToAction {
                Text(callToAction).font(.caption.bold()).padding(6).background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
