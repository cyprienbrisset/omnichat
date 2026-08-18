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
                    Text(conversation.createdAt, style: .relative)
                        .font(OmniTheme.mono(9))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 15)
            .padding(.trailing, 18)
        }
    }
}
