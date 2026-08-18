import SwiftUI
import SwiftData
import OmniRouteKit

struct ChatView: View {
    let conversation: Conversation
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var draft = ""
    @State private var viewModel: ChatViewModel?
    @State private var streamingTask: Task<Void, Never>?
    @State private var mode: ComposerMode = .text

    var body: some View {
        HStack(spacing: 0) {
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
                            MessageEntry(
                                message: message,
                                isGenerating: (viewModel?.isStreaming ?? false)
                                    && message.persistentModelID == conversation.orderedMessages.last?.persistentModelID,
                                pendingKind: viewModel?.lastAttemptKind
                            )
                        }
                    }
                    .padding(24)
                }
                .background(OmniTheme.paper)
                .background { OmniPaperTexture() }

                composer
            }

            if conversation.telemetryTotals.hasAnyData {
                Rectangle().fill(OmniTheme.hairline).frame(width: 1)
                TelemetryPanel(totals: conversation.telemetryTotals)
            }
        }
        .background(OmniTheme.paper)
        .task(id: "\(conversation.persistentModelID)-\(appEnvironment.activeProfile.baseURL.absoluteString)") {
            let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
            viewModel = ChatViewModel(
                conversation: conversation,
                client: client,
                mediaClient: client,
                mediaFileStore: MediaFileStore(),
                context: context,
                diagnosticLogger: appEnvironment.diagnosticLogger,
                endpointName: appEnvironment.activeProfile.name
            )
        }
        .navigationTitle(conversation.title)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                OmniTheme.label("Conversation", size: 10, color: OmniTheme.inkSoft)
                Text(conversation.title)
                    .font(OmniTheme.serif(24, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(1)
            }
            Spacer()
            if let strategy = conversation.telemetryTotals.lastRoutingStrategy
                ?? conversation.telemetryTotals.lastRoutingProvider {
                RoutingBadge(totals: conversation.telemetryTotals, fallbackLabel: strategy)
            }
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
            modeSelector
            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text(mode.placeholder).font(OmniTheme.serif(14).italic()).foregroundStyle(OmniTheme.inkSoft),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(OmniTheme.serif(14).italic())
                .foregroundStyle(OmniTheme.ink)
                .lineLimit(1...6)

                if viewModel?.isStreaming ?? false {
                    Button("Arrêter", action: { streamingTask?.cancel() })
                        .buttonStyle(.omniLink)
                }

                Button {
                    let text = draft
                    draft = ""
                    streamingTask = Task {
                        if let kind = mode.mediaKind {
                            await viewModel?.sendMediaPrompt(text, kind: kind)
                        } else {
                            await viewModel?.send(text)
                        }
                    }
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

    /// A row of tracked mono tags — the print-shop's substitute for a
    /// segmented control — switching what the composer sends to. Sized to
    /// match the mockup's composer toolbar (small caps, hairline underline).
    private var modeSelector: some View {
        HStack(spacing: 14) {
            ForEach(ComposerMode.allCases) { candidate in
                Button {
                    mode = candidate
                } label: {
                    Text(candidate.label.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(mode == candidate ? OmniTheme.accent : OmniTheme.inkSoft)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(mode == candidate ? OmniTheme.accent : OmniTheme.hairline)
                                .frame(height: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
