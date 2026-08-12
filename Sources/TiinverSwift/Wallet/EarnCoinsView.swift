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

    /// Port de `showRewardedVideo`/`OnUserEarnedRewardListener.onUserEarnedReward` — crédit local
    /// optimiste, puis rapport serveur (`rewardedCoins`, `type` selon `adsRewardAsGems`), avec repli
    /// `pendingCoinsAmount`/`pendingGemsAmount` en cas d'échec réseau (fidèle à
    /// `updateToServer`/`updateGemsToServer`, `catch` implicite via `try?`).
    private func onRewardEarned(_ rewardAmount: Double) async {
        let divided = rewardAmount / max(config.rewardDividedBy, 1)
        lastReward = divided
        guard let userId = UserSession.shared.myId else { return }
        if config.adsRewardAsGems {
            let newTotal = UserSession.shared.gemsAmount + divided
            UserSession.shared.gemsAmount = newTotal
            do {
                try await WalletRepository.shared.creditReward(userId: userId, totalAmount: newTotal, type: "gems")
                UserSession.shared.pendingGemsAmount = 0
            } catch {
                UserSession.shared.pendingGemsAmount += Int(divided)
            }
        } else {
            let newTotal = UserSession.shared.coinsAmount + divided
            UserSession.shared.coinsAmount = newTotal
            do {
                try await WalletRepository.shared.creditReward(userId: userId, totalAmount: newTotal, type: "coins")
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
