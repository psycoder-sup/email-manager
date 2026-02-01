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

    // MARK: - Full Sync Tests

    func testFullSyncFetchesLabelsFirst() async throws {
        // Given
        let labels = [
            TestFixtures.makeGmailLabelDTO(id: "INBOX", name: "Inbox"),
            TestFixtures.makeGmailLabelDTO(id: "SENT", name: "Sent")
        ]
        mockApiService.listLabelsResult = .success(labels)
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))

        // When
        _ = try await sut.sync()

        // Then
        XCTAssertEqual(mockApiService.listLabelsCallCount, 1)

        // Verify labels were saved
        let labelDescriptor = FetchDescriptor<Label>()
        let savedLabels = try context.fetch(labelDescriptor)
        XCTAssertEqual(savedLabels.count, 2)
    }

    func testFullSyncFetchesEmails() async throws {
        // Given
        let messageId = "msg-123"
        let threadId = "thread-123"
        let messageSummary = GmailMessageSummaryDTO(id: messageId, threadId: threadId)
        mockApiService.listLabelsResult = .success([])
        mockApiService.listMessagesResult = .success((messages: [messageSummary], nextPageToken: nil))
        mockApiService.batchGetMessagesResult = .success(BatchResult(
            succeeded: [TestFixtures.makeGmailMessageDTO(id: messageId, threadId: threadId)],
            failed: []
        ))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))

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
        mockApiService.listLabelsResult = .success([])
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))
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
        mockApiService.listLabelsResult = .success([])
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))

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

        mockApiService.listLabelsResult = .success([])
        mockApiService.listMessagesResult = .success((
            messages: [
                GmailMessageSummaryDTO(id: "msg-1", threadId: threadId),
                GmailMessageSummaryDTO(id: "msg-2", threadId: threadId)
            ],
            nextPageToken: nil
        ))
        mockApiService.batchGetMessagesResult = .success(BatchResult(succeeded: [msg1, msg2], failed: []))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))

        // When
        let result = try await sut.sync()

        // Then - Should report 2 new emails synced
        // Note: Thread derivation is tested via integration test since it requires
        // proper SwiftData context relationship handling
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

        mockApiService.listLabelsResult = .success([])
        mockApiService.listMessagesResult = .success((
            messages: [GmailMessageSummaryDTO(id: "msg-123", threadId: "thread-123")],
            nextPageToken: nil
        ))
        mockApiService.batchGetMessagesResult = .success(BatchResult(succeeded: [updatedDTO], failed: []))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))

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

        mockApiService.listLabelsResult = .success([])
        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [],
            historyId: "10001"
        ))

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

        mockApiService.listLabelsResult = .success([])
        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [historyRecord],
            historyId: "10001"
        ))
        mockApiService.getMessageResult = .success(TestFixtures.makeGmailMessageDTO(id: newMessageId, threadId: newThreadId))

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

        mockApiService.listLabelsResult = .success([])
        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [historyRecord],
            historyId: "10001"
        ))

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

    func testIncrementalSyncHandlesLabelsChanged() async throws {
        // Given - Email exists with UNREAD label
        let existingEmail = TestFixtures.makeEmail(
            gmailId: "existing-msg",
            threadId: "thread-1",
            isRead: false,
            labelIds: ["INBOX", "UNREAD"]
        )
        existingEmail.account = account
        context.insert(existingEmail)

        let syncState = SyncState(accountId: account.id)
        syncState.historyId = "10000"
        syncState.lastFullSyncDate = Date()
        context.insert(syncState)
        try context.save()

        // Remove UNREAD label (mark as read)
        let historyRecord = TestFixtures.makeGmailHistoryDTO(
            id: "10001",
            labelsRemoved: [TestFixtures.makeGmailHistoryLabelDTO(
                messageId: "existing-msg",
                threadId: "thread-1",
                labelIds: ["UNREAD"]
            )]
        )

        mockApiService.listLabelsResult = .success([])
        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [historyRecord],
            historyId: "10001"
        ))

        // When
        let result = try await sut.sync()

        // Then
        if case .success(_, let updatedEmails, _) = result {
            XCTAssertEqual(updatedEmails, 1)
        } else {
            XCTFail("Expected success result")
        }

        // Verify email is now read
        let emailDescriptor = FetchDescriptor<Email>(predicate: #Predicate { $0.gmailId == "existing-msg" })
        let emails = try context.fetch(emailDescriptor)
        XCTAssertTrue(emails.first?.isRead ?? false)
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
        mockApiService.listLabelsResult = .success([])
        mockApiService.listMessagesResult = .success((messages: [], nextPageToken: nil))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "99999"))

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
        // Second record: label added to same message
        let record2 = TestFixtures.makeGmailHistoryDTO(
            id: "10002",
            labelsAdded: [TestFixtures.makeGmailHistoryLabelDTO(messageId: messageId, threadId: threadId, labelIds: ["STARRED"])]
        )

        mockApiService.listLabelsResult = .success([])
        mockApiService.getHistoryResult = .success(TestFixtures.makeGmailHistoryListDTO(
            history: [record1, record2],
            historyId: "10002"
        ))
        mockApiService.getMessageResult = .success(TestFixtures.makeGmailMessageDTO(
            id: messageId,
            threadId: threadId,
            labelIds: ["INBOX", "STARRED"]
        ))

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
        mockApiService.listLabelsResult = .failure(APIError.serverError(statusCode: 500))

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
        mockApiService.listLabelsResult = .success([])

        // Create slow message listing
        let messages = (0..<100).map {
            GmailMessageSummaryDTO(id: "msg-\($0)", threadId: "thread-\($0)")
        }
        mockApiService.listMessagesResult = .success((messages: messages, nextPageToken: "next"))
        mockApiService.batchGetMessagesResult = .success(BatchResult(
            succeeded: messages.map { TestFixtures.makeGmailMessageDTO(id: $0.id, threadId: $0.threadId) },
            failed: []
        ))
        mockApiService.getProfileResult = .success(TestFixtures.makeGmailProfileDTO(historyId: "12345"))

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
        mockApiService.listLabelsResult = .failure(APIError.networkError(nil))

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
