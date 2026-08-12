import SwiftUI

/// Port PARTIEL de `ui/certification/CertificationActivity.java`/`CertificationRequestActivity.
/// java`/`CertificationPlanFragment.java` (aucun des 3 lu en détail cette session, hors budget) —
/// consultation du statut de certification uniquement (voir `CertificationRepository.swift`). La
/// soumission d'une nouvelle demande (upload de justificatif + choix de palier tarifaire, lié à
/// `FirebaseConfigManager.certificationPrice`, module 15) N'EST PAS construite ici.
struct CertificationView: View {
    @State private var status: CertificationStatus?
    @State private var isLoading = false

    var body: some View {
        List {
            if let status {
                LabeledContent("Statut", value: status.status ?? "—")
                if let level = status.level { LabeledContent("Palier", value: level) }
                if let requestedAt = status.requested_at { LabeledContent("Demandé le", value: requestedAt) }
                if status.is_certified == 1 {
                    Label("Compte certifié", systemImage: "checkmark.seal.fill").foregroundStyle(.blue)
                }
            } else if isLoading {
                ProgressView()
            } else {
                Text("Aucune demande de certification en cours.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Certification")
        .task { await load() }
    }

    private func load() async {
        guard let userId = UserSession.shared.myId else { return }
        isLoading = true
        defer { isLoading = false }
        status = try? await CertificationRepository.shared.status(userId: userId)
    }
}
