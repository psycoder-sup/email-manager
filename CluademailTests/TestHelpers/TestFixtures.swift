import Foundation
@testable import Cluademail

/// Factory methods for creating test data.
/// Use these to create consistent test fixtures across tests.
enum TestFixtures {

    // MARK: - Account Fixtures

    /// Creates a test Account with optional customization.
    /// - Parameters:
    ///   - email: Email address (default: "test@gmail.com")
    ///   - displayName: Display name (default: "Test User")
    /// - Returns: A configured Account
    static func makeAccount(
        email: String = "test@gmail.com",
        displayName: String = "Test User"
    ) -> Account {
        Account(
            email: email,
            displayName: displayName
        )
    }

    /// Creates multiple test accounts.
    /// - Parameter count: Number of accounts to create
    /// - Returns: Array of accounts with sequential email addresses
    static func makeAccounts(count: Int) -> [Account] {
        (0..<count).map { index in
            makeAccount(
                email: "user\(index)@gmail.com",
                displayName: "User \(index)"
            )
        }
    }

    // MARK: - Email Fixtures

    /// Creates a test Email with optional customization.
    /// - Parameters:
    ///   - gmailId: Gmail message ID (default: generated UUID string)
    ///   - threadId: Gmail thread ID (default: generated UUID string)
    ///   - draftId: Gmail draft ID (default: nil)
    ///   - subject: Email subject (default: "Test Subject")
    ///   - snippet: Email snippet (default: "Test email content...")
    ///   - fromAddress: Sender's email address (default: "sender@gmail.com")
    ///   - fromName: Sender's name (default: "Test Sender")
    ///   - toAddresses: Recipients (default: ["recipient@gmail.com"])
    ///   - date: Email date (default: now)
    ///   - isRead: Read status (default: false)
    ///   - isStarred: Starred status (default: false)
    ///   - labelIds: Label IDs (default: ["INBOX"])
    /// - Returns: A configured Email
    static func makeEmail(
        gmailId: String = UUID().uuidString,
        threadId: String = UUID().uuidString,
        draftId: String? = nil,
        subject: String = "Test Subject",
        snippet: String = "Test email content...",
        fromAddress: String = "sender@gmail.com",
        fromName: String? = "Test Sender",
        toAddresses: [String] = ["recipient@gmail.com"],
        date: Date = Date(),
        isRead: Bool = false,
        isStarred: Bool = false,
        labelIds: [String] = ["INBOX"]
    ) -> Email {
        Email(
            gmailId: gmailId,
            threadId: threadId,
            draftId: draftId,
            subject: subject,
            snippet: snippet,
            fromAddress: fromAddress,
            fromName: fromName,
            toAddresses: toAddresses,
            date: date,
            isRead: isRead,
            isStarred: isStarred,
            labelIds: labelIds
        )
    }

    /// Creates a test draft Email.
    /// - Parameters:
    ///   - gmailId: Gmail message ID (default: generated UUID string)
    ///   - threadId: Gmail thread ID (default: generated UUID string)
    ///   - draftId: Gmail draft ID (default: generated UUID string)
    ///   - subject: Email subject (default: "Draft Subject")
    /// - Returns: A configured draft Email
    static func makeDraftEmail(
        gmailId: String = UUID().uuidString,
        threadId: String = UUID().uuidString,
        draftId: String = UUID().uuidString,
        subject: String = "Draft Subject"
    ) -> Email {
        makeEmail(
            gmailId: gmailId,
            threadId: threadId,
            draftId: draftId,
            subject: subject,
            labelIds: ["DRAFT"]
        )
    }

    /// Creates multiple test emails.
    /// - Parameter count: Number of emails to create
    /// - Returns: Array of emails with sequential subjects
    static func makeEmails(count: Int) -> [Email] {
        (0..<count).map { index in
            makeEmail(
                subject: "Email \(index)",
                snippet: "This is email number \(index)"
            )
        }
    }

