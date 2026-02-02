import Foundation
import SwiftData
import os.log

/// MCP tool for adding or removing labels from an email.
final class ManageLabelsTool: MCPToolProtocol, @unchecked Sendable {

    let name = "manage_labels"
    let description = "Add or remove labels from an email. Can be used to mark as read/unread, star/unstar, move to folders, etc."

    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            inputSchema: JSONSchema(
                properties: [
                    "email_id": .string("Gmail message ID of the email to modify (required)"),
                    "account": .string("Email address of the account (required)"),
                    "add_labels": .stringArray("Label IDs to add (e.g., STARRED, IMPORTANT, or custom label IDs)"),
                    "remove_labels": .stringArray("Label IDs to remove (e.g., UNREAD to mark as read)")
                ],
                required: ["email_id", "account"]
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
        let emailId = try getString("email_id", from: arguments)
        let accountEmail = try getString("account", from: arguments)
        let addLabels = getStringArray("add_labels", from: arguments)
        let removeLabels = getStringArray("remove_labels", from: arguments)

        // Validate at least one operation
        guard !addLabels.isEmpty || !removeLabels.isEmpty else {
            throw MCPError.invalidParameter("add_labels or remove_labels (at least one required)")
        }

        // Verify account exists
        guard let account = try await databaseService.fetchAccount(byEmail: accountEmail) else {
            throw MCPError.accountNotFound(accountEmail)
        }

        // Verify email exists and belongs to account
        guard let email = try await databaseService.fetchEmail(byGmailId: emailId) else {
            throw MCPError.emailNotFound(emailId)
        }

        // Verify email belongs to the specified account
        guard email.account?.id == account.id else {
            throw MCPError.emailNotFound(emailId)
        }

        // Verify we have tokens for this account
        guard tokenStorage.hasTokens(for: accountEmail) else {
            throw MCPError.authenticationRequired(accountEmail)
        }

        // Modify labels via Gmail API
        Logger.mcp.info("Modifying labels for email \(emailId): add=\(addLabels), remove=\(removeLabels)")

        let updatedMessage = try await gmailAPI.modifyMessage(
            accountEmail: accountEmail,
            messageId: emailId,
            addLabelIds: addLabels,
            removeLabelIds: removeLabels
        )

        // Update local email with new labels
        try await databaseService.performWrite { context in
            let predicate = #Predicate<Email> { $0.gmailId == emailId }
            var descriptor = FetchDescriptor<Email>(predicate: predicate)
            descriptor.fetchLimit = 1

            if let localEmail = try context.fetch(descriptor).first {
                localEmail.labelIds = updatedMessage.labelIds ?? localEmail.labelIds
                localEmail.isRead = !(updatedMessage.labelIds?.contains("UNREAD") ?? !localEmail.isRead)
                localEmail.isStarred = updatedMessage.labelIds?.contains("STARRED") ?? localEmail.isStarred
            }
        }

        return formatLabelResult(emailId: emailId, addLabels: addLabels, removeLabels: removeLabels)
    }

    // MARK: - Private

    private func formatLabelResult(emailId: String, addLabels: [String], removeLabels: [String]) -> String {
        var output = "Labels updated for email \(emailId):\n"

        if !addLabels.isEmpty {
            output += "Added: \(addLabels.joined(separator: ", "))\n"
        }

        if !removeLabels.isEmpty {
            output += "Removed: \(removeLabels.joined(separator: ", "))\n"
        }

        return output
    }
}
