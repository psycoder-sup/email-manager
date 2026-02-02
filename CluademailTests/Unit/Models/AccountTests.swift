import XCTest
@testable import Cluademail

/// Tests for Account model initialization and properties.
final class AccountTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitSetsRequiredProperties() {
        let account = Account(
            email: "test@gmail.com",
            displayName: "Test User"
        )

        XCTAssertEqual(account.email, "test@gmail.com")
        XCTAssertEqual(account.displayName, "Test User")
    }

    func testInitSetsDefaultValues() {
        let account = TestFixtures.makeAccount()

        XCTAssertNotNil(account.id)
        XCTAssertNil(account.profileImageURL)
        XCTAssertTrue(account.isEnabled)
        XCTAssertNil(account.lastSyncDate)
        XCTAssertNil(account.historyId)
        XCTAssertTrue(account.emails.isEmpty)
    }

    func testInitGeneratesUniqueId() {
        let account1 = TestFixtures.makeAccount()
        let account2 = TestFixtures.makeAccount()

        XCTAssertNotEqual(account1.id, account2.id)
    }

}
