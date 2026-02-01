import SwiftUI

/// Displays an unread count in a styled capsule badge.
struct UnreadCountBadge: View {
    let count: Int

    private var displayText: String {
        count > 99 ? "99+" : "\(count)"
    }

    var body: some View {
        Text(displayText)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor, in: Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        UnreadCountBadge(count: 5)
        UnreadCountBadge(count: 42)
        UnreadCountBadge(count: 100)
    }
    .padding()
}
