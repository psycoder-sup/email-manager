import SwiftUI


/// Displays active search filters as removable chips.
struct SearchFiltersBar: View {
    @Binding var filters: SearchFilters
    let onAddFilter: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeChips, id: \.label) { chip in
                    FilterChip(label: chip.label, onRemove: chip.onRemove)
                }

                Button {
                    onAddFilter()
                } label: {
                    Label("Add filter...", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var activeChips: [ChipData] {
        var chips: [ChipData] = []

        if let from = filters.from, !from.isEmpty {
            chips.append(ChipData(
                label: "From: \(from)",
                onRemove: { filters.from = nil }
            ))
        }

        if let to = filters.to, !to.isEmpty {
            chips.append(ChipData(
                label: "To: \(to)",
                onRemove: { filters.to = nil }
            ))
        }

        if let afterDate = filters.afterDate {
            chips.append(ChipData(
                label: "After: \(afterDate.formatted(date: .abbreviated, time: .omitted))",
                onRemove: { filters.afterDate = nil }
            ))
        }

        if let beforeDate = filters.beforeDate {
            chips.append(ChipData(
                label: "Before: \(beforeDate.formatted(date: .abbreviated, time: .omitted))",
                onRemove: { filters.beforeDate = nil }
            ))
        }

        if filters.hasAttachment {
            chips.append(ChipData(
                label: "Has attachment",
                onRemove: { filters.hasAttachment = false }
            ))
        }

        if filters.isUnread {
            chips.append(ChipData(
                label: "Unread only",
                onRemove: { filters.isUnread = false }
            ))
        }

        return chips
    }
}

/// Data for a single filter chip.
private struct ChipData {
    let label: String
    let onRemove: () -> Void
}

/// A single filter chip with remove button.
struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }
}

#Preview {
    VStack {
        SearchFiltersBar(
            filters: .constant(SearchFilters(
                from: "john@example.com",
                hasAttachment: true,
                isUnread: true
            )),
            onAddFilter: {}
        )

        SearchFiltersBar(
            filters: .constant(SearchFilters()),
            onAddFilter: {}
        )
    }
}