    // MARK: - EmailThread Fixtures

    /// Creates a test EmailThread with optional customization.
    /// - Parameters:
    ///   - threadId: Gmail thread ID (default: generated UUID string)
    ///   - subject: Thread subject (default: "Test Thread")
    ///   - snippet: Preview snippet (default: "Test thread content...")
    ///   - lastMessageDate: Last message date (default: now)
    ///   - messageCount: Message count (default: 1)
    ///   - isRead: Read state (default: false)
    ///   - isStarred: Starred state (default: false)
    ///   - participantEmails: Participant emails (default: ["user@gmail.com"])
    /// - Returns: A configured EmailThread
    static func makeEmailThread(
        threadId: String = UUID().uuidString,
        subject: String = "Test Thread",
        snippet: String = "Test thread content...",
        lastMessageDate: Date = Date(),
        messageCount: Int = 1,
        isRead: Bool = false,
        isStarred: Bool = false,
        participantEmails: [String] = ["user@gmail.com"]
    ) -> EmailThread {
        EmailThread(
            threadId: threadId,
            subject: subject,
            snippet: snippet,
            lastMessageDate: lastMessageDate,
            messageCount: messageCount,
            isRead: isRead,
            isStarred: isStarred,
            participantEmails: participantEmails
        )
    }

    // MARK: - Attachment Fixtures

    /// Creates a test Attachment with optional customization.
    /// - Parameters:
    ///   - id: Local ID (default: generated UUID string)
    ///   - gmailAttachmentId: Gmail attachment ID (default: generated UUID string)
    ///   - filename: Filename (default: "document.pdf")
    ///   - mimeType: MIME type (default: "application/pdf")
    ///   - size: File size in bytes (default: 1024)
    /// - Returns: A configured Attachment
    static func makeAttachment(
        id: String = UUID().uuidString,
        gmailAttachmentId: String = UUID().uuidString,
        filename: String = "document.pdf",
        mimeType: String = "application/pdf",
        size: Int64 = 1024
    ) -> Attachment {
        Attachment(
            id: id,
            gmailAttachmentId: gmailAttachmentId,
            filename: filename,
            mimeType: mimeType,
            size: size
        )
    }

    // MARK: - SyncState Fixtures

    /// Creates a test SyncState with optional customization.
    /// - Parameters:
    ///   - accountId: Account ID (default: new UUID)
    /// - Returns: A configured SyncState
    static func makeSyncState(
        accountId: UUID = UUID()
    ) -> SyncState {
        SyncState(accountId: accountId)
    }

    // MARK: - OAuth Fixtures

