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
            header

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
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(conversation.orderedMessages, id: \.persistentModelID) { message in
                        MessageEntry(message: message)
                    }
                }
                .padding(24)
            }
            .background(OmniTheme.paper)
            .background { OmniPaperTexture() }

            composer
        }
        .background(OmniTheme.paper)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Conversation", size: 10, color: OmniTheme.inkSoft)
            Text(conversation.title)
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OmniTheme.paper)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text("Écrire la suite…").font(OmniTheme.serif(14).italic()).foregroundStyle(OmniTheme.inkSoft),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(OmniTheme.serif(14).italic())
                .foregroundStyle(OmniTheme.ink)
                .lineLimit(1...6)

                Button {
                    let text = draft
                    draft = ""
                    Task { await viewModel?.send(text) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.omniIcon)
                .disabled(
                    viewModel == nil
                        || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (viewModel?.isStreaming ?? false)
                )
            }
            .padding(16)
        }
        .background(OmniTheme.paper)
    }
}

private struct PersistenceErrorBanner: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Enregistrement", size: 10, color: OmniTheme.warning)
            Text(message)
                .font(OmniTheme.serif(13))
                .foregroundStyle(OmniTheme.ink)
        }
        .padding(14)
        .background(OmniTheme.paperMuted)
        .overlay(alignment: .leading) {
            Rectangle().fill(OmniTheme.warning).frame(width: 3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

/// Each turn is set in its own register: a request reads as a quoted,
/// italic aside in the margin; a response reads as flowing serif prose —
/// the print-shop's substitute for chat bubbles.
private struct MessageEntry: View {
    let message: Message

    var body: some View {
        if message.role == "user" {
            requestBlock
        } else {
            responseBlock
        }
    }

    private var requestBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label("Demande", size: 10, color: OmniTheme.inkSoft)
            Text(message.content)
                .font(OmniTheme.serif(15).italic())
                .foregroundStyle(OmniTheme.ink.opacity(0.85))
        }
        .padding(.leading, 14)
        .padding(.vertical, 2)
        .overlay(alignment: .leading) {
            Rectangle().fill(OmniTheme.accent).frame(width: 3)
        }
    }

    private var responseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(message.isIncomplete ? OmniTheme.warning : OmniTheme.success)
                    .frame(width: 6, height: 6)
                OmniTheme.label("Réponse", size: 10, color: OmniTheme.inkSoft)
            }
            Text(message.content.isEmpty ? "…" : message.content)
                .font(OmniTheme.serif(15))
                .foregroundStyle(OmniTheme.ink)
                .lineSpacing(5)
            if let telemetrySummary = message.telemetrySummary {
                Text(telemetrySummary)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
    }
}
