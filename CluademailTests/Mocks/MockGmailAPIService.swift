import Foundation
@testable import Cluademail

/// Mock implementation of GmailAPIServiceProtocol for testing.
final class MockGmailAPIService: GmailAPIServiceProtocol, @unchecked Sendable {

    // MARK: - Call Tracking

    var listMessagesCallCount = 0
    var getMessageCallCount = 0
    var batchGetMessagesCallCount = 0
    var modifyMessageCallCount = 0
    var trashMessageCallCount = 0
    var untrashMessageCallCount = 0
    var listThreadsCallCount = 0
    var getThreadCallCount = 0
    var listDraftsCallCount = 0
    var createDraftCallCount = 0
    var updateDraftCallCount = 0
    var deleteDraftCallCount = 0
    var getDraftCallCount = 0
    var sendMessageCallCount = 0
    var getAttachmentCallCount = 0
    var getHistoryCallCount = 0
    var getProfileCallCount = 0

    // MARK: - Configurable Responses

    var listMessagesResult: Result<(messages: [GmailMessageSummaryDTO], nextPageToken: String?), Error> =
        .success((messages: [], nextPageToken: nil))

    var getMessageResult: Result<GmailMessageDTO, Error>?
    var getMessageResults: [String: Result<GmailMessageDTO, Error>] = [:]

    var batchGetMessagesResult: Result<BatchResult<GmailMessageDTO>, Error>?

    var modifyMessageResult: Result<GmailMessageDTO, Error>?

    var listThreadsResult: Result<(threads: [GmailThreadSummaryDTO], nextPageToken: String?), Error> =
        .success((threads: [], nextPageToken: nil))

    var getThreadResult: Result<GmailThreadDTO, Error>?

    var listDraftsResult: Result<(drafts: [GmailDraftSummaryDTO], nextPageToken: String?), Error> =
        .success((drafts: [], nextPageToken: nil))
    var getDraftResults: [String: Result<GmailDraftDTO, Error>] = [:]

    var createDraftResult: Result<GmailDraftDTO, Error>?
    var updateDraftResult: Result<GmailDraftDTO, Error>?
    var getDraftResult: Result<GmailDraftDTO, Error>?
    var deleteDraftError: Error?

    var sendMessageResult: Result<GmailMessageDTO, Error>?

    var getAttachmentResult: Result<Data, Error>?

    var getHistoryResult: Result<GmailHistoryListDTO, Error>?
    var getProfileResult: Result<GmailProfileDTO, Error>?

    // MARK: - Protocol Implementation

