import Foundation

struct ChatCompletionStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
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
              let content = chunk.choices.first?.delta.content else {
            return nil
        }
        return ChatDelta(content: content, isFinal: false)
    }
}
