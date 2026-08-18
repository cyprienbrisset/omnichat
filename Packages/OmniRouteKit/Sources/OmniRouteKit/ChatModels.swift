import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant
}

public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: ChatRole
    public let content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatCompletionRequest: Encodable, Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var stream: Bool

    public init(model: String, messages: [ChatMessage], stream: Bool = true) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

public struct ChatDelta: Sendable, Equatable {
    public let content: String
    public let isFinal: Bool
    /// Present only on the delta that carries the response's recognized
    /// `X-OmniRoute-*` telemetry headers (yielded once, before any content,
    /// since headers are available as soon as the HTTP response arrives).
    public let telemetry: RequestTelemetry?

    public init(content: String, isFinal: Bool, telemetry: RequestTelemetry? = nil) {
        self.content = content
        self.isFinal = isFinal
        self.telemetry = telemetry
    }
}
