import XCTest
@testable import Cluademail

/// Tests for EmailThread model initialization and properties.
final class EmailThreadTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithRequiredParameters() {
        let date = Date()
        let thread = EmailThread(
            threadId: "thread123",
            subject: "Test Subject",
            snippet: "Test snippet...",
            lastMessageDate: date
        )

        XCTAssertEqual(thread.threadId, "thread123")
        XCTAssertEqual(thread.subject, "Test Subject")
        XCTAssertEqual(thread.snippet, "Test snippet...")
        XCTAssertEqual(thread.lastMessageDate, date)
        XCTAssertEqual(thread.messageCount, 1)
        XCTAssertFalse(thread.isRead)
        XCTAssertFalse(thread.isStarred)
        XCTAssertTrue(thread.participantEmails.isEmpty)
    }

    func testInitWithAllParameters() {
        let date = Date()
        let participants = ["user1@gmail.com", "user2@gmail.com"]
        let thread = EmailThread(
            threadId: "thread456",
            subject: "Complete Thread",
            snippet: "Thread snippet...",
            lastMessageDate: date,
            messageCount: 5,
            isRead: true,
            isStarred: true,
            participantEmails: participants
        )

        XCTAssertEqual(thread.threadId, "thread456")
        XCTAssertEqual(thread.subject, "Complete Thread")
        XCTAssertEqual(thread.snippet, "Thread snippet...")
        XCTAssertEqual(thread.lastMessageDate, date)
        XCTAssertEqual(thread.messageCount, 5)
        XCTAssertTrue(thread.isRead)
        XCTAssertTrue(thread.isStarred)
        XCTAssertEqual(thread.participantEmails, participants)
    }

    // MARK: - Identifiable Tests

    func testIdReturnsThreadId() {
        let thread = TestFixtures.makeEmailThread(threadId: "unique-thread-id")
        XCTAssertEqual(thread.id, "unique-thread-id")
    }
}
