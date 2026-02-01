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
            EmailDetailPlaceholderView()
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle(appState.displayTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    // TODO: Implement in Task 09
                    Logger.ui.info("Compose button tapped")
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("Compose new message")

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
}

// MARK: - Placeholder Views

/// Placeholder email detail view (Task 09)
struct EmailDetailPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.open")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select an email")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(ErrorHandler())
        .environment(DatabaseService(isStoredInMemoryOnly: true))
}
