import Foundation

/// Port de `contacts/Group.java` (lu en entier, 2026-08-15) — création de groupe + invitation des
/// membres sélectionnés. Fidèle à `onButtonPressed()` (ligne 274) et à la boucle `POST membership`
/// (lignes 389-458).
@MainActor
final class GroupRepository {
    static let shared = GroupRepository()
    private init() {}

    struct CreatedGroup {
        var groupId: String
        var token: String
        var name: String
        var description: String?
        var profile: String?
    }

    /// Port de `Group.onButtonPressed()` — `POST group`. Champs fidèles à l'original, y COMPRIS la
    /// faute de frappe réelle du serveur (`type: "pivate"`, PAS "private" — reproduite telle quelle,
    /// une valeur "corrigée" ne matcherait pas ce que l'API attend). `description` réutilise le
    /// MÊME texte que `name` (Android n'a pas de champ description séparé dans ce formulaire,
    /// vérifié). `profile_picture` toujours vide (aucun upload d'avatar de groupe dans ce flux).
    func createGroup(name: String, isPrivate: Bool, isLucrative: Bool, price: Int, creatorId: String) async throws -> CreatedGroup {
        let params: [String: String] = [
            "name": name,
            "description": name,
            "token": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "creator": creatorId,
            "type": isPrivate ? "pivate" : "public",
            "lucrative": isLucrative ? "1" : "0",
            "price": isLucrative ? String(price) : "0",
            "profile_picture": "",
        ]
        let value = try await APIClient.shared.post(params, endpoint: "group")
        // `looselyEncodedJSON` plutôt que `stringEncodedJSON` seul — voir sa doc (2026-08-17) :
        // même lecture Android `getString`+Gson qui s'est révélée fausse sur `weekly_rank`, aucun
        // JSON réel de CET endpoint pour trancher, donc tolère les deux formes plutôt que d'en
        // supposer une seule (risque concret pour P0-F : create échoue silencieusement dans
        // `catch` de `GroupCreationView.create()` si l'hypothèse est fausse ici aussi).
        guard value.isBackendSuccess, let data = value.looselyEncodedJSON("data") else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "group")
        }
        return CreatedGroup(
            groupId: (try? String(data.int("id"))) ?? "",
            token: data.optionalString("token") ?? "",
            name: data.optionalString("name") ?? name,
            description: data.optionalString("description"),
            profile: data.optionalString("profile")
        )
    }

    /// Port de `GroupModel` (`ShareActivity.joinGroup`'s champ source) — champs RÉELLEMENT lus par
    /// `joinGroup()` pour construire le `RosterModel` de la conversation, voir `DeepLinkRouter.swift`.
    struct GroupInfo {
        var id: Int
        var token: String
        var name: String
        var nikname: String?
        var description: String?
        var profile: String?
        var price: Int
        var lucrative: Int
        var isMember: Bool
        var creator: String
        var type: String

        /// Port de `joinGroup(GroupModel,...)` (`ShareActivity.java`) — construction du
        /// `RosterModel` d'un groupe pas encore forcément ouvert localement, à partir des SEULES
        /// données déjà connues côté client (résolution d'un lien profond `/group/{token}` OU,
        /// depuis le 2026-08-17 (P1), résultat de recherche de groupe `search/{myId}/{str}`, voir
        /// `ChatSearchView.swift` — MÊME construction dans les deux cas, extraite ici en un seul
        /// point plutôt que dupliquée). `subTitle` = `R.string.groupinfo` ("tab here for group
        /// info"), MÊME chaîne déjà identifiée et utilisée par `RosterListViewModel.refresh()` pour
        /// les groupes déjà dans le roster — corrige la version précédente de
        /// `DeepLinkRouter.routeToGroup`, qui laissait ce champ vide faute d'avoir alors identifié
        /// la chaîne réelle.
        func rosterModel(myId: String, myUsername: String?) -> RosterModel {
            let conversationId = ConversationIdGenerator.groupConversationId(currentUser: myId, remoteUser: String(id))
            var roster = RosterModel()
            roster.currentUsername = myUsername
            roster.currentUserId = myId
            roster.token = token
            roster.title = name
            // Port de `R.string.groupinfo`, corrigé avec `RosterListView.swift` (V3-F-006, P1) —
            // vraie traduction française (`values-fr/strings.xml:313`), pas le texte de
            // développement anglais.
            roster.subTitle = "onglet ici pour les informations sur le groupe"
            roster.conversationId = conversationId
            roster.userId = myId
            roster.username = myUsername
            roster.nikname = nikname
            roster.from = myUsername
            roster.to = token
            roster.sender = myId
            roster.receiver = token
            roster.groupId = String(id)
            roster.type = ChatType.group.wireValue
            roster.groupType = type
            roster.groupName = name
            roster.description = description
            roster.profile = profile
            roster.price = price
            roster.lucrative = lucrative
            roster.groupMember = isMember
            roster.creator = creator
            return roster
        }
    }

    /// Port de `ShareActivity.getGroup`/`connectToServeur` (`group/{myId}/{token}`, clé de réponse
    /// `"data"` — MÊME clé que `createGroup` ci-dessus, format cohérent entre les deux endpoints
    /// `group`) — résolution d'un lien profond `/group/{token}` (`DeepLinkRouter.swift`,
    /// 2026-08-16).
    func fetchGroup(token: String, myId: String) async throws -> GroupInfo {
        let value = try await APIClient.shared.get("group/\(myId)/\(token)")
        guard value.isBackendSuccess, let data = value.looselyEncodedJSON("data") else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "group")
        }
        return GroupInfo(
            id: (try? data.int("id")) ?? 0,
            token: data.optionalString("token") ?? token,
            name: data.optionalString("name") ?? "",
            nikname: data.optionalString("nikname"),
            description: data.optionalString("description"),
            profile: data.optionalString("profile"),
            price: (try? data.int("price")) ?? 0,
            lucrative: (try? data.int("lucrative")) ?? 0,
            isMember: (try? data.bool("isMember")) ?? false,
            creator: data.optionalString("creator") ?? "",
            type: data.optionalString("type") ?? "public"
        )
    }

    /// **Ajouté le 2026-08-18 (P1)** — port de `RechercheTiinver.getItFromServeur` (`Recherche/ui/
    /// RechercheTiinver.java:687-720`, mode `tokenSearch="chat"` lancé par `Roster.java:437`) :
    /// repli serveur de la recherche de groupe/conversation quand aucune conversation LOCALE ne
    /// matche déjà (voir `ChatSearchView.swift`, qui porte le filtre local ET appelle cette
    /// méthode). `GET search/{myId}/{str}`, clé `"data"` → `GroupModel[]` (Gson) — mêmes champs que
    /// `GroupInfo` ci-dessus, décodage per-item + diagnostic (même motif que `ContactsRepository.
    /// connectedUsers`/`fetchMembers`, P0-4, plutôt qu'un `try?` global sur le tableau entier).
    func searchGroups(myId: String, query: String) async throws -> [GroupInfo] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let value = try await APIClient.shared.get("search/\(myId)/\(encoded)")
        guard value.isBackendSuccess, let array = value.looselyEncodedJSON("data")?.toArray() else { return [] }
        let decoded = array.compactMap { item -> GroupInfo? in
            guard item.toDictionary() != nil else {
                print("GROUP SEARCH: item is not an object — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            // **Corrigé (2026-09-03, JSON réel `search/{myId}/{str}` fourni par l'utilisateur)** —
            // 2 champs silencieusement perdus (aucun des deux ne lève d'erreur, `optionalString`
            // renvoie juste `nil`/le repli par défaut) : la réponse réelle envoie la photo de groupe
            // sous la clé `"profile_picture"`, jamais `"profile"` (avatar de groupe jamais affiché
            // en résultat de recherche) ; `"creator"` arrive en NOMBRE JSON natif (l'id utilisateur
            // du créateur, ex. `196`), pas en chaîne (`creator` retombait toujours à `""`).
            return GroupInfo(
                id: (try? item.int("id")) ?? 0,
                token: item.optionalString("token") ?? "",
                name: item.optionalString("name") ?? "",
                nikname: item.optionalString("nikname"),
                description: item.optionalString("description"),
                profile: item.optionalString("profile") ?? item.optionalString("profile_picture"),
                price: (try? item.int("price")) ?? 0,
                lucrative: (try? item.int("lucrative")) ?? 0,
                isMember: (try? item.bool("isMember")) ?? false,
                creator: item.optionalString("creator") ?? (try? item.int("creator")).map(String.init) ?? "",
                type: item.optionalString("type") ?? "public"
            )
        }
        if decoded.count != array.count {
            print("GROUP SEARCH: received=\(array.count) groups, only \(decoded.count) usable — \(array.count - decoded.count) skipped, see above")
        }
        return decoded
    }

    /// Port de la boucle `POST membership` (un appel par membre sélectionné, ligne 389-458) —
    /// échecs individuels ignorés (Android ne bloque pas la création de groupe si l'invitation d'UN
    /// membre échoue, chaque appel est indépendant dans la boucle d'origine).
    func addMembers(_ members: [GroupMemberCandidate], toGroupId groupId: String, inviterId: String) async {
        for member in members {
            let params: [String: String] = [
                "groupId": groupId,
                "userId": member.userId,
                "joined": "0",
                "invited": "1",
                "inviter": inviterId,
                "role": "user",
            ]
            _ = try? await APIClient.shared.post(params, endpoint: "membership")
        }
    }

    // MARK: - Gestion de groupe (GAP-011, audit du 2026-08-16) — port de
    // `messagerie/group/SettingGroupMessageFragmant.java`/`GroupDetailActivity.java`/
    // `AddGroupDescriptionActivity.java`, tous lus en entier.

    /// **Simplification de portage documentée, pas une invention.** Côté Android, la liste des
    /// membres n'est PAS un appel réseau direct dans l'écran de gestion : `GroupDetailActivity`
    /// lit une table SQLite locale (`infoContract.USER_URI`) synchronisée en tâche de fond
    /// (`MyBackgroundTask`, non porté — infrastructure de synchronisation locale hors périmètre de
    /// ce gap). L'appel réseau direct existe bel et bien mais est COMMENTÉ dans le fichier source
    /// Android lui-même (`getGroupMemebers()`, `SettingGroupMessageFragmant.java:485-539` :
    /// `GET membership/{groupId}`, réponse `{error, data: "<MemberModel[] JSON>"}`) — utilisé ici
    /// directement plutôt que de reconstruire toute une couche de synchronisation locale pour un
    /// seul écran.
    /// **DURCI le 2026-08-17 (P0-4, même défense-en-profondeur que `ContactsRepository.
    /// connectedUsers` ci-dessus, trouvée en vérifiant les autres appelants de ce même motif dans
    /// ce fichier)** : même remplacement `try?` global sur le TABLEAU entier → décodage per-item,
    /// pour éviter qu'UN SEUL membre au format inattendu ne vide silencieusement tout l'écran de
    /// gestion de groupe.
    func fetchMembers(groupId: String) async throws -> [GroupMember] {
        let value = try await APIClient.shared.get("membership/\(groupId)")
        guard value.isBackendSuccess, let array = value.looselyEncodedJSON("data")?.toArray() else { return [] }
        let decoded = array.compactMap { item -> GroupMember? in
            guard let data = item.rawData else {
                print("GROUP MEMBERS: item.rawData nil for one member — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(GroupMember.self, from: data)
            } catch {
                print("GROUP MEMBERS: decode failure for one member — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("GROUP MEMBERS: received=\(array.count) members, only \(decoded.count) decoded successfully — \(array.count - decoded.count) silently dropped, see decode failures above")
        }
        return decoded
    }

    /// Port de `TransportData.updateMember` (`Http/TransportData.java:175-190`) — `POST
    /// /member/update`, `column="roles"`, `value="admin"`/`"user"`.
    ///
    /// **Corrigé le 2026-08-23 (MIGRATION_PARITY_AUDIT_V4.md V4-F-020, Phase B P1)** — les 7
    /// méthodes de mutation de ce fichier (celle-ci et les 6 suivantes) ignoraient jusqu'ici
    /// `value.isBackendSuccess`, contrairement à `createGroup`/`fetchGroup` ci-dessus qui font déjà
    /// ce contrôle. Vérifié dans `TransportData.Post` (`Http/TransportData.java:615-681`, lu en
    /// entier) : le callback Android n'appelle `onResonse` (qui applique les effets locaux) QUE si
    /// `response.getString("error").equals("false")` — sinon `onError` est appelé à la place. Le
    /// `if (action==0)` visible dans chaque appelant (`SettingGroupMessageFragmant.java:553` etc.)
    /// est donc TOUJOURS vrai quand `onResonse` est atteint (`action` y est un littéral `0` fixé par
    /// le framework, pas un champ lu dans la réponse) — le vrai gate Android est `error=="false"`,
    /// exactement `JSONValue.isBackendSuccess`. Les appelants iOS (`GroupDetailView.swift`,
    /// `ChatViewModel.resolveGroupSubscription`) enveloppent déjà chaque appel dans un `do/catch` et
    /// n'appliquent leurs effets locaux qu'APRÈS le `try await` — il ne manquait que le `throw` côté
    /// dépôt pour que ce `catch` existant se déclenche réellement sur un rejet backend.
    func updateMemberRole(userId: Int, groupId: String, creatorId: String, makeAdmin: Bool) async throws {
        let params: [String: String] = [
            "creator": creatorId, "groupId": groupId, "value": makeAdmin ? "admin" : "user", "column": "roles",
            "userId": String(userId),
        ]
        let value = try await APIClient.shared.post(params, endpoint: "/member/update")
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "/member/update")
        }
    }

    /// Port de `SettingGroupMessageFragmant.deleteGroupMemebers` (lignes 542-548 pour les
    /// paramètres réseau — le reste de la méthode Android insère un message système local, déjà
    /// géré côté iOS par le rendu existant des messages système reçus via Socket.IO, pas dupliqué
    /// ici). Voir V4-F-020 ci-dessus pour le contrôle `isBackendSuccess`.
    func removeMember(userId: Int, groupId: String, creatorId: String) async throws {
        let params: [String: String] = ["userId": String(userId), "creator": creatorId, "groupId": groupId]
        let value = try await APIClient.shared.post(params, endpoint: "deleteMember")
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "deleteMember")
        }
    }

    /// Port de `SettingGroupMessageFragmant.sendFotoPerfilToServer` (lignes 628-738, entier) —
    /// **ajouté le 2026-08-24 (MIGRATION_PARITY_AUDIT_V4.md V4-F-025, Phase B P2)**, précédemment
    /// noté "pas porté ici" sur `updateDescription` ci-dessous. Protocole ENTIÈREMENT différent des
    /// autres méthodes `updategroup` (JSON `column`/`value`) : multipart DIRECT vers le backend
    /// (`HttpFileUploader.uploadRequestBodyGroupPerfil`), PAS BunnyCDN — le backend gère lui-même le
    /// stockage et renvoie l'URL CDN finale (`object_url` dans la réponse). Champs fidèles à
    /// l'original : `creator`/`id`/`apiKey`/`column="profile_picture"` (littéral copié-collé côté
    /// Android depuis le flux photo de profil PERSONNEL — pas une faute de frappe de ce portage,
    /// reproduit tel quel)/`format="json"`, fichier sous `object_url` en `image/jpeg`.
    func updatePhoto(groupId: String, creatorId: String, apiKey: String, imageData: Data) async throws -> String {
        let value = try await APIClient.shared.uploadMultipart(
            endpoint: "updategroup",
            fields: ["creator": creatorId, "id": groupId, "apiKey": apiKey, "column": "profile_picture", "format": "json"],
            fileFieldName: "object_url",
            filename: "wn_image.jpeg",
            mimeType: "image/jpeg",
            fileData: imageData
        )
        guard value.isBackendSuccess, let photoUrl = value.optionalString("object_url") else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "updategroup")
        }
        return photoUrl
    }

    /// Port de `AddGroupDescriptionActivity.updateGroup` (lignes 95-105) — endpoint générique
    /// `updategroup` par colonne (JSON `column`/`value`, protocole DIFFÉRENT du changement de photo
    /// ci-dessus, qui est multipart). Voir V4-F-020 ci-dessus.
    func updateDescription(_ description: String, groupId: String, creatorId: String, apiKey: String) async throws {
        let params: [String: String] = [
            "creator": creatorId, "id": groupId, "value": description, "column": "description", "apiKey": apiKey,
        ]
        let value = try await APIClient.shared.post(params, endpoint: "updategroup")
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "updategroup")
        }
    }

    /// Port de `ChangeGroupTopicActivity.updateGroup` (lignes 91-101, entier, 2026-08-18 P2) —
    /// MÊME endpoint générique `updategroup` qu'`updateDescription` ci-dessus, `column="name"`. Voir
    /// V4-F-020 ci-dessus.
    func updateName(_ name: String, groupId: String, creatorId: String, apiKey: String) async throws {
        let params: [String: String] = [
            "creator": creatorId, "id": groupId, "value": name, "column": "name", "apiKey": apiKey,
        ]
        let value = try await APIClient.shared.post(params, endpoint: "updategroup")
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "updategroup")
        }
    }

    /// Port de `GroupDetailActivity.exit()` (lignes 260-271) — `POST leftgroup`. Voir V4-F-020
    /// ci-dessus.
    func leaveGroup(groupId: String, userId: String, apiKey: String) async throws {
        let params: [String: String] = ["groupId": groupId, "userId": userId, "apiKey": apiKey]
        let value = try await APIClient.shared.post(params, endpoint: "leftgroup")
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "leftgroup")
        }
    }

    // MARK: - Groupes payants (port de `ChatFragmentTest.checkSubcribtion`/`displaySubscriptionInfo`/
    // `renewSubscription`/`Subscribe.bind`/`RenewSubscription.bind`, module 11) — **ajouté le
    // 2026-08-19, V3-F-070 GROUPS-07, P1**. Aucun de ces 3 points n'était appelé nulle part côté
    // iOS avant ce correctif : `ChatListItem.subscriptionRequired`/`.subscriptionRenewal` étaient
    // déclarés dans l'énum et gérés dans le `switch` de rendu, mais RIEN ne les construisait jamais
    // (0 site d'appel, confirmé par grep) — la bannière d'abonnement ne s'affichait donc jamais du
    // tout, un gap plus sévère que "bouton inerte" tel que décrit initialement dans le finding.

    /// Résultat de `GET group/checksubscription/{userId}/{groupId}` — port de `checkSubcribtion`
    /// (`ChatFragmentTest.java:707-749`). Le serveur répond `error:"false"` (abonnement actif, rien
    /// à afficher) ou `error:"true"` avec `message` égal à l'une des 2 chaînes EXACTES vérifiées
    /// dans `infoContract.java:49-50` (`"subscription expires."`/`"Restricted access."` — fautes de
    /// frappe/casse Android reproduites telles quelles, ce sont les valeurs réellement comparées).
    ///
    /// **Corrigé (2026-09-04, audit forensique groupes lucratifs)** — `expired`/`restricted`
    /// portent désormais le `price` FRAIS lu dans CETTE MÊME réponse (`object.getInt("price")`,
    /// `ChatFragmentTest.java:742`). Vérifié précisément : Android ne se contente pas de lire ce
    /// prix pour l'afficher — il réécrit `userData.setPrice(price)` (`:744`) AVANT de construire la
    /// bannière (`renewSubscription()`/`displaySubscriptionInfo()`, `:1203`/`:1232`, lisent
    /// `userData.getPrice()`, la valeur qui vient d'être réécrite) ET avant tout appel ultérieur
    /// `group/subscribe`/`group/renewsubscription` (`quantity=price`, `MessageListAdapter.java:
    /// 267-494`) — donc pas seulement un texte périmé si le prix change côté serveur, mais un
    /// MONTANT DÉBITÉ potentiellement faux. `lucrative`/`description` sont aussi réécrits côté
    /// Android (`:745-746`) mais ne sont lus par AUCUNE des deux méthodes de bannière ni par la
    /// requête d'abonnement elle-même (vérifié en lisant `renewSubscription`/`displaySubscriptionInfo`
    /// en entier) — pas ajoutés ici, aucun effet observable à reproduire.
    enum GroupSubscriptionState {
        case active
        case expired(price: Int?)
        case restricted(price: Int?)
    }

    /// **Corrigé le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-016, Phase B P1-8)** — l'endpoint
    /// Android exact est `group/checksubscription2` (avec le chiffre "2", `ChatFragmentTest.java:727`,
    /// confirmé par grep exhaustif — aucune autre occurrence dans tout le code Android). Le suffixe
    /// numérique avait été omis lors du portage, faisant échouer silencieusement chaque appel
    /// (retombant sur `.active` via le `try?` ci-dessous) et empêchant tout blocage du composeur
    /// pour un abonnement expiré/restreint.
    func checkSubscription(userId: String, groupId: String) async -> GroupSubscriptionState {
        guard let value = try? await APIClient.shared.get("group/checksubscription2/\(userId)/\(groupId)")
        else { return .active }
        guard !value.isBackendSuccess, let message = value.backendErrorMessage else { return .active }
        // `nil` si absent/mal formé plutôt qu'une valeur inventée — l'appelant retombe alors sur le
        // `price` mis en cache localement (`RosterModel.price`), jamais sur 0.
        let freshPrice = try? value.int("price")
        switch message {
        case "subscription expires.": return .expired(price: freshPrice)
        case "Restricted access.": return .restricted(price: freshPrice)
        default: return .active
        }
    }

    /// **Ajouté le 2026-08-25 (MIGRATION_PARITY_AUDIT_V5.md V5-F-020, Phase B P1-10)** — port de
    /// `ChatRepository.loadMoreFromServeur` (`messagerie/repository/ChatRepository.java:1129-1177`) :
    /// repli REST pour l'historique de GROUPE quand le cache local Core Data est épuisé. `GET
    /// group/{groupId}/messages?lastDate={lastDate}&limit={limit}`, réponse `{error, data: [...]}` —
    /// `error` est un booléen JSON natif chez Android (`object.getBoolean("error")`, pas la
    /// convention chaîne habituelle), déjà tolérée par `isBackendSuccess`/`errorFieldNormalized`
    /// sans changement. Décodage per-item + diagnostic, même motif que `fetchMembers`/
    /// `searchGroups` ci-dessus.
    ///
    /// **Portée délibérément limitée** : `ChatManager.prepareOldGroupMessage` (le récepteur Android
    /// de cette réponse, ligne 1090-1155, lu en entier) contient aussi des branches spéciales pour
    /// `object == "voicecall"`/`"missedvoicecall"` qui déclenchent des effets de bord de
    /// signalisation d'appel (accusé de livraison, lancement/déclin d'appel via `CallService`) —
    /// spécifiques à l'infrastructure d'appel Android (`CallService.isOnCall`), sans équivalent 1:1
    /// évident avec `CallCoordinator` iOS, et hors du périmètre de CE finding (Socket.IO/historique,
    /// pas Calls). Seule la branche générique (persister + afficher) est portée ici ; les 2 branches
    /// d'effets de bord d'appel dans l'historique de groupe restent NON portées, documenté plutôt
    /// que deviné.
    func fetchOlderGroupMessages(groupId: String, lastDate: String, limit: Int) async throws -> [MessageLib] {
        let value = try await APIClient.shared.get("group/\(groupId)/messages?lastDate=\(lastDate)&limit=\(limit)")
        guard value.isBackendSuccess, let array = value.looselyEncodedJSON("data")?.toArray() else { return [] }
        let decoded = array.compactMap { item -> MessageLib? in
            guard let data = item.rawData else {
                print("GROUP HISTORY: item.rawData nil for one message — raw=\(item.toDictionary() ?? [:])")
                return nil
            }
            do {
                return try JSONDecoder().decode(MessageLib.self, from: data)
            } catch {
                print("GROUP HISTORY: decode failure for one message — error=\(error) raw=\(item.toDictionary() ?? [:])")
                return nil
            }
        }
        if decoded.count != array.count {
            print("GROUP HISTORY: received=\(array.count) messages, only \(decoded.count) decoded successfully — \(array.count - decoded.count) silently dropped, see decode failures above")
        }
        return decoded
    }

    /// Port de `Subscribe.bind`'s `subscribe.setOnClickListener` (`MessageListAdapter.java:267-314`)
    /// — `POST group/subscribe`. Champs fidèles à l'original, y compris `joined`/`invited`/`role`
    /// toujours fixés à `"1"`/`"0"`/`"user"` (aucune variation observée dans le code source). Voir
    /// V4-F-020 ci-dessus pour le contrôle `isBackendSuccess`.
    func subscribeToGroup(groupId: String, userId: String, creatorId: String, price: Int) async throws {
        let params: [String: String] = [
            "groupId": groupId, "userId": userId, "receiver": creatorId,
            "quantity": String(price), "joined": "1", "invited": "0", "role": "user",
        ]
        let value = try await APIClient.shared.post(params, endpoint: "group/subscribe")
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "group/subscribe")
        }
    }

    /// Port de `RenewSubscription.bind`'s `subscribe.setOnClickListener`
    /// (`MessageListAdapter.java:365-412`) — MÊME payload que `subscribeToGroup`, endpoint différent
    /// (`group/renewsubscription`, tout en minuscules — vérifié, contrairement à
    /// `group/checksubscription` qui a la même casse). Voir V4-F-020 ci-dessus.
    func renewGroupSubscription(groupId: String, userId: String, creatorId: String, price: Int) async throws {
        let params: [String: String] = [
            "groupId": groupId, "userId": userId, "receiver": creatorId,
            "quantity": String(price), "joined": "1", "invited": "0", "role": "user",
        ]
        let value = try await APIClient.shared.post(params, endpoint: "group/renewsubscription")
        guard value.isBackendSuccess else {
            throw JSONError.typeMismatch(value.backendErrorMessage ?? "group/renewsubscription")
        }
    }
}
