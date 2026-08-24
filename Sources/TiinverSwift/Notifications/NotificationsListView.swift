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
    /// Port de `AdapterNoti`'s tap sur la vignette de contenu → `Intent(FullScreenMedia.class)`
    /// (`NotiLikecmt/AdapterNoti.java`, réutilise `CustomCardView`/`CustomVideoView` — les MÊMES
    /// classes déjà remises à parité pour l'avatar/tap-profil dans `FeedDetailCell`, GAP-020) —
    /// absent jusqu'ici côté iOS. Réutilise `FeedDetailPagerView`'s variante "post isolé" (déjà
    /// câblée pour les liens profonds), MÊME motif.
    @State private var detailPost: FeedActivity?

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
                        NotificationRow(noti: noti, onOpenPost: { detailPost = $0 })
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
            .fullScreenCover(item: $detailPost) { post in
                // notifiesAuthor: PAS câblé (défaut `false`) — MÊME source Android que SearchView
                // (`FullScreenMedia`, `notifyUser` jamais appelé, V4-F-030).
                FeedDetailPagerView(posts: [post], startIndex: 0, onClose: { detailPost = nil })
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
    var onOpenPost: (FeedActivity) -> Void = { _ in }
    @State private var justFollowedBack = false

    private var thumbnailURL: URL? {
        let raw = noti.cdnThumbnailUrl ?? noti.cdnContentUrl ?? noti.objectUrl
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// Port de `activityId`/`object`/`object_url`/`cdn_*` déjà décodés (`NotificationCenterViewModel`)
    /// — reconstruit un `FeedActivity` minimal pour réutiliser `FeedDetailPagerView` tel quel plutôt
    /// que construire un second visualiseur fullscreen pour ce seul point d'entrée.
    private var reconstructedPost: FeedActivity? {
        guard noti.activityId > 0 else { return nil }
        return FeedActivity(
            id: Int(noti.activityId), actor: String(noti.userId),
            lastname: noti.lastname == "null" ? nil : noti.lastname, firstname: noti.firstname,
            object: noti.object, object_url: noti.objectUrl, profile: noti.profile,
            cdn_content_id: noti.cdnContentId, cdn_content_url: noti.cdnContentUrl, cdn_thumbnail_url: noti.cdnThumbnailUrl
        )
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
            // Port de `AdapterNoti.img_avatar.setOnClickListener`/`bindAvatarClick` (`NotiLikecmt/
            // AdapterNoti.java:482-483` et `:587-588`, les DEUX formes de ligne de notification) —
            // absent jusqu'ici côté iOS (gap confirmé, pas une hypothèse : aucune navigation du
            // tout sur cette ligne). Zone tapable = avatar + bloc nom/texte, comme Android.
            NavigationLink {
                ProfileView(userId: String(noti.userId), isCurrentUser: false)
            } label: {
                HStack {
                    CDNAsyncImage(url: noti.profile.flatMap(URL.init)) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(noti.firstname ?? "") \(noti.lastname == "null" ? "" : (noti.lastname ?? ""))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(bodyText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()

            if noti.verb == "follow" {
                Button {
                    Task {
                        guard let myId = UserSession.shared.myId else { return }
                        justFollowedBack = true
                        // Corrigé le 2026-08-20 (MIGRATION_PARITY_AUDIT_V3.md V3-F-107, Phase B
                        // P1 — bug frère, même pattern `try?` + optimiste sans rollback, trouvé en
                        // vérifiant tous les appelants de `ProfileRepository.follow`) : rollback
                        // ajouté, fidèle au vrai comportement Android (`UserProfile.java:507-508`).
                        do {
                            try await ProfileRepository.shared.follow(userId: String(noti.userId), followerId: myId)
                        } catch {
                            justFollowedBack = false
                        }
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
                Button {
                    if let post = reconstructedPost { onOpenPost(post) }
                } label: {
                    CDNAsyncImage(url: thumbnailURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(reconstructedPost == nil)
            }
        }
        .opacity(noti.isRead == 0 ? 1 : 0.6)
    }
}
