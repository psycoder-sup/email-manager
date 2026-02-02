import XCTest
import SwiftData
@testable import Cluademail

@MainActor
final class DatabaseServiceTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializesWithInMemoryContainer() async throws {
        // When
        let service = DatabaseService(isStoredInMemoryOnly: true)

        // Then
        XCTAssertNotNil(service.container)
        XCTAssertNotNil(service.mainContext)
    }

    func testMainContextIsFromContainer() async throws {
        // Given
        let service = DatabaseService(isStoredInMemoryOnly: true)

        // Then
        XCTAssertTrue(service.mainContext === service.container.mainContext)
    }

    // MARK: - Background Context Tests

    func testNewBackgroundContextCreatesNewContext() async throws {
        // Given
        let service = DatabaseService(isStoredInMemoryOnly: true)

        // When
        let context1 = service.newBackgroundContext()
        let context2 = service.newBackgroundContext()

        // Then
        XCTAssertFalse(context1 === context2)
    }

    func testNewBackgroundContextHasAutosaveDisabled() async throws {
        // Given
        let service = DatabaseService(isStoredInMemoryOnly: true)

        // When
        let context = service.newBackgroundContext()

        // Then
        XCTAssertFalse(context.autosaveEnabled)
    }

    // MARK: - Schema Tests

    func testContainerIncludesAllModels() async throws {
        // Given
        let service = DatabaseService(isStoredInMemoryOnly: true)

        // When - Create and save instances of all models
        let account = TestFixtures.makeAccount()
        service.mainContext.insert(account)

        let email = TestFixtures.makeEmail()
        email.account = account
        service.mainContext.insert(email)

        let thread = TestFixtures.makeEmailThread()
        thread.account = account
        service.mainContext.insert(thread)

        let attachment = TestFixtures.makeAttachment()
        attachment.email = email
        service.mainContext.insert(attachment)

        let syncState = TestFixtures.makeSyncState(accountId: account.id)
        service.mainContext.insert(syncState)

        // Then - All inserts should succeed
        XCTAssertNoThrow(try service.mainContext.save())
    }

    // MARK: - Integration Tests

    func testBackgroundContextChangesVisibleInMainContext() async throws {
        // Given
        let service = DatabaseService(isStoredInMemoryOnly: true)
        let bgContext = service.newBackgroundContext()

        // When - Insert in background context
        let account = TestFixtures.makeAccount(email: "background@test.com")
        bgContext.insert(account)
        try bgContext.save()

        // Then - Visible in main context
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.email == "background@test.com" }
        )
        let results = try service.mainContext.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
    }
}
