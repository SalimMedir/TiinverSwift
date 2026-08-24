# CLAUDE_CONTINUATION.md — Mémoire persistante entre sessions Claude Code

**Ce fichier est la mémoire de continuité du portage Android → iOS de Tiinver.**
Une nouvelle session doit le lire EN PRIORITÉ, mais le CROISER avec `MIGRATION_AUDIT.md` (audit
détaillé, cartographie complète), `MIGRATION_PROGRESS.md` (journal chronologique complet, ~3500
lignes) et l'état réel du code + `git log` — ne jamais faire confiance aveuglément à un seul
document. Voir section 15 du prompt-cadre de ce projet : plusieurs sessions travaillent
successivement sur le même dépôt, ne jamais supposer être seul à l'avoir modifié.

---

# CURRENT HANDOFF (2026-08-24 — cycle V3 clos [backlog P2/P3 épuisé], cycle V4 Phase A terminée,
Phase B V4 : backlog P0 épuisé, LISTE P1 IMPOSÉE ENTIÈREMENT TRAITÉE [22 corrigés BUILD_VALIDATED
+ V4-F-003 BLOQUÉ], **backlog P2 EN COURS** [Lot P2-1 : V4-F-004 BLOQUÉ, V4-F-006 différé,
V4-F-009/010/011 BUILD_VALIDATED ; Lot P2-2 : V4-F-012 BUILD_VALIDATED] — backlog P3 PAS ENCORE
ATTAQUÉ)

**⚠️ Les entrées "suite 2" à "suite 5" ci-dessous (toutes datées 2026-08-17) sont PÉRIMÉES.**
Conservées pour l'historique GAP-020 à GAP-023 uniquement — ne pas s'y fier pour l'état actuel.

## Cycle V3 (CLOS pour ce cycle — voir `MIGRATION_PARITY_AUDIT_V3.md`/`PROGRESS_V3.md`)

Backlog P0/P1/P2/P3 balayé exhaustivement finding par finding, preuve Android fichier:ligne à chaque
fois. Tout ce qui restait ouvert est soit corrigé (CI verte), soit documenté comme légitimement
bloqué (backend/serveur/test physique — V3-F-078/081/084/115/121/140/036/046), soit une prémisse
invalidée (V3-F-133/151). **Tous les correctifs V3 sont `BUILD_VALIDATED`, AUCUN
`COMPLETE_PARITY_VALIDATED`** — tests réels sur device toujours en attente, détail lot par lot dans
`PROGRESS_V3.md`. V3-F-095 (analytics temps de visionnage) reste différé.

## Cycle V4 — NOUVEAU (2026-08-23)

