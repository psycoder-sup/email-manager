import Foundation
import SwiftUI
import os.log

/// View model for the compose window, managing message composition and sending.
@Observable
@MainActor
final class ComposeViewModel {

    // MARK: - State

    /// Recipients
    var toRecipients: [String] = []
    var ccRecipients: [String] = []
    var bccRecipients: [String] = []

    /// Message content
    var subject: String = ""
    var body: String = ""
    var isHtml: Bool = true

    /// Attachments
    var attachments: [ComposeAttachment] = []

    /// Draft state
    var draftId: String?
    var hasChanges: Bool = false
    var lastSaveDate: Date?

    /// UI state
    var isSending: Bool = false
    var isSavingDraft: Bool = false
    var showCcBcc: Bool = false
    var errorMessage: String?

    // MARK: - Configuration

    let mode: ComposeMode
    let account: Account
    let windowId: UUID

    // MARK: - Dependencies

    private let gmailAPIService: GmailAPIService
    private let databaseService: DatabaseService
    private var autoSaveManager: DraftAutoSaveManager?

    // MARK: - Initialization

    init(
        mode: ComposeMode,
        account: Account,
        windowId: UUID,
        databaseService: DatabaseService
    ) {
        self.mode = mode
        self.account = account
        self.windowId = windowId
        self.databaseService = databaseService
        self.gmailAPIService = GmailAPIService.shared

        // Initialize from mode
        setupFromMode()

        // Set up auto-save
        setupAutoSave()
    }

    private func setupFromMode() {
        subject = mode.generateSubject()
        toRecipients = mode.generateToRecipients(currentUserEmail: account.email)
        ccRecipients = mode.generateCCRecipients(currentUserEmail: account.email)
        body = mode.generateBody()

        // Show CC/BCC if they have content
        showCcBcc = !ccRecipients.isEmpty || !bccRecipients.isEmpty

        // If editing a draft, load the draft content
        if case .draft(let email) = mode {
            draftId = email.gmailId
        }
    }

    private func setupAutoSave() {
        autoSaveManager = DraftAutoSaveManager { [weak self] in
            await self?.saveDraft()
        }
    }

    // MARK: - Content Changes

    /// Call when any content changes to track modifications.
    func contentDidChange() {
        hasChanges = true
        autoSaveManager?.scheduleAutoSave()
    }

    // MARK: - Validation

    /// Validates the message before sending.
    var validationErrors: [String] {
        var errors: [String] = []

        if toRecipients.isEmpty {
            errors.append("Please add at least one recipient")
        }

        // Validate email formats
        let allRecipients = toRecipients + ccRecipients + bccRecipients
        for recipient in allRecipients {
            if !isValidEmail(recipient) {
                errors.append("Invalid email address: \(recipient)")
            }
        }

        return errors
    }

