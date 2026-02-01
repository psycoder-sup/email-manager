import XCTest
@testable import Cluademail

/// Tests for GoogleOAuthClient and AuthorizationResult.
/// Note: Tests that require OAuth credentials are skipped if credentials are not configured.
/// Tests focus on URL parsing, code extraction, and AuthorizationResult behavior.
final class GoogleOAuthClientTests: XCTestCase {

    private var sut: GoogleOAuthClient!

    override func setUp() {
        super.setUp()
        sut = GoogleOAuthClient.shared
        sut.reset()  // Clear state from previous tests
    }

    override func tearDown() {
        sut.reset()  // Clean up test state
        sut = nil
        super.tearDown()
    }

    // MARK: - Extract Authorization Code Tests (No Credentials Required)

    func testExtractAuthorizationCodeThrowsOnMissingState() async throws {
        // Given - callback URL without state parameter
        let callbackURL = URL(string: "cluademail://oauth/callback?code=test_code")!

        // When/Then
        do {
            _ = try sut.extractAuthorizationCode(from: callbackURL)
            XCTFail("Expected AuthenticationError.invalidCallbackURL")
        } catch let error as AuthenticationError {
            XCTAssertEqual(error.errorCode, "OAUTH_012")
        }
    }

    func testExtractAuthorizationCodeThrowsOnInvalidState() async throws {
        // Given - callback with state that doesn't match any pending flow
        let callbackURL = URL(string: "cluademail://oauth/callback?code=test_code&state=invalid_state")!

        // When/Then
        do {
            _ = try sut.extractAuthorizationCode(from: callbackURL)
            XCTFail("Expected AuthenticationError.invalidCallbackURL")
        } catch let error as AuthenticationError {
            XCTAssertEqual(error.errorCode, "OAUTH_012")
        }
    }

    func testExtractAuthorizationCodeThrowsOnInvalidURL() async throws {
        // Given - malformed callback URL
        let callbackURL = URL(string: "cluademail://oauth/callback")!

        // When/Then
        do {
            _ = try sut.extractAuthorizationCode(from: callbackURL)
            XCTFail("Expected AuthenticationError.invalidCallbackURL")
        } catch let error as AuthenticationError {
            XCTAssertEqual(error.errorCode, "OAUTH_012")
        }
    }

    func testExtractAuthorizationCodeThrowsOnOAuthErrorInCallback() async throws {
        // Given - callback URL with OAuth error (doesn't require pending flow)
        let callbackURL = URL(string: "cluademail://oauth/callback?error=access_denied&error_description=User%20denied%20access")!

        // When/Then
        do {
            _ = try sut.extractAuthorizationCode(from: callbackURL)
            XCTFail("Expected AuthenticationError.tokenExchangeFailed")
        } catch let error as AuthenticationError {
            XCTAssertEqual(error.errorCode, "OAUTH_003")
        }
    }

    // MARK: - AuthorizationResult Tests

    func testAuthorizationResultEquality() {
        // Given
        let result1 = AuthorizationResult(code: "code1", state: "state1")
        let result2 = AuthorizationResult(code: "code1", state: "state1")
        let result3 = AuthorizationResult(code: "code2", state: "state1")

        // Then
        XCTAssertEqual(result1, result2)
        XCTAssertNotEqual(result1, result3)
    }

    func testAuthorizationResultProperties() {
        // Given
        let result = AuthorizationResult(code: "my_auth_code", state: "my_state_param")

        // Then
        XCTAssertEqual(result.code, "my_auth_code")
        XCTAssertEqual(result.state, "my_state_param")
    }

    func testAuthorizationResultSendable() {
        // This test verifies AuthorizationResult conforms to Sendable
        // by using it across an async boundary
        let result = AuthorizationResult(code: "code", state: "state")

        Task {
            // If AuthorizationResult weren't Sendable, this would cause a compiler error
            let _ = result.code
        }
    }
}
