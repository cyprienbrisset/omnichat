import SwiftUI
import OmniRouteKit

/// The ⌘K model rack — a searchable catalog of every model the server
/// actually reports via `listModels()`, grouped by its real `owned_by`
/// value. No families/quota/auth-type classification (the mockup's richer
/// version needs data `/v1/models` doesn't expose), but every entry here
/// is a real, selectable model, and selecting one actually changes the
/// conversation's model — that capability didn't exist before this.
struct ModelPickerView: View {
    let currentModelID: String
    let onSelect: (String) -> Void

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var models: [ModelInfo] = []
    @State private var loadState: LoadState = .loading

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private var filteredModels: [ModelInfo] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return models }
        return models.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
                || ($0.ownedBy ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedModels: [(provider: String, models: [ModelInfo])] {
        let groups = Dictionary(grouping: filteredModels) { $0.ownedBy ?? "Autre" }
        return groups.sorted { $0.key < $1.key }.map { (provider: $0.key, models: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            content
        }
        .frame(width: 480, height: 540)
        .background(OmniTheme.paper)
        .task { await loadModels() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            OmniTheme.label("⌘K", size: 10, color: OmniTheme.accent)
            TextField("Rechercher un modèle…", text: $searchText)
                .textFieldStyle(.plain)
                .font(OmniTheme.serif(15).italic())
                .foregroundStyle(OmniTheme.ink)
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            VStack {
                Spacer()
                Text("Chargement du catalogue…")
                    .font(OmniTheme.mono(11))
                    .foregroundStyle(OmniTheme.inkSoft)
                Spacer()
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Spacer()
                OmniTheme.label("Erreur", size: 10, color: OmniTheme.danger)
                Text(message)
                    .font(OmniTheme.serif(13))
                    .foregroundStyle(OmniTheme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        case .loaded:
            if !showsAutoRow && filteredModels.isEmpty {
                VStack {
                    Spacer()
                    Text("Aucun modèle ne correspond.")
                        .font(OmniTheme.serif(13).italic())
                        .foregroundStyle(OmniTheme.inkSoft)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if showsAutoRow {
                            Section {
                                autoRow
                            } header: {
                                OmniTheme.label("Routage automatique", size: 9, color: OmniTheme.inkSoft)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(OmniTheme.paper)
                            }
                        }
                        ForEach(groupedModels, id: \.provider) { group in
                            Section {
                                ForEach(group.models, id: \.id) { model in
                                    modelRow(model)
                                }
                            } header: {
                                OmniTheme.label(group.provider, size: 9, color: OmniTheme.inkSoft)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(OmniTheme.paper)
                            }
                        }
                    }
                }
                .background(OmniTheme.paper)
            }
        }
    }

    /// `"auto"` is a real, working routing alias (confirmed live) but never
    /// appears in `/v1/models` itself — without this synthetic row, a
    /// conversation that had a specific model picked could never go back to
    /// automatic routing through this picker.
    private var showsAutoRow: Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || "auto".localizedCaseInsensitiveContains(query)
    }

    private var autoRow: some View {
        Button {
            onSelect("auto")
            dismiss()
        } label: {
            HStack {
                Text("auto")
                    .font(OmniTheme.mono(12, weight: .medium))
                    .foregroundStyle(OmniTheme.ink)
                Text("laisse OmniRoute choisir")
                    .font(OmniTheme.serif(11).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
                Spacer()
                if currentModelID == "auto" {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OmniTheme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(currentModelID == "auto" ? OmniTheme.paperMuted : Color.clear)
    }

    private func modelRow(_ model: ModelInfo) -> some View {
        Button {
            onSelect(model.id)
            dismiss()
        } label: {
            HStack {
                Text(model.id)
                    .font(OmniTheme.mono(12, weight: .medium))
                    .foregroundStyle(OmniTheme.ink)
                Spacer()
                if model.id == currentModelID {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OmniTheme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(model.id == currentModelID ? OmniTheme.paperMuted : Color.clear)
    }

    private func loadModels() async {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            // `/v1/models` lists chat, embedding, image, video, audio,
            // rerank, and moderation models together (confirmed live) —
            // picking one of the non-chat types here fails with a real
            // 400/404 on `/v1/chat/completions` ("is an image-generation
            // model and cannot be used on /v1/chat/completions", etc.).
            // Combos and plain chat models carry no `type` field; only
            // those belong in a chat model picker.
            models = try await client.listModels()
                .filter { $0.type == nil }
                .sorted { $0.id < $1.id }
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
