public struct ModelInfo: Decodable, Sendable, Equatable {
    public let id: String
    public let ownedBy: String?
    /// Present on `/v1/models` entries — distinguishes generation modality
    /// (`image`, `video`, `audio`, `embedding`, `rerank`, `moderation`, or
    /// absent for plain chat models). Confirmed against a live OmniRoute
    /// 3.8.49 instance, not documented in the API reference.
    public let type: String?
    /// Further narrows `type` — e.g. an `audio` entry's `subtype` is either
    /// `speech` (TTS, what this app needs) or `transcription` (STT).
    public let subtype: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
        case type
        case subtype
    }

    public init(id: String, ownedBy: String?, type: String? = nil, subtype: String? = nil) {
        self.id = id
        self.ownedBy = ownedBy
        self.type = type
        self.subtype = subtype
    }
}

struct ModelListResponse: Decodable {
    let data: [ModelInfo]
}
