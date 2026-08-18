import Foundation

/// What the chat composer currently sends to — plain text, or one of the
/// four media-generation kinds. Drives both the composer's placeholder/
/// dispatch and (via `mediaKind`) `ChatViewModel.sendMediaPrompt`.
enum ComposerMode: String, CaseIterable, Identifiable {
    case text, image, video, music, speech

    var id: String { rawValue }

    var mediaKind: MediaKind? {
        switch self {
        case .text: return nil
        case .image: return .image
        case .video: return .video
        case .music: return .music
        case .speech: return .speech
        }
    }

    var label: String {
        mediaKind?.label ?? "Texte"
    }

    var placeholder: String {
        mediaKind?.promptPlaceholder ?? "Écrire la suite…"
    }
}
