import Foundation
import os.log

/// Manages automatic saving of drafts with debouncing.
@MainActor
final class DraftAutoSaveManager {

    // MARK: - Configuration

    /// Delay before saving after last change (debounce).
    private let debounceInterval: TimeInterval = 2.0

    /// Interval for periodic saves while editing.
    private let autoSaveInterval: TimeInterval = 30.0

    // MARK: - State

    private var debounceTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var lastSaveDate: Date?

    // MARK: - Callback

    private let onSave: () async -> Void

    // MARK: - Initialization

    init(onSave: @escaping () async -> Void) {
        self.onSave = onSave
    }

    // Note: deinit removed - @MainActor class deinit may run on non-main thread.
    // ComposeView calls stopAutoSave() in onDisappear which handles cleanup.

    // MARK: - Public Methods

    /// Stops auto-save and cancels pending tasks.
    func stopAutoSave() {
        cancelPending()
    }

    /// Schedules an auto-save after a debounce delay.
    func scheduleAutoSave() {
        // Cancel any pending debounce
        debounceTask?.cancel()

        // Schedule new debounce
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .seconds(debounceInterval))

                // Check if enough time has passed since last save
                if shouldSave {
                    await performSave()
                }
            } catch {
                // Task was cancelled, that's fine
            }
        }

        // Start periodic save timer if not already running
        startPeriodicSave()
    }

    /// Forces an immediate save.
    func saveNow() async {
        cancelPending()
        await performSave()
    }

    /// Cancels any pending saves.
    func cancelPending() {
        debounceTask?.cancel()
        debounceTask = nil
        periodicTask?.cancel()
        periodicTask = nil
    }

    // MARK: - Private Methods

    private var shouldSave: Bool {
        guard let lastSave = lastSaveDate else { return true }
        return Date().timeIntervalSince(lastSave) > debounceInterval
    }

    private func performSave() async {
        lastSaveDate = Date()
        await onSave()
        Logger.ui.debug("Auto-save triggered")
    }

    private func startPeriodicSave() {
        guard periodicTask == nil else { return }

        periodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                do {
                    try await Task.sleep(for: .seconds(autoSaveInterval))
                    await performSave()
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
    }
}
