import SwiftUI
import OmniRouteKit

/// A real browser for OmniRoute's management-gated memory store — reads
/// `Conversation.telemetryTotals`-style honesty: if the key lacks
/// management scope, this says so plainly instead of showing an empty
/// list that looks like "no memories exist yet."
struct MemoryView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var memories: [MemoryEntry] = []
    @State private var loadState: LoadState = .idle
    @State private var memoryPendingDeletion: MemoryEntry?
    @State private var deletionError: String?

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            content
        }
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
        .navigationTitle("Mémoire")
        .task { await refresh() }
        .alert(
            "Supprimer ce souvenir ?",
            isPresented: Binding(
                get: { memoryPendingDeletion != nil },
                set: { if !$0 { memoryPendingDeletion = nil } }
            ),
            presenting: memoryPendingDeletion
        ) { memory in
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { Task { await delete(memory) } }
        } message: { memory in
            Text(memory.content)
        }
        .alert(
            "Une erreur est survenue",
            isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(deletionError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Passerelle", size: 10, color: OmniTheme.inkSoft)
            HStack(alignment: .firstTextBaseline) {
                Text("Mémoire")
                    .font(OmniTheme.serif(24, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
                Spacer()
                if case .loaded = loadState {
                    Text(String(format: "%03d", memories.count))
                        .font(OmniTheme.mono(12, weight: .semibold))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OmniTheme.paper)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            centeredMessage("Chargement…")
        case .unavailable:
            centeredMessage("Cette clé n'a pas les droits de gestion nécessaires pour lire la mémoire. Teste-la depuis les Réglages.")
        case .failed(let message):
            centeredMessage(message)
        case .loaded:
            if memories.isEmpty {
                centeredMessage("Aucun souvenir stocké côté serveur pour l'instant.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(memories) { memory in
                            row(for: memory)
                            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func centeredMessage(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(OmniTheme.serif(13).italic())
                .foregroundStyle(OmniTheme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(for memory: MemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let type = memory.type {
                    OmniTheme.label(type, size: 8, color: OmniTheme.accent)
                }
                if let key = memory.key {
                    Text(key)
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
                Spacer()
                if let createdAt = memory.createdAt {
                    Text(createdAt, style: .date)
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            }
            Text(memory.content)
                .font(OmniTheme.serif(14))
                .foregroundStyle(OmniTheme.ink)
                .lineLimit(3)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Supprimer", systemImage: "trash", role: .destructive) {
                memoryPendingDeletion = memory
            }
        }
    }

    private func refresh() async {
        guard appEnvironment.managementAccessState == .available else {
            loadState = appEnvironment.managementAccessState == .unavailable ? .unavailable : .idle
            return
        }
        loadState = .loading
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            memories = try await client.listMemories()
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func delete(_ memory: MemoryEntry) async {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            try await client.deleteMemory(id: memory.id)
            memories.removeAll { $0.id == memory.id }
        } catch let error as OmniRouteError {
            deletionError = error.userMessage
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