    func listMessages(
        accountEmail: String,
        query: String?,
        labelIds: [String]?,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> (messages: [GmailMessageSummaryDTO], nextPageToken: String?) {
        listMessagesCallCount += 1
        return try listMessagesResult.get()
    }

    func getMessage(
        accountEmail: String,
        messageId: String
    ) async throws -> GmailMessageDTO {
        getMessageCallCount += 1

        // Check per-message results first
        if let result = getMessageResults[messageId] {
            return try result.get()
        }

        // Fall back to default result
        if let result = getMessageResult {
            return try result.get()
        }

        throw APIError.notFound
    }

    func batchGetMessages(
        accountEmail: String,
        messageIds: [String]
    ) async throws -> BatchResult<GmailMessageDTO> {
        batchGetMessagesCallCount += 1

        if let result = batchGetMessagesResult {
            return try result.get()
        }

        // Default: try to get each message individually
        var succeeded: [GmailMessageDTO] = []
        var failed: [BatchFailure] = []

        for (index, messageId) in messageIds.enumerated() {
            if let result = getMessageResults[messageId] {
                do {
                    let message = try result.get()
                    succeeded.append(message)
                } catch let error as APIError {
                    failed.append(BatchFailure(
                        requestIndex: index,
                        itemId: messageId,
                        statusCode: 404,
                        error: error
                    ))
                } catch {
                    failed.append(BatchFailure(
                        requestIndex: index,
                        itemId: messageId,
                        statusCode: 500,
                        error: .serverError(statusCode: 500)
                    ))
                }
            }
        }

        return BatchResult(succeeded: succeeded, failed: failed)
    }

    func modifyMessage(
        accountEmail: String,
        messageId: String,
        addLabelIds: [String],
        removeLabelIds: [String]
    ) async throws -> GmailMessageDTO {
        modifyMessageCallCount += 1
        if let result = modifyMessageResult {
            return try result.get()
        }
        throw APIError.notFound
    }

    func trashMessage(accountEmail: String, messageId: String) async throws {
        trashMessageCallCount += 1
    }

    func untrashMessage(accountEmail: String, messageId: String) async throws {
        untrashMessageCallCount += 1
    }

    func listThreads(
        accountEmail: String,
        query: String?,
        labelIds: [String]?,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> (threads: [GmailThreadSummaryDTO], nextPageToken: String?) {
        listThreadsCallCount += 1
        return try listThreadsResult.get()
    }

    func getThread(
        accountEmail: String,
        threadId: String
    ) async throws -> GmailThreadDTO {
        getThreadCallCount += 1
        if let result = getThreadResult {
            return try result.get()
        }
        throw APIError.notFound
    }

    func listDrafts(
        accountEmail: String,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> (drafts: [GmailDraftSummaryDTO], nextPageToken: String?) {
        listDraftsCallCount += 1
        return try listDraftsResult.get()
    }

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
    ) async throws -> GmailDraftDTO {
        createDraftCallCount += 1
        if let result = createDraftResult {
            return try result.get()
        }
        throw APIError.invalidResponse
    }

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
    ) async throws -> GmailDraftDTO {
        updateDraftCallCount += 1
        if let result = updateDraftResult {
            return try result.get()
        }
        throw APIError.invalidResponse
    }

    func deleteDraft(accountEmail: String, draftId: String) async throws {
        deleteDraftCallCount += 1
        if let error = deleteDraftError {
            throw error
        }
    }

    func getDraft(accountEmail: String, draftId: String) async throws -> GmailDraftDTO {
        getDraftCallCount += 1

        // Check per-draft results first
        if let result = getDraftResults[draftId] {
            return try result.get()
        }

        // Fall back to default result
        if let result = getDraftResult {
            return try result.get()
        }
        throw APIError.notFound
    }

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
    ) async throws -> GmailMessageDTO {
        sendMessageCallCount += 1
        if let result = sendMessageResult {
            return try result.get()
        }
        throw APIError.invalidResponse
    }

    func getAttachment(
        accountEmail: String,
        messageId: String,
        attachmentId: String
    ) async throws -> Data {
        getAttachmentCallCount += 1
        if let result = getAttachmentResult {
            return try result.get()
        }
        throw APIError.notFound
    }

    func getHistory(
        accountEmail: String,
        startHistoryId: String,
        historyTypes: [String]?
    ) async throws -> GmailHistoryListDTO {
        getHistoryCallCount += 1
        if let result = getHistoryResult {
            return try result.get()
        }
        throw APIError.invalidResponse
    }

    func getProfile(accountEmail: String) async throws -> GmailProfileDTO {
        getProfileCallCount += 1
        if let result = getProfileResult {
            return try result.get()
        }
        throw APIError.invalidResponse
    }

    // MARK: - Reset

    func reset() {
        listMessagesCallCount = 0
        getMessageCallCount = 0
        batchGetMessagesCallCount = 0
        modifyMessageCallCount = 0
        trashMessageCallCount = 0
        untrashMessageCallCount = 0
        listThreadsCallCount = 0
        getThreadCallCount = 0
        listDraftsCallCount = 0
        createDraftCallCount = 0
        updateDraftCallCount = 0
        deleteDraftCallCount = 0
        getDraftCallCount = 0
        sendMessageCallCount = 0
        getAttachmentCallCount = 0
        getHistoryCallCount = 0
        getProfileCallCount = 0

        listMessagesResult = .success((messages: [], nextPageToken: nil))
        getMessageResult = nil
        getMessageResults = [:]
        batchGetMessagesResult = nil
        modifyMessageResult = nil
        listThreadsResult = .success((threads: [], nextPageToken: nil))
        getThreadResult = nil
        listDraftsResult = .success((drafts: [], nextPageToken: nil))
        getDraftResults = [:]
        createDraftResult = nil
        updateDraftResult = nil
        getDraftResult = nil
        deleteDraftError = nil
        sendMessageResult = nil
        getAttachmentResult = nil
        getHistoryResult = nil
        getProfileResult = nil
    }
}
