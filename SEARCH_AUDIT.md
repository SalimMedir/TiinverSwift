# SEARCH_AUDIT.md — Audit complet du système de recherche (global + chat/messages)

Date : 2026-09-03
Portée : recherche universelle (publications/utilisateurs/hashtags), recherche de conversations
(roster), recherche dans une conversation ouverte. Comparaison ligne à ligne Android (source de
vérité) vs iOS. Audit uniquement — **aucun fichier de code n'a été modifié pendant cette passe.**

---

## 1. Résumé exécutif

Le bug rapporté (`SearchView` affiche "Erreur de chargement." pour une recherche normale, ex.
"Salim") a une cause racine **identifiée avec un niveau de confiance élevé, mais non confirmée à
100 % faute d'une capture réseau réelle** (aucun device/simulateur disponible dans cet
environnement, conformément à la contrainte donnée).

**Cause racine (CRITIQUE)** — `SearchRepository.decodeResults(_:isFull:tab:)`
(`Sources/TiinverSwift/Discover/SearchRepository.swift:65-75`) teste le champ `"error"` de
l'enveloppe backend avec `value.bool("error")`, une méthode qui **n'accepte qu'un booléen JSON natif
Swift** et échoue silencieusement (`typeMismatch`, avalé par `try?`) sur toute autre forme. Or
l'analyse du code Android réellement exécuté par `searchFull`/`searchSuggest`
(`RechercheTiinver.java:433-459,412-431` → `TransportData.get()`, `Http/TransportData.java:537-563`)
montre que `TransportData.get()` fait `response.getString(ERROR)` **avant même d'invoquer le
callback** — `JSONObject.getString()` (org.json) lève une `JSONException` sur toute valeur qui n'est
PAS une chaîne. Comme cette exception n'est pas catchée sur ce chemin précis (elle serait
re-levée en `RuntimeException`, ce qui ferait planter l'app à CHAQUE recherche — non observé/non
documenté), le champ `"error"` de cet endpoint est très vraisemblablement la **chaîne** `"false"`/
`"true"` (convention standard de ce backend, voir `JSONValue.isBackendSuccess`), **PAS un booléen
JSON natif** comme l'affirme à tort le commentaire actuel de `decodeResults` (lignes 35-38 du
fichier, citant par erreur `object.getBoolean("error")` dans `parseAndDisplay` comme preuve — cette
méthode org.json accepte EN RÉALITÉ aussi bien un booléen natif qu'une chaîne `"true"/"false"`, ce
qui invalide la déduction faite).

Conséquence : `value.bool("error")` échoue TOUJOURS (succès comme échec), donc le court-circuit
`return SearchResults()` prévu pour un `"error":"true"` gracieux (Android : `showEmpty("Aucun
résultat")`, silencieux) **ne se déclenche jamais**. Sur toute réponse backend où `"error"` vaut
`"true"` (chaîne) — ce qui, empiriquement, semble être exactement ce qui se produit pour certaines
recherches valides comme "Salim" — le code tombe dans `guard let data =
value["results"]?.rawData else { throw APIError.server(message: "results manquant") }`, la clé
`"results"` étant vraisemblablement absente sur ce type de réponse, ce qui déclenche l'erreur,
remontée telle quelle jusqu'à `SearchView.runSearch`'s `catch`, qui affiche indistinctement
**"Erreur de chargement."** — exactement le symptôme rapporté.

**Preuve corroborante interne au repo** : `GroupRepository.searchGroups`
(`Sources/TiinverSwift/Messagerie/GroupRepository.swift:142-158`), qui interroge un endpoint
`search/{myId}/{query}` du MÊME backend, utilise correctement `value.isBackendSuccess` (la
convention documentée et éprouvée, cf. incident "login" du 2026-08-17 dans `JSONValue.swift:118-137`)
— **PAS** `value.bool("error")`. `SearchRepository.decodeResults` est donc la SEULE fonction de
recherche du repo à diverger de la convention établie, sans preuve réseau réelle à l'appui de cette
divergence (contrairement au cas `notification2/{userId}` cité en comparaison, qui lui a une preuve
directe dans `NotificationRepository.java`).

**2e finding HIGH** : le message d'erreur générique "Erreur de chargement." masque en réalité
au moins 5 causes distinctes possibles côté iOS (échec réseau/HTTP non-2xx, `error:"true"` mal
détecté — ci-dessus —, `results` réellement absent, JSON malformé, timeout) sans aucune
télémétrie/logging permettant de les distinguer en production — déjà partiellement connu
(`V4-F-037`, différé car jugé "cosmétique" à l'époque, mais qui masque en réalité le bug CRITIQUE
ci-dessus).

