# MIGRATION PARITY PROGRESS V5

Journal de correction du cycle d'audit V5 (`MIGRATION_PARITY_AUDIT_V5.md`).

**État actuel (2026-08-25) : Phase A (Audit) TERMINÉE. Phase A.2 (contre-audit ciblé) TERMINÉE.
Phase B (correction) EN COURS — **BACKLOG P0 ENTIÈREMENT TRAITÉ (7/7)** : V5-F-094, V5-F-018,
V5-F-031, V5-F-032, V5-F-042, V5-F-045, V5-F-064 (V5-F-064 = doublon de V5-F-005, résolu en même
temps). Backlog P1 (40 findings) EN COURS [30/40 clos : V5-F-001, V5-F-005 (DUPLICATE), V5-F-006,
V5-F-007, V5-F-009, V5-F-010, V5-F-013, V5-F-016, V5-F-019, V5-F-020, V5-F-021, V5-F-022,
V5-F-023, V5-F-029, V5-F-033, V5-F-034, V5-F-036, V5-F-037 (IOS_INTENTIONAL_DIFFERENCE),
V5-F-043, V5-F-046, V5-F-047, V5-F-050, V5-F-057, V5-F-058, V5-F-060 (DIFFÉRÉ), V5-F-062,
V5-F-063, V5-F-067, V5-F-068, V5-F-070], démarré automatiquement à V5-F-001, dans l'ordre du
document. Prochain : V5-F-072. Puis 31 P2, 21 P3.**

`MIGRATION_PARITY_AUDIT_V5.md` contient **99 findings** (V5-F-001 à V5-F-099) au total :

