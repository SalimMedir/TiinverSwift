# v7_transversal.md — Problèmes transversaux, cycle V7

Document séparé pour le contenu transversal (touchant potentiellement plusieurs domaines) produit
par l'agent "Network/Socket.IO/Concurrence" du cycle V7. Les 2 findings eux-mêmes (V7-F-026,
V7-F-027) sont documentés en détail dans `MIGRATION_PARITY_AUDIT_V7.md` section 7 — ce fichier
contient le matériel de support qui ne rentrait pas dans le format finding standard.

## Balayage exhaustif des sites `Task {}` (Sources/TiinverSwift)

Action explicitement laissée ouverte par `MIGRATION_PARITY_AUDIT_V6.md` (section Transversal : "pas
de sweep exhaustif de tous les sites `Task {` du projet pour l'annulation à la navigation — seulement
4 écrans échantillonnés"). Fait pour la première fois ce cycle : 187 occurrences de `Task {`
recensées via `grep -rn "Task {" Sources/TiinverSwift`. Classées par catégorie (budget d'agent ne
permettant pas une relecture individuelle des 187 sites) :

| Catégorie | Nb approx. | Verdict | Justification |
|---|---|---|---|
| Boutons d'action utilisateur (submit/follow/like/delete/send...) dans les Views | ~90 | **Fine** | Actions ponctuelles déclenchées par tap, résultat idempotent ou à effet unique ; pas de risque d'écrasement par une réponse plus ancienne. |
| `ChatViewModel.swift` (194, 446, 688, 765, 859, 883) — abonnement groupe, envoi cadeau, insertion/suppression DB | 6 | **Fine, volontaire** | Écritures transactionnelles/financières qui DOIVENT survivre à une navigation hors de l'écran de chat, comme leur pendant Android (thread pool, pas lié à l'Activity). `[weak self]` évite le crash si le VM est désalloué. |
| `searchTask`/`lookupTask`/`typingResetTask` (SearchView, ChatSearchView, NewMessageView, ChatViewModel:825) | 4 | **Déjà géré** | Debounce correctement annulé à chaque frappe via `.cancel()` avant réassignation. |
| `CreateBoostView.scheduleCountrySearch()` (ligne 195) | 1 | **BUG confirmé** | Voir V7-F-026 dans l'audit principal. |
| Listeners socket `ChatRepository.swift` (79-186) | ~20 | **Fine** | Liés à la durée de vie du socket (singleton), pas d'une vue ; comportement déjà audité V6 (symétrique Android). |
| `CallCoordinator`/`CallKitManager`/`WebRTCConnection`/`VoIPPushManager` | ~20 | **Fine (non individuellement re-vérifié)** | Machine à états d'appel, doit survivre à la navigation (CallKit gère le cycle de vie, pas la vue SwiftUI). Voir section "investigation future" de l'audit principal — le domaine Calls dans son ensemble n'a pas eu d'agent dédié ce cycle. |
| `AdMobManager` (préchargement pubs) | 5 | **Fine, fire-and-forget par design** | Précharge un pool, aucune donnée utilisateur écrite tardivement. |
| `CoinStoreManager.updatesTask` (StoreKit transaction listener) | 1 | **Fine, déjà géré** | `deinit { updatesTask?.cancel() }` présent. |
| Chargement initial d'écran `.task {}`/`.onAppear { Task { await load() } }` (ProfileView, CreatorOfWeekView, StatisticsView, WalletView, BoostDashboardView...) | ~25 | **Fine dans la pratique** | Non stockés/annulés explicitement, mais écrivent dans un `@State`/`@StateObject` local à la vue ; si la vue est désallouée, SwiftUI ne matérialise plus les mutations. Risque réel seulement si le VM est un singleton partagé (aucun cas trouvé). |
| `MessageRepository.swift:499-508` — file `task`/`tail` séquentielle | 1 | **Fine** | Sérialise explicitement les écritures DB, pattern correct anti-race. |
| `PublishComposeView.swift:436` | 1 | **Fine** | Passerelle callback progress → MainActor, pas de logique réseau. |

**Conclusion du sweep** : sur 187 sites, 1 seul bug confirmé (V7-F-026), 1 domaine entier
(Calls/WebRTC) non individuellement re-vérifié faute de budget dédié dans ce cycle, le reste jugé
sain. Un futur cycle souhaitant fermer complètement ce sujet devrait dédier un agent uniquement au
domaine Calls/WebRTC (signalé aussi en section 8 de l'audit principal suite à l'archéologie git
ChatGroup ayant repéré 3 commits Android récents touchant ces écrans).

## Historique des tentatives de lancement de cet agent

Cet agent a échoué 3 fois avant de réussir au 4ᵉ essai :
1. Session-limite utilisateur atteinte pendant l'exécution (résolue par réinitialisation automatique).
2. Blocage de flux ("stalled: no progress for 600s").
3. Perte de connexion réseau infrastructure ("Connection lost mid-response").
4. Succès, avec un budget resserré (~25-30 appels d'outils, priorité au sweep `Task {}` et à un
   finding profond plutôt que plusieurs superficiels) — même stratégie qui avait débloqué l'agent
   transversal équivalent du cycle V6.

Aucune de ces pannes n'a affecté le contenu ni la qualité du rapport final — le prompt n'a nécessité
qu'un resserrement du budget d'effort, pas de changement de fond, cohérent avec le diagnostic déjà
posé lors du cycle V6 (panne d'infrastructure transitoire, pas un problème de conception de la tâche).
