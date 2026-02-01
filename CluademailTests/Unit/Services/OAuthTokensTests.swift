import XCTest
@testable import Cluademail

/// Tests for OAuthTokens model.
final class OAuthTokensTests: XCTestCase {

    // MARK: - Expiration Tests

    func testIsExpiredReturnsFalseForFutureExpiration() {
        // Given
        let tokens = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600), // 1 hour from now
            scope: "email"
        )

        // Then
        XCTAssertFalse(tokens.isExpired)
    }

    func testIsExpiredReturnsTrueForPastExpiration() {
        // Given
        let tokens = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(-3600), // 1 hour ago
            scope: "email"
        )

        // Then
        XCTAssertTrue(tokens.isExpired)
    }

    func testIsExpiredReturnsTrueWithin5MinuteBuffer() {
        // Given - expires in 4 minutes (within 5-minute buffer)
        let tokens = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(240), // 4 minutes from now
            scope: "email"
        )

        // Then - should be considered expired due to buffer
        XCTAssertTrue(tokens.isExpired)
    }

    func testIsExpiredReturnsFalseJustOutsideBuffer() {
        // Given - expires in 6 minutes (outside 5-minute buffer)
        let tokens = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(360), // 6 minutes from now
            scope: "email"
        )

        // Then - should not be considered expired
        XCTAssertFalse(tokens.isExpired)
    }

    // MARK: - Initialization Tests

    func testInitWithExpiresIn() {
        // Given
        let expiresIn: TimeInterval = 3600

        // When
        let tokens = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: expiresIn,
            scope: "email"
        )

        // Then - expiresAt should be approximately 1 hour from now
        let expectedDate = Date().addingTimeInterval(expiresIn)
        XCTAssertEqual(tokens.expiresAt.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testInitWithExpiresAt() {
        // Given
        let expiresAt = Date().addingTimeInterval(7200)

        // When
        let tokens = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: expiresAt,
            scope: "email"
        )

        // Then
        XCTAssertEqual(tokens.expiresAt, expiresAt)
    }

    // MARK: - Codable Tests

    func testEncodingAndDecoding() throws {
        // Given
        let original = OAuthTokens(
            accessToken: "test_access",
            refreshToken: "test_refresh",
            expiresAt: Date(),
            scope: "email profile"
        )

        // When
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: data)

        // Then
        XCTAssertEqual(decoded.accessToken, original.accessToken)
        XCTAssertEqual(decoded.refreshToken, original.refreshToken)
        XCTAssertEqual(decoded.scope, original.scope)
        XCTAssertEqual(decoded.expiresAt.timeIntervalSince1970, original.expiresAt.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Equatable Tests

    func testEquatableWithSameValues() {
        // Given
        let expiresAt = Date()
        let tokens1 = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: expiresAt,
            scope: "email"
        )
        let tokens2 = OAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: expiresAt,
            scope: "email"
        )

        // Then
        XCTAssertEqual(tokens1, tokens2)
    }

    func testEquatableWithDifferentValues() {
        // Given
        let tokens1 = OAuthTokens(
            accessToken: "access1",
            refreshToken: "refresh",
            expiresAt: Date(),
            scope: "email"
        )
        let tokens2 = OAuthTokens(
            accessToken: "access2",
            refreshToken: "refresh",
            expiresAt: Date(),
            scope: "email"
        )

        // Then
        XCTAssertNotEqual(tokens1, tokens2)
    }
}
