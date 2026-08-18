import Foundation

/// A stored memory entry from OmniRoute's management-gated `/api/memory`
/// store. Field names follow the API reference's POST body exactly
/// (camelCase, matching the Zod schema) since this management surface is a
/// different convention from the snake_case OpenAI-compatible `/v1/*` API.
public struct MemoryEntry: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let content: String
    public let key: String?
    public let type: String?
    public let sessionId: String?
    public let createdAt: Date?

    public init(id: String, content: String, key: String?, type: String?, sessionId: String?, createdAt: Date?) {
        self.id = id
        self.content = content
        self.key = key
        self.type = type
        self.sessionId = sessionId
        self.createdAt = createdAt
    }
}

enum MemoryResponseParsingError: Error {
    case unrecognizedShape
}

/// The exact list-response wrapper isn't shown in the API reference (only
/// the row shape, via the POST body's fields, is documented) — this tries
/// the shapes a Next.js API route commonly returns, in order, rather than
/// betting on one. If none match, the caller sees a clear parse error
/// instead of silently-wrong or crashing behavior.
func parseMemoryListResponse(_ data: Data) throws -> [MemoryEntry] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    if let direct = try? decoder.decode([MemoryEntry].self, from: data) {
        return direct
    }
    struct DataWrapper: Decodable { let data: [MemoryEntry] }
    if let wrapped = try? decoder.decode(DataWrapper.self, from: data) {
        return wrapped.data
    }
    struct MemoriesWrapper: Decodable { let memories: [MemoryEntry] }
    if let wrapped = try? decoder.decode(MemoriesWrapper.self, from: data) {
        return wrapped.memories
    }
    throw MemoryResponseParsingError.unrecognizedShape
}
