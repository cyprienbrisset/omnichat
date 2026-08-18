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
    private let mediaClient: MediaGenerating
    private let mediaFileStore: MediaFileStore
    private let context: ModelContext
    private let diagnosticLogger: DiagnosticLogger
    private let endpointName: String
    /// The kind of the most recent attempt — `nil` for text. Read by the
    /// view while `isStreaming` to pick which loading animation to show,
    /// and by `retryLastMessage()` to know which path to re-dispatch.
    private(set) var lastAttemptKind: MediaKind?

    init(
        conversation: Conversation,
        client: ChatCompleting,
        mediaClient: MediaGenerating,
        mediaFileStore: MediaFileStore,
        context: ModelContext,
        diagnosticLogger: DiagnosticLogger,
        endpointName: String
    ) {
        self.conversation = conversation
        self.client = client
        self.mediaClient = mediaClient
        self.mediaFileStore = mediaFileStore
        self.context = context
        self.diagnosticLogger = diagnosticLogger
        self.endpointName = endpointName
    }

    func send(_ text: String) async {
        currentError = nil
        persistenceError = nil
        lastAttemptKind = nil
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
                // Cooperative stop: ChatView cancels the Task it wraps this
                // call in when the user taps "Arrêter". Breaking here (rather
                // than throwing) means no error banner — a deliberate stop
                // isn't a failure — and breaking out of the for-loop tears
                // down the underlying AsyncThrowingStream, which cancels the
                // in-flight network request via its `onTermination` handler.
                if Task.isCancelled { break }
                if let telemetry = delta.telemetry {
                    assistantMessage.routingStrategy = telemetry.routingStrategy
                    assistantMessage.routingProvider = telemetry.routingProvider
                    assistantMessage.routingLatencyMs = telemetry.routingLatencyMs
                    assistantMessage.responseCostUSD = telemetry.responseCostUSD
                    assistantMessage.tokensIn = telemetry.tokensIn
                    assistantMessage.tokensOut = telemetry.tokensOut
                    assistantMessage.cacheHit = telemetry.cacheHit
                }
                assistantMessage.content += delta.content
            }
            if Task.isCancelled {
                assistantMessage.isIncomplete = true
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

    func sendMediaPrompt(_ text: String, kind: MediaKind) async {
        currentError = nil
        persistenceError = nil
        lastAttemptKind = kind

        let userMessage = Message(role: "user", content: text)
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)

        let assistantMessage = Message(role: "assistant", content: "")
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)

        isStreaming = true
        defer { isStreaming = false }

        do {
            let result = try await generate(kind: kind, prompt: text)
            let fileName = try await mediaFileStore.save(result, preferredExtension: kind.fileExtension)
            let mediaItem = MediaItem(kind: kind.rawValue, prompt: text, modelID: "auto", fileName: fileName)
            mediaItem.conversation = conversation
            context.insert(mediaItem)
            assistantMessage.mediaItem = mediaItem
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
            persistenceError = "Impossible d'enregistrer le média : \(error.localizedDescription)"
            return
        }
        persistenceError = nil
    }

    private func generate(kind: MediaKind, prompt: String) async throws -> MediaGenerationResult {
        switch kind {
        case .image:
            return try await mediaClient.generateImage(MediaGenerationRequest(model: "auto", prompt: prompt))
        case .video:
            return try await mediaClient.generateVideo(MediaGenerationRequest(model: "auto", prompt: prompt))
        case .music:
            return try await mediaClient.generateMusic(MediaGenerationRequest(model: "auto", prompt: prompt))
        case .speech:
            return try await mediaClient.synthesizeSpeech(SpeechRequest(model: "auto", input: prompt))
        }
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

        if let kind = lastAttemptKind {
            await sendMediaPrompt(lastUserMessage.content, kind: kind)
        } else {
            await send(lastUserMessage.content)
        }
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
