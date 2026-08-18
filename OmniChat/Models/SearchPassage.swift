import Foundation
import SwiftData

/// One locally-indexed, searchable passage of a conversation message — the
/// real vector comes from `/v1/embeddings`, indexed only when the user taps
/// "Indexer" (never automatically, since every indexing call has a real
/// cost and sends the passage's text to a third-party embeddings provider
/// through OmniRoute).
@Model
final class SearchPassage {
    var text: String
    var embedding: [Double]
    var embeddingModelID: String
    var indexedAt: Date
    var conversation: Conversation?

    init(text: String, embedding: [Double], embeddingModelID: String, indexedAt: Date = Date(), conversation: Conversation?) {
        self.text = text
        self.embedding = embedding
        self.embeddingModelID = embeddingModelID
        self.indexedAt = indexedAt
        self.conversation = conversation
    }
}
