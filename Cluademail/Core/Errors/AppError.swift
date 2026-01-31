import Foundation

// MARK: - AppError Protocol

/// Base protocol for all application errors.
/// Provides consistent error handling across the app.
protocol AppError: LocalizedError, Sendable {
    /// Unique error code for logging and debugging
    var errorCode: String { get }

    /// Whether the error can be recovered from (e.g., retry possible)
    var isRecoverable: Bool { get }

    /// The underlying error, if any
    var underlyingError: Error? { get }
}

extension AppError {
    var underlyingError: Error? { nil }
}

// MARK: - AuthError

/// Errors related to authentication and authorization
enum AuthError: AppError {
    case userCancelled
    case invalidCredentials
    case tokenExpired
    case tokenRefreshFailed(Error?)
    case keychainError(Error?)
    case networkError(Error?)

    var errorCode: String {
        switch self {
        case .userCancelled: return "AUTH_001"
        case .invalidCredentials: return "AUTH_002"
        case .tokenExpired: return "AUTH_003"
        case .tokenRefreshFailed: return "AUTH_004"
        case .keychainError: return "AUTH_005"
        case .networkError: return "AUTH_006"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .userCancelled, .networkError:
            return true
        case .invalidCredentials, .tokenExpired, .tokenRefreshFailed, .keychainError:
            return false
        }
    }

    var underlyingError: Error? {
        switch self {
        case .tokenRefreshFailed(let error),
             .keychainError(let error),
             .networkError(let error):
            return error
        default:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Sign in was cancelled."
        case .invalidCredentials:
            return "Invalid credentials. Please sign in again."
        case .tokenExpired:
            return "Your session has expired. Please sign in again."
        case .tokenRefreshFailed:
            return "Failed to refresh authentication. Please sign in again."
        case .keychainError:
            return "Failed to access secure storage."
        case .networkError:
            return "Network error during authentication. Please check your connection."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .userCancelled:
            return "Try signing in again when ready."
        case .invalidCredentials, .tokenExpired, .tokenRefreshFailed:
            return "Go to Settings > Accounts and sign in again."
        case .keychainError:
            return "Try restarting the application."
        case .networkError:
            return "Check your internet connection and try again."
        }
    }
}

// MARK: - SyncError

/// Errors related to email synchronization
enum SyncError: AppError {
    case networkUnavailable
    case historyExpired
    case quotaExceeded
    case syncInProgress
    case partialFailure(successCount: Int, failureCount: Int)
    case databaseError(Error?)

    var errorCode: String {
        switch self {
        case .networkUnavailable: return "SYNC_001"
        case .historyExpired: return "SYNC_002"
        case .quotaExceeded: return "SYNC_003"
        case .syncInProgress: return "SYNC_004"
        case .partialFailure: return "SYNC_005"
        case .databaseError: return "SYNC_006"
        }
    }

    var isRecoverable: Bool {
        // All sync errors are recoverable
        true
    }

    var underlyingError: Error? {
        switch self {
        case .databaseError(let error):
            return error
        default:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Unable to sync. Network is unavailable."
        case .historyExpired:
            return "Sync history expired. A full sync will be performed."
        case .quotaExceeded:
            return "Gmail API quota exceeded. Please try again later."
        case .syncInProgress:
            return "A sync is already in progress."
        case .partialFailure(let success, let failure):
            return "Sync partially completed: \(success) succeeded, \(failure) failed."
        case .databaseError:
            return "Failed to save sync data."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .historyExpired:
            return "This will happen automatically on next sync."
        case .quotaExceeded:
            return "Wait a few minutes before syncing again."
        case .syncInProgress:
            return "Wait for the current sync to complete."
        case .partialFailure:
            return "Try syncing again to complete the operation."
        case .databaseError:
            return "Try syncing again. If the problem persists, restart the app."
        }
    }
}

// MARK: - APIError

/// Errors from Gmail API communication
enum APIError: AppError {
    case unauthorized
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse
    case serverError(statusCode: Int)
    case networkError(Error?)
    case decodingError(Error?)

    var errorCode: String {
        switch self {
        case .unauthorized: return "API_001"
        case .notFound: return "API_002"
        case .rateLimited: return "API_003"
        case .invalidResponse: return "API_004"
        case .serverError: return "API_005"
        case .networkError: return "API_006"
        case .decodingError: return "API_007"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .rateLimited, .networkError, .serverError:
            return true
        case .unauthorized, .notFound, .invalidResponse, .decodingError:
            return false
        }
    }

    var underlyingError: Error? {
        switch self {
        case .networkError(let error), .decodingError(let error):
            return error
        default:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Not authorized to access Gmail. Please sign in again."
        case .notFound:
            return "The requested email was not found."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Too many requests. Please wait \(Int(seconds)) seconds."
            }
            return "Too many requests. Please try again later."
        case .invalidResponse:
            return "Received an invalid response from Gmail."
        case .serverError(let code):
            return "Gmail server error (code: \(code))."
        case .networkError:
            return "Network error communicating with Gmail."
        case .decodingError:
            return "Failed to parse Gmail response."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unauthorized:
            return "Go to Settings > Accounts and sign in again."
        case .notFound:
            return "The email may have been deleted or moved."
        case .rateLimited:
            return "Wait and try again."
        case .invalidResponse, .decodingError:
            return "If this persists, the app may need to be updated."
        case .serverError:
            return "Gmail may be experiencing issues. Try again later."
        case .networkError:
            return "Check your internet connection and try again."
        }
    }
}
