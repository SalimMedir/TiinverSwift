import SwiftUI

/// Port de `comments/ui/MyBottomSheetDialogFragment.java`/`CommentViewModel.java` (structure —
/// pas lus en détail, UI reconstruite depuis `CommentRepository`/`CommentModel` déjà vérifiés) —
/// feuille de commentaires d'une publication.
struct CommentsView: View {
    let activityId: Int
    /// Port de `this.data.getActor()` (`MyBottomSheetDialogFragment.onPost`, branche cadeau) —
    /// l'AUTEUR de la publication commentée, destinataire (`receiverId`) d'un cadeau envoyé en
    /// commentaire. **Ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-048, Phase B P2)**.
    let postActorId: String?
    @State private var comments: [Comment] = []
    @State private var inputText = ""
    @State private var replyTarget: Comment?
    @State private var isLoading = false
    @State private var offset = 0
    private let limit = 20
    // V5-F-046 (Phase B P1-20) — réponses imbriquées (threading), voir `repliesSection(for:)`.
    @State private var expandedReplies: [Int: [Comment]] = [:]
    @State private var loadingReplyIds: Set<Int> = []
    /// Port du panneau cadeau (`giftPanel`) — voir `giftSheet`/`sendGift` (V5-F-048).
    @State private var showGiftPicker = false
    @State private var selectedGift: String?
    @State private var isSendingGift = false
    @State private var giftError: String?

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
                    // Port de `btn_gift` (`MyBottomSheetDialogFragment.java:94-131`) — visible
                    // UNIQUEMENT si `FirebaseConfigManager.allowGiftCommenter()`. **Ajouté le
                    // 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-048, Phase B P2)** — le
                    // panneau cadeau-commentaire était entièrement absent côté iOS.
                    if TiinverFirebaseConfigManager.shared.allowGiftCommenter {
                        Button { showGiftPicker = true } label: { Image(systemName: "gift") }
                    }
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
            .sheet(isPresented: $showGiftPicker) { giftSheet }
            .alert(
                "Échec de l'envoi", isPresented: Binding(get: { giftError != nil }, set: { if !$0 { giftError = nil } })
            ) {
                Button("OK", role: .cancel) { giftError = nil }
            } message: {
                Text(giftError ?? "")
            }
        }
    }

    /// Port du panneau cadeau (`giftPanel`/`GridLayoutManager(4)`/`GiftAdapter`) —
    /// **ajouté le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-048, Phase B P2)**.
    private var giftSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Solde : \(Int(UserSession.shared.coinsAmount)) pièces")
                    .font(.subheadline).foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(GiftCatalog.orderedGiftIds, id: \.self) { giftId in
                            let resolved = GiftCatalog.resolve(giftId)
                            Button {
                                selectedGift = giftId
                            } label: {
                                VStack(spacing: 4) {
                                    Text(resolved?.emoji ?? "🎁").font(.system(size: 32))
                                    Text("\(resolved?.price ?? 0)").font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedGift == giftId ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                                )
                            }
                        }
                    }
                    .padding()
                }
                if let selectedGift, let resolved = GiftCatalog.resolve(selectedGift) {
                    let canAfford = Double(resolved.price) <= UserSession.shared.coinsAmount
                    VStack(spacing: 8) {
                        Text("\(resolved.emoji)  \(resolved.price) pièces")
                        if isSendingGift {
                            ProgressView()
                        } else {
                            Button("Envoyer") { Task { await sendGift(giftId: selectedGift, price: resolved.price) } }
                                .disabled(!canAfford)
                            if !canAfford {
                                Text("Solde insuffisant").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.bottom)
                }
            }
            .navigationTitle("Envoyer un cadeau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { showGiftPicker = false } }
            }
        }
    }

    /// Port de `sendGiftComment`/`onPost` (branche cadeau) — **ajouté le 2026-08-26
    /// (MIGRATION_PARITY_AUDIT_V5.md V5-F-048, Phase B P2)**.
    ///
    /// **Vérification financière** : le contrôle d'affordabilité (`gift.getPrice() >
    /// userCoinBalance`) est fait dans `giftSheet` (désactive le bouton "Envoyer", comme
    /// `btnSendGift.setEnabled(canAfford)` côté Android) — répété ici comme garde défensive avant
    /// tout appel réseau. `UserSession.shared.coinsAmount` n'est décrémenté qu'APRÈS un succès
    /// serveur CONFIRMÉ (`isBackendSuccess`), jamais avant, jamais de façon optimiste — fidèle à
    /// `onPost` Android : `userCoinBalance -= data.getGiftPrice()` n'existe QUE dans la branche
    /// `Result.SUCCESS` de `debitCoins`, jamais avant l'envoi. Sur échec, AUCUNE mutation de solde
    /// (le `userCoinBalance += price` d'Android dans sa branche `ERROR` est un no-op réel — le
    /// solde n'a jamais été décrémenté avant cet appel sur ce chemin, rien à rembourser ; ni
    /// persisté via `Settings.setFloatPreference` sur cette branche côté Android non plus).
    private func sendGift(giftId: String, price: Int) async {
        guard let myId = UserSession.shared.myId, let receiverId = postActorId else { return }
        guard Double(price) <= UserSession.shared.coinsAmount else { return }
        isSendingGift = true
        defer { isSendingGift = false }
        do {
            try await CommentRepository.shared.sendGift(
                activityId: activityId, userId: myId, giftId: giftId, receiverId: receiverId, amount: price
            )
            UserSession.shared.coinsAmount -= Double(price)
            showGiftPicker = false
            selectedGift = nil
            offset = 0
            comments = []
            await loadMore()
        } catch {
            giftError = "L'envoi du cadeau a échoué — réessaie ou annule."
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
