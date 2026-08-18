import SwiftUI
import SwiftData
import OmniRouteKit

/// Local semantic search over conversation history — real `/v1/embeddings`
/// vectors, indexed only when the user taps "Indexer" (never automatically:
/// every index call costs real money and sends the passage's text to a
/// third-party embeddings provider through OmniRoute). Document import
/// isn't implemented — only conversations already in OmniChat are
/// searchable.
struct RAGView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \Conversation.createdAt, order: .reverse) private var conversations: [Conversation]

    @State private var embeddingModelID: String?
    @State private var embeddingModelError: String?
    @State private var indexingConversationID: PersistentIdentifier?
    @State private var indexingError: String?
    @State private var query = ""
    @State private var results: [ScoredPassage] = []
    @State private var selectedPassageIDs: Set<PersistentIdentifier> = []
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            searchField
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !results.isEmpty {
                        resultsSection
                        Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                    }
                    conversationsSection
                }
            }
        }
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
        .navigationTitle("Recherche")
        .task { await resolveEmbeddingModel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Passerelle", size: 10, color: OmniTheme.inkSoft)
            Text("Recherche locale")
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
            Text("mots-clés + vecteur, sur l'historique indexé — pas de documents importés pour l'instant.")
                .font(OmniTheme.serif(12).italic())
                .foregroundStyle(OmniTheme.inkSoft)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Rechercher dans l'historique indexé…", text: $query)
                    .textFieldStyle(.plain)
                    .font(OmniTheme.serif(14).italic())
                    .onSubmit { Task { await runSearch() } }
                if isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            if let embeddingModelError {
                Text(embeddingModelError)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
            }
            if let searchError {
                Text(searchError)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
            }
        }
        .padding(16)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                OmniTheme.label("\(results.count) passages", size: 10, color: OmniTheme.accent)
                Spacer()
                if !selectedPassageIDs.isEmpty {
                    Button("Joindre \(selectedPassageIDs.count) passage\(selectedPassageIDs.count > 1 ? "s" : "")") {
                        attachSelectedPassages()
                    }
                    .buttonStyle(.omniLink)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(results) { scored in
                resultRow(scored)
                Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            }
        }
    }

    private func resultRow(_ scored: ScoredPassage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if selectedPassageIDs.contains(scored.id) {
                    selectedPassageIDs.remove(scored.id)
                } else {
                    selectedPassageIDs.insert(scored.id)
                }
            } label: {
                Image(systemName: selectedPassageIDs.contains(scored.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedPassageIDs.contains(scored.id) ? OmniTheme.accent : OmniTheme.inkSoft)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(scored.passage.conversation?.title ?? "Conversation supprimée")
                        .font(OmniTheme.mono(9, weight: .semibold))
                        .foregroundStyle(OmniTheme.inkSoft)
                    Text(String(format: "%.2f", scored.score))
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.accent)
                }
                Text(scored.passage.text)
                    .font(OmniTheme.serif(13))
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            OmniTheme.label("Conversations indexables", size: 10, color: OmniTheme.inkSoft)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 8)
            if let indexingError {
                Text(indexingError)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            ForEach(conversations) { conversation in
                conversationRow(conversation)
                Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            }
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(OmniTheme.serif(13))
                    .foregroundStyle(OmniTheme.ink)
                Text("\(conversation.orderedMessages.count) messages · \(conversation.searchPassages.count) indexés")
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
            Spacer()
            if indexingConversationID == conversation.persistentModelID {
                ProgressView().controlSize(.small)
            } else {
                Button("Indexer") { Task { await index(conversation) } }
                    .buttonStyle(.omniLink)
                    .disabled(embeddingModelID == nil || conversation.orderedMessages.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func resolveEmbeddingModel() async {
        guard embeddingModelID == nil else { return }
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            let models = try await client.listEmbeddingModels()
            guard let first = models.first else {
                embeddingModelError = "Aucun modèle d'embedding disponible sur ce serveur."
                return
            }
            embeddingModelID = first.id
        } catch let error as OmniRouteError {
            embeddingModelError = error.userMessage
        } catch {
            embeddingModelError = error.localizedDescription
        }
    }

    private func index(_ conversation: Conversation) async {
        guard let embeddingModelID else { return }
        indexingError = nil
        indexingConversationID = conversation.persistentModelID
        defer { indexingConversationID = nil }
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            try await SearchIndexService.reindex(conversation, client: client, embeddingModel: embeddingModelID, context: context)
        } catch let error as OmniRouteError {
            indexingError = error.userMessage
        } catch {
            indexingError = error.localizedDescription
        }
    }

    private func runSearch() async {
        guard let embeddingModelID, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchError = nil
        isSearching = true
        defer { isSearching = false }
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            results = try await SearchIndexService.search(query: query, client: client, embeddingModel: embeddingModelID, context: context)
        } catch let error as OmniRouteError {
            searchError = error.userMessage
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func attachSelectedPassages() {
        let texts = results.filter { selectedPassageIDs.contains($0.id) }.map(\.passage.text)
        appEnvironment.pendingAttachedContext.append(contentsOf: texts)
        selectedPassageIDs.removeAll()
    }
}
