import SwiftUI

/// Colored badge for account identification in email lists.
/// Generates consistent color from email hash.
struct AccountBadge: View {
    let email: String

    var body: some View {
        Text(username)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular.tint(badgeColor), in: .capsule)
    }

    /// Extracts username portion from email address
    private var username: String {
        email.components(separatedBy: "@").first ?? email
    }

    /// Generates a consistent color from email using stable djb2 hash
    private var badgeColor: Color {
        // djb2 hash algorithm - stable across app launches unlike hashValue
        var hash: UInt32 = 5381
        for char in email.utf8 {
            hash = ((hash &* 33) &+ UInt32(char))
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.7)
    }
}

#Preview {
    VStack(spacing: 8) {
        AccountBadge(email: "john@gmail.com")
        AccountBadge(email: "jane@outlook.com")
        AccountBadge(email: "bob@company.org")
    }
    .padding()
}
