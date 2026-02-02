import SwiftUI

/// Displays a label as a colored badge.
struct LabelBadgeView: View {
    let label: Label

    var body: some View {
        Text(displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(textColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Returns the display name (last component for nested labels).
    private var displayName: String {
        label.name.components(separatedBy: "/").last ?? label.name
    }

    /// Returns the background color from hex, defaulting to gray.
    private var backgroundColor: Color {
        Color(hex: label.backgroundColor) ?? .secondary.opacity(0.3)
    }

    /// Returns the text color from hex, defaulting to primary.
    private var textColor: Color {
        Color(hex: label.textColor) ?? .primary
    }
}

/// Displays a label badge from raw data (for search results that may not have Label model).
struct LabelBadgeFromIdView: View {
    let labelId: String
    let labelName: String?
    let backgroundColor: String?
    let textColor: String?

    var body: some View {
        Text(displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgColor)
            .foregroundStyle(fgColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var displayName: String {
        if let name = labelName {
            return name.components(separatedBy: "/").last ?? name
        }
        // Prettify system label IDs
        switch labelId {
        case "INBOX": return "Inbox"
        case "SENT": return "Sent"
        case "DRAFT": return "Draft"
        case "TRASH": return "Trash"
        case "SPAM": return "Spam"
        case "STARRED": return "Starred"
        case "IMPORTANT": return "Important"
        default:
            // Handle category labels
            if labelId.hasPrefix("CATEGORY_") {
                return labelId.replacingOccurrences(of: "CATEGORY_", with: "").capitalized
            }
            return labelId
        }
    }

    private var bgColor: Color {
        Color(hex: backgroundColor) ?? .secondary.opacity(0.3)
    }

    private var fgColor: Color {
        Color(hex: textColor) ?? .primary
    }
}

#Preview("Label Badge") {
    HStack {
        LabelBadgeFromIdView(
            labelId: "INBOX",
            labelName: nil,
            backgroundColor: "#4285F4",
            textColor: "#FFFFFF"
        )

        LabelBadgeFromIdView(
            labelId: "custom_label",
            labelName: "Work/Projects",
            backgroundColor: "#34A853",
            textColor: "#FFFFFF"
        )

        LabelBadgeFromIdView(
            labelId: "IMPORTANT",
            labelName: nil,
            backgroundColor: nil,
            textColor: nil
        )
    }
    .padding()
}
