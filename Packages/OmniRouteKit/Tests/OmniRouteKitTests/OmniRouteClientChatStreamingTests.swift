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

    func test_streamChatCompletion_withDecisionHeader_yieldsTelemetryDeltaFirst() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let sseBody = """
        data: {"choices":[{"delta":{"content":"Bon"}}]}

        data: [DONE]

        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-OmniRoute-Decision": "strategy=cheapest; provider=cerebras; latency_ms=812"]
            )!
            return (response, sseBody.data(using: .utf8)!)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let request = ChatCompletionRequest(model: "auto", messages: [ChatMessage(role: .user, content: "Salut")])
        var deltas: [ChatDelta] = []
        for try await delta in client.streamChatCompletion(request) {
            deltas.append(delta)
        }
        XCTAssertEqual(deltas.first?.telemetry?.routingProvider, "cerebras")
        XCTAssertEqual(deltas.first?.content, "")
        XCTAssertEqual(deltas.last?.content, "Bon")
        XCTAssertNil(deltas.last?.telemetry)
    }

    func test_streamChatCompletion_noRecognizedHeaders_yieldsNoTelemetryDelta() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let sseBody = """
        data: {"choices":[{"delta":{"content":"Bon"}}]}

        data: [DONE]

        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sseBody.data(using: .utf8)!)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let request = ChatCompletionRequest(model: "auto", messages: [ChatMessage(role: .user, content: "Salut")])
        var deltas: [ChatDelta] = []
        for try await delta in client.streamChatCompletion(request) {
            deltas.append(delta)
        }
        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas.first?.content, "Bon")
        XCTAssertNil(deltas.first?.telemetry)
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
