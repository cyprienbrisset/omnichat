import Foundation

/// A flattened, undecoded JSON object — used for management-API resources
/// whose row shape isn't documented (Providers), same reasoning as MCP's
/// `MCPRawSnapshot`: guessing field names risks silently mislabeling real
/// data, so this surfaces exactly what the server sent instead.
public struct AdminRawSnapshot: Sendable, Equatable, Identifiable {
    public let fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) {
        self.fields = fields
    }

    /// Best-effort id for actions (test/delete) that need one — checks the
    /// common key names in order rather than assuming one specific name.
    public var id: String {
        for key in ["id", "providerId", "_id", "slug"] {
            if case .string(let value)? = fields[key] { return value }
        }
        return fields["name"].map(\.displayValue) ?? UUID().uuidString
    }

    public var sortedEntries: [(key: String, value: String)] {
        fields.keys.sorted().map { ($0, fields[$0]!.displayValue) }
    }
}

enum AdminResponseParsingError: Error {
    case unrecognizedShape
}

func parseAdminRawSnapshot(_ data: Data) throws -> AdminRawSnapshot {
    guard case .object(let fields) = try JSONDecoder().decode(JSONValue.self, from: data) else {
        throw AdminResponseParsingError.unrecognizedShape
    }
    return AdminRawSnapshot(fields: fields)
}

/// Same defensive multi-shape + generic-array-fallback parsing as
/// `parseMCPAuditListResponse` — the list wrapper for management-API
/// resources like `/api/providers` isn't documented.
func parseAdminRawSnapshotList(_ data: Data) throws -> [AdminRawSnapshot] {
    func objects(from values: [JSONValue]) throws -> [AdminRawSnapshot] {
        try values.map { value in
            guard case .object(let fields) = value else { throw AdminResponseParsingError.unrecognizedShape }
            return AdminRawSnapshot(fields: fields)
        }
    }
    let decoder = JSONDecoder()
    if let direct = try? decoder.decode([JSONValue].self, from: data) {
        return try objects(from: direct)
    }
    for key in ["data", "providers", "result", "items"] {
        if let top = try? decoder.decode(JSONValue.self, from: data), case .object(let fields) = top,
           case .array(let values)? = fields[key] {
            return try objects(from: values)
        }
    }
    if let top = try? decoder.decode(JSONValue.self, from: data) {
        switch top {
        case .object(let fields):
            for candidateKey in fields.keys.sorted() {
                if case .array(let values) = fields[candidateKey]!, let objs = try? objects(from: values), !objs.isEmpty {
                    return objs
                }
            }
        default:
            break
        }
    }
    throw AdminResponseParsingError.unrecognizedShape
}

/// `POST /api/usage/budget` body — schema fully documented
/// (`setBudgetSchema`): `apiKeyId` required, at least one limit field
/// required, `warningThreshold` 0–1, `resetInterval` one of the three
/// listed values.
public struct SetBudgetRequest: Encodable, Sendable {
    public let apiKeyId: String
    public let dailyLimitUsd: Double?
    public let weeklyLimitUsd: Double?
    public let monthlyLimitUsd: Double?
    public let warningThreshold: Double?
    public let resetInterval: String?

    public init(
        apiKeyId: String,
        dailyLimitUsd: Double? = nil,
        weeklyLimitUsd: Double? = nil,
        monthlyLimitUsd: Double? = nil,
        warningThreshold: Double? = nil,
        resetInterval: String? = nil
    ) {
        self.apiKeyId = apiKeyId
        self.dailyLimitUsd = dailyLimitUsd
        self.weeklyLimitUsd = weeklyLimitUsd
        self.monthlyLimitUsd = monthlyLimitUsd
        self.warningThreshold = warningThreshold
        self.resetInterval = resetInterval
    }
}

