import Foundation
import SwiftData
import os.log

// MARK: - Sync Coordinator

/// Coordinates sync across multiple accounts.
/// Updates AppState directly for UI observation.
@Observable
@MainActor
final class SyncCoordinator {

    // MARK: - Dependencies

    private let appState: AppState
    private let databaseService: DatabaseService
    private let apiService: any GmailAPIServiceProtocol
    private let accountRepository: AccountRepository
    private let syncLock: SyncLock

    // MARK: - Engine Cache

    /// Cached sync engines per account ID
    private var engines: [UUID: SyncEngine] = [:]

    // MARK: - Progress Tracking

    /// Per-account sync progress (observable)
    private(set) var syncProgress: [UUID: SyncProgress] = [:]

    // MARK: - Initialization

    init(
        appState: AppState,
        databaseService: DatabaseService,
        apiService: any GmailAPIServiceProtocol = GmailAPIService.shared
    ) {
        self.appState = appState
        self.databaseService = databaseService
        self.apiService = apiService
        self.accountRepository = AccountRepository()
        self.syncLock = SyncLock()
    }

    // MARK: - Public Methods

    /// Syncs all enabled accounts concurrently.
    func syncAllAccounts() async {
        Logger.sync.info("Starting sync for all accounts")

        appState.isSyncing = true

        defer {
            appState.isSyncing = false
            appState.lastSyncDate = Date()
            Logger.sync.info("Sync completed for all accounts")
        }

        let context = databaseService.mainContext

        do {
            let accounts = try await accountRepository.fetchAll(context: context)
            let enabledAccounts = accounts.filter { $0.isEnabled }

            guard !enabledAccounts.isEmpty else {
                Logger.sync.info("No enabled accounts to sync")
                return
            }

            // Sync accounts concurrently
            // Extract account IDs before TaskGroup to avoid passing SwiftData models across isolation boundaries
            let accountIds = enabledAccounts.map(\.id)

            await withTaskGroup(of: Void.self) { group in
                for accountId in accountIds {
                    group.addTask {
                        await self.syncAccountById(accountId)
                    }
                }
            }

        } catch {
            Logger.sync.error("Failed to fetch accounts: \(error)")
        }
    }

    /// Syncs a single account.
    /// - Parameter account: The account to sync
    func syncAccount(_ account: Account) async {
        let accountId = account.id

        Logger.sync.info("Syncing account: \(account.email, privacy: .private(mask: .hash))")

        // Try to acquire lock
        guard await syncLock.acquireLock(for: accountId) else {
            Logger.sync.warning("Sync already in progress for account: \(account.email, privacy: .private(mask: .hash))")
            return
        }

        // Update progress
        syncProgress[accountId] = SyncProgress(status: .syncing, message: "Syncing...")

        do {
            let engine = getOrCreateEngine(for: account)
            let result = try await engine.sync()

            // Update progress based on result
            switch result {
            case .success(let newEmails, let updatedEmails, let deletedEmails):
                let message = formatResultMessage(
                    new: newEmails,
                    updated: updatedEmails,
                    deleted: deletedEmails
                )
                syncProgress[accountId] = SyncProgress(status: .completed, message: message)

            case .partialSuccess(let success, let failure, _):
                syncProgress[accountId] = SyncProgress(
                    status: .completed,
                    message: "Completed with \(failure) errors"
                )
                Logger.sync.warning("Partial sync: \(success) succeeded, \(failure) failed")

            case .failure(let error):
                syncProgress[accountId] = SyncProgress(
                    status: .error,
                    message: error.localizedDescription
                )
            }

        } catch {
            Logger.sync.error("Sync failed for \(account.email, privacy: .private(mask: .hash)): \(error)")
            syncProgress[accountId] = SyncProgress(
                status: .error,
                message: error.localizedDescription
            )
        }

        // Always release the lock after sync completes (success or failure)
        await syncLock.releaseLock(for: accountId)
    }

    /// Triggers an immediate sync for a specific account.
    /// - Parameter account: The account to sync
    func triggerSync(for account: Account) async {
        await syncAccount(account)
    }

    /// Cancels sync for an account if in progress.
    /// - Parameter accountId: The account ID to cancel sync for
    func cancelSync(for accountId: UUID) async {
        if let engine = engines[accountId] {
            await engine.cancelSync()
        }
    }

    /// Syncs an account by its ID. Used internally for TaskGroup-based concurrent sync.
    /// Fetches the Account fresh from the database to ensure proper MainActor binding.
    /// - Parameter accountId: The account ID to sync
    private func syncAccountById(_ accountId: UUID) async {
        do {
            let context = databaseService.mainContext
            guard let account = try await accountRepository.fetch(byId: accountId, context: context) else {
                Logger.sync.warning("Account not found for sync: \(accountId)")
                return
            }
            await syncAccount(account)
        } catch {
            Logger.sync.error("Failed to fetch account for sync: \(error)")
        }
    }

    /// Gets the current sync progress for an account.
    /// - Parameter accountId: The account ID
    /// - Returns: The sync progress, or idle if no progress tracked
    func getProgress(for accountId: UUID) -> SyncProgress {
        syncProgress[accountId] ?? SyncProgress(status: .idle, message: "")
    }

    /// Clears the engine cache (useful for testing or account removal).
    func clearEngineCache() {
        engines.removeAll()
    }

    // MARK: - Private Methods

    private func getOrCreateEngine(for account: Account) -> SyncEngine {
        if let existing = engines[account.id] {
            return existing
        }

        let engine = SyncEngine(
            accountId: account.id,
            accountEmail: account.email,
            apiService: apiService,
            databaseService: databaseService
        )
        engines[account.id] = engine
        return engine
    }

    private func formatResultMessage(new: Int, updated: Int, deleted: Int) -> String {
        var parts: [String] = []

        if new > 0 {
            parts.append("\(new) new")
        }
        if updated > 0 {
            parts.append("\(updated) updated")
        }
        if deleted > 0 {
            parts.append("\(deleted) deleted")
        }

        if parts.isEmpty {
            return "Up to date"
        }

        return parts.joined(separator: ", ")
    }
}
