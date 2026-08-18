import Foundation
import Observation
import OmniRouteKit

/// One column of the model comparison view (2b) — a scratch, ephemeral
/// stream against a single model. Deliberately not persisted anywhere
/// (no SwiftData `Message`/`Conversation`): this is a side-by-side
/// exploration surface, not a saved conversation.
@Observable
@MainActor
final class ComparisonColumnViewModel: Identifiable {
    let id = UUID()
    let modelID: String
    private(set) var content = ""
    private(set) var isStreaming = false
    private(set) var telemetry: RequestTelemetry?
    private(set) var error: OmniRouteError?

    private let client: ChatCompleting

    init(modelID: String, client: ChatCompleting) {
        self.modelID = modelID
        self.client = client
    }

    func send(_ prompt: String) async {
        content = ""
        telemetry = nil
        error = nil
        isStreaming = true
        defer { isStreaming = false }

        let request = ChatCompletionRequest(model: modelID, messages: [ChatMessage(role: .user, content: prompt)])
        do {
            for try await delta in client.streamChatCompletion(request) {
                if Task.isCancelled { break }
                if let deltaTelemetry = delta.telemetry {
                    telemetry = deltaTelemetry
                }
                content += delta.content
            }
        } catch let error as OmniRouteError {
            self.error = error
        } catch {
            self.error = .unknown(description: "\(error)")
        }
    }
}
