import Foundation
@testable import Cluademail

/// Mock implementation of OAuthClientProtocol for testing.
final class MockOAuthClient: OAuthClientProtocol, @unchecked Sendable {

    // MARK: - Configurable Responses

    var authorizationURL: URL = URL(string: "https://example.com/auth")!
    var authResultToReturn: AuthorizationResult = AuthorizationResult(code: "test_auth_code", state: "test_state")
    var tokensToReturn: OAuthTokens = TestFixtures.makeOAuthTokens()
    var profileToReturn: GoogleUserProfile = TestFixtures.makeGoogleUserProfile()

    // MARK: - Error Configuration

    var extractCodeError: AuthenticationError?
    var exchangeTokensError: AuthenticationError?
    var refreshTokenError: AuthenticationError?
    var getUserProfileError: AuthenticationError?
    var revokeTokenError: AuthenticationError?

    // MARK: - Call Tracking

    /// Lock for thread-safe access.
    /// Retained even though tests typically run sequentially, as the TokenManager
    /// actor may access this mock from different isolation contexts during async tests.
    private let lock = NSLock()
    private(set) var buildAuthorizationURLCallCount: Int = 0
    private(set) var extractAuthorizationCodeCallCount: Int = 0
    private(set) var exchangeCodeForTokensCallCount: Int = 0
    private(set) var refreshTokenCallCount: Int = 0
    private(set) var getUserProfileCallCount: Int = 0
    private(set) var revokeTokenCallCount: Int = 0

    private(set) var lastExchangedCode: String?
    private(set) var lastRefreshedToken: String?
    private(set) var lastRevokedToken: String?

    // MARK: - Configuration

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        authorizationURL = URL(string: "https://example.com/auth")!
        authResultToReturn = AuthorizationResult(code: "test_auth_code", state: "test_state")
        tokensToReturn = TestFixtures.makeOAuthTokens()
        profileToReturn = TestFixtures.makeGoogleUserProfile()

        extractCodeError = nil
        exchangeTokensError = nil
        refreshTokenError = nil
        getUserProfileError = nil
        revokeTokenError = nil

        buildAuthorizationURLCallCount = 0
        extractAuthorizationCodeCallCount = 0
        exchangeCodeForTokensCallCount = 0
        refreshTokenCallCount = 0
        getUserProfileCallCount = 0
        revokeTokenCallCount = 0

        lastExchangedCode = nil
        lastRefreshedToken = nil
        lastRevokedToken = nil
    }

    // MARK: - OAuthClientProtocol

    func buildAuthorizationURL() async -> URL? {
        lock.lock()
        buildAuthorizationURLCallCount += 1
        let url = authorizationURL
        lock.unlock()
        return url
    }

    func extractAuthorizationCode(from callbackURL: URL) throws -> AuthorizationResult {
        lock.lock()
        extractAuthorizationCodeCallCount += 1
        let error = extractCodeError
        let result = authResultToReturn
        lock.unlock()

        if let error = error {
            throw error
        }

        return result
    }

    func exchangeCodeForTokens(_ result: AuthorizationResult) async throws -> OAuthTokens {
        lock.lock()
        exchangeCodeForTokensCallCount += 1
        lastExchangedCode = result.code
        let error = exchangeTokensError
        let tokens = tokensToReturn
        lock.unlock()

        if let error = error {
            throw error
        }

        return tokens
    }

    func refreshToken(_ refreshToken: String) async throws -> OAuthTokens {
        lock.lock()
        refreshTokenCallCount += 1
        lastRefreshedToken = refreshToken
        let error = refreshTokenError
        let tokens = tokensToReturn
        lock.unlock()

        if let error = error {
            throw error
        }

        return tokens
    }

    func getUserProfile(accessToken: String) async throws -> GoogleUserProfile {
        lock.lock()
        getUserProfileCallCount += 1
        let error = getUserProfileError
        let profile = profileToReturn
        lock.unlock()

        if let error = error {
            throw error
        }

        return profile
    }

    func revokeToken(_ token: String) async throws {
        lock.lock()
        revokeTokenCallCount += 1
        lastRevokedToken = token
        let error = revokeTokenError
        lock.unlock()

        if let error = error {
            throw error
        }
    }
}
