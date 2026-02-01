import SwiftUI
import UserNotifications

/// Settings view for configuring notification preferences.
struct NotificationSettingsView: View {
    @Environment(NotificationService.self) private var notificationService

    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notificationSound") private var notificationSound = true
    @AppStorage("notificationBadge") private var notificationBadge = true

    var body: some View {
        Form {
            // Permission Warning (if denied)
            if notificationService.authorizationStatus == .denied {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications Disabled")
                                .fontWeight(.semibold)
                            Text("Enable notifications in System Settings to receive email alerts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Open Settings") {
                            notificationService.openSystemSettings()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Main Toggle
            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            Task {
                                await requestPermissionIfNeeded()
                            }
                        }
                    }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Notifications will appear for new emails when Cluademail is running.")
            }

            // Options (shown when enabled)
            if notificationsEnabled && notificationService.authorizationStatus != .denied {
                Section {
                    Toggle("Play Sound", isOn: $notificationSound)
                    Toggle("Show Badge on Dock", isOn: $notificationBadge)
                } header: {
                    Text("Options")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await notificationService.checkAuthorizationStatus()
        }
    }

    private func requestPermissionIfNeeded() async {
        if notificationService.authorizationStatus == .notDetermined {
            let granted = await notificationService.requestAuthorization()
            if !granted {
                notificationsEnabled = false
            }
        }
    }
}

#Preview {
    NotificationSettingsView()
        .environment(NotificationService.shared)
        .frame(width: 500, height: 400)
}
