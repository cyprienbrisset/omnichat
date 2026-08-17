# OmniChat — Socle + Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundational Swift package (`OmniRouteKit`) and the first working, testable slice of the OmniChat macOS app — chat with streaming, robust error handling, local persistence, Keychain-backed credentials, and a menu bar + main window shell.

**Architecture:** Two modules in one Xcode project generated via XcodeGen: `OmniRouteKit` (local SPM package, no UI dependency, reusable later by OmniCLI) handles all network/error/retry logic; `OmniChat` (SwiftUI app target, macOS 26+) handles persistence (SwiftData), Keychain, and UI.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Concurrency (actors, `AsyncThrowingStream`), XCTest, XcodeGen.

**Spec:** [docs/superpowers/specs/2026-08-17-omnichat-macos-app-design.md](../specs/2026-08-17-omnichat-macos-app-design.md)

## Global Constraints

- macOS minimum: macOS 26+.
- Distribution target: DMG notarié, hors Mac App Store (hardened runtime, pas de sandboxing App Store à respecter pour ce plan).
- Aucune télémétrie externe, aucun envoi de données à un service tiers autre qu'OmniRoute lui-même.
- Clé API OmniRoute stockée exclusivement dans le Keychain macOS — jamais dans `UserDefaults`, un plist, ou un fichier en clair.
- Endpoint par défaut : `http://localhost:20128/v1`, configurable par l'utilisateur (local ou distant).
- Aucune erreur silencieuse : toute erreur `OmniRouteError` doit être observable par l'UI avec une action de reprise.
- Toute tâche de ce plan qui livre une fonctionnalité utilisateur visible met à jour `README.md` dans le même commit.

---

## File Structure

```
OmniChat/                                    (repo root)
├── project.yml                              XcodeGen spec (generates OmniChat.xcodeproj, gitignored)
├── .gitignore                               updated with build artifacts
├── Packages/OmniRouteKit/
│   ├── Package.swift
│   ├── Sources/OmniRouteKit/
│   │   ├── OmniRouteError.swift             error taxonomy + HTTP/URLError mapping
│   │   ├── RetryPolicy.swift                backoff + retry decision
│   │   ├── EndpointProfile.swift            endpoint value type
│   │   ├── CredentialStore.swift            CredentialStore protocol + InMemoryCredentialStore
│   │   ├── ChatModels.swift                 ChatRole, ChatMessage, ChatCompletionRequest, ChatDelta
│   │   ├── SSELineParser.swift              SSE line -> ChatDelta parsing
│   │   ├── ModelInfo.swift                  GET /v1/models response types
│   │   ├── OmniRouteClient.swift            actor: listModels(), streamChatCompletion(), ChatCompleting
│   │   └── DiagnosticLogger.swift           local JSON error log + purge
│   └── Tests/OmniRouteKitTests/
│       ├── MockURLProtocol.swift            shared network mocking helper
│       ├── OmniRouteErrorMappingTests.swift
│       ├── RetryPolicyTests.swift
│       ├── CredentialStoreTests.swift
│       ├── SSELineParserTests.swift
│       ├── OmniRouteClientModelsTests.swift
│       ├── OmniRouteClientChatStreamingTests.swift
│       └── DiagnosticLoggerTests.swift
├── OmniChat/
│   ├── App/OmniChatApp.swift                 @main, MenuBarExtra + WindowGroup + Settings scenes
│   ├── Models/Conversation.swift
│   ├── Models/Message.swift
│   ├── Models/StoredEndpointProfile.swift
│   ├── Support/AppEnvironment.swift           @Observable holder of active profile + credential store
│   ├── Support/KeychainCredentialStore.swift  CredentialStore impl backed by Keychain Services
│   ├── ViewModels/ChatViewModel.swift
│   └── Views/ContentView.swift, ChatView.swift, ErrorBannerView.swift, SettingsView.swift, MenuBarChatView.swift
└── OmniChatTests/
    ├── PersistenceModelsTests.swift
    ├── KeychainCredentialStoreTests.swift
    └── ChatViewModelTests.swift
```

---

### Task 1: Project scaffolding (XcodeGen + OmniRouteKit skeleton)

**Files:**
- Create: `project.yml`
- Create: `Packages/OmniRouteKit/Package.swift`
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteKit.swift`
- Create: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteKitTests.swift`
- Create: `OmniChat/App/OmniChatApp.swift` (placeholder, replaced in Task 12)
- Modify: `.gitignore`

**Interfaces:**
- Produces: a buildable `OmniChat.xcodeproj` (generated, gitignored) with targets `OmniChat`, `OmniChatTests`, and a local package dependency `OmniRouteKit`.

- [ ] **Step 1: Install XcodeGen if missing**

Run: `which xcodegen || brew install xcodegen`
Expected: `xcodegen` is on PATH afterwards (`xcodegen --version` prints a version).

- [ ] **Step 2: Create the OmniRouteKit package skeleton**

`Packages/OmniRouteKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OmniRouteKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OmniRouteKit", targets: ["OmniRouteKit"])
    ],
    targets: [
        .target(name: "OmniRouteKit"),
        .testTarget(name: "OmniRouteKitTests", dependencies: ["OmniRouteKit"])
    ]
)
```

`Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteKit.swift`:

```swift
// Network client and shared types for talking to an OmniRoute instance.
// See docs/superpowers/specs/2026-08-17-omnichat-macos-app-design.md
public enum OmniRouteKitInfo {
    public static let apiVersion = "v1"
}
```

`Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteKitTests.swift`:

```swift
import XCTest
@testable import OmniRouteKit

final class OmniRouteKitTests: XCTestCase {
    func test_apiVersion_isV1() {
        XCTAssertEqual(OmniRouteKitInfo.apiVersion, "v1")
    }
}
```

- [ ] **Step 3: Verify the package builds and tests pass**

