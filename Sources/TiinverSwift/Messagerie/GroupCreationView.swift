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

    /// **Corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md V3-F-069 GROUPS-06, P1)** — contradit
    /// délibérément la conclusion initiale du finding (qui affirmait qu'Android utilise
    /// 250/500/1250/2500/5000, valeurs QUE CE FICHIER N'A JAMAIS UTILISÉES). Vérifié directement
    /// dans `Group.java` (module Android `contacts`) : ces 5 valeurs ne sont que les LIBELLÉS
    /// AFFICHÉS du spinner (`prixList`, lignes 188-192) — le prix RÉELLEMENT soumis au serveur
    /// (`price`, ligne 203/286) vient d'une méthode complètement différente,
    /// `getPrice(int position)` (lignes 508-533), indexée sur la position du spinner (0-4, PAS les
    /// valeurs affichées) : position 0 → `default` → 100 ; position 1 → `case 1` → 100 ; position 2
    /// → `case 2` → 200 ; position 3 → `case 3` → 400 ; position 4 → `case 4` → 500. C'est un bug
    /// Android réel (libellé "5000" soumet en fait 500), mais le résultat NUMÉRIQUE réellement
    /// transmis au serveur ne peut donc JAMAIS être autre chose que {100, 200, 400, 500} — les cases
    /// 5/6/7 (700/800/1000) du switch sont du code mort, un spinner à 5 éléments ne produit jamais
    /// une position ≥5. La version précédente de cette liste (`[100, 200, 400, 500, 700, 800,
    /// 1000]`) était donc déjà correcte sur les 4 premières valeurs, mais exposait 3 choix
    /// (700/800/1000) qu'aucun utilisateur Android ne peut jamais produire — retirés pour une
    /// fidélité stricte au comportement RÉEL (pas au bug d'étiquetage, qu'il n'y a aucune raison de
    /// reproduire côté iOS puisque ce fichier n'affiche jamais de libellé trompeur).
    private let priceOptions = [100, 200, 400, 500]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Form {
                Section {
                    HStack {
                        // Port de l'icône appareil-photo affichée dans le champ de nom (capture
                        // d'écran) — Android n'a pas de vraie action de sélection d'avatar de
                        // groupe dans ce formulaire (confirmé, `GroupRepository.createGroup`
                        // envoie toujours `profile_picture` vide), purement décoratif ici aussi.
                        Image(systemName: "camera.fill").foregroundStyle(.secondary)
                        TextField("Tapez le sujet du groupe ici..", text: $groupName)
                    }
                }

                Section("type de groupe") {
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
                    LabeledContent("Lien d'invitation:") {
                        Text("https://tiinver.com/group/\(localToken)")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Membres (\(members.count))") {
                    ForEach(members) { member in
                        HStack(spacing: 10) {
                            CDNAsyncImage(url: URL(string: member.profile ?? ""), targetSize: CGSize(width: 32, height: 32)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
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

            // Port du FAB `btnCreateGrp` (capture d'écran : bouton rond rose bas-droite, icône
            // flèche d'envoi) — remplace l'icône de barre d'outils d'une version antérieure de ce
            // fichier, écart visuel réel corrigé.
            if isCreating {
                ProgressView()
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color(.systemBackground)))
                    .padding(.trailing, 20).padding(.bottom, 24)
            } else if !groupName.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { Task { await create() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(radius: 4)
                }
                .padding(.trailing, 20).padding(.bottom, 24)
            }
        }
        .navigationTitle("Nouveau groupe")
        .navigationBarTitleDisplayMode(.inline)
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
        print("SESSION: myId=\(UserSession.shared.myId ?? "nil") authenticated=\(UserSession.shared.isLoggedIn)")
        guard let myId = UserSession.shared.myId else {
            errorText = "Session invalide — reconnecte-toi puis réessaie."
            print("GROUP CREATE: aborted — UserSession.shared.myId is nil")
            return
        }
        isCreating = true
        errorText = nil
        defer { isCreating = false }
        print("GROUP CREATE REQUEST: endpoint=group name=\(groupName) isPrivate=\(isPrivate) isLucrative=\(isLucrative) members=\(members.count)")
        do {
            let group = try await GroupRepository.shared.createGroup(
                name: groupName.trimmingCharacters(in: .whitespaces),
                isPrivate: isPrivate, isLucrative: isLucrative, price: price, creatorId: myId
            )
            print("GROUP CREATE RESPONSE: success groupId=\(group.groupId) token=\(group.token)")
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
            print("GROUP CREATE RESPONSE: error=\(error)")
            errorText = "Impossible de créer le groupe : \(error.localizedDescription)"
        }
    }
}
