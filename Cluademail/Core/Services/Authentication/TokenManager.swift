import Foundation
import os.log

/// Manages OAuth tokens for accounts.
/// Handles token storage, retrieval, and automatic refresh when expired.
actor TokenManager: TokenManagerProtocol {

    /// Shared singleton instance
    static let shared = TokenManager()

    /// File-based storage for tokens
    private let fileStorage: FileTokenStorage

    /// OAuth client for token refresh
    private let oauthClient: any OAuthClientProtocol

    /// Creates a TokenManager with default dependencies.
    private init() {
        self.fileStorage = FileTokenStorage.shared
        self.oauthClient = GoogleOAuthClient.shared
    }

    /// Creates a TokenManager with custom dependencies (for testing).
    init(fileStorage: FileTokenStorage, oauthClient: any OAuthClientProtocol) {
        self.fileStorage = fileStorage
        self.oauthClient = oauthClient
    }

    // MARK: - TokenManagerProtocol Implementation

    /// Saves tokens for an account.
    func saveTokens(_ tokens: OAuthTokens, for accountEmail: String) async throws {
        try fileStorage.saveTokens(tokens, for: accountEmail)
        Logger.auth.info("Saved tokens for account: \(accountEmail, privacy: .private(mask: .hash))")
    }

    /// Retrieves tokens for an account.
    func getTokens(for accountEmail: String) async throws -> OAuthTokens {
        let tokens = try fileStorage.getTokens(for: accountEmail)
        Logger.auth.debug("Retrieved tokens for account: \(accountEmail, privacy: .private(mask: .hash))")
        return tokens
    }

    /// Deletes tokens for an account.
    /// Does not throw if tokens don't exist.
    func deleteTokens(for accountEmail: String) async throws {
        try fileStorage.deleteTokens(for: accountEmail)
        Logger.auth.info("Deleted tokens for account: \(accountEmail, privacy: .private(mask: .hash))")
    }

    /// Checks if tokens exist for an account without throwing.
    func hasTokens(for accountEmail: String) async -> Bool {
        return fileStorage.hasTokens(for: accountEmail)
    }

    /// Gets a valid access token, refreshing if necessary.
    func getValidAccessToken(for accountEmail: String) async throws -> String {
        // Get stored tokens
        let tokens = try await getTokens(for: accountEmail)

        // Check if expired
        if !tokens.isExpired {
            Logger.auth.debug("Using existing access token for: \(accountEmail, privacy: .private(mask: .hash))")
            return tokens.accessToken
        }

        Logger.auth.info("Access token expired, refreshing for: \(accountEmail, privacy: .private(mask: .hash))")

        // Refresh the token
        do {
            let newTokens = try await oauthClient.refreshToken(tokens.refreshToken)

            // Save refreshed tokens
            try await saveTokens(newTokens, for: accountEmail)

            Logger.auth.info("Successfully refreshed access token for: \(accountEmail, privacy: .private(mask: .hash))")
            return newTokens.accessToken
        } catch let error as AuthenticationError {
            // Handle invalid_grant (expired refresh token)
            if case .invalidGrant = error {
                Logger.auth.warning("Refresh token expired for: \(accountEmail, privacy: .private(mask: .hash))")
                // Delete stale tokens - log but don't propagate cleanup errors
                do {
                    try await deleteTokens(for: accountEmail)
                } catch {
                    Logger.auth.error("Failed to delete stale tokens during cleanup: \(error.localizedDescription)")
                }
            }
            throw error
        }
    }
}
