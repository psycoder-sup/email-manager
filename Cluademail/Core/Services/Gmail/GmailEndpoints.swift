import Foundation

/// Gmail API message format options.
enum GmailMessageFormat: String, Sendable {
    /// Returns only message ID and thread ID
    case minimal
    /// Returns full message data (default for getMessage)
    case full
    /// Returns raw RFC 2822 message
    case raw
    /// Returns metadata only (headers, labels)
    case metadata
}

/// Gmail API endpoints with URL construction.
enum GmailEndpoints: Sendable {
    // Base URL
    static let baseURL = "https://gmail.googleapis.com/gmail/v1/users"
    static let batchURL = "https://gmail.googleapis.com/batch/gmail/v1"

    // MARK: - Messages

    /// List messages: GET /users/{userId}/messages
    case listMessages

    /// Get a single message: GET /users/{userId}/messages/{id}
    case getMessage(id: String, format: GmailMessageFormat)

    /// Modify message labels: POST /users/{userId}/messages/{id}/modify
    case modifyMessage(id: String)

    /// Move message to trash: POST /users/{userId}/messages/{id}/trash
    case trashMessage(id: String)

    /// Remove message from trash: POST /users/{userId}/messages/{id}/untrash
    case untrashMessage(id: String)

    /// Send a message: POST /users/{userId}/messages/send
    case sendMessage

    // MARK: - Threads

    /// List threads: GET /users/{userId}/threads
    case listThreads

    /// Get a thread: GET /users/{userId}/threads/{id}
    case getThread(id: String, format: GmailMessageFormat)

    // MARK: - Labels

    /// List labels: GET /users/{userId}/labels
    case listLabels

    /// Get a label: GET /users/{userId}/labels/{id}
    case getLabel(id: String)

    // MARK: - Drafts

    /// Create a draft: POST /users/{userId}/drafts
    case createDraft

    /// Get a draft: GET /users/{userId}/drafts/{id}
    case getDraft(id: String)

    /// Update a draft: PUT /users/{userId}/drafts/{id}
    case updateDraft(id: String)

    /// Delete a draft: DELETE /users/{userId}/drafts/{id}
    case deleteDraft(id: String)

    // MARK: - Attachments

    /// Get attachment: GET /users/{userId}/messages/{messageId}/attachments/{id}
    case getAttachment(messageId: String, attachmentId: String)

    // MARK: - Sync

    /// Get profile: GET /users/{userId}/profile
    case getProfile

    /// List history: GET /users/{userId}/history
    case getHistory

    // MARK: - URL Construction

    /// Returns the path component for this endpoint.
    var path: String {
        switch self {
        case .listMessages:
            return "/messages"
        case .getMessage(let id, _):
            return "/messages/\(id)"
        case .modifyMessage(let id):
            return "/messages/\(id)/modify"
        case .trashMessage(let id):
            return "/messages/\(id)/trash"
        case .untrashMessage(let id):
            return "/messages/\(id)/untrash"
        case .sendMessage:
            return "/messages/send"
        case .listThreads:
            return "/threads"
        case .getThread(let id, _):
            return "/threads/\(id)"
        case .listLabels:
            return "/labels"
        case .getLabel(let id):
            return "/labels/\(id)"
        case .createDraft:
            return "/drafts"
        case .getDraft(let id):
            return "/drafts/\(id)"
        case .updateDraft(let id):
            return "/drafts/\(id)"
        case .deleteDraft(let id):
            return "/drafts/\(id)"
        case .getAttachment(let messageId, let attachmentId):
            return "/messages/\(messageId)/attachments/\(attachmentId)"
        case .getProfile:
            return "/profile"
        case .getHistory:
            return "/history"
        }
    }

    /// Returns the HTTP method for this endpoint.
    var method: String {
        switch self {
        case .listMessages, .getMessage, .listThreads, .getThread,
             .listLabels, .getLabel, .getDraft, .getAttachment,
             .getProfile, .getHistory:
            return "GET"
        case .modifyMessage, .trashMessage, .untrashMessage,
             .sendMessage, .createDraft:
            return "POST"
        case .updateDraft:
            return "PUT"
        case .deleteDraft:
            return "DELETE"
        }
    }

    /// Returns query items for this endpoint.
    var queryItems: [URLQueryItem] {
        switch self {
        case .getMessage(_, let format), .getThread(_, let format):
            return [URLQueryItem(name: "format", value: format.rawValue)]
        default:
            return []
        }
    }

    /// Builds the complete URL for this endpoint.
    /// - Parameters:
    ///   - userId: The Gmail user ID (usually "me" for authenticated user)
    ///   - additionalQueryItems: Additional query parameters
    /// - Returns: The complete URL
    func url(userId: String = "me", additionalQueryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(string: Self.baseURL)
        components?.path += "/\(userId)" + path

        let allQueryItems = queryItems + additionalQueryItems
        if !allQueryItems.isEmpty {
            components?.queryItems = allQueryItems
        }

        return components?.url
    }
}

// MARK: - Query Parameter Builders

extension GmailEndpoints {

    /// Builds query items for listing messages.
    static func listMessagesQuery(
        query: String? = nil,
        labelIds: [String]? = nil,
        maxResults: Int? = nil,
        pageToken: String? = nil
    ) -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }

        for labelId in labelIds ?? [] {
            items.append(URLQueryItem(name: "labelIds", value: labelId))
        }

        if let maxResults {
            items.append(URLQueryItem(name: "maxResults", value: String(maxResults)))
        }

        if let pageToken {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        return items
    }

    /// Builds query items for listing threads (same parameters as messages).
    static func listThreadsQuery(
        query: String? = nil,
        labelIds: [String]? = nil,
        maxResults: Int? = nil,
        pageToken: String? = nil
    ) -> [URLQueryItem] {
        listMessagesQuery(query: query, labelIds: labelIds, maxResults: maxResults, pageToken: pageToken)
    }

    /// Builds query items for history API.
    static func historyQuery(
        startHistoryId: String,
        historyTypes: [String]? = nil,
        labelId: String? = nil,
        maxResults: Int? = nil,
        pageToken: String? = nil
    ) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "startHistoryId", value: startHistoryId)
        ]

        for type in historyTypes ?? [] {
            items.append(URLQueryItem(name: "historyTypes", value: type))
        }

        if let labelId {
            items.append(URLQueryItem(name: "labelId", value: labelId))
        }

        if let maxResults {
            items.append(URLQueryItem(name: "maxResults", value: String(maxResults)))
        }

        if let pageToken {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        return items
    }
}
