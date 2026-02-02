import Foundation
@testable import Cluademail

/// Mock implementation of TokenManagerProtocol for testing.
final class MockTokenManager: TokenManagerProtocol, @unchecked Sendable {

    // MARK: - State

    /// In-memory token storage
    private var tokens: [String: OAuthTokens] = [:]

    /// Errors to throw for specific accounts
    private var errorsToThrow: [String: Error] = [:]

    /// Lock for thread-safe access.
    /// Retained for safety during concurrent async test operations.
    private let lock = NSLock()

    // MARK: - Call Tracking

    private(set) var saveTokensCallCount: Int = 0
    private(set) var getTokensCallCount: Int = 0
    private(set) var deleteTokensCallCount: Int = 0
    private(set) var getValidAccessTokenCallCount: Int = 0
    private(set) var hasTokensCallCount: Int = 0

    private(set) var lastSavedEmail: String?
    private(set) var lastSavedTokens: OAuthTokens?

    // MARK: - Configuration

    /// Set tokens for an account.
    func setTokens(_ tokens: OAuthTokens, for email: String) {
        lock.lock()
        defer { lock.unlock() }
        self.tokens[email] = tokens
    }

    /// Set an error to be thrown for an account.
    func setError(_ error: Error, for email: String) {
        lock.lock()
        defer { lock.unlock() }
        errorsToThrow[email] = error
    }

    /// Clear all state.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        tokens.removeAll()
        errorsToThrow.removeAll()
        saveTokensCallCount = 0
        getTokensCallCount = 0
        deleteTokensCallCount = 0
        getValidAccessTokenCallCount = 0
        hasTokensCallCount = 0
        lastSavedEmail = nil
        lastSavedTokens = nil
    }

    // MARK: - TokenManagerProtocol

    func saveTokens(_ tokens: OAuthTokens, for accountEmail: String) async throws {
        lock.lock()
        saveTokensCallCount += 1
        lastSavedEmail = accountEmail
        lastSavedTokens = tokens
        let error = errorsToThrow[accountEmail]
        lock.unlock()

        if let error = error {
            throw error
        }

        lock.lock()
        self.tokens[accountEmail] = tokens
        lock.unlock()
    }

    func getTokens(for accountEmail: String) async throws -> OAuthTokens {
        lock.lock()
        getTokensCallCount += 1
        let error = errorsToThrow[accountEmail]
        let storedTokens = tokens[accountEmail]
        lock.unlock()

        if let error = error {
            throw error
        }

        guard let storedTokens = storedTokens else {
            throw AuthError.tokenExpired
        }

        return storedTokens
    }

    func deleteTokens(for accountEmail: String) async throws {
        lock.lock()
        deleteTokensCallCount += 1
        let error = errorsToThrow[accountEmail]
        lock.unlock()

        if let error = error {
            throw error
        }

        lock.lock()
        tokens.removeValue(forKey: accountEmail)
        lock.unlock()
    }

    func getValidAccessToken(for accountEmail: String) async throws -> String {
        lock.lock()
        getValidAccessTokenCallCount += 1
        let error = errorsToThrow[accountEmail]
        let storedTokens = tokens[accountEmail]
        lock.unlock()

        if let error = error {
            throw error
        }

        guard let storedTokens = storedTokens else {
            throw AuthError.tokenExpired
        }

        return storedTokens.accessToken
    }

    func hasTokens(for accountEmail: String) async -> Bool {
        lock.lock()
        hasTokensCallCount += 1
        let exists = tokens[accountEmail] != nil
        lock.unlock()
        return exists
    }
}
