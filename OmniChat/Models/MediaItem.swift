import Foundation
import SwiftData

@Model
final class MediaItem {
    var kind: String
    var prompt: String
    var modelID: String
    var fileName: String
    var createdAt: Date
    var conversation: Conversation?
    /// Inverse side of `Message.mediaItem` — see that property for why an
    /// explicit, paired relationship matters here.
    var message: Message?

    init(kind: String, prompt: String, modelID: String, fileName: String, createdAt: Date = Date()) {
        self.kind = kind
        self.prompt = prompt
        self.modelID = modelID
        self.fileName = fileName
        self.createdAt = createdAt
    }

    var fileURL: URL {
        MediaFileStore.defaultDirectory.appendingPathComponent(fileName)
    }
}
