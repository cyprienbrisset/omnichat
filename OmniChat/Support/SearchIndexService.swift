import Foundation
import SwiftData
import OmniRouteKit

/// One local search hit — the passage plus a hybrid score. `score` blends
/// real cosine similarity against the query's embedding with a plain
/// keyword-overlap ratio; this is a local, honest approximation and never
/// claims to be a specific technology (e.g. FTS5) this app doesn't actually
/// use.
struct ScoredPassage: Identifiable {
    let passage: SearchPassage
    let score: Double
    var id: PersistentIdentifier { passage.persistentModelID }
}

/// Local semantic + keyword search over conversation history, backed by
/// real `/v1/embeddings` vectors the user explicitly indexed. Document
/// import isn't implemented — only conversations already in OmniChat.
enum SearchIndexService {
    /// Deletes this conversation's existing passages and re-embeds every
    /// message fresh — a real `/v1/embeddings` call per message, so this
    /// only runs when the user explicitly asks for it.
    @MainActor
    static func reindex(
        _ conversation: Conversation,
        client: OmniRouteClient,
        embeddingModel: String,
        context: ModelContext
    ) async throws {
        for passage in conversation.searchPassages {
            context.delete(passage)
        }
        for message in conversation.orderedMessages where !message.content.isEmpty {
            let vector = try await client.createEmbedding(model: embeddingModel, input: message.content)
            context.insert(SearchPassage(
                text: message.content,
                embedding: vector,
                embeddingModelID: embeddingModel,
                conversation: conversation
            ))
        }
        try context.save()
    }

    /// Searches every locally-indexed passage across all conversations —
    /// only passages embedded with the same model as the query are
    /// comparable, so anything indexed with a different model is skipped
    /// rather than scored against an incompatible vector space.
    @MainActor
    static func search(
        query: String,
        client: OmniRouteClient,
        embeddingModel: String,
        context: ModelContext,
        limit: Int = 20
    ) async throws -> [ScoredPassage] {
        let queryVector = try await client.createEmbedding(model: embeddingModel, input: query)
        let allPassages = try context.fetch(FetchDescriptor<SearchPassage>())
        let queryTokens = tokenize(query)

        let scored: [ScoredPassage] = allPassages.compactMap { passage in
            guard passage.embeddingModelID == embeddingModel else { return nil }
            let vectorScore = cosineSimilarity(queryVector, passage.embedding)
            let passageTokens = tokenize(passage.text)
            let overlap = queryTokens.isEmpty
                ? 0
                : Double(queryTokens.intersection(passageTokens).count) / Double(queryTokens.count)
            return ScoredPassage(passage: passage, score: (vectorScore + overlap) / 2)
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    private static func tokenize(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