**3e finding MEDIUM** : l'en-tête `Authorization` est envoyé de façon conditionnelle côté iOS
(`APIClient.headers()` : `if let apiKey = ...`) alors qu'Android l'envoie **inconditionnellement**
(`TransportData.get():601`, `headers.put("Authorization", apiKey)`, même si `apiKey` est `null`).
Si `UserSession.shared.apiKey` est `nil` au moment de la recherche (session pas encore
rafraîchie, edge case de démarrage), iOS omet complètement l'en-tête au lieu d'envoyer une valeur
vide/null — un serveur strict sur la présence de l'en-tête (indépendamment de sa valeur) se
comporterait différemment entre les deux plateformes. Non confirmé comme cause du bug rapporté
(l'utilisateur est presumé connecté), mais divergence réelle de parité.

**Recherche dans une conversation ouverte (message search)** : **fonctionnalité INEXISTANTE côté
Android** (confirmé par grep exhaustif sur `messagerie/ui/*.java`, `ActivityMsg.java` inclus — 0
occurrence de recherche de messages). L'icône "search" trouvée dans les réglages de groupe
(`SettingGroupMessageFragmant.java:296-306`) ouvre `FilterGroupMemberList` (recherche de MEMBRES,
pas de messages). iOS ne l'implémente pas non plus (`ChatView.swift`/`ChatViewModel.swift` : 0
occurrence) — **conforme par absence symétrique**, ce n'est PAS un écart à corriger.

**Recherche de conversations (roster / "chat" search)** : déjà portée fidèlement
(`ChatSearchView.swift`), y compris le repli serveur `search/{myId}/{str}`
(`GroupRepository.searchGroups`) signalé MANQUANT lors d'un audit antérieur (V2, ligne 408) et
depuis corrigé — confirmé correctement fermé, aucune régression trouvée.

---

## 2. Architecture Android

### 2.1 Recherche universelle (posts/utilisateurs/hashtags)

Fichier unique : `app/src/main/java/com/tiinver/Recherche/ui/RechercheTiinver.java` (754 lignes).
Activity partagée par DEUX écrans distincts via l'extra `tokenSearch` (`"universal"` | `"chat"`).

- `Recherche/SearchRepository.java` : **vide** (4 lignes, `public class SearchRepository {}`),
  confirmé — toute la logique réseau vit dans l'Activity elle-même (`td.get(...)`, `TransportData`).
- `RechercheTiinver2.java` (681 lignes) : confirmé **mort** par grep exhaustif (aucune référence
  `new RechercheTiinver2(...)` ni `RechercheTiinver2.class` ailleurs dans le code), non audité en
  détail — non pertinent pour le bug.
- `models/search/SearchResultModel.java` (179 lignes) : modèle unifié pour TOUS les types de
  résultat (`TYPE_HEADER`/`TYPE_USER`/`TYPE_POST`/`TYPE_HASHTAG`), rempli par `parseAndDisplay`.
- `Recherche/ui/RecentSearchManager.java` (69 lignes, lu en entier) : historique local
  `SharedPreferences`, 10 entrées max, stockage `"|||"`-joint, plus récent en tête.
- `Recherche/ui/UniversalSearchAdapter.java` : `RecyclerView.Adapter` de rendu, contient la
  logique de navigation au tap (post → plein écran, hashtag → feed hashtag, utilisateur → profil +
  bouton "Suivre" inline) et le fallback CDN thumbnail des posts (`cdn_thumbnail_url` →
  `cdn_content_url` → fond gris, PostViewHolder.bind()).

**Endpoints réels (`td.get`, GET, via `Http/TransportData.java:537-613`)** :

| Fonction Android | Endpoint exact | Déclenchement |
|---|---|---|
| `searchSuggest(query)` (`:412-431`) | `content/search/suggest?q=<query NON encodé>` | query.length() ≥ 1, debounce 300ms, ou query 1 caractère |
| `searchFull(query, tab)` (`:433-459`) | `content/search?q=<query>&types=<types>&limit=10&offset=0` | query.length() ≥ 2, submit clavier, changement d'onglet, tap historique |

`types` = `getTypesForTab(tab)` (`:376-383`) : `"posts"` / `"users"` / `"hashtags"` / par défaut
(`"all"`) → `"users,posts,hashtags"`.

**Aucun `URLEncoder.encode()` n'est appliqué à `query`** avant concaténation dans l'URL côté
Android — la requête part telle quelle vers Volley/OkHttp, qui gère l'encodage UTF-8/percent-encoding
au niveau transport (`OkHttpStack`, non audité en détail ici, hors scope du bug rapporté).

