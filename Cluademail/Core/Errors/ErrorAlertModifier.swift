import SwiftUI

/// View modifier that attaches an error alert to any view.
/// Uses the ErrorHandler to manage error display state.
struct ErrorAlertModifier: ViewModifier {
    @Bindable var errorHandler: ErrorHandler

    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: $errorHandler.showingError,
                presenting: errorHandler.currentError
            ) { error in
                // OK button is always present
                Button("OK") {
                    errorHandler.dismissError()
                }

                // Retry button only for recoverable errors
                if error.isRecoverable, let retry = errorHandler.retryAction {
                    Button("Retry") {
                        errorHandler.dismissError()
                        retry()
                    }
                }
            } message: { error in
                VStack {
                    Text(error.localizedDescription)
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                    }
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches the error alert modifier to this view.
    /// - Parameter errorHandler: The error handler to observe
    /// - Returns: A view with error alert capability
    func errorAlert(using errorHandler: ErrorHandler) -> some View {
        modifier(ErrorAlertModifier(errorHandler: errorHandler))
    }
}
