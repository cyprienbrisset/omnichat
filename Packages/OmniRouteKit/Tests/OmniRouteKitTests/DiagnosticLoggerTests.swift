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