Run: `cd Packages/OmniRouteKit && swift test`
Expected: `Test Suite 'All tests' passed` with 1 test.

- [ ] **Step 4: Create the XcodeGen project spec**

`project.yml` (repo root):

```yaml
name: OmniChat
options:
  bundleIdPrefix: online.omniroute.omnichat
  deploymentTarget:
    macOS: "26.0"
packages:
  OmniRouteKit:
    path: Packages/OmniRouteKit
targets:
  OmniChat:
    type: application
    platform: macOS
    sources: [OmniChat]
    dependencies:
      - package: OmniRouteKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: online.omniroute.omnichat
        MARKETING_VERSION: "0.1.0"
        ENABLE_HARDENED_RUNTIME: YES
  OmniChatTests:
    type: bundle.unit-test
    platform: macOS
    sources: [OmniChatTests]
    dependencies:
      - target: OmniChat
schemes:
  OmniChat:
    build:
      targets:
        OmniChat: all
        OmniChatTests: [test]
    test:
      targets: [OmniChatTests]
```

- [ ] **Step 5: Create a placeholder app entry point so XcodeGen has sources to include**

`OmniChat/App/OmniChatApp.swift`:

```swift
import SwiftUI

@main
struct OmniChatApp: App {
    var body: some Scene {
        WindowGroup {
            Text("OmniChat — socle en construction")
                .padding()
        }
    }
}
```

- [ ] **Step 6: Generate the Xcode project and verify it builds**

Run: `xcodegen generate && xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Ignore generated/build artifacts**

Append to `.gitignore`:

```
# Xcode / SwiftPM build artifacts
.build/
.swiftpm/
DerivedData/
*.xcodeproj/
```

- [ ] **Step 8: Commit**

```bash
git add project.yml .gitignore Packages/OmniRouteKit OmniChat/App/OmniChatApp.swift
git commit -m "chore: scaffold OmniChat project (XcodeGen + OmniRouteKit skeleton)"
```

---

### Task 2: `OmniRouteError` taxonomy + HTTP/URLError mapping

**Files:**
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteError.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteErrorMappingTests.swift`

**Interfaces:**
- Produces: `public enum OmniRouteError: Error, Equatable` with cases `.authenticationFailed`, `.rateLimited(retryAfterSeconds: Double?)`, `.network(description: String)`, `.invalidResponse(statusCode: Int)`, `.streamInterrupted`, `.unknown(description: String)`; static factories `OmniRouteError.from(httpStatusCode:retryAfterHeader:)` and `OmniRouteError.from(urlError:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class OmniRouteErrorMappingTests: XCTestCase {
    func test_401_mapsToAuthenticationFailed() {
        XCTAssertEqual(OmniRouteError.from(httpStatusCode: 401, retryAfterHeader: nil), .authenticationFailed)
    }

    func test_429_mapsToRateLimitedWithRetryAfter() {
        XCTAssertEqual(
            OmniRouteError.from(httpStatusCode: 429, retryAfterHeader: "12"),
            .rateLimited(retryAfterSeconds: 12)
        )
    }

    func test_500_mapsToInvalidResponse() {
        XCTAssertEqual(OmniRouteError.from(httpStatusCode: 500, retryAfterHeader: nil), .invalidResponse(statusCode: 500))
    }

    func test_urlError_mapsToNetwork() {
        let urlError = URLError(.timedOut)
        XCTAssertEqual(OmniRouteError.from(urlError: urlError), .network(description: urlError.localizedDescription))
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteErrorMappingTests`
Expected: FAIL — `OmniRouteError` does not exist.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum OmniRouteError: Error, Equatable {
    case authenticationFailed
    case rateLimited(retryAfterSeconds: Double?)
    case network(description: String)
    case invalidResponse(statusCode: Int)
    case streamInterrupted
    case unknown(description: String)
}

extension OmniRouteError {
    public static func from(httpStatusCode: Int, retryAfterHeader: String?) -> OmniRouteError {
        switch httpStatusCode {
        case 401, 403:
            return .authenticationFailed
        case 429:
            return .rateLimited(retryAfterSeconds: retryAfterHeader.flatMap(Double.init))
        default:
            return .invalidResponse(statusCode: httpStatusCode)
        }
    }

