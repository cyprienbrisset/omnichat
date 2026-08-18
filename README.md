# OmniChat

App macOS native (Swift + SwiftUI, macOS 26+) pour exploiter
[OmniRoute](https://github.com/diegosouzapw/OmniRoute), une passerelle IA
open-source agrégeant 339 fournisseurs de modèles derrière une API
compatible OpenAI.

> **Statut : socle + chat + génération média fonctionnels.** Chat
> multi-modèles en streaming, génération d'images/vidéo/musique et synthèse
> vocale avec rendu inline + galerie dédiée, gestion des conversations
> (renommer, archiver, corbeille à rétention 30 jours), gestion d'erreurs
> (auth/rate limit/réseau/stream interrompu/arrêt manuel), persistance
> locale (SwiftData), clé API dans le Keychain, thème clair/sombre manuel,
> sélection de modèle par conversation (⌘K), détection des droits de
> gestion sur la clé API, navigateur de mémoire réel (lecture/suppression
> via l'API de gestion, avec message explicite si la clé n'a pas les
> droits), navigateur du serveur MCP embarqué (statut, outils exposés,
> statistiques d'audit), menu bar + fenêtre principale. RAG, A2A, OCR,
> transcription audio, comparaison multi-modèles et gestion des
> combos/routage ne sont pas encore implémentés (voir le spec pour le
> périmètre complet).

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
streaming), il n'apparaît simplement pas. Une vue comparaison de réponses
et un panneau de gestion des combos/routage font partie d'une direction
future documentée mais non planifiée — ils dépendent de fonctionnalités
(télémétrie de combo, coûts/latences par requête) pas encore construites.

## Génération média

Le composeur de la fenêtre principale bascule entre Texte/Image/Vidéo/
Musique/Voix via une rangée d'onglets mono trackés (le substitut « atelier
d'imprimerie » du sélecteur segmenté classique). Chaque résultat s'affiche
inline dans la conversation (image, lecteur vidéo, lecteur audio pour
musique/voix) et rejoint la Galerie (icône dédiée dans le rail), filtrable
par type. Les fichiers sont enregistrés sous
`~/Library/Application Support/OmniChat/Media/` — jamais dans le bundle de
l'app, jamais dans un chemin synchronisé iCloud. Ces quatre appels
(`/v1/images/generations`, `/v1/videos/generations`,
`/v1/music/generations`, `/v1/audio/speech`) sont synchrones côté OmniRoute
(pas de file d'attente/polling), vérifié directement dans le code source
de l'API avant implémentation.

## Gestion des conversations

Trois vues commutables depuis des icônes dédiées du rail (inspiré de
ChatGPT) : Conversations, Archivées, Corbeille. Un clic droit sur une
conversation permet de la renommer, l'archiver/désarchiver, ou la
supprimer — la suppression la déplace en Corbeille plutôt que de l'effacer
immédiatement ; elle y reste 30 jours (purgée automatiquement ensuite,
même logique que `DiagnosticLogger`) avant suppression définitive, avec
restauration ou suppression immédiate possibles entre-temps.

## Mémoire (API de gestion)

Icône dédiée du rail (`brain`) ouvrant un navigateur réel des souvenirs
stockés côté serveur (`GET/DELETE /api/memory`), accessible uniquement
avec une clé API disposant des droits de gestion — la même clé que celle
utilisée pour le chat, jamais un second identifiant : `hasManagementAccess()`
sonde silencieusement `GET /api/memory` au lancement et adapte l'interface
en conséquence. Si la clé n'a pas ces droits, la vue l'indique explicitement
plutôt que d'afficher une liste vide trompeuse. La forme exacte de la
réponse `/api/memory` n'étant pas documentée avec certitude, le parsing
essaie plusieurs formes plausibles (tableau nu, `{data:[...]}`,
`{memories:[...]}`) avant d'échouer proprement.

## Serveur MCP (API de gestion)

Icône dédiée du rail ouvrant un navigateur du serveur MCP embarqué
d'OmniRoute (`GET /api/mcp/status`, `/api/mcp/tools`, `/api/mcp/audit/stats`),
même garde d'accès et même clé que la Mémoire. La forme JSON exacte du
statut et des stats d'audit n'est documentée qu'en prose dans la référence
d'API (pas de noms de champs) — plutôt que de deviner des clés et risquer
d'afficher une donnée réelle sous une mauvaise étiquette, ces deux réponses
sont affichées telles quelles (liste brute clé/valeur triée). Seule la
liste des outils (`name`, `description`, `scopes`, `phase`, `auditLevel`,
`sourceEndpoints`) a une forme documentée et un rendu dédié.

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

L'app autorise les connexions HTTP simples vers n'importe quel domaine
(`NSAllowsArbitraryLoads` dans `project.yml`) — beaucoup d'instances
OmniRoute auto-hébergées (localhost, IP nue derrière un reverse-proxy sans
TLS) n'ont pas de certificat, et App Transport Security les bloquerait
sinon par défaut, avec une erreur réseau générique ne mentionnant jamais
la vraie cause.
