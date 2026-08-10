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

private struct NotificationRow: View {
    let noti: NotiEntity

    var body: some View {
        HStack {
            AsyncImage(url: noti.profile.flatMap(URL.init)) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading) {
                Text("\(noti.firstname ?? "") \(noti.lastname == "null" ? "" : (noti.lastname ?? ""))")
                    .font(.subheadline.bold())
                Text(noti.commentText ?? noti.verb ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .opacity(noti.isRead == 0 ? 1 : 0.6)
    }
}
