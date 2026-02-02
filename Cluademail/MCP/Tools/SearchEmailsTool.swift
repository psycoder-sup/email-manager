import Foundation
import SwiftData

/// MCP tool for searching emails by query.
final class SearchEmailsTool: MCPToolProtocol, @unchecked Sendable {

    let name = "search_emails"
    let description = "Search emails by query. Searches in subject, sender, and body snippet."

    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            inputSchema: JSONSchema(
                properties: [
                    "query": .string("Search query to match against subject, sender, and snippet (required)"),
                    "account": .string("Email address of the account to search (required)"),
                    "limit": .integer("Maximum number of results (default: 20, max: 50)")
                ],
                required: ["query", "account"]
            )
        )
    }

    private let databaseService: MCPDatabaseService

    init(databaseService: MCPDatabaseService) {
        self.databaseService = databaseService
    }

    func execute(arguments: [String: AnyCodable]?) async throws -> String {
        let query = try getString("query", from: arguments)
        let accountEmail = try getString("account", from: arguments)
        let limit = min(max(getInt("limit", from: arguments, default: MCPConfiguration.defaultSearchLimit), 1), MCPConfiguration.maxSearchLimit)

        let emails = try await databaseService.performRead { context in
            // Find account
            let accountPredicate = #Predicate<Account> { $0.email == accountEmail }
            var accountDescriptor = FetchDescriptor<Account>(predicate: accountPredicate)
            accountDescriptor.fetchLimit = 1

            guard let account = try context.fetch(accountDescriptor).first else {
                throw MCPError.accountNotFound(accountEmail)
            }

            // Search emails
            let accountId = account.id
            let searchPredicate = #Predicate<Email> {
                $0.account?.id == accountId &&
                ($0.subject.localizedStandardContains(query) ||
                 $0.fromAddress.localizedStandardContains(query) ||
                 $0.snippet.localizedStandardContains(query))
            }

            var descriptor = FetchDescriptor<Email>(
                predicate: searchPredicate,
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = limit

            return try context.fetch(descriptor)
        }

        return formatSearchResults(query: query, emails: emails)
    }

    // MARK: - Private

    private func formatSearchResults(query: String, emails: [Email]) -> String {
        guard !emails.isEmpty else {
            return "No emails found matching \"\(query)\"."
        }

        var output = "Search results for \"\(query)\": \(emails.count) email\(emails.count == 1 ? "" : "s")\n\n"

        for email in emails {
            output += "ID: \(email.gmailId)\n"
            output += "From: \(formatSender(email))\n"
            output += "Subject: \(email.subject)\n"
            output += "Date: \(formatDate(email.date))\n"

            // Truncate snippet to 100 chars
            let snippet = email.snippet
            if snippet.count > 100 {
                output += "Snippet: \(String(snippet.prefix(100)))...\n"
            } else {
                output += "Snippet: \(snippet)\n"
            }

            output += "---\n"
        }

        return output
    }
}
