import SwiftUI
import os.log

/// Displays sync status and manual refresh button in the sidebar footer.
struct SyncStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                if appState.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(timeAgoText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await performSync() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(appState.isSyncing)
                .help("Check for new mail")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular)
    }

    private var timeAgoText: String {
        guard let lastSync = appState.lastSyncDate else {
            return "Not synced"
        }
        return "Synced \(lastSync.formatted(.relative(presentation: .named)))"
    }

    private func performSync() async {
        // TODO: Implement actual sync in Task 06
        Logger.ui.info("Manual sync requested")
    }
}

#Preview {
    VStack {
        Spacer()
        SyncStatusView()
    }
    .frame(width: 250, height: 200)
    .environment(AppState())
}
