import Foundation
import SwiftData

// MARK: - Sync Result

/// Result of a sync operation.
enum SyncResult: Sendable {
    /// Sync completed successfully with counts of changes
    case success(newEmails: Int, updatedEmails: Int, deletedEmails: Int)

    /// Sync partially succeeded with some failures
    case partialSuccess(successCount: Int, failureCount: Int, errors: [String])

    /// Sync failed completely
    case failure(Error)

    /// Number of new emails synced
    var newEmailsCount: Int {
        switch self {
        case .success(let count, _, _): return count
        case .partialSuccess: return 0
        case .failure: return 0
        }
    }

    /// Whether sync completed (fully or partially)
    var isCompleted: Bool {
        switch self {
        case .success, .partialSuccess: return true
        case .failure: return false
        }
    }
}

// MARK: - Sync Progress

/// Progress of a sync operation for a single account.
struct SyncProgress: Sendable {
    /// Status of the sync
    let status: Status

    /// Human-readable progress message
    let message: String

    enum Status: Sendable {
        case idle
        case syncing
        case completed
        case error
    }
}

// MARK: - Sync Phase

/// Phase of progressive initial sync.
enum SyncPhase: Sendable {
    /// Phase 1: Fetch first 100 emails quickly
    case initial

    /// Phase 2: Continue fetching up to 1000 in background
    case extended

    /// Sync complete
    case complete
}

// MARK: - Sync Engine Protocol

/// Protocol for sync engines (Gmail API, IMAP fallback).
/// Enables mocking for tests and future IMAP implementation.
protocol SyncEngineProtocol: Sendable {
    /// Performs sync for the engine's account.
    /// - Returns: Result indicating success, partial success, or failure
    func sync() async throws -> SyncResult

    /// Cancels any in-progress sync.
    func cancelSync() async
}

// MARK: - Message Delta

/// Represents accumulated changes to a single message from history records.
/// Used for deduplicating multiple history entries for the same message.
struct MessageDelta: Sendable {
    /// Gmail message ID
    let messageId: String

    /// Whether the message was deleted
    var isDeleted: Bool = false

    /// Whether we need to fetch the full message (new message added)
    var needsFullFetch: Bool = false

    /// Labels to add to the message
    var labelsToAdd: Set<String> = []

    /// Labels to remove from the message
    var labelsToRemove: Set<String> = []

    init(messageId: String) {
        self.messageId = messageId
    }
}
