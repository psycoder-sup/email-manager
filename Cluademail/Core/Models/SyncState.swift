import Foundation
import SwiftData

// MARK: - Sync Status

/// Status of a sync operation.
enum SyncStatus: String, Codable, Sendable {
    /// No sync in progress
    case idle
    /// Sync currently running
    case syncing
    /// Sync completed with errors
    case error
    /// Sync completed successfully
    case completed
}

// MARK: - SyncState Model

/// Tracks sync progress per account for incremental sync.
/// Used to resume sync from last known state.
@Model
final class SyncState: Identifiable {

    // MARK: - Identity

    /// Identifier for Identifiable conformance (returns accountId)
    var id: UUID { accountId }

    /// Account ID this sync state belongs to
    @Attribute(.unique) var accountId: UUID

    // MARK: - Sync Progress

    /// Gmail history ID for incremental sync
    var historyId: String?

    /// Date of last full sync
    var lastFullSyncDate: Date?

    /// Date of last incremental sync
    var lastIncrementalSyncDate: Date?

    // MARK: - Status

    /// Number of emails synced
    var emailCount: Int

    /// Current sync status
    var syncStatus: SyncStatus

    /// Error message if sync failed (nil if no error)
    var errorMessage: String?

    // MARK: - Initialization

    /// Creates a new SyncState.
    /// - Parameter accountId: Account ID to track sync for
    init(accountId: UUID) {
        self.accountId = accountId
        self.historyId = nil
        self.lastFullSyncDate = nil
        self.lastIncrementalSyncDate = nil
        self.emailCount = 0
        self.syncStatus = .idle
        self.errorMessage = nil
    }
}
