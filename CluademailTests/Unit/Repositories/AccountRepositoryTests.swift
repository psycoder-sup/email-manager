import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class AccountRepositoryTests: XCTestCase {

    // MARK: - Properties

    var container: ModelContainer!
    var context: ModelContext!
    var repository: AccountRepository!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        let schema = Schema([
            Account.self,
            Email.self,
            EmailThread.self,
            Attachment.self,
            SyncState.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        repository = AccountRepository()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        repository = nil
    }

    // MARK: - FetchAll Tests

    func testFetchAllReturnsEmptyArrayWhenNoAccounts() async throws {
        let accounts = try await repository.fetchAll(context: context)
        XCTAssertEqual(accounts.count, 0)
    }

    func testFetchAllReturnsAccountsSortedByEmail() async throws {
        // Given
        let account1 = TestFixtures.makeAccount(email: "charlie@gmail.com")
        let account2 = TestFixtures.makeAccount(email: "alice@gmail.com")
        let account3 = TestFixtures.makeAccount(email: "bob@gmail.com")
        context.insert(account1)
        context.insert(account2)
        context.insert(account3)
        try context.save()

        // When
        let accounts = try await repository.fetchAll(context: context)

        // Then
        XCTAssertEqual(accounts.count, 3)
        XCTAssertEqual(accounts[0].email, "alice@gmail.com")
        XCTAssertEqual(accounts[1].email, "bob@gmail.com")
        XCTAssertEqual(accounts[2].email, "charlie@gmail.com")
    }

    // MARK: - Fetch by ID Tests

    func testFetchByIdReturnsAccountWhenExists() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)
        try context.save()

        // When
        let fetched = try await repository.fetch(byId: account.id, context: context)

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.email, account.email)
    }

    func testFetchByIdReturnsNilWhenNotExists() async throws {
        let fetched = try await repository.fetch(byId: UUID(), context: context)
        XCTAssertNil(fetched)
    }

    // MARK: - Fetch by Email Tests

    func testFetchByEmailReturnsAccountWhenExists() async throws {
        // Given
        let account = TestFixtures.makeAccount(email: "unique@gmail.com")
        context.insert(account)
        try context.save()

        // When
        let fetched = try await repository.fetch(byEmail: "unique@gmail.com", context: context)

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, account.id)
    }

    func testFetchByEmailReturnsNilWhenNotExists() async throws {
        let fetched = try await repository.fetch(byEmail: "nonexistent@gmail.com", context: context)
        XCTAssertNil(fetched)
    }

    // MARK: - Save Tests

    func testSaveInsertsNewAccount() async throws {
        // Given
        let account = TestFixtures.makeAccount()

        // When
        try await repository.save(account, context: context)

        // Then
        let fetched = try await repository.fetch(byId: account.id, context: context)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.email, account.email)
    }

    // MARK: - Delete Tests

    func testDeleteRemovesAccount() async throws {
        // Given
        let account = TestFixtures.makeAccount()
        context.insert(account)
        try context.save()

        // When
        try await repository.delete(account, context: context)

        // Then
        let fetched = try await repository.fetch(byId: account.id, context: context)
        XCTAssertNil(fetched)
    }
}
