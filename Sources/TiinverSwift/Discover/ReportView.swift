import SwiftUI

/// Port de `report/Report.java` (172, entier) + `models/report/ReportData.java` (95, entier) —
/// signalement d'un utilisateur ou d'un groupe. **Motifs de signalement (`R.array.
/// report_setting_array`, fichier ressource) PAS lus** — liste standard reconstruite (mêmes
/// catégories que la plupart des réseaux sociaux), à faire valider/ajuster contre la vraie liste
/// Android avant mise en production plutôt que supposée figée.
struct ReportView: View {
    let targetId: String
    let username: String
    let reportType: String // "user" (avec `target_id`/`report_type` d'origine) ou "group"
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReason: String?
    @State private var isSubmitting = false
    @State private var didSend = false

    /// Reconstruit faute d'avoir lu `R.array.report_setting_array` — motifs usuels, PAS vérifiés
    /// mot pour mot contre la ressource Android réelle.
    private let reasons = ["Spam", "Contenu inapproprié", "Harcèlement", "Usurpation d'identité", "Fausses informations", "Autre"]

    var body: some View {
        List(reasons, id: \.self) { reason in
            Button(reason) { confirmingReason = reason }
        }
        .navigationTitle("Signaler")
        .disabled(isSubmitting)
        .confirmationDialog(
            "Signaler \(username) ?", isPresented: Binding(get: { confirmingReason != nil }, set: { if !$0 { confirmingReason = nil } }),
            titleVisibility: .visible
        ) {
            Button("Signaler", role: .destructive) {
                if let reason = confirmingReason { Task { await submit(reason: reason) } }
            }
        }
        .alert("Signalement envoyé", isPresented: $didSend) { // R.string.report_send
            Button("OK") { dismiss() }
        }
    }

    /// Port de `Report.report(pos)` — `POST report`, `{userId, username, message, target_id,
    /// report_type}`.
    private func submit(reason: String) async {
        isSubmitting = true
        defer { isSubmitting = false }
        let params = ["userId": targetId, "username": username, "message": reason, "target_id": targetId, "report_type": reportType]
        if (try? await APIClient.shared.post(params, endpoint: "report")) != nil {
            didSend = true
        }
    }
}