    public static func from(urlError: URLError) -> OmniRouteError {
        .network(description: urlError.localizedDescription)
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteErrorMappingTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteError.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteErrorMappingTests.swift
git commit -m "feat(kit): add OmniRouteError taxonomy and HTTP/URLError mapping"
```

---

### Task 3: `RetryPolicy` (backoff + retry decision)

**Files:**
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/RetryPolicy.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/RetryPolicyTests.swift`

**Interfaces:**
- Consumes: `OmniRouteError` (Task 2).
- Produces: `public struct RetryPolicy` with `init(maxAttempts:baseDelay:maxDelay:)` (defaults `4, 0.5, 8.0`), `func delay(forAttempt: Int, jitter: Double) -> Double`, `func shouldRetry(attempt: Int, error: OmniRouteError) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class RetryPolicyTests: XCTestCase {
    func test_delay_growsExponentiallyAndCaps() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0, maxDelay: 4.0)
        XCTAssertEqual(policy.delay(forAttempt: 1, jitter: 0), 1.0)
        XCTAssertEqual(policy.delay(forAttempt: 2, jitter: 0), 2.0)
        XCTAssertEqual(policy.delay(forAttempt: 3, jitter: 0), 4.0)
        XCTAssertEqual(policy.delay(forAttempt: 4, jitter: 0), 4.0, "must cap at maxDelay")
    }

    func test_shouldRetry_trueForTransientErrorsUnderMaxAttempts() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.1, maxDelay: 1.0)
        XCTAssertTrue(policy.shouldRetry(attempt: 1, error: .network(description: "timeout")))
        XCTAssertFalse(policy.shouldRetry(attempt: 3, error: .network(description: "timeout")), "must stop at maxAttempts")
    }

    func test_shouldRetry_falseForAuthenticationFailed() {
        let policy = RetryPolicy()
        XCTAssertFalse(policy.shouldRetry(attempt: 1, error: .authenticationFailed))
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd Packages/OmniRouteKit && swift test --filter RetryPolicyTests`
Expected: FAIL — `RetryPolicy` does not exist.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: Double
    public let maxDelay: Double

    public init(maxAttempts: Int = 4, baseDelay: Double = 0.5, maxDelay: Double = 8.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public func delay(forAttempt attempt: Int, jitter: Double) -> Double {
        let exponential = baseDelay * pow(2.0, Double(attempt - 1))
        return min(exponential, maxDelay) * (1.0 + jitter)
    }

    public func shouldRetry(attempt: Int, error: OmniRouteError) -> Bool {
        guard attempt < maxAttempts else { return false }
        switch error {
        case .rateLimited, .network, .invalidResponse:
            return true
        case .authenticationFailed, .streamInterrupted, .unknown:
            return false
        }
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter RetryPolicyTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/RetryPolicy.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/RetryPolicyTests.swift
git commit -m "feat(kit): add RetryPolicy with exponential backoff"
```

---

### Task 4: `EndpointProfile` + `CredentialStore`

**Files:**
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/EndpointProfile.swift`
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/CredentialStore.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/CredentialStoreTests.swift`

**Interfaces:**
- Produces: `public struct EndpointProfile: Sendable, Identifiable, Equatable` (`id: UUID`, `name: String`, `baseURL: URL`, static `.defaultLocal` = `http://localhost:20128/v1`); `public protocol CredentialStore: Sendable { func apiKey(for: UUID) throws -> String?; func setAPIKey(_:for:) throws }`; `public final class InMemoryCredentialStore: CredentialStore` (used by later kit tests).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class CredentialStoreTests: XCTestCase {
    func test_setThenGet_returnsStoredKey() throws {
        let store = InMemoryCredentialStore()
        let id = UUID()
        try store.setAPIKey("sk-test-123", for: id)
        XCTAssertEqual(try store.apiKey(for: id), "sk-test-123")
    }

    func test_get_beforeSet_returnsNil() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.apiKey(for: UUID()))
    }

    func test_defaultLocalProfile_pointsAtLocalhost20128() {
        XCTAssertEqual(EndpointProfile.defaultLocal.baseURL.absoluteString, "http://localhost:20128/v1")
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd Packages/OmniRouteKit && swift test --filter CredentialStoreTests`
Expected: FAIL — types do not exist.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct EndpointProfile: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var baseURL: URL

    public init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }

    public static let defaultLocal = EndpointProfile(
        name: "Local",
        baseURL: URL(string: "http://localhost:20128/v1")!
    )
}
```

```swift
import Foundation

public protocol CredentialStore: Sendable {
    func apiKey(for profileID: UUID) throws -> String?
    func setAPIKey(_ apiKey: String, for profileID: UUID) throws
}

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: String] = [:]

    public init() {}

    public func apiKey(for profileID: UUID) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[profileID]
    }

    public func setAPIKey(_ apiKey: String, for profileID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        storage[profileID] = apiKey
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter CredentialStoreTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/EndpointProfile.swift Packages/OmniRouteKit/Sources/OmniRouteKit/CredentialStore.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/CredentialStoreTests.swift
git commit -m "feat(kit): add EndpointProfile and CredentialStore protocol"
```

---

### Task 5: Chat models + SSE line parser

**Files:**
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/ChatModels.swift`
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/SSELineParser.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/SSELineParserTests.swift`

**Interfaces:**
- Produces: `public enum ChatRole: String, Codable, Sendable { case system, user, assistant }`; `public struct ChatMessage: Codable, Sendable, Equatable`; `public struct ChatCompletionRequest: Encodable, Sendable`; `public struct ChatDelta: Sendable, Equatable` (`content: String`, `isFinal: Bool`); `public enum SSELineParser { static func parse(line: String) -> ChatDelta? }`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class SSELineParserTests: XCTestCase {
    func test_dataLine_withContent_returnsDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"Bonjour"}}]}"#
        XCTAssertEqual(SSELineParser.parse(line: line), ChatDelta(content: "Bonjour", isFinal: false))
    }

    func test_doneLine_returnsFinalDelta() {
        XCTAssertEqual(SSELineParser.parse(line: "data: [DONE]"), ChatDelta(content: "", isFinal: true))
    }

    func test_nonDataLine_returnsNil() {
        XCTAssertNil(SSELineParser.parse(line: ": comment"))
    }

    func test_malformedJSON_returnsNil() {
        XCTAssertNil(SSELineParser.parse(line: "data: {not json"))
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd Packages/OmniRouteKit && swift test --filter SSELineParserTests`
Expected: FAIL — types do not exist.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant
}

public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: ChatRole
    public let content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatCompletionRequest: Encodable, Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var stream: Bool

    public init(model: String, messages: [ChatMessage], stream: Bool = true) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

public struct ChatDelta: Sendable, Equatable {
    public let content: String
    public let isFinal: Bool

    public init(content: String, isFinal: Bool) {
        self.content = content
        self.isFinal = isFinal
    }
}
```

```swift
import Foundation

struct ChatCompletionStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

public enum SSELineParser {
    public static func parse(line: String) -> ChatDelta? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return ChatDelta(content: "", isFinal: true)
        }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatCompletionStreamChunk.self, from: data),
              let content = chunk.choices.first?.delta.content else {
            return nil
        }
        return ChatDelta(content: content, isFinal: false)
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter SSELineParserTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/ChatModels.swift Packages/OmniRouteKit/Sources/OmniRouteKit/SSELineParser.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/SSELineParserTests.swift
git commit -m "feat(kit): add chat models and SSE line parser"
```

---

### Task 6: `OmniRouteClient.listModels()` with mocked networking

**Files:**
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/ModelInfo.swift`
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient.swift`
- Create: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/MockURLProtocol.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteClientModelsTests.swift`

**Interfaces:**
- Consumes: `EndpointProfile`, `CredentialStore`, `InMemoryCredentialStore` (Task 4), `OmniRouteError` (Task 2), `RetryPolicy` (Task 3).
- Produces: `public struct ModelInfo: Decodable, Sendable, Equatable` (`id: String`, `ownedBy: String?`); `public actor OmniRouteClient` with `init(profile:credentialStore:session:retryPolicy:)` and `func listModels() async throws -> [ModelInfo]`.

- [ ] **Step 1: Write the shared mock helper (no test yet, just infrastructure)**

```swift
import Foundation

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("MockURLProtocol.requestHandler not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class OmniRouteClientModelsTests: XCTestCase {
    func test_listModels_decodesResponseBody() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        try store.setAPIKey("sk-test", for: profile.id)
        let json = #"{"data":[{"id":"claude-sonnet-5","owned_by":"anthropic"}]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let models = try await client.listModels()
        XCTAssertEqual(models, [ModelInfo(id: "claude-sonnet-5", ownedBy: "anthropic")])
    }

    func test_listModels_401_throwsAuthenticationFailed() async throws {
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
            _ = try await client.listModels()
            XCTFail("expected authenticationFailed")
        } catch OmniRouteError.authenticationFailed {
            // expected
        }
    }
}
```

- [ ] **Step 3: Run and verify failure**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteClientModelsTests`
Expected: FAIL — `OmniRouteClient`/`ModelInfo` do not exist.