/// A budget entry as returned by `GET /api/usage/budget` — the response
/// shape itself isn't documented, but it almost certainly mirrors the
/// documented `POST` schema (same fields the server just validated and
/// stored), so this decodes those fields directly rather than falling back
/// to a fully raw snapshot; all fields but `apiKeyId` stay optional to
/// tolerate whatever this server's real shape turns out to be.
public struct BudgetEntry: Codable, Sendable, Equatable, Identifiable {
    public let apiKeyId: String
    public let dailyLimitUsd: Double?
    public let weeklyLimitUsd: Double?
    public let monthlyLimitUsd: Double?
    public let warningThreshold: Double?
    public let resetInterval: String?

    public var id: String { apiKeyId }

    public init(
        apiKeyId: String,
        dailyLimitUsd: Double?,
        weeklyLimitUsd: Double?,
        monthlyLimitUsd: Double?,
        warningThreshold: Double?,
        resetInterval: String?
    ) {
        self.apiKeyId = apiKeyId
        self.dailyLimitUsd = dailyLimitUsd
        self.weeklyLimitUsd = weeklyLimitUsd
        self.monthlyLimitUsd = monthlyLimitUsd
        self.warningThreshold = warningThreshold
        self.resetInterval = resetInterval
    }
}

func parseBudgetListResponse(_ data: Data) throws -> [BudgetEntry] {
    let decoder = JSONDecoder()
    if let direct = try? decoder.decode([BudgetEntry].self, from: data) {
        return direct
    }
    struct DataWrapper: Decodable { let data: [BudgetEntry] }
    if let wrapped = try? decoder.decode(DataWrapper.self, from: data) {
        return wrapped.data
    }
    struct BudgetsWrapper: Decodable { let budgets: [BudgetEntry] }
    if let wrapped = try? decoder.decode(BudgetsWrapper.self, from: data) {
        return wrapped.budgets
    }
    throw AdminResponseParsingError.unrecognizedShape
}

/// `POST /api/usage/token-limits` body — schema fully documented
/// (`setTokenLimitSchema`).
public struct SetTokenLimitRequest: Encodable, Sendable {
    public let id: String?
    public let apiKeyId: String
    public let scopeType: String
    public let scopeValue: String?
    public let tokenLimit: Int
    public let resetInterval: String?
    public let resetTime: String?
    public let enabled: Bool?

    public init(
        id: String? = nil,
        apiKeyId: String,
        scopeType: String,
        scopeValue: String?,
        tokenLimit: Int,
        resetInterval: String? = nil,
        resetTime: String? = nil,
        enabled: Bool? = nil
    ) {
        self.id = id
        self.apiKeyId = apiKeyId
        self.scopeType = scopeType
        self.scopeValue = scopeValue
        self.tokenLimit = tokenLimit
        self.resetInterval = resetInterval
        self.resetTime = resetTime
        self.enabled = enabled
    }
}

/// A token-limit entry — fields match the documented `POST` schema, plus
/// the documented `GET`-only enrichment fields (`tokensUsed`, `remaining`,
/// `windowStart`, `periodStartAt`, `nextResetAt`).
public struct TokenLimitEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let apiKeyId: String
    public let scopeType: String
    public let scopeValue: String?
    public let tokenLimit: Int
    public let resetInterval: String?
    public let enabled: Bool?
    public let tokensUsed: Int?
    public let remaining: Int?
    public let nextResetAt: String?

    public init(
        id: String,
        apiKeyId: String,
        scopeType: String,
        scopeValue: String?,
        tokenLimit: Int,
        resetInterval: String?,
        enabled: Bool?,
        tokensUsed: Int?,
        remaining: Int?,
        nextResetAt: String?
    ) {
        self.id = id
        self.apiKeyId = apiKeyId
        self.scopeType = scopeType
        self.scopeValue = scopeValue
        self.tokenLimit = tokenLimit
        self.resetInterval = resetInterval
        self.enabled = enabled
        self.tokensUsed = tokensUsed
        self.remaining = remaining
        self.nextResetAt = nextResetAt
    }
}

