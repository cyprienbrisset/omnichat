import XCTest
@testable import OmniRouteKit

final class MCPModelsTests: XCTestCase {
    func test_parseMCPToolListResponse_parsesBareArray() throws {
        let json = #"""
        [{"name":"web_search","description":"Search the web","scopes":["mcp"],"phase":"stable","auditLevel":"full","sourceEndpoints":["/v1/chat/completions"]}]
        """#
        let tools = try parseMCPToolListResponse(Data(json.utf8))
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].name, "web_search")
        XCTAssertEqual(tools[0].scopes, ["mcp"])
    }

    func test_parseMCPToolListResponse_parsesDataWrapper() throws {
        let json = #"{"data":[{"name":"t1","description":null,"scopes":null,"phase":null,"auditLevel":null,"sourceEndpoints":null}]}"#
        let tools = try parseMCPToolListResponse(Data(json.utf8))
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].name, "t1")
    }

    func test_parseMCPToolListResponse_parsesResultWrapper() throws {
        let json = #"{"result":[{"name":"t2"}]}"#
        let tools = try parseMCPToolListResponse(Data(json.utf8))
        XCTAssertEqual(tools.map(\.name), ["t2"])
    }

    func test_parseMCPToolListResponse_parsesItemsWrapper() throws {
        let json = #"{"items":[{"name":"t3"}]}"#
        let tools = try parseMCPToolListResponse(Data(json.utf8))
        XCTAssertEqual(tools.map(\.name), ["t3"])
    }

    /// A wrapper key this app has never seen (e.g. a hypothetical
    /// `"toolsList"`) shouldn't hard-fail — the fallback finds the array
    /// regardless of what it's keyed under.
    func test_parseMCPToolListResponse_unknownWrapperKey_fallsBackToAnyArray() throws {
        let json = #"{"toolsList":[{"name":"t4"}],"meta":{"count":1}}"#
        let tools = try parseMCPToolListResponse(Data(json.utf8))
        XCTAssertEqual(tools.map(\.name), ["t4"])
    }

    func test_parseMCPToolListResponse_unrecognizedShape_throws() {
        XCTAssertThrowsError(try parseMCPToolListResponse(Data(#"{"nope":true}"#.utf8)))
    }

    func test_parseMCPRawSnapshot_flattensMixedTypes() throws {
        let json = #"{"online":true,"transport":"sse","successRate24h":0.97,"topTools":["a","b"],"lastCall":null}"#
        let snapshot = try parseMCPRawSnapshot(Data(json.utf8))
        XCTAssertEqual(snapshot.fields["online"], .bool(true))
        XCTAssertEqual(snapshot.fields["transport"], .string("sse"))
        XCTAssertEqual(snapshot.fields["lastCall"], .null)
        XCTAssertEqual(snapshot.fields["topTools"]?.displayValue, "[a, b]")
    }

    func test_parseMCPRawSnapshot_nonObjectTopLevel_throws() {
        XCTAssertThrowsError(try parseMCPRawSnapshot(Data("[1,2,3]".utf8)))
    }

    func test_jsonValue_displayValue_nestedObject_rendersRealKeyValuePairsNotJustKeys() {
        let value = JSONValue.object(["plan": .string("pro"), "tier": .number(2)])
        XCTAssertEqual(value.displayValue, "{plan: pro, tier: 2}")
    }

    func test_parseMCPAuditListResponse_parsesBareArrayOfRawObjects() throws {
        let json = #"[{"tool":"web_search","success":true,"durationMs":84}]"#
        let entries = try parseMCPAuditListResponse(Data(json.utf8))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["tool"], .string("web_search"))
        XCTAssertEqual(entries[0].fields["success"], .bool(true))
    }

    func test_parseMCPAuditListResponse_parsesDataWrapper() throws {
        let json = #"{"data":[{"tool":"quota_status"}]}"#
        let entries = try parseMCPAuditListResponse(Data(json.utf8))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["tool"], .string("quota_status"))
    }

    func test_parseMCPAuditListResponse_unknownWrapperKey_fallsBackToAnyArray() throws {
        let json = #"{"auditLog":[{"tool":"web_search"}]}"#
        let entries = try parseMCPAuditListResponse(Data(json.utf8))
        XCTAssertEqual(entries.map { $0.fields["tool"] }, [.string("web_search")])
    }

    func test_parseMCPAuditListResponse_unrecognizedShape_throws() {
        XCTAssertThrowsError(try parseMCPAuditListResponse(Data(#"{"nope":true}"#.utf8)))
    }
}
