import PhotosUI
import SwiftUI

/// Port de `messagerie/group/SettingGroupMessageFragmant.java` (740 lignes, entier) +
/// `GroupDetailActivity.java` (entier) — écran de gestion d'un groupe existant (GAP-011, audit du
/// 2026-08-16 : cet écran était ENTIÈREMENT absent côté iOS, `ChatView.swift` ne faisait que rendre
/// les messages système `deleteMember`/`groupDescriptionChanged` reçus, sans jamais permettre de les
/// déclencher).
///
/// **Simplification de portage documentée** : la liste des membres utilise l'endpoint réseau direct
/// `GET membership/{groupId}` (`GroupRepository.fetchMembers`) plutôt que la synchronisation locale
/// SQLite (`MyBackgroundTask`) qu'Android utilise réellement — cet endpoint existe côté serveur (le
/// code Android qui l'appelle directement est présent mais COMMENTÉ dans le fichier source lui-même,
/// voir `GroupRepository.swift`), reconstruire toute une couche de synchronisation locale pour ce
/// seul écran aurait été hors de proportion avec le gap réel à combler.
///
/// L'action "Message" du menu contextuel membre a été portée (V4-F-019, voir `memberRow`/
/// `chatTarget`). Le changement de photo de groupe a été porté (V4-F-025, voir `photoPickerItem`/
/// `uploadPhoto`) — `PhotosPicker` natif plutôt que `CustomGalleryView`+`CroperView`, même écart
/// d'architecture déjà assumé et documenté pour la photo de profil PERSONNELLE
/// (`ProfileView.swift` : Android recadre AVANT l'envoi, ici l'image est envoyée telle quelle).
struct GroupDetailView: View {
    let groupId: String
    /// Port de `ChangeGroupTopicActivity` (168 lignes, entier, 2026-08-18 P2) — `@State` plutôt
    /// que `let` (auparavant immuable, gap réel trouvé : le renommage du groupe n'avait aucune UI
    /// côté iOS) pour refléter immédiatement le nouveau nom après un renommage réussi, MÊME motif
    /// que `descriptionDraft`/`isEditingDescription` déjà en place pour la description.
    @State private var groupName: String
    let groupToken: String
    let groupType: String
    /// **CORRIGÉ le 2026-08-18 (P2)** : était `let`, donc l'en-tête restait figé sur l'ANCIENNE
    /// description après un renommage réussi via `submitDescription()` (jusqu'à re-navigation vers
    /// cet écran) — même classe de bug que `groupName` (voir sa doc ci-dessus), trouvée en
    /// appliquant le même motif de correction aux deux champs.
    @State private var groupDescription: String?
    /// **CORRIGÉ le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-025, Phase B P2)** — était `let`,
    /// même classe de bug déjà corrigée pour `groupName`/`groupDescription` (voir leur doc
    /// ci-dessus) : l'en-tête resterait figé sur l'ANCIENNE photo après un changement réussi sans
    /// cette mutabilité.
    @State private var groupProfile: String?
    /// Port de `lucrative`/`price` (`SettingGroupMessageFragmant.java:190-196`, V5-F-017) — pilote
    /// le panneau "Contenu restreint" ci-dessous, visible à TOUT membre (hors garde `IAM_ADMIN`).
    let lucrative: Int
    let price: Int

