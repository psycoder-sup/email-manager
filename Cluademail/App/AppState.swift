import Foundation
import Observation

/// Global application state observable by all views.
/// Marked @MainActor to ensure all state mutations occur on the main thread.
@Observable
@MainActor
final class AppState {

    // MARK: - Selection State

    /// Currently selected account (nil = all accounts / aggregated view)
    var selectedAccount: Account?

    /// Currently selected folder
    var selectedFolder: Folder = .inbox

    /// Currently selected email for detail view
    var selectedEmail: Email?

    // MARK: - Sync State

    /// Whether a sync operation is in progress
    var isSyncing: Bool = false

    /// Last sync date across all accounts
    var lastSyncDate: Date?

    // MARK: - MCP State

    /// Whether the MCP server is currently running
    var mcpServerRunning: Bool = false
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

// MARK: - Placeholder Types (to be replaced in Task 02)

/// Placeholder for Account model (Task 02)
struct Account: Identifiable, Hashable {
    let id: UUID
    let email: String
    let displayName: String
}

/// Placeholder for Email model (Task 02)
struct Email: Identifiable, Hashable {
    let id: String
    let subject: String
    let snippet: String
}
