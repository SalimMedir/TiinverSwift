import Foundation

/// Port de `models/wallet/Transaction.java` (169 lignes, lu en entier) — une ligne d'historique
/// (achat, retrait, conversion), `type` distingue `"purchaserequests"`/`"withdrawalrequests"` (voir
/// `WalletView.manageTransaction`, port de `WalletActivity.manageTransaction`).
struct WalletTransaction: Codable, Identifiable, Equatable {
    var id: Int = 0
    var userId: Int = 0
    var transactionId: String?
    var requestedBalance: Double = 0
    var requestedAmount: Double = 0
    var calculatedMoney: Double = 0
    var quantity: Int = 0
    var price: Int = 0
    var currency: String?
    var operatorName: String?
    var operatorTransactionId: String?
    var country: String?
    var phoneNumber: String?
    var status: String?
    var createAt: String?
    var type: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, transactionId, requestedBalance, requestedAmount, calculatedMoney, quantity, price, currency
        case operatorName = "operator"
        case operatorTransactionId, country, phoneNumber, status, createAt, type
    }
}

/// Port de `models/wallet/Operator.java` — un moyen de paiement/retrait "manuel" (mobile money ou
/// crypto), utilisé UNIQUEMENT par le retrait/transfert (`WithdrawView`) — PAS par l'achat, qui
/// passe désormais par StoreKit 2 (voir avertissement de tête de `CoinStoreManager.swift` et la
/// section "Audit conformité App Store" de MIGRATION_PROGRESS.md).
struct PaymentOperator: Identifiable, Hashable {
    let id: String
    let name: String
    /// Numéro mobile money OU adresse de portefeuille crypto à créditer manuellement.
    let destination: String
    let isCrypto: Bool

    /// Port des listes câblées en dur dans `WithdrawActivity.setupSpinners`/`PurchaseActivity.
    /// setupSpinners` (adresses/numéros identiques dans les deux fichiers Android, recopiés tels
    /// quels — PAS de source de vérité centralisée côté Android non plus).
    static func forCurrentZone() -> [PaymentOperator] {
        var list: [PaymentOperator] = []
        if TiinverConfig.zone == .cemac {
            list.append(PaymentOperator(id: "Orange-Money", name: "Orange Money", destination: "658777060", isCrypto: false))
            list.append(PaymentOperator(id: "Airtel-Money", name: "Airtel Money", destination: "63961330", isCrypto: false))
        }
        list.append(
            PaymentOperator(
                id: "Crypto", name: "Crypto (USDC)", destination: "0xe11c9c06329Be948DAabE4691C811f756B1A2109", isCrypto: true))
        return list
    }
}

/// Port des paliers câblés en dur dans `SelectAmountActivity.setupOffers` (250/500/1250/2500/5000).
/// **Réutilisés comme identifiants de `Product` StoreKit 2** (`com.tiinver.ios.coins.<quantity>`,
/// voir `CoinStoreManager.swift`) plutôt que comme un prix calculé côté client — le prix réel est
/// désormais fixé dans App Store Connect (territoires/devises Apple), PAS par la formule Android
/// `quantity × pieceValue × (1+frais%)`, incompatible avec le modèle de tarification StoreKit.
enum CoinTier {
    static let quantities = [250, 500, 1250, 2500, 5000]

    static func productID(forQuantity quantity: Int) -> String {
        "com.tiinver.ios.coins.\(quantity)"
    }
}