- [ ] **Step 4: Implement `ModelInfo`**

```swift
public struct ModelInfo: Decodable, Sendable, Equatable {
    public let id: String
    public let ownedBy: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
    }

    public init(id: String, ownedBy: String?) {
        self.id = id
        self.ownedBy = ownedBy
    }
}

struct ModelListResponse: Decodable {
    let data: [ModelInfo]
}
```

- [ ] **Step 5: Implement `OmniRouteClient`**

```swift
import Foundation

public actor OmniRouteClient {
    private nonisolated let profile: EndpointProfile
    private nonisolated let credentialStore: CredentialStore
    private nonisolated let session: URLSession
    private nonisolated let retryPolicy: RetryPolicy

    public init(
        profile: EndpointProfile,
        credentialStore: CredentialStore,
        session: URLSession = .shared,
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.profile = profile
        self.credentialStore = credentialStore
        self.session = session
        self.retryPolicy = retryPolicy
    }

    private nonisolated func authorizedRequest(path: String) throws -> URLRequest {
        var request = URLRequest(url: profile.baseURL.appendingPathComponent(path))
        if let apiKey = try credentialStore.apiKey(for: profile.id) {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func listModels() async throws -> [ModelInfo] {
        var attempt = 1
        while true {
            do {
                let request = try authorizedRequest(path: "models")
                let (data, response) = try await session.data(for: request)
                _ = try Self.requireSuccess(response)
                return try JSONDecoder().decode(ModelListResponse.self, from: data).data
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt, jitter: 0)))
                attempt += 1
            }
        }
    }

    static func requireSuccess(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw OmniRouteError.invalidResponse(statusCode: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OmniRouteError.from(
                httpStatusCode: http.statusCode,
                retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After")
            )
        }
        return http
    }

    static func mapNetworkingError(_ error: Error) -> OmniRouteError {
        if let omni = error as? OmniRouteError { return omni }
        if let urlError = error as? URLError { return .from(urlError: urlError) }
        return .unknown(description: "\(error)")
    }
}
```

- [ ] **Step 6: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteClientModelsTests`
Expected: PASS, 2 tests.

- [ ] **Step 7: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/ModelInfo.swift Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/MockURLProtocol.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteClientModelsTests.swift
git commit -m "feat(kit): add OmniRouteClient.listModels with retry"
```

---

### Task 7: `OmniRouteClient.streamChatCompletion()` (SSE streaming)

**Files:**
- Modify: `Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteClientChatStreamingTests.swift`

**Interfaces:**
- Consumes: `SSELineParser`, `ChatCompletionRequest`, `ChatDelta` (Task 5); `OmniRouteClient.requireSuccess`/`mapNetworkingError` (Task 6).
- Produces: `public protocol ChatCompleting: Sendable { func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> }`; `extension OmniRouteClient: ChatCompleting`; `OmniRouteClient.streamChatCompletion(_:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class OmniRouteClientChatStreamingTests: XCTestCase {
    func test_streamChatCompletion_yieldsDeltasInOrder() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let sseBody = """
        data: {"choices":[{"delta":{"content":"Bon"}}]}

        data: {"choices":[{"delta":{"content":"jour"}}]}

        data: [DONE]

        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sseBody.data(using: .utf8)!)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        var received: [String] = []
        let request = ChatCompletionRequest(model: "auto", messages: [ChatMessage(role: .user, content: "Salut")])
        for try await delta in client.streamChatCompletion(request) {
            received.append(delta.content)
        }
        XCTAssertEqual(received, ["Bon", "jour"])
    }

    func test_streamChatCompletion_missingDoneMarker_throwsStreamInterrupted() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let sseBody = #"data: {"choices":[{"delta":{"content":"Bon"}}]}"# + "\n\n"
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sseBody.data(using: .utf8)!)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let request = ChatCompletionRequest(model: "auto", messages: [ChatMessage(role: .user, content: "Salut")])
        do {
            for try await _ in client.streamChatCompletion(request) {}
            XCTFail("expected streamInterrupted")
        } catch OmniRouteError.streamInterrupted {
            // expected
        }
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteClientChatStreamingTests`
Expected: FAIL — `streamChatCompletion` does not exist.

