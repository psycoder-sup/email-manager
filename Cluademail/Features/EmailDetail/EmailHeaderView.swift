import SwiftUI

/// Displays email header information (subject, sender, recipients, date).
struct EmailHeaderView: View {
    let email: Email

    /// Whether to show expanded recipient details
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subject
            Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(3)
                .textSelection(.enabled)

            Divider()

            // Sender row
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                senderAvatar

                VStack(alignment: .leading, spacing: 4) {
                    // Sender name/email
                    HStack {
                        Text(senderDisplayName)
                            .font(.headline)
                            .textSelection(.enabled)

                        if email.isStarred {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                        }
                    }

                    // Sender email (if name exists)
                    if email.fromName != nil {
                        Text(email.fromAddress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    // Date
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Expand/collapse button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Expanded recipient details
            if isExpanded {
                recipientDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Compact recipients line
                compactRecipients
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Subviews

    private var senderAvatar: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
            Text(avatarInitials)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
    }

    private var compactRecipients: some View {
        HStack(spacing: 4) {
            Text("to")
                .foregroundStyle(.secondary)

            Text(formattedRecipients)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var recipientDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            // To
            recipientRow(label: "To:", addresses: email.toAddresses)

            // CC
            if !email.ccAddresses.isEmpty {
                recipientRow(label: "Cc:", addresses: email.ccAddresses)
            }

            // BCC
            if !email.bccAddresses.isEmpty {
                recipientRow(label: "Bcc:", addresses: email.bccAddresses)
            }
        }
        .padding(.leading, 52) // Align with text after avatar
    }

    private func recipientRow(label: String, addresses: [String]) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(addresses.joined(separator: ", "))
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }

    // MARK: - Computed Properties

    private var senderDisplayName: String {
        email.fromName ?? email.fromAddress
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(email.date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: email.date)
        } else if calendar.isDateInYesterday(email.date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Yesterday at \(formatter.string(from: email.date))"
        } else if calendar.isDate(email.date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d 'at' h:mm a"
            return formatter.string(from: email.date)
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: email.date)
        }
    }

    private var formattedRecipients: String {
        var recipients = email.toAddresses
        if recipients.count > 3 {
            recipients = Array(recipients.prefix(2)) + ["+\(recipients.count - 2) more"]
        }
        return recipients.joined(separator: ", ")
    }

    private var avatarInitials: String {
        let name = email.fromName ?? email.fromAddress
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        // Generate consistent color from email address
        let hash = email.fromAddress.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.7)
    }
}

#Preview {
    EmailHeaderView(
        email: Email(
            gmailId: "123",
            threadId: "thread123",
            subject: "Important Meeting Tomorrow - Please Review Attached Documents",
            snippet: "Preview text...",
            fromAddress: "john.doe@example.com",
            fromName: "John Doe",
            toAddresses: ["me@example.com", "colleague@example.com"],
            ccAddresses: ["manager@example.com"],
            date: Date(),
            isRead: true,
            isStarred: true
        )
    )
    .frame(width: 600)
}
