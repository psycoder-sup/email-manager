import Foundation

// MARK: - Gmail API Service Protocol

/// Protocol for Gmail API operations.
/// Enables testability and mocking.
protocol GmailAPIServiceProtocol: Sendable {

    // MARK: - Messages

    /// Lists messages matching the query.
    /// - Parameters:
    ///   - accountEmail: Account email for authentication
    ///   - query: Gmail search query (e.g., "is:unread", "from:user@example.com")
    ///   - labelIds: Filter by label IDs
    ///   - maxResults: Maximum messages per page (default: 100)
    ///   - pageToken: Token for pagination
    /// - Returns: List of message summaries and optional next page token
    func listMessages(
        accountEmail: String,
        query: String?,
        labelIds: [String]?,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> (messages: [GmailMessageSummaryDTO], nextPageToken: String?)

    /// Gets a single message with full content.
    /// - Parameters:
    ///   - accountEmail: Account email for authentication
    ///   - messageId: The message ID
    /// - Returns: Full message DTO
    func getMessage(
        accountEmail: String,
        messageId: String
    ) async throws -> GmailMessageDTO

    /// Batch fetches multiple messages.
    /// - Parameters:
    ///   - accountEmail: Account email for authentication
    ///   - messageIds: Array of message IDs to fetch
    /// - Returns: BatchResult with succeeded and failed items
    func batchGetMessages(
        accountEmail: String,
        messageIds: [String]
    ) async throws -> BatchResult<GmailMessageDTO>

    /// Modifies message labels.
    /// - Parameters:
    ///   - accountEmail: Account email for authentication
    ///   - messageId: The message ID
    ///   - addLabelIds: Labels to add
    ///   - removeLabelIds: Labels to remove
    /// - Returns: Updated message DTO
    func modifyMessage(
        accountEmail: String,
        messageId: String,
        addLabelIds: [String],
        removeLabelIds: [String]
    ) async throws -> GmailMessageDTO

    /// Moves a message to trash.
    func trashMessage(accountEmail: String, messageId: String) async throws

    /// Removes a message from trash.
    func untrashMessage(accountEmail: String, messageId: String) async throws

    // MARK: - Threads

    /// Lists threads matching the query.
    func listThreads(
        accountEmail: String,
        query: String?,
        labelIds: [String]?,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> (threads: [GmailThreadSummaryDTO], nextPageToken: String?)

    /// Gets a single thread with all messages.
    func getThread(
        accountEmail: String,
        threadId: String
    ) async throws -> GmailThreadDTO

    // MARK: - Drafts

    /// Creates a new draft.
    /// - Parameters:
    ///   - accountEmail: Account email for authentication
    ///   - to: Recipients
    ///   - cc: CC recipients
    ///   - bcc: BCC recipients
    ///   - subject: Email subject
    ///   - body: Email body content
    ///   - isHtml: Whether body is HTML
    ///   - replyToMessageId: Message ID if this is a reply
    ///   - attachments: Attachment data
    /// - Returns: Created draft DTO
    func createDraft(
        accountEmail: String,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        body: String,
        isHtml: Bool,
        replyToMessageId: String?,
        attachments: [AttachmentData]
    ) async throws -> GmailDraftDTO

    /// Updates an existing draft.
    func updateDraft(
        accountEmail: String,
        draftId: String,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        body: String,
        isHtml: Bool,
        attachments: [AttachmentData]
    ) async throws -> GmailDraftDTO

    /// Deletes a draft.
    func deleteDraft(accountEmail: String, draftId: String) async throws

    /// Gets a draft by ID.
    func getDraft(accountEmail: String, draftId: String) async throws -> GmailDraftDTO

    // MARK: - Sending (User-Only, NOT for MCP)

    /// Sends an email directly.
    /// NOTE: This method should ONLY be called from user-initiated actions (UI),
    /// never from MCP tools. MCP should use createDraft instead.
    func sendMessage(
        accountEmail: String,
        to: [String],
        cc: [String],
        bcc: [String],
        subject: String,
        body: String,
        isHtml: Bool,
        replyToMessageId: String?,
        attachments: [AttachmentData]
    ) async throws -> GmailMessageDTO

    // MARK: - Attachments

    /// Downloads an attachment.
    /// - Returns: Raw attachment data
    func getAttachment(
        accountEmail: String,
        messageId: String,
        attachmentId: String
    ) async throws -> Data

    // MARK: - Sync

    /// Gets history changes since a given history ID.
    func getHistory(
        accountEmail: String,
        startHistoryId: String,
        historyTypes: [String]?
    ) async throws -> GmailHistoryListDTO

    /// Gets the user's profile with current history ID.
    func getProfile(accountEmail: String) async throws -> GmailProfileDTO
}

// MARK: - Batch Result Types

/// Result of a batch operation with partial success support.
struct BatchResult<T: Sendable>: Sendable {
    /// Successfully processed items
    let succeeded: [T]

    /// Failed items with error details
    let failed: [BatchFailure]

    /// Whether any items failed
    var hasFailures: Bool { !failed.isEmpty }

    /// Number of successful items
    var successCount: Int { succeeded.count }

    /// Number of failed items
    var failureCount: Int { failed.count }

    /// Total items attempted
    var totalCount: Int { successCount + failureCount }
}

/// Details of a failed batch item.
struct BatchFailure: Sendable {
    /// Index in the original request array
    let requestIndex: Int

    /// The ID of the item that failed
    let itemId: String

    /// HTTP status code of the failure
    let statusCode: Int

    /// The error that occurred
    let error: APIError
}

// MARK: - Attachment Data

/// Attachment data for sending/creating drafts.
struct AttachmentData: Sendable {
    /// Filename with extension
    let filename: String

    /// MIME type (e.g., "application/pdf")
    let mimeType: String

    /// Raw file data
    let data: Data
}
