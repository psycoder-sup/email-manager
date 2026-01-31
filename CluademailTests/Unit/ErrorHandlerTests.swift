import XCTest
@testable import Cluademail

@MainActor
final class ErrorHandlerTests: XCTestCase {

    var sut: ErrorHandler!

    override func setUp() async throws {
        sut = ErrorHandler()
    }

    override func tearDown() async throws {
        sut = nil
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertNil(sut.currentError)
        XCTAssertFalse(sut.showingError)
        XCTAssertNil(sut.retryAction)
    }

    // MARK: - Error Handling Tests

    func testHandleAppErrorShowsAlert() {
        let error = AuthError.tokenExpired

        sut.handle(error)

        XCTAssertNotNil(sut.currentError)
        XCTAssertTrue(sut.showingError)
        XCTAssertEqual(sut.currentError?.errorCode, "AUTH_003")
    }

    func testHandleAppErrorWithoutAlert() {
        let error = AuthError.tokenExpired

        sut.handle(error, showAlert: false)

        XCTAssertNil(sut.currentError)
        XCTAssertFalse(sut.showingError)
    }

    func testShowErrorWithRecoverableError() {
        let error = AuthError.networkError(nil)
        var retryCalled = false

        sut.showError(error) {
            retryCalled = true
        }

        XCTAssertTrue(sut.showingError)
        XCTAssertNotNil(sut.retryAction)

        sut.retryAction?()
        XCTAssertTrue(retryCalled)
    }

    func testShowErrorWithNonRecoverableError() {
        let error = AuthError.invalidCredentials

        sut.showError(error) {
            XCTFail("Retry should not be set for non-recoverable errors")
        }

        XCTAssertTrue(sut.showingError)
        XCTAssertNil(sut.retryAction)
    }

    func testDismissError() {
        sut.showError(AuthError.tokenExpired)
        XCTAssertTrue(sut.showingError)

        sut.dismissError()

        XCTAssertFalse(sut.showingError)
        XCTAssertNil(sut.currentError)
        XCTAssertNil(sut.retryAction)
    }
}

// MARK: - AppError Tests

final class AppErrorTests: XCTestCase {

    // MARK: - AuthError Tests

    func testAuthErrorCodes() {
        XCTAssertEqual(AuthError.userCancelled.errorCode, "AUTH_001")
        XCTAssertEqual(AuthError.invalidCredentials.errorCode, "AUTH_002")
        XCTAssertEqual(AuthError.tokenExpired.errorCode, "AUTH_003")
        XCTAssertEqual(AuthError.tokenRefreshFailed(nil).errorCode, "AUTH_004")
        XCTAssertEqual(AuthError.keychainError(nil).errorCode, "AUTH_005")
        XCTAssertEqual(AuthError.networkError(nil).errorCode, "AUTH_006")
    }

    func testAuthErrorRecoverability() {
        XCTAssertTrue(AuthError.userCancelled.isRecoverable)
        XCTAssertTrue(AuthError.networkError(nil).isRecoverable)
        XCTAssertFalse(AuthError.invalidCredentials.isRecoverable)
        XCTAssertFalse(AuthError.tokenExpired.isRecoverable)
    }

    func testAuthErrorDescriptions() {
        XCTAssertNotNil(AuthError.userCancelled.errorDescription)
        XCTAssertNotNil(AuthError.tokenExpired.recoverySuggestion)
    }

    // MARK: - SyncError Tests

    func testSyncErrorCodes() {
        XCTAssertEqual(SyncError.networkUnavailable.errorCode, "SYNC_001")
        XCTAssertEqual(SyncError.historyExpired.errorCode, "SYNC_002")
        XCTAssertEqual(SyncError.quotaExceeded.errorCode, "SYNC_003")
        XCTAssertEqual(SyncError.syncInProgress.errorCode, "SYNC_004")
        XCTAssertEqual(SyncError.partialFailure(successCount: 10, failureCount: 2).errorCode, "SYNC_005")
        XCTAssertEqual(SyncError.databaseError(nil).errorCode, "SYNC_006")
    }

    func testSyncErrorsAreRecoverable() {
        XCTAssertTrue(SyncError.networkUnavailable.isRecoverable)
        XCTAssertTrue(SyncError.historyExpired.isRecoverable)
        XCTAssertTrue(SyncError.quotaExceeded.isRecoverable)
        XCTAssertTrue(SyncError.syncInProgress.isRecoverable)
        XCTAssertTrue(SyncError.partialFailure(successCount: 1, failureCount: 1).isRecoverable)
        XCTAssertTrue(SyncError.databaseError(nil).isRecoverable)
    }

    // MARK: - APIError Tests

    func testAPIErrorCodes() {
        XCTAssertEqual(APIError.unauthorized.errorCode, "API_001")
        XCTAssertEqual(APIError.notFound.errorCode, "API_002")
        XCTAssertEqual(APIError.rateLimited(retryAfter: nil).errorCode, "API_003")
        XCTAssertEqual(APIError.invalidResponse.errorCode, "API_004")
        XCTAssertEqual(APIError.serverError(statusCode: 500).errorCode, "API_005")
        XCTAssertEqual(APIError.networkError(nil).errorCode, "API_006")
        XCTAssertEqual(APIError.decodingError(nil).errorCode, "API_007")
    }

    func testAPIErrorRecoverability() {
        XCTAssertTrue(APIError.rateLimited(retryAfter: 60).isRecoverable)
        XCTAssertTrue(APIError.networkError(nil).isRecoverable)
        XCTAssertTrue(APIError.serverError(statusCode: 503).isRecoverable)
        XCTAssertFalse(APIError.unauthorized.isRecoverable)
        XCTAssertFalse(APIError.notFound.isRecoverable)
        XCTAssertFalse(APIError.invalidResponse.isRecoverable)
    }

    func testAPIErrorRateLimitedDescription() {
        let errorWithRetry = APIError.rateLimited(retryAfter: 30)
        XCTAssertTrue(errorWithRetry.errorDescription?.contains("30") ?? false)

        let errorWithoutRetry = APIError.rateLimited(retryAfter: nil)
        XCTAssertFalse(errorWithoutRetry.errorDescription?.contains("30") ?? true)
    }
}