**Phase A (Audit) TERMINÉE** : `MIGRATION_PARITY_AUDIT_V4.md` contient 75 findings (V4-F-001 à
V4-F-075, 16 domaines), produits par 16 agents de recherche indépendants qui n'ont PAS lu les audits
V1/V2/V3 (pour maximiser les chances de trouver ce qu'ils ont manqué). 4 findings découverts
indépendamment par 2 agents différents (signal de fiabilité fort) : V4-F-008 (upload photo profil),
et les findings fusionnés sous V4-F-004/012/022/031. Répartition : 3 P0, 25 P1, 32 P2, 15 P3.
**AUCUN code modifié pendant la Phase A.** Commit `0d9caeb`.

**Phase B DÉMARRÉE (2026-08-23)** — ordre imposé par l'utilisateur : P0-1(V4-F-065) →
P0-2(V4-F-040) → P0-3(V4-F-007) → P0-4(V4-F-008) → puis 23 items P1 dans un ordre précis (voir le
prompt Phase B de l'utilisateur pour la liste complète si besoin de la reconstituer). Règle stricte :
un lot à la fois, jamais plusieurs findings en parallèle, vérification Android AVANT toute
modification Swift à chaque fois.

**Lot P0-1 traité (V4-F-065 + V4-F-066)** — Wallet, bug financier réel : le crédit de récompense
post-retrait/transfert/conversion (`showRewardedInterstitialAfterSuccess` dans `WithdrawView.swift`/
`TransferCoinsView.swift`/`ConversionView.swift`) envoyait le SOLDE TOTAL du compte au serveur
(`rewardedCoins`) au lieu du DELTA (`pendingCoinCount + currenGainCoins`, vérifié dans
`wallet/WalletRepository.java:301-328` — le solde total Android ne sert QUE à l'affichage local,
jamais envoyé au réseau). Corrigé en reproduisant exactement le motif déjà validé dans
`EarnCoinsView.onRewardEarned` (V3-F-092) : delta calculé via `pendingCoinsAmount`, remis à 0 sur
succès, accumulé sur échec (ce qui résout aussi V4-F-066 dans la foulée — même fonction Android de
référence, même 3 fichiers). Détail complet, preuve Android ligne par ligne, et flux frères vérifiés
(`grep creditReward` = exactement 5 sites, aucun autre écran affecté) dans `PROGRESS_V4.md`, Lot
P0-1. **Commit `393b485`, CI verte confirmée (run `32663823532`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : regarder la pub après un retrait réel, inspecter le
payload réseau `rewardedCoins`, confirmer que le solde serveur n'augmente pas anormalement).

**Lot P0-2 traité (V4-F-040)** — Calls, push VoIP pendant un appel en cours saute le report CallKit
obligatoire. Pas d'équivalent Android (obligation PushKit propre à iOS) — référence : le contrat
Apple lui-même + le motif déjà validé sur la branche sœur "payload malformé" de la même fonction
(V3-F-031). `guard state == .idle else { onReported?(); return }` (`CallCoordinator.swift:199`) est
atteinte par 2 chemins réels (tracés via `grep handleIncomingCall(` = exactement 2 sites) : (a) socket
normal app-déjà-active (`onReported=nil`, no-op fidèle à Android, `ChatRepository.lunchcall` ignore
aussi silencieusement ce cas — INCHANGÉ) ; (b) push VoIP pendant un appel en cours (`onReported!=nil`
= le callback PushKit système, DOIT être précédé d'un report CallKit quel que soit l'état de l'app).
Corrigé : chemin (b) reporte maintenant un appel générique puis le termine (`reason: .failed`), même
motif que la branche payload malformé voisine. Détail complet dans `PROGRESS_V4.md`, Lot P0-2.
**Commit `14e5ee1`, CI verte confirmée (run `32664500075`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel quasi impossible sans backend VoIP fonctionnel + 2 appareils).

**Lot P0-3 traité (V4-F-007)** — Viewer plein écran (`FeedDetailPagerView`) : boutons "..."
(supprimer/copier lien/ne plus suivre/bloquer/signaler/télécharger) et commentaire réellement morts.
Portée RÉELLE plus large que le texte d'audit (limité à Profile) : `grep FeedDetailPagerView(` a
confirmé que 5 des 6 appelants (`SearchView`/`HashtagFeedView`/`NotificationsListView`/
`HomeShellView`/`ProfileView`) utilisaient l'init `posts:` dont `onComment`/`onMore` retombaient sur
`{ _ in }` — le pager affichait les boutons mais rien ne se passait au tap, PARTOUT sauf depuis le
fil principal (`FeedView`, seul appelant à fournir de vraies closures). Vérification Android : 4
menus "..." lus intégralement (`ProfileFeedFragment`/`MainFragment`/`FullScreenMedia`/
`HashtagProfile`) — confirmé que `download` n'est câblé QUE dans `ProfileFeedFragment` (les 3 autres
n'ont pas l'item, ou pointent vers un handler mort/buggé), donc PAS ajouté ailleurs. Corrigé : tout
l'état/dialogues déplacé DANS `FeedDetailPagerView` elle-même (plus de closures remontées à
l'appelant), avec 2 flags `showManagementActions`/`includesDownload` pour les 2 écarts légitimes
(Statistiques/Promouvoir = `FeedView` seul ; téléchargement = `ProfileView` seul). Nouveau
`FeedMediaDownloader.swift` : port fidèle de `checkBestQualityAndDownload`/`downloadFile` (sonde
HEAD 720p/480p/360p, `Referer: https://tiinver.com`, repli `cdn_content_url` brut,
`PHPhotoLibrary.performChanges`), + `NSPhotoLibraryAddUsageDescription` ajoutée à `project.yml`.
Détail complet dans `PROGRESS_V4.md`, Lot P0-3. **Commit `d9bb80e`, CI verte confirmée (run
`32665481871`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (chacune des 5 actions à
vérifier séparément sur device réel, depuis chacun des 6 points d'entrée — y compris la première
demande d'autorisation Photos jamais déclenchée avant ce correctif).

**Lot P0-4 traité (V4-F-008)** — Profile, upload photo de profil contournait BunnyCDN. Reconfirmé
par relecture directe (pas seulement Phase A) : `AddPerfilFoto.java:558`
(`// profileViewModel.uploadPhotoProfile(foto);`) est commenté, seul site d'appel possible de
`ProfileRepository.uploadPhotoProfile` — chemin mort. Le vrai flux (`uploadProfilePicture`, ligne
557, toujours exécuté → `ProfileService`) fait PUT direct vers Bunny Storage
(`storage.bunnycdn.com/tiinver-media/tiinver/profile/photos/{token}.webp`, `AccessKey`) puis POST
`user/avatar/add` avec l'URL CDN ABSOLUE résultante (`cdn.tiinver.com/...` — différent du chemin
RELATIF que renvoie le flux Feed, écart réel entre les deux, pas une simplification). iOS portait le
POST multipart mort vers `{SERVER}user` — réécrit pour reproduire PUT Bunny + POST `user/avatar/add`.
**Décision prise avec l'utilisateur pendant ce lot** : les constantes de stockage BunnyCDN
(zone/clé/hôte) sont RÉUTILISÉES depuis `FeedMediaUploader` (rendues internes) plutôt que
redupliquées une 3ᵉ fois dans `ProfileRepository.swift` — bien qu'Android lui-même triple ces
littéraux dans 3 fichiers source, le détecteur de secrets de la session a bloqué le premier `git
add`/`git push` contenant une 3ᵉ copie littérale de la clé d'accès ; réutiliser la constante existante
évite cette 3ᵉ occurrence en clair dans le dépôt SANS changer le comportement réseau (même zone/clé/
hôte). `CertificationRepository.submit` vérifié comme un flux séparé non affecté. Détail complet dans
`PROGRESS_V4.md`, Lot P0-4. **Commit `4293e06`, CI verte confirmée (run `32673048282`)** —
`BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : changer l'avatar sur un compte
réel, inspecter le PUT Bunny + le POST `user/avatar/add`, confirmer que l'avatar rechargé depuis
`getuserbyid` correspond à l'image envoyée).

**Backlog P0 (V4) épuisé** — les 4 lots P0 sont tous `BUILD_VALIDATED`, CI verte à chaque fois.

**Lot P1-1 traité (V4-F-020)** — Groups, 7 méthodes de `GroupRepository.swift`
(`updateMemberRole`/`removeMember`/`updateDescription`/`updateName`/`leaveGroup`/`subscribeToGroup`/
`renewGroupSubscription`) discardaient la réponse serveur (`_ = try await ...`) au lieu de vérifier
`value.isBackendSuccess`, contrairement à `createGroup`/`fetchGroup` dans le même fichier. Vérifié
dans `Http/TransportData.java:615-681` (lu en entier) : le `if (action==0)` de chaque appelant Android
est un artefact — `action` est un littéral `0` fixé par le framework UNIQUEMENT dans la branche
`error.equals("false")` du callback ; le vrai gate est `error=="false"`, exactement
`JSONValue.isBackendSuccess`. Les 7 appelants iOS (`GroupDetailView.swift`,
`ChatViewModel.resolveGroupSubscription`) enveloppaient déjà chaque appel dans un `do/catch`
n'appliquant les effets locaux qu'après succès — il ne manquait que le `throw` côté dépôt. Correctif :
`guard value.isBackendSuccess else { throw ... }` ajouté aux 7 méthodes, aucun changement côté
appelants. Détail complet dans `PROGRESS_V4.md`, Lot P1-1. **Commit `6190dee`, CI verte confirmée (run
`32673545395`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : provoquer un
rejet backend réel et confirmer que l'effet local ne s'applique pas).

**Lot P1-2 traité (V4-F-032)** — Feed, supprimer son propre post retirait le post du fil MÊME si
l'appel serveur échouait. Vérifié dans `ActivityAdapter.deleteMyPost`
(`Activity/adapter/ActivityAdapter.java:847-867`) : `deletePostById` (retrait local) n'est appelé QUE
dans `onResonse` (succès), `onError` affiche seulement un Toast — même contrat `TransportData.Post`
que V4-F-020. `FeedRepository.deleteActivity` vérifiait déjà `isBackendSuccess` et levait
correctement ; le `try?` de `FeedViewModel.deleteOwnPost` avalait cette levée, puis
`posts.removeAll` s'exécutait inconditionnellement. Corrigé : retrait local conditionné au succès
réel (`do/catch`), nouvelle propriété `@Published var deleteError: String?` (équivalent du Toast
Android) affichée via une alerte dans les 2 vrais sites d'appel (`FeedView` grille,
`FeedDetailPagerView` plein écran). `hideOthersPost` (pas d'appel serveur côté Android, masquage
local seul) et `block` (même pattern bugué, mais finding SÉPARÉ V4-F-033) délibérément non touchés.
Détail complet dans `PROGRESS_V4.md`, Lot P1-2. **Commit `f503a72`, CI verte confirmée (run
`32674024379`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : provoquer
un rejet serveur réel sur une suppression et confirmer que le post reste visible avec l'alerte).

**Lot P1-3 traité (V4-F-033)** — Feed, bloquer un utilisateur depuis le Feed retirait son post même
en cas d'échec ou de bascule inverse (déblocage). Vérifié dans `MainFragment.block()`
(`Activity/ui/MainFragment.java:1704-1758`, entier) : `mAdapter.deletePost` n'est appelé QUE sur
`message.equals(USER_BLOCKED)` — pas sur `USER_UNBLOCKED` (bascule inverse), pas sur `onError`
(Toast seul). `ProfileRepository.toggleBlock` retournait déjà le bon `Bool`
(`message == "USER BLOCKED"`), mais `FeedViewModel.block` le discardait (`_ = try?`) et retirait le
post inconditionnellement. Corrigé : retrait local conditionné à `blocked == true`. **Décision de
scope** : pas d'UI d'erreur ajoutée (contrairement à V4-F-032) — `toggleBlock` ne distingue pas
"déblocage légitime" de "rejet backend" (les deux retournent `false`) et la modifier aurait affecté
`ProfileViewModel.toggleBlock` (bouton Profil, usage différent, déjà correct), hors périmètre de ce
lot ; le comportement correct (ne pas retirer le post) est identique dans les deux cas. Détail complet
dans `PROGRESS_V4.md`, Lot P1-3. **Commit `8d6ebae`, CI verte confirmée (run `32674513016`)** —
`BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : bloquer puis débloquer un
utilisateur depuis le Feed, confirmer le retrait uniquement sur blocage réussi).

**Lot P1-4 traité (V4-F-042)** — WebRTC-Calls, notification d'appel manqué déclenchée du mauvais côté
(logique inversée). Vérifié dans `CallActivity.java` (entier) + `CallService.java:571-612` :
`CallActivity` (qui possède `isCalleMissedCall`/`notifyMissedCall`) n'est lancée QUE pour
`callType==OUTGOINGCALL` — le côté entrant route TOUJOURS vers `IncomingCallActivity`, classe séparée
qui n'appelle jamais `notifyMissedCall`. `isCalleMissedCall` (init `true`) n'est remis à `false` que
sur acceptation ou `callEnd()` socket (l'autre partie a raccroché) ; `endCall()` notifie
UNIQUEMENT si encore `true` — donc UNIQUEMENT côté appelant, sur un appel sortant jamais décroché.
`CallCoordinator.performEndCall` avait la garde inversée (`if !isOutgoingCall, !wasAnswered` — côté
CALLEE). Corrigé : simple inversion (`if isOutgoingCall, !wasAnswered`), aucune logique
supplémentaire. `grep notifyMissedCall` → un seul site d'appel dans tout le projet, celui corrigé ;
`endCallFromRemote` (chemin "l'autre a raccroché") ne déclenche pas cette notification, fidèle à
Android. Détail complet dans `PROGRESS_V4.md`, Lot P1-4. **Commit `9de2d73`, CI verte confirmée (run
`32674952912`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : appel
sortant non répondu + raccrocher → message "appel manqué" ; appel entrant refusé → AUCUN message côté
callee, idéalement testé avec un pair Android réel pour l'interopérabilité).

**Lot P1-5 traité (V4-F-038)** — Chat-Socket, race condition : un message reçu par socket pendant le
chargement initial de l'historique était perdu visuellement. Vérifié dans `ChatFragmentTest.java:220`
: `messages` est un `LinkedList<MessageLib>` UNIQUE, jamais réassigné en bloc — chargement initial ET
socket AJOUTENT toujours, jamais de remplacement. `ChatViewModel.loadInitial()` faisait `items =
built` INCONDITIONNELLEMENT après `await messages.page(...)`, écrasant tout ce qu'`onIncoming`
(actif dès `init` via `subscribeToRealtimeEvents`, capable de s'exécuter concurremment pendant ce
même `await`) aurait ajouté entre-temps. Corrigé : fusion — tout message encore présent dans `items`
après l'`await` et absent de la page fraîche est réinjecté, l'ensemble trié par `stamp`, puis les
séparateurs de date reconstruits sur la liste fusionnée. `loadMore()` (pagination) n'avait PAS ce
problème (`items.insert(at: 0)`, jamais de remplacement) — non touché. Détail complet dans
`PROGRESS_V4.md`, Lot P1-5. **Commit `d093438`, CI verte confirmée (run `32675426271`)** —
`BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (scénario de course difficile à provoquer sans
outillage — ralentir `messages.page` en debug pour élargir la fenêtre, envoyer un message depuis un
second appareil pendant ce délai, confirmer qu'il reste visible sans fermer/rouvrir la conversation).

**Lot P1-6 traité (V4-F-017)** — Settings, toggle confidentialité gardait le mauvais état visuel en
cas d'échec serveur. Cause racine plus profonde que le seul `try?` de `SettingPrivacyView.save` :
`ProfileRepository.updateProfileField` (méthode PARTAGÉE, 9 appelants) discardait la réponse sans
jamais vérifier `isBackendSuccess` — ne pouvait donc JAMAIS lever sur un rejet backend, seulement sur
échec réseau. Vérifié dans `SettingPrivacityFragment.swichtToPrivate` (lignes 294-328, entier) :
`onError` fait `account_type_switch.setChecked(!isChecked)`, ET câblé sur `setOnClickListener` (pas
`setOnCheckedChangeListener`) donc ce revert NE redéclenche PAS d'appel réseau. Corrigé :
`updateProfileField` lève désormais correctement (0 changement observable pour les 8 appelants
`try?` déjà indifférents ; `CategoryPickerView.save`, qui avait déjà un `do/catch` prêt, en bénéficie
gratuitement) ; `SettingPrivacyView.save` fait `do/catch` + revert `isPrivate` sur échec, avec un
flag `isReverting` pour empêcher `.onChange(of:)` de SwiftUI (qui, contrairement à `setChecked`
Android, redéclenche TOUJOURS) d'envoyer un second appel réseau non désiré lors du revert. Détail
complet dans `PROGRESS_V4.md`, Lot P1-6. **Commit `d63c2f6`, CI verte confirmée (run `32675965460`)**
— `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : couper le réseau, basculer
le toggle, confirmer le revert visuel SANS second appel réseau observable).

**Lot P1-7 traité (V4-F-046)** — Animems-ImportExport, collision PTS frame 0/frame 1 à l'export
vidéo. `AnimemesExporter.swift:202` : `max(frameDurationNs, Int64(f) * frameDurationNs)` donnait
EXACTEMENT `frameDurationNs` pour `f=0` ET `f=1` (calcul direct vérifié) — aucun échantillon jamais
écrit à pts=0 malgré `startSession(atSourceTime: .zero)`. Vérifié côté Android
(`MP4Encoder.java:1752-1753`, `getPresentationTimeUsec(frameIndex) { return frameIndex * FRAME_NS;
}`) : aucun clamp équivalent. Recherche de justification historique du `max(...)` (demandée
explicitement avant suppression) : aucun commentaire, aucune trace `git log -p` ne l'explique.
Corrigé : `max(...)` retiré, `ptsNs = Int64(f) * frameDurationNs`. Seul `f=0` change de valeur
(`f>=1` produisait déjà le même résultat avec ou sans clamp) — aucun risque de régression au-delà de
la 1ʳᵉ frame. `grep frameDurationNs/ptsNs` → un seul site de calcul PTS dans tout le module, piste
audio indépendante (timestamps natifs). Détail complet dans `PROGRESS_V4.md`, Lot P1-7. **Commit
`b0b61ea`, CI verte confirmée (run `32676432499`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : exporter une vidéo, `ffprobe -show_frames` pour
confirmer pts=0 sur la 1ʳᵉ frame sans doublon).

**Lot P1-8 traité (V4-F-048)** — Animems, zoom du canevas inerte visuellement. Chaîne complète tracée
(UI→état→renderer→geste→export, sur les DEUX plateformes) avant correction, conformément à la
consigne de rigueur renforcée. `CanvasZoomState` (algorithme) déjà fidèle avant ce lot — seul le
RENDU manquait (`currentScale` jamais appliqué au `Canvas` SwiftUI). Le risque documenté par une
session précédente (désynchronisation de coordonnées de geste si `.scaleEffect` cohabite avec
`combinedGesture` sur la même vue) analysé et résolu par construction : `.scaleEffect(zoomState.
currentScale)` placé APRÈS `.gesture(combinedGesture)` dans la chaîne de modificateurs —
`.scaleEffect` étant un `GeometryEffect` SwiftUI de premier ordre, les coordonnées tactiles
continuent d'être rapportées dans l'espace LOCAL non-transformé du `Canvas`, donc AUCUNE correction
n'était nécessaire dans `AnimemesEditorState`. Vérifié en plus (au-delà du strict périmètre) :
`AnimemesExporter.render(frame:into:)` dessine dans un `CVPixelBuffer` totalement indépendant du
pipeline interactif — pas d'équivalent requis aux 2 `zoomController.reset()` qu'Android fait avant
encodage. Détail complet dans `PROGRESS_V4.md`, Lot P1-8. **Commit `da0e744`, CI verte confirmée (run
`32677174090`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (raisonnement SwiftUI non
vérifiable empiriquement sans Xcode/simulateur — test réel IMPÉRATIF : confirmer l'effet visuel ET
qu'un geste sur un objet à `currentScale != 1.0` reste cohérent avec le doigt, sans dérive).

**Lot P1-9 traité (V4-F-049)** — Animems, marqueurs de keyframe sans cible tactile. Chaîne complète
tracée (geste Android→état Android→callback Android→rendu Android, puis les 4 mêmes côté iOS AVANT
câblage) conformément à la rigueur renforcée. `hitTestKeyframeMarker`/`KeyframeTrack.removeKeyframe`
DÉJÀ portés fidèlement mais ZÉRO appelant. Câblé : `hitTestKeyframeMarker` testé EN PREMIER dans
`combinedDragGesture` (avant `resolveMode`), nouveau `DragMode.keyframeTap` (port du `return true`
d'`onDown`, consomme toute la touche). 1er tap = sélection (`TimelineViewModel.selectedKeyframeId`,
nouveau) ; 2e tap sur le MÊME keyframe = suppression (`AnimemesEditorState.deleteKeyframe`, nouveau,
`version += 1` — structurel, pas `renderVersion` — via `AnimationObjectData.removeKeyframe`,
nouveau). Ajouté AU-DELÀ du strict texte de l'audit : le contour blanc de sélection
(`kfSelectPaint`) dans `drawKeyframeMarkers`, sans quoi l'utilisateur n'aurait aucun moyen visuel de
savoir quel keyframe est armé pour suppression. Détail complet dans `PROGRESS_V4.md`, Lot P1-9.
**Commit `fc60738`, CI verte confirmée (run `32677846820`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : tap→contour blanc, tap à nouveau→suppression +
canevas mis à jour, tap sur un AUTRE keyframe→simple changement de sélection).

**Lot P1-10 traité (V4-F-050)** — Animems, icônes verrou/visibilité par calque totalement absentes,
aucune protection au niveau geste. **DERNIER des 3 findings Animems à rigueur renforcée — tous
CLOS.** Recommandation initiale de l'audit CORRIGÉE par relecture directe de `MemesView2.java` : la
garde `.isLocked()` n'existe QUE dans 3 sites réels (`onScroll`, `onScale`, la boucle de dispatch
`onTouchEvent` dont `rotate()` dépend via `executeTouchEvent`) — JAMAIS dans `touchDown`/
`isPointInsideObject` (sélectionner un calque verrouillé reste possible côté Android, seule la
manipulation est bloquée). Visibilité confirmée séparément : ne gate JAMAIS le geste sur Android non
plus (rendu uniquement, déjà correct côté iOS). Corrigé fidèlement : `toggleLocked`/`toggleVisible`
(nouveau, `AnimemesEditorState`, `version += 1`) ; garde `!layers[idx].locked` ajoutée à
`dragMoved`/`rotationChanged`/`scaleChanged` UNIQUEMENT (pas `selectObject`) ; icônes verrou/œil
dessinées dans le panneau gauche de `TimelineView` (jusqu'ici vide), lues directement depuis
`AnimationObjectData.locked/.visible` (pas le registre générique `trackIcons` déjà présent mais
réservé à la 3ᵉ icône Android "compose group", séparée et déjà différée) ; nouveau `DragMode.iconTap`
inséré dans `combinedDragGesture` entre le hit-test keyframe et le repli `resolveMode`, même ordre
qu'Android. **Incident CI** : 1er commit (`8ab3088`) a échoué (`Image.foregroundColor`/`resolve`
ambigu sous Xcode 16.2) — corrigé (`1ff1032`) via `Text(Image(systemName:))` +
`context.draw(_:at:)`, motif déjà éprouvé dans ce même fichier (`drawRuler`). Détail complet dans
`PROGRESS_V4.md`, Lot P1-10. **CI verte confirmée (run `32679329863`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : icône verrou → bascule + blocage réel du geste ;
icône œil → bascule + masquage réel ; calque verrouillé reste sélectionnable).

**Lot P1-11 traité (V4-F-001)** — Session-Auth, cold start bloqué derrière un fetch réseau Firebase
Remote Config. Vérifié dans `SplashActivity.java:80-122` (entier) : Android navigue Home/Login/
UpdateApp de façon SYNCHRONE à partir du cache LOCAL du SDK Remote Config (`setDefaultsAsync`,
appliqué SYNCHRONEMENT à l'init malgré le nom, ou valeurs du dernier fetch réussi) — ZÉRO I/O
réseau — puis lance `fetchAndActivate()` SANS l'attendre, pour la PROCHAINE ouverture.
`RootRouterView.checkForceUpdate()` faisait `_ = await ...fetchAndActivate()` AVANT de lire
`expireDay`/`expireMonth`/`expireYear`, bloquant l'écran racine ENTIER (Home ET Login) jusqu'à ~60s
sur réseau dégradé. Corrigé : lecture cache immédiate (`RemoteConfig.setDefaults(fromPlist:)` = même
mécanisme synchrone qu'Android), `fetchAndActivate()` déplacé dans un `Task` en arrière-plan APRÈS
`configChecked = true`. `grep fetchAndActivate` → un seul site d'appel dans tout le projet, celui
corrigé. Détail complet dans `PROGRESS_V4.md`, Lot P1-11. **Commit `d7d50b0`, CI verte confirmée (run
`32679885732`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : session
locale valide + réseau coupé/dégradé au lancement, confirmer l'arrivée quasi-instantanée sur Home).

**Lot P1-12 traité (V4-F-002)** — Navigation-DeepLinks, lien profond résolu AVANT le montage de
`HomeShellView` silencieusement perdu. Vérifié dans `ShareActivity.java:140-291` : Android résout
puis lance DIRECTEMENT l'écran cible via `startActivity`, sans dépendre qu'une autre Activity soit
déjà à l'écran. `HomeShellView.onChange(of: deepLinks.pending)` (seul consommateur dans tout le
projet, confirmé par grep) ne réagit QUE sur une transition nil→valeur survenant APRÈS l'attachement
du modificateur — jamais pour une valeur déjà présente au montage. Corrigé : table de dispatch
extraite en `handleDeepLink(_:)` partagée, appelée par le `.onChange` existant (inchangé) ET par le
`.task` déjà présent (nouvelle consommation au montage) — `DeepLinkCenter.consume()`'s `defer {
pending = nil }` existant rend les deux appels sûrs sans double traitement. Détail complet dans
`PROGRESS_V4.md`, Lot P1-12. **Commit `97f87fd`, CI verte confirmée (run `32680432322`)** —
`BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : lien profond reçu PENDANT le
cold start/écran de login, avant authentification, confirmer qu'il est honoré une fois `HomeShellView`
monté après connexion).

**Lot P1-13 traité (V4-F-029)** — Feed, publication n'envoyait jamais le consentement IA ni les
métadonnées enrichies (divergence légale/conformité réelle). Gap déjà explicitement documenté par le
cycle V3 (V3-F-017) comme non construit à l'époque — retrouvé indépendamment par l'audit V4 (2
cycles concordants). Vérifié `PublishFragment.java:544-639` + `models/MediaMetaData.java` (entier) :
`acceptAi` (`CheckBox` réelle, `fragment_publish.xml:86-92`) alimente `consentAi`/`license` réels ;
`style`/`content_type`/`bitRate` confirmés TOUJOURS `null`/`0` (jamais assignés dans
`PublishFragment.java`, grep exhaustif) ; `format` uniquement pour une photo (`getVideoMetadata` ne
l'appelle jamais). Corrigé : `Toggle` de consentement IA ajouté à `PublishComposeView` (décoché par
défaut, libellé exact `@string/allow_my_content_for_ai_training`), extraction fps/piste audio pour
la vidéo (à côté de l'extraction width/height/duration déjà existante), nouveau
`FeedRepository.MediaMetaData` (struct Swift, champs Gson exacts) sérialisé en JSON dans `metadata`,
`consentAi` envoyé fidèlement selon l'état réel du toggle. `grep publish(` → 2 seuls sites d'appel
(photo/vidéo), tous deux corrigés. Détail complet dans `PROGRESS_V4.md`, Lot P1-13. **Commit
`ec7dd68`, CI verte confirmée (run `32681106944`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : publier avec le toggle activé ET désactivé, inspecter
le payload réseau `activity/add` pour confirmer `consentAi`/`metadata` corrects dans les deux cas).

**Lot P1-14 traité (V4-F-030)** — Feed, like/partage/commentaire ne notifiaient jamais l'auteur du
post. Portée réelle affinée par rapport au texte d'audit : `notifyUser` câblé dans `MainFragment`
(Feed), `ProfileFeedFragment` (Profile), `HashtagProfile` (hashtag), mais CONFIRMÉ ABSENT de
`FullScreenMedia` (source de `SearchView`/`NotificationsListView`, `grep` = 0). Placement exact
vérifié ligne par ligne : like → inconditionnel après like ET unlike, sans attendre la réponse ;
partage → uniquement sur succès réseau, hors du if/else SHARE/UNSHARE ; commentaire → à l'OUVERTURE
du panneau, pas à l'envoi. Corrigé : `FeedRepository.notifyPostAuthor(userId:)` (nouveau), flag
`notifiesAuthorOnInteraction` sur `FeedViewModel` (init, chaque écran possède déjà son propre
viewModel jetable) — `true` pour Feed/Profile/Hashtag/deep-link, `false` documenté explicitement pour
Search/Notifications. Détail complet dans `PROGRESS_V4.md`, Lot P1-14. **Commit `b6e6807`, CI verte
confirmée (run `32681817117`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel
requis : liker/partager/commenter un post d'un autre compte depuis Feed/Profile/Hashtag → confirmer
la notification reçue ; répéter depuis Search/Notifications → confirmer l'ABSENCE, fidèle à Android).

**Lot P1-15 traité (V4-F-056)** — Gallery-PhotoEditor, le recadrage libre (freeform) ignorait
l'orientation EXIF (photos portrait rendues de côté/en miroir). Vérifié dans
`BitmapLoadingWorkerTask.java:66-79` + `CropImageView.java:981-994` : `rotateBitmapByExif` appliqué
EN AMONT du chargement du bitmap, avant tout branchement rect/oval/freeform — les 3 sous-modes
reçoivent donc déjà un buffer physiquement tourné côté Android. Côté iOS, seul le mode freeform
(`PublishComposeView.swift`, `.freeformCropping`) extrayait `image.cgImage` BRUT, dessiné ensuite
via `Image(decorative:)` (`FreeformCropView.swift:18`) qui ignore `imageOrientation` — le mode
rect/oval (`TOCropViewController`) respecte déjà nativement l'orientation, confirmant exactement la
`DIFFÉRENCE` du texte d'audit. Corrigé : nouvelle `UIImage.normalizedToUpOrientation()` (redessine
via `UIGraphicsImageRenderer`/`draw(in:)`, qui respecte `imageOrientation`) appliquée avant
extraction du `cgImage` ; résultat découpé reconstruit avec `orientation: .up` (pas
`image.imageOrientation`, qui aurait doublé la rotation puisque la source est déjà normalisée).
Flux frères vérifiés : `PhotoCropView.swift:54` (oval, opère sur la SORTIE déjà tournée de
`TOCropViewController`) et `PhotoToolsView.swift` (flip/removeBackground, affiche via
`Image(uiImage:)` pas `decorative:`) — ni l'un ni l'autre affecté ; les `Image(decorative:)` du
module Animems opèrent sur des calques internes, jamais une photo EXIF importée — hors périmètre.
Détail complet dans `PROGRESS_V4.md`, Lot P1-15. **Commit `29385f5`, CI verte confirmée (run
`32682553930`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : publier
depuis une photo portrait EXIF via "Freeform", confirmer que le tracé et le résultat final sont
dans le bon sens).

**Lot P1-16 traité (V4-F-064)** — BunnyCDN-Media, l'upload de pièce jointe de chat chargeait le
fichier entier en RAM avant envoi. Vérifié dans `UploadFileOrDataService.java:242-267,269-301`
(`uploadToBunny`, seul chemin réseau pour LES 4 types de pièce jointe — photo/vidéo/audio/doc,
aucun branchement type-spécifique avant l'appel) + `ProgressRequestBodyUri.java` (entier) :
streaming natif par blocs de 8Ko depuis un `InputStream` sur l'`Uri` du fichier, jamais de
chargement intégral, progression réelle calculée à chaque bloc. Côté iOS,
`ChatMediaUploadService.put` faisait `try Data(contentsOf: localFile)` avant l'envoi — même
anti-pattern à risque OOM déjà corrigé pour l'upload vidéo du Feed principal
(`FeedMediaUploader.uploadVideo`, V3-F-019/BUNNY-03), jamais appliqué au chemin Chat séparé.
Corrigé : `put` passé à `URLSession.shared.upload(for:fromFile:delegate:)` (streaming natif depuis
le disque) ; `UploadProgressDelegate` (`FeedMediaUploader.swift`) rendue interne et RÉUTILISÉE telle
quelle (pas dupliquée), même motif de partage que les constantes BunnyCDN (V4-F-008) ; nouveau
paramètre `progress` optionnel propagé, défaut `nil` (pas de barre de progression UI branchée dans
ce lot — `ChatBubbleViews.swift` affiche déjà un `ProgressView()` indéterminé fidèle à l'écran chat
Android, qui route sa propre progression vers une notification système séparée, hors périmètre des
`IOS FILES` cités par ce finding). Flux frères vérifiés : les 2 usages restants de
`URLSession.shared.upload(for:from:)` (Data en mémoire) sont `FeedMediaUploader.uploadPhoto`/
`ProfileRepository.uploadProfilePicture` — photos compressées, chemin Android correspondant
(`uploadImageToBunny`) non streamé non plus, donc pas affectés. Détail complet dans
`PROGRESS_V4.md`, Lot P1-16. **Commit `1090279`, CI verte confirmée (run `32683050887`)** —
`BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : envoyer une pièce jointe
volumineuse en chat, confirmer via Instruments/Memory Graph l'absence de pic mémoire, et la
réussite de l'upload).

**Lot P1-17 traité (V4-F-059)** — VideoEditor, la sélection de trim n'avait aucun plafond continu
de durée maximale. Vérifié dans `ProTimelineView.java:685-713` (`handleMove`,
`DRAG_LEFT_PX`/`DRAG_RIGHT_PX`) : `selMaxWidthPx` (dérivé de `setTrimeLimitMax(60000)`,
`MediaTrim.java:175`) est reclampé À CHAQUE déplacement de poignée, dans les DEUX directions — si
le nouveau bord dépasserait la largeur max, c'est CE bord (celui en cours de glissement) qui est
ramené en arrière, pas un blocage dur du geste. Côté iOS, `MediaTrimView.dragGesture` n'appliquait
qu'une borne MINIMALE (`minHandleSpacing`) — `load()` cadre bien la sélection par défaut à ≤60s si
la vidéo est plus longue, mais ce cadrage n'a lieu QU'UNE FOIS ; rien n'empêchait ensuite d'étendre
la sélection par glissement. Corrigé : nouveau clamp `maxWidthFraction = min(1, maxDurationSeconds
/ duration)` appliqué après le clamp minimal existant dans les deux branches, recadrant la poignée
en cours de déplacement (pas un blocage dur), fidèle à Android. Flux frères vérifiés : `grep
minHandleSpacing/dragGesture(isStart:` → un seul site dans tout le projet, `MediaTrimView.swift`.
Détail complet dans `PROGRESS_V4.md`, Lot P1-17. **Commit `0e7f651`, CI verte confirmée (run
`32683632141`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel requis : charger
une vidéo >60s, glisser chaque poignée pour tenter de dépasser 60s, confirmer le plafond continu).

**Lot P1-18 traité (V4-F-068)** — Wallet-Monetization, `WithdrawView` ne rafraîchissait jamais le
solde depuis le serveur avant un retrait. Vérifié dans `WithdrawActivity.java:221`
(`getRealAmount()` appelé INCONDITIONNELLEMENT dans `onCreate`, avant le câblage de `submitButton`)
+ `:415-448` : le champ `currentBalance` est écrasé par la réponse `getuserbyid`, puis réutilisé à
la fois pour la validation (`requestedAmount < currentBalance`) ET comme valeur envoyée telle
quelle au serveur dans le payload (`submitWithdrawalRequest(myId, currentBalance, ...)`). Côté iOS,
`WalletRepository.refreshBalance(userId:)` existait déjà (port fidèle) mais avait ZÉRO appelant ;
`WithdrawView` utilisait uniquement le paramètre statique `coinsAmount` (cache local), jamais
rafraîchi. Corrigé : nouveau `@State private var currentBalance: Double` initialisé depuis
`coinsAmount` (via `init` explicite), rafraîchi par un `.task` non bloquant, tous les usages internes
de `submit()` et l'affichage basculés vers `currentBalance`. Flux frères vérifiés PAR LECTURE
DIRECTE du code Android : `TransfertCoinsActivity.java`/`ConversionActivity.java` → 0 occurrence de
`getRealAmount`/`getuserbyid` dans les deux — Android lui-même ne rafraîchit le solde serveur QUE
pour Retrait (le cash-out réel, zone App Store 3.1.5) — `TransferCoinsView`/`ConversionView`
laissés inchangés, fidèles à leur source. Détail complet dans `PROGRESS_V4.md`, Lot P1-18.
**Commit `4e6c2f1`, CI verte confirmée (run `32684195949`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : modifier le solde serveur depuis un autre
appareil/session pendant que l'écran Retrait est ouvert, confirmer la mise à jour sans blocage
visuel du formulaire).

**Lot P1-19 traité (V4-F-073)** — Performance-Memory, `CDNAsyncImage` décodait chaque image CDN à
pleine résolution. Vérifié dans `ChargerImages.java` (entier) : CHAQUE chargeur Glide
sous-échantillonne dès la source (`.override(200)`/`.override(400)`/`.override(width,height)`) —
`glidLoadImageRequireAuth` (avec le même header `Referer` que `CDNAsyncImage`, donc l'équivalent
Android direct) prend `width`/`height` en PARAMÈTRES fournis par chaque appelant. Côté iOS,
`grep CDNAsyncImage(` recompté au moment de ce lot → **25 occurrences dans 16 fichiers** (l'audit
en citait 18 — écart dû à la croissance du projet entre la Phase A et ce lot, notamment
V4-F-007/V4-F-030 de ce même cycle) — les 25 occurrences ACTUELLES ont toutes été traitées.
Corrigé : nouveau paramètre `targetSize: CGSize?` sur les 2 signatures d'`init` de `CDNAsyncImage`,
décodage via `CGImageSourceCreateThumbnailAtIndex` (sous-échantillonne dès la source, jamais un
décodage complet suivi d'un redimensionnement) quand fourni, repli inchangé sur `UIImage(data:)`
sinon. Les 25 sites migrés avec leur taille réelle : avatars fixes (32 à 84pt selon l'écran),
bulles média chat (220pt), grilles Feed/Profile/Search (largeur de colonne dérivée du nombre de
colonnes réel : 2 pour `FeedGridCell` partagée Feed/Hashtag, 3 pour Profile/Search), 2 arrière-plans
plein écran (taille écran, pas de borne plus petite disponible). Flux frères vérifiés :
`AIChatView.swift` (seul autre `AsyncImage(` du projet) hors CDN Tiinver, non touché. Détail
complet dans `PROGRESS_V4.md`, Lot P1-19. **Commit `63039ff`, CI verte confirmée (run
`32685087464`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel IMPÉRATIF,
changement le plus risqué visuellement de ce cycle P1 — 17 fichiers, 25 sites : confirmer la
netteté sur chacun des 16 écrans touchés, profiler via Instruments/Memory Graph).

**Lot P1-20 traité (V4-F-021)** — Groups / Social, les motifs de signalement de `ReportView` ne
correspondaient pas à la vraie liste Android. Vérifié dans `strings.xml:516-525`
(`report_setting_array`, 8 items) + `Report.java:67`
(`getResources().getStringArray(R.array.report_setting_array)`, UNE SEULE liste, réutilisée pour
"user" ET "group"). Côté iOS, `ReportView.reasons` (6 items inventés, "Spam"/"Autre" absents
d'Android, 4 vrais motifs manquants) — alors que la bonne liste à 8 items existait déjà, mot pour
mot, dans `FeedView.swift` (`feedReportReasons`, `private`, utilisée par un flux de signalement
Android séparé mais lisant la MÊME ressource). Corrigé : `feedReportReasons` rendue interne et
RÉUTILISÉE dans `ReportView` (liste divergente supprimée), même motif de partage que
`UploadProgressDelegate` (V4-F-064) — aucun branchement `reportType`-spécifique nécessaire, la
ressource Android est unique pour les deux types. Détail complet dans `PROGRESS_V4.md`, Lot P1-20.
**Commit `4ff545b`, CI verte confirmée (run `32685665777`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : signaler un profil ET un groupe, confirmer les 8
motifs et le payload envoyé).

**Lot P1-21 traité (V4-F-027)** — Following, la liste abonnés/abonnements n'avait aucun bouton
suivre par ligne. Vérifié dans `Recherche/ui/Adapter.java:85-164` (`labelSuivre`, câblé) +
`Following/FollowList.java:24,43,60` (`import com.tiinver.Recherche.ui.Adapter` — l'écran
abonnés/abonnements RÉUTILISE littéralement le même adaptateur/bouton que Recherche, pas une
implémentation séparée). Côté iOS, `FollowListView` n'avait qu'un `NavigationLink` avatar+nom,
`SearchUserResult.isFollowed` jamais lu. Corrigé : `followButton`/`toggleFollow` ajoutés, en
RÉUTILISANT exactement le motif déjà présent et déjà corrigé dans `SearchView.swift` (V3-F-107 :
optimiste + rollback sur échec, suivre uniquement — pas de bascule "ne plus suivre" depuis cette
liste, fidèle à `ProfileRepository.follow`) — aucune nouvelle logique réseau. Flux frères
vérifiés : `grep FollowListView(` → 2 sites d'appel (abonnés/abonnements), une seule implémentation
corrigée une fois. Détail complet dans `PROGRESS_V4.md`, Lot P1-21. **Commit `a2725a9`, CI verte
confirmée (run `32686191058`)** — `BUILD_VALIDATED`, PAS `COMPLETE_PARITY_VALIDATED` (test réel
requis : suivre un utilisateur depuis la liste, confirmer le changement d'état et la persistance).

**Lot P1-22 traité (V4-F-019)** — Groups, action "Envoyer un message" absente de la gestion des
membres. Vérifié dans `SettingGroupMessageFragmant.java:162-172,417-447` +
`strings.xml:443-455` (3 tableaux, "Message" TOUJOURS en premier) + `Adapter.java:119-144`
(`sendMessage`, construit un `RosterModel` `type=CHAT`). Côté iOS, le dialogue admin n'avait que 2
actions (rôle/retrait), et un non-admin tapant un membre ne déclenchait STRICTEMENT rien. Corrigé :
"Message" ajouté en premier au dialogue admin ; nouveau dialogue à 1 action pour un non-admin ;
`chatTarget(for:)` (port fidèle de `Adapter.sendMessage`) + `.navigationDestination` vers
`ChatView`, réutilisant le motif déjà établi par `ProfileView.messageTarget`/
`NewMessageView.rosterTarget`. Détail complet dans `PROGRESS_V4.md`, Lot P1-22. **Commit
`bda7955`, CI verte confirmée (run `32686822701`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : Message en tête pour un admin, dialogue à 1 action
pour un non-admin, conversation 1:1 ouverte dans les deux cas).

**Lot P1-23 traité (V4-F-003, DERNIER de la liste P1 imposée) — DOCUMENTÉ `BLOQUÉ`, AUCUN CODE
MODIFIÉ.** Navigation-DeepLinks, aucun vrai Universal Link (`project.yml` ne déclare que les
schémas privés `myapp`/`tiinver`, `grep applinks:` = 0, aucun `.entitlements`). Finding CONFIRMÉ
réel — et redécouverte indépendante de `V3-F-078` (cycle V3, déjà `BLOCKED` à l'époque, signal de
fiabilité fort). La correction réelle nécessite, dans l'ordre : (1) entitlement Associated Domains
— SANS EFFET seul, et RISQUE RÉEL de casser la signature/CI si la capability n'est pas d'abord
activée côté portail développeur Apple ; (2) activer cette capability pour l'App ID — décision de
compte développeur, hors accès de cette session ; (3) héberger un `apple-app-site-association` sur
`tiinver.com` — décision infra serveur, hors dépôt iOS, hors accès de cette session. Faire (1) seul
risquerait de casser la CI verte des 22 lots précédents pour un gain fonctionnel nul tant que (2)
et (3) ne sont pas faits — conformément à la règle Phase B ("si hors périmètre atteignable, ne pas
modifier le code — documenter pourquoi"), **aucun code n'a été touché, aucun commit, aucune CI**.
Détail complet dans `PROGRESS_V4.md`, Lot P1-23.

**LISTE P1 IMPOSÉE ENTIÈREMENT TRAITÉE (2026-08-24)** — 23 lots dans l'ordre exact imposé : V4-F-020,
032, 033, 042, 038, 017, 046, 048, 049, 050, 001, 002, 029, 030, 056, 064, 059, 068, 073, 021, 027,
019, 003. 22 corrigés avec CI verte, 1 (V4-F-003) documenté `BLOQUÉ` hors dépôt. Aucune régression
introduite à aucun lot. Aucun finding marqué `COMPLETE_PARITY_VALIDATED` (aucun test réel sur
device disponible dans cet environnement, conformément à la règle du projet).

**Backlog P2 DÉMARRÉ (2026-08-24)** — instruction explicite de l'utilisateur : traiter le backlog
P2 (27 findings réels dans le document actuel, dans son ordre) par petits lots, méthodiquement
(Android source → comportement réel → code iOS → différence exacte → correction minimale → CI →
doc), puis enchaîner automatiquement sur P3 une fois P2 entièrement traité. Règles strictes
rappelées par l'utilisateur : ne pas corriger un finding juste parce qu'il est P2 ; vérifier que la
différence Android/iOS est réelle avant tout ; ne pas porter du code Android mort/inutilisé ;
marquer `BLOQUÉ` (raison précise) tout ce qui dépend backend/Apple Developer/serveur/test physique ;
ne jamais confondre `BUILD_VALIDATED` et `COMPLETE_PARITY_VALIDATED` ; pour toute vue, vérifier
toute la chaîne navigation→état→action→API→réponse→état Swift→rendu→interaction suivante (pas
seulement la présence du code — on a déjà trouvé plusieurs "code jamais appelé"/"état change mais
rien ne se rend") ; pour Animems, vérifier toute la chaîne UI→geste→état→transformation→
renderer→timeline→export avant de considérer un point terminé.

**Lot P2-1 traité (V4-F-004, V4-F-006, V4-F-009, V4-F-010, V4-F-011)** — V4-F-004
(Navigation-DeepLinks/Social, Share Extension absente) : `BLOQUÉ`, PAS un simple bug de code —
nécessite un target Xcode dédié ET un partage de session (Keychain access group) entre l'app et
l'extension, lui-même bloqué par la même dépendance Apple Developer Portal que V4-F-003 (risque
réel de casser la signature/CI sans activation préalable de la capability) — aucun code modifié.
V4-F-006 (route deep link `update`) : différé, sans objet — `appStoreId = nil` est un placeholder
déjà documenté, aucun App Store ID réel n'existe avant publication, la RECOMMANDATION de l'audit le
confirme elle-même — aucun code modifié. V4-F-009 (échec upload photo profil silencieux) : corrigé,
nouveau `photoUploadFailed` + icône d'erreur superposée, port fidèle de
`ProfileAdapter2.java:281-285`. V4-F-010 (grille profil sans état loading/vide) : corrigé,
`isLoadingPosts` (déjà publié, zéro lecteur) maintenant rendu + nouveau `postsLoadError`, port
fidèle du footer 3-états `ProfileAdapter2.FooterViewHolder` (le seul état "vide" ajouté est un
confort UX documenté comme NON issu d'Android, aucune vue "empty" trouvée côté Android après
recherche explicite). V4-F-011 (EditProfile ne charge jamais bio/lien) : corrigé, `loadCategory()`
étendue pour peupler `existingBiography`/`existingLink` utilisés comme PLACEHOLDER (pas pré-saisis
— fidèle à `EditProfile.onResume`'s `setHint`, PAS `setText`). Détail complet dans `PROGRESS_V4.md`,
Lot P2-1. **Commit `ac3ce38`, CI verte confirmée (run `32709964672`)** — `BUILD_VALIDATED` pour les
3 findings corrigés, PAS `COMPLETE_PARITY_VALIDATED`.

**Lot P2-2 traité (V4-F-012)** — Profile/Settings, écran résumé lecture-seule "Informations
personnelles" entièrement absent. Vérifié dans `setting/FragmentProfile.java` (247, entier, case 9)
+ chaîne de navigation tracée sur 3 fichiers (`SettingAccountFragment.java:97-105` →
`SettingsActivity.java:164-181` → `FragmentProfile.java:73-80`) : le SEUL chemin réel Android est
Réglages → Compte → Informations personnelles (lecture seule, 10 champs dont téléphone/email) →
Modifier ; `grep onFragmentInteraction(10)` = UN SEUL appelant dans tout Android, confirmant
qu'aucun accès direct au formulaire d'édition n'existe. Côté iOS, `SettingsView` menait DIRECTEMENT
au formulaire d'édition (2 déviations : aucun écran lecture seule nulle part, ET ce raccourci
racine lui-même sans équivalent Android). Corrigé : nouvelle `PersonalInformationSummaryView`
(port fidèle de `FragmentProfile`, 10 champs + bouton "Modifier") ; câblée dans `SettingAccountView`
("Compte", nouvelle entrée fidèle à `pref_personnel_info`) ; le raccourci racine préexistant
redirigé vers ce résumé au lieu du formulaire direct. Détail complet dans `PROGRESS_V4.md`, Lot
P2-2. **Commit `4cc0ba2`, CI verte confirmée (run `32711209239`)** — `BUILD_VALIDATED`, PAS
`COMPLETE_PARITY_VALIDATED` (test réel requis : confirmer l'affichage des 10 champs, notamment
téléphone/email, depuis les deux points d'entrée).

**PROCHAINE TÂCHE EXACTE** : Lot P2-2 terminé (vérifié/corrigé/documenté/commité/CI verte).
Enchaîner **automatiquement** sur le prochain P2 dans l'ordre du document : **V4-F-014** (Profile —
les posts d'un profil sont récupérés même si l'utilisateur visionné est bloqué :
`Profile/ProfileViewModel.swift:118-142`, aucune garde `isBlocked` avant `loadInitialPosts`/
`loadMorePosts` ; Android — `uploadPerfilPhoto/UserProfile.java:723-727`,
`if (!isBlocked) { ... }` — écart mineur de confidentialité/cohérence, requête réseau émise malgré
le blocage — recommandation : ajouter `guard !isBlocked else { return }` avant
`loadInitialPosts`/`loadMorePosts`), puis continuer AUTOMATIQUEMENT le backlog P2 restant dans
l'ordre du document (V4-F-022, V4-F-025, V4-F-028, V4-F-031, V4-F-035, V4-F-039, V4-F-041,
V4-F-043, V4-F-047, V4-F-051, V4-F-052, V4-F-057, V4-F-058, V4-F-060, V4-F-061, V4-F-066, V4-F-067,
V4-F-069, V4-F-070, V4-F-074 — 20 findings restants après V4-F-014), puis le backlog P3 (21
findings) une fois P2 entièrement clos, SANS attendre de nouvelle confirmation utilisateur pour
chaque lot (instruction explicite : continuer automatiquement). Repo Android source de vérité :
`C:\Users\helen\AndroidStudioProjects\tiinver\app\src\main\java\com\tiinver\`.

---

# ARCHIVE — entrées 2026-08-17 (PÉRIMÉES, voir avertissement ci-dessus, conservées pour GAP-020/021/022/023)

---

# CURRENT HANDOFF (2026-08-17, suite 4 — audit exhaustif Other User Profile + cause racine réelle vidéo)

**Contexte** : deux demandes successives de l'utilisateur. (1) "audit municieux, TOUT clic sur un
profil doit rediriger vers Other User Profile" — reprise de GAP-021 pour couvrir le reste de la
surface. (2) Retest explicite du Feed Grid/Fullscreen (photos/thumbnails/streaming vidéo), malgré le
correctif déjà appliqué (commit `8fd7493`) — a redemandé de vérifier en tenant compte du `Referer`.

**GAP-021 complété** : `FullScreenMedia.java` (3ᵉ visualiseur fullscreen Android, laissé en suspens
la fois précédente) lu en entier et TRANCHÉ — réellement reachable depuis `AdapterNoti` (vignette de
notification) ET `UniversalSearchAdapter` (résultat de recherche "publication"), réutilise
`CustomCardView`/`CustomVideoView` (déjà couverts par GAP-020). Chemin Search→post était déjà câblé
(`SearchView.detailPost`) ; chemin Notifications→post ne l'était pas — ajouté
(`NotificationRow.reconstructedPost`, reconstruit un `FeedActivity` minimal depuis les champs déjà
décodés de la notification). Vérifié et CONFIRMÉ (pas supposé) que bulles de chat et liste des
membres de groupe ne sont PAS des gaps : `grep "UserProfile.class"` sur tout `com.tiinver.messagerie`
= 0 résultat, Android ne le fait pas non plus à ces deux endroits. Créateurs/Abonnés-Abonnements
revérifiés en détail (liste complète, pas juste un item) — déjà corrects. Commit `df94461`, CI verte.

**CAUSE RACINE RÉELLE #12 (vidéo streaming peu fiable, retest utilisateur)** : `FeedActivity.
playbackURL` utilisait `cdn_content_url` en PRIORITÉ — l'INVERSE de la vraie priorité Android. Lu en
entier `Activity/service/VideoPlaybackCoordinator.java` (jamais lu jusqu'ici, malgré 2 passes
précédentes sur la vidéo) : l'URL PRINCIPALE passée à `playVideo(...)` est TOUJOURS `object_url` —
confirmé cohérent avec le côté photo (`CustomCardView.setData` charge aussi `object_url`
directement, jamais `cdn_content_url`). `cdn_content_url` ne sert QU'À construire une URL de REPLI
distincte (`stream.tiinver.com/{videoId}/play_720p.mp4`, `videoId`=premier segment de chemin de
`cdn_content_url`), essayée UNIQUEMENT si `object_url` échoue à jouer (`playVideoWithFallback`).
**Découverte notable** : `VideoPlayerManager.swift` avait DÉJÀ tout le mécanisme de repli-sur-échec
porté fidèlement depuis une session antérieure (`handlePlaybackFailure`, `currentFallbackURL`) —
mais `FeedDetailCell` ne lui passait jamais de `fallbackURL:`, le rendant mort en pratique. Ajouté
`FeedActivity.fallbackPlaybackURL` + branché dans `FeedView.swift`. Corrigé aussi `CDNAsyncImage`
(`cachePolicy = .reloadIgnoringLocalCacheData`) : un appareil testé AVANT le correctif Referer
(commit `8fd7493`) a pu mettre en cache une réponse 403 pour ces mêmes URLs — la clé de cache HTTP
standard ne tient pas compte des en-têtes de requête personnalisés, donc l'échec pouvait persister
même après le correctif sans que le code soit en cause. Commit `eded5f1`, CI verte.

**CI VALIDÉ (toutes vertes)** : `df94461`, `eded5f1`. **AUCUN de ces correctifs n'a encore été
confirmé par un test réel** — "CI VALIDATED, FUNCTIONALLY UNVERIFIED" jusqu'à preuve du contraire.

---

# CURRENT HANDOFF (2026-08-17, suite 3 — GAP-020/021/022 : ordre exact Fullscreen, Other User Profile partout, écran 1 création de groupe)

**Contexte** : l'utilisateur a fourni une capture Android réelle du fullscreen Feed (bouton
"S'abonner" visible) suite au tour précédent, redemandant explicitement de documenter dans
`MIGRATION_AUDIT.md` (pas seulement `CLAUDE_CONTINUATION.md`) AVANT toute correction — puis a
fourni 3 gaps précis confirmés par test réel : Other User Profile inaccessible depuis la plupart des
écrans, chaîne de création de groupe incomplète (écran 1 manquant), Fullscreen déjà en bonne voie.

**GAP-020 (MIGRATION_AUDIT.md)** : l'ordre vertical du bloc d'infos du fullscreen Feed
(`FeedDetailCell`) était inversé par rapport à `reaction_pub_but.xml` (lu en entier) — Android :
légende D'ABORD, puis avatar+pseudo+date, puis "S'abonner" ; iOS avait l'inverse. Corrigé (ordre
exact) + ajout de la date (`TimeUtils.getDate`, "yyyy-MM-dd HH:mm:ss"→"dd-MM-yy", reproduit à
l'identique). **Découverte en cours de route** : `Activity/ui/FullscreenActivity.java` est un
template Android Studio mort (écouteurs vides, jamais atteint par aucune navigation réelle) — le
VRAI fullscreen est `FeedFragment.java`→`ViewPagerAdapter.java`→`CustomCardView.java`, tous lus en
entier. Commit `3bf7ae3`, CI verte.

**GAP-021 (MIGRATION_AUDIT.md) — Other User Profile** : `grep -rl "UserProfile.class"` sur tout
Android = 16 fichiers. `ProfileView.swift` elle-même était déjà complète (menu "..." correct :
Signaler/Bloquer-Débloquer, exactement 2 items comme `menu_user_profile`), mais seulement 4/12
points d'entrée reachable étaient câblés côté iOS. Ajoutés : `NotificationsListView` (aucune
navigation avant), `SuggestionsCarouselView` (avatar tapable maintenant — **piège évité** : cette
vue vit dans l'onglet Accueil, PAS enveloppé dans un `NavigationStack`, donc `fullScreenCover`+état
local plutôt que `NavigationLink`, qui y serait silencieusement inopérant), `CommentsView` (avatar+
pseudo, commentaires ET réponses), `ChatView` (nouveau bouton toolbar pour un chat 1:1, MÊME motif
que le bouton groupe existant — l'écran de réglages complet `SettingPrivateMessageFragmant` reste un
gap connu et borné, voir GAP-011, pas reconstruit ici). **PAS traité** : un 3ᵉ visualiseur fullscreen
distinct (`NotiLikecmt/FullScreenMedia.java`/`CustomVideoView.java`, accessible depuis Notifications
ET Search) — accessibilité réelle non confirmée par preuve d'instanciation active, à revérifier si
rapporté. Commit `acbddc7`.

**GAP-022 (MIGRATION_AUDIT.md) — écran 1 de création de groupe manquant** : `Contact.java` (Activity
hôte, lu en entier) atterrit TOUJOURS sur `ContactsFragment` en premier (écran 1 : liste générale,
tap = ouvrir un chat individuel DIRECTEMENT, `Adapter.ContactHolder`), quel que soit le point
d'entrée (`Roster.java` FAB "créer groupe" ET `MonetizationActivity.java` "inviter des contacts" —
DEUX entrées distinctes, vérifiées séparément). L'en-tête cliquable dédié ("Créer un groupe") bascule
SEULEMENT ALORS vers `ChooseFragment` (écran 2, sélection multiple). `ContactPickerView.swift`
sautait directement à l'écran 2 depuis TOUT point d'entrée — réécrite avec deux modes (`.browse`
par défaut / `.selectForGroup`). Commit `acbddc7`.

**Piège rencontré (déjà documenté dans le commit correctif)** : `navigationDestination(item:)`
nécessite iOS 17, ce projet cible iOS 16 — cassait la compilation (`acbddc7`). Corrigé avec le même
contournement `isPresented:`+`Binding(get:set:)` déjà utilisé partout ailleurs dans ce code base.
Commit `e860d32`, CI verte.

**CI VALIDÉ (toutes vertes)** : `3bf7ae3`, `e860d32` (inclut `acbddc7`, corrigé au commit suivant).
**AUCUN de ces correctifs n'a encore été confirmé par un test réel** — statut correct : "CI
VALIDATED, FUNCTIONALLY UNVERIFIED".

**Reste à faire, explicitement en attente de preuve réelle de l'utilisateur avant tout code
supplémentaire (règle "ne pas tâtonner")** : Animems — audit complet déjà fait (session précédente),
aucun bug supplémentaire identifiable sans capture/vidéo réelle du problème rapporté (objets qui ne
se déplacent pas facilement) ; en attente.

---

# CURRENT HANDOFF (2026-08-17, suite 2 — audit de complétude P0 : Feed Grid/Fullscreen, Profile tap, création de groupe)

**Contexte** : l'utilisateur a REJETÉ la clôture précédente ("les problèmes persistants montrent
clairement que la migration est encore loin de la parité fonctionnelle"), a explicitement redemandé
un audit de complétude par fonctionnalité (pas seulement une correction de bugs isolés), et a listé
5 zones P0 : Feed Grid (images/thumbnails absents malgré vidéo jouable), Fullscreen sans vraie
parité Android, clic Profile Grid cassé, Animems non fluide, création de groupe impossible. Règle de
travail : ne jamais déclarer une fonctionnalité "COMPLETE" sur CI verte seule — distinction stricte
BUILD VALIDATED / FUNCTIONALLY VALIDATED tant qu'aucun test réel ne l'a confirmé.

**CAUSE RACINE #8 (Feed Grid + Fullscreen : photos/thumbnails vidéo absents malgré lecture vidéo
fonctionnelle)** — port fidèle de `view/BubbleStatusPhoto.java` (`setMediaObject`, lu en entier) :
`FeedActivity.thumbnailURL` ne lisait QUE `cdn_thumbnail_url`, un champ QUE le backend renseigne
pour certaines vidéos, JAMAIS pour une photo. Android : PHOTO → toujours `object_url` ; VIDÉO →
`cdn_thumbnail_url` SI `cdn_content_id` présent et ≠ `"NULL"` (chaîne littérale), sinon repli sur
`object_url`. Comme la lecture vidéo (`playbackURL`) est un chemin de code totalement séparé, elle
continuait de fonctionner pendant que Grid ET le fullscreen restaient noirs pour presque tout le
contenu (essentiellement des photos). Corrigé dans `FeedActivity.swift` et sa réplique
`SearchModels.SearchPostResult`. Commit `8fd7493`, CI verte.

**CAUSE RACINE #9 (Fullscreen sans parité Android réelle)** — lu `Activity/ui/FeedFragment.java` →
`ViewPagerAdapter.java` → `view/CustomCardView.java` en entier (le VRAI écran fullscreen, PAS
`FullscreenActivity.java` qui s'est avéré être un template Android Studio mort/inutilisé — écouteurs
`OnClickListener` vides, jamais atteint via `onArticleSelected`). Confirmé : like/comment/share/more
étaient DÉJÀ correctement câblés côté iOS (`FeedDetailCell.actionRail`) — probablement juste rendus
peu visibles par le bug ci-dessus. RÉELLEMENT manquants : avatar + tap sur l'identité → profil de
l'AUTEUR du post (`CustomCardView.nameContainer`, jamais reproduit), et le bouton "Suivre"
(`followBtn`, piloté par `activityLib.java:43`'s `isFollowed`, jamais décodé côté iOS). Les trois
ajoutés (`FeedActivity.isFollowed`, `FeedViewModel.followFromDetail`, UI dans `FeedDetailCell`/
navigation dans `FeedDetailPagerView` vers `ProfileView(isCurrentUser:false)`). Commit `a796446`, CI
verte.

**CAUSE RACINE #10 (clic Profile Grid ne fait rien)** — confirmée par lecture directe du code, pas
une hypothèse : `ProfileView`'s `ForEach(viewModel.posts) { post in postCell(post) }` n'avait
**AUCUN** geste attaché, ni navigation, ni état — contrairement à `FeedGridCell` qui ouvrait déjà
`FeedDetailPagerView`. Corrigé en réutilisant CE MÊME pager (déjà remis à parité ci-dessus) plutôt
que d'en dupliquer un second, cohérent avec la fusion déjà assumée de ce fichier
(`UserProfile`+`AddPerfilFoto`). Commit `8fd4356`, CI verte (transitivement, via le build de
`f4e0dd2` qui inclut ce commit).

**CAUSE RACINE #11 (création de groupe toujours FUNCTIONALLY FAILED)** — DEUX bugs indépendants qui
se cumulent dans `ContactsRepository.connectedUsers` (`GET connectedusers/{userId}`, alimente
`ContactPickerView`, ÉTAPE 1 de la création de groupe) :
1. `GroupMemberCandidate` n'avait pas de décodeur tolérant : si le backend envoie `userId` en NOMBRE
   JSON pour ne serait-ce qu'UN SEUL contact (Gson tolère cette divergence côté Android via
   `nextString()`, `Codable` Swift STRICT ne la tolère pas), le décodage du TABLEAU ENTIER échoue,
   avalé silencieusement par le `try?` du ViewModel → liste "Aucun contact" → aucune sélection
   possible → chaîne de création bloquée dès la toute première étape. Ajouté `GroupMemberCandidate.
   init(from:)` + nouveau `decodeLenientString(forKey:)` (`LenientDecoding.swift`).
2. `connectedUsers()` supposait `"data"` toujours ré-encodé en chaîne (`stringEncodedJSON`), en
   analogie avec le code Android (`getString`+Gson) — LA MÊME analogie s'est révélée FAUSSE sur
   `weekly_rank` (cause racine #4 du handoff précédent). Sans JSON réel de CET endpoint précis,
   tolère maintenant les deux formes. Même traitement appliqué par prudence à `GroupRepository.
   createGroup`/`fetchGroup`/`fetchMembers` (mêmes symptômes possibles plus loin dans la chaîne),
   via un nouveau point d'entrée générique `JSONValue.looselyEncodedJSON(_:)` — à utiliser
   désormais PARTOUT où cette ambiguïté n'a pas été tranchée par un JSON réel.
Commits `f4e0dd2` + `cccca41`, CI verte.

**Animems (P0-E) — investigué, PAS de correctif appliqué, conformément à la règle "ne pas tâtonner"
de l'utilisateur** : `AnimemesGestureController.swift`/`AnimemesEditorState.swift` relus en entier.
Code déjà mature (hit-test par inversion de matrice, translation/rotation/échelle correctement
composées en "post-", diagnostic `gestureDiagnostics` déjà affiché à l'écran). Aucun bug
supplémentaire identifiable sans capture/vidéo réelle du problème actuel — en attente des captures
Appetize promises par l'utilisateur plutôt que d'inventer un correctif spéculatif.

**Résiduel non traité, risque bas** : `GroupMember.userId: Int` (liste des membres d'un groupe
EXISTANT, `GroupDetailView`) a le même profil de risque théorique que `GroupMemberCandidate.userId`
avant correction, mais hors du chemin CRÉATION explicitement P0 — pas touché cette passe, à garder
en tête si un bug similaire est rapporté sur la gestion d'un groupe existant.

**CI VALIDÉ (toutes vertes)** : `8fd7493`, `a796446`, `8fd4356` (via le build de `f4e0dd2`),
`f4e0dd2`, `cccca41`. **AUCUN de ces correctifs n'a encore été confirmé par un test réel/capture
Appetize** — statut correct : "CI VALIDATED, FUNCTIONALLY UNVERIFIED" jusqu'à preuve du contraire.

---

# CURRENT HANDOFF (2026-08-17, suite — CDN Referer, Créateurs, Monétisation, solde Wallet, en-tête Home)

**Contexte** : après les 3 causes racines de session vide (voir handoff précédent), l'utilisateur a
confirmé que du contenu réel se charge enfin (Feed/Profile avec vrais compteurs), puis a fourni une
liste de bugs restants + le JSON réel de `weekly_rank` (Créateurs). Tous corrigés et validés CI
verte ci-dessous.

**CAUSE RACINE #4 (Créateurs, liste des trophées vide)** : `weekly_rank`'s champ `"data"` est un
TABLEAU JSON DIRECT (confirmé par le JSON réel fourni par l'utilisateur), PAS une chaîne
ré-encodée comme supposé précédemment par analogie avec d'autres endpoints — `TrophyRepository.
weeklyRank()` décodait `data` avec `stringEncodedJSON` qui échouait TOUJOURS sur un tableau natif.
Décodage direct maintenant. **Leçon retenue** : ne plus jamais supposer le format d'un champ
"data"/"users" par analogie avec un autre endpoint sans preuve — voir `SuggestionsRepository`
ci-dessous qui tolère les deux formes faute de JSON réel disponible pour CET endpoint précis.

**CAUSE RACINE #5 (images ne s'affichent pas, vidéo ne se lance jamais)** : le CDN Tiinver exige un
en-tête HTTP `Referer` (`https://tiinver.com` pour les images, `https://stream.tiinver.com` +
`User-Agent: TiinverPlayer/1.0` pour le streaming vidéo — valeurs EXACTES reprises de
`ChargerImages.java`/`ExoPlayerManager.java`) et rejette silencieusement toute requête sans cet
en-tête. `AsyncImage` de SwiftUI n'a AUCUN point d'extension pour ajouter un en-tête personnalisé.
Corrigé par `CDNAsyncImage.swift` (remplaçant drop-in, tous les ~20 sites d'appel `AsyncImage(`
migrés) + `VideoPlayerManager.makeAsset(url:)` (`AVURLAsset` avec en-têtes HTTP).
**Piège rencontré en cours de route** : `AVURLAssetHTTPHeaderFieldsKey` (la constante "officielle")
n'est PAS exposée au compilateur Swift (clé interne Objective-C jamais déclarée côté Swift dans le
SDK AVFoundation — confirmé par recherche externe) → échec de compilation CI (commit `f2fef82`).
Corrigé (commit `7094756`) en passant la même valeur sous forme de `String` littérale brute.

**CAUSE RACINE #6 (solde de pièces Wallet ne s'affiche jamais)** : Android n'a AUCUN endpoint dédié
"solde du portefeuille" et ne persiste PAS `coinsAmount` à la connexion — le cache local
(`Settings`/`COINS_AMOUNT`, ici `UserSession.coinsAmount`) n'est mis à jour QUE lors du rechargement
du PROPRE profil (`AddPerfilFoto.java:636`). `WalletViewModel` lisait déjà ce cache correctement ;
c'est l'écriture qui manquait, jamais portée. Corrigée dans `ProfileViewModel.loadProfile()`.

**CAUSE RACINE #7 (bouton "monétisation" du Profil mène au même écran que "portefeuille")** :
conclusion antérieure FAUSSE ("aucun écran Android dédié identifié"), jamais revérifiée après la
première passe — `wallet/MonetizationActivity.java` (117 lignes) EST bien un écran séparé (hub
"booster ses revenus" : publier/inviter/parrainage/récompense Animems), porté dans
`MonetizationView.swift` (nouveau), routage `ProfileView` corrigé.

**Structure de l'en-tête Home (demande explicite de l'utilisateur)** : une décision antérieure de
CETTE session (avant compaction) avait conclu que le carrousel de suggestions Android était du code
mort (`// sugestionRecycle.setAdapter(mAdapterSuggest)` commenté dans `MainFragment.java`) et avait
donc délibérément choisi de NE PAS le reproduire. **Cette conclusion était fausse** : cette ligne
commentée est un résidu d'un champ DUPLIQUÉ sans rapport ; le VRAI adapter est câblé dans
`ActivityAdapter.HeaderViewHolder` (`sugestionRecycle.setAdapter(mAdapterSuggest)`, ligne 327,
DANS le fichier adapter, pas le fragment) — trouvé en relisant `ActivityAdapter.java` en entier
suite à la demande explicite et réitérée de l'utilisateur. Porté fidèlement (`feed_header_layout.
xml` : carrousel de comptes suggérés `GET suggestions/{userId}` + bannière AdMob (même ID que
Wallet) + bannière promo "Gagnez des pièces gratuites" → Referral), toujours visible au-dessus du
fil (même vide), fidèle à l'item `TYPE_HEADER` de position 0 côté Android.

**CI VALIDÉ** :
- commit `7094756` (correctif compilation `AVURLAssetHTTPHeaderFieldsKey`) — run `31987473027`, **SUCCESS**.
- commit `1715e7c` (écran Monétisation + solde Wallet) — inclus dans le run suivant.
- commit `9ed52b2` (en-tête Home : suggestions/AdMob/bannière promo) — run `31988589990`, **SUCCESS**.

**Pas encore vérifié par un test réel** (build vert ≠ fonctionnellement correct, ne pas déclarer
"terminé" avant capture d'écran/rapport réel) :
- Le carrousel de suggestions (`SuggestionsRepository`) tolère DEUX formats possibles pour le champ
  `"users"` faute de JSON réel de CET endpoint précis — à confirmer/simplifier dès qu'un JSON réel
  sera fourni (même piège que la leçon `weekly_rank` ci-dessus, anticipé cette fois).
- Bouton fullscreen Feed "like/comment/share/more" signalé manquant par l'utilisateur — code
  (`FeedDetailCell.actionRail`) relu et semble correctement câblé, PAS de correctif appliqué faute
  de preuve (pas de capture d'écran de cet écran précis) — à réexaminer avec une capture fraîche
  maintenant que le CDN fonctionne (l'écran était peut-être juste rendu illisible par des vignettes
  grises avant ce correctif).

---

# CURRENT HANDOFF (2026-08-17, TROISIÈME cause racine réelle trouvée — Keychain silencieux)

**Après le correctif GET-sans-corps (voir handoff précédent), un nouveau test réel a montré que la
requête atteint ENFIN le serveur** (fini le rejet client Alamofire) — **mais le serveur répond
`HTTP 400`** sur `feedtimeline`/`getuserbyid`. Le bandeau de diagnostic a montré la clé : `userId`
correct des deux côtés (`197`), mais **`apiKey=nil`** malgré un login décodé avec un `apiKey`
valide dans le JSON.

**CAUSE RACINE #3, CONFIRMÉE PAR L'ARCHITECTURE CI, PAS UNE HYPOTHÈSE** : `codemagic.yaml`'s
workflow `visual-smoke-test` (**celui qui produit RÉELLEMENT le `.zip` testé sur Appetize**)
compile avec `CODE_SIGNING_ALLOWED=NO` — nécessaire pour produire un binaire testable sans compte
Apple Developer payant. Sans signature de code, l'OS ne peut pas déterminer de façon fiable le
groupe d'accès Keychain par défaut de l'app — `SecItemAdd` (écriture Keychain de l'apiKey) peut
échouer silencieusement, et `KeychainStore.swift` **ne vérifiait jamais son code de retour
`OSStatus`** avant ce correctif. `myId` (UserDefaults) persistait correctement ; `apiKey`
(Keychain) non — exactement le écart observé. Sans en-tête `Authorization` (jamais ajouté quand
`apiKey` est nil, voir `APIClient.headers()`), le serveur rejette avec 400.

**Corrigé** : `KeychainStore` écrit désormais AUSSI dans UserDefaults en repli (lu si le Keychain
revient vide) — pas une régression de sécurité, Android stocke déjà cette même valeur dans
`SharedPreferences` ordinaire, pas l'Android Keystore. Le statut `OSStatus` réel de la dernière
écriture Keychain est maintenant affiché dans le bandeau permanent pour confirmer/infirmer.

**CI VALIDÉ** : run `31983140075`, commit `11e8935`, **SUCCESS**.

**Récapitulatif des 3 causes racines réelles trouvées et corrigées cette session** (toutes
confirmées par preuve directe — JSON réel, message d'erreur exact, ou architecture CI — jamais
par supposition) :
1. `error` booléen JSON sur `login` (pas la convention chaîne) → session vide malgré connexion
   propre.
2. Alamofire rejette les GET avec corps HTTP → aucune requête GET n'atteignait jamais le réseau.
3. Écriture Keychain silencieusement en échec sur build non signé → `apiKey` jamais persisté,
   401/400 sur les endpoints authentifiés.

**Reste à confirmer par le prochain test réel** — devrait cette fois montrer Feed/Profile
fonctionnels, ou révéler un éventuel 4ᵉ problème.

---

# HANDOFF PRÉCÉDENT (2026-08-17, DEUXIÈME cause racine réelle trouvée — erreur Alamofire exacte)

**Après le correctif `errorFieldNormalized` (voir handoff précédent), un nouveau test réel a montré
que la session fonctionne ENFIN** (`userId(objet reçu)=197 · userId(session persistée)=197`,
confirmé dans le bandeau permanent) — **mais Feed et Profile échouent encore**, avec cette fois une
VRAIE erreur de transport visible dans les panneaux de diagnostic :
```
error=transport(Alamofire.AFError.urlRequestValidationFailed(reason:
Alamofire.AFError.URLRequestValidationFailureReason.bodyDataInGETRequest(2 bytes)))
```

**CAUSE RACINE #2, CONFIRMÉE PAR LE MESSAGE D'ERREUR EXACT, PAS UNE HYPOTHÈSE** : Alamofire
(depuis la 5.7) rejette désormais TOUTE requête GET porteuse d'un corps HTTP, même vide (`{}`) —
`APIClient.swift` envoyait volontairement un corps JSON même sur GET, choix de fidélité avec
Android (`Volley.JsonObjectRequest` envoie toujours un corps) documenté comme "non négociable"
dans `TIINVER_IOS_PORT_ANALYSIS.md §6.3`. Cette fidélité est devenue **techniquement impossible**
avec la version moderne d'Alamofire utilisée par ce projet — la requête est rejetée AVANT même
d'atteindre le réseau. **Vérifié par grep sur tout le projet : AUCUN appel `.get(...)` n'envoie
jamais de vrais `params`** (chaque endpoint encode ses paramètres dans le CHEMIN de l'URL) — le
corps vide n'avait donc AUCUNE utilité fonctionnelle. Corrigé : les requêtes GET n'envoient plus
de corps du tout (`URLEncoding.default` au lieu de `JSONEncoding.default` pour `method == .get`).

**Portée probable** : ce bug affecte TOUTES les requêtes GET de l'app, pas seulement Feed/Profile
— très probablement la VRAIE raison pour laquelle Home/Feed/Profile/Créateurs/Notifications/
Recherche/Wallet/Commentaires n'ont JAMAIS fonctionné depuis le tout début du portage, pas
seulement "depuis hier".

**CI VALIDÉ** : run `31981817316`, commit `c63655a`, **SUCCESS**.

**État à ce stade** : 2 causes racines réelles trouvées et corrigées à partir de preuves directes
(JSON réel + message d'erreur exact), pas de suppositions. Reste à confirmer par le prochain test
réel — devrait cette fois révéler si Feed/Profile fonctionnent enfin, ou s'il reste un 3ᵉ problème.

---

# HANDOFF PRÉCÉDENT (2026-08-17, CAUSE RACINE RÉELLE CONFIRMÉE — JSON brut fourni par l'utilisateur)

**L'utilisateur a fourni le JSON RÉEL de `login` et `feedtimeline`** (pas une capture d'écran —
le payload texte complet), après une frustration légitime sur la lenteur du diagnostic. Ce JSON a
permis de trancher DÉFINITIVEMENT, sans plus deviner :

1. **`"error": false` sur `login` est un BOOLÉEN JSON natif**, alors que la convention documentée
   partout ailleurs dans ce backend (et supposée universelle jusqu'ici, y compris dans
   `TIINVER_IOS_PORT_ANALYSIS.md §6.3`) est la CHAÎNE `"false"`. `AuthEndpoints.parseLoginResponse`
   comparait `error == "false"` (texte) contre cette valeur, qui ne correspondait JAMAIS — tombait
   dans le DERNIER repli du code (`User()` vide, `etat` recopié depuis `message` = "Login
   Successful"), que `LoginView.handle` reconnaît quand même comme un succès. D'où : navigation
   propre vers Accueil, session ENTIÈREMENT vide, exactement le symptôme signalé depuis hier.
   **Corrigé** : `JSONValue.errorFieldNormalized` (nouveau) tolère chaîne OU booléen, utilisé
   partout où "error" est vérifié dans `AuthEndpoints.swift`/`VerificationEndpoints.swift`/
   `JSONValue.isBackendSuccess`.
2. **6 divergences de type supplémentaires trouvées dans le MÊME JSON**, qui auraient maintenu le
   bug même après le correctif ci-dessus : `User.emailVerified`/`certified`/`followers`/`following`
   envoyés en NOMBRE (pas en texte) ; `FeedActivity.actor` envoyé en NOMBRE ; `FeedActivity.isLiked`
   envoyé en BOOLÉEN JSON natif sur **CHAQUE** item du flux échantillon fourni — celui-ci à lui seul
   aurait vidé tout le Feed même une fois la session correctement établie. Tous corrigés avec
   `LenientDecoding.swift` (nouveau helper `decodeLenientBoolAsStringIfPresent` pour le cas
   `isLiked`).

**CI VALIDÉ** : run `31980597737`, commit `6513950`, **SUCCESS**.

**Confiance** : MAXIMALE — pas une hypothèse déduite du comportement observé, mais une correction
directement dérivée du JSON réel envoyé par le serveur, comparé champ par champ au modèle Swift.
**Reste à confirmer par un test réel** (l'utilisateur a dit vouloir économiser Appetize — attendre
son prochain test plutôt que de le lui redemander).

---

# HANDOFF PRÉCÉDENT (2026-08-17, bandeau userId permanent ajouté sur demande explicite)

**Demande directe de l'utilisateur** : "il faut afficher le userId pourqu'on puisse de savoir si
réellement la session fonctionne" — au lieu d'un panneau de diagnostic caché dans un état d'erreur
d'un écran précis, un bandeau ROUGE/VERT **visible en permanence sur les 3 onglets réels**
(Accueil/Chat/Créateurs) a été ajouté à `HomeShellView.swift` (`.safeAreaInset(edge: .top)`,
nouvelle propriété `userIdDebugBanner`). Affiche trois valeurs côte à côte en une ligne :
`userId(objet reçu)` (ce que `User` contenait à la construction de `HomeShellView`, donc juste
après connexion/restauration) vs `userId(session persistée)` (`UserSession.shared.myId`, ce que
Feed/Profile lisent réellement) vs `apiKey` (présence Keychain) — permet de voir EN UN COUP D'ŒIL,
sans naviguer nulle part, si le problème est au décodage, à la persistance, ou spécifique au
Keychain (si `myId` est présent mais pas `apiKey`, ou l'inverse).

**CI VALIDÉ** : run `31977901638`, commit `b09b2e7`, **SUCCESS**.

**À retirer une fois la cause de la session vide confirmée et corrigée** — c'est un ajout
temporaire de diagnostic, documenté comme tel dans le code.

---

# HANDOFF PRÉCÉDENT (2026-08-16, mise à jour APRÈS retour UX Profile + nouveau test partiel)

**Nouveau test réel reçu** (horodatage 00:41/00:42, DIFFÉRENT du lot précédent 19:52/19:53 — un
vrai nouveau test, pas les mêmes captures) : mêmes symptômes `myId=nil`/`authenticated=false` sur
Feed/Profile. **Point important** : le panneau `LOGIN RAW USER JSON` (ajouté commit `26b278d`
justement pour ce cas) N'EST PAS apparu dans ce lot — ce qui signifie que le scénario précis anticipé
("décodage réussi mais id manquant") ne s'est PAS produit cette fois, donc soit (a) aucune connexion
n'a été retentée pendant CE test précis, soit (b) `login()` a levé une vraie erreur visible (page de
connexion non capturée dans ce lot). **Pas encore élucidé — nécessite la capture de l'ÉCRAN DE
CONNEXION lui-même au prochain test pour trancher.**

**Retour UX direct de l'utilisateur, traité immédiatement** : l'écran Profile masquait TOUT son
chrome (avatar/abonnés/boutons) dès qu'il y avait une erreur — corrigé (commit `2edcd65`, CI
SUCCESS run `31977346121`) : le chrome (avatar placeholder, "0" abonnés, boutons "MODIFIER LE
PROFIL"/portefeuille/monétisation) s'affiche désormais TOUJOURS, l'erreur/diagnostic apparaît en
plus, pas à la place. Créateurs (`CreatorOfWeekView`) laissé tel quel — motif différent, déjà
comparé à une capture Android réelle, écran de liste complet pas une mise en page fixe comme Profile.

---

# HANDOFF PRÉCÉDENT (2026-08-16, mise à jour APRÈS balayage complet de la classe de bug decode)

**Pendant l'attente d'un nouveau test réel** (l'utilisateur a explicitement demandé de continuer
sans s'arrêter), balayage systématique de TOUT le code pour la MÊME classe de bug que Feed/Profile
(`LenientDecoding.swift`) : champ `Int`/`Bool`/`Double` non-optionnel OU avec valeur par défaut
Swift (`= 0`/`= false`) décodé strictement, alors que **la synthèse `Decodable` de Swift n'utilise
JAMAIS la valeur par défaut d'une propriété comme repli au décodage** — piège Swift documenté,
distinct de l'initialiseur memberwise (qui LUI en bénéficie). Corrigé dans, par ordre d'impact
probable :
- `SearchModels.swift` (`SearchUserResult.id`, `SearchPostResult.id`/`.actor`) — un seul résultat
  mal typé vidait TOUT le tableau `users`/`posts` (`SearchResults.init` catch tout le tableau).
- `CommentModels.swift` (`Comment.id`) — même risque pour un fil de commentaires entier.
- `Models/MessageLib.swift` — décodé via `try? JSONDecoder().decode([MessageLib])` dans
  `ChatRepository` : un seul message mal typé effaçait TOUT l'historique d'une conversation.
- `Creators/CreatorModel.swift` (`rankPosition`/`score`/`followers`/`isStar`, tous `= 0`/`= false`).
- `Discover/CertificationModels.swift` (`CertificationStatus`, un seul objet, pas un tableau —
  échec total du statut de certification).
- `Animems/TemplateRemoteModel.swift` — dégradait déjà proprement (`try?`+défaut manuel), mais
  substituait silencieusement une FAUSSE valeur par défaut au lieu de la vraie ; corrigé pour
  décoder correctement au lieu de juste ne pas planter.
- `Wallet/WalletModels.swift` (`WalletTransaction`), `Models/TurnCredentials.swift` (crédentials
  TURN WebRTC) — même correctif, moindre priorité (pas confirmés cassés, fermés par prudence).
- Nouveau helper `decodeLenientStringIfPresent` (`LenientDecoding.swift`) pour le cas INVERSE : un
  champ typé `String` mais envoyé comme NOMBRE JSON (`CreatorModel.userId`, `MessageLib.userId`).

**NON corrigé, signalé, PAS une supposition non fondée** : `Models/WebrtcData.swift`/
`Shareboard/PBSWireModels.swift` — signalisation WebRTC transmise directement entre les stacks
natifs pairs, PAS via le backend PHP flaky à l'origine de cette classe de bug — risque
structurellement moindre, pas corrigé sans preuve concrète d'un problème réel.

**CI VALIDÉ** : run `31975209032` (commit `92fb087`, SUCCESS) puis run `31975582942` (commit
`61fb7d9`, **SUCCESS**).

---

# HANDOFF PRÉCÉDENT (2026-08-16, après captures Android de référence — P0-4)

**Nouvelles captures Android RÉELLES reçues** (Créateurs/Animems/Home/Profile) pour la parité
visuelle P0-4. Comparaison systématique menée contre le code Android source (layouts XML +
adapters), pas devinée depuis les images :
- **Animems** : toolbar du haut, zoom controls, toolbar droite (9 icônes, même ordre), "Capture
  automatique"/ratio/"Ajouter un son" — TOUS déjà fidèles au code actuel, confirmés par relecture.
  "Compose"/"Load compose" (2 boutons Android vs 1 bouton fusionné désactivé côté iOS) — vérifié
  que `RecomposeGalleryView.java` (333 lignes, la classe derrière "Load compose") n'est JAMAIS
  instanciée dans `MemesFragment.java` (grep confirmé, zéro appelant) — fonctionnellement mort des
  deux côtés, divergence purement cosmétique, laissée telle quelle.
- **Home** : le carrousel "créateurs à suivre" et la bannière "Gagnez des pièces gratuites" ne sont
  PAS reproduits côté iOS — **vérifié que c'est CORRECT** : `MainFragment.java:787`
  (`// sugestionRecycle.setAdapter(mAdapterSuggest);`) est en commentaire, zéro adapter actif dans
  le code Android actuel malgré ce qui apparaît sur la capture (probablement injecté par un SDK
  publicitaire tiers, pas une fonctionnalité app native reproductible fidèlement). Décision de la
  session précédente (ne pas reproduire) RECONFIRMÉE, pas juste répétée.
- **Créateurs** : badge "STAR" corrigé en "👑 STAR" (`fragment_creator.xml:95`, emoji couronne
  vérifié dans le layout XML, pas deviné). "Score : "/"Score: " (avec/sans espace) déjà fidèles.
- **Profile** : `roundIconButton` (portefeuille/monétisation) a déjà ses labels texte — déjà fidèle.

**CI VALIDÉ** : run `31968325770`, commit `ca96c7c`, **SUCCESS** (fix STAR badge).

**P0-4 largement traité** pour les 4 écrans fournis — reste en attente d'éventuelles captures
Android supplémentaires que l'utilisateur a annoncé vouloir envoyer.

---

# HANDOFF PRÉCÉDENT (2026-08-16, après confirmation "login email, pas Google" — le diagnostic
# login ci-dessous reste actif et en attente d'un nouveau test réel)

**L'utilisateur a confirmé** (répondant à 3 questions ciblées, PAS un nouveau test Appetize) :
compte **existant**, **login email** (pas Google/inscription), **transition immédiate et propre**
vers Home après connexion. Ceci **élimine** la cause `registerWithProvider` ci-dessous comme
explication de CES captures précises (le bug reste réel et corrigé, juste pas responsable ici).

**Nouvelle conclusion, la SEULE compatible avec "transition propre + session vide"** :
`AuthEndpoints.parseLoginResponse` décode le "user" SANS lever d'exception (sinon pas de
transition propre) mais `user.id` reste `nil` — possible UNIQUEMENT si la clé JSON réelle de
l'identifiant sur l'endpoint `login` n'est ni `"id"` ni `"userId"` (les deux champs candidats sont
`Optional`, donc une clé absente/différente ne fait PAS échouer le décodage, elle produit
silencieusement `nil`). Impossible à confirmer par lecture de code seule — aucun exemple de réponse
JSON réelle n'est documenté nulle part dans le dépôt Android (vérifié). **Corrigé en ajoutant un
diagnostic** (pas une hypothèse de plus) : `AuthEndpoints.parseLoginResponse` capture maintenant le
dictionnaire JSON brut du "user" reçu dans EXACTEMENT ce scénario (`error=="false"` + `user.id ==
nil`), persisté via `UserSession.debugLastLoginRawUserJSON`, et affiché dans les panneaux de
diagnostic déjà visibles de `FeedViewModel`/`ProfileViewModel`. **Au prochain test réel, ce panneau
donnera la clé JSON exacte** — corriger alors `User.id`/`.userId` (ou ajouter un `CodingKey`
alternatif) en UNE SEULE passe, sans deviner une 5ᵉ fois.

**CI VALIDÉ pour ce lot** : run `31965293572`, commit `26b278d`, **SUCCESS**.

---

# HANDOFF PRÉCÉDENT (2026-08-16, après première lecture des captures Appetize — pour mémoire)

**NOUVELLE PREUVE REÇUE CE TOUR** : l'utilisateur a fourni 6 captures d'écran d'un VRAI test
Appetize (pas des hypothèses). Panneaux de diagnostic (ajoutés au tour précédent) VISIBLES dessus :
- Écran Feed : `SESSION: myId=nil token=nil authenticated=false` / `FEED REQUEST: aborted — myId
  nil or non-numeric`.
- Écran Profile : `SESSION: userId(param, figé à la construction)="" myId(relu maintenant)=nil
  authenticated=false` / `PROFILE REQUEST: aborted — UserSession.shared.myId is nil`.
- Écran Créateurs : "Impossible de charger le classement" (générique, `try?` dans
  `CreatorOfWeekViewModel.load()`).
- Écran Chat : "Aucune conversation" (état vide légitime en apparence, FAB de création de groupe
  bien visible — P0-6 confirmé visuellement présent).
- 2 captures Animems : HUD `selectedId=nil·calques=0` (canevas vide, avant ajout média) puis
  `selectedId=<uuid>·calques=1` + `DRAG at (...) → calque #0 déplacé` (SÉLECTION ET DRAG reçus sur
  le TOUT PREMIER contact avec un calque neuf — transform encore identité, ne contredit PAS le bug
  de resélection déjà trouvé/corrigé, qui ne se manifeste qu'APRÈS une première transformation).

**CAUSE RACINE DE LA SESSION VIDE (myId=nil/apiKey=nil PARTOUT) — TROUVÉE ET CORRIGÉE** :
`AuthEndpoints.parseRegisterResponse` avalait silencieusement tout échec de `decodeUser(meta)` via
`try? decodeUser(meta) ?? User()` — si le décodage du "user" imbriqué échoue, le code continuait
avec un `User()` VIDE (id/apiKey nil) MAIS `etat` restait quand même renseigné avec le message de
SUCCÈS du backend ("User created successfully"). `SignUpWithGoogleView.handle(_:)` ne regarde QUE
`user.etat`, jamais si le décodage a réellement réussi — il sauvegardait donc cette session VIDE et
naviguait vers Home. Corrigé : propage maintenant l'échec comme une vraie erreur (`throw`).
**Bug adjacent trouvé en même temps** : `LoginView`/`RegisterView`/`SignUpWithGoogleView`
n'affichaient JAMAIS `viewModel.errorMessage` (le canal d'erreur réseau/décodage de
`AuthViewModel.run`'s `catch`) — seulement leur `errorText` local, alimenté UNIQUEMENT par
`handle(_:)`, qui ne s'exécute jamais si l'appel réseau lève une exception. Toute erreur
réseau/décodage pendant l'authentification était donc invisible. Corrigé dans les 3 vues.
**Honnêteté** : ce bug est spécifique au chemin "S'inscrire avec Google" (`registerWithProvider`).
Le chemin login/register-email a été revérifié et est structurellement sain (décodage `throw`-ant
correctement propagé, jamais avalé). Si l'utilisateur confirme avoir utilisé login/email plutôt que
Google pour ce test, cette cause précise n'explique pas TOUT et il faudra creuser plus — signalé
honnêtement plutôt que de survendre la correction.

**CI VALIDÉ pour ce lot** : run `31963720961`, commit `6d4aa50`, **SUCCESS**.

---

# HANDOFF PRÉCÉDENT (2026-08-16, session BUILD-FIRST/TEST-GLOBAL — toujours valide, voir ci-dessus pour la suite)

**RÈGLE ABSOLUE TOUJOURS EN VIGUEUR** : ne jamais déclarer HOME/FEED, PROFILE ou ANIMEMS "COMPLETE"/
"FUNCTIONALLY VALIDATED" sur la seule base d'un build vert. MAIS — changement important ce tour —
**3 VRAIES CAUSES RACINES ont été trouvées et corrigées par comparaison de code Android↔Swift
champ par champ** (pas des hypothèses, pas des diagnostics ajoutés en attendant un test) :

1. **HOME/FEED + PROFILE vides — CAUSE RACINE CONFIRMÉE** : `JSONValue.int(_:)` (chemin JSON
   dynamique) tolère déjà un `Int` OU une chaîne numérique — preuve déjà présente dans le code que
   ce backend n'envoie PAS toujours ses champs numériques en JSON natif. Mais `FeedActivity`/`User`
   (chemin `Codable` strict) n'avaient JAMAIS cette tolérance : `FeedActivity.id` (SEUL champ non
   optionnel) fait échouer le décodage de CHAQUE activité dès que le serveur l'envoie en chaîne —
   Gson (Android) tolère ça nativement, `JSONDecoder` (Swift) non. Corrigé : nouveau
   `Networking/LenientDecoding.swift` + `init(from:)` manuel sur `FeedActivity`/`User` utilisant ces
   helpers pour tous les champs `Int`/`Bool`/`Double`. Cascade automatiquement à `AuthEndpoints`
   (login) et partout où `User` est décodé.
2. **ANIMEMS canvas/transformations — CAUSE RACINE CONFIRMÉE** : `AnimemesEditorState.selectObject
   (at:)` comparait le point de toucher (repère ÉCRAN) directement à `obj.bound` (repère LOCAL du
   calque, confirmé dans `LayerRenderer` : `context.concatenate(matrix)` PUIS bound assigné en
   coordonnées locales — exactement comme Android `canvas.concat(matrix)` puis `bound.set(offsetX,
   offsetY,...)`, JAMAIS pré-multiplié). Dès qu'un calque est déplacé/pivoté/redimensionné UNE FOIS,
   son repère local ne coïncide plus avec l'écran → la resélection échoue silencieusement → tout
   geste suivant semble "ne pas marcher". Le test correct (inversion de matrice) existait déjà dans
   `AnimemesGestureController.isPoint(_:insideObjectAt:)` mais n'était jamais appelé par
   `selectObject`. Corrigé : `selectObject` délègue maintenant à `gestureController.isPoint`.
3. **Bug de build auto-infligé, trouvé et corrigé dans la FOULÉE** : ajouter `init(from decoder:)` à
   `FeedActivity`/`User` supprime silencieusement l'initialiseur memberwise AUTOMATIQUE de Swift —
   cassait `SearchModels.swift`'s `asFeedActivity` et tous les `User()` (Login/Register/
   SignUpWithGoogle/NewPassword/AuthEndpoints). Restauré via des `init(...)` explicites.

**CI VALIDÉ pour ce lot** : run `31953585109`, commit `02142a2`, **SUCCESS**. **Codemagic PAS ENCORE
déclenché pour ce commit** — demander à l'utilisateur de le lancer manuellement sur `02142a2` pour la
double validation demandée. **AUCUN test Appetize fait** (interdit explicitement par l'utilisateur
tant que le cycle n'est pas terminé) — donc toujours : HOME/FEED, PROFILE, ANIMEMS restent
officiellement "CI VALIDATED, FUNCTIONALLY UNCONFIRMED" jusqu'au test global final, MAIS la
confiance dans ces 3 corrections est HAUTE (causes prouvées par lecture de code, pas des
suppositions) contrairement aux tours précédents qui n'avaient QUE de l'instrumentation.

**AVANT DE CONTINUER : une AUTRE session Claude Code a TOUJOURS des modifications NON commitées EN
COURS** (confirmé par `git status` au moment d'écrire ceci) sur : `Advertising/AdMobManager.swift`,
`App/AppDelegate.swift`, `Messagerie/ChatView.swift`, `Messagerie/GroupModels.swift`,
`Messagerie/GroupRepository.swift`, `Messagerie/AddGroupMemberView.swift` (nouveau, non suivi),
`Messagerie/GroupDetailView.swift` (nouveau, non suivi) — GAP-018 (App Tracking Transparency) et
GAP-011 (gestion de groupe). `MIGRATION_AUDIT.md`/`MIGRATION_PROGRESS.md` sont ÉGALEMENT modifiés/non
commités (probablement par cette même autre session). **Vérifier `git status`/`git diff` AVANT de
toucher un de ces fichiers** — ne pas les modifier en parallèle, ne pas les committer à la place de
l'autre session (même arbre de travail, pas des branches isolées — une collision ici n'est pas un
conflit git résolvable).

**RISQUE APPARENTÉ NON CORRIGÉ, documenté pour la suite** : `Messagerie/GroupModels.swift`
(actuellement non commité par l'autre session) a `GroupMember.userId: Int` et `.groupId: Int`,
NON-optionnels, décodés via `JSONDecoder().decode` strict — EXACT même classe de risque que
`FeedActivity.id` ci-dessus (le backend pourrait aussi envoyer ces champs en chaîne pour les
membres de groupe). PAS corrigé cette session pour éviter d'éditer un fichier en cours de
modification par l'autre session — à traiter dès que ce fichier est stable/commité, avec le même
motif `LenientDecoding.swift` déjà en place (`decodeLenientInt`/`decodeLenientIntIfPresent`).

## Last confirmed state
- Branch: `main`
- HEAD commit: `02142a2` ("fix(build): restore memberwise initializers lost by adding custom
  init(from:)") — poussé sur `origin/main`, confirmé par `git fetch`. Précédé de `2fd1149`
  (les 3 vraies corrections ci-dessus), `c63a3c8` (doc), `328f7ad`/`f634788` (tours précédents).
- Dernier run GitHub Actions confirmé : `31953585109` sur commit `02142a2`, **SUCCESS**.
  Run intermédiaire `31952957757` sur `2fd1149` avait ÉCHOUÉ (le bug d'initialiseur memberwise
  ci-dessus, trouvé via le log réel puis corrigé dans la foulée — pas deviné).
- Dernier build Codemagic confirmé fonctionnellement testé (par l'utilisateur, PAS par cette
  session) : celui qui a produit le rapport "STOP" — build sur un commit antérieur à `f634788`
  (probablement `60818bc` ou `b485f34`), compile avec succès, MAIS Home/Feed, Profile, Animems
  FONCTIONNELLEMENT ÉCHOUÉS À CE MOMENT-LÀ. **Aucun nouveau test Appetize/Codemagic depuis** — le
  travail de CE tour (les 3 vraies corrections) n'a jamais été vu tourner réellement.

## Actually completed cette session (audit + 2 corrections, PAS commité)
1. **Audit indépendant des 7 priorités utilisateur (Chat/Animems/Appels/Shareboard/Wallet/
   Publicité/Réglages-Divers)** — voir `MIGRATION_AUDIT.md`, section "SESSION DU 2026-08-16 (passe
   d'audit indépendante)". Résultat : Chat (signalisation Socket.IO 23/23 vérifiée, DONE), Appels
   (WebRTC re-vérifié ligne par ligne, DONE au niveau code), Shareboard (architecture WebRTC
   partagée confirmée fidèle), Wallet (couche réseau DONE, retrait PARTIAL), AdMob (formats DONE,
   ATT MISSING), Réglages/Divers (8 nouveaux gaps réels documentés GAP-009 à GAP-016).
2. **GAP-018 (App Tracking Transparency) CORRIGÉ** — `Advertising/AdMobManager.swift` +
   `App/AppDelegate.swift` (nouveau `applicationDidBecomeActive`).
3. **GAP-011 (gestion de groupe) CORRIGÉ pour le cœur** — nouveaux `Messagerie/GroupDetailView.swift`
   + `Messagerie/AddGroupMemberView.swift`, `GroupModels.swift`/`GroupRepository.swift` étendus,
   `ChatView.swift` : bouton "info.circle" toolbar pour ouvrir les infos de groupe (membres/rôles/
   description/lien d'invitation/quitter). PAS couvert : photo de groupe, action "Message" directe
   sur un membre, mute privé (documenté dans `GroupDetailView.swift` en tête de fichier).
4. **Re-vérification fraîche et approfondie de Feed (Session→API→Decode→ViewModel→View) et
   Galerie/Publish** — AUCUN nouveau bug statique trouvé au-delà de ce que le 11ᵉ tour avait déjà
   corrigé/instrumenté. `UserSession` confirmée synchrone/fiable (pas de race condition de cache).
   `FeedActivity.id: Int` confirmé être le SEUL champ non-optionnel (tous les autres le sont),
   correspond à `activityLib.java`'s `int id` — pas de divergence de type trouvée qui expliquerait un
   échec de décodage systématique. `FeedView.swift`/`PublishComposeView.swift` relus intégralement,
   logique de state (`stage`/`croppedImage`) correctement séquencée. **Conclusion honnête : la cause
   racine des P0 Home/Profile/Chat-bouton reste NON CONFIRMÉE par manque de logs Appetize réels —
   voir "Next exact task" ci-dessous, ne pas re-creuser sans nouvelle preuve.**

## Currently in progress
- **Rien de mon côté** (pas de tâche interrompue à mi-chemin).
- **L'AUTRE session** semble en train de faire une passe de parité UI systématique à partir de
  captures Android fraîchement reçues (Roster FAB, Profile boutons ronds, vignettes Profile compteur
  de vues, Animems, Search, Notifications) — fichiers listés en tête de cette section, TOUS non
  commités au moment d'écrire.

## Uncommitted work (cette session, séparé de l'autre session — voir liste ci-dessus)
- `MIGRATION_AUDIT.md` (audit + documentation des 2 corrections)
- `Sources/TiinverSwift/Advertising/AdMobManager.swift` (GAP-018)
- `Sources/TiinverSwift/App/AppDelegate.swift` (GAP-018)
- `Sources/TiinverSwift/Messagerie/GroupModels.swift` (GAP-011)
- `Sources/TiinverSwift/Messagerie/GroupRepository.swift` (GAP-011)
- `Sources/TiinverSwift/Messagerie/ChatView.swift` (GAP-011, bouton toolbar)
- `Sources/TiinverSwift/Messagerie/GroupDetailView.swift` (GAP-011, nouveau)
- `Sources/TiinverSwift/Messagerie/AddGroupMemberView.swift` (GAP-011, nouveau)
- **AUCUNE compilation réelle vérifiée** — pas d'accès Xcode/macOS depuis cet environnement Windows,
  code relu manuellement (signatures, `deploymentTarget: 16.0` respecté — `ContentUnavailableView`
  iOS 17+ repéré et évité dans `AddGroupMemberView.swift`) mais pas confirmé par un build CI.

## Appetize failures requiring fixes (toujours ouvertes, cause NON confirmée)
- **P0 HOME** : le feed n'affiche toujours rien. Logs `SESSION:`/`FEED REQUEST:`/`FEED RESPONSE:`/
  `FEED UI:` déjà en place dans `FeedViewModel.loadNextPage()` (depuis le 11ᵉ tour) — **la prochaine
  session DOIT obtenir la sortie console réelle d'un test Appetize pour trancher**, aucune relecture
  de code supplémentaire ne peut progresser sans cette preuve (déjà tentée deux fois : 11ᵉ tour +
  cette session, aucun bug statique trouvé au-delà de ce qui est déjà corrigé).
- **P0 PROFILE** : idem, logs `PROFILE REQUEST:`/`PROFILE RESPONSE:` déjà en place.
- **P0 CHAT — bouton créer un groupe** : root cause probablement TROUVÉE par l'autre session (diff
  non commité de `RosterListView.swift`) — le bouton était un item de barre d'outils
  (`person.2.badge.plus`), invisible/pas assez découvrable vs le vrai FAB rose bas-droite d'Android
  vu sur la capture d'écran — corrigé en FAB dans le diff non commité actuel. **À CONFIRMER par le
  prochain test Appetize une fois ce travail commité**, pas encore validé.
- **P0 ANIMEMS** : en cours de reconstruction par l'autre session à partir des captures Android
  reçues (diff non commité `AnimemesEditorView.swift`/`AnimemesEditorState.swift`/
  `AnimemesDrawingView.swift`) — ne pas toucher ces fichiers en parallèle.
- **P0 GALERIE/PUBLIER** : bug silencieux déjà trouvé et corrigé au 11ᵉ tour (2 `guard` silencieux).
  Re-vérifié cette session, aucun autre bug statique trouvé. **Pas re-testé sur Appetize depuis le
  correctif** — reste "CODE WRITTEN, CI VALIDATED" mais PAS "TESTED ON APPETIZE"/"FUNCTIONALLY
  VALIDATED".

## CI validated but NOT functionally validated
Absolument tout le travail depuis `b485f34` inclus (Profile fix, Galerie fix, groupes fix) — AUCUN
test Appetize n'a eu lieu depuis. Plus tout le travail non commité de cette session (GAP-018,
GAP-011) et de l'autre session (parité UI) — encore au niveau "CODE WRITTEN", pas même "CI
VALIDATED" tant que non commité/buildé.

## Known bugs
- Voir "Appetize failures" ci-dessus — Home/Profile vides, bouton groupe (probablement résolu, à
  confirmer), Animems non fidèle (en cours de résolution par l'autre session).
- GAP-011 : photo de groupe, action "Message" sur un membre, mute privé — MISSING, documentés,
  pas des oublis silencieux.
- GAP-016 (statistiques créateur), GAP-013/014 (cadeaux/réponses commentaires), GAP-015 (motifs de
  signalement inventés), GAP-010 (liens légaux About/Help génériques), GAP-009 (stockage granulaire)
  — tous MISSING/INCORRECT, non traités cette session, voir `MIGRATION_AUDIT.md` pour le détail
  complet de chaque gap.

## Hypothèses NON vérifiées
- L'hypothèse "décodage `Codable` strict avalant des items Feed" (11ᵉ tour) reste NON confirmée —
  cette session a re-vérifié que `FeedActivity.id` est le seul champ non-optionnel et correspond
  exactement au type Android (`int`), ce qui rend cette hypothèse MOINS probable comme cause d'un
  feed COMPLÈTEMENT vide (elle expliquerait au mieux quelques items manquants, pas un flux à zéro
  post) — mais reste possible si le serveur retourne parfois un `id` non-numérique. Logs déjà en
  place pour trancher.
- Aucune hypothèse nouvelle avancée pour Home/Profile cette session — voir conclusion honnête dans
  "Actually completed" ci-dessus.

## Next exact task
1. **Obtenir un vrai test Appetize AVEC les logs console** (ou une capture d'écran claire de
   l'erreur) une fois le travail actuel (GAP-018, GAP-011, ET le travail de parité UI de l'autre
   session) commité et un build CI vert confirmé — c'est le SEUL moyen de trancher Home/Profile,
   deux passes de relecture de code n'ayant rien trouvé de plus à corriger statiquement.
2. Si les logs confirment la piste `Codable`/décodage pour Feed : corriger `FeedActivity` (rendre
   `id` plus tolérant, ou ajouter un `init(from:)` custom comme `SearchModels.swift` l'a déjà fait
   pour un problème similaire, GAP déjà résolu le 2026-08-15/16).
3. Si les logs montrent autre chose (erreur réseau, timeout, mauvaise base URL) : suivre la preuve,
   pas une hypothèse.
4. Une fois Home/Profile/Chat confirmés fonctionnels : traiter GAP-016 (statistiques créateur, écran
   entier à construire) et GAP-010 (liens légaux About/Help, correctif trivial de 3 lignes,
   rapport bénéfice/effort excellent).
5. Committer le travail de cette session (GAP-018 + GAP-011) ET celui de l'autre session (parité UI)
   séparément si possible, avec des messages de commit distincts reflétant leurs objectifs réels
   respectifs — vérifier `git status` d'abord pour confirmer qui a fini d'éditer quoi.

## Resume instruction for next Claude
"Vérifie d'abord `git status` — si les fichiers Animems/Roster/Profile/Contacts listés en tête de
cette section sont encore non commités, NE LES MODIFIE PAS avant d'avoir confirmé qu'aucune autre
session n'est en train de les éditer. Committe le travail prêt (GAP-018 ATT + GAP-011 gestion de
groupe, cette session ; parité UI captures Android, l'autre session, si elle a terminé), déclenche
un build GitHub Actions, corrige toute erreur réelle de compilation. Puis attends/demande un test
Appetize réel AVEC LES LOGS CONSOLE avant de retoucher Home/Profile — ne recommence pas une 3ᵉ passe
de relecture de code sans cette preuve, ça n'a rien donné de plus aux 2 passes précédentes. Une fois
les logs en main, corrige la cause RÉELLE qu'ils révèlent, pas une hypothèse. Ensuite GAP-016
(statistiques créateur) et GAP-010 (liens légaux) sont les prochains gaps documentés les plus
rentables (voir `MIGRATION_AUDIT.md`)."

---

## 0. BUILD CI — À LIRE EN PREMIER

**BUILD CI VALIDÉ :** Oui (GitHub Actions uniquement — voir stratégie double-CI ci-dessous,
Codemagic en attente d'un déclenchement manuel par l'utilisateur, jamais rapporté à ce jour)
**Build :** GitHub Actions run `31941895327` (workflow `ios-build.yml`)
**Commit :** `b485f34` ("fix(profile,galerie,groups): surface silent errors, add diagnostic logs"
— dernier commit de la session, 11ᵉ tour, voir section 11quater ci-dessous)
**Date :** 2026-08-16
**Résultat :** `** BUILD SUCCEEDED **`. Confirmé via l'API GitHub Actions (`status: completed,
conclusion: success`).
**IMPORTANT — ce commit N'A PAS ENCORE été testé fonctionnellement** : Codemagic + GitHub Actions
ont validé la COMPILATION du tour précédent (`68fd1d3`) et l'utilisateur a fait un premier test
Appetize GLOBAL dessus, qui a trouvé 3 problèmes CRITIQUES (Home/Feed vide, Profile vide, Galerie
publication muette) + 1 problème P0 non résolu (bouton créer-groupe absent) + Animems à comparer
visuellement (captures à venir). Ce tour (`b485f34`) corrige 2 des 3 CRITIQUES par lecture de code
(voir section 11quater) et ajoute des logs de diagnostic pour le reste — **AUCUN de ces correctifs
n'a encore été revérifié sur un run Appetize réel**, seule la compilation est confirmée.
**Historique complet des runs depuis le dernier point de reprise** (pour ne pas confondre) :
1. `31912698274` (commit `f2460f2`, Chat+Galerie+Animems minimal construits) — SUCCESS (session
   précédente, voir section 0ter).
2. `31916776657` (commit `d19e372`, gestes Animems réels + fix WebRTC glare + parité Galerie) —
   SUCCESS.
3. `31915767632` (commit `ab36462`, native ads câblées dans le pager Feed) — SUCCESS.
4. `31916776657`... voir plus haut, doublon d'affichage — le run suivant (commit `3f1c22d`,
   timeline/keyframes/lecture/masques Animems câblés pour la première fois) — **ÉCHEC** :
   `ProfileRepository()` appelé directement (`init` privé, singleton `.shared` requis) dans
   `HashtagFeedView.swift`/`SearchView.swift` (fonctionnalité Search du même lot).
5. `31917572782` (commit `b90ae3d`, fix ProfileRepository + panneau/geste masque câblés) —
   **ÉCHEC** : `error: conflicting arguments to generic parameter 'T' ('AnyGesture<(some
   Gesture).Value>' vs. 'AnyGesture<(some Gesture).Value>')` — deux propriétés `some Gesture`
   distinctes (`combinedGesture`/`maskEditGesture`) choisies par ternaire ne s'unifient PAS même
   structurellement identiques.
6. `31918239357` (commit `fd92885`, tentative de fix via type explicite `AnyGesture<ObjectGestureValue>`
   partagé + permission micro avant appel) — **ÉCHEC** : `error: type of expression is ambiguous
   without a type annotation` sur la construction imbriquée `AnyGesture(SimultaneousGesture(...))`.
7. `31918549314` (commit `0fa0de8`, tentative de fix via bindings `let` explicitement typés) —
   **ÉCHEC** : log non entièrement récupéré avant la décision de changer d'approche (téléchargement
   du log `xcodebuild` via l'API GitHub Actions systématiquement lent/tronqué pour ce projet — log
   complet ~25-27k lignes, dépendances Firebase compilées avant la cible propre, `curl --max-time
   590` en arrière-plan nécessaire, jamais en une seule commande synchrone).
8. `31923679579` (commit `e4b347a`, gestes fusionnés en UN SEUL jeu avec bascule `isMaskEditMode` à
   l'exécution plutôt que deux graphes de gestes différemment typés) — **SUCCESS.** Lot Animems
   timeline/keyframes/masques enfin confirmé compilé après 4 tentatives.
9. `31924209161` (commit `70692d5`, sauvegarde image statique pour composition Animems non animée)
   — **SUCCESS.**
10. `31924498415` (commit `ef3a34b`, recadrage temporel vidéo `MediaTrim` câblé dans la Galerie) —
    **SUCCESS.**
11. `31935598442` (commit `ac67c79`, modèles de mouvement Animems locaux : sauvegarde/chargement/
    suppression/galerie, port fidèle de `MotionTemplateManager.java`) — **SUCCESS.**
12. `31936056808` (commit `f2012a1`, stickers/emoji Galerie via clavier emoji natif + routage
    complet des liens profonds `myapp://parrainage`/`tiinver://{user,post,group,...}`) —
    **SUCCESS.**
13. `31938768739` (commit `adf9564`, modèles de mouvement COMMUNAUTAIRES Animems — parcourir/
    télécharger/appliquer, portion upload confirmée code mort côté Android donc non portée) —
    **SUCCESS.**
14. `31939406542` (commit `16c1fbd`, interactions Feed like/commentaire/partage/suppression/
    ne-plus-suivre/blocage/signalement + suppression "pour tout le monde" côté Chat) —
    **SUCCESS.**
15. `31939780419` (commit `6014cc6`, dépendance `FirebaseCrashlytics`) — **SUCCESS.**
16. `31940076878` (commit `68fd1d3`, purge des caches locaux Chat/Roster/Notifications à la
    déconnexion/suppression de compte) — **SUCCESS.**
17. `31941895327` (commit `b485f34`, correctifs P0 post-Appetize : erreurs silencieuses Profile/
    Galerie-publication/création-groupe rendues visibles + logs de diagnostic Session/Feed) —
    **SUCCESS.** Dernier run connu. **Compilation seulement — voir section 11quater : rien de ce
    tour n'a encore été revérifié sur un run Appetize réel.**

### CI VALIDATION — format demandé par l'utilisateur pour chaque commit important

**Commit :** `f2460f2` (englobe aussi `3dc83d3` Chat et `1aab36e` Galerie, même run)
**GitHub Actions :** Build ID `31912698274` — Result **SUCCESS**
**Codemagic :** Build ID — (aucun, déclenchement manuel par l'utilisateur, en attente de retour —
toujours vrai pour TOUS les commits du jour, aucun build Codemagic n'a encore été rapporté)
**Double validation :** NO (GitHub seul pour l'instant, sur les 2 derniers commits importants)
**Erreurs GitHub :** 0
**Erreurs Codemagic :** N/A (pas encore lancé)
**Prochaine tâche :** voir section 10.

### GAP CI — corrections Appetize non encore testées fonctionnellement

**Compilation Swift atteinte :** OUI (run `31911325017`, SUCCESS)
**Xcode :** 16.2 (sélection dynamique, dernière version disponible sur le runner)
**Runner :** `macos-14-arm64`, image GitHub Actions `20260629.0180.1`
**Erreur éventuelle :** aucune
**Test fonctionnel réel (Appetize) après ces corrections :** **NON EFFECTUÉ** — rappel explicite de
l'utilisateur, règle absolue de cette mission : un build vert signifie UNIQUEMENT que le code
compile, jamais que Home/Profile/Search fonctionnent réellement comme Android. Voir
`MIGRATION_AUDIT.md`, section "APPETIZE FUNCTIONAL TEST — 2026-08-15" pour le détail complet
problème par problème.

**Règle permanente adoptée cette session (explicite, utilisateur)** : à partir de maintenant,
chaque modification importante doit être testée sur le MÊME commit par les deux CI. Aucun
credential Codemagic disponible dans cet environnement (contrairement à GitHub, où Git Credential
Manager est déjà configuré et fonctionnel, confirmé par `git ls-remote` immédiat) —
**l'utilisateur déclenche Codemagic manuellement** sur son dashboard (codemagic.io), sur le même
commit que celui poussé et validé côté GitHub Actions. Le rôle de la session Claude Code : préparer
le code, committer, pousser, valider via GitHub Actions, PUIS signaler explicitement à l'utilisateur
que le commit est prêt pour un déclenchement Codemagic manuel — ne jamais prétendre avoir
lancé/vérifié Codemagic soi-même sans credential réel.

### Sécurité — token GitHub

Un token GitHub était présent en clair dans `git remote -v` en début de session (signalé par
l'utilisateur, déjà exposé une fois dans les logs de cette conversation avant la sécurisation —
**rotation recommandée, pas encore effectuée à la connaissance de cette session**). Remote nettoyé
(`git remote set-url` sans credential). Toutes les opérations Git/API suivantes utilisent **Git
Credential Manager** via `git credential fill` — jamais réaffiché, jamais écrit dans un fichier.
Vérifié qu'aucun fichier du dépôt/temporaire ne contient le motif de token.

---

## 0ter. CHAT/GALERIE/ANIMEMS — FICHE DE VALIDATION (construits le 2026-08-15, tour 7)

**Contexte** : les 3 GAPs identifiés par le test Appetize comme "fonctionnalités jamais
construites" (pas des bugs) ont été bâtis dans la MÊME session, sur instruction explicite de
l'utilisateur de ne pas s'arrêter entre chaque correction (quota Appetize limité → un seul test
global prévu, pas encore fait).

- **Chat (création de groupe)** : COMPLET — sélecteur de contacts + création de groupe, fidèle à
  `ContactsFragment`/`ChooseFragment`/`Group.java` (endpoints `connectedusers`/`group`/
  `membership` exacts, y compris la faute de frappe serveur `"pivate"`). Commit `3dc83d3`.
- **Galerie (MediaEditor + publication)** : PÉRIMÈTRE RÉDUIT ASSUMÉ — crop→légende→publication
  réelle (`POST activity/add`) fonctionnels ; peinture/texte/stickers sur la photo PAS repris
  (confirmés secondaires par l'investigation Android, `PublishFragment`/`ImageEditorCompound` lus
  en entier). `MediaTrim` (recadrage vidéo) pas repris non plus. Commit `1aab36e`.
- **Animems (écran éditeur)** : PÉRIMÈTRE MINIMAL ASSUMÉ, PAS LA PARITÉ COMPLÈTE — ajout photo/
  texte/forme, déplacement au doigt (translation seule), export MP4 statique 3s. PAS de rotation/
  échelle/masques/keyframes/timeline détaillée (GAP-006 reste un chantier à part entière, ~24 942
  lignes Android, déjà estimé à plusieurs semaines-ingénieur). Commit `f2460f2`.

**Compilation CI :** VALIDÉE (GitHub Actions, run `31912698274`, SUCCESS, 11/11 fichiers confirmés
compilés par leur chemin complet, 0 erreur, 0 warning — voir section 0).
**Tests réels sur appareil :** NON EFFECTUÉS — conforme à la consigne explicite de l'utilisateur
(un seul test Appetize global prévu à la fin du lot complet, pas encore fait à ce stade).

---

## 0bis. GAP-004 — FICHE DE VALIDATION (format demandé par l'utilisateur)

**Implémentation :** COMPLÈTE (les 3 usages : photo de profil, soumission certification, pièces
jointes chat — upload seulement, le téléchargement des pièces jointes REÇUES est un gap distinct,
voir section 4)
**Compilation CI :** VALIDÉE (GitHub Actions uniquement — Codemagic en attente, voir section 0)
**Build ID :** `31908841925`
**Commit :** `e4b1832`
**Résultat :** `BUILD SUCCEEDED`, 10/10 fichiers GAP-004 confirmés présents dans les invocations de
compilation réelles (chemin complet vérifié dans le log, pas une supposition)
**Fichiers compilés :** `Networking/APIClient.swift`, `Profile/ProfileRepository.swift`,
`Profile/ProfileViewModel.swift`, `Profile/ProfileView.swift`, `Discover/CertificationModels.swift`,
`Discover/CertificationView.swift`, `Messagerie/ChatMediaUploadService.swift`,
`Messagerie/ChatViewModel.swift`, `Messagerie/ChatView.swift`, `Storage/MessageRepository.swift`
**Erreurs :** 0
**Warnings :** 2, tous les deux dans du code PRÉ-EXISTANT de `ChatViewModel.swift`
(`markConversationRead`/`deleteSelectedForEveryone`) — 0 dans le code effectivement écrit pour
GAP-004
**Tests réels sur appareil :** NON EFFECTUÉS — rappel explicite de l'utilisateur à ne jamais
oublier : "compile réellement" ≠ "fonctionne" ≠ "validé sur device". Rien de ce qui suit n'a été
vérifié : sélection photo, upload profil réel (jamais touché un vrai serveur), certification réelle,
pièce jointe chat réelle, upload BunnyCDN réel, réception du message par l'autre participant,
téléchargement des pièces jointes (non implémenté).

---

## 1. ÉTAT ACTUEL (2026-08-15, fin de session)

Projet Android de référence : `C:\Users\helen\AndroidStudioProjects\tiinver`
Projet iOS cible : `C:\Users\helen\iOSProjects\TiinverSwift`

Les 18 modules du plan de portage initial sont "fermés" depuis le 2026-08-12, mais **aucune
compilation réelle n'a jamais eu lieu** depuis un environnement Windows sans Xcode — ni pendant le
portage initial, ni pendant cette session. Toute vérification passe par CI :
- `.github/workflows/ios-build.yml` (GitHub Actions, `workflow_dispatch` manuel, compilation seule)
- `codemagic.yaml` (2 workflows : `checkpoint-build` compilation seule, `visual-smoke-test`
  captures d'écran simulateur + `.zip` pour test interactif via Appetize.io)

**Dernier build CI confirmé : ÉCHEC le 2026-08-13**, 2 corrections appliquées (GoogleMobileAds
épinglé à 13.0.0+, `Tool` enum rendu `internal`) — **jamais reconfirmées par un nouveau build**.
Deux bugs visuels majeurs (feed blanc, navigation à 3 onglets au lieu de 5) corrigés par une session
parallèle le 2026-08-13, vérifiés par lecture de code uniquement, jamais vus tourner réellement.

## 2. DERNIÈRES DÉCOUVERTES (cette session, 2026-08-15)

1. **GAP-000 (démarrage) clos** — `App.java` (`onCreate()` réel, PAS `onCreate2()` qui est du code
   mort) comparé ligne par ligne à `AppDelegate.swift`. SDK Facebook (App Events/attribution pub,
   PAS de login) jamais porté côté iOS — P3, aucun impact utilisateur.
2. **GAP-008 (nouveau)** — `Storage/ViewEventRepository.swift` (stockage local watch-time,
   équivalent `ViewTracker.java`) **existe mais n'est appelé NULLE PART** dans tout le projet : ni
   enregistrement local depuis le feed, ni synchronisation périodique vers le serveur
   (`BGTaskScheduler` absent). Si le classement Créateurs/algorithme dépend de ces données côté
   serveur (à confirmer), le feed iOS ne contribue actuellement AUCUNE donnée de visionnage.
3. **GAP-004 (upload de fichiers) — l'hypothèse "un seul service partagé" de la session précédente
   était FAUSSE.** 3 protocoles réels, pas 1 :
   - Photo de profil + Certification → backend Tiinver, POST multipart, `APIClient.uploadMultipart`
   - Pièces jointes chat → BunnyCDN storage, PUT direct, `ChatMediaUploadService` (nouveau, séparé)
4. **2 bugs "double slash" trouvés dans `UploadFileOrDataService.java`** (Android) en le relisant
   précisément pour l'implémentation BunnyCDN — accidentels (incohérents entre 2 branches), NON
   reproduits côté iOS, corrigés uniformément. Détail complet dans `ChatMediaUploadService.swift`
   (commentaire de tête) et `MIGRATION_AUDIT.md` GAP-004.
5. **2 bugs Swift trouvés et corrigés AVANT de considérer le travail fini** (vérification statique,
   pas de compilation réelle possible) :
   - `.onChange(of:) { oldValue, newValue in }` (API iOS 17+) utilisée par erreur dans
     `ProfileView.swift` — `deploymentTarget: 16.0` (`project.yml`) ne la supporte pas, corrigée en
     forme à un seul paramètre.
   - `FirebaseConfigManager.shared` (n'existe pas) au lieu de `TiinverFirebaseConfigManager.shared`
     dans `CertificationView.swift`.

## 3. FONCTIONNALITÉS TERMINÉES CETTE SESSION

- **GAP-000** : audit du démarrage clos (voir `MIGRATION_AUDIT.md`).
- **GAP-004, entièrement clos** (les 3 usages) :
  - Upload photo de profil (`ProfileRepository.uploadProfilePicture` + `PhotosPicker` dans
    `ProfileView.swift`).
  - Soumission de certification (`CertificationRepository.submit` + section "Nouvelle demande" dans
    `CertificationView.swift`).
  - Pièces jointes chat, UPLOAD SEULEMENT (`ChatMediaUploadService.swift`, nouveau fichier ; bouton
    trombone dans `ChatView.swift` ; `ChatViewModel.attachMedia`/`requestUpload`).

## 4. FONCTIONNALITÉS EN COURS / PARTIELLES

Rien "en cours" au sens d'un travail interrompu à mi-chemin — chaque incrément ci-dessus est fermé
de bout en bout côté code. Mais GAP-004 lui-même a révélé 2 gaps ADJACENTS explicitement laissés de
côté (documentés, pas oubliés) :
- **Download des pièces jointes REÇUES** (`ChatViewModel.requestDownload`, toujours un `TODO` vide)
  — `DownloadReceiver.java` (Android) jamais lu. Upload ≠ download, protocole probablement différent
  (GET direct depuis l'URL CDN publique, pas de clé `AccessKey` nécessaire côté lecture — À VÉRIFIER,
  pas supposé).
- **Confirmation que le message avec pièce jointe atteint réellement l'autre participant** via
  Socket.IO une fois l'upload terminé — le code appelle `send(mlib)` (émission), mais l'événement
  socket exact et sa réception côté pair n'ont PAS été re-vérifiés (rattaché à GAP-003).

## 5. GAPS RESTANTS (par priorité, voir `MIGRATION_AUDIT.md` section 10 pour le détail complet)

- **P0** — Confirmer par un test CI/Appetize.io réel que le code compile ET que feed/navigation
  fonctionnent visuellement (jamais fait, ni avant cette session ni pendant).
- **P1** — GAP-003 (Chat, audit profond événement-par-événement, jamais refait depuis le portage
  initial) ; GAP-005 (Appels WebRTC/CallKit, jamais exécutés) ; GAP-006 (Animems, audit/parité
  COMPLÈTE — un écran minimal fonctionnel existe désormais, voir section 0ter, mais PAS la parité
  avec les 24 942 lignes Android) ; download pièces jointes chat (voir section 4 ci-dessus) ; Feed
  like/commentaire/partage (jamais portés, périmètre Checkpoint 1 exclu à l'époque) ; MediaEditor
  peinture/texte/stickers (Galerie, périmètre réduit assumé cette session, voir section 0ter).
- **P2** — GAP-008 (sync watch-time, voir section 2) ; Réglages (8 fragments à vérifier un par un) ;
  Recherche/Follow/Commentaires (audit ciblé) ; AdMob (jamais vu charger une vraie pub) ; rotation/
  échelle/masques/keyframes/timeline Animems (voir section 0ter, périmètre minimal actuel).
- **P3** — SDK Facebook (App Events) ; décoratifs Créateurs ; Statistiques/boost interne (jamais
  explorés en détail). **Contacts** : le sélecteur pour la création de GROUPE existe désormais
  (section 0ter) — reste un éventuel écran "Contacts" autonome si Android en a un hors du flux
  groupe (pas confirmé/investigué).

## 6. FICHIERS RÉCEMMENT MODIFIÉS (état final, TOUS COMMITÉS ET POUSSÉS sur `origin/main`)

```
Commit 8aeb5a6 : .github/workflows/ios-build.yml (fix sélection Xcode)
Commit e48dbed : .github/workflows/ios-build.yml (Metal Toolchain non bloquant — introduisait un bug YAML)
Commit a66c509 : .github/workflows/ios-build.yml (fix du bug YAML introduit par e48dbed)
Commit e4b1832 : "feat(migration): complete file upload migration (GAP-004)"
  MIGRATION_AUDIT.md                                     (GAP-000/GAP-004/GAP-008/section 12 CI)
  MIGRATION_PROGRESS.md                                  (4 entrées de journal 2026-08-15)
  Sources/TiinverSwift/Networking/APIClient.swift        (+ uploadMultipart, multipartHeaders)
  Sources/TiinverSwift/Profile/ProfileRepository.swift   (uploadProfilePicture implémenté)
  Sources/TiinverSwift/Profile/ProfileViewModel.swift    (+ uploadProfilePicture, isUploadingPhoto)
  Sources/TiinverSwift/Profile/ProfileView.swift         (+ PhotosPicker sur l'avatar)
  Sources/TiinverSwift/Discover/CertificationModels.swift (+ CertificationRepository.submit)
  Sources/TiinverSwift/Discover/CertificationView.swift  (+ section "Nouvelle demande")
  Sources/TiinverSwift/Messagerie/ChatMediaUploadService.swift  (NOUVEAU FICHIER, BunnyCDN)
  Sources/TiinverSwift/Messagerie/ChatViewModel.swift    (+ attachMedia/requestUpload implémenté)
  Sources/TiinverSwift/Messagerie/ChatView.swift         (+ bouton trombone)
  Sources/TiinverSwift/Storage/MessageRepository.swift   (+ updateFileUploaded)
Commit 3f5f880 : "fix(migration): resolve Appetize functional parity issues (P0: Home/Profile/Search)"
  Sources/TiinverSwift/Feed/FeedView.swift                       (réécrit : grille 2 colonnes + détail plein écran)
  Sources/TiinverSwift/Authentication/AuthSessionPersistence.swift (+ saveSession, sync)
  Sources/TiinverSwift/Authentication/LoginView.swift             (appel saveSession avant navigation)
  Sources/TiinverSwift/Authentication/SignUpWithGoogleView.swift  (idem)
  Sources/TiinverSwift/Authentication/EmailVerificationView.swift (idem)
  Sources/TiinverSwift/Discover/SearchModels.swift                (init(from:) tolérant clés absentes)
Commit 3dc83d3 : "feat(chat): implement group creation flow"
  Sources/TiinverSwift/Messagerie/GroupModels.swift              (NOUVEAU)
  Sources/TiinverSwift/Messagerie/ContactsRepository.swift       (NOUVEAU, GET connectedusers)
  Sources/TiinverSwift/Messagerie/GroupRepository.swift          (NOUVEAU, POST group+membership)
  Sources/TiinverSwift/Messagerie/ContactPickerView.swift        (NOUVEAU)
  Sources/TiinverSwift/Messagerie/GroupCreationView.swift        (NOUVEAU)
  Sources/TiinverSwift/Messagerie/RosterListView.swift           (+ bouton d'entrée)
Commit 1aab36e : "feat(feed): implement media publish flow (photo/video)"
  Sources/TiinverSwift/Feed/PublishComposeView.swift             (NOUVEAU)
  Sources/TiinverSwift/Feed/FeedRepository.swift                 (+ publish(), POST activity/add)
  Sources/TiinverSwift/Feed/FeedView.swift                       (fermetures caméra/galerie câblées)
Commit f2460f2 : "feat(animems): assemble minimal functional editor screen"
  Sources/TiinverSwift/Animems/AnimemesEditorView.swift          (NOUVEAU)
  Sources/TiinverSwift/Animems/AnimemesEditorState.swift         (NOUVEAU)
Non commité : CLAUDE_CONTINUATION.md (ce fichier — sera commité en fin de session, doc pure),
MIGRATION_AUDIT.md/MIGRATION_PROGRESS.md (section Appetize ajoutée après ce commit, à committer avec
ce fichier)
```

## 7. TESTS EFFECTUÉS

- **Vérification statique** (lecture manuelle) avant push : cohérence des types Swift, signatures
  d'appel, disponibilité API vs `deploymentTarget: 16.0`.
- **Comparaison Android ↔ iOS** : chaque endpoint/champ/header vérifié contre le fichier Android
  source correspondant, lu en entier (pas deviné). Pour la mission Appetize (ce tour), 6
  investigations Android↔iOS menées en parallèle par des agents dédiés, résultats croisés avec
  lecture directe du code avant toute correction.
- **Compilation CI RÉELLE, GitHub Actions** : run `31911325017`, commit `3f5f880`, **SUCCESS**
  confirmé, les 6 fichiers modifiés confirmés présents dans les invocations de compilation par leur
  chemin complet, 0 erreur, 1 warning pré-existant sans rapport.
- **Test fonctionnel réel sur Appetize.io (device réel)** — celui qui a RÉVÉLÉ tous les problèmes de
  cette section : Home vide, Profile vide, Search sans résultats, bouton créer-groupe Chat absent,
  sélection galerie sans effet, bouton Animems non fonctionnel. C'est ce test, pas une lecture de
  code, qui a permis de trouver la race condition de session et l'erreur d'architecture du feed.

## 8. TESTS IMPOSSIBLES/PAS ENCORE EFFECTUÉS

- **Compilation Codemagic** — en attente d'un déclenchement manuel par l'utilisateur, toujours vrai
  pour `e4b1832` ET `3f5f880` (aucun credential Codemagic disponible dans cet environnement).
- Exécution sur simulateur/device DEPUIS CETTE SESSION — jamais (pas de Xcode local) ; SEUL le test
  Appetize fourni PAR L'UTILISATEUR fait exception, et c'est justement lui qui a motivé cette
  section.
- **Retest Appetize des 3 corrections P0 de ce tour (Home/Profile/Search)** — PAS ENCORE FAIT. Le
  commit `3f5f880` compile (confirmé CI) mais n'a PAS été revu sur un device réel après correction.
- Chat (création de groupe), Galerie (MediaEditor), Animems (éditeur) — non implémentés, donc rien à
  tester (voir section "APPETIZE FUNCTIONAL TEST" de `MIGRATION_AUDIT.md`).
→ **Rappel permanent de l'utilisateur, à ne jamais oublier, règle absolue de la mission Appetize** :
un build CI vert signifie UNIQUEMENT que le code compile — jamais que Home/Profile/Search
fonctionnent réellement comme Android tant qu'un nouveau test Appetize ne l'a pas confirmé.

## 9. DÉCISIONS TECHNIQUES (cette session)

- **Pas de recadrage avant upload** (photo de profil ET document de certification) — Android
  recadre via `CroperView` avant envoi, iOS envoie l'image choisie telle quelle (juste ré-encodée en
  JPEG). Assumé : l'avatar est affiché en cercle recadré côté client de toute façon.
- **2 bugs "double slash" Android (BunnyCDN) corrigés, pas reproduits** — jugés accidentels
  (incohérents entre 2 fonctions), contrairement à `MyMediaType.IMAGE` (`.webp`/`image/jpeg`
  incohérent mais VOLONTAIRE et cohérent partout) qui LUI est reproduit à l'identique.
  Règle appliquée : un bug qui diverge entre 2 chemins de code n'est pas une "décision produit" à
  respecter ; une constante bizarre mais utilisée uniformément partout l'est.
- **Miniature vidéo chat générée réellement côté iOS** (`AVAssetImageGenerator`) alors qu'Android a
  ce code commenté/mort à cet endroit précis — sans génération réelle, l'upload de la miniature
  (`uploadMediaAndThumbnail`, qui suppose un `thumbnailUri` non nul) aurait été cassé même côté
  Android. Reproduit le comportement INTENTIONNEL (upload média+miniature), pas le bug qui l'entoure.
- **Bouton d'attache pièce jointe chat** : emplacement exact non identifiable dans les 3080 lignes
  déjà lues de `ChatFragmentTest.java` (probablement dans un layout XML non fourni) — branché sur
  une icône trombone, cohérent avec d'autres points d'entrée déjà non localisés précisément dans ce
  même fichier (bouton d'appel, Shareboard).
- **`CertificationPlanFragment.tarification()` (re-fetch réseau du prix) PAS porté** — redondant
  avec la valeur déjà disponible via Remote Config (`certificationPrice`), jugé hors périmètre
  strict de GAP-004 (transfert de fichier).
- **Feed reconstruit : grille = écran principal, pager plein écran = écran de détail** — pas une
  invention, port fidèle de `MainFragment.OnAdapterItemClicked` (Android ouvre RÉELLEMENT ce même
  pager plein écran, mais SEULEMENT au tap sur une cellule de la grille, jamais comme écran
  d'accueil). Le pager iOS pré-existant n'était donc pas à jeter, juste mal positionné dans la
  hiérarchie d'écrans — code réutilisé presque intégralement (`FeedDetailPagerView`).
- **Bannières décoratives du Home (carrousel Créateurs, promo pièces gratuites) volontairement PAS
  reproduites** dans la reconstruction de la grille — visibles sur les captures Android fournies,
  mais hors du périmètre strict du problème rapporté ("données absentes"/"pas en grille de 2"), pas
  un oubli. `CreatorOfWeekView.swift`/`EarnCoinsView.swift` existent déjà comme écrans séparés,
  pourraient alimenter une version compacte de ces bannières dans une passe dédiée.
- **`AuthSessionPersistence.saveSession` séparé de `persist`** plutôt que de faire attendre tout
  `persist` (Core Data + jeton push) avant de naviguer — seule la ligne qui affecte réellement le
  premier rendu de Profile/Feed (`UserSession.shared.myId`) est rendue bloquante ; le reste continue
  en tâche de fond sans retarder la navigation.

## 10. PROCHAINE TÂCHE EXACTE

**RÈGLE ABSOLUE ADOPTÉE AU 11ᵉ TOUR (2026-08-16), remplace toute lecture antérieure de "COMPLETE"
dans ce document et dans `MIGRATION_AUDIT.md` pour Feed/Profile/Chat/Galerie-publication** :
l'utilisateur a fait son PREMIER test Appetize GLOBAL sur le code jusqu'à `68fd1d3` et a trouvé que
Home/Feed, Profile et la publication Galerie — TOUS précédemment marqués COMPLETE parce qu'ils
compilaient — ne fonctionnaient PAS réellement à l'usage. Désormais : **"le fichier existe" et "le
build est SUCCESS" NE SONT PLUS des preuves suffisantes de COMPLETE.** Une fonctionnalité est
COMPLETE seulement si : code présent + compile + chemin UI accessible + comportement fonctionnel +
comparable à Android + aucun blocage évident. Documenter séparément désormais : **COMPILED** /
**FUNCTIONALLY VERIFIED** / **UI VERIFIED AGAINST ANDROID** — ne jamais fusionner les trois. Voir
section 11quater pour le détail complet de ce tour.

**Instruction explicite et répétée de l'utilisateur (8ᵉ à 11ᵉ tour, 2026-08-16) : NE PAS
s'arrêter, NE PAS demander/attendre de test Appetize — UN SEUL nouveau test global prévu APRÈS ce
lot de corrections, quota limité.** Cette règle reste valable pour la prochaine session tant que
l'utilisateur ne dit pas explicitement le contraire.

**État réel après le 10ᵉ tour** — voir `MIGRATION_PROGRESS.md` (entrée "SESSION DU 2026-08-16, 10ᵉ
tour") et `MIGRATION_AUDIT.md` (section "SESSION DU 2026-08-16 (10ᵉ tour)") pour le détail complet.
Résumé : le 10ᵉ tour a repris la liste de priorités EXPLICITE et RÉPÉTÉE de l'utilisateur (ANIMEMS →
GALERIE → CHAT → WEBRTC → FEED → PROFILE → SEARCH → AUDIT GLOBAL) avec 3 audits dédiés en parallèle
(Home/Feed, Navigation+Permissions, Chat+dead-code, puis Auth/session) qui ont trouvé et fait
corriger **3 vrais gaps fonctionnels réels**, en plus de traiter la tâche #49 :
- **Animems — modèles de mouvement COMMUNAUTAIRES (parcourir/télécharger/appliquer)** : COMPLETE
  (tâche #49 close). Audit dédié call-chain a confirmé la moitié "browse" RÉELLE et accessible côté
  Android (`btn_display_online_template`), contrairement à la moitié "upload" (bouton commenté dans
  le source Android lui-même, code mort, NON porté). **Limitation de fidélité documentée, pas un
  bug** : le fichier `.tmpl` téléchargé est une sérialisation Java sans équivalent Swift décodable —
  reproduit le repli `rebuildFromRemote` d'Android (métadonnées seules, sans pistes de mouvement).
  Commit `adf9564`.
- **Feed — like/commentaire/partage/suppression/ne-plus-suivre/blocage/signalement** : COMPLETE
  (nouveau — un audit dédié a trouvé ces 7 actions ENTIÈREMENT absentes côté iOS malgré des endpoints
  déjà identifiables). `FeedGridCell`/`FeedDetailCell` ont maintenant de vrais boutons, `FeedView`
  gère le menu "...", les motifs de signalement, et la confirmation de blocage. Commit `16c1fbd`.
- **Chat — suppression "pour tout le monde"** : COMPLETE (nouveau — `deleteSelectedForEveryone()`
  était entièrement câblé côté ViewModel/Repository mais SANS AUCUN point d'entrée UI). Commit
  `16c1fbd`.
- **Firebase/Analytics — crash reporting (Crashlytics)** : COMPLETE (nouveau — Android a le plugin
  `com.google.firebase.crashlytics` réellement actif, zéro appelant manuel donc zéro logique à
  porter, seulement une dépendance manquante côté iOS). Commit `6014cc6`. **Limite assumée** : pas de
  script d'upload dSYM (symbolication) ajouté, risque jugé disproportionné sans environnement Xcode
  local pour le vérifier — collecte de crash fonctionnelle dès ce commit, lisibilité des stack traces
  un suivi possible.
- **Auth/session — purge locale à la déconnexion/suppression de compte** : COMPLETE (nouveau — un
  audit dédié a trouvé qu'Android purge TOUT le cache local ContentResolver (messages/roster/
  notifications/etc.) à la fois pour "logout" ET "deleteaccount" (même méthode partagée côté
  Android), alors qu'iOS ne vidait que les identifiants de session. Risque réel sur appareil
  partagé : les données du compte précédent restaient lisibles). Nouveau `LocalDataPurger.swift`.
  Commit `68fd1d3`.
- **Navigation globale + Permissions** : audités, COMPLETE à une exception près déjà documentée par
  une session antérieure (invitation d'amis via les contacts du téléphone — `RosterListView.swift`
  en-tête, descope volontaire aux côtés de la suppression multi-sélection et des mises à jour roster
  en direct). Pas retraité ce tour : périmètre comparable à une fonctionnalité séparée (accès
  contacts + flux d'invitation SMS/lien), décision déjà actée plutôt que réouverte sans signal fort.
- **Home/Feed (grille/pager/pagination)** : audité, structure déjà COMPLETE (confirmé par lecture
  fraîche de `MainFragment.java`/`FeedFragment.java` — grille 2 colonnes réelle, pager plein écran
  vertical réel) — seules les ACTIONS de post manquaient (voir ci-dessus).
- **Chat — pagination/read-receipts** : audités, reconfirmés COMPLETE (déjà réel des deux côtés).

**Tâche exacte pour la suite (mise à jour 11ᵉ tour)** :
1. **ATTENDRE les captures Android promises par l'utilisateur avant de toucher à l'UI Animems ou à
   toute autre UI nécessitant une comparaison visuelle** — instruction explicite, ne pas anticiper.
2. **Le bouton "créer un groupe" (Chat/Roster) reste NON RÉSOLU** — relu ligne par ligne
   (`RosterListView.swift`), présent et correctement câblé vers `ContactPickerView`, AUCUN bug
   statique trouvé. Log de diagnostic ajouté (`ROSTER: refresh() started/rosterAll() returned N
   rows`). Si le bouton manque toujours au prochain test réel, il faudra soit une capture d'écran
   exacte du problème, soit un accès Xcode/simulateur réel pour observer le rendu — la lecture de
   code seule a atteint sa limite ici.
3. **Rien de ce tour (`b485f34`) n'a encore été revérifié fonctionnellement** — seule la compilation
   est confirmée (voir section 0). Les logs de diagnostic ajoutés (préfixes `SESSION:`/`PROFILE
   REQUEST:`/`PROFILE RESPONSE:`/`FEED REQUEST:`/`FEED RESPONSE:`/`FEED UI:`/`PUBLISH REQUEST:`/
   `PUBLISH RESPONSE:`/`GROUP CREATE REQUEST:`/`GROUP CREATE RESPONSE:`/`ROSTER:`) sont TEMPORAIRES —
   à lire lors du prochain test Appetize pour confirmer les causes racines, puis à retirer une fois
   confirmées (ne pas les laisser indéfiniment en production).
4. **Ne PAS redemander de test Appetize avant que l'utilisateur en fasse un lui-même** — quota
   limité, un seul test global prévu, consigne explicite et répétée.
5. **Demander le retour Codemagic manuel** — toujours en attente depuis GAP-004, jamais rapporté
   pour AUCUN commit à ce jour.
6. Invitation d'amis par contacts téléphone : toujours descopée par choix (voir section 10 du tour
   précédent), pas retraitée.

## 11. HANDOFF — DERNIÈRE SESSION

**Session :** Claude Code (Sonnet 5), continuation autonome sans mémoire de session précédente,
contexte reconstruit depuis Git + documentation existante. 8ᵉ tour, 2026-08-16.
**Date :** 2026-08-16
**Dernière tâche terminée :** Cycle complet de continuation demandé explicitement par l'utilisateur
("CONTINUE LA MIGRATION... NE T'ARRÊTE PAS AVANT D'AVOIR TRAITÉ TOUT CE QUI EST RÉALISABLE") couvrant
Animems (priorité principale), Galerie, Chat, WebRTC, Feed, Profile, Search, et un audit transversal.
Voir section 10 ci-dessus pour le détail COMPLETE/PARTIAL/MISSING par fonctionnalité, et
`MIGRATION_PROGRESS.md` (entrée 8ᵉ tour) pour le récit complet.
**Travail effectué (tour 8), dans l'ordre chronologique réel :**
- Repris exactement où le tour 7 s'était arrêté : fix du geste Animems cassé (`AnimemesEditorView`
  référençait une méthode `moveObject` déjà supprimée de `AnimemesEditorState` — corrigé en premier,
  avant tout nouveau travail), gestes translation/rotation/échelle réels câblés via
  `AnimemesGestureController` (déjà porté, jamais utilisé), fix bug sélection (le calque sélectionné
  restait bloqué après le premier toucher).
- Fix bug WebRTC réel trouvé en fin de tour précédent : `makingOffer` jamais réinitialisé après
  échec `setRemoteDescription` (`RTConnection2.onSetFailure` non reproduit).
- Batch de 5 audits dédiés en parallèle (Socket.IO Chat, MediaEditor Galerie, WebRTC/CallKit complet,
  Profile complet, Search complet) — 2 premières tentatives ont échoué avec une erreur API
  transitoire, relancées avec succès.
- Galerie : freeform crop + suppression arrière-plan (composants déjà portés, jamais câblés) +
  flip + peinture/texte (nouveau `PhotoToolsView.swift`) + miniature/durée vidéo réelles + limite
  légende + partage natif.
- Native ads câblées dans le pager Feed (pas la grille — vérifié contre le code Android réel avant
  de choisir l'emplacement).
- Search : navigation hashtag/publication + bouton Suivre + états erreur/vide.
- WebRTC : 2 corrections réelles trouvées par l'audit (config audio session + permission micro).
- **Animems, le morceau principal** : lecture complète de `AnimemesCompound.java` (3947 lignes) +
  `TimelineView.java` (1320 lignes) a révélé que le moteur (timeline/keyframes/masques) était déjà
  porté à ~95% lors d'une session antérieure mais jamais câblé à l'éditeur. Câblage complet :
  `TimelineView.swift` (nouveau, rendu `Canvas` + geste unique multi-mode), enregistrement de
  keyframes explicite (bouton ◆), lecture/pause réelle (`AnimationEngine`/`CADisplayLink`), panneau
  + geste de masque.
- **4 tentatives de build CI pour le seul lot Animems** avant succès — voir section 0 pour le détail
  exact de chaque échec/diagnostic. Aucune ne pouvait être anticipée sans environnement macOS ; toutes
  diagnostiquées à partir du VRAI log `xcodebuild`, jamais devinées.
- Après le lot principal (build vert), deux compléments ajoutés et validés séparément : sauvegarde
  image statique Animems (`hasAnimation`/`exportStaticImage`, commit `70692d5`, SUCCESS) et
  recadrage temporel vidéo Galerie (`MediaTrimView.swift` nouveau, commit `ef3a34b`, SUCCESS).
- Documentation (ce fichier + `MIGRATION_PROGRESS.md` + `MIGRATION_AUDIT.md`) mise à jour en fin de
  tour avec les deux compléments inclus.
**Travail actuellement en cours :** Aucun code en cours — dernier commit (`ef3a34b`) confirmé
SUCCESS. Mise à jour de documentation en cours de finalisation, reste à committer avec ce fichier.
**PROCHAINE TÂCHE EXACTE :** Voir section 10 ci-dessus — modèles de mouvement/export GIF (Animems),
stickers (Galerie), audit des modules non encore couverts (paiements/deep links/Firebase-analytics).
**Fichiers modifiés :** Voir `MIGRATION_PROGRESS.md` (entrée 8ᵉ tour) pour la liste complète —
volume trop important pour être dupliqué ici sans risque de désynchronisation. Tout le code
applicatif de ce tour est commité et poussé (8 commits, `d19e372`…`e4b347a`) ; seule la documentation
de ce tour reste à committer.
**Fichiers à surveiller :** aucun changement externe détecté ce tour (contrairement au tour 7 où un
worktree Android parallèle était en cours) — à revérifier via `git status`/`git log` en début de
prochaine session, ne jamais supposer.
**Bugs connus :** Aucun bug de compilation à ce jour (dernier run SUCCESS). Deux VRAIS bugs
fonctionnels trouvés ET corrigés ce tour (glare WebRTC `makingOffer`, config audio session absente).
Un potentiel troisième sujet non résolu : la lenteur/l'instabilité du téléchargement des logs
`xcodebuild` complets via l'API GitHub Actions pour ce projet (jamais un problème de fond côté code,
juste un frein opérationnel à connaître pour la prochaine session — voir section 10, point 5).
**Tests effectués :** Compilation CI réelle réussie pour tout le lot du tour (GitHub Actions,
`e4b347a`, SUCCESS confirmé via l'API, pas seulement supposé). **AUCUN test fonctionnel réel
(Appetize)** — conforme à la consigne explicite et répétée de l'utilisateur ce tour.
**Résultats :** Animems/Galerie/Chat/WebRTC/Feed/Profile/Search tous avancés d'un cran réel (voir
section 10 pour le détail COMPLETE/PARTIAL/MISSING). Niveau "compile réellement" atteint pour tout
le lot (GitHub Actions SUCCESS). Codemagic toujours jamais rapporté. Test fonctionnel réel toujours
non fait — reste le seul niveau de validation manquant, sur décision explicite de l'utilisateur de
le reporter à la fin d'un cycle plus complet.
**Décisions techniques :** Voir section 9 (décisions antérieures, toujours valables) +
`MIGRATION_PROGRESS.md` entrée 8ᵉ tour pour les décisions de ce tour (piste-par-calque simplifiée
pour la timeline, pas de re-bake keyframes pour l'aperçu live vs export, gestes fusionnés en un seul
jeu plutôt que deux graphes typés différemment, etc. — chacune documentée avec sa justification dans
le code source directement, pas seulement ici).
**Points importants pour la prochaine session :**
- Ne PAS refaire les audits déjà faits ce tour (Socket.IO Chat, MediaEditor Galerie, WebRTC/CallKit,
  Profile, Search) — tous documentés en détail dans `MIGRATION_PROGRESS.md`, resultats fiables.
- Ne PAS supposer qu'un geste/timeline/masque Animems fonctionne VISUELLEMENT correctement — seule
  la compilation est confirmée, comme toujours dans cette mission tant qu'Appetize n'a pas tourné.
- **Si un nouveau lot de Swift touche des `Gesture`/`SimultaneousGesture`/`AnyGesture` composés en
  plusieurs variantes choisies dynamiquement, éviter d'emblée le pattern "deux `some Gesture`
  différentes + ternaire + `AnyGesture`"** — préférer un seul jeu de gestes avec bascule d'état À
  L'EXÉCUTION dans les handlers (voir `AnimemesEditorView.swift`, section geste, et son commentaire
  de tête qui documente l'historique complet de cet écueil). Coût réel ce tour : 4 builds CI, ~1h de
  cycles diagnostic/fix sans environnement macOS local pour vérifier.
- Ne JAMAIS déclencher Codemagic soi-même sans credential réel — l'utilisateur le fait manuellement.
- Tout le code est commité/poussé ; seule la documentation de ce tour reste à committer.
**Instructions pour la prochaine session (valables pour le tour 8, voir mise à jour tour 9
ci-dessous) :**
1. Lire ce fichier EN PREMIER, section 0 (CI) et 10 (prochaine tâche) en priorité absolue.
2. Vérifier qu'il correspond toujours au code réel (`git log`, `git status`) — une autre session a
   pu intervenir/pousser depuis.
3. Continuer directement les points listés en section 10 SANS demander confirmation ni test Appetize,
   sauf si l'utilisateur donne une instruction contraire explicite dans le nouveau message reçu.
4. Mettre à jour ce fichier (sections 0 et 11 au minimum) à la fin de la session, quel que soit le
   résultat.

---

## 11bis. HANDOFF — 9ᵉ TOUR (2026-08-16, suite directe du 8ᵉ tour)

**Session :** Claude Code (Sonnet 5), continuation directe (même session logique que le tour 8,
reprise après compaction du contexte) sur instruction explicite de l'utilisateur listant un ORDRE DE
PRIORITÉ précis : ANIMEMS → GALERIE → PAYMENTS/MONÉTISATION → DEEP LINKS → FIREBASE/ANALYTICS →
AUDIT TRANSVERSAL FINAL, avec consigne explicite de travailler "EN GROS LOTS" et de ne jamais
s'arrêter après un build vert.
**Travail effectué, dans l'ordre chronologique réel :**
- **Animems — modèles de mouvement locaux** : `MotionTemplateManager.java` (551 lignes) lu en
  entier avant tout code. Port fidèle : `MotionTemplate.swift`/`MotionTemplateManager.swift`/
  `MotionTemplateGalleryView.swift` (nouveaux), extraction/application normalisée par taille de
  canevas, reconstruction de masque auto-frame par composition de matrice `postScale`/`postRotate`/
  `postTranslate` (même idiome que `AnimemesGestureController`, déjà dans le projet). Fidélité
  délibérée : la non-reconstruction des keyframes de matrice au chargement (absent du switch Android
  `apply()`) est reproduite telle quelle, pas "corrigée". UI intégrée à `AnimemesEditorView.swift`
  (galerie de modèles, sauver-comme-modèle). Commit `ac67c79`, run `31935598442` **SUCCESS** (premier
  coup, aucun échec).
- **Galerie — stickers/emoji** : audit dédié a confirmé qu'Android utilise son propre clavier emoji
  Unicode standard (`com.vanniktech.emoji.EmojiView`), pas un catalogue custom — porté via le clavier
  emoji natif iOS (`TextField`) dans `PhotoToolsView.swift`, `PlacedText.isSticker` avec rendu 64pt
  non teinté.
- **Deep links** : audit dédié a trouvé un GAP RÉEL total (zéro schéma déclaré, zéro `.onOpenURL`,
  zéro routage côté iOS avant ce tour). `AndroidManifest.xml` (intent-filters) + `ShareActivity.java`
  lignes ~130-340 (`processUri`/`processUrl`/`getGroup`/`getUser`/`getPost`/`joinGroup`) lus en
  entier. Porté : `DeepLinkRouter.swift` (nouveau), extension de `DeepLinkCenter.swift`
  (`DeepLinkDestination`), montage `.onOpenURL` dans `RootRouterView.swift` (avant authentification,
  pour capter le parrainage dès l'inscription), présentations dans `HomeShellView.swift`,
  `CFBundleURLTypes` dans `project.yml` (schémas `myapp` et `tiinver`). Nouveaux endpoints :
  `ProfileRepository.fetchUser(byUsername:)`, `FeedRepository.fetchPost(byToken:)`,
  `GroupRepository.fetchGroup(token:myId:)` — chacun vérifié séparément pour la forme réelle de sa
  réponse (`userData` est un objet imbriqué sur `getuserbyid` mais une CHAÎNE JSON-encodée sur
  `getuser/{username}`, deux endpoints différents, jamais supposés identiques). A fermé une vraie
  lacune trouvée en passant : `REFERRED_BY` (`UserDefaults`) était déjà LU par `RegisterView.swift`/
  `SignUpWithGoogleView.swift` depuis une session antérieure mais jamais ÉCRIT nulle part avant ce
  tour. Commit `f2012a1`, run `31936056808` **SUCCESS** (premier coup, aucun échec).
- **Payments/Monétisation, Firebase/Analytics** : audités dédiés, aucun gap réel au-delà de ce qui
  était déjà connu/documenté (GAP-007 pour les paiements) — aucune implémentation nécessaire,
  conforme à la consigne explicite de ne pas dupliquer de code inutile.
- **Audit transversal final** : repasse dédiée (TODO/FIXME/placeholder/stub/mock/`fatalError`/
  fonctions vides/boutons morts/`NavigationLink` sans destination/API inutilisée/Repository
  déconnecté/ViewModel inutilisé/données codées en dur) — aucune nouvelle trouvaille actionnable au
  delà de la tâche #49 déjà identifiée.
- **Modèles de mouvement communautaires (upload/parcourir)** : évalué et EXPLICITEMENT DIFFÉRÉ
  (tâche #49) — périmètre comparable à un portage de fonctionnalité séparée entière (upload
  BunnyCDN, endpoints backend dédiés, galerie communautaire paginée avec aperçu audio, flux
  télécharger-puis-appliquer). Décision documentée plutôt que travail bâclé en fin de liste.
- Documentation (ce fichier + `MIGRATION_PROGRESS.md` + `MIGRATION_AUDIT.md`) mise à jour en fin de
  tour pour refléter `ac67c79` et `f2012a1`.
**Travail actuellement en cours :** Aucun code en cours — dernier commit (`f2012a1`) confirmé
SUCCESS par GitHub Actions. Mise à jour de documentation en cours de finalisation, reste à committer.
**PROCHAINE TÂCHE EXACTE :** Voir section 10 ci-dessus — la liste de priorités explicite de
l'utilisateur est désormais entièrement traitée ; il ne reste plus de gap réalisable en attente
autre que la tâche #49 (différée par choix, pas par oubli). Le rapport final unique demandé par
l'utilisateur est désormais approprié à produire.
**Fichiers modifiés :** Voir `MIGRATION_PROGRESS.md` (entrée 9ᵉ tour) pour la liste complète. Tout le
code applicatif de ce tour est commité et poussé (`ac67c79`, `f2012a1`) ; seule la documentation
reste à committer avec ce fichier.
**Bugs connus :** Aucun bug de compilation (les deux runs CI de ce tour ont réussi du premier coup,
contrairement au lot Animems timeline/masques du tour 8 qui avait nécessité 4 tentatives). Aucun
nouveau bug fonctionnel trouvé par les audits Payments/Firebase/transversal.
**Tests effectués :** Compilation CI réelle réussie pour les deux commits de ce tour (GitHub Actions,
`31935598442` et `31936056808`, SUCCESS confirmés via l'API). **AUCUN test fonctionnel réel
(Appetize)** — conforme à la consigne explicite et répétée de l'utilisateur, "APPETIZE EST INTERDIT
POUR L'INSTANT" tant que le rapport final n'a pas été produit et validé par l'utilisateur.
**Point de sécurité traité ce tour** : une notification de tâche en arrière-plan inconnue
(`bjyot2t0x`, "rechercher un token Codemagic") non issue par cette session a été explicitement
signalée à l'utilisateur avant toute action, conformément aux règles de sécurité de la mission —
l'utilisateur a confirmé de l'ignorer complètement, résolu.
**Instructions pour la prochaine session :**
1. Lire ce fichier EN PREMIER (section 0 pour le CI, cette section 11bis pour l'état le plus récent),
   puis `MIGRATION_AUDIT.md` (section "SESSION DU 2026-08-16, 9ᵉ tour") et `MIGRATION_PROGRESS.md`
   (entrée 9ᵉ tour).
2. Vérifier qu'il correspond toujours au code réel (`git log`, `git status`) avant toute action.
3. S'il ne reste vraiment plus de gap réalisable listé nulle part, ne PAS inventer de travail — soit
   proposer/produire le rapport final demandé par l'utilisateur, soit attendre une nouvelle
   instruction. Ne PAS lancer Appetize ni Codemagic soi-même.
4. Si l'utilisateur redemande explicitement la tâche #49 (modèles de mouvement communautaires), la
   traiter comme un chantier à part entière (lire d'abord le code Android d'upload/liste avant
   d'écrire quoi que ce soit), pas comme un ajout rapide.

---

## 11ter. HANDOFF — 10ᵉ TOUR (2026-08-16, suite directe du 9ᵉ tour)

**Session :** Claude Code (Sonnet 5), continuation directe (même session logique, reprise après
compaction du contexte) sur une nouvelle instruction explicite de l'utilisateur reprenant l'ordre de
priorité complet (ANIMEMS → GALERIE → CHAT → WEBRTC → FEED → PROFILE → SEARCH → AUDIT GLOBAL) avec
une checklist de 18 domaines à vérifier "comportement par comportement", PAS en se fiant à un ancien
rapport.
**Travail effectué, dans l'ordre chronologique réel :**
- **Phase A/B/C/D** : relu l'état Git réel avant toute décision (conforme à la consigne explicite de
  l'utilisateur), puis audité en détail la fonctionnalité MISSING explicitement désignée (modèles de
  mouvement communautaires Animems). Un agent dédié a tracé la vraie chaîne d'appel (pas juste les
  noms de classes) et a trouvé un résultat scindé : la moitié "parcourir/télécharger/appliquer" est
  RÉELLE et accessible (`btn_display_online_template` → `MemesFragment.showCommunityTemplates` →
  `CommunityTemplateGalleryView.java`, lu en entier), la moitié "publier/upload" est CODE MORT
  (bouton `AnimemesActionSheet` entièrement commenté dans le source Android). Porté fidèlement :
  `TemplateRemoteModel.swift`/`CommunityTemplateRepository.swift`/`CommunityTemplateGalleryView.swift`
  (nouveaux), avec une note de fidélité importante sur l'incompatibilité de format binaire
  `.tmpl` (sérialisation Java, aucun équivalent Swift décodable — repli `rebuildFromRemote`
  systématique, PAS un bug). Commit `adf9564`, run `31938768739` **SUCCESS** (premier coup).
- **Phase F/G** : 3 audits dédiés lancés EN PARALLÈLE (Home/Feed profond, Navigation+Permissions,
  Chat+sweep dead-code frais) puis un 4ᵉ (Auth/session) — tous avec instruction explicite de tracer
  les VRAIS chemins d'appel, pas de deviner depuis les noms. Résultats :
  - **Home/Feed** : structure (grille 2 colonnes/pager vertical/pagination) confirmée déjà réelle
    des deux côtés, MAIS les 7 actions de post (`OnLikeClicked`/`OnclickCommentaire`/`OnclickPrtg`/
    `OnclickMoreExpand` → delete/copy-link/unfollow/block/report) étaient ENTIÈREMENT absentes côté
    iOS malgré des endpoints déjà identifiables. Le plus gros morceau de code de ce tour :
    `FeedRepository.swift` (+`reaction`/`deleteActivity`/`reportUser`), `FeedViewModel.swift`
    (+7 méthodes d'action, persistance des posts masqués via `UserDefaults`), `FeedView.swift`
    (boutons réels sur `FeedGridCell`/`FeedDetailCell`, menu "...", dialogue de motifs de
    signalement, confirmation de blocage). `FeedDetailPagerView` restructuré pour partager le MÊME
    `FeedViewModel` que la grille (`@StateObject(wrappedValue:)`, piège `@ObservedObject`+init
    identifié et évité — recréerait un ViewModel à chaque re-rendu du parent).
  - **Navigation + Permissions** : COMPLETE, un seul gap réel confirmé (invitation d'amis par
    contacts téléphone) — DÉJÀ documenté comme descope volontaire par une session antérieure
    (`RosterListView.swift`), pas un oubli de ce tour, non retraité.
  - **Chat + dead-code** : sweep frais n'a rien trouvé de nouveau, MAIS a trouvé que
    `deleteSelectedForEveryone()` (suppression visible par le correspondant) était entièrement câblé
    côté ViewModel/Repository SANS AUCUN point d'entrée UI (le bouton corbeille n'appelait que
    `deleteSelectedForMe()`). Fixé dans `ChatView.swift` avec un dialogue à 2 choix.
  - **Auth/session** : COMPLETE sur les 5 premiers points (login/inscription/Google/mot de passe
    oublié/persistance de session), MAIS a trouvé qu'Android route "logout" ET "deleteaccount" vers
    la MÊME méthode qui purge tout le cache local (messages/roster/notifications), alors qu'iOS ne
    videait que les identifiants de session — risque réel sur appareil partagé. Fixé avec un nouveau
    `LocalDataPurger.swift` (purge `ActivityEntity`/`RosterEntity`/`MessageEntity`+
    `GroupMessageEntity`/`NotiEntity` en parallèle via `async let`), appelé depuis
    `SettingSubViews.logout()`/`deleteAccount()`.
  - Ces deux derniers correctifs (Chat + Auth) commités ensemble avec les actions Feed :
    commit `16c1fbd`, run `31939406542` **SUCCESS** (premier coup) pour Feed+Chat ;
    commit `68fd1d3` pour la purge Auth/session, run `31940076878` **SUCCESS** (premier coup).
- **Complément trouvé en passant** : Android a le plugin `com.google.firebase.crashlytics`
  réellement actif (pas du code mort — vérifié dans `app/build.gradle`) avec ZÉRO appelant manuel
  dans tout le code source (collecte 100% automatique). iOS n'avait aucune dépendance Crashlytics.
  Ajouté (`project.yml`, produit SPM `FirebaseCrashlytics`) — aucun code applicatif nécessaire,
  `FirebaseApp.configure()` déjà appelé suffit à activer la collecte. Script d'upload dSYM
  délibérément PAS ajouté (risque jugé disproportionné sans environnement Xcode local pour le
  vérifier, historique documenté de fragilité `postBuildScripts`/`resources:` XcodeGen sur ce projet
  précis — voir `GoogleService-Info.plist`). Commit `6014cc6`, run `31939780419` **SUCCESS**.
**Travail actuellement en cours :** Aucun — tous les commits de ce tour sont poussés ET confirmés
`SUCCESS` (`adf9564`/`16c1fbd`/`6014cc6`/`68fd1d3`).
**PROCHAINE TÂCHE EXACTE :** Voir section 10 — il ne reste plus de gap réalisable identifié par la
liste de priorités de l'utilisateur ni les 4 audits de ce tour, hormis l'invitation d'amis par
contacts (descope déjà acté). Le rapport final unique devient approprié.
**Fichiers modifiés :** Voir `MIGRATION_PROGRESS.md` (entrée 10ᵉ tour) pour la liste complète. Tout
le code applicatif est commité et poussé (`adf9564`, `16c1fbd`, `6014cc6`, `68fd1d3`).
**Bugs connus :** Aucun bug de compilation — les 4 commits de ce tour sont tous confirmés `SUCCESS`.
Aucun nouveau bug fonctionnel introduit à ma connaissance — les 3 vrais gaps trouvés par les audits
(actions Feed, suppression Chat "pour tous", purge locale Auth) sont désormais fixés, pas de
régression identifiée dans le code existant qu'ils touchent.
**Tests effectués :** Compilation CI réelle réussie pour les 4 commits de ce tour (GitHub Actions,
SUCCESS confirmés via l'API pour `adf9564`/`16c1fbd`/`6014cc6`/`68fd1d3`). **AUCUN test fonctionnel
réel (Appetize)**
— conforme à la consigne explicite et répétée de l'utilisateur, "APPETIZE EST INTERDIT POUR
L'INSTANT" tant que le rapport final n'a pas été produit et validé par l'utilisateur. Les nouvelles
interactions Feed (like/comment/partage/suppression/etc.) et le menu Chat à 2 choix de suppression
n'ont donc PAS été vérifiés visuellement — seule la compilation est confirmée, comme pour tout le
reste de cette migration tant qu'Appetize n'a pas tourné.
**Instructions pour la prochaine session :**
1. Lire ce fichier EN PREMIER (section 0 pour le CI, cette section 11ter pour l'état le plus récent),
   puis `MIGRATION_AUDIT.md` (section "SESSION DU 2026-08-16, 10ᵉ tour") et `MIGRATION_PROGRESS.md`
   (entrée 10ᵉ tour).
2. Vérifier qu'il correspond toujours au code réel (`git log`, `git status`) avant toute action —
   en particulier confirmer le résultat du run `31940076878` s'il n'était pas encore connu à la fin
   de ce tour.
3. S'il ne reste vraiment plus de gap réalisable listé nulle part, ne PAS inventer de travail — soit
   proposer/produire le rapport final demandé par l'utilisateur, soit attendre une nouvelle
   instruction. Ne PAS lancer Appetize ni Codemagic soi-même.
4. Si l'utilisateur redemande explicitement l'invitation d'amis par contacts téléphone, lire
   `RosterListAdapter.java:206-212`/`Invite.java` avant d'écrire quoi que ce soit —
   `NSContactsUsageDescription` est déjà déclaré dans `project.yml` (orphelin pour l'instant), prêt à
   servir.

---

## 11quater. HANDOFF — 11ᵉ TOUR (2026-08-16) — PREMIER TEST APPETIZE RÉEL, CORRECTIFS P0

**Session :** Claude Code (Sonnet 5), continuation directe (même session logique, reprise après
compaction du contexte). **Changement de nature du tour** : ce n'est plus un audit de couverture
fonctionnelle mais la correction de bugs RÉELS trouvés par le PREMIER test Appetize global de
l'utilisateur sur le code du 10ᵉ tour — la phase "audit + implémentation de features" cède la place
à une phase "diagnostic + correction de bugs runtime". L'utilisateur a explicitement retiré la
confiance accordée à "ça compile" comme preuve de fonctionnement (voir section 10, règle absolue).

**Contexte reçu de l'utilisateur** : Codemagic ET GitHub Actions compilent avec succès (déjà su),
MAIS le test Appetize réel montre 3 problèmes CRITIQUES (Home/Feed sans données malgré la grille 2
colonnes déjà présente, Profile complètement vide, publication Galerie qui ne fait "rien" au clic)
+ 1 problème P0 non résolu depuis un tour antérieur (bouton créer-groupe Chat absent malgré un code
déjà écrit) + Animems à comparer visuellement à des captures Android à venir (PAS encore reçues —
consigne explicite de ne PAS toucher l'UI Animems avant leur réception).

**Travail effectué, dans l'ordre chronologique réel :**
1. **Traçabilité complète Session → Feed** (Android : login/session → userId → endpoint →
   paramètres → réponse → parsing → repository → ViewModel → UI ; même chaîne côté Swift) :
   - `LoginView.swift:132` : confirmé que `AuthSessionPersistence.saveSession(user)` (synchrone) est
     bien appelée AVANT `onLoginSuccess(user)` (navigation) — le correctif de race condition du
     2026-08-13 est toujours en place et correct. PAS de bug trouvé ici.
   - `RootRouterView.swift` : `UserSession.shared.cachedUser()` lu depuis `UserDefaults`/Keychain,
     synchrone, aucune dépendance réseau — restauration de session au lancement structurellement
     correcte. PAS de bug trouvé ici.
   - `FeedRepository.fetchTimeline()` : trouvé un risque réel non confirmé mais plausible — le
     `compactMap` de décodage `Codable` avalait silencieusement TOUT item dont le JSON ne
     correspondait pas exactement à `FeedActivity` (Swift `Codable` est strict, contrairement à
     Gson côté Android qui coerce plus librement), produisant un tableau final plus petit que le
     nombre RÉEL d'items reçus sans la moindre erreur visible. Rendu visible par un log dédié
     (`FEED RESPONSE: decode failure for one activity...`), PAS confirmé comme LA cause — log ajouté
     précisément pour trancher au prochain test réel plutôt que de deviner.
   - Logs `SESSION:`/`FEED REQUEST:`/`FEED RESPONSE:`/`FEED UI:` ajoutés dans
     `FeedViewModel.loadNextPage()`, format exact demandé par l'utilisateur.
2. **Profile — VRAI BUG TROUVÉ ET CORRIGÉ** : `ProfileViewModel.loadProfile()` appelait
   `try? await repository.fetchProfile(...)`, avalant SILENCIEUSEMENT toute erreur réseau/session.
   `ProfileView.header` ne rendait ALORS RIEN (ni spinner — `isLoadingProfile` déjà retombé à
   `false` — ni erreur — jamais renseignée — ni contenu — `profile` resté `nil`) : un écran
   blanc indiscernable d'un profil réellement vide. **C'est EXACTEMENT le bug déjà root-causé et
   corrigé pour `FeedViewModel` le 2026-08-13** (voir section 0, historique), mais ce correctif
   n'avait JAMAIS été porté à `ProfileViewModel`, qui a été écrit séparément. Corrigé : nouveau
   `@Published var errorMessage`, `try await` + `catch` explicite, `ProfileView.header` affiche
   maintenant un état d'erreur + bouton "Réessayer" (même pattern que `FeedView.emptyOrStatusState`).
   Logs `PROFILE REQUEST:`/`PROFILE RESPONSE:`/`PROFILE POSTS REQUEST:`/`PROFILE POSTS RESPONSE:`
   ajoutés.
3. **Galerie publication — VRAI BUG TROUVÉ ET CORRIGÉ** : `PublishComposeView.publish()` avait DEUX
   `guard ... else { return }` silencieux (`UserSession.shared.myId` nil, `croppedImage` nil) — dans
   les deux cas, taper "Publier" ne produit RIEN de visible (pas d'erreur, pas de fermeture d'écran,
   juste... rien), correspondance EXACTE avec le symptôme rapporté. Corrigé : les deux surfacent
   maintenant `errorText` (déjà affiché dans le formulaire, jamais branché à ces deux cas
   précédemment). Logs `PUBLISH REQUEST:`/`PUBLISH RESPONSE:` ajoutés, plus un log dédié dans
   `FeedRepository.publish()` pour capturer explicitement le statut/corps de réponse en cas
   d'échec réseau OU d'échec applicatif (`error`≠"false"), fidèle à l'interdiction explicite de
   laisser une erreur réseau invisible.
4. **Création de groupe — MÊME classe de bug trouvée et corrigée** : `GroupCreationView.create()`
   avait le même `guard let myId = ... else { return }` silencieux. Corrigé de la même façon.
5. **Bouton "créer un groupe" absent — NON RÉSOLU, investigation approfondie sans succès** :
   `RosterListView.swift` relu ligne par ligne — le bouton (`person.2.badge.plus`,
   `.navigationBarTrailing`, navigue vers `ContactPickerView`) est RÉELLEMENT présent, câblé
   correctement, et son `.toolbar` est appliqué EN DEHORS du `Group` conditionnel sur l'état des
   données (donc ne dépend pas de `rows`/`hasLoaded`). Aucune duplication de `RosterListView`
   trouvée dans le dépôt. Aucun bug statique identifiable par lecture de code. Log de diagnostic
   ajouté (`ROSTER: refresh() started/rosterAll() returned N rows`) pour au moins confirmer que
   l'écran est bien atteint au prochain test — mais si le bouton manque toujours malgré un code
   correct, la cause est probablement un problème de rendu propre au runtime/appareil, qui
   nécessitera soit une capture d'écran du problème exact, soit un accès direct à un environnement
   Xcode/simulateur pour être diagnostiqué au-delà de ce que la lecture de code permet.
6. **`SearchView.swift` revérifié** : déjà correctement instrumenté (états erreur/vide distincts)
   depuis une session antérieure — aucune action nécessaire.
7. **Animems : PAS touché**, conformément à l'instruction explicite d'attendre les captures Android.

**Commit unique de ce tour** : `b485f34` ("fix(profile,galerie,groups): surface silent errors, add
diagnostic logs"). Run GitHub Actions `31941895327` **SUCCESS**.

**COMPILED** (compile réellement, confirmé CI) : les 7 fichiers modifiés ce tour
(`ProfileViewModel.swift`, `ProfileView.swift`, `PublishComposeView.swift`, `FeedRepository.swift`,
`FeedViewModel.swift`, `GroupCreationView.swift`, `RosterListView.swift`).

**FUNCTIONALLY VERIFIED** (comportement réellement confirmé sur un run réel) : **AUCUN élément de ce
tour** — zéro test Appetize effectué sur ce commit, conforme à la consigne explicite de l'utilisateur
de n'en faire qu'un seul, à la fin de ce lot complet.

**UI VERIFIED AGAINST ANDROID** : **AUCUN élément de ce tour** — aucune capture Android fournie
encore, aucune modification visuelle faite (seule la logique d'affichage d'erreur a changé, pas la
mise en page).

**NOT FUNCTIONALLY VERIFIED, à confirmer au prochain test Appetize** :
- Le bug Profile est-il réellement résolu (l'erreur s'affiche-t-elle, ou le profil se charge-t-il
  enfin correctement) ?
- Le bug Galerie-publication est-il réellement résolu ?
- La cause RÉELLE du Home/Feed vide (les logs la révéleront — décodage silencieux ? réponse
  réellement vide ? autre chose ?).
- Le bouton créer-groupe Chat — toujours non expliqué.
- Toute la parité visuelle Animems — bloquée sur réception des captures.

**Instructions pour la prochaine session :**
1. Lire ce fichier EN PREMIER (section 0 + cette section 11quater), puis `MIGRATION_AUDIT.md`/
   `MIGRATION_PROGRESS.md` (entrées 11ᵉ tour).
2. Si l'utilisateur fournit un nouveau rapport Appetize (avec ou sans logs de diagnostic copiés/
   captures d'écran), l'utiliser comme SOURCE DE VÉRITÉ prioritaire sur toute supposition de ce
   document — les logs ajoutés ce tour sont faits pour être lus à ce moment précis.
3. Si les captures Android promises sont arrivées, ENFIN traiter Animems (et toute autre UI
   nécessitant une comparaison visuelle) — comparer systématiquement écran par écran, prioriser P0
   (écran/bouton/donnée/action absent) > P1 (mauvaise structure/composant) > P2 (détails visuels).
4. Ne pas déclencher Appetize soi-même, ne pas le redemander avant que l'utilisateur le fasse.
5. Une fois les logs de diagnostic ayant servi à confirmer une cause racine, penser à les retirer
   (ce sont des ajouts temporaires, documentés comme tels dans chaque fichier).

---

## 11quinquies. HANDOFF — 12ᵉ TOUR (2026-08-16) — "STOP" UTILISATEUR : LE TEST APPETIZE RÉEL A
## CONTREDIT "COMPLETE", DIAGNOSTIC RUNTIME PROFOND + INSTRUMENTATION VISIBLE À L'ÉCRAN

**Déclencheur** : l'utilisateur a testé un build Codemagic RÉEL sur Appetize (premier test après le
lot de reconstruction UI du tour précédent) et a explicitement REJETÉ toute conclusion "COMPLETE"
basée sur un build vert. Message "STOP" détaillé (voir citation complète en tête de fichier, section
CURRENT HANDOFF) exigeant une traçabilité runtime complète (pas des hypothèses) pour 3 bugs P0 :
Home/Feed vide, Profile vide, Animems canvas/transformations non fonctionnels — DANS CET ORDRE,
sans passer aux P1 avant que les causes racines des P0 soient identifiées ET corrigées, sans
redemander de test Appetize entre chaque petit correctif (quota limité).

**Travail effectué, dans l'ordre chronologique réel :**
1. **P0-1 (Home/Feed) — retraçage complet** : re-vérifié les 3 points d'entrée auth
   (`LoginView.swift`/`SignUpWithGoogleView.swift`/`EmailVerificationView.swift`) — le correctif de
   race condition du 2026-08-13 (`AuthSessionPersistence.saveSession()` synchrone avant navigation)
   est TOUJOURS en place et correct dans les 3. `UserSession.shared.myId` structurellement fiable
   (lecture `UserDefaults` synchrone). AUCUN nouveau bug statique trouvé au-delà de ce qui était déjà
   connu — la piste `Codable` strict avalant silencieusement des items reste une hypothèse PLAUSIBLE
   NON CONFIRMÉE.
2. **P0-2 (Profile) — VRAI mécanisme de bug trouvé et corrigé** : `ProfileView` construit son
   `@StateObject ProfileViewModel` via `ProfileView.init()` (sans argument), qui capture
   `UserSession.shared.myId ?? ""` **UNE SEULE FOIS** à la construction. Si cette vue est construite
   avant que la session soit pleinement peuplée (navigation qui suit immédiatement le login/lancement
   à froid), `userId` reste figé à `""` À VIE pour cette instance — l'endpoint devient
   `getuserbyid//{myId}` (double slash, `userId` vide), échec serveur quasi certain, écran
   indéfiniment vide. Corrigé : `ProfileViewModel.userId` passé de `let` à `private(set) var` +
   nouvelle méthode `healStaleUserIdIfNeeded()` (auto-guérison si `userId` vide mais
   `UserSession.shared.myId` disponible), appelée en tête de `loadProfile()`. **Ceci N'EST PAS
   confirmé comme LA cause exacte rapportée par l'utilisateur** — c'est un vrai mécanisme de bug
   plausible, corrigé par prudence, à confirmer/infirmer par le diagnostic à l'écran (point 4).
3. **P0-3 (Animems) — retraçage géométrique complet, aucun bug trouvé statiquement** : relu
   ligne à ligne `AnimemesGestureController.swift` (sélection/translation/rotation/échelle) contre la
   sémantique Android "post*" documentée (`postTranslate`/`postRotate`/`postScale`) — composition de
   matrices fidèle, ordre correct. `Transform.cgAffineTransform` (conversion d'ordre Android→Core
   Graphics) revérifiée, cohérente. `version += 1` → `.id(state.version)` confirme que le `Canvas`
   est bien forcé à se redessiner après chaque mutation. **Seul risque structurel NOUVEAU identifié
   (pas confirmé)** : la refonte visuelle du tour précédent a ajouté `zoomControls`/`rightToolbar`
   en overlay DANS LE MÊME `ZStack` que le `Canvas` récepteur de gestes — un changement structurel
   réel qui pourrait (sans certitude) intercepter des gestes selon le comportement runtime SwiftUI.
   Non modifié à cette étape (pas de preuve, seulement une hypothèse) — instrumenté à la place
   (point 4).
4. **Instrumentation visible À L'ÉCRAN pour les 3 P0** (nouveauté de ce tour : l'utilisateur n'a
   probablement PAS accès aux logs console Xcode depuis Appetize, donc tout `print()` seul est
   inutile pour le prochain test) :
   - `FeedRepository.fetchTimeline()` retourne désormais `TimelineResult { activities, receivedCount
     }` au lieu de `[FeedActivity]` seul — expose le nombre RÉEL d'items renvoyés par le serveur à
     côté du nombre décodés avec succès, fermant l'angle mort où un échec de décodage silencieux
     produisait "0 posts, aucune erreur" indiscernable d'un flux réellement vide.
     `FeedViewModel.diagnostics` (nouveau `@Published String`) accumule les mêmes lignes que les
     `print()` déjà en place (`SESSION:`/`FEED REQUEST:`/`FEED RESPONSE: server sent N activities, M
     decoded successfully [— K DROPPED BY DECODE FAILURE]`), rendu dans un panneau
     `ScrollView`+texte monospace sélectionnable dans `FeedView.emptyOrStatusState`.
   - `ProfileViewModel.diagnostics` (même motif) accumule `SESSION:`/`PROFILE REQUEST:`/`PROFILE
     RESPONSE:`, avec une ligne WARNING explicite si `userId` est vide malgré `myId` non-nil (preuve
     directe du mécanisme du point 2). `ProfileView` gagne un panneau diagnostic visible dans la
     branche d'erreur ET dans une nouvelle branche de repli (profil nil / pas de chargement / pas
     d'erreur — l'état auparavant silencieusement blanc).
   - `AnimemesEditorState.gestureDiagnostics` (nouveau `@Published String`) : chaque geste
     (`selectObject`/`dragMoved`/`dragEnded`/`rotationChanged`/`scaleChanged`) logue en temps réel ce
     qu'il a fait ou pourquoi il a été ignoré (aucune sélection, aucun `bound`, calque touché, valeurs
     de matrice résultantes). Affiché en HUD vert monospace sur fond noir
     (`gestureDiagnosticsHUD` dans `AnimemesEditorView`, entre la barre du haut et le canevas) —
     **c'est la preuve directe qui tranchera si les gestes sont seulement reçus mais n'affectent rien,
     ou pas reçus du tout, ou affectent un calque différent de celui rendu**.
5. **Tableaux de diagnostic produits** (`Étape | Android | iOS | Résultat réel | Preuve | Cause`,
   demande explicite de l'utilisateur) — présentés directement à l'utilisateur dans la conversation
   pour les 3 P0, pas dupliqués ici (voir transcript de session si besoin de les relire ; résumé :
   aucun bug statique NOUVEAU confirmé pour Feed/Animems au-delà de ce qui est listé ci-dessus, un
   vrai mécanisme de bug plausible corrigé pour Profile).

**Commits de ce tour** :
- `f634788` ("feat(animems,chat,profile,ui): rebuild toolbars/screens to match real Android
  screenshots") — travail de refonte UI du tour précédent, committé en DÉBUT de ce tour (n'était pas
  encore poussé). Run GitHub Actions **SUCCESS** (confirmé avant de continuer).
- `328f7ad` ("fix(profile): heal stale-captured userId; add on-screen runtime diagnostics for
  Feed/Profile/Animems P0s") — le travail de ce tour décrit ci-dessus. Run GitHub Actions
  `31951566226` **SUCCESS**.

**COMPILED** (confirmé CI, `31951566226`) : tous les fichiers touchés ce tour — `ProfileViewModel.swift`,
`ProfileView.swift`, `FeedRepository.swift`, `FeedViewModel.swift`, `FeedView.swift`,
`AnimemesEditorState.swift`, `AnimemesEditorView.swift`.

**FUNCTIONALLY VERIFIED** : **AUCUN** — pas de test Appetize effectué par cette session, conforme à
l'instruction explicite de l'utilisateur ("NE LANCE PAS APPETIZE APRÈS CHAQUE PETITE CORRECTION").

**Statuts imposés par l'utilisateur, à respecter jusqu'à preuve du contraire par un test réel** :
- HOME/FEED = CI VALIDATED, FUNCTIONALLY FAILED
- PROFILE = CI VALIDATED, FUNCTIONALLY FAILED
- ANIMEMS CANVAS/TRANSFORMATIONS = CI VALIDATED, FUNCTIONALLY FAILED

**Instructions pour la prochaine session :**
1. Lire ce fichier EN PREMIER (section CURRENT HANDOFF tout en haut + cette section 11quinquies),
   PUIS vérifier `git status`/`git log`/`git fetch origin main` avant toute action — l'autre session
   (GAP-018/GAP-011, fichiers listés dans CURRENT HANDOFF) a probablement continué depuis.
2. **NE PAS redéclarer Home/Feed, Profile ou Animems "COMPLETE"/"FUNCTIONALLY VALIDATED"** tant qu'un
   test Appetize réel sur le commit `328f7ad` (ou plus récent) ne le confirme pas explicitement.
3. **Dès que l'utilisateur fournit un nouveau rapport Appetize** (idéalement avec une capture des 3
   nouveaux panneaux/HUD de diagnostic ajoutés ce tour) : LIRE CES LOGS COMME SOURCE DE VÉRITÉ, PAS
   une hypothèse. Le panneau Feed dira si c'est un problème de décodage (N reçus ≠ M décodés) ou de
   requête (aucune réponse/erreur réseau) ou d'affichage. Le panneau Profile dira si le mécanisme du
   point 2 était LA cause (ligne WARNING présente) ou autre chose. Le HUD Animems dira si les gestes
   sont reçus, quel calque ils affectent, et quelles valeurs de matrice en résultent.
4. Une fois la cause EXACTE connue via ces logs, corriger CETTE cause précise — pas une nouvelle
   hypothèse. Puis retirer l'instrumentation temporaire (documentée comme telle dans chaque fichier
   modifié ce tour) une fois qu'elle a servi.
5. Continuer dans l'ordre P0 imposé (Home/Feed → Profile → Animems) avant tout retour aux points P1
   déjà listés en section 10/11quater (bouton créer-groupe Roster, parité visuelle Animems restante,
   etc.).
6. Ne pas déclencher Appetize soi-même ; ne pas le redemander entre chaque petit correctif — quota
   limité, instruction explicite et répétée de l'utilisateur.
