import Foundation
import Observation
import os.log

// MARK: - SidebarItem

/// Represents a selectable item in the sidebar for native List selection binding.
enum SidebarItem: Hashable {
    case allAccounts
    case account(UUID)
    case folder(Folder)
}

/// Global application state observable by all views.
/// Marked @MainActor to ensure all state mutations occur on the main thread.
@Observable
@MainActor
final class AppState {

    // MARK: - Selection State

    /// Currently selected account, or nil for aggregated "All Accounts" view
    var selectedAccount: Account?
    var selectedFolder: Folder = .inbox
    var selectedEmail: Email?

    // MARK: - Data

    var accounts: [Account] = []

    // MARK: - Sync State

    var isSyncing: Bool = false
    var lastSyncDate: Date?

    // MARK: - MCP State

    var mcpServerRunning: Bool = false

    // MARK: - UI Refresh Triggers

    /// Version counter for triggering unread count refreshes
    var unreadCountVersion: Int = 0

    /// Increments the version to trigger UI refreshes for unread counts
    func incrementUnreadCountVersion() {
        unreadCountVersion += 1
    }

    // MARK: - Computed Properties

    /// Display title combining folder and account name
    var displayTitle: String {
        let folderName = selectedFolder.displayName
        if let account = selectedAccount {
            return "\(folderName) — \(account.displayName)"
        }
        return folderName
    }

    // MARK: - Selection Methods

    /// Selects an account and clears email selection.
    /// - Parameter account: The account to select, or nil for "All Accounts"
    func selectAccount(_ account: Account?) {
        selectedAccount = account
        selectedEmail = nil
        Logger.ui.info("Selected account: \(account?.email ?? "All Accounts", privacy: .public)")
    }

    /// Selects a folder and clears email selection.
    /// - Parameter folder: The folder to select
    func selectFolder(_ folder: Folder) {
        selectedFolder = folder
        selectedEmail = nil
        Logger.ui.info("Selected folder: \(folder.displayName)")
    }
}

// MARK: - Folder Enum

/// Represents Gmail system folders/labels
enum Folder: String, CaseIterable, Identifiable {
    case inbox = "INBOX"
    case sent = "SENT"
    case drafts = "DRAFT"
    case trash = "TRASH"
    case spam = "SPAM"
    case starred = "STARRED"
    case allMail = "ALL_MAIL"

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .trash: return "Trash"
        case .spam: return "Spam"
        case .starred: return "Starred"
        case .allMail: return "All Mail"
        }
    }

    /// SF Symbol name for folder icon
    var systemImage: String {
        switch self {
        case .inbox: return "tray"
        case .sent: return "paperplane"
        case .drafts: return "doc"
        case .trash: return "trash"
        case .spam: return "exclamationmark.triangle"
        case .starred: return "star"
        case .allMail: return "tray.full"
        }
    }
}

