import Foundation
import OmniRouteKit

struct MediaFileStore {
    let directory: URL

    init(directory: URL = MediaFileStore.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OmniChat", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }

    func save(_ result: MediaGenerationResult, preferredExtension: String) async throws -> String {
        let data: Data
        switch result {
        case .remoteURL(let url):
            let (downloaded, _) = try await URLSession.shared.data(from: url)
            data = downloaded
        case .inlineData(let inline, _):
            data = inline
        }
        let fileName = "\(UUID().uuidString).\(preferredExtension)"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }
}
