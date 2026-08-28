# MIGRATION_PARITY_AUDIT_V7.md — Audit de parité Android → iOS (Tiinver), cycle V7

**Phase** : AUDIT UNIQUEMENT — aucune correction de code appliquée pendant ce cycle. Toutes les
corrections listées ci-dessous sont des recommandations pour une phase B ultérieure.

**Date** : 2026-08-28. **Méthodologie** : 10 agents de recherche read-only (`Explore`), lancés en
parallèle, chacun couvrant un domaine avec pour consigne explicite de lire d'abord
`MIGRATION_PARITY_AUDIT_V5.md`/`V6.md`/`PHYSICAL_DEVICE_VALIDATION_V5.md` (et les audits V2-V4 via
grep ciblé) pour éviter toute redite, puis de comparer le code Android (`C:\Users\helen\
AndroidStudioProjects\tiinver`) au code iOS (`C:\Users\helen\iOSProjects\TiinverSwift`) fichier par
fichier, flux par flux. Android est la référence fonctionnelle mais un bug Android manifeste n'est
jamais reproduit aveuglément — voir la section 4 "IOS_INTENTIONAL_DIFFERENCE". Un agent (Network/
Socket.IO/Concurrence) a nécessité 4 tentatives de lancement (2 pannes d'infrastructure — perte de
connexion/blocage de flux — puis 1 limite de session utilisateur atteinte pendant l'exécution,
résolue par réinitialisation, avant un 4ᵉ lancement réussi avec un budget d'appels d'outils resserré)
— aucune de ces pannes n'a affecté le contenu ni la qualité du rapport final produit.

---

## 1. Résumé exécutif

**27 findings** produits (V7-F-001 à V7-F-027), dont **24 nécessitent une décision/correction**
et **3 sont des `IOS_INTENTIONAL_DIFFERENCE`** confirmées (aucune action requise). Aucun P0
« blocage total » au sens classique, mais **1 finding de sévérité P0 est une faille de sécurité
réelle** (V7-F-022, stockage en clair de l'`apiKey`) — traité en priorité malgré l'absence de crash
ou de perte de fonctionnalité associée.

Répartition par sévérité :

| Priorité | Nombre |
|---|---|
| P0 | 1 |
| P1 | 3 |
| P2 | 15 |
| P3 | 8 |
| **Total** | **27** |

Répartition par domaine :

| Domaine | Findings |
|---|---|
| Animems — Éditeur (panneau "Contrôle") | 3 (V7-F-001 à 003) |
| Animems — Export/Timeline/Publication | 3 (V7-F-004 à 006) |
| ChatGroup | 4 (V7-F-007 à 010) |
| Search | 1 (V7-F-011) |
| Promotion / Boost | 3 (V7-F-012 à 014) |
| Video Statistics | 4 (V7-F-015 à 018) |
| Feed / Home / Profile | 1 (V7-F-019) |
| Notifications | 2 (V7-F-020, 021) |
| Auth / Compte / Sécurité | 1 (V7-F-022) |
| Persistance / Cache | 2 (V7-F-023, 024) |
| UI/UX/Navigation | 1 (V7-F-025) |
| Transversal — Réseau/Concurrence | 2 (V7-F-026, 027) |

**Constat global le plus important de ce cycle** : contrairement à V5/V6 qui trouvaient surtout des
fonctionnalités *totalement absentes*, le V7 trouve majoritairement des **lacunes de câblage fines**
dans du code déjà largement porté et déjà audité 6 fois — la nature des bugs a changé (ordre de
callbacks non garanti par SwiftUI, garde de réentrance oubliée sur UN SEUL des N call-sites d'un
pattern par ailleurs correct, cas asymétriques entre le chemin "aperçu" et le chemin "export"). C'est
attendu et sain pour un 7ᵉ cycle d'audit sur un projet déjà mature.

---

## 2. Méthodologie

Pour chaque candidat de divergence : (1) localiser l'implémentation Android (fichier:lignes) ; (2)
localiser l'équivalent iOS (fichier:lignes), ou constater son absence ; (3) tracer le flux complet,
pas seulement le point d'entrée ; (4) comparer les modèles de données ; (5) comparer les
conditions/gardes ; (6) comparer l'ordre des callbacks ; (7) comparer la gestion d'erreur ; (8)
comparer le comportement arrière-plan/premier-plan ; (9) classifier : vrai bug iOS / bug Android (à
ne PAS copier sauf exception justifiée) / différence intentionnelle / duplicate / déjà corrigé /
problème backend partagé / nécessite validation physique / problème réellement nouveau.

Une différence n'est reportée comme finding QUE si elle produit ou peut raisonnablement produire un
écart fonctionnel réel pour l'utilisateur — pas de finding pour une différence de code sans
conséquence observable.

## 3. Périmètre couvert

Animems (éditeur complet + timeline/keyframes/playback/export/publication, en 2 lots séparés vu la
taille du domaine), ChatGroup (groupes + messagerie), Search (universelle + conversation + membres
de groupe), Promotion/Boost, Video Statistics (incluant une ré-vérification indépendante complète du
pipeline watch-time construit lors du cycle V6 précédent), Feed/Home/Profile, Notifications,
Auth/Compte/Sécurité, Persistance/Cache/État, UI/UX/Navigation fonctionnelle, et un balayage
transversal Réseau/Socket.IO/Concurrence incluant un inventaire exhaustif des ~187 sites `Task {}`
du projet iOS (jamais fait dans les cycles précédents — gap explicitement laissé ouvert par V6).

**Domaines non couverts par ce cycle** (à noter pour un futur audit) : Appels audio/vidéo WebRTC en
profondeur (seulement effleuré via l'archéologie git ChatGroup — voir section 6), Shareboard/PBS
(module explicitement non atteint, exclu délibérément pour ne pas dupliquer un chantier déjà planifié
par ailleurs), le reste du module Animems au-delà du panneau "Contrôle" et de l'export (les ~13
boutons de la barre du bas, l'undo/redo dessin libre — jugés déjà suffisamment couverts par V1/V5/V6
et non ré-audités ligne à ligne ici), flux mot de passe oublié/vérification email-téléphone,
Sign in with Google/Apple en profondeur.

---

## 4. IOS_INTENTIONAL_DIFFERENCE confirmées ce cycle

Ces 3 findings ne nécessitent AUCUNE action — documentées ici pour éviter qu'un futur cycle ne les
re-signale ou qu'une future session ne les "corrige" en croyant réparer un écart de parité :

- **V7-F-011** (Search) — `ChatSearchView.swift` applique un debounce de 300ms au repli serveur de
  recherche de groupes dans le chemin "chat", alors qu'Android n'a AUCUN debounce sur ce chemin
  précis (seul le chemin "universal" en a un côté Android). Résultat : iOS envoie moins de requêtes
  réseau redondantes qu'Android pour le même usage, avec un délai de ~300ms imperceptible en
  pratique. Amélioration iOS, ne pas retirer.
- **V7-F-014** (Promotion) — Les boutons financiers "Lancer la campagne"/"Arrêter la promotion" sont
  protégés contre le double-tap côté iOS (`isSubmitting`/`isCancelling` posés avant tout appel
  réseau) alors qu'Android n'a AUCUNE garde équivalente sur ces deux écrans précis (risque réel de
  double-débit/double-annulation resté ouvert côté Android). Protection iOS déjà correcte, ne pas
  retirer pour "aligner" sur Android.
- **V7-F-010** (ChatGroup) — Android permet de taper sur sa propre ligne dans la liste des membres
  d'un groupe (déclenchant le menu contextuel, y compris une auto-rétrogradation de rôle admin sans
  quitter le groupe) ; iOS désactive explicitement ce tap. Le comportement Android ressemble à un
  oubli plutôt qu'une fonctionnalité voulue (aucune UI dédiée). Aucune action recommandée sauf
  demande produit explicite de porter cette capacité de niche.

## 5. SHARED_BACKEND_ISSUE (bug partagé, candidat légitime à une correction iOS indépendante)

- **V7-F-021** (Notifications) — `NotificationCenterViewModel.triggerSystemNotifications` re-déclenche
  une notification système locale pour CHAQUE notification serveur encore non lue à CHAQUE appel de
  fetch (pas seulement les nouvelles) — bug Android réel (`NotificationRepository.java:194-215`),
  fidèlement reproduit côté iOS avec un commentaire explicite "identique à l'original". Contrairement
  à V5-F-026 (où la même règle "ne pas copier un bug Android" avait été correctement appliquée et
  documentée), ce cas n'a jamais reçu cette décision explicite lors du portage initial. Nuisance
  partagée réelle (spam de notifications système), candidat légitime pour qu'iOS diverge et corrige
  indépendamment — décision produit nécessaire avant correctif.