func parseTokenLimitListResponse(_ data: Data) throws -> [TokenLimitEntry] {
    let decoder = JSONDecoder()
    if let direct = try? decoder.decode([TokenLimitEntry].self, from: data) {
        return direct
    }
    struct DataWrapper: Decodable { let data: [TokenLimitEntry] }
    if let wrapped = try? decoder.decode(DataWrapper.self, from: data) {
        return wrapped.data
    }
    struct LimitsWrapper: Decodable { let limits: [TokenLimitEntry] }
    if let wrapped = try? decoder.decode(LimitsWrapper.self, from: data) {
        return wrapped.limits
    }
    throw AdminResponseParsingError.unrecognizedShape
}

// MARK: - ACP agents (fully documented response shape, incl. real JSON example)

public struct ACPAgent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let binary: String?
    public let version: String?
    public let installed: Bool
    public let protocolName: String?
    public let providerAlias: String?
    public let isCustom: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, binary, version, installed, providerAlias, isCustom
        case protocolName = "protocol"
    }

    public init(
        id: String,
        name: String,
        binary: String?,
        version: String?,
        installed: Bool,
        protocolName: String?,
        providerAlias: String?,
        isCustom: Bool
    ) {
        self.id = id
        self.name = name
        self.binary = binary
        self.version = version
        self.installed = installed
        self.protocolName = protocolName
        self.providerAlias = providerAlias
        self.isCustom = isCustom
    }
}

public struct ACPAgentsResponse: Decodable, Sendable, Equatable {
    public let agents: [ACPAgent]
    public let cacheTtlMs: Double?
    public let cacheAge: Double?
}

func parseACPAgentsResponse(_ data: Data) throws -> ACPAgentsResponse {
    try JSONDecoder().decode(ACPAgentsResponse.self, from: data)
}

// MARK: - Model latency stats (shape confirmed via a real authenticated
// response against a live server — GET /api/usage/model-latency-stats)

/// One provider/model route's rolling-window latency and success stats.
/// Real example: `{"provider":"gemini","model":"gemini-3.5-flash",
/// "key":"gemini/gemini-3.5-flash","totalRequests":2,
/// "successfulRequests":1,"successRate":0.5,"avgLatencyMs":12865,
/// "p50LatencyMs":12865,"p95LatencyMs":12865,"p99LatencyMs":12865,
/// "latencyStdDev":0,"windowHours":24,"avgTtftMs":12865,
/// "avgE2ELatencyMs":12865,"avgTokensPerSecond":173.49}`.
public struct ModelLatencyEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { key }
    public let provider: String
    public let model: String
    public let key: String
    public let totalRequests: Int
    public let successfulRequests: Int
    public let successRate: Double
    public let avgLatencyMs: Double
    public let p50LatencyMs: Double
    public let p95LatencyMs: Double
    public let p99LatencyMs: Double
    public let latencyStdDev: Double
    public let windowHours: Int
    public let avgTtftMs: Double
    public let avgE2ELatencyMs: Double
    public let avgTokensPerSecond: Double
}

public struct ModelLatencyStatsResponse: Codable, Sendable, Equatable {
    public let entries: [ModelLatencyEntry]
    public let windowHours: Int
    public let generatedAt: String
}

func parseModelLatencyStatsResponse(_ data: Data) throws -> ModelLatencyStatsResponse {
    try JSONDecoder().decode(ModelLatencyStatsResponse.self, from: data)
}

// MARK: - Model cooldowns / failovers (envelope confirmed via a real
// authenticated response — GET /api/resilience/model-cooldowns returned
// `{"items":[]}` with no active cooldown to see a populated item's exact
// shape, so individual entries stay a raw snapshot rather than typed
// fields guessed without a real example.)

public struct ModelCooldownsResponse: Sendable, Equatable {
    public let items: [AdminRawSnapshot]
}

func parseModelCooldownsResponse(_ data: Data) throws -> ModelCooldownsResponse {
    guard case .object(let fields) = try JSONDecoder().decode(JSONValue.self, from: data),
          case .array(let values)? = fields["items"] else {
        throw AdminResponseParsingError.unrecognizedShape
    }
    let items = try values.map { value -> AdminRawSnapshot in
        guard case .object(let itemFields) = value else { throw AdminResponseParsingError.unrecognizedShape }
        return AdminRawSnapshot(fields: itemFields)
    }
    return ModelCooldownsResponse(items: items)
}
