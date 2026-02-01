import SwiftUI
import os.log

/// Main sidebar view containing accounts list and folder navigation.
struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(DatabaseService.self) private var databaseService

    var body: some View {
        List {
            Section("Accounts") {
                AccountRow(account: nil, isSelected: appState.selectedAccount == nil)
                    .onTapGesture {
                        appState.selectAccount(nil)
                    }

                ForEach(appState.accounts) { account in
                    AccountRow(
                        account: account,
                        isSelected: appState.selectedAccount?.id == account.id
                    )
                    .onTapGesture {
                        appState.selectAccount(account)
                    }
                }
            }

            Section("Folders") {
                ForEach(Folder.allCases) { folder in
                    FolderRow(
                        folder: folder,
                        account: appState.selectedAccount,
                        isSelected: appState.selectedFolder == folder
                    )
                    .onTapGesture {
                        appState.selectFolder(folder)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SyncStatusView()
        }
        .frame(minWidth: 200)
        .task {
            await loadAccounts()
        }
    }

    private func loadAccounts() async {
        let repository = AccountRepository()
        do {
            appState.accounts = try await repository.fetchAll(context: databaseService.mainContext)
            Logger.ui.info("Loaded \(appState.accounts.count) accounts")
        } catch {
            Logger.ui.error("Failed to load accounts: \(error.localizedDescription)")
        }
    }
}

#Preview {
    SidebarView()
        .frame(width: 250, height: 500)
        .environment(AppState())
        .environment(DatabaseService(isStoredInMemoryOnly: true))
}