- [ ] **Step 3: Implement (append to `OmniRouteClient.swift`)**

```swift
public protocol ChatCompleting: Sendable {
    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error>
}

extension OmniRouteClient: ChatCompleting {
    public nonisolated func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try authorizedRequest(path: "chat/completions")
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    _ = try Self.requireSuccess(response)

                    var receivedFinal = false
                    for try await line in bytes.lines {
                        guard let delta = SSELineParser.parse(line: line) else { continue }
                        if delta.isFinal {
                            receivedFinal = true
                            break
                        }
                        continuation.yield(delta)
                    }
                    guard receivedFinal else { throw OmniRouteError.streamInterrupted }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapNetworkingError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter OmniRouteClientChatStreamingTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Run the full kit test suite**

Run: `cd Packages/OmniRouteKit && swift test`
Expected: all tests pass (should be ~18 tests across all files so far).

- [ ] **Step 6: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/OmniRouteClient.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/OmniRouteClientChatStreamingTests.swift
git commit -m "feat(kit): add streaming chat completion over SSE"
```

---

### Task 8: `DiagnosticLogger` (local error journal + purge)

**Files:**
- Create: `Packages/OmniRouteKit/Sources/OmniRouteKit/DiagnosticLogger.swift`
- Test: `Packages/OmniRouteKit/Tests/OmniRouteKitTests/DiagnosticLoggerTests.swift`

**Interfaces:**
- Produces: `public struct DiagnosticLogEntry: Codable, Sendable, Equatable` (`timestamp: Date`, `category: String`, `endpointName: String`, `detail: String`); `public actor DiagnosticLogger` with `init(fileURL:retentionDays:)`, `func log(_:) throws`, `func purgeExpired(now:) throws`, `func readAll() throws -> [DiagnosticLogEntry]`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OmniRouteKit

final class DiagnosticLoggerTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    func test_log_thenReadAll_returnsEntry() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let logger = DiagnosticLogger(fileURL: url)
        let entry = DiagnosticLogEntry(timestamp: Date(), category: "network", endpointName: "Local", detail: "timeout")
        try await logger.log(entry)
        let all = try await logger.readAll()
        XCTAssertEqual(all, [entry])
    }

    func test_purgeExpired_removesOldEntries() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let logger = DiagnosticLogger(fileURL: url, retentionDays: 1)
        let old = DiagnosticLogEntry(timestamp: Date(timeIntervalSinceNow: -2 * 24 * 60 * 60), category: "network", endpointName: "Local", detail: "old")
        let recent = DiagnosticLogEntry(timestamp: Date(), category: "network", endpointName: "Local", detail: "recent")
        try await logger.log(old)
        try await logger.log(recent)
        try await logger.purgeExpired()
        let all = try await logger.readAll()
        XCTAssertEqual(all, [recent])
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd Packages/OmniRouteKit && swift test --filter DiagnosticLoggerTests`
Expected: FAIL — `DiagnosticLogger` does not exist.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct DiagnosticLogEntry: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let category: String
    public let endpointName: String
    public let detail: String

    public init(timestamp: Date, category: String, endpointName: String, detail: String) {
        self.timestamp = timestamp
        self.category = category
        self.endpointName = endpointName
        self.detail = detail
    }
}

public actor DiagnosticLogger {
    private let fileURL: URL
    private let retention: TimeInterval

    public init(fileURL: URL, retentionDays: Int = 30) {
        self.fileURL = fileURL
        self.retention = TimeInterval(retentionDays * 24 * 60 * 60)
    }

    public func log(_ entry: DiagnosticLogEntry) throws {
        var entries = try readAll()
        entries.append(entry)
        try write(entries)
    }

    public func purgeExpired(now: Date = Date()) throws {
        let kept = try readAll().filter { now.timeIntervalSince($0.timestamp) < retention }
        try write(kept)
    }

    public func readAll() throws -> [DiagnosticLogEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([DiagnosticLogEntry].self, from: data)
    }

    private func write(_ entries: [DiagnosticLogEntry]) throws {
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `cd Packages/OmniRouteKit && swift test --filter DiagnosticLoggerTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/OmniRouteKit/Sources/OmniRouteKit/DiagnosticLogger.swift Packages/OmniRouteKit/Tests/OmniRouteKitTests/DiagnosticLoggerTests.swift
git commit -m "feat(kit): add local diagnostic log with purge policy"
```

`OmniRouteKit` is now feature-complete for this phase. Remaining tasks build the `OmniChat` app target on top of it.

---

### Task 9: SwiftData persistence models

**Files:**
- Create: `OmniChat/Models/Conversation.swift`
- Create: `OmniChat/Models/Message.swift`
- Create: `OmniChat/Models/StoredEndpointProfile.swift`
- Test: `OmniChatTests/PersistenceModelsTests.swift`

**Interfaces:**
- Produces: `@Model final class Conversation` (`title: String`, `createdAt: Date`, `defaultModelID: String`, `messages: [Message]`); `@Model final class Message` (`role: String`, `content: String`, `isIncomplete: Bool`, `createdAt: Date`, `conversation: Conversation?`); `@Model final class StoredEndpointProfile` (`profileID: UUID`, `name: String`, `baseURLString: String`).

- [ ] **Step 1: Regenerate the Xcode project (no new files referenced by tests yet, skip)**

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
import SwiftData
@testable import OmniChat

final class PersistenceModelsTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Conversation.self, Message.self, StoredEndpointProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_savingConversationWithMessage_persistsRelationship() throws {
        let context = try makeInMemoryContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        let message = Message(role: "user", content: "Salut")
        message.conversation = conversation
        conversation.messages.append(message)
        context.insert(conversation)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.messages.count, 1)
        XCTAssertEqual(fetched.first?.messages.first?.content, "Salut")
    }
}
```

