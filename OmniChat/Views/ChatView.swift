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
                    let text = draft
                    Task { await viewModel?.send(text) }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(conversation.messages, id: \.persistentModelID) { message in
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
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (viewModel?.isStreaming ?? false))
            }
            .padding()
        }
        .task(id: conversation.persistentModelID) {
            let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
            viewModel = ChatViewModel(conversation: conversation, client: client, context: context)
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
