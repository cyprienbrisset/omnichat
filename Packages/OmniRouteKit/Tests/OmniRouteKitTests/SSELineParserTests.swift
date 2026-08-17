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
