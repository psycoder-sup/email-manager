import Foundation
import SwiftData

/// MCP tool for reading the full content of a specific email.
final class ReadEmailTool: MCPToolProtocol, @unchecked Sendable {

    let name = "read_email"
    let description = "Get the full content of a specific email including body, recipients, and attachments."

    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            inputSchema: JSONSchema(
                properties: [
                    "email_id": .string("Gmail message ID of the email to read (required)"),
                    "account": .string("Email address of the account (required)")
                ],
                required: ["email_id", "account"]
            )
        )
    }

    private let databaseService: MCPDatabaseService

    init(databaseService: MCPDatabaseService) {
        self.databaseService = databaseService
    }

    func execute(arguments: [String: AnyCodable]?) async throws -> String {
        let emailId = try getString("email_id", from: arguments)
        let accountEmail = try getString("account", from: arguments)

        let email = try await databaseService.performRead { context in
            // Find account
            let accountPredicate = #Predicate<Account> { $0.email == accountEmail }
            var accountDescriptor = FetchDescriptor<Account>(predicate: accountPredicate)
            accountDescriptor.fetchLimit = 1

            guard let account = try context.fetch(accountDescriptor).first else {
                throw MCPError.accountNotFound(accountEmail)
            }

            // Find email
            let emailPredicate = #Predicate<Email> { $0.gmailId == emailId }
            var emailDescriptor = FetchDescriptor<Email>(predicate: emailPredicate)
            emailDescriptor.fetchLimit = 1

            guard let email = try context.fetch(emailDescriptor).first else {
                throw MCPError.emailNotFound(emailId)
            }

            // Verify email belongs to account
            guard email.account?.id == account.id else {
                throw MCPError.emailNotFound(emailId)
            }

            return email
        }

        return formatEmailDetail(email)
    }

    // MARK: - Private

    private func formatEmailDetail(_ email: Email) -> String {
        var output = ""

        output += "ID: \(email.gmailId)\n"
        output += "Thread ID: \(email.threadId)\n"
        output += "From: \(formatSender(email))\n"
        output += "To: \(email.toAddresses.joined(separator: ", "))\n"

        if !email.ccAddresses.isEmpty {
            output += "Cc: \(email.ccAddresses.joined(separator: ", "))\n"
        }

        if !email.bccAddresses.isEmpty {
            output += "Bcc: \(email.bccAddresses.joined(separator: ", "))\n"
        }

        output += "Subject: \(email.subject)\n"
        output += "Date: \(formatDate(email.date))\n"
        output += "Labels: \(email.labelIds.joined(separator: ", "))\n"

        output += "\n--- Body ---\n"

        // Prefer plain text, fallback to stripped HTML, then snippet
        if let bodyText = email.bodyText, !bodyText.isEmpty {
            output += bodyText
        } else if let bodyHtml = email.bodyHtml, !bodyHtml.isEmpty {
            output += stripHtml(bodyHtml)
        } else {
            output += email.snippet
        }

        // Attachments
        if !email.attachments.isEmpty {
            output += "\n\n--- Attachments ---\n"
            for attachment in email.attachments {
                output += "- \(attachment.filename) (\(formatSize(attachment.size)), \(attachment.mimeType))\n"
                output += "  ID: \(attachment.gmailAttachmentId)\n"
            }
        }

        return output
    }
}
