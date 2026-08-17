import Foundation
import SwiftData

@Model
final class StoredEndpointProfile {
    @Attribute(.unique) var profileID: UUID
    var name: String
    var baseURLString: String

    init(profileID: UUID, name: String, baseURLString: String) {
        self.profileID = profileID
        self.name = name
        self.baseURLString = baseURLString
    }
}
