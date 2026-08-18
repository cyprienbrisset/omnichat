# OmniChat — Génération média (images, vidéo, musique, voix) — spec

Date : 2026-08-18
Statut : validé par l'utilisateur, prêt pour plan d'implémentation

## Contexte

Ce spec couvre le deuxième jalon d'implémentation d'OmniChat, après le
socle + chat (voir
[docs/superpowers/specs/2026-08-17-omnichat-macos-app-design.md](2026-08-17-omnichat-macos-app-design.md)).
Il ajoute la génération d'images, de vidéo, de musique et la synthèse
vocale (TTS) via OmniRoute, avec une bibliothèque locale (Galerie).

## Recherche préalable (contrat API vérifié)

Contrairement à l'hypothèse du spec du socle (« job-based avec
polling »), la lecture directe du fichier source
`docs/reference/API_REFERENCE.md` du dépôt OmniRoute — récupéré via
`curl` brut, sans résumé LLM intermédiaire, pour éviter le risque
d'injection de contenu déjà rencontré une fois sur ce projet lors d'un
fetch antérieur — montre que ces quatre endpoints sont **synchrones** :

```
POST /v1/images/generations  { model, prompt, size }   → JSON, format "OpenAI Images"
POST /v1/videos/generations  { model, prompt }         → JSON, "OpenAI-style"
POST /v1/music/generations   { model, prompt }         → JSON, "OpenAI-style"
POST /v1/audio/speech        { model, input, voice }   → corps audio brut (ex. audio/mpeg)
```

Aucun `job_id` ni endpoint de polling n'apparaît dans la documentation
source pour ces quatre routes — elles suivent le même modèle
requête/réponse synchrone que `/v1/chat/completions` (sans le
streaming).

