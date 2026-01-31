import Foundation
import SwiftData

/// Groups related emails for thread/conversation view.
/// Stores aggregated metadata for efficient list display.
@Model
final class EmailThread: Identifiable {

    // MARK: - Identity

    /// Identifier for Identifiable conformance (returns threadId)
    var id: String { threadId }

    /// Gmail thread ID (unique)
    @Attribute(.unique) var threadId: String

    // MARK: - Display

    /// Thread subject (from first message)
    var subject: String

    /// Preview snippet (from latest message)
    var snippet: String

    // MARK: - Metadata

    /// Date of the most recent message
    var lastMessageDate: Date

    /// Total number of messages in thread
    var messageCount: Int

    /// Aggregated read state (true if all messages are read)
    var isRead: Bool

    /// Aggregated starred state (true if any message is starred)
    var isStarred: Bool

    /// Email addresses of all participants
    var participantEmails: [String]

    // MARK: - Relationships

    /// The account this thread belongs to
    var account: Account?

    // MARK: - Initialization

    /// Creates a new EmailThread.
    /// - Parameters:
    ///   - threadId: Gmail thread ID
    ///   - subject: Thread subject
    ///   - snippet: Content preview
    ///   - lastMessageDate: Date of most recent message
    ///   - messageCount: Total message count
    ///   - isRead: Aggregated read state
    ///   - isStarred: Aggregated starred state
    ///   - participantEmails: All participant email addresses
    init(
        threadId: String,
        subject: String,
        snippet: String,
        lastMessageDate: Date,
        messageCount: Int = 1,
        isRead: Bool = false,
        isStarred: Bool = false,
        participantEmails: [String] = []
    ) {
        self.threadId = threadId
        self.subject = subject
        self.snippet = snippet
        self.lastMessageDate = lastMessageDate
        self.messageCount = messageCount
        self.isRead = isRead
        self.isStarred = isStarred
        self.participantEmails = participantEmails
    }
}
