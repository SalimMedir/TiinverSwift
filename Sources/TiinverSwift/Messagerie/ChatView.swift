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
    @State private var showDeleteOptions = false
    @State private var showGroupDetail = false
    /// **CORRIGÉ le 2026-08-18 (P1)** : ce bouton menait AUPARAVANT directement à `ProfileView`,
    /// documenté comme un raccourci volontaire faute d'avoir porté l'écran de réglages complet
    /// (`setting/SettingPrivateMessageFragmant.java`, hébergé par `ProfileDetailActivity`, MÊME
    /// Activity que `SettingGroupMessageFragmant`/`GroupDetailView.swift` juste au-dessus selon
    /// `chatType`). Cet écran est maintenant porté (`PrivateMessageSettingView.swift`) — le
    /// raccourci direct-vers-profil devient une simple rangée DEDANS cet écran (`profile_btn`),
    /// fidèle à la hiérarchie réelle Android (`ActivityMsg.titleContainer` → `ProfileDetailActivity`
    /// → `SettingPrivateMessageFragmant` → `profile_btn` → `UserProfile`), pas un accès direct.
    @State private var showPrivateMessageSettings = false
    @FocusState private var inputFocused: Bool
    // V5-F-033 (Phase B P1-15) — enregistrement/envoi de messages vocaux, voir `inputBar` et
    // `VoiceRecorder.swift`.
    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var isStartingVoiceRecording = false
    @State private var voiceRecordPermissionDenied = false

    /// `initialInputText` — port de `NewMessage.mMessage` (`roster/NewMessage.java`, 2026-08-18 P2) :
    /// Android pré-remplit le champ de saisie AVANT le premier envoi (l'utilisateur tape le message
    /// sur l'écran de recherche, PAS dans le champ de `ActivityMsg` lui-même) — reproduit en
    /// pré-remplissant `inputText` du `ChatViewModel` fraîchement créé, envoi réel laissé au VRAI
    /// pipeline `sendText()` déjà existant plutôt que dupliqué (voir note de `NewMessageView.swift`
    /// sur l'insertion locale directe `ContentValues` d'Android, délibérément PAS reproduite).
    init(target: RosterModel, initialInputText: String = "") {
        let vm = ChatViewModel(target: target)
        vm.inputText = initialInputText
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if let quote = viewModel.quote {
                quoteBar(quote)
            }
            // Port de `block_layout.setVisibility(VISIBLE)` (`ChatFragmentTest.java`, voir
            // `ChatViewModel.checkGroupSubscription`, V3-F-070 P1) — composeur remplacé par un
            // message tant qu'un abonnement groupe payant n'est pas résolu, comme Android masque
            // entièrement la barre de saisie derrière `block_layout`.
            if viewModel.isComposerBlocked {
                Text("Abonne-toi pour continuer à participer à ce groupe.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.bar)
            } else {
                inputBar
            }
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
        //
        // **Corrigé (V5-F-001, 2026-08-24)** — la présentation de `CallView` elle-même
        // (`.fullScreenCover(isPresented: callCoordinator.state != .idle)`) a été déplacée vers
        // `RootRouterView.swift`, seul point TOUJOURS monté quel que soit l'écran affiché
        // (`AndroidManifest.xml:347-353`/`CallService.java:571-617` : `CallActivity`/
        // `IncomingCallActivity` sont des Activities système lancées par un Service via
        // `FLAG_ACTIVITY_NEW_TASK`, donc atteignables depuis N'IMPORTE QUEL écran, jamais
        // dépendantes d'un Fragment particulier). La présenter seulement ici la rendait
        // inatteignable dès que l'utilisateur n'était pas précisément sur LE ChatView de la
        // conversation en cours d'appel.
        //
        // Port de `PermissionRequest.java:62-99` (refus explicite signalé à l'utilisateur) — l'appel
        // sortant refusé pour permission micro ne quitte jamais `.idle` (voir
        // `CallCoordinator.startOutgoingCall`), donc `CallView` ne s'affiche jamais pour ce cas :
        // cette alerte reste ICI (pas dans `CallView`/`RootRouterView`) car le bouton d'appel
        // sortant qui la déclenche vit sur CET écran — l'utilisateur regarde déjà ChatView au
        // moment du refus.
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
        .confirmationDialog("Supprimer \(viewModel.selection.count) message(s)", isPresented: $showDeleteOptions, titleVisibility: .visible) {
            Button("Supprimer pour moi") { viewModel.deleteSelectedForMe() }
            Button("Supprimer pour tout le monde", role: .destructive) { viewModel.deleteSelectedForEveryone() }
            Button("Annuler", role: .cancel) {}
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
        // Port du point d'entrée "infos du groupe" (`GroupDetailActivity`, GAP-011, audit du
        // 2026-08-16) — tap sur le titre de la conversation pour un groupe, comme
        // `ChatFragmentTest`'s en-tête de toolbar cliquable menant vers `GroupDetailActivity`.
        .sheet(isPresented: $showGroupDetail) {
            NavigationStack {
                GroupDetailView(
                    groupId: viewModel.target.groupId ?? "", groupName: viewModel.target.groupName ?? "",
                    groupToken: viewModel.target.token ?? "", groupType: viewModel.target.groupType ?? "",
                    groupDescription: viewModel.target.description, groupProfile: viewModel.target.profile,
                    // Port du panneau "Contenu restreint" (V5-F-017) — absent jusqu'ici de ce site d'appel.
                    lucrative: viewModel.target.lucrative, price: viewModel.target.price
                )
            }
        }
        // Port de `ProfileDetailActivity` (branche `chatType="chat"`, voir déclaration de
        // `showPrivateMessageSettings` ci-dessus) — équivalent 1:1 de `showGroupDetail` ci-dessus.
        .sheet(isPresented: $showPrivateMessageSettings) {
            NavigationStack {
                PrivateMessageSettingView(
                    displayTitle: viewModel.target.nikname ?? viewModel.target.username ?? viewModel.target.to ?? "",
                    username: viewModel.target.username ?? viewModel.target.to ?? "",
                    userId: viewModel.target.userId
                )
            }
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

    /// **Corrigé (V5-F-018, 2026-08-24)** — port de `mLayoutManager.setStackFromEnd(true)`
    /// (positionnement initial) + `mRecycleView.smoothScrollToPosition(getItemCount()-1)` (appelé
    /// par `addMessage`, à chaque nouveau message envoyé/reçu en direct — `ChatFragmentTest.java:
    /// 2678-2717`). Vérifié précisément côté Android que la pagination (`displayMoreMessageOnScroll`,
    /// prépend en tête de liste) N'APPELLE PAS ce scroll — seuls le chargement initial et un AJOUT
    /// EN FIN de liste ramènent la vue vers le bas, la RecyclerView préserve nativement la position
    /// de lecture pendant un scroll-up de pagination. `ScrollViewReader` + `.onChange(of: items.
    /// last?.id)` reproduit exactement cette distinction : le dernier item ne change JAMAIS lors
    /// d'un `loadMore()` (qui insère au DÉBUT, `items.insert(contentsOf:at: 0)`), donc ce signal ne
    /// se déclenche que pour le chargement initial et les ajouts en fin de liste (message envoyé
    /// via `appendOptimistic`, reçu en direct via `onIncoming`) — jamais pour la pagination.
    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.items) { item in
                    row(for: item)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .id(item.id)
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
            .onChange(of: viewModel.items.last?.id) { lastId in
                guard let lastId else { return }
                withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
            }
        }
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
        case .subscriptionRequired(let id, let groupName, let groupId, let creatorId, let price):
            // R.string.subscribe_title / R.string.renewable_monthly
            SubscriptionBannerRow(
                title: "\(groupName) — abonnement \(price) pièces/mois", isRenewal: false,
                isLoading: viewModel.pendingSubscriptionItemIds.contains("sub-\(id)")
            ) {
                viewModel.resolveGroupSubscription(itemId: id, groupId: groupId, creatorId: creatorId, price: price, isRenewal: false)
            }
        case .subscriptionRenewal(let id, let groupId, let creatorId, let price):
            SubscriptionBannerRow(
                title: "Renouveler pour \(price) pièces", isRenewal: true,
                isLoading: viewModel.pendingSubscriptionItemIds.contains("renew-\(id)")
            ) {
                viewModel.resolveGroupSubscription(itemId: id, groupId: groupId, creatorId: creatorId, price: price, isRenewal: true)
            }
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
            // Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-019, Phase B P1-9) — un tap
            // sur cette bulle relance un appel sortant côté Android (MissedViewHolder.java:15-39 →
            // ChatFragmentTest.java:561-563 → ActivityMsg.java:516-518, case 8: startCall(), même
            // action que le bouton d'appel de la barre d'outils), fermeture auparavant vide.
            MissedCallBubbleRow(message: mlib, text: systemInfoText(for: mlib)) {
                guard callCoordinator.state == .idle else { return }
                callCoordinator.startOutgoingCall(profile: outgoingCallProfile, chatType: viewModel.target.type)
            }
        default:
            ChatBubbleRow(
                message: mlib, isGroup: viewModel.target.isGroup,
                hasDownloadFailed: mlib.messageId.map(viewModel.failedDownloadMessageIds.contains) ?? false,
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
            // Port de `MessageEventLayout` — l'enregistrement remplace tout le
            // `messageViewContainer` par `recordView` (`safeSetVisibility`, `startRecording`/
            // `endRecord`) — reproduit ici en substituant tout le contenu de la barre plutôt que de
            // n'assourdir qu'une icône, fidèle à Android.
            if voiceRecorder.isRecording {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
                Text(Self.formattedRecordingDuration(voiceRecorder.elapsedSeconds))
                    .font(.callout.monospacedDigit())
                Spacer()
                Text("‹ glisser pour annuler") // port du hint de glissement de `RecordView`
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Port de `pickImageOrVideo`/`pickMedia` (`ChatFragmentTest.java`, lu en entier,
                // GAP-004 2026-08-15) — icône séparée non identifiée dans les 3080 lignes lues
                // (bouton déclencheur hors du fragment, probablement `chat_salon.xml` non fourni),
                // branchée ici sur un trombone, motif déjà établi ailleurs dans ce portage pour les
                // points d'entrée non localisés précisément (ex. bouton d'appel, Shareboard — voir
                // commentaires `outgoingCallProfile`/`showShareboard`).
                Button { showAttachmentPicker = true } label: { Image(systemName: "paperclip") }
                Button { showGifPicker = true } label: { Image(systemName: "face.smiling") } // onDisplayGif
                Button { showGiftPicker = true } label: { Image(systemName: "gift") } // onDisplayGift
                TextField("Message", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onChange(of: viewModel.inputText) { _ in viewModel.onTextChanged() }
            }
            micOrSendButton
        }
        .padding(8)
        .background(.bar)
        // V5-F-033 (Phase B P1-15) — même motif que l'alerte "Micro requis" existante des appels
        // (`callCoordinator.micPermissionDenied`), source distincte (`VoiceRecorder`).
        .alert("Micro requis", isPresented: $voiceRecordPermissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Autorisez l'accès au micro dans Réglages pour envoyer un message vocal.")
        }
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

    // MARK: - Message vocal (V5-F-033, Phase B P1-15) — port du bouton morphant Android
    // (`OnRecordClickListener`/`OnRecordListener` de `MessageEventLayout` : tap = envoyer le texte
    // si non vide, appui maintenu = enregistrer si vide, glissement = annuler).

    @ViewBuilder
    private var micOrSendButton: some View {
        if voiceRecorder.isRecording || viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty {
            Image(systemName: voiceRecorder.isRecording ? "mic.circle.fill" : "mic.circle")
                .font(.title2)
                .foregroundStyle(voiceRecorder.isRecording ? Color.red : Color.accentColor)
                .gesture(voiceRecordGesture)
        } else {
            Button {
                viewModel.sendText()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
        }
    }

    /// Port de `OnRecordListener.onStart`/`onFinish`/`onCancel` — `DragGesture(minimumDistance: 0)`
    /// détecte l'appui initial dès `onChanged` (déclenche `startRecording`, gardé par
    /// `isStartingVoiceRecording` pour ne démarrer qu'une fois malgré les rappels continus du
    /// glissement) ; `onEnded` distingue annulation (glissement franc vers la gauche, port du geste
    /// `RecordView` "glisser pour annuler") d'envoi normal.
    private var voiceRecordGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !voiceRecorder.isRecording, !isStartingVoiceRecording else { return }
                isStartingVoiceRecording = true
                Task {
                    let started = await voiceRecorder.start()
                    isStartingVoiceRecording = false
                    if !started { voiceRecordPermissionDenied = true }
                }
            }
            .onEnded { value in
                guard voiceRecorder.isRecording else { return }
                if value.translation.width < -80 {
                    voiceRecorder.cancel()
                } else if let result = voiceRecorder.stop() {
                    viewModel.sendMedia(
                        object: "audio", localFileURI: result.url.absoluteString,
                        width: nil, height: nil, duration: String(result.durationMillis))
                }
            }
    }

    private static func formattedRecordingDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isSelecting {
            ToolbarItem(placement: .navigationBarLeading) {
                Text("\(viewModel.selection.count)")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                // Port du dialogue à 2 choix affiché après sélection + suppression
                // (`ChatFragmentTest.java:2493-2521`) — "supprimer pour moi" (retrait local) vs
                // "supprimer pour tout le monde" (visible par le correspondant, `deletemessage`
                // via socket). `deleteSelectedForEveryone()` était déjà entièrement câblé côté
                // ViewModel/Repository (garde `belongsToCurrentUser` déjà présente) mais n'avait
                // AUCUN point d'entrée UI avant ce tour — trouvé par un audit dédié, PAS une
                // fonctionnalité nouvelle inventée ici.
                Button(role: .destructive) {
                    showDeleteOptions = true
                } label: { Image(systemName: "trash") }
            }
        } else {
            if viewModel.target.isGroup {
                // Port de l'en-tête cliquable de `ChatFragmentTest`/`ActivityMsg` menant à
                // `GroupDetailActivity` (GAP-011) — ajouté EN PLUS du bouton d'appel existant, pas à
                // sa place : le point d'entrée réel du bouton d'appel n'a jamais été localisé dans
                // les 3080 lignes lues de `ChatFragmentTest.java` (voir commentaire de
                // `outgoingCallProfile` plus bas), donc aucune preuve qu'il soit masqué pour un
                // groupe côté Android — ne pas le retirer sans preuve.
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showGroupDetail = true } label: { Image(systemName: "info.circle") }
                }
            } else if viewModel.target.userId != nil {
                // Port de `profile_btn` — équivalent 1:1 du bouton "info.circle" ci-dessus.
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPrivateMessageSettings = true } label: { Image(systemName: "person.circle") }
                }
            }
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
