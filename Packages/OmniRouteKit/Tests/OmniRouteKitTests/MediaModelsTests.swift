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
