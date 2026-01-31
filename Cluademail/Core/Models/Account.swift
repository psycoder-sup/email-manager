import Foundation
import SwiftData

/// Represents a Gmail account linked to the app.
/// Manages email and label relationships with cascade delete.
@Model
final class Account: Identifiable {

    // MARK: - Identity

    /// Unique identifier for the account
    @Attribute(.unique) var id: UUID

    /// Gmail email address
    var email: String

    // MARK: - Profile

    /// User's display name
    var displayName: String

    /// URL to user's profile image (optional)
    var profileImageURL: String?

    // MARK: - State

    /// Whether the account is enabled for syncing
    var isEnabled: Bool

    /// Last successful sync date
    var lastSyncDate: Date?

    /// Gmail history ID for incremental sync
    var historyId: String?

    // MARK: - Relationships

    /// All emails belonging to this account (cascade delete)
    @Relationship(deleteRule: .cascade, inverse: \Email.account)
    var emails: [Email] = []

    /// All labels belonging to this account (cascade delete)
    @Relationship(deleteRule: .cascade, inverse: \Label.account)
    var labels: [Label] = []

    /// All email threads belonging to this account (cascade delete)
    @Relationship(deleteRule: .cascade, inverse: \EmailThread.account)
    var threads: [EmailThread] = []

    // MARK: - Initialization

    /// Creates a new Account.
    /// - Parameters:
    ///   - email: Gmail email address
    ///   - displayName: User's display name
    init(email: String, displayName: String) {
        self.id = UUID()
        self.email = email
        self.displayName = displayName
        self.profileImageURL = nil
        self.isEnabled = true
        self.lastSyncDate = nil
        self.historyId = nil
    }
}
