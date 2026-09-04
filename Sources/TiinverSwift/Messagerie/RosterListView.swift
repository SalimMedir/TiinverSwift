import SwiftUI

/// Port de `roster/ui/Roster.java` (lu en entier, 761 lignes) — écran-liste des conversations,
/// explicitement laissé de côté à la clôture du module 11 ("écran de liste des conversations...
/// fichier séparé, hors périmètre explicite de cette passe — `RosterModel` accepté en entrée, prêt
/// à être branché"). Ce fichier ferme ce gap : charge `wk_roster` (déjà porté, module 2,
/// `RosterRepository.rosterAll()`), affiche chaque conversation triée par `stamp` DESCENDANT —
/// fidèle au résultat FINAL affiché côté Android (le `CursorLoader` trie ASC en SQL, mais
/// `Roster.sortIt()` re-trie ensuite DESC en mémoire juste avant l'affichage ; seul cet ordre final
/// est reproduit ici, pas la requête SQL intermédiaire).
///
/// **PAS porté, décision de portée** (comme le reste de ce portage lorsqu'un sous-écran nécessite sa
/// propre passe de lecture dédiée) : sélection multiple/suppression (`ToolBarActionCompound`,
/// `RosterListAdapter.itemSelected`) ; assistant IA (`TiinverGeminiAIChat`, hors périmètre
/// `TIINVER_IOS_PORT_ANALYSIS.md`) ; présence en ligne/indicateur de frappe (`Roster.
/// organizeAndDisplayMessage`, distinct du point suivant). Recherche d'une conversation existante et
/// navigation vers `ChatView` sont portés.
///
/// **Corrigé (2026-09-04, CHAT_CONSISTENCY_REVIEW.md)** — "mise à jour temps réel de la liste... non
/// câblé" ci-dessus n'est plus vrai : un nouveau message reçu pendant que cet écran est affiché
/// relance désormais `viewModel.refresh()` via `ChatRepository.chatEvents` (voir `.onReceive` dans
/// `body`), même mécanisme déjà utilisé par le badge de l'onglet Chat (`HomeShellView.swift`). Reste
/// un `refresh()` complet (pas une mise à jour incrémentale ciblée sur la seule conversation
/// concernée) — fidèle au bouton manuel préexistant, pas une optimisation ajoutée au passage.
///
/// **Création de groupe portée le 2026-08-15** (test Appetize réel, GAP fonctionnel) — port de
/// `Contact.class` (FAB `GoToContact`) : voir `ContactPickerView.swift`/`GroupCreationView.swift`.
/// **Parité UI avec Android confirmée par capture d'écran (2026-08-16)** — le point d'entrée réel
/// de la création de groupe est un FAB rose bas-droite (icône personnes+plus), PAS l'icône de
/// barre d'outils utilisée dans une version antérieure de ce fichier (`person.2.badge.plus` en
/// `.navigationBarTrailing`) : capture Android montre clairement `Roster.java`'s FAB `GoToContact`
/// (lignes 84,133-144, déjà identifié par le commentaire d'origine, mais le choix "convention
/// native, pas de FAB flottant standard en SwiftUI" s'est avéré être un ÉCART VISUEL réel gênant
/// la découverte du bouton, pas une simplification neutre — corrigé pour correspondre exactement).
/// La capture montre aussi 2 liens texte roses sous la liste des conversations ("+ Nouveau
/// message", "+ Invitez vos amis et votre famille") — "Nouveau message" ouvre désormais
/// `NewMessageView.swift` (2026-08-18, P2, `roster/NewMessage.java` porté — recherche téléphone/
/// email pour un chat 1:1 direct, confirmée `MISSING` par l'audit V2, corrige le stub léger vers
/// `ContactPickerView` utilisé jusqu'ici en attendant). "Invitez vos amis" reste le gap contacts
/// déjà documenté (`CNContactStore` non porté).
struct RosterListView: View {
    @StateObject private var viewModel = RosterListViewModel()
    @State private var showContactPicker = false
    /// Port de `Roster.java:437` (icône loupe de la toolbar) → `RechercheTiinver` en mode
    /// `tokenSearch="chat"` — voir `ChatSearchView.swift` (2026-08-18, P1, recherche de
    /// groupe/conversation, confirmée `MISSING` par l'audit V2).
    @State private var showChatSearch = false
    /// Port de "+ Nouveau message" (`NewMessage.java`) — voir `NewMessageView.swift`.
    @State private var showNewMessage = false
    /// **Ajouté (2026-09-04, diagnostic temporaire)** — voir `SocketDiagnosticsView`.
    @State private var showSocketDiagnostics = false

