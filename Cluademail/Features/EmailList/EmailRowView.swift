import SwiftUI

/// Displays a single email row in the list.
struct EmailRowView: View {
    let email: Email
    let showAccountBadge: Bool
    let onStarToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            UnreadStarIndicator(
                isRead: email.isRead,
                isStarred: email.isStarred,
                onStarToggle: onStarToggle
            )

            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Sender and date
                HStack {
                    Text(displaySender)
                        .fontWeight(email.isRead ? .regular : .semibold)
                        .lineLimit(1)

                    Spacer()

                    Text(EmailListFormatters.relativeDate(from: email.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Row 2: Subject and attachment indicator
                HStack(spacing: 4) {
                    Text(EmailListFormatters.displaySubject(email.subject))
                        .foregroundStyle(email.isRead ? .secondary : .primary)
                        .lineLimit(1)

                    if !email.attachments.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Row 3: Snippet
                Text(email.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Row 4: Account badge (in aggregated view)
                if showAccountBadge, let accountEmail = email.account?.email {
                    AccountBadge(email: accountEmail)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Computed Properties

    private var displaySender: String {
        if let name = email.fromName, !name.isEmpty {
            return name
        }
        return EmailListFormatters.username(from: email.fromAddress)
    }
}

#Preview {
    List {
        EmailRowView(
            email: previewEmail(isRead: false, isStarred: true),
            showAccountBadge: false,
            onStarToggle: {}
        )

        EmailRowView(
            email: previewEmail(isRead: true, isStarred: false),
            showAccountBadge: false,
            onStarToggle: {}
        )

        EmailRowView(
            email: previewEmail(isRead: false, isStarred: false),
            showAccountBadge: true,
            onStarToggle: {}
        )
    }
    .listStyle(.inset(alternatesRowBackgrounds: true))
    .frame(width: 400, height: 400)
}

// MARK: - Preview Helpers

private func previewEmail(isRead: Bool, isStarred: Bool) -> Email {
    Email(
        gmailId: UUID().uuidString,
        threadId: UUID().uuidString,
        subject: "Meeting Tomorrow at 3pm",
        snippet: "Hi team, just a reminder about our meeting tomorrow. Please review the attached documents before we meet.",
        fromAddress: "john.doe@example.com",
        fromName: "John Doe",
        toAddresses: ["me@example.com"],
        ccAddresses: [],
        bccAddresses: [],
        date: Date().addingTimeInterval(-3600),
        isRead: isRead,
        isStarred: isStarred,
        labelIds: ["INBOX"]
    )
}
