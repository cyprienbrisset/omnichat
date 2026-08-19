import SwiftUI
import SwiftData
import OmniRouteKit

/// Fusion (3b): the same prompt goes to N source models (exactly like
/// Comparison — independent, real, concurrent `streamChatCompletion`
/// calls), then a judge model reads every answer that came back and
/// synthesizes one final response. Unlike Comparison, Fusion sessions are
/// real, persisted history — in their own store (`FusionSession`), never
/// mixed into the normal conversation list, since a fused answer isn't a
/// single model's reply.
struct FusionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FusionSession.createdAt, order: .reverse) private var sessions: [FusionSession]
    @State private var selectedSession: FusionSession?

    var body: some View {
        HStack(spacing: 0) {
            sessionList
                .frame(width: 260)
            Rectangle().fill(OmniTheme.hairline).frame(width: 1)
            if let selectedSession {
                FusionSessionDetailView(session: selectedSession)
                    .id(selectedSession.persistentModelID)
            } else {
                emptyDetailState
            }
        }
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
        .navigationTitle("Fusion")
        .onAppear {
            if selectedSession == nil { selectedSession = sessions.first }
        }
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            HStack {
                OmniTheme.label("Fusion", size: 10, color: OmniTheme.inkSoft)
                Spacer()
                Button { createSession() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OmniTheme.accent)
                .help("Nouvelle session de fusion")
            }
            .padding(16)
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            if sessions.isEmpty {
                VStack {
                    Spacer()
                    Text("Aucune session. Crée-en une pour commencer.")
                        .font(OmniTheme.serif(13).italic())
                        .foregroundStyle(OmniTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                        }
                    }
                }
            }
        }
        .background(OmniTheme.paper)
    }

    private func sessionRow(_ session: FusionSession) -> some View {
        let isSelected = session.persistentModelID == selectedSession?.persistentModelID
        return Button {
            selectedSession = session
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(OmniTheme.serif(13))
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(1)
                Text("\(session.orderedRounds.count) échange(s) · juge \(session.judgeModelID)")
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? OmniTheme.paperMuted : Color.clear)
        .contextMenu {
            Button("Supprimer", role: .destructive) { delete(session) }
        }
    }

    private var emptyDetailState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Sélectionne ou crée une session de fusion.")
                .font(OmniTheme.serif(14).italic())
                .foregroundStyle(OmniTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createSession() {
        let session = FusionSession(title: "Fusion \(sessions.count + 1)")
        context.insert(session)
        try? context.save()
        selectedSession = session
    }

    private func delete(_ session: FusionSession) {
        if selectedSession?.persistentModelID == session.persistentModelID {
            selectedSession = nil
        }
        context.delete(session)
        try? context.save()
    }
}

/// A source model's answer or the fused answer, in the shape both the
/// live in-flight round (read from `FusionViewModel`) and a persisted
/// `FusionRound` can be projected into — one rendering path for both.
private struct FusionSourceDisplay: Identifiable {
    let id: String
    let content: String
    let isIncomplete: Bool
}

