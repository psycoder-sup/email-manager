import Foundation
import SwiftData
import os.log

/// View model for the email detail view, managing email loading and actions.
@Observable
@MainActor
final class EmailDetailViewModel {

    // MARK: - State

    /// The currently displayed email (nil if not loaded or no selection)
    private(set) var email: Email?

    /// HTML body with CID references resolved to data URIs
    private(set) var resolvedBodyHtml: String?

    /// Whether the full email content is loading
    private(set) var isLoading: Bool = false

    /// Error message if loading failed
    private(set) var errorMessage: String?

    /// Whether external images should be loaded
    var loadExternalImages: Bool = false

    // MARK: - Dependencies

    private let gmailAPIService: GmailAPIService
    private let databaseService: DatabaseService
    private let cidResolver: CIDResolver

    // MARK: - Initialization

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
        self.gmailAPIService = GmailAPIService.shared
        self.cidResolver = CIDResolver()
    }

    // MARK: - Loading

    /// Sets and potentially loads full content for an email.
    /// - Parameter email: The email to display
    func setEmail(_ email: Email?) async {
        self.email = email
        self.errorMessage = nil
        self.loadExternalImages = false
        self.resolvedBodyHtml = nil

        guard let email else { return }

        // If body is already loaded, resolve CIDs and mark as read
        if email.bodyHtml != nil || email.bodyText != nil {
            await resolveCIDsIfNeeded(email)
            await markAsReadIfNeeded(email)
            return
        }

        // Load full email content
        await loadFullEmail(email)
    }

    /// Resolves CID references in HTML body to data URIs.
    private func resolveCIDsIfNeeded(_ email: Email) async {
        guard let html = email.bodyHtml, !email.attachments.isEmpty else {
            resolvedBodyHtml = email.bodyHtml
            return
        }

        // Check if there are any CID references to resolve
        if html.contains("cid:") {
            resolvedBodyHtml = await cidResolver.resolveAllCIDs(in: html, email: email)
        } else {
            resolvedBodyHtml = html
        }
    }

    /// Loads the full content of an email from Gmail API.
    private func loadFullEmail(_ email: Email) async {
        guard let account = email.account else {
            errorMessage = "No account associated with email"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fullMessage = try await gmailAPIService.getMessage(
                accountEmail: account.email,
                messageId: email.gmailId
            )

            // Update email with full content
            let updatedEmail = try GmailModelMapper.mapToEmail(fullMessage, account: account)
            email.bodyHtml = updatedEmail.bodyHtml
            email.bodyText = updatedEmail.bodyText

            // Update attachments if they were re-parsed
            if email.attachments.isEmpty && !updatedEmail.attachments.isEmpty {
                for attachment in updatedEmail.attachments {
                    attachment.email = email
                }
                email.attachments = updatedEmail.attachments
            }

            try databaseService.mainContext.save()

            Logger.ui.info("Loaded full email content for: \(email.gmailId, privacy: .private)")

            // Resolve CID references after loading
            await resolveCIDsIfNeeded(email)
            await markAsReadIfNeeded(email)

        } catch {
            Logger.ui.error("Failed to load email content: \(error.localizedDescription)")
            errorMessage = "Failed to load email content"
        }
    }

    /// Marks the email as read if it's currently unread.
    private func markAsReadIfNeeded(_ email: Email) async {
        guard !email.isRead, let account = email.account else { return }

        do {
            _ = try await gmailAPIService.modifyMessage(
                accountEmail: account.email,
                messageId: email.gmailId,
                addLabelIds: [],
                removeLabelIds: ["UNREAD"]
            )

            email.isRead = true
            email.labelIds.removeAll { $0 == "UNREAD" }
            try databaseService.mainContext.save()

            Logger.ui.info("Marked email as read: \(email.gmailId, privacy: .private)")
        } catch {
            Logger.ui.error("Failed to mark as read: \(error.localizedDescription)")
        }
    }

    // MARK: - Actions

    /// Toggles the star status of the current email.
    func toggleStar() async {
        guard let email, let account = email.account else { return }

        do {
            let addLabels = email.isStarred ? [] : ["STARRED"]
            let removeLabels = email.isStarred ? ["STARRED"] : []

            _ = try await gmailAPIService.modifyMessage(
                accountEmail: account.email,
                messageId: email.gmailId,
                addLabelIds: addLabels,
                removeLabelIds: removeLabels
            )

            email.isStarred.toggle()
            if email.isStarred {
                if !email.labelIds.contains("STARRED") {
                    email.labelIds.append("STARRED")
                }
            } else {
                email.labelIds.removeAll { $0 == "STARRED" }
            }
            try databaseService.mainContext.save()

            Logger.ui.info("Toggled star: \(email.isStarred)")
        } catch {
            Logger.ui.error("Failed to toggle star: \(error.localizedDescription)")
        }
    }

    /// Archives the current email (removes from inbox).
    func archive() async {
        guard let email, let account = email.account else { return }

        do {
            _ = try await gmailAPIService.modifyMessage(
                accountEmail: account.email,
                messageId: email.gmailId,
                addLabelIds: [],
                removeLabelIds: ["INBOX"]
            )

            email.labelIds.removeAll { $0 == "INBOX" }
            try databaseService.mainContext.save()

            Logger.ui.info("Archived email: \(email.gmailId, privacy: .private)")
        } catch {
            Logger.ui.error("Failed to archive: \(error.localizedDescription)")
        }
    }

    /// Moves the current email to trash.
    func moveToTrash() async {
        guard let email, let account = email.account else { return }

        do {
            try await gmailAPIService.trashMessage(
                accountEmail: account.email,
                messageId: email.gmailId
            )

            email.labelIds.removeAll { $0 == "INBOX" }
            if !email.labelIds.contains("TRASH") {
                email.labelIds.append("TRASH")
            }
            try databaseService.mainContext.save()

            Logger.ui.info("Trashed email: \(email.gmailId, privacy: .private)")
        } catch {
            Logger.ui.error("Failed to trash: \(error.localizedDescription)")
        }
    }

    /// Marks the current email as read.
    func markAsRead() async {
        guard let email, !email.isRead else { return }
        await markAsReadIfNeeded(email)
    }

    /// Marks the current email as unread.
    func markAsUnread() async {
        guard let email, email.isRead, let account = email.account else { return }

        do {
            _ = try await gmailAPIService.modifyMessage(
                accountEmail: account.email,
                messageId: email.gmailId,
                addLabelIds: ["UNREAD"],
                removeLabelIds: []
            )

            email.isRead = false
            if !email.labelIds.contains("UNREAD") {
                email.labelIds.append("UNREAD")
            }
            try databaseService.mainContext.save()

            Logger.ui.info("Marked as unread: \(email.gmailId, privacy: .private)")
        } catch {
            Logger.ui.error("Failed to mark as unread: \(error.localizedDescription)")
        }
    }

    /// Enables loading of external images.
    func allowExternalImages() {
        loadExternalImages = true
    }

    // MARK: - Reply/Forward Helpers

    /// Gets the display name or email address for the sender.
    var senderDisplayName: String {
        guard let email else { return "" }
        return email.fromName ?? email.fromAddress
    }

    /// Gets the formatted date for display.
    var formattedDate: String {
        guard let email else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: email.date)
    }

    /// Gets recipients formatted for display.
    var formattedRecipients: String {
        guard let email else { return "" }
        var recipients = email.toAddresses
        if recipients.count > 3 {
            recipients = Array(recipients.prefix(2)) + ["+\(recipients.count - 2) more"]
        }
        return recipients.joined(separator: ", ")
    }

    /// Gets CC recipients formatted for display.
    var formattedCC: String? {
        guard let email, !email.ccAddresses.isEmpty else { return nil }
        return email.ccAddresses.joined(separator: ", ")
    }
}
