import SwiftUI

/// Main content view for the application.
/// This is the root view displayed in the main window.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            EmailListPlaceholderView()
        } detail: {
            EmailDetailPlaceholderView()
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle(appState.selectedFolder.displayName)
    }
}

// MARK: - Placeholder Views

/// Placeholder sidebar view (Task 07)
struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedFolder },
            set: { appState.selectedFolder = $0 }
        )) {
            Section("Folders") {
                ForEach(Folder.allCases) { folder in
                    SwiftUI.Label(folder.displayName, systemImage: folder.systemImage)
                        .tag(folder)
                }
            }

            Section("Accounts") {
                Text("No accounts configured")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }
}

/// Placeholder email list view (Task 08)
struct EmailListPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No emails")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Add an account in Settings to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 300)
    }
}

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
}
