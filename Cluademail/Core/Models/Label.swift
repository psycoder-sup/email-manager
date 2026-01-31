import Foundation
import SwiftData

// MARK: - Label Type

/// Classification of a Gmail label.
enum LabelType: String, Codable, Sendable {
    /// System-defined label (INBOX, SENT, etc.)
    case system
    /// User-created label
    case user
}

// MARK: - Label Visibility

/// Visibility setting for Gmail labels.
enum LabelVisibility: String, Codable, Sendable {
    /// Always show
    case show
    /// Always hide
    case hide
    /// Show only if there are unread messages
    case showIfUnread
}

// MARK: - Label Model

/// Gmail label representation (system and user labels).
/// System labels map to folder concepts; user labels are custom tags.
@Model
final class Label: Identifiable {

    // MARK: - Identity

    /// Identifier for Identifiable conformance (returns gmailLabelId)
    var id: String { gmailLabelId }

    /// Gmail label ID (unique)
    @Attribute(.unique) var gmailLabelId: String

    /// Display name
    var name: String

    // MARK: - Classification

    /// Label type (system or user)
    var type: LabelType

    // MARK: - Visibility

    /// Visibility in message list
    var messageListVisibility: LabelVisibility

    /// Visibility in label list
    var labelListVisibility: LabelVisibility

    // MARK: - Appearance

    /// Text color in hex format (e.g., "#000000")
    var textColor: String?

    /// Background color in hex format (e.g., "#ffffff")
    var backgroundColor: String?

    // MARK: - Relationships

    /// The account this label belongs to
    var account: Account?

    // MARK: - Static Constants

    /// Gmail system label IDs
    static let systemLabelIds: Set<String> = [
        "INBOX",
        "SENT",
        "DRAFT",
        "TRASH",
        "SPAM",
        "STARRED",
        "UNREAD",
        "IMPORTANT",
        "CATEGORY_PERSONAL",
        "CATEGORY_SOCIAL",
        "CATEGORY_PROMOTIONS",
        "CATEGORY_UPDATES"
    ]

    // MARK: - Initialization

    /// Creates a new Label.
    /// - Parameters:
    ///   - gmailLabelId: Gmail label ID
    ///   - name: Display name
    ///   - type: Label type (system or user)
    ///   - messageListVisibility: Visibility in message list
    ///   - labelListVisibility: Visibility in label list
    ///   - textColor: Text color in hex (optional)
    ///   - backgroundColor: Background color in hex (optional)
    init(
        gmailLabelId: String,
        name: String,
        type: LabelType = .user,
        messageListVisibility: LabelVisibility = .show,
        labelListVisibility: LabelVisibility = .show,
        textColor: String? = nil,
        backgroundColor: String? = nil
    ) {
        self.gmailLabelId = gmailLabelId
        self.name = name
        self.type = type
        self.messageListVisibility = messageListVisibility
        self.labelListVisibility = labelListVisibility
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
}
