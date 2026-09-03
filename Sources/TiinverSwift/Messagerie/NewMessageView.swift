import SwiftUI

/// Port de `roster/NewMessage.java` (196 lignes, entier, 2026-08-18 P2 — confirmé `MISSING` par
/// l'audit V2, référencé depuis `RosterListView.swift`'s liens "Nouveau message" comme hors
/// périmètre jusqu'ici) — recherche d'un utilisateur par téléphone OU email pour démarrer une
/// conversation 1:1 directe (`isPhoneOrEmailExiste`, recherche EN DIRECT à chaque frappe,
/// `TextWatcher.onTextChanged`, pas de debounce côté Android — reproduit sans debounce non plus,
/// fidèle, l'endpoint étant un simple lookup léger).
///
/// **Écart assumé, documenté** : Android insère le PREMIER message directement en local
/// (`ContentValues`/`ContentProvider`, `infoContract.MSG_URI`) AVANT de naviguer vers `ActivityMsg`
/// — AUCUN appel réseau visible pour ce message précis dans ce fichier (dépend probablement d'une
/// synchronisation locale en tâche de fond, `MyBackgroundTask`, déjà explicitement hors périmètre
/// de ce portage ailleurs — voir `RosterListView.swift`/`GroupDetailView.swift`). Reproduire cette
/// insertion locale sans le mécanisme de sync qui la pousse réellement au serveur laisserait le
/// message strictement local, jamais livré — donc PAS reproduit ici : le texte tapé est transmis
/// en pré-remplissage à `ChatView`, qui envoie réellement le message via son pipeline `sendText()`
/// déjà fonctionnel (REST/Socket.IO) dès que l'utilisateur confirme depuis l'écran de conversation.
struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var message = ""
    @State private var foundUser: User?
    @State private var lookupFailed = false
    @State private var lookupTask: Task<Void, Never>?
    @State private var openChat = false

    private var rosterTarget: RosterModel? {
        guard let foundUser, let userId = foundUser.id else { return nil }
        var target = RosterModel()
        target.type = ChatType.chat.wireValue
        let nikname = [foundUser.firstname, foundUser.lastname].compactMap { $0 }.joined(separator: " ")
        target.nikname = nikname
        target.username = foundUser.username
        target.to = foundUser.username
        target.from = UserSession.shared.username
        target.userId = String(userId)
        target.sender = UserSession.shared.myId
        target.receiver = String(userId)
        // **Corrigé (2026-09-04, CHAT_CONSISTENCY_REVIEW.md)** — jamais assigné, laissant
        // `conversationId` vide sur toute conversation démarrée depuis cet écran. Port de
        // `ConversationIdGenerator.java` (déjà porté, `ConversationIdGenerator.swift`) : identifiant
        // déterministe (tri alphabétique des 2 participants), même calcul que celui déjà utilisé à
        // la réception (`ChatViewModel.swift:353`) et dans les autres flux de création (`MessageRepository.swift:131`).
        target.conversationId = ConversationIdGenerator.conversationId(currentUser: UserSession.shared.myId ?? "", remoteUser: String(userId))
        target.title = nikname
        target.subTitle = foundUser.username
        target.profile = foundUser.profile
        target.currentUsername = UserSession.shared.username
        target.currentUserId = UserSession.shared.myId
        target.currentNikname = UserSession.shared.nikname
        return target
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Téléphone ou email", text: $query)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: query) { _ in scheduleLookup() }
                        statusIcon
                    }
                }
                if foundUser != nil {
                    Section {
                        TextField("Message", text: $message, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("Nouveau message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Port de `mSend`/`click` — port de la garde `isUserExiste && !message.isEmpty()`.
                    Button("Envoyer") { openChat = true }
                        .disabled(foundUser == nil || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationDestination(isPresented: $openChat) {
                if let rosterTarget {
                    ChatView(target: rosterTarget, initialInputText: message)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if foundUser != nil {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue) // port de `ic_verified`
        } else if lookupFailed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red) // port de `ic_error_red_24dp`
        }
    }

    /// Port de `getUserByPhoneNumber` — appelé à chaque frappe (`onTextChanged`), sans debounce
    /// côté Android non plus (endpoint léger, un seul utilisateur recherché).
    private func scheduleLookup() {
        lookupTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { foundUser = nil; lookupFailed = false; return }
        lookupTask = Task {
            do {
                let user = try await ContactsRepository.shared.lookupByPhoneOrEmail(q)
                guard !Task.isCancelled else { return }
                foundUser = user
                lookupFailed = user == nil
            } catch {
                guard !Task.isCancelled else { return }
                foundUser = nil
                lookupFailed = true
            }
        }
    }
}
