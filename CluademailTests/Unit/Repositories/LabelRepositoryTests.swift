import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class LabelRepositoryTests: XCTestCase {

    // MARK: - Properties

    var container: ModelContainer!
    var context: ModelContext!
    var repository: LabelRepository!

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
        repository = LabelRepository()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        repository = nil
    }

    // MARK: - FetchAll Tests

    func testFetchAllReturnsLabelsForAccount() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)

        let label1 = TestFixtures.makeLabel(gmailLabelId: "INBOX", name: "Inbox")
        label1.account = account
        let label2 = TestFixtures.makeLabel(gmailLabelId: "SENT", name: "Sent")
        label2.account = account

        context.insert(label1)
        context.insert(label2)
        try context.save()

        // When
        let labels = try await repository.fetchAll(account: account, context: context)

        // Then
        XCTAssertEqual(labels.count, 2)
    }

    func testFetchAllReturnsOnlyLabelsForSpecificAccount() async throws {
        // Given
        let account1 = TestFixtures.makeAccount(email: "user1@gmail.com")
        let account2 = TestFixtures.makeAccount(email: "user2@gmail.com")
        context.insert(account1)
        context.insert(account2)

        let label1 = TestFixtures.makeLabel(gmailLabelId: "INBOX-1", name: "Inbox")
        label1.account = account1
        let label2 = TestFixtures.makeLabel(gmailLabelId: "INBOX-2", name: "Inbox")
        label2.account = account2

        context.insert(label1)
        context.insert(label2)
        try context.save()

        // When
        let labels = try await repository.fetchAll(account: account1, context: context)

        // Then
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels[0].gmailLabelId, "INBOX-1")
    }

    func testFetchAllSortsByName() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)

        let labelZ = TestFixtures.makeLabel(gmailLabelId: "Z", name: "Zebra")
        labelZ.account = account
        let labelA = TestFixtures.makeLabel(gmailLabelId: "A", name: "Alpha")
        labelA.account = account

        context.insert(labelZ)
        context.insert(labelA)
        try context.save()

        // When
        let labels = try await repository.fetchAll(account: account, context: context)

        // Then
        XCTAssertEqual(labels[0].name, "Alpha")
        XCTAssertEqual(labels[1].name, "Zebra")
    }

    // MARK: - Fetch by Gmail ID Tests

    func testFetchByGmailIdReturnsLabelWhenExists() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)

        let label = TestFixtures.makeLabel(gmailLabelId: "STARRED", name: "Starred")
        label.account = account
        context.insert(label)
        try context.save()

        // When
        let fetched = try await repository.fetch(
            byGmailId: "STARRED",
            account: account,
            context: context
        )

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Starred")
    }

    func testFetchByGmailIdReturnsNilWhenNotExists() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)
        try context.save()

        // When
        let fetched = try await repository.fetch(
            byGmailId: "NONEXISTENT",
            account: account,
            context: context
        )

        // Then
        XCTAssertNil(fetched)
    }

    func testFetchByGmailIdRequiresMatchingAccount() async throws {
        // Given
        let account1 = TestFixtures.makeAccount(email: "user1@gmail.com")
        let account2 = TestFixtures.makeAccount(email: "user2@gmail.com")
        context.insert(account1)
        context.insert(account2)

        let label = TestFixtures.makeLabel(gmailLabelId: "INBOX", name: "Inbox")
        label.account = account1
        context.insert(label)
        try context.save()

        // When - searching with different account
        let fetched = try await repository.fetch(
            byGmailId: "INBOX",
            account: account2,
            context: context
        )

        // Then
        XCTAssertNil(fetched)
    }

    // MARK: - Save Tests

    func testSaveInsertsNewLabel() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)
        try context.save()

        let label = TestFixtures.makeLabel(gmailLabelId: "CUSTOM", name: "Custom Label")
        label.account = account

        // When
        try await repository.save(label, context: context)

        // Then
        let fetched = try await repository.fetch(
            byGmailId: "CUSTOM",
            account: account,
            context: context
        )
        XCTAssertNotNil(fetched)
    }

    func testSaveAllInsertsBatchLabels() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)
        try context.save()

        let labels = [
            TestFixtures.makeLabel(gmailLabelId: "L1", name: "Label 1"),
            TestFixtures.makeLabel(gmailLabelId: "L2", name: "Label 2"),
            TestFixtures.makeLabel(gmailLabelId: "L3", name: "Label 3")
        ]
        for label in labels {
            label.account = account
        }

        // When
        try await repository.saveAll(labels, context: context)

        // Then
        let fetched = try await repository.fetchAll(account: account, context: context)
        XCTAssertEqual(fetched.count, 3)
    }
}