    /// Creates a test OAuthTokens with optional customization.
    /// - Parameters:
    ///   - accessToken: Access token (default: "test_access_token")
    ///   - refreshToken: Refresh token (default: "test_refresh_token")
    ///   - expiresAt: Expiration date (default: 1 hour from now)
    ///   - scope: OAuth scopes (default: standard Gmail scopes)
    /// - Returns: A configured OAuthTokens
    static func makeOAuthTokens(
        accessToken: String = "test_access_token",
        refreshToken: String = "test_refresh_token",
        expiresAt: Date = Date().addingTimeInterval(3600),
        scope: String = "email profile https://www.googleapis.com/auth/gmail.readonly"
    ) -> OAuthTokens {
        OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scope: scope
        )
    }

    /// Creates expired test OAuthTokens.
    /// - Returns: OAuthTokens with an expiration date in the past
    static func makeExpiredOAuthTokens() -> OAuthTokens {
        OAuthTokens(
            accessToken: "expired_access_token",
            refreshToken: "test_refresh_token",
            expiresAt: Date().addingTimeInterval(-3600), // 1 hour ago
            scope: "email profile"
        )
    }

    /// Creates a test GoogleUserProfile with optional customization.
    /// - Parameters:
    ///   - email: Email address (default: "test@gmail.com")
    ///   - name: Display name (default: "Test User")
    ///   - picture: Profile picture URL (default: nil)
    /// - Returns: A configured GoogleUserProfile
    static func makeGoogleUserProfile(
        email: String = "test@gmail.com",
        name: String = "Test User",
        picture: String? = nil
    ) -> GoogleUserProfile {
        GoogleUserProfile(
            email: email,
            name: name,
            picture: picture
        )
    }

    // MARK: - Error Fixtures

    /// Sample auth errors for testing
    static let sampleAuthErrors: [AuthError] = [
        .userCancelled,
        .invalidCredentials,
        .tokenExpired,
        .tokenRefreshFailed(nil),
        .keychainError(nil),
        .networkError(nil)
    ]

    /// Sample authentication errors for testing
    static let sampleAuthenticationErrors: [AuthenticationError] = [
        .userCancelled,
        .invalidResponse,
        .tokenExchangeFailed("Invalid code"),
        .tokenExpired,
        .refreshFailed(nil),
        .networkError(NSError(domain: "test", code: -1)),
        .accountAlreadyExists("test@gmail.com"),
        .invalidGrant
    ]


    /// Sample sync errors for testing
    static let sampleSyncErrors: [SyncError] = [
        .networkUnavailable,
        .historyExpired,
        .quotaExceeded,
        .syncInProgress,
        .partialFailure(successCount: 5, failureCount: 2),
        .databaseError(nil)
    ]

    /// Sample API errors for testing
    static let sampleAPIErrors: [APIError] = [
        .unauthorized,
        .notFound,
        .rateLimited(retryAfter: 30),
        .invalidResponse,
        .serverError(statusCode: 500),
        .networkError(nil),
        .decodingError(nil)
    ]
}

// MARK: - Date Extensions for Testing

extension TestFixtures {

    /// Creates a date relative to now.
    /// - Parameter days: Number of days in the past (positive = past)
    /// - Returns: A Date
    static func dateAgo(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    /// Creates a date at a specific time today.
    /// - Parameters:
    ///   - hour: Hour (0-23)
    ///   - minute: Minute (0-59)
    /// - Returns: A Date
    static func today(at hour: Int, minute: Int = 0) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Gmail DTO Fixtures

extension TestFixtures {

    /// Creates a test GmailMessageDTO with optional customization.
    /// - Parameters:
    ///   - id: Message ID (default: generated)
    ///   - threadId: Thread ID (default: generated)
    ///   - labelIds: Label IDs (default: ["INBOX"])
    ///   - snippet: Preview snippet (default: "Test message...")
    /// - Returns: A configured GmailMessageDTO
    static func makeGmailMessageDTO(
        id: String = UUID().uuidString,
        threadId: String = UUID().uuidString,
        labelIds: [String]? = ["INBOX"],
        snippet: String? = "Test message..."
    ) -> GmailMessageDTO {
        GmailMessageDTO(
            id: id,
            threadId: threadId,
            labelIds: labelIds,
            snippet: snippet,
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000)),
            payload: makePayloadDTO()
        )
    }

    /// Creates a test PayloadDTO with default headers.
    /// - Returns: A configured PayloadDTO
    static func makePayloadDTO() -> PayloadDTO {
        PayloadDTO(
            headers: [
                HeaderDTO(name: "From", value: "sender@gmail.com"),
                HeaderDTO(name: "To", value: "recipient@gmail.com"),
                HeaderDTO(name: "Subject", value: "Test Subject")
            ],
            body: BodyDTO(size: 100, data: nil, attachmentId: nil),
            parts: nil,
            mimeType: "text/plain"
        )
    }

    /// Creates a test GmailDraftDTO with optional customization.
    static func makeGmailDraftDTO(
        id: String = UUID().uuidString,
        messageId: String = UUID().uuidString,
        threadId: String = UUID().uuidString
    ) -> GmailDraftDTO {
        GmailDraftDTO(
            id: id,
            message: makeGmailMessageDTO(id: messageId, threadId: threadId, labelIds: ["DRAFT"])
        )
    }

