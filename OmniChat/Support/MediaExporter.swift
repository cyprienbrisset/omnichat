import AppKit

/// Saves a copy of an already-downloaded media file to wherever the user
/// picks — the actual network download already happened when the media
/// was generated (`MediaFileStore`); this is the macOS "export a copy
/// somewhere I control" step, not a second network fetch.
enum MediaExporter {
    @MainActor
    static func exportCopy(of sourceURL: URL, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destinationURL = panel.url else { return }
            try? FileManager.default.removeItem(at: destinationURL)
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }
}
