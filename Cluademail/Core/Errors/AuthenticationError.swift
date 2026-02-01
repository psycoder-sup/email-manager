import Foundation

/// Errors related to OAuth authentication.
enum AuthenticationError: AppError {
    /// User cancelled the authentication flow
    case userCancelled

    /// Received an invalid response from the OAuth server
    case invalidResponse

    /// Failed to exchange authorization code for tokens
    case tokenExchangeFailed(String?)

    /// The access token has expired
    case tokenExpired

    /// Failed to refresh the access token
    case refreshFailed(Error?)

    /// The token has been revoked
    case tokenRevoked

    /// Rate limited by the OAuth server
    case rateLimited(retryAfter: TimeInterval)

    /// Network error during authentication
    case networkError(Error)

    /// The account is already signed in
    case accountAlreadyExists(String)

    /// Refresh token has expired (common for unverified apps)
    case invalidGrant

    /// OAuth configuration is missing
    case missingConfiguration(String)

    /// Failed to parse callback URL
    case invalidCallbackURL

    // MARK: - AppError Conformance

    var errorCode: String {
        switch self {
        case .userCancelled: return "OAUTH_001"
        case .invalidResponse: return "OAUTH_002"
        case .tokenExchangeFailed: return "OAUTH_003"
        case .tokenExpired: return "OAUTH_004"
        case .refreshFailed: return "OAUTH_005"
        case .tokenRevoked: return "OAUTH_006"
        case .rateLimited: return "OAUTH_007"
        case .networkError: return "OAUTH_008"
        case .accountAlreadyExists: return "OAUTH_009"
        case .invalidGrant: return "OAUTH_010"
        case .missingConfiguration: return "OAUTH_011"
        case .invalidCallbackURL: return "OAUTH_012"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .userCancelled, .networkError, .rateLimited:
            return true
        case .tokenExpired, .invalidGrant:
            return true // Can retry with re-authentication
        case .invalidResponse, .tokenExchangeFailed, .refreshFailed,
             .tokenRevoked, .accountAlreadyExists, .missingConfiguration, .invalidCallbackURL:
            return false
        }
    }

    var underlyingError: Error? {
        switch self {
        case .refreshFailed(let error):
            return error
        case .networkError(let error):
            return error
        default:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Sign in was cancelled."
        case .invalidResponse:
            return "Received an invalid response from Google."
        case .tokenExchangeFailed(let message):
            if let message = message {
                return "Authentication failed: \(message)"
            }
            return "Failed to complete authentication with Google."
        case .tokenExpired:
            return "Your session has expired."
        case .refreshFailed:
            return "Failed to refresh your authentication."
        case .tokenRevoked:
            return "Your access has been revoked."
        case .rateLimited(let retryAfter):
            return "Too many requests. Please wait \(Int(retryAfter)) seconds."
        case .networkError:
            return "Network error during authentication."
        case .accountAlreadyExists(let email):
            return "The account \(email) is already signed in."
        case .invalidGrant:
            return "Your authentication has expired. Please sign in again."
        case .missingConfiguration(let detail):
            return "Authentication not configured: \(detail)"
        case .invalidCallbackURL:
            return "Failed to process authentication response."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .userCancelled:
            return "Try signing in again when ready."
        case .invalidResponse, .tokenExchangeFailed, .invalidCallbackURL:
            return "Please try again. If the problem persists, contact support."
        case .tokenExpired, .invalidGrant:
            return "Go to Settings > Accounts and sign in again."
        case .refreshFailed:
            return "Sign out and sign in again to restore access."
        case .tokenRevoked:
            return "Sign in again to restore access."
        case .rateLimited:
            return "Wait a moment and try again."
        case .networkError:
            return "Check your internet connection and try again."
        case .accountAlreadyExists:
            return "Use a different account or sign out first."
        case .missingConfiguration:
            return "Please contact the developer."
        }
    }
}
