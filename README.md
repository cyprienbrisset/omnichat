# OmniChat

App macOS native (Swift + SwiftUI, macOS 26+) pour exploiter
[OmniRoute](https://github.com/diegosouzapw/OmniRoute), une passerelle IA
open-source agrégeant 339 fournisseurs de modèles derrière une API
compatible OpenAI.

> **Statut : socle + chat fonctionnels.** Chat multi-modèles en streaming,
> gestion d'erreurs (auth/rate limit/réseau/stream interrompu), persistance
> locale (SwiftData), clé API dans le Keychain, menu bar + fenêtre
> principale. Médias, RAG, MCP, A2A, OCR et traduction audio ne sont pas
> encore implémentés (voir le spec pour le périmètre complet).

## Ce que fait OmniChat

Une fois implémenté, OmniChat exploitera l'intégralité de la surface
d'OmniRoute : chat multi-modèles en streaming, génération d'images, de
vidéo et de musique, recherche web intégrée, recherche sémantique locale
(RAG) sur l'historique et les documents importés, modèles locaux
(Ollama/LM Studio/vLLM), outils et agents MCP, agents externes A2A, OCR,
transcription/traduction audio, et routage automatique (auto-combo) avec
suivi des quotas par fournisseur.

Détail complet du périmètre, de l'architecture et des décisions de
conception :
[docs/superpowers/specs/2026-08-17-omnichat-macos-app-design.md](docs/superpowers/specs/2026-08-17-omnichat-macos-app-design.md)

## Sous-projets liés

- **OmniChat** (ce dépôt) — l'app macOS native.
- **OmniCLI** — CLI type Claude Code intégré à OmniRoute, spec à venir
  séparément ; réutilisera le module réseau partagé `OmniRouteKit`.

## Build & lancement

Prérequis : Xcode récent, [XcodeGen](https://github.com/yonaskolb/XcodeGen), macOS 26+.

```bash
xcodegen generate
open OmniChat.xcodeproj
```

Lancer les tests du socle réseau (rapide, sans Xcode) :

```bash
cd Packages/OmniRouteKit && swift test
```

Lancer tous les tests (kit + app) :

```bash
xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS'
```

**Compte Apple Developer local requis.** L'app utilise le trousseau à
protection de données (`kSecUseDataProtectionKeychain` +
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) pour stocker la clé API, afin
qu'elle ne puisse pas se synchroniser via iCloud Keychain — un choix de
sécurité assumé, pas un oubli. Cela exige une signature de code réelle
(pas seulement ad-hoc), donc **builder ou tester ce projet nécessite un
compte Apple Developer (gratuit ou payant) configuré dans Xcode, avec un
profil de provisioning pour l'identifiant `online.omniroute.omnichat`** —
ce n'est pas portable sur une machine ou un CI vierge sans ça.
`project.yml` configure `CODE_SIGN_STYLE: Automatic` sans figer d'équipe
(pour éviter de committer un identifiant d'équipe personnel) ; fournis le
tien :

```bash
xcodebuild build DEVELOPMENT_TEAM=TONIDENTIFIANT ...
```

ou renseigne l'équipe dans Xcode (Signing & Capabilities du target `OmniChat`
et `OmniChatTests`) après `open OmniChat.xcodeproj` — Xcode s'en souviendra
localement sans modifier `project.yml`.

## Configuration

Au premier lancement, ouvre les réglages de l'app (menu OmniChat > Réglages)
pour renseigner l'URL de ton instance OmniRoute (`http://localhost:20128/v1`
par défaut, ou une instance distante) et ta clé API. La clé est stockée dans
le Keychain macOS, jamais en clair.
