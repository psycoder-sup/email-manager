import Foundation
import SwiftData
import os.log

/// MCP tool for creating email drafts.
/// NOTE: This tool creates drafts only - it cannot send emails directly.
final class CreateDraftTool: MCPToolProtocol, @unchecked Sendable {

    let name = "create_draft"
    let description = "Create a draft email. The user must manually review and send the draft from the Cluademail app or Gmail. This tool cannot send emails directly."

    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            inputSchema: JSONSchema(
                properties: [
                    "account": .string("Email address of the account to create the draft in (required)"),
                    "to": .stringArray("Recipient email addresses (required)"),
                    "cc": .stringArray("CC recipient email addresses"),
                    "subject": .string("Email subject (required)"),
                    "body": .string("Email body content (required)"),
                    "reply_to_id": .string("Gmail message ID if this is a reply to an existing email")
                ],
                required: ["account", "to", "subject", "body"]
            )
        )
    }

    private let databaseService: MCPDatabaseService
    private let gmailAPI: GmailAPIServiceProtocol
    private let tokenStorage: FileTokenStorage

    init(databaseService: MCPDatabaseService, gmailAPI: GmailAPIServiceProtocol, tokenStorage: FileTokenStorage) {
        self.databaseService = databaseService
        self.gmailAPI = gmailAPI
        self.tokenStorage = tokenStorage
    }

    func execute(arguments: [String: AnyCodable]?) async throws -> String {
        // Extract parameters
        let accountEmail = try getString("account", from: arguments)
        let toAddresses = getStringArray("to", from: arguments)
        let ccAddresses = getStringArray("cc", from: arguments)
        let subject = try getString("subject", from: arguments)
        let body = try getString("body", from: arguments)
        let replyToId = getOptionalString("reply_to_id", from: arguments)

        // Validate recipients
        guard !toAddresses.isEmpty else {
            throw MCPError.invalidParameter("to (must have at least one recipient)")
        }

        // Verify account exists
        guard try await databaseService.fetchAccount(byEmail: accountEmail) != nil else {
            throw MCPError.accountNotFound(accountEmail)
        }

        // Verify we have tokens for this account
        guard tokenStorage.hasTokens(for: accountEmail) else {
            throw MCPError.authenticationRequired(accountEmail)
        }

        // Create draft via Gmail API
        Logger.mcp.info("Creating draft for account: \(accountEmail, privacy: .private(mask: .hash))")

        let draft = try await gmailAPI.createDraft(
            accountEmail: accountEmail,
            to: toAddresses,
            cc: ccAddresses,
            bcc: [],
            subject: subject,
            body: body,
            isHtml: false,
            replyToMessageId: replyToId,
            attachments: []
        )

        return formatDraftResult(draft: draft, to: toAddresses, cc: ccAddresses, subject: subject)
    }

    // MARK: - Private

    private func formatDraftResult(draft: GmailDraftDTO, to: [String], cc: [String], subject: String) -> String {
        var output = "Draft created successfully!\n\n"
        output += "Draft ID: \(draft.id)\n"
        output += "To: \(to.joined(separator: ", "))\n"

        if !cc.isEmpty {
            output += "Cc: \(cc.joined(separator: ", "))\n"
        }

        output += "Subject: \(subject)\n\n"
        output += "Note: The user must manually review and send this draft from the Cluademail app or Gmail."

        return output
    }
}
