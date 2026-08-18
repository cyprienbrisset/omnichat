import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.createdAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?

    var body: some View {
        NavigationSplitView {
            List(conversations, selection: $selectedConversation) { conversation in
                Text(conversation.title).tag(conversation)
            }
            .toolbar {
                ToolbarItem {
                    Button("Nouvelle conversation", systemImage: "plus", action: createConversation)
                }
                ToolbarItem {
                    SettingsLink {
                        Label("Réglages", systemImage: "gear")
                    }
                }
            }
        } detail: {
            if let selectedConversation {
                ChatView(conversation: selectedConversation)
            } else {
                ContentUnavailableView {
                    Label("Aucune conversation", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Crée une conversation pour commencer à discuter.")
                } actions: {
                    Button("Nouvelle conversation", action: createConversation)
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle("OmniChat")
            }
        }
        .onAppear {
            if selectedConversation == nil {
                selectedConversation = conversations.first
            }
        }
    }

    private func createConversation() {
        let conversation = Conversation(title: "Nouvelle conversation", defaultModelID: "auto")
        context.insert(conversation)
        selectedConversation = conversation
    }
}
