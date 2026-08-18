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

    /// Fixtures below are verbatim chunks captured from a live OmniRoute
    /// 3.8.49 instance streaming a real tool call, not a guessed shape.
    func test_toolCallFirstChunk_capturesIdAndName() {
        let line = #"data: {"choices":[{"index":0,"finish_reason":null,"delta":{"tool_calls":[{"index":0,"id":"call_512ab9f11c4b40d2ade78ea2","type":"function","function":{"name":"calculator","arguments":""}}]}}]}"#
        let delta = SSELineParser.parse(line: line)
        XCTAssertEqual(delta?.toolCallDeltas, [ToolCallDelta(index: 0, id: "call_512ab9f11c4b40d2ade78ea2", name: "calculator", argumentsFragment: "")])
    }

    func test_toolCallArgumentFragment_capturesFragmentOnly() {
        let line = #"data: {"choices":[{"index":0,"finish_reason":null,"delta":{"tool_calls":[{"index":0,"id":null,"type":"function","function":{"name":null,"arguments":"{\"expression\": "}}]}}]}"#
        let delta = SSELineParser.parse(line: line)
        XCTAssertEqual(delta?.toolCallDeltas, [ToolCallDelta(index: 0, id: nil, name: nil, argumentsFragment: "{\"expression\": ")])
    }

    func test_toolCallFinish_setsFinishReason() {
        let line = #"data: {"choices":[{"delta":{"role":null,"content":null,"tool_calls":null},"finish_reason":"tool_calls"}]}"#
        let delta = SSELineParser.parse(line: line)
        XCTAssertEqual(delta?.finishReason, "tool_calls")
        XCTAssertEqual(delta?.toolCallDeltas, [])
    }

    func test_emptyChoicesUsageOnlyChunk_returnsNil() {
        let line = #"data: {"choices":[],"usage":{"prompt_tokens":1}}"#
        XCTAssertNil(SSELineParser.parse(line: line))
    }
}
