import Foundation

/// Represents OAuth 2.0 tokens returned from Google's token endpoint.
/// Stored securely in the Keychain via TokenManager.
struct OAuthTokens: Codable, Sendable, Equatable {

    /// The access token used to authenticate API requests
    let accessToken: String

    /// The refresh token used to obtain new access tokens
    let refreshToken: String

    /// The date/time when the access token expires
    let expiresAt: Date

    /// Space-separated list of scopes granted
    let scope: String

    /// Whether the access token is expired or about to expire.
    /// Uses a 5-minute buffer to allow time for token refresh.
    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-300) // 5-minute buffer
    }

    /// Creates tokens from a token endpoint response.
    /// - Parameters:
    ///   - accessToken: The access token
    ///   - refreshToken: The refresh token
    ///   - expiresIn: Seconds until expiration (typically 3600)
    ///   - scope: Space-separated scopes
    init(
        accessToken: String,
        refreshToken: String,
        expiresIn: TimeInterval,
        scope: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = Date().addingTimeInterval(expiresIn)
        self.scope = scope
    }

    /// Creates tokens with an explicit expiration date.
    /// - Parameters:
    ///   - accessToken: The access token
    ///   - refreshToken: The refresh token
    ///   - expiresAt: The expiration date
    ///   - scope: Space-separated scopes
    init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        scope: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }
}
