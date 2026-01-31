import XCTest
@testable import Cluademail

/// Tests for Email model initialization and computed properties.
final class EmailTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithRequiredParameters() {
        let email = Email(
            gmailId: "msg123",
            threadId: "thread456",
            subject: "Test Subject",
            snippet: "Test snippet...",
            fromAddress: "sender@gmail.com",
            date: Date()
        )

        XCTAssertEqual(email.gmailId, "msg123")
        XCTAssertEqual(email.threadId, "thread456")
        XCTAssertEqual(email.subject, "Test Subject")
        XCTAssertEqual(email.snippet, "Test snippet...")
        XCTAssertEqual(email.fromAddress, "sender@gmail.com")
        XCTAssertNil(email.fromName)
        XCTAssertTrue(email.toAddresses.isEmpty)
        XCTAssertTrue(email.ccAddresses.isEmpty)
        XCTAssertTrue(email.bccAddresses.isEmpty)
        XCTAssertFalse(email.isRead)
        XCTAssertFalse(email.isStarred)
        XCTAssertTrue(email.labelIds.isEmpty)
    }

    func testInitWithAllParameters() {
        let date = Date()
        let email = Email(
            gmailId: "msg123",
            threadId: "thread456",
            subject: "Test Subject",
            snippet: "Test snippet...",
            fromAddress: "sender@gmail.com",
            fromName: "John Doe",
            toAddresses: ["recipient1@gmail.com", "recipient2@gmail.com"],
            ccAddresses: ["cc@gmail.com"],
            bccAddresses: ["bcc@gmail.com"],
            date: date,
            isRead: true,
            isStarred: true,
            labelIds: ["INBOX", "STARRED"]
        )

        XCTAssertEqual(email.fromName, "John Doe")
        XCTAssertEqual(email.toAddresses.count, 2)
        XCTAssertEqual(email.ccAddresses, ["cc@gmail.com"])
        XCTAssertEqual(email.bccAddresses, ["bcc@gmail.com"])
        XCTAssertTrue(email.isRead)
        XCTAssertTrue(email.isStarred)
        XCTAssertEqual(email.labelIds, ["INBOX", "STARRED"])
    }

    func testBodyFieldsDefaultToNil() {
        let email = TestFixtures.makeEmail()

        XCTAssertNil(email.bodyText)
        XCTAssertNil(email.bodyHtml)
    }

    // MARK: - Computed Properties Tests

    func testIsInInboxWithInboxLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["INBOX"])
        XCTAssertTrue(email.isInInbox)
    }

    func testIsInInboxWithoutInboxLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["SENT"])
        XCTAssertFalse(email.isInInbox)
    }

    func testIsInTrashWithTrashLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["TRASH"])
        XCTAssertTrue(email.isInTrash)
    }

    func testIsInTrashWithoutTrashLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["INBOX"])
        XCTAssertFalse(email.isInTrash)
    }

    func testIsInSpamWithSpamLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["SPAM"])
        XCTAssertTrue(email.isInSpam)
    }

    func testIsInSpamWithoutSpamLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["INBOX"])
        XCTAssertFalse(email.isInSpam)
    }

    func testIsDraftWithDraftLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["DRAFT"])
        XCTAssertTrue(email.isDraft)
    }

    func testIsDraftWithoutDraftLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["INBOX"])
        XCTAssertFalse(email.isDraft)
    }

    func testIsSentWithSentLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["SENT"])
        XCTAssertTrue(email.isSent)
    }

    func testIsSentWithoutSentLabel() {
        let email = TestFixtures.makeEmail(labelIds: ["INBOX"])
        XCTAssertFalse(email.isSent)
    }

    // MARK: - Identifiable Tests

    func testIdReturnsGmailId() {
        let email = TestFixtures.makeEmail(gmailId: "unique-gmail-id-123")
        XCTAssertEqual(email.id, "unique-gmail-id-123")
    }
}
