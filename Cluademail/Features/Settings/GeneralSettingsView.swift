import SwiftUI

/// Settings view displaying app version info and general information.
struct GeneralSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App Icon
            Image(systemName: "envelope.badge")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            // App Name
            Text("Cluademail")
                .font(.title)
                .fontWeight(.bold)

            // Version and Build
            VStack(spacing: 4) {
                Text("Version \(AppConfiguration.appVersion)")
                    .foregroundStyle(.secondary)

                Text("Build \(AppConfiguration.buildNumber)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Description
            Text("A native macOS email client with MCP integration for AI assistants.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            Spacer()

            // Copyright
            Text("© \(Calendar.current.component(.year, from: Date())) Cluademail. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
                .frame(height: 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 500, height: 400)
}
