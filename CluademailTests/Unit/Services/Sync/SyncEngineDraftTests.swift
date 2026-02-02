import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class SyncEngineDraftTests: XCTestCase {

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

    // MARK: - Draft Sync Tests

    func testSyncDraftsFetchesNewDrafts() async throws {
        // Given
        let draftId = "draft-123"
        let messageId = "msg-123"
        let threadId = "thread-123"

        setupBasicSyncMocks()

        let draftSummary = TestFixtures.makeGmailDraftSummaryDTO(
            id: draftId,
            messageId: messageId,
            threadId: threadId
        )
        let fullDraft = TestFixtures.makeGmailDraftDTO(
            id: draftId,
            messageId: messageId,
            threadId: threadId
        )

        mockApiService.listDraftsResult = .success((drafts: [draftSummary], nextPageToken: nil))
        mockApiService.getDraftResults[draftId] = .success(fullDraft)

        // When
        _ = try await sut.sync()

        // Then
        XCTAssertEqual(mockApiService.listDraftsCallCount, 1)
        XCTAssertEqual(mockApiService.getDraftCallCount, 1)

        // Verify draft was saved with draftId
        let predicate = #Predicate<Email> { $0.draftId == draftId }
        var descriptor = FetchDescriptor<Email>(predicate: predicate)
        descriptor.fetchLimit = 1
        let savedDrafts = try context.fetch(descriptor)
        XCTAssertEqual(savedDrafts.count, 1)
        XCTAssertEqual(savedDrafts.first?.draftId, draftId)
        XCTAssertEqual(savedDrafts.first?.gmailId, messageId)
    }

    func testSyncDraftsUpdatesExistingDraft() async throws {
        // Given
        let draftId = "draft-123"
        let oldMessageId = "msg-old"
        let newMessageId = "msg-new"
        let threadId = "thread-123"

        // First sync to establish draft (using same context as sync engine)
        setupBasicSyncMocks()
        let initialDraftSummary = TestFixtures.makeGmailDraftSummaryDTO(
            id: draftId,
            messageId: oldMessageId,
            threadId: threadId
        )
        let initialFullDraft = TestFixtures.makeGmailDraftDTO(
            id: draftId,
            messageId: oldMessageId,
            threadId: threadId
        )
        mockApiService.listDraftsResult = .success((drafts: [initialDraftSummary], nextPageToken: nil))
        mockApiService.getDraftResults[draftId] = .success(initialFullDraft)

        _ = try await sut.sync()

        // Verify initial draft was created
        let initialPredicate = #Predicate<Email> { $0.draftId == draftId }
        var initialDescriptor = FetchDescriptor<Email>(predicate: initialPredicate)
        initialDescriptor.fetchLimit = 1
        let initialDrafts = try context.fetch(initialDescriptor)
        XCTAssertEqual(initialDrafts.count, 1)
        XCTAssertEqual(initialDrafts.first?.gmailId, oldMessageId)

        // Now simulate draft being edited in Gmail - new message ID but same draft ID
        // Reset mocks for second sync (getProfileResult is consumed by first sync)
        setupBasicSyncMocks()

        let updatedDraftSummary = TestFixtures.makeGmailDraftSummaryDTO(
            id: draftId,
            messageId: newMessageId,
            threadId: threadId
        )
        let updatedFullDraft = TestFixtures.makeGmailDraftDTO(
            id: draftId,
            messageId: newMessageId,
            threadId: threadId
        )

        mockApiService.listDraftsResult = .success((drafts: [updatedDraftSummary], nextPageToken: nil))
        mockApiService.getDraftResults[draftId] = .success(updatedFullDraft)

        // When - sync again
        _ = try await sut.sync()

        // Then - should have updated the existing draft, not created a new one
        let predicate = #Predicate<Email> { $0.draftId == draftId }
        let descriptor = FetchDescriptor<Email>(predicate: predicate)
        let drafts = try context.fetch(descriptor)
        XCTAssertEqual(drafts.count, 1, "Should have exactly one draft with this draftId")
        XCTAssertEqual(drafts.first?.gmailId, newMessageId, "gmailId should be updated to new message ID")
        XCTAssertEqual(drafts.first?.draftId, draftId, "draftId should remain the same")
    }

    func testSyncDraftsRemovesDeletedDrafts() async throws {
        // Given
        let draftId = "draft-to-delete"
        let messageId = "msg-123"
        let threadId = "thread-123"

        // Insert existing draft
        let existingDraft = TestFixtures.makeDraftEmail(
            gmailId: messageId,
            threadId: threadId,
            draftId: draftId
        )
        existingDraft.account = account
        context.insert(existingDraft)
        try context.save()

        setupBasicSyncMocks()

        // Gmail returns empty drafts list - draft was deleted or sent
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        _ = try await sut.sync()

        // Then - draft should be removed from local database
        let predicate = #Predicate<Email> { $0.draftId == draftId }
        let descriptor = FetchDescriptor<Email>(predicate: predicate)
        let drafts = try context.fetch(descriptor)
        XCTAssertEqual(drafts.count, 0, "Deleted draft should be removed from local database")
    }

    func testSyncDraftsHandlesPagination() async throws {
        // Given
        let draftId1 = "draft-1"
        let draftId2 = "draft-2"

        setupBasicSyncMocks()

        // First page
        let draftSummary1 = TestFixtures.makeGmailDraftSummaryDTO(id: draftId1)
        let fullDraft1 = TestFixtures.makeGmailDraftDTO(id: draftId1)

        // Second page
        let draftSummary2 = TestFixtures.makeGmailDraftSummaryDTO(id: draftId2)
        let fullDraft2 = TestFixtures.makeGmailDraftDTO(id: draftId2)

        // Configure mock to return paginated results
        // Note: Current mock doesn't support pagination tracking, so this tests basic flow
        mockApiService.listDraftsResult = .success((drafts: [draftSummary1, draftSummary2], nextPageToken: nil))
        mockApiService.getDraftResults[draftId1] = .success(fullDraft1)
        mockApiService.getDraftResults[draftId2] = .success(fullDraft2)

        // When
        _ = try await sut.sync()

        // Then - both drafts should be saved
        let descriptor = FetchDescriptor<Email>(predicate: #Predicate { $0.draftId != nil })
        let drafts = try context.fetch(descriptor)
        XCTAssertEqual(drafts.count, 2)

        let draftIds = Set(drafts.compactMap(\.draftId))
        XCTAssertTrue(draftIds.contains(draftId1))
        XCTAssertTrue(draftIds.contains(draftId2))
    }

    func testSyncDraftsPreservesNonDraftEmails() async throws {
        // Given
        let regularEmailId = "msg-regular"
        let threadId = "thread-123"

        // Insert a regular email (not a draft)
        let regularEmail = TestFixtures.makeEmail(
            gmailId: regularEmailId,
            threadId: threadId,
            draftId: nil,
            labelIds: ["INBOX"]
        )
        regularEmail.account = account
        context.insert(regularEmail)
        try context.save()

        setupBasicSyncMocks()
        mockApiService.listDraftsResult = .success((drafts: [], nextPageToken: nil))

        // When
        _ = try await sut.sync()

        // Then - regular email should not be affected
        let predicate = #Predicate<Email> { $0.gmailId == regularEmailId }
        var descriptor = FetchDescriptor<Email>(predicate: predicate)
        descriptor.fetchLimit = 1
        let emails = try context.fetch(descriptor)
        XCTAssertEqual(emails.count, 1, "Regular email should not be deleted by draft sync")
        XCTAssertNil(emails.first?.draftId, "Regular email should not have draftId")
    }
}
