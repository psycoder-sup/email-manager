import SwiftUI

/// Displays search history and search tips as suggestions.
struct SearchSuggestionsView: View {
    @Binding var searchQuery: String
    let history: [SearchHistoryItem]
    let onSelect: (SearchHistoryItem) -> Void
    let onDelete: (UUID) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recent searches section
            if !filteredHistory.isEmpty {
                Section {
                    ForEach(filteredHistory) { item in
                        SearchHistoryRow(
                            item: item,
                            onSelect: { onSelect(item) },
                            onDelete: { onDelete(item.id) }
                        )
                    }
                } header: {
                    HStack {
                        Text("Recent Searches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear All") {
                            onClearAll()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }

            // Search tips section
            Section {
                SearchTipRow(tip: "from:email", description: "Search by sender")
                SearchTipRow(tip: "to:email", description: "Search by recipient")
                SearchTipRow(tip: "subject:text", description: "Search in subject")
                SearchTipRow(tip: "has:attachment", description: "Emails with attachments")
                SearchTipRow(tip: "is:unread", description: "Unread emails only")
                SearchTipRow(tip: "after:2024/01/01", description: "Emails after date")
            } header: {
                Text("Search Tips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
    }

    private var filteredHistory: [SearchHistoryItem] {
        if searchQuery.isEmpty {
            return Array(history.prefix(5))
        }
        let query = searchQuery.lowercased()
        return history
            .filter { $0.query.lowercased().contains(query) }
            .prefix(5)
            .map { $0 }
    }
}

/// A single search history row.
struct SearchHistoryRow: View {
    let item: SearchHistoryItem
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.query)
                        .lineLimit(1)

                    Text(item.date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A search tip row showing operator syntax.
struct SearchTipRow: View {
    let tip: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.yellow)

            Text(tip)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.blue)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

#Preview {
    SearchSuggestionsView(
        searchQuery: .constant(""),
        history: [
            SearchHistoryItem(query: "quarterly report"),
            SearchHistoryItem(query: "from:john@example.com"),
            SearchHistoryItem(query: "project update")
        ],
        onSelect: { _ in },
        onDelete: { _ in },
        onClearAll: {}
    )
    .frame(width: 350)
}
