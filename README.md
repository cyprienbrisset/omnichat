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

## Identité visuelle : l'atelier d'imprimerie

OmniChat adopte une direction artistique distincte plutôt qu'une interface
macOS générique : papier (`#f5efe2`/`#dcd5c6`), encre quasi noire, serif
(prose des réponses, titres) contrastée avec du monospace tracké en
majuscules (labels, métadonnées), filets fins et une texture de hachures
diagonales très discrète — un clin d'œil aux plaques d'imprimerie plutôt
qu'aux bulles de chat classiques : une requête utilisateur se lit comme une
citation en italique, une réponse comme un paragraphe de prose. Le thème
est centralisé dans `OmniChat/Support/Theme.swift` (`OmniTheme`) et
s'adapte clair/sombre comme avant.

Ce traitement est appliqué à la fenêtre principale (conversation +
sidebar), aux réglages/premier lancement et au menu bar. Chaque réponse
affiche, quand OmniRoute les fournit, sa trace de routage et son coût réels
(stratégie/fournisseur, latence, tokens, coût, cache) — lus depuis les
en-têtes `X-OmniRoute-*` de la réponse, jamais recalculés ni fabriqués : si
un champ est absent (le jeu coût/tokens n'est confirmé par la doc que hors
streaming), il n'apparaît simplement pas. Une vue
comparaison de réponses, un sélecteur de modèles façon trombinoscope
(⌘K) et un panneau de routage/combos font partie d'une direction future
documentée mais non planifiée — ils dépendent de fonctionnalités
(télémétrie de combo, coûts/latences par requête) pas encore construites.

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
le Keychain macOS, jamais en clair. Une fois la connexion enregistrée,
« Tester la connexion actuelle » appelle réellement `GET /v1/models` pour
confirmer que l'endpoint et la clé sont valides (pas un indicateur factice).