**Enveloppe réponse attendue par `TransportData.get()` (AVANT même d'atteindre `RechercheTiinver`)**,
`Http/TransportData.java:544-563` :
```java
public void onResponse(JSONObject response) {
    if (callback != null) {
        String error = null;
        try {
            error = response.getString(ERROR);          // ← EXIGE une STRING, lève JSONException sinon
            if (error.equals("false")) {
                callback.onResonse(context, 0, response); // succès → parseAndDisplay est appelé
            } else {
                callback.onError("");                      // "error" présent et != "false" → onError("")
            }
        } catch (JSONException e) {
            throw new RuntimeException(e);                 // non catché plus haut → crash si "error" n'est PAS une String
        }
    }
}
```
`getBodyContentType()`/`getHeaders()` (`:596-607`) : `Content-Type: application/json; charset=utf-8`,
`Accept: application/json`, `Authorization: <apiKey brut>` (**toujours envoyé**, même si `apiKey`
est `null`).

**Enveloppe réponse attendue par `parseAndDisplay` (`:461-573`)**, UNIQUEMENT atteint quand
`TransportData.get()` a déjà validé `error == "false"` :
```java
boolean error = object.getBoolean("error");     // org.json coerce "false"/"true" (String) OU Boolean natif — TOUJOURS false ici (déjà filtré en amont)
if (error) { showEmpty("Aucun résultat"); return; }   // code mort en pratique sur ce chemin précis
JSONObject results = object.getJSONObject("results"); // OBLIGATOIRE — objet, pas tableau
// results.has("users")   → JSONArray "users"   : id(int, requis), username, firstname, lastname,
//                           profile, certified(bool), isFollowed(bool), followers(String),
//                           following(String), location, biography, category
// results.has("hashtags") → JSONArray "hashtags" : tag, post_count(int), total_views(int)
// results.has("posts")    → JSONArray "posts" (SEULEMENT si isFull==true) : id(int, requis),
//                           token, verb, object, object_url, message, likes(int), comment(int),
//                           views(int), stamp, cdn_thumbnail_url, cdn_content_url, cdn_provider,
//                           cdn_content_id, isLiked(bool), actor(int, requis), username,
//                           firstname, profile, isCertified(int 0/1)
```
Chaque section utilise `results.has("<clé>")` — **la clé entière est absente** de la réponse pour
une catégorie non pertinente par rapport au `tab`/`types` demandé (pas une valeur `null`, pas un
tableau vide) — confirmé par le commentaire déjà présent côté iOS (`SearchModels.swift:145-156`,
trouvé lors d'un test Appetize réel antérieur).

Gestion erreur réseau (`Response.ErrorListener`, `:564-593`) : log Volley, tentative de parser le
corps d'erreur en JSON (log seulement, pas exploité), puis `callback.onError(error.getMessage())`.
`searchFull.onError` (`:451-455`) affiche TOUJOURS **"Erreur de chargement"** (texte fixe, pas de
distinction entre panne réseau, HTTP non-2xx, ou `error:"true"` métier).
`searchSuggest.onError` (`:423-427`) affiche **"Aucun résultat"** (texte neutre, différent).

### 2.2 Recherche de conversations / groupes ("chat" mode) — même Activity

`tokenSearch == "chat"` (`:192-197`) : pas d'onglets, `RetrieveContacts(null)` initial (liste
complète locale), puis à chaque frappe `RetrieveContacts(str)` (**PAS de debounce sur ce chemin**,
contrairement au mode "universal").

`RetrieveContacts(str)` (`:584-685`) :
1. Requête un `Cursor` LOCAL (`ContentResolver.query(infoContract.MSG_URI, ...)`, tri
   `"conversationId"`) — équivalent Android d'une base locale de conversations déjà connues.
2. Pour chaque ligne : construit un `MessageLib`, puis SI `str` non vide, filtre en mémoire :
   `title.toLowerCase().contains(str.toLowerCase()) || message.toLowerCase().contains(...) ||
   subTitle.toLowerCase().contains(...)` — 3 champs (titre, dernier message, sous-titre),
   insensible à la casse, substring simple (pas de normalisation Unicode/accents particulière).
3. Si **aucune** ligne locale ne matche (`searchOnLocal == false`) → repli serveur
   `getItFromServeur(str, mChatAdapter)`.

`getItFromServeur` (`:687-726`) : `td.volleyGet(null, "search/" + myId + "/" + str, "search",
callback)` → GET, réponse attendue `{"data": [ {...GroupModel...}, ... ]}` (désérialisé via Gson
`GroupModel[].class`), chaque groupe transformé en `MessageLib`/conversation "rejoignable" (pas
encore membre).

### 2.3 Recherche de messages DANS une conversation ouverte

**Fonctionnalité INEXISTANTE côté Android.** Grep exhaustif (`search`/`Search`, insensible à la
casse) sur tout `messagerie/ui/*.java` (dont `ActivityMsg.java`, `ChatFragmentTest.java`,
`MessageListView.java`, `MessageRecyclerView.java`) : aucune occurrence pertinente. Les seules
occurrences de "search" dans cet arbre sont :
- `ChatFragmentTest.java:1267,1845` : `performFileSearch()` — sélecteur de FICHIER (`Intent.
  ACTION_OPEN_DOCUMENT`), sans rapport avec la recherche de messages.
- `SettingGroupMessageFragmant.java:296-306` : bouton "search" des réglages de groupe → ouvre
  `FilterGroupMemberList` (recherche parmi les MEMBRES du groupe), pas les messages échangés.

Aucun écran Android ne permet de chercher un mot-clé parmi les messages d'une conversation déjà
ouverte, ni de naviguer vers un message trouvé. Ce n'est donc pas un écart de portage — c'est une
fonctionnalité qui n'existe simplement pas dans l'app de référence.

---

## 3. Architecture iOS

### 3.1 Recherche universelle

| Couche | Fichier |
|---|---|
| UI | `Sources/TiinverSwift/Discover/SearchView.swift` |
| Modèles + décodage enveloppe | `Sources/TiinverSwift/Discover/SearchModels.swift` |
| Réseau | `Sources/TiinverSwift/Discover/SearchRepository.swift` |
| JSON dynamique | `Sources/TiinverSwift/Networking/JSONValue.swift` |
| Client HTTP | `Sources/TiinverSwift/Networking/APIClient.swift` |

`SearchRepository.suggest(query:)` (`:19-26`) → `GET content/search/suggest?q=<percent-encoded>`,
`decodeResults(value, isFull: false, tab: .all)` — `"all"` en dur, fidèle à Android.
`SearchRepository.search(query:tab:)` (`:29-33`) → `GET content/search?q=<percent-encoded>&types=
<tab.apiTypes>&limit=10&offset=0` — `apiTypes` (`SearchModels.swift:178-185`) reproduit
`getTypesForTab` à l'identique (`"users,posts,hashtags"` / `"posts"` / `"users"` / `"hashtags"`).

`decodeResults` (`SearchRepository.swift:65-75`, voir §1 pour le détail du bug) :
```swift
private static func decodeResults(_ value: JSONValue, isFull: Bool, tab: SearchTab) throws -> SearchResults {
    guard (try? value.bool("error")) != true else { return SearchResults() }
    guard let data = value["results"]?.rawData else {
        throw APIError.server(message: "results manquant")
    }
    var results = try JSONDecoder().decode(SearchResults.self, from: data)
    if tab != .all, tab != .users { results.users = [] }
    if tab != .all, tab != .hashtags { results.hashtags = [] }
    if !isFull || (tab != .all && tab != .posts) { results.posts = [] }
    return results
}
```
`SearchResults.init(from:)` (`SearchModels.swift:166-171`) décode chaque tableau avec
`decodeIfPresent(...) ?? []`, fidèle à `results.has(...)` Android. `SearchUserResult`/
`SearchPostResult` utilisent un décodage tolérant (`decodeLenientInt`/`decodeLenientBoolIfPresent`)
pour absorber les incohérences de type observées sur ce backend (`id`/`actor` parfois en chaîne).

`SearchView.swift` : debounce 300ms (`Task.sleep(300_000_000)`, fidèle à `DEBOUNCE_DELAY_MS = 300`),
seuils identiques (`suggest` dès 1 caractère, `search` dès 2), soumission clavier court-circuite le
debounce (`onSubmit(of: .search)`), jeton de génération anti-race-condition (`searchGeneration`,
amélioration volontaire au-delà de la parité stricte, documentée comme telle), grille 3 colonnes
pour les posts (`GridLayoutManager(this,3)`), navigation résultat → profil/hashtag/plein-écran avec
rechargement frais par token avant affichage (`openDetail`, fidèle à `UniversalSearchAdapter.java:
298-306`).

### 3.2 Recherche de conversations (roster) — `ChatSearchView.swift`

Filtre LOCAL d'abord sur `RosterListViewModel.rows` (titre/sous-titre/dernier message, insensible à
la casse, substring — fidèle aux 3 champs Android), repli serveur `GroupRepository.searchGroups`
UNIQUEMENT si le filtre local est vide, debounce 300ms sur le repli serveur uniquement (fidèle :
Android ne debounce pas non plus le filtre local, seul le fallback réseau a une latence naturelle).

