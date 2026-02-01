import SwiftUI
import SwiftData

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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(errorHandler)
                .environment(databaseService)
                .modifier(ErrorAlertModifier(errorHandler: errorHandler))
                .task {
                    await setupSyncSystem()
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
            SettingsView()
                .environment(appState)
                .environment(errorHandler)
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
}
