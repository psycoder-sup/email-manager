import Foundation

/// Advanced search filter state for email search.
struct SearchFilters: Codable, Equatable, Hashable {

    // MARK: - Filter Properties

    /// Filter by sender email or name
    var from: String?

    /// Filter by recipient email or name
    var to: String?

    /// Filter emails after this date
    var afterDate: Date?

    /// Filter emails before this date
    var beforeDate: Date?

    /// Filter emails with attachments
    var hasAttachment: Bool = false

    /// Filter unread emails only
    var isUnread: Bool = false

    /// Filter by account IDs (nil = all accounts)
    var accountIds: [UUID]?

    // MARK: - Computed Properties

    /// Returns true if any filter is active
    var isActive: Bool {
        from != nil ||
        to != nil ||
        afterDate != nil ||
        beforeDate != nil ||
        hasAttachment ||
        isUnread ||
        accountIds != nil
    }

    /// Returns true if searching multiple accounts
    var isMultiAccount: Bool {
        accountIds == nil || (accountIds?.count ?? 0) > 1
    }

    // MARK: - Gmail Query Building

    /// Builds a Gmail search query string from filters.
    /// - Parameter baseQuery: The base text query to include
    /// - Returns: Gmail-compatible query string
    func toGmailQuery(baseQuery: String) -> String {
        var parts: [String] = []

        // If base query already contains operators, use as-is
        if !baseQuery.isEmpty {
            if baseQuery.contains(":") {
                return baseQuery
            }
            parts.append(baseQuery)
        }

        if let from = from, !from.isEmpty {
            parts.append("from:\(from)")
        }

        if let to = to, !to.isEmpty {
            parts.append("to:\(to)")
        }

        if let afterDate = afterDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            parts.append("after:\(formatter.string(from: afterDate))")
        }

        if let beforeDate = beforeDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            parts.append("before:\(formatter.string(from: beforeDate))")
        }

        if hasAttachment {
            parts.append("has:attachment")
        }

        if isUnread {
            parts.append("is:unread")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Mutation

    /// Resets all filters to default values
    mutating func reset() {
        from = nil
        to = nil
        afterDate = nil
        beforeDate = nil
        hasAttachment = false
        isUnread = false
        accountIds = nil
    }
}

// MARK: - Search Scope

/// Defines the scope of email search.
enum SearchScope: String, CaseIterable, Identifiable {
    case all = "All Mail"
    case inbox = "Inbox"
    case sent = "Sent"
    case drafts = "Drafts"

    var id: String { rawValue }

    /// Maps scope to Gmail label ID
    var labelId: String? {
        switch self {
        case .all: return nil
        case .inbox: return "INBOX"
        case .sent: return "SENT"
        case .drafts: return "DRAFT"
        }
    }
}
