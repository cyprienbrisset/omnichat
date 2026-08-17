# OmniChat

App macOS native (Swift + SwiftUI, macOS 26+) pour exploiter
[OmniRoute](https://github.com/diegosouzapw/OmniRoute), une passerelle IA
open-source agrégeant 339 fournisseurs de modèles derrière une API
compatible OpenAI.

> **Statut : en conception.** Le code n'existe pas encore — voir le spec
> ci-dessous pour l'état d'avancement réel. Cette section sera mise à
> jour à chaque fonctionnalité livrée.

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

À documenter dès que le projet Xcode existe (commande de build, version
macOS minimale requise, dépendances).

## Configuration

À documenter dès que l'écran de réglages existe : comment déclarer un
`EndpointProfile` (URL OmniRoute locale ou distante) et où renseigner la
clé API (stockée dans le Keychain macOS, jamais en clair).
