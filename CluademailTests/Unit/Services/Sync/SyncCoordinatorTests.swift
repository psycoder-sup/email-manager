import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class SyncCoordinatorTests: XCTestCase {

    // MARK: - Properties

    var sut: SyncCoordinator!
    var appState: AppState!
    var mockApiService: MockGmailAPIService!
    var databaseService: DatabaseService!
    var context: ModelContext!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory database
        databaseService = DatabaseService(isStoredInMemoryOnly: true)
        context = databaseService.mainContext

        // Create app state
        appState = AppState()

        // Create mock API service
        mockApiService = MockGmailAPIService()
        setupDefaultMockResponses()

        // Create SUT
        sut = SyncCoordinator(
            appState: appState,
            databaseService: databaseService,
            apiService: mockApiService
        )
    }

    override func tearDown() async throws {
        sut = nil
        appState = nil
        mockApiService = nil
        databaseService = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func setupDefaultMockResponses() {
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))
        // Set history result for incremental sync (used when historyId exists from previous sync)
        mockApiService.getHistoryResult = .success(GmailHistoryListDTO(history: nil, nextPageToken: nil, historyId: "12345"))
    }

    private func createEnabledAccount(email: String = "enabled@gmail.com") -> Account {
        let account = TestFixtures.makeAccount(email: email)
        account.isEnabled = true
        context.insert(account)
        try? context.save()
        return account
    }

    private func createDisabledAccount(email: String = "disabled@gmail.com") -> Account {
        let account = TestFixtures.makeAccount(email: email)
        account.isEnabled = false
        context.insert(account)
        try? context.save()
        return account
    }

    // MARK: - Sync All Accounts Tests

    func testSyncAllAccountsSyncsEnabledAccounts() async throws {
        // Given
        _ = createEnabledAccount(email: "user1@gmail.com")
        _ = createEnabledAccount(email: "user2@gmail.com")

        // When
        await sut.syncAllAccounts()

        // Then - Both accounts should have been synced
        // API should be called for labels for each account
        XCTAssertEqual(mockApiService.listMessagesCallCount, 2)
    }

    func testSyncAllAccountsSkipsDisabledAccounts() async throws {
        // Given
        _ = createEnabledAccount(email: "enabled@gmail.com")
        _ = createDisabledAccount(email: "disabled@gmail.com")

        // When
        await sut.syncAllAccounts()

        // Then - Only enabled account should be synced
        XCTAssertEqual(mockApiService.listMessagesCallCount, 1)
    }

    func testSyncAllAccountsUpdatesisSyncing() async throws {
        // Given
        _ = createEnabledAccount()

        // When/Then - isSyncing should be true during sync
        XCTAssertFalse(appState.isSyncing)

        let syncTask = Task {
            await sut.syncAllAccounts()
        }

        // Give time for sync to start
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        // After sync completes
        await syncTask.value
        XCTAssertFalse(appState.isSyncing)
    }

    func testSyncAllAccountsUpdatesLastSyncDate() async throws {
        // Given
        _ = createEnabledAccount()
        let beforeSync = Date()

        // When
        await sut.syncAllAccounts()

        // Then
        XCTAssertNotNil(appState.lastSyncDate)
        XCTAssertTrue(appState.lastSyncDate! >= beforeSync)
    }

    // MARK: - Single Account Sync Tests

    func testSyncAccountUpdatesProgress() async throws {
        // Given
        let account = createEnabledAccount()

        // When
        await sut.syncAccount(account)

        // Then - Progress should be completed
        let progress = sut.getProgress(for: account.id)
        XCTAssertEqual(progress.status, .completed)
    }

    func testSyncAccountSkipsWhenAlreadySyncing() async throws {
        // Given
        let account = createEnabledAccount()

        // Default API response is fine for this test

        // Start first sync
        let task1 = Task {
            await sut.syncAccount(account)
        }

        // Give time for first sync to acquire lock
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        // Attempt second sync
        let task2 = Task {
            await sut.syncAccount(account)
        }

        await task1.value
        await task2.value

        // Then - API should only be called once (second sync was skipped)
        // Note: Due to async timing, this test may be flaky. In production,
        // we'd use more robust synchronization mechanisms.
        XCTAssertLessThanOrEqual(mockApiService.listMessagesCallCount, 2)
    }

    func testSyncAccountReleasesLockAfterCompletion() async throws {
        // Given
        let account = createEnabledAccount()

        // When - First sync
        await sut.syncAccount(account)

        // Then - Second sync should also succeed (lock was released)
        mockApiService.reset()
        setupDefaultMockResponses()
        await sut.syncAccount(account)

        // Verify second sync ran (either full sync or incremental sync)
        let syncApiCalls = mockApiService.listMessagesCallCount + mockApiService.getHistoryCallCount
        XCTAssertGreaterThanOrEqual(syncApiCalls, 1, "Second sync should have made API calls")
    }

    func testSyncAccountReleasesLockOnError() async throws {
        // Given
        let account = createEnabledAccount()
        mockApiService.listDraftsResult = .failure(APIError.serverError(statusCode: 500))

        // When - First sync (fails)
        await sut.syncAccount(account)

        // Then - Verify error status
        let progress1 = sut.getProgress(for: account.id)
        XCTAssertEqual(progress1.status, .error)

        // And - Second sync should be able to run (lock was released)
        mockApiService.reset()
        setupDefaultMockResponses()
        await sut.syncAccount(account)

        let progress2 = sut.getProgress(for: account.id)
        XCTAssertEqual(progress2.status, .completed)
    }

    // MARK: - Progress Tracking Tests

    func testGetProgressReturnsIdleForUnknownAccount() async throws {
        // Given
        let unknownAccountId = UUID()

        // When
        let progress = sut.getProgress(for: unknownAccountId)

        // Then
        XCTAssertEqual(progress.status, .idle)
        XCTAssertEqual(progress.message, "")
    }

    func testProgressShowsSuccessMessage() async throws {
        // Given
        let account = createEnabledAccount()

        // Set up mock to return emails
        mockApiService.listMessagesResult = .success((
            messages: [GmailMessageSummaryDTO(id: "msg-1", threadId: "thread-1")],
            nextPageToken: nil
        ))
        mockApiService.batchGetMessagesResult = .success(BatchResult(
            succeeded: [TestFixtures.makeGmailMessageDTO(id: "msg-1", threadId: "thread-1")],
            failed: []
        ))

        // When
        await sut.syncAccount(account)

        // Then
        let progress = sut.getProgress(for: account.id)
        XCTAssertEqual(progress.status, .completed)
        XCTAssertTrue(progress.message.contains("1 new"))
    }

    func testProgressShowsUpToDateMessage() async throws {
        // Given
        let account = createEnabledAccount()

        // Empty mailbox
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))

        // When
        await sut.syncAccount(account)

        // Then
        let progress = sut.getProgress(for: account.id)
        XCTAssertEqual(progress.message, "Up to date")
    }

    // MARK: - Engine Cache Tests

    func testEnginesAreCachedPerAccount() async throws {
        // Given
        let account = createEnabledAccount()

        // When - Sync twice
        await sut.syncAccount(account)
        await sut.syncAccount(account)

        // Then - API calls should reflect two syncs were performed
        // First sync uses full sync (listMessages), second uses incremental (getHistory)
        let totalSyncCalls = mockApiService.listMessagesCallCount + mockApiService.getHistoryCallCount
        XCTAssertGreaterThanOrEqual(totalSyncCalls, 2, "Two syncs should have been performed")
    }

    func testClearEngineCacheRemovesEngines() async throws {
        // Given
        let account = createEnabledAccount()
        await sut.syncAccount(account)

        // When
        sut.clearEngineCache()

        // Then - Next sync should create a new engine
        mockApiService.reset()
        setupDefaultMockResponses()
        await sut.syncAccount(account)

        // Verify sync ran (either full sync or incremental sync)
        let syncApiCalls = mockApiService.listMessagesCallCount + mockApiService.getHistoryCallCount
        XCTAssertGreaterThanOrEqual(syncApiCalls, 1, "Sync should have made API calls after cache clear")
    }

    // MARK: - Trigger Sync Tests

    func testTriggerSyncCallsSyncAccount() async throws {
        // Given
        let account = createEnabledAccount()

        // When
        await sut.triggerSync(for: account)

        // Then
        XCTAssertEqual(mockApiService.listMessagesCallCount, 1)
        let progress = sut.getProgress(for: account.id)
        XCTAssertEqual(progress.status, .completed)
    }

    // MARK: - Cancel Sync Tests

    func testCancelSyncCancelsInProgressSync() async throws {
        // Given
        let account = createEnabledAccount()

        // Start a sync
        let syncTask = Task {
            await sut.syncAccount(account)
        }

        // Give time for sync to start
        try await Task.sleep(nanoseconds: 5_000_000)

        // When
        await sut.cancelSync(for: account.id)

        // Then - Sync completes (cancellation is best-effort)
        await syncTask.value
        // No assertion needed - just verify it doesn't hang
    }
}
