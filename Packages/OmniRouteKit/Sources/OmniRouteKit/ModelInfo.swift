public struct ModelInfo: Decodable, Sendable, Equatable {
    public let id: String
    public let ownedBy: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
    }

    public init(id: String, ownedBy: String?) {
        self.id = id
        self.ownedBy = ownedBy
    }
}

struct ModelListResponse: Decodable {
    let data: [ModelInfo]
}
