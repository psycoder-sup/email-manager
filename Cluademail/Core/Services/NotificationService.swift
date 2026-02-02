import Foundation
import UserNotifications
import AppKit
import os.log

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when user taps a notification to navigate to an email
    static let navigateToEmail = Notification.Name("navigateToEmail")

    /// Posted when user taps Reply on a notification
    static let openComposeWithReply = Notification.Name("openComposeWithReply")

    /// Posted when a background sync context saves, signaling the main context to refresh
    static let syncContextDidSave = Notification.Name("syncContextDidSave")
}

// MARK: - Notification Service

/// Handles macOS notifications for new email alerts.
/// Manages permission requests, notification delivery, and action handling.
@Observable
@MainActor
final class NotificationService: NSObject {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Constants

    /// Notification category identifier for new emails
    static let newEmailCategory = "NEW_EMAIL"

    /// Notification action identifiers
    enum ActionIdentifier {
        static let markRead = "MARK_READ"
        static let archive = "ARCHIVE"
        static let reply = "REPLY"
    }

    /// UserInfo keys for notification data
    enum UserInfoKey {
        static let emailId = "emailId"
        static let accountId = "accountId"
        static let accountEmail = "accountEmail"
    }

    // MARK: - Observable State

    /// Current notification authorization status
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Dependencies

    private let notificationCenter: UNUserNotificationCenter
    private let apiService: any GmailAPIServiceProtocol

    // MARK: - Initialization

