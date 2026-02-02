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

        // Save draft to local database for immediate visibility
        try await saveDraftLocally(draft: draft, accountEmail: accountEmail)

        return formatDraftResult(draft: draft, to: toAddresses, cc: ccAddresses, subject: subject)
    }

    // MARK: - Private

    /// Saves the created draft to local database for immediate visibility.
    private func saveDraftLocally(draft: GmailDraftDTO, accountEmail: String) async throws {
        do {
            try await databaseService.performWrite { context in
                // Find the account in this context
                let predicate = #Predicate<Account> { $0.email == accountEmail }
                var descriptor = FetchDescriptor<Account>(predicate: predicate)
                descriptor.fetchLimit = 1
                guard let account = try context.fetch(descriptor).first else {
                    Logger.mcp.warning("Account not found when saving draft locally")
                    return
                }

                // Map draft to Email with draftId set (does NOT set account to avoid auto-insertion)
                let email = try GmailModelMapper.mapDraftToEmail(draft)

                // Check if draft already exists (by draftId or gmailId)
                let draftId = draft.id
                let gmailId = draft.message.id
                let existingPredicate = #Predicate<Email> {
                    $0.draftId == draftId || $0.gmailId == gmailId
                }
                var existingDescriptor = FetchDescriptor<Email>(predicate: existingPredicate)
                existingDescriptor.fetchLimit = 1

                if let existing = try context.fetch(existingDescriptor).first {
                    // Update existing
                    existing.gmailId = email.gmailId
                    existing.draftId = email.draftId
                    existing.subject = email.subject
                    existing.snippet = email.snippet
                    existing.bodyText = email.bodyText
                    existing.bodyHtml = email.bodyHtml
                    existing.toAddresses = email.toAddresses
                    existing.ccAddresses = email.ccAddresses
                    existing.labelIds = email.labelIds
                    existing.date = email.date
                    existing.account = account
                } else {
                    // Insert new - set account before inserting
                    email.account = account
                    context.insert(email)
                }
            }
            Logger.mcp.debug("Draft saved to local database: \(draft.id)")
        } catch {
            // Log but don't fail - draft was created successfully in Gmail
            Logger.mcp.warning("Failed to save draft locally: \(error.localizedDescription)")
        }
    }

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
