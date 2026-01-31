import SwiftUI

/// Settings window view for managing accounts and preferences.
struct SettingsView: View {
    private enum SettingsTab: Hashable {
        case accounts
        case sync
        case mcp
        case about
    }

    @State private var selectedTab: SettingsTab = .accounts

    var body: some View {
        TabView(selection: $selectedTab) {
            AccountsSettingsView()
                .tabItem {
                    SwiftUI.Label("Accounts", systemImage: "person.crop.circle")
                }
                .tag(SettingsTab.accounts)

            SyncSettingsView()
                .tabItem {
                    SwiftUI.Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsTab.sync)

            MCPSettingsView()
                .tabItem {
                    SwiftUI.Label("MCP", systemImage: "server.rack")
                }
                .tag(SettingsTab.mcp)

            AboutSettingsView()
                .tabItem {
                    SwiftUI.Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 500, height: 350)
    }
}

// MARK: - Accounts Settings

struct AccountsSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("No accounts configured")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Gmail Accounts")
            }

            Section {
                Button("Add Account...") {
                    // TODO: Implement in Task 04
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sync Settings

struct SyncSettingsView: View {
    @AppStorage("syncInterval") private var syncInterval: Double = 300

    var body: some View {
        Form {
            Section {
                Picker("Sync Interval", selection: $syncInterval) {
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                    Text("30 minutes").tag(1800.0)
                    Text("Manual only").tag(0.0)
                }
            } header: {
                Text("Automatic Sync")
            }

            Section {
                Button("Sync Now") {
                    // TODO: Implement in Task 06
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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

                if appState.mcpServerRunning {
                    SwiftUI.Label("Server Running", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    SwiftUI.Label("Server Stopped", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("MCP Server")
            } footer: {
                Text("The MCP server allows AI assistants like Claude to read and manage your emails.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Cluademail")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(AppConfiguration.fullVersionString)")
                .foregroundStyle(.secondary)

            Text("A native macOS email client with MCP integration for AI assistants.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
