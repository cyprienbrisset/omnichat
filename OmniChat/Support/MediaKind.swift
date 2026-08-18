import Foundation

enum MediaKind: String, CaseIterable, Identifiable {
    case image, video, music, speech

    var id: String { rawValue }

    var label: String {
        switch self {
        case .image: return "Image"
        case .video: return "Vidéo"
        case .music: return "Musique"
        case .speech: return "Voix"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .music: return "music.note"
        case .speech: return "waveform"
        }
    }

    var fileExtension: String {
        switch self {
        case .image: return "png"
        case .video: return "mp4"
        case .music, .speech: return "mp3"
        }
    }

    var promptPlaceholder: String {
        switch self {
        case .image: return "Décris l'image à générer…"
        case .video: return "Décris la vidéo à générer…"
        case .music: return "Décris la musique à générer…"
        case .speech: return "Texte à transformer en voix…"
        }
    }
}
