import SwiftUI
import SwiftData

/// Main entry point for the Cluademail application.
@main
struct CluademailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appState = AppState()
    @State private var errorHandler = ErrorHandler()
    @State private var databaseService = DatabaseService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(errorHandler)
                .environment(databaseService)
                .modifier(ErrorAlertModifier(errorHandler: errorHandler))
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
