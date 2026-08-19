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
    /// Tools OmniChat actually executes itself when the model calls them —
    /// empty by default, so callers that don't pass any get the exact same
    /// request shape (`tools: nil`) and behavior as before this existed.
    private let localTools: [LocalTool]
    /// Hard cap on tool round-trips per `send()` call, so a model that keeps
    /// calling tools can't loop forever.
    private let maxToolRounds = 3
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
        endpointName: String,
        localTools: [LocalTool] = []
    ) {
        self.conversation = conversation
        self.client = client
        self.mediaClient = mediaClient
        self.mediaFileStore = mediaFileStore
        self.context = context
        self.diagnosticLogger = diagnosticLogger
        self.endpointName = endpointName
        self.localTools = localTools
    }

    func send(_ text: String, attachedContext: [String] = []) async {
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
        var history = conversation.orderedMessages
            .filter { $0.persistentModelID != assistantMessage.persistentModelID }
            .map { ChatMessage(role: ChatRole(rawValue: $0.role) ?? .user, content: $0.content) }
        // Passages picked from local search are sent as context for this
        // request only — never persisted as a real conversation message.
        if !attachedContext.isEmpty {
            let block = attachedContext.joined(separator: "\n\n---\n\n")
            history.insert(ChatMessage(role: .system, content: "Contexte joint depuis la recherche locale :\n\n\(block)"), at: 0)
        }
        let toolDefinitions = localTools.map(\.definition)
        var roundsRemaining = maxToolRounds

        do {
            roundLoop: while true {
                let request = ChatCompletionRequest(
                    model: conversation.defaultModelID,
                    messages: history,
                    tools: toolDefinitions.isEmpty ? nil : toolDefinitions
                )
                // Streamed tool calls arrive as incremental fragments keyed
                // by index — `id`/`name` on the first fragment only,
                // `arguments` split across many — accumulated here and only
                // parsed once the round's `finish_reason` confirms the call
                // is complete.
                var pendingCalls: [Int: (id: String?, name: String?, arguments: String)] = [:]
                var endedWithToolCalls = false

                for try await delta in client.streamChatCompletion(request) {
                    // Cooperative stop: ChatView cancels the Task it wraps this
                    // call in when the user taps "Arrêter". Breaking here (rather
                    // than throwing) means no error banner — a deliberate stop
                    // isn't a failure — and breaking out of the for-loop tears
                    // down the underlying AsyncThrowingStream, which cancels the
                    // in-flight network request via its `onTermination` handler.
                    if Task.isCancelled { break roundLoop }
                    if let telemetry = delta.telemetry {
                        assistantMessage.routingStrategy = telemetry.routingStrategy
                        assistantMessage.routingProvider = telemetry.routingProvider
                        assistantMessage.routingLatencyMs = telemetry.routingLatencyMs
                        assistantMessage.responseCostUSD = telemetry.responseCostUSD
                        assistantMessage.tokensIn = telemetry.tokensIn
                        assistantMessage.tokensOut = telemetry.tokensOut
                        assistantMessage.cacheHit = telemetry.cacheHit
                    }
                    for fragment in delta.toolCallDeltas {
                        var entry = pendingCalls[fragment.index] ?? (id: nil, name: nil, arguments: "")
                        if let id = fragment.id { entry.id = id }
                        if let name = fragment.name { entry.name = name }
                        if let argumentsFragment = fragment.argumentsFragment { entry.arguments += argumentsFragment }
                        pendingCalls[fragment.index] = entry
                    }
                    if delta.finishReason == "tool_calls" {
                        endedWithToolCalls = true
                    }
                    assistantMessage.content += delta.content
                }
                if Task.isCancelled {
                    assistantMessage.isIncomplete = true
                    break roundLoop
                }

                guard endedWithToolCalls, roundsRemaining > 0,
                      let firstCall = pendingCalls.sorted(by: { $0.key < $1.key }).first?.value,
                      let callId = firstCall.id, let name = firstCall.name,
                      let tool = localTools.first(where: { $0.definition.function.name == name }) else {
                    break roundLoop
                }
                roundsRemaining -= 1

                let result: String
                do {
                    result = try await tool.execute(argumentsJSON: firstCall.arguments)
                } catch {
                    result = "Erreur lors de l'exécution de l'outil : \(error.localizedDescription)"
                }
                assistantMessage.toolName = name
                assistantMessage.toolArguments = firstCall.arguments
                assistantMessage.toolResult = result
                // The partial content emitted before the model decided to
                // call a tool (if any) isn't the real answer — only the
                // content from the round that finally responds without
                // calling another tool is.
                assistantMessage.content = ""

                history.append(ChatMessage(
                    role: .assistant,
                    content: "",
                    toolCalls: [ToolCall(id: callId, function: .init(name: name, arguments: firstCall.arguments))]
                ))
                history.append(ChatMessage(role: .tool, content: result, toolCallId: callId))
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
            context.rollback()
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
            let (result, modelID) = try await generate(kind: kind, prompt: text)
            let fileName = try await mediaFileStore.save(result, preferredExtension: kind.fileExtension)
            let mediaItem = MediaItem(kind: kind.rawValue, prompt: text, modelID: modelID, fileName: fileName)
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
            context.rollback()
            return
        }
        persistenceError = nil
    }

    /// Media generation endpoints reject the chat-only `"auto"` routing
    /// alias (confirmed live: `"Invalid image model: auto. Use format:
    /// provider/model"`, same for video/music/speech) — so this resolves a
    /// real model id from the server's own catalog for each kind first.
    ///
    /// Confirmed live: a server can list a model in that very catalog whose
    /// generation route still 404s (`"Path not found: /v1/images/
    /// generations"` for a specific Fireworks entry, even though the
    /// catalog GET itself succeeds) — a provider-registration quirk on
    /// OmniRoute's side, not something a fixed "pick the first one" can
    /// paper over. Confirmed live again: this isn't a single bad entry —
    /// on one real server, the *entire* Fireworks block (5 consecutive
    /// catalog entries) 404s the same way, followed by a Gemini entry that
    /// 404s for an unrelated upstream reason. Confirmed live a third time,
    /// via a real user's own diagnostics log: the same "listed but broken"
    /// pattern also shows up as 401/403, not just 404 — a candidate whose
    /// *provider-specific* key is invalid or lacks rights for this media
    /// type, even while other providers further down the catalog are
    /// correctly configured with active quota. So this tries a generous
    /// number of real candidates in order and only moves to the next on
    /// those two exact "this candidate isn't usable" shapes; any other
    /// error (budget, rate limit, content policy) is real and surfaces
    /// immediately rather than masking it behind a pointless retry.
    private func generate(kind: MediaKind, prompt: String) async throws -> (MediaGenerationResult, modelID: String) {
        let candidates = try await mediaModelCandidates(for: kind)
        guard !candidates.isEmpty else {
            throw OmniRouteError.unknown(description: "Aucun modèle disponible pour la génération (\(kind.label.lowercased())) sur ce serveur.")
        }
        var lastRetryableError: OmniRouteError?
        for modelID in candidates.prefix(20) {
            do {
                return (try await performMediaGeneration(kind: kind, modelID: modelID, prompt: prompt), modelID)
            } catch let error as OmniRouteError {
                switch error {
                case .invalidResponse(404), .authenticationFailed:
                    lastRetryableError = error
                default:
                    throw error
                }
            }
        }
        throw lastRetryableError ?? OmniRouteError.unknown(
            description: "Aucun modèle disponible pour la génération (\(kind.label.lowercased())) sur ce serveur."
        )
    }

    private func performMediaGeneration(kind: MediaKind, modelID: String, prompt: String) async throws -> MediaGenerationResult {
        switch kind {
        case .image:
            return try await mediaClient.generateImage(MediaGenerationRequest(model: modelID, prompt: prompt))
        case .video:
            return try await mediaClient.generateVideo(MediaGenerationRequest(model: modelID, prompt: prompt))
        case .music:
            return try await mediaClient.generateMusic(MediaGenerationRequest(model: modelID, prompt: prompt))
        case .speech:
            return try await mediaClient.synthesizeSpeech(SpeechRequest(model: modelID, input: prompt))
        }
    }

    private func mediaModelCandidates(for kind: MediaKind) async throws -> [String] {
        let models: [ModelInfo]
        switch kind {
        case .image: models = try await mediaClient.listImageModels()
        case .video: models = try await mediaClient.listVideoModels()
        case .music: models = try await mediaClient.listMusicModels()
        case .speech: models = try await mediaClient.listSpeechModels()
        }
        return models.map(\.id)
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
