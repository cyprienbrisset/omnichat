import XCTest
@testable import OmniRouteKit

final class MemoryModelsTests: XCTestCase {
    func test_parseMemoryListResponse_bareArray_decodes() throws {
        let json = #"""
        [{"id":"m1","content":"Le trousseau ne synchronise jamais via iCloud","key":"keychain-note","type":"FACTUAL","sessionId":null,"createdAt":"2026-08-18T10:00:00Z"}]
        """#.data(using: .utf8)!

        let entries = try parseMemoryListResponse(json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "m1")
        XCTAssertEqual(entries[0].type, "FACTUAL")
    }

    func test_parseMemoryListResponse_dataWrapper_decodes() throws {
        let json = #"""
        {"data":[{"id":"m2","content":"x","key":null,"type":null,"sessionId":null,"createdAt":null}]}
        """#.data(using: .utf8)!

        let entries = try parseMemoryListResponse(json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "m2")
    }

    func test_parseMemoryListResponse_memoriesWrapper_decodes() throws {
        let json = #"""
        {"memories":[{"id":"m3","content":"y","key":null,"type":null,"sessionId":null,"createdAt":null}]}
        """#.data(using: .utf8)!

        let entries = try parseMemoryListResponse(json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "m3")
    }

    func test_parseMemoryListResponse_unrecognizedShape_throws() {
        let json = #"{"unexpected":"shape"}"#.data(using: .utf8)!

        XCTAssertThrowsError(try parseMemoryListResponse(json))
    }
}
