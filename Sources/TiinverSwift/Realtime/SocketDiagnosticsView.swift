import SwiftUI

/// **Ajouté (2026-09-04, diagnostic temporaire — audit "conversation instantanée")** — écran de
/// diagnostic manuel, accessible depuis `RosterListView` (bouton "stéthoscope" de la barre
/// d'outils), pour observer l'état réel de la socket pendant un test sur un appareil/simulateur où
/// la console Xcode n'est pas accessible (Appetize). À retirer une fois la cause du problème de
/// livraison temps réel confirmée et corrigée — pas une fonctionnalité destinée aux utilisateurs
/// finaux.
struct SocketDiagnosticsView: View {
    @ObservedObject private var diagnostics = SocketDiagnostics.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("État de la socket") {
                    row("Statut", diagnostics.status, color: statusColor)
                    if let lastEventAt = diagnostics.lastEventAt {
                        row("Dernier événement", Self.formatter.string(from: lastEventAt))
                    }
                    row("Tentatives de connexion", "\(diagnostics.connectAttempts)")
                    if let hadPayload = diagnostics.lastConnectHadPayload {
                        row("Jeton envoyé au handshake", hadPayload ? "Oui" : "NON (absent/vide)", color: hadPayload ? .green : .red)
                    }
                }

                Section("Activité serveur reçue") {
                    row("Événements reçus (presence/message)", "\(diagnostics.liveServerEventsReceivedCount)",
                        color: diagnostics.liveServerEventsReceivedCount > 0 ? .green : .orange)
                    if let lastEvent = diagnostics.lastLiveServerEventName {
                        row("Dernier événement reçu", lastEvent)
                    } else {
                        Text("Aucun événement poussé par le serveur reçu depuis le lancement de l'app.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                if let error = diagnostics.lastErrorMessage {
                    Section("Dernier message d'erreur/déconnexion") {
                        Text(error).font(.footnote.monospaced())
                    }
                }

                // **Ajouté (2026-09-04, audit "historique de conversation absent après envoi")**
                Section("Roster — écriture (après un envoi/réception)") {
                    if let conversationId = diagnostics.lastRosterWriteConversationId,
                       let at = diagnostics.lastRosterWriteAt {
                        row("conversationId écrit", conversationId)
                        row("Type d'écriture", diagnostics.lastRosterWriteWasInsert == true ? "Création" : "Mise à jour")
                        row("À", Self.formatter.string(from: at))
                    } else {
                        Text("Aucune écriture roster observée depuis le lancement de l'app — si vous venez d'envoyer un message, ceci indique que RosterRepository.updateRoster n'a jamais été atteint avec un conversationId valide.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("Roster — dernière lecture (RosterListView)") {
                    if let count = diagnostics.lastRosterRefreshRowCount, let at = diagnostics.lastRosterRefreshAt {
                        row("Lignes trouvées", "\(count)", color: count > 0 ? .green : .orange)
                        row("À", Self.formatter.string(from: at))
                    } else {
                        Text("L'onglet Chat n'a pas encore rafraîchi sa liste depuis le lancement de l'app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Session") {
                    row("Compte", UserSession.shared.username ?? "—")
                    row("apiKey présente", UserSession.shared.apiKey?.isEmpty == false ? "Oui" : "NON", color: UserSession.shared.apiKey?.isEmpty == false ? .green : .red)
                    row("URL socket", diagnostics.socketURL)
                }

                // **Ajouté (2026-09-04, diagnostic temporaire — audit "nikname vide")** — voir
                // `UserSession.debugLastLoginNiknameRaw`/`AuthEndpoints.captureNiknameDiagnostic`.
                Section("Dernier login — champ \"nikname\" reçu") {
                    if let raw = UserSession.shared.debugLastLoginNiknameRaw {
                        Text(raw).font(.footnote.monospaced())
                    } else {
                        Text("Pas encore de login effectué depuis l'installation de ce build.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Cet écran est un outil de diagnostic temporaire, pas une fonctionnalité destinée à rester dans l'app.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Diagnostic socket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var statusColor: Color {
        switch diagnostics.status {
        case "Connectée": return .green
        case "Connexion en cours…": return .orange
        default: return .red
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
