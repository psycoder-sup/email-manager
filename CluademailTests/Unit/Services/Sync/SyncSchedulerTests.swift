import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class SyncSchedulerTests: XCTestCase {

    // MARK: - Properties

    var sut: SyncScheduler!
    var coordinator: SyncCoordinator!
    var appState: AppState!
    var mockApiService: MockGmailAPIService!
    var databaseService: DatabaseService!

    // Short interval for testing (100ms)
    let testInterval: TimeInterval = 0.1

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory database
        databaseService = DatabaseService(isStoredInMemoryOnly: true)

        // Create app state
        appState = AppState()

        // Create mock API service
        mockApiService = MockGmailAPIService()
        setupDefaultMockResponses()

        // Create coordinator
        coordinator = SyncCoordinator(
            appState: appState,
            databaseService: databaseService,
            apiService: mockApiService
        )

        // Create SUT with short interval
        sut = SyncScheduler(coordinator: coordinator, interval: testInterval)
    }

    override func tearDown() async throws {
        // Make sure scheduler is stopped
        sut.stop()
        sut = nil
        coordinator = nil
        appState = nil
        mockApiService = nil
        databaseService = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func setupDefaultMockResponses() {
        mockApiService.listLabelsResult = .success([])
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))
    }

    private func createTestAccount() {
        let account = TestFixtures.makeAccount(email: "test@gmail.com")
        account.isEnabled = true
        databaseService.mainContext.insert(account)
        try? databaseService.mainContext.save()
    }

    // MARK: - Start/Stop Tests

    func testStartBeginsScheduledSync() async throws {
        // Given
        createTestAccount()
        XCTAssertFalse(sut.isRunning)

        // When
        sut.start()

        // Then
        XCTAssertTrue(sut.isRunning)

        // Wait for immediate sync to trigger
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        XCTAssertGreaterThanOrEqual(mockApiService.listLabelsCallCount, 1)
    }

    func testStartTriggersImmediateSync() async throws {
        // Given
        createTestAccount()

        // When
        sut.start()

        // Wait just a bit for immediate sync
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        // Then - Sync should have been triggered immediately
        XCTAssertGreaterThanOrEqual(mockApiService.listLabelsCallCount, 1)
    }

    func testStopCancelsScheduledSync() async throws {
        // Given
        createTestAccount()
        sut.start()

        // Wait for immediate sync
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        let callCountAtStop = mockApiService.listLabelsCallCount

        // When
        sut.stop()

        // Then
        XCTAssertFalse(sut.isRunning)

        // Wait past the interval
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

        // No additional syncs should have occurred
        XCTAssertEqual(mockApiService.listLabelsCallCount, callCountAtStop)
    }

    // MARK: - Running State Tests

    func testIsRunningReflectsState() async throws {
        // Initially not running
        XCTAssertFalse(sut.isRunning)

        // After start
        sut.start()
        XCTAssertTrue(sut.isRunning)

        // After stop
        sut.stop()
        XCTAssertFalse(sut.isRunning)
    }

    // MARK: - Immediate Sync Tests

    func testTriggerImmediateSyncDoesNotAffectSchedule() async throws {
        // Given
        createTestAccount()
        sut.start()

        // Wait for initial sync
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        let countAfterStart = mockApiService.listLabelsCallCount

        // When
        await sut.triggerImmediateSync()

        // Then - One more sync should have happened
        XCTAssertEqual(mockApiService.listLabelsCallCount, countAfterStart + 1)

        // And scheduler should still be running
        XCTAssertTrue(sut.isRunning)
    }

    func testTriggerImmediateSyncWorksWhenNotRunning() async throws {
        // Given
        createTestAccount()
        XCTAssertFalse(sut.isRunning)

        // When
        await sut.triggerImmediateSync()

        // Then - Sync should have run
        XCTAssertEqual(mockApiService.listLabelsCallCount, 1)

        // And scheduler should still not be running
        XCTAssertFalse(sut.isRunning)
    }

    // MARK: - Interval Update Tests

    func testUpdateIntervalRestartsIfRunning() async throws {
        // Given
        createTestAccount()
        sut.start()

        // Wait for initial sync
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        // When
        let newInterval: TimeInterval = 0.2  // 200ms
        sut.updateInterval(newInterval)

        // Then - Still running with new interval
        XCTAssertTrue(sut.isRunning)
        XCTAssertEqual(sut.syncInterval, newInterval)
    }

    func testUpdateIntervalDoesNotStartIfNotRunning() async throws {
        // Given
        XCTAssertFalse(sut.isRunning)

        // When
        sut.updateInterval(0.5)

        // Then
        XCTAssertFalse(sut.isRunning)
        XCTAssertEqual(sut.syncInterval, 0.5)
    }

    // MARK: - Idempotency Tests

    func testMultipleStartCallsAreIgnored() async throws {
        // Given
        createTestAccount()
        sut.start()

        // When
        sut.start()  // Second call
        sut.start()  // Third call

        // Then - Still running, no issues
        XCTAssertTrue(sut.isRunning)
    }

    func testMultipleStopCallsAreIgnored() async throws {
        // Given
        sut.start()
        sut.stop()

        // When
        sut.stop()  // Second call
        sut.stop()  // Third call

        // Then - Not running, no issues
        XCTAssertFalse(sut.isRunning)
    }

    // MARK: - Default Interval Tests

    func testDefaultIntervalIs5Minutes() {
        XCTAssertEqual(SyncScheduler.defaultInterval, 300)
    }

    func testInitializesWithProvidedInterval() {
        // Given/When
        let customScheduler = SyncScheduler(coordinator: coordinator, interval: 60)

        // Then
        XCTAssertEqual(customScheduler.syncInterval, 60)
    }

    func testInitializesWithDefaultIntervalIfNotProvided() {
        // Given/When
        let defaultScheduler = SyncScheduler(coordinator: coordinator)

        // Then
        XCTAssertEqual(defaultScheduler.syncInterval, SyncScheduler.defaultInterval)
    }
}
