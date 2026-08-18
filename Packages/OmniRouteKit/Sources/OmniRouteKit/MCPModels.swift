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
    throw MCPResponseParsingError.unrecognizedShape
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
