import Foundation
import SwiftData
import os.log

/// MCP tool for downloading and reading attachment content.
final class GetAttachmentTool: MCPToolProtocol, @unchecked Sendable {

    let name = "get_attachment"
    let description = "Download and read the content of an email attachment. For text files, returns the content directly. For binary files, saves to a temporary location."

    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            inputSchema: JSONSchema(
                properties: [
                    "email_id": .string("Gmail message ID of the email containing the attachment (required)"),
                    "attachment_id": .string("Gmail attachment ID (required, get from read_email output)"),
                    "account": .string("Email address of the account (required)")
                ],
                required: ["email_id", "attachment_id", "account"]
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
        let attachmentId = try getString("attachment_id", from: arguments)
        let accountEmail = try getString("account", from: arguments)

        // Verify account exists
        guard try await databaseService.fetchAccount(byEmail: accountEmail) != nil else {
            throw MCPError.accountNotFound(accountEmail)
        }

        // Find attachment metadata
        let attachment = try await databaseService.performRead { context in
            let emailPredicate = #Predicate<Email> { $0.gmailId == emailId }
            var emailDescriptor = FetchDescriptor<Email>(predicate: emailPredicate)
            emailDescriptor.fetchLimit = 1

            guard let email = try context.fetch(emailDescriptor).first else {
                throw MCPError.emailNotFound(emailId)
            }

            guard let attachment = email.attachments.first(where: { $0.gmailAttachmentId == attachmentId }) else {
                throw MCPError.attachmentNotFound(attachmentId)
            }

            return attachment
        }

        // Check size limits
        if attachment.size > MCPConfiguration.maxAttachmentSize {
            throw MCPError.attachmentTooLarge(size: attachment.size, maxSize: MCPConfiguration.maxAttachmentSize)
        }

        // Verify we have tokens for this account
        guard tokenStorage.hasTokens(for: accountEmail) else {
            throw MCPError.authenticationRequired(accountEmail)
        }

        // Download attachment
        Logger.mcp.info("Downloading attachment: \(attachment.filename) (\(self.formatSize(attachment.size)))")

        let data = try await gmailAPI.getAttachment(
            accountEmail: accountEmail,
            messageId: emailId,
            attachmentId: attachmentId
        )

        return formatAttachmentResult(attachment: attachment, data: data)
    }

    // MARK: - Private

    private func formatAttachmentResult(attachment: Attachment, data: Data) -> String {
        var output = "Attachment: \(attachment.filename)\n"
        output += "Size: \(formatSize(attachment.size))\n"
        output += "Type: \(attachment.mimeType)\n\n"
        output += "--- Content ---\n"

        // Handle content based on MIME type
        if attachment.mimeType.hasPrefix("text/") || attachment.mimeType == "application/json" {
            // Text content - return directly
            if let text = String(data: data, encoding: .utf8) {
                output += text
            } else {
                output += "[Unable to decode text content]"
            }
        } else if attachment.mimeType == "application/pdf" {
            output += "[PDF file - \(formatSize(attachment.size)). Use a PDF viewer to read.]"
        } else if attachment.mimeType.hasPrefix("image/") {
            output += "[Image file - \(formatSize(attachment.size)).]"

            // For large images, save to temp file
            if attachment.size > MCPConfiguration.maxInlineAttachmentSize {
                if let tempPath = saveToTempFile(data: data, filename: attachment.filename) {
                    output += "\nSaved to: \(tempPath)"
                    output += "\n[File will be deleted in 1 hour]"
                }
            }
        } else {
            output += "[Binary file - \(formatSize(attachment.size))]"

            // For large binary files, save to temp file
            if attachment.size > MCPConfiguration.maxInlineAttachmentSize {
                if let tempPath = saveToTempFile(data: data, filename: attachment.filename) {
                    output += "\nSaved to: \(tempPath)"
                    output += "\n[File will be deleted in 1 hour]"
                }
            }
        }

        return output
    }

    private func saveToTempFile(data: Data, filename: String) -> String? {
        do {
            try MCPConfiguration.ensureAttachmentTempDirectoryExists()

            // Extract extension safely and construct a fully controlled filename
            // This prevents path traversal via URL-encoded sequences (%2F, %00, etc.)
            let ext = (filename as NSString).pathExtension
            let safeExt = ext.isEmpty ? "" : ".\(ext.filter { $0.isLetter || $0.isNumber })"
            let tempFilename = "\(UUID().uuidString)\(safeExt)"
            let tempURL = MCPConfiguration.attachmentTempDirectory.appendingPathComponent(tempFilename)

            try data.write(to: tempURL)

            Logger.mcp.info("Saved attachment to temp file: \(tempURL.path)")
            return tempURL.path
        } catch {
            Logger.mcp.error("Failed to save attachment to temp file: \(error.localizedDescription)")
            return nil
        }
    }
}