**Point encore incertain** (à vérifier en tout début d'implémentation,
pas deviné) : la forme exacte du JSON de réponse pour
images/vidéo/musique — `data: [{url}]` vs `data: [{b64_json}]` (le
format « OpenAI Images » suggère fortement l'un des deux, à confirmer
contre la doc source ou une vraie instance avant d'écrire le parsing).

## Objectifs (ce jalon)

- Génération d'images, de vidéo, de musique, et synthèse vocale (TTS)
  depuis l'app.
- Bibliothèque locale (Galerie) indexant tous les médias générés,
  filtrable par type et par date.
- Chaque média généré apparaît à la fois inline dans la conversation
  d'origine et dans la Galerie.

## Hors scope (jalons futurs séparés)

- OCR, transcription audio (STT), recherche web, RAG, MCP, A2A.
- Édition d'image (`/v1/images/edits`) — non demandé, à considérer plus
  tard si besoin.
- Sélecteur de modèle par fournisseur pour chaque modalité — ce jalon
  utilise un modèle par défaut par modalité ; un vrai sélecteur (vu les
  339 fournisseurs) reste un jalon futur.

## Architecture

### `OmniRouteKit` (package, sans dépendance UI)

- `MediaGenerationRequest` — `model: String`, `prompt: String`, et des
  champs optionnels par modalité (`size: String?` pour les images).
- `MediaGenerationResult` — modélise les deux formes de réponse
  possibles (URL distante à télécharger, ou données binaires déjà
  décodées) : `enum MediaGenerationResult { case remoteURL(URL); case data(Data, contentType: String) }`.
- `OmniRouteClient.generateImage(_:) async throws -> MediaGenerationResult`
- `OmniRouteClient.generateVideo(_:) async throws -> MediaGenerationResult`
- `OmniRouteClient.generateMusic(_:) async throws -> MediaGenerationResult`
- `OmniRouteClient.synthesizeSpeech(_:) async throws -> Data` (audio
  brut, pas de wrapper JSON, format `{model, input, voice}` en entrée)
- Réutilise `OmniRouteError` et `RetryPolicy` (jitter par défaut) tels
  quels — aucun nouveau cas d'erreur nécessaire ; ces requêtes ne sont
  pas streamées donc `.streamInterrupted` ne s'applique pas ici.

### Persistance (SwiftData, app target)

- `MediaItem` — nouveau modèle :
  - `kind: String` (`"image"` / `"video"` / `"music"` / `"speech"`)
  - `prompt: String`
  - `modelID: String`
  - `fileName: String` (nom de fichier relatif au dossier Media, pas un
    chemin absolu — portable entre installations)
  - `createdAt: Date`
  - `conversation: Conversation?` (lien vers la conversation d'origine,
    pour la navigation depuis la Galerie)
- `Message` — nouvelle relation optionnelle `var mediaItem: MediaItem?`
  pour afficher le résultat inline sans dupliquer le contenu binaire
  dans le modèle `Message`.
- Fichiers stockés sous
  `~/Library/Application Support/OmniChat/Media/<uuid>.<ext>`
  (extension déduite du type de contenu retourné : `png`/`jpg` pour
  image, `mp4` pour vidéo, `mp3` pour musique/voix).

### UX / UI

- `ChatView` : sélecteur de mode compact (Texte / Image / Vidéo /
  Musique / Voix) au-dessus du champ de saisie. Le placeholder et le
  comportement d'envoi changent selon le mode actif.
- En mode média : le message utilisateur (le prompt) s'ajoute
  normalement ; au lieu de streamer une réponse texte, le ViewModel
  appelle la méthode de génération correspondante, télécharge ou
  décode le résultat, l'enregistre sur disque, crée un `MediaItem`, et
  l'associe à un message assistant dont le contenu texte reste vide —
  l'affichage se fait via le `MediaItem` lié.
- `MessageBubble` (dans `ChatView`) : si `message.mediaItem != nil`,
  affiche selon le type — image (`AsyncImage`/`Image`), lecteur vidéo
  (`AVKit.VideoPlayer`), contrôle de lecture audio simple pour
  musique/voix — plutôt que du texte.
- Nouvel onglet **Galerie** dans la barre latérale (`ContentView`) :
  grille de tous les `MediaItem` toutes conversations confondues,
  filtrable par type et triée par date, avec accès rapide à la
  conversation d'origine.
- Design : réutilise `OmniTheme` (cartes, boutons pilule, monospace
  pour le nom du modèle) — cohérent avec le reste de l'app, pas de
  nouveau système visuel.

### Gestion d'erreurs

- Réutilise `OmniRouteError` tel quel. Toute génération échouée affiche
  la bannière d'erreur existante (`ErrorBannerView`) avec l'action de
  reprise adaptée, exactement comme pour le chat.
- Téléchargement/sauvegarde du fichier sur disque : si l'écriture
  échoue, l'erreur est surfacée via un mécanisme similaire à
  `persistenceError` de `ChatViewModel` — jamais d'échec silencieux.

### Tests

- `OmniRouteKit` : tests avec `URLProtocol` mocké pour chaque méthode
  de génération (succès, erreur, format de réponse), une fois le
  format de réponse confirmé en début d'implémentation.
- App : test de persistance pour `MediaItem` et la relation
  `Message.mediaItem` (à la manière de `PersistenceModelsTests`), test
  du ViewModel de génération média avec un client factice (à la
  manière de `ChatViewModelTests`).

## Décisions actées durant le brainstorming

| Sujet | Décision |
|---|---|
| Contrat API | Synchrone (pas de job/polling), corrigeant l'hypothèse du spec du socle |
| Synthèse vocale (TTS) | Incluse dans ce jalon (endpoint simple, proche des autres) |
| Déclenchement UX | Mode de conversation dédié (sélecteur au-dessus du champ de saisie), pas un écran séparé |
| Affichage | Inline dans la conversation ET dans la Galerie |
| Édition d'image, sélecteur de modèle par fournisseur | Hors scope, jalons futurs |

## Prochaine étape

Invoquer `writing-plans` pour transformer ce spec en plan
d'implémentation, en commençant par la vérification du format de
réponse JSON exact des trois endpoints JSON (images/vidéo/musique)
avant d'écrire le parsing — même discipline que pour le socle + chat.