    /// Whether the message is ready to send.
    var canSend: Bool {
        validationErrors.isEmpty && !isSending
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Sending

    /// Sends the message.
    func send() async -> Bool {
        guard canSend else {
            errorMessage = validationErrors.first
            return false
        }

        isSending = true
        errorMessage = nil

        defer { isSending = false }

        do {
            // Build attachment data
            let attachmentData = attachments.map { attachment in
                AttachmentData(
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    data: attachment.data
                )
            }

            // Get reply-to message ID if this is a reply
            let replyToMessageId: String?
            if mode.isReply, let originalEmail = mode.originalEmail {
                replyToMessageId = originalEmail.gmailId
            } else {
                replyToMessageId = nil
            }

            // Send the message
            _ = try await gmailAPIService.sendMessage(
                accountEmail: account.email,
                to: toRecipients,
                cc: ccRecipients,
                bcc: bccRecipients,
                subject: subject,
                body: body,
                isHtml: isHtml,
                replyToMessageId: replyToMessageId,
                attachments: attachmentData
            )

            Logger.ui.info("Message sent successfully")

            // Delete draft if one was saved
            if let draftId {
                try? await gmailAPIService.deleteDraft(accountEmail: account.email, draftId: draftId)
            }

            hasChanges = false
            return true

        } catch {
            Logger.ui.error("Failed to send message: \(error.localizedDescription)")
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Draft Saving

    /// Saves the current message as a draft.
    func saveDraft() async {
        guard hasChanges, !isSavingDraft else { return }

        isSavingDraft = true
        defer { isSavingDraft = false }

        do {
            // Build attachment data
            let attachmentData = attachments.map { attachment in
                AttachmentData(
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    data: attachment.data
                )
            }

            if let existingDraftId = draftId {
                // Update existing draft
                _ = try await gmailAPIService.updateDraft(
                    accountEmail: account.email,
                    draftId: existingDraftId,
                    to: toRecipients,
                    cc: ccRecipients,
                    bcc: bccRecipients,
                    subject: subject,
                    body: body,
                    isHtml: isHtml,
                    attachments: attachmentData
                )
            } else {
                // Create new draft
                let replyToMessageId: String?
                if mode.isReply, let originalEmail = mode.originalEmail {
                    replyToMessageId = originalEmail.gmailId
                } else {
                    replyToMessageId = nil
                }

                let draft = try await gmailAPIService.createDraft(
                    accountEmail: account.email,
                    to: toRecipients,
                    cc: ccRecipients,
                    bcc: bccRecipients,
                    subject: subject,
                    body: body,
                    isHtml: isHtml,
                    replyToMessageId: replyToMessageId,
                    attachments: attachmentData
                )
                draftId = draft.id
            }

            lastSaveDate = Date()
            Logger.ui.info("Draft saved")

        } catch {
            Logger.ui.error("Failed to save draft: \(error.localizedDescription)")
        }
    }

    /// Discards the current draft.
    func discardDraft() async {
        if let draftId {
            try? await gmailAPIService.deleteDraft(accountEmail: account.email, draftId: draftId)
            Logger.ui.info("Draft discarded")
        }
    }

    // MARK: - Attachments

    /// Adds attachments from file URLs.
    func addAttachments(urls: [URL]) {
        for url in urls {
            if let attachment = ComposeAttachment(url: url) {
                attachments.append(attachment)
                contentDidChange()
            }
        }
    }

    /// Removes an attachment.
    func removeAttachment(_ attachment: ComposeAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        contentDidChange()
    }

    /// Total size of all attachments in bytes.
    var totalAttachmentSize: Int64 {
        attachments.reduce(0) { $0 + $1.size }
    }

    /// Whether attachments exceed Gmail's limit (25MB).
    var attachmentSizeExceeded: Bool {
        totalAttachmentSize > 25 * 1024 * 1024
    }

    // MARK: - Recipients

    /// Adds a recipient to the specified field.
    func addRecipient(_ email: String, to field: RecipientField) {
        guard isValidEmail(email) else { return }

        switch field {
        case .to:
            if !toRecipients.contains(email) {
                toRecipients.append(email)
            }
        case .cc:
            if !ccRecipients.contains(email) {
                ccRecipients.append(email)
            }
        case .bcc:
            if !bccRecipients.contains(email) {
                bccRecipients.append(email)
            }
        }
        contentDidChange()
    }

    /// Removes a recipient from the specified field.
    func removeRecipient(_ email: String, from field: RecipientField) {
        switch field {
        case .to:
            toRecipients.removeAll { $0 == email }
        case .cc:
            ccRecipients.removeAll { $0 == email }
        case .bcc:
            bccRecipients.removeAll { $0 == email }
        }
        contentDidChange()
    }

    // MARK: - Cleanup

    /// Stops auto-save timer.
    func stopAutoSave() {
        autoSaveManager?.cancelPending()
    }
}

// MARK: - Recipient Field Type

enum RecipientField {
    case to
    case cc
    case bcc
}
