import SwiftUI
import SwiftData

private enum DetailOverlay {
    case gallery
    case memory
    case mcp
    case rag
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \Conversation.createdAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?
    @State private var sidebarMode: SidebarMode = .conversations
    @State private var detailOverlay: DetailOverlay?
    @State private var conversationPendingPermanentDeletion: Conversation?
    @State private var conversationPendingRename: Conversation?
    @State private var renameText = ""
    @State private var operationError: String?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var activeConversations: [Conversation] {
        conversations.filter { $0.deletedAt == nil && !$0.isArchived }
    }

    private var archivedConversations: [Conversation] {
        conversations.filter { $0.deletedAt == nil && $0.isArchived }
    }

    private var trashedConversations: [Conversation] {
        conversations.filter { $0.deletedAt != nil }
    }

    private var visibleConversations: [Conversation] {
        switch sidebarMode {
        case .conversations: return activeConversations
        case .archived: return archivedConversations
        case .trash: return trashedConversations
        }
    }

    var body: some View {
        // A plain HStack instead of NavigationSplitView: the system split
        // view draws its own translucent-sidebar shadow/divider (meant for
        // a vibrancy background), which reads as a floating card hovering
        // over flat opaque cream — this stays one seamless surface instead.
        HStack(spacing: 0) {
            RailView(
                mode: Binding(get: { sidebarMode }, set: { sidebarMode = $0; detailOverlay = nil }),
                isGallerySelected: detailOverlay == .gallery,
                isMemorySelected: detailOverlay == .memory,
                isMCPSelected: detailOverlay == .mcp,
                isRAGSelected: detailOverlay == .rag,
                catalogSummary: appEnvironment.catalogSummary,
                onNewConversation: createConversation,
                onSelectGallery: { detailOverlay = .gallery },
                onSelectMemory: { detailOverlay = .memory },
                onSelectMCP: { detailOverlay = .mcp },
                onSelectRAG: { detailOverlay = .rag }
            )
            registerPanel
                .frame(width: 300)

            Rectangle().fill(OmniTheme.hairline).frame(width: 1)

            Group {
                switch detailOverlay {
                case .gallery:
                    GalleryView()
                case .memory:
                    MemoryView()
                case .mcp:
                    MCPView()
                case .rag:
                    RAGView()
                case nil:
                    if let selectedConversation {
                        ChatView(conversation: selectedConversation)
                    } else {
                        emptyState
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            purgeExpiredTrash()
            if selectedConversation == nil {
                selectedConversation = activeConversations.first
            }
        }
        .onChange(of: selectedConversation) { _, newValue in
            if newValue != nil { detailOverlay = nil }
        }
        .sheet(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { hasCompletedOnboarding = !$0 })) {
            OnboardingView(onFinish: { hasCompletedOnboarding = true })
        }
        .alert(
            "Supprimer définitivement ?",
            isPresented: Binding(
                get: { conversationPendingPermanentDeletion != nil },
                set: { if !$0 { conversationPendingPermanentDeletion = nil } }
            ),
            presenting: conversationPendingPermanentDeletion
        ) { conversation in
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { permanentlyDelete(conversation) }
        } message: { conversation in
            Text("« \(conversation.title) » et tous ses messages seront supprimés définitivement. Cette action est irréversible.")
        }
        .alert(
            "Renommer la conversation",
            isPresented: Binding(
                get: { conversationPendingRename != nil },
                set: { if !$0 { conversationPendingRename = nil } }
            ),
            presenting: conversationPendingRename
        ) { conversation in
            TextField("Titre", text: $renameText)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") { applyRename(to: conversation) }
        } message: { _ in
            Text("Choisis un nouveau titre.")
        }
        .alert(
            "Une erreur est survenue",
            isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(operationError ?? "")
        }
    }

    private var registerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                OmniTheme.label("Registre")
                HStack(alignment: .firstTextBaseline) {
                    Text(sidebarMode.title)
                        .font(OmniTheme.serif(20, weight: .semibold))
                        .foregroundStyle(OmniTheme.ink)
                    Spacer()
                    Text(String(format: "%03d", visibleConversations.count))
                        .font(OmniTheme.mono(12, weight: .semibold))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            }
            .padding(EdgeInsets(top: 20, leading: 18, bottom: 14, trailing: 18))

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            if visibleConversations.isEmpty {
                Text(sidebarMode.emptyMessage)
                    .font(OmniTheme.serif(12).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
                    .padding(18)
                Spacer()
            } else {
                List(selection: $selectedConversation) {
                    if sidebarMode == .conversations {
                        ForEach(dateSections(of: visibleConversations), id: \.label) { section in
                            Section {
                                ForEach(section.conversations) { conversation in
                                    row(for: conversation)
                                }
                            } header: {
                                OmniTheme.label(section.label, size: 9, color: OmniTheme.inkSoft)
                            }
                        }
                    } else {
                        ForEach(visibleConversations) { conversation in
                            row(for: conversation)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(OmniTheme.paper)
            }

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            HStack(spacing: 6) {
                Circle().fill(OmniTheme.success).frame(width: 5, height: 5)
                Text(appEnvironment.activeProfile.baseURL.host ?? appEnvironment.activeProfile.baseURL.absoluteString)
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.inkSoft)
                    .lineLimit(1)
                // Only shown once measured via /api/monitoring/health — never
                // a placeholder count when the key lacks management rights.
                if let health = appEnvironment.monitoringHealth {
                    Spacer()
                    Text("\(health.activeCount)/\(health.catalogCount) actifs")
                        .font(OmniTheme.mono(10))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
                Spacer()
            }
            .padding(EdgeInsets(top: 10, leading: 18, bottom: 12, trailing: 18))
        }
        .background(OmniTheme.paper)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("O")
                .font(OmniTheme.serif(20, weight: .semibold))
                .foregroundStyle(OmniTheme.railText)
                .frame(width: 44, height: 44)
                .background(OmniTheme.rail)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text("Aucune conversation")
                .font(OmniTheme.serif(20, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)

            Text("Ouvre une nouvelle conversation pour commencer à discuter avec OmniRoute.")
                .font(OmniTheme.serif(13).italic())
                .foregroundStyle(OmniTheme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Nouvelle conversation", action: createConversation)
                .buttonStyle(.omniPrimary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
        .navigationTitle("OmniChat")
    }

    @ViewBuilder
    private func row(for conversation: Conversation) -> some View {
        ConversationRow(
            conversation: conversation,
            isSelected: conversation.persistentModelID == selectedConversation?.persistentModelID,
            daysRemaining: sidebarMode == .trash ? daysRemainingInTrash(conversation) : nil
        )
        .tag(conversation)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(
            conversation.persistentModelID == selectedConversation?.persistentModelID
                ? OmniTheme.paperMuted
                : OmniTheme.paper
        )
        .contextMenu {
            switch sidebarMode {
            case .conversations, .archived:
                Button("Renommer", systemImage: "pencil") {
                    renameText = conversation.title
                    conversationPendingRename = conversation
                }
                if conversation.isArchived {
                    Button("Désarchiver", systemImage: "arrow.uturn.backward") {
                        conversation.isArchived = false
                        saveOrReportError()
                    }
                } else {
                    Button("Archiver", systemImage: "archivebox") {
                        conversation.isArchived = true
                        saveOrReportError()
                    }
                }
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    moveToTrash(conversation)
                }
            case .trash:
                Button("Restaurer", systemImage: "arrow.uturn.backward") {
                    restore(conversation)
                }
                Button("Supprimer définitivement", systemImage: "trash.slash", role: .destructive) {
                    conversationPendingPermanentDeletion = conversation
                }
            }
        }
    }

    private struct DateSection {
        let label: String
        let conversations: [Conversation]
    }

    /// Groups by real `createdAt` day — "Aujourd'hui"/"Hier"/an explicit
    /// date beyond that — relying on the incoming list already being sorted
    /// newest-first (the `@Query` sort), so same-day items stay contiguous.
    private func dateSections(of items: [Conversation]) -> [DateSection] {
        let calendar = Calendar.current
        var sections: [DateSection] = []
        for conversation in items {
            let label: String
            if calendar.isDateInToday(conversation.createdAt) {
                label = "Aujourd’hui"
            } else if calendar.isDateInYesterday(conversation.createdAt) {
                label = "Hier"
            } else {
                label = conversation.createdAt.formatted(.dateTime.day().month(.wide))
            }
            if let last = sections.last, last.label == label {
                sections[sections.count - 1] = DateSection(label: label, conversations: last.conversations + [conversation])
            } else {
                sections.append(DateSection(label: label, conversations: [conversation]))
            }
        }
        return sections
    }

    private func daysRemainingInTrash(_ conversation: Conversation) -> Int? {
        guard let deletedAt = conversation.deletedAt else { return nil }
        let expiryDate = Calendar.current.date(byAdding: .day, value: Conversation.trashRetentionDays, to: deletedAt) ?? deletedAt
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        return max(days, 0)
    }

    private func createConversation() {
        let conversation = Conversation(title: "Nouvelle conversation", defaultModelID: "auto")
        context.insert(conversation)
        selectedConversation = conversation
        sidebarMode = .conversations
    }

    private func moveToTrash(_ conversation: Conversation) {
        conversation.deletedAt = Date()
        if selectedConversation?.persistentModelID == conversation.persistentModelID {
            selectedConversation = activeConversations.first { $0.persistentModelID != conversation.persistentModelID }
        }
        saveOrReportError()
    }

    private func restore(_ conversation: Conversation) {
        conversation.deletedAt = nil
        conversation.isArchived = false
        saveOrReportError()
    }

    private func permanentlyDelete(_ conversation: Conversation) {
        if selectedConversation?.persistentModelID == conversation.persistentModelID {
            selectedConversation = nil
        }
        context.delete(conversation)
        saveOrReportError()
    }

    private func applyRename(to conversation: Conversation) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversation.title = trimmed
        saveOrReportError()
    }

    /// Permanently removes conversations that have sat in the trash past the
    /// retention window — the same "keep briefly, then purge" shape as
    /// `DiagnosticLogger.purgeExpired(now:)`, just for conversations.
    private func purgeExpiredTrash() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Conversation.trashRetentionDays, to: Date()) ?? .distantPast
        let expired = conversations.filter { conversation in
            guard let deletedAt = conversation.deletedAt else { return false }
            return deletedAt < cutoff
        }
        guard !expired.isEmpty else { return }
        for conversation in expired {
            context.delete(conversation)
        }
        saveOrReportError()
    }

    private func saveOrReportError() {
        do {
            try context.save()
        } catch {
            operationError = error.localizedDescription
        }
    }
}
