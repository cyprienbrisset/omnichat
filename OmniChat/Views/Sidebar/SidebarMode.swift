import Foundation

/// Which slice of the conversation list the sidebar currently shows.
enum SidebarMode: String, CaseIterable, Identifiable {
    case conversations, archived, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversations: return "Conversations"
        case .archived: return "Archivées"
        case .trash: return "Corbeille"
        }
    }

    var systemImage: String {
        switch self {
        case .conversations: return "bubble.left.and.bubble.right"
        case .archived: return "archivebox"
        case .trash: return "trash"
        }
    }

    var emptyMessage: String {
        switch self {
        case .conversations: return "Ouvre une nouvelle conversation pour commencer à discuter avec OmniRoute."
        case .archived: return "Les conversations archivées apparaîtront ici."
        case .trash: return "Les conversations supprimées restent ici 30 jours avant suppression définitive."
        }
    }
}
