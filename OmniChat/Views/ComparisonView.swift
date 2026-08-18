import SwiftUI
import OmniRouteKit

/// Side-by-side model comparison (2b) — the same prompt sent to several
/// models at once, each streaming independently. Deliberately ephemeral:
/// nothing here is saved as a conversation, so switching away loses the
/// columns. No shared "combo"/judge concept — each column is just its own
/// real `streamChatCompletion` call.
struct ComparisonView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var columns: [ComparisonColumnViewModel] = []
    @State private var prompt = ""
    @State private var showingModelPicker = false
    @State private var streamingTasks: [UUID: Task<Void, Never>] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            if columns.isEmpty {
                emptyState
            } else {
                columnsRow
            }
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            composer
        }
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
        .navigationTitle("Comparaison")
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerView(currentModelID: "", onSelect: addColumn)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                OmniTheme.label("Passerelle", size: 10, color: OmniTheme.inkSoft)
                Text("Comparaison")
                    .font(OmniTheme.serif(24, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
            }
            Spacer()
            Button("+ Ajouter un modèle") { showingModelPicker = true }
                .buttonStyle(.omniLink)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Ajoute au moins un modèle pour commencer.")
                .font(OmniTheme.serif(14).italic())
                .foregroundStyle(OmniTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var columnsRow: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                columnView(column)
                if column.id != columns.last?.id {
                    Rectangle().fill(OmniTheme.hairline).frame(width: 1)
                }
            }
        }
    }

    private func columnView(_ column: ComparisonColumnViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(column.modelID)
                    .font(OmniTheme.mono(11, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(1)
                Spacer()
                if column.isStreaming {
                    OmniTheme.label("écrit", size: 8, color: OmniTheme.accent)
                }
                Button {
                    removeColumn(column)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OmniTheme.inkSoft)
            }
            .padding(12)

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            ScrollView {
                if let error = column.error {
                    Text(error.userMessage)
                        .font(OmniTheme.serif(13))
                        .foregroundStyle(OmniTheme.danger)
                        .padding(12)
                } else {
                    Text(column.content)
                        .font(OmniTheme.serif(13))
                        .foregroundStyle(OmniTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            columnFooter(column)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func columnFooter(_ column: ComparisonColumnViewModel) -> some View {
        HStack(spacing: 10) {
            if let telemetry = column.telemetry {
                if let tokensOut = telemetry.tokensOut {
                    Text("\(tokensOut) tok")
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
                if let cost = telemetry.responseCostUSD {
                    Text(String(format: "%.4f $", cost))
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
                if let latency = telemetry.routingLatencyMs {
                    Text("\(Int(latency)) ms")
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            } else if column.isStreaming {
                Text("en cours…")
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            } else {
                Text("—")
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField(
                "",
                text: $prompt,
                prompt: Text("Envoyer le même prompt à tous les modèles…").font(OmniTheme.serif(14).italic()).foregroundStyle(OmniTheme.inkSoft),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(OmniTheme.serif(14).italic())
            .lineLimit(1...6)

            Button("Envoyer à tous") { sendToAll() }
                .buttonStyle(.omniLink)
                .disabled(columns.isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
    }

    private func addColumn(modelID: String) {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        columns.append(ComparisonColumnViewModel(modelID: modelID, client: client))
    }

    private func removeColumn(_ column: ComparisonColumnViewModel) {
        streamingTasks[column.id]?.cancel()
        streamingTasks[column.id] = nil
        columns.removeAll { $0.id == column.id }
    }

    private func sendToAll() {
        let text = prompt
        for column in columns {
            streamingTasks[column.id] = Task { await column.send(text) }
        }
    }
}
