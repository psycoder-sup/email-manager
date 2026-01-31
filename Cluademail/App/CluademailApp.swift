import SwiftUI
import SwiftData

/// Main entry point for the Cluademail application.
@main
struct CluademailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appState = AppState()
    @State private var errorHandler = ErrorHandler()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Account.self,
            Email.self,
            EmailThread.self,
            Attachment.self,
            Label.self,
            SyncState.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(errorHandler)
                .modifier(ErrorAlertModifier(errorHandler: errorHandler))
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    // TODO: Implement in Task 09
                }
                .keyboardShortcut("N", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Button("Check Mail") {
                    // TODO: Implement in Task 06
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(errorHandler)
        }
    }
}
