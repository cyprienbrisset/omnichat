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
> suivant, appels d'outils agentiques réels dans le fil (`tools`/
> `tool_calls` OpenAI confirmés sur `/v1/chat/completions`, outils exécutés
> par OmniChat lui-même — jamais via le serveur MCP d'OmniRoute, inaccessible
> à distance), comparaison multi-modèles côte à côte (prompt unique, N flux
> réels indépendants), mode Fusion (N modèles sources + synthèse par un
> juge auto ou choisi, persisté dans son propre store séparé des
> conversations normales), retour possible au routage automatique
> (« auto ») après sélection d'un modèle précis dans une conversation,
> panneau Administration (fournisseurs, budgets, limites de jetons —
> visible uniquement si la clé a les droits de gestion), menu bar +
> fenêtre principale. RAG documentaire (import de fichiers), A2A, OCR,
> transcription audio et gestion des combos de routage/compression ne
> sont pas encore implémentés (voir le spec pour le périmètre complet).

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
sidebar), aux réglages/premier lancement et au menu bar. Le registre des
conversations (colonne du milieu, 300pt) ne s'affiche que face à une
conversation : Galerie, Mémoire, MCP, Recherche locale, Comparaison et
Administration gèrent chacun leur propre contenu de bout en bout et n'ont
rien à voir avec le choix d'une conversation — ils prennent donc toute la
largeur restante plutôt que de partager l'écran avec une liste sans
rapport. Chaque réponse
affiche, quand OmniRoute les fournit, sa trace de routage et son coût réels
(stratégie/fournisseur, latence, tokens, coût, cache) — lus depuis les
en-têtes `X-OmniRoute-*` de la réponse, jamais recalculés ni fabriqués : si
un champ est absent (le jeu coût/tokens n'est confirmé par la doc que hors
streaming), il n'apparaît simplement pas. Une vue comparaison de réponses
et un panneau de gestion des combos/routage font partie d'une direction
future documentée mais non planifiée — ils dépendent de fonctionnalités
(télémétrie de combo, coûts/latences par requête) pas encore construites.

## Fil de conversation

Le fil reste ancré en bas : au chargement, à chaque nouveau message, et
pendant le streaming (le contenu du dernier message grandit sur place sans
changer le nombre de messages, donc un `ScrollViewReader` suit explicitement
son `content` en plus du nombre de messages). Chaque message (demande ou
réponse) a un bouton copier discret qui place le texte réel dans le
presse-papiers — jamais un texte vide : pour un message média ou un simple
appel d'outil sans texte, il retombe sur le prompt ou le résultat d'outil
plutôt que de disparaître.

