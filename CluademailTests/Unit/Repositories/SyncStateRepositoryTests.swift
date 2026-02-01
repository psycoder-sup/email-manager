import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class SyncStateRepositoryTests: XCTestCase {

    // MARK: - Properties

    var container: ModelContainer!
    var context: ModelContext!
    var repository: SyncStateRepository!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        let schema = Schema([
            Account.self,
            Email.self,
            EmailThread.self,
            Attachment.self,
            Label.self,
            SyncState.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        repository = SyncStateRepository()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        repository = nil
    }

    // MARK: - Fetch Tests

    func testFetchReturnsSyncStateWhenExists() async throws {
        // Given
        let accountId = UUID()
        let syncState = TestFixtures.makeSyncState(accountId: accountId)
        context.insert(syncState)
        try context.save()

        // When
        let fetched = try await repository.fetch(accountId: accountId, context: context)

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.accountId, accountId)
    }

    func testFetchReturnsNilWhenNotExists() async throws {
        let fetched = try await repository.fetch(accountId: UUID(), context: context)
        XCTAssertNil(fetched)
    }

    // MARK: - Save Tests

    func testSaveInsertsSyncState() async throws {
        // Given
        let accountId = UUID()
        let syncState = TestFixtures.makeSyncState(accountId: accountId)

        // When
        try await repository.save(syncState, context: context)

        // Then
        let fetched = try await repository.fetch(accountId: accountId, context: context)
        XCTAssertNotNil(fetched)
    }

    func testSavePersistsSyncStateProperties() async throws {
        // Given
        let accountId = UUID()
        let syncState = SyncState(accountId: accountId)
        syncState.historyId = "12345"
        syncState.emailCount = 100
        syncState.syncStatus = .completed
        syncState.lastFullSyncDate = Date()

        // When
        try await repository.save(syncState, context: context)

        // Then
        let fetched = try await repository.fetch(accountId: accountId, context: context)
        XCTAssertEqual(fetched?.historyId, "12345")
        XCTAssertEqual(fetched?.emailCount, 100)
        XCTAssertEqual(fetched?.syncStatus, .completed)
        XCTAssertNotNil(fetched?.lastFullSyncDate)
    }

    // MARK: - UpdateHistoryId Tests

    func testUpdateHistoryIdUpdatesExistingSyncState() async throws {
        // Given
        let accountId = UUID()
        let syncState = SyncState(accountId: accountId)
        syncState.historyId = "old-history-id"
        context.insert(syncState)
        try context.save()

        // When
        try await repository.updateHistoryId("new-history-id", for: accountId, context: context)

        // Then
        let fetched = try await repository.fetch(accountId: accountId, context: context)
        XCTAssertEqual(fetched?.historyId, "new-history-id")
    }

    func testUpdateHistoryIdThrowsWhenSyncStateNotFound() async throws {
        // Given
        let nonExistentAccountId = UUID()

        // When/Then
        do {
            try await repository.updateHistoryId(
                "history-id",
                for: nonExistentAccountId,
                context: context
            )
            XCTFail("Expected error to be thrown")
        } catch let error as DatabaseError {
            switch error {
            case .notFound(let entityType, _):
                XCTAssertEqual(entityType, "SyncState")
            default:
                XCTFail("Expected notFound error, got \(error)")
            }
        }
    }

    func testUpdateHistoryIdPreservesOtherProperties() async throws {
        // Given
        let accountId = UUID()
        let syncState = SyncState(accountId: accountId)
        syncState.historyId = "old-history-id"
        syncState.emailCount = 500
        syncState.syncStatus = .syncing
        context.insert(syncState)
        try context.save()

        // When
        try await repository.updateHistoryId("new-history-id", for: accountId, context: context)

        // Then
        let fetched = try await repository.fetch(accountId: accountId, context: context)
        XCTAssertEqual(fetched?.historyId, "new-history-id")
        XCTAssertEqual(fetched?.emailCount, 500)
        XCTAssertEqual(fetched?.syncStatus, .syncing)
    }
}
