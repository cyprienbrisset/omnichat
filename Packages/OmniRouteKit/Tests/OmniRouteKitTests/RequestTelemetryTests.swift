import XCTest
@testable import OmniRouteKit

final class RequestTelemetryTests: XCTestCase {
    private func makeResponse(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    func test_parse_noRecognizedHeaders_returnsNil() {
        let response = makeResponse(headers: ["Content-Type": "text/event-stream"])
        XCTAssertNil(RequestTelemetry.parse(from: response))
    }

    func test_parse_decisionHeaderOnly_parsesStrategyProviderLatency() throws {
        let response = makeResponse(headers: [
            "X-OmniRoute-Decision": "strategy=cheapest; provider=cerebras; latency_ms=812"
        ])
        let telemetry = try XCTUnwrap(RequestTelemetry.parse(from: response))
        XCTAssertEqual(telemetry.routingStrategy, "cheapest")
        XCTAssertEqual(telemetry.routingProvider, "cerebras")
        XCTAssertEqual(telemetry.routingLatencyMs, 812)
        XCTAssertNil(telemetry.responseCostUSD)
        XCTAssertNil(telemetry.tokensIn)
    }

    func test_parse_fullCostTelemetrySet_parsesAllFields() throws {
        let response = makeResponse(headers: [
            "X-OmniRoute-Decision": "strategy=single; provider=openai; latency_ms=1204",
            "X-OmniRoute-Request-Id": "req_abc123",
            "X-OmniRoute-Response-Cost": "0.0012000000",
            "X-OmniRoute-Tokens-In": "128",
            "X-OmniRoute-Tokens-Out": "342",
            "X-OmniRoute-Cache-Hit": "true",
            "X-OmniRoute-Fallback-Attempts": "2"
        ])
        let telemetry = try XCTUnwrap(RequestTelemetry.parse(from: response))
        XCTAssertEqual(telemetry.routingStrategy, "single")
        XCTAssertEqual(telemetry.requestId, "req_abc123")
        XCTAssertEqual(telemetry.responseCostUSD, 0.0012)
        XCTAssertEqual(telemetry.tokensIn, 128)
        XCTAssertEqual(telemetry.tokensOut, 342)
        XCTAssertEqual(telemetry.cacheHit, true)
        XCTAssertEqual(telemetry.fallbackAttempts, 2)
    }

    func test_parse_malformedDecisionHeader_ignoresUnparseableParts() throws {
        let response = makeResponse(headers: ["X-OmniRoute-Decision": "garbage-no-equals"])
        XCTAssertNil(RequestTelemetry.parse(from: response))
    }
}