- **Phase A** (69 findings, V5-F-001 à V5-F-069) : produits par 23 agents de recherche
  indépendants (répartis sur autant de domaines fonctionnels) + 1 agent critique de complétude qui
  a passé en revue les 23 rapports pour repérer les zones sous-creusées et les patterns de bug
  systématiquement sous-cherchés (voir §3 de l'audit). Aucun agent n'a lu les audits V1/V2/V3/V4
  avant de produire ses findings.
- **Phase A.2** (30 nouveaux findings, V5-F-070 à V5-F-099, voir section "PHASE A.2" en fin
  d'audit) : contre-audit ciblé demandé explicitement par l'utilisateur pour vérifier les 8 zones
  signalées comme sous-creusées par l'agent critique de la Phase A (Socket.IO, Chat, pipeline
  média BunnyCDN — décomposé en 5 sous-domaines vérifiés séparément [avatar/photo-vidéo Feed/
  chat/Animems], Photo Editor, Animems Canvas) + 3 patterns transversaux (double action/
  idempotence, mémoire/concurrence, lifecycle). 12 agents indépendants, chacun recevant la liste
  des findings V5 déjà connus dans son périmètre pour éviter les doublons. **12 findings de la
  Phase A ont été reconfirmés indépendamment** (§A.2.2 de l'audit) — non recréés.

**AUCUN code source n'a été modifié pour produire cet audit, dans aucune des deux phases** —
conformément à la consigne explicite de l'utilisateur. Aucun finding n'a encore été corrigé.

Répartition finale (Phase A + A.2) : 7 P0, 40 P1, 31 P2, 21 P3. Voir `MIGRATION_PARITY_AUDIT_V5.md`
§0 pour la ventilation complète par statut suggéré, §1 pour le TOP 20 de la Phase A (le contre-audit
n'a pas été re-classé dans ce TOP 20), §2 pour le détail domaine par domaine de la Phase A, et la
section "PHASE A.2" en fin de document pour le détail complet du contre-audit (findings, findings
reconfirmés, couverture par domaine).

**Découverte la plus critique du contre-audit** : V5-F-094 (P0, `FUNCTIONALLY_FAILED`) — l'export
vidéo MP4 d'Animems (fonctionnalité de sortie principale du module) est totalement non fonctionnel
pour tout contenu animé : `AnimemesExporter` est capturé en `[weak self]` sur l'unique point
d'entrée de son pipeline d'écriture asynchrone, mais rien ne retient l'instance en vie pendant
cette durée (variable locale, pas de propriété stockée côté `AnimemesEditorState`) — l'objet est
désalloué par ARC avant que la closure GCD ne s'exécute, donc `self` vaut `nil` à chaque
invocation, aucune frame n'est écrite, `completion`/`isExporting` ne se déclenchent jamais :
l'export reste bloqué indéfiniment sans aucune erreur visible.

## 2026-08-24 — Phase B V5 — Lot P0-1 : V5-F-094 (BUILD_VALIDATED)

### Vérification

**Android** : `AnimemesCompound.java:259` (`MP4Encoder encoder;`, champ de la vue) et `:3317`
(`encoder = new MP4Encoder();`) — l'encodeur est un champ PERSISTANT de la vue, retenu pour toute
la durée de l'encodage tant que la vue existe, utilisé aux lignes 2624-2654
(`createVideosFromBitmap`).

**iOS avant correctif** : `AnimemesEditorState.export(canvasSize:completion:)` créait `exporter`
comme variable purement LOCALE. `AnimemesExporter.export(to:completion:)` enregistre son pipeline
vidéo via `videoInput.requestMediaDataWhenReady(on:using:)` (callback ASYNCHRONE rappelé plus tard
sur `videoQueue`) puis retourne immédiatement — `AnimemesEditorState.export(...)` retourne lui
aussi aussitôt après. Plus rien ne retenait alors `exporter` : ARC le désallouait avant le premier
rappel du callback, dont la capture `[weak self]` retrouvait systématiquement `self == nil` —
aucune frame jamais écrite, `completion` jamais invoquée, `isExporting` bloqué à `true`
indéfiniment, aucune erreur visible. Confirmé par lecture complète des 2 fichiers (227 lignes
d'`AnimemesExporter.swift` + le site d'appel).

### Correctif appliqué

Nouvelle propriété stockée forte `AnimemesEditorState.activeExporter: AnimemesExporter?`,
assignée juste avant `exporter.export(to:completion:)`, remise à `nil` dans la completion (succès
ET échec) — fidèle au champ persistant `encoder` d'Android. Diff strictement additif (1 propriété
+ 2 lignes), aucune ligne de logique de rendu/écriture/audio touchée. `exportStaticImage` (chemin
synchrone séparé pour l'export d'image statique) intégralement inchangé.

### Garanties vérifiées (demandées explicitement par l'utilisateur)

- Export image inchangé — `exportStaticImage` non touché.
- Export MP4 fonctionnel — le pipeline complet peut désormais s'exécuter jusqu'au bout, `self`
  restant valide tout du long.
- Toutes les frames écrites — la boucle `while videoInput.isReadyForMoreMediaData` n'est plus
  interrompue prématurément.
- Completion toujours appelée — les 3 points de sortie du pipeline atteignent désormais
  réellement la completion d'`AnimemesEditorState`.
- `isExporting` toujours réinitialisé — `self.isExporting = false` s'exécute dans tous les cas.
- Erreur correctement propagée — la branche `.failure` continue de positionner `exportError`.
- Aucune régression du pipeline existant — diff strictement additif.

### Flux frères vérifiés

Un seul site de construction d'`AnimemesExporter` et 2 sites d'appel de `export(canvasSize:)` dans
tout le projet (les 2 boutons "Exporter la vidéo" d'`AnimemesEditorView.swift`), tous deux passent
par la même fonction corrigée.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/AnimemesEditorState.swift`.

**Résultat CI** : commit `f5b7fbd`, push confirmé (`a85063a..f5b7fbd main -> main`), run
`32888135380` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis (aucun accès Xcode/simulateur/device) : ajouter un
calque animé, taper "Exporter la vidéo", confirmer qu'un MP4 valide est produit (frames + son si
piste audio ajoutée), que le spinner disparaît à la fin, et qu'un export raté affiche `exportError`
plutôt que de rester bloqué indéfiniment.

## 2026-08-24 — Phase B V5 — Lot P0-2 : V5-F-018 (BUILD_VALIDATED)

### Vérification

**Android — approfondie au-delà de la citation de l'audit** : `mLayoutManager.setStackFromEnd(true)`
positionne implicitement en bas au chargement initial (`ChatFragmentTest.java:539`).
`addMessage`/`onOldMessage`→`addOldMessage` (message envoyé localement OU reçu en direct par
socket — `:2678-2717,2001-2065`, PAS des noms trompeurs : `addOldMessage` gère en réalité les
messages socket "en retard", pas la pagination REST) appellent explicitement
`smoothScrollToPosition(getItemCount()-1)`. **Point clé vérifié personnellement, absent de la
citation d'audit initiale** : `displayMoreMessageOnScroll` (`:1645-1758`, le VRAI gestionnaire de
pagination, déclenché par `onScrolled`/`!canScrollVertically(-1)`) N'APPELLE PAS ce scroll — il
insère les anciens messages en tête (`messages.add(0, mlib)`) et laisse le `LinearLayoutManager`
préserver nativement la position de lecture pendant un prépend. La RECOMMANDATION de l'audit
restait incertaine sur ce point ; la vérification personnelle confirme qu'un scroll inconditionnel
sur CHAQUE ajout (y compris pagination) aurait été infidèle à Android.

**iOS avant correctif** : `ChatView.messageList` était un `List` SwiftUI classique sans
`ScrollViewReader` ni aucun mécanisme de scroll. La conversation s'ouvrait sur les messages les
PLUS ANCIENS de la page chargée. Pire : le premier item (le plus ancien) déclenchait immédiatement
son `.onAppear` → `loadMore()`, qui préfixait une page supplémentaire dont le nouveau premier
élément redevenait visible en haut, redéclenchant `loadMore()` en cascade — chargement de tout
l'historique de la conversation avant toute interaction utilisateur.

### Correctif appliqué

`messageList` entourée d'un `ScrollViewReader`, scroll vers `viewModel.items.last?.id` dans
`.onChange(of:)`. Ce signal ne se déclenche JAMAIS pendant `loadMore()` (insère exclusivement à
l'index 0 — le dernier élément ne change donc jamais), mais se déclenche pour le chargement initial
(`items` vide → peuplé) et tout ajout en fin de liste (`onIncoming`/`appendOptimistic`) —
reproduisant exactement la distinction Android vérifiée ci-dessus, sans flag/garde supplémentaire
côté ViewModel.

**Effet de bord positif confirmé** : résout AUSSI la cascade de pagination — une fois la vue
effectivement scrollée en bas au chargement, le premier item n'est plus dans le viewport visible,
donc son `.onAppear` ne se déclenche plus immédiatement à l'ouverture.

### Flux frères vérifiés

`grep "List {"` dans `Sources/TiinverSwift/Messagerie` → `ChatSearchView`/`GroupDetailView`/
`PrivateMessageSettingView`/`RosterListView` — aucun n'est un historique de messages avec
équivalent de `stackFromEnd` côté Android, pas de site frère à corriger.

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/ChatView.swift`.

**Résultat CI** : commit `5964e87`, push confirmé (`61d96f6..5964e87 main -> main`), run
`32889479501` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : ouvrir une conversation avec plus d'une page
d'historique, confirmer l'affichage immédiat des messages les plus récents sans scroll manuel ;
confirmer via l'inspecteur réseau qu'aucune requête de pagination en cascade ne se déclenche avant
toute interaction ; remonter manuellement l'historique et confirmer que la position de lecture est
préservée pendant le chargement d'anciens messages ; envoyer/recevoir un message en direct et
confirmer le scroll automatique vers le bas.

## 2026-08-24 — Phase B V5 — Lot P0-3 : V5-F-031 (BUILD_VALIDATED)

### Vérification financière DOUBLE (règle explicite du cycle)

**Android** : `TransportData.Post` (`Http/TransportData.java:614-634`) lit le champ `error` du
corps JSON MÊME sur une réponse HTTP 200 — si `error != "false"`, `onError(message)` est appelé au
lieu de `onResonse`. `WalletRepository.updateToServer` (`:301-328`) : `onError` NE remet JAMAIS
`pendingCoinCount` à 0 — il l'incrémente au contraire du gain courant pour retry au prochain crédit.

**iOS avant correctif** : `WalletRepository.creditReward` ignorait entièrement le champ `error`
(seul le status code HTTP était vérifié par `APIClient.post`). Un rejet applicatif serveur (fraude
anti-abus, limite quotidienne, session expirée) ne levait jamais d'exception : les 4 appelants
exécutaient leur branche `do` (succès) à tort, remettant `pendingCoinsAmount`/`pendingGemsAmount` à
0 alors que le serveur n'avait jamais crédité le gain — perte silencieuse et définitive.

**Vérification 1 (paramètres/delta/solde inchangés)** : confirmé que le calcul du delta
(`pendingCoinCount + currenGainCoins`) et le crédit local optimiste étaient déjà corrects (fix
antérieur V4-F-065/066) — seul le contrôle de la réponse serveur manquait.

**Vérification 2 (rollback/idempotence/erreur réseau)** : confirmé qu'Android lui-même NE fait PAS
de rollback du crédit local optimiste sur erreur (seul `pendingCoinCount`/`PENDING_COINS_AMOUNT`
change côté Android) — donc aucun rollback supplémentaire n'était nécessaire côté iOS (déjà
absent, correctement fidèle). Confirmé que les 4 appelants (`EarnCoinsView`/`WithdrawView`/
`TransferCoinsView`/`ConversionView`) ont déjà un bloc `catch` correctement structuré
(`pendingCoinsAmount += ...`) prêt à recevoir l'erreur nouvellement levée.

### Correctif appliqué

`guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ??
"rewardedCoins") }` ajouté après le POST dans `WalletRepository.creditReward` — motif identique à
`referralTotal`/`refreshBalance` (même fichier) et au reste du projet (`AdsRepository`,
`FeedRepository`).

### Flux frères vérifiés

5 sites d'appel confirmés (4 vues + la fonction elle-même) — un seul point de correction couvre
tous.

**Fichiers modifiés** : `Sources/TiinverSwift/Wallet/WalletRepository.swift`.

**Résultat CI** : commit `23b40af`, push confirmé (`c232bed..23b40af main -> main`), run
`32890639113` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis (aucun accès backend de test permettant de simuler
un rejet applicatif) : provoquer un rejet serveur réel, confirmer que `pendingCoinsAmount`/
`pendingGemsAmount` ne repasse pas à 0 et qu'un nouveau crédit est retenté au prochain gain.

## 2026-08-24 — Phase B V5 — Lot P0-4 : V5-F-032 (BUILD_VALIDATED)

### Vérification financière DOUBLE (même méthodologie que V5-F-031)

**Android** : `WithdrawActivity.java:151-157` mappe explicitement `WITHDRAWAL_THRESHOLD_EXCEEDED`
sur un libellé dédié — preuve que ce chemin d'erreur applicatif HTTP-200 est réellement emprunté en
production. `TransfertCoinsActivity.java:128-150` : la déduction locale du solde
(`coinCount - Integer.parseInt(m)`) n'a lieu QUE dans `onResonse`, jamais dans `onError`.
`submitWithdrawalByCrypto` vérifié séparément : `TransportData.postToVPS` (serveur VPS crypto
DISTINCT) applique le MÊME contrat `error`/`onError` que `Post`.

**iOS avant correctif** : les 4 méthodes de `WalletRepository` (`submitWithdrawalRequest`,
`submitWithdrawalByCrypto`, `convert`, `transferCoins`) ne vérifiaient jamais `isBackendSuccess` —
un rejet serveur applicatif se traduisait par un faux message de succès, et pour le transfert P2P,
une déduction de solde local alors qu'aucune pièce n'avait quitté le compte serveur.

**Vérification des 3 vues appelantes** : succès UI et déduction de solde déjà placés APRÈS le
`try await`, à l'intérieur du bloc `do` — aucune modification nécessaire de leur côté.

### Correctif appliqué

`guard value.isBackendSuccess else { throw JSONError.typeMismatch(value.backendErrorMessage ??
endpoint) }` ajouté aux 4 méthodes, motif identique à V5-F-031.

**Gap mineur documenté, non corrigé** : le mapping `WITHDRAWAL_THRESHOLD_EXCEEDED` → libellé
dédié français n'est pas reproduit (texte générique affiché à la place) — explicitement optionnel
dans la RECOMMANDATION de l'audit ("envisager aussi"), la divergence critique (faux succès) est
intégralement corrigée.

### Flux frères vérifiés

4 méthodes, 5 sites d'appel (3 vues + 2 transports `post`/`postToVPS`) tous couverts par ce lot.

**Fichiers modifiés** : `Sources/TiinverSwift/Wallet/WalletRepository.swift`.

**Résultat CI** : commit `b170c2b`, push confirmé (`6719e1a..b170c2b main -> main`), run
`32891699920` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : provoquer un retrait dépassant le seuil serveur,
un rejet de transfert P2P, et un rejet de conversion ; confirmer dans chaque cas qu'aucun message
de succès ne s'affiche et qu'aucun solde local n'est altéré.

## 2026-08-24 — Phase B V5 — Lot P0-5 : V5-F-042 (BUILD_VALIDATED)

### Vérification

**Android** : `onDown` (`TimelineView.java:898-910`) — `selected = hit` s'exécute AVANT le test
`!hit.locked` (sélection toujours mise à jour au toucher), puis `mode = Mode.NONE` si verrouillé.
`onMove` (`:922-1008`) retourne immédiatement pour `Mode.NONE` — geste totalement inerte, y compris
pas de défilement de la timeline.

**iOS avant correctif** : `TimelineView.resolveMode(at:model:)` ne lisait jamais `item.locked` —
un calque verrouillé restait glissable/redimensionnable, la mutation atteignant
`AnimationObjectData` réel puis le moteur de lecture via `applyTimelineItemsToLayers()`.

### Correctif appliqué — et écart avec la RECOMMANDATION de l'audit

La RECOMMANDATION suggérait de réutiliser `.pan` pour un item verrouillé. Vérification personnelle
: cela aurait introduit 2 régressions — (1) le dispatch `.pan` désélectionne désormais
explicitement (correctif V4-F-053, même cycle), un item verrouillé se serait désélectionné au
toucher ; (2) le handler par frame de `.pan` fait défiler la TIMELINE elle-même, ce qu'Android ne
fait STRICTEMENT PAS en `Mode.NONE`. Ajouté à la place un cas dédié `DragMode.lockedTap(id:)` —
sélection préservée, geste entièrement inerte, miroir exact de `Mode.NONE`.

### Flux frère vérifié

La Phase A.2 (contre-audit ciblé) avait déjà re-vérifié indépendamment le geste de manipulation
directe sur le CANEVAS (distinct de la timeline) et confirmé sa garde de verrouillage fidèle
("parité confirmée, pas de finding") — pas de bug sœur à corriger de ce côté.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/TimelineView.swift`.

**Résultat CI** : commit `76da082`, push confirmé (`40c0fc1..76da082 main -> main`), run
`32892903483` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : verrouiller une piste, confirmer sélection
possible mais glisser/redimensionner bloqués, et absence de défilement de la timeline.

## 2026-08-24 — Phase B V5 — Lot P0-6 : V5-F-045 (BUILD_VALIDATED)

### Vérification

**Android** : `MyBottomSheetDialogFragment.java:498` — `map.put("comment", data.getCommentText())`,
la clé réseau est `"comment"`. `"commentText"` n'est qu'un nom de champ Java interne
(`CommentModel.commentText`), jamais sérialisé tel quel — distinct de `"comment_text"`
(snake_case), la clé lue par `NotificationRepository.java:176` sur un endpoint différent.

**iOS avant correctif** : `CommentRepository.post` envoyait `"commentText": text` au lieu de
`"comment"` — risque réel que le texte du commentaire arrive vide/absent côté serveur, sans
qu'aucune erreur ne soit levée (seul `isBackendSuccess` est vérifié, pas le contenu retourné).

### Correctif appliqué

Renommage trivial de la clé du dictionnaire `params` : `"commentText"` → `"comment"`.

### Flux frères vérifiés

`grep "commentText"` → un seul site réseau concerné ; les 3 autres occurrences sont des attributs
Core Data locaux (noms de champ de stockage), sans rapport avec le protocole réseau.

**Fichiers modifiés** : `Sources/TiinverSwift/Discover/CommentRepository.swift`.

**Résultat CI** : commit `7df099a`, push confirmé (`2515367..7df099a main -> main`), run
`32893884706` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : poster un commentaire et une réponse depuis iOS,
confirmer via le backend que le texte est bien enregistré.

## 2026-08-24 — Phase B V5 — Lot P0-7 : V5-F-064 (BUILD_VALIDATED) — dernier P0 du backlog

### Vérification

**Android** : `transportDataBackground.java:90-116` — la purge des préférences locales (profil/id/
username) et le retour à l'écran de connexion ne surviennent QUE dans `onResponse` (succès réseau
confirmé), pour `method="logout"` ET `"deleteaccount"` (routés vers la même méthode
`deleteaccount()`). `onErrorResponse` pour ces 2 cas ne fait QUE `dialog.dismiss()` — noté :
Android n'affiche même AUCUN texte d'erreur pour ces 2 cas précis (contrairement à `"Logout1"` qui
montre un Toast "NoConnect") — juste la fermeture silencieuse du dialogue de progression, session
locale intacte.

**iOS avant correctif** : `try?` sur `ProfileRepository.shared.logout`/`deleteAccount` avalait
silencieusement toute erreur réseau, laissant `LocalDataPurger.purgeAll()`/
`UserSession.shared.clear()`/`.userDidLogout` s'exécuter INCONDITIONNELLEMENT — pour la
suppression de compte en particulier, un échec réseau signifiait que le compte N'ÉTAIT PAS
supprimé côté serveur, mais que tout le cache local ET la session étaient quand même détruits,
éjectant l'utilisateur vers l'écran de connexion en lui faisant croire son compte supprimé.

**Doublon confirmé** : ce finding est IDENTIQUE à **V5-F-005** (même code exact,
`SettingSubViews.swift:35-61`, même citation Android, même cause, même recommandation) — trouvé
indépendamment par 2 agents différents de la Phase A (domaines "Session" et "Gestion d'erreur
transversale"). Corrigé UNE SEULE FOIS ici (V5-F-064, le P0) ; V5-F-005 sera marqué `DUPLICATE`
sans modification de code lorsque le backlog P1 l'atteindra.

### Correctif appliqué

`try?` remplacé par `do/catch` dans `logout()` et `deleteAccount()` : la purge/déconnexion locale
ne s'exécute plus que dans la branche succès. Ajout d'un `@State private var errorMessage: String?`
+ `.alert` pour donner un minimum de retour utilisateur sur l'échec — écart volontaire mineur par
rapport à Android (qui n'affiche AUCUN texte pour ces 2 cas précis, juste `dialog.dismiss()`),
documenté explicitement : la garde essentielle (pas de purge tant que le serveur n'a pas confirmé)
reste fidèle, seul l'ajout d'un message minimal diverge, au bénéfice de l'utilisateur (éviter qu'un
tap sans effet visible ne semble être un bug côté iOS).

### Flux frères vérifiés

`grep "ProfileRepository.shared.logout\|ProfileRepository.shared.deleteAccount"` → exactement 2
sites d'appel dans tout le projet, tous deux dans `SettingAccountView`, tous deux corrigés.

**Fichiers modifiés** : `Sources/TiinverSwift/Settings/SettingSubViews.swift`.

**Résultat CI** : commit `dd67146`, push confirmé (`7df099a..dd67146 main -> main`), run
`32894676015` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED` (CI verte confirmée). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : couper le réseau puis tenter une déconnexion ET
une suppression de compte, confirmer dans les deux cas qu'aucune purge locale ne se produit, que
l'utilisateur reste connecté, et qu'un message d'erreur s'affiche.

---

# BACKLOG P0 ENTIÈREMENT TRAITÉ (7/7 findings)

Répartition finale : 7 `BUILD_VALIDATED` — V5-F-094 (export MP4 Animems), V5-F-018 (chat scroll +
cascade pagination), V5-F-031 (rewardedCoins), V5-F-032 (retrait/transfert/conversion), V5-F-042
(verrouillage timeline Animems), V5-F-045 (clé JSON commentaire), V5-F-064 (logout/suppression
compte, doublon de V5-F-005 résolu en même temps). Aucun `BLOQUÉ`, aucun `DIFFÉRÉ` — tous les P0
étaient de vraies divergences fonctionnelles corrigeables sans dépendance externe. Aucun
`COMPLETE_PARITY_VALIDATED` — conforme à la règle stricte du cycle.

Backlog P1 (40 findings) démarré immédiatement après, sans confirmation utilisateur
supplémentaire, conformément à l'instruction explicite de continuation automatique.

## 2026-08-24 — Phase B V5 — Lot P1-1 : V5-F-001 (BUILD_VALIDATED)

### Vérification

**Android** : `AndroidManifest.xml:347-353` confirme `CallActivity`/`IncomingCallActivity` comme
Activities `exported` indépendantes. `CallService.java:571-617` confirme leur lancement
inconditionnel via `FLAG_ACTIVITY_NEW_TASK` depuis un Service, atteignables par-dessus n'importe
quel écran.

**iOS avant correctif** : `CallView` n'était présenté que via un `.fullScreenCover` LOCAL à
`ChatView` — si l'utilisateur n'était pas précisément sur le ChatView de la conversation en cours
d'appel (autre onglet, autre conversation, app relancée en arrière-plan après réponse CallKit
depuis l'écran verrouillé), aucun contrôle muet/haut-parleur/raccrocher n'était disponible.

### Correctif appliqué

`.fullScreenCover` déplacé de `ChatView.swift` vers `RootRouterView.swift` — choisi plutôt que
`HomeShellView.swift` car un commentaire existant dans `RootRouterView.swift` confirme que
`CallCoordinator.start()` peut déjà être actif AVANT authentification ; seul `RootRouterView`
(monté dans TOUS les états de l'app) garantit la disponibilité totale. L'alerte "Micro requis"
reste dans `ChatView.swift`, liée au bouton d'appel sortant qui vit sur cet écran précis.

**Fichiers modifiés** : `Sources/TiinverSwift/Navigation/RootRouterView.swift`,
`Sources/TiinverSwift/Messagerie/ChatView.swift`.

**Résultat CI** : commit `7c77d7b`, push confirmé (`a59e01b..7c77d7b main -> main`), run
`32912327146` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis (device + backend d'appel fonctionnel).

## 2026-08-24 — Phase B V5 — Lot P1-2 : V5-F-005 (DUPLICATE de V5-F-064)

Code exact identique (`SettingSubViews.swift:35-61`), même citation Android, même cause, même
recommandation que V5-F-064 (P0, déjà corrigé — commit `dd67146`, CI run `32894676015`). Trouvé
indépendamment par 2 agents distincts de la Phase A. Aucune modification de code supplémentaire,
conformément à la règle « ne pas modifier le code inutilement » pour un finding déjà résolu par un
autre commit.

**Fichiers modifiés** : `MIGRATION_PARITY_AUDIT_V5.md` (STATUT `DUPLICATE` uniquement).

## 2026-08-24 — Phase B V5 — Lot P1-3 : V5-F-006 (BUILD_VALIDATED)

### Vérification

**Android** : `FeedFragment.java:1246-1247,1360-1365` — `R.id.download` inclus dans le menu "..."
du plein écran Home, câblé sur `addingDownloadingFileToQueue`/`checkBestQualityAndDownload`,
masqué uniquement sur les posts PROPRES via `idContentHide`.

**iOS avant correctif** : `FeedView.swift`'s `.fullScreenCover` (grille Home) n'appelait PAS
`includesDownload: true` — la garde `if !isOwnPost { if includesDownload { ... } }` existait déjà
et reproduisait fidèlement le masquage Android, seul le paramètre manquait.

### Correctif appliqué

`includesDownload: true` ajouté à l'appel de `FeedDetailPagerView` dans le `.fullScreenCover` du
fil Home. Corrigé au passage le commentaire stale de `FeedMediaDownloader.swift` (affirmait à tort
que Profile était le SEUL contexte Android câblé — analyse incomplète, n'avait pas vérifié
`FeedFragment.java`).

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedView.swift`,
`Sources/TiinverSwift/Feed/FeedMediaDownloader.swift`.

**Résultat CI** : commit `8157db3`, push confirmé (`95db132..8157db3 main -> main`), run
`32913100968` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : confirmer "Télécharger" visible sur les posts d'autrui, absent sur ses propres posts.

## 2026-08-24 — Phase B V5 — Lot P1-4 : V5-F-007 (BUILD_VALIDATED)

### Vérification

**Android** : `FeedFragment.java:1351-1359` — branche `report_content` du plein écran Home remplit
`target_id`/`report_type="content"` en plus de userId/username/nikname ; `Report.java:70-71,149-150`
lit ces champs depuis l'Intent et les envoie dans le `map` POST vers l'endpoint `report`.
`ProfileFeedFragment.java`/`HashtagProfile.java` (leurs plein écrans respectifs) confirmés faire de
même. `MainFragment.OnclickMoreExpand` (la grille) les laisse vides — 2 comportements Android
distincts selon la classe appelante.

**iOS avant correctif** : `FeedViewModel.report(_:reason:)` / `FeedRepository.reportUser` étaient
appelées IDENTIQUEMENT par la grille ET par `FeedDetailPagerView` (plein écran), `target_id`/
`report_type` codés en dur à `""` dans les deux cas — le commentaire du fichier ne citait que
`MainFragment` comme référence, sans avoir vérifié le cas plein écran.

### Correctif appliqué

Nouveau paramètre `includesTarget: Bool = false` sur `FeedViewModel.report`/
`FeedRepository.reportUser` (défaut `false`, préservant le comportement vide existant de la grille,
site d'appel `FeedView.swift` ~ligne 259 inchangé). `FeedDetailPagerView.confirmationDialog`
(~ligne 653) — struct UNIQUE partagé par 6 écrans parents (Home/Profile/Hashtag/Search/
Notifications/HomeShellView deep-link) — passe désormais `includesTarget: true`, corrigeant
correctement TOUS ces contextes plein écran d'un seul coup.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedRepository.swift`,
`Sources/TiinverSwift/Feed/FeedViewModel.swift`, `Sources/TiinverSwift/Feed/FeedView.swift`.

**Résultat CI** : commit `3845bc5`, push confirmé (`2b3b7a6..3845bc5 main -> main`), run
`32913810419` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis (accès back-office modération) : signaler un post depuis le plein écran, confirmer
`target_id`/`report_type` remplis côté serveur ; signaler depuis la grille, confirmer qu'ils
restent vides.

## 2026-08-25 — Phase B V5 — Lot P1-5 : V5-F-009 (BUILD_VALIDATED)

### Vérification

**Android** : `MainFragment.java:481-489` (`loadResetData`, appelée par `HomeActivity.java:182` au
nouveau tap sur l'onglet Accueil) — ne teste AUCUN flag `loading`/`isLoadingMore` avant de relancer
`executeBackTask()` : le rafraîchissement (page 1, offset 0) est TOUJOURS déclenché, même si une
pagination (`loadMoreData`, ligne 505-517) est en cours.

**iOS avant correctif** : `FeedViewModel.swift` — `reset()` réutilisait la MÊME fonction
`loadNextPage()`, protégée par le MÊME verrou `isLoading`, que la pagination infinie
(`FeedView.swift`, seuil `count-2`). Scénario reproductible : pagination en vol
(`isLoading=true`) → tirage pour rafraîchir → `reset()` vide `posts`/`offset` puis appelle
`loadNextPage()` qui retourne aussitôt (`guard !isLoading`, toujours vrai) → la réponse de
pagination obsolète (ancienne page) s'applique ensuite au tableau fraîchement vidé → doublons à la
pagination suivante, vraie page 1 jamais récupérée.

### Correctif appliqué

Jeton de génération : `private var loadGeneration = 0` sur `FeedViewModel`. `reset()` incrémente la
génération et appelle directement une nouvelle fonction privée `fetchPage(generation:)` (bypass du
verrou `isLoading`, fidèle au comportement Android "toujours déclenché"). `loadNextPage()` reste
gardée par `guard !isLoading` (fidèle à la pagination infinie, inchangée) et délègue aussi à
`fetchPage(generation:)`. `fetchPage` rejette toute réponse réseau dont la génération est périmée
(`guard generation == loadGeneration else { discard; return }`) avant tout traitement de page.

**Course auto-détectée avant commit** : le `defer` de remise à `isLoading = false` devait être
conditionné à la génération courante (`defer { if generation == loadGeneration { isLoading = false } }`)
— sinon une tâche périmée résolue APRÈS un `reset()` plus récent aurait pu effacer à tort le
spinner d'une pagination encore en vol. Tracé manuellement les deux ordres de résolution réseau
possibles pour confirmer l'absence de course résiduelle dans les deux cas.

**Flux frère vérifié** : `grep` sur tous les appelants (`.refreshable`, seuil de pagination
infinie, bouton retry, reset post-publication) — tous routés par le même `FeedViewModel` partagé,
aucune modification nécessaire de leur côté.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedViewModel.swift`.

**Résultat CI** : commit `f5096d3`, push confirmé (`3845bc5..f5096d3 main -> main`), run
`32914485375` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : atteindre le seuil de pagination infinie, tirer pour rafraîchir avant la réponse
réseau, confirmer l'absence de flux figé sur une ancienne page et l'absence de doublons à la
pagination suivante.

## 2026-08-25 — Phase B V5 — Lot P1-6 : V5-F-010 (BUILD_VALIDATED)

### Vérification

**Android** : `UniversalSearchAdapter.java`, `PostViewHolder.bind()` lignes 270-282 — fallback
simple à DEUX étages : `item.getThumbnail()` (`cdn_thumbnail_url`) non vide → l'utiliser ; sinon
`item.getContentUrl()` (`cdn_content_url`) non vide → l'utiliser ; sinon fond gris uni. Aucune
branche vidéo/photo, `object_url` (pourtant stocké via `setObjectUrl`) n'est JAMAIS lu par ce
ViewHolder — confirmé par lecture complète de `bind()`.

**iOS avant correctif** : `SearchPostResult.thumbnailURL` réimplémentait l'algorithme de priorité
CDN générique utilisé pour `FeedActivity` (fil principal) : `isVideo`/`hasContentId` déterminés,
puis repli sur `object_url` dès que `cdn_content_id` était absent/NULL/vide — même si
`cdn_thumbnail_url`/`cdn_content_url` était renseigné et non vide.

### Correctif appliqué

Cause confirmée : le correctif V3-F-009 (2026-08-19) avait par erreur porté la logique de
`FeedActivity.thumbnailURL` (endpoint différent où `object_url` fait foi) sur cette structure,
alors qu'`UniversalSearchAdapter` a sa propre logique bien plus simple pour l'endpoint
`content/search`. `SearchPostResult.thumbnailURL` réécrit en fallback à deux étages littéral,
suppression complète de `isVideo`/`hasContentId`/`object_url` de cette propriété. Diff minimal et
strictement localisé.

**Flux frère vérifié** : `grep thumbnailURL` — un seul site d'appel (`SearchView.swift:264`),
aucun autre écran affecté. `asFeedActivity` (conversion pour le plein écran au tap) inchangée,
utilise ses propres champs CDN sans lien avec cette propriété.

**Fichiers modifiés** : `Sources/TiinverSwift/Discover/SearchModels.swift`.

**Résultat CI** : commit `9418ef4`, push confirmé (`9f33822..9418ef4 main -> main`), run
`32915044191` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : rechercher un terme retournant des posts avec `cdn_content_id` absent/NULL/vide mais
`cdn_thumbnail_url` renseigné, confirmer l'affichage correct de la vignette CDN dans la grille
"Publications".

## 2026-08-25 — Phase B V5 — Lot P1-7 : V5-F-013 (BUILD_VALIDATED)

### Vérification

**Android** : `UserProfile.java:1094-1145` (`block()`), branche `USER_UNBLOCKED` lignes 1118-1124
— `isBlocked=false` PUIS appel explicite à `loadInitialData()` (ligne 1123) →
`executeTask()`(lignes 723-727, gardée par `if (!isBlocked)`) → `profileViewModel.executeBackTask(...)`,
relançant immédiatement la requête de la première page de médias et republiant la grille sans que
l'utilisateur quitte/revienne sur l'écran.

**iOS avant correctif** : `ProfileViewModel.toggleBlock()` mettait à jour `isBlocked` mais
n'appelait QUE `if blocked { posts = [] }` — rien n'était fait quand `blocked == false`. Comme
`posts` avait été vidé au blocage et qu'aucun élément n'était présent pour déclencher le
`.onAppear` qui relance `loadMorePosts()`, la grille restait vide indéfiniment après un déblocage
réussi, jusqu'à sortie/retour complet de l'écran (nouvelle instance de `ProfileViewModel`).

### Correctif appliqué

Cause : port incomplet de `UserProfile.java:1123` — seul le cas "bloquer" avait été porté, pas le
cas symétrique "débloquer". `toggleBlock()` gagne un `else` symétrique au `if blocked { posts = [] }`
existant, appelant `await loadInitialPosts()` (déjà porté pour V4-F-014 : reset `offset=0`/
`reachedEnd=false`/`posts=[]` puis `loadMorePosts()`) quand `blocked == false`. Diff strictement
additif.

**Fichiers modifiés** : `Sources/TiinverSwift/Profile/ProfileViewModel.swift`.

**Résultat CI** : commit `797e43e`, push confirmé (`c6fed06..797e43e main -> main`), run
`32915890209` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : bloquer puis débloquer un utilisateur depuis son profil, confirmer la republication
immédiate de la grille de posts.

## 2026-08-25 — Phase B V5 — Lot P1-8 : V5-F-016 (BUILD_VALIDATED)

### Vérification

**Android** : `ChatFragmentTest.java:727-728` (`checkSubcribtion`) — endpoint exact
`group/checksubscription2/{userId}/{groupId}` (suffixe "2"), appelé dès l'ouverture d'une
conversation de groupe par un membre existant. Réponse `error:"true"` avec `message` =
`"subscription expires."`/`"Restricted access."` masque la barre de saisie et insère une bannière
"renouveler"/"s'abonner". Grep exhaustif confirmant qu'aucune autre occurrence de cet endpoint
n'existe dans tout le code Android (pas de variante sans suffixe).

**iOS avant correctif** : `GroupRepository.checkSubscription` appelait
`group/checksubscription/{userId}/{groupId}` — SANS le suffixe "2". Combiné au `try? ... else {
return .active }` existant, tout échec réseau (404 sur une route inexistante) retombait
silencieusement sur `.active`, empêchant `checkGroupSubscription()` de jamais atteindre les
branches `.expired`/`.restricted` : le composeur n'était jamais bloqué pour un abonnement payant
expiré/restreint.

### Correctif appliqué

Endpoint corrigé : `group/checksubscription` → `group/checksubscription2`. Repli optionnel de la
RECOMMANDATION (distinguer un échec réseau franc du repli `.active`) délibérément NON appliqué :
vérifié que l'`onError` Android de `checkSubcribtion` ne fait lui-même rien de spécial sur échec
réseau (pas de blocage) — le "fail open" du `try?` existant est déjà fidèle à Android, seul le
suffixe d'endpoint était la vraie divergence. Diff strictement localisé (1 ligne + commentaire).

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/GroupRepository.swift`.

**Résultat CI** : commit `904d77a`, push confirmé (`8db4f0c..904d77a main -> main`), run
`32916536677` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : ouvrir la conversation d'un groupe payant avec abonnement expiré/restreint côté
serveur, confirmer le blocage du composeur et l'affichage de la bannière.

## 2026-08-25 — Phase B V5 — Lot P1-9 : V5-F-019 (BUILD_VALIDATED)

### Vérification

**Android** : `MissedViewHolder.java:15-39` (`onClick` → construit `ResultData` avec
`object=ResultData.CALL`) → `ChatFragmentTest.java:561-563` (le listener détecte `ResultData.CALL`
et appelle `mListener.onArticleSelected(8,null)`) → `ActivityMsg.java:516-518` (`case 8:
startCall();` — même méthode que le bouton d'appel de la barre d'outils). Un tap sur une bulle
"appel manqué"/"appel vocal" déclenche exactement la même action que le bouton toolbar : appel
sortant relancé immédiatement.

**iOS avant correctif** : `ChatView.swift:190-191` — `MissedCallBubbleRow(message:text:) { }`, le
paramètre `onTap` est une fermeture totalement VIDE. Le composant lui-même
(`ChatBubbleViews.swift:306-322`) est un `Button` fonctionnel, câblé côté vue ; le fichier possède
déjà `outgoingCallProfile`/`callCoordinator.startOutgoingCall(...)` utilisés juste à côté pour le
bouton toolbar (lignes 356-359/385).

### Correctif appliqué

Cause : point d'entrée UI non câblé lors du portage. Fermeture `onTap` remplacée par
`callCoordinator.startOutgoingCall(profile: outgoingCallProfile, chatType: viewModel.target.type)`,
gardée par `guard callCoordinator.state == .idle else { return }` — même garde que le bouton
toolbar (`.disabled(callCoordinator.state != .idle)`), empêchant un double-appel concurrent.
`callCoordinator`/`outgoingCallProfile` déjà en portée (propriétés `ChatView`).

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/ChatView.swift`.

**Résultat CI** : commit `8bacdcb`, push confirmé (`f4ae1c6..8bacdcb main -> main`), run
`32917273673` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : taper sur une bulle "appel manqué"/"appel vocal", confirmer le déclenchement d'un
appel sortant.

## 2026-08-25 — Phase B V5 — Lot P1-10 : V5-F-020 (BUILD_VALIDATED)

### Vérification

**Android** : `ChatFragmentTest.java:985-995` (`loadMoreFromServeur`, déclenché uniquement pour un
GROUPE) ; `:1415-1430` (`onLoadFinished` : si le `CursorLoader` local retourne 0 ligne pendant un
'load more', `hasLocalData=false` puis appel de `loadMoreFromServeur()`) ; `:203/1731` (`lastDate`
= stamp du plus ancien message déjà chargé) ; `ChatViewModel.java:128-130` (délègue à
`chatRepository.loadMoreFromServeur`) ; `ChatRepository.java:1129-1177` (`GET
/group/{groupId}/messages?lastDate={lastDate}&limit={limit}`, `error` en booléen JSON natif) ;
`ChatManager.java:1090-1155` (`prepareOldGroupMessage` : parse `data`, persiste via
`addGroupMessage(meta,true/false)`, propage à l'UI via `sendLiveData(ChatModel.OLDMESSAGE)`).
Chaîne complète confirmée atteignable, tous les maillons s'appellent réellement.

**iOS avant correctif** : `ChatViewModel.loadMore()` interrogeait UNIQUEMENT le cache Core Data
local (`MessageRepository.page`) ; si la page était vide, retour immédiat sans aucun appel réseau
de repli. Grep exhaustif sur `group/*/messages`/`loadMoreFromServeur`/`lastDate` : AUCUN résultat,
fonctionnalité absente même partiellement.

### Correctif appliqué

Nouvelle méthode `GroupRepository.fetchOlderGroupMessages(groupId:lastDate:limit:)` — décodage
per-item + diagnostic, même motif que `fetchMembers`/`searchGroups` (même fichier). `error` booléen
JSON natif déjà toléré par `isBackendSuccess`/`errorFieldNormalized` sans changement.
`ChatViewModel.loadMore()` bascule sur une nouvelle `loadOlderGroupMessagesFromServer()` quand la
page locale est vide, UNIQUEMENT pour un groupe (`target.isGroup`) — `lastDate` calculé depuis le
premier message présent dans `items` (déjà en ordre chronologique croissant). Persistance par
message via `MessageRepository.addGroupMessage` (déjà existant, aucune modification). Résultats
triés chronologiquement avant insertion en tête d'`items` (l'ordre exact renvoyé par cet endpoint
n'a pas pu être confirmé par lecture du seul code Android ; la page locale équivalente est déjà
toujours croissante avant insertion en tête, ce repli reproduit la même garantie).

**Portée délibérément limitée** : `ChatManager.prepareOldGroupMessage` contient aussi des branches
spéciales pour `object == "voicecall"`/`"missedvoicecall"` déclenchant des effets de bord de
signalisation d'appel (`CallService.isOnCall`, déclin/lancement d'appel) — spécifiques à
l'infrastructure d'appel Android, sans équivalent 1:1 évident avec `CallCoordinator` iOS, et hors
du périmètre de ce finding (Socket.IO/historique, pas Calls). Seule la branche générique
(persister + afficher) est portée, documenté explicitement dans le code plutôt que deviné.

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/GroupRepository.swift`,
`Sources/TiinverSwift/Messagerie/ChatViewModel.swift`.

**Résultat CI** : commit `d136a68`, push confirmé (`3f46ca1..d136a68 main -> main`), run
`32918138299` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : conversation de groupe avec historique local incomplet, scroller au-delà du cache
local, confirmer le chargement depuis le serveur sans troncature silencieuse.

## 2026-08-25 — Phase B V5 — Lot P1-11 : V5-F-021 (BUILD_VALIDATED)

### Vérification

**Android** : `back_sync/NotificationUtils.java:290-338` (`displayNoMessageNotification`) et
`:103-153` (`displayNotificationOrPushMessage`) — les deux construisent la destination via
`String destination = "MainActivity";` puis `show()` fait `new Intent(mContext,
activityMap.get(destination))` où `activityMap.put("MainActivity", SplashActivity.class)` — le
tap sur N'IMPORTE QUELLE notification (activité OU message de chat) ouvre l'écran d'accueil
générique, jamais un centre de notifications.

**iOS avant correctif** : `AppDelegate.userNotificationCenter(_:didReceive:)` appelait
systématiquement `DeepLinkCenter.shared.route(.notifications)`, y compris pour les notifications
de message de chat (`LocalNotificationBuilder.chatMessageNotificationContent`, sans
`categoryIdentifier` distinct) — ouvrant une sheet `NotificationsListView` sans AUCUNE trace des
messages de chat.

### Correctif appliqué

Cause : le commentaire de justification affirmait à tort que router vers `.notifications`
reproduisait `activityMap.get("MainActivity")` par défaut côté Android — mais ce mapping pointe
vers l'écran d'accueil, pas un centre de notifications. Correctif : `content.categoryIdentifier =
"activity"` ajouté dans `activityNotificationContent`, `"chat_message"` dans
`chatMessageNotificationContent` (les deux écrasés par `"missed_call"` pour la branche existante,
inchangée). `didReceive` route désormais `.notifications` UNIQUEMENT pour `categoryIdentifier ==
"activity"`, `.home` (déjà câblé, `HomeShellView.swift:283`) pour tout le reste.

**Fichiers modifiés** : `Sources/TiinverSwift/App/AppDelegate.swift`,
`Sources/TiinverSwift/Notifications/LocalNotificationBuilder.swift`.

**Résultat CI** : commit `846eae1`, push confirmé (`648d4fc..846eae1 main -> main`), run
`32919120599` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : taper sur une notification de chat (ouvre l'accueil) et sur une notification
d'activité (ouvre le centre de notifications).

## 2026-08-25 — Phase B V5 — Lot P1-12 : V5-F-022 (BUILD_VALIDATED)

### Vérification

**Android** : `NotiLikecmt/AdapterNoti.java:420-441` (`FollowVH.bind`'s
`butSeguir.setOnClickListener`) — `td.Post(map, "followback", ...)` avec `{userId: e.userId,
followId: myId}`. SEUL appelant de l'endpoint `followback` dans tout le code Android (vérifié).
`Http/TransportData.java:1428-1430` (`Following()` → `volleyPost(..., "follow")`) utilisé par
`SuggestionVH` (ligne 511, "suggestions de comptes"), endpoint DIFFÉRENT.

**iOS avant correctif** : `NotificationsListView.swift`, bouton "Suivre en Retour" — appelait
`ProfileRepository.shared.follow(userId: String(noti.userId), followerId: myId)`, qui poste
TOUJOURS sur l'endpoint générique `follow`, jamais `followback`.

### Correctif appliqué

Cause : le portage a réutilisé le repository de follow générique déjà existant au lieu de
reproduire l'appel réseau spécifique de `FollowVH`. Correctif : nouvelle méthode
`ProfileRepository.followBack(userId:followerId:)` (mêmes paramètres `{userId, followId}` que
`follow`, endpoint `followback`), site d'appel du bouton basculé dessus. Rollback optimiste (fix
V3-F-107 antérieur, même fichier) préservé sans modification.

**Flux frère vérifié** : grep sur `ProfileRepository.shared.follow(` — 3 autres appelants
(`FollowListView.swift`, `SearchView.swift`, `SuggestionsCarouselView.swift`) confirmés inchangés,
fidèles à l'endpoint `follow` générique.

**Fichiers modifiés** : `Sources/TiinverSwift/Profile/ProfileRepository.swift`,
`Sources/TiinverSwift/Notifications/NotificationsListView.swift`.

**Résultat CI** : commit `2a41e27`, push confirmé (`3ffe89a..2a41e27 main -> main`), run
`32919699798` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : taper "Suivre en Retour" depuis le centre de notifications, confirmer via
inspection réseau que la requête cible `followback`.

## 2026-08-25 — Phase B V5 — Lot P1-13 : V5-F-023 (BUILD_VALIDATED)

### Vérification

**Android** : `NotiLikecmt/AdapterNoti.java:586-600` (`bindAvatarClick`, attaché SEULEMENT à
`contentAvatar` → `UserProfile`) et `:612-625` (`bindBodyClick`, attaché au conteneur `body` =
titre/texte → `FullScreenMedia` si `activityId>0`, sinon `body.setClickable(false)` explicite).
Deux zones tapables DISTINCTES avec deux destinations différentes, indépendamment de la présence
d'une vignette (`bindThumb`, `:564-584`, peut masquer tout le conteneur photo sans désactiver le
clic sur `body`).

**iOS avant correctif** : `NotificationsListView.swift` — bloc avatar+nom+texte enveloppé dans un
SEUL `NavigationLink` allant TOUJOURS vers `ProfileView`. Seul accès au post : le bouton vignette
séparé, existant UNIQUEMENT si `thumbnailURL != nil` — absent pour un post texte (sans photo/
vidéo).

### Correctif appliqué

Cause : le portage a fusionné les deux zones tapables Android (avatar→profil, corps→post) en une
seule (avatar+texte→profil). Correctif : `NavigationLink` restreint à l'avatar seul
(inconditionnel → profil) ; bloc nom/texte extrait en `nameAndBodyText` (`@ViewBuilder`),
enveloppé dans un `Button` → `onOpenPost(post)` quand `reconstructedPost != nil` (`activityId>0`),
sinon affiché tel quel non tapable — fidèle à `body.setClickable(false)`, pas un `Button`
désactivé. Bouton vignette séparé (existant, hors périmètre) laissé inchangé.

**Fichiers modifiés** : `Sources/TiinverSwift/Notifications/NotificationsListView.swift`.

**Résultat CI** : commit `e49cb70`, push confirmé (`a72684c..e49cb70 main -> main`), run
`32920326997` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : like/commentaire sur un post texte, taper le texte de la notification (ouvre le
post), taper l'avatar (ouvre le profil).

## 2026-08-25 — Phase B V5 — Lot P1-14 : V5-F-029 (BUILD_VALIDATED)

### Vérification

**Android** : `messagerie/ui/call/CallActivity.java:85` (`isCalleMissedCall=true` à l'init) ;
`:483-500` (`callBusy()` : affiche "Occupé" 3s puis `initEndCall(false)`, ne réinitialise JAMAIS
`isCalleMissedCall`) ; `:376-384` (`initEndCall` → `endCall()`) ; `:509-525` (`endCall()` :
`if(isCalleMissedCall) callService.notifyMissedCall(...)` — flag remis à `false` UNIQUEMENT dans
`callEnd()` [:476] et `onAccepCall()` [:506], jamais dans `callBusy()`) ;
`messagerie/repository/ChatRepository.java:1045-1057` (`notifyMissedCall` insère un message
"missedvoicecall" persistant).

**iOS avant correctif** : `CallCoordinator.swift:111-112` (`case .busyCall:
endCallFromRemote(reason: .unanswered)`) ; `:326-330` (`endCallFromRemote` : `callKit.
reportCallEnded` + `teardown()`, AUCUN appel à `notifyMissedCall`) ; `:403-413` (`performEndCall`,
SEUL point d'appel de `notifyMissedCall`, uniquement sur raccroché LOCAL non répondu, jamais sur
`.busyCall`). L'appel se terminait sans laisser AUCUNE trace dans la conversation.

### Correctif appliqué

Cause : la fin d'appel a été factorisée en un point de sortie unique
(`teardown()`/`endCallFromRemote()`) qui ne reproduit pas la logique "`isCalleMissedCall` reste
`true` seulement si `callBusy`" d'Android. Correctif : dans `handle(.busyCall)`, appel à
`chatRepository.notifyMissedCall(profile:chatType:object:"missedvoicecall":messageId:)` — même
appel que `performEndCall` — avant `endCallFromRemote(reason: .unanswered)`, gardé par
`isOutgoingCall` (`CallActivity` n'existe côté Android QUE pour un appel sortant) et `profile`
non-nil.

**Fichiers modifiés** : `Sources/TiinverSwift/Calls/CallCoordinator.swift`.

**Résultat CI** : commit `61e9999`, push confirmé (`e57bb9f..61e9999 main -> main`), run
`32920903373` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis (2 appareils/comptes) : appeler un correspondant déjà en communication, confirmer
l'insertion d'un message "appel manqué" dans la conversation de l'appelant.

## 2026-08-25 — Phase B V5 — Lot P1-15 : V5-F-033 (BUILD_VALIDATED)

### Vérification

**Android** : `messagerie/layout/MessageEventLayout.java:238-301` — bouton morphant :
`OnRecordClickListener` (tap simple) envoie le texte courant si non vide ; `OnRecordListener`
(appui maintenu) gère `onStart`→`startRecording`/`onFinish`→`endRecord`/`onCancel`→`cancelRecord`/
`onLessThanSecond`→`cancelRecord`. `messagerie/AudioManager.java:105-112` : `MediaRecorder`,
`AudioSource.MIC`, `OutputFormat.THREE_GPP`, `AudioEncoder.AMR_NB` — encodage RÉEL AMR_NB/3GP, pas
une étiquette trompeuse. `ChatFragmentTest.java:823-826`/`:1355-1358` : `onVoiceMessage` →
`sendAudioMessage` → `prepareFileMessage(detail,"audio",null)`, même pipeline que photo/vidéo.

**iOS avant correctif** : AUCUN bouton micro dans la barre de composition
(`ChatView.swift:270-317`), `ChatViewModel.sendMedia`/`attachMedia` ne géraient que photo/vidéo,
grep exhaustif `AVAudioRecorder` = 0 résultat dans tout le projet — fonctionnalité d'ENVOI
totalement absente (la RÉCEPTION/lecture fonctionnait déjà, `ChatBubbleViews.swift`
`AudioBubbleBody`).

### Correctif appliqué

Nouveau fichier `VoiceRecorder.swift` : `AVAudioRecorder` (AAC/`.m4a`), permission micro via
`AVAudioSession.recordPermission`/`requestRecordPermission` (déclenche la demande système comme
`listener.askPermission()` Android), `start()`/`stop()`/`cancel()`, annulation automatique si
enregistrement <1s (port de `onLessThanSecond`). Bouton morphant câblé dans `ChatView.inputBar` :
tap→texte si non vide (inchangé), `DragGesture(minimumDistance: 0)`→appui maintenu déclenche
l'enregistrement si vide (`onChanged`, gardé par `isStartingVoiceRecording` pour ne démarrer
qu'une fois), glissement >80pt vers la gauche avant relâchement→annulation (port du hint
`RecordView` "glisser pour annuler"), sinon envoi normal. Toute la barre de composition bascule en
affichage waveform+minuteur+hint pendant l'enregistrement (port du basculement
`messageViewContainer`↔`recordView`). Résultat routé SANS changement à travers
`ChatViewModel.sendMedia(object: "audio", …)` déjà existant.

**Écart technique documenté (pas une invention)** : `AVAudioRecorder` n'expose PUBLIQUEMENT aucun
encodeur AMR — capture en AAC/`.m4a` (seul format haute qualité largement disponible sans
bibliothèque de codec tierce). `ChatMediaUploadService.MessageMediaKind.audio` étiquette déjà
INCONDITIONNELLEMENT tout objet "audio" comme `audio/3gpp`/`.3gp` (comportement PRÉEXISTANT, non
modifié) — le fichier envoyé au CDN est donc du contenu AAC réel sous une étiquette `.3gp`.
**Risque réel NON résolu** : la lecture d'un message vocal envoyé par iOS pourrait échouer côté
récepteur Android si son décodeur suppose strictement un flux AMR_NB.

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/VoiceRecorder.swift` (nouveau),
`Sources/TiinverSwift/Messagerie/ChatView.swift`.

**Résultat CI** : commit `b9e549f`, push confirmé (`61e9999..b9e549f main -> main`), run
`32921757759` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel PRIORITAIRE et CROISÉ (2 appareils) requis : enregistrer/envoyer un message vocal depuis iOS,
confirmer sa lecture correcte côté récepteur Android (risque de codec, point le plus critique) ;
confirmer aussi le geste d'annulation par glissement et le blocage <1s.

## 2026-08-25 — Phase B V5 — Lot P1-16 : V5-F-034 (BUILD_VALIDATED, portée réduite documentée)

### Vérification

**Android** : `engine/.../AnimemesCompound.java:2108-2113` (clic `ic_add` → `addBitmapFromGallerie()`),
`:2251-2253` (→ `animemesListener.onOpenGalleryImageOnly()`) ; `MemesFragment.java:386-388`
(`onOpenGalleryImageOnly()` → `pickOnlyImage()`), `:551-559` (sélecteur filtre
`PickVisualMedia.ImageAndVideo`), `:561-587` (callback : si vidéo, `videotrimmer.setVideoUri(uri)`
+ `setVisibility(VISIBLE)`), `:233-267` (`videotrimmer.setVideoTrimmerListener` → `onBitmaps` →
`animemes_compound.addBitmaps(bitmaps, 33)`). Chemin réellement atteignable confirmé.

**iOS avant correctif** : `AnimemesEditorView.swift:167-178`, `onVideoPicked: { _ in
showGalleryPicker = false }` — la vidéo sélectionnée était totalement jetée, aucun trimmer, aucune
extraction, aucun calque ajouté, fermeture silencieuse sans aucune indication.

### Correctif appliqué (portée réduite, documentée)

Investigation avant codage : `MediaTrimView.swift` existe déjà mais produit un fichier vidéo
RÉ-ENCODÉ (`AVMutableComposition`), pas une séquence de bitmaps pour un calque canevas — périmètre
différent de `VideoTrimmerView`/`addBitmaps` Android. `AnimemesEditorState.addCapturedPaintFrames`
existe (mécanisme structurellement proche) mais la géométrie exacte calque/canevas attendue n'a
pas été confirmée suffisamment pour improviser un `addVideoFrames(...)` fiable. Plutôt que de
deviner cette géométrie (risque de bug canevas silencieux), correctif du repli EXPLICITEMENT
autorisé par la RECOMMANDATION de l'audit elle-même : `onVideoPicked` affiche maintenant une
alerte claire ("Vidéo non prise en charge") au lieu de fermer silencieusement la feuille.

**Portage complet reporté** : trim temporel + extraction de trames + intégration calque nécessite
une lecture complète de `AnimemesEditorState.swift` (géométrie canevas) avant implémentation
fiable — non tenté ce tour, pas deviné.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/AnimemesEditorView.swift`.

**Résultat CI** : commit `f49cafc`, push confirmé (`6e88fdc..f49cafc main -> main`), run
`32922541422` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`, portée réduite documentée (pas le
portage complet). PAS `COMPLETE_PARITY_VALIDATED` — test réel requis : choisir une vidéo depuis la
galerie Animems, confirmer l'alerte au lieu d'un échec silencieux.

## 2026-08-25 — Phase B V5 — Lot P1-17 : V5-F-036 (BUILD_VALIDATED, écart architectural documenté)

### Vérification

**Android** : `ImageViewCanvas.java:317-326` (`deletePrecedenteDraw`, opère sur
`composer.getPaintLayers()`, garde vide) ; `core/AnimationComposer.java:10,46-47` (`paintLayers`
ArrayList SÉPARÉE de `layers`) ; câblage bouton `ImageEditorCompound.java:353,458-460`/
`AnimemesCompound.java:341,460,1939` ; visibilité limitée au mode peinture
(`ImageEditorCompound.java:565` show/`:590,761` gone, même pattern `AnimemesCompound.java:
2085/2099/1809`) ; traits ajoutés via `composer.addPaintLayer()` (`ImageViewCanvas.java:
1795-1798,1022-1024`), JAMAIS dans `getLayers()`. `startDraw()` : `drawPath(canvas)` appelé AVANT
la boucle sur `getLayers()` — traits toujours composités en arrière-plan, JAMAIS animés (pas de
lookup transform indexé par frame pour `paintLayers`).

**iOS avant correctif** : `AnimationComposer.swift` — `paintLayers`/`addPaintLayer()` portés
fidèlement mais JAMAIS appelés/lus ailleurs dans tout le module (vérifié exhaustivement).
`AnimemesEditorState.removeLast()` : commentaire de tête affirmant À TORT la fidélité, faisait
`composer.setLayers(Array(composer.layers.dropLast()))` — retire le DERNIER calque TOUTES
catégories confondues. `addFreehandDrawing` ajoute le trait comme calque `.bitmap` ORDINAIRE via
`composer.addLayer()`. Bouton undo toujours visible (`bottomToolbar`, aucune condition de mode),
`.disabled(state.layers.isEmpty)`.

### Correctif appliqué

**Écart architectural assumé, documenté explicitement** : reproduire la séparation de conteneur
RÉELLE + composition "toujours en arrière-plan" exigerait de toucher 3 sites de rendu distincts
(canevas live `AnimemesEditorView.swift` ~485-499, miniature/preview ~644-655, export MP4/image
`AnimemesExporter.swift` ~292-312) — hors périmètre d'un correctif P1 unique, risque réel de
rendre des traits invisibles dans un contexte oublié si mal exécuté. Correctif appliqué à la
place : nouveau champ `AnimationObjectData.isFreehandStroke: Bool` (propagé dans `duplicate()`),
posé `true` par `addFreehandDrawing` — reste un calque `.bitmap` ordinaire dans `composer.layers`
(rendu/animation/export inchangés, zéro risque sur ces chemins). `removeLast()` retrouve et
retire spécifiquement le DERNIER calque marqué via `lastIndex(where:)` (pas positionnellement le
dernier élément du tableau, laissant tout le reste — stickers/images/texte ajoutés APRÈS le
trait — intact), garde `nil` si aucun trait présent (fidèle à la garde `paintLayers` vide
Android), efface `selectedId` s'il pointait vers le calque retiré (sécurité ajoutée, cohérente
avec `deleteSelected()`). Bouton undo : `.disabled` basculé vers
`!state.layers.contains { $0.isFreehandStroke }` — ne s'active plus que s'il existe un trait
undoable, empêchant la suppression silencieuse du dernier sticker/image/texte en son absence
(fidèle au comportement OBSERVABLE d'Android, sans reproduire le mode-gating de visibilité).

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/AnimationObjectData.swift`,
`Sources/TiinverSwift/Animems/AnimemesEditorState.swift`,
`Sources/TiinverSwift/Animems/AnimemesEditorView.swift`.

**Résultat CI** : commit `1d3ad22`, push confirmé (`34457d9..1d3ad22 main -> main`), run
`32923611967` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`, écart architectural documenté (mode-gated
visibility et composition "toujours en arrière-plan" non reproduits). PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : sticker → trait → sticker, confirmer qu'undo
retire le trait ; sans trait dessiné, confirmer que le bouton reste désactivé.

## 2026-08-25 — Phase B V5 — Lot P1-18 : V5-F-037 (IOS_INTENTIONAL_DIFFERENCE)

### Vérification

**Android** : `Utils/media/VideoTransformer.java:122-157` (`process()`) — `needsTransform =
(cropNorm != null) || (rotation != 0) || flipH`, IGNORE `startMs`/`endMs`. Pour tout trim sans
transformation géométrique, fast path `SimpleTrimmer.trim()` (`SimpleTrimmer.java:26-66,107-127`) :
remux SANS ré-encodage (<1s, aucune perte), calé sur la keyframe précédente la plus proche
(`correctTimeToSyncSample`), MÊME point corrigé appliqué à TOUTES les pistes y compris audio
(ligne 124, commentaire de code : "c'est le design voulu"). Incohérence interne notée : le
commentaire de TÊTE de `SimpleTrimmer.java` affirme à tort que l'audio démarre pile à `startMs` —
contredit par le code 25 lignes plus bas, confirmé par lecture directe plutôt que confiance au
commentaire.

**iOS avant correctif** : 2 correctifs précédents (V3-F-032, V3-F-124) affirmaient à tort qu'
"Android ne fait jamais de remux/copie pour un trim temporel seul" et avaient supprimé un chemin
passthrough sur cette base — affirmation invalidée par cette vérification directe.

### Correctif appliqué (documentation uniquement, AUCUN changement fonctionnel)

Décision : conserver le ré-encodage frame-exact existant (résultat plus précis — coupe exacte au
timestamp demandé, jamais de contenu avant le point choisi — au prix d'un export plus lent) plutôt
que de reproduire le fast path Android, dont la réplication fidèle exigerait une introspection
sync-sample via `AVAssetReader` (aucun équivalent direct simple dans AVFoundation) et une
synchronisation vidéo/audio manuelle — risque réel de désynchronisation si mal implémenté, pour un
gain de vitesse sur une opération non critique en latence. Correction des commentaires de tête de
`MediaTrimView.swift`/`VideoTrimState.swift` pour documenter honnêtement ce choix comme un écart
assumé plutôt que la fausse "fidélité Android" affirmée précédemment.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/MediaTrimView.swift`,
`Sources/TiinverSwift/Media/VideoTrimState.swift` (commentaires uniquement, diff vérifié comme ne
touchant aucune ligne de code fonctionnel).

**Résultat CI** : commit `df62da7`, push confirmé (`1d3ad22..df62da7 main -> main`), run
`32924295725` → **`conclusion: success`**.

**Statut honnête** : `IOS_INTENTIONAL_DIFFERENCE`. Aucun test réel requis (aucun changement de
comportement).

## 2026-08-25 — Phase B V5 — Lot P1-19 : V5-F-043 (BUILD_VALIDATED)

### Vérification

**Android** : `AnimemesCompound.java:859-871` (`onKeyframeButtonClicked`) : `if
(controller_mode_activate) captureTransformKeyframe(); else showPanelEditor(sel);`.
`controller_mode_activate` (`:1857-1877`) confirmé `false` par défaut, piloté par un bouton
SÉPARÉ `R.id.controlle_movement`, remis à `false` par `R.id.timelineTabs`. `btn_keyframe`
(`:420-436,1390`) masqué par défaut, rendu VISIBLE dès qu'un item timeline est sélectionné —
atteignable en mode timeline NORMAL, pas seulement en mode "controller".

**iOS avant correctif** : `AnimemesEditorView.swift` bouton ◆ appelait inconditionnellement
`state.recordKeyframe()`. `MovementControllerState.swift` (le modèle du mode "controller"
Android) confirmé jamais instancié nulle part dans le projet (grep exhaustif) — le SEUL mode
existant côté iOS correspond au mode timeline PAR DÉFAUT d'Android, où le même bouton devrait
ouvrir le panneau de propriétés sans créer aucun keyframe.

### Correctif appliqué

Cause : le commentaire de `recordKeyframe()` citait avoir audité les 2 méthodes Android
(`captureTransformKeyframe`/`showPanelEditor`) mais ne retenait que la première, sans reproduire
la condition `controller_mode_activate` qui l'encadre. Correctif : bouton ◆ câblé vers
`state.snapshotLayerEditor()`/`showLayerEditor` — MÊME action que le bouton "propriétés" déjà
existant dans `bottomToolbar`. `recordKeyframe()` non supprimé : reste utilisé par `dragEnded()`
(gardé par `autoCaptureEnabled`), concern séparé du bouton ◆, inchangé par ce correctif.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/AnimemesEditorView.swift`.

**Résultat CI** : commit `1cf255b`, push confirmé (`6760bc0..1cf255b main -> main`), run
`32924984556` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : sélectionner un calque, taper ◆ plusieurs fois, confirmer l'ouverture du panneau de
propriétés sans effet de bord sur la timeline.

## 2026-08-25 — Phase B V5 — Lot P1-20 : V5-F-046 (BUILD_VALIDATED)

### Vérification

**Android** : `comments/ui/CommentAdapter.java:211-233` — bouton "Afficher N commentaires"
visible si `elts.getRepliesCount() > 0`, tap → `listener.getReplay(elts, callback)` →
`replayCommentAdapter.submitList(...)`. `MyBottomSheetDialogFragment.java:516-520` : `getReplay`
→ `commentViewModel.getReplay(data.getId(), LIMIT, OFFSET)`.
`comments/controller/CommentRepository.java:177-229` : `getReplay`/`prepareReplayeData`, endpoint
`/comment/replay/{activityId}/{limit}/{offset}`.

**iOS avant correctif** : `CommentRepository.replies(commentId:limit:offset:)` existait déjà,
port fonctionnel correct de `getReplay` — mais grep exhaustif (`\.replies(commentId`) = 0
résultat dans tout le projet. `CommentsView` ne récupérait ni n'affichait jamais aucune réponse ;
`repliesCount` décodé mais jamais lu dans l'UI.

### Correctif appliqué

Cause : `CommentRepository.replies` porté comme fonction isolée mais jamais câblée dans
`CommentsView` — code mort côté fonction réseau, fonctionnalité UI simplement absente. Correctif :
`commentRow` restructuré, rendu de ligne extrait en `commentLine(_:)` réutilisable (commentaires
ET réponses, même présentation) ; nouvelle `repliesSection(for:)` affichant "Afficher N
commentaire(s)" quand `repliesCount > 0` ; nouvelle `loadReplies(for:)` appelant
`CommentRepository.shared.replies` (offset 0, même limite que la page principale) ; résultats
rendus imbriqués (indentation 40pt, alignée sous le texte du parent) via `commentLine`.

**Fichiers modifiés** : `Sources/TiinverSwift/Discover/CommentsView.swift`.

**Résultat CI** : commit `ff728a9`, push confirmé (`7b3ba10..ff728a9 main -> main`), run
`32925870270` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : commentaire avec réponses existantes, taper "Afficher N commentaires", confirmer
l'affichage correct.

## 2026-08-25 — Phase B V5 — Lot P1-21 : V5-F-047 (BUILD_VALIDATED)

### Vérification

**Android** : `models/activity/comments/CommentModel.java:300-330` — commentaire de code explicite
: "Les champs existants suffisent : comments → stocke gift_thumb_name, object → stocke gift" ;
`resolveGift(Context)` résout LOCALEMENT emoji/nom/prix depuis `commentText` via
`GiftCatalogHelper`, ne lit JAMAIS `getGiftEmoji()`/`getGiftName()`/`getGiftPrice()`.
`CommentAdapter.java:197-198,276-281` `bindGiftView` appelle `elts.resolveGift(context)`, pas les
getters directs. Le serveur n'envoie, pour un commentaire-cadeau, QUE `object="gift"` et
`comments="gift_thumb_name"` — aucune preuve de champs séparés pré-résolus envoyés par le backend.

**iOS avant correctif** : `Comment` décodait `giftEmoji`/`giftName`/`giftPrice`/`hasGift`
directement depuis des clés JSON supposées du serveur, AUCUN champ `object` décodé.
`GiftCatalog.swift` documentait lui-même explicitement que son intégration au module Commentaires
n'était "pas encore" faite.

### Correctif appliqué

Cause : le port iOS suppose que le serveur envoie des champs de cadeau pré-résolus, contredit par
la preuve Android (résolution intégralement client-side). Correctif : les 4 champs retirés de
`Comment`, remplacés par `object: String?` + `isGiftComment` calculé.
`CommentsView.commentLine` résout l'affichage via `GiftCatalog.emoji(for:)`/`price(for:)` à
partir de `commentText` (l'id du cadeau) quand `isGiftComment`, avec repli 🎁 pour un id inconnu
(même motif que `LocalNotificationBuilder`, V4-F-071). Vérifié par grep qu'aucun autre site ne
consommait les 4 champs retirés.

**Fichiers modifiés** : `Sources/TiinverSwift/Discover/CommentModels.swift`,
`Sources/TiinverSwift/Discover/CommentsView.swift`.

**Résultat CI** : commit `d9d8a8c`, push confirmé (`1087db0..d9d8a8c main -> main`), run
`32926668287` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : commentaire-cadeau reçu, confirmer le badge emoji + prix au lieu d'un id brut.

## 2026-08-25 — Phase B V5 — Lot P1-22 : V5-F-050 (BUILD_VALIDATED)

### Vérification

**Android** : `partage/ShareActivity.java:264-268,366-376` — `onError` → `showDialog()`
(`R.string.errorLoad`), monté sur `ShareActivity` elle-même, INDÉPENDAMMENT de tout état de
connexion — aucune logique de redirection vers un login avant de traiter le lien.

**iOS avant correctif** : `.onOpenURL` monté sur `RootRouterView` (délibérément, pour capter un
lien reçu AVANT authentification), mais `DeepLinkCenter.errorMessage` n'était consommé que dans
`HomeShellView`. Un lien échouant à se résoudre pendant `AuthCoordinatorView` (non connecté) ne
montrait RIEN à l'écran. `routeToGroup` retournait en plus silencieusement (aucune erreur) si
`myId` était `nil`.

### Correctif appliqué

Cause : l'alerte d'erreur n'était câblée que sur `HomeShellView`, incohérent avec le placement
délibéré de `.onOpenURL` sur `RootRouterView` pour le cas pré-authentification. Correctif : même
`.alert("Erreur", ...)` que `HomeShellView` (V3-F-138) ajouté sur `RootRouterView`
(`@ObservedObject deepLinks: DeepLinkCenter = .shared`) — sans risque de double-affichage,
`RootRouterView`/`HomeShellView` mutuellement exclusifs dans la hiérarchie. `routeToGroup` appelle
désormais `showError()` au lieu de retourner silencieusement quand `myId == nil` (l'endpoint
exige réellement `myId`, donc affichage direct de l'erreur plutôt qu'un appel voué à l'échec).

**Fichiers modifiés** : `Sources/TiinverSwift/Navigation/RootRouterView.swift`,
`Sources/TiinverSwift/Navigation/DeepLinkRouter.swift`.

**Résultat CI** : commit `65db96d`, push confirmé (`d9d8a8c..65db96d main -> main`), run
`32927383114` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : lien profond invalide avant connexion, confirmer l'alerte visible.

## 2026-08-25 — Phase B V5 — Lot P1-23 : V5-F-057 (BUILD_VALIDATED)

### Vérification

**Android** : `editor/memes/MemesFragment.java:144-176` — `onPause`/`onStop`/`onDestroyView`
appellent TOUS `animemes_compound.pause()` + `animemes_compound.stopView()`, et `onDestroyView`
appelle en plus `animemes_compound.onDestroy()`. Le rendu par frame ne peut jamais continuer après
la sortie de l'écran.

**iOS avant correctif** : `AnimemesEditorState` sans `deinit`, `AnimemesEditorView` sans
`.onDisappear`. `AnimationEngine.displayLink` n'était arrêté (`stopDisplayLink()`) que par un
second tap explicite sur pause ou un scrub manuel. Cause racine : `DisplayLinkProxy.onTick`
capture `self` (`AnimationEngine`) en `[weak self]` (évite un crash), mais `RunLoop.main` retient
fortement le `CADisplayLink` LUI-MÊME (et son target `DisplayLinkProxy`) INDÉPENDAMMENT de
`AnimationEngine` — sans `deinit`/`.onDisappear` appelant `engine.stop()`, le lien continue de
déclencher son callback à chaque rafraîchissement (jusqu'à 60-120Hz) INDÉFINIMENT après la sortie
de l'écran (le `self?.tick(...)` devient un no-op silencieux, mais le `CADisplayLink` n'est jamais
libéré).

### Correctif appliqué

`.onDisappear { state.engine.stop() }` ajouté sur la vue racine d'`AnimemesEditorView` — port
direct et déterministe de `onPause`/`onStop`/`onDestroyView` ; `engine.stop()` invalide déjà le
lien via `stopDisplayLink()` (préexistant) et est un no-op si aucune lecture n'est en cours.
`deinit` ajouté sur `AnimationEngine` (`displayLink?.invalidate()`) comme filet de sécurité
supplémentaire pour un chemin de désallocation qui ne passerait pas par `.onDisappear`.

**Fichiers modifiés** : `Sources/TiinverSwift/Animems/AnimemesEditorView.swift`,
`Sources/TiinverSwift/Animems/AnimationEngine.swift`.

**Résultat CI** : commit `7bbca19` (code), documentation regroupée au commit `76fc029`, push
confirmé (`65db96d..76fc029 main -> main`), run `32928191420` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis (profiling Instruments) : lancer la lecture, quitter l'écran sans pause, confirmer
l'absence de `CADisplayLink` résiduel actif.

## 2026-08-25 — Phase B V5 — Lot P1-24 : V5-F-058 (BUILD_VALIDATED)

### Vérification

**Android** : `Activity/service/CacheWorker.java:66-69,231-234` — `CacheDataSource.Factory` +
`CacheWriter(dataSource, dataSpec, buffer, ...)` écrit en FLUX, par blocs bornés, directement dans
`SimpleCache` sur disque. Téléchargement utilisateur via `android.app.DownloadManager` — streaming
disque système, jamais chargé en tas Java. Aucun des deux chemins ne retient jamais le fichier
complet en mémoire, quelle que soit sa durée/poids.

**iOS avant correctif** : `FeedMediaDownloader.download` via `URLSession.shared.data(for:
request)` — fichier vidéo entier chargé en mémoire comme `Data` avant `data.write(to:)`.
`VideoCacheManager.precache` [appelé automatiquement en arrière-plan par
`VideoPlayerManager.preload` pour chaque vidéo de la fenêtre `currentIndex±2` PENDANT le
défilement du Feed] via `URLSession.shared.dataTask` — même mise en tampon RAM complète avant
écriture.

### Correctif appliqué

Cause : `URLSession.shared.data(for:)`/`dataTask` (API haut niveau) chargent systématiquement
tout le corps HTTP en RAM, contrairement à `URLSession.shared.download(for:)`/`downloadTask`
(téléchargement en flux direct vers un fichier temporaire). Correctif : `FeedMediaDownloader.download`
basculé vers `URLSession.shared.download(for:)`, fichier temporaire système déplacé immédiatement
(synchrone, avant tout retour au run loop, condition requise par l'API). `VideoCacheManager.precache`
basculé vers `URLSession.shared.downloadTask(with:completionHandler:)`, fichier temporaire déplacé
dans le callback avec `removeItem` défensif avant `moveItem` (même tolérance à l'écrasement que
l'ancien `data.write(to:)`).

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/FeedMediaDownloader.swift`,
`Sources/TiinverSwift/Media/VideoCacheManager.swift`.

**Résultat CI** : commit `d92eec9`, push confirmé (`2df9dd5..d92eec9 main -> main`), run
`32928942478` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis (profiling mémoire) : téléchargement vidéo + défilement rapide du Feed, confirmer
l'absence de pic mémoire correspondant à la taille du fichier.

## 2026-08-25 — Phase B V5 — V5-F-060 : DIFFÉRÉ (aucun correctif de code)

### Vérification

**Android** : `Utils/ViewTracker.java:100-113` (`startPeriodicSync`, `PeriodicWorkRequest` 15min
sur `ViewSyncWorker`, appelé depuis `App.java:259,329`) ; `Activity/ui/HomeActivity.java:365,
373-375,752-782` (`scheduleDynamicWorker` → 3 `PeriodicWorkRequest` sur `MyWorker`, 1-2 jours :
"suggest-content", "get-suggest-content", "my-boost-deliver") ; `service/worker/ViewSyncWorker.java`
(`doWork`) ; `service/MyWorker.java` (`doWork`, appelle `NotificationUtils.displaySuggestNotification`
et `/boost/deliver/{userId}`). 4 tâches `WorkManager` périodiques persistant au-delà du cycle de
vie du process, avec retry/backoff/contrainte réseau.

**iOS** : `grep -r BGTaskScheduler` sur tout `Sources/TiinverSwift/` = 0 résultat.
`BGTaskSchedulerPermittedIdentifiers` absent de `project.yml`. `ViewEventRepository` (stockage
local, seul morceau écrit) jamais instancié (`grep -rn "ViewEventRepository("` vide). Endpoints
`activity/suggest-content`/`boost/deliver` absents de TOUT fichier Swift, ni en tâche de fond ni
même en appel synchrone au premier plan.

### Décision : DIFFÉRÉ, pas de correctif de code

4 raisons cumulatives : (1) enregistrer `BGTaskSchedulerPermittedIdentifiers` exige une
modification `project.yml`/capability Xcode ("Background Modes"), une décision de configuration
de build au-delà d'un correctif de code pur, à ne pas prendre seul au fil d'un balayage
automatisé de backlog ; (2) ce finding regroupe 3 comportements d'arrière-plan
architecturalement distincts (sync analytics/watchtime, notifications de ré-engagement, livraison
de boost payante), chacun exigeant une vérification complète et séparée de la logique/l'endpoint
Android avant une implémentation fiable ; (3) précédent direct déjà posé dans le cycle V3 :
`V3-F-095` (MÊME domaine fonctionnel, temps de visionnage/analytics) déjà explicitement différé ;
(4) la partie livraison de boost touche de l'ARGENT RÉEL dépensé par l'utilisateur — mérite une
implémentation et un test dédiés, pas un correctif bundlé dans un balayage automatisé.

**Fichiers modifiés** : aucun. **Commit** : aucun. **CI** : aucune.

**Statut honnête** : `DIFFÉRÉ`. Nécessite une décision produit (capability Background Modes) et
une session dédiée pour vérifier/implémenter séparément les 3 comportements + le câblage de
`ViewEventRepository`.

## 2026-08-25 — Phase B V5 — Lot P1-25 : V5-F-062 (BUILD_VALIDATED)

### Vérification

**Android** : `NotiLikecmt/ShowNoti.java:107-142` (`setupObservers`) — Observer 1 "Room LiveData"
(`:110-122`, `messageEmpty` = `notifNetworkDone && itemCount==0`) et Observer 2 "état réseau"
(`:125-142`, `messageError` = résultat réseau `MyResult.ERROR`, affiché uniquement si
`itemCount==0`) — 2 états visuels INDÉPENDANTS, `messageError` rendu `VISIBLE` dès que le type
réseau est `ERROR`, indépendamment de l'observateur 1.

**iOS avant correctif** : `NotificationsListView.body` testait `notifications.isEmpty` (branche
vide) AVANT `errorMessage != nil && notifications.isEmpty` (branche erreur) — la garde vide étant
un sur-ensemble strict de la garde erreur, la branche erreur était strictement inatteignable dès
que `isLoading` repassait à `false` (le `defer` de `fetchNotifications` s'exécute toujours).

### Correctif appliqué

Cause : erreur d'ordonnancement des conditions `if/else if`. Correctif : branches réordonnées —
erreur testée AVANT vide, même motif déjà correct dans
`FeedView.emptyOrStatusState`/`ProfileView.header`. Diff strictement limité au réordonnancement.

**Fichiers modifiés** : `Sources/TiinverSwift/Notifications/NotificationsListView.swift`.

**Résultat CI** : commit `aa922ad`, push confirmé (`d45a95b..aa922ad main -> main`), run
`32929729728` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : ouvrir le centre de notifications sans réseau/session expirée, confirmer le message
d'erreur.

## 2026-08-25 — Phase B V5 — Lot P1-26 : V5-F-063 (BUILD_VALIDATED)

### Vérification

**Android** : `wallet/WalletActivity.java:124-186` — observer `getLiveData()`, branche
`Result.ERROR` (`:128-129`) → `attemptReconnect()` (`:178-186`), relance automatiquement
`executeBackTask()` toutes les 5s via `Handler.postDelayed`, indéfiniment, jusqu'à succès — sans
jamais afficher de message d'erreur visible.

**iOS avant correctif** : `WalletViewModel.errorMessage` peuplé sur échec
(`catch { errorMessage = error.localizedDescription }`) mais jamais lu par `WalletView` (grep
confirmé). Si l'échec survenait au chargement INITIAL, `transactions` restait vide — aucune
cellule pour déclencher `.onAppear`, pas de `.refreshable` — écran vide et figé en permanence,
sans texte, sans bouton, sans reprise.

### Correctif appliqué

Cause : `errorMessage` publié côté ViewModel mais jamais consommé côté vue ; absence du
mécanisme `attemptReconnect`. Correctif (option "visible + reprise manuelle", PAS la reprise
automatique à 5s — nécessiterait un timer géré par le cycle de vie de la vue, même classe de
risque de fuite que V5-F-057/`CADisplayLink`) : bandeau `Text(errorMessage)` + bouton "Réessayer"
affiché dans la section Historique quand `transactions.isEmpty && errorMessage != nil` ;
`.refreshable { await viewModel.loadInitial() }` ajouté sur la `List`. `errorMessage` désormais
effacé au DÉBUT de chaque tentative (`loadMore()`), pas seulement en cas de succès, pour éviter
qu'un ancien message persiste après une reprise réussie.

**Fichiers modifiés** : `Sources/TiinverSwift/Wallet/WalletView.swift`,
`Sources/TiinverSwift/Wallet/WalletViewModel.swift`.

**Résultat CI** : commit `a7f4c8f`, push confirmé (`aa922ad..a7f4c8f main -> main`), run
`32930424123` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : Portefeuille avec réseau instable, confirmer message d'erreur + bouton "Réessayer".

## 2026-08-25 — Phase B V5 — Lot P1-27 : V5-F-067 (BUILD_VALIDATED)

### Vérification

**Android** : `back_sync/MyFirebaseMessagingService.java:109-119` (`onMessageReceived` →
`WorkManager.enqueueUniqueWork("FCM_SYNC_WORK", ExistingWorkPolicy.KEEP, syncWork)`) — une synchro
déjà en file/en cours fait IGNORER la nouvelle. `NotiLikecmt/NotificationRepository.java:89-120`
(`fetchNotifications`, appelé par `TiinverSyncWorker.visiteServeur`, un seul exécutant garanti par
la clé unique WorkManager) ne peut donc jamais s'exécuter deux fois en parallèle.

**iOS avant correctif** : `AppDelegate.didReceiveRemoteNotification` instancie un
`NotificationCenterViewModel()` FRAIS à chaque push (donc `isLoading` toujours `false` au
départ) ; `NotificationCenterViewModel.fetchNotifications` n'avait AUCUNE garde `isLoading` avant
de lancer le fetch ; `NotificationsListView.task` appelle aussi `fetchNotifications` sur SA
PROPRE instance, indépendante. Une rafale de push, ou un push pendant que le centre de
notifications est déjà ouvert, faisait tourner plusieurs exécutions concurrentes de
`fetchNotifications`/`triggerSystemNotifications` sans synchronisation — chaque exécution relisait
`isRead == 0` pour les mêmes lignes avant qu'aucune ne l'ait marquée lue, et
`LocalNotificationBuilder.present` utilisant un UUID aléatoire à chaque appel, aucune
déduplication système n'était possible.

### Correctif appliqué

Cause : absence de verrou "single-flight" côté iOS, et `isLoading` (propriété d'instance) rendu
inefficace par la recréation d'instance à chaque push. Correctif : `private static var isSyncing`
ajouté sur `NotificationCenterViewModel` — verrou GLOBAL partagé par TOUTES les instances ;
`fetchNotifications` retourne immédiatement si une synchro est déjà en cours, reproduisant la
sémantique `ExistingWorkPolicy.KEEP` (skip, pas queue). Classe déjà `@MainActor`, accès au membre
statique intrinsèquement isolé sans `actor` dédié.

**Fichiers modifiés** : `Sources/TiinverSwift/Notifications/NotificationCenterViewModel.swift`.

**Résultat CI** : commit `df56d8b`, push confirmé (`246b159..df56d8b main -> main`), run
`32931145696` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : rafale de push ou push pendant l'écran Notifications ouvert, confirmer l'absence de
bannières système dupliquées.

## 2026-08-25 — Phase B V5 — Lot P1-28 : V5-F-068 (BUILD_VALIDATED)

### Vérification

**Android** : `messagerie/ui/adapter/MessageListAdapter.java:322-365` (`Subscribe.bind`,
`subscribe.setOnClickListener` → `td.Post(..., "group/subscribe", Callback)`) et `:420+`
(`RenewSubscription`, même motif) — `onLoading()` (`:361-364`) exécute
`subscribe.setVisibility(GONE); progress.setVisibility(VISIBLE)` SYNCHRONEMENT dès le clic, avant
l'appel réseau : le bouton n'est plus dans la hiérarchie cliquable pendant toute la durée de la
requête, empêchant MÉCANIQUEMENT un second appui de déclencher un second débit.

**iOS avant correctif** : `SubscriptionBannerRow` — `Button` TOUJOURS actif, aucun état
`isLoading`/`disabled`. `ChatViewModel.resolveGroupSubscription` — vérifie
`coinsAmount > Double(price)` PUIS lance un `Task` réseau, SANS aucun flag "requête déjà en cours
pour cet item" ; `coinsAmount -= Double(price)` exécuté APRÈS chaque appel réseau réussi, SANS
idempotence.

### Vérification financière DOUBLE (règle Wallet)

(1) Paramètres envoyés/calcul du delta/appel serveur INCHANGÉS — seul un verrou ajouté ; rollback
sur erreur inchangé (`catch { return }`, fidèle à `onError` Android qui ré-affiche simplement le
bouton sans message — `defer` libère le verrou dans ce même chemin, aucun débit n'a lieu sur ce
chemin, avant comme après ce correctif). (2) Confirmé par relecture qu'un double-tap AVANT ce
correctif produisait un lire-puis-écrire NON ATOMIQUE sur `coinsAmount` : les 2 `Task` concurrents
lisaient le solde AVANT que le premier ne le décrémente, passaient chacun la garde, envoyaient
chacun leur requête serveur, puis décrémentaient chacun `coinsAmount` — double débit local RÉEL
pour une seule action utilisateur, scénario UI ordinaire (double-tap accidentel).

### Correctif appliqué

`ChatViewModel.pendingSubscriptionItemIds: Set<String>` ajouté — verrou logique PAR ITEM (clé =
`"sub-\(itemId)"`/`"renew-\(itemId)"`, la MÊME déjà utilisée pour le retrait de bannière), pas un
booléen global, pour ne pas bloquer à tort 2 bannières de groupes DIFFÉRENTS en cours
simultanément. `resolveGroupSubscription` retourne immédiatement si la même clé est déjà
présente dans le Set. `SubscriptionBannerRow` gagne un paramètre `isLoading` remplaçant le bouton
par un `ProgressView` pendant la requête — analogue visuel direct du `setVisibility(GONE)`/
`setVisibility(VISIBLE)` Android. Commentaire de tête de fichier corrigé au passage (affirmait à
tort "PAS fonctionnel", obsolète depuis le portage réel de `resolveGroupSubscription`).

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/ChatViewModel.swift`,
`Sources/TiinverSwift/Messagerie/ChatBubbleViews.swift`,
`Sources/TiinverSwift/Messagerie/ChatView.swift`.

**Résultat CI** : commit `ee9f40b`, push confirmé (`533fdef..ee9f40b main -> main`), run
`32932069058` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test
réel requis : double-tap rapide sur "S'abonner"/"Renouveler l'abonnement", confirmer un SEUL
débit et une SEULE requête réseau.

## 2026-08-25 — Phase B V5 — Lot P1-29 : V5-F-070 (BUILD_VALIDATED, portée réduite documentée)

### Vérification

**Android** : `messagerie/repository/ChatRepository.java:780-818` (`NewPrivateMessage`, poste sur
`Handler(Looper.getMainLooper())`) + `Utils/DecodeThreadPool.java:8-19` (`ThreadPoolExecutor
corePoolSize=1` + `LinkedBlockingQueue` non bornée ⇒ UN SEUL thread de décodage en pratique) +
`messagerie/ui/ChatManager.java:1156-1159` (`addMessage(MessageLib)` déclarée `synchronized`,
check-then-insert protégé). Trois mécanismes garantissant que le couple vérifier-existe+insérer
est atomique et que 2 événements ne peuvent jamais s'entrelacer.

**iOS avant correctif** : `MessageRepository.addMessage`/`addGroupMessage` — `guard
!(try await messageExists(messageId:))` PUIS `try await messages.insert { ... }`, deux `await`
séparés SANS verrou entre eux ; aucune contrainte d'unicité Core Data sur `messageId`. Deux
événements socket portant le même `messageId` (redélivrance après reconnexion) pouvaient chacun
passer le guard avant qu'aucun n'ait terminé son insert.

### Décision et correctif appliqué

**Option Core Data (contrainte d'unicité) délibérément ÉCARTÉE** : `messageId` est `optional`
avec `defaultValueString="0"` — une contrainte dure risquerait d'échouer sur des bases locales
EXISTANTES ayant déjà des collisions issues de ce même bug, changement de schéma/migration à
risque réel sur des installations en production. **Option `actor` simple également écartée** : la
réentrance des `actor` Swift n'empêcherait PAS la course ici (un `await` interne à l'opération
protégée laisse une fenêtre pour un second appel concurrent).

Correctif : nouveau `actor SerialTaskQueue` (enchaînement EXPLICITE par continuation `Task`, pas
une réentrance d'actor nue) enveloppant `addMessage`/`addGroupMessage` en entier — UNE SEULE
instance partagée entre les deux méthodes (même table `wk_messages`).

**Portée délibérément réduite** : seul le risque de DOUBLON EN BASE (le plus sévère des 2
impacts) est corrigé. L'ordre d'affichage entre 2 messages arrivés en rafale N'EST PAS traité —
nécessiterait de sérialiser tout le pipeline de dispatch socket, un chantier plus large touchant
l'architecture temps réel ; risque cosmétique mineur, auto-corrigé à la prochaine réouverture de
la conversation (`loadInitial()` trie déjà par `stamp`).

**Fichiers modifiés** : `Sources/TiinverSwift/Storage/MessageRepository.swift`.

**Résultat CI** : commit `d938554`, push confirmé (`ee9f40b..d938554 main -> main`), run
`32932952310` → **`conclusion: success`**.

**Statut honnête après correction** : `BUILD_VALIDATED`, portée réduite documentée. PAS
`COMPLETE_PARITY_VALIDATED` — test réel requis : redélivrance rapprochée du même message
(coupure réseau/reconnexion), confirmer l'absence de bulle dupliquée persistante.

## 2026-08-26 — Phase B V5 — Lot P1-30 : V5-F-072 (roster — texte du dernier message)

**Commit** : `6404681` — CI **success** (run `32934697138`).

**Cause exacte** : `RosterRepository.rosterAll()` reproduisait la jointure SQL brute `rosterall`
de `StubProvider.java` — elle-même confirmée **code mort côté Android** (`ROSTER_ALL_URI` jamais
requêté par aucun appelant réel ; seul `ROSTER_URI` dénormalisé est utilisé par l'écran
`Roster.java` réellement affiché). Le port faisait, pour chaque ligne roster, un second `fetch`
`MessageEntity` filtré par `conversationId` avec `fetchLimit = 1` **sans aucun tri** — l'ordre de
retour de Core Data sans `sortDescriptors` n'est pas garanti être le plus récent (souvent l'ordre
d'insertion, donc potentiellement le PREMIER message jamais envoyé). `RosterListView.refresh()`
utilisait ensuite ce résultat non fiable EN PRIORITÉ (`pair.lastMessage?.message ?? entity.
lastMessage`), masquant systématiquement la colonne `entity.lastMessage` — déjà correctement
tenue à jour à chaque envoi/réception par `RosterRepository.updateRoster*` (port fidèle de
`RosterManager.updateRoster*`, confirmé correct) — dès qu'une correspondance existait (quasi
toujours).

**Correction appliquée** : option 2 de la RECOMMANDATION (plus simple, plus fidèle au mécanisme
Android réel). Suppression entière de la ré-agrégation : `rosterAll()` retourne désormais
`[RosterEntity]` brut (plus de `struct RosterWithLastMessage`, plus de propriété `messages:
CoreDataRepository<MessageEntity>` — confirmée par grep comme n'étant utilisée QUE pour ce join,
donc supprimable sans reste). `RosterListView.refresh()` consomme directement `[RosterEntity]`
(suppression de l'indirection `pair.roster`) et assigne `model.message = entity.lastMessage`
sans repli.

**Fichiers modifiés** : `Sources/TiinverSwift/Storage/RosterRepository.swift`,
`Sources/TiinverSwift/Messagerie/RosterListView.swift`.

**Flux frère vérifié** : `rosterAll()` n'a qu'un seul appelant dans tout le projet
(`RosterListView.swift`, confirmé par grep) — aucun autre site à mettre à jour.
`ChatSearchView.swift` référence un champ `.lastMessage` sans rapport (autre `Row` struct), non
concerné.

**Résultat CI** : commit `6404681`, push confirmé (`cc962db..6404681 main -> main`), run
`32934697138` → **`conclusion: success`**.

**Statut honnête** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test réel requis :
vérifier sur device qu'une conversation avec plusieurs messages échangés affiche bien le dernier
message envoyé/reçu (et non un message plus ancien) dans la liste des conversations, y compris
juste après réception d'un nouveau message.

## 2026-08-26 — Phase B V5 — Lot P1-31 : V5-F-076 (Feed — résilience arrière-plan de l'upload de publication)

**Commit** : `e1b8b0a` — CI **success** (run `32935455105`).

**Cause exacte** : Android protège tout le flux de publication (upload BunnyCDN photo/vidéo puis
`POST activity/add`) via un vrai `Service` en foreground (`ActivityService.onStartCommand`,
`startForeground(NOTIF_ID,...)`), explicitement immunisé contre la suspension liée au passage en
arrière-plan de l'app, complété par une file d'attente persistée localement
(`FILE_TRANSFERT_URI`) permettant une reprise après échec. Côté iOS,
`PublishComposeView.publish()` lançait cet upload dans un `Task` Swift non structuré, déclenché
depuis un bouton, sans aucune protection (`beginBackgroundTask`) ni `URLSessionConfiguration
.background`, ni persistance locale de l'état de publication en cours — confirmé par grep
exhaustif (0 occurrence de ces deux mécanismes dans tout le dépôt iOS).

**Correction appliquée** : option "à défaut" de la RECOMMANDATION (portée réduite, documentée).
`publish()` enveloppe désormais l'intégralité de son corps dans une paire
`UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)` /
`endBackgroundTask` (fin garantie via `defer`, coexistant avec le `defer { isPublishing = false }`
déjà existant), pour survivre à une mise en arrière-plan brève de l'app (~30s, prolongeable par
iOS selon la charge système) au lieu d'être suspendu immédiatement.

**Portée délibérément réduite** : l'option complète de la RECOMMANDATION
(`URLSessionConfiguration(.background)` + persistance Core Data de l'état de publication +
reprise après échec réseau complet, reproduisant l'intention de `FILE_TRANSFERT_URI`) N'EST PAS
traitée — bundlerait un changement d'architecture réseau majeur (délégation de session en
arrière-plan, wiring AppDelegate/SceneDelegate) et une nouvelle infrastructure de file d'attente
persistée, disproportionné par rapport à ce finding P1 isolé. Le cas réellement corrigé (bascule
brève vers une autre app ou verrouillage d'écran pendant l'upload) est de loin le plus fréquent en
usage réel ; le cas non couvert (app tuée par l'utilisateur ou le système, ou backgroundTask expiré
sur un upload anormalement long) laisse le comportement identique à avant ce correctif.

**Fichiers modifiés** : `Sources/TiinverSwift/Feed/PublishComposeView.swift`.

**Flux frère vérifié** : `FeedMediaUploader.swift` (upload BunnyCDN lui-même, endpoints/headers/
ordre des appels) non modifié — déjà fidèle après plusieurs correctifs V2/V3/V4, seul le manque de
protection contre la suspension en arrière-plan était en cause ici.

**Résultat CI** : commit `e1b8b0a`, push confirmé (`6404681..e1b8b0a main -> main`), run
`32935455105` → **`conclusion: success`**.

**Statut honnête** : `BUILD_VALIDATED`, portée réduite documentée. PAS `COMPLETE_PARITY_VALIDATED`
— test réel requis : lancer une publication (surtout vidéo, upload plus long), basculer vers une
autre app ou verrouiller l'écran pendant l'upload, confirmer que la publication aboutit malgré tout
au retour dans l'app (au lieu d'échouer silencieusement comme avant ce correctif).

## 2026-08-26 — Phase B V5 — Lot P1-32 : V5-F-077 (Chat — en-tête Referer manquant au téléchargement de pièce jointe)

**Commit** : `fde9608` — CI **success** (run `32936140166`).

**Cause exacte** : `ChatFragmentTest.downloadFile` (Android, ligne 3159) attache systématiquement
`request.addRequestHeader("Referer", "https://tiinver.com")` sur chaque téléchargement de pièce
jointe chat via `DownloadManager` — le même en-tête que TOUS les autres points d'accès au CDN
Tiinver du projet Android (~15 fichiers : `ChargerImages.java`, `ExoPlayerManager.java`,
`ActivityAdapter.java`, etc.). Côté iOS, `ChatViewModel.requestDownload` utilisait
`URLSession.shared.download(from: remoteURL)` — appel brut sans `URLRequest` ni en-tête — alors
que TOUS les autres chemins CDN déjà portés côté iOS (`FeedMediaDownloader`, `CDNAsyncImage`,
`VideoPlayerManager`, `VideoCacheManager`, `CommunityTemplateRepository`) l'ajoutent explicitement,
plusieurs documentant en commentaire que ce Referer est une exigence RÉELLE du CDN Tiinver
confirmée par test. Le commentaire de tête de `requestDownload` affirmait à tort qu'Android
n'attache aucun en-tête sur ce téléchargement précis — contredit par la lecture directe de
`ChatFragmentTest.java:3159`.

**Correction appliquée** : RECOMMANDATION suivie telle quelle. `requestDownload` construit
désormais un `URLRequest` portant `Referer: https://tiinver.com` et appelle
`URLSession.shared.download(for: request)` au lieu de `download(from: remoteURL)`, à l'identique
des autres chemins CDN du projet. Commentaire stale corrigé au passage.

**Fichiers modifiés** : `Sources/TiinverSwift/Messagerie/ChatViewModel.swift`.

**Flux frère vérifié** : `requestUpload`/`ChatMediaUploadService` (branche upload de la même pièce
jointe) déjà fidèle (en-tête `AccessKey` de Bunny Storage porté correctement) — seule la branche
téléchargement manquait son en-tête, cause confirmée isolée à `requestDownload`.

**Résultat CI** : commit `fde9608`, push confirmé (`e1b8b0a..fde9608 main -> main`), run
`32936140166` → **`conclusion: success`**.

**Statut honnête** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test réel requis :
recevoir une pièce jointe chat (photo/vidéo/audio/document) d'un correspondant et confirmer
qu'elle se télécharge avec succès (absence de 403), si la zone CDN bloque effectivement les
requêtes sans Referer comme le suggèrent les autres correctifs déjà validés pour la même raison.

## 2026-08-26 — Phase B V5 — Lot P1-33 : V5-F-078 (Chat — reprise d'upload de pièce jointe indépendante de l'UI)

**Commit** : `d5b583c` — CI **success** (run `32937077298`).

**Cause exacte** : Android dispose de DEUX mécanismes de reprise d'upload de pièce jointe chat
indépendants : (1) `checkAndUploadFile`/`onBindViewHolder` (rebind de vue, seul mécanisme déjà
porté côté iOS via `ChatViewModel.handleAppear`) ; (2) `ChatManager.sendMessageFromCursor`, balayage
de TOUS les messages locaux `status=0` avec `isFileUploaded==0`, ré-enfilant un
`OneTimeWorkRequest<UploadChatWork>` (WorkManager, contrainte réseau + backoff exponentiel),
déclenché par 4 sources distinctes : reconnexion réseau (`NetworkStateReceiver`), job planifié
(`MyJobService`), synchronisation périodique (`SyncAdapter`/`SyncWorker`), et à CHAQUE notification
push reçue (`MyFirebaseMessagingService`). Seul le mécanisme (1) avait été porté côté iOS — un
upload interrompu (app tuée en cours d'envoi, coupure réseau prolongée) ne reprenait JAMAIS sans
que l'utilisateur rouvre la conversation ET fasse défiler jusqu'à la bulle concernée.

**Correction appliquée** : portée réduite documentée — seul le déclencheur reconnexion socket est
reproduit (`ChatRepository.onConnected()`, déjà appelé sur `.connect` ET `.reconnect`), ni scan
périodique en arrière-plan (`BGTaskScheduler`, même famille d'infrastructure déjà écartée dans
V5-F-060 DIFFÉRÉ) ni scan à la réception d'une notification push, ni politique de retry/backoff
dédiée (contrairement à `UploadChatWork`+`WorkManager` — un échec laisse `isFileUploaded=0`,
retenté au prochain `onConnected()`/`handleAppear`, à l'identique de la politique déjà en place
côté `requestUpload`). Ajouté `MessageRepository.pendingUploads(currentUsername:)` (scan
`isFileUploaded==0 AND usernameFrom==currentUsername`, TOUTES conversations confondues, pas de
filtre `conversationId`) et `ChatRepository.resumePendingUploads(currentUsername:)` (ré-upload via
`ChatMediaUploadService` + persistance `updateFileUploaded` + ré-émission socket
`sendPrivateMessage`/`sendGroupMessage` pour chaque message trouvé, appelé depuis `onConnected()`).

**Risque identifié et corrigé pendant la correction** : ce nouveau chemin (`resumePendingUploads`,
déclenché par reconnexion socket) peut désormais courir CONCURREMMENT avec `ChatViewModel.
requestUpload` (déclenché par une bulle visible) pour le MÊME message, si une conversation est
ouverte au moment d'une reconnexion — risque de double PUT BunnyCDN et surtout de double
`sendPrivateMessage`/`sendGroupMessage` pour le même `messageId` (doublon perçu par le
destinataire, même famille de risque que V5-F-070). Corrigé par un verrou synchrone partagé :
`ChatMediaUploadService.reserveUpload(messageId:)`/`releaseUpload(messageId:)`, un simple
`Set<String>` protégé par le fait que les DEUX appelants (`ChatViewModel`, `ChatRepository`) sont
`@MainActor`-isolés et que la réservation elle-même ne contient AUCUN `await` interne entre le
test et l'insertion — donc atomique du point de vue MainActor, sans nécessiter d'`actor` dédié
(contrairement à `SerialTaskQueue`, V5-F-070, dont le problème venait justement d'un `await`
interne à l'opération protégée).

**Fichiers modifiés** : `Sources/TiinverSwift/Storage/MessageRepository.swift`,
`Sources/TiinverSwift/Realtime/ChatRepository.swift`,
`Sources/TiinverSwift/Messagerie/ChatViewModel.swift`,
`Sources/TiinverSwift/Messagerie/ChatMediaUploadService.swift`.

**Flux frère vérifié** : `requestDownload` (téléchargement, V5-F-077 corrigé juste avant dans ce
même lot P1) non concerné — mécanisme de reprise distinct, pas de risque de concurrence
équivalent identifié côté téléchargement (pas de second déclencheur ajouté sur cette branche).

**Résultat CI** : commit `d5b583c`, push confirmé (`fde9608..d5b583c main -> main`), run
`32937077298` → **`conclusion: success`**.

**Statut honnête** : `BUILD_VALIDATED`, portée réduite documentée. PAS `COMPLETE_PARITY_VALIDATED`
— test réel requis : envoyer une pièce jointe chat, tuer l'app (ou couper le réseau) avant la fin
de l'upload, rouvrir l'app SANS revenir sur la conversation concernée, confirmer que l'upload et
l'envoi du message reprennent automatiquement dès la reconnexion socket ; confirmer aussi l'absence
de doublon si la conversation est rouverte pendant qu'une reprise est en cours.

## 2026-08-26 — Phase B V5 — V5-F-082 (Animems — habillage promotionnel export/partage) — DIFFÉRÉ

**Pas de commit** — décision de report, pas un correctif de code.

**Finding** : Android lance un pipeline de composition secondaire complet au partage externe d'une
vidéo Animems exportée (bouton "Partager" natif, PAS "Publier") : un outro de 4 secondes (logo
Tiinver + nom d'utilisateur + message "Connect, grow and monetize") ET un watermark animé (5
keyframes de position/échelle/alpha/rotation avec interpolation bézier, se déplaçant haut-gauche →
haut-droite → bas-gauche puis fixe) superposés sur toute la vidéo — mécanisme de croissance
virale/attribution systématique. Côté iOS, `AnimemesEditorView`'s `ShareLink` partage le fichier
brut d'`AnimemesExporter` directement, sans aucune étape de composition — confirmé par grep
exhaustif de "watermark"/"outro"/"UnifiedComposer" (seule occurrence : un TODO explicite déjà
présent dans `AnimemesExporter.swift` avant ce cycle).

**Investigation menée avant la décision** : lu directement (au-delà de la citation de l'audit) les
3 fichiers Android sources réels : `UnifiedComposerFinal.java` (719 lignes, composition/muxing
final main+outro+watermark), `AnimatedWatermarkComposer.java` (166 lignes, interpolation bézier
par keyframe), et `ExportVideoService.java:280-480` (configuration outro + les 5 keyframes exacts
avec leurs valeurs bézier). Confirmé aussi : asset logo `mipmap/ic_logo.png` (5 densités Android)
et chaîne `R.string.connect_grow_and_monetize` = "Connect, grow and monetize" existent côté
Android mais N'ONT AUCUN équivalent côté iOS (ni asset catalog, ni chaîne localisée).

**Décision** : `DIFFÉRÉ`, 4 raisons cumulatives — (1) ~900+ lignes de code natif bas niveau
MediaCodec/MediaMuxer à REDESIGNER (pas transposer ligne à ligne) pour AVFoundation via un
compositeur `AVVideoCompositing` personnalisé, infrastructure dont AUCUN équivalent n'existe
ailleurs dans ce dépôt iOS ; (2) portage d'asset binaire (logo) + chaîne localisée nécessaire,
décisions de sélection/format allant au-delà d'un correctif de code pur ; (3) risque de régression
ÉLEVÉ sur le flux CŒUR d'export/partage Animems — ce compositeur s'insère directement dans le
chemin du fichier réellement partagé, une implémentation précipitée pourrait produire un fichier
corrompu pour TOUS les exports, strictement pire que l'absence actuelle de branding ; (4) même
l'option "au minimum" de la RECOMMANDATION reste un sous-système `AVVideoCompositing` entièrement
nouveau, non réductible à un correctif chirurgical compatible avec la cadence de ce balayage
automatisé. Les valeurs exactes (keyframes, durée, ratios de texte) sont déjà toutes documentées
dans `MIGRATION_PARITY_AUDIT_V5.md` — l'implémentation future n'aura pas besoin d'une nouvelle
lecture du source Android, seulement d'une session de conception AVFoundation dédiée.

**Statut honnête** : `DIFFÉRÉ`. Aucun fichier modifié, aucun commit, aucune CI.

## 2026-08-26 — Phase B V5 — Lot P1-34 : V5-F-085 (Photo Editor — manipulation des calques placés)

**Commit** : `df853b8` — CI **success** (run `32938280334`).

**Cause exacte** : `ImageViewCanvas.java:1156-1358` (`GestureListener.onSingleTapUp`/`onScroll`,
`ScaleListener.onScale`, rotation à deux doigts) permet de sélectionner puis glisser, pincer-zoomer
(bornes `MIN_SCALE`/`MAX_SCALE` = 0.3/5.0) et pivoter librement TOUT calque non verrouillé de type
!= PATH après son ajout au canevas (texte, emoji, image ajoutée) — comportement standard de tout
éditeur type Stories/mèmes. Côté iOS, `PhotoToolsView` ne portait que le sous-ensemble "ajout" de
chaque type de calque : `drawGesture` (le seul geste du fichier) n'est actif qu'en mode peinture et
attaché au `ZStack` entier, jamais à un élément individuel ; `addText`/`addSticker` fixaient la
position une seule fois à l'ajout sans aucun moyen ultérieur de la modifier. Le commentaire de tête
du fichier signalait ce manque comme "périmètre volontairement réduit" mais sans jamais l'avoir
formalisé en finding numéroté ni évalué.

**Correction appliquée** : `PlacedText` gagne `scale: CGFloat = 1`/`rotation: Angle = .zero`.
Nouvelle vue `PlacedItemView` (prend un `Binding<PlacedText>`) enveloppe chaque calque du
`ForEach($texts)` avec 3 gestes composés : `DragGesture` (translation de `position`),
`MagnificationGesture` (clampée EN TEMPS RÉEL aux bornes 0.3...5.0, fidèle à `ScaleListener.
onScale` qui corrige `scaleFactor` dès que la borne est dépassée, pas seulement au relâché),
`RotationGesture` (rotation libre, aucune borne côté Android, reproduite à l'identique) — les 3 via
`.gesture()`+`.simultaneousGesture()` pour reconnaissance simultanée (pincer+pivoter+glisser en
même temps, comme Android). `flatten()` applique `scaleEffect(item.scale)`/`rotationEffect(item.
rotation)` avant `.position()` lors de la composition finale, dans le même ordre que le rendu live.
Les gestes sont désactivés pendant le mode peinture (`allowsHitTesting(!isDrawMode)`) pour ne pas
concurrencer `drawGesture`.

**Écart mineur assumé et documenté** : pas d'indicateur visuel de sélection dédié (`objectInAction`
côté Android). SwiftUI route déjà chaque geste au calque effectivement touché via son propre
hit-testing (`ForEach($texts)`, un geste par vue) — comportement observable équivalent
(glisser/pincer/pivoter fonctionne directement sur l'élément touché), simplement sans surbrillance
pendant la manipulation.

**Fichiers modifiés** : `Sources/TiinverSwift/PhotoEditor/PhotoToolsView.swift`.

**Flux frère vérifié** : `flatten()` (composition finale avant publication, déjà correctement
fidèle après V3-F-126) mis à jour en cohérence — mêmes valeurs `scale`/`rotation` appliquées dans
le même ordre de transformation que le rendu live, pour que le résultat final corresponde
exactement à ce que l'utilisateur voyait à l'écran.

**Résultat CI** : commit `df853b8`, push confirmé (`7fa46a2..df853b8 main -> main`), run
`32938280334` → **`conclusion: success`**.

**Statut honnête** : `BUILD_VALIDATED`. PAS `COMPLETE_PARITY_VALIDATED` — test réel requis :
ajouter plusieurs textes/stickers superposés, confirmer que glisser/pincer-zoomer/pivoter
fonctionnent indépendamment sur chacun sans interférence, confirmer que le rendu final
(`flatten()`) reflète fidèlement la position/échelle/rotation finale de chaque calque.

Ce fichier sera alimenté lot par lot, dans le même format que `MIGRATION_PARITY_PROGRESS_V4.md`.

Pour chaque lot futur, le format attendu est :

```
## <date> — Phase B V5 — Lot N : <ID> (<titre court>)

**Commit** : `<sha>` — CI **<résultat>**.

**Cause exacte** : ...

**Fichiers modifiés** : ...

**Flux frère vérifié** : ...

**Statut honnête** : `BUILD_VALIDATED` (CI verte) — PAS `COMPLETE_PARITY_VALIDATED` (device-test
requis, indisponible dans cet environnement) sauf indication contraire explicite de l'utilisateur.
```

Règles strictes héritées du cycle V4, à respecter identiquement pour V5 :
- Ne pas corriger un finding uniquement parce qu'il est marqué. Vérifier d'abord qu'il s'agit
  réellement d'une différence Android/iOS (Android source de vérité, mais jamais de code mort).
- Si le finding est déjà corrigé par un autre commit (dont un correctif V4), marquer
  doublon/résolu, ne pas modifier le code inutilement.
- Si le problème dépend du backend, d'Apple Developer, d'un serveur ou d'un test physique
  impossible à réaliser actuellement, marquer `BLOQUÉ` avec la raison précise.
- Ne jamais transformer `BUILD_VALIDATED` en `COMPLETE_PARITY_VALIDATED` sans test réel confirmé.
