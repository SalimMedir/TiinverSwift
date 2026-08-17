import SwiftUI

/// Port de `advertising/ui/CommandeActivity.java` (entier, 2026-08-18, P1) — détail en LECTURE
/// SEULE d'un boost (les champs affichés viennent de l'`AdsData` déjà en mémoire, PAS d'un
/// rechargement réseau — fidèle à l'original, `data.getSerializable("data")`) + action "arrêter la
/// promotion" (`stop_promotion` → `boostCancel`).
struct BoostDetailView: View {
    let userId: String
    let boost: AdsData

    @Environment(\.dismiss) private var dismiss
    @State private var showCancelConfirm = false
    @State private var isCancelling = false
    @State private var statusMessage: String?
    @State private var succeeded = false

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    CDNAsyncImage(url: boost.resolvedObjectUrl.flatMap(URL.init)) { $0.resizable().aspectRatio(contentMode: .fit) } placeholder: {
                        Color(.secondarySystemBackground)
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
            }
            Section("Résumé") {
                row("Statut", boost.status ?? "")
                row("Objectif", boost.objective ?? "")
                row("Démarré le", boost.start_at ?? "")
                row("Durée", "\(boost.duration_days ?? "0") jours")
                row("Budget total", "\(Int(boost.budget_points ?? 0))")
                row("Dépensé", boost.total_spent ?? "0")
            }
            Section("Performance") {
                row("Vues", "\(boost.views ?? 0)")
                row("J'aime", "\(boost.likes ?? 0)")
                row("Nouveaux abonnés", "\(boost.followers ?? 0)")
                row("Temps de visionnage total", "\(boost.total_watch_time ?? 0)")
                row("Temps de visionnage moyen", "\(boost.avg_watch_time ?? 0)")
            }
            if boost.status?.lowercased() != "cancel" {
                Section {
                    Button(role: .destructive) {
                        showCancelConfirm = true
                    } label: {
                        if isCancelling { ProgressView() } else { Text("Arrêter la promotion").frame(maxWidth: .infinity) }
                    }
                    .disabled(isCancelling)
                }
            }
            if let statusMessage {
                Section {
                    Text(statusMessage).foregroundStyle(succeeded ? .green : .red)
                }
            }
        }
        .navigationTitle("Détail du boost")
        // Port du dialogue `FireMissilesDialogFragment` (`cancel_promotion`/`cancel_promotion_message`).
        .alert("Arrêter la promotion ?", isPresented: $showCancelConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Arrêter", role: .destructive) { cancel() }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func cancel() {
        isCancelling = true
        statusMessage = nil
        Task {
            do {
                try await AdsRepository.shared.cancelBoost(userId: userId, boostId: boost.id)
                isCancelling = false
                succeeded = true
                statusMessage = "Envoyé avec succès"
            } catch {
                isCancelling = false
                succeeded = false
                statusMessage = "Oups, une erreur est survenue"
            }
        }
    }
}