---

## 6. TOP 10 — Problèmes les plus importants

1. **V7-F-022** [P0, SÉCURITÉ] — L'`apiKey` (identifiant d'authentification permanent) est TOUJOURS
   écrite en clair dans `UserDefaults`, inconditionnellement, même quand l'écriture Keychain réussit
   — annule en production le bénéfice de sécurité que le projet visait explicitement ("faire mieux
   qu'Android" sur ce point précis, objectif de conception documenté).
2. **V7-F-015** [P1] — Le suivi du temps de visionnage (pipeline construit lors du cycle V6
   précédent) n'est JAMAIS interrompu quand l'app passe en arrière-plan sans quitter l'écran vidéo —
   surcomptage direct des statistiques de monétisation créateur (`total_watch_time`,
   `avg_watch_time`, `completion_rate`, `replay_count`).
3. **V7-F-004** [P1] — Un calque TEXTE ou STICKER recadré sur la timeline Animems reste visible sur
   TOUTE la durée de la vidéo exportée au lieu de respecter son intervalle de clip — contredit
   silencieusement ce que montre l'éditeur.
4. **V7-F-007** [P1] — Aucun message système "a quitté le groupe" n'est inséré localement quand
   l'utilisateur quitte un groupe — l'aperçu du dernier message dans la liste des conversations ne
   reflète jamais le départ.
5. **V7-F-016** [P2, mais impact potentiel maximal] — L'ordre `onAppear`/`onDisappear` non garanti
   par SwiftUI lors d'un changement de page dans le pager vidéo pourrait, dans le pire cas, faire que
   le temps de visionnage de CHAQUE vidéo suivante (le cas d'usage le plus fréquent du feed) ne soit
   quasiment jamais comptabilisé — nécessite une validation physique urgente vu la gravité
   potentielle si confirmé.
6. **V7-F-013** [P2] — Le curseur d'âge minimum de ciblage publicitaire Boost descend jusqu'à 13 ans
   côté iOS contre un plancher structurel de 18 ans côté Android — risque de conformité (ciblage
   publicitaire de mineurs).
7. **V7-F-019** [P2] — La vignette de notification (like/comment/partage) réimplémente une 3ᵉ
   logique de priorité de champ CDN indépendante, ni fidèle à Android ni à la logique centrale iOS
   déjà corrigée — même classe d'erreur que V6-F-015 (Boost), non corrigée ici.
8. **V7-F-012** [P2] — L'objectif de campagne publicitaire par défaut diffère (iOS: "likes", Android:
   "views" en pratique) — impact direct sur ce que l'utilisateur paie s'il soumet sans toucher le
   sélecteur.
9. **V7-F-008** [P2] — Aucun message système "X a ajouté Y" n'est inséré lors de l'ajout de membres à
   un groupe (création ou après coup) — l'historique de conversation iOS est incomplet par rapport à
   Android sur ce point.
10. **V7-F-005** [P2] — L'export vidéo Animems n'a aucune protection `beginBackgroundTask` — un
    export peut être perdu silencieusement si l'app est tuée en arrière-plan pendant l'encodage, alors
    que l'étape suivante du même flux (publication/upload) a déjà cette protection dans ce dépôt.

---

## 7. Findings détaillés

### Domaine : Animems — Éditeur (panneau "Contrôle")

```
ID : V7-F-001
PRIORITÉ : P2
DOMAINE : Animems — Panneau "Contrôle" (capture automatique de keyframe)
FEATURE : Relâcher le curseur d'angle du panneau "Contrôle" ne déclenche jamais la capture automatique de keyframe, contrairement à un glisser-déposer direct sur le canevas quand le mode "capture automatique" est actif
ANDROID SOURCE : AnimemesCompound.java:499-517 (listener MovementControllerHandlerListener : onStart→touchDown(0)+initControllerMovement(), onStop→controllerMovementUp()+touchUp(0)) ; AnimemesCompound.java:3214-3221 (touchUp(int) : pause() inconditionnel + branche automateCapture) ; MemesView2.java:1742/1753 (le MÊME touchUp() est le point de sortie PARTAGÉ pour tout geste, drag inclus)
ANDROID BEHAVIOR : touchUp() est le point de sortie unique et partagé pour "fin de manipulation d'un calque" — que ce soit via drag direct OU via le panneau Contrôle, une nouvelle capture est enregistrée si automateCapture est actif
IOS FILES : AnimemesEditorState.swift:441-446 (dragEnded(), applique bien autoCaptureEnabled→recordKeyframe() pour le drag direct) ; MovementControllerPanelView.swift:51-62 (Slider onEditingChanged ne traite que editing==true) ; AnimemesEditorState.swift:509-527 (movementControllerBeginTracking/ProgressChanged/closeMovementController — aucun n'appelle recordKeyframe())
IOS BEHAVIOR : Le point de sortie du panneau "Contrôle" (relâchement du curseur ou fermeture) n'appelle jamais recordKeyframe(), même avec autoCaptureEnabled==true
CAUSE : Le correctif V6-F-002 (panneau Contrôle, ajouté le jour même de l'audit) a porté fidèlement applySeekBarTransform/applySeekBarTransformOnAnchor mais pas la branche automateCapture du callback touchUp() qui encadre TOUS les points de sortie de geste côté Android
IMPACT : Un utilisateur ayant activé "capture automatique" ET utilisant le nouveau panneau Contrôle (pensé comme alternative précise au geste) pour animer un calque n'obtient AUCUN keyframe enregistré — l'animation escomptée ne se construit pas, silencieusement
REPRODUCTIBILITÉ : certaine par lecture de code
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Appeler recordKeyframe() dans closeMovementController() (et/ou à onEditingChanged(false) du slider) quand autoCaptureEnabled==true, miroir de la garde déjà appliquée dans dragEnded().
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-002
PRIORITÉ : P2
DOMAINE : Animems — Bascule des panneaux de zone timeline (Bezier/Contrôle/Masque/Timeline)
FEATURE : Fermer un panneau de zone timeline prioritaire peut faire réapparaître silencieusement un autre panneau (Contrôle) resté "ouvert" en arrière-plan
ANDROID SOURCE : AnimemesCompound.java:1857-1874 (controlle_movement) ; :1970-1980 (btn_bezier — masque explicitement les autres zones à l'ouverture, mais ne restaure rien à la fermeture, v.setSelected(false) seul — bug Android probable, symptôme différent)
ANDROID BEHAVIOR : Chaque bouton masque les autres zones à l'ouverture (exclusion mutuelle partielle câblée bouton par bouton) ; aucune restauration automatique à la fermeture
IOS FILES : AnimemesEditorView.swift:128,133,138 (3 @State Bool indépendants showBezierEditor/showTimeline/showMovementController) ; :166-182 (chaîne if/else-if à priorité fixe) ; :1145,1152-1153,1174,1193 (4 actions d'ouverture, AUCUNE ne réinitialise les 3 autres)
IOS BEHAVIOR : Scénario reproductible : ouvrir Contrôle → ouvrir bezier (Contrôle masqué par priorité, reste true en arrière-plan) → refermer bezier → Contrôle RÉAPPARAÎT sans que l'utilisateur ait retapé son bouton, potentiellement avec des bascules zoom/rotation/etc. encore actives d'une session précédente (MovementControllerState non remis à zéro sauf closeMovementController() explicite)
CAUSE : Chaque bouton de panneau porté indépendamment (sessions/correctifs différents) avec un simple .toggle() local, sans garde de bascule mutuellement exclusive centralisée
IMPACT : Séquence d'usage plausible produisant une réapparition inattendue du panneau Contrôle, pouvant induire une transformation non désirée au prochain contact avec le curseur si une bascule est restée active
REPRODUCTIBILITÉ : certaine par lecture de code
NIVEAU DE CONFIANCE : haute
VALIDATION : PHYSICAL_VALIDATION_REQUIRED (logique certaine, expérience utilisateur exacte à confirmer)
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Centraliser les 4 panneaux dans un seul état enum "panneau actif" (au plus une valeur vraie à la fois), ou a minima faire que chaque bouton remette explicitement les 3 autres à false / appelle closeMovementController() en désactivant Contrôle.
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-003
PRIORITÉ : P3
DOMAINE : Animems — Panneau "Contrôle" (plage du curseur d'angle)
FEATURE : La plage du curseur d'angle du panneau "Contrôle" ne correspond pas à la plage réelle du SeekBar Android
ANDROID SOURCE : movement_controller_handler.xml:74-82 (SeekBar max=100, progress=0) ; MovementControllerHandlerView.java:85-92 (finalProgress=progress+90 → plage effective [90,190], asymétrique, jamais sous 90)
ANDROID BEHAVIOR : Plage [90,190] — le curseur ne peut jamais "reculer" sous 90
IOS FILES : MovementControllerPanelView.swift:15 (sliderValue init 90), :51-52 (Slider in: 0...180)
IOS BEHAVIOR : Plage [0,180], quasi symétrique autour de 90 — permet de descendre jusqu'à 0 (delta -90 impossible côté Android) mais plafonne 10 unités plus tôt (180 au lieu de 190)
CAUSE : Choix d'une plage symétrique par simplicité lors du portage, sans reprendre la plage réelle asymétrique du SeekBar Android
IMPACT : Amplitude maximale de transformation atteignable en un geste continu différente entre plateformes, surtout à l'extrémité basse (atteignable seulement côté iOS)
REPRODUCTIBILITÉ : certaine pour la divergence structurelle ; NEEDS_PHYSICAL_VALIDATION pour la perceptibilité réelle
NIVEAU DE CONFIANCE : moyenne
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Aligner la plage du Slider iOS sur 90...190.
NOTE ANNEXE (pas un défaut à corriger) : Android lui-même a un bug probable où oldProgress (init=1, jamais réaligné sur [90,190] à l'ouverture) produit un saut de transformation instantané d'environ 89-90 unités au premier contact — le port iOS (oldProgress réinitialisé via beginTracking(atProgress:), réellement appelé depuis onStart) NE reproduit PAS ce bug, déjà meilleur ici, aucune action.
STATUT : NON CORRIGÉ (audit uniquement)
```

### Domaine : Animems — Export / Timeline / Publication

```
ID : V7-F-004
PRIORITÉ : P1
DOMAINE : Animems — Export vidéo (recadrage temporel des calques texte/sticker)
FEATURE : Un calque TEXTE ou STICKER dont le clip timeline a été raccourci reste visible sur TOUTE la durée de la vidéo exportée au lieu de disparaître hors de son intervalle startFrame/endFrame
ANDROID SOURCE : MP4Encoder.java:347-354 (renderSceneIntoFbo, boucle unique appliquant `if (f < s || f > e) continue` à TOUS les calques, texte/sticker inclus)
ANDROID BEHAVIOR : Un calque, quel que soit son type, n'est dessiné que sur les frames dans [objStart, objEnd] dans le MP4 réellement produit
IOS FILES : AnimemesExporter.swift:301-320 (render(frame:into:)) — cas .bitmap/.shapeRect/.shapeCircle/.shapeLine (lignes 306-309, garde explicite startAt[i]/endAt[i]) vs cas .text/.sticker (lignes 314-317, AUCUNE garde) ; AnimemesEditorState.applyTimelineItemsToLayers() écrit startFrame/endFrame pour n'importe quel type sans filtre
IOS BEHAVIOR : AnimemesExporter.render appelle drawText/drawSticker inconditionnellement pour chaque frame, sans jamais consulter engine.startAt[i]/endAt[i] — pourtant déjà calculées et utilisées 6 lignes plus haut pour le cas bitmap/shape
CAUSE : Le correctif V6-F-006 (2026-08-28) a ajouté currentNs pour l'interpolation matricielle mais pas la garde de bornes temporelles que le cas bitmap/shape applique juste au-dessus dans la même boucle — omission distincte, indépendante de l'interpolation
IMPACT : Tout utilisateur raccourcissant le clip d'un calque texte ou sticker sur la timeline obtient un export MP4 qui ne respecte pas ce recadrage — contredit silencieusement l'éditeur
REPRODUCTIBILITÉ : certaine par lecture de code
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE (garde absente) + PHYSICAL_VALIDATION_REQUIRED (confirmation visuelle du rendu MP4)
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Ajouter dans AnimemesExporter.render(frame:into:), cas .text/.sticker, la même garde que bitmap : `guard i < startAt.count, i < endAt.count, renderFrame >= startAt[i], renderFrame <= endAt[i] else { continue }`. Ne PAS toucher au rendu de l'éditeur en direct — Android lui-même n'applique cette borne qu'à l'export, jamais à l'aperçu pour TEXT/STICKER ; reproduire cette asymétrie est fidèle, pas une régression.
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-005
PRIORITÉ : P2
DOMAINE : Animems — Export (comportement en arrière-plan)
FEATURE : L'export MP4 Animems n'est protégé par aucun beginBackgroundTask, contrairement au flux de publication qui suit immédiatement dans le même écran
ANDROID SOURCE : AnimemesCompound.java:2583,2606-2660 (createVideosFromBitmap, thread/executor Java classique — continue de tourner tant que le process vit, non suspendu par le simple passage en arrière-plan)
ANDROID BEHAVIOR : Basculer vers une autre app pendant l'encodage n'interrompt pas le thread d'encodage
IOS FILES : AnimemesEditorState.swift:1154-1191 (export(canvasSize:completion:)) ; AnimemesExporter.swift (pipeline AVAssetWriter piloté par de simples DispatchQueue) — grep exhaustif : zéro occurrence de beginBackgroundTask dans Sources/TiinverSwift/Animems/
IOS BEHAVIOR : Aucune protection n'enveloppe exporter.export(to:completion:) — iOS suspend l'exécution quasi immédiatement après le passage en arrière-plan sans tâche protégée. Le MÊME fichier de flux (l'export débouche sur PublishComposeView.swift) protège DÉJÀ sa propre étape suivante (l'upload) avec exactement ce mécanisme (PublishComposeView.swift:303-334) — le pattern existe et est compris dans ce dépôt, juste pas étendu en amont
CAUSE : Le pattern beginBackgroundTask a été appliqué à l'étape de publication (V6-F-024/correctifs antérieurs) mais jamais à l'étape d'export qui la précède dans le même flux utilisateur
IMPACT : Basculer vers une autre app pendant l'encodage peut geler/perdre l'export silencieusement si l'app est tuée pendant qu'elle est en arrière-plan — aucun message d'erreur, fichier temporaire orphelin
REPRODUCTIBILITÉ : probable (dépend du timing OS et de la pression mémoire)
NIVEAU DE CONFIANCE : moyenne
VALIDATION : PHYSICAL_VALIDATION_REQUIRED
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Envelopper exporter.export(to:completion:) dans AnimemesEditorState.export(...) avec beginBackgroundTask/endBackgroundTask, même pattern que PublishComposeView.publish() (déjà dans ce dépôt, à réutiliser tel quel).
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-006
PRIORITÉ : P2
DOMAINE : Animems — Export (remontée d'erreur à l'utilisateur)
FEATURE : exportError est calculé sur échec d'export mais n'est lu par AUCUNE vue — l'utilisateur ne voit jamais qu'un export a échoué
ANDROID SOURCE : N/A directement comparable — Android a un gap partiellement similaire (catch IOException réactive juste la vue sans Toast), donc pas un cas où Android affiche un message qu'iOS aurait oublié de porter ; défaut interne iOS indépendant
IOS FILES : AnimemesEditorState.swift:54 (@Published var exportError: String?), :1186,:1227 (les 2 seuls sites d'écriture) ; AnimemesEditorView.swift:392,540 (les 2 seuls appels de state.export(...), complétion ignorant totalement le cas nil/exportError) — grep exhaustif : 4 occurrences totales, toutes dans AnimemesEditorState.swift, aucune lecture côté vue
IOS BEHAVIOR : Sur échec (ex. celui que corrige V6-F-008), exportError passe à "L'export a échoué.", isExporting repasse à false, et rien d'autre — exportedURL reste nil, aucune alerte, contrairement à publishConversionError (même fichier, ligne 386-390) qui LUI est câblé à une .alert
CAUSE : Le correctif V6-F-008 a rendu export() capable d'échouer explicitement, mais aucun correctif n'a ajouté le câblage vue manquant
IMPACT : Toute défaillance d'export est invisible pour l'utilisateur — "ça n'a rien fait", sans indice pour réessayer, alors que le pattern d'alerte existe déjà 4 lignes plus bas dans le même fichier
REPRODUCTIBILITÉ : certaine par lecture de code
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : PARTIAL
RECOMMANDATION : Ajouter une .alert sur AnimemesEditorView liée à state.exportError, même pattern que publishConversionError.
STATUT : NON CORRIGÉ (audit uniquement)
```

### Domaine : ChatGroup

```
ID : V7-F-007
PRIORITÉ : P1
DOMAINE : ChatGroup — sortie de groupe (écho local du message système)
FEATURE : Aucun message système "a quitté le groupe" n'est inséré localement quand l'utilisateur quitte un groupe, contrairement à Android
ANDROID SOURCE : GroupDetailActivity.java:260-337 (exit(), insertion verb="leftGroup" AVANT dialog.dismiss())
IOS FILES : GroupDetailView.swift:445-453 (leaveGroup()) — appelle GroupRepository.leaveGroup puis dismiss(), AUCUN appel à insertSystemMessage, contrairement aux 5 autres mutations du même fichier (submitName/submitDescription/uploadPhoto/remove) qui l'appellent toutes après succès réseau
IOS BEHAVIOR : leaveGroup() n'insère jamais de message système — seule exception non justifiée du fichier
CAUSE : Oubli — le pattern "POST réseau puis écho système local via MessageRepository.insertTextMessage (qui met aussi à jour wk_roster)" est établi partout ailleurs dans ce fichier mais pas appliqué ici
IMPACT : MessageRepository.insertTextMessage est ce qui appelle roster.updateRoster(...) — sans lui, l'aperçu du dernier message dans la liste des conversations pour ce groupe ne reflète JAMAIS le départ. L'historique de la conversation elle-même est incomplet par rapport à Android
REPRODUCTIBILITÉ : certaine par lecture de code
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Dans GroupDetailView.leaveGroup(), après succès de GroupRepository.shared.leaveGroup(...) et avant dismiss(), appeler insertSystemMessage(verb: "leftGroup", ...) — même pattern que remove()/submitName()/submitDescription().
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-008
PRIORITÉ : P2
DOMAINE : ChatGroup — ajout de membres (écho local des messages système)
FEATURE : Aucun message système "X a ajouté Y" n'est inséré localement lors de l'ajout de membres (création OU après coup), contrairement à Android qui en insère un par membre ajouté
ANDROID SOURCE : Group.java:388-459 (groupCreated(), insertion verb="addMember" par membre) ; AddGroupMemberActivity.java:163-244 (addMemebers(), insertion verb="addMember")
IOS FILES : GroupRepository.swift:174-186 (addMembers, fonction PARTAGÉE) ; GroupCreationView.swift:133-189 (create() — un seul insertTextMessage pour "createGroup", jamais pour les membres) ; AddGroupMemberView.swift:80-88 (submit() — appelle addMembers puis dismiss(), aucun écho)
IOS BEHAVIOR : addMembers se contente d'un POST membership par membre, sans jamais construire/insérer de message système — seule méthode de mutation du fichier ne suivant pas ce pattern
CAUSE : addMembers n'a jamais suivi le pattern "POST réseau + écho système local" ; aucun de ses deux appelants ne compense
IMPACT : Quand un groupe est créé avec des membres initiaux, ou que des participants sont ajoutés plus tard, le fil de discussion iOS ne montre AUCUNE trace "X a ajouté Y" — les nouveaux membres apparaissent sans explication visible
REPRODUCTIBILITÉ : certaine par lecture de code
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : MISSING
RECOMMANDATION : Ajouter dans GroupRepository.addMembers (ou ses deux appelants) une insertion de message système (verb="addMember") par membre ajouté avec succès.
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-009
PRIORITÉ : P3
DOMAINE : ChatGroup — création de groupe (type de groupe transmis au serveur)
FEATURE : Le champ "type" transmis pour un groupe privé diffère selon interaction : Android envoie "private" (correct) par défaut, "pivate" (coquille) seulement si l'utilisateur clique explicitement le sélecteur ; iOS envoie systématiquement "pivate"
ANDROID SOURCE : Group.java:73 (groupType="private" par défaut) ; :243-260 (radioClicked, réassigne "pivate" AVEC la coquille SEULEMENT sur clic explicite) ; fragment_group.xml:88-91 (prvte déjà checked="true" par défaut — donc le listener ne se déclenche jamais si l'utilisateur n'interagit pas)
ANDROID BEHAVIOR : Dans le parcours le plus courant (utilisateur qui accepte le défaut), "private" (orthographe correcte) part au serveur
IOS FILES : GroupRepository.swift:24-34 (createGroup, ligne 30 : "type": isPrivate ? "pivate" : "public")
IOS BEHAVIOR : "pivate" est TOUJOURS envoyé pour un groupe privé, y compris dans le parcours le plus courant — le commentaire documente la coquille comme volontairement reproduite mais n'a pas remarqué que le défaut Android réel (avant interaction) est correctement orthographié
CAUSE : Reproduction de la branche de clic explicite sans remarquer que le vrai défaut Android (avant interaction) diffère
IMPACT : Incertain sans visibilité sur le traitement serveur du champ type — si le backend distingue "private" de "pivate", le comportement par défaut diffère entre plateformes ; si le backend traite tout ce qui n'est pas "public" comme privé, impact nul
REPRODUCTIBILITÉ : certaine pour le fait générateur ; incertaine pour l'impact réel (dépend du backend)
NIVEAU DE CONFIANCE : moyenne
VALIDATION : PHYSICAL_VALIDATION_REQUIRED (comportement backend)
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Vérifier côté backend si "type" est comparé strictement ailleurs qu'à "public" ; si oui, envoyer "private" par défaut. Sinon, laisser tel quel (écart cosmétique).
STATUT : NON CORRIGÉ (audit uniquement)
```

*(V7-F-010 = IOS_INTENTIONAL_DIFFERENCE, voir section 4 ci-dessus.)*

### Domaine : Search

*(V7-F-011 = IOS_INTENTIONAL_DIFFERENCE, voir section 4 ci-dessus — aucun autre finding produit
dans ce domaine ce cycle ; recherche universelle/conversation/membres de groupe/tri/pagination/cache
tous vérifiés conformes, voir le journal de progrès pour le détail des vérifications négatives.)*

### Domaine : Promotion / Boost

```
ID : V7-F-012
PRIORITÉ : P2
DOMAINE : Promotion — Création (objectif publicitaire par défaut)
FEATURE : L'objectif de campagne pré-sélectionné diffère entre Android et iOS, changeant le calcul d'estimation ET la valeur "objectif" envoyée au serveur si soumission sans interaction
ANDROID SOURCE : fragment_create_boost.xml:50-55 (radioView checked="true") ; CreateBoostFragment.java:338-343 (getSelectedObjectif() : repli "likes" jamais atteint en pratique car radioView est déjà coché)
ANDROID BEHAVIOR : "Vues" réellement coché au chargement — objectif="views" tant que non modifié, estimation = budget*4 vues
IOS FILES : CreateBoostView.swift:21 (@State private var objective = "likes", commenté à tort "port du repli par défaut")
IOS BEHAVIOR : État initial "likes", pas "views" — segment différent en surbrillance, estimation initiale = budget/3 likes, et si soumission immédiate, objectif="likes"/dailyLimit=budget/3 au lieu de "views"/budget*4
CAUSE : Le porteur iOS a reproduit la branche de repli TEXTUELLE du code Java, sans remarquer qu'elle n'est jamais atteinte en pratique côté Android (le XML pré-coche "views")
IMPACT : Si l'utilisateur soumet sans interagir avec le sélecteur, la campagne payante créée cible un objectif différent de celui qu'un utilisateur Android obtiendrait dans la même situation, avec un dailyLimit/objectifCible calculé différemment — impact direct sur ce pour quoi l'utilisateur paie
REPRODUCTIBILITÉ : certaine par lecture de code
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : MISMATCH
RECOMMANDATION : Changer @State private var objective = "likes" en "views" (CreateBoostView.swift:21), corriger le commentaire trompeur.
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-013
PRIORITÉ : P2
DOMAINE : Promotion — Ciblage d'audience (tranche d'âge)
FEATURE : La borne minimale du curseur d'âge minimum de ciblage est plus permissive côté iOS (13 ans) que côté Android (18 ans), permettant un age_min qu'Android ne peut structurellement jamais produire
ANDROID SOURCE : fragment_create_boost.xml:174-191 (RangeSlider valueFrom="18", valueTo="55" — les deux poignées bornées dans [18,55])
ANDROID BEHAVIOR : minAge ne peut jamais descendre sous 18 ; Audience.age_min toujours >= "18"
IOS FILES : CreateBoostView.swift:122-123 (Slider(value: $minAge, in: 13...maxAge, step: 1))
IOS BEHAVIOR : La borne basse du slider minAge est câblée à 13, pas 18 — un utilisateur peut glisser jusqu'à 13 ans et soumettre un ciblage publicitaire avec age_min="13"
CAUSE : Vraisemblablement une erreur lors du portage du RangeSlider Material (deux poignées, une plage) vers deux Slider SwiftUI séparés — la borne basse n'a pas été alignée sur valueFrom="18"
IMPACT : Un boost publicitaire peut être configuré et payé côté iOS avec un ciblage d'âge minimum descendant à 13 ans, ce qu'Android empêche structurellement — risque de non-conformité potentielle (ciblage de mineurs) selon les règles internes/légales de la plateforme publicitaire
REPRODUCTIBILITÉ : certaine par lecture de code ; NEEDS_PHYSICAL_VALIDATION pour le rendu visuel exact et pour savoir si le serveur rejette déjà age_min<18 (auquel cas l'impact serait purement UX)
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : MISMATCH
RECOMMANDATION : Changer la borne basse du slider en 18...maxAge (CreateBoostView.swift:122).
STATUT : NON CORRIGÉ (audit uniquement)
```

*(V7-F-014 = IOS_INTENTIONAL_DIFFERENCE, voir section 4 ci-dessus.)*

### Domaine : Video Statistics

```
ID : V7-F-015
PRIORITÉ : P1
DOMAINE : Video Statistics — Pipeline watch-time, câblage cycle de vie app
FEATURE : Le suivi du temps de visionnage n'est jamais interrompu quand l'app passe en arrière-plan sans quitter l'écran du pager
ANDROID SOURCE : FeedFragment.java:1575-1595 (onPause(), flush systématique du watchTracker dès que le Fragment perd le premier plan, pour QUELQUE raison que ce soit — navigation interne OU passage en arrière-plan)
ANDROID BEHAVIOR : accumulatedWatchTimeMs ne peut jamais courir pendant que l'app est en arrière-plan
IOS FILES : FeedView.swift:918-922 (.onDisappear du pager, ne se déclenche QUE sur navigation interne) ; RootRouterView.swift:95-109 (.onChange(of: scenePhase), branche .background ne fait que NetworkMonitor.shared.stop(), aucun appel au tracker)
IOS BEHAVIOR : Basculer vers Accueil (ou consulter une notification) sans revenir en arrière ni changer de page ne déclenche ni .onDisappear ni aucun scenePhase handler pour pauseTracking()/flushAndRecord() — watchTracker.isTracking reste true, l'horloge monotone continue d'avancer tant que l'appareil est éveillé
CAUSE : WatchTimeTracker.swift utilise une horloge monotone (choix correct, insensible aux ajustements d'horloge murale) mais celle-ci continue d'avancer en arrière-plan écran allumé ; Android compense ce même choix d'horloge par un flush explicite dans onPause(), sans pendant côté iOS
IMPACT : Surcomptage direct pour tout scénario "bascule vers une autre app/notification puis retour" — fausse total_watch_time/avg_watch_time/completion_rate, peut gonfler artificiellement replay_count. Impact direct sur la monétisation créateur (métriques faussées à la hausse)
REPRODUCTIBILITÉ : certaine (gap structurel prouvable par lecture de code)
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : NOUVEAU
RECOMMANDATION : Ajouter un .onChange(of: scenePhase) local à FeedDetailPagerView qui appelle flushAndRecord(index:) sur phase != .active (alternative : flush déclenché depuis RootRouterView via callback/NotificationCenter si un pager est présenté).
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-016
PRIORITÉ : P2
DOMAINE : Video Statistics — Pipeline watch-time, ordre des callbacks SwiftUI
FEATURE : Ordre non garanti entre onAppear de la vidéo entrante et onDisappear de la vidéo sortante lors d'un changement de page dans le pager
ANDROID SOURCE : FeedFragment.java:731-743 (onIsPlayingChanged) — séquencement garanti par ExoPlayer, un seul lecteur, transition strictement séquentielle
IOS FILES : FeedView.swift:1106-1121 (FillVideoPlayerView.onAppear/.onDisappear, partagent UN SEUL AVPlayer ET un seul watchTracker, ligne 627) ; VideoPlayerManager.swift:96 (replaceCurrentItem synchrone) ; FeedView.swift:973-1010 (handleVideoPlaybackActiveChanged, captureExitPointAndDuration)
IOS BEHAVIOR : SwiftUI NE garantit PAS l'ordre relatif entre .onAppear d'une vue entrante et .onDisappear d'une vue sortante sur un changement de selection TabView. Si onAppear(B) s'exécute AVANT onDisappear(A) : (1) playVideo a déjà remplacé currentItem par B avant que captureExitPointAndDuration() de A ne lise position/durée — pollution mineure ; (2) PLUS GRAVE : pauseTracking() de A s'exécute alors qu'isTracking est déjà true pour B (resumeTracking() de B vient de s'exécuter) — ce pauseTracking() "en retard" met B en pause immédiatement après son démarrage, sans qu'aucun événement ne le relance avant le prochain changement de page
CAUSE : SwiftUI ne garantit pas l'ordre relatif onAppear/onDisappear lors d'un changement de selection sur TabView (comportement non spécifié, connu pour varier) ; le modèle Android à lecteur unique séquentiel n'a pas cette vulnérabilité
IMPACT : Si cet ordre se produit en pratique, la quasi-totalité du temps de visionnage vidéo-à-vidéo (le cas d'usage LE PLUS courant du feed) pourrait être silencieusement non comptabilisée — viderait de son sens la statistique total_watch_time/avg_watch_time que V6-F-019 visait justement à réparer
REPRODUCTIBILITÉ : incertaine (dépend d'un comportement SwiftUI non documenté — nécessite instrumentation sur device réel)
NIVEAU DE CONFIANCE : moyenne
VALIDATION : PHYSICAL_VALIDATION_REQUIRED — À VALIDER EN PRIORITÉ vu la gravité potentielle
SUGGESTED_STATUS : NOUVEAU
RECOMMANDATION : Découpler pauseTracking() de l'identité de la cellule qui le déclenche — stocker lastTrackedIndex et ignorer un onVideoPlaybackActiveChanged(false) provenant d'une cellule qui n'est plus l'index actif, ou plus robustement : piloter resume/pause UNIQUEMENT depuis .onChange(of: currentIndex) (ordre déterministe, point d'entrée unique) plutôt que depuis onAppear/onDisappear de deux vues différentes.
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-017
PRIORITÉ : P3
DOMAINE : Video Statistics — Persistance locale, sûreté concurrentielle
FEATURE : ViewEventRepository.record() n'a pas d'équivalent à la sérialisation par exécuteur mono-thread d'Android
ANDROID SOURCE : ViewTracker.java:29-30 (dbExecutor = Executors.newSingleThreadExecutor(), tous les record() sérialisés) ; db/ViewEvent.java:9 (index unique Room)
IOS FILES : ViewEventRepository.swift:32-80 (record) ; CoreDataRepository.swift:34-57 (insert/update, chacun crée son propre newBackgroundContext() indépendant)
IOS BEHAVIOR : record(...) invoqué depuis des Task séparées sans file d'attente partagée ni verrou ; le modèle CoreData ne déclare aucune contrainte d'unicité sur (activityId, userId)
CAUSE : Absence de sérialisation équivalente au dbExecutor Android
IMPACT : Deux Task concurrentes pour le même (activityId, userId) (flushs rapprochés) peuvent chacune lire un état stale puis écrire indépendamment — perte silencieuse d'un incrément de watchtime, ou lignes dupliquées jamais fusionnées
REPRODUCTIBILITÉ : incertaine (dépend de la vitesse de swipe/latence CoreData réelle)
NIVEAU DE CONFIANCE : basse
VALIDATION : PHYSICAL_VALIDATION_REQUIRED
SUGGESTED_STATUS : NOUVEAU (priorité mineure)
RECOMMANDATION : Sérialiser les appels record() (acteur Swift dédié ou file DispatchQueue unique) et/ou ajouter une contrainte d'unicité applicative sur (activityId, userId).
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-018
PRIORITÉ : P3
DOMAINE : Video Statistics — Synchronisation réseau, couverture du déclencheur "retour au premier plan"
FEATURE : Le déclencheur de sync au retour au premier plan ne couvre pas le lancement à froid
ANDROID SOURCE : ViewTracker.java:100-114 (startPeriodicSync, WorkManager 15 min, survit à un kill complet)
IOS FILES : RootRouterView.swift:95-113 — le commentaire confirme explicitement que .onChange(of: scenePhase) ne se déclenche PAS pour l'état .active initial au lancement ; seul .onAppear { startNetworkMonitor() } couvre ce cas, sans appeler ViewEventSyncService.sync()
IOS BEHAVIOR : Une session courte (1-4 vues, sous le seuil syncThreshold=5) suivie d'un kill complet de l'app laisse ces lignes en attente jusqu'à un futur cycle bg→fg d'une session ULTÉRIEURE, ou jusqu'à la purge 7 jours
CAUSE : Absence du job périodique en arrière-plan (BGTaskScheduler, déjà hors périmètre V5-F-060) — mais le gap précis "le lancement à froid ne tente pas de sync" n'était pas mentionné dans V6-F-019
IMPACT : Perte silencieuse de données de visionnage pour les sessions courtes suivies d'un kill complet — mineur en volume par vue mais peut affecter significativement les créateurs à faible audience
REPRODUCTIBILITÉ : probable
NIVEAU DE CONFIANCE : moyenne
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : NOUVEAU (priorité mineure, extension du scope déjà connu de V5-F-060)
RECOMMANDATION : Ajouter Task { await ViewEventSyncService.sync() } également dans .onAppear de RootRouterView, pas seulement dans la branche .active de .onChange(of: scenePhase).
STATUT : NON CORRIGÉ (audit uniquement)
```

### Domaine : Feed / Home / Profile

```
ID : V7-F-019
PRIORITÉ : P2
DOMAINE : Notifications — vignette de post dans la liste de notifications (like/comment/partage)
FEATURE : La vignette affichée dans une notification utilise une logique de priorité de champ CDN inventée, différente de celle d'Android — même classe d'erreur que V6-F-015 (Boost)
ANDROID SOURCE : AdapterNoti.java:564-584 (bindThumb) — PHOTO → object_url INCONDITIONNELLEMENT (jamais cdn_thumbnail_url/cdn_content_url) ; VIDÉO → cdn_thumbnail_url si non nul, sinon extraction cliente d'une frame depuis object_url
ANDROID BEHAVIOR : Pour une notification PHOTO, la vignette vient toujours de object_url
IOS FILES : NotificationsListView.swift:83-87 (thumbnailURL) : `noti.cdnThumbnailUrl ?? noti.cdnContentUrl ?? noti.objectUrl` — priorité fixe, ne teste JAMAIS noti.object
IOS BEHAVIOR : Pour une notification PHOTO, si cdn_thumbnail_url est renseigné (même avec une valeur bidon déjà confirmée réelle sur ce champ pour des photos, cf. correctif BUG 1 du 2026-08-27), CETTE valeur est utilisée à la place d'object_url. Pour une notification VIDÉO sans cdn_thumbnail_url, iOS retombe sur cdn_content_url (un manifest de lecture, pas une image) plutôt que object_url
CAUSE : NotificationRow réimplémente une 3ᵉ variante de priorité CDN, indépendante à la fois de FeedActivity.thumbnailURL (logique centrale déjà corrigée) ET de la vraie logique Android de ce contexte précis — alors qu'un FeedActivity complet existe déjà dans le même fichier et n'est utilisé que pour le tap, jamais pour la vignette
IMPACT : Pour toute notification sur une publication PHOTO dont le backend renseigne cdn_thumbnail_url avec une valeur non affichable (cas déjà confirmé réel), la vignette échoue à charger ou affiche une image incorrecte. Pour une notification VIDÉO sans cdn_thumbnail_url, iOS tente de charger un manifest vidéo comme image (échec quasi certain)
REPRODUCTIBILITÉ : certaine pour la divergence de logique ; certaine pour le cas photo précis (pattern déjà confirmé réel ailleurs dans ce projet)
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE + PHYSICAL_VALIDATION_REQUIRED (fréquence réelle du cas)
SUGGESTED_STATUS : FUNCTIONALLY_FAILED
RECOMMANDATION : Remplacer NotificationRow.thumbnailURL par une vraie branche sur noti.object, fidèle à AdapterNoti.bindThumb : PHOTO → objectUrl inconditionnellement ; VIDÉO → cdnThumbnailUrl si non vide sinon objectUrl ; masquer si les deux vides. Alternative : réutiliser reconstructedPost?.thumbnailURL si l'équipe accepte que ce ne soit pas un pur miroir d'Android dans ce contexte précis.
STATUT : NON CORRIGÉ (audit uniquement)
```

### Domaine : Notifications

```
ID : V7-F-020
PRIORITÉ : P2
DOMAINE : Notifications — Push générique/marketing (foreground)
FEATURE : Une notification push "notification-only" (marketing, sans payload data) s'affiche TOUJOURS en bannière système côté iOS au premier plan, alors qu'Android la supprime silencieusement
ANDROID SOURCE : MyFirebaseMessagingService.java:83-98 (onMessageReceived) — la branche remoteMessage.getNotification()!=null est ENTIÈREMENT commentée (no-op total)
ANDROID BEHAVIOR : Un message FCM "notification"-only reçu au premier plan ne produit aucun affichage
IOS FILES : AppDelegate.swift:133-139 (userNotificationCenter(_:willPresent:))
IOS BEHAVIOR : completionHandler([.banner,.sound,.badge]) appelé INCONDITIONNELLEMENT pour toute notification au premier plan, y compris une notification purement aps.alert sans categoryIdentifier/données custom. Le commentaire de tête justifie ce choix en affirmant qu'Android n'a pas de distinction premier-plan/arrière-plan pour ce cas, ce qui est FAUX précisément pour ce cas
CAUSE : Confusion entre le comportement Android pour les push data custom (traités identiquement fg/bg, vrai) et son comportement pour les push notification-only marketing (silencieux au fg, visible en bg), non distingué lors du portage
IMPACT : Un utilisateur avec l'app ouverte reçoit un bandeau+son pour toute notification marketing envoyée en push générique, alors qu'un utilisateur Android ne voit rien — écart de bruit/UX, sous réserve que le backend envoie effectivement ce type de push
REPRODUCTIBILITÉ : probable (dépend de l'usage réel côté backend)
NIVEAU DE CONFIANCE : moyenne
VALIDATION : PHYSICAL_VALIDATION_REQUIRED
SUGGESTED_STATUS : VISUALLY_DIFFERENT
RECOMMANDATION : Dans willPresent, distinguer les catégories reconnues (activity/chat_message, à afficher comme aujourd'hui) d'une notification sans categoryIdentifier reconnu ET sans données custom — retourner [] pour cette dernière au premier plan.
STATUT : NON CORRIGÉ (audit uniquement)
```

*(V7-F-021 = SHARED_BACKEND_ISSUE, voir section 5 ci-dessus.)*

### Domaine : Auth / Compte / Sécurité

```
ID : V7-F-022
PRIORITÉ : P0
DOMAINE : Auth/Compte/Sécurité — Stockage de l'apiKey (Keychain vs UserDefaults)
FEATURE : L'apiKey (identifiant d'authentification permanent, envoyé brut dans l'en-tête Authorization de CHAQUE requête réseau) est TOUJOURS écrite en clair dans UserDefaults, inconditionnellement, même quand l'écriture Keychain réussit
ANDROID SOURCE : infoContract.java (clé MY_API_KEY, SharedPreferences — Android stocke déjà l'apiKey en clair nativement, référence, pas un point de comparaison "à sécuriser")
IOS FILES : KeychainStore.swift:41-60 (saveAPIKey) : ligne 44, UserDefaults.standard.set(apiKey, ...) exécuté EN PREMIER, INCONDITIONNELLEMENT, AVANT la tentative d'écriture Keychain (SecItemAdd, ligne 56)
IOS BEHAVIOR : Toute session active laisse l'apiKey lisible en clair dans Library/Preferences/*.plist, extractible via une sauvegarde iTunes/Finder non chiffrée ou tout accès au sandbox — sans jailbreak nécessaire pour une sauvegarde non chiffrée. deleteAPIKey() nettoie bien les deux emplacements au logout, donc l'exposition est "pendant toute session connectée", pas permanente après déconnexion
CAUSE : Le repli a été ajouté (2026-08-17) pour contourner un échec Keychain silencieux observé UNIQUEMENT en CI avec CODE_SIGNING_ALLOWED=NO (build Appetize non signé) — implémenté comme une écriture systématique inconditionnelle plutôt que gatée sur un échec constaté (status != errSecSuccess, variable déjà présente à des fins de diagnostic mais pas utilisée pour cette garde)
IMPACT : Régression de sécurité réelle par rapport à l'intention de conception documentée du projet lui-même (« Keychain pour apiKey », TIINVER_IOS_PORT_ANALYSIS.md §6.2). L'argument « pas une régression par rapport à Android, qui stocke aussi en clair » est invalide pour justifier de ne pas corriger : le choix du projet était de faire MIEUX qu'Android sur ce point précis, et ce repli inconditionnel annule ce bénéfice en production, pas seulement dans le scénario CI qui l'a motivé
REPRODUCTIBILITÉ : certaine par lecture de code — saveAPIKey est appelée à chaque login réussi
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : FUNCTIONALLY_FAILED (faille de sécurité)
RECOMMANDATION : Gater l'écriture UserDefaults derrière l'échec RÉEL de SecItemAdd (if status != errSecSuccess { UserDefaults... }), après la tentative Keychain et non avant ; supprimer toute copie orpheline dès qu'une écriture Keychain réussit ultérieurement. Envisager un flag de build (#if DEBUG/variable CI) pour restreindre ce repli aux builds non signés spécifiquement.
STATUT : NON CORRIGÉ (audit uniquement)
```

### Domaine : Persistance / Cache

```
ID : V7-F-023
PRIORITÉ : P2
DOMAINE : Persistance/Cache — Purge de compte / documentation de code obsolète
FEATURE : LocalDataPurger.swift justifie l'exclusion de deux caches Core Data de la purge logout/suppression-compte par "aucun écran consommateur à ce jour", affirmation désormais fausse pour les deux
ANDROID SOURCE : transportDataBackground.java:147-181 (deleteaccount(), routé aussi par logout) — ne purge PAS AppDatabase (Room, ViewEvent+AiConversationEntity) — lacune déjà présente côté Android également
IOS FILES : LocalDataPurger.swift:18-25 (commentaire de justification) ; ViewEventRepository.swift:1-10 (propre commentaire, mis à jour V6-F-019, contredisant directement LocalDataPurger) ; AIChatViewModel.swift ; RosterListView.swift:71 (NavigationLink vers AIChatView, écran réellement atteignable)
IOS BEHAVIOR : LocalDataPurger.purgeAll() ne purge ni AiConversationRepository ni ViewEventRepository — or AIChatView est un écran réel atteignable, et AIChatViewModel écrit réellement des conversations (TTL 3 jours côté client). ViewEventRepository a été câblé à un vrai flux réseau la session précédente (V6-F-019)
CAUSE : LocalDataPurger.swift n'a pas été mis à jour quand ViewEventSyncService/AIChatView ont été câblés lors de sessions ultérieures — dérive de documentation
IMPACT : Le filtrage par userId empêche une fuite visible immédiate entre comptes sur un appareil partagé, mais l'intention affichée par l'utilisateur (déconnexion, suppression de compte) n'est pas honorée pour ce contenu potentiellement sensible (conversations IA), qui persiste jusqu'à expiration naturelle au lieu d'être supprimé immédiatement. Risque documentaire pour un futur mainteneur
REPRODUCTIBILITÉ : certaine
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : décision produit nécessaire
RECOMMANDATION : Mettre à jour le commentaire de LocalDataPurger.swift pour refléter l'état réel ; envisager d'ajouter la purge d'AiConversationRepository/ViewEventRepository à purgeAll(), en particulier pour le flux "suppression de compte".
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-024
PRIORITÉ : P2
DOMAINE : Persistance/Cache — Migration de schéma Core Data
FEATURE : Aucune chaîne de versions de modèle ni filet de sécurité pour les 3 stores Core Data, contrairement aux mécanismes de migration Android
ANDROID SOURCE : AppDatabase.java:12-33 (Room, fallbackToDestructiveMigration()) ; Dbase.java (SQLiteOpenHelper, SCHEMA_VERSION=26, chaîne de migration incrémentale éprouvée depuis 2018)
IOS FILES : CoreDataStack.swift, AnalyticsCoreDataStack.swift, NotiCoreDataStack.swift ; les 3 .xcdatamodeld ne contiennent chacun qu'UNE SEULE version de modèle
IOS BEHAVIOR : Aucun NSPersistentStoreDescription configuré, aucun repli — en cas d'échec de chargement du store, fatalError() : crash immédiat et systématique au lancement pour TOUS les utilisateurs, jusqu'à correction et nouvelle soumission App Store
CAUSE : Le port initial n'a pas encore eu besoin de faire évoluer son schéma
IMPACT : Latent — aucun bug aujourd'hui, mais le jour où un attribut/une relation change dans un des 3 modèles sans version+mapping, crash au démarrage pour tous les utilisateurs (contrairement à Android qui perd juste le cache silencieusement)
REPRODUCTIBILITÉ : incertaine (ne se manifeste qu'au prochain changement de schéma)
NIVEAU DE CONFIANCE : haute (absence de configuration confirmée par grep exhaustif)
VALIDATION : CODE_VERIFIABLE (le risque lui-même ne sera observable qu'à la prochaine évolution de schéma)
SUGGESTED_STATUS : à corriger avant la première évolution de schéma
RECOMMANDATION : Ajouter un NSPersistentStoreDescription avec repli explicite (catch + destroyPersistentStore + recréation) pour approcher fallbackToDestructiveMigration() ; documenter la procédure de versionnement de modèle à suivre.
STATUT : NON CORRIGÉ (audit uniquement)
```

### Domaine : UI/UX/Navigation

```
ID : V7-F-025
PRIORITÉ : P3
DOMAINE : UI-UX-Navigation — Action non câblée (bouton mort)
FEATURE : Le bouton "Fermer" de la barre d'outils de la feuille de commentaires ne fait rien
ANDROID SOURCE : N/A — Android n'a pas de bouton de fermeture explicite (fermeture par balayage/tap extérieur du BottomSheetDialogFragment standard)
IOS FILES : CommentsView.swift:65 (Button("Fermer") {} — closure vide)
IOS BEHAVIOR : Le bouton est visible et cliquable mais sa closure est vide. La feuille reste néanmoins fermable par balayage vers le bas (comportement .sheet par défaut), donc l'utilisateur n'est pas bloqué
CAUSE : Oubli — closure jamais remplie
IMPACT : Mineur — confusion pour un utilisateur qui s'attend à ce que "Fermer" fasse quelque chose, mais aucune fonctionnalité bloquée
REPRODUCTIBILITÉ : certaine
NIVEAU DE CONFIANCE : haute
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : fix trivial
RECOMMANDATION : Ajouter @Environment(\.dismiss) private var dismiss et appeler dismiss() dans la closure (CommentsView.swift:65).
STATUT : NON CORRIGÉ (audit uniquement)
```

### Domaine : Transversal — Réseau / Concurrence

*(Voir aussi `v7_transversal.md` pour le tableau complet du balayage exhaustif des ~187 sites
`Task {}` du projet, action explicitement laissée ouverte par le cycle V6.)*

```
ID : V7-F-026
PRIORITÉ : P2
DOMAINE : Transversal — Debounce recherche pays (Boost) — course de réponses obsolètes
FEATURE : Recherche de pays lors de la création d'un Boost — le correctif de garde de réponse obsolète appliqué ailleurs dans le projet (V6-F-012) n'a pas été répliqué ici
ANDROID SOURCE : N/A — pas une régression Android, une incohérence interne iOS (le pattern correct existe déjà dans 2 endroits soeurs du même dépôt)
IOS FILES : CreateBoostView.swift:191-200 (scheduleCountrySearch) — Task.isCancelled vérifié UNE SEULE FOIS juste après le sommeil de debounce, PAS après le retour de l'appel réseau AdsRepository.searchTags avant d'écrire countrySuggestions. Comparer avec ChatSearchView.swift:126-133 et NewMessageView.swift:105-116, qui re-vérifient Task.isCancelled APRÈS l'appel réseau
IOS BEHAVIOR : Une réponse lente pour une frappe ancienne peut arriver après une réponse plus récente et l'écraser
CAUSE : Garde manquante après le second point de suspension (l'appel réseau)
IMPACT : L'utilisateur tapant rapidement un nom de pays peut voir la liste de suggestions revenir à un état obsolète — confusion UI mineure, pas de perte de données ni d'impact financier (le champ pays n'est qu'une saisie assistée)
REPRODUCTIBILITÉ : probable (latence réseau variable entre deux frappes rapprochées)
NIVEAU DE CONFIANCE : haute (comparaison directe avec 2 implémentations soeurs correctement gardées)
VALIDATION : CODE_VERIFIABLE
SUGGESTED_STATUS : OPEN
RECOMMANDATION : Ajouter guard !Task.isCancelled else { return } immédiatement après l'await searchTags, avant d'assigner countrySuggestions — même correctif déjà en place dans ChatSearchView.swift.
STATUT : NON CORRIGÉ (audit uniquement)
```

```
ID : V7-F-027
PRIORITÉ : P2
DOMAINE : Transversal — Synchronisation réseau concurrente / idempotence (ViewEventSyncService)
FEATURE : Envoi différé des événements de visionnage vers addview — aucune garde de réentrance entre les 2 déclencheurs indépendants
ANDROID SOURCE : ViewTracker.java:100-122 — le job périodique utilise enqueueUniquePeriodicWork(WORK_NAME, KEEP, ...), déclenchements jamais chevauchés entre eux ; le déclenchement immédiat n'est en revanche pas explicitement exclu du périodique (risque théorique symétrique côté Android, non vérifié en profondeur)
IOS FILES : ViewEventSyncService.swift:30-58 (sync()) ; appelants FeedView.swift:967-968 (seuil) et RootRouterView.swift:105 (retour au premier plan)
IOS BEHAVIOR : sync() n'a aucun verrou de réentrance — les deux sites peuvent se déclencher à quelques instants d'intervalle (ex. retour au premier plan pile au moment où le seuil de 5 événements est atteint), lisant le même lot pending(), chacun envoyant un POST addview pour les mêmes lignes, chacun tentant repo.delete(localId:) — double comptage de vue côté serveur avant que la première suppression locale n'ait pu s'exécuter
CAUSE : Absence de garde de réentrance/mutex sur ViewEventSyncService.sync(), contrairement au pattern enqueueUniqueWork côté Android
IMPACT : Faible — inflation mineure et non visible du compteur de vues côté serveur dans une fenêtre de course étroite ; aucune perte de données, aucun impact financier direct (endpoint semble être un simple compteur addview)
REPRODUCTIBILITÉ : incertaine — fenêtre de course étroite, plausible en usage réel (retour d'arrière-plan pendant scroll actif)
NIVEAU DE CONFIANCE : moyenne — confirmé par lecture de code (pas de verrou), mais idempotence réelle du endpoint serveur non vérifiable côté client (possible SHARED_BACKEND_ISSUE, impact potentiellement nul si le serveur déduplique déjà)
VALIDATION : PHYSICAL_VALIDATION_REQUIRED
SUGGESTED_STATUS : OPEN — à confirmer avec l'équipe backend (idempotence de addview) avant priorisation
RECOMMANDATION : Ajouter un flag statique isSyncing (booléen simple) dans ViewEventSyncService, vérifié/positionné en tête de sync() avec defer { isSyncing = false }, pour rendre les deux déclencheurs mutuellement exclusifs.
STATUT : NON CORRIGÉ (audit uniquement)
```

---

## 8. Éléments nécessitant une investigation future (pas des findings confirmés)

- **Écrans d'appel et migration Android 16** — l'agent ChatGroup a repéré via archéologie git 3
  commits Android récents (`3f9dc83`, `956db38`, `0d34592`, migration Android 16) touchant la gestion
  du bouton retour système / swipe-back sur les écrans d'appel (`CallActivity`/`IncomingCallActivity`
  — routage désormais unifié vers le même chemin de raccrochage que les boutons on-screen). L'agent
  n'a PAS eu le budget de vérifier si l'équivalent iOS (navigation SwiftUI/geste de retour sur l'écran
  d'appel) raccroche proprement le WebRTC en cas de retour système. Ce domaine "Calls" n'était couvert
  par AUCUN des 10 agents de ce cycle de façon dédiée — candidat sérieux pour un futur cycle V8 ou une
  vérification ciblée.
- **`AVPlayer` en arrière-plan** — le comportement exact de pause automatique garantie ou non selon
  `AVAudioSession`/background modes n'a pas été vérifié ; pertinent pour borner la fenêtre réelle de
  surcomptage de V7-F-015.
- **Idempotence serveur de `addview`** — non vérifiable côté client seul (V7-F-027) ; à confirmer
  avec l'équipe backend avant priorisation.
- **Backend du champ `type` de groupe** — non vérifiable côté client seul (V7-F-009) ; à confirmer si
  le champ est comparé de façon stricte quelque part côté serveur.

## 9. Rappel — éléments déjà connus, hors périmètre de correction de code (ne pas re-flaguer)

Confirmés toujours d'actualité pendant ce cycle, cités seulement pour cohérence documentaire :
- `V4-F-003` (pas de vrais Universal Links — nécessite une entitlement Associated Domains + AASA
  hébergé côté serveur, pas du code Swift pur) et `V4-F-004` (pas d'extension de partage iOS —
  nécessite un nouveau target Xcode) — tous deux `BLOQUÉ`, infrastructure/projet, pas corrigibles par
  du code isolé.
- `V3-F-140` (vérification serveur StoreKit 2 toujours absente — `storekit/verify-purchase`
  n'existe toujours pas côté backend) — `FUNCTIONALLY_FAILED`, dépend d'un endpoint backend à créer.
- `V5-F-082`/`V6-F-026` (habillage promotionnel outro/watermark export/téléchargement Animems) —
  `DIFFÉRÉ`, infrastructure de post-traitement vidéo substantielle jugée disproportionnée pour ce
  cycle.
- `V6-F-017` (ping quotidien `boost/deliver`) — `DIFFÉRÉ`, dépend du chantier `BGTaskScheduler` déjà
  différé pour `V5-F-060`.

---

## 10. Inventaire final des 27 findings V7

| ID | Priorité | Domaine | Statut suggéré |
|---|---|---|---|
| V7-F-001 | P2 | Animems Éditeur | MISSING |
| V7-F-002 | P2 | Animems Éditeur | PARTIAL |
| V7-F-003 | P3 | Animems Éditeur | VISUALLY_DIFFERENT |
| V7-F-004 | P1 | Animems Export | FUNCTIONALLY_FAILED |
| V7-F-005 | P2 | Animems Export | PARTIAL |
| V7-F-006 | P2 | Animems Export | PARTIAL |
| V7-F-007 | P1 | ChatGroup | MISSING |
| V7-F-008 | P2 | ChatGroup | MISSING |
| V7-F-009 | P3 | ChatGroup | VISUALLY_DIFFERENT |
| V7-F-010 | P3 | ChatGroup | IOS_INTENTIONAL_DIFFERENCE |
| V7-F-011 | P3 | Search | IOS_INTENTIONAL_DIFFERENCE |
| V7-F-012 | P2 | Promotion | MISMATCH |
| V7-F-013 | P2 | Promotion | MISMATCH |
| V7-F-014 | P3 | Promotion | IOS_INTENTIONAL_DIFFERENCE |
| V7-F-015 | P1 | Video Statistics | NOUVEAU |
| V7-F-016 | P2 | Video Statistics | NOUVEAU (validation urgente) |
| V7-F-017 | P3 | Video Statistics | NOUVEAU |
| V7-F-018 | P3 | Video Statistics | NOUVEAU |
| V7-F-019 | P2 | Feed/Profile (Notifications) | FUNCTIONALLY_FAILED |
| V7-F-020 | P2 | Notifications | VISUALLY_DIFFERENT |
| V7-F-021 | P2 | Notifications | SHARED_BACKEND_ISSUE |
| V7-F-022 | P0 | Auth/Sécurité | FUNCTIONALLY_FAILED (sécurité) |
| V7-F-023 | P2 | Persistance/Cache | décision produit |
| V7-F-024 | P2 | Persistance/Cache | à corriger avant évolution schéma |
| V7-F-025 | P3 | UI/UX | fix trivial |
| V7-F-026 | P2 | Transversal | OPEN |
| V7-F-027 | P2 | Transversal | OPEN (shared backend possible) |

Aucun finding V5/V6 recréé — vérifié par grep systématique de chaque domaine contre les deux
documents précédents avant rédaction de ce rapport (voir `MIGRATION_PARITY_PROGRESS_V7.md` pour le
détail par agent des vérifications négatives).
