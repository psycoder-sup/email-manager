import Foundation

enum DatabaseError: AppError {
    case fetchFailed(Error)
    case saveFailed(Error)
    case deleteFailed(Error)
    case notFound(entityType: String, identifier: String)

    var errorCode: String {
        switch self {
        case .fetchFailed: "DB_001"
        case .saveFailed: "DB_002"
        case .deleteFailed: "DB_003"
        case .notFound: "DB_004"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .fetchFailed, .saveFailed, .deleteFailed: true
        case .notFound: false
        }
    }

    var underlyingError: Error? {
        switch self {
        case .fetchFailed(let error), .saveFailed(let error), .deleteFailed(let error):
            error
        case .notFound:
            nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .fetchFailed: "Failed to fetch data from database."
        case .saveFailed: "Failed to save data to database."
        case .deleteFailed: "Failed to delete data from database."
        case .notFound(let entityType, let identifier):
            "\(entityType) with identifier '\(identifier)' not found."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fetchFailed, .saveFailed, .deleteFailed:
            "Try again. If the problem persists, restart the app."
        case .notFound:
            "The requested data may have been deleted."
        }
    }
}