    @Environment(\.dismiss) private var dismiss
    @State private var members: [GroupMember] = []
    @State private var memberSearchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddMember = false
    @State private var isEditingDescription = false
    @State private var descriptionDraft = ""
    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var showLeaveConfirm = false
    @State private var memberActionTarget: GroupMember?
    @State private var showInviteShare = false
    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-022, Phase B P2)** — port de
    /// `GroupDetailActivity.onOptionsItemSelected` (`R.id.report`, `menu_group.xml:12-15`) :
    /// visible à TOUT membre (pas de garde admin sur cet item précis de menu, contrairement à
    /// `change_subject`). `ReportView` supportait déjà `reportType: "group"` mais n'était jamais
    /// instanciée depuis cet écran — gap de câblage pur.
    @State private var showReport = false
    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-019, Phase B P1)** — port de
    /// `SettingGroupMessageFragmant.showMemberIsNotAdminDialog` (`action_on_members_group_no_admin`,
    /// `strings.xml:453-455`, un seul item "Message") : dialogue à option unique proposé à un
    /// non-admin qui tape sur un AUTRE membre.
    @State private var messageOnlyTarget: GroupMember?
    @State private var chatDestination: RosterModel?
    @State private var openChat = false
    /// **Ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-025, Phase B P2)** — port de
    /// `profileContainer.setOnClickListener` (`SettingGroupMessageFragmant.java:197-247`, gardé
    /// `IAM_ADMIN`).
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    /// Port de l'aperçu optimiste `SettingGroupMessageFragmant.onUriResult` (V5-F-074) — bitmap
    /// local affiché IMMÉDIATEMENT au choix, avant même le début de l'upload réseau.
    @State private var pendingGroupAvatarImage: UIImage?

    init(groupId: String, groupName: String, groupToken: String, groupType: String, groupDescription: String?, groupProfile: String?, lucrative: Int = 0, price: Int = 0) {
        self.groupId = groupId
        _groupName = State(initialValue: groupName)
        self.groupToken = groupToken
        self.groupType = groupType
        _groupDescription = State(initialValue: groupDescription)
        _groupProfile = State(initialValue: groupProfile)
        self.lucrative = lucrative
        self.price = price
    }

    /// Port de `FilterGroupMemberList`'s `SearchView`/`filterMember` (410 lignes, entier — même
    /// écran de gestion des membres qu'ici, mais sourcé depuis la synchronisation locale SQLite au
    /// lieu de l'endpoint réseau direct déjà utilisé volontairement, voir note de tête de fichier ;
    /// SEULE différence fonctionnelle réelle après comparaison ligne à ligne : le filtre de
    /// recherche, ajouté ici plutôt que dupliquer tout l'écran pour cette unique différence).
    private var filteredMembers: [GroupMember] {
        guard !memberSearchText.isEmpty else { return members }
        return members.filter { $0.displayName.localizedCaseInsensitiveContains(memberSearchText) || ($0.username ?? "").localizedCaseInsensitiveContains(memberSearchText) }
    }

    private var currentUserId: Int? { UserSession.shared.myId.flatMap { Int($0) } }
    private var currentMember: GroupMember? { members.first { $0.userId == currentUserId } }
    private var isCurrentUserAdmin: Bool { currentMember?.isAdmin ?? false }
    /// Port de `InviteLinkActivity.java:74` — construction CLIENT-SIDE, aucun appel réseau requis
    /// pour générer le lien lui-même (Android ne fait un `POST updategroup` que pour poster le
    /// message "lien partagé" dans la conversation, pas pour générer le lien).
    private var inviteLink: URL? { URL(string: "https://tiinver.com/group/\(groupToken)") }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    groupAvatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(groupName).font(.headline)
                        Text(groupDescription?.isEmpty == false ? groupDescription! : "Aucune description") // R.string equivalent non identifié
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if isCurrentUserAdmin {
                    Button("Modifier le nom") { // ChangeGroupTopicActivity
                        nameDraft = groupName
                        isEditingName = true
                    }
                    Button("Modifier la description") { // add_group_description
                        descriptionDraft = groupDescription ?? ""
                        isEditingDescription = true
                    }
                }
            }

            // Port de `container_static_info` (`SettingGroupMessageFragmant.java:190-196`,
            // V5-F-017) — visible à TOUT membre (PAS de garde `IAM_ADMIN` sur ce bloc précis,
            // contrairement à la section invite/ajout ci-dessous), affiché dès que `lucrative==1`.
            if lucrative == 1 {
                Section {
                    Text("🔒 Contenu restreint") // Restricted_content
                    Text("Ce groupe est accessible uniquement aux abonnés.") // only_subscribers
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Abonnement : \(price) jetons/mois") // subscription + price + coins_per_month
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if isCurrentUserAdmin {
                Section {
                    Button { showInviteShare = true } label: { Label("Lien d'invitation", systemImage: "link") } // invite_link
                    Button { showAddMember = true } label: { Label("Ajouter des participants", systemImage: "person.badge.plus") } // add_participants
                }
            }

            Section("Membres (\(members.count))") { // memberCount
                if isLoading {
                    ProgressView()
                } else {
                    ForEach(filteredMembers) { member in
                        memberRow(member)
                    }
                }
            }

            Section {
                Button("Quitter le groupe", role: .destructive) { showLeaveConfirm = true } // R.id.exit
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("Infos du groupe")
        .navigationBarTitleDisplayMode(.inline)
        // Port de `FilterGroupMemberList`'s `SearchView` — voir `filteredMembers` en tête de fichier.
        .searchable(text: $memberSearchText, prompt: "Rechercher un membre")
        .task { await loadMembers() }
        .refreshable { await loadMembers() }
        // Port de `menu_group.xml`/`GroupDetailActivity.onOptionsItemSelected` (`R.id.report`) —
        // V4-F-022.
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Signaler le groupe", systemImage: "flag") { showReport = true }
            }
        }
        .navigationDestination(isPresented: $showReport) {
            ReportView(targetId: groupId, username: groupName, reportType: "group")
        }
        .sheet(isPresented: $showAddMember) {
            AddGroupMemberView(groupId: groupId, existingMemberIds: Set(members.map(\.userId))) {
                Task { await loadMembers() }
            }
        }
        .sheet(isPresented: $isEditingName) {
            NavigationStack {
                Form {
                    TextField("Nom du groupe", text: $nameDraft)
                }
                .navigationTitle("Nom du groupe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { isEditingName = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") { Task { await submitName() } }
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingDescription) {
            NavigationStack {
                Form {
                    TextField("Description", text: $descriptionDraft, axis: .vertical)
                }
                .navigationTitle("Description")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { isEditingDescription = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") { Task { await submitDescription() } }
                    }
                }
            }
        }
        .sheet(isPresented: $showInviteShare) {
            if let inviteLink { ShareSheet(items: [inviteLink]) }
        }
        // Port de `showMemberDialog` (`action_on_members_group`/`action_on_members_group_admin`,
        // `strings.xml:443-451` — "Message" TOUJOURS en premier, avant le rôle/retrait) — menu
        // contextuel admin, 3 actions.
        .confirmationDialog("Gérer ce membre", isPresented: Binding(get: { memberActionTarget != nil }, set: { if !$0 { memberActionTarget = nil } }), presenting: memberActionTarget) { member in
            Button("Message") { openChatWithMember(member); memberActionTarget = nil }
            Button(member.isAdmin ? "Retirer le rôle admin" : "Nommer administrateur") {
                Task { await toggleAdmin(member) }
            }
            Button("Retirer du groupe", role: .destructive) { Task { await remove(member) } }
            Button("Annuler", role: .cancel) {}
        }
        // Port de `showMemberIsNotAdminDialog` (`action_on_members_group_no_admin`, un seul item
        // "Message") — menu contextuel non-admin, 1 action.
        .confirmationDialog("Ce membre", isPresented: Binding(get: { messageOnlyTarget != nil }, set: { if !$0 { messageOnlyTarget = nil } }), presenting: messageOnlyTarget) { member in
            Button("Message") { openChatWithMember(member); messageOnlyTarget = nil }
            Button("Annuler", role: .cancel) {}
        }
        .navigationDestination(isPresented: $openChat) {
            if let chatDestination { ChatView(target: chatDestination) }
        }
        .alert("Quitter le groupe ?", isPresented: $showLeaveConfirm) {
            Button("Quitter", role: .destructive) { Task { await leaveGroup() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Quitter \"\(groupName)\" ?") // port du libellé `GroupDetailActivity.onOptionsItemSelected` (R.id.exit)
        }
        .onChange(of: photoPickerItem) { item in
            guard let item else { return }
            Task {
                guard let raw = try? await item.loadTransferable(type: Data.self), let uiImage = UIImage(data: raw),
                    let jpegData = uiImage.jpegData(compressionQuality: 0.9)
                else { return }
                pendingGroupAvatarImage = uiImage
                await uploadPhoto(jpegData)
                pendingGroupAvatarImage = nil
                photoPickerItem = nil
            }
        }
    }

    /// Port de `profileContainer` (avatar de groupe, `SettingGroupMessageFragmant.java:197-247`) —
    /// tapable UNIQUEMENT pour un admin (`if (IAM_ADMIN) { ...galerie+crop... }`), même garde côté
    /// iOS. `PhotosPicker` enveloppe directement l'avatar (comme `ProfileView.avatar`) plutôt qu'un
    /// bouton séparé superposé.
    ///
    /// **Corrigé le 2026-08-26 (MIGRATION_PARITY_AUDIT_V5.md V5-F-074, Phase B P2)** — même
    /// correctif que `ProfileView.avatar` : `pendingGroupAvatarImage` prend la priorité d'affichage
    /// tant que non-nil, fidèle à `onUriResult` qui affiche le bitmap AVANT `sendFotoPerfilToServer`.
    @ViewBuilder
    private var groupAvatar: some View {
        let image: AnyView
        if let pendingGroupAvatarImage {
            image = AnyView(Image(uiImage: pendingGroupAvatarImage).resizable().aspectRatio(contentMode: .fill))
        } else {
            image = AnyView(
                CDNAsyncImage(url: groupProfile.flatMap(URL.init), targetSize: CGSize(width: 56, height: 56)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    if isUploadingPhoto {
                        ProgressView()
                    } else {
                        Color(.tertiarySystemFill)
                    }
                }
            )
        }
        let framed = image
            .frame(width: 56, height: 56).clipShape(Circle())

        if isCurrentUserAdmin {
            PhotosPicker(selection: $photoPickerItem, matching: .images) { framed }
                .disabled(isUploadingPhoto)
        } else {
            framed
        }
    }

    /// Port de `sendFotoPerfilToServer` (`SettingGroupMessageFragmant.java:628-738`, entier) —
    /// upload multipart direct vers `updategroup` (PAS BunnyCDN, voir `GroupRepository.updatePhoto`),
    /// puis même motif "écho local immédiat" déjà établi par `submitName`/`submitDescription`
    /// ci-dessous : `groupProfile` mis à jour EN PREMIER (l'en-tête reflète le changement
    /// immédiatement, comme Android `ChargerImages.glidLoadAvatar` dans le callback `Onresponse`),
    /// puis message système `groupPictureChanged` inséré localement (`mlib.setProfile(fotoPath)`
    /// côté Android — reproduit via `groupProfile` déjà à jour au moment de l'appel).
    private func uploadPhoto(_ imageData: Data) async {
        guard let myId = UserSession.shared.myId, let apiKey = UserSession.shared.apiKey else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let url = try await GroupRepository.shared.updatePhoto(groupId: groupId, creatorId: myId, apiKey: apiKey, imageData: imageData)
            groupProfile = url
            await insertSystemMessage(verb: "groupPictureChanged", text: UserSession.shared.username ?? "")
        } catch {
            errorMessage = "Échec du changement de photo."
        }
    }

    @ViewBuilder
    private func memberRow(_ member: GroupMember) -> some View {
        HStack {
            CDNAsyncImage(url: member.profile.flatMap(URL.init), targetSize: CGSize(width: 36, height: 36)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Color(.tertiarySystemFill) }
                .frame(width: 36, height: 36).clipShape(Circle())
            VStack(alignment: .leading) {
                Text(member.displayName)
                if member.isAdmin { Text("Administrateur").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Port du `if (IAM_ADMIN) showMemberDialog(...) else showMemberIsNotAdminDialog(...)`
            // (`onItemClick`, `SettingGroupMessageFragmant.java:162-172`) — un admin obtient le menu
            // à 3 actions (Message/rôle/retrait), un non-admin obtient le menu à 1 action (Message
            // seul), tous deux CÂBLÉS maintenant (V4-F-019) — plus de tap mort pour un non-admin.
            guard member.userId != currentUserId else { return }
            if isCurrentUserAdmin {
                memberActionTarget = member
            } else {
                messageOnlyTarget = member
            }
        }
    }

    /// Port de `Adapter.sendMessage(pos)` (`messagerie/group/Adapter.java:119-144`) — construit le
    /// `RosterModel` d'une conversation 1:1 (`type=CHAT`, pas `group`) avec les mêmes champs que
    /// l'original (`nikname`/`username`/`userId`/`profile`/`from`=utilisateur courant/`to`=membre
    /// ciblé), même motif déjà établi par `ProfileView.messageTarget`/`NewMessageView.rosterTarget`.
    private func chatTarget(for member: GroupMember) -> RosterModel? {
        guard let username = member.username else { return nil }
        var target = RosterModel()
        target.type = ChatType.chat.wireValue
        target.nikname = member.nikname ?? member.displayName
        target.username = username
        target.to = username
        target.from = UserSession.shared.username
        target.currentUsername = UserSession.shared.username
        target.currentUserId = UserSession.shared.myId
        target.userId = String(member.userId)
        target.title = target.nikname
        target.subTitle = username
        target.profile = member.profile
        return target
    }

    private func openChatWithMember(_ member: GroupMember) {
        guard let target = chatTarget(for: member) else { return }
        chatDestination = target
        openChat = true
    }

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await GroupRepository.shared.fetchMembers(groupId: groupId)
        } catch {
            errorMessage = "Impossible de charger les membres."
        }
    }

    private func toggleAdmin(_ member: GroupMember) async {
        guard let myId = UserSession.shared.myId else { return }
        memberActionTarget = nil
        do {
            try await GroupRepository.shared.updateMemberRole(userId: member.userId, groupId: groupId, creatorId: myId, makeAdmin: !member.isAdmin)
            await loadMembers()
        } catch {
            errorMessage = "Échec de la mise à jour du rôle."
        }
    }

    /// Port de `deleteGroupMemebers` — retrait réseau puis écho système local immédiat (même motif
    /// que `GroupCreationView.create()`, `dbInsertMessageCrossPoint(..., false)` côté Android).
    private func remove(_ member: GroupMember) async {
        guard let myId = UserSession.shared.myId, let myUsername = UserSession.shared.username else { return }
        memberActionTarget = nil
        do {
            try await GroupRepository.shared.removeMember(userId: member.userId, groupId: groupId, creatorId: myId)
            members.removeAll { $0.id == member.id }
            await insertSystemMessage(verb: "deleteMember", text: "\(myUsername)/\(member.username ?? "")")
        } catch {
            errorMessage = "Échec du retrait du membre."
        }
    }

    private func submitDescription() async {
        guard let myId = UserSession.shared.myId, let apiKey = UserSession.shared.apiKey else { return }
        isEditingDescription = false
        do {
            try await GroupRepository.shared.updateDescription(descriptionDraft, groupId: groupId, creatorId: myId, apiKey: apiKey)
            groupDescription = descriptionDraft
            await insertSystemMessage(verb: "groupDescriptionChanged", text: "\(UserSession.shared.username ?? "")/\(descriptionDraft)")
        } catch {
            errorMessage = "Échec de la mise à jour de la description."
        }
    }

    /// Port de `ChangeGroupTopicActivity.updateGroup` — MÊME motif que `submitDescription`
    /// ci-dessus, `column="name"`/`verb="groupNameChanged"`.
    private func submitName() async {
        guard let myId = UserSession.shared.myId, let apiKey = UserSession.shared.apiKey else { return }
        isEditingName = false
        do {
            try await GroupRepository.shared.updateName(nameDraft, groupId: groupId, creatorId: myId, apiKey: apiKey)
            groupName = nameDraft
            await insertSystemMessage(verb: "groupNameChanged", text: "\(UserSession.shared.username ?? "")/\(nameDraft)")
        } catch {
            errorMessage = "Échec du renommage du groupe."
        }
    }

    private func leaveGroup() async {
        guard let myId = UserSession.shared.myId, let apiKey = UserSession.shared.apiKey else { return }
        do {
            try await GroupRepository.shared.leaveGroup(groupId: groupId, userId: myId, apiKey: apiKey)
            dismiss()
        } catch {
            errorMessage = "Échec de la sortie du groupe."
        }
    }

    /// Port de `GroupRepository.dbInsertMessageCrossPoint(..., false)` (Android) — même motif déjà
    /// établi par `GroupCreationView.create()` (module 11) : écho local immédiat d'un message
    /// système, pas d'attente du round-trip serveur/socket pour que l'auteur de l'action le voie.
    private func insertSystemMessage(verb: String, text: String) async {
        guard let myId = UserSession.shared.myId else { return }
        var systemMessage = MessageLib()
        systemMessage.messageId = myId + String(Int64(Date().timeIntervalSince1970 * 1000))
        systemMessage.conversationId = ConversationIdGenerator.groupConversationId(currentUser: myId, remoteUser: groupId)
        systemMessage.type = ChatType.group.wireValue
        systemMessage.groupType = groupType
        systemMessage.groupId = groupId
        systemMessage.groupName = groupName
        systemMessage.token = groupToken
        systemMessage.profile = groupProfile
        systemMessage.username = UserSession.shared.username
        systemMessage.nikname = UserSession.shared.nikname
        systemMessage.message = text
        systemMessage.verb = verb
        systemMessage.object = "information"
        systemMessage.status = 0
        systemMessage.vu = "false"
        systemMessage.regroupage = groupToken
        systemMessage.stamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        try? await MessageRepository().insertTextMessage(systemMessage)
    }
}

/// `UIActivityViewController` minimal — partage natif du lien d'invitation, aucun équivalent
/// SwiftUI natif compatible `deploymentTarget: 16.0` (le `ShareLink` natif est iOS 16+ mais son API
/// `Transferable` générique est plus contrainte pour un simple `URL`) — motif déjà utilisé ailleurs
/// dans ce portage pour le partage natif de publication.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
