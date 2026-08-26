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
                // Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-062, Phase B P1-25) —
                // la branche "vide" (garde `notifications.isEmpty`) est un SUR-ENSEMBLE strict de
                // la garde de la branche "erreur" (`errorMessage != nil && notifications.isEmpty`)
                // et était testée AVANT elle — dès que `isLoading` repasse à `false` (le `defer`
                // de `fetchNotifications` s'exécute toujours), "Aucune notification" captait
                // systématiquement le cas, y compris quand `errorMessage` était non-nil, rendant
                // la branche erreur strictement inatteignable. Port de `ShowNoti.setupObservers`
                // (`:107-142`) : `messageError` (Observer 2, état réseau `ERROR`) est distinct de
                // `messageEmpty` (Observer 1, liste vide ET réseau terminé) — l'erreur doit être
                // testée AVANT le vide, même motif déjà correct dans
                // `FeedView.emptyOrStatusState`/`ProfileView.header`.
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    ProgressView()
                } else if let error = viewModel.errorMessage, viewModel.notifications.isEmpty {
                    Text(error) // messageError
                        .foregroundStyle(.red)
                } else if viewModel.notifications.isEmpty {
                    Text("Aucune notification") // messageEmpty
                        .foregroundStyle(.secondary)
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
            // **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-024, Phase B P2)** — ce
            // switch ne testait que `noti.verb`, jamais `noti.payloadType`, contrairement à
            // `LocalNotificationBuilder.activityNotificationContent` (même module, déjà correct) :
            // un commentaire-cadeau (`AdapterNoti.java:219-224,361-392`, `TYPE_GIFT`) affichait
            // l'identifiant brut du cadeau (`noti.commentText`, ex. "gift_rose_23") entre
            // guillemets au lieu de l'emoji + nom lisible. Même résolution `GiftCatalog` que la
            // notification push équivalente, réutilisée telle quelle plutôt que dupliquée.
            if noti.payloadType == "gift" {
                let emoji = GiftCatalog.emoji(for: noti.commentText)
                let name = GiftCatalog.resolve(noti.commentText)?.name ?? "cadeau"
                return "vous a envoyé un cadeau \(emoji) \(name) en tant que commenter"
            }
            // **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-027, Phase B P3)** — port
            // du `switch(type)` de `CommentVH.bind` (`AdapterNoti.java:301-327`) : `noti.type` était
            // déjà décodé/persisté (`NotificationCenterViewModel.swift:98`) mais jamais consulté
            // ici, un commentaire normal, une réponse à un commentaire, et une réponse à la
            // publication affichaient tous le même texte générique.
            switch noti.type {
            case "reply": return "a répondu à votre commentaire « \(noti.commentText ?? "") »"
            case "reply_on_my_post": return "a répondu à votre publication"
            default:
                if let text = noti.commentText, !text.isEmpty { return "a commenté : « \(text) »" }
                return "a commenté votre publication"
            }
        case "follow": return "a commencé à te suivre"
        case "transfert":
            // **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-025, Phase B P2)** — port
            // de `AdapterNoti.TransferVH.bind` (`"%s %s %s << %s >>"`, fullName+transferred_you+
            // MONTANT+coins) : `NotiEntity.commentText` porte le montant transféré pour ce `verb`
            // précis (`NotiEntity.java:26`, documenté explicitement dans le commentaire de champ
            // Android — même propriété que le texte de commentaire/id de cadeau selon le `verb`),
            // jamais lu ici auparavant. Bracket ASCII Android "<< coins >>" pas reproduit tel quel
            // (déjà remplacé par des guillemets français ailleurs dans ce même switch, cohérent).
            if let amount = noti.commentText, !amount.isEmpty {
                return "vous a transféré \(amount) pièces"
            }
            return "vous a transféré des coins"
        default: return noti.commentText ?? noti.verb ?? ""
        }
    }

    @ViewBuilder
    private var nameAndBodyText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(noti.firstname ?? "") \(noti.lastname == "null" ? "" : (noti.lastname ?? ""))")
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Text(bodyText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        HStack {
            // Port de `AdapterNoti.img_avatar.setOnClickListener`/`bindAvatarClick` (`NotiLikecmt/
            // AdapterNoti.java:482-483` et `:587-588`, les DEUX formes de ligne de notification) —
            // zone tapable = avatar SEUL, inconditionnellement → profil.
            NavigationLink {
                ProfileView(userId: String(noti.userId), isCurrentUser: false)
            } label: {
                CDNAsyncImage(url: noti.profile.flatMap(URL.init), targetSize: CGSize(width: 44, height: 44)) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-023, Phase B P1-13)** —
            // port de `AdapterNoti.bindBodyClick` (`:612-625`) : zone tapable DISTINCTE de l'avatar,
            // attachée au bloc nom/texte, → le post visé (`FullScreenMedia`), indépendamment de la
            // présence d'une vignette. Android désactive explicitement le clic
            // (`body.setClickable(false)`) quand `activityId<=0` (ex. notification `follow`, sans
            // post associé) — reproduit ici en affichant le texte SANS le rendre tapable dans ce cas,
            // plutôt qu'un `Button` désactivé (pas de retour visuel de "bouton" pour Android non plus).
            if let post = reconstructedPost {
                Button {
                    onOpenPost(post)
                } label: {
                    nameAndBodyText
                }
                .buttonStyle(.plain)
            } else {
                nameAndBodyText
            }
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
                        //
                        // Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-022, Phase B
                        // P1-12) — ce bouton reproduit `FollowVH.bind` (`AdapterNoti.java:420-441`),
                        // qui poste sur l'endpoint `followback`, PAS l'endpoint `follow` générique
                        // utilisé par le profil/les suggestions.
                        do {
                            try await ProfileRepository.shared.followBack(userId: String(noti.userId), followerId: myId)
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
                    CDNAsyncImage(url: thumbnailURL, targetSize: CGSize(width: 44, height: 44)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
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
