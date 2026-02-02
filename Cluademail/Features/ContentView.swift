import SwiftUI
import os.log

/// Main content view for the application.
/// This is the root view displayed in the main window.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            EmailListView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
        } detail: {
            EmailDetailView()
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle(appState.displayTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openComposeWindow(mode: .new)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("Compose new message")
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    // TODO: Implement in Task 06
                    Logger.ui.info("Refresh button tapped")
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Check for new mail")
                .disabled(appState.isSyncing)
            }
        }
    }

    /// Opens a compose window with the specified mode.
    private func openComposeWindow(mode: ComposeMode) {
        NotificationCenter.default.post(
            name: .openComposeWindow,
            object: nil,
            userInfo: ["mode": mode]
        )
        Logger.ui.info("Opening compose window: \(mode.windowTitle)")
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(ErrorHandler())
        .environment(DatabaseService(isStoredInMemoryOnly: true))
}
