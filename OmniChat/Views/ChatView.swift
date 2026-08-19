import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OmniRouteKit

struct ChatView: View {
    let conversation: Conversation
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var draft = ""
    @State private var viewModel: ChatViewModel?
    @State private var streamingTask: Task<Void, Never>?
    @State private var mode: ComposerMode = .text
    @State private var showingModelPicker = false
    @State private var isTranscribing = false
    @State private var transcriptionError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header

                Button("") { showingModelPicker = true }
                    .keyboardShortcut("k", modifiers: .command)
                    .hidden()
                    .frame(width: 0, height: 0)

                if let error = viewModel?.currentError {
                    ErrorBannerView(error: error) {
                        Task { await viewModel?.retryLastMessage() }
                    }
                    .disabled(viewModel?.isStreaming ?? false)
                }
                if let persistenceError = viewModel?.persistenceError {
                    PersistenceErrorBanner(message: persistenceError)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(conversation.orderedMessages, id: \.persistentModelID) { message in
                                MessageEntry(
                                    message: message,
                                    isGenerating: (viewModel?.isStreaming ?? false)
                                        && message.persistentModelID == conversation.orderedMessages.last?.persistentModelID,
                                    pendingKind: viewModel?.lastAttemptKind
                                )
                                .id(message.persistentModelID)
                            }
                        }
                        .padding(24)
                    }
                    .background(OmniTheme.paper)
                    .background { OmniPaperTexture() }
                    .onAppear { scrollToBottom(proxy: proxy, animated: false) }
                    .onChange(of: conversation.orderedMessages.count) { _, _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: conversation.orderedMessages.last?.content) { _, _ in
                        guard viewModel?.isStreaming == true else { return }
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }

                composer
            }

            if conversation.telemetryTotals.hasAnyData {
                Rectangle().fill(OmniTheme.hairline).frame(width: 1)
                TelemetryPanel(totals: conversation.telemetryTotals)
            }
        }
        .background(OmniTheme.paper)
        .task(id: "\(conversation.persistentModelID)-\(appEnvironment.activeProfile.baseURL.absoluteString)") {
            viewModel = appEnvironment.chatViewModel(for: conversation, context: context)
        }
        .navigationTitle(conversation.title)
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView(currentModelID: conversation.defaultModelID) { modelID in
                conversation.defaultModelID = modelID
                try? context.save()
            }
        }
    }

    /// Keeps the thread pinned to its latest message — on load, whenever a
    /// new message is appended, and, while streaming, as the assistant's
    /// message grows in place (its `content` mutates without changing the
    /// message count).
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let lastID = conversation.orderedMessages.last?.persistentModelID else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(lastID, anchor: .bottom) }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("OmniChat — \(conversation.title)")
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("\(Date().formatted(.dateTime.day().month(.wide).year())) ·")
                Button {
                    showingModelPicker = true
                } label: {
                    Text("model: \(conversation.defaultModelID) · ⌘K")
                }
                .buttonStyle(.plain)
                .foregroundStyle(OmniTheme.accent)
            }
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(OmniTheme.inkSoft)

            Rectangle().fill(OmniTheme.ink.opacity(0.5)).frame(height: 1).padding(.top, 9)
            Rectangle().fill(OmniTheme.ink.opacity(0.5)).frame(height: 1).padding(.top, 3)

            HStack(alignment: .lastTextBaseline) {
                Text(conversation.title)
                    .font(OmniTheme.serif(30, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let strategy = conversation.telemetryTotals.lastRoutingStrategy
                    ?? conversation.telemetryTotals.lastRoutingProvider {
                    RoutingBadge(totals: conversation.telemetryTotals, fallbackLabel: strategy)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
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
            if !appEnvironment.pendingAttachedContext.isEmpty {
                attachedContextRow
            }
            if let transcriptionError {
                Text(transcriptionError)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
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

                if appEnvironment.canTranscribeAudio {
                    Button {
                        pickAndTranscribeAudio()
                    } label: {
                        Image(systemName: isTranscribing ? "waveform" : "mic")
                    }
                    .buttonStyle(.omniLink)
                    .disabled(isTranscribing || (viewModel?.isStreaming ?? false))
                    .help("Transcrire un fichier audio dans le brouillon")
                }

                if viewModel?.isStreaming ?? false {
                    Button("Arrêter", action: { streamingTask?.cancel() })
                        .buttonStyle(.omniLink)
                }

                Button {
                    let text = draft
                    let attachedContext = appEnvironment.pendingAttachedContext
                    draft = ""
                    appEnvironment.pendingAttachedContext = []
                    streamingTask = Task {
                        if let kind = mode.mediaKind {
                            await viewModel?.sendMediaPrompt(text, kind: kind)
                        } else {
                            await viewModel?.send(text, attachedContext: attachedContext)
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

    /// Shows what local-search passages will ride along with the *next*
    /// message — real content the user picked in `RAGView`, removable
    /// individually, cleared automatically once sent.
    private var attachedContextRow: some View {
        HStack(spacing: 6) {
            OmniTheme.label("Contexte joint", size: 9, color: OmniTheme.accent)
            ForEach(Array(appEnvironment.pendingAttachedContext.enumerated()), id: \.offset) { index, passage in
                HStack(spacing: 4) {
                    Text(passage.prefix(40) + (passage.count > 40 ? "…" : ""))
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                    Button {
                        appEnvironment.pendingAttachedContext.remove(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(OmniTheme.paperMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// A row of tracked mono tags — the print-shop's substitute for a
    /// segmented control — switching what the composer sends to. Sized to
    /// match the mockup's composer toolbar (small caps, hairline underline).
    /// Only offers a generation mode the server actually has a model for —
    /// `.text` is always available (chat has no "no model configured"
    /// failure mode the way media generation does).
    private var availableModes: [ComposerMode] {
        ComposerMode.allCases.filter { candidate in
            guard let mediaKind = candidate.mediaKind else { return true }
            return appEnvironment.availableMediaKinds.contains(mediaKind)
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 14) {
            ForEach(availableModes) { candidate in
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

    /// Picks a local audio file and transcribes it into the draft — the
    /// composer's "Transcrire" action. Only presented when
    /// `canTranscribeAudio` is true, so this never fires against a server
    /// with zero speech-to-text models configured.
    private func pickAndTranscribeAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, .mpeg4Audio, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await transcribe(fileURL: url) }
        }
    }

    private func transcribe(fileURL: URL) async {
        isTranscribing = true
        transcriptionError = nil
        defer { isTranscribing = false }
        do {
            let fileData = try Data(contentsOf: fileURL)
            let text = try await viewModel?.transcribeAudio(fileData: fileData, fileName: fileURL.lastPathComponent)
            guard let text, !text.isEmpty else { return }
            draft = draft.isEmpty ? text : draft + "\n" + text
        } catch let error as OmniRouteError {
            transcriptionError = error.userMessage
        } catch {
            transcriptionError = "Impossible de lire le fichier audio : \(error.localizedDescription)"
        }
    }
}
