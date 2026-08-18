import XCTest
import OmniRouteKit
@testable import OmniChat

final class MediaFileStoreTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func test_save_inlineData_writesFileWithExtension() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MediaFileStore(directory: directory)
        let payload = Data("fake-image-bytes".utf8)

        let fileName = try await store.save(.inlineData(payload, contentType: "image/png"), preferredExtension: "png")

        XCTAssertTrue(fileName.hasSuffix(".png"))
        let written = try Data(contentsOf: directory.appendingPathComponent(fileName))
        XCTAssertEqual(written, payload)
    }

    func test_save_remoteURL_downloadsAndWritesFile() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceData = Data("fake-video-bytes".utf8)
        let sourceFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try sourceData.write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        let store = MediaFileStore(directory: directory)
        let fileName = try await store.save(.remoteURL(sourceFile), preferredExtension: "mp4")

        XCTAssertTrue(fileName.hasSuffix(".mp4"))
        let written = try Data(contentsOf: directory.appendingPathComponent(fileName))
        XCTAssertEqual(written, sourceData)
    }
}