    private override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        self.apiService = GmailAPIService.shared
        super.init()
    }

    /// Testing initializer with injectable dependencies
    init(
        notificationCenter: UNUserNotificationCenter,
        apiService: any GmailAPIServiceProtocol
    ) {
        self.notificationCenter = notificationCenter
        self.apiService = apiService
        super.init()
    }

    // MARK: - Setup

    /// Registers notification categories and actions. Call on app launch.
    func setupNotificationCategories() {
        let markReadAction = UNNotificationAction(
            identifier: ActionIdentifier.markRead,
            title: "Mark as Read",
            options: []
        )

        let archiveAction = UNNotificationAction(
            identifier: ActionIdentifier.archive,
            title: "Archive",
            options: [.destructive]
        )

        let replyAction = UNNotificationAction(
            identifier: ActionIdentifier.reply,
            title: "Reply",
            options: [.foreground]
        )

        let newEmailCategory = UNNotificationCategory(
            identifier: Self.newEmailCategory,
            actions: [markReadAction, archiveAction, replyAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([newEmailCategory])
        Logger.ui.info("Notification categories registered")
    }

    // MARK: - Authorization

    /// Requests notification authorization from the user.
    /// - Returns: True if authorization was granted
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )

            await checkAuthorizationStatus()

            if granted {
                Logger.ui.info("Notification authorization granted")
            } else {
                Logger.ui.info("Notification authorization denied")
            }

            return granted
        } catch {
            Logger.ui.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }

    /// Checks and updates the current authorization status.
    /// - Returns: The current authorization status
    @discardableResult
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        return authorizationStatus
    }

    /// Opens macOS System Settings to the Notifications pane.
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Notification Sending

    /// Sends a notification for a new email.
    /// - Parameters:
    ///   - email: The new email
    ///   - account: The account the email belongs to
    func sendNewEmailNotification(email: Email, account: Account) async {
        // Check if notifications are enabled (default to true for first run)
        let notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard notificationsEnabled else {
            return
        }

        // Check authorization
        let status = await checkAuthorizationStatus()
        guard status == .authorized else {
            Logger.ui.debug("Skipping notification - not authorized")
            return
        }

        let content = UNMutableNotificationContent()

        // Title: Sender name or email
        content.title = email.fromName ?? email.fromAddress

        // Subtitle: Subject
        if !email.subject.isEmpty {
            content.subtitle = email.subject
        }

        // Body: Snippet
        if !email.snippet.isEmpty {
            content.body = email.snippet
        }

        // Sound (default to true for first run)
        let soundEnabled = UserDefaults.standard.object(forKey: "notificationSound") as? Bool ?? true
        if soundEnabled {
            content.sound = .default
        }

        // Category for actions
        content.categoryIdentifier = Self.newEmailCategory

        // Thread identifier groups by account
        content.threadIdentifier = account.email

        // User info for action handling
        content.userInfo = [
            UserInfoKey.emailId: email.gmailId,
            UserInfoKey.accountId: account.id.uuidString,
            UserInfoKey.accountEmail: account.email
        ]

        let request = UNNotificationRequest(
            identifier: "\(account.id.uuidString)-\(email.gmailId)",
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await notificationCenter.add(request)
            Logger.ui.debug("Notification sent for email")
        } catch {
            Logger.ui.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Badge Management

    /// Updates the dock badge count.
    /// - Parameter count: The unread count to display (0 to clear)
    func updateBadgeCount(_ count: Int) {
        // Check badge setting (default to true for first run)
        let badgeEnabled = UserDefaults.standard.object(forKey: "notificationBadge") as? Bool ?? true
        guard badgeEnabled else {
            // Clear badge if disabled
            NSApplication.shared.dockTile.badgeLabel = nil
            return
        }

        if count > 0 {
            NSApplication.shared.dockTile.badgeLabel = count > 99 ? "99+" : "\(count)"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }

    /// Clears all notifications for a specific account.
    /// - Parameter accountId: The account ID to clear notifications for
    func clearNotifications(for accountId: UUID) async {
        let notifications = await notificationCenter.deliveredNotifications()

        let idsToRemove = notifications.compactMap { notification -> String? in
            guard let notifAccountId = notification.request.content.userInfo[UserInfoKey.accountId] as? String,
                  notifAccountId == accountId.uuidString else {
                return nil
            }
            return notification.request.identifier
        }

        notificationCenter.removeDeliveredNotifications(withIdentifiers: idsToRemove)

        if !idsToRemove.isEmpty {
            Logger.ui.debug("Cleared \(idsToRemove.count) notifications for account")
        }
    }

    // MARK: - Action Handling

    /// Handles the Mark as Read notification action.
    func handleMarkReadAction(emailId: String, accountEmail: String) async {
        await modifyEmailFromNotification(
            emailId: emailId,
            accountEmail: accountEmail,
            removeLabelIds: ["UNREAD"],
            actionName: "Mark Read"
        )
    }

    /// Handles the Archive notification action.
    func handleArchiveAction(emailId: String, accountEmail: String) async {
        await modifyEmailFromNotification(
            emailId: emailId,
            accountEmail: accountEmail,
            removeLabelIds: ["INBOX"],
            actionName: "Archive"
        )
    }

    /// Modifies an email from a notification action.
    private func modifyEmailFromNotification(
        emailId: String,
        accountEmail: String,
        addLabelIds: [String] = [],
        removeLabelIds: [String] = [],
        actionName: String
    ) async {
        Logger.ui.info("Handling \(actionName) action")

        do {
            _ = try await apiService.modifyMessage(
                accountEmail: accountEmail,
                messageId: emailId,
                addLabelIds: addLabelIds,
                removeLabelIds: removeLabelIds
            )
            Logger.ui.info("Email \(actionName.lowercased()) via notification action")
        } catch {
            Logger.ui.error("Failed to \(actionName.lowercased()) email: \(error.localizedDescription)")
        }
    }

    /// Handles the Reply notification action by posting a notification to open compose.
    func handleReplyAction(emailId: String, accountId: String) async {
        Logger.ui.info("Handling Reply action")
        postEmailNotification(.openComposeWithReply, emailId: emailId, accountId: accountId)
    }

    /// Handles the default notification tap by posting a navigation notification.
    func handleDefaultAction(emailId: String, accountId: String) async {
        Logger.ui.info("Handling default notification tap")
        postEmailNotification(.navigateToEmail, emailId: emailId, accountId: accountId)
    }

    /// Posts a Foundation notification with email context.
    private func postEmailNotification(
        _ name: Foundation.Notification.Name,
        emailId: String,
        accountId: String
    ) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [
                UserInfoKey.emailId: emailId,
                UserInfoKey.accountId: accountId
            ]
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Called when a notification is about to be displayed while app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notifications even when app is in foreground
        return [.banner, .sound, .badge]
    }

    /// Called when user interacts with a notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        guard let emailId = userInfo[UserInfoKey.emailId] as? String,
              let accountId = userInfo[UserInfoKey.accountId] as? String,
              let accountEmail = userInfo[UserInfoKey.accountEmail] as? String else {
            Logger.ui.error("Invalid notification userInfo")
            return
        }

        // Call MainActor methods - they will hop to main actor automatically
        switch response.actionIdentifier {
        case ActionIdentifier.markRead:
            await handleMarkReadAction(emailId: emailId, accountEmail: accountEmail)

        case ActionIdentifier.archive:
            await handleArchiveAction(emailId: emailId, accountEmail: accountEmail)

        case ActionIdentifier.reply:
            await handleReplyAction(emailId: emailId, accountId: accountId)

        case UNNotificationDefaultActionIdentifier:
            await handleDefaultAction(emailId: emailId, accountId: accountId)

        default:
            break
        }
    }
}
