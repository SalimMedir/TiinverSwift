import SwiftUI

/// Port de `EarnCoinsActivity.java` (400 lignes, lu en entier) — récompense en pièces (ou gemmes,
/// selon `FirebaseConfigManager.adsRewardAsGems`) après visionnage d'une publicité "rewarded".
///
/// **Le SDK Google Mobile Ads (chargement/affichage de `RewardedAd`) N'EST PAS câblé ici** — hors
/// périmètre de ce fichier par construction, differé au module 16 (AdMob), qui vérifiera l'API iOS
/// réelle (`GADRewardedAd`) avant d'implémenter `AdRewardProvider` ci-dessous. `onRewardEarned` est
/// le point d'ancrage exact où le module 16 devra brancher le callback `userDidEarnReward` du SDK.
/// Le minuteur de 10s avant affichage du bouton "voir la pub" (`CountDownTimer`/`createTimer`,
/// simple pacing UX sans logique métier) N'EST PAS reproduit — décoratif, retiré pour ne pas
/// bloquer artificiellement l'écran tant que le vrai SDK n'est pas branché.
protocol AdRewardProvider {
    /// Retourne le montant gagné, ou `nil` si l'utilisateur a fermé la pub sans la terminer.
    func showRewardedAd() async -> Double?
}

/// Implémentation temporaire tant que le module 16 (AdMob) n'a pas câblé le vrai SDK — permet de
/// tester l'écran/le crédit de récompense sans dépendance externe.
struct PlaceholderAdRewardProvider: AdRewardProvider {
    func showRewardedAd() async -> Double? { nil }
}

struct EarnCoinsView: View {
    var adProvider: AdRewardProvider = PlaceholderAdRewardProvider()
    @State private var isShowingAd = false
    @State private var lastReward: Double?

    private let config = TiinverFirebaseConfigManager.shared

    var body: some View {
        VStack(spacing: 16) {
            AdBannerView(adUnitID: AdMobIdentifiers.resolvedBanner(AdMobIdentifiers.bannerWallet))
                .frame(height: 50)

            Text("\(UserSession.shared.coinsAmount, specifier: "%.0f") pièces") // R.string.coins
                .font(.title.bold())
            Button {
                Task { await watchAd() }
            } label: {
                Label("Regarder une publicité", systemImage: "play.rectangle.fill") // R.id.show_video_button
            }
            .buttonStyle(.borderedProminent)
            .disabled(isShowingAd)
            if let lastReward {
                Text("+\(lastReward, specifier: "%.0f")").foregroundStyle(.green)
            }
        }
        .padding()
        .navigationTitle("Gagner des pièces")
    }

    /// Port de `showRewardedVideo`/`OnUserEarnedRewardListener.onUserEarnedReward` → `addCoins`/
    /// `updateToServer`/`updateGemsToServer` (`EarnCoinsActivity.java:227-238,342-396`, relu en
    /// entier pour ce correctif) — crédit local optimiste (`coinCount += coins`, persisté et
    /// affiché immédiatement, INCONDITIONNELLEMENT), puis rapport serveur séparé.
    ///
    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-092 SILENT-03, P1)** — deux bugs
    /// distincts trouvés en retraçant `updateToServer`/`updateGemsToServer` ligne par ligne, pas
    /// seulement celui décrit dans le finding original :
    /// 1. (Bug décrit dans le finding) `pendingCoinsAmount`/`pendingGemsAmount` étaient bien écrits
    ///    en cas d'échec réseau, mais JAMAIS relus nulle part — un gain perdu au premier échec
    ///    restait perdu pour toujours, contrairement à Android qui les relit à `onCreate`
    ///    (`pendingCoinCount = Settings.getIntegerPreference(...)`, ligne 121) et les réinjecte à
    ///    CHAQUE appel suivant de `updateToServer`.
    /// 2. **Bug plus grave, non décrit dans le finding original, découvert en traçant la valeur
    ///    RÉELLEMENT envoyée au serveur** : `updateToServer(totalAmoun, currenGainCoins)` calcule
    ///    `currentAmouont = pendingCoinCount + currenGainCoins` — le champ `"coins"` envoyé à
    ///    `rewardedCoins` est un DELTA (ce gain + le solde en attente), PAS le solde total du
    ///    compte (`totalAmoun`, qui lui n'est utilisé QUE pour la mise à jour locale optimiste,
    ///    ligne 352/382). La version précédente de cette fonction envoyait `newTotal` (le solde
    ///    COMPLET du compte après crédit local) dans ce même champ `"coins"` — si le serveur traite
    ///    ce champ comme un delta à ADDITIONNER au solde serveur existant (cohérent avec le nom de
    ///    l'endpoint et avec le calcul Android), chaque publicité regardée aurait fait
    ///    ~DOUBLER le solde réel côté serveur au lieu de l'incrémenter du montant réellement gagné.
    private func onRewardEarned(_ rewardAmount: Double) async {
        let divided = rewardAmount / max(config.rewardDividedBy, 1)
        lastReward = divided
        guard let userId = UserSession.shared.myId else { return }
        if config.adsRewardAsGems {
            UserSession.shared.gemsAmount += divided
            let amountToReport = Double(UserSession.shared.pendingGemsAmount) + divided
            do {
                try await WalletRepository.shared.creditReward(userId: userId, totalAmount: amountToReport, type: "gems")
                UserSession.shared.pendingGemsAmount = 0
            } catch {
                UserSession.shared.pendingGemsAmount += Int(divided)
            }
        } else {
            UserSession.shared.coinsAmount += divided
            let amountToReport = Double(UserSession.shared.pendingCoinsAmount) + divided
            do {
                try await WalletRepository.shared.creditReward(userId: userId, totalAmount: amountToReport, type: "coins")
                UserSession.shared.pendingCoinsAmount = 0
            } catch {
                UserSession.shared.pendingCoinsAmount += Int(divided)
            }
        }
    }

    private func watchAd() async {
        isShowingAd = true
        defer { isShowingAd = false }
        if let reward = await adProvider.showRewardedAd() {
            await onRewardEarned(reward)
        }
    }
}
