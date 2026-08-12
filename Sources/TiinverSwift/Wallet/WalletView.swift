import SwiftUI

/// Port de `wallet/WalletActivity.java` (`activity_wallet.xml`, non lue en détail — reconstruite
/// depuis les `findViewById`/`ClickListener` observés) — écran principal du portefeuille : solde,
/// menu (acheter/retirer/transférer/convertir/gagner), historique paginé.
struct WalletView: View {
    @StateObject private var viewModel = WalletViewModel()
    @State private var selectedDetail: (title: String, message: String)?

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text("\(viewModel.coinsAmount, specifier: "%.0f")") // R.string.coins
                        .font(.system(size: 40, weight: .bold))
                    Text("pièces") // R.string.coins
                        .foregroundStyle(.secondary)
                    Text(viewModel.totalValueLabel).font(.caption).foregroundStyle(.secondary)
                    Text("\(viewModel.gemsAmount, specifier: "%.0f") gemmes") // R.string.gems
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                menuRow("cart.fill", "Acheter des pièces") { BuyCoinsView() } // R.id.btn_buycoins
                menuRow("arrow.down.circle.fill", "Retirer") { WithdrawView(coinsAmount: viewModel.coinsAmount) } // R.id.btn_withdraw
                menuRow("arrow.left.arrow.right.circle.fill", "Transférer") { TransferCoinsView() } // R.id.btn_transfert
                menuRow("arrow.triangle.2.circlepath.circle.fill", "Convertir en gemmes") { ConversionView() } // R.id.btn_convertion
                menuRow("gift.circle.fill", "Parrainage / Gagner des pièces") { ReferralView() } // R.id.btn_earn
            }

            Section("Historique") { // pas de libellé Android identifié pour cet en-tête
                ForEach(viewModel.transactions) { transaction in
                    Button {
                        selectedDetail = viewModel.detail(for: transaction)
                    } label: {
                        transactionRow(transaction)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if transaction.id == viewModel.transactions.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Portefeuille") // titre d'écran non identifié dans le XML non lu
        .task { await viewModel.loadInitial() }
        .alert(selectedDetail?.title ?? "", isPresented: Binding(get: { selectedDetail != nil }, set: { if !$0 { selectedDetail = nil } })) {
            Button("OK") {}
        } message: {
            Text(selectedDetail?.message ?? "")
        }
    }

    private func menuRow<Destination: View>(_ icon: String, _ title: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            Label(title, systemImage: icon)
        }
    }

    private func transactionRow(_ transaction: WalletTransaction) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.type == "withdrawalrequests" ? "Retrait" : "Achat")
                    .font(.subheadline)
                Text(transaction.createAt ?? "").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(transaction.requestedAmount, specifier: "%.0f")")
                Text(transaction.status ?? "").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
