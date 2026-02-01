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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(errorHandler)
                .environment(databaseService)
                .modifier(ErrorAlertModifier(errorHandler: errorHandler))
                .task {
                    await setupSyncSystem()
                    await setupNotifications()
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToEmail)) { notification in
                    handleNavigateToEmail(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openComposeWithReply)) { notification in
                    handleOpenComposeWithReply(notification)
                }
        }
        .modelContainer(databaseService.container)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    // TODO: Implement in Task 09
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

        // TODO: Open compose window with reply context (Task 09 integration)
        Logger.ui.info("Open compose with reply to email: \(context.emailId) for account: \(context.accountId)")
    }
}
