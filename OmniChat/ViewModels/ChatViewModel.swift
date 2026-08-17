import Foundation
import Observation
import SwiftData
import OmniRouteKit

@Observable
@MainActor
final class ChatViewModel {
    let conversation: Conversation
    private(set) var isStreaming = false
    private(set) var currentError: OmniRouteError?

    private let client: ChatCompleting
    private let context: ModelContext

    init(conversation: Conversation, client: ChatCompleting, context: ModelContext) {
        self.conversation = conversation
        self.client = client
        self.context = context
    }

    func send(_ text: String) async {
        currentError = nil
        let userMessage = Message(role: "user", content: text)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)

        let assistantMessage = Message(role: "assistant", content: "")
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)

        isStreaming = true
        defer { isStreaming = false }

        let history = conversation.messages.dropLast().map {
            ChatMessage(role: ChatRole(rawValue: $0.role) ?? .user, content: $0.content)
        }
        let request = ChatCompletionRequest(model: conversation.defaultModelID, messages: Array(history))

        do {
            for try await delta in client.streamChatCompletion(request) {
                assistantMessage.content += delta.content
            }
        } catch let error as OmniRouteError {
            assistantMessage.isIncomplete = true
            currentError = error
        } catch {
            assistantMessage.isIncomplete = true
            currentError = .unknown(description: "\(error)")
        }
        try? context.save()
        // SwiftData's to-many relationships are backed by Core Data's unordered
        // NSSet storage; a save can shuffle the materialized array even though the
        // in-memory order was stable pre-save. Re-sort by creation time so
        // `conversation.messages` remains chronologically ordered after saving.
        conversation.messages.sort { $0.createdAt < $1.createdAt }
    }
}
