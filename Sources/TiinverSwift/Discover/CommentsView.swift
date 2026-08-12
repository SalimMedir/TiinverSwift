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
        HStack(alignment: .top, spacing: 8) {
            AsyncImage(url: URL(string: comment.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Color(.secondarySystemBackground)
            }
            .frame(width: 32, height: 32).clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("@\(comment.username ?? "")").font(.caption).bold()
                    if comment.certified == "1" { Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue) }
                }
                if comment.hasGift == true, let emoji = comment.giftEmoji {
                    Label("\(emoji) \(comment.giftName ?? "") — \(comment.giftPrice ?? 0)", systemImage: "gift.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Text(comment.commentText ?? "").font(.subheadline)
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
