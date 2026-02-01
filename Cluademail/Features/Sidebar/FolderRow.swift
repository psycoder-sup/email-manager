import SwiftUI
import os.log

/// Displays a folder row with icon and unread count badge.
/// Loads unread count asynchronously using .task modifier.
struct FolderRow: View {
    let folder: Folder
    let account: Account?

    @Environment(DatabaseService.self) private var databaseService
    @State private var unreadCount: Int = 0

    var body: some View {
        HStack {
            SwiftUI.Label {
                Text(folder.displayName)
            } icon: {
                Image(systemName: folder.systemImage)
            }

            Spacer()

            if unreadCount > 0 {
                UnreadCountBadge(count: unreadCount)
            }
        }
        .contentShape(Rectangle())
        .task(id: taskId) {
            await loadUnreadCount()
        }
    }

    private var taskId: String {
        "\(account?.id.uuidString ?? "all")-\(folder.rawValue)"
    }

    @MainActor
    private func loadUnreadCount() async {
        let repository = EmailRepository()
        do {
            unreadCount = try await repository.unreadCount(
                account: account,
                folder: folder.rawValue,
                context: databaseService.mainContext
            )
        } catch {
            Logger.ui.error("Failed to load unread count for \(folder.displayName): \(error.localizedDescription)")
            unreadCount = 0
        }
    }
}

#Preview {
    List {
        FolderRow(folder: .inbox, account: nil)
        FolderRow(folder: .sent, account: nil)
        FolderRow(folder: .drafts, account: nil)
        FolderRow(folder: .starred, account: nil)
        FolderRow(folder: .trash, account: nil)
    }
    .listStyle(.sidebar)
    .frame(width: 250)
    .environment(DatabaseService(isStoredInMemoryOnly: true))
}
