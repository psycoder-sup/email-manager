import Foundation
import os.log

/// Gmail API service implementation.
/// Handles all Gmail REST API operations with retry logic and batch support.
final class GmailAPIService: GmailAPIServiceProtocol, @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance
    static let shared = GmailAPIService()

    // MARK: - Dependencies

    private let tokenManager: any TokenManagerProtocol
    private let session: URLSession
    private let decoder: JSONDecoder

    // MARK: - Configuration

    private let maxRetries = 3
    private let batchSize = 50
    private let defaultTimeout: TimeInterval = 30
    private let attachmentTimeout: TimeInterval = 300

    // MARK: - Initialization

    private init() {
        self.tokenManager = TokenManager.shared
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
    }

    /// Creates a GmailAPIService with custom dependencies (for testing).
    init(tokenManager: any TokenManagerProtocol, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Messages

    func listMessages(
        accountEmail: String,
        query: String?,
        labelIds: [String]?,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> (messages: [GmailMessageSummaryDTO], nextPageToken: String?) {
        let queryItems = GmailEndpoints.listMessagesQuery(
            query: query,
            labelIds: labelIds,
            maxResults: maxResults,
            pageToken: pageToken
        )

        guard let url = GmailEndpoints.listMessages.url(additionalQueryItems: queryItems) else {
            throw APIError.invalidResponse
        }

        let response: GmailMessageListDTO = try await executeRequest(
            url: url,
            method: "GET",
            accountEmail: accountEmail
        )

        return (messages: response.messages ?? [], nextPageToken: response.nextPageToken)
    }

    func getMessage(
        accountEmail: String,
        messageId: String
    ) async throws -> GmailMessageDTO {
        guard let url = GmailEndpoints.getMessage(id: messageId, format: .full).url() else {
            throw APIError.invalidResponse
        }

        return try await executeRequest(
            url: url,
            method: "GET",
            accountEmail: accountEmail
        )
    }

    func batchGetMessages(
        accountEmail: String,
        messageIds: [String]
    ) async throws -> BatchResult<GmailMessageDTO> {
        guard !messageIds.isEmpty else {
            return BatchResult(succeeded: [], failed: [])
        }

        var allSucceeded: [GmailMessageDTO] = []
        var allFailed: [BatchFailure] = []

        // Process in chunks of batchSize
        let chunks = messageIds.chunked(into: batchSize)

        for (chunkIndex, chunk) in chunks.enumerated() {
            let baseIndex = chunkIndex * batchSize
            let result = try await executeBatchRequest(
                accountEmail: accountEmail,
                messageIds: chunk,
                baseIndex: baseIndex
            )
            allSucceeded.append(contentsOf: result.succeeded)
            allFailed.append(contentsOf: result.failed)
        }

        return BatchResult(succeeded: allSucceeded, failed: allFailed)
    }

    func modifyMessage(
        accountEmail: String,
        messageId: String,
        addLabelIds: [String],
        removeLabelIds: [String]
    ) async throws -> GmailMessageDTO {
        guard let url = GmailEndpoints.modifyMessage(id: messageId).url() else {
            throw APIError.invalidResponse
        }

        let modifyRequest = ModifyMessageRequest(
            addLabelIds: addLabelIds.isEmpty ? nil : addLabelIds,
            removeLabelIds: removeLabelIds.isEmpty ? nil : removeLabelIds
        )

        return try await executeRequest(
            url: url,
            method: "POST",
            body: try JSONEncoder().encode(modifyRequest),
            accountEmail: accountEmail
        )
    }

    func trashMessage(accountEmail: String, messageId: String) async throws {
        guard let url = GmailEndpoints.trashMessage(id: messageId).url() else {
            throw APIError.invalidResponse
        }

        _ = try await executeRequest(url: url, method: "POST", accountEmail: accountEmail) as GmailMessageDTO
    }

    func untrashMessage(accountEmail: String, messageId: String) async throws {
        guard let url = GmailEndpoints.untrashMessage(id: messageId).url() else {
            throw APIError.invalidResponse
        }

        _ = try await executeRequest(url: url, method: "POST", accountEmail: accountEmail) as GmailMessageDTO
    }

    // MARK: - Threads

    func listThreads(
        accountEmail: String,
        query: String?,
        labelIds: [String]?,
        maxResults: Int?,
        pageToken: String?
    ) async throws -> (threads: [GmailThreadSummaryDTO], nextPageToken: String?) {
        let queryItems = GmailEndpoints.listThreadsQuery(
            query: query,
            labelIds: labelIds,
            maxResults: maxResults,
            pageToken: pageToken
        )

        guard let url = GmailEndpoints.listThreads.url(additionalQueryItems: queryItems) else {
            throw APIError.invalidResponse
        }

        let response: GmailThreadListDTO = try await executeRequest(
            url: url,
            method: "GET",
            accountEmail: accountEmail
        )

        return (threads: response.threads ?? [], nextPageToken: response.nextPageToken)
    }

    func getThread(
        accountEmail: String,
        threadId: String
    ) async throws -> GmailThreadDTO {
        guard let url = GmailEndpoints.getThread(id: threadId, format: .full).url() else {
            throw APIError.invalidResponse
        }

        return try await executeRequest(
            url: url,
            method: "GET",
            accountEmail: accountEmail
        )
    }

    // MARK: - Drafts

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
        guard let url = GmailEndpoints.createDraft.url() else {
            throw APIError.invalidResponse
        }

        let rawMessage = MIMEMessageBuilder.buildMessage(
            from: accountEmail, to: to, cc: cc, bcc: bcc,
            subject: subject, body: body, isHtml: isHtml,
            replyToMessageId: replyToMessageId, attachments: attachments
        )

        let threadId = try await fetchThreadIdIfReply(
            accountEmail: accountEmail, replyToMessageId: replyToMessageId
        )

        let draftRequest = DraftRequest(
            message: DraftMessageRequest(raw: rawMessage, threadId: threadId)
        )

        return try await executeRequest(
            url: url,
            method: "POST",
            body: try JSONEncoder().encode(draftRequest),
            accountEmail: accountEmail
        )
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
        guard let url = GmailEndpoints.updateDraft(id: draftId).url() else {
            throw APIError.invalidResponse
        }

        let rawMessage = MIMEMessageBuilder.buildMessage(
            from: accountEmail, to: to, cc: cc, bcc: bcc,
            subject: subject, body: body, isHtml: isHtml,
            replyToMessageId: nil, attachments: attachments
        )

        let draftRequest = DraftRequest(
            message: DraftMessageRequest(raw: rawMessage, threadId: nil)
        )

        return try await executeRequest(
            url: url,
            method: "PUT",
            body: try JSONEncoder().encode(draftRequest),
            accountEmail: accountEmail
        )
    }

    func deleteDraft(accountEmail: String, draftId: String) async throws {
        guard let url = GmailEndpoints.deleteDraft(id: draftId).url() else {
            throw APIError.invalidResponse
        }

        try await executeRequestNoResponse(
            url: url,
            method: "DELETE",
            accountEmail: accountEmail
        )
    }

    func getDraft(accountEmail: String, draftId: String) async throws -> GmailDraftDTO {
        guard let url = GmailEndpoints.getDraft(id: draftId).url() else {
            throw APIError.invalidResponse
        }

        return try await executeRequest(
            url: url,
            method: "GET",
            accountEmail: accountEmail
        )
    }

    // MARK: - Sending

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
        guard let url = GmailEndpoints.sendMessage.url() else {
            throw APIError.invalidResponse
        }

        let rawMessage = MIMEMessageBuilder.buildMessage(
            from: accountEmail, to: to, cc: cc, bcc: bcc,
            subject: subject, body: body, isHtml: isHtml,
            replyToMessageId: replyToMessageId, attachments: attachments
        )

        let threadId = try await fetchThreadIdIfReply(
            accountEmail: accountEmail, replyToMessageId: replyToMessageId
        )

        let sendRequest = SendMessageRequest(raw: rawMessage, threadId: threadId)

        return try await executeRequest(
            url: url,
            method: "POST",
            body: try JSONEncoder().encode(sendRequest),
            accountEmail: accountEmail
        )
    }

    // MARK: - Attachments

    func getAttachment(
        accountEmail: String,
        messageId: String,
        attachmentId: String
    ) async throws -> Data {
        guard let url = GmailEndpoints.getAttachment(
            messageId: messageId,
            attachmentId: attachmentId
        ).url() else {
            throw APIError.invalidResponse
        }

        let response: GmailAttachmentDTO = try await executeRequest(
            url: url,
            method: "GET",
            accountEmail: accountEmail,
            timeout: attachmentTimeout
        )

        guard let dataString = response.data,
              let data = Data(base64URLEncoded: dataString) else {
            throw APIError.invalidResponse
        }

        return data
    }

    // MARK: - Sync

    func getHistory(
        accountEmail: String,
        startHistoryId: String,
        historyTypes: [String]?
    ) async throws -> GmailHistoryListDTO {
        let queryItems = GmailEndpoints.historyQuery(
            startHistoryId: startHistoryId,
            historyTypes: historyTypes
        )

        guard let url = GmailEndpoints.getHistory.url(additionalQueryItems: queryItems) else {
            throw APIError.invalidResponse
        }

        return try await executeRequest(
            url: url,
            method: "GET",
            accountEmail: accountEmail
        )
    }

    func getProfile(accountEmail: String) async throws -> GmailProfileDTO {
        guard let url = GmailEndpoints.getProfile.url() else {
            throw APIError.invalidResponse
        }

        return try await executeRequest(
            url: url,
            method: "GET",
            accountEmail: accountEmail
        )
    }

    // MARK: - Private Helpers

    /// Fetches thread ID for a reply, if applicable.
    private func fetchThreadIdIfReply(
        accountEmail: String,
        replyToMessageId: String?
    ) async throws -> String? {
        guard let replyToMessageId else { return nil }
        let replyToMessage = try await getMessage(accountEmail: accountEmail, messageId: replyToMessageId)
        return replyToMessage.threadId
    }

    // MARK: - Private Request Execution

    /// Builds an authenticated URLRequest.
    private func buildRequest(
        url: URL,
        method: String,
        accessToken: String,
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout ?? defaultTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    /// Handles retry decision and returns true if should continue retrying.
    private func handleRetry(
        error: Error,
        attempt: Int
    ) async throws -> Bool {
        let decision = RetryHelper.shouldRetry(error, attempt: attempt, maxAttempts: maxRetries)

        switch decision {
        case .retry(let delay):
            Logger.api.debug("Retrying request after \(String(format: "%.2f", delay))s (attempt \(attempt + 1)/\(self.maxRetries))")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return true

        case .retryWithRefresh:
            Logger.api.debug("Retrying with token refresh (attempt \(attempt + 1)/\(self.maxRetries))")
            return true

        case .doNotRetry:
            throw error
        }
    }

    /// Executes an authenticated request with retry logic.
    private func executeRequest<T: Decodable>(
        url: URL,
        method: String,
        body: Data? = nil,
        accountEmail: String,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        var lastError: Error = APIError.networkError(nil)

        for attempt in 0..<maxRetries {
            do {
                let accessToken = try await tokenManager.getValidAccessToken(for: accountEmail)
                let request = buildRequest(url: url, method: method, accessToken: accessToken, body: body, timeout: timeout)

                Logger.api.logRequest(method: method, url: url.absoluteString, hasBody: body != nil)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                Logger.api.logResponse(statusCode: httpResponse.statusCode, url: url.absoluteString)

                try handleResponseError(statusCode: httpResponse.statusCode, data: data, headers: httpResponse.allHeaderFields)

                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    Logger.api.error("Decoding error: \(error.localizedDescription)")
                    throw APIError.decodingError(error)
                }

            } catch {
                lastError = error
                if try await handleRetry(error: error, attempt: attempt) {
                    continue
                }
            }
        }

        throw lastError
    }

    /// Executes a request that returns no response body.
    private func executeRequestNoResponse(
        url: URL,
        method: String,
        body: Data? = nil,
        accountEmail: String
    ) async throws {
        var lastError: Error = APIError.networkError(nil)

        for attempt in 0..<maxRetries {
            do {
                let accessToken = try await tokenManager.getValidAccessToken(for: accountEmail)
                let request = buildRequest(url: url, method: method, accessToken: accessToken, body: body)

                Logger.api.logRequest(method: method, url: url.absoluteString, hasBody: body != nil)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                Logger.api.logResponse(statusCode: httpResponse.statusCode, url: url.absoluteString)

                try handleResponseError(statusCode: httpResponse.statusCode, data: data, headers: httpResponse.allHeaderFields)
                return

            } catch {
                lastError = error
                if try await handleRetry(error: error, attempt: attempt) {
                    continue
                }
            }
        }

        throw lastError
    }

    /// Maps HTTP status code to APIError.
    private func mapStatusCodeToError(_ statusCode: Int, retryAfter: TimeInterval? = nil) -> APIError {
        switch statusCode {
        case 401: return .unauthorized
        case 404: return .notFound
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 400..<500: return .invalidResponse
        case 500..<600: return .serverError(statusCode: statusCode)
        default: return .networkError(nil)
        }
    }

    /// Handles HTTP error responses by throwing appropriate APIError.
    private func handleResponseError(
        statusCode: Int,
        data: Data,
        headers: [AnyHashable: Any]
    ) throws {
        guard !(200..<300).contains(statusCode) else { return }

        let retryAfter = (headers["Retry-After"] as? String).flatMap(TimeInterval.init)
        throw mapStatusCodeToError(statusCode, retryAfter: retryAfter)
    }

    // MARK: - Batch Request Execution

    /// Executes a batch request for multiple messages.
    private func executeBatchRequest(
        accountEmail: String,
        messageIds: [String],
        baseIndex: Int
    ) async throws -> BatchResult<GmailMessageDTO> {
        let accessToken = try await tokenManager.getValidAccessToken(for: accountEmail)

        // Build multipart batch request
        let boundary = "batch_\(UUID().uuidString)"
        var bodyParts: [String] = []

        for (index, messageId) in messageIds.enumerated() {
            guard let url = GmailEndpoints.getMessage(id: messageId, format: .full).url() else {
                continue
            }

            let part = """
            --\(boundary)
            Content-Type: application/http
            Content-ID: <request-\(index)>

            GET \(url.path)?\(url.query ?? "") HTTP/1.1
            Host: gmail.googleapis.com
            Authorization: Bearer \(accessToken)

            """
            bodyParts.append(part)
        }

        bodyParts.append("--\(boundary)--")
        let bodyString = bodyParts.joined(separator: "\r\n")

        guard let batchURL = URL(string: GmailEndpoints.batchURL),
              let bodyData = bodyString.data(using: .utf8) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: batchURL)
        request.httpMethod = "POST"
        request.timeoutInterval = defaultTimeout
        request.setValue("multipart/mixed; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        Logger.api.logRequest(method: "POST", url: batchURL.absoluteString, hasBody: true)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        Logger.api.logResponse(statusCode: httpResponse.statusCode, url: batchURL.absoluteString)

        guard httpResponse.statusCode == 200 else {
            try handleResponseError(statusCode: httpResponse.statusCode, data: data, headers: httpResponse.allHeaderFields)
            throw APIError.invalidResponse
        }

        // Extract boundary from response Content-Type header (Google uses its own boundary, not ours)
        let responseBoundary: String
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           let boundaryRange = contentType.range(of: "boundary=") {
            responseBoundary = String(contentType[boundaryRange.upperBound...])
        } else {
            // Fallback to sent boundary (shouldn't happen)
            responseBoundary = boundary
            Logger.api.warning("Could not extract boundary from batch response, using sent boundary")
        }

        // Parse batch response
        return parseBatchResponse(data: data, boundary: responseBoundary, messageIds: messageIds, baseIndex: baseIndex)
    }

    /// Parses a multipart batch response.
    private func parseBatchResponse(
        data: Data,
        boundary: String,
        messageIds: [String],
        baseIndex: Int
    ) -> BatchResult<GmailMessageDTO> {
        guard let responseString = String(data: data, encoding: .utf8) else {
            return BatchResult(
                succeeded: [],
                failed: messageIds.enumerated().map { index, id in
                    BatchFailure(
                        requestIndex: baseIndex + index,
                        itemId: id,
                        statusCode: 0,
                        error: .invalidResponse
                    )
                }
            )
        }

        var succeeded: [GmailMessageDTO] = []
        var failed: [BatchFailure] = []

        // Split by boundary
        let parts = responseString.components(separatedBy: "--\(boundary)")

        for part in parts {
            // Skip empty parts and closing boundary
            if part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               part.trimmingCharacters(in: .whitespacesAndNewlines) == "--" {
                continue
            }

            // Extract Content-ID to get index
            // Google batch API returns Content-ID: <response-request-{index}> format
            guard let contentIdRange = part.range(of: "Content-ID: <response-request-"),
                  let endRange = part.range(of: ">", range: contentIdRange.upperBound..<part.endIndex),
                  let index = Int(part[contentIdRange.upperBound..<endRange.lowerBound]) else {
                continue
            }

            guard index < messageIds.count else { continue }
            let messageId = messageIds[index]

            // Find HTTP status line
            guard let statusRange = part.range(of: "HTTP/1.1 "),
                  let statusEndRange = part.range(of: " ", range: statusRange.upperBound..<part.endIndex),
                  let statusCode = Int(part[statusRange.upperBound..<statusEndRange.lowerBound]) else {
                failed.append(BatchFailure(
                    requestIndex: baseIndex + index,
                    itemId: messageId,
                    statusCode: 0,
                    error: .invalidResponse
                ))
                continue
            }

            // Find JSON body (after double newline)
            guard let bodyStart = part.range(of: "\r\n\r\n", range: statusRange.upperBound..<part.endIndex) ??
                                  part.range(of: "\n\n", range: statusRange.upperBound..<part.endIndex) else {
                failed.append(BatchFailure(
                    requestIndex: baseIndex + index,
                    itemId: messageId,
                    statusCode: statusCode,
                    error: .invalidResponse
                ))
                continue
            }

            let jsonString = String(part[bodyStart.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let jsonData = jsonString.data(using: .utf8) else {
                failed.append(BatchFailure(
                    requestIndex: baseIndex + index,
                    itemId: messageId,
                    statusCode: statusCode,
                    error: .invalidResponse
                ))
                continue
            }

            if (200..<300).contains(statusCode) {
                do {
                    let message = try decoder.decode(GmailMessageDTO.self, from: jsonData)
                    succeeded.append(message)
                } catch {
                    failed.append(BatchFailure(
                        requestIndex: baseIndex + index,
                        itemId: messageId,
                        statusCode: statusCode,
                        error: .decodingError(error)
                    ))
                }
            } else {
                failed.append(BatchFailure(
                    requestIndex: baseIndex + index,
                    itemId: messageId,
                    statusCode: statusCode,
                    error: mapStatusCodeToError(statusCode)
                ))
            }
        }

        return BatchResult(succeeded: succeeded, failed: failed)
    }
}

// MARK: - Array Extension

private extension Array {
    /// Chunks array into smaller arrays of specified size.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
