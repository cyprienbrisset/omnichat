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
    private(set) var persistenceError: String?

    private let client: ChatCompleting
    private let context: ModelContext
    private let diagnosticLogger: DiagnosticLogger
    private let endpointName: String

    init(
        conversation: Conversation,
        client: ChatCompleting,
        context: ModelContext,
        diagnosticLogger: DiagnosticLogger,
        endpointName: String
    ) {
        self.conversation = conversation
        self.client = client
        self.context = context
        self.diagnosticLogger = diagnosticLogger
        self.endpointName = endpointName
    }

    func send(_ text: String) async {
        currentError = nil
        persistenceError = nil
        let userMessage = Message(role: "user", content: text)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)

        let assistantMessage = Message(role: "assistant", content: "")
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)

        isStreaming = true
        defer { isStreaming = false }

        // `orderedMessages` is the single source of truth for chronological
        // order (SwiftData's to-many relationship is unordered); exclude the
        // fresh assistant placeholder by identity, not by array position.
        let history = conversation.orderedMessages
            .filter { $0.persistentModelID != assistantMessage.persistentModelID }
            .map { ChatMessage(role: ChatRole(rawValue: $0.role) ?? .user, content: $0.content) }
        let request = ChatCompletionRequest(model: conversation.defaultModelID, messages: history)

        do {
            for try await delta in client.streamChatCompletion(request) {
                assistantMessage.content += delta.content
            }
        } catch let error as OmniRouteError {
            assistantMessage.isIncomplete = true
            currentError = error
            await logDiagnostic(error)
        } catch {
            assistantMessage.isIncomplete = true
            let mapped = OmniRouteError.unknown(description: "\(error)")
            currentError = mapped
            await logDiagnostic(mapped)
        }

        do {
            try context.save()
        } catch {
            persistenceError = "Impossible d'enregistrer la conversation : \(error.localizedDescription)"
            return
        }
        persistenceError = nil
    }

    /// Resends the last user message without re-sending an empty draft.
    /// Removes the trailing incomplete assistant message from the failed
    /// attempt (if any) and re-runs `send` with the same text, rather than
    /// duplicating the streaming logic.
    func retryLastMessage() async {
        guard let lastUserMessage = conversation.orderedMessages.last(where: { $0.role == "user" }) else { return }

        if let trailing = conversation.orderedMessages.last,
           trailing.role == "assistant",
           trailing.isIncomplete {
            conversation.messages.removeAll { $0.persistentModelID == trailing.persistentModelID }
            context.delete(trailing)
        }

        await send(lastUserMessage.content)
    }

    private func logDiagnostic(_ error: OmniRouteError) async {
        let category = Self.categoryName(for: error)
        let entry = DiagnosticLogEntry(
            timestamp: Date(),
            category: category,
            endpointName: endpointName,
            detail: Self.detail(for: category)
        )
        try? await diagnosticLogger.log(entry)
    }

    private static func categoryName(for error: OmniRouteError) -> String {
        switch error {
        case .authenticationFailed: return "authenticationFailed"
        case .rateLimited: return "rateLimited"
        case .network: return "network"
        case .invalidResponse: return "invalidResponse"
        case .streamInterrupted: return "streamInterrupted"
        case .unknown: return "unknown"
        }
    }

    private static func detail(for category: String) -> String {
        switch category {
        case "authenticationFailed": return "Échec d'authentification auprès d'OmniRoute."
        case "rateLimited": return "Limite de requêtes atteinte."
        case "network": return "Erreur réseau lors de l'appel à OmniRoute."
        case "invalidResponse": return "Réponse HTTP inattendue reçue d'OmniRoute."
        case "streamInterrupted": return "Le flux de réponse a été interrompu avant la fin."
        case "unknown": return "Erreur inconnue."
        default: return "Erreur."
        }
    }
}
