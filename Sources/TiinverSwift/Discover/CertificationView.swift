import PhotosUI
import SwiftUI

/// Port de `ui/certification/CertificationActivity.java` (2 onglets : "create"/`
/// CertificationPlanFragment`, "dashboard"/statut) + `CertificationRequestActivity.java` (upload du
/// justificatif, GAP-004, lu en entier le 2026-08-15) — consolidés en UN SEUL écran défilant plutôt
/// que 2 onglets séparés (même simplification assumée qu'ailleurs dans ce portage, ex. `ProfileView`
/// pour `UserProfile`/`AddPerfilFoto`). Palier tarifaire ("basic", seul palier réellement envoyé par
/// `CertificationRequestActivity.btnSubmitCertification`, voir `CertificationRepository.submit`) —
/// PAS de sélection de palier multiple : Android lui-même n'en propose qu'un côté client malgré une
/// API générique. `CertificationPlanFragment.tarification()` (re-fetch réseau redondant avec la
/// valeur Remote Config déjà affichée) délibérément PAS porté ici — `certificationPrice` (Remote
/// Config) suffit à afficher le prix, hors périmètre strict de GAP-004 (transfert de fichier).
struct CertificationView: View {
    @State private var status: CertificationStatus?
    @State private var isLoading = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var submitSucceeded = false

    var body: some View {
        List {
            Section {
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

            // Port de `CertificationPlanFragment` (bouton "create") + `CertificationRequestActivity`
            // — TOUJOURS affiché, sans condition sur `status` (Android ne bloque pas non plus une
            // nouvelle demande si une précédente existe déjà, `CertificationActivity` montre les 2
            // onglets inconditionnellement).
            Section("Nouvelle demande") {
                Text(String(format: "À partir de %.0f pièces/mois", TiinverFirebaseConfigManager.shared.certificationPrice)) // R.string.from + coins_per_month
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choisir un justificatif", systemImage: "doc.badge.plus")
                }
                .disabled(isSubmitting)

                if isSubmitting {
                    ProgressView()
                } else if let submitError {
                    Text(submitError).foregroundStyle(.red) // R.string.oops2
                } else if submitSucceeded {
                    Text("Envoyé avec succès").foregroundStyle(.green) // R.string.submited_successfully
                }
            }
        }
        .navigationTitle("Certification")
        .task { await load() }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await submit(item) }
        }
    }

    private func load() async {
        guard let userId = UserSession.shared.myId else { return }
        isLoading = true
        defer { isLoading = false }
        status = try? await CertificationRepository.shared.status(userId: userId)
    }

    /// Port de `btnUploadDocument`/`btnSubmitCertification` (`CertificationRequestActivity`) — pas
    /// de bouton "envoyer" séparé après sélection : Android exige un tap distinct sur
    /// `btnSubmitCertification`, mais celui-ci n'a AUCUNE autre condition/saisie entre la sélection
    /// du fichier et l'envoi (pas de champ texte, pas de confirmation) — fusionner les deux taps en
    /// un seul (sélection = envoi immédiat) simplifie l'UI sans changer le comportement observable.
    private func submit(_ item: PhotosPickerItem) async {
        guard let userId = UserSession.shared.myId,
              let raw = try? await item.loadTransferable(type: Data.self),
              let jpegData = UIImage(data: raw)?.jpegData(compressionQuality: 0.9)
        else { return }
        isSubmitting = true
        submitError = nil
        submitSucceeded = false
        defer { isSubmitting = false; pickerItem = nil }
        do {
            try await CertificationRepository.shared.submit(userId: userId, documentData: jpegData)
            submitSucceeded = true
            await load() // reflète immédiatement le nouveau statut "pending", comme Android le ferait au prochain onResume du dashboard
        } catch {
            submitError = "Une erreur est survenue" // R.string.oops2
        }
    }
}
