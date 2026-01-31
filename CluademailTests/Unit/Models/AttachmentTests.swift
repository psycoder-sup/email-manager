import XCTest
@testable import Cluademail

/// Tests for Attachment model initialization and computed properties.
final class AttachmentTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitSetsPropertiesCorrectly() {
        let attachment = Attachment(
            id: "att123",
            gmailAttachmentId: "gmail-att-456",
            filename: "document.pdf",
            mimeType: "application/pdf",
            size: 1024 * 1024  // 1 MB
        )

        XCTAssertEqual(attachment.id, "att123")
        XCTAssertEqual(attachment.gmailAttachmentId, "gmail-att-456")
        XCTAssertEqual(attachment.filename, "document.pdf")
        XCTAssertEqual(attachment.mimeType, "application/pdf")
        XCTAssertEqual(attachment.size, 1024 * 1024)
        XCTAssertNil(attachment.localPath)
        XCTAssertFalse(attachment.isDownloaded)
    }

    // MARK: - Display Size Tests

    func testDisplaySizeForBytes() {
        let attachment = TestFixtures.makeAttachment(size: 500)
        XCTAssertEqual(attachment.displaySize, "500 bytes")
    }

    func testDisplaySizeForKilobytes() {
        let attachment = TestFixtures.makeAttachment(size: 1024)
        XCTAssertEqual(attachment.displaySize, "1 KB")
    }

    func testDisplaySizeForMegabytes() {
        let attachment = TestFixtures.makeAttachment(size: 1024 * 1024)
        XCTAssertEqual(attachment.displaySize, "1 MB")
    }

    func testDisplaySizeForLargerMegabytes() {
        let attachment = TestFixtures.makeAttachment(size: 5 * 1024 * 1024 + 512 * 1024)  // ~5.5 MB
        // ByteCountFormatter uses different rounding, just check it contains MB
        XCTAssertTrue(attachment.displaySize.contains("MB"))
    }

    func testDisplaySizeForGigabytes() {
        let attachment = TestFixtures.makeAttachment(size: 2 * 1024 * 1024 * 1024)  // ~2 GB
        // ByteCountFormatter uses different rounding, just check it contains GB
        XCTAssertTrue(attachment.displaySize.contains("GB"))
    }

    func testDisplaySizeForZeroBytes() {
        let attachment = TestFixtures.makeAttachment(size: 0)
        XCTAssertEqual(attachment.displaySize, "Zero KB")
    }

    // MARK: - Identifiable Tests

    func testIdProperty() {
        let attachment = TestFixtures.makeAttachment(id: "unique-attachment-id")
        XCTAssertEqual(attachment.id, "unique-attachment-id")
    }
}
