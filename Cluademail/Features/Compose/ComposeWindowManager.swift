import Foundation
import SwiftUI
import os.log

/// Manages multiple compose windows and their state.
@Observable
@MainActor
final class ComposeWindowManager {

    // MARK: - State

    /// Active compose windows
    private(set) var windows: [UUID: ComposeWindowState] = [:]

    // MARK: - Window Management

    /// Creates a new compose window.
    /// - Parameters:
    ///   - mode: The compose mode (new, reply, forward, etc.)
    ///   - account: The account to send from
    /// - Returns: Window data for opening the window
    func createWindow(mode: ComposeMode, account: Account) -> ComposeWindowData {
        let id = UUID()
        let state = ComposeWindowState(id: id, mode: mode, account: account)
        windows[id] = state

        Logger.ui.info("Created compose window: \(id)")

        return ComposeWindowData(id: id, mode: mode, account: account)
    }

    /// Closes a compose window.
    /// - Parameter id: The window ID to close
    func closeWindow(id: UUID) {
        windows.removeValue(forKey: id)
        Logger.ui.info("Closed compose window: \(id)")
    }

    /// Gets the state for a specific window.
    /// - Parameter id: The window ID
    /// - Returns: The window state if it exists
    func getWindowState(id: UUID) -> ComposeWindowState? {
        windows[id]
    }

    /// Updates the window state.
    /// - Parameters:
    ///   - id: The window ID
    ///   - update: A closure that modifies the state
    func updateWindow(id: UUID, update: (inout ComposeWindowState) -> Void) {
        guard var state = windows[id] else { return }
        update(&state)
        windows[id] = state
    }

    /// Checks if any windows have unsaved changes.
    var hasUnsavedChanges: Bool {
        windows.values.contains { $0.hasChanges && !$0.isSaved }
    }

    /// Gets all windows with unsaved changes.
    var unsavedWindows: [ComposeWindowState] {
        windows.values.filter { $0.hasChanges && !$0.isSaved }
    }
}

// MARK: - Window State

/// State for a single compose window.
struct ComposeWindowState: Identifiable {
    let id: UUID
    let mode: ComposeMode
    let account: Account

    // Content state
    var toRecipients: [String] = []
    var ccRecipients: [String] = []
    var bccRecipients: [String] = []
    var subject: String = ""
    var body: String = ""
    var attachments: [ComposeAttachment] = []

    // Draft state
    var draftId: String?
    var hasChanges: Bool = false
    var isSaved: Bool = false
    var lastSaveDate: Date?

    // UI state
    var isSending: Bool = false
    var isSavingDraft: Bool = false

    init(id: UUID, mode: ComposeMode, account: Account) {
        self.id = id
        self.mode = mode
        self.account = account

        // Pre-fill based on mode
        self.subject = mode.generateSubject()
        self.toRecipients = mode.generateToRecipients(currentUserEmail: account.email)
        self.ccRecipients = mode.generateCCRecipients(currentUserEmail: account.email)
        self.body = mode.generateBody()
    }
}

// MARK: - Compose Attachment

/// Represents an attachment being added to a compose message.
struct ComposeAttachment: Identifiable {
    let id: UUID
    let filename: String
    let mimeType: String
    let size: Int64
    let data: Data

    /// Creates an attachment from a file URL.
    init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }

        self.id = UUID()
        self.filename = url.lastPathComponent
        self.mimeType = Self.mimeType(for: url)
        self.size = Int64(data.count)
        self.data = data
    }

    /// Creates an attachment from raw data.
    init(filename: String, mimeType: String, data: Data) {
        self.id = UUID()
        self.filename = filename
        self.mimeType = mimeType
        self.size = Int64(data.count)
        self.data = data
    }

    /// Determines MIME type from file extension.
    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "zip": return "application/zip"
        case "txt": return "text/plain"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        case "xml": return "application/xml"
        default: return "application/octet-stream"
        }
    }

    /// Human-readable file size.
    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
