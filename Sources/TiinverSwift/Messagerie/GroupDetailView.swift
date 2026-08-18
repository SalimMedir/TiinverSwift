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
/// **Non porté ici, gap restant documenté** : changement de photo de groupe (Android :
/// `CustomGalleryView`+`CroperView`+upload multipart type=4 vers `updategroup`) et lien d'un membre
/// vers une conversation privée directe (Android : action "Message" du menu contextuel membre) —
/// tous deux secondaires par rapport au cœur du gap (membres/rôles/description/lien d'invitation).
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
    let groupProfile: String?

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

    init(groupId: String, groupName: String, groupToken: String, groupType: String, groupDescription: String?, groupProfile: String?) {
        self.groupId = groupId
        _groupName = State(initialValue: groupName)
        self.groupToken = groupToken
        self.groupType = groupType
        _groupDescription = State(initialValue: groupDescription)
        self.groupProfile = groupProfile
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
                    CDNAsyncImage(url: groupProfile.flatMap(URL.init)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color(.tertiarySystemFill) }
                        .frame(width: 56, height: 56).clipShape(Circle())
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
        // Port de `showMemberDialog`/`showMemberIsNotAdminDialog` — menu contextuel à 2 actions
        // (promouvoir/rétrograder, retirer) pour un admin, RIEN pour un non-admin (l'action
        // "Message" — ouvrir une conversation privée avec ce membre — n'est pas portée, voir
        // avertissement de tête de fichier).
        .confirmationDialog("Gérer ce membre", isPresented: Binding(get: { memberActionTarget != nil }, set: { if !$0 { memberActionTarget = nil } }), presenting: memberActionTarget) { member in
            Button(member.isAdmin ? "Retirer le rôle admin" : "Nommer administrateur") {
                Task { await toggleAdmin(member) }
            }
            Button("Retirer du groupe", role: .destructive) { Task { await remove(member) } }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Quitter le groupe ?", isPresented: $showLeaveConfirm) {
            Button("Quitter", role: .destructive) { Task { await leaveGroup() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Quitter \"\(groupName)\" ?") // port du libellé `GroupDetailActivity.onOptionsItemSelected` (R.id.exit)
        }
    }

    @ViewBuilder
    private func memberRow(_ member: GroupMember) -> some View {
        HStack {
            CDNAsyncImage(url: member.profile.flatMap(URL.init)) { image in
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
            // Port du `if (IAM_ADMIN) showMemberDialog(...) else showMemberIsNotAdminDialog(...)` —
            // seul un admin obtient un menu d'actions ; un non-admin qui tape sur un membre n'a
            // qu'un menu "Message" (non porté, voir tête de fichier), donc rien n'est présenté ici.
            guard isCurrentUserAdmin, member.userId != currentUserId else { return }
            memberActionTarget = member
        }
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
