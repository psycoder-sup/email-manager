import Foundation
import os.log

// MARK: - Sync Scheduler

/// Background sync scheduler with configurable interval.
/// Auto-starts on app launch and runs periodic sync.
/// Marked @MainActor for thread-safe state access.
@MainActor
final class SyncScheduler {

    // MARK: - Properties

    /// The sync coordinator to use for syncing
    private let coordinator: SyncCoordinator

    /// The scheduler task (nil if not running)
    private var schedulerTask: Task<Void, Never>?

    /// Current sync interval in seconds
    private(set) var syncInterval: TimeInterval

    /// Default sync interval (5 minutes)
    nonisolated static let defaultInterval: TimeInterval = 300

    /// Whether the scheduler is currently running
    var isRunning: Bool {
        schedulerTask != nil && !(schedulerTask?.isCancelled ?? true)
    }

    // MARK: - Initialization

    /// Creates a new sync scheduler.
    /// - Parameters:
    ///   - coordinator: The sync coordinator to use
    ///   - interval: Initial sync interval (default: 5 minutes)
    init(
        coordinator: SyncCoordinator,
        interval: TimeInterval = SyncScheduler.defaultInterval
    ) {
        self.coordinator = coordinator
        self.syncInterval = interval
    }

    // MARK: - Public Methods

    /// Starts the scheduled sync.
    /// Performs an immediate sync, then repeats at the configured interval.
    @MainActor
    func start() {
        guard !isRunning else {
            Logger.sync.warning("Scheduler already running")
            return
        }

        Logger.sync.info("Starting sync scheduler with \(self.syncInterval)s interval")

        schedulerTask = Task { [weak self] in
            guard let self else { return }

            // Immediate sync on start
            await self.coordinator.syncAllAccounts()

            // Periodic sync loop
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.syncInterval * 1_000_000_000))

                    guard !Task.isCancelled else { break }

                    await self.coordinator.syncAllAccounts()

                } catch {
                    // Task was cancelled
                    break
                }
            }

            Logger.sync.info("Sync scheduler stopped")
        }
    }

    /// Stops the scheduled sync.
    @MainActor
    func stop() {
        guard isRunning else {
            Logger.sync.warning("Scheduler not running")
            return
        }

        schedulerTask?.cancel()
        schedulerTask = nil

        Logger.sync.info("Sync scheduler stopped")
    }

    /// Triggers an immediate sync without affecting the schedule.
    @MainActor
    func triggerImmediateSync() async {
        Logger.sync.info("Triggering immediate sync")
        await coordinator.syncAllAccounts()
    }

    /// Updates the sync interval.
    /// If the scheduler is running, it will be restarted with the new interval.
    /// - Parameter interval: New interval in seconds
    @MainActor
    func updateInterval(_ interval: TimeInterval) {
        let wasRunning = isRunning

        if wasRunning {
            stop()
        }

        syncInterval = interval
        Logger.sync.info("Sync interval updated to \(interval)s")

        if wasRunning {
            start()
        }
    }
}
