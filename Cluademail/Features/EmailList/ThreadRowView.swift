import SwiftUI

/// Displays a thread summary row in the list.
struct ThreadRowView: View {
    let thread: EmailThread
    let showAccountBadge: Bool
    let onStarToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            UnreadStarIndicator(
                isRead: thread.isRead,
                isStarred: thread.isStarred,
                onStarToggle: onStarToggle
            )

            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Participants, message count, and date
                HStack {
                    Text(participantsDisplay)
                        .fontWeight(thread.isRead ? .regular : .semibold)
                        .lineLimit(1)

                    if thread.messageCount > 1 {
                        Text("(\(thread.messageCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(EmailListFormatters.relativeDate(from: thread.lastMessageDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Row 2: Subject
                Text(EmailListFormatters.displaySubject(thread.subject))
                    .foregroundStyle(thread.isRead ? .secondary : .primary)
                    .lineLimit(1)

                // Row 3: Snippet
                Text(thread.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Row 4: Account badge (in aggregated view)
                if showAccountBadge, let accountEmail = thread.account?.email {
                    AccountBadge(email: accountEmail)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Computed Properties

    private var participantsDisplay: String {
        let participants = thread.participantEmails
        guard !participants.isEmpty else { return "Unknown" }

        let usernames = participants.map(EmailListFormatters.username(from:))

        if usernames.count <= 3 {
            return usernames.joined(separator: ", ")
        }
        return "\(usernames.prefix(3).joined(separator: ", ")) +\(usernames.count - 3)"
    }
}

#Preview {
    List {
        ThreadRowView(
            thread: previewThread(isRead: false, isStarred: true, messageCount: 5),
            showAccountBadge: false,
            onStarToggle: {}
        )

        ThreadRowView(
            thread: previewThread(isRead: true, isStarred: false, messageCount: 1),
            showAccountBadge: false,
            onStarToggle: {}
        )

        ThreadRowView(
            thread: previewThread(isRead: false, isStarred: false, messageCount: 3),
            showAccountBadge: true,
            onStarToggle: {}
        )
    }
    .listStyle(.inset(alternatesRowBackgrounds: true))
    .frame(width: 400, height: 400)
}

// MARK: - Preview Helpers

private func previewThread(isRead: Bool, isStarred: Bool, messageCount: Int) -> EmailThread {
    EmailThread(
        threadId: UUID().uuidString,
        subject: "Project Discussion",
        snippet: "Let's finalize the project timeline and deliverables for next quarter.",
        lastMessageDate: Date().addingTimeInterval(-7200),
        messageCount: messageCount,
        isRead: isRead,
        isStarred: isStarred,
        participantEmails: ["alice@example.com", "bob@example.com", "charlie@example.com", "dave@example.com"]
    )
}
