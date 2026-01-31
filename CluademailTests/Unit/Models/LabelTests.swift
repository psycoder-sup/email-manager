import XCTest
@testable import Cluademail

/// Tests for Label model initialization and static constants.
final class LabelTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithDefaultValues() {
        let label = Label(
            gmailLabelId: "Label_123",
            name: "My Label"
        )

        XCTAssertEqual(label.gmailLabelId, "Label_123")
        XCTAssertEqual(label.name, "My Label")
        XCTAssertEqual(label.type, .user)
        XCTAssertEqual(label.messageListVisibility, .show)
        XCTAssertEqual(label.labelListVisibility, .show)
        XCTAssertNil(label.textColor)
        XCTAssertNil(label.backgroundColor)
    }

    func testInitWithAllParameters() {
        let label = Label(
            gmailLabelId: "INBOX",
            name: "Inbox",
            type: .system,
            messageListVisibility: .show,
            labelListVisibility: .showIfUnread,
            textColor: "#000000",
            backgroundColor: "#FFFFFF"
        )

        XCTAssertEqual(label.gmailLabelId, "INBOX")
        XCTAssertEqual(label.name, "Inbox")
        XCTAssertEqual(label.type, .system)
        XCTAssertEqual(label.messageListVisibility, .show)
        XCTAssertEqual(label.labelListVisibility, .showIfUnread)
        XCTAssertEqual(label.textColor, "#000000")
        XCTAssertEqual(label.backgroundColor, "#FFFFFF")
    }

    // MARK: - System Label IDs Tests

    func testSystemLabelIds() {
        let expectedLabels: Set<String> = [
            "INBOX", "SENT", "DRAFT", "TRASH", "SPAM",
            "STARRED", "UNREAD", "IMPORTANT",
            "CATEGORY_PERSONAL", "CATEGORY_SOCIAL",
            "CATEGORY_PROMOTIONS", "CATEGORY_UPDATES"
        ]
        XCTAssertEqual(Label.systemLabelIds, expectedLabels)
    }

    // MARK: - LabelType Enum Tests

    func testLabelTypeRawValues() {
        XCTAssertEqual(LabelType.system.rawValue, "system")
        XCTAssertEqual(LabelType.user.rawValue, "user")
    }

    func testLabelTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Test system
        let systemData = try encoder.encode(LabelType.system)
        let decodedSystem = try decoder.decode(LabelType.self, from: systemData)
        XCTAssertEqual(decodedSystem, .system)

        // Test user
        let userData = try encoder.encode(LabelType.user)
        let decodedUser = try decoder.decode(LabelType.self, from: userData)
        XCTAssertEqual(decodedUser, .user)
    }

    // MARK: - LabelVisibility Enum Tests

    func testLabelVisibilityRawValues() {
        XCTAssertEqual(LabelVisibility.show.rawValue, "show")
        XCTAssertEqual(LabelVisibility.hide.rawValue, "hide")
        XCTAssertEqual(LabelVisibility.showIfUnread.rawValue, "showIfUnread")
    }

    func testLabelVisibilityCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for visibility in [LabelVisibility.show, .hide, .showIfUnread] {
            let data = try encoder.encode(visibility)
            let decoded = try decoder.decode(LabelVisibility.self, from: data)
            XCTAssertEqual(decoded, visibility)
        }
    }

    // MARK: - Identifiable Tests

    func testIdReturnsGmailLabelId() {
        let label = TestFixtures.makeLabel(gmailLabelId: "unique-label-id")
        XCTAssertEqual(label.id, "unique-label-id")
    }
}
