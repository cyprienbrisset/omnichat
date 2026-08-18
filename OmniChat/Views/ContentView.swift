import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \Conversation.createdAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?

    var body: some View {
        NavigationSplitView {
            HStack(spacing: 0) {
                RailView(onNewConversation: createConversation)
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
            if selectedConversation == nil {
                selectedConversation = conversations.first
            }
        }
    }

    private var registerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                OmniTheme.label("Registre")
                HStack(alignment: .firstTextBaseline) {
                    Text("Conversations")
                        .font(OmniTheme.serif(20, weight: .semibold))
                        .foregroundStyle(OmniTheme.ink)
                    Spacer()
                    Text(String(format: "%03d", conversations.count))
                        .font(OmniTheme.mono(12, weight: .semibold))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            }
            .padding(EdgeInsets(top: 20, leading: 18, bottom: 14, trailing: 18))

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            List(conversations, selection: $selectedConversation) { conversation in
                ConversationRow(
                    conversation: conversation,
                    isSelected: conversation.persistentModelID == selectedConversation?.persistentModelID
                )
                .tag(conversation)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(
                    conversation.persistentModelID == selectedConversation?.persistentModelID
                        ? OmniTheme.paperMuted
                        : OmniTheme.paper
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(OmniTheme.paper)

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

    private func createConversation() {
        let conversation = Conversation(title: "Nouvelle conversation", defaultModelID: "auto")
        context.insert(conversation)
        selectedConversation = conversation
    }
}

/// The dark, fixed-ink strip carrying the app's identity mark, primary
/// navigation action, and settings entry point.
private struct RailView: View {
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
                Text(conversation.createdAt, style: .relative)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
            .padding(.vertical, 8)
            .padding(.leading, 15)
            .padding(.trailing, 18)
        }
    }
}
