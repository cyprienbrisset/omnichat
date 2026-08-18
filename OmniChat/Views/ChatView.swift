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
                PersistenceErrorBanner(message: persistenceError)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(conversation.orderedMessages, id: \.persistentModelID) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            .background(OmniTheme.canvasBackground)
            .background { OmniDotGridBackground() }
            HStack(spacing: 10) {
                TextField("Écris un message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(OmniTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(OmniTheme.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button {
                    let text = draft
                    draft = ""
                    Task { await viewModel?.send(text) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.omniPrimary)
                .disabled(
                    viewModel == nil
                        || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (viewModel?.isStreaming ?? false)
                )
            }
            .padding(12)
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

private struct PersistenceErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" {
                Spacer(minLength: 40)
                userBubble
            } else {
                assistantCard
                Spacer(minLength: 40)
            }
        }
    }

    private var userBubble: some View {
        Text(message.content)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(OmniTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(message.isIncomplete ? Color.orange : OmniTheme.success)
                    .frame(width: 6, height: 6)
                Text("assistant")
                    .font(OmniTheme.mono(10, weight: .semibold))
                    .foregroundStyle(OmniTheme.secondaryText)
            }
            Text(message.content.isEmpty ? "…" : message.content)
                .font(.system(size: 13))
        }
        .padding(12)
        .background(OmniTheme.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OmniTheme.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
