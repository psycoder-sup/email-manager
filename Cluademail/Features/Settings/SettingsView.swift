import SwiftUI
import SwiftData
import os.log

/// Settings window view for managing accounts and preferences.
struct SettingsView: View {
    private enum SettingsTab: Hashable {
        case general
        case accounts
        case sync
        case notifications
        case mcp
    }

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    SwiftUI.Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            AccountsSettingsView()
                .tabItem {
                    SwiftUI.Label("Accounts", systemImage: "person.2")
                }
                .tag(SettingsTab.accounts)

            SyncSettingsView()
                .tabItem {
                    SwiftUI.Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsTab.sync)

            NotificationSettingsView()
                .tabItem {
                    SwiftUI.Label("Notifications", systemImage: "bell")
                }
                .tag(SettingsTab.notifications)

            MCPSettingsView()
                .tabItem {
                    SwiftUI.Label("MCP", systemImage: "network")
                }
                .tag(SettingsTab.mcp)
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Accounts Settings

struct AccountsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(DatabaseService.self) private var databaseService
    @Environment(ErrorHandler.self) private var errorHandler
    @Environment(SyncScheduler.self) private var syncScheduler

    @State private var authService = AuthenticationService()
    @State private var isAddingAccount = false
    @State private var showingRemoveConfirmation = false
    @State private var accountToRemove: Account?

    var body: some View {
        Form {
            Section {
                if appState.accounts.isEmpty {
                    Text("No accounts configured")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(appState.accounts) { account in
                            AccountSettingsRow(
                                account: account,
                                isSyncing: appState.isSyncing,
                                onRemove: {
                                    accountToRemove = account
                                    showingRemoveConfirmation = true
                                }
                            )
                        }
                    }
                    .frame(height: 150)
                }
            } header: {
                Text("Gmail Accounts")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Add Account...") {
                        Task {
                            await addAccount()
                        }
                    }
                    .disabled(isAddingAccount)
                }
            } footer: {
                Text("Accounts are authenticated via Google OAuth. Credentials are stored securely in the Keychain.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "Remove Account",
            isPresented: $showingRemoveConfirmation,
            presenting: accountToRemove
        ) { account in
            Button("Remove", role: .destructive) {
                Task {
                    await removeAccount(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text("Are you sure you want to remove \"\(account.displayName)\"? This will delete all local data for this account.")
        }
        .task {
            await loadAccounts()
        }
    }

    @MainActor
    private func loadAccounts() async {
        let repository = AccountRepository()
        do {
            appState.accounts = try await repository.fetchAll(context: databaseService.mainContext)
        } catch {
            Logger.ui.error("Failed to load accounts in settings: \(error.localizedDescription)")
        }
    }

    private func addAccount() async {
        isAddingAccount = true
        defer { isAddingAccount = false }

        do {
            let account = try await authService.signIn(
                presentingFrom: NSApp.keyWindow,
                context: databaseService.mainContext
            )
            appState.accounts.append(account)
            Logger.ui.info("Account added successfully")

            // Trigger immediate sync to fetch emails for the new account
            await syncScheduler.triggerImmediateSync()
        } catch let error as AuthenticationError {
            if case .userCancelled = error {
                // User cancelled, no error needed
                return
            }
            errorHandler.handle(error, context: "Add Account", showAlert: true)
        } catch {
            errorHandler.handle(error, context: "Add Account", showAlert: true)
        }
    }

    private func removeAccount(_ account: Account) async {
        do {
            try await authService.signOut(account, context: databaseService.mainContext)
            appState.accounts.removeAll { $0.id == account.id }

            // Clear notifications for this account
            await NotificationService.shared.clearNotifications(for: account.id)

            Logger.ui.info("Account removed successfully")
        } catch {
            errorHandler.handle(error, context: "Remove Account", showAlert: true)
        }
    }
}

/// Row displaying a single account in settings.
private struct AccountSettingsRow: View {
    let account: Account
    let isSyncing: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(.blue.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(account.displayName.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

            // Name and email
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .fontWeight(.medium)
                Text(account.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            statusIndicator

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove account")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isSyncing {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: account.isEnabled ? "checkmark.circle.fill" : "circle.fill")
                .foregroundStyle(account.isEnabled ? .green : .gray)
        }
    }
}

// MARK: - Sync Settings

struct SyncSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncScheduler.self) private var syncScheduler

    @AppStorage("syncInterval") private var syncInterval: Double = 300

    var body: some View {
        Form {
            Section {
                Picker("Sync Interval", selection: $syncInterval) {
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                    Text("30 minutes").tag(1800.0)
                    Text("1 hour").tag(3600.0)
                }
                .onChange(of: syncInterval) { _, newValue in
                    syncScheduler.updateInterval(newValue)
                }
            } header: {
                Text("Automatic Sync")
            }

            Section {
                HStack {
                    syncStatusView
                    Spacer()
                    Button("Sync Now") {
                        Task {
                            await syncScheduler.triggerImmediateSync()
                        }
                    }
                    .disabled(appState.isSyncing)
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var syncStatusView: some View {
        if appState.isSyncing {
            ProgressView()
                .controlSize(.small)
            Text("Syncing...")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(lastSyncText)
                .foregroundStyle(.secondary)
        }
    }

    private var lastSyncText: String {
        guard let lastSync = appState.lastSyncDate else {
            return "Not synced"
        }
        return "Synced \(lastSync.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - MCP Settings

struct MCPSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("mcpEnabled") private var mcpEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable MCP Server", isOn: $mcpEnabled)

                HStack {
                    Image(systemName: appState.mcpServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.mcpServerRunning ? .green : .secondary)
                    Text(appState.mcpServerRunning ? "Server Running" : "Server Stopped")
                    Spacer()
                    Text("Transport: stdio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            } header: {
                Text("MCP Server")
            } footer: {
                Text("The MCP server allows AI assistants like Claude to read and manage your emails.")
            }

            Section {
                MCPToolRow(name: "list_emails", description: "List emails with filters")
                MCPToolRow(name: "read_email", description: "Read full email content")
                MCPToolRow(name: "search_emails", description: "Search emails by query")
                MCPToolRow(name: "create_draft", description: "Create email draft")
                MCPToolRow(name: "get_attachment", description: "Download attachment")
            } header: {
                Text("Available Tools")
            } footer: {
                Text("AI assistants can only create drafts, not send emails directly. You maintain full control over what gets sent.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Row displaying an MCP tool.
private struct MCPToolRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack {
            Text(name)
                .fontWeight(.medium)
                .monospaced()
            Spacer()
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .environment(DatabaseService(isStoredInMemoryOnly: true))
        .environment(ErrorHandler())
        .environment(NotificationService.shared)
}
