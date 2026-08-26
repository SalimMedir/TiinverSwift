import Foundation

/// Port de `wallet/WalletViewModel.java` + `WalletActivity.java` (229 lignes, lu en entier) —
/// orchestration de l'écran principal du portefeuille : solde, historique paginé, navigation vers
/// les sous-écrans (achat/retrait/transfert/conversion/parrainage).
@MainActor
final class WalletViewModel: ObservableObject {
    @Published var transactions: [WalletTransaction] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository = WalletRepository.shared
    private let limit = 10
    private var offset = 0
    private var reachedEnd = false

    var coinsAmount: Double { UserSession.shared.coinsAmount }
    var gemsAmount: Double { UserSession.shared.gemsAmount }

    /// Port de `WalletActivity.onCreate` (calcul du total affiché) — `pieceValue` sélectionné selon
    /// la zone, comme partout ailleurs dans ce module.
    var totalValueLabel: String {
        let pieceValue = TiinverConfig.zone == .cemac ? TiinverFirebaseConfigManager.shared.coinsValue : TiinverFirebaseConfigManager.shared.coinsValueInDollar
        let total = (coinsAmount * pieceValue * 100).rounded() / 100
        return "\(total) \(TiinverConfig.currency)"
    }

    /// Port de `loadInitialData`/`executeBackTask`.
    func loadInitial() async {
        offset = 0
        reachedEnd = false
        transactions = []
        await loadMore()
    }

    /// Port de `loadMoreData`/`onScrolled` (pagination infinie de `WalletActivity`).
    func loadMore() async {
        guard !isLoading, !reachedEnd, let userId = UserSession.shared.myId else { return }
        isLoading = true
        // V5-F-063 (Phase B P1-26) — effacé au début de CHAQUE tentative (pas seulement en cas de
        // succès) : `errorMessage` est maintenant réellement consommé par `WalletView` (bandeau +
        // bouton "Réessayer"), un ancien message ne doit pas persister après une reprise réussie.
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await repository.transactions(userId: userId, limit: limit, offset: offset)
            if page.isEmpty {
                reachedEnd = true
            } else {
                transactions.append(contentsOf: page)
                offset += limit
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Port de `WalletActivity.manageTransaction` — libellé lisible pour le détail d'une
    /// transaction, dispatché par `type` (les deux SEULS types vus dans l'historique, vérifié).
    func detail(for transaction: WalletTransaction) -> (title: String, message: String)? {
        switch transaction.type {
        case "withdrawalrequests":
            let message = [
                "Retrait via : \(transaction.operatorName ?? "")", // R.string.withdrawal_via
                "Pays : \(transaction.country ?? "")", // R.string.country
                "Solde actuel : \(coinsAmount)", // R.string.Current_balance
                "Montant demandé : \(transaction.requestedAmount) coins", // R.string.Amount_requested
                "Montant calculé : \(transaction.calculatedMoney) \(transaction.currency ?? "")", // R.string.Money_calculated
                "Destinataire : \(transaction.phoneNumber ?? "")",
                "Statut : \(transaction.status ?? "")", // R.string.status
            ].joined(separator: "\n")
            return ("Statut de la demande de retrait", message) // R.string.status_of_withdrawal_request
        case "purchaserequests":
            let message = [
                "Paiement via : \(transaction.operatorName ?? "")",
                "Pays : \(transaction.country ?? "")",
                "Quantité : \(transaction.requestedAmount)",
                "Prix total : \(transaction.calculatedMoney) \(transaction.currency ?? "")",
                "ID transaction : \(transaction.operatorTransactionId ?? "")",
                "Statut : \(transaction.status ?? "")",
            ].joined(separator: "\n")
            return ("Statut de la commande", message) // R.string.order_status
        default:
            return nil
        }
    }
}
