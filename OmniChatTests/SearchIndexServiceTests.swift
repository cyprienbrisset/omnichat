import XCTest
@testable import OmniChat
import OmniRouteKit

private final class FakeEmbeddingGenerating: EmbeddingGenerating, @unchecked Sendable {
    var catalog: [ModelInfo] = [ModelInfo(id: "fake/embed", ownedBy: "fake")]
    var outcomesByModel: [String: Result<[Double], Error>] = [:]
    private(set) var attemptedModelIDs: [String] = []

    func listEmbeddingModels() async throws -> [ModelInfo] { catalog }

    func createEmbedding(model: String, input: String) async throws -> [Double] {
        attemptedModelIDs.append(model)
        switch outcomesByModel[model] ?? .success([0.1, 0.2]) {
        case .success(let vector): return vector
        case .failure(let error): throw error
        }
    }
}

final class SearchIndexServiceTests: XCTestCase {
    /// Confirmed live (the same pattern found in media generation): a
    /// server can list an embedding model whose provider isn't actually
    /// configured — resolution must try the next real candidate rather
    /// than trusting the first catalog entry.
    func test_resolveWorkingEmbeddingModel_firstCandidateNotFound_triesNext() async throws {
        let client = FakeEmbeddingGenerating()
        client.catalog = [
            ModelInfo(id: "broken/embed", ownedBy: "broken"),
            ModelInfo(id: "working/embed", ownedBy: "working"),
        ]
        client.outcomesByModel = [
            "broken/embed": .failure(OmniRouteError.invalidResponse(statusCode: 404)),
        ]

        let resolved = try await SearchIndexService.resolveWorkingEmbeddingModel(client: client)

        XCTAssertEqual(resolved, "working/embed")
        XCTAssertEqual(client.attemptedModelIDs, ["broken/embed", "working/embed"])
    }

    func test_resolveWorkingEmbeddingModel_authFailedCandidate_triesNext() async throws {
        let client = FakeEmbeddingGenerating()
        client.catalog = [
            ModelInfo(id: "key-limited/embed", ownedBy: "x"),
            ModelInfo(id: "working/embed", ownedBy: "x"),
        ]
        client.outcomesByModel = [
            "key-limited/embed": .failure(OmniRouteError.authenticationFailed),
        ]

        let resolved = try await SearchIndexService.resolveWorkingEmbeddingModel(client: client)

        XCTAssertEqual(resolved, "working/embed")
    }

    func test_resolveWorkingEmbeddingModel_nonRetryableError_surfacesImmediately() async throws {
        let client = FakeEmbeddingGenerating()
        client.catalog = [
            ModelInfo(id: "bad-input/embed", ownedBy: "x"),
            ModelInfo(id: "unreached/embed", ownedBy: "x"),
        ]
        client.outcomesByModel = [
            "bad-input/embed": .failure(OmniRouteError.invalidResponse(statusCode: 400)),
        ]

        do {
            _ = try await SearchIndexService.resolveWorkingEmbeddingModel(client: client)
            XCTFail("expected the 400 to surface immediately")
        } catch OmniRouteError.invalidResponse(let statusCode) {
            XCTAssertEqual(statusCode, 400)
        }
        XCTAssertEqual(client.attemptedModelIDs, ["bad-input/embed"])
    }

    func test_resolveWorkingEmbeddingModel_emptyCatalog_throwsClearError() async throws {
        let client = FakeEmbeddingGenerating()
        client.catalog = []

        do {
            _ = try await SearchIndexService.resolveWorkingEmbeddingModel(client: client)
            XCTFail("expected an error for an empty catalog")
        } catch OmniRouteError.unknown {
            // expected
        }
    }
}
