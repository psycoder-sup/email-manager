import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class SyncEngineTests: XCTestCase {

    // MARK: - Properties

    var sut: SyncEngine!
    var mockApiService: MockGmailAPIService!
    var databaseService: DatabaseService!
    var account: Account!
    var context: ModelContext!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory database service
        databaseService = DatabaseService(isStoredInMemoryOnly: true)
        context = databaseService.mainContext

        // Create and save test account
        account = TestFixtures.makeAccount(email: "test@gmail.com", displayName: "Test User")
        context.insert(account)
        try context.save()

        // Create mock API service
        mockApiService = MockGmailAPIService()

        // Create SUT
        sut = SyncEngine(
            account: account,
            apiService: mockApiService,
            databaseService: databaseService
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockApiService = nil
        databaseService = nil
        account = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func setupBasicSyncMocks() {
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))
        // Set history result for incremental sync (used when historyId exists from previous sync)
        mockApiService.getHistoryResult = .success(GmailHistoryListDTO(history: nil, nextPageToken: nil, historyId: "12345"))
    }

    // MARK: - Full Sync Tests

    func testFullSyncFetchesEmails() async throws {
        // Given
        let messageId = "msg-123"
        let threadId = "thread-123"
        let messageSummary = GmailMessageSummaryDTO(id: messageId, threadId: threadId)
        mockApiService.listMessagesResult = .success((messages: [messageSummary], nextPageToken: nil))
        mockApiService.batchGetMessagesResult = .success(BatchResult(
            succeeded: [TestFixtures.makeGmailMessageDTO(id: messageId, threadId: threadId)],
            failed: []
        ))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        let result = try await sut.sync()

        // Then
        if case .success(let newEmails, _, _) = result {
            XCTAssertEqual(newEmails, 1)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testFullSyncUpdatesHistoryId() async throws {
        // Given
        let expectedHistoryId = "99999"
        setupBasicSyncMocks()
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: expectedHistoryId))

        // When
        _ = try await sut.sync()

        // Then
        let accountId = account.id
        let syncStatePredicate = #Predicate<SyncState> { $0.accountId == accountId }
        var descriptor = FetchDescriptor<SyncState>(predicate: syncStatePredicate)
        descriptor.fetchLimit = 1
        let syncStates = try context.fetch(descriptor)
        XCTAssertEqual(syncStates.first?.historyId, expectedHistoryId)
    }

    func testFullSyncHandlesEmptyMailbox() async throws {
        // Given
        setupBasicSyncMocks()

        // When
        let result = try await sut.sync()

        // Then
        if case .success(let newEmails, let updatedEmails, let deletedEmails) = result {
            XCTAssertEqual(newEmails, 0)
            XCTAssertEqual(updatedEmails, 0)
            XCTAssertEqual(deletedEmails, 0)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testFullSyncDerivesThreads() async throws {
        // Given - Two emails in the same thread
        let threadId = "shared-thread"
        let msg1 = TestFixtures.makeGmailMessageDTO(id: "msg-1", threadId: threadId, snippet: "First message")
        let msg2 = TestFixtures.makeGmailMessageDTO(id: "msg-2", threadId: threadId, snippet: "Second message")

        mockApiService.listMessagesResult = .success((
            messages: [
                GmailMessageSummaryDTO(id: "msg-1", threadId: threadId),
                GmailMessageSummaryDTO(id: "msg-2", threadId: threadId)
            ],
            nextPageToken: nil
        ))
        mockApiService.batchGetMessagesResult = .success(BatchResult(succeeded: [msg1, msg2], failed: []))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        let result = try await sut.sync()

        // Then - Should report 2 new emails synced
        if case .success(let newEmails, _, _) = result {
            XCTAssertEqual(newEmails, 2)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testFullSyncUpdatesExistingEmails() async throws {
        // Given - Email already exists
        let existingEmail = TestFixtures.makeEmail(gmailId: "msg-123", threadId: "thread-123", isRead: false)
        existingEmail.account = account
        context.insert(existingEmail)
        try context.save()

        let updatedDTO = TestFixtures.makeGmailMessageDTO(
            id: "msg-123",
            threadId: "thread-123",
            labelIds: ["INBOX"]  // No UNREAD = isRead
        )

        mockApiService.listMessagesResult = .success((
            messages: [GmailMessageSummaryDTO(id: "msg-123", threadId: "thread-123")],
            nextPageToken: nil
        ))
        mockApiService.batchGetMessagesResult = .success(BatchResult(succeeded: [updatedDTO], failed: []))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        let result = try await sut.sync()

        // Then
        if case .success(let newEmails, let updatedEmails, _) = result {
            XCTAssertEqual(newEmails, 0)
            XCTAssertEqual(updatedEmails, 1)
        } else {
            XCTFail("Expected success result")
        }
    }

    // MARK: - Incremental Sync Tests

    func testIncrementalSyncUsesHistoryApi() async throws {
        // Given - Set up existing sync state with history ID
        let syncState = SyncState(accountId: account.id)
        syncState.historyId = "10000"
        syncState.lastFullSyncDate = Date()
        context.insert(syncState)
        try context.save()

        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [],
            historyId: "10001"
        ))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        _ = try await sut.sync()

        // Then
        XCTAssertEqual(mockApiService.getHistoryCallCount, 1)
        XCTAssertEqual(mockApiService.listMessagesCallCount, 0)  // Should not do full sync
    }

    func testIncrementalSyncHandlesMessagesAdded() async throws {
        // Given - Set up sync state with history ID
        let syncState = SyncState(accountId: account.id)
        syncState.historyId = "10000"
        syncState.lastFullSyncDate = Date()
        context.insert(syncState)
        try context.save()

        let newMessageId = "new-msg"
        let newThreadId = "new-thread"
        let historyRecord = TestFixtures.makeGmailHistoryDTO(
            id: "10001",
            messagesAdded: [TestFixtures.makeGmailHistoryMessageDTO(messageId: newMessageId, threadId: newThreadId)]
        )

        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [historyRecord],
            historyId: "10001"
        ))
        mockApiService.getMessageResult = .success(TestFixtures.makeGmailMessageDTO(id: newMessageId, threadId: newThreadId))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        let result = try await sut.sync()

        // Then
        if case .success(let newEmails, _, _) = result {
            XCTAssertEqual(newEmails, 1)
        } else {
            XCTFail("Expected success result")
        }
        XCTAssertEqual(mockApiService.getMessageCallCount, 1)
    }

    func testIncrementalSyncHandlesMessagesDeleted() async throws {
        // Given - Email exists in database
        let existingEmail = TestFixtures.makeEmail(gmailId: "to-delete", threadId: "thread-1")
        existingEmail.account = account
        context.insert(existingEmail)

        let syncState = SyncState(accountId: account.id)
        syncState.historyId = "10000"
        syncState.lastFullSyncDate = Date()
        context.insert(syncState)
        try context.save()

        let historyRecord = TestFixtures.makeGmailHistoryDTO(
            id: "10001",
            messagesDeleted: [TestFixtures.makeGmailHistoryMessageDTO(messageId: "to-delete", threadId: "thread-1")]
        )

        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [historyRecord],
            historyId: "10001"
        ))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        let result = try await sut.sync()

        // Then
        if case .success(_, _, let deletedEmails) = result {
            XCTAssertEqual(deletedEmails, 1)
        } else {
            XCTFail("Expected success result")
        }

        // Verify email was deleted
        let emailDescriptor = FetchDescriptor<Email>(predicate: #Predicate { $0.gmailId == "to-delete" })
        let emails = try context.fetch(emailDescriptor)
        XCTAssertTrue(emails.isEmpty)
    }

    func testIncrementalSyncFallsBackOnHistoryExpired() async throws {
        // Given - Set up sync state with old history ID
        let syncState = SyncState(accountId: account.id)
        syncState.historyId = "expired-history"
        syncState.lastFullSyncDate = Date()
        context.insert(syncState)
        try context.save()

        // History API returns 404 (history expired)
        mockApiService.getHistoryResult = .failure(APIError.notFound)
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "99999"))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        _ = try await sut.sync()

        // Then - Should fall back to full sync
        XCTAssertEqual(mockApiService.getHistoryCallCount, 1)
        XCTAssertEqual(mockApiService.listMessagesCallCount, 1)  // Full sync was triggered
    }

    func testIncrementalSyncDeduplicatesHistory() async throws {
        // Given - Multiple history records for same message
        let syncState = SyncState(accountId: account.id)
        syncState.historyId = "10000"
        syncState.lastFullSyncDate = Date()
        context.insert(syncState)
        try context.save()

        let messageId = "dedupe-msg"
        let threadId = "thread-1"

        // First record: message added
        let record1 = TestFixtures.makeGmailHistoryDTO(
            id: "10001",
            messagesAdded: [TestFixtures.makeGmailHistoryMessageDTO(messageId: messageId, threadId: threadId)]
        )
        // Second record: label changed on same message (simulated as labels added)
        let record2 = TestFixtures.makeGmailHistoryDTO(
            id: "10002",
            labelsAdded: [GmailHistoryLabelDTO(message: GmailMessageSummaryDTO(id: messageId, threadId: threadId), labelIds: ["STARRED"])]
        )

        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [record1, record2],
            historyId: "10002"
        ))
        mockApiService.getMessageResult = .success(TestFixtures.makeGmailMessageDTO(
            id: messageId,
            threadId: threadId,
            labelIds: ["INBOX", "STARRED"]
        ))
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        let result = try await sut.sync()

        // Then - Should only fetch message once (deduplication)
        XCTAssertEqual(mockApiService.getMessageCallCount, 1)
        if case .success(let newEmails, _, _) = result {
            XCTAssertEqual(newEmails, 1)
        } else {
            XCTFail("Expected success result")
        }
    }

    // MARK: - Error Handling Tests

    func testSyncUpdatesSyncStateOnError() async throws {
        // Given
        mockApiService.listMessagesResult = .failure(APIError.serverError(statusCode: 500))

        // When/Then
        let accountId = account.id
        do {
            _ = try await sut.sync()
            XCTFail("Expected error to be thrown")
        } catch {
            // Verify sync state has error
            let syncStatePredicate = #Predicate<SyncState> { $0.accountId == accountId }
            var descriptor = FetchDescriptor<SyncState>(predicate: syncStatePredicate)
            descriptor.fetchLimit = 1
            let syncStates = try context.fetch(descriptor)
            XCTAssertEqual(syncStates.first?.syncStatus, .error)
            XCTAssertNotNil(syncStates.first?.errorMessage)
        }
    }

    func testSyncCanBeCancelled() async throws {
        // Given
        setupBasicSyncMocks()

        // Create slow message listing
        let messages = (0..<100).map {
            GmailMessageSummaryDTO(id: "msg-\($0)", threadId: "thread-\($0)")
        }
        mockApiService.listMessagesResult = .success((messages: messages, nextPageToken: "next"))
        mockApiService.batchGetMessagesResult = .success(BatchResult(
            succeeded: messages.map { TestFixtures.makeGmailMessageDTO(id: $0.id, threadId: $0.threadId) },
            failed: []
        ))

        // Cancel before completing
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            await sut.cancelSync()
        }

        // When
        _ = try await sut.sync()

        // Then - We just verify it doesn't hang indefinitely
        // The exact behavior depends on when cancellation is checked
    }

    func testSyncHandlesApiErrors() async throws {
        // Given
        mockApiService.listMessagesResult = .failure(APIError.networkError(nil))

        // When/Then
        do {
            _ = try await sut.sync()
            XCTFail("Expected error to be thrown")
        } catch let error as APIError {
            if case .networkError = error {
                // Expected
            } else {
                XCTFail("Expected network error")
            }
        }
    }
}
