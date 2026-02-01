import Foundation

// MARK: - Sync Lock

/// Actor-based lock to prevent concurrent syncs for the same account.
/// Only one sync per account can run at a time.
actor SyncLock {

    // MARK: - Properties

    /// Set of account IDs currently syncing
    private var activeSyncs: Set<UUID> = []

    // MARK: - Public Methods

    /// Attempts to acquire lock for an account.
    /// - Parameter accountId: The account ID to lock
    /// - Returns: true if lock acquired, false if account is already syncing
    func acquireLock(for accountId: UUID) -> Bool {
        guard !activeSyncs.contains(accountId) else {
            return false
        }
        activeSyncs.insert(accountId)
        return true
    }

    /// Releases lock for an account.
    /// - Parameter accountId: The account ID to unlock
    func releaseLock(for accountId: UUID) {
        activeSyncs.remove(accountId)
    }

    /// Checks if an account is currently syncing.
    /// - Parameter accountId: The account ID to check
    /// - Returns: true if account has an active sync
    func isLocked(_ accountId: UUID) -> Bool {
        activeSyncs.contains(accountId)
    }

    /// Returns count of currently active syncs.
    var activeCount: Int {
        activeSyncs.count
    }
}
