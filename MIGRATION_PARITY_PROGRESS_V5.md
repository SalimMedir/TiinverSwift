# MIGRATION PARITY PROGRESS V5

Journal de correction du cycle d'audit V5 (`MIGRATION_PARITY_AUDIT_V5.md`).

**État actuel (2026-08-25) : Phase A (Audit) TERMINÉE. Phase A.2 (contre-audit ciblé) TERMINÉE.
Phase B (correction) EN COURS — **BACKLOG P0 ENTIÈREMENT TRAITÉ (7/7)** : V5-F-094, V5-F-018,
V5-F-031, V5-F-032, V5-F-042, V5-F-045, V5-F-064 (V5-F-064 = doublon de V5-F-005, résolu en même
temps). Backlog P1 (40 findings) EN COURS [8/40 clos : V5-F-001, V5-F-005 (DUPLICATE), V5-F-006,
V5-F-007, V5-F-009, V5-F-010, V5-F-013, V5-F-016], démarré automatiquement à V5-F-001, dans
l'ordre du document. Prochain : V5-F-019. Puis 31 P2, 21 P3.**

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
