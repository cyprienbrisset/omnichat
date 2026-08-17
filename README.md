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

## Configuration

Au premier lancement, ouvre les réglages de l'app (menu OmniChat > Réglages)
pour renseigner l'URL de ton instance OmniRoute (`http://localhost:20128/v1`
par défaut, ou une instance distante) et ta clé API. La clé est stockée dans
le Keychain macOS, jamais en clair.
