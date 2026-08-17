# OmniChat — App macOS native (spec v1)

Date : 2026-08-17
Statut : validé par l'utilisateur, prêt pour plan d'implémentation

## Contexte

OmniChat est une application macOS native permettant d'exploiter les capacités
d'[OmniRoute](https://github.com/diegosouzapw/OmniRoute), une passerelle IA
open-source agrégeant 339 fournisseurs de modèles derrière une API compatible
OpenAI (chat, images, vidéo, musique, recherche web, MCP, modèles locaux).

Ce document couvre uniquement le **sous-projet app macOS**. Un second
sous-projet, **OmniCLI** (CLI type Claude Code intégré à OmniRoute), fera
l'objet d'une spec séparée et réutilisera le module réseau partagé décrit
ci-dessous (`OmniRouteKit`).

## Objectifs (v1 — périmètre complet)

Décision actée : **pas de découpage v1/v2 sur les capacités OmniRoute**.
L'app doit exploiter correctement et intégralement la surface de l'API dès
la première version livrable. Chaque capacité d'OmniRoute est mappée à une
fonctionnalité concrète de l'app :

| Capacité OmniRoute | Fonctionnalité OmniChat |
|---|---|
| Chat / LLM (339 providers) | Chat multi-modèles avec streaming, historique par conversation |
| Images (24 providers) | Génération d'images + Galerie |
| Vidéo (14 providers) | Génération vidéo + Galerie |
| Musique (6 providers) | Génération musicale + lecteur intégré + Galerie |
| Audio / TTS (7 providers) | Synthèse vocale des réponses, lecteur intégré |
| Recherche web (11 providers) | Intégrée au flux de chat (tool call), sources affichées inline |
| Embeddings & Rerank | Recherche sémantique locale dans l'historique des conversations et les documents importés (RAG local) |
| Modèles locaux (Ollama / LM Studio / vLLM) | Sélectionnables comme provider au même titre que les modèles cloud dans le picker de modèle |
| Outils / agents MCP (105 outils, 31 scopes) | Panneau « Outils » : activation par scope au niveau conversation, exécutions tracées et affichées inline |
| Agent-to-Agent (JSON-RPC 2.0) | Écran « Agents » : connexion à des agents A2A externes, suivi des échanges |
| OCR (Mistral OCR) | Import PDF/image → texte extrait injecté comme contexte de conversation |
| Traduction audio (style Whisper) | Import ou enregistrement audio → transcription/traduction injectée dans le chat |
| Auto-combo routing | Mode « Auto » dans le sélecteur de modèle : OmniRoute choisit la meilleure chaîne de fallback ; l'UI affiche quel provider a effectivement répondu |
| Quotas (headers `X-OmniRoute-*`) | Indicateur de quota/coût restant par provider, visible dans les réglages et en popover contextuel |

Autres exigences transverses :

- Connexion à une instance OmniRoute locale (`http://localhost:20128/v1`
  par défaut) ou distante, configurable par l'utilisateur.
- Accès rapide via une icône de menu bar, en plus d'une fenêtre principale
  complète.
- Bibliothèque locale (Galerie) indexant tous les médias générés.

## Hors scope v1

- Distribution Mac App Store (v1 = DMG notarié hors store) — reste
  atteignable plus tard sans refonte grâce au design sandboxing-friendly.
- OmniCLI (spec et cycle de développement séparés, réutilise `OmniRouteKit`).

Compte tenu de ce périmètre élargi, le plan d'implémentation (prochaine
étape) devra très probablement être phasé en plusieurs jalons livrables
indépendamment (ex. socle + chat, puis médias, puis RAG/MCP/agents) —
c'est un détail de séquencement pour `writing-plans`, pas une réduction du
périmètre fonctionnel décrit ici.

## Architecture

Deux modules dans un seul projet Xcode :

### `OmniRouteKit` (Swift Package local, sans dépendance UI)

Client réseau pur vers l'API OmniRoute, conçu pour être réutilisé tel quel
par OmniCLI plus tard.

- `OmniRouteClient` (actor) : construit les requêtes HTTP, header
  `Authorization: Bearer <clé>`, base URL résolue depuis la configuration
  active (`EndpointProfile`).
- Chat : `POST /v1/chat/completions`, streaming SSE exposé comme
  `AsyncThrowingStream<ChatDelta>`, avec support du tool calling (recherche
  web, outils MCP).
- Modèles : `GET /v1/models` pour peupler les sélecteurs par
  modalité/provider (avec recherche/filtre côté UI, vu le volume de 339
  providers) ; `GET /v1/auto-combo/{channel}/candidates` pour le mode Auto.
- Génération média : `POST /v1/{images,video,audio}/generations`, jobs
  asynchrones avec polling à backoff exponentiel jusqu'à complétion, puis
  téléchargement de l'asset final.
- Embeddings & rerank : endpoints dédiés utilisés en interne par le moteur
  de recherche sémantique locale (RAG), jamais exposés bruts à l'UI.
- OCR (`POST /v1/ocr`) et traduction audio (`POST /v1/audio/translations`) :
  pipelines d'import (document/image → texte, audio → texte).
