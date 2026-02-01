import Foundation

/// Errors related to Keychain operations.
enum KeychainError: AppError {
    /// The requested item was not found in the Keychain
    case itemNotFound

    /// An item with the same key already exists
    case duplicateItem

    /// Keychain operation failed with an unexpected status
    case unexpectedStatus(OSStatus)

    /// Failed to encode data for Keychain storage
    case encodingError(Error)

    /// Failed to decode data from Keychain
    case decodingError(Error)

    // MARK: - AppError Conformance

    var errorCode: String {
        switch self {
        case .itemNotFound: return "KEYCHAIN_001"
        case .duplicateItem: return "KEYCHAIN_002"
        case .unexpectedStatus: return "KEYCHAIN_003"
        case .encodingError: return "KEYCHAIN_004"
        case .decodingError: return "KEYCHAIN_005"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .itemNotFound, .duplicateItem:
            return false
        case .unexpectedStatus, .encodingError, .decodingError:
            return true
        }
    }

    var underlyingError: Error? {
        switch self {
        case .encodingError(let error), .decodingError(let error):
            return error
        default:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The requested item was not found in secure storage."
        case .duplicateItem:
            return "An item with this key already exists in secure storage."
        case .unexpectedStatus(let status):
            return "Secure storage operation failed (error code: \(status))."
        case .encodingError:
            return "Failed to encode data for secure storage."
        case .decodingError:
            return "Failed to decode data from secure storage."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .itemNotFound:
            return "Sign in again to create new credentials."
        case .duplicateItem:
            return "This is an internal error. Try signing out and signing in again."
        case .unexpectedStatus, .encodingError, .decodingError:
            return "Try restarting the app. If the problem persists, contact support."
        }
    }
}
