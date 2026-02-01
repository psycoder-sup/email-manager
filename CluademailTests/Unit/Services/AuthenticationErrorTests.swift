import XCTest
@testable import Cluademail

/// Tests for AuthenticationError.
final class AuthenticationErrorTests: XCTestCase {

    // MARK: - Error Code Tests

    func testAuthenticationErrorCodes() {
        XCTAssertEqual(AuthenticationError.userCancelled.errorCode, "OAUTH_001")
        XCTAssertEqual(AuthenticationError.invalidResponse.errorCode, "OAUTH_002")
        XCTAssertEqual(AuthenticationError.tokenExchangeFailed("test").errorCode, "OAUTH_003")
        XCTAssertEqual(AuthenticationError.tokenExpired.errorCode, "OAUTH_004")
        XCTAssertEqual(AuthenticationError.refreshFailed(nil).errorCode, "OAUTH_005")
        XCTAssertEqual(AuthenticationError.tokenRevoked.errorCode, "OAUTH_006")
        XCTAssertEqual(AuthenticationError.rateLimited(retryAfter: 30).errorCode, "OAUTH_007")
        XCTAssertEqual(AuthenticationError.networkError(NSError(domain: "", code: 0)).errorCode, "OAUTH_008")
        XCTAssertEqual(AuthenticationError.accountAlreadyExists("test@gmail.com").errorCode, "OAUTH_009")
        XCTAssertEqual(AuthenticationError.invalidGrant.errorCode, "OAUTH_010")
        XCTAssertEqual(AuthenticationError.missingConfiguration("test").errorCode, "OAUTH_011")
        XCTAssertEqual(AuthenticationError.invalidCallbackURL.errorCode, "OAUTH_012")
    }

    // MARK: - Recoverability Tests

    func testRecoverableErrors() {
        XCTAssertTrue(AuthenticationError.userCancelled.isRecoverable)
        XCTAssertTrue(AuthenticationError.networkError(NSError(domain: "", code: 0)).isRecoverable)
        XCTAssertTrue(AuthenticationError.rateLimited(retryAfter: 30).isRecoverable)
        XCTAssertTrue(AuthenticationError.tokenExpired.isRecoverable)
        XCTAssertTrue(AuthenticationError.invalidGrant.isRecoverable)
    }

    func testNonRecoverableErrors() {
        XCTAssertFalse(AuthenticationError.invalidResponse.isRecoverable)
        XCTAssertFalse(AuthenticationError.tokenExchangeFailed("test").isRecoverable)
        XCTAssertFalse(AuthenticationError.refreshFailed(nil).isRecoverable)
        XCTAssertFalse(AuthenticationError.tokenRevoked.isRecoverable)
        XCTAssertFalse(AuthenticationError.accountAlreadyExists("test@gmail.com").isRecoverable)
        XCTAssertFalse(AuthenticationError.missingConfiguration("test").isRecoverable)
        XCTAssertFalse(AuthenticationError.invalidCallbackURL.isRecoverable)
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        XCTAssertNotNil(AuthenticationError.userCancelled.errorDescription)
        XCTAssertNotNil(AuthenticationError.invalidResponse.errorDescription)
        XCTAssertNotNil(AuthenticationError.tokenExchangeFailed("test").errorDescription)
        XCTAssertNotNil(AuthenticationError.tokenExpired.errorDescription)
        XCTAssertNotNil(AuthenticationError.refreshFailed(nil).errorDescription)
        XCTAssertNotNil(AuthenticationError.tokenRevoked.errorDescription)
        XCTAssertNotNil(AuthenticationError.rateLimited(retryAfter: 30).errorDescription)
        XCTAssertNotNil(AuthenticationError.networkError(NSError(domain: "", code: 0)).errorDescription)
        XCTAssertNotNil(AuthenticationError.accountAlreadyExists("test@gmail.com").errorDescription)
        XCTAssertNotNil(AuthenticationError.invalidGrant.errorDescription)
        XCTAssertNotNil(AuthenticationError.missingConfiguration("test").errorDescription)
        XCTAssertNotNil(AuthenticationError.invalidCallbackURL.errorDescription)
    }

    func testRateLimitedErrorDescriptionIncludesRetryTime() {
        let error = AuthenticationError.rateLimited(retryAfter: 30)
        XCTAssertTrue(error.errorDescription?.contains("30") ?? false)
    }

    func testAccountAlreadyExistsErrorDescriptionIncludesEmail() {
        let error = AuthenticationError.accountAlreadyExists("user@gmail.com")
        XCTAssertTrue(error.errorDescription?.contains("user@gmail.com") ?? false)
    }

    func testTokenExchangeFailedWithMessage() {
        let error = AuthenticationError.tokenExchangeFailed("Invalid client")
        XCTAssertTrue(error.errorDescription?.contains("Invalid client") ?? false)
    }

    func testTokenExchangeFailedWithoutMessage() {
        let error = AuthenticationError.tokenExchangeFailed(nil)
        XCTAssertNotNil(error.errorDescription)
    }

    // MARK: - Recovery Suggestion Tests

    func testRecoverySuggestions() {
        XCTAssertNotNil(AuthenticationError.userCancelled.recoverySuggestion)
        XCTAssertNotNil(AuthenticationError.invalidResponse.recoverySuggestion)
        XCTAssertNotNil(AuthenticationError.tokenExpired.recoverySuggestion)
        XCTAssertNotNil(AuthenticationError.networkError(NSError(domain: "", code: 0)).recoverySuggestion)
    }

    // MARK: - Underlying Error Tests

    func testUnderlyingErrorForNetworkError() {
        let underlying = NSError(domain: "TestDomain", code: 42)
        let error = AuthenticationError.networkError(underlying)
        XCTAssertNotNil(error.underlyingError)
        XCTAssertEqual((error.underlyingError as? NSError)?.code, 42)
    }

    func testUnderlyingErrorForRefreshFailed() {
        let underlying = NSError(domain: "TestDomain", code: 99)
        let error = AuthenticationError.refreshFailed(underlying)
        XCTAssertNotNil(error.underlyingError)
        XCTAssertEqual((error.underlyingError as? NSError)?.code, 99)
    }

    func testNoUnderlyingErrorForSimpleErrors() {
        XCTAssertNil(AuthenticationError.userCancelled.underlyingError)
        XCTAssertNil(AuthenticationError.invalidResponse.underlyingError)
        XCTAssertNil(AuthenticationError.invalidGrant.underlyingError)
    }
}
