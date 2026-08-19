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
    ///
    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-084 PAY-03, Phase B P0-7)** —
    /// `transaction.finish()` n'est plus appelé QUE si `creditAndReport` confirme que le serveur a
    /// réellement enregistré le crédit. Voir le commentaire de tête de `creditAndReport` pour le
    /// détail complet du risque financier et de ce que ce correctif change (et ne change PAS —
    /// `storekit/verify-purchase` reste un endpoint backend manquant, non simulé ici).
    func purchase(_ product: Product, quantity: Int) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                let confirmed = await creditAndReport(transaction: transaction, quantity: quantity)
                if confirmed {
                    await transaction.finish()
                } else {
                    lastError =
                        "Achat effectué mais non confirmé par le serveur — la transaction sera "
                        + "re-proposée automatiquement au prochain lancement de l'application."
                }
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
    /// différé, cas `.pending` ci-dessus), ET (depuis le correctif P0-7 ci-dessus) les transactions
    /// laissées SCIEMMENT non-`finish()`ées parce que `creditAndReport` n'avait pas pu confirmer le
    /// crédit côté serveur — StoreKit redélivre automatiquement toute transaction non terminée à
    /// chaque lancement de l'app via ce même flux `Transaction.updates`, ce qui donne un vrai point
    /// de nouvelle tentative une fois l'endpoint serveur disponible, au lieu d'une perte silencieuse
    /// et définitive. Signature vérifiée (`for await result in Transaction.updates`) contre
    /// `StoreKit2TransactionListener.swift` (voir avertissement de tête de fichier).
    private func listenForTransactionUpdates() async {
        for await result in StoreKit.Transaction.updates {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            let quantity = Int(CoinTier.quantities.first { CoinTier.productID(forQuantity: $0) == transaction.productID } ?? 0)
            let confirmed = await creditAndReport(transaction: transaction, quantity: quantity)
            if confirmed {
                await transaction.finish()
            }
            // Sinon : transaction laissée non terminée délibérément, voir commentaire ci-dessus.
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
    ///
    /// **P0-7 (2026-08-19) — ce qui a été investigué, vérifié et NON simulé** : `WalletRepository.
    /// submitPurchasseRequest`/`submitPurchasseByCrypto` (Android) attendent un payload mobile
    /// money/crypto incompatible avec une preuve d'achat StoreKit (pas de transactionId Apple, pas
    /// de receipt) — réutiliser ces endpoints tels quels serait un mensonge fonctionnel, PAS une
    /// vraie vérification serveur. Aucun endpoint backend existant n'accepte une preuve d'achat
    /// StoreKit ; en créer un côté client (ex. appeler un endpoint générique de crédit sans preuve
    /// vérifiable) reviendrait à fabriquer une validation serveur inexistante, explicitement interdit.
    /// **Ce correctif NE CRÉE DONC AUCUN nouveau chemin réseau** — il corrige uniquement le cycle de
    /// vie StoreKit local : avant, `transaction.finish()` était appelé inconditionnellement même
    /// quand le POST vers `storekit/verify-purchase` échouait (404 avalé par `try?`), ce qui
    /// consommait le reçu Apple sans confirmation serveur ; la prochaine relecture du profil
    /// personnel (`ProfileViewModel.swift:99-100`, qui écrase `UserSession.shared.coinsAmount` avec
    /// la valeur serveur) effaçait alors silencieusement et DÉFINITIVEMENT le crédit local — argent
    /// réel dépensé, crédit définitivement perdu, sans qu'aucune trace ne le signale. Ce correctif
    /// retourne maintenant `true`/`false` selon que le serveur a confirmé, permettant à l'appelant de
    /// ne PAS terminer la transaction en cas d'échec — StoreKit la redélivrera automatiquement au
    /// prochain lancement (`Transaction.updates`), donnant une vraie chance de resynchronisation
    /// future SANS rien simuler côté serveur.
    ///
    /// **Travail backend requis pour une vraie parité (documenté, PAS implémenté ici)** : créer un
    /// endpoint serveur `storekit/verify-purchase` qui (1) reçoit `userId`/`productId`/
    /// `transactionId`/`originalTransactionId`, (2) vérifie la transaction auprès de l'App Store
    /// Server API (`https://api.storekit.itunes.apple.com/inApps/v1/transactions/{transactionId}`,
    /// avec le fallback sandbox) pour confirmer authenticité + montant + non-duplication (rejouer un
    /// `transactionId` déjà crédité doit être un no-op, pas un double crédit), (3) UNIQUEMENT alors
    /// crédite `coinsAmount` en base et renvoie succès. Tant que ce point n'existe pas, la
    /// fonctionnalité reste **FUNCTIONALLY_FAILED** au sens strict de la parité (l'argent réel
    /// dépensé n'est jamais durablement crédité côté serveur) — ce correctif réduit le risque de
    /// perte silencieuse mais ne le supprime pas, et NE DOIT PAS être déclaré COMPLETE_PARITY_*.
    @discardableResult
    private func creditAndReport(transaction: StoreKit.Transaction, quantity: Int) async -> Bool {
        let newBalance = UserSession.shared.coinsAmount + Double(quantity)
        UserSession.shared.coinsAmount = newBalance
        guard let userId = UserSession.shared.myId else { return false }
        let params: [String: String] = [
            "userId": userId, "quantity": String(quantity), "productId": transaction.productID,
            "transactionId": String(transaction.id), "originalTransactionId": String(transaction.originalID),
        ]
        do {
            let response = try await APIClient.shared.post(params, endpoint: "storekit/verify-purchase")
            return response.isBackendSuccess
        } catch {
            return false
        }
    }
}
