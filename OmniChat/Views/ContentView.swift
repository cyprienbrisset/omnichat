import SwiftUI
import SwiftData

private enum SidebarMode: String, CaseIterable, Identifiable {
    case conversations, archived, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversations: return "Conversations"
        case .archived: return "Archivées"
        case .trash: return "Corbeille"
        }
    }

    var systemImage: String {
        switch self {
        case .conversations: return "bubble.left.and.bubble.right"
        case .archived: return "archivebox"
        case .trash: return "trash"
        }
    }

    var emptyMessage: String {
        switch self {
        case .conversations: return "Ouvre une nouvelle conversation pour commencer à discuter avec OmniRoute."
        case .archived: return "Les conversations archivées apparaîtront ici."
        case .trash: return "Les conversations supprimées restent ici 30 jours avant suppression définitive."
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \Conversation.createdAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?
    @State private var sidebarMode: SidebarMode = .conversations
    @State private var conversationPendingPermanentDeletion: Conversation?
    @State private var conversationPendingRename: Conversation?
    @State private var renameText = ""
    @State private var operationError: String?

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
        NavigationSplitView {
            HStack(spacing: 0) {
                RailView(mode: $sidebarMode, onNewConversation: createConversation)
                registerPanel
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 520)
        } detail: {
            if let selectedConversation {
                ChatView(conversation: selectedConversation)
            } else {
                emptyState
            }
        }
        .onAppear {
            purgeExpiredTrash()
            if selectedConversation == nil {
                selectedConversation = activeConversations.first
            }
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
                    ForEach(visibleConversations) { conversation in
                        row(for: conversation)
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

/// The dark, fixed-ink strip carrying the app's identity mark, primary
/// navigation action, sidebar mode switcher, and settings entry point.
private struct RailView: View {
    @Binding var mode: SidebarMode
    let onNewConversation: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // The real macOS traffic lights already occupy this corner once
            // the window uses a hidden title bar — no decorative stand-ins.
            Spacer().frame(height: 28)

            Text("O")
                .font(OmniTheme.serif(14, weight: .semibold))
                .foregroundStyle(OmniTheme.railText)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(OmniTheme.railText.opacity(0.4), lineWidth: 1)
                )

            Button(action: onNewConversation) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OmniTheme.railText)
            }
            .buttonStyle(.plain)
            .help("Nouvelle conversation")

            Rectangle().fill(OmniTheme.railText.opacity(0.2)).frame(width: 20, height: 1)

            ForEach([SidebarMode.conversations, .archived, .trash]) { candidate in
                Button {
                    mode = candidate
                } label: {
                    Image(systemName: candidate.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mode == candidate ? OmniTheme.accent : OmniTheme.railText.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(candidate.title)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(OmniTheme.railText.opacity(0.75))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        // Wide enough to fully contain macOS's real traffic-light cluster
        // (~76pt from the left edge) so the green button doesn't spill onto
        // the sidebar's cream background behind it.
        .frame(width: 84)
        .frame(maxHeight: .infinity)
        .background(OmniTheme.rail)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let daysRemaining: Int?

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? OmniTheme.accent : Color.clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(OmniTheme.serif(14, weight: .medium))
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(1)
                if let daysRemaining {
                    Text("supprimée définitivement dans \(daysRemaining) j")
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.warning)
                } else {
                    Text(conversation.createdAt, style: .relative)
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 15)
            .padding(.trailing, 18)
        }
    }
}
