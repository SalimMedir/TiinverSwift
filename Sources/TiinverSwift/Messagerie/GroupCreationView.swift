import SwiftUI

/// Port de `contacts/Group.java` (lu en entier, 2026-08-15) — étape 2 de la création de groupe :
/// nom, confidentialité (privé/public), option lucrative + prix, lien d'invitation (généré
/// localement depuis le `token`, comme Android — `String.format("https://tiinver.com/group/%s",
/// token)`, PAS un appel serveur), récapitulatif des membres choisis à l'étape 1, bouton d'envoi
/// (FAB `btnCreateGrp` → `onButtonPressed()`).
struct GroupCreationView: View {
    let members: [GroupMemberCandidate]

    @State private var groupName = ""
    @State private var isPrivate = true
    @State private var isLucrative = false
    @State private var price = 100
    @State private var isCreating = false
    @State private var errorText: String?
    @State private var createdTarget: RosterModel?
    @State private var showCreatedChat = false

    /// Port de `token = String.valueOf(System.currentTimeMillis())` (généré à l'ouverture du
    /// fragment, PAS au moment de l'envoi) — le lien d'invitation affiché est donc dérivé de ce
    /// jeton local, indépendant de la vraie création serveur (qui utilise CE MÊME token comme champ
    /// `token` du `POST group`).
    @State private var localToken = String(Int64(Date().timeIntervalSince1970 * 1000))

    private let priceOptions = [100, 200, 400, 500, 700, 800, 1000]

    var body: some View {
        Form {
            Section {
                TextField("Tapez le sujet du groupe ici..", text: $groupName)
            }

            Section("Type de groupe") {
                Picker("Type de groupe", selection: $isPrivate) {
                    Text("privé").tag(true)
                    Text("public").tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Toggle("groupe à but lucratif", isOn: $isLucrative)
                if isLucrative {
                    Picker("Prix (pièces/mois)", selection: $price) {
                        ForEach(priceOptions, id: \.self) { Text("\($0)") }
                    }
                }
            }

            Section {
                LabeledContent("Lien d'invitation") {
                    Text("https://tiinver.com/group/\(localToken)")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Membres (\(members.count))") {
                ForEach(members) { member in
                    HStack(spacing: 10) {
                        AsyncImage(url: URL(string: member.profile ?? "")) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                            Circle().fill(Color(.secondarySystemBackground))
                        }
                        .frame(width: 32, height: 32).clipShape(Circle())
                        Text(member.displayName)
                    }
                }
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .navigationTitle("Nouveau groupe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isCreating {
                    ProgressView()
                } else {
                    Button { Task { await create() } } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationDestination(isPresented: $showCreatedChat) {
            if let createdTarget { ChatView(target: createdTarget) }
        }
    }

    /// Port de `Group.onButtonPressed()` — `POST group`, puis `POST membership` par membre
    /// sélectionné, puis message système local "créer groupe" (port de
    /// `GroupRepository.dbInsertMessageCrossPoint`, réutilise `MessageRepository.insertTextMessage`
    /// qui met déjà à jour `wk_roster` — même chemin de code que les messages normaux, pas dupliqué),
    /// puis navigation vers la conversation créée (port de la construction `RosterModel` +
    /// `Intent(ActivityMsg.class)`).
    private func create() async {
        guard let myId = UserSession.shared.myId else { return }
        isCreating = true
        errorText = nil
        defer { isCreating = false }
        do {
            let group = try await GroupRepository.shared.createGroup(
                name: groupName.trimmingCharacters(in: .whitespaces),
                isPrivate: isPrivate, isLucrative: isLucrative, price: price, creatorId: myId
            )
            await GroupRepository.shared.addMembers(members, toGroupId: group.groupId, inviterId: myId)

            let conversationId = ConversationIdGenerator.groupConversationId(currentUser: myId, remoteUser: group.groupId)
            var systemMessage = MessageLib()
            systemMessage.messageId = myId + String(Int64(Date().timeIntervalSince1970 * 1000))
            systemMessage.conversationId = conversationId
            systemMessage.type = ChatType.group.wireValue
            systemMessage.token = group.token
            systemMessage.groupId = group.groupId
            systemMessage.groupName = group.name
            systemMessage.userId = myId
            systemMessage.username = UserSession.shared.username
            systemMessage.from = UserSession.shared.username
            systemMessage.object = "information"
            systemMessage.verb = "createGroup"
            systemMessage.profile = group.profile
            systemMessage.description = group.description
            systemMessage.stamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            try? await MessageRepository().insertTextMessage(systemMessage)

            var target = RosterModel()
            target.conversationId = conversationId
            target.type = ChatType.group.wireValue
            target.token = group.token
            target.groupId = group.groupId
            target.groupName = group.name
            target.title = group.name
            target.profile = group.profile
            target.description = group.description
            target.groupMember = true
            target.currentUserId = myId
            target.currentUsername = UserSession.shared.username
            target.currentNikname = UserSession.shared.nikname
            createdTarget = target
            showCreatedChat = true
        } catch {
            errorText = "Impossible de créer le groupe. Réessaie."
        }
    }
}
