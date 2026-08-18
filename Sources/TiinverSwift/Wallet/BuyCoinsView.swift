import StoreKit
import SwiftUI

/// Port de `SelectAmountActivity.java`/`PurchaseActivity.java` — **PAS un portage littéral de leur
/// flux mobile money/crypto manuel** (voir `CoinStoreManager.swift` en tête de fichier pour la
/// justification complète) : mêmes paliers de pièces (250/500/1250/2500/5000), achat réel via
/// StoreKit 2 au lieu de la saisie manuelle d'un identifiant de transaction.
struct BuyCoinsView: View {
    @StateObject private var store = CoinStoreManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var purchasedQuantity: Int?

    var body: some View {
        List {
            if store.products.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(store.products, id: \.id) { product in
                Button {
                    Task {
                        let quantity = CoinTier.quantities.first { CoinTier.productID(forQuantity: $0) == product.id } ?? 0
                        if await store.purchase(product, quantity: quantity) {
                            purchasedQuantity = quantity
                        }
                    }
                } label: {
                    HStack {
                        Text(quantityLabel(for: product))
                        Spacer()
                        Text(product.displayPrice).foregroundStyle(.secondary)
                    }
                }
                .disabled(store.isPurchasing)
            }
        }
        .navigationTitle("Acheter des pièces") // titre non identifié précisément dans le XML Android non lu
        // Port de `tutoriel_withdraw` (`SelectAmountActivity`, l'écran remplacé par CET écran) —
        // voir `TransactionTutorialView.swift`, 2026-08-18 P2.
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { TransactionTutorialView() } label: { Image(systemName: "questionmark.circle") }
            }
        }
        .task { await store.loadProducts() }
        .alert("Erreur", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.lastError ?? "")
        }
        .alert("Achat réussi", isPresented: Binding(get: { purchasedQuantity != nil }, set: { if !$0 { purchasedQuantity = nil } })) {
            Button("OK") { dismiss() }
        } message: {
            Text("\(purchasedQuantity ?? 0) pièces ajoutées à votre solde.")
        }
    }

    private func quantityLabel(for product: Product) -> String {
        let quantity = CoinTier.quantities.first { CoinTier.productID(forQuantity: $0) == product.id } ?? 0
        return "\(quantity) pièces" // R.string.coins
    }
}
