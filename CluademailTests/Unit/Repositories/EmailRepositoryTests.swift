import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class EmailRepositoryTests: XCTestCase {

    // MARK: - Properties

    var container: ModelContainer!
    var context: ModelContext!
    var repository: EmailRepository!

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
        repository = EmailRepository()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        repository = nil
    }

    // MARK: - Fetch by Gmail ID Tests

    func testFetchByGmailIdReturnsEmailWhenExists() async throws {
        // Given
        let email = TestFixtures.makeEmail(gmailId: "test-gmail-id")
        context.insert(email)
        try context.save()

        // When
        let fetched = try await repository.fetch(byGmailId: "test-gmail-id", context: context)

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.gmailId, "test-gmail-id")
    }

    func testFetchByGmailIdReturnsNilWhenNotExists() async throws {
        let fetched = try await repository.fetch(byGmailId: "nonexistent", context: context)
        XCTAssertNil(fetched)
    }

    // MARK: - Fetch with Filters Tests

    func testFetchReturnsAllEmailsWhenNoFilters() async throws {
        // Given
        let emails = TestFixtures.makeEmails(count: 5)
        for email in emails {
            context.insert(email)
        }
        try context.save()

        // When
        let fetched = try await repository.fetch(
            account: nil,
            folder: nil,
            isRead: nil,
            limit: nil,
            offset: nil,
            context: context
        )

        // Then
        XCTAssertEqual(fetched.count, 5)
    }

    func testFetchFiltersByAccount() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)

        let email1 = TestFixtures.makeEmail(gmailId: "1")
        email1.account = account
        let email2 = TestFixtures.makeEmail(gmailId: "2")
        email2.account = account
        let email3 = TestFixtures.makeEmail(gmailId: "3")  // No account

        context.insert(email1)
        context.insert(email2)
        context.insert(email3)
        try context.save()

        // When
        let fetched = try await repository.fetch(
            account: account,
            folder: nil,
            isRead: nil,
            limit: nil,
            offset: nil,
            context: context
        )

        // Then
        XCTAssertEqual(fetched.count, 2)
    }

    func testFetchFiltersByFolder() async throws {
        // Given
        let email1 = TestFixtures.makeEmail(gmailId: "1", labelIds: ["INBOX"])
        let email2 = TestFixtures.makeEmail(gmailId: "2", labelIds: ["INBOX"])
        let email3 = TestFixtures.makeEmail(gmailId: "3", labelIds: ["SENT"])

        context.insert(email1)
        context.insert(email2)
        context.insert(email3)
        try context.save()

        // When
        let fetched = try await repository.fetch(
            account: nil,
            folder: "INBOX",
            isRead: nil,
            limit: nil,
            offset: nil,
            context: context
        )

        // Then
        XCTAssertEqual(fetched.count, 2)
    }

    func testFetchFiltersByReadStatus() async throws {
        // Given
        let email1 = TestFixtures.makeEmail(gmailId: "1", isRead: true)
        let email2 = TestFixtures.makeEmail(gmailId: "2", isRead: false)
        let email3 = TestFixtures.makeEmail(gmailId: "3", isRead: false)

        context.insert(email1)
        context.insert(email2)
        context.insert(email3)
        try context.save()

        // When
        let fetched = try await repository.fetch(
            account: nil,
            folder: nil,
            isRead: false,
            limit: nil,
            offset: nil,
            context: context
        )

        // Then
        XCTAssertEqual(fetched.count, 2)
    }

    func testFetchRespectsLimit() async throws {
        // Given
        for i in 0..<10 {
            let email = TestFixtures.makeEmail(gmailId: "email-\(i)")
            context.insert(email)
        }
        try context.save()

        // When
        let fetched = try await repository.fetch(
            account: nil,
            folder: nil,
            isRead: nil,
            limit: 5,
            offset: nil,
            context: context
        )

        // Then
        XCTAssertEqual(fetched.count, 5)
    }

    func testFetchSortsByDateDescending() async throws {
        // Given
        let oldDate = TestFixtures.dateAgo(days: 2)
        let newDate = Date()

        let email1 = TestFixtures.makeEmail(gmailId: "old", date: oldDate)
        let email2 = TestFixtures.makeEmail(gmailId: "new", date: newDate)

        context.insert(email1)
        context.insert(email2)
        try context.save()

        // When
        let fetched = try await repository.fetch(
            account: nil,
            folder: nil,
            isRead: nil,
            limit: nil,
            offset: nil,
            context: context
        )

        // Then
        XCTAssertEqual(fetched[0].gmailId, "new")
        XCTAssertEqual(fetched[1].gmailId, "old")
    }

    // MARK: - Search Tests

    func testSearchFindsEmailsBySubject() async throws {
        // Given
        let email1 = TestFixtures.makeEmail(gmailId: "1", subject: "Meeting tomorrow")
        let email2 = TestFixtures.makeEmail(gmailId: "2", subject: "Unrelated email")

        context.insert(email1)
        context.insert(email2)
        try context.save()

        // When
        let results = try await repository.search(query: "Meeting", account: nil, context: context)

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].subject, "Meeting tomorrow")
    }

    func testSearchFindsEmailsByFromAddress() async throws {
        // Given
        let email1 = TestFixtures.makeEmail(gmailId: "1", fromAddress: "john@example.com")
        let email2 = TestFixtures.makeEmail(gmailId: "2", fromAddress: "jane@example.com")

        context.insert(email1)
        context.insert(email2)
        try context.save()

        // When
        let results = try await repository.search(query: "john", account: nil, context: context)

        // Then
        XCTAssertEqual(results.count, 1)
    }

    func testSearchFindsEmailsBySnippet() async throws {
        // Given
        let email1 = TestFixtures.makeEmail(gmailId: "1", snippet: "Please review the attached document")
        let email2 = TestFixtures.makeEmail(gmailId: "2", snippet: "Hello world")

        context.insert(email1)
        context.insert(email2)
        try context.save()

        // When
        let results = try await repository.search(query: "document", account: nil, context: context)

        // Then
        XCTAssertEqual(results.count, 1)
    }

    func testSearchIsCaseInsensitive() async throws {
        // Given
        let email = TestFixtures.makeEmail(subject: "IMPORTANT Meeting")
        context.insert(email)
        try context.save()

        // When
        let results = try await repository.search(query: "important", account: nil, context: context)

        // Then
        XCTAssertEqual(results.count, 1)
    }

    func testSearchLimitsTo100Results() async throws {
        // Given
        for i in 0..<150 {
            let email = TestFixtures.makeEmail(gmailId: "email-\(i)", subject: "Searchable topic")
            context.insert(email)
        }
        try context.save()

        // When
        let results = try await repository.search(query: "Searchable", account: nil, context: context)

        // Then
        XCTAssertEqual(results.count, 100)
    }

    // MARK: - Save Tests

    func testSaveAllInsertsBatchEmails() async throws {
        // Given
        let emails = TestFixtures.makeEmails(count: 10)

        // When
        try await repository.saveAll(emails, context: context)

        // Then
        let fetched = try await repository.fetch(
            account: nil,
            folder: nil,
            isRead: nil,
            limit: nil,
            offset: nil,
            context: context
        )
        XCTAssertEqual(fetched.count, 10)
    }

    // MARK: - Delete Oldest Tests

    func testDeleteOldestRemovesExcessEmails() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)

        // Create emails with different dates
        for i in 0..<15 {
            let email = TestFixtures.makeEmail(
                gmailId: "email-\(i)",
                date: TestFixtures.dateAgo(days: i)
            )
            email.account = account
            context.insert(email)
        }
        try context.save()

        // When
        try await repository.deleteOldest(account: account, keepCount: 10, context: context)

        // Then
        let remaining = try await repository.fetch(
            account: account,
            folder: nil,
            isRead: nil,
            limit: nil,
            offset: nil,
            context: context
        )
        XCTAssertEqual(remaining.count, 10)
    }

    func testDeleteOldestKeepsNewestEmails() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)

        // Newest email
        let newestEmail = TestFixtures.makeEmail(gmailId: "newest", date: Date())
        newestEmail.account = account
        context.insert(newestEmail)

        // Older emails
        for i in 1..<10 {
            let email = TestFixtures.makeEmail(
                gmailId: "email-\(i)",
                date: TestFixtures.dateAgo(days: i)
            )
            email.account = account
            context.insert(email)
        }
        try context.save()

        // When
        try await repository.deleteOldest(account: account, keepCount: 5, context: context)

        // Then
        let newest = try await repository.fetch(byGmailId: "newest", context: context)
        XCTAssertNotNil(newest)
    }

    func testDeleteOldestDoesNothingWhenUnderLimit() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)

        for i in 0..<5 {
            let email = TestFixtures.makeEmail(gmailId: "email-\(i)")
            email.account = account
            context.insert(email)
        }
        try context.save()

        // When
        try await repository.deleteOldest(account: account, keepCount: 10, context: context)

        // Then
        let remaining = try await repository.fetch(
            account: account,
            folder: nil,
            isRead: nil,
            limit: nil,
            offset: nil,
            context: context
        )
        XCTAssertEqual(remaining.count, 5)
    }

    // MARK: - Count Tests

    func testCountReturnsCorrectCount() async throws {
        // Given
        for i in 0..<5 {
            context.insert(TestFixtures.makeEmail(gmailId: "email-\(i)"))
        }
        try context.save()

        // When
        let count = try await repository.count(account: nil, folder: nil, context: context)

        // Then
        XCTAssertEqual(count, 5)
    }

    func testUnreadCountReturnsOnlyUnreadEmails() async throws {
        // Given
        let read1 = TestFixtures.makeEmail(gmailId: "1", isRead: true)
        let read2 = TestFixtures.makeEmail(gmailId: "2", isRead: true)
        let unread1 = TestFixtures.makeEmail(gmailId: "3", isRead: false)
        let unread2 = TestFixtures.makeEmail(gmailId: "4", isRead: false)
        let unread3 = TestFixtures.makeEmail(gmailId: "5", isRead: false)

        context.insert(read1)
        context.insert(read2)
        context.insert(unread1)
        context.insert(unread2)
        context.insert(unread3)
        try context.save()

        // When
        let count = try await repository.unreadCount(account: nil, folder: nil, context: context)

        // Then
        XCTAssertEqual(count, 3)
    }

    func testUnreadCountFiltersByAccountAndFolder() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)

        let email1 = TestFixtures.makeEmail(gmailId: "1", isRead: false, labelIds: ["INBOX"])
        email1.account = account
        let email2 = TestFixtures.makeEmail(gmailId: "2", isRead: false, labelIds: ["INBOX"])
        email2.account = account
        let email3 = TestFixtures.makeEmail(gmailId: "3", isRead: false, labelIds: ["SENT"])
        email3.account = account

        context.insert(email1)
        context.insert(email2)
        context.insert(email3)
        try context.save()

        // When
        let count = try await repository.unreadCount(account: account, folder: "INBOX", context: context)

        // Then
        XCTAssertEqual(count, 2)
    }
}
