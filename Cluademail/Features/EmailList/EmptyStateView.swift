import SwiftUI

/// Displays an empty state message specific to the current folder or search.
struct EmptyStateView: View {
    let folder: Folder
    let searchQuery: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Computed Properties

    private var isSearching: Bool {
        searchQuery.map { !$0.isEmpty } ?? false
    }

    private var icon: String {
        isSearching ? "magnifyingglass" : folder.systemImage
    }

    private var title: String {
        if isSearching {
            return "No Results"
        }

        switch folder {
        case .inbox: return "Inbox is Empty"
        case .sent: return "No Sent Messages"
        case .drafts: return "No Drafts"
        case .starred: return "No Starred Messages"
        case .trash: return "Trash is Empty"
        case .spam: return "No Spam"
        case .allMail: return "No Messages"
        }
    }

    private var message: String {
        if let query = searchQuery, !query.isEmpty {
            return "No emails match \"\(query)\""
        }

        switch folder {
        case .inbox: return "New messages will appear here"
        case .sent: return "Messages you send will appear here"
        case .drafts: return "Drafts you save will appear here"
        case .starred: return "Star important messages to find them here"
        case .trash: return "Deleted messages appear here"
        case .spam: return "Messages marked as spam appear here"
        case .allMail: return "All your messages appear here"
        }
    }
}

#Preview("Inbox Empty") {
    EmptyStateView(folder: .inbox, searchQuery: nil)
        .frame(width: 400, height: 300)
}

#Preview("Search Empty") {
    EmptyStateView(folder: .inbox, searchQuery: "quarterly report")
        .frame(width: 400, height: 300)
}

#Preview("Starred Empty") {
    EmptyStateView(folder: .starred, searchQuery: nil)
        .frame(width: 400, height: 300)
}

#Preview("Trash Empty") {
    EmptyStateView(folder: .trash, searchQuery: nil)
        .frame(width: 400, height: 300)
}
