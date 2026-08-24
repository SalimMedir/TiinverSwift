import SwiftUI

/// Port de `report/Report.java` (172, entier) + `models/report/ReportData.java` (95, entier) —
/// signalement d'un utilisateur ou d'un groupe.
///
/// **Corrigé le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-021, Phase B P1)** — les motifs
/// affichés ici ("Spam"/"Contenu inapproprié"/.../"Autre", 6 items inventés) ne correspondaient
/// PAS à `R.array.report_setting_array` (`strings.xml:516-525`, 8 motifs réels) : "Spam"/"Autre"
/// n'existent pas côté Android, et Nudité/Vente non autorisée/Discours de haine/Moins de 13 ans en
/// étaient absents — alors que cette même liste, correcte, existait DÉJÀ ailleurs dans le projet
/// iOS (`feedReportReasons`, `FeedView.swift`, utilisée par le menu "..." du Feed) sans jamais
/// avoir été réutilisée ici, le seul point d'entrée réel du signalement DEPUIS Profile.
struct ReportView: View {
    let targetId: String
    let username: String
    let reportType: String // "user" (avec `target_id`/`report_type` d'origine) ou "group"
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReason: String?
    @State private var isSubmitting = false
    @State private var didSend = false

    var body: some View {
        List(feedReportReasons, id: \.self) { reason in
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
        } message: {
            // **Ajouté (V4-F-024, 2026-08-24)** — port de `Report.onItemClick` (lignes 117-124) :
            // le motif choisi était rappelé dans le corps du dialogue, texte EXACT de
            // `R.string.report_msg`.
            if let confirmingReason {
                Text("Je signale cet utilisateur pour avoir publié du contenu lié à \(confirmingReason)")
            }
        }
        .alert("Signalement envoyé", isPresented: $didSend) { // R.string.report_send
            Button("OK") { dismiss() }
        }
    }

    /// Port de `Report.report(pos)` — `POST report`, `{userId, username, message, target_id,
    /// report_type}`. **`userId` = `"0"`** pour un signalement de groupe (`Report.java:77-78`,
    /// convention hardcodée côté Android — `type=="group"` n'a pas d'utilisateur réel visé).
    private func submit(reason: String) async {
        isSubmitting = true
        defer { isSubmitting = false }
        let userId = reportType == "group" ? "0" : targetId
        let params = ["userId": userId, "username": username, "message": reason, "target_id": targetId, "report_type": reportType]
        if (try? await APIClient.shared.post(params, endpoint: "report")) != nil {
            didSend = true
        }
    }
}
