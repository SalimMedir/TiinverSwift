# Instructions de build — TiinverSwift

## ⚠️ Contrainte d'environnement critique

Ce projet est écrit et maintenu depuis une machine **Windows** (pas d'accès à macOS/Xcode
dans cet environnement de travail). Cela a une conséquence directe sur la méthodologie de
portage décrite dans `MIGRATION_PROGRESS.md` :

- **Le code Swift est écrit et sa cohérence est vérifiée par lecture/relecture attentive**,
  en respectant la syntaxe Swift et les API publiques connues des frameworks utilisés.
- **Aucune compilation (`xcodebuild`) n'a pu être exécutée** sur le code produit dans cet
  environnement — Xcode n'existe pas sur Windows, ni en CLI ni en GUI. La règle du cahier
  des charges ("compiler après chaque module") ne peut donc pas être exécutée à la lettre
  ici ; elle est remplacée par une relecture manuelle systématique + une note explicite de
  statut "NON COMPILÉ" dans le tracker tant qu'aucun build réel n'a eu lieu.
- **Dès qu'une machine macOS avec Xcode est disponible**, la première action à faire est de
  lancer un build complet (voir ci-dessous) et de corriger toutes les erreurs de compilation
  avant de considérer un seul module comme "validé" au sens de la règle originale.

## Générer le projet Xcode (à faire sur macOS)

Le dépôt ne contient pas de `.xcodeproj` — celui-ci est généré à partir de `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen), pour permettre l'édition des sources depuis
n'importe quelle machine sans dépendre du format binaire/XML propriétaire d'un `.xcodeproj`.

```bash
brew install xcodegen
cd TiinverSwift
xcodegen generate
open TiinverSwift.xcodeproj
```

Cela résout aussi les dépendances Swift Package Manager déclarées dans `project.yml`
(Alamofire, Socket.IO-Client-Swift, MetalPetal, Gifu, Google Mobile Ads, Google Sign-In,
Facebook SDK, WebRTC, Firebase) — Xcode les téléchargera à la première ouverture.

## Compiler en ligne de commande

```bash
xcodebuild -project TiinverSwift.xcodeproj -scheme TiinverSwift \
  -destination 'generic/platform=iOS Simulator' build
```

## Points à vérifier en priorité au premier build réel

1. **Auth Socket.IO** (`Realtime/TiinverSocket.swift`) — la configuration `.connectParams`
   utilisée pour transmettre l'apiKey au handshake est une décision prise sans pouvoir
   vérifier contre la vraie lib compilée. À confirmer côté serveur que le token arrive bien
   dans `socket.handshake.auth.token` (comportement Android attendu) et non ailleurs.
2. Versions exactes des packages SPM dans `project.yml` (`from:`) — fixées à des versions
   plausibles au moment de l'écriture (2026), à ajuster si Xcode signale une incompatibilité.
3. Toute dépendance Objective-C (WebRTC, Facebook SDK) nécessite un bridging correct — à
   vérifier à la première compilation, ce type d'erreur est invisible sans Xcode.