- [ ] **Step 3: Implement the models**

```swift
import Foundation
import SwiftData

@Model
final class Conversation {
    var title: String
    var createdAt: Date
    var defaultModelID: String
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(title: String, defaultModelID: String, createdAt: Date = Date()) {
        self.title = title
        self.defaultModelID = defaultModelID
        self.createdAt = createdAt
    }
}
```

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

    init(role: String, content: String, isIncomplete: Bool = false, createdAt: Date = Date()) {
        self.role = role
        self.content = content
        self.isIncomplete = isIncomplete
        self.createdAt = createdAt
    }
}
```

```swift
import Foundation
import SwiftData

@Model
final class StoredEndpointProfile {
    @Attribute(.unique) var profileID: UUID
    var name: String
    var baseURLString: String

    init(profileID: UUID, name: String, baseURLString: String) {
        self.profileID = profileID
        self.name = name
        self.baseURLString = baseURLString
    }
}
```

- [ ] **Step 4: Regenerate the project and run the test**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/PersistenceModelsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OmniChat/Models OmniChatTests/PersistenceModelsTests.swift
git commit -m "feat(app): add SwiftData persistence models"
```

---

### Task 10: `KeychainCredentialStore`

**Files:**
- Create: `OmniChat/Support/KeychainCredentialStore.swift`
- Test: `OmniChatTests/KeychainCredentialStoreTests.swift`

**Interfaces:**
- Consumes: `CredentialStore` protocol (`OmniRouteKit`, Task 4).
- Produces: `final class KeychainCredentialStore: CredentialStore` with `init(service: String)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import Security
@testable import OmniChat
import OmniRouteKit

final class KeychainCredentialStoreTests: XCTestCase {
    private var service: String!

    override func setUpWithError() throws {
        service = "online.omniroute.omnichat.tests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as Any
        ]
        SecItemDelete(query as CFDictionary)
    }

    func test_setThenGet_roundTripsThroughRealKeychain() throws {
        let store = KeychainCredentialStore(service: service)
        let profileID = UUID()
        try store.setAPIKey("sk-test-abc", for: profileID)
        XCTAssertEqual(try store.apiKey(for: profileID), "sk-test-abc")
    }

    func test_update_overwritesExistingKey() throws {
        let store = KeychainCredentialStore(service: service)
        let profileID = UUID()
        try store.setAPIKey("sk-first", for: profileID)
        try store.setAPIKey("sk-second", for: profileID)
        XCTAssertEqual(try store.apiKey(for: profileID), "sk-second")
    }

    func test_get_unknownProfile_returnsNil() throws {
        let store = KeychainCredentialStore(service: service)
        XCTAssertNil(try store.apiKey(for: UUID()))
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/KeychainCredentialStoreTests`
Expected: FAIL — `KeychainCredentialStore` does not exist.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Security
import OmniRouteKit

enum KeychainError: Error {
    case invalidData
    case osStatus(OSStatus)
}

final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String

    init(service: String = "online.omniroute.omnichat") {
        self.service = service
    }

    func apiKey(for profileID: UUID) throws -> String? {
        var query = baseQuery(for: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    func setAPIKey(_ apiKey: String, for profileID: UUID) throws {
        let data = Data(apiKey.utf8)
        let query = baseQuery(for: profileID)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.osStatus(updateStatus)
        }
    }

    private func baseQuery(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString
        ]
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/KeychainCredentialStoreTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add OmniChat/Support/KeychainCredentialStore.swift OmniChatTests/KeychainCredentialStoreTests.swift
git commit -m "feat(app): add Keychain-backed CredentialStore"
```

---

### Task 11: `ChatViewModel`

**Files:**
- Create: `OmniChat/ViewModels/ChatViewModel.swift`
- Test: `OmniChatTests/ChatViewModelTests.swift`

**Interfaces:**
- Consumes: `Conversation`, `Message` (Task 9); `ChatCompleting`, `ChatCompletionRequest`, `ChatMessage`, `ChatRole`, `ChatDelta`, `OmniRouteError` (Task 5/7).
- Produces: `@Observable @MainActor final class ChatViewModel` with `init(conversation:client:context:)`, `func send(_ text: String) async`, read-only `isStreaming: Bool`, `currentError: OmniRouteError?`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import SwiftData
@testable import OmniChat
import OmniRouteKit

private struct FakeChatCompleting: ChatCompleting {
    let deltas: [ChatDelta]
    let error: OmniRouteError?

    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}

@MainActor
final class ChatViewModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Conversation.self, Message.self, StoredEndpointProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_send_appendsUserAndAssembledAssistantMessage() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fake = FakeChatCompleting(
            deltas: [ChatDelta(content: "Bon", isFinal: false), ChatDelta(content: "jour", isFinal: false)],
            error: nil
        )
        let viewModel = ChatViewModel(conversation: conversation, client: fake, context: context)

        await viewModel.send("Salut")

        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.last?.content, "Bonjour")
        XCTAssertNil(viewModel.currentError)
    }

    func test_send_onError_marksAssistantMessageIncompleteAndExposesError() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fake = FakeChatCompleting(
            deltas: [ChatDelta(content: "Bon", isFinal: false)],
            error: .network(description: "timeout")
        )
        let viewModel = ChatViewModel(conversation: conversation, client: fake, context: context)

        await viewModel.send("Salut")

        XCTAssertEqual(viewModel.currentError, .network(description: "timeout"))
        XCTAssertEqual(conversation.messages.last?.isIncomplete, true)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/ChatViewModelTests`
Expected: FAIL — `ChatViewModel` does not exist.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Observation
import SwiftData
import OmniRouteKit

@Observable
@MainActor
final class ChatViewModel {
    let conversation: Conversation
    private(set) var isStreaming = false
    private(set) var currentError: OmniRouteError?

    private let client: ChatCompleting
    private let context: ModelContext

    init(conversation: Conversation, client: ChatCompleting, context: ModelContext) {
        self.conversation = conversation
        self.client = client
        self.context = context
    }

    func send(_ text: String) async {
        currentError = nil
        let userMessage = Message(role: "user", content: text)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)

        let assistantMessage = Message(role: "assistant", content: "")
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)

        isStreaming = true
        defer { isStreaming = false }

        let history = conversation.messages.dropLast().map {
            ChatMessage(role: ChatRole(rawValue: $0.role) ?? .user, content: $0.content)
        }
        let request = ChatCompletionRequest(model: conversation.defaultModelID, messages: Array(history))

        do {
            for try await delta in client.streamChatCompletion(request) {
                assistantMessage.content += delta.content
            }
        } catch let error as OmniRouteError {
            assistantMessage.isIncomplete = true
            currentError = error
        } catch {
            assistantMessage.isIncomplete = true
            currentError = .unknown(description: "\(error)")
        }
        try? context.save()
    }
}
```

- [ ] **Step 4: Run and verify pass**

Run: `xcodegen generate && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' -only-testing:OmniChatTests/ChatViewModelTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add OmniChat/ViewModels/ChatViewModel.swift OmniChatTests/ChatViewModelTests.swift
git commit -m "feat(app): add ChatViewModel wiring streaming into persistence"
```

---

### Task 12: SwiftUI shell (menu bar + main window) and README update

**Files:**
- Create: `OmniChat/Support/AppEnvironment.swift`
- Create: `OmniChat/Views/ContentView.swift`
- Create: `OmniChat/Views/ChatView.swift`
- Create: `OmniChat/Views/ErrorBannerView.swift`
- Create: `OmniChat/Views/SettingsView.swift`
- Create: `OmniChat/Views/MenuBarChatView.swift`
- Modify: `OmniChat/App/OmniChatApp.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `Conversation`, `Message` (Task 9); `KeychainCredentialStore` (Task 10); `ChatViewModel` (Task 11); `EndpointProfile`, `OmniRouteClient`, `OmniRouteError` (`OmniRouteKit`).

