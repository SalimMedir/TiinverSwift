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
                // **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-063, Phase B P1-26)**
                // — `WalletActivity.java:124-186` relance automatiquement `executeBackTask()`
                // toutes les 5s sur échec réseau (`attemptReconnect`, `:178-186`), sans jamais
                // afficher de message d'erreur — Android se rétablit silencieusement dès que le
                // réseau revient. `viewModel.errorMessage` était déjà peuplé sur échec mais
                // JAMAIS lu ici : si l'échec survenait au chargement INITIAL (liste vide), aucune
                // cellule n'existait pour déclencher un nouvel essai via `.onAppear`, et l'écran
                // restait vide/figé en permanence, sans texte, sans bouton, sans reprise. Repli
                // ASSUMÉ, pas la reproduction de la reprise automatique silencieuse à 5s
                // d'Android (nécessiterait un timer géré par le cycle de vie de la vue, même
                // classe de risque de fuite que V5-F-057/CADisplayLink) : message d'erreur visible
                // + bouton "Réessayer" explicite, complété par `.refreshable` ci-dessous pour un
                // second mécanisme de reprise manuelle.
                if let errorMessage = viewModel.errorMessage, viewModel.transactions.isEmpty {
                    VStack(spacing: 8) {
                        Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                        Button("Réessayer") { Task { await viewModel.loadInitial() } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .refreshable { await viewModel.loadInitial() }
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
