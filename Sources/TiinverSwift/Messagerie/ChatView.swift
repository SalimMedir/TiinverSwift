import SwiftUI

/// Port de l'écran `ChatFragmentTest.java` (mise en page `chat_salon.xml`, pas lue en détail — XML
/// non fourni, structure reconstruite depuis les `findViewById` observés : liste de messages,
/// barre de saisie `MessageEventLayout`, bandeau de citation, indicateur en ligne/frappe, barre
/// d'outils de sélection multiple). `ChatViewModel` porte la logique ; cette vue porte
/// l'agencement.
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @ObservedObject private var callCoordinator: CallCoordinator = .shared
    @State private var showGifPicker = false
    @State private var showGiftPicker = false
    @State private var showAttachmentPicker = false
    @State private var showShareboard = false
    @State private var showMessageGraphicCompose = false
    @FocusState private var inputFocused: Bool

    init(target: RosterModel) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(target: target))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if let quote = viewModel.quote {
                quoteBar(quote)
            }
            inputBar
        }
        .navigationTitle(viewModel.target.isGroup ? (viewModel.target.groupName ?? "") : (viewModel.target.nikname ?? viewModel.target.to ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await viewModel.loadInitial() }
        // Port du bouton d'appel (`R.id.call`/`mListener.onArticleSelected(8,null)`, jamais câblé
        // dans `ChatFragmentTest.java` lui-même — le point d'entrée réel n'a pas été identifié dans
        // les 3080 lignes lues, probablement ailleurs dans la barre d'outils XML non fournie).
        // Câblé ici directement sur `CallCoordinator.startOutgoingCall`, module 12, plutôt que
        // deviné à partir d'un fichier non lu.
        .fullScreenCover(isPresented: Binding(get: { callCoordinator.state != .idle }, set: { _ in })) {
            CallView(coordinator: callCoordinator)
        }
        // Port de `PermissionRequest.java:62-99` (refus explicite signalé à l'utilisateur) — l'appel
        // sortant refusé pour permission micro ne quitte jamais `.idle` (voir
        // `CallCoordinator.startOutgoingCall`), donc `CallView` (gardé par `state != .idle`
        // ci-dessus) ne s'affiche jamais pour ce cas : l'alerte doit vivre ICI, pas dans `CallView`.
        .alert(
            "Micro requis", isPresented: Binding(
                get: { callCoordinator.micPermissionDenied },
                set: { if !$0 { callCoordinator.acknowledgeMicPermissionDenied() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Autorise l'accès au micro dans Réglages pour passer ou recevoir des appels.")
        }
        // Port du point d'entrée Shareboard (`R.id.shareboard`/`mListener.onArticleSelected(9,…)`,
        // pas plus identifié que celui de l'appel dans les 3080 lignes lues de
        // `ChatFragmentTest.java` — câblé directement sur `FragmentPbs.newInstance`, module 13).
        .fullScreenCover(isPresented: $showShareboard) {
            ShareboardView(profile: outgoingCallProfile, receiver: shareboardReceiver, chatType: viewModel.target.type, status: 1)
        }
        // Port du point d'entrée `FragmentMessageGraphic` (module 14).
        .sheet(isPresented: $showMessageGraphicCompose) {
            MessageGraphicComposeView { payload in viewModel.sendGraphic(payload: payload) }
        }
        .safeAreaInset(edge: .top, alignment: .center) {
            if let typing = viewModel.typingUsername {
                // Port de `onTyping(String)`/`subTitleView.setText(R.string.typing)`.
                Text("\(typing) est en train d'écrire…") // R.string.typing
                    .font(.caption2).foregroundStyle(.secondary)
            } else if viewModel.isPeerOnline, !viewModel.target.isGroup {
                // Port de `OnlineView`/`userOnLine`/`userOffLine`.
                Text("En ligne")
                    .font(.caption2).foregroundStyle(.green)
            }
        }
    }

    // MARK: - Liste (port de `mRecycleView`/`MessageListAdapter`)

    private var messageList: some View {
        List {
            ForEach(viewModel.items) { item in
                row(for: item)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear {
                        // Port de `onScrolled` (`!canScrollVertically(-1)`) : ici, approximé par
                        // l'apparition du PREMIER élément affiché (haut de la liste inversée).
                        if item.id == viewModel.items.first?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func row(for item: ChatListItem) -> some View {
        switch item {
        case .message(let mlib):
            messageRow(mlib)
        case .dateSeparator(_, _, let text):
            DateSeparatorRow(text: text)
        case .groupHeader(_, let description):
            GroupHeaderRow(description: description)
        case .subscriptionRequired(_, let groupName, let price):
            // R.string.subscribe_title / R.string.renewable_monthly
            SubscriptionBannerRow(title: "\(groupName) — abonnement \(price) pièces/mois", isRenewal: false) {}
        case .subscriptionRenewal(_, let price):
            SubscriptionBannerRow(title: "Renouveler pour \(price) pièces", isRenewal: true) {}
        }
    }

    /// Port de `getItemViewType` — `"information"` (10)/`"shareboard"` (13) → bandeaux non
    /// cliquables (`InformationViewHolder`/`ShareBordInformationViewHolder`) ; `"missedvoicecall"`
    /// (14)/`"voicecall"` (15) → LES DEUX rendus par `MissedViewHolder` (même layout,
    /// `missed_call_msg_layout`), cliquables, déclenchant `ResultData.CALL` →
    /// `mListener.onArticleSelected(8,null)` (écran d'appel, module 12).
    @ViewBuilder
    private func messageRow(_ mlib: MessageLib) -> some View {
        switch mlib.object {
        case "information", "shareboard":
            SystemInfoRow(text: systemInfoText(for: mlib))
        case "missedvoicecall", "voicecall":
            MissedCallBubbleRow(message: mlib, text: systemInfoText(for: mlib)) { }
        default:
            ChatBubbleRow(
                message: mlib, isGroup: viewModel.target.isGroup,
                onAppearEffects: { viewModel.handleAppear(of: mlib) },
                onTapQuoteSwipe: { viewModel.startQuote(for: mlib) },
                onTapMedia: { _ in },
                onLongPress: { if let id = mlib.messageId { viewModel.toggleSelection(id) } }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.isSelecting, let id = mlib.messageId { viewModel.toggleSelection(id) }
            }
            .listRowBackground(
                (mlib.messageId.map(viewModel.selection.contains) ?? false) ? Color.accentColor.opacity(0.12) : Color.clear
            )
        }
    }

    /// Port de `getInformationWithGoodVersion`/`getInformation`/`getInformation126` — dispatch par
    /// `verb`, deux formats selon `versionCode` (l'ancien format encodait nom+groupe DANS le texte
    /// via une regex `StringManager.parseString`, l'ancien format n'est PAS reproduit ici : les
    /// champs `from`/`groupName` structurés sont TOUJOURS disponibles côté serveur actuel, viser
    /// l'ancien format `<127` ajouterait de la complexité pour des messages historiques déjà rares).
    private func systemInfoText(for mlib: MessageLib) -> String {
        switch mlib.verb {
        case "createGroup", "deleteGroup":
            return "\(mlib.from ?? "") a créé le groupe \"\(mlib.groupName ?? "")\""
        case "addMember":
            return "\(mlib.from ?? "") a ajouté \"\(mlib.to ?? "")\""
        case "deleteMember":
            return "\(mlib.from ?? "") a retiré \"\(mlib.to ?? "")\""
        case "joinGroup":
            return "\(mlib.from ?? "") a rejoint \"\(mlib.groupName ?? "")\""
        case "leftGroup":
            return "\(mlib.from ?? "") a quitté \"\(mlib.groupName ?? "")\""
        case "groupNameChanged":
            return "\(mlib.from ?? "") a renommé le groupe \"\(mlib.groupName ?? "")\""
        case "groupPictureChanged":
            return "\(mlib.from ?? "") a changé la photo du groupe"
        case "groupDescriptionChanged":
            return "\(mlib.from ?? "") a changé la description \"\(mlib.description ?? "")\""
        case "shareboard":
            return "\(mlib.from ?? "") a partagé un tableau"
        case "missedvoicecall":
            return "Appel manqué" // R.string.missedvoicecall
        case "voicecall":
            return "Appel vocal" // R.string.voicecall
        default:
            return ""
        }
    }

    // MARK: - Bandeau de citation (port de `showQuotedMessage`/`hideReplyLayout`/`QuoteView`)

    private func quoteBar(_ quote: ChatViewModel.QuoteState) -> some View {
        HStack {
            Rectangle().fill(Color.accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.title).font(.caption).bold()
                Text(quote.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { viewModel.cancelQuote() } label: { Image(systemName: "xmark.circle.fill") }
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.default, value: viewModel.quote)
    }

    // MARK: - Barre de saisie (port de `MessageEventLayout` — champ texte, boutons gif/gift/média)

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Port de `pickImageOrVideo`/`pickMedia` (`ChatFragmentTest.java`, lu en entier,
            // GAP-004 2026-08-15) — icône séparée non identifiée dans les 3080 lignes lues (bouton
            // déclencheur hors du fragment, probablement `chat_salon.xml` non fourni), branchée ici
            // sur un trombone, motif déjà établi ailleurs dans ce portage pour les points d'entrée
            // non localisés précisément (ex. bouton d'appel, Shareboard — voir commentaires
            // `outgoingCallProfile`/`showShareboard`).
            Button { showAttachmentPicker = true } label: { Image(systemName: "paperclip") }
            Button { showGifPicker = true } label: { Image(systemName: "face.smiling") } // onDisplayGif
            Button { showGiftPicker = true } label: { Image(systemName: "gift") } // onDisplayGift
            TextField("Message", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onChange(of: viewModel.inputText) { _ in viewModel.onTextChanged() }
            Button {
                viewModel.sendText()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
        .background(.bar)
        // Port de `onDisplayGif`/`StickerPickerDialog` et `onDisplayGift`/`GiftGalleryView` — les
        // deux écrans-pickers eux-mêmes N'ONT PAS été lus cette passe (fichiers séparés,
        // `StickerPickerDialog.java`/`GiftGalleryView.java`) ; câblés ici via une feuille minimale
        // pour ne pas bloquer l'envoi de texte, contenu réel différé.
        .sheet(isPresented: $showGifPicker) {
            Text("Sélecteur de GIF/stickers — à porter (StickerPickerDialog.java non lu)")
                .padding()
        }
        .sheet(isPresented: $showGiftPicker) {
            GiftPickerPlaceholder { giftId in
                viewModel.sendGift(giftId: giftId)
                showGiftPicker = false
            }
        }
        // Port de `pickMedia` (`ActivityResultContracts.PickVisualMedia`, `ImageAndVideo` — même
        // filtre que `GalleryPickerView`, réutilisé tel quel plutôt qu'un second picker dédié).
        .sheet(isPresented: $showAttachmentPicker) {
            GalleryPickerView(
                onImagePicked: { url in
                    showAttachmentPicker = false
                    viewModel.attachMedia(url: url, isVideo: false)
                },
                onVideoPicked: { url in
                    showAttachmentPicker = false
                    viewModel.attachMedia(url: url, isVideo: true)
                },
                onCancel: { showAttachmentPicker = false }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isSelecting {
            ToolbarItem(placement: .navigationBarLeading) {
                Text("\(viewModel.selection.count)")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    viewModel.deleteSelectedForMe()
                } label: { Image(systemName: "trash") }
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    callCoordinator.startOutgoingCall(profile: outgoingCallProfile, chatType: viewModel.target.type)
                } label: { Image(systemName: "phone.fill") }
                .disabled(callCoordinator.state != .idle)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showShareboard = true } label: { Image(systemName: "person.2.wave.2.fill") } // R.id.pbdId (Shareboard)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showMessageGraphicCompose = true } label: { Image(systemName: "scribble.variable") } // Message Graphic
            }
        }
    }

    /// Port de `FragmentPbs.RECEIVER` — identifiant de salon transmis au serveur (même champ
    /// `to`/`username` que la signalisation d'appel, voir `outgoingCallProfile`).
    private var shareboardReceiver: String { viewModel.target.to ?? viewModel.target.username ?? "" }

    /// Port des champs de `Profile p` construits juste avant `startService(CallService...)` dans
    /// `ChatManager`/les points d'appel non identifiés (bouton d'appel jamais localisé dans les
    /// 3080 lignes lues de `ChatFragmentTest.java`) — reconstruit ici depuis `RosterModel`
    /// (l'identité de conversation déjà disponible côté `ChatView`), champs alignés sur ceux QUE
    /// `lunchcall`/`lunchcall`-side utilisent réellement (`messageId`/`username`/`nikname`/
    /// `chatType`, voir `ChatRepository.handleNewMessage`, module 11).
    private var outgoingCallProfile: ChatProfile {
        var profile = ChatProfile()
        profile.messageId = UserSession.shared.myId.map { $0 + String(Int64(Date().timeIntervalSince1970 * 1000)) }
        profile.username = viewModel.target.isGroup ? nil : viewModel.target.to
        profile.nikname = viewModel.target.nikname
        profile.to = viewModel.target.to
        profile.receiver = viewModel.target.userId
        profile.conversationId = viewModel.target.conversationId
        profile.chatType = viewModel.target.type
        profile.groupId = viewModel.target.groupId
        profile.token = viewModel.target.token
        profile.groupName = viewModel.target.groupName
        return profile
    }
}

/// Sélecteur de cadeau minimal — le catalogue (`GiftCatalog`) est réel et vérifié, l'écran
/// `GiftGalleryView.java` (mise en page complète, achat/recharge) n'a pas été lu cette passe.
private struct GiftPickerPlaceholder: View {
    let onSelect: (String) -> Void
    private let giftIds = [
        "gift_thumb_name", "gift_fire_name", "gift_rose_name", "gift_love_name", "gift_rainbow_name",
        "gift_pearl_name", "gift_first_name", "gift_car_name", "gift_gold_name", "gift_elite_name",
        "gift_diamond_name", "gift_crown_name",
    ]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))]) {
                ForEach(giftIds, id: \.self) { id in
                    Button { onSelect(id) } label: {
                        VStack {
                            Text(GiftCatalog.emoji(for: id)).font(.largeTitle)
                            Text("\(GiftCatalog.price(for: id))").font(.caption2)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
