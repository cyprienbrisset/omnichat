import SwiftUI
import SwiftData
import OmniRouteKit

struct ChatView: View {
    let conversation: Conversation
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var draft = ""
    @State private var viewModel: ChatViewModel?

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel?.currentError {
                ErrorBannerView(error: error) {
                    Task { await viewModel?.retryLastMessage() }
                }
                .disabled(viewModel?.isStreaming ?? false)
            }
            if let persistenceError = viewModel?.persistenceError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(persistenceError)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.12))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(conversation.orderedMessages, id: \.persistentModelID) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            HStack {
                TextField("Écris un message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Envoyer") {
                    let text = draft
                    draft = ""
                    Task { await viewModel?.send(text) }
                }
                .disabled(
                    viewModel == nil
                        || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (viewModel?.isStreaming ?? false)
                )
            }
            .padding()
        }
        .task(id: "\(conversation.persistentModelID)-\(appEnvironment.activeProfile.baseURL.absoluteString)") {
            let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
            viewModel = ChatViewModel(
                conversation: conversation,
                client: client,
                context: context,
                diagnosticLogger: appEnvironment.diagnosticLogger,
                endpointName: appEnvironment.activeProfile.name
            )
        }
        .navigationTitle(conversation.title)
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "assistant" { Spacer(minLength: 40) }
            Text(message.content.isEmpty ? "…" : message.content)
                .padding(10)
                .background(message.role == "user" ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if message.role == "user" { Spacer(minLength: 40) }
        }
    }
}