    /// Creates a test GmailDraftSummaryDTO for listing drafts.
    static func makeGmailDraftSummaryDTO(
        id: String = UUID().uuidString,
        messageId: String = UUID().uuidString,
        threadId: String = UUID().uuidString
    ) -> GmailDraftSummaryDTO {
        GmailDraftSummaryDTO(
            id: id,
            message: GmailMessageSummaryDTO(id: messageId, threadId: threadId)
        )
    }

    /// Creates a test GmailProfileDTO with optional customization.
    static func makeGmailProfileDTO(
        emailAddress: String = "test@gmail.com",
        historyId: String = "12345"
    ) -> GmailProfileDTO {
        GmailProfileDTO(
            emailAddress: emailAddress,
            messagesTotal: 1000,
            threadsTotal: 500,
            historyId: historyId
        )
    }

    /// Creates a test BatchResult with customizable success/failure.
    static func makeBatchResult<T>(
        succeeded: [T] = [],
        failed: [BatchFailure] = []
    ) -> BatchResult<T> {
        BatchResult(succeeded: succeeded, failed: failed)
    }

    /// Creates a test AttachmentData for drafts.
    static func makeAttachmentData(
        filename: String = "test.pdf",
        mimeType: String = "application/pdf",
        data: Data = Data("test content".utf8)
    ) -> AttachmentData {
        AttachmentData(
            filename: filename,
            mimeType: mimeType,
            data: data
        )
    }

    // MARK: - Gmail History DTO Fixtures

    /// Creates a test GmailHistoryDTO with optional customization.
    /// - Parameters:
    ///   - id: History ID (default: "12345")
    ///   - messagesAdded: Messages added in this history record
    ///   - messagesDeleted: Messages deleted in this history record
    ///   - labelsAdded: Labels added to messages
    ///   - labelsRemoved: Labels removed from messages
    /// - Returns: A configured GmailHistoryDTO
    static func makeGmailHistoryDTO(
        id: String = "12345",
        messagesAdded: [GmailHistoryMessageDTO]? = nil,
        messagesDeleted: [GmailHistoryMessageDTO]? = nil,
        labelsAdded: [GmailHistoryLabelDTO]? = nil,
        labelsRemoved: [GmailHistoryLabelDTO]? = nil
    ) -> GmailHistoryDTO {
        GmailHistoryDTO(
            id: id,
            messagesAdded: messagesAdded,
            messagesDeleted: messagesDeleted,
            labelsAdded: labelsAdded,
            labelsRemoved: labelsRemoved
        )
    }

    /// Creates a test GmailHistoryListDTO with optional customization.
    /// - Parameters:
    ///   - history: Array of history records
    ///   - historyId: Current history ID (default: "99999")
    ///   - nextPageToken: Token for pagination
    /// - Returns: A configured GmailHistoryListDTO
    static func makeGmailHistoryListDTO(
        history: [GmailHistoryDTO]? = nil,
        historyId: String = "99999",
        nextPageToken: String? = nil
    ) -> GmailHistoryListDTO {
        GmailHistoryListDTO(
            history: history,
            nextPageToken: nextPageToken,
            historyId: historyId
        )
    }

    /// Creates a test GmailHistoryMessageDTO for history records.
    /// - Parameters:
    ///   - messageId: Message ID (default: generated UUID)
    ///   - threadId: Thread ID (default: generated UUID)
    /// - Returns: A configured GmailHistoryMessageDTO
    static func makeGmailHistoryMessageDTO(
        messageId: String = UUID().uuidString,
        threadId: String = UUID().uuidString
    ) -> GmailHistoryMessageDTO {
        GmailHistoryMessageDTO(
            message: GmailMessageSummaryDTO(id: messageId, threadId: threadId)
        )
    }

}
