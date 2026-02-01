import SwiftUI

/// Displays a single account row or "All Accounts" option in the sidebar.
/// Pass `nil` for account to display the "All Accounts" row.
struct AccountRow: View {
    let account: Account?

    var body: some View {
        HStack(spacing: 12) {
            avatarView
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(account?.displayName ?? "All Accounts")

                if let account {
                    Text(account.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatarView: some View {
        if let account {
            accountAvatar(for: account)
        } else {
            Image(systemName: "tray.2")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func accountAvatar(for account: Account) -> some View {
        if let urlString = account.profileImageURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    accountPlaceholder
                }
            }
            .clipShape(Circle())
        } else {
            accountPlaceholder
        }
    }

    private var accountPlaceholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
    }
}

#Preview {
    List {
        AccountRow(account: nil)
        AccountRow(
            account: Account(email: "john@gmail.com", displayName: "John Doe")
        )
        AccountRow(
            account: Account(email: "jane@gmail.com", displayName: "Jane Smith")
        )
    }
    .listStyle(.sidebar)
    .frame(width: 250)
}