- MCP : découverte des outils/scopes disponibles et invocation via le
  protocole MCP-server d'OmniRoute ; chaque invocation est tracée
  (`ToolInvocation`).
- A2A : client JSON-RPC 2.0 pour dialoguer avec des agents externes
  compatibles Agent-to-Agent.
- Quotas : lecture des headers `X-OmniRoute-*` sur chaque réponse,
  exposés via un `QuotaSnapshot` observable par provider.
- `OmniRouteError` unifié : auth invalide, rate limit, job échoué, timeout,
  endpoint injoignable, outil MCP en échec, agent A2A injoignable.

**⚠️ Risque technique identifié** : le résumé de documentation récupéré ne
garantit pas le schéma exact de chacun de ces endpoints (polling de job,
format MCP-server, format A2A, structure exacte des headers de quota).
**Avant d'implémenter chaque sous-ensemble, une étape de recherche dédiée
est requise** : lire directement les fichiers correspondants dans
`docs/reference/`, `docs/frameworks/MCP-SERVER.md` et
`docs/frameworks/A2A-SERVER.md` du dépôt
[OmniRoute](https://github.com/diegosouzapw/OmniRoute) plutôt que de
supposer un format. Cette vérification doit être la première tâche de
chaque jalon du plan d'implémentation, pas seulement du socle chat/media.

### `OmniChat` (app target, SwiftUI, macOS 26+)

- `MenuBarExtra` : popover compact pour un prompt de chat rapide, avec
  action « ouvrir en fenêtre complète ».
- Fenêtre principale : `NavigationSplitView` — sidebar (conversations,
  Galerie, Agents, Recherche sémantique) + zone centrale adaptative selon
  le type de contenu (bulles de chat, image, lecteur vidéo, lecteur audio).
- Sélecteur de modèle/provider par conversation, avec favoris et mode
  « Auto » (auto-combo) affichant le provider effectivement utilisé.
- Panneau « Outils » par conversation : activation/désactivation des
  scopes MCP, journal des invocations d'outils inline dans le fil de
  discussion.
- Écran « Agents » : gestion des connexions A2A externes et de leur
  historique d'échanges.
- Import de documents/images (OCR) et d'audio (transcription/traduction)
  directement depuis le chat, glisser-déposer supporté.
- Onglet « Recherche » : recherche sémantique (embeddings + rerank) dans
  l'historique des conversations et les documents importés.
- Réglages : gestion des `EndpointProfile` (URL + clé API), stockage de la
  clé exclusivement dans le Keychain macOS (jamais en clair dans
  `UserDefaults` ou un plist), indicateurs de quota par provider.

## Persistance (SwiftData)

Modèles principaux :

- `Conversation` — titre, date, modèle/provider par défaut.
- `Message` — rôle, contenu texte, pièces jointes, conversation parente.
- `MediaItem` — type (image/vidéo/musique), prompt source,
  provider/modèle utilisé, chemin du fichier dans
  `~/Library/Application Support/OmniChat/`, date de génération, lien vers
  la conversation d'origine.
- `EndpointProfile` — nom, URL de base, identifiant de la clé Keychain
  associée.
- `ImportedDocument` — fichier source (PDF/image/audio), texte extrait
  (OCR ou transcription), lien vers la conversation d'origine.
- `EmbeddingRecord` — vecteur + référence vers un `Message` ou
  `ImportedDocument`, utilisé par la recherche sémantique locale.
- `ToolInvocation` — outil MCP appelé, scope, payload, résultat, statut,
  horodatage, message associé.
- `AgentConnection` — agent A2A externe (URL, nom), historique
  d'échanges JSON-RPC.

Chaque média généré est sauvegardé automatiquement dans la bibliothèque
locale (visible dans la conversation ET dans l'onglet Galerie, filtrable
par type/date/prompt).

## Distribution & sécurité

- Distribution hors Mac App Store : DMG signé + notarisation Apple,
  hardened runtime, entitlements minimaux (réseau client, accès fichiers
  restreint aux exports utilisateur).
- Aucune télémétrie par défaut, cohérent avec la philosophie d'OmniRoute
  lui-même (pas de compte requis, stockage local).
- **Point de vigilance conformité** : si l'app est amenée à traiter des
  données professionnelles ou sensibles via un des 339 fournisseurs tiers
  d'OmniRoute (dont l'hébergement n'est pas garanti en France), une
  validation par le RSSI est recommandée avant tout usage en contexte
  professionnel (RGPD/ISO 27001).

## Gestion d'erreurs

Exigence explicite : la gestion d'erreurs doit être **exhaustive et
robuste**, pas une simple bannière générique. Elle est traitée comme un
composant de premier ordre d'`OmniRouteKit`, avec sa propre taxonomie et
ses propres tests, pas comme un détail d'implémentation de l'UI.

### Taxonomie (`OmniRouteError`)

Une erreur par cause racine, pas une erreur générique fourre-tout :

| Catégorie | Exemples | Action de reprise |
|---|---|---|
| Authentification | clé invalide/expirée (401) | Repromptage de la clé, lien vers les réglages |
| Quota / rate limit | 429, quota provider épuisé | Retry avec backoff exponentiel + jitter, ou bascule automatique sur un autre provider si mode Auto |
| Réseau / endpoint injoignable | timeout, DNS, connexion refusée (local ou distant) | État « déconnecté » explicite, bouton de reconnexion, dernière erreur affichée |
| Job média échoué | image/vidéo/musique : job en erreur ou expiré | Proposer relance avec les mêmes paramètres, conserver le prompt |
| Streaming interrompu | coupure SSE en cours de réponse | Reprise si possible, sinon message partiel conservé et marqué incomplet |
| Outil MCP en échec | scope refusé, exécution en erreur | Résultat d'erreur affiché inline dans le journal d'outils, sans bloquer la conversation |
| Agent A2A injoignable | erreur JSON-RPC, timeout | Statut de connexion visible dans l'écran Agents |
| Import échoué | OCR/transcription en erreur, format non supporté | Message clair sur la cause (format, taille, provider indisponible) |

### Politique de retry

- Backoff exponentiel + jitter pour rate limit et erreurs réseau
  transitoires, plafonné (nombre de tentatives et délai max configurables).
- Pas de retry automatique sur les erreurs d'authentification ou de
  validation (échec définitif tant que l'utilisateur n'a pas agi).
- En mode Auto (auto-combo), un échec sur un provider déclenche le
  fallback OmniRoute lui-même ; l'app affiche la chaîne de tentatives
  (quel provider a échoué, lequel a répondu) pour la transparence.

### Journal de diagnostic local

- Toute erreur est journalisée localement (fichier local, jamais envoyé à
  un service externe — cohérent avec le principe « aucune télémétrie »)
  avec contexte suffisant pour le support (endpoint, catégorie d'erreur,
  provider concerné, horodatage) et **sans** logguer le contenu des
  messages utilisateur ni les clés API.
- Purge automatique après une durée configurable (ex. 30 jours) et bouton
  « Exporter le journal » pour partager un rapport de bug sans exposer de
  données sensibles.

### UX

Chaque erreur remonte vers l'UI avec : un message compréhensible (pas de
message technique brut), la catégorie, et une action de reprise adaptée
issue du tableau ci-dessus. Aucune erreur silencieuse — un échec sans
action utilisateur possible reste visible tant qu'il n'est pas résolu ou
explicitement ignoré.

