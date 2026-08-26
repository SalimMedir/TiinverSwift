import SwiftUI

/// Port de `TransfertCoinsActivity.java` (331 lignes, lu en entier) — transfert P2P de pièces entre
/// utilisateurs Tiinver (PAS d'argent réel — juste la monnaie virtuelle interne), via recherche du
/// destinataire par téléphone/email (`isPhoneOrEmailExiste`) puis `transfert` (endpoint, faute
/// d'orthographe française réelle côté serveur, préservée).
struct TransferCoinsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var recipientInput = ""
    @State private var foundUser: User?
    @State private var lookupFailed = false
    @State private var amountText = ""
    @State private var isSubmitting = false
    @State private var resultMessage: String?
    @StateObject private var rewardedInterstitial = RewardedInterstitialAdManager()

    private var coinsAmount: Double { UserSession.shared.coinsAmount }

    var body: some View {
        Form {
            Section {
                AdBannerView(adUnitID: AdMobIdentifiers.resolvedBanner(AdMobIdentifiers.bannerWallet))
                    .frame(height: 50)
                    .listRowInsets(EdgeInsets())
            }
            Section("Destinataire") {
                TextField("Téléphone ou email", text: $recipientInput)
                    .onChange(of: recipientInput) { _ in lookup() }
                if let foundUser {
                    Label("\(foundUser.firstname ?? "") \(foundUser.lastname ?? "")", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if lookupFailed {
                    Label("Utilisateur introuvable", systemImage: "exclamationmark.triangle.fill") // R.drawable.ic_error_red_24dp
                        .foregroundStyle(.red)
                }
            }
            Section {
                TextField("Quantité de pièces", text: $amountText)
                    .keyboardType(.numberPad)
                Text("Solde disponible : \(coinsAmount, specifier: "%.0f")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let resultMessage {
                Text(resultMessage).font(.caption)
            }
            Section {
                Button("Transférer") { transfer() } // R.id.transfert
                    .disabled(foundUser == nil || isSubmitting || !isValidAmount)
            }
        }
        .navigationTitle("Transférer des pièces")
    }

    private var isValidAmount: Bool {
        guard let amount = Double(amountText) else { return false }
        return amount > 0 && amount < coinsAmount
    }

    /// Port de `add_user.addTextChangedListener` — relance la recherche à chaque frappe (fidèle à
    /// l'original, PAS de debounce ajouté : Android n'en a pas non plus).
    private func lookup() {
        foundUser = nil
        lookupFailed = false
        guard !recipientInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            do {
                if let user = try await WalletRepository.shared.findUser(phoneOrEmail: recipientInput) {
                    foundUser = user
                } else {
                    lookupFailed = true
                }
            } catch {
                lookupFailed = true
            }
        }
    }

    /// **`isSubmitting` positionné SYNCHRONEMENT ici le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md
    /// V5-F-097, Phase B P1, financier)** — avant ce correctif, `isSubmitting = true` n'était fixé
    /// qu'À L'INTÉRIEUR de la closure `Task` (tour de boucle suivant, PAS synchrone dans le handler
    /// de tap), et aucun `guard !isSubmitting` n'existait du tout. Port fidèle de
    /// `TransfertCoinsActivity.java:115-140` : `transfert.setVisibility(View.GONE)` exécuté
    /// SYNCHRONEMENT dans `onClick`, AVANT l'appel réseau — un second tap immédiat ne peut plus
    /// atteindre le bouton (`GONE`). Un double-tap rapide (avant le premier repaint SwiftUI)
    /// pouvait démarrer DEUX `Task` exécutant chacune `transferCoins` en parallèle avant qu'aucune
    /// n'ait eu la chance de positionner `isSubmitting` → double débit réel de pièces.
    private func transfer() {
        guard !isSubmitting else { return }
        guard let foundUser, let myId = UserSession.shared.myId, let amount = Int(amountText) else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await WalletRepository.shared.transferCoins(senderId: myId, receiverId: String(foundUser.id ?? 0), quantity: amount)
                UserSession.shared.coinsAmount = coinsAmount - Double(amount)
                if let recipientId = foundUser.id {
                    try? await WalletRepository.shared.notifyTransferReceived(userId: String(recipientId))
                }
                resultMessage = "Vous avez transféré \(amount) pièces à \(foundUser.firstname ?? "")" // R.string.succefull_transfery_message
                await showRewardedInterstitialAfterSuccess()
            } catch {
                resultMessage = "Une erreur est survenue" // R.string.message_error
            }
        }
    }

    /// Port de `showRewardedVideoAfter`/`showRewardedVideo` (`TransfertCoinsActivity`).
    ///
    /// **Corrigé (V4-F-065, P0)** — même bug que `WithdrawView`/`ConversionView` : le champ
    /// `"coins"` envoyé à `rewardedCoins` doit être un DELTA (`pendingCoinCount + currenGainCoins`,
    /// `wallet/WalletRepository.java:301-328`), pas le solde total du compte. Voir `WithdrawView.
    /// showRewardedInterstitialAfterSuccess` pour la preuve Android complète.
    private func showRewardedInterstitialAfterSuccess() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let reward = await rewardedInterstitial.showRewardedAd() else { return }
        UserSession.shared.coinsAmount += reward
        guard let userId = UserSession.shared.myId else { return }
        let amountToReport = Double(UserSession.shared.pendingCoinsAmount) + reward
        do {
            try await WalletRepository.shared.creditReward(userId: userId, totalAmount: amountToReport, type: "coins")
            UserSession.shared.pendingCoinsAmount = 0
        } catch {
            UserSession.shared.pendingCoinsAmount += Int(reward)
        }
    }
}