`GroupRepository.searchGroups(myId:query:)` (`GroupRepository.swift:142-158`) → `GET
search/<myId>/<percent-encoded query>`, utilise **correctement** `value.isBackendSuccess` +
`value.looselyEncodedJSON("data")?.toArray()` — cohérent avec la convention documentée du backend,
contrairement à `SearchRepository.decodeResults`.

### 3.3 Recherche de messages dans une conversation ouverte

**Non implémentée** (`ChatView.swift`, `ChatViewModel.swift` : 0 occurrence de "search"/"Search").
Conforme à l'absence de cette fonctionnalité côté Android (§2.3) — **pas un écart**.

---

## 4. Recherche publications

| Aspect | Android | iOS |
|---|---|---|
| Endpoint | `content/search?q=&types=posts\|users,posts,hashtags&limit=10&offset=0` | Identique |
| Champ requis | `results.posts[].id` (int), `.actor` (int) | `SearchPostResult.id`/`.actor` non-optionnels, décodage tolérant |
| Visible seulement si | `isFull==true` (jamais sur `searchSuggest`) | `decodeResults` vide `posts` si `!isFull` — conforme |
| Miniature | `cdn_thumbnail_url` → `cdn_content_url` → gris (`UniversalSearchAdapter.java:270-282`) | `SearchPostResult.thumbnailURL` — même fallback à 2 étages, corrigé le 2026-08-25 (V5-F-010) |
| Tap → détail | `activityId`/`userId`/`type` seuls transmis, recharge par ID (`:298-306`) | `openDetail` recharge par `token` via `FeedRepository.fetchPost(byToken:)`, repli sur données de recherche si échec réseau |
| Layout | Grille 3 colonnes (`GridLayoutManager(this,3)`) | `LazyVGrid` 3 colonnes — conforme |

Aucun écart non déjà corrigé identifié sur ce sous-système.

---

## 5. Recherche utilisateurs

