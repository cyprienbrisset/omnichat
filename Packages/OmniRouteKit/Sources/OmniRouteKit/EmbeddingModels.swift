import Foundation

/// Request body for `POST /v1/embeddings` — the plain string-input shape,
/// not the structured multimodal-item variant the reference also documents.
struct EmbeddingRequest: Encodable, Sendable {
    let model: String
    let input: String
}

/// One vector in an embeddings response — standard OpenAI-compatible shape
/// (undocumented in the API reference itself, but this response format has
/// been stable across the ecosystem for years and OmniRoute advertises
/// OpenAI compatibility).
struct EmbeddingVector: Decodable, Sendable {
    let embedding: [Double]
    let index: Int
}

struct EmbeddingListResponse: Decodable, Sendable {
    let data: [EmbeddingVector]
}
