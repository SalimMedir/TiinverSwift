import StoreKit

/// Développement NOUVEAU (module 15) — REMPLACE le flux d'achat réel Android (`SelectAmountActivity`
/// → `PurchaseActivity` → `WalletRepository.submitPurchasseRequest`/`submitPurchasseByCrypto`), qui
/// fait payer l'utilisateur HORS APPLICATION (transfert mobile money/crypto manuel vers un numéro/
/// une adresse affichée à l'écran) puis lui fait SAISIR À LA MAIN l'identifiant de la transaction
/// comme preuve de paiement, vérifiée ensuite côté serveur. **Ce mécanisme, reproduit tel quel sur
/// iOS, constituerait une violation quasi certaine des règles App Store 3.1.1 (contournement d'achat
/// intégré pour un bien numérique/une monnaie virtuelle) ET 3.1.5 (cash-out apps)** — voir la
/// section "Audit conformité App Store — Wallet/Paiements" de MIGRATION_PROGRESS.md pour l'analyse
/// complète, écrite pour cette session précisément parce que la découverte (le fichier UNIQUE que
/// l'analyse de faisabilité initiale visait comme "à porter vers StoreKit 2", `BuyCoinsActivity.
/// java`, est en réalité DU CODE MORT — absent d'`AndroidManifest.xml`, entièrement commenté dans
/// le fichier source lui-même) change matériellement l'évaluation du risque par rapport à ce que le
/// rapport de faisabilité initial supposait.
///
/// **API StoreKit 2 vérifiée avant écriture, PAS devinée** : signatures de `Product.PurchaseResult`
/// (`.success(VerificationResult<Transaction>)`/`.pending`/`.userCancelled`) et `VerificationResult`
/// (`.verified(Transaction)`/`.unverified(Transaction, VerificationResult.VerificationError)`)
/// confirmées en lisant le code source réel de `RevenueCat/purchases-ios`
/// (`Sources/Purchasing/StoreKit2/StoreKit2TransactionListener.swift`, bibliothèque de paiement
/// tierce très largement utilisée en production, choisie comme référence faute de rendu JS
/// exploitable sur `developer.apple.com` — même contrainte que pour CallKit/PushKit aux modules 12).
@MainActor
final class CoinStoreManager: ObservableObject {
    static let shared = CoinStoreManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await listenForTransactionUpdates() }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// À appeler à l'affichage de l'écran d'achat (voir `BuyCoinsView`) — port de
    /// `SelectAmountActivity.setupOffers` (paliers 250/500/1250/2500/5000), les IDs `Product`
    /// correspondants doivent être créés dans App Store Connect comme achats CONSOMMABLES.
    func loadProducts() async {
        let ids = CoinTier.quantities.map(CoinTier.productID(forQuantity:))
        products = (try? await Product.products(for: ids))?.sorted { $0.price < $1.price } ?? []
    }

    /// Port du point d'entrée `buyButton.setOnClickListener`/`luncheProduct` — lance l'achat
    /// StoreKit 2, crédite le solde local de façon optimiste sur succès (même motif que
    /// `WithdrawActivity.addCoins`/`EarnCoinsActivity.addCoins` : mise à jour locale immédiate,
    /// re-synchronisée par le serveur ensuite).
    func purchase(_ product: Product, quantity: Int) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await creditAndReport(transaction: transaction, quantity: quantity)
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                lastError = "Achat en attente d'approbation (contrôle parental ou autre)." // R.string équivalent non identifié
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Port de `PurchasesUpdatedListener`/`Transaction.updates` — rattrape les transactions
    /// conclues hors de l'appel `purchase()` direct (ex. achat approuvé après un contrôle parental
    /// différé, cas `.pending` ci-dessus). Signature vérifiée (`for await result in
    /// Transaction.updates`) contre `StoreKit2TransactionListener.swift` (voir avertissement de
    /// tête de fichier).
    private func listenForTransactionUpdates() async {
        for await result in StoreKit.Transaction.updates {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            let quantity = Int(CoinTier.quantities.first { CoinTier.productID(forQuantity: $0) == transaction.productID } ?? 0)
            await creditAndReport(transaction: transaction, quantity: quantity)
            await transaction.finish()
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw JSONError.typeMismatch("StoreKit VerificationResult")
        case .verified(let value): return value
        }
    }

    /// Port de `addCoins`/`updateToServer` (mise à jour optimiste locale) — **le rapport au
    /// serveur utilise un endpoint QUI N'EXISTE PAS ENCORE côté backend** (`storekit/verify-purchase`,
    /// PAS `purchaserequests`, qui attend un payload mobile money/crypto incompatible). Voir la
    /// section "Backend à implémenter" de MIGRATION_PROGRESS.md — tant que ce point serveur n'est
    /// pas fait, le crédit reste local uniquement (comme `pendingCoinsAmount` pour les récompenses
    /// pub, même mécanisme de repli en cas d'échec réseau).
    private func creditAndReport(transaction: StoreKit.Transaction, quantity: Int) async {
        let newBalance = UserSession.shared.coinsAmount + Double(quantity)
        UserSession.shared.coinsAmount = newBalance
        guard let userId = UserSession.shared.myId else { return }
        let params: [String: String] = [
            "userId": userId, "quantity": String(quantity), "productId": transaction.productID,
            "transactionId": String(transaction.id), "originalTransactionId": String(transaction.originalID),
        ]
        _ = try? await APIClient.shared.post(params, endpoint: "storekit/verify-purchase")
    }
}
