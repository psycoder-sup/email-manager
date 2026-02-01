import XCTest
@testable import Cluademail

/// Tests for TokenManager.
@MainActor
final class TokenManagerTests: XCTestCase {

    private var sut: TokenManager!
    private var mockKeychainService: MockKeychainService!
    private var mockOAuthClient: MockOAuthClient!

    override func setUp() async throws {
        try await super.setUp()
        mockKeychainService = MockKeychainService()
        mockOAuthClient = MockOAuthClient()
        sut = TokenManager(keychainService: mockKeychainService, oauthClient: mockOAuthClient)
    }

    override func tearDown() async throws {
        sut = nil
        mockKeychainService = nil
        mockOAuthClient = nil
        try await super.tearDown()
    }

    // MARK: - Save Tokens Tests

    func testSaveTokensStoresInKeychain() async throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens()
        let email = "test@gmail.com"

        // When
        try await sut.saveTokens(tokens, for: email)

        // Then
        XCTAssertEqual(mockKeychainService.saveCallCount, 1)
    }

    func testSaveTokensUsesCorrectKeyFormat() async throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens()
        let email = "test@gmail.com"

        // When
        try await sut.saveTokens(tokens, for: email)

        // Then - should be able to retrieve with correct key
        let retrieved = try await sut.getTokens(for: email)
        XCTAssertEqual(retrieved.accessToken, tokens.accessToken)
    }

    // MARK: - Get Tokens Tests

    func testGetTokensRetrievesFromKeychain() async throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens()
        let email = "test@gmail.com"
        try await sut.saveTokens(tokens, for: email)

        // When
        let retrieved = try await sut.getTokens(for: email)

        // Then
        XCTAssertEqual(retrieved.accessToken, tokens.accessToken)
        XCTAssertEqual(retrieved.refreshToken, tokens.refreshToken)
    }

    func testGetTokensThrowsWhenNotFound() async throws {
        // Given
        let email = "nonexistent@gmail.com"

        // When/Then
        do {
            _ = try await sut.getTokens(for: email)
            XCTFail("Expected KeychainError.itemNotFound")
        } catch is KeychainError {
            // Expected
        }
    }

    // MARK: - Delete Tokens Tests

    func testDeleteTokensRemovesFromKeychain() async throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens()
        let email = "test@gmail.com"
        try await sut.saveTokens(tokens, for: email)

        // When
        try await sut.deleteTokens(for: email)

        // Then
        do {
            _ = try await sut.getTokens(for: email)
            XCTFail("Expected KeychainError.itemNotFound after deletion")
        } catch is KeychainError {
            // Expected
        }
    }

    func testDeleteTokensDoesNotThrowWhenNotFound() async throws {
        // Given
        let email = "nonexistent@gmail.com"

        // When/Then - should not throw
        try await sut.deleteTokens(for: email)
    }

    // MARK: - Get Valid Access Token Tests

    func testGetValidAccessTokenReturnsTokenWhenNotExpired() async throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens() // Not expired
        let email = "test@gmail.com"
        try await sut.saveTokens(tokens, for: email)

        // When
        let accessToken = try await sut.getValidAccessToken(for: email)

        // Then
        XCTAssertEqual(accessToken, tokens.accessToken)
        XCTAssertEqual(mockOAuthClient.refreshTokenCallCount, 0, "Should not refresh non-expired token")
    }

    func testGetValidAccessTokenRefreshesExpiredToken() async throws {
        // Given
        let expiredTokens = TestFixtures.makeExpiredOAuthTokens()
        let newTokens = TestFixtures.makeOAuthTokens(accessToken: "new_access_token")
        let email = "test@gmail.com"

        try await sut.saveTokens(expiredTokens, for: email)
        mockOAuthClient.tokensToReturn = newTokens

        // When
        let accessToken = try await sut.getValidAccessToken(for: email)

        // Then
        XCTAssertEqual(accessToken, "new_access_token")
        XCTAssertEqual(mockOAuthClient.refreshTokenCallCount, 1)
    }

    func testGetValidAccessTokenSavesRefreshedTokens() async throws {
        // Given
        let expiredTokens = TestFixtures.makeExpiredOAuthTokens()
        let newTokens = TestFixtures.makeOAuthTokens(accessToken: "refreshed_token")
        let email = "test@gmail.com"

        try await sut.saveTokens(expiredTokens, for: email)
        mockOAuthClient.tokensToReturn = newTokens

        // When
        _ = try await sut.getValidAccessToken(for: email)

        // Then - saved tokens should be the refreshed ones
        let savedTokens = try await sut.getTokens(for: email)
        XCTAssertEqual(savedTokens.accessToken, "refreshed_token")
    }

    func testGetValidAccessTokenDeletesTokensOnInvalidGrant() async throws {
        // Given
        let expiredTokens = TestFixtures.makeExpiredOAuthTokens()
        let email = "test@gmail.com"

        try await sut.saveTokens(expiredTokens, for: email)
        mockOAuthClient.refreshTokenError = .invalidGrant

        // When
        do {
            _ = try await sut.getValidAccessToken(for: email)
            XCTFail("Expected AuthenticationError.invalidGrant")
        } catch let error as AuthenticationError {
            // Then
            XCTAssertEqual(error.errorCode, "OAUTH_010")

            // Tokens should be deleted
            do {
                _ = try await sut.getTokens(for: email)
                XCTFail("Expected tokens to be deleted")
            } catch is KeychainError {
                // Expected
            }
        }
    }

    // MARK: - Has Tokens Tests

    func testHasTokensReturnsTrueWhenTokensExist() async throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens()
        let email = "test@gmail.com"
        try await sut.saveTokens(tokens, for: email)

        // When
        let hasTokens = await sut.hasTokens(for: email)

        // Then
        XCTAssertTrue(hasTokens)
    }

    func testHasTokensReturnsFalseWhenNoTokens() async throws {
        // Given
        let email = "nonexistent@gmail.com"

        // When
        let hasTokens = await sut.hasTokens(for: email)

        // Then
        XCTAssertFalse(hasTokens)
    }

    func testHasTokensReturnsFalseAfterDeletion() async throws {
        // Given
        let tokens = TestFixtures.makeOAuthTokens()
        let email = "test@gmail.com"
        try await sut.saveTokens(tokens, for: email)
        try await sut.deleteTokens(for: email)

        // When
        let hasTokens = await sut.hasTokens(for: email)

        // Then
        XCTAssertFalse(hasTokens)
    }
}
