import SwiftUI

/// Port de `comments/ui/MyBottomSheetDialogFragment.java`/`CommentViewModel.java` (structure —
/// pas lus en détail, UI reconstruite depuis `CommentRepository`/`CommentModel` déjà vérifiés) —
/// feuille de commentaires d'une publication.
struct CommentsView: View {
    let activityId: Int
    @State private var comments: [Comment] = []
    @State private var inputText = ""
    @State private var replyTarget: Comment?
    @State private var isLoading = false
    @State private var offset = 0
    private let limit = 20
    // V5-F-046 (Phase B P1-20) — réponses imbriquées (threading), voir `repliesSection(for:)`.
    @State private var expandedReplies: [Int: [Comment]] = [:]
    @State private var loadingReplyIds: Set<Int> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(comments) { comment in
                    commentRow(comment)
                        .onAppear { if comment.id == comments.last?.id { Task { await loadMore() } } }
                }
                .listStyle(.plain)

                if let replyTarget {
                    HStack {
                        Text("Réponse à @\(replyTarget.username ?? "")").font(.caption)
                        Spacer()
                        Button { self.replyTarget = nil } label: { Image(systemName: "xmark.circle.fill") }
                    }
                    .padding(.horizontal)
                }

                HStack {
                    TextField("Ajouter un commentaire…", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                    Button("Envoyer") { Task { await send() } } // pas de libellé Android identifié (layout non fourni)
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Commentaires")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Fermer") {} } }
            .task { await loadMore() }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            commentLine(comment)
            // **Ajouté le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-046, Phase B P1-20)** —
            // port de `CommentAdapter.java:211-233` (bouton "Afficher N commentaires", visible si
            // `elts.getRepliesCount() > 0`, tap → `getReplay` → `ReplayCommentAdapter`) : le
            // threading n'était jamais chargé ni affiché côté iOS — `CommentRepository.replies`
            // existait déjà (port fonctionnel correct de `getReplay`) mais n'avait AUCUN appelant
            // dans tout le projet (grep exhaustif), fonctionnalité de LECTURE totalement absente.
            if (comment.repliesCount ?? 0) > 0 {
                repliesSection(for: comment)
            }
        }
    }

    @ViewBuilder
    private func repliesSection(for comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let replies = expandedReplies[comment.id] {
                ForEach(replies) { reply in
                    commentLine(reply)
                }
            } else {
                Button {
                    Task { await loadReplies(for: comment) }
                } label: {
                    if loadingReplyIds.contains(comment.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Afficher \(comment.repliesCount ?? 0) commentaire\((comment.repliesCount ?? 0) > 1 ? "s" : "")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .disabled(loadingReplyIds.contains(comment.id))
            }
        }
        .padding(.leading, 40) // aligné sous le texte du commentaire parent (avatar 32pt + spacing 8)
    }

    private func loadReplies(for comment: Comment) async {
        guard expandedReplies[comment.id] == nil, !loadingReplyIds.contains(comment.id) else { return }
        loadingReplyIds.insert(comment.id)
        defer { loadingReplyIds.remove(comment.id) }
        let page = (try? await CommentRepository.shared.replies(commentId: comment.id, limit: limit, offset: 0)) ?? []
        expandedReplies[comment.id] = page
    }

    @ViewBuilder
    private func commentLine(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Port de `CommentAdapter.img_avatar.setOnClickListener`/`ReplayCommentAdapter` (les
            // DEUX adapters, commentaires ET réponses — `comments/ui/CommentAdapter.java:244-247`,
            // `ReplayCommentAdapter.java:202-205`) — absent jusqu'ici côté iOS (gap confirmé).
            NavigationLink {
                if let actorId = comment.actor {
                    ProfileView(userId: String(actorId), isCurrentUser: false)
                }
            } label: {
                CDNAsyncImage(url: URL(string: comment.profile ?? ""), targetSize: CGSize(width: 32, height: 32)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    Color(.secondarySystemBackground)
                }
                .frame(width: 32, height: 32).clipShape(Circle())
            }
            .disabled(comment.actor == nil)

            VStack(alignment: .leading, spacing: 2) {
                NavigationLink {
                    if let actorId = comment.actor {
                        ProfileView(userId: String(actorId), isCurrentUser: false)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("@\(comment.username ?? "")").font(.caption).bold().foregroundStyle(.primary)
                        if comment.certified == "1" { Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue) }
                    }
                }
                .buttonStyle(.plain)
                .disabled(comment.actor == nil)
                // Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-047, Phase B P1-21) —
                // port de `CommentAdapter.bindGiftView`/`CommentModel.resolveGift` : le serveur
                // n'envoie que `object="gift"` + `comments=<gift_id>` pour un commentaire-cadeau,
                // résolu ENTIÈREMENT côté client via `GiftCatalog` (mêmes tables que le chat), pas
                // via des champs serveur pré-résolus (jamais confirmés envoyés par le backend).
                // Emoji/prix résolus INDÉPENDAMMENT (même motif que `LocalNotificationBuilder`,
                // V4-F-071) : un id de cadeau inconnu affiche quand même 🎁, jamais un id brut.
                if comment.isGiftComment {
                    let emoji = GiftCatalog.emoji(for: comment.commentText)
                    let price = GiftCatalog.price(for: comment.commentText)
                    Label("\(emoji) \(comment.commentText ?? "cadeau") — \(price)", systemImage: "gift.fill")
                        .font(.caption2).foregroundStyle(.orange)
                } else {
                    Text(comment.commentText ?? "").font(.subheadline)
                }
                Button("Répondre") { replyTarget = comment } // pas de libellé Android identifié
                    .font(.caption2)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let page = (try? await CommentRepository.shared.comments(activityId: activityId, limit: limit, offset: offset)) ?? []
        guard !page.isEmpty else { return }
        comments.append(contentsOf: page)
        offset += limit
    }

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        let parentId = replyTarget?.id
        replyTarget = nil
        try? await CommentRepository.shared.post(activityId: activityId, text: text, parentId: parentId)
        offset = 0
        comments = []
        await loadMore()
    }
}
