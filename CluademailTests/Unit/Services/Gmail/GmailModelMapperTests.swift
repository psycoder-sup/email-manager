import XCTest
import SwiftData
@testable import Cluademail

final class GmailModelMapperTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var account: Account!

    override func setUp() async throws {
        let schema = Schema([Account.self, Email.self, Attachment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)

        account = Account(email: "test@gmail.com", displayName: "Test User")
        context.insert(account)
        try context.save()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        account = nil
    }

    // MARK: - Email Mapping Tests

    func testMapToEmail_BasicMessage() throws {
        let dto = GmailMessageDTO(
            id: "msg123",
            threadId: "thread456",
            labelIds: ["INBOX", "UNREAD"],
            snippet: "Hello, this is a test...",
            internalDate: "1704067200000", // 2024-01-01 00:00:00 UTC
            payload: PayloadDTO(
                headers: [
                    HeaderDTO(name: "From", value: "sender@example.com"),
                    HeaderDTO(name: "To", value: "recipient@gmail.com"),
                    HeaderDTO(name: "Subject", value: "Test Subject"),
                    HeaderDTO(name: "Date", value: "Mon, 01 Jan 2024 00:00:00 +0000")
                ],
                body: nil,
                parts: nil,
                mimeType: "text/plain"
            )
        )

        let email = try GmailModelMapper.mapToEmail(dto)

        XCTAssertEqual(email.gmailId, "msg123")
        XCTAssertEqual(email.threadId, "thread456")
        XCTAssertEqual(email.subject, "Test Subject")
        XCTAssertEqual(email.snippet, "Hello, this is a test...")
        XCTAssertEqual(email.fromAddress, "sender@example.com")
        XCTAssertEqual(email.toAddresses, ["recipient@gmail.com"])
        XCTAssertFalse(email.isRead) // UNREAD label present
        XCTAssertFalse(email.isStarred)
        XCTAssertTrue(email.isInInbox)
    }

    func testMapToEmail_ReadAndStarred() throws {
        let dto = GmailMessageDTO(
            id: "msg123",
            threadId: "thread456",
            labelIds: ["INBOX", "STARRED"], // No UNREAD = read
            snippet: "Test",
            internalDate: "1704067200000",
            payload: PayloadDTO(
                headers: [
                    HeaderDTO(name: "From", value: "sender@example.com"),
                    HeaderDTO(name: "Subject", value: "Test")
                ],
                body: nil,
                parts: nil,
                mimeType: nil
            )
        )

        let email = try GmailModelMapper.mapToEmail(dto)

        XCTAssertTrue(email.isRead)
        XCTAssertTrue(email.isStarred)
    }

    func testMapToEmail_ParsesNameAndEmail() throws {
        let dto = GmailMessageDTO(
            id: "msg123",
            threadId: "thread456",
            labelIds: [],
            snippet: "",
            internalDate: nil,
            payload: PayloadDTO(
                headers: [
                    HeaderDTO(name: "From", value: "John Doe <john@example.com>"),
                    HeaderDTO(name: "To", value: "Jane Smith <jane@example.com>, bob@example.com"),
                    HeaderDTO(name: "Cc", value: "cc@example.com"),
                    HeaderDTO(name: "Subject", value: "Test")
                ],
                body: nil,
                parts: nil,
                mimeType: nil
            )
        )

        let email = try GmailModelMapper.mapToEmail(dto)

        XCTAssertEqual(email.fromAddress, "john@example.com")
        XCTAssertEqual(email.fromName, "John Doe")
        XCTAssertEqual(email.toAddresses, ["jane@example.com", "bob@example.com"])
        XCTAssertEqual(email.ccAddresses, ["cc@example.com"])
    }

    func testMapToEmail_ExtractsPlainTextBody() throws {
        let bodyText = "Hello, World!"
        let encodedBody = bodyText.data(using: .utf8)!.base64URLEncodedString()

        let dto = GmailMessageDTO(
            id: "msg123",
            threadId: "thread456",
            labelIds: [],
            snippet: "",
            internalDate: nil,
            payload: PayloadDTO(
                headers: [],
                body: BodyDTO(size: bodyText.count, data: encodedBody, attachmentId: nil),
                parts: nil,
                mimeType: "text/plain"
            )
        )

        let email = try GmailModelMapper.mapToEmail(dto)

        XCTAssertEqual(email.bodyText, "Hello, World!")
        XCTAssertNil(email.bodyHtml)
    }

    func testMapToEmail_ExtractsHtmlBody() throws {
        let bodyHtml = "<p>Hello, World!</p>"
        let encodedBody = bodyHtml.data(using: .utf8)!.base64URLEncodedString()

        let dto = GmailMessageDTO(
            id: "msg123",
            threadId: "thread456",
            labelIds: [],
            snippet: "",
            internalDate: nil,
            payload: PayloadDTO(
                headers: [],
                body: BodyDTO(size: bodyHtml.count, data: encodedBody, attachmentId: nil),
                parts: nil,
                mimeType: "text/html"
            )
        )

        let email = try GmailModelMapper.mapToEmail(dto)

        XCTAssertNil(email.bodyText)
        XCTAssertEqual(email.bodyHtml, "<p>Hello, World!</p>")
    }

    func testMapToEmail_ExtractsMultipartBodies() throws {
        let plainText = "Plain text body"
        let htmlText = "<p>HTML body</p>"

        let dto = GmailMessageDTO(
            id: "msg123",
            threadId: "thread456",
            labelIds: [],
            snippet: "",
            internalDate: nil,
            payload: PayloadDTO(
                headers: [],
                body: nil,
                parts: [
                    PartDTO(
                        partId: "0",
                        mimeType: "text/plain",
                        filename: nil,
                        headers: nil,
                        body: BodyDTO(
                            size: plainText.count,
                            data: plainText.data(using: .utf8)!.base64URLEncodedString(),
                            attachmentId: nil
                        ),
                        parts: nil
                    ),
                    PartDTO(
                        partId: "1",
                        mimeType: "text/html",
                        filename: nil,
                        headers: nil,
                        body: BodyDTO(
                            size: htmlText.count,
                            data: htmlText.data(using: .utf8)!.base64URLEncodedString(),
                            attachmentId: nil
                        ),
                        parts: nil
                    )
                ],
                mimeType: "multipart/alternative"
            )
        )

        let email = try GmailModelMapper.mapToEmail(dto)

        XCTAssertEqual(email.bodyText, "Plain text body")
        XCTAssertEqual(email.bodyHtml, "<p>HTML body</p>")
    }

    func testMapToEmail_ExtractsAttachments() throws {
        let dto = GmailMessageDTO(
            id: "msg123",
            threadId: "thread456",
            labelIds: [],
            snippet: "",
            internalDate: nil,
            payload: PayloadDTO(
                headers: [],
                body: nil,
                parts: [
                    PartDTO(
                        partId: "0",
                        mimeType: "text/plain",
                        filename: nil,
                        headers: nil,
                        body: BodyDTO(size: 10, data: "dGVzdA", attachmentId: nil),
                        parts: nil
                    ),
                    PartDTO(
                        partId: "1",
                        mimeType: "application/pdf",
                        filename: "document.pdf",
                        headers: nil,
                        body: BodyDTO(size: 1024, data: nil, attachmentId: "att123"),
                        parts: nil
                    )
                ],
                mimeType: "multipart/mixed"
            )
        )

        let email = try GmailModelMapper.mapToEmail(dto)

        XCTAssertEqual(email.attachments.count, 1)
        XCTAssertEqual(email.attachments.first?.filename, "document.pdf")
        XCTAssertEqual(email.attachments.first?.mimeType, "application/pdf")
        XCTAssertEqual(email.attachments.first?.gmailAttachmentId, "att123")
        XCTAssertEqual(email.attachments.first?.size, 1024)
    }

    // MARK: - RFC 2047 Decoding Tests

    func testDecodeRFC2047_Base64() {
        let encoded = "=?UTF-8?B?5pel5pys6Kqe?="
        let decoded = GmailModelMapper.decodeRFC2047(encoded)
        XCTAssertEqual(decoded, "日本語")
    }

    func testDecodeRFC2047_QuotedPrintable() {
        let encoded = "=?UTF-8?Q?Hello_World?="
        let decoded = GmailModelMapper.decodeRFC2047(encoded)
        XCTAssertEqual(decoded, "Hello World")
    }

    func testDecodeRFC2047_PlainText() {
        let plain = "Just plain text"
        let decoded = GmailModelMapper.decodeRFC2047(plain)
        XCTAssertEqual(decoded, "Just plain text")
    }
}
