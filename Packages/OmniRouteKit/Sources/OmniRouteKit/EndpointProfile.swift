import Foundation

public struct EndpointProfile: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var baseURL: URL

    public init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }

    public static let defaultLocal = EndpointProfile(
        name: "Local",
        baseURL: URL(string: "http://localhost:20128/v1")!
    )
}
