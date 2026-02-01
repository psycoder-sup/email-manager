import Foundation

// MARK: - KeychainServiceProtocol

/// Protocol for secure storage operations.
/// Enables testability and alternative implementations.
protocol KeychainServiceProtocol: Sendable {
    /// Saves a Codable item to secure storage.
    /// - Parameters:
    ///   - item: The item to save
    ///   - key: The key to store the item under
    func save<T: Codable>(_ item: T, forKey key: String) throws

    /// Retrieves a Codable item from secure storage.
    /// - Parameters:
    ///   - type: The type of item to retrieve
    ///   - key: The key the item is stored under
    /// - Returns: The retrieved item
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) throws -> T

    /// Deletes an item from secure storage.
    /// - Parameter key: The key of the item to delete
    func delete(forKey key: String) throws
}

// MARK: - AuthorizationResult

/// Result of extracting authorization code from OAuth callback.
/// Contains both the authorization code and the state parameter for CSRF protection.
struct AuthorizationResult: Sendable, Equatable {
    /// The authorization code to exchange for tokens
    let code: String

    /// The state parameter for CSRF verification
    let state: String
}

// MARK: - OAuthClientProtocol

/// Protocol for OAuth provider implementations.
/// Abstracts provider-specific details to enable multi-provider support.
protocol OAuthClientProtocol: Sendable {
    /// Builds the authorization URL with PKCE challenge.
    /// - Returns: The URL to open in the browser for user authorization, or nil if construction fails
    func buildAuthorizationURL() async -> URL?

    /// Extracts the authorization code and state from the callback URL.
    /// - Parameter callbackURL: The URL received from the OAuth callback
    /// - Returns: The authorization result containing code and state
    func extractAuthorizationCode(from callbackURL: URL) throws -> AuthorizationResult

    /// Exchanges an authorization code for tokens.
    /// - Parameter result: The authorization result from the callback
    /// - Returns: The OAuth tokens
    func exchangeCodeForTokens(_ result: AuthorizationResult) async throws -> OAuthTokens

    /// Refreshes an expired access token.
    /// - Parameter refreshToken: The refresh token
    /// - Returns: New OAuth tokens (with the original refresh token preserved)
    func refreshToken(_ refreshToken: String) async throws -> OAuthTokens

    /// Fetches the user's profile information.
    /// - Parameter accessToken: A valid access token
    /// - Returns: The user's profile
    func getUserProfile(accessToken: String) async throws -> GoogleUserProfile

    /// Revokes a token for clean sign-out.
    /// - Parameter token: The token to revoke (refresh token preferred)
    func revokeToken(_ token: String) async throws
}

// MARK: - TokenManagerProtocol

/// Protocol for token lifecycle management.
/// Handles storage, retrieval, and automatic refresh of OAuth tokens.
protocol TokenManagerProtocol: Sendable {
    /// Saves tokens for an account.
    /// - Parameters:
    ///   - tokens: The OAuth tokens to save
    ///   - accountEmail: The account email (used as key)
    func saveTokens(_ tokens: OAuthTokens, for accountEmail: String) async throws

    /// Retrieves tokens for an account.
    /// - Parameter accountEmail: The account email
    /// - Returns: The stored OAuth tokens
    func getTokens(for accountEmail: String) async throws -> OAuthTokens

    /// Deletes tokens for an account.
    /// - Parameter accountEmail: The account email
    func deleteTokens(for accountEmail: String) async throws

    /// Gets a valid access token, refreshing if necessary.
    /// - Parameter accountEmail: The account email
    /// - Returns: A valid access token
    func getValidAccessToken(for accountEmail: String) async throws -> String

    /// Checks if tokens exist for an account without throwing.
    /// - Parameter accountEmail: The account email
    /// - Returns: true if tokens exist, false otherwise
    func hasTokens(for accountEmail: String) async -> Bool
}