private struct FusionSessionDetailView: View {
    let session: FusionSession
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var viewModel: FusionViewModel?
    @State private var prompt = ""
    @State private var showingSourceModelPicker = false
    @State private var showingJudgePicker = false
    @State private var streamingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(session.orderedRounds, id: \.persistentModelID) { round in
                            FusionRoundView(
                                prompt: round.prompt,
                                fusedContent: round.fusedContent,
                                fusedIsIncomplete: round.fusedIsIncomplete,
                                isGenerating: false,
                                judgeLabel: Self.judgeLabel(
                                    setTo: round.judgeModelIDAtRoundTime,
                                    resolvedTo: round.resolvedJudgeModelID
                                ),
                                sources: round.orderedSourceResponses.map {
                                    FusionSourceDisplay(id: $0.modelID, content: $0.content, isIncomplete: $0.isIncomplete)
                                }
                            )
                            .id(round.persistentModelID)
                        }
                        if let viewModel, viewModel.isRunning {
                            FusionRoundView(
                                prompt: viewModel.runningPrompt ?? "",
                                fusedContent: viewModel.fusedContent,
                                fusedIsIncomplete: viewModel.fusedError != nil,
                                isGenerating: viewModel.fusedIsStreaming,
                                judgeLabel: Self.judgeLabel(
                                    setTo: viewModel.judgeModelID,
                                    resolvedTo: viewModel.resolvedJudgeModelID
                                ),
                                sources: viewModel.sourceColumns.map {
                                    FusionSourceDisplay(
                                        id: $0.modelID,
                                        content: $0.error?.userMessage ?? $0.content,
                                        isIncomplete: $0.error != nil
                                    )
                                }
                            )
                        }
                    }
                    .padding(24)
                }
                .onChange(of: session.orderedRounds.count) { _, _ in
                    guard let lastID = session.orderedRounds.last?.persistentModelID else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            composer
        }
        .background(OmniTheme.paper)
        .task(id: session.persistentModelID) {
            let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
            viewModel = FusionViewModel(session: session, client: client, context: context)
        }
        .sheet(isPresented: $showingSourceModelPicker) {
            ModelPickerView(currentModelID: "") { modelID in
                viewModel?.addSourceModel(modelID)
            }
        }
        .sheet(isPresented: $showingJudgePicker) {
            ModelPickerView(currentModelID: viewModel?.judgeModelID ?? "auto") { modelID in
                viewModel?.judgeModelID = modelID
            }
        }
    }

    private static func judgeLabel(setTo judgeModelID: String, resolvedTo resolved: String?) -> String {
        guard judgeModelID == "auto" else { return judgeModelID }
        guard let resolved else { return "auto" }
        return "auto → \(resolved)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(OmniTheme.serif(20, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
                Spacer()
            }
            HStack(spacing: 8) {
                OmniTheme.label("Sources", size: 9, color: OmniTheme.inkSoft)
                if let viewModel {
                    ForEach(viewModel.sourceColumns) { column in
                        HStack(spacing: 4) {
                            Text(column.modelID)
                                .font(OmniTheme.mono(10, weight: .medium))
                                .foregroundStyle(OmniTheme.ink)
                            Button {
                                viewModel.removeSourceModel(column)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(OmniTheme.inkSoft)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OmniTheme.paperMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                Button("+ Ajouter") { showingSourceModelPicker = true }
                    .buttonStyle(.omniLink)
                Spacer()
                OmniTheme.label("Juge", size: 9, color: OmniTheme.inkSoft)
                Button(viewModel?.judgeModelID ?? "auto") { showingJudgePicker = true }
                    .buttonStyle(.omniLink)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField(
                "",
                text: $prompt,
                prompt: Text("Envoyer à toutes les sources, puis fusionner…").font(OmniTheme.serif(14).italic()).foregroundStyle(OmniTheme.inkSoft),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(OmniTheme.serif(14).italic())
            .lineLimit(1...6)

            Button("Fusionner") { send() }
                .buttonStyle(.omniLink)
                .disabled(
                    viewModel == nil
                        || (viewModel?.sourceColumns.isEmpty ?? true)
                        || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (viewModel?.fusedIsStreaming ?? false)
                )
        }
        .padding(16)
    }

    private func send() {
        let text = prompt
        prompt = ""
        streamingTask = Task { await viewModel?.sendFusionPrompt(text) }
    }
}

private struct FusionRoundView: View {
    let prompt: String
    let fusedContent: String
    let fusedIsIncomplete: Bool
    let isGenerating: Bool
    let judgeLabel: String
    let sources: [FusionSourceDisplay]
    @State private var showsSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                OmniTheme.label("Demande", size: 10, color: OmniTheme.inkSoft)
                Text(prompt)
                    .font(OmniTheme.serif(15).italic())
                    .foregroundStyle(OmniTheme.ink.opacity(0.85))
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle().fill(OmniTheme.accent).frame(width: 3)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(fusedIsIncomplete ? OmniTheme.warning : OmniTheme.success)
                        .frame(width: 6, height: 6)
                    OmniTheme.label("Fusion", size: 10, color: OmniTheme.inkSoft)
                    Text("· \(judgeLabel)")
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
                if fusedContent.isEmpty {
                    if isGenerating {
                        GeneratingIndicatorView(kind: nil)
                    } else {
                        Text("…")
                            .font(OmniTheme.serif(15))
                            .foregroundStyle(OmniTheme.ink)
                    }
                } else {
                    MarkdownContentView(blocks: MarkdownParser.parse(fusedContent), appliesDropCap: true)
                        .textSelection(.enabled)
                }
                if !sources.isEmpty {
                    Button(showsSources ? "Masquer les \(sources.count) réponses sources" : "Voir les \(sources.count) réponses sources") {
                        showsSources.toggle()
                    }
                    .buttonStyle(.omniLink)
                    if showsSources {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(sources) { source in
                                sourceView(source)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func sourceView(_ source: FusionSourceDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.id)
                .font(OmniTheme.mono(10, weight: .semibold))
                .foregroundStyle(source.isIncomplete ? OmniTheme.danger : OmniTheme.accent)
            Text(source.content)
                .font(OmniTheme.serif(13))
                .foregroundStyle(OmniTheme.ink)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(OmniTheme.paperMuted)
        .overlay(alignment: .leading) {
            Rectangle().fill(OmniTheme.hairline).frame(width: 2)
        }
    }
}
