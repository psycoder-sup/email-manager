import Foundation
import SwiftData

/// Full email representation with all Gmail metadata.
/// Body content is optional to support lazy loading.
@Model
final class Email: Identifiable {

    // MARK: - Identity

    /// Identifier for Identifiable conformance (returns gmailId)
    var id: String { gmailId }

    /// Gmail message ID (unique across all messages)
    @Attribute(.unique) var gmailId: String

    /// Gmail thread ID for conversation grouping
    var threadId: String

    /// Gmail draft ID (only set for drafts, nil for regular messages)
    /// When a draft is edited in Gmail, message.id changes but draft.id remains stable
    var draftId: String?

    // MARK: - Content

    /// Email subject line
    var subject: String

    /// Short preview of email content
    var snippet: String

    /// Plain text body (nil if not yet loaded)
    var bodyText: String?

    /// HTML body (nil if not yet loaded)
    var bodyHtml: String?

    // MARK: - Sender

    /// Sender's email address
    var fromAddress: String

    /// Sender's display name (optional)
    var fromName: String?

    // MARK: - Recipients

    /// To recipients
    var toAddresses: [String]

    /// CC recipients
    var ccAddresses: [String]

    /// BCC recipients
    var bccAddresses: [String]

    // MARK: - Metadata

    /// Email date/time
    var date: Date

    /// Whether the email has been read
    var isRead: Bool

    /// Whether the email is starred
    var isStarred: Bool

    /// Gmail label IDs applied to this email
    var labelIds: [String]

    // MARK: - Relationships

    /// The account this email belongs to
    var account: Account?

    /// Attachments for this email (cascade delete)
    @Relationship(deleteRule: .cascade, inverse: \Attachment.email)
    var attachments: [Attachment] = []

    // MARK: - Computed Properties

    /// Whether the email is in the inbox
    var isInInbox: Bool {
        labelIds.contains("INBOX")
    }

    /// Whether the email is in trash
    var isInTrash: Bool {
        labelIds.contains("TRASH")
    }

    /// Whether the email is in spam
    var isInSpam: Bool {
        labelIds.contains("SPAM")
    }

    /// Whether the email is a draft
    var isDraft: Bool {
        labelIds.contains("DRAFT")
    }

    /// Whether the email is in sent folder
    var isSent: Bool {
        labelIds.contains("SENT")
    }

    // MARK: - Initialization

    /// Creates a new Email.
    /// - Parameters:
    ///   - gmailId: Gmail message ID
    ///   - threadId: Gmail thread ID
    ///   - draftId: Gmail draft ID (only for drafts)
    ///   - subject: Email subject
    ///   - snippet: Content preview
    ///   - fromAddress: Sender's email address
    ///   - fromName: Sender's display name (optional)
    ///   - toAddresses: To recipients
    ///   - ccAddresses: CC recipients
    ///   - bccAddresses: BCC recipients
    ///   - date: Email date
    ///   - isRead: Read status
    ///   - isStarred: Starred status
    ///   - labelIds: Gmail label IDs
    init(
        gmailId: String,
        threadId: String,
        draftId: String? = nil,
        subject: String,
        snippet: String,
        fromAddress: String,
        fromName: String? = nil,
        toAddresses: [String] = [],
        ccAddresses: [String] = [],
        bccAddresses: [String] = [],
        date: Date,
        isRead: Bool = false,
        isStarred: Bool = false,
        labelIds: [String] = []
    ) {
        self.gmailId = gmailId
        self.threadId = threadId
        self.draftId = draftId
        self.subject = subject
        self.snippet = snippet
        self.bodyText = nil
        self.bodyHtml = nil
        self.fromAddress = fromAddress
        self.fromName = fromName
        self.toAddresses = toAddresses
        self.ccAddresses = ccAddresses
        self.bccAddresses = bccAddresses
        self.date = date
        self.isRead = isRead
        self.isStarred = isStarred
        self.labelIds = labelIds
    }
}