**Correctif rendu markdown :** les réponses n'étaient affichées qu'en texte
brut (`Text(content)`), donc `### titre`, `---` et `**gras**` s'affichaient
tels quels au lieu d'être mis en forme. Un parseur de blocs dédié
(`MarkdownParser`, testé unitairement) découpe désormais titres, règles
horizontales, listes et blocs de code ; chaque bloc de texte passe par
`Text(LocalizedStringKey:)`, qui applique le gras/italique/liens inline
nativement — pas de ré-implémentation d'un parseur inline. La lettrine
(grande première lettre) du mockup est conservée mais devient consciente du
markdown : si le paragraphe commence par un caractère spécial (`*`, `` ` ``…)
plutôt qu'une lettre, elle s'efface pour ne pas casser une paire
d'emphase.

**Correctif résultat d'outil tronqué :** la carte d'appel d'outil coupait le
résultat à 4 lignes (`lineLimit(4)`), ce qui coupait le vrai texte au milieu
d'un mot et se lisait comme un bug de troncature. Le résultat s'affiche
maintenant en entier en dessous d'un certain seuil, et au-delà propose un
vrai bouton « Afficher tout / Réduire » — jamais de donnée perdue en
silence.

**Correctif indicateur de génération après changement de conversation :**
`ChatView` recrée son `@State` (dont le `ChatViewModel`) à chaque
changement de conversation — y compris en revenant sur celle qu'on vient
de quitter — via `.task(id:)`. Une génération média lancée puis laissée en
arrière-plan pendant qu'on change de conversation continue réellement côté
réseau (elle finit par écrire le bon `MediaItem`), mais l'ancien
`ChatViewModel` qui suivait son `isStreaming`/`lastAttemptKind` était
remplacé par une instance neuve en revenant sur la conversation — l'app
affichait alors le mauvais indicateur (l'animation « Rédaction en cours… »
générique au lieu du squelette du bon type de média, voire rien) le temps
que la génération se termine. `AppEnvironment` garde désormais un
`ChatViewModel` par (conversation, profil actif) et le réutilise plutôt
que d'en recréer un à chaque passage — la génération en cours reste
suivie par la même instance, peu importe la navigation entre-temps.

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

**Correctif confirmé empiriquement :** ces quatre endpoints rejettent
l'alias de routage `"auto"` (valide sur `/v1/chat/completions` mais pas
ici — `"Invalid image model: auto. Use format: provider/model"`, même
schéma pour vidéo/musique/voix). OmniChat résout désormais un vrai modèle
avant chaque génération : `GET /v1/images|videos|music/generations`
renvoie le catalogue réel par type (comme `GET /v1/embeddings`) ; pour la
voix, qui n'a pas de catalogue dédié (`GET /v1/audio/speech` → `405` en
direct), les modèles TTS sont filtrés depuis `/v1/models` par
`type:"audio", subtype:"speech"` (à distinguer de `subtype:"transcription"`,
inutilisable pour la génération). Si un serveur n'a aucun modèle configuré
pour un type donné (ex. musique), l'app le dit clairement plutôt que
d'envoyer une requête vouée à échouer.

Pendant la génération, un squelette animé (au format réel de la sortie
attendue — image/vidéo/audio) remplace la simple icône qui clignotait
auparavant.

**Autre correctif confirmé empiriquement :** un serveur peut lister un
modèle dans son propre catalogue (`GET /v1/images/generations` par
exemple) dont la route de génération renvoie quand même un vrai `404`
(constaté en direct sur une entrée Fireworks précise) — un problème
d'enregistrement côté fournisseur, pas quelque chose qu'un simple « prendre
le premier de la liste » peut masquer. Constaté aussi : ce n'est pas une
entrée isolée — sur un serveur réel, tout un bloc de 5 entrées Fireworks
consécutives échoue de la même façon, suivi d'une entrée Gemini qui échoue
aussi (pour une raison amont différente). OmniChat essaie donc jusqu'à 20
modèles candidats du catalogue dans l'ordre, et ne passe au suivant que
sur ce `404` précis, ainsi qu'un `401`/`403` — toute autre erreur (quota,
budget, politique de contenu) est réelle et remonte immédiatement, sans
nouvelle tentative inutile qui la masquerait.

**Agrandir/lire et télécharger un média généré :** chaque média (fil de
conversation ou Galerie) affiche désormais un chip discret en coin avec
deux actions réelles — « Agrandir » ouvre `MediaDetailView` (le même
fichier réel en plus grand : image redimensionnée, `VideoPlayer` pour
vidéo/musique/voix), « Télécharger » ouvre un vrai panneau d'enregistrement
macOS (`NSSavePanel`) pour copier le fichier déjà téléchargé localement
(`~/Library/Application Support/OmniChat/Media/`) vers l'emplacement de
son choix — ce n'est pas un second téléchargement réseau, juste une copie
locale vers un endroit que l'utilisateur contrôle. Une image est en plus
cliquable n'importe où sur sa surface pour l'agrandir (elle n'a aucun
contrôle natif avec lequel un geste de tap pourrait entrer en conflit,
contrairement à `VideoPlayer` qui garde ses propres contrôles de lecture
intacts). Le chip ne s'affiche pas si le fichier réel est introuvable —
jamais de bouton menant à une action qui échouerait silencieusement.

**Correctif confirmé via le journal de diagnostic réel d'un utilisateur**
(`~/Library/Application Support/OmniChat/diagnostics.json`) : la
génération échouait malgré des fournisseurs bien configurés et un quota
actif, parce que le retry ne couvrait que le `404` — pas le `401`/`403`.
Si le tout premier candidat du catalogue appartient à un fournisseur dont
la clé est invalide ou n'a pas les droits pour ce type de média
spécifiquement (même quand d'autres fournisseurs, plus loin dans le
catalogue, sont correctement configurés), l'app abandonnait immédiatement
au lieu d'essayer les candidats suivants. Même logique que la résolution
de modèle d'embedding (RAG) : un candidat listé mais cassé (`404` ou
`401`/`403`) est ignoré, une vraie erreur d'un autre type surface
immédiatement.

Le composeur ne propose désormais un mode de génération (Image/Vidéo/
Musique/Voix) que si le serveur a réellement au moins un modèle pour ce
type — plus jamais de bouton menant systématiquement à une erreur
« aucun modèle disponible ».

Enfin, le casier ⌘K (sélection de modèle pour le chat et la comparaison)
filtre désormais `/v1/models` pour ne garder que les modèles de chat et
les combos : ce catalogue mélange en réalité chat, embeddings, images,
vidéo, audio, rerank et modération (confirmé en direct — `/v1/models`
« Returns all chat, embedding, and image models + combos »), et choisir
par erreur un modèle non-chat y échouait avec un vrai 400/404 côté serveur
(`"is an image-generation model and cannot be used on /v1/chat/completions"`).
Le casier propose aussi désormais une entrée « auto » fixe en tête de
liste (le routage automatique réel, mais qui n'apparaît jamais dans
`/v1/models` lui-même) — sans elle, une conversation dont le modèle avait
été changé ne pouvait plus jamais revenir au routage automatique.

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

**Correctif :** le parsing des listes (outils, journal d'audit) essayait
seulement 3 formes d'enveloppe (`data`/`tools`/`entries`/`logs`) et
échouait sur toute autre forme avec une erreur « unrecognized shape » peu
utile. Il essaie maintenant aussi `result`/`items`, et en dernier recours,
cherche n'importe quel tableau présent au premier niveau de la réponse —
quel que soit son nom de clé — avant d'abandonner. Toujours honnête : si
vraiment aucun tableau n'est trouvé, l'erreur reste claire plutôt que
d'inventer une liste vide.

Le journal d'audit (« Activité récente ») montre les appels d'outils MCP
*réellement* effectués contre ce serveur, par n'importe quel client. Ce
n'est **pas** le mécanisme derrière les cartes d'appel d'outil affichées
dans le fil de conversation (voir « Appels d'outils dans le fil »
ci-dessous) — ce journal reste utile même si OmniRoute lui-même est
inaccessible pour les appels de la passerelle.

**Confirmé empiriquement contre une instance OmniRoute réelle (3.8.49) :**
tous les `/api/mcp/*` renvoient `403 {"error":{"code":"LOCAL_ONLY",...}}`
dès qu'on les appelle depuis ailleurs que la machine qui héberge OmniRoute
elle-même — quels que soient les droits de la clé. Pour une instance
auto-hébergée distante (le cas d'usage principal de cette app), ce
navigateur MCP affichera donc toujours cette erreur, jamais une vraie
donnée. L'app détecte ce code précis et affiche le vrai message serveur
plutôt qu'un « Clé API invalide » trompeur (qui serait la lecture par
défaut d'un 403 générique).

## Appels d'outils dans le fil

Contrairement à ce que la découverte ci-dessus laissait présager, OmniChat
implémente désormais un vrai appel d'outils agentique — confirmé
empiriquement contre l'instance OmniRoute réelle : `POST
/v1/chat/completions` accepte bien un paramètre `tools` de type OpenAI, et
diffuse de vrais fragments `tool_calls` (`id`/`name` sur le premier
fragment, `arguments` réparti en morceaux JSON à concaténer, jusqu'à
`finish_reason: "tool_calls"`) — capturé directement depuis le serveur, pas
deviné. OmniChat **n'appelle jamais le serveur MCP d'OmniRoute** pour
exécuter ces outils (rappel : `/api/mcp/sse` et `/api/mcp/stream`, les
transports MCP réels, sont eux aussi `LOCAL_ONLY` et donc inaccessibles
pour une instance distante) — les outils proposés au modèle sont
entièrement définis et exécutés par OmniChat lui-même (`LocalTool` dans
`OmniChat/Support/LocalTools.swift`). Un seul outil pour l'instant :
`search_local_history`, qui appelle la recherche locale déjà construite
(RAG, section suivante). Chaque appel s'affiche dans le fil comme une
carte réelle (nom, arguments, résultat) — jamais fabriquée : si l'outil
échoue, le message d'erreur réel s'affiche. La boucle est plafonnée à 3
aller-retours par message pour éviter qu'un modèle bavard ne boucle
indéfiniment.

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

**Correctif confirmé empiriquement :** le bouton « Indexer » (et la
recherche, et l'outil `search_local_history`) ne faisaient confiance qu'au
tout premier modèle d'embedding du catalogue — le même problème que pour
la génération média (un modèle listé peut appartenir à un fournisseur non
configuré). La résolution du modèle d'embedding essaie maintenant
plusieurs candidats réels avec un vrai appel de test, jusqu'à en trouver un
qui fonctionne, et réutilise le même pour l'indexation et la recherche
d'une même session (des vecteurs de modèles différents ne sont jamais
comparables).

## Comparaison multi-modèles

Icône dédiée du rail. Un seul prompt envoyé à N modèles ajoutés via le
même casier ⌘K que le reste de l'app ; chaque colonne diffuse
indépendamment sa propre réponse réelle (`streamChatCompletion`) et
affiche ses propres jetons/coût/latence une fois reçus. Volontairement
éphémère : rien n'est persisté comme conversation — changer d'écran perd
les colonnes. Aucune notion de « combo » ou de juge ici, contrairement au
mode Fusion (section suivante) : c'est une comparaison brute, pas une
synthèse.

## Fusion

Icône dédiée du rail (à côté de Comparaison). Le même prompt part vers N
modèles sources (ajoutés via le casier ⌘K, comme Comparaison), puis un
modèle **juge** lit toutes les réponses réellement reçues et produit une
synthèse unique — un vrai second appel `/v1/chat/completions`, pas une
fusion côté client des textes. Il n'existe aucun endpoint OmniRoute dédié
à la fusion : contrairement aux combos de routage (fallback automatique
entre fournisseurs), c'est entièrement orchestré par OmniChat lui-même.

Le juge peut être choisi explicitement (casier ⌘K, avec la ligne « auto »
déjà utilisée pour le chat) ou laissé sur `"auto"`. Contrairement à la
génération média, `/v1/chat/completions` accepte réellement `"auto"`
côté serveur (confirmé en direct) — quand le juge est en auto, le vrai
modèle qui a répondu est lu depuis la télémétrie de routage de la réponse
(`X-OmniRoute-Decision`) et affiché à côté de la réponse fusionnée
(`auto → openai/gpt-4o`, par exemple), jamais juste « auto ».

Un modèle source qui échoue n'annule pas la fusion : seules les réponses
réellement reçues nourrissent le juge ; le round échoue explicitement
uniquement si **aucune** source n'a répondu (rien à fusionner). Les N
réponses sources restent consultables, repliées sous la réponse fusionnée
(bouton « Voir les réponses sources ») — la synthèse reste vérifiable
contre ce qui l'a réellement nourrie.

**Persistance délibérément séparée des conversations normales** (demande
explicite) : les sessions de Fusion vivent dans leur propre store SwiftData
(`FusionSession`/`FusionRound`/`FusionSourceResponse`), avec leur propre
liste dans l'écran Fusion — jamais mélangées à la liste de conversations
normale, puisqu'une réponse fusionnée n'est pas la réponse d'un seul
modèle. Seules les réponses sources qui ont réellement répondu sont
enregistrées dans un round persisté (un échec de source ne produit pas de
« réponse source » fictive).

## Administration (paramétrage OmniRoute via l'API de gestion)

Nouvelle icône du rail (curseurs), visible **uniquement** si la clé active a
les droits de gestion (`managementAccessState == .available`, même garde
que Mémoire/MCP) — une clé sans ces droits ne voit pas l'entrée du tout,
plutôt que de la voir échouer avec une erreur d'auth. Trois écrans :

- **Fournisseurs** (`GET/DELETE /api/providers`, `POST
  /api/providers/{id}/test`) — la forme exacte n'est documentée qu'en prose
  (pas de noms de champs garantis), donc chaque fournisseur reste une
  capture brute (`AdminRawSnapshot`) en dessous, mais une vraie carte met
  désormais en avant tout ce qu'on reconnaît sous plusieurs noms candidats :
  pastille de statut (`isActive`), badges type/auth (`provider`/`authType`),
  plan/tier (extraits même s'ils sont imbriqués dans un champ comme
  `providerSpecificData` — confirmé en direct sur un fournisseur connecté
  par OAuth), priorité, protection rate-limit (`rateLimitProtection`/
  `backoffLevel`), et l'expiration du token en relatif (« expire dans 8 h »)
  plutôt qu'un horodatage ISO brut. Le reste des champs (une vingtaine sur
  un fournisseur OAuth réel) se déplie en grille à deux colonnes, jamais un
  mur d'une seule colonne. **Correctif :** `JSONValue.displayValue` pour un
  objet imbriqué n'affichait que les *noms* de ses clés (`{plan, tier, ...}`),
  jamais leurs valeurs — un fournisseur avec un plan/tier réel dans
  `providerSpecificData` ne montrait donc littéralement rien d'utile ; il
  affiche maintenant les vraies paires clé/valeur récursivement
  (`{plan: pro, tier: 2}`). Bouton « Tester » par fournisseur, suppression
  avec confirmation. La création (`POST /api/providers`) envoie un corps au
  mieux (`{name, provider, apiKey}`) : **la forme réelle attendue n'est pas
  documentée** dans la référence d'API. L'écran d'ajout le dit explicitement
  et, si le serveur refuse ces champs, affiche son vrai message d'erreur Zod
  (`throwWithServerMessage`) plutôt qu'un « requête invalide » générique.
- **Budget** (`GET/POST /api/usage/budget`) — schéma entièrement documenté
  (Zod) dans la référence d'API : formulaire complet (jour/semaine/mois,
  seuil d'alerte en %, intervalle de réinitialisation), pas seulement la
  limite mensuelle.
- **Limites & quotas** (`GET/POST/DELETE /api/usage/token-limits` +
  `GET /api/rate-limits`) — **c'est ici que se trouve le vrai quota restant
  par fournisseur** : un vrai sélecteur de portée (Global/Modèle/Fournisseur,
  pas une devinette sur le texte saisi comme avant) permet de définir une
  limite scoped `provider`, et la lecture enrichit chaque limite avec
  `tokensUsed`/`remaining`/`nextResetAt` réels — affichés avec une barre de
  progression (rouge sous 15% restant, orange sous 40%). En dessous, le
  statut de rate-limit du compte (`GET /api/rate-limits`, forme non
  documentée elle aussi) s'affiche en lecture seule, en brut comme
  Fournisseurs.

Contrairement aux autres écrans de gestion (Mémoire, MCP), ce panneau
**modifie** la configuration réelle du serveur connecté (au lieu de
seulement la lire) — d'où la garde d'accès stricte et le choix de toujours
remonter le message d'erreur serveur réel plutôt qu'un message générique,
surtout là où le corps de requête est une hypothèse plutôt qu'un fait
documenté.

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

Si la clé a les droits de gestion, les Réglages (élargis à 620 pt) affichent
aussi une section « Fournisseurs » avec les vrais chiffres de
`/api/monitoring/health` (actifs / catalogue / configurés). **Constaté en
direct sur une instance réelle : un serveur peut n'avoir que ~25
fournisseurs configurés sur ~300 au catalogue.** La grande majorité des
modèles proposés partout dans l'app (chat, comparaison, génération média)
appartiennent alors à des fournisseurs sans identifiants configurés sur ce
serveur OmniRoute — les choisir échoue avec une vraie erreur serveur
(souvent un 404, parfois un 400/402/403 selon le fournisseur), qui n'est
pas un bug d'OmniChat mais un fournisseur non activé côté OmniRoute. Cette
section aide à distinguer immédiatement les deux cas.