    var body: some View {
        Group {
            if viewModel.rows.isEmpty && viewModel.hasLoaded {
                emptyState
            } else {
                List {
                    ForEach(viewModel.rows) { row in
                        NavigationLink {
                            ChatView(target: row.rosterModel)
                        } label: {
                            RosterRowView(row: row)
                        }
                    }
                    footerLinks
                }
                .listStyle(.plain)
            }
        }
        // R.string.chat = "Chats" (chaîne Android réelle, reprise verbatim) — teinte rose de
        // marque, fidèle à la capture (titre rendu dans la couleur d'accent, pas noir/systeme).
        .navigationTitle("Chats")
        .toolbar {
            // Port de `action_AI`/`action_AI2` (`Roster.java:443-445`) — voir `AIChatView.swift`,
            // 2026-08-18 P2, confirmé `PARTIAL` par l'audit V2 (seule la couche de stockage était
            // déjà portée).
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { AIChatView() } label: {
                    Image(systemName: "sparkles")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showChatSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
            // **Ajouté (2026-09-04, diagnostic temporaire — audit "conversation instantanée")** —
            // voir `SocketDiagnosticsView`, à retirer une fois la cause confirmée/corrigée.
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSocketDiagnostics = true
                } label: {
                    Image(systemName: "stethoscope")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Port du FAB `GoToContact` (`Roster.java:84,133-144`).
            Button { showContactPicker = true } label: {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(radius: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .navigationDestination(isPresented: $showContactPicker) {
            ContactPickerView()
        }
        // Présenté en modal (`.sheet`), PAS en push (`navigationDestination`) — `ChatSearchView`
        // porte sa propre `NavigationStack`/bouton "Fermer" (écran de recherche autonome, fidèle à
        // Android où `RechercheTiinver` est une Activity séparée avec sa propre pile de retour, pas
        // un simple fragment inséré dans la pile de `Roster`).
        .sheet(isPresented: $showChatSearch) {
            ChatSearchView(rosterViewModel: viewModel)
        }
        .sheet(isPresented: $showNewMessage) {
            NewMessageView()
        }
        .sheet(isPresented: $showSocketDiagnostics) {
            SocketDiagnosticsView()
        }
        .task { await viewModel.refresh() }
        // **Corrigé (2026-09-04, CHAT_CONSISTENCY_REVIEW.md)** — "mise à jour temps réel de la
        // liste... non câblé, refresh() manuel via le bouton toolbar en attendant" (voir doc de tête
        // de ce fichier). Même mécanisme déjà câblé pour le badge de l'onglet Chat
        // (`HomeShellView.swift`, `ChatRepository.chatEvents` publie `.message(meta)` à chaque
        // nouveau message privé/groupe, persistance Core Data déjà `await`ée avant l'émission) —
        // réutilisé ici tel quel plutôt qu'une seconde architecture temps réel : un message reçu
        // pendant que cet écran est affiché relance le même `refresh()` que le bouton manuel.
        .onReceive(ChatRepository.shared.chatEvents) { event in
            guard case .message = event else { return }
            Task { await viewModel.refresh() }
        }
        .onChange(of: showContactPicker) { presented in
            // Reflète immédiatement le nouveau groupe dans la liste dès qu'on revient (pas
            // d'observation temps réel de `wk_roster`, voir réserves de portée ci-dessus).
            if !presented { Task { await viewModel.refresh() } }
        }
        .onChange(of: showNewMessage) { presented in
            if !presented { Task { await viewModel.refresh() } }
        }
    }

    /// Port des 2 liens texte roses sous la liste (`Roster.java`, capture d'écran) — "Nouveau
    /// message" ouvre `NewMessageView` (recherche téléphone/email dédiée, `NewMessage.java`,
    /// 2026-08-18 P2) ; "Invitez vos amis" route vers `ReferralView` (déjà porté, module 15) —
    /// lien d'invitation générique, fidèle à l'intention du texte même si le flux contacts natif
    /// reste absent.
    private var footerLinks: some View {
        Section {
            Button { showNewMessage = true } label: {
                Label("Nouveau message", systemImage: "plus.circle.fill")
            }
            .foregroundStyle(Color.accentColor)
            NavigationLink {
                ReferralView()
            } label: {
                Label("Invitez vos amis et votre famille", systemImage: "person.badge.plus")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .listRowSeparator(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "message").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Aucune conversation").foregroundStyle(.secondary)
            Button { showNewMessage = true } label: {
                Label("Nouveau message", systemImage: "plus.circle.fill")
            }
            NavigationLink {
                ReferralView()
            } label: {
                Label("Invitez vos amis et votre famille", systemImage: "person.badge.plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RosterRowView: View {
    let row: RosterListViewModel.Row

    var body: some View {
        HStack(spacing: 12) {
            CDNAsyncImage(url: URL(string: row.profile ?? ""), targetSize: CGSize(width: 50, height: 50)) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Circle().fill(Color(.secondarySystemBackground))
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    // Port de `acuser`/`ic_acuser_0..3` — accusé de réception du dernier message
                    // ENVOYÉ, voir `RosterListViewModel.refresh()` pour le détail complet.
                    if let statusIconName = row.statusIconName {
                        Image(systemName: statusIconName)
                            .font(.caption2)
                            .foregroundStyle(statusIconName == "checkmark.circle.fill" ? Color.accentColor : Color.secondary)
                    }
                    Text(row.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                // Port de `stamp.setText(tps)` (`RosterListAdapter.java:279-282`) — heure du
                // dernier message, toujours affichée (pas seulement quand non lu).
                if !row.time.isEmpty {
                    Text(row.time).font(.caption2).foregroundStyle(.secondary)
                }
                if row.unreadCount > 0 {
                    Text("\(row.unreadCount)")
                        .font(.caption2.bold())
                        .padding(6)
                        .background(Circle().fill(.red))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
final class RosterListViewModel: ObservableObject {
    struct Row: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        let profile: String?
        let unreadCount: Int
        let stamp: String
        let rosterModel: RosterModel
        /// Port du texte du dernier message (V3-F-108, SEARCH complémentaire) — la donnée existait
        /// déjà (`model.message`) mais n'était exposée nulle part pour être filtrable, contrairement
        /// à `RechercheTiinver.java:666-668` qui filtre sur `title`/`message`/`subTitle` (3 champs,
        /// pas 2).
        let lastMessage: String?
        /// **Ajouté (2026-09-04)** — voir `RosterListViewModel.refresh()` pour le raisonnement
        /// complet (port de `StringUtils.getTime(long)`/`acuser`).
        let time: String
        let statusIconName: String?
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var hasLoaded = false

    private let repository = RosterRepository()

    /// Port de `Roster.messagePrivateRoster` (assemblage `Cursor` → `RosterModel`) + `Roster.
    /// sortIt()` (tri final DESC par `stamp`) — assemble chaque ligne `wk_roster` en un
    /// `RosterModel` prêt à être passé à `ChatView`, exactement comme `Roster.onItemClicked`
    /// transmet son `RosterModel` à `ActivityMsg` côté Android.
    ///
    /// **Corrigé le 2026-08-26 (V5-F-072, Phase B P1-30)** — `entity.lastMessage` (colonne
    /// dénormalisée, tenue à jour par `RosterRepository.updateRoster*`) est désormais l'unique
    /// source du texte affiché ; voir `RosterRepository.swift` pour le détail de la correction.
    func refresh() async {
        // Log de diagnostic temporaire (2026-08-16) — avant réception des captures Android, le
        // bouton "créer un groupe" avait été relu et confirmé présent/câblé (alors une icône de
        // toolbar) sans qu'aucun bug statique soit trouvé ; corrigé depuis en FAB fidèle à la
        // capture (voir doc de tête de fichier). Log laissé en place pour confirmer au prochain
        // test que l'écran est bien atteint et que `refresh()` s'exécute.
        print("ROSTER: refresh() started, myId=\(UserSession.shared.myId ?? "nil")")
        guard let entities = try? await repository.rosterAll() else {
            hasLoaded = true
            print("ROSTER: rosterAll() failed or returned nil")
            return
        }
        print("ROSTER: rosterAll() returned \(entities.count) rows")
        let currentUserId = UserSession.shared.myId ?? ""
        let currentUsername = UserSession.shared.username ?? ""
        let currentNikname = UserSession.shared.nikname ?? ""

        rows = entities.compactMap { entity -> Row? in
            guard let conversationId = entity.conversationId else { return nil }
            let type = entity.type ?? ChatType.chat.wireValue
            let isGroup = type == ChatType.group.wireValue
            let title = isGroup ? (entity.groupName ?? "") : (entity.nikname ?? entity.username ?? "")
            // Port de `R.string.groupinfo` — **corrigé le 2026-08-19 (MIGRATION_PARITY_AUDIT_V3.md
            // V3-F-006 SEARCH-06, P1)** : le commentaire précédent affirmait à tort que cette
            // chaîne n'était "pas traduite côté source non plus" — vérifié directement dans
            // `values-fr/strings.xml:313`, la vraie chaîne vue par un utilisateur Android en
            // français est "onglet ici pour les informations sur le groupe" (`values/strings.xml`
            // ne contient que le texte de développement anglais, `values-fr` le traduit
            // réellement) ; iOS affichait le texte de développement anglais brut à TOUS les
            // utilisateurs, jamais la traduction réelle.
            // Port de `RosterListAdapter.display` (`RosterListAdapter.java:315-393`, lu en entier
            // le 2026-09-04) — **étendu au switch COMPLET** (texte/audio/photo/gif/cadeau/
            // sticker/document/vidéo/graphique), au-delà du seul cas "gift" porté initialement
            // (item 6 de l'audit forensique). Chaînes FRANÇAISES réelles de `values-fr/strings.xml`
            // (`me`="moi", `photo`="photo", `document`="document", `audio`="audio",
            // `sticker`="sticker", `graphic`="Graphique", `video`="Vidéo", `gift`="cadeau"), pas
            // l'anglais de développement de `values/strings.xml`. Émojis en préfixe = substitut
            // d'icône (`mediaTitle.setCompoundDrawablesRelativeWithIntrinsicBounds`, Android utilise
            // un vrai drawable, cette ligne iOS n'affiche qu'un `Text` simple) — pas un ajout
            // arbitraire, un remplacement visuel de plateforme pour la MÊME information.
            //
            // Le cas "text" reproduit fidèlement `String.format("%s: %s..", R.string.me, s)`
            // (`RosterListAdapter.java:320-326`) : Android ajoute TOUJOURS ".." littéralement,
            // même quand le message n'a pas été tronqué (25 caractères pile) — pas "corrigé"
            // silencieusement ici.
            //
            // Branche `isGroup` INCHANGÉE (`R.string.groupinfo`, V3-F-006) — la ligne Android
            // équivalente n'a pas été revérifiée dans cette passe (portée volontairement limitée
            // aux conversations privées, seul contexte explicitement demandé), ne pas retoucher un
            // comportement déjà validé sans preuve nouvelle contradictoire.
            let subtitle: String
            if isGroup {
                subtitle = "onglet ici pour les informations sur le groupe"
            } else if entity.verb != "post" {
                // Port du `else` de `display()` (`:382-393`, `verb != "post"` → `getInformation`/
                // `getInformation126`, textes système type "X a créé le groupe") — non porté au
                // niveau de CETTE ligne (nécessiterait de dupliquer `ChatViewModel.systemInfoText`
                // ici), conserve le repli existant plutôt que d'inventer un texte système.
                subtitle = entity.username ?? ""
            } else {
                switch entity.object {
                case "text":
                    let raw = entity.lastMessage ?? ""
                    let truncated = raw.count > 20 ? String(raw.prefix(20)) : raw
                    subtitle = entity.belongsToCurrentUser == 1 ? "moi: \(truncated).." : "\(truncated).."
                case "audio": subtitle = "🎤 audio"
                case "photo": subtitle = "📷 photo"
                case "gif": subtitle = "🎞️ gif"
                case "gift": subtitle = "🎁 cadeau"
                case "sticker": subtitle = "🏷️ sticker"
                case "doc": subtitle = "📄 document"
                case "video": subtitle = "🎥 Vidéo"
                case "graphic": subtitle = "✏️ Graphique"
                default: subtitle = entity.username ?? ""
                }
            }
            // Port de `acuser`/`ic_acuser_0..3` (`RosterListAdapter.java:285-298`) — icône d'accusé
            // de réception, UNIQUEMENT pour les messages ENVOYÉS par l'utilisateur courant
            // (`isBelongsToCurrentUser() && verb=="post"`). `entity.status` suit l'échelle déjà
            // établie côté iOS (`MessageDeliveryStatus`, `ChatEvent.swift`) plutôt que l'échelle
            // Android 0-3 (elles ne correspondent pas terme à terme, voir doc de
            // `Row.statusIconName` ci-dessous) — simplifié en 3 états visuels façon WhatsApp
            // (horloge/un crochet/deux crochets) à la demande explicite de l'utilisateur pour ce
            // point précis, faute d'équivalent SF Symbol natif à un double-crochet Android exact.
            let statusIconName: String?
            if entity.belongsToCurrentUser == 1, entity.verb == "post" {
                switch entity.status {
                case 0: statusIconName = "clock"
                case 1: statusIconName = "checkmark"
                case 2, 3, 4: statusIconName = "checkmark.circle.fill"
                default: statusIconName = "checkmark"
                }
            } else {
                statusIconName = nil
            }
            // Port de `StringUtils.getTime(long)` (`:94-104`, PAS la variante relative
            // `getTime(Context,long)` — confirmé que `RosterListAdapter` utilise la variante SANS
            // contexte) — heure exacte du dernier message, format 12h. `DateFormatter` localisé
            // choisi plutôt qu'une reproduction octet-pour-octet du format "HH:mm, a. m." (détail
            // cosmétique mineur, pas fonctionnel) — s'adapte à la locale de l'utilisateur.
            let time: String
            if let stampMs = Double(entity.stamp ?? ""), stampMs > 0 {
                time = Self.timeFormatter.string(from: Date(timeIntervalSince1970: stampMs / 1000))
            } else {
                time = ""
            }

            var model = RosterModel()
            model.id = Int(entity.localId)
            model.conversationId = conversationId
            model.messageId = entity.messageId
            model.userId = entity.userId
            model.token = entity.token
            model.groupType = entity.groupType
            model.type = type
            model.groupName = entity.groupName
            model.username = entity.username
            model.nikname = entity.nikname
            model.groupId = entity.groupId
            model.stamp = entity.stamp
            model.message = entity.lastMessage
            model.object = entity.object
            model.verb = entity.verb
            model.status = Int(entity.status)
            model.profile = entity.profile
            model.title = title
            model.subTitle = subtitle
            model.groupMember = true
            model.vu = entity.unreadCount <= 0
            model.belongsToCurrentUser = entity.belongsToCurrentUser == 1
            model.unreadCount = Int(entity.unreadCount)
            model.creator = "1"
            model.description = entity.rosterDescription
            model.price = Int(entity.price)
            model.lucrative = Int(entity.lucrative)
            model.versionCode = Int(entity.versionCode)
            model.currentUserId = currentUserId
            model.currentUsername = currentUsername
            model.currentNikname = currentNikname
            model.from = currentUsername
            model.to = isGroup ? entity.token : entity.username

            return Row(
                id: model.id,
                title: title,
                subtitle: subtitle,
                profile: entity.profile,
                unreadCount: Int(entity.unreadCount),
                stamp: entity.stamp ?? "0",
                rosterModel: model,
                lastMessage: model.message,
                time: time,
                statusIconName: statusIconName
            )
        }
        .sorted { (Int64($0.stamp) ?? 0) > (Int64($1.stamp) ?? 0) }

        hasLoaded = true
        // Diagnostic temporaire (2026-09-04, audit "historique de conversation absent après
        // envoi") — voir `SocketDiagnostics` pour le raisonnement complet.
        SocketDiagnostics.shared.recordRosterRefresh(rowCount: rows.count)
    }

    /// Port de `StringUtils.getTime(long)` — voir la doc au site d'appel dans `refresh()`.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
