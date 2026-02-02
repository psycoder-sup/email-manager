import SwiftUI
import SwiftData
import os.log

/// Main entry point for the Cluademail application.
@main
struct CluademailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appState = AppState()
    @State private var errorHandler = ErrorHandler()
    @State private var databaseService = DatabaseService()

    /// Sync coordinator for managing email sync across accounts
    @State private var syncCoordinator: SyncCoordinator?

    /// Background sync scheduler
    @State private var syncScheduler: SyncScheduler?

    /// Notification service singleton (exposed for environment)
    private let notificationService = NotificationService.shared

    /// Manager for compose windows
    @State private var composeWindowManager = ComposeWindowManager()

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(errorHandler)
                .environment(databaseService)
                .modifier(ErrorAlertModifier(errorHandler: errorHandler))
                .task {
                    repairOrphanedEmailsIfNeeded()
                    await setupSyncSystem()
                    await setupNotifications()
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToEmail)) { notification in
                    handleNavigateToEmail(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openComposeWithReply)) { notification in
                    handleOpenComposeWithReply(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openComposeWindow)) { notification in
                    handleOpenComposeWindow(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: .syncContextDidSave)) { _ in
                    databaseService.refreshMainContext()
                }
        }
        .modelContainer(databaseService.container)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    openComposeWindow(mode: .new)
                }
                .keyboardShortcut("N", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Button("Check Mail") {
                    Task {
                        await syncScheduler?.triggerImmediateSync()
                    }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                .disabled(appState.isSyncing)
            }
        }

        // Compose windows
        WindowGroup(id: "compose", for: ComposeWindowData.self) { $windowData in
            if let data = windowData {
                ComposeView(
                    mode: data.mode,
                    account: data.account,
                    windowId: data.id,
                    onClose: {
                        composeWindowManager.closeWindow(id: data.id)
                    },
                    windowData: data
                )
                .environment(appState)
                .environment(errorHandler)
                .environment(databaseService)
            }
        }
        .modelContainer(databaseService.container)
        .windowResizability(.contentSize)
        .defaultSize(width: 640, height: 480)

        Settings {
            if let scheduler = syncScheduler {
                SettingsView()
                    .environment(appState)
                    .environment(errorHandler)
                    .environment(databaseService)
                    .environment(scheduler)
                    .environment(notificationService)
            } else {
                ProgressView("Loading...")
                    .frame(width: 500, height: 400)
            }
        }
    }

    // MARK: - Data Repair

    /// Repairs orphaned emails on app launch (one-time fix for corrupted relationships).
    @MainActor
    private func repairOrphanedEmailsIfNeeded() {
        do {
            try databaseService.repairOrphanedEmails()
        } catch {
            Logger.database.error("Failed to repair orphaned emails: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync Setup

    /// Sets up the sync system on app launch.
    @MainActor
    private func setupSyncSystem() async {
        // Create sync coordinator if not already created
        guard syncCoordinator == nil else { return }

        let coordinator = SyncCoordinator(
            appState: appState,
            databaseService: databaseService
        )
        syncCoordinator = coordinator

        // Create and start scheduler
        let scheduler = SyncScheduler(coordinator: coordinator)
        syncScheduler = scheduler

        // Auto-start background sync
        scheduler.start()
    }

    // MARK: - Notification Setup

    /// Sets up the notification system on app launch.
    @MainActor
    private func setupNotifications() async {
        // Check current authorization status
        await notificationService.checkAuthorizationStatus()
    }

    // MARK: - Notification Handlers

    /// Extracts email context from a notification's userInfo.
    private func extractEmailContext(
        from notification: Foundation.Notification
    ) -> (emailId: String, accountId: String)? {
        guard let userInfo = notification.userInfo,
              let emailId = userInfo[NotificationService.UserInfoKey.emailId] as? String,
              let accountId = userInfo[NotificationService.UserInfoKey.accountId] as? String else {
            return nil
        }
        return (emailId, accountId)
    }

    /// Handles navigation to an email from a notification tap.
    @MainActor
    private func handleNavigateToEmail(_ notification: Foundation.Notification) {
        guard let context = extractEmailContext(from: notification),
              let accountId = UUID(uuidString: context.accountId),
              let account = appState.accounts.first(where: { $0.id == accountId }) else {
            return
        }

        appState.selectAccount(account)
        // TODO: Navigate to specific email (Task 08 integration)
        Logger.ui.info("Navigate to email: \(context.emailId)")
    }

    /// Handles opening compose with reply from a notification action.
    @MainActor
    private func handleOpenComposeWithReply(_ notification: Foundation.Notification) {
        guard let context = extractEmailContext(from: notification) else {
            return
        }

        // Find the email and open reply compose
        // Note: In a full implementation, we'd fetch the email from the database
        Logger.ui.info("Open compose with reply to email: \(context.emailId) for account: \(context.accountId)")
    }

    /// Handles the openComposeWindow notification.
    @MainActor
    private func handleOpenComposeWindow(_ notification: Foundation.Notification) {
        guard let userInfo = notification.userInfo,
              let mode = userInfo["mode"] as? ComposeMode else {
            // Default to new message if no mode specified
            openComposeWindow(mode: .new)
            return
        }
        openComposeWindow(mode: mode)
    }

    /// Opens a new compose window with the specified mode.
    @MainActor
    private func openComposeWindow(mode: ComposeMode) {
        // Get the first account or use the selected account
        let account = appState.selectedAccount ?? appState.accounts.first

        guard let account else {
            Logger.ui.warning("No account available for compose")
            errorHandler.handle(ComposeError.noAccountAvailable)
            return
        }

        let windowData = composeWindowManager.createWindow(mode: mode, account: account)

        // Post notification to trigger window opening
        NotificationCenter.default.post(
            name: .openComposeWindowWithData,
            object: nil,
            userInfo: ["data": windowData]
        )

        Logger.ui.info("Opening compose window: \(mode.windowTitle)")
    }
}

// MARK: - Compose Window Data

/// Data passed to compose windows for initialization.
struct ComposeWindowData: Identifiable, Hashable, Codable {
    let id: UUID
    let modeType: String  // "new", "reply", "replyAll", "forward", "draft"
    let emailId: String?  // Gmail ID of original email (nil for .new)
    let accountEmail: String

    /// Returns a placeholder mode - actual reconstruction requires database access.
    ///
    /// For email-based modes (reply, replyAll, forward, draft), the full `ComposeMode`
    /// cannot be reconstructed here because it requires fetching the Email from the database.
    /// The actual mode reconstruction happens in `ComposeView.reconstructMode()` which has
    /// access to DatabaseService and can fetch the email using `emailId`.
    ///
    /// This property exists only for Codable conformance and initial view setup.
    var mode: ComposeMode {
        // Only .new can be fully reconstructed without database access
        if modeType == "new" || emailId == nil {
            return .new
        }
        // Return .new as placeholder - actual mode reconstruction happens in ComposeView.reconstructMode()
        return .new
    }

    var account: Account? {
        // This would need to be looked up from the database
        // For now, we'll handle this in the ComposeView
        nil
    }

    init(id: UUID = UUID(), mode: ComposeMode, account: Account) {
        self.id = id
        self.accountEmail = account.email

        switch mode {
        case .new:
            self.modeType = "new"
            self.emailId = nil
        case .reply(let email):
            self.modeType = "reply"
            self.emailId = email.gmailId
        case .replyAll(let email):
            self.modeType = "replyAll"
            self.emailId = email.gmailId
        case .forward(let email):
            self.modeType = "forward"
            self.emailId = email.gmailId
        case .draft(let email):
            self.modeType = "draft"
            self.emailId = email.gmailId
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ComposeWindowData, rhs: ComposeWindowData) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openComposeWindowWithData = Notification.Name("openComposeWindowWithData")
}

// MARK: - Compose Errors

enum ComposeError: AppError {
    case noAccountAvailable
    case sendFailed(Error)
    case draftSaveFailed(Error)

    var errorCode: String {
        switch self {
        case .noAccountAvailable: return "COMPOSE_001"
        case .sendFailed: return "COMPOSE_002"
        case .draftSaveFailed: return "COMPOSE_003"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .noAccountAvailable: return false
        case .sendFailed, .draftSaveFailed: return true
        }
    }

    var errorDescription: String? {
        switch self {
        case .noAccountAvailable:
            return "No email account available"
        case .sendFailed(let error):
            return "Failed to send message: \(error.localizedDescription)"
        case .draftSaveFailed(let error):
            return "Failed to save draft: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noAccountAvailable:
            return "Please add an email account in Settings."
        case .sendFailed:
            return "Check your internet connection and try again."
        case .draftSaveFailed:
            return "Your draft may not be saved. Try saving manually."
        }
    }
}
