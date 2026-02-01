import XCTest
@testable import Cluademail

final class SyncLockTests: XCTestCase {

    // MARK: - Properties

    var sut: SyncLock!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = SyncLock()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Acquire Lock Tests

    func testAcquireLockSucceedsForNewAccount() async {
        // Given
        let accountId = UUID()

        // When
        let result = await sut.acquireLock(for: accountId)

        // Then
        XCTAssertTrue(result)
    }

    func testAcquireLockFailsWhenAlreadyLocked() async {
        // Given
        let accountId = UUID()
        _ = await sut.acquireLock(for: accountId)

        // When
        let result = await sut.acquireLock(for: accountId)

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Release Lock Tests

    func testReleaseLockAllowsReacquisition() async {
        // Given
        let accountId = UUID()
        _ = await sut.acquireLock(for: accountId)
        await sut.releaseLock(for: accountId)

        // When
        let result = await sut.acquireLock(for: accountId)

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - Is Locked Tests

    func testIsLockedReturnsTrueWhenLocked() async {
        // Given
        let accountId = UUID()
        _ = await sut.acquireLock(for: accountId)

        // When
        let result = await sut.isLocked(accountId)

        // Then
        XCTAssertTrue(result)
    }

    func testIsLockedReturnsFalseWhenNotLocked() async {
        // Given
        let accountId = UUID()

        // When
        let result = await sut.isLocked(accountId)

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Multiple Accounts Tests

    func testMultipleAccountsCanBeLocked() async {
        // Given
        let accountId1 = UUID()
        let accountId2 = UUID()
        let accountId3 = UUID()

        // When
        let result1 = await sut.acquireLock(for: accountId1)
        let result2 = await sut.acquireLock(for: accountId2)
        let result3 = await sut.acquireLock(for: accountId3)

        // Then
        XCTAssertTrue(result1)
        XCTAssertTrue(result2)
        XCTAssertTrue(result3)

        let activeCount = await sut.activeCount
        XCTAssertEqual(activeCount, 3)
    }

    func testReleaseLockOnlyAffectsTargetAccount() async {
        // Given
        let accountId1 = UUID()
        let accountId2 = UUID()
        _ = await sut.acquireLock(for: accountId1)
        _ = await sut.acquireLock(for: accountId2)

        // When
        await sut.releaseLock(for: accountId1)

        // Then
        let isLocked1 = await sut.isLocked(accountId1)
        let isLocked2 = await sut.isLocked(accountId2)
        XCTAssertFalse(isLocked1)
        XCTAssertTrue(isLocked2)
    }

    // MARK: - Active Count Tests

    func testActiveCountReflectsLockedAccounts() async {
        // Given
        let accountId1 = UUID()
        let accountId2 = UUID()

        // When - Initially empty
        let initialCount = await sut.activeCount
        XCTAssertEqual(initialCount, 0)

        // When - After acquiring locks
        _ = await sut.acquireLock(for: accountId1)
        _ = await sut.acquireLock(for: accountId2)
        let countAfterAcquire = await sut.activeCount
        XCTAssertEqual(countAfterAcquire, 2)

        // When - After releasing one lock
        await sut.releaseLock(for: accountId1)
        let countAfterRelease = await sut.activeCount
        XCTAssertEqual(countAfterRelease, 1)
    }
}
