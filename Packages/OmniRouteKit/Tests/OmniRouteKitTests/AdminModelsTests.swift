import XCTest
@testable import OmniRouteKit

final class AdminModelsTests: XCTestCase {
    func test_parseAdminRawSnapshotList_parsesBareArray() throws {
        let json = #"[{"id":"p1","name":"OpenAI","status":"active"}]"#
        let providers = try parseAdminRawSnapshotList(Data(json.utf8))
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers[0].id, "p1")
        XCTAssertEqual(providers[0].fields["name"], .string("OpenAI"))
    }

    func test_parseAdminRawSnapshotList_parsesProvidersWrapper() throws {
        let json = #"{"providers":[{"id":"p2","name":"Fireworks"}]}"#
        let providers = try parseAdminRawSnapshotList(Data(json.utf8))
        XCTAssertEqual(providers.map(\.id), ["p2"])
    }

    func test_parseAdminRawSnapshotList_unknownWrapperKey_fallsBackToAnyArray() throws {
        let json = #"{"providerList":[{"id":"p3"}],"meta":{"count":1}}"#
        let providers = try parseAdminRawSnapshotList(Data(json.utf8))
        XCTAssertEqual(providers.map(\.id), ["p3"])
    }

    func test_adminRawSnapshot_id_fallsBackThroughKnownKeyNames() {
        let snapshot = AdminRawSnapshot(fields: ["providerId": .string("abc")])
        XCTAssertEqual(snapshot.id, "abc")
    }

    func test_parseBudgetListResponse_parsesBareArray() throws {
        let json = #"[{"apiKeyId":"key-1","dailyLimitUsd":5.0,"weeklyLimitUsd":null,"monthlyLimitUsd":100.0,"warningThreshold":0.8,"resetInterval":"monthly"}]"#
        let budgets = try parseBudgetListResponse(Data(json.utf8))
        XCTAssertEqual(budgets.count, 1)
        XCTAssertEqual(budgets[0].apiKeyId, "key-1")
        XCTAssertEqual(budgets[0].dailyLimitUsd, 5.0)
        XCTAssertNil(budgets[0].weeklyLimitUsd)
    }

    func test_parseTokenLimitListResponse_parsesDocumentedFields() throws {
        let json = #"""
        [{"id":"tl-1","apiKeyId":"key-1","scopeType":"model","scopeValue":"openai/gpt-4o","tokenLimit":1000000,"resetInterval":"monthly","enabled":true,"tokensUsed":42,"remaining":999958,"nextResetAt":"2026-09-01T00:00:00Z"}]
        """#
        let limits = try parseTokenLimitListResponse(Data(json.utf8))
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].id, "tl-1")
        XCTAssertEqual(limits[0].scopeType, "model")
        XCTAssertEqual(limits[0].tokenLimit, 1_000_000)
        XCTAssertEqual(limits[0].tokensUsed, 42)
    }

    func test_setBudgetRequest_encodesDocumentedSchema() throws {
        let request = SetBudgetRequest(apiKeyId: "key-1", dailyLimitUsd: 5.0, resetInterval: "daily")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["apiKeyId"] as? String, "key-1")
        XCTAssertEqual(json?["dailyLimitUsd"] as? Double, 5.0)
        XCTAssertEqual(json?["resetInterval"] as? String, "daily")
        XCTAssertNil(json?["weeklyLimitUsd"])
    }
}
