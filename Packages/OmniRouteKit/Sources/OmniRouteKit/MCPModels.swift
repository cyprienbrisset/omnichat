import Foundation

/// A single OmniRoute-embedded MCP tool, from `/api/mcp/tools`. Field names
/// are the ones the API reference documents explicitly for this route.
public struct MCPTool: Decodable, Sendable, Equatable, Identifiable {
    public let name: String
    public let description: String?
    public let scopes: [String]?
    public let phase: String?
    public let auditLevel: String?
    public let sourceEndpoints: [String]?

    public var id: String { name }

    public init(
        name: String,
        description: String?,
        scopes: [String]?,
        phase: String?,
        auditLevel: String?,
        sourceEndpoints: [String]?
    ) {
        self.name = name
        self.description = description
        self.scopes = scopes
        self.phase = phase
        self.auditLevel = auditLevel
        self.sourceEndpoints = sourceEndpoints
    }
}

enum MCPResponseParsingError: Error {
    case unrecognizedShape
}

/// Same reasoning as `parseMemoryListResponse`: the list wrapper isn't shown
/// in the API reference, only the row shape is — so this tries the shapes a
/// Next.js API route commonly returns rather than betting on one.
func parseMCPToolListResponse(_ data: Data) throws -> [MCPTool] {
    let decoder = JSONDecoder()
    if let direct = try? decoder.decode([MCPTool].self, from: data) {
        return direct
    }
    struct DataWrapper: Decodable { let data: [MCPTool] }
    if let wrapped = try? decoder.decode(DataWrapper.self, from: data) {
        return wrapped.data
    }
    struct ToolsWrapper: Decodable { let tools: [MCPTool] }
    if let wrapped = try? decoder.decode(ToolsWrapper.self, from: data) {
        return wrapped.tools
    }
    struct ResultWrapper: Decodable { let result: [MCPTool] }
    if let wrapped = try? decoder.decode(ResultWrapper.self, from: data) {
        return wrapped.result
    }
    struct ItemsWrapper: Decodable { let items: [MCPTool] }
    if let wrapped = try? decoder.decode(ItemsWrapper.self, from: data) {
        return wrapped.items
    }
    // Last resort: none of the known wrapper keys matched — rather than
    // fail outright on a wrapper name this app hasn't seen, look for *any*
    // top-level array and try to decode its elements as tools, skipping
    // ones that don't fit. Still throws if genuinely nothing usable is found.
    if let top = try? decoder.decode(JSONValue.self, from: data), let array = firstArray(in: top) {
        let decoded = array.compactMap { item -> MCPTool? in
            guard let itemData = try? JSONSerialization.data(withJSONObject: item.foundationObject) else { return nil }
            return try? decoder.decode(MCPTool.self, from: itemData)
        }
        if !decoded.isEmpty { return decoded }
    }
    throw MCPResponseParsingError.unrecognizedShape
}

/// Finds the first JSON array anywhere at the top level of a value — either
/// the value itself, or the first array-valued field of an object (checked
/// in a stable, sorted key order).
private func firstArray(in value: JSONValue) -> [JSONValue]? {
    switch value {
    case .array(let values):
        return values
    case .object(let fields):
        for key in fields.keys.sorted() {
            if case .array(let values) = fields[key]! { return values }
        }
        return nil
    default:
        return nil
    }
}

/// A JSON value with no assumed shape — used where the API reference only
/// describes a response in prose ("heartbeat, transport, online state, last
/// call, top tools, 24h success rate") without naming the actual JSON keys.
/// Guessing key names here would risk silently mislabeling real data;
/// decoding into this instead surfaces exactly what the server sent.
public indirect enum JSONValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    /// Bridges to a plain Foundation object tree so a value decoded once as
    /// `JSONValue` can be re-serialized and decoded again as a concrete
    /// type — used only as a last-resort fallback when no known wrapper
    /// key matches a list response, to avoid hard-failing on a wrapper
    /// shape this app hasn't seen yet.
    var foundationObject: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let values): return values.map(\.foundationObject)
        case .object(let fields): return fields.mapValues { $0.foundationObject }
        }
    }

    /// A short, single-line rendering for display in a raw key/value list.
    public var displayValue: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "—"
        case .array(let values): return "[" + values.map(\.displayValue).joined(separator: ", ") + "]"
        case .object(let fields): return "{" + fields.keys.sorted().joined(separator: ", ") + "}"
        }
    }
}

/// A flattened, undecoded snapshot of a JSON object response — see
/// `JSONValue` for why this exists instead of a typed struct.
public struct MCPRawSnapshot: Sendable, Equatable {
    public let fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) {
        self.fields = fields
    }

    public var sortedEntries: [(key: String, value: String)] {
        fields.keys.sorted().map { ($0, fields[$0]!.displayValue) }
    }
}

func parseMCPRawSnapshot(_ data: Data) throws -> MCPRawSnapshot {
    guard case .object(let fields) = try JSONDecoder().decode(JSONValue.self, from: data) else {
        throw MCPResponseParsingError.unrecognizedShape
    }
    return MCPRawSnapshot(fields: fields)
}

/// `/api/mcp/audit` entries — like the status/audit-stats snapshot, no
/// per-row field shape is documented, so this decodes each row as a raw
/// object rather than guessing column names, and tries the same set of
/// plausible list wrappers as `parseMCPToolListResponse`.
func parseMCPAuditListResponse(_ data: Data) throws -> [MCPRawSnapshot] {
    func objects(from values: [JSONValue]) throws -> [MCPRawSnapshot] {
        try values.map { value in
            guard case .object(let fields) = value else { throw MCPResponseParsingError.unrecognizedShape }
            return MCPRawSnapshot(fields: fields)
        }
    }
    let decoder = JSONDecoder()
    if let direct = try? decoder.decode([JSONValue].self, from: data) {
        return try objects(from: direct)
    }
    struct DataWrapper: Decodable { let data: [JSONValue] }
    if let wrapped = try? decoder.decode(DataWrapper.self, from: data) {
        return try objects(from: wrapped.data)
    }
    struct EntriesWrapper: Decodable { let entries: [JSONValue] }
    if let wrapped = try? decoder.decode(EntriesWrapper.self, from: data) {
        return try objects(from: wrapped.entries)
    }
    struct LogsWrapper: Decodable { let logs: [JSONValue] }
    if let wrapped = try? decoder.decode(LogsWrapper.self, from: data) {
        return try objects(from: wrapped.logs)
    }
    // Same last-resort fallback as `parseMCPToolListResponse`.
    if let top = try? decoder.decode(JSONValue.self, from: data), let array = firstArray(in: top),
       let objs = try? objects(from: array), !objs.isEmpty {
        return objs
    }
    throw MCPResponseParsingError.unrecognizedShape
}
