import Foundation
import os.log
import Observation

/// Centralized error handling service.
/// Logs errors and optionally displays them to the user.
@Observable
@MainActor
final class ErrorHandler {

    // MARK: - Properties

    /// The current error being displayed to the user
    private(set) var currentError: (any AppError)?

    /// Whether an error alert should be shown
    var showingError: Bool = false

    /// Retry action for recoverable errors
    var retryAction: (() -> Void)?

    // MARK: - Public Methods

    /// Handles an error by logging it and optionally showing an alert.
    /// - Parameters:
    ///   - error: The error to handle
    ///   - context: Additional context for logging
    ///   - showAlert: Whether to show an alert to the user (default: true)
    func handle(_ error: any AppError, context: String? = nil, showAlert: Bool = true) {
        // Log the error
        let contextString = context.map { " [\($0)]" } ?? ""
        Logger.app.error("Error\(contextString): \(error.errorCode) - \(error.localizedDescription)")

        if let underlying = error.underlyingError {
            Logger.app.debug("Underlying error: \(underlying.localizedDescription)")
        }

        // Show alert if requested
        if showAlert {
            showError(error)
        }
    }

    /// Handles any Error type, wrapping it in a generic error if needed.
    /// - Parameters:
    ///   - error: The error to handle
    ///   - context: Additional context for logging
    ///   - showAlert: Whether to show an alert to the user
    func handle(_ error: Error, context: String? = nil, showAlert: Bool = true) {
        if let appError = error as? any AppError {
            handle(appError, context: context, showAlert: showAlert)
        } else {
            // Log generic error
            let contextString = context.map { " [\($0)]" } ?? ""
            Logger.app.error("Error\(contextString): \(error.localizedDescription)")

            if showAlert {
                // Create a wrapper to display
                showGenericError(error)
            }
        }
    }

    /// Displays an error alert to the user.
    /// - Parameters:
    ///   - error: The error to display
    ///   - retryAction: Optional retry closure. **Important:** Use `[weak self]` in the closure
    ///                  to avoid retain cycles since this closure is stored.
    func showError(_ error: any AppError, retryAction: (() -> Void)? = nil) {
        self.currentError = error
        self.retryAction = error.isRecoverable ? retryAction : nil
        self.showingError = true
    }

    /// Dismisses the current error alert.
    func dismissError() {
        showingError = false
        currentError = nil
        retryAction = nil
    }

    // MARK: - Private Methods

    private func showGenericError(_ error: Error) {
        // For non-AppError types, we still need to show something
        // Using a simple struct that conforms to AppError
        let wrapper = GenericErrorWrapper(error: error)
        currentError = wrapper
        retryAction = nil
        showingError = true
    }
}

// MARK: - Generic Error Wrapper

/// Wraps non-AppError types for display purposes.
/// Stores only the error description to satisfy Sendable requirements.
private struct GenericErrorWrapper: AppError, Sendable {
    let _errorDescription: String

    init(error: Error) {
        self._errorDescription = error.localizedDescription
    }

    var errorCode: String { "GENERIC_001" }
    var isRecoverable: Bool { false }
    var underlyingError: Error? { nil }

    var errorDescription: String? {
        _errorDescription
    }

    var recoverySuggestion: String? {
        "If this problem persists, please restart the application."
    }
}
