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

## Objectifs (v1)

- Chat texte multi-modèles avec streaming.
- Génération d'images, de vidéo et de musique.
- Recherche web intégrée au flux de chat (fallback OmniRoute).
- Connexion à une instance OmniRoute locale (`http://localhost:20128/v1`
  par défaut) ou distante, configurable par l'utilisateur.
- Accès rapide via une icône de menu bar, en plus d'une fenêtre principale
  complète.
- Bibliothèque locale (Galerie) indexant tous les médias générés.

## Hors scope v1 (roadmap v2)

- Modèles locaux (Ollama / LM Studio / vLLM) comme provider sélectionnable.
- Outils / agents MCP (105 outils exposés par OmniRoute).
- Distribution Mac App Store (v1 = DMG notarié hors store).
- OmniCLI (spec et cycle de développement séparés).

## Architecture

Deux modules dans un seul projet Xcode :

### `OmniRouteKit` (Swift Package local, sans dépendance UI)

Client réseau pur vers l'API OmniRoute, conçu pour être réutilisé tel quel
par OmniCLI plus tard.

- `OmniRouteClient` (actor) : construit les requêtes HTTP, header
  `Authorization: Bearer <clé>`, base URL résolue depuis la configuration
  active (`EndpointProfile`).
- Chat : `POST /v1/chat/completions`, streaming SSE exposé comme
  `AsyncThrowingStream<ChatDelta>`.
- Modèles : `GET /v1/models` pour peupler les sélecteurs par
  modalité/provider (avec recherche/filtre côté UI, vu le volume de 339
  providers).
- Génération média : `POST /v1/{images,video,audio}/generations`, jobs
  asynchrones avec polling à backoff exponentiel jusqu'à complétion, puis
  téléchargement de l'asset final.
- `OmniRouteError` unifié : auth invalide, rate limit, job échoué, timeout,
  endpoint injoignable.

**⚠️ Risque technique identifié** : le résumé de documentation récupéré ne
garantit pas le schéma exact du polling de job (nom du champ job id,
endpoint de statut, format de la réponse). **Avant d'implémenter cette
partie, une étape de recherche dédiée est requise** : lire directement
`docs/reference/API_REFERENCE.md` dans le dépôt
[OmniRoute](https://github.com/diegosouzapw/OmniRoute) plutôt que de
supposer un format. Cette vérification doit être la première tâche du plan
d'implémentation pour `OmniRouteKit`.

### `OmniChat` (app target, SwiftUI, macOS 26+)

- `MenuBarExtra` : popover compact pour un prompt de chat rapide, avec
  action « ouvrir en fenêtre complète ».
- Fenêtre principale : `NavigationSplitView` — sidebar (liste des
  conversations + onglet Galerie), zone centrale adaptative selon le type
  de contenu (bulles de chat, image, lecteur vidéo, lecteur audio).
- Sélecteur de modèle/provider par conversation, avec favoris.
- Réglages : gestion des `EndpointProfile` (URL + clé API), stockage de la
  clé exclusivement dans le Keychain macOS (jamais en clair dans
  `UserDefaults` ou un plist).

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

Toute erreur `OmniRouteError` remonte vers l'UI sous forme de bannière
avec action de reprise adaptée (ex. re-saisir la clé API sur 401,
réessayer après délai sur 429, relancer le polling sur échec de job).
Détection de l'indisponibilité de l'endpoint (local ou distant) avec état
« déconnecté » explicite et action de reconnexion.

## Tests

- `OmniRouteKit` : tests unitaires avec `URLProtocol` mocké (aucun appel
  réseau réel), couvrant le parsing du streaming SSE et la state machine
  de polling de jobs.
- `OmniChat` : SwiftUI previews pour l'itération visuelle ; tests UI XCTest
  ciblés sur les flux critiques (envoyer un message, lancer une
  génération média).

## Décisions actées durant le brainstorming

| Sujet | Décision |
|---|---|
| Découpage du projet | App macOS d'abord, OmniCLI en spec séparée ensuite |
| Stack | Swift + SwiftUI natif |
| Connexion | Local (défaut) + distant, configurable |
| Modalités v1 | Chat (streaming) + images + vidéo + musique |
| Autres capacités v1 | Recherche web intégrée au chat uniquement |
| Modèles locaux / MCP | Reportés en v2 |
| Distribution | DMG notarié, hors App Store |
| macOS minimum | macOS 26+ |
| UI | Menu bar (accès rapide) + fenêtre principale |
| Médias générés | Bibliothèque locale avec vue Galerie dédiée |

## Prochaine étape

Invoquer la skill `writing-plans` pour transformer ce spec en plan
d'implémentation détaillé, en commençant par la vérification du contrat
API exact d'`OmniRouteKit` (job polling) avant tout code.
