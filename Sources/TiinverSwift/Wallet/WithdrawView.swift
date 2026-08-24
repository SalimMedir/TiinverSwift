import SwiftUI

/// Port de `WithdrawActivity.java` (566 lignes, lu en entier) — retrait de pièces converties en
/// argent réel (mobile money ou crypto USDC selon la zone). **Zone d'audit conformité prioritaire**
/// (guideline App Store 3.1.5, cash-out) — voir MIGRATION_PROGRESS.md, section dédiée. Porté
/// FIDÈLEMENT (formulaire, calcul de frais, seuil minimum, confirmation) sur demande explicite,
/// contrairement à l'écran d'achat (`BuyCoinsView`, remplacé par StoreKit 2).
struct WithdrawView: View {
    /// Valeur initiale (cache local, `WalletViewModel.coinsAmount`) — affichée immédiatement au
    /// montage, puis remplacée par `currentBalance` dès que le solde serveur est connu.
    let coinsAmount: Double
    @Environment(\.dismiss) private var dismiss

    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-068, Phase B P1)** — port de
    /// `getRealAmount()` (`WithdrawActivity.java:221,415-448`), appelé INCONDITIONNELLEMENT dans
    /// `onCreate` avant même que `submitButton` ne soit câblé. `currentBalance` (champ Android)
    /// démarre avec la valeur transmise par l'écran précédent (ici, le paramètre `coinsAmount`),
    /// PUIS est écrasé par la réponse serveur — c'est CETTE MÊME variable qui sert ensuite à la
    /// validation (`requestedAmount < currentBalance`) ET qui est envoyée telle quelle au serveur
    /// dans le payload de la demande de retrait (`submitWithdrawalRequest(myId, currentBalance,
    /// ...)`). Reproduit à l'identique : rafraîchissement lancé au montage (`.task`, non bloquant
    /// pour le formulaire, fidèle au caractère asynchrone fire-and-forget de `getRealAmount`), et
    /// c'est `currentBalance` (pas `coinsAmount`) qui est utilisé partout dans `submit()`.
    @State private var currentBalance: Double

    @State private var operators = PaymentOperator.forCurrentZone()
    @State private var selectedOperator: PaymentOperator = PaymentOperator.forCurrentZone().first!
    @State private var countries = WalletCountry.forCurrentZone
    @State private var selectedCountry: WalletCountry = WalletCountry.forCurrentZone.first!
    @State private var destination = ""
    @State private var requestedAmountText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    @StateObject private var rewardedInterstitial = RewardedInterstitialAdManager()
    private let config = TiinverFirebaseConfigManager.shared

    init(coinsAmount: Double) {
        self.coinsAmount = coinsAmount
        _currentBalance = State(initialValue: coinsAmount)
    }

    private var pieceValue: Double { selectedOperator.isCrypto ? config.coinsValueInDollar : config.coinsValue }
    private var currency: String { selectedOperator.isCrypto ? "USDC" : "FCFA" }
    private var requestedAmount: Double { Double(requestedAmountText) ?? 0 }
    private var calculatedMoney: Double {
        let gross = requestedAmount * pieceValue
        let fee = gross * config.transactionFeePercent / 100
        return ((gross - fee) * 100).rounded() / 100
    }

    var body: some View {
        Form {
            Section {
                AdBannerView(adUnitID: AdMobIdentifiers.resolvedBanner(AdMobIdentifiers.bannerWallet))
                    .frame(height: 50)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Text("Solde disponible : \(currentBalance, specifier: "%.0f")") // R.string.quantity_available
            }
            Section("Moyen de retrait") { // R.string.withdrawal_via (utilisé comme libellé de section ici)
                Picker("Opérateur", selection: $selectedOperator) {
                    ForEach(operators) { op in Text(op.name).tag(op) }
                }
                if !selectedOperator.isCrypto {
                    Picker("Pays", selection: $selectedCountry) { // R.string.country
                        ForEach(countries) { country in Text(country.name).tag(country) }
                    }
                }
                TextField(
                    selectedOperator.isCrypto ? "Adresse de portefeuille crypto" : "Numéro de téléphone", // R.string.enter_your_crypto_wallet_address / your_number_to_receive_the_money
                    text: $destination
                )
                .keyboardType(selectedOperator.isCrypto ? .default : .phonePad)
            }
            Section {
                TextField("Quantité de pièces à retirer", text: $requestedAmountText) // R.string equivalent non identifié
                    .keyboardType(.numberPad)
                Text("Montant à recevoir : \(calculatedMoney, specifier: "%.2f") \(currency) (\(config.transactionFeePercent, specifier: "%.0f")% de frais)")
                    .font(.caption).foregroundStyle(.secondary) // R.string.amount_to_be_received / fees
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
            Section {
                Button("Envoyer la demande de retrait") { submit() } // R.id.sendWithdrawRequestButton
                    .disabled(isSubmitting)
            }
        }
        .navigationTitle("Retrait") // R.string.status_of_withdrawal_request (titre d'écran non identifié précisément)
        // Port de `tutoriel_withdraw`/`TransactionTutorialActivity` — voir `TransactionTutorialView
        // .swift`, 2026-08-18 P2.
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { TransactionTutorialView() } label: { Image(systemName: "questionmark.circle") }
            }
        }
        .alert("Retrait envoyé", isPresented: $didSubmit) {
            Button("OK") { dismiss() }
        }
        .task { await refreshBalance() }
    }

    /// Port de `getRealAmount()` — appelé au montage, sans bloquer le formulaire (fidèle au
    /// caractère fire-and-forget de l'appel Android, câblé dans `onCreate` avant même que
    /// `submitButton` ne soit prêt à être tapé).
    private func refreshBalance() async {
        guard let userId = UserSession.shared.myId else { return }
        currentBalance = (try? await WalletRepository.shared.refreshBalance(userId: userId)) ?? currentBalance
    }

    /// Port de `submitButton.setOnClickListener` — validations dans le MÊME ordre que l'original
    /// (téléphone/adresse vide → montant nul → seuil minimum → solde insuffisant → confirmation).
    private func submit() {
        errorMessage = nil
        guard !destination.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Merci de remplir tous les champs" // R.string.please_fill_in_all_fields
            return
        }
        guard requestedAmount > 0 else {
            errorMessage = "Merci de remplir tous les champs"
            return
        }
        guard requestedAmount >= config.minimumWithdrawalAmount else {
            errorMessage = "Le montant minimum de retrait n'est pas atteint" // R.string.the_minimum_withdrawal_amount
            return
        }
        guard requestedAmount < currentBalance else {
            errorMessage = "Solde insuffisant" // R.string.Insufficient_balance_msg
            return
        }
        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            guard let userId = UserSession.shared.myId else { return }
            let fullDestination = selectedOperator.isCrypto ? destination.trimmingCharacters(in: .whitespaces) : selectedCountry.phoneCode + destination.trimmingCharacters(in: .whitespaces)
            do {
                if selectedOperator.isCrypto {
                    try await WalletRepository.shared.submitWithdrawalByCrypto(
                        userId: userId, currentBalance: currentBalance, requestedAmount: requestedAmount, calculatedMoney: calculatedMoney,
                        operatorName: selectedOperator.name, country: selectedCountry.name, destAddress: fullDestination, currency: currency)
                } else {
                    try await WalletRepository.shared.submitWithdrawalRequest(
                        userId: userId, currentBalance: currentBalance, requestedAmount: requestedAmount, calculatedMoney: calculatedMoney,
                        operatorName: selectedOperator.name, country: selectedCountry.name, phoneNumber: fullDestination, currency: currency)
                }
                didSubmit = true
                await showRewardedInterstitialAfterSuccess()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Port de `showRewardedVideoAfter`/`showRewardedVideo` — délai de 500ms fidèle à l'original
    /// (pas justifié par un commentaire Android non plus, conservé par fidélité).
    ///
    /// **Corrigé (V4-F-065, P0)** — `WithdrawActivity.addCoins`/`WalletRepository.updateToServer`
    /// (`wallet/WithdrawActivity.java:558-563`, `wallet/WalletRepository.java:301-328`, relus en
    /// entier) : `coinCount += coins` est un crédit local INCONDITIONNEL (affichage optimiste), mais
    /// le champ `"coins"` réellement envoyé à `rewardedCoins` est calculé séparément par
    /// `updateToServer` comme `pendingCoinCount + currenGainCoins` — un DELTA (ce gain + tout gain
    /// en attente d'un échec précédent), JAMAIS le solde total du compte. Sur succès,
    /// `PENDING_COINS_AMOUNT` est remis à 0 ; sur échec, le gain est ajouté à
    /// `PENDING_COINS_AMOUNT` pour être réessayé au prochain crédit. L'ancienne version de cette
    /// fonction envoyait `UserSession.shared.coinsAmount` (le solde TOTAL du compte après crédit
    /// local) dans ce même champ `"coins"` — si le serveur traite ce champ comme un delta à
    /// additionner (cohérent avec le nom de l'endpoint et le calcul Android), chaque publicité
    /// regardée après un retrait aurait doublé le solde réel côté serveur. Même motif de correction
    /// déjà établi dans `EarnCoinsView.onRewardEarned` (V3-F-092) — reproduit ici à l'identique.
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
