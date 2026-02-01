import Foundation

// MARK: - Gmail Message DTOs

/// Gmail message response from the API.
struct GmailMessageDTO: Codable, Sendable {
    /// Message ID
    let id: String
    /// Thread ID
    let threadId: String
    /// Label IDs applied to this message
    let labelIds: [String]?
    /// Short snippet of message content
    let snippet: String?
    /// Internal date in milliseconds since epoch
    let internalDate: String?
    /// Message payload containing headers and body
    let payload: PayloadDTO?
}

/// Message payload structure.
struct PayloadDTO: Codable, Sendable {
    /// Email headers (From, To, Subject, etc.)
    let headers: [HeaderDTO]?
    /// Message body (for simple messages)
    let body: BodyDTO?
    /// Message parts (for multipart messages)
    let parts: [PartDTO]?
    /// MIME type of the payload
    let mimeType: String?
}

/// Email header (name/value pair).
struct HeaderDTO: Codable, Sendable {
    /// Header name (e.g., "From", "Subject")
    let name: String
    /// Header value
    let value: String
}

/// Message body content.
struct BodyDTO: Codable, Sendable {
    /// Size in bytes
    let size: Int?
    /// Base64URL encoded body data
    let data: String?
    /// Attachment ID (if body is an attachment)
    let attachmentId: String?
}

/// Message part (for multipart messages, can be recursive).
struct PartDTO: Codable, Sendable {
    /// Part ID
    let partId: String?
    /// MIME type of this part
    let mimeType: String?
    /// Filename (for attachments)
    let filename: String?
    /// Part body content
    let body: BodyDTO?
    /// Nested parts (for multipart/* content types)
    let parts: [PartDTO]?
}

// MARK: - Gmail Message List DTOs

/// Response from messages.list API.
struct GmailMessageListDTO: Codable, Sendable {
    /// List of messages (may only contain id and threadId)
    let messages: [GmailMessageSummaryDTO]?
    /// Token for next page of results
    let nextPageToken: String?
    /// Estimated total results
    let resultSizeEstimate: Int?
}

/// Summary message in list response (only IDs).
struct GmailMessageSummaryDTO: Codable, Sendable {
    /// Message ID
    let id: String
    /// Thread ID
    let threadId: String
}

// MARK: - Gmail Thread DTOs

/// Gmail thread response from the API.
struct GmailThreadDTO: Codable, Sendable {
    /// Thread ID
    let id: String
    /// History ID
    let historyId: String?
    /// Messages in this thread
    let messages: [GmailMessageDTO]?
}

/// Response from threads.list API.
struct GmailThreadListDTO: Codable, Sendable {
    /// List of threads
    let threads: [GmailThreadSummaryDTO]?
    /// Token for next page of results
    let nextPageToken: String?
    /// Estimated total results
    let resultSizeEstimate: Int?
}

/// Summary thread in list response.
struct GmailThreadSummaryDTO: Codable, Sendable {
    /// Thread ID
    let id: String
    /// Snippet preview
    let snippet: String?
    /// History ID
    let historyId: String?
}

// MARK: - Gmail Label DTOs

/// Gmail label response from the API.
struct GmailLabelDTO: Codable, Sendable {
    /// Label ID
    let id: String
    /// Label name
    let name: String
    /// Label type
    let type: String?
    /// Message list visibility
    let messageListVisibility: String?
    /// Label list visibility
    let labelListVisibility: String?
    /// Label color settings
    let color: GmailLabelColorDTO?
    /// Total messages with this label
    let messagesTotal: Int?
    /// Unread messages with this label
    let messagesUnread: Int?
}

/// Label color settings.
struct GmailLabelColorDTO: Codable, Sendable {
    /// Text color in hex format
    let textColor: String?
    /// Background color in hex format
    let backgroundColor: String?
}

/// Response from labels.list API.
struct GmailLabelListDTO: Codable, Sendable {
    /// List of labels
    let labels: [GmailLabelDTO]?
}

// MARK: - Gmail History DTOs

/// Response from history.list API for incremental sync.
struct GmailHistoryListDTO: Codable, Sendable {
    /// History records
    let history: [GmailHistoryDTO]?
    /// Next page token
    let nextPageToken: String?
    /// Current history ID
    let historyId: String?
}

/// A single history record.
struct GmailHistoryDTO: Codable, Sendable {
    /// History ID
    let id: String
    /// Messages added
    let messagesAdded: [GmailHistoryMessageDTO]?
    /// Messages deleted
    let messagesDeleted: [GmailHistoryMessageDTO]?
    /// Labels added to messages
    let labelsAdded: [GmailHistoryLabelDTO]?
    /// Labels removed from messages
    let labelsRemoved: [GmailHistoryLabelDTO]?
}

/// Message reference in history.
struct GmailHistoryMessageDTO: Codable, Sendable {
    /// The message
    let message: GmailMessageSummaryDTO
}

/// Label change in history.
struct GmailHistoryLabelDTO: Codable, Sendable {
    /// The message
    let message: GmailMessageSummaryDTO
    /// Labels that were added or removed
    let labelIds: [String]
}

// MARK: - Gmail Attachment DTOs

/// Response from attachments.get API.
struct GmailAttachmentDTO: Codable, Sendable {
    /// Attachment ID
    let attachmentId: String?
    /// Size in bytes
    let size: Int?
    /// Base64URL encoded attachment data
    let data: String?
}

// MARK: - Gmail Draft DTOs

/// Gmail draft response from the API.
struct GmailDraftDTO: Codable, Sendable {
    /// Draft ID
    let id: String
    /// The draft message
    let message: GmailMessageDTO
}

/// Response from drafts.list API.
struct GmailDraftListDTO: Codable, Sendable {
    /// List of drafts
    let drafts: [GmailDraftSummaryDTO]?
    /// Token for next page of results
    let nextPageToken: String?
    /// Estimated total results
    let resultSizeEstimate: Int?
}

/// Summary draft in list response.
struct GmailDraftSummaryDTO: Codable, Sendable {
    /// Draft ID
    let id: String
    /// Associated message (may be partial)
    let message: GmailMessageSummaryDTO?
}

// MARK: - Gmail Profile DTO

/// User profile response from the API.
struct GmailProfileDTO: Codable, Sendable {
    /// User's email address
    let emailAddress: String
    /// Total messages in mailbox
    let messagesTotal: Int?
    /// Total threads in mailbox
    let threadsTotal: Int?
    /// Current history ID for incremental sync
    let historyId: String?
}

// MARK: - Request DTOs

/// Request body for modifying message labels.
struct ModifyMessageRequest: Codable, Sendable {
    /// Label IDs to add
    let addLabelIds: [String]?
    /// Label IDs to remove
    let removeLabelIds: [String]?
}

/// Request body for creating/updating drafts.
struct DraftRequest: Codable, Sendable {
    /// The message to create as draft
    let message: DraftMessageRequest
}

/// Message content for draft creation.
struct DraftMessageRequest: Codable, Sendable {
    /// Base64URL encoded raw RFC 2822 message
    let raw: String
    /// Thread ID for replies
    let threadId: String?
}

/// Request body for sending messages.
struct SendMessageRequest: Codable, Sendable {
    /// Base64URL encoded raw RFC 2822 message
    let raw: String
    /// Thread ID for replies
    let threadId: String?
}