No new unit tests in this task — SwiftUI view bodies have no business logic to unit test (it already lives in `ChatViewModel`, covered by Task 11). Verification is a build check plus a manual smoke test, as is standard for UI wiring.

- [ ] **Step 1: `AppEnvironment` — shared active profile + credential store**

```swift
import Foundation
import OmniRouteKit

@Observable
final class AppEnvironment {
    var activeProfile: EndpointProfile
    let credentialStore: CredentialStore

    init(activeProfile: EndpointProfile = .defaultLocal, credentialStore: CredentialStore = KeychainCredentialStore()) {
        self.activeProfile = activeProfile
        self.credentialStore = credentialStore
    }
}
```

- [ ] **Step 2: `ErrorBannerView`**

```swift
import SwiftUI
import OmniRouteKit

struct ErrorBannerView: View {
    let error: OmniRouteError
    let retryAction: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message)
            Spacer()
            Button("Réessayer", action: retryAction)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var message: String {
        switch error {
        case .authenticationFailed:
            return "Clé API invalide ou expirée. Vérifie les réglages."
        case .rateLimited(let retryAfter):
            let suffix = retryAfter.map { " Réessaie dans \(Int($0))s." } ?? ""
            return "Limite de requêtes atteinte." + suffix
        case .network:
            return "Impossible de joindre OmniRoute. Vérifie ta connexion ou l'endpoint configuré."
        case .invalidResponse(let statusCode):
            return "Réponse inattendue d'OmniRoute (code \(statusCode))."
        case .streamInterrupted:
            return "La réponse a été interrompue avant la fin."
        case .unknown:
            return "Une erreur inattendue est survenue."
        }
    }
}
```

- [ ] **Step 3: `ChatView`**

```swift
import SwiftUI
import SwiftData
import OmniRouteKit

struct ChatView: View {
    let conversation: Conversation
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var draft = ""
    @State private var viewModel: ChatViewModel?

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel?.currentError {
                ErrorBannerView(error: error) {
                    let text = draft
                    Task { await viewModel?.send(text) }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(conversation.messages, id: \.persistentModelID) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            HStack {
                TextField("Écris un message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Envoyer") {
                    let text = draft
                    draft = ""
                    Task { await viewModel?.send(text) }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (viewModel?.isStreaming ?? false))
            }
            .padding()
        }
        .task(id: conversation.persistentModelID) {
            let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
            viewModel = ChatViewModel(conversation: conversation, client: client, context: context)
        }
        .navigationTitle(conversation.title)
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "assistant" { Spacer(minLength: 40) }
            Text(message.content.isEmpty ? "…" : message.content)
                .padding(10)
                .background(message.role == "user" ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if message.role == "user" { Spacer(minLength: 40) }
        }
    }
}
```