| Aspect | Android | iOS |
|---|---|---|
| Champs | `id,username,firstname,lastname,profile,certified,isFollowed,followers,following,location,biography,category` (tous `optString`/`optBoolean` sauf `id`) | `SearchUserResult` — mêmes champs, `id` seul non-optionnel (décodage tolérant `decodeLenientInt`) |
| Bouton "Suivre" inline | `UniversalSearchAdapter.java:225-247`, PAS de bascule "ne plus suivre" | `followButton`/`toggleFollow` — même sens unique, rollback local sur échec (corrigé V3-F-107) |
| Filtrage par onglet | `showUsers = tab=="all"\|\|tab=="users"`, appliqué CÔTÉ CLIENT indépendamment de la clé JSON présente | `decodeResults` vide `users` hors `.all`/`.users` — conforme (corrigé V5-F-011) |

Aucun écart non déjà corrigé.

---

## 6. Recherche hashtags

| Aspect | Android | iOS |
|---|---|---|
| Champs | `tag`(String), `post_count`(int), `total_views`(int) | `SearchHashtagResult` — identique |
| Préfixe `#` en query live | Non strippé — envoyé tel quel au serveur si tapé directement (`onQueryTextChange` ne touche pas au `#`) | `SearchView.swift` — même comportement, `query` transmis tel quel |
| Historique préfixé | `buildDisplayEntry`: `"#"+query` si `tab=="hashtags"`, dépouillé au clic (`entry.substring(1)`) | `displayEntry`/`selectRecent` — logique identique (corrigé V3-F-103/V4-F-035) |
| Affichage compteurs | `"{n} publication(s)"` + vues formatées (`HashtagViewHolder.bind`) | `hashtagRow` — même format (corrigé V3-F-101) |

Aucun écart non déjà corrigé. Caractères Arabes/accentués : ni Android ni iOS n'appliquent de
normalisation Unicode particulière à la query — comportement dépendant uniquement du moteur de
recherche backend, hors scope du portage client.

---

## 7. Recherche globale ("all" — combinée)

`types="users,posts,hashtags"` envoyé identiquement des deux côtés. Android affiche chaque section
seulement si `results.has(<clé>)` ET (`tab=="all"` OU `tab==<clé correspondante>`) — la garde
`isFull` s'applique en plus pour `posts`. iOS reproduit les 3 gardes (`tab`, `isFull`) après les
corrections V3-F-106/V5-F-011 déjà appliquées. **Pagination** : `limit=10&offset=0` fixes des DEUX
côtés — **ni Android ni iOS n'implémentent de pagination réelle** (pas de "charger plus", `offset`
toujours à 0) ; ce n'est pas un écart de portage, c'est une limite du produit Android reproduite
telle quelle.

**Résultats vides** : Android → `showEmpty("Aucun résultat pour \"" + lastQuery + "\"")` si
`!hasResults` après filtrage ; iOS → texte équivalent (`SearchView.swift:139-142`), conforme.

**Erreurs API** : voir §1/§10 — c'est le point de divergence CRITIQUE de tout l'audit.

---

## 8. Recherche chat/messages

Couvre les 3 sous-cas explicitement distingués par la demande :

1. **Recherche globale de conversations dans l'app** (bouton loupe du roster,
   `tokenSearch="chat"` côté Android / `ChatSearchView.swift` côté iOS) : voir §2.2/§3.2 — **conforme**,
   y compris le repli serveur `search/{myId}/{query}` correctement implémenté et utilisant la bonne
   convention d'enveloppe (`isBackendSuccess`).
2. **Recherche dans la liste des conversations** : c'est le MÊME écran que (1) sur Android (une
   seule Activity, un seul mode `"chat"`) — pas d'écran séparé. iOS reproduit ceci fidèlement en un
   seul `ChatSearchView.swift`, pas de distinction supplémentaire nécessaire.
3. **Recherche DANS une conversation ouverte** (retrouver un message précis dans un fil déjà
   ouvert) : voir §2.3/§3.3 — **fonctionnalité absente des deux côtés**, conforme par absence.

Points vérifiés spécifiquement demandés :
- **Debounce** : Android n'a PAS de debounce sur le filtre local du mode "chat" (chaque frappe
  relance `RetrieveContacts` synchrone sur le curseur local) ; iOS non plus (`localMatches` est un
  computed property réévalué à chaque frappe, pas de `Task.sleep`) — SEUL le repli serveur a un
  debounce des deux côtés. Conforme.
