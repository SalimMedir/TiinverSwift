import SwiftUI

/// Port de `ConversionActivity.java` (251 lignes, lu en entier) — conversion pièces → gemmes à un
/// taux fixe ×3 (`grossAmount = requestedAmount * 3`, valeur câblée en dur côté Android, pas une
/// valeur de configuration distante — reproduite telle quelle).
struct ConversionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var isSubmitting = false
    @State private var resultMessage: String?
    @State private var succeeded = false
    @StateObject private var rewardedInterstitial = RewardedInterstitialAdManager()

    private var coinsAmount: Double { UserSession.shared.coinsAmount }
    private var requestedAmount: Double { Double(amountText) ?? 0 }
    private var gems: Double { requestedAmount * 3 }

    var body: some View {
        Form {
            Section {
                AdBannerView(adUnitID: AdMobIdentifiers.resolvedBanner(AdMobIdentifiers.bannerWallet))
                    .frame(height: 50)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                TextField("Quantité de pièces à convertir", text: $amountText)
                    .keyboardType(.numberPad)
                Text("\(gems, specifier: "%.0f") gemmes") // R.string.gems
                    .foregroundStyle(.secondary)
            }
            if let resultMessage {
                Text(resultMessage).font(.caption)
            }
            Section {
                Button("Convertir") { convert() } // R.id.convert
                    .disabled(isSubmitting || requestedAmount <= 0)
            }
        }
        .navigationTitle("Convertir en gemmes")
    }

    private func convert() {
        guard let userId = UserSession.shared.myId else { return }
        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            do {
                try await WalletRepository.shared.convert(userId: userId, currentBalance: coinsAmount, requestedAmount: requestedAmount, gems: gems)
                resultMessage = "Envoyé avec succès" // R.string.submited_successfully
                succeeded = true
                await showRewardedInterstitialAfterSuccess()
            } catch {
                resultMessage = "Oups, une erreur est survenue" // R.string.oops2
            }
        }
    }

    /// Port de `showRewardedVideoAfter`/`showRewardedVideo` (`ConversionActivity`).
    private func showRewardedInterstitialAfterSuccess() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let reward = await rewardedInterstitial.showRewardedAd() else { return }
        UserSession.shared.coinsAmount += reward
        guard let userId = UserSession.shared.myId else { return }
        try? await WalletRepository.shared.creditReward(userId: userId, totalAmount: UserSession.shared.coinsAmount, type: "coins")
    }
}
