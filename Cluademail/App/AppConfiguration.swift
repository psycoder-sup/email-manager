import Foundation
import os.log

/// Centralized configuration management for the application.
/// Loads environment-specific settings from Info.plist and xcconfig files.
enum AppConfiguration {

    // MARK: - Environment

    /// Application environment (development or production)
    enum Environment: String {
        case development
        case production

        var isDebug: Bool {
            self == .development
        }
    }

    /// Current application environment
    static let environment: Environment = {
        guard let envString = Bundle.main.infoDictionary?["APP_ENVIRONMENT"] as? String,
              let env = Environment(rawValue: envString) else {
            #if DEBUG
            return .development
            #else
            return .production
            #endif
        }
        return env
    }()

    // MARK: - OAuth Configuration

    /// Google OAuth Client ID loaded from Info.plist
    static let googleClientId: String = {
        guard let clientId = Bundle.main.infoDictionary?["GOOGLE_CLIENT_ID"] as? String,
              !clientId.isEmpty,
              !clientId.hasPrefix("YOUR_") else {
            Logger.auth.fault("GOOGLE_CLIENT_ID not configured in Info.plist")
            fatalError("GOOGLE_CLIENT_ID must be configured. See README for setup instructions.")
        }
        return clientId
    }()

    /// OAuth redirect URI for handling callbacks
    static let oauthRedirectURI = "cluademail://oauth/callback"

    /// OAuth callback scheme (without ://)
    static let oauthCallbackScheme = "cluademail"

    /// OAuth scopes required for Gmail access and user profile
    static let oauthScopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.compose",
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.labels",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ]

    // MARK: - Logging

    /// Logging subsystem identifier
    static let loggingSubsystem = "com.cluademail.app"

    /// Enable verbose logging in non-production environments
    static var verboseLoggingEnabled: Bool {
        environment.isDebug
    }

    // MARK: - Sync Configuration

    /// Default sync interval in seconds (5 minutes)
    static let defaultSyncInterval: TimeInterval = 300

    /// Maximum emails to sync per account
    static let maxEmailsPerAccount = 1000

    // MARK: - App Info

    /// Application version string
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// Application build number
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    /// Full version string (e.g., "1.0.0 (1)")
    static var fullVersionString: String {
        "\(appVersion) (\(buildNumber))"
    }
}
