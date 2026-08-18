import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant, tool
}

/// One function call the model asked for — confirmed against a live
/// OmniRoute 3.8.49 instance's real streamed `tool_calls` shape.
public struct ToolCall: Codable, Sendable, Equatable {
    public struct FunctionCall: Codable, Sendable, Equatable {
        public let name: String
        public let arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }

    public let id: String
    public let type: String
    public let function: FunctionCall

    public init(id: String, type: String = "function", function: FunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: ChatRole
    public let content: String
    /// Set on an assistant message that called tools — required by the
    /// OpenAI-compatible wire format when replaying history that includes
    /// a prior tool call.
    public let toolCalls: [ToolCall]?
    /// Set on a `.tool`-role message: which call this is the result of.
    public let toolCallId: String?

    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    public init(role: ChatRole, content: String, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

/// A single OpenAI-compatible function-tool definition offered to the
/// model. OmniChat only ever offers tools it can actually execute itself
/// (never OmniRoute's embedded MCP catalog, which a self-hosted remote
/// instance can't reach — see `OmniRouteClient+MCP.swift`).
public struct ToolDefinition: Encodable, Sendable {
    public struct FunctionSpec: Encodable, Sendable {
        public let name: String
        public let description: String
        public let parameters: ToolParameterSchema

        public init(name: String, description: String, parameters: ToolParameterSchema) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }

    public let type = "function"
    public let function: FunctionSpec

    public init(function: FunctionSpec) {
        self.function = function
    }
}

/// A minimal JSON Schema object — just enough to describe this app's
/// single-string-argument local tools, not a general-purpose schema type.
public struct ToolParameterSchema: Encodable, Sendable {
    public struct Property: Encodable, Sendable {
        public let type: String
        public let description: String

        public init(type: String, description: String) {
            self.type = type
            self.description = description
        }
    }

    public let type = "object"
    public let properties: [String: Property]
    public let required: [String]

    public init(properties: [String: Property], required: [String]) {
        self.properties = properties
        self.required = required
    }
}

public struct ChatCompletionRequest: Encodable, Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var stream: Bool
    public var tools: [ToolDefinition]?

    private enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools
    }

    public init(model: String, messages: [ChatMessage], stream: Bool = true, tools: [ToolDefinition]? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.tools = tools
    }
}

/// One incremental fragment of a streamed tool call — OpenAI-compatible
/// streaming sends the call's `name` once (first chunk) and its
/// `arguments` as a raw JSON string split across many chunks; callers
/// accumulate fragments by `index` and parse `arguments` only once
/// `finishReason == "tool_calls"`.
public struct ToolCallDelta: Sendable, Equatable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let argumentsFragment: String?

    public init(index: Int, id: String?, name: String?, argumentsFragment: String?) {
        self.index = index
        self.id = id
        self.name = name
        self.argumentsFragment = argumentsFragment
    }
}

public struct ChatDelta: Sendable, Equatable {
    public let content: String
    public let isFinal: Bool
    /// Present only on the delta that carries the response's recognized
    /// `X-OmniRoute-*` telemetry headers (yielded once, before any content,
    /// since headers are available as soon as the HTTP response arrives).
    public let telemetry: RequestTelemetry?
    public let toolCallDeltas: [ToolCallDelta]
    public let finishReason: String?

    public init(
        content: String,
        isFinal: Bool,
        telemetry: RequestTelemetry? = nil,
        toolCallDeltas: [ToolCallDelta] = [],
        finishReason: String? = nil
    ) {
        self.content = content
        self.isFinal = isFinal
        self.telemetry = telemetry
        self.toolCallDeltas = toolCallDeltas
        self.finishReason = finishReason
    }
}
