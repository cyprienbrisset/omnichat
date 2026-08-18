# OmniChat — Génération média (images, vidéo, musique, voix) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add image, video, music generation and text-to-speech to OmniChat, with each result appearing inline in its conversation and in a new local Gallery.

**Architecture:** `OmniRouteKit` gets a `MediaGenerating` protocol + four synchronous request methods on `OmniRouteClient` (no job/polling — verified against the real API reference). The app target adds a `MediaItem` SwiftData model linked optionally from `Message`, a `MediaFileStore` that saves results to disk, and wires a composer mode picker into the existing `ChatView`/`ChatViewModel`, plus a new Gallery screen.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVKit (video/audio playback), XCTest.

**Spec:** [docs/superpowers/specs/2026-08-18-omnichat-media-generation-design.md](../specs/2026-08-18-omnichat-media-generation-design.md)

## Global Constraints

- macOS minimum: macOS 26+ (already the project's deployment target).
- No new `OmniRouteError` cases — media generation failures map onto the existing six cases (`.unknown` for unparseable responses).
- These four endpoints are synchronous request/response — no job ID, no polling loop. Verified against the OmniRoute repo's `docs/reference/API_REFERENCE.md` (raw file, not a summarized fetch).
- Media files are saved under `~/Library/Application Support/OmniChat/Media/<uuid>.<ext>` — never the app bundle, never iCloud-synced paths.
- Aucune erreur silencieuse : every failure (network, parsing, disk write) must be visible to the user via the existing `currentError`/`persistenceError` pattern on `ChatViewModel` — never swallowed.
- Any task that lands a user-visible feature updates `README.md` in the same changeset (established project rule).
- No new UI design system — reuse `OmniTheme` (colors, `omniPrimary` button style, monospace helper) exactly as already defined in `OmniChat/Support/Theme.swift`.

---

## File Structure

```
Packages/OmniRouteKit/Sources/OmniRouteKit/
├── OmniRouteClient.swift            MODIFY: widen 3 declarations from private to internal
├── MediaModels.swift                CREATE: MediaGenerationRequest, SpeechRequest, MediaGenerationResult,
│                                             MediaGenerating protocol, response parsing
└── OmniRouteClient+Media.swift       CREATE: OmniRouteClient conformance to MediaGenerating

Packages/OmniRouteKit/Tests/OmniRouteKitTests/
├── MediaModelsTests.swift                       CREATE
├── OmniRouteClientMediaGenerationTests.swift     CREATE
└── OmniRouteClientSpeechTests.swift              CREATE

OmniChat/Support/
├── MediaFileStore.swift             CREATE: saves a MediaGenerationResult to disk, returns a file name
└── MediaKind.swift                  CREATE: image/video/music/speech enum driving UI + generation dispatch

OmniChat/Models/
├── MediaItem.swift                  CREATE: SwiftData model for a generated media item
└── Message.swift                    MODIFY: add optional `mediaItem` relationship

OmniChat/ViewModels/
└── ChatViewModel.swift              MODIFY: add mediaClient/mediaFileStore deps, sendMediaPrompt(), retry dispatch

OmniChat/Views/
├── ChatView.swift                   MODIFY: composer mode picker, media rendering in MessageBubble
├── ContentView.swift                MODIFY: sidebar Gallery entry
└── GalleryView.swift                CREATE: grid of all generated media, filterable by kind

OmniChat/App/
└── OmniChatApp.swift                MODIFY: register MediaItem in the ModelContainer schema

OmniChatTests/
├── MediaFileStoreTests.swift        CREATE
├── MediaItemPersistenceTests.swift  CREATE
└── ChatViewModelTests.swift         MODIFY: update ChatViewModel(...) call sites, add media-path tests

README.md                            MODIFY: document the new capability (Task 9)
```

---

### Task 1: `MediaModels.swift` + widen `OmniRouteClient` internal access

**Files:**
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/MediaModels.swift`
- Modify: `Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/MediaModelsTests.swift`

**Interfaces:**
- Consumes: `OmniRouteError` (existing).
- Produces: `public struct MediaGenerationRequest`, `public struct SpeechRequest`, `public enum MediaGenerationResult: Sendable, Equatable { case remoteURL(URL); case inlineData(Data, contentType: String) }`, `public protocol MediaGenerating: Sendable` (four method signatures, defined here so Task 2/3 can conform and Task 6 can depend on it without a forward reference), internal `func parseMediaGenerationResponse(_:defaultContentType:) throws -> MediaGenerationResult`. Also produces: `session`, `retryPolicy`, and `authorizedRequest(path:)` on `OmniRouteClient` are no longer `private` (now file-and-module-internal) — Task 2/3 need to call them from a different file, the same way Task 7 of the previous plan called them from an extension in the *same* file. Swift's `private` is file-scoped, so a second file cannot use them unless the modifier is dropped.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OmniRouteKit

final class MediaModelsTests: XCTestCase {
    func test_parseMediaGenerationResponse_withURL_returnsRemoteURL() throws {
        let json = #"{"data":[{"url":"https://example.com/image.png"}]}"#.data(using: .utf8)!
        let result = try parseMediaGenerationResponse(json, defaultContentType: "image/png")
        XCTAssertEqual(result, .remoteURL(URL(string: "https://example.com/image.png")!))
    }

    func test_parseMediaGenerationResponse_withBase64_returnsInlineData() throws {
        let payload = Data("fake-bytes".utf8).base64EncodedString()
        let json = #"{"data":[{"b64_json":"\#(payload)"}]}"#.data(using: .utf8)!
        let result = try parseMediaGenerationResponse(json, defaultContentType: "image/png")
        XCTAssertEqual(result, .inlineData(Data("fake-bytes".utf8), contentType: "image/png"))
    }

    func test_parseMediaGenerationResponse_emptyData_throws() {
        let json = #"{"data":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try parseMediaGenerationResponse(json, defaultContentType: "image/png"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/OmniRouteKit && swift test --filter MediaModelsTests`
Expected: FAIL — `parseMediaGenerationResponse` does not exist.

- [ ] **Step 3: Implement `MediaModels.swift`**

```swift
import Foundation

public struct MediaGenerationRequest: Encodable, Sendable {
    public var model: String
    public var prompt: String
    public var size: String?

    public init(model: String, prompt: String, size: String? = nil) {
        self.model = model
        self.prompt = prompt
        self.size = size
    }
}

public struct SpeechRequest: Encodable, Sendable {
    public var model: String
    public var input: String
    public var voice: String

    public init(model: String, input: String, voice: String = "alloy") {
        self.model = model
        self.input = input
        self.voice = voice
    }
}

public enum MediaGenerationResult: Sendable, Equatable {
    case remoteURL(URL)
    case inlineData(Data, contentType: String)
}

public protocol MediaGenerating: Sendable {
    func generateImage(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult
    func generateVideo(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult
    func generateMusic(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult
    func synthesizeSpeech(_ request: SpeechRequest) async throws -> MediaGenerationResult
}

struct MediaGenerationResponse: Decodable {
    struct DataItem: Decodable {
        let url: String?
        let b64Json: String?

        private enum CodingKeys: String, CodingKey {
            case url
            case b64Json = "b64_json"
        }
    }
    let data: [DataItem]
}

enum MediaResponseParsingError: Error {
    case emptyData
    case unrecognizedItem
}

func parseMediaGenerationResponse(_ data: Data, defaultContentType: String) throws -> MediaGenerationResult {
    let decoded = try JSONDecoder().decode(MediaGenerationResponse.self, from: data)
    guard let first = decoded.data.first else {
        throw MediaResponseParsingError.emptyData
    }
    if let urlString = first.url, let url = URL(string: urlString) {
        return .remoteURL(url)
    }
    if let base64 = first.b64Json, let decodedData = Data(base64Encoded: base64) {
        return .inlineData(decodedData, contentType: defaultContentType)
    }
    throw MediaResponseParsingError.unrecognizedItem
}
```

- [ ] **Step 4: Widen access in `OmniRouteClient.swift`**

In `Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient.swift`, remove the `private` keyword from exactly these three declarations (leave everything else — including their `nonisolated` modifiers — unchanged):

```swift
    nonisolated let session: URLSession
    nonisolated let retryPolicy: RetryPolicy
```

and

```swift
    nonisolated func authorizedRequest(path: String) throws -> URLRequest {
```

`profile` and `credentialStore` stay `private` — nothing outside this file needs them directly, only through `authorizedRequest`.

- [ ] **Step 5: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test`
Expected: 24/24 passing (21 pre-existing + 3 new `MediaModelsTests`), no regressions from the access-level change.

- [ ] **Step 6: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/MediaModels.swift Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/MediaModelsTests.swift
git commit -m "feat(kit): add media generation models and response parsing"
```

---

### Task 2: `OmniRouteClient.generateImage/generateVideo/generateMusic`

**Files:**
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient+Media.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteClientMediaGenerationTests.swift`

**Interfaces:**
- Consumes: `MediaGenerationRequest`, `MediaGenerationResult`, `MediaGenerating`, `parseMediaGenerationResponse` (Task 1); `session`, `retryPolicy`, `authorizedRequest`, `requireSuccess`, `mapNetworkingError` (now internal, Task 1); `MockURLProtocol`/`makeMockSession()` (existing, from Task 6 of the previous plan).
- Produces: `extension OmniRouteClient: MediaGenerating` with `generateImage`, `generateVideo`, `generateMusic` implemented (`synthesizeSpeech` comes in Task 3, in the same file).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class OmniRouteClientMediaGenerationTests: XCTestCase {
    func test_generateImage_success_returnsRemoteURL() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let json = #"{"data":[{"url":"https://example.com/cat.png"}]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let result = try await client.generateImage(MediaGenerationRequest(model: "auto", prompt: "un chat"))
        XCTAssertEqual(result, .remoteURL(URL(string: "https://example.com/cat.png")!))
    }

    func test_generateVideo_success_returnsRemoteURL() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let json = #"{"data":[{"url":"https://example.com/clip.mp4"}]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let result = try await client.generateVideo(MediaGenerationRequest(model: "auto", prompt: "un lever de soleil"))
        XCTAssertEqual(result, .remoteURL(URL(string: "https://example.com/clip.mp4")!))
    }

    func test_generateMusic_success_returnsRemoteURL() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let json = #"{"data":[{"url":"https://example.com/song.mp3"}]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let result = try await client.generateMusic(MediaGenerationRequest(model: "auto", prompt: "une berceuse"))
        XCTAssertEqual(result, .remoteURL(URL(string: "https://example.com/song.mp3")!))
    }

    func test_generateImage_401_throwsAuthenticationFailed() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(
            profile: profile, credentialStore: store, session: makeMockSession(),
            retryPolicy: RetryPolicy(maxAttempts: 1)
        )
        do {
            _ = try await client.generateImage(MediaGenerationRequest(model: "auto", prompt: "x"))
            XCTFail("expected authenticationFailed")
        } catch OmniRouteError.authenticationFailed {
            // expected
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteClientMediaGenerationTests`
Expected: FAIL — `generateImage`/`generateVideo`/`generateMusic` do not exist on `OmniRouteClient`.

- [ ] **Step 3: Implement**

```swift
import Foundation

extension OmniRouteClient: MediaGenerating {
    public func generateImage(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try await performMediaGeneration(request, path: "images/generations", defaultContentType: "image/png")
    }

    public func generateVideo(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try await performMediaGeneration(request, path: "videos/generations", defaultContentType: "video/mp4")
    }

    public func generateMusic(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try await performMediaGeneration(request, path: "music/generations", defaultContentType: "audio/mpeg")
    }

    private func performMediaGeneration(
        _ request: MediaGenerationRequest,
        path: String,
        defaultContentType: String
    ) async throws -> MediaGenerationResult {
        var attempt = 1
        while true {
            do {
                var urlRequest = try authorizedRequest(path: path)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try JSONEncoder().encode(request)

                let (data, response) = try await session.data(for: urlRequest)
                _ = try Self.requireSuccess(response)
                do {
                    return try parseMediaGenerationResponse(data, defaultContentType: defaultContentType)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse média invalide: \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteClientMediaGenerationTests`
Expected: PASS, 4/4.

- [ ] **Step 5: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient+Media.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteClientMediaGenerationTests.swift
git commit -m "feat(kit): add generateImage/generateVideo/generateMusic"
```

---

### Task 3: `OmniRouteClient.synthesizeSpeech`

**Files:**
- Modify: `Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient+Media.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteClientSpeechTests.swift`

**Interfaces:**
- Consumes: `SpeechRequest`, `MediaGenerationResult` (Task 1).
- Produces: `OmniRouteClient.synthesizeSpeech(_:)` completing the `MediaGenerating` conformance.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class OmniRouteClientSpeechTests: XCTestCase {
    func test_synthesizeSpeech_success_returnsInlineDataWithContentType() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let audioBytes = Data("fake-mp3-bytes".utf8)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "audio/mpeg"]
            )!
            return (response, audioBytes)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let result = try await client.synthesizeSpeech(SpeechRequest(model: "auto", input: "Bonjour"))
        XCTAssertEqual(result, .inlineData(audioBytes, contentType: "audio/mpeg"))
    }

    func test_synthesizeSpeech_429_throwsRateLimited() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "5"]
            )!
            return (response, Data())
        }
        let client = OmniRouteClient(
            profile: profile, credentialStore: store, session: makeMockSession(),
            retryPolicy: RetryPolicy(maxAttempts: 1)
        )
        do {
            _ = try await client.synthesizeSpeech(SpeechRequest(model: "auto", input: "x"))
            XCTFail("expected rateLimited")
        } catch OmniRouteError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 5)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteClientSpeechTests`
Expected: FAIL — `synthesizeSpeech` does not exist.

- [ ] **Step 3: Implement (append to `OmniRouteClient+Media.swift`)**

```swift
extension OmniRouteClient {
    public func synthesizeSpeech(_ request: SpeechRequest) async throws -> MediaGenerationResult {
        var attempt = 1
        while true {
            do {
                var urlRequest = try authorizedRequest(path: "audio/speech")
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try JSONEncoder().encode(request)

                let (data, response) = try await session.data(for: urlRequest)
                let http = try Self.requireSuccess(response)
                let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "audio/mpeg"
                return .inlineData(data, contentType: contentType)
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteClientSpeechTests`
Expected: PASS, 2/2.

- [ ] **Step 5: Run the full kit suite**

Run: `cd Packages/OmniRouteKit && swift test`
Expected: 30/30 passing (24 after Task 1 + 4 from Task 2 + 2 from Task 3).

- [ ] **Step 6: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient+Media.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteClientSpeechTests.swift
git commit -m "feat(kit): add synthesizeSpeech, completing MediaGenerating"
```

`OmniRouteKit` is now feature-complete for this phase. Remaining tasks build the `OmniChat` app target.

---

### Task 4: `MediaFileStore`

**Files:**
- Create: `OmniChat/Support/MediaFileStore.swift`
- Test: `OmniChatTests/MediaFileStoreTests.swift`

**Interfaces:**
- Consumes: `MediaGenerationResult` (`OmniRouteKit`, Task 1).
- Produces: `struct MediaFileStore` with `init(directory: URL = MediaFileStore.defaultDirectory)`, `static var defaultDirectory: URL`, `func save(_ result: MediaGenerationResult, preferredExtension: String) async throws -> String` (returns a file name, not a full path).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import OmniRouteKit
@testable import OmniChat

final class MediaFileStoreTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func test_save_inlineData_writesFileWithExtension() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MediaFileStore(directory: directory)
        let payload = Data("fake-image-bytes".utf8)

        let fileName = try await store.save(.inlineData(payload, contentType: "image/png"), preferredExtension: "png")

        XCTAssertTrue(fileName.hasSuffix(".png"))
        let written = try Data(contentsOf: directory.appendingPathComponent(fileName))
        XCTAssertEqual(written, payload)
    }

    func test_save_remoteURL_downloadsAndWritesFile() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceData = Data("fake-video-bytes".utf8)
        let sourceFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try sourceData.write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        let store = MediaFileStore(directory: directory)
        let fileName = try await store.save(.remoteURL(sourceFile), preferredExtension: "mp4")

        XCTAssertTrue(fileName.hasSuffix(".mp4"))
        let written = try Data(contentsOf: directory.appendingPathComponent(fileName))
        XCTAssertEqual(written, sourceData)
    }
}
```

Note: `.remoteURL(sourceFile)` uses a `file://` URL on purpose — `URLSession.data(from:)` supports the `file` scheme, so this test exercises the real download code path without any network mocking.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/MediaFileStoreTests`
Expected: FAIL — `MediaFileStore` does not exist.

- [ ] **Step 3: Implement**

```swift
import Foundation
import OmniRouteKit

struct MediaFileStore {
    let directory: URL

    init(directory: URL = MediaFileStore.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OmniChat", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }

    func save(_ result: MediaGenerationResult, preferredExtension: String) async throws -> String {
        let data: Data
        switch result {
        case .remoteURL(let url):
            let (downloaded, _) = try await URLSession.shared.data(from: url)
            data = downloaded
        case .inlineData(let inline, _):
            data = inline
        }
        let fileName = "\(UUID().uuidString).\(preferredExtension)"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/MediaFileStoreTests`
Expected: PASS, 2/2.

- [ ] **Step 5: Commit**

```bash
git add OmniChat/Support/MediaFileStore.swift OmniChatTests/MediaFileStoreTests.swift
git commit -m "feat(app): add MediaFileStore"
```

---

### Task 5: `MediaItem` model + `Message.mediaItem`

**Files:**
- Create: `OmniChat/Models/MediaItem.swift`
- Modify: `OmniChat/Models/Message.swift`
- Modify: `OmniChat/App/OmniChatApp.swift`
- Test: `OmniChatTests/MediaItemPersistenceTests.swift`

**Interfaces:**
- Consumes: `MediaFileStore.defaultDirectory` (Task 4); `Conversation` (existing).
- Produces: `@Model final class MediaItem` (`kind: String`, `prompt: String`, `modelID: String`, `fileName: String`, `createdAt: Date`, `conversation: Conversation?`, computed `fileURL: URL`); `Message.mediaItem: MediaItem?`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftData
@testable import OmniChat

final class MediaItemPersistenceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Conversation.self, Message.self, StoredEndpointProfile.self, MediaItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_savingMessageWithMediaItem_persistsRelationshipAndFileURL() throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)

        let mediaItem = MediaItem(kind: "image", prompt: "un chat", modelID: "auto", fileName: "abc.png")
        mediaItem.conversation = conversation
        context.insert(mediaItem)

        let message = Message(role: "assistant", content: "")
        message.conversation = conversation
        message.mediaItem = mediaItem
        conversation.messages.append(message)

        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.mediaItem?.fileName, "abc.png")
        XCTAssertTrue(fetched.first?.mediaItem?.fileURL.path.hasSuffix("abc.png") ?? false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/MediaItemPersistenceTests`
Expected: FAIL — `MediaItem` does not exist.

- [ ] **Step 3: Implement `MediaItem.swift`**

```swift
import Foundation
import SwiftData

@Model
final class MediaItem {
    var kind: String
    var prompt: String
    var modelID: String
    var fileName: String
    var createdAt: Date
    var conversation: Conversation?

    init(kind: String, prompt: String, modelID: String, fileName: String, createdAt: Date = Date()) {
        self.kind = kind
        self.prompt = prompt
        self.modelID = modelID
        self.fileName = fileName
        self.createdAt = createdAt
    }

    var fileURL: URL {
        MediaFileStore.defaultDirectory.appendingPathComponent(fileName)
    }
}
```

- [ ] **Step 4: Add the relationship to `Message.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Message {
    var role: String
    var content: String
    var createdAt: Date
    var isIncomplete: Bool
    var conversation: Conversation?
    var mediaItem: MediaItem?

    init(role: String, content: String, isIncomplete: Bool = false, createdAt: Date = Date()) {
        self.role = role
        self.content = content
        self.isIncomplete = isIncomplete
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 5: Register `MediaItem` in the app's `ModelContainer`**

In `OmniChat/App/OmniChatApp.swift`, change:

```swift
modelContainer = try ModelContainer(for: Conversation.self, Message.self, StoredEndpointProfile.self)
```

to:

```swift
modelContainer = try ModelContainer(for: Conversation.self, Message.self, StoredEndpointProfile.self, MediaItem.self)
```

- [ ] **Step 6: Run and verify pass**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS'`
Expected: 13/13 app tests passing (10 pre-existing + 2 from Task 4 + 1 new).

- [ ] **Step 7: Commit**

```bash
git add OmniChat/Models/MediaItem.swift OmniChat/Models/Message.swift OmniChat/App/OmniChatApp.swift OmniChatTests/MediaItemPersistenceTests.swift
git commit -m "feat(app): add MediaItem model and Message.mediaItem relationship"
```

---

### Task 6: `MediaKind` + `ChatViewModel.sendMediaPrompt`

**Files:**
- Create: `OmniChat/Support/MediaKind.swift`
- Modify: `OmniChat/ViewModels/ChatViewModel.swift`
- Modify: `OmniChatTests/ChatViewModelTests.swift`

**Interfaces:**
- Consumes: `MediaGenerating`, `MediaGenerationRequest`, `SpeechRequest`, `MediaGenerationResult` (`OmniRouteKit`); `MediaFileStore` (Task 4); `MediaItem` (Task 5).
- Produces: `enum MediaKind: String, CaseIterable, Identifiable` (`image`, `video`, `music`, `speech`; `label`, `systemImage`, `fileExtension`, `promptPlaceholder`); `ChatViewModel.init(conversation:client:mediaClient:mediaFileStore:context:diagnosticLogger:endpointName:)` (two new required parameters); `ChatViewModel.sendMediaPrompt(_:kind:) async`. `retryLastMessage()` now dispatches to the correct path (text vs. media) based on what was last attempted.

- [ ] **Step 1: Implement `MediaKind.swift` (no test — pure enum of static data, exercised indirectly by Step 3's tests)**

```swift
enum MediaKind: String, CaseIterable, Identifiable {
    case image, video, music, speech

    var id: String { rawValue }

    var label: String {
        switch self {
        case .image: return "Image"
        case .video: return "Vidéo"
        case .music: return "Musique"
        case .speech: return "Voix"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .music: return "music.note"
        case .speech: return "waveform"
        }
    }

    var fileExtension: String {
        switch self {
        case .image: return "png"
        case .video: return "mp4"
        case .music, .speech: return "mp3"
        }
    }

    var promptPlaceholder: String {
        switch self {
        case .image: return "Décris l'image à générer…"
        case .video: return "Décris la vidéo à générer…"
        case .music: return "Décris la musique à générer…"
        case .speech: return "Texte à transformer en voix…"
        }
    }
}
```

- [ ] **Step 2: Write the failing tests**

Add to `OmniChatTests/ChatViewModelTests.swift` — a `FakeMediaGenerating` spy alongside the existing `FakeChatCompleting`, an updated `makeViewModel` helper, and two new test functions. Apply this diff (the existing `FakeChatCompleting` class and the three existing `send`/history tests are unchanged; only `makeViewModel` and the additions below matter):

```swift
private final class FakeMediaGenerating: MediaGenerating, @unchecked Sendable {
    enum Outcome {
        case success(MediaGenerationResult)
        case failure(Error)
    }

    var outcome: Outcome = .success(.inlineData(Data("fake".utf8), contentType: "image/png"))
    private(set) var lastPrompt: String?

    private func resolve(_ prompt: String) throws -> MediaGenerationResult {
        lastPrompt = prompt
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    func generateImage(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt)
    }
    func generateVideo(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt)
    }
    func generateMusic(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt)
    }
    func synthesizeSpeech(_ request: SpeechRequest) async throws -> MediaGenerationResult {
        try resolve(request.input)
    }
}
```

Replace the existing `makeViewModel` helper with:

```swift
    private func makeMediaFileStore() -> MediaFileStore {
        MediaFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func makeViewModel(
        conversation: Conversation,
        client: ChatCompleting,
        context: ModelContext,
        mediaClient: MediaGenerating = FakeMediaGenerating()
    ) -> ChatViewModel {
        ChatViewModel(
            conversation: conversation,
            client: client,
            mediaClient: mediaClient,
            mediaFileStore: makeMediaFileStore(),
            context: context,
            diagnosticLogger: makeDiagnosticLogger(),
            endpointName: "Test"
        )
    }
```

Add these two test functions:

```swift
    func test_sendMediaPrompt_createsMediaItemAndLinksToAssistantMessage() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeMedia = FakeMediaGenerating()
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, mediaClient: fakeMedia)

        await viewModel.sendMediaPrompt("un chat sur la lune", kind: .image)

        XCTAssertEqual(fakeMedia.lastPrompt, "un chat sur la lune")
        let assistantMessage = conversation.orderedMessages.last
        XCTAssertEqual(assistantMessage?.mediaItem?.kind, "image")
        XCTAssertNil(viewModel.currentError)
    }

    func test_retryLastMessage_afterFailedMediaPrompt_retriesSameKind() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeMedia = FakeMediaGenerating()
        fakeMedia.outcome = .failure(OmniRouteError.network(description: "timeout"))
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, mediaClient: fakeMedia)

        await viewModel.sendMediaPrompt("un chat", kind: .image)
        XCTAssertNotNil(viewModel.currentError)

        fakeMedia.outcome = .success(.inlineData(Data("fake".utf8), contentType: "image/png"))
        await viewModel.retryLastMessage()

        XCTAssertNil(viewModel.currentError)
        XCTAssertEqual(conversation.orderedMessages.last?.mediaItem?.kind, "image")
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/ChatViewModelTests`
Expected: FAIL to compile — `ChatViewModel.init` doesn't accept `mediaClient`/`mediaFileStore`, `sendMediaPrompt` doesn't exist.

- [ ] **Step 4: Implement — modify `ChatViewModel.swift`**

Replace the stored properties and `init`:

```swift
    private let client: ChatCompleting
    private let mediaClient: MediaGenerating
    private let mediaFileStore: MediaFileStore
    private let context: ModelContext
    private let diagnosticLogger: DiagnosticLogger
    private let endpointName: String
    private var lastAttemptKind: MediaKind?

    init(
        conversation: Conversation,
        client: ChatCompleting,
        mediaClient: MediaGenerating,
        mediaFileStore: MediaFileStore,
        context: ModelContext,
        diagnosticLogger: DiagnosticLogger,
        endpointName: String
    ) {
        self.conversation = conversation
        self.client = client
        self.mediaClient = mediaClient
        self.mediaFileStore = mediaFileStore
        self.context = context
        self.diagnosticLogger = diagnosticLogger
        self.endpointName = endpointName
    }
```

At the top of `send(_:)`, right after `persistenceError = nil`, add:

```swift
        lastAttemptKind = nil
```

Add these two new methods (after `send(_:)`, before `retryLastMessage()`):

```swift
    func sendMediaPrompt(_ text: String, kind: MediaKind) async {
        currentError = nil
        persistenceError = nil
        lastAttemptKind = kind

        let userMessage = Message(role: "user", content: text)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)

        let assistantMessage = Message(role: "assistant", content: "")
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)

        isStreaming = true
        defer { isStreaming = false }

        do {
            let result = try await generate(kind: kind, prompt: text)
            let fileName = try await mediaFileStore.save(result, preferredExtension: kind.fileExtension)
            let mediaItem = MediaItem(kind: kind.rawValue, prompt: text, modelID: "auto", fileName: fileName)
            mediaItem.conversation = conversation
            context.insert(mediaItem)
            assistantMessage.mediaItem = mediaItem
        } catch let error as OmniRouteError {
            assistantMessage.isIncomplete = true
            currentError = error
            await logDiagnostic(error)
        } catch {
            assistantMessage.isIncomplete = true
            let mapped = OmniRouteError.unknown(description: "\(error)")
            currentError = mapped
            await logDiagnostic(mapped)
        }

        do {
            try context.save()
        } catch {
            persistenceError = "Impossible d'enregistrer le média : \(error.localizedDescription)"
            return
        }
        persistenceError = nil
    }

    private func generate(kind: MediaKind, prompt: String) async throws -> MediaGenerationResult {
        switch kind {
        case .image:
            return try await mediaClient.generateImage(MediaGenerationRequest(model: "auto", prompt: prompt))
        case .video:
            return try await mediaClient.generateVideo(MediaGenerationRequest(model: "auto", prompt: prompt))
        case .music:
            return try await mediaClient.generateMusic(MediaGenerationRequest(model: "auto", prompt: prompt))
        case .speech:
            return try await mediaClient.synthesizeSpeech(SpeechRequest(model: "auto", input: prompt))
        }
    }
```

Replace `retryLastMessage()`'s final line (`await send(lastUserMessage.content)`) so the whole method reads:

```swift
    func retryLastMessage() async {
        guard let lastUserMessage = conversation.orderedMessages.last(where: { $0.role == "user" }) else { return }

        if let trailing = conversation.orderedMessages.last,
           trailing.role == "assistant",
           trailing.isIncomplete {
            conversation.messages.removeAll { $0.persistentModelID == trailing.persistentModelID }
            context.delete(trailing)
        }

        if let kind = lastAttemptKind {
            await sendMediaPrompt(lastUserMessage.content, kind: kind)
        } else {
            await send(lastUserMessage.content)
        }
    }
```

- [ ] **Step 5: Run and verify pass**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/ChatViewModelTests`
Expected: PASS, 6/6 (4 pre-existing + 2 new).

- [ ] **Step 6: Run the full app test suite**

Run: `xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS'`
Expected: 15/15 passing (13 after Task 5 + 2 new).

- [ ] **Step 7: Commit**

```bash
git add OmniChat/Support/MediaKind.swift OmniChat/ViewModels/ChatViewModel.swift OmniChatTests/ChatViewModelTests.swift
git commit -m "feat(app): add MediaKind and ChatViewModel.sendMediaPrompt"
```

---

### Task 7: `ChatView` composer mode + media rendering

**Files:**
- Modify: `OmniChat/Views/ChatView.swift`

**Interfaces:**
- Consumes: `MediaKind` (Task 6); `ChatViewModel.sendMediaPrompt` (Task 6); `MediaFileStore` (Task 4); `MediaItem.fileURL` (Task 5).
- Produces: none consumed by later tasks — this is a leaf UI change. No new tests (SwiftUI view bodies have no business logic beyond what `ChatViewModel` already covers, per this project's established testing convention).

- [ ] **Step 1: Add `ComposerMode`, the mode picker, and media dispatch**

Replace the whole file with:

```swift
import SwiftUI
import SwiftData
import AVKit
import OmniRouteKit

private enum ComposerMode: String, CaseIterable, Identifiable {
    case text, image, video, music, speech

    var id: String { rawValue }

    var mediaKind: MediaKind? {
        switch self {
        case .text: return nil
        case .image: return .image
        case .video: return .video
        case .music: return .music
        case .speech: return .speech
        }
    }

    var systemImage: String {
        mediaKind?.systemImage ?? "text.bubble"
    }

    var placeholder: String {
        mediaKind?.promptPlaceholder ?? "Écris un message…"
    }
}

struct ChatView: View {
    let conversation: Conversation
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var draft = ""
    @State private var viewModel: ChatViewModel?
    @State private var mode: ComposerMode = .text

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel?.currentError {
                ErrorBannerView(error: error) {
                    Task { await viewModel?.retryLastMessage() }
                }
                .disabled(viewModel?.isStreaming ?? false)
            }
            if let persistenceError = viewModel?.persistenceError {
                PersistenceErrorBanner(message: persistenceError)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(conversation.orderedMessages, id: \.persistentModelID) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            .background(OmniTheme.canvasBackground)
            .background { OmniDotGridBackground() }
            VStack(spacing: 8) {
                Picker("Mode", selection: $mode) {
                    ForEach(ComposerMode.allCases) { candidate in
                        Label(candidate.mediaKind?.label ?? "Texte", systemImage: candidate.systemImage)
                            .labelStyle(.iconOnly)
                            .tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)

                HStack(spacing: 10) {
                    TextField(mode.placeholder, text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(OmniTheme.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(OmniTheme.cardBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        let text = draft
                        draft = ""
                        Task {
                            if let kind = mode.mediaKind {
                                await viewModel?.sendMediaPrompt(text, kind: kind)
                            } else {
                                await viewModel?.send(text)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(.omniPrimary)
                    .disabled(
                        viewModel == nil
                            || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (viewModel?.isStreaming ?? false)
                    )
                }
            }
            .padding(12)
        }
        .task(id: "\(conversation.persistentModelID)-\(appEnvironment.activeProfile.baseURL.absoluteString)") {
            let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
            viewModel = ChatViewModel(
                conversation: conversation,
                client: client,
                mediaClient: client,
                mediaFileStore: MediaFileStore(),
                context: context,
                diagnosticLogger: appEnvironment.diagnosticLogger,
                endpointName: appEnvironment.activeProfile.name
            )
        }
        .navigationTitle(conversation.title)
    }
}

private struct PersistenceErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" {
                Spacer(minLength: 40)
                userBubble
            } else {
                assistantCard
                Spacer(minLength: 40)
            }
        }
    }

    private var userBubble: some View {
        Text(message.content)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(OmniTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(message.isIncomplete ? Color.orange : OmniTheme.success)
                    .frame(width: 6, height: 6)
                Text("assistant")
                    .font(OmniTheme.mono(10, weight: .semibold))
                    .foregroundStyle(OmniTheme.secondaryText)
            }
            if let mediaItem = message.mediaItem {
                MediaContentView(mediaItem: mediaItem)
            } else {
                Text(message.content.isEmpty ? "…" : message.content)
                    .font(.system(size: 13))
            }
        }
        .padding(12)
        .background(OmniTheme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OmniTheme.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MediaContentView: View {
    let mediaItem: MediaItem

    var body: some View {
        switch mediaItem.kind {
        case "image":
            if let nsImage = NSImage(contentsOf: mediaItem.fileURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("Image indisponible").font(.system(size: 12)).foregroundStyle(OmniTheme.secondaryText)
            }
        case "video":
            VideoPlayer(player: AVPlayer(url: mediaItem.fileURL))
                .frame(width: 320, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case "music", "speech":
            VideoPlayer(player: AVPlayer(url: mediaItem.fileURL))
                .frame(width: 280, height: 50)
        default:
            Text("Média indisponible").font(.system(size: 12)).foregroundStyle(OmniTheme.secondaryText)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run the full app test suite (no new tests, must still pass)**

Run: `xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS'`
Expected: 15/15 passing, no regressions.

- [ ] **Step 4: Commit**

```bash
git add OmniChat/Views/ChatView.swift
git commit -m "feat(app): add composer mode picker and inline media rendering"
```

---

### Task 8: `GalleryView` + sidebar wiring

**Files:**
- Create: `OmniChat/Views/GalleryView.swift`
- Modify: `OmniChat/Views/ContentView.swift`

**Interfaces:**
- Consumes: `MediaItem` (Task 5); `MediaKind` (Task 6); `MediaContentView` (Task 7, reused for thumbnails — but at gallery-cell scale via a size-constrained frame, no changes needed to `MediaContentView` itself since callers control frame size).
- Produces: none consumed by later tasks in this plan.

- [ ] **Step 1: Implement `GalleryView.swift`**

```swift
import SwiftUI
import SwiftData

struct GalleryView: View {
    @Query(sort: \MediaItem.createdAt, order: .reverse) private var items: [MediaItem]
    @State private var filterKind: MediaKind?

    private var filteredItems: [MediaItem] {
        guard let filterKind else { return items }
        return items.filter { $0.kind == filterKind.rawValue }
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            filterBar
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "Aucun média généré",
                    systemImage: "photo.on.rectangle",
                    description: Text("Passe en mode Image, Vidéo, Musique ou Voix dans une conversation pour en générer un.")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredItems) { item in
                        GalleryCell(item: item)
                    }
                }
                .padding()
            }
        }
        .background(OmniTheme.canvasBackground)
        .navigationTitle("Galerie")
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterChip(title: "Tout", isSelected: filterKind == nil) { filterKind = nil }
            ForEach(MediaKind.allCases) { kind in
                FilterChip(title: kind.label, isSelected: filterKind == kind) { filterKind = kind }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? OmniTheme.accent : OmniTheme.cardBackground)
                .foregroundStyle(isSelected ? .white : OmniTheme.secondaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct GalleryCell: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaContentView(mediaItem: item)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(item.prompt)
                .font(.system(size: 11))
                .foregroundStyle(OmniTheme.secondaryText)
                .lineLimit(2)
        }
        .padding(8)
        .background(OmniTheme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmniTheme.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
```

- [ ] **Step 2: Wire the sidebar in `ContentView.swift`**

Replace the whole file with:

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.createdAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?
    @State private var isGallerySelected = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedConversation) {
                Button {
                    isGallerySelected = true
                    selectedConversation = nil
                } label: {
                    Label("Galerie", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                .listRowBackground(isGallerySelected ? OmniTheme.accent.opacity(0.15) : Color.clear)

                Section("Conversations") {
                    ForEach(conversations) { conversation in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.title)
                                .font(.system(size: 13, weight: .medium))
                            Text(conversation.createdAt, style: .relative)
                                .font(OmniTheme.mono(10))
                                .foregroundStyle(OmniTheme.secondaryText)
                        }
                        .padding(.vertical, 3)
                        .tag(conversation)
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem {
                    Button("Nouvelle conversation", systemImage: "plus", action: createConversation)
                }
                ToolbarItem {
                    SettingsLink {
                        Label("Réglages", systemImage: "gear")
                    }
                }
            }
            .onChange(of: selectedConversation) { _, newValue in
                if newValue != nil { isGallerySelected = false }
            }
        } detail: {
            if isGallerySelected {
                GalleryView()
            } else if let selectedConversation {
                ChatView(conversation: selectedConversation)
            } else {
                ContentUnavailableView {
                    Label("Aucune conversation", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Crée une conversation pour commencer à discuter.")
                } actions: {
                    Button("Nouvelle conversation", action: createConversation)
                        .buttonStyle(.omniPrimary)
                }
                .background(OmniTheme.canvasBackground)
                .background { OmniDotGridBackground() }
                .navigationTitle("OmniChat")
            }
        }
        .onAppear {
            if selectedConversation == nil && !isGallerySelected {
                selectedConversation = conversations.first
            }
        }
    }

    private func createConversation() {
        let conversation = Conversation(title: "Nouvelle conversation", defaultModelID: "auto")
        context.insert(conversation)
        selectedConversation = conversation
        isGallerySelected = false
    }
}
```

- [ ] **Step 3: Build and run the full test suite**

Run: `xcodegen generate && xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS'`
Expected: 15/15 passing, no regressions.

- [ ] **Step 4: Commit**

```bash
git add OmniChat/Views/GalleryView.swift OmniChat/Views/ContentView.swift
git commit -m "feat(app): add Gallery screen and sidebar entry"
```

---

### Task 9: README update + manual smoke test

**Files:**
- Modify: `README.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Update the "Statut" callout and feature list**

In `README.md`, update the status callout to add media generation to what's delivered:

```markdown
> **Statut : socle + chat + génération média fonctionnels.** Chat
> multi-modèles en streaming, génération d'images/vidéo/musique et
> synthèse vocale, galerie locale, gestion d'erreurs, persistance
> locale (SwiftData), clé API dans le Keychain, thème clair/sombre
> manuel, menu bar + fenêtre principale. RAG, MCP, A2A, OCR et
> transcription audio ne sont pas encore implémentés (voir le spec
> pour le périmètre complet).
```

- [ ] **Step 2: Regenerate the project, build, and run the full suite one last time**

Run: `xcodegen generate && xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

Run: `cd Packages/OmniRouteKit && swift test && cd .. && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS'`
Expected: 30/30 kit tests + 15/15 app tests passing.

- [ ] **Step 3: Manual smoke test**

This step is manual because it requires a running OmniRoute instance with image/video/music/speech-capable models configured.

1. Launch the app, open a conversation.
2. Switch the composer mode to Image, enter a prompt, send. Verify either the image appears inline (and in the Galerie tab), or a comprehensible error banner appears if no instance is reachable.
3. Repeat for Vidéo, Musique, and Voix.
4. Open the Galerie tab from the sidebar and confirm all four generated items appear, with filter chips working.
5. Confirm switching back to Texte mode still sends normal chat messages.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document media generation and update status"
```

---

## Self-Review Notes

- **Spec coverage:** image/vidéo/musique/voix generation ✓ (Tasks 1-3, 6-7), synchronous contract (no polling) ✓ (verified in spec's research section, reflected in Tasks 2-3's implementation), `MediaItem` persistence + file storage ✓ (Tasks 4-5), inline display in conversation ✓ (Task 7), Galerie ✓ (Task 8), no new `OmniRouteError` cases ✓ (Tasks 2-3 reuse `.unknown`/existing mapping), no silent errors ✓ (`currentError`/`persistenceError` reused for media path, Task 6), README updated ✓ (Task 9).
- **Placeholder scan:** none found — every step has concrete code or an exact command.
- **Type consistency checked:** `MediaGenerationResult` (Task 1) is the return type of all four `MediaGenerating` methods (Tasks 2-3) and the sole input to `MediaFileStore.save` (Task 4); `MediaKind.fileExtension`/`.label`/`.systemImage`/`.promptPlaceholder` (Task 6) are consumed identically by `ChatViewModel` (Task 6), `ChatView`'s `ComposerMode` (Task 7), and `GalleryView`'s filter chips (Task 8); `MediaItem.kind` stores `MediaKind.rawValue` (Task 6) and is read back as a raw string in `MediaContentView`'s `switch` (Task 7) and `GalleryView`'s filter (Task 8) — same four literal strings (`"image"`, `"video"`, `"music"`, `"speech"`) throughout.
- **Known residual risk carried from the spec:** the exact JSON response shape (`url` vs `b64_json`) is inferred from OmniRoute's stated "OpenAI Images"/"OpenAI-style" compatibility claim, not from a literal example in the source doc. Task 7's manual smoke test (a live OmniRoute instance) is what actually confirms this — if it turns out wrong, only `MediaModels.swift`'s `parseMediaGenerationResponse` and its 3 tests need to change; nothing downstream depends on the wire format directly, only on the resulting `MediaGenerationResult` enum.
