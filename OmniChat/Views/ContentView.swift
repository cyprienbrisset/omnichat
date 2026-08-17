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
                Button("Nouvelle conversation", systemImage: "plus", action: createConversation)
            }
        } detail: {
            if let selectedConversation {
                ChatView(conversation: selectedConversation)
            } else {
                ContentUnavailableView("Sélectionne ou crée une conversation", systemImage: "bubble.left.and.bubble.right")
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
