import SwiftUI

/// Displays an unread indicator circle and star toggle button.
struct UnreadStarIndicator: View {
    let isRead: Bool
    let isStarred: Bool
    let onStarToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)

            Button(action: onStarToggle) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isStarred ? "Unstar" : "Star")
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UnreadStarIndicator(isRead: false, isStarred: true, onStarToggle: {})
        UnreadStarIndicator(isRead: true, isStarred: false, onStarToggle: {})
        UnreadStarIndicator(isRead: false, isStarred: false, onStarToggle: {})
    }
    .padding()
}
