import SwiftUI
import SwiftData
import AVKit
import OmniRouteKit

private enum ComposerMode: String, CaseIterable, Identifiable {
    case text, image, video, music, speech

    var id: String { rawValue }

    var mediaKind: MediaKind? {
        switch self {
        case .text: return nil
        case .image: return .image
        case .video: return .video
        case .music: return .music
        case .speech: return .speech
        }
    }

    var label: String {
        mediaKind?.label ?? "Texte"
    }

    var placeholder: String {
        mediaKind?.promptPlaceholder ?? "Écrire la suite…"
    }
}

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
                            MessageEntry(message: message)
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
    /// segmented control — switching what the composer sends to.
    private var modeSelector: some View {
        HStack(spacing: 20) {
            ForEach(ComposerMode.allCases) { candidate in
                Button {
                    mode = candidate
                } label: {
                    Text(candidate.label.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(mode == candidate ? OmniTheme.ink : OmniTheme.inkSoft)
                        .padding(.bottom, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(mode == candidate ? OmniTheme.accent : Color.clear)
                                .frame(height: 2)
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

/// A compact, real-data-only echo of the routing decision behind the most
/// recent response — omits anything this session doesn't actually capture
/// (combo target count, compression ratio) rather than inventing it.
private struct RoutingBadge: View {
    let totals: ConversationTelemetryTotals
    let fallbackLabel: String

    var body: some View {
        HStack(spacing: 6) {
            if let strategy = totals.lastRoutingStrategy, let provider = totals.lastRoutingProvider {
                Text("\(strategy) → \(provider)")
            } else {
                Text(fallbackLabel)
            }
            if let latency = totals.lastRoutingLatencyMs {
                Text("· \(Int(latency)) ms")
            }
        }
        .font(OmniTheme.mono(10, weight: .semibold))
        .foregroundStyle(OmniTheme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(OmniTheme.accent.opacity(0.4), lineWidth: 1)
        )
    }
}

/// Conversation-level metrics in the margin, mirroring the mockup's layout
/// but populated only from telemetry this app actually captures — no quota
/// or combo-comparison data yet, since those need work not done here.
private struct TelemetryPanel: View {
    let totals: ConversationTelemetryTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OmniTheme.label("Métriques", size: 10, color: OmniTheme.inkSoft)

            metric(label: "Jetons", value: "\(totals.totalTokensIn)→\(totals.totalTokensOut)")

            if totals.totalCostUSD > 0 {
                metric(label: "Coût", value: String(format: "$%.4f", totals.totalCostUSD))
            }

            if totals.cacheEligibleTurns > 0 {
                metric(label: "Cache sémantique", value: "\(totals.cacheHits) coup(s) sur \(totals.cacheEligibleTurns) tour(s)")
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 190, alignment: .leading)
        .background(OmniTheme.paperMuted)
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            OmniTheme.label(label, size: 8, color: OmniTheme.inkSoft)
            Text(value)
                .font(OmniTheme.serif(15, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
        }
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
            if let mediaItem = message.mediaItem {
                MediaContentView(mediaItem: mediaItem)
                Text(mediaItem.prompt)
                    .font(OmniTheme.serif(13).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
            } else {
                Text(message.content.isEmpty ? "…" : message.content)
                    .font(OmniTheme.serif(15))
                    .foregroundStyle(OmniTheme.ink)
                    .lineSpacing(5)
            }
            if let telemetrySummary = message.telemetrySummary {
                Text(telemetrySummary)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
    }
}

/// Renders a generated media item inline — reused at gallery-cell scale by
/// `GalleryView` (frame size is the caller's responsibility, not baked in
/// here beyond a sensible chat-inline default).
struct MediaContentView: View {
    let mediaItem: MediaItem

    var body: some View {
        Group {
            switch mediaItem.kind {
            case "image":
                if let nsImage = NSImage(contentsOf: mediaItem.fileURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360)
                } else {
                    unavailable
                }
            case "video":
                VideoPlayer(player: AVPlayer(url: mediaItem.fileURL))
                    .frame(width: 360, height: 220)
            case "music", "speech":
                VideoPlayer(player: AVPlayer(url: mediaItem.fileURL))
                    .frame(width: 320, height: 50)
            default:
                unavailable
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(OmniTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var unavailable: some View {
        Text("Média indisponible")
            .font(OmniTheme.mono(11))
            .foregroundStyle(OmniTheme.inkSoft)
            .padding(12)
    }
}