- **Query vide/changée** : Android réaffiche la liste complète locale quand `str` est vide/null
  (`RetrieveContacts(null)` au chargement initial et à l'effacement) ; iOS fait de même
  (`localMatches` retourne `rosterViewModel.rows` quand `q.isEmpty`, corrigé V6-F-014). Conforme.
- **Messages supprimés/médias** : hors-sujet ici — aucun des deux côtés ne recherche dans le
  CONTENU média d'un message (seul le texte `message`/titre/sous-titre est comparé), et cette
  recherche porte sur des CONVERSATIONS, pas des messages individuels (voir point 3 ci-dessus pour
  la recherche de messages, absente).
- **Pagination** : aucune des deux plateformes ne pagine cette liste (résultats locaux + un seul
  appel serveur de repli, sans `limit`/`offset`).
- **Navigation vers résultat** : Android ouvre `ActivityMsg` directement (pas d'étape de
  confirmation) qu'il s'agisse d'un résultat local ou serveur ; iOS fait de même
  (`openTarget` → `ChatView(target:)` directement). Conforme.

---

## 9. Tableau Android vs iOS

| Fonctionnalité | Android | iOS | Conforme ? | Problème |
|---|---|---|---|---|
| Endpoint suggestion | `content/search/suggest?q=` | Identique | ✅ | — |
| Endpoint recherche complète | `content/search?q=&types=&limit=10&offset=0` | Identique | ✅ | — |
| Types par onglet (`getTypesForTab`) | `posts`/`users`/`hashtags`/`users,posts,hashtags` | `SearchTab.apiTypes` identique | ✅ | — |
| Debounce recherche universelle | 300ms (`Handler.postDelayed`) | 300ms (`Task.sleep`) | ✅ | — |
| Seuils longueur (suggest≥1, full≥2) | Oui | Oui | ✅ | — |
| Soumission clavier court-circuite debounce | Oui | Oui (corrigé V6-F-013) | ✅ | — |
| **Enveloppe réponse — champ `"error"`** | **STRING `"false"`/`"true"`** (déduit de `TransportData.get()`) | **`value.bool("error")` — n'accepte QUE un booléen natif** | ❌ | **CRITIQUE — cause racine, voir §1/§10** |
| Clé `"results"` absente si `error≠"false"` | Provoque `onError` AVANT `parseAndDisplay` (jamais atteint) | Provoque `throw APIError.server("results manquant")`, texte "Erreur de chargement." | ❌ | Conséquence directe du point ci-dessus |
| Filtrage par onglet côté client (users/hashtags/posts) | Oui (`parseAndDisplay`) | Oui (corrigé V5-F-011/V3-F-106) | ✅ | — |
| Garde `isFull` sur `posts` | Oui | Oui (corrigé V3-F-106) | ✅ | — |
| Fallback miniature post | `cdn_thumbnail_url`→`cdn_content_url`→gris | Identique (corrigé V5-F-010) | ✅ | — |
| Historique local préfixé `#`/`@` | Oui (`buildDisplayEntry`/parsing au clic) | Oui (corrigé V3-F-103/V4-F-035) | ✅ | — |
| En-tête `Authorization` | Toujours envoyé, même si `apiKey==null` | Envoyé SEULEMENT si `apiKey` non-nil | ⚠️ | MEDIUM — voir §10 |
| Recherche conversations (roster), filtre local | 3 champs (titre/message/sous-titre), insensible casse | Identique (corrigé V3-F-108) | ✅ | — |
| Recherche conversations, repli serveur `search/{myId}/{q}` | Oui | Oui (`GroupRepository.searchGroups`, utilise `isBackendSuccess` — bonne convention) | ✅ | — |
| Recherche DANS une conversation ouverte | **Inexistante** | **Inexistante** | ✅ (absence symétrique) | — |
| Message d'erreur réseau générique | Texte fixe "Erreur de chargement" (aucune distinction de cause) | Texte fixe "Erreur de chargement." (idem) | ⚠️ | LOW/HIGH — masque le bug CRITIQUE, aucune télémétrie (voir §10) |
| Pagination recherche universelle | `limit=10&offset=0` fixes, pas de "charger plus" | Identique | ✅ (limite produit reproduite, pas un bug) | — |

---

## 10. Cause racine de l'erreur

**CRITIQUE — SEARCH-ROOT-01**
- **Fichier** : `Sources/TiinverSwift/Discover/SearchRepository.swift`
- **Ligne** : 66 (`guard (try? value.bool("error")) != true else { return SearchResults() }`), avec
  la déclaration de `bool(_:)` en cause dans `Sources/TiinverSwift/Networking/JSONValue.swift:63-67`
- **Comportement Android** : `TransportData.get()` (`Http/TransportData.java:550-561`) exige que le
  champ `"error"` soit une **chaîne** (`response.getString(ERROR)`), comparée textuellement à
  `"false"`. Une valeur `"true"` (ou toute autre chaîne) route vers `callback.onError("")` — jamais
  vers `parseAndDisplay`. Le check `object.getBoolean("error")` DANS `parseAndDisplay`
  (`RechercheTiinver.java:466`) est en pratique du code mort sur ce chemin (déjà filtré en amont),
  et de toute façon `org.json.JSONObject.getBoolean()` accepte AUSSI bien une chaîne "true"/"false"
  qu'un booléen natif — il ne prouve donc RIEN sur le type réel du champ côté serveur.
- **Comportement iOS** : `JSONValue.bool(_:)` n'accepte QU'un booléen Swift natif
  (`value as? Bool`), échoue (`typeMismatch`) sur une chaîne `"true"`/`"false"`. L'échec est avalé
  par `try?`, donnant `nil`, et `nil != true` vaut `true` en Swift — le `guard` laisse TOUJOURS
  passer, que `"error"` vaille `"false"` (succès, comportement correct par coïncidence) OU
  `"true"` (échec métier, comportement INCORRECT : devrait retourner `SearchResults()` vide
  silencieusement, comme Android, mais continue au lieu de ça vers le décodage de `"results"`).
- **Différence** : sur une réponse où `"error":"true"` (chaîne) ET où la clé `"results"` est
  absente (cohérent avec la convention `.has(...)` du reste du backend — la clé entière est omise
  plutôt que vidée), Android affiche silencieusement "Aucun résultat" tandis qu'iOS lève
  `APIError.server(message: "results manquant")`, capturé par `SearchView.runSearch`'s `catch`, qui
  affiche **"Erreur de chargement."** — le symptôme exact rapporté par l'utilisateur.
- **Cause** : le commentaire de `decodeResults` (lignes 35-38 du fichier) affirme à tort que
  `"error"` est un booléen JSON natif sur CET endpoint précis, par analogie erronée avec
  `notification2/{userId}` (qui LUI a une preuve directe dans `NotiLikecmt/
  NotificationRepository.java`). Cette affirmation n'a jamais été vérifiée par une capture réseau
  réelle pour `content/search`/`content/search/suggest`, et est contredite par le comportement de
  `TransportData.get()` — le SEUL point d'entrée réseau réellement utilisé par `searchFull`/
  `searchSuggest` côté Android.
- **Correction proposée** (§12) : remplacer `value.bool("error")` par `value.isBackendSuccess`
  (négation : `guard value.isBackendSuccess else { return SearchResults() }`), cohérent avec
  `GroupRepository.searchGroups` (même backend, même convention, déjà correct) et avec la leçon
  déjà documentée dans `JSONValue.swift:118-137` pour l'incident `login`.

**Niveau de confiance** : élevé mais pas absolu — aucune capture réseau réelle de
`content/search?q=Salim...` n'était disponible dans cet environnement (pas de device/simulateur).
L'hypothèse alternative (échec HTTP non-2xx pur, ex. token expiré → §10 MEDIUM ci-dessous, ou tout
autre problème d'authentification) produirait EXACTEMENT le même texte "Erreur de chargement." côté
UI, ce qui est précisément le 2e problème (HIGH) documenté ci-dessous : le texte seul ne permet pas
de trancher entre les deux sans logs.

**HIGH — SEARCH-ROOT-02 (masquage diagnostic)**
- **Fichier** : `Sources/TiinverSwift/Discover/SearchView.swift`, ligne 408
  (`errorText = "Erreur de chargement."`)
- **Comportement** : TOUTE exception (réseau, HTTP non-2xx, décodage JSON, `results manquant`,
  timeout) affiche le même texte générique, sans log distinctif exploitable en debug/production.
  Android a exactement le même défaut (`searchFull.onError` affiche toujours "Erreur de
  chargement" sans distinction), donc CE point précis n'est PAS un écart de parité — mais il
  aggrave directement le bug CRITIQUE ci-dessus en le rendant indiscernable d'une vraie panne
  réseau sans instrumentation supplémentaire.
- **Correction proposée** (§12) : ajouter un `print`/log distinctif de l'erreur réelle
  (`error.localizedDescription`) dans le `catch` de `runSearch`, uniquement en DEBUG, pour permettre
  un diagnostic futur sans capture réseau externe.

**MEDIUM — SEARCH-ROOT-03 (Authorization conditionnelle)**
- **Fichier** : `Sources/TiinverSwift/Networking/APIClient.swift`, lignes 42-51 (`headers()`)
- **Comportement Android** : `Authorization` toujours présent dans les en-têtes, même `null`
  (`Http/TransportData.java:601`, `headers.put("Authorization", apiKey)` sans garde de nullité).
- **Comportement iOS** : `if let apiKey = UserSession.shared.apiKey { headers.add(...) }` — l'en-tête
  est ABSENT (pas juste vide) si `apiKey` est `nil`.
- **Différence** : un serveur qui distingue "en-tête absent" de "en-tête présent mais vide/invalide"
  pourrait retourner un code HTTP ou un corps d'erreur différent entre les deux plateformes dans ce
  cas précis (session pas encore établie / token non chargé au moment de la requête).
- **Cause** : simplification volontaire lors du portage (`UserSession.shared.apiKey` est
  `Optional` côté Swift, contrairement à un champ Java qui peut être `null` mais reste "présent"
  dans la Map d'en-têtes).
- **Correction proposée** (§12) : envoyer `Authorization: ""` (chaîne vide) plutôt que d'omettre
  l'en-tête quand `apiKey` est `nil`, pour matcher le comportement Android au plus près — sous
  réserve de confirmer que ce n'est pas la cause réelle du bug rapporté (peu probable si
  l'utilisateur est authentifié au moment du test, mais pas exclu si le token expire/se recharge de
  façon asynchrone).

---

## 11. Fichiers concernés

**iOS (à corriger)** :
- `Sources/TiinverSwift/Discover/SearchRepository.swift` (ligne 66 — cause racine CRITIQUE)
- `Sources/TiinverSwift/Discover/SearchView.swift` (ligne 405-409 — logging diagnostic HIGH)
- `Sources/TiinverSwift/Networking/APIClient.swift` (lignes 42-51 — Authorization MEDIUM)

**iOS (référence / déjà conformes, cités pour contexte)** :
- `Sources/TiinverSwift/Discover/SearchModels.swift`
- `Sources/TiinverSwift/Networking/JSONValue.swift` (méthode `isBackendSuccess` à réutiliser)
- `Sources/TiinverSwift/Messagerie/ChatSearchView.swift`
- `Sources/TiinverSwift/Messagerie/GroupRepository.swift` (référence de bon usage `isBackendSuccess`)

**Android (source de vérité, lus intégralement ou en grande partie)** :
- `app/src/main/java/com/tiinver/Recherche/ui/RechercheTiinver.java` (754 lignes, lu en entier)
- `app/src/main/java/com/tiinver/Recherche/SearchRepository.java` (4 lignes, vide, confirmé)
- `app/src/main/java/com/tiinver/Recherche/ui/RecentSearchManager.java` (70 lignes, lu en entier)
- `app/src/main/java/com/tiinver/models/search/SearchResultModel.java` (179 lignes, lu en entier)
- `app/src/main/java/com/tiinver/Http/TransportData.java` (extraits pertinents, `get()`
  lignes 537-613, en-têtes lignes 596-607)
- `app/src/main/java/com/tiinver/roster/ui/Roster.java` (extrait, ligne 436-439)
- `app/src/main/java/com/tiinver/messagerie/group/SettingGroupMessageFragmant.java` (extrait,
  lignes 296-306 — confirme l'absence de recherche de messages)

---

## 12. Corrections proposées (NON appliquées — audit uniquement)

1. **CRITIQUE** — `SearchRepository.swift:66` : remplacer
   ```swift
   guard (try? value.bool("error")) != true else { return SearchResults() }
   ```
   par
   ```swift
   guard value.isBackendSuccess else { return SearchResults() }
   ```
   Cohérent avec `GroupRepository.searchGroups` et la convention documentée dans
   `JSONValue.errorFieldNormalized`/`isBackendSuccess`. Mettre à jour le commentaire au-dessus
   (lignes 35-38) pour retirer l'affirmation non vérifiée sur un booléen JSON natif et documenter
   la preuve réelle (`TransportData.get()` exige une String via `getString(ERROR)`).

2. **HIGH** — `SearchView.swift`, `catch` de `runSearch` (ligne ~405-409) : ajouter un log DEBUG de
   l'erreur réelle avant de l'écraser par le texte générique, pour permettre un diagnostic futur
   sans capture réseau externe.

3. **MEDIUM** — `APIClient.swift:42-51` : envoyer `Authorization: ""` plutôt que d'omettre
   l'en-tête quand `UserSession.shared.apiKey` est `nil`, pour matcher Android au plus près.

4. **Recommandé (non bloquant)** — obtenir UNE capture réseau réelle de
   `content/search?q=Salim&types=users,posts,hashtags&limit=10&offset=0` (via proxy ou logs
   serveur) pour confirmer définitivement la forme exacte du champ `"error"` et de la clé
   `"results"` sur une réponse concrète, et valider le correctif #1 avant de le committer en
   production.

---

## 13. Corrections effectuées

N/A — audit uniquement, en attente de validation.

## 14. Tests

N/A — audit uniquement, en attente de validation.

## 15. Résultats

N/A — audit uniquement, en attente de validation.

## 16. Problèmes restants

N/A — audit uniquement, en attente de validation.

---

## 17. Recommandations

1. Appliquer le correctif CRITIQUE (§12.1) en priorité absolue — c'est la cause la plus probable du
   bug rapporté et il est cohérent avec la convention déjà établie ailleurs dans le même repo
   (`GroupRepository.searchGroups`), donc à faible risque de régression.
2. Avant de committer, si possible, capturer un VRAI payload réseau (proxy Charles/mitmproxy sur un
   device de test, ou logs serveur) pour la query "Salim" afin de confirmer à 100 % la forme du
   champ `"error"` — actuellement déduite par inférence du code Android, pas observée directement.
3. Ajouter le logging diagnostic (§12.2) même si le correctif #1 résout le symptôme immédiat — la
   prochaine régression de ce type (n'importe quel endpoint) sera bien plus rapide à diagnostiquer
   avec un message d'erreur réel visible en debug plutôt que le texte générique uniquement.
4. Envisager d'auditer systématiquement TOUS les appels `value.bool("error")` restants dans le
   reste du codebase iOS (recherche `grep -rn "\.bool(\"error\")"`) — si `decodeResults` est le
   SEUL endroit où cette convention (a priori erronée) a été appliquée par erreur, très bien ; sinon
   chaque occurrence supplémentaire est un candidat au même bug, à vérifier au cas par cas contre
   son propre `TransportData.*` Android correspondant plutôt que de supposer une réponse uniforme.
5. La divergence MEDIUM sur `Authorization` (§10) mérite un correctif à part, sans lien direct avec
   le bug rapporté mais utile pour la parité générale de la couche réseau.
6. Aucune action requise sur la recherche de messages dans une conversation ouverte — fonctionnalité
   absente des deux côtés, conforme par construction.
