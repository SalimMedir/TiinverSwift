import SwiftUI

/// Port de `NotiLikecmt/ShowNoti.java` — écran "centre de notifications" complet, remplace le
/// placeholder `sheet` de `HomeShellView.swift`.
///
/// PAS porté ici, volontairement (voir `NotificationRepository.retriaveData`, déjà exclu du
/// module 4 pour la même raison) : l'injection de suggestions de follow dans la même liste
/// (`displayList(JSONObject)`, `SearchModel`, pagination `followers`) — c'est une fonctionnalité
/// de suggestions de contacts, pas une notification à proprement parler ; `SearchModel.java`
/// n'a pas été lu. Cet écran affiche donc UNIQUEMENT les vraies notifications
/// (`NotificationCenterViewModel`, déjà écrit module 4), pas le flux mixte notifications+
/// suggestions de l'original. Pagination infinie (`VISIBLE_THRESHOLD`/`onScrolled`) non
/// reproduite non plus, pour la même raison — `NotificationCenterViewModel.fetchNotifications`
/// ne prend pas encore de paramètre `offset`.
struct NotificationsListView: View {
    @StateObject private var viewModel = NotificationCenterViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    ProgressView()
                } else if viewModel.notifications.isEmpty {
                    Text("Aucune notification") // messageEmpty
                        .foregroundStyle(.secondary)
                } else if let error = viewModel.errorMessage, viewModel.notifications.isEmpty {
                    Text(error) // messageError
                        .foregroundStyle(.red)
                } else {
                    List(viewModel.notifications, id: \.id) { noti in
                        NotificationRow(noti: noti)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifications") // R.string.title_notifications
            .task {
                if let userId = UserSession.shared.myId {
                    await viewModel.fetchNotifications(userId: userId)
                }
            }
            // Port de `ShowNoti.onStop()` : marque tout comme lu en quittant l'écran.
            .onDisappear {
                Task { await viewModel.markAllRead() }
            }
        }
    }
}

/// **Parité UI avec Android corrigée par capture d'écran (2026-08-16)** — la ligne affichait
/// seulement `verb` brut (ex. "follow") au lieu d'un texte formaté, et n'avait ni bouton
/// "Suivre en Retour" (notifications `follow`) ni vignette de la publication concernée
/// (notifications `like`/`comment`/`share`) — les deux visibles sur la capture Android réelle.
/// Texte formaté réutilise EXACTEMENT le même mapping verb→phrase que
/// `LocalNotificationBuilder.activityNotificationContent` (déjà porté), pas un texte réinventé.
private struct NotificationRow: View {
    let noti: NotiEntity
    @State private var justFollowedBack = false

    private var thumbnailURL: URL? {
        let raw = noti.cdnThumbnailUrl ?? noti.cdnContentUrl ?? noti.objectUrl
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// Port de `LocalNotificationBuilder.activityNotificationContent`'s switch sur `verb` — même
    /// texte, réutilisé ici pour la liste plutôt que dupliqué.
    private var bodyText: String {
        switch noti.verb {
        case "like": return "a aimé votre publication"
        case "share": return "a partagé votre publication"
        case "comment":
            if let text = noti.commentText, !text.isEmpty { return "a commenté : « \(text) »" }
            return "a commenté votre publication"
        case "follow": return "a commencé à te suivre"
        case "transfert": return "vous a transféré des coins"
        default: return noti.commentText ?? noti.verb ?? ""
        }
    }

    var body: some View {
        HStack {
            AsyncImage(url: noti.profile.flatMap(URL.init)) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(noti.firstname ?? "") \(noti.lastname == "null" ? "" : (noti.lastname ?? ""))")
                    .font(.subheadline.bold())
                Text(bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if noti.verb == "follow" {
                Button {
                    Task {
                        guard let myId = UserSession.shared.myId else { return }
                        justFollowedBack = true
                        try? await ProfileRepository.shared.follow(userId: String(noti.userId), followerId: myId)
                    }
                } label: {
                    Text(justFollowedBack ? "Suivi" : "Suivre en Retour")
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(justFollowedBack ? Color(.secondarySystemBackground) : Color.accentColor)
                        .foregroundStyle(justFollowedBack ? Color.primary : Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
                .disabled(justFollowedBack)
            } else if let thumbnailURL {
                AsyncImage(url: thumbnailURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .opacity(noti.isRead == 0 ? 1 : 0.6)
    }
}
