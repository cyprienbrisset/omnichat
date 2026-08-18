import Foundation

struct ChatCompletionStreamChunk: Decodable {
    struct Choice: Decodable {
        struct ToolCallFragment: Decodable {
            struct FunctionFragment: Decodable {
                let name: String?
                let arguments: String?
            }
            let index: Int
            let id: String?
            let function: FunctionFragment?
        }
        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCallFragment]?

            private enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        let delta: Delta
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
}

public enum SSELineParser {
    public static func parse(line: String) -> ChatDelta? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return ChatDelta(content: "", isFinal: true)
        }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatCompletionStreamChunk.self, from: data),
              let choice = chunk.choices.first else {
            return nil
        }
        let toolCallDeltas = (choice.delta.toolCalls ?? []).map {
            ToolCallDelta(index: $0.index, id: $0.id, name: $0.function?.name, argumentsFragment: $0.function?.arguments)
        }
        guard choice.delta.content != nil || !toolCallDeltas.isEmpty || choice.finishReason != nil else {
            return nil
        }
        return ChatDelta(
            content: choice.delta.content ?? "",
            isFinal: false,
            toolCallDeltas: toolCallDeltas,
            finishReason: choice.finishReason
        )
    }
}
