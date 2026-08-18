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
> statistiques d'audit), indicateur réel de santé des fournisseurs en pied
> de sidebar (`/api/monitoring/health`), recherche locale (RAG) sur
> l'historique des conversations avec attache de contexte au message
> suivant, comparaison multi-modèles côte à côte (prompt unique, N flux
> réels indépendants), menu bar + fenêtre principale. RAG documentaire
> (import de fichiers), A2A, OCR, transcription audio et gestion des
> combos/routage/compression ne sont pas encore implémentés (voir le spec
> pour le périmètre complet).

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

L'indicateur de santé (`/api/monitoring/health`) et le navigateur MCP ont
été vérifiés contre une instance OmniRoute réelle et corrigés en
conséquence : les compteurs de fournisseurs vivent sous `providerSummary`
dans une réponse de santé processus beaucoup plus large que ce que la
référence d'API laissait supposer, et les erreurs `.unknown` affichent
maintenant le vrai message de diagnostic plutôt qu'un texte générique —
sinon des messages comme celui du blocage MCP ci-dessous n'auraient jamais
été visibles.

## Serveur MCP (API de gestion)

Icône dédiée du rail ouvrant un navigateur du serveur MCP embarqué
d'OmniRoute (`GET /api/mcp/status`, `/api/mcp/tools`, `/api/mcp/audit/stats`,
`/api/mcp/audit`), même garde d'accès et même clé que la Mémoire. La forme
JSON exacte du statut, des stats d'audit et des entrées d'audit n'est
documentée qu'en prose dans la référence d'API (pas de noms de champs) —
plutôt que de deviner des clés et risquer d'afficher une donnée réelle sous
une mauvaise étiquette, ces réponses sont affichées telles quelles (liste
brute clé/valeur triée). Seule la liste des outils (`name`, `description`,
`scopes`, `phase`, `auditLevel`, `sourceEndpoints`) a une forme documentée
et un rendu dédié.

Le journal d'audit (« Activité récente ») montre les appels d'outils MCP
*réellement* effectués contre ce serveur, par n'importe quel client — ce
n'est **pas** une carte d'appel affichée en direct dans le fil de
conversation. OmniChat n'implémente pas (encore) de boucle d'appel d'outils
agentique sur `/v1/chat/completions` : la référence d'API ne documente
aucun support `tools`/`tool_calls` de type OpenAI sur cette route malgré la
compatibilité OpenAI annoncée, donc afficher une carte d'appel en direct
dans le fil serait fabriquer une interaction qui n'a pas lieu. Un
écran de permissions par portée n'aurait de sens qu'une fois cette boucle
réellement construite et confirmée contre un serveur accessible.

**Confirmé empiriquement contre une instance OmniRoute réelle (3.8.49) :**
tous les `/api/mcp/*` renvoient `403 {"error":{"code":"LOCAL_ONLY",...}}`
dès qu'on les appelle depuis ailleurs que la machine qui héberge OmniRoute
elle-même — quels que soient les droits de la clé. Pour une instance
auto-hébergée distante (le cas d'usage principal de cette app), ce
navigateur MCP affichera donc toujours cette erreur, jamais une vraie
donnée. L'app détecte ce code précis et affiche le vrai message serveur
plutôt qu'un « Clé API invalide » trompeur (qui serait la lecture par
défaut d'un 403 générique).

## Recherche locale (RAG sur l'historique)

Icône dédiée du rail ouvrant un navigateur de recherche locale sur les
conversations. Contrairement à Mémoire et MCP, aucune clé de gestion n'est
requise : l'indexation et la recherche passent par `POST /v1/embeddings` et
`GET /v1/embeddings`, la même clé que le chat. L'indexation d'une
conversation (« Indexer ») est **toujours manuelle** — jamais déclenchée en
arrière-plan — parce que chaque appel a un coût réel et envoie le contenu
des messages à un fournisseur d'embeddings tiers via OmniRoute. Le score
combine une similarité cosinus réelle (vecteurs) et un recouvrement de
mots-clés simple ; ce n'est pas du FTS5 SQLite malgré ce que suggère le
mockup, donc l'interface ne prétend pas l'être. Les résultats cochés
peuvent être joints comme contexte au prochain message envoyé (message
`system` transitoire, jamais persisté comme un vrai message de la
conversation). L'import de documents externes n'est pas implémenté — seul
l'historique des conversations déjà dans OmniChat est indexable.

## Comparaison multi-modèles

Icône dédiée du rail. Un seul prompt envoyé à N modèles ajoutés via le
même casier ⌘K que le reste de l'app ; chaque colonne diffuse
indépendamment sa propre réponse réelle (`streamChatCompletion`) et
affiche ses propres jetons/coût/latence une fois reçus. Volontairement
éphémère : rien n'est persisté comme conversation — changer d'écran perd
les colonnes. Aucune notion de « combo » ou de juge ici, contrairement au
mockup 3b (Fusion) : c'est une comparaison brute, pas une synthèse.

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
