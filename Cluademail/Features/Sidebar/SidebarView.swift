import SwiftUI
import os.log

/// Main sidebar view containing accounts list and folder navigation.
struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(DatabaseService.self) private var databaseService

    @State private var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Accounts") {
                AccountRow(account: nil)
                    .tag(SidebarItem.allAccounts)

                ForEach(appState.accounts) { account in
                    AccountRow(account: account)
                        .tag(SidebarItem.account(account.id))
                }
            }

            Section("Folders") {
                ForEach(Folder.allCases) { folder in
                    FolderRow(folder: folder, account: appState.selectedAccount)
                        .tag(SidebarItem.folder(folder))
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, newValue in
            handleSelectionChange(newValue)
        }
        .onAppear {
            selection = .folder(appState.selectedFolder)
        }
        .safeAreaInset(edge: .bottom) {
            SyncStatusView()
        }
        .frame(minWidth: 200)
        .task {
            await loadAccounts()
        }
    }

    private func handleSelectionChange(_ item: SidebarItem?) {
        switch item {
        case .allAccounts:
            appState.selectAccount(nil)
        case .account(let id):
            if let account = appState.accounts.first(where: { $0.id == id }) {
                appState.selectAccount(account)
            }
        case .folder(let folder):
            appState.selectFolder(folder)
        case nil:
            break
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
