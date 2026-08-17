import Foundation

public struct DiagnosticLogEntry: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let category: String
    public let endpointName: String
    public let detail: String

    public init(timestamp: Date, category: String, endpointName: String, detail: String) {
        self.timestamp = timestamp
        self.category = category
        self.endpointName = endpointName
        self.detail = detail
    }
}

public actor DiagnosticLogger {
    private let fileURL: URL
    private let retention: TimeInterval

    public init(fileURL: URL, retentionDays: Int = 30) {
        self.fileURL = fileURL
        self.retention = TimeInterval(retentionDays * 24 * 60 * 60)
    }

    public func log(_ entry: DiagnosticLogEntry) throws {
        var entries = try readAll()
        entries.append(entry)
        try write(entries)
    }

    public func purgeExpired(now: Date = Date()) throws {
        let kept = try readAll().filter { now.timeIntervalSince($0.timestamp) < retention }
        try write(kept)
    }

    public func readAll() throws -> [DiagnosticLogEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([DiagnosticLogEntry].self, from: data)
    }

    private func write(_ entries: [DiagnosticLogEntry]) throws {
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