## Documentation vivante (README)

Exigence explicite de l'utilisateur : le `README.md` doit **toujours
rester à jour**. Il est versionné (exception ajoutée au `.gitignore` du
projet malgré l'exclusion globale de l'utilisateur) et doit couvrir en
permanence :

- ce qu'est OmniChat et son lien avec OmniRoute,
- la liste des capacités réellement implémentées à date (à faire
  correspondre au tableau des objectifs de ce spec, sans survendre de
  fonctionnalité pas encore livrée),
- comment builder/lancer le projet (Xcode, version macOS requise),
- comment configurer un `EndpointProfile` (endpoint local vs distant, clé
  API).

Règle de travail pour la suite : **toute tâche du plan d'implémentation
qui livre une fonctionnalité utilisateur met à jour le README dans le
même changeset** — ce n'est pas une tâche séparée qu'on peut reporter.

## Tests

- `OmniRouteKit` : tests unitaires avec `URLProtocol` mocké (aucun appel
  réseau réel), couvrant le parsing du streaming SSE, la state machine de
  polling de jobs, le mapping vers chaque catégorie d'`OmniRouteError`, la
  politique de retry/backoff, et les clients MCP/A2A.
- `OmniChat` : SwiftUI previews pour l'itération visuelle ; tests UI XCTest
  ciblés sur les flux critiques (envoyer un message, lancer une
  génération média, déclencher puis récupérer d'une erreur).

## Décisions actées durant le brainstorming

| Sujet | Décision |
|---|---|
| Découpage du projet | App macOS d'abord, OmniCLI en spec séparée ensuite |
| Stack | Swift + SwiftUI natif |
| Connexion | Local (défaut) + distant, configurable |
| Périmètre fonctionnel | Toutes les capacités OmniRoute dès v1 (pas de découpage v1/v2) — chat, médias, recherche web, RAG local, modèles locaux, MCP, A2A, OCR, traduction audio, auto-combo, quotas |
| Distribution | DMG notarié, hors App Store |
| macOS minimum | macOS 26+ |
| UI | Menu bar (accès rapide) + fenêtre principale |
| Médias générés | Bibliothèque locale avec vue Galerie dédiée |
| Gestion d'erreurs | Taxonomie exhaustive, retry/backoff explicite, journal de diagnostic local, aucune erreur silencieuse |
| README | Toujours à jour, versionné malgré le gitignore global, mis à jour dans le même changeset que chaque fonctionnalité livrée |

## Prochaine étape

Invoquer la skill `writing-plans` pour transformer ce spec en plan
d'implémentation détaillé et phasé (socle + chat, puis médias, puis
RAG/MCP/A2A/OCR/audio), chaque phase commençant par la vérification du
contrat API exact des endpoints qu'elle couvre avant tout code.
