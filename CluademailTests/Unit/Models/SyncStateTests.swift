import XCTest
@testable import Cluademail

/// Tests for SyncState model initialization and SyncStatus enum.
final class SyncStateTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitSetsAccountId() {
        let accountId = UUID()
        let syncState = SyncState(accountId: accountId)

        XCTAssertEqual(syncState.accountId, accountId)
    }

    func testInitSetsDefaultValues() {
        let syncState = TestFixtures.makeSyncState()

        XCTAssertNil(syncState.historyId)
        XCTAssertNil(syncState.lastFullSyncDate)
        XCTAssertNil(syncState.lastIncrementalSyncDate)
        XCTAssertEqual(syncState.emailCount, 0)
        XCTAssertEqual(syncState.syncStatus, .idle)
        XCTAssertNil(syncState.errorMessage)
    }

    // MARK: - SyncStatus Enum Tests

    func testSyncStatusRawValues() {
        XCTAssertEqual(SyncStatus.idle.rawValue, "idle")
        XCTAssertEqual(SyncStatus.syncing.rawValue, "syncing")
        XCTAssertEqual(SyncStatus.error.rawValue, "error")
        XCTAssertEqual(SyncStatus.completed.rawValue, "completed")
    }

    func testSyncStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [SyncStatus.idle, .syncing, .error, .completed] {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(SyncStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: - Identifiable Tests

    func testIdReturnsAccountId() {
        let accountId = UUID()
        let syncState = SyncState(accountId: accountId)
        XCTAssertEqual(syncState.id, accountId)
    }
}
