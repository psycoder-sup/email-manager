import Foundation
import SwiftData

/// MCP tool for listing emails with optional filters.
final class ListEmailsTool: MCPToolProtocol, @unchecked Sendable {

    let name = "list_emails"
    let description = "List emails with optional filters. Returns email summaries including ID, sender, subject, date, and read/starred status."

    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            inputSchema: JSONSchema(
                properties: [
                    "account": .string("Email address of the account to list emails from (required)"),
                    "folder": .string("Folder to list from: inbox, sent, drafts, trash, spam, starred (default: inbox)"),
                    "unread_only": .boolean("Only return unread emails (default: false)"),
                    "limit": .integer("Maximum number of emails to return (default: 20, max: 100)"),
                    "sender": .string("Filter by sender email address (partial match)")
                ],
                required: ["account"]
            )
        )
    }

    private let databaseService: MCPDatabaseService

    init(databaseService: MCPDatabaseService) {
        self.databaseService = databaseService
    }

    func execute(arguments: [String: AnyCodable]?) async throws -> String {
        // Extract parameters
        let accountEmail = try getString("account", from: arguments)
        let folderName = getOptionalString("folder", from: arguments) ?? "inbox"
        let unreadOnly = getBool("unread_only", from: arguments)
        let limit = min(max(getInt("limit", from: arguments, default: MCPConfiguration.defaultEmailListLimit), 1), MCPConfiguration.maxEmailListLimit)
        let senderFilter = getOptionalString("sender", from: arguments)

        // Map folder name to Gmail label ID
        let folder = mapFolderToLabelId(folderName)

        // Fetch emails
        let emails = try await databaseService.performRead { context in
            // Find account
            let accountPredicate = #Predicate<Account> { $0.email == accountEmail }
            var accountDescriptor = FetchDescriptor<Account>(predicate: accountPredicate)
            accountDescriptor.fetchLimit = 1

            guard let account = try context.fetch(accountDescriptor).first else {
                throw MCPError.accountNotFound(accountEmail)
            }

            // Build predicate
            let accountId = account.id
            let predicate: Predicate<Email>
            if unreadOnly {
                predicate = #Predicate<Email> { $0.account?.id == accountId && $0.isRead == false }
            } else {
                predicate = #Predicate<Email> { $0.account?.id == accountId }
            }

            // Fetch emails
            var descriptor = FetchDescriptor<Email>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )

            let emails = try context.fetch(descriptor)

            // Filter by folder in-memory (SwiftData can't translate array.contains)
            var filtered = emails.filter { $0.labelIds.contains(folder) }

            // Filter by sender if specified
            if let sender = senderFilter?.lowercased() {
                filtered = filtered.filter { $0.fromAddress.lowercased().contains(sender) }
            }

            // Apply limit
            return Array(filtered.prefix(limit))
        }

        return formatEmailList(emails)
    }

    // MARK: - Private

    private func mapFolderToLabelId(_ folder: String) -> String {
        switch folder.lowercased() {
        case "inbox": return "INBOX"
        case "sent": return "SENT"
        case "drafts", "draft": return "DRAFT"
        case "trash": return "TRASH"
        case "spam": return "SPAM"
        case "starred": return "STARRED"
        default: return folder.uppercased()
        }
    }

    private func formatEmailList(_ emails: [Email]) -> String {
        guard !emails.isEmpty else {
            return "No emails found."
        }

        var output = "Found \(emails.count) email\(emails.count == 1 ? "" : "s"):\n\n"

        for email in emails {
            output += "ID: \(email.gmailId)\n"
            output += "From: \(formatSender(email))\n"
            output += "Subject: \(email.subject)\n"
            output += "Date: \(formatDate(email.date))\n"
            output += "Unread: \(!email.isRead)\n"
            output += "Starred: \(email.isStarred)\n"
            output += "---\n"
        }

        return output
    }
}