- [ ] **Step 4: `ContentView`**

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.createdAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?

    var body: some View {
        NavigationSplitView {
            List(conversations, selection: $selectedConversation) { conversation in
                Text(conversation.title).tag(conversation)
            }
            .toolbar {
                Button("Nouvelle conversation", systemImage: "plus", action: createConversation)
            }
        } detail: {
            if let selectedConversation {
                ChatView(conversation: selectedConversation)
            } else {
                ContentUnavailableView("Sélectionne ou crée une conversation", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .onAppear {
            if selectedConversation == nil {
                selectedConversation = conversations.first
            }
        }
    }

    private func createConversation() {
        let conversation = Conversation(title: "Nouvelle conversation", defaultModelID: "auto")
        context.insert(conversation)
        selectedConversation = conversation
    }
}
```

- [ ] **Step 5: `SettingsView`**

```swift
import SwiftUI
import OmniRouteKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var baseURLText = EndpointProfile.defaultLocal.baseURL.absoluteString
    @State private var apiKey = ""
    @State private var saveError: String?

    var body: some View {
        Form {
            TextField("URL OmniRoute", text: $baseURLText)
            SecureField("Clé API", text: $apiKey)
            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
            Button("Enregistrer", action: save)
        }
        .padding()
        .frame(width: 360)
    }

    private func save() {
        guard let url = URL(string: baseURLText) else {
            saveError = "URL invalide"
            return
        }
        let profile = EndpointProfile(name: "Défaut", baseURL: url)
        appEnvironment.activeProfile = profile
        do {
            try appEnvironment.credentialStore.setAPIKey(apiKey, for: profile.id)
            saveError = nil
        } catch {
            saveError = "Impossible d'enregistrer la clé: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 6: `MenuBarChatView`**

```swift
import SwiftUI
import AppKit

struct MenuBarChatView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OmniChat").font(.headline)
            Text("Ouvre la fenêtre principale pour discuter.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Ouvrir OmniChat") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where !window.title.isEmpty {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .padding()
        .frame(width: 220)
    }
}
```

- [ ] **Step 7: Wire the app entry point**

```swift
import SwiftUI
import SwiftData

@main
struct OmniChatApp: App {
    let modelContainer: ModelContainer
    @State private var appEnvironment = AppEnvironment()

    init() {
        do {
            modelContainer = try ModelContainer(for: Conversation.self, Message.self, StoredEndpointProfile.self)
        } catch {
            fatalError("Impossible d'initialiser SwiftData: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appEnvironment)
        }
        .modelContainer(modelContainer)

        MenuBarExtra("OmniChat", systemImage: "bubble.left.and.bubble.right") {
            MenuBarChatView()
                .environment(appEnvironment)
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .environment(appEnvironment)
        }
        .modelContainer(modelContainer)
    }
}
```

- [ ] **Step 8: Regenerate the project and build**

Run: `xcodegen generate && xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Run the full test suite (kit + app)**

Run: `cd Packages/OmniRouteKit && swift test && cd ../.. && xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS'`
Expected: all tests pass.

- [ ] **Step 10: Manual smoke test**

This step is manual because it requires a running OmniRoute instance (local or remote) — no stub server exists yet in this phase.

1. Open `OmniChat.xcodeproj` in Xcode and press Run.
2. Open Settings, set the OmniRoute URL (default `http://localhost:20128/v1` or your remote instance) and paste an API key.
3. In the main window, click "Nouvelle conversation" and send a message.
4. Verify either: the response streams in token by token, or — if no OmniRoute instance is reachable — the network error banner appears with a working "Réessayer" button.
5. Click the menu bar icon and confirm "Ouvrir OmniChat" brings the main window to front.

- [ ] **Step 11: Update the README to reflect what's actually implemented**

Replace the "Statut" callout and add a "Build & lancement" / "Configuration" content in `README.md`:

```markdown
> **Statut : socle + chat fonctionnels.** Chat multi-modèles en streaming,
> gestion d'erreurs (auth/rate limit/réseau/stream interrompu), persistance
> locale (SwiftData), clé API dans le Keychain, menu bar + fenêtre
> principale. Médias, RAG, MCP, A2A, OCR et traduction audio ne sont pas
> encore implémentés (voir le spec pour le périmètre complet).
```

```markdown
## Build & lancement

Prérequis : Xcode récent, [XcodeGen](https://github.com/yonaskolb/XcodeGen), macOS 26+.

\`\`\`bash
xcodegen generate
open OmniChat.xcodeproj
\`\`\`

Lancer les tests du socle réseau (rapide, sans Xcode) :

\`\`\`bash
cd Packages/OmniRouteKit && swift test
\`\`\`

Lancer tous les tests (kit + app) :

\`\`\`bash
xcodebuild test -project OmniChat.xcodeproj -scheme OmniChat -destination 'platform=macOS'
\`\`\`

## Configuration

Au premier lancement, ouvre les réglages de l'app (menu OmniChat > Réglages)
pour renseigner l'URL de ton instance OmniRoute (`http://localhost:20128/v1`
par défaut, ou une instance distante) et ta clé API. La clé est stockée dans
le Keychain macOS, jamais en clair.
```

- [ ] **Step 12: Commit**

```bash
git add OmniChat/Support/AppEnvironment.swift OmniChat/Views OmniChat/App/OmniChatApp.swift README.md
git commit -m "feat(app): wire menu bar + main window shell, update README"
```

---

## Self-Review Notes

- **Spec coverage (this phase):** connexion locale/distante configurable ✓ (Task 4/12), chat streaming ✓ (Task 5/7/11), menu bar + fenêtre principale ✓ (Task 12), Keychain pour la clé API ✓ (Task 10), persistance locale ✓ (Task 9), taxonomie d'erreurs + retry/backoff + UX de reprise ✓ (Task 2/3/12), journal de diagnostic local ✓ (Task 8), README toujours à jour ✓ (Task 12, et règle actée dans les contraintes globales pour les plans suivants).
- **Not covered here (by design — separate future plans):** génération d'images/vidéo/musique, recherche web, RAG (embeddings/rerank), modèles locaux, MCP, A2A, OCR, traduction audio, auto-combo, quotas. Each becomes its own plan once this one ships, per the spec's phasing note.
- **Type consistency checked:** `OmniRouteError` cases used identically across Tasks 2, 3, 6, 7, 11, 12. `ChatCompleting` (Task 7) is the exact type consumed by `ChatViewModel` (Task 11) and satisfied by `OmniRouteClient` and the tests' `FakeChatCompleting`. `EndpointProfile`/`CredentialStore` (Task 4) flow unchanged through `OmniRouteClient` (Task 6), `KeychainCredentialStore` (Task 10), and `AppEnvironment`/`SettingsView` (Task 12).
