import Foundation
@testable import Cluademail

/// Protocol for error handling behavior - allows mocking in tests.
protocol ErrorHandling: AnyObject {
    var currentError: (any AppError)? { get }
    var showingError: Bool { get set }
    var retryAction: (() -> Void)? { get set }

    func handle(_ error: any AppError, context: String?, showAlert: Bool)
    func showError(_ error: any AppError, retryAction: (() -> Void)?)
    func dismissError()
}

/// Mock implementation of error handling for testing.
/// Since ErrorHandler uses @Observable (which makes it final),
/// we use a separate mock class that tracks calls for testing.
@MainActor
final class MockErrorHandling: ErrorHandling {

    // MARK: - State Properties

    private(set) var _currentError: (any AppError)?
    var currentError: (any AppError)? { _currentError }

    var showingError: Bool = false
    var retryAction: (() -> Void)?

    // MARK: - Tracking Properties

    /// All errors that have been handled
    private(set) var handledErrors: [any AppError] = []

    /// All contexts passed to handle()
    private(set) var handledContexts: [String?] = []

    /// Number of times handle() was called
    var handleCallCount: Int { handledErrors.count }

    /// Whether showError() was called
    private(set) var showErrorCalled = false

    /// Whether dismissError() was called
    private(set) var dismissErrorCalled = false

    // MARK: - Mock Implementations

    func handle(_ error: any AppError, context: String? = nil, showAlert: Bool = true) {
        handledErrors.append(error)
        handledContexts.append(context)

        if showAlert {
            showError(error, retryAction: nil)
        }
    }

    func showError(_ error: any AppError, retryAction: (() -> Void)? = nil) {
        showErrorCalled = true
        _currentError = error
        self.retryAction = error.isRecoverable ? retryAction : nil
        showingError = true
    }

    func dismissError() {
        dismissErrorCalled = true
        showingError = false
        _currentError = nil
        retryAction = nil
    }

    // MARK: - Test Helpers

    /// Resets all tracking state
    func reset() {
        handledErrors = []
        handledContexts = []
        showErrorCalled = false
        dismissErrorCalled = false
        _currentError = nil
        showingError = false
        retryAction = nil
    }

    /// Returns the last handled error
    var lastHandledError: (any AppError)? {
        handledErrors.last
    }

    /// Returns the last context
    var lastContext: String?? {
        handledContexts.last
    }
}
