import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let daysRemaining: Int?

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? OmniTheme.accent : Color.clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(OmniTheme.serif(14, weight: .medium))
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(1)
                if let daysRemaining {
                    Text("supprimée définitivement dans \(daysRemaining) j")
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.warning)
                } else {
                    HStack(spacing: 6) {
                        Text(conversation.defaultModelID)
                            .foregroundStyle(OmniTheme.accent)
                        Text(conversation.createdAt.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(OmniTheme.inkSoft)
                    }
                    .font(OmniTheme.mono(9, weight: .medium))
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 15)
            .padding(.trailing, 18)
        }
    }
}
